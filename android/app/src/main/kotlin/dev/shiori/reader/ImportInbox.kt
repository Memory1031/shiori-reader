package dev.shiori.reader

import android.system.Os
import android.system.OsConstants
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.io.RandomAccessFile
import java.nio.channels.OverlappingFileLockException
import java.util.Locale
import java.util.UUID

/** One app-owned batch. Only the working -> pending rename publishes receipts. */
internal class ImportInbox internal constructor(
    root: File,
    private val maxFiles: Int = MAX_FILES,
    private val maxFileBytes: Long = MAX_FILE_BYTES,
    private val maxBatchBytes: Long = MAX_BATCH_BYTES,
) {
    private val root = root.canonicalFile

    init {
        require(maxFiles in 1..MAX_FILES)
        require(maxFileBytes in 1..MAX_FILE_BYTES)
        require(maxBatchBytes in 1..MAX_BATCH_BYTES)
    }

    class Issue(val code: String, cause: Throwable? = null) : Exception(code, cause)
    data class Input(val name: String, val size: Long? = null, val open: () -> InputStream)
    private data class Receipt(
        val directory: File,
        val id: String,
        val name: String,
        val size: Long,
        val order: Int,
    ) {
        fun channelValue(): Map<String, Any> = mapOf(
            "id" to id, "name" to name, "size" to size,
            "path" to File(directory, "payload").absolutePath,
        )
    }

    companion object {
        const val MAX_FILES = 64
        const val MAX_FILE_BYTES = 128L * 1024 * 1024
        const val MAX_BATCH_BYTES = 512L * 1024 * 1024
        private const val BUFFER_BYTES = 64 * 1024
        private const val PROGRESS_BYTES = 1024 * 1024L
        private const val MAX_RECEIPT_BYTES = 64 * 1024L
        private const val UUID_PATTERN = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
        private val ITEM_NAME = Regex("item-[0-9]{4}-$UUID_PATTERN")
        private val TRASH_NAME = Regex("ack-trash-$UUID_PATTERN")
    }

    fun pending(): List<Map<String, Any>> = locked {
        recover()
        inspect().map { it.channelValue() }
    }

    fun acknowledge(id: String) = locked {
        recover()
        // Match metadata, never construct a path from the caller's opaque id.
        val receipt = inspect().firstOrNull { it.id == id } ?: return@locked
        val trash = File(root, "ack-trash-${UUID.randomUUID()}")
        Os.rename(receipt.directory.path, trash.path)
        val pending = File(root, "pending")
        if (pending.exists()) syncDirectory(pending)
        syncDirectory(root)
        removeEmptyPending()
        // A crash or deletion failure here cannot damage the remaining batch.
        runCatching { deleteTree(trash) }
    }

    fun stage(
        inputs: List<() -> Input>,
        cancelled: () -> Boolean,
        progress: (Long) -> Unit = {},
    ) = locked {
        recover()
        if (inspect().isNotEmpty()) throw Issue("busy")
        if (inputs.isEmpty()) throw Issue("unreadable")
        if (inputs.size > maxFiles) throw Issue("batchLimit")
        fun checkCancellation() { if (cancelled()) throw Issue("cancelled") }
        checkCancellation()
        // Resolve all metadata before creating working or opening any stream.
        val prepared = inputs.map { prepare ->
            checkCancellation()
            val source = prepare()
            checkCancellation()
            if (source.name.substringAfterLast('.', "").lowercase(Locale.ROOT) !in listOf("txt", "epub")) {
                throw Issue("unsupported")
            }
            if (source.size != null && source.size > maxFileBytes) throw Issue("tooLarge")
            source
        }
        checkCancellation()
        val working = File(root, "working")
        if (!working.mkdir()) throw Issue("storage")
        try {
            var total = 0L
            var reported = 0L
            val buffer = ByteArray(BUFFER_BYTES)
            prepared.forEachIndexed { order, source ->
                checkCancellation()
                val id = UUID.randomUUID().toString()
                val item = File(working, "item-${order.toString().padStart(4, '0')}-$id")
                if (!item.mkdir()) throw Issue("storage")
                var size = 0L
                val input = try { source.open() } catch (e: Exception) { throw Issue("unreadable", e) }
                input.use {
                    FileOutputStream(File(item, "payload")).use { output ->
                        while (true) {
                            checkCancellation()
                            val count = try { input.read(buffer) } catch (e: Exception) { throw Issue("unreadable", e) }
                            checkCancellation()
                            if (count < 0) break
                            if (count == 0) continue
                            size += count
                            total += count
                            if (size > maxFileBytes) throw Issue("tooLarge")
                            if (total > maxBatchBytes) throw Issue("batchLimit")
                            output.write(buffer, 0, count)
                            if (total - reported >= PROGRESS_BYTES) {
                                progress(total)
                                reported = total
                            }
                        }
                        if (size == 0L) throw Issue("unreadable")
                        output.fd.sync()
                    }
                }
                val metadata = JSONObject(mapOf("id" to id, "name" to source.name, "size" to size, "order" to order))
                    .toString().toByteArray(Charsets.UTF_8)
                if (metadata.size > MAX_RECEIPT_BYTES) throw Issue("unreadable")
                FileOutputStream(File(item, "receipt.json")).use { output ->
                    output.write(metadata)
                    output.fd.sync()
                }
                syncDirectory(item)
            }
            syncDirectory(working)
            checkCancellation()
            Os.rename(working.path, File(root, "pending").path)
            syncDirectory(root)
        } finally {
            // After publication working no longer exists. Never roll back pending.
            deleteTree(working)
        }
    }

    private fun <T> locked(body: () -> T): T {
        try {
            if (!root.isDirectory && !root.mkdirs()) throw Issue("storage")
            val lockFile = File(root, "lock")
            requireOwned(lockFile)
            RandomAccessFile(lockFile, "rw").use { file ->
                val lock = try { file.channel.tryLock() } catch (_: OverlappingFileLockException) { null }
                if (lock == null) throw Issue("busy")
                try { return body() } finally { lock.release() }
            }
        } catch (e: Issue) {
            throw e
        } catch (e: Exception) {
            throw Issue("storage", e)
        }
    }

    private fun recover() {
        deleteTree(File(root, "working"))
        children(root).filter { TRASH_NAME.matches(it.name) }.forEach {
            runCatching { deleteTree(it) }
        }
        removeEmptyPending()
    }

    private fun removeEmptyPending() {
        val pending = File(root, "pending")
        requireOwned(pending)
        if (pending.exists() && pending.isDirectory && children(pending).isEmpty()) {
            if (!pending.delete()) throw Issue("storage")
            syncDirectory(root)
        }
    }

    private fun inspect(): List<Receipt> {
        val pending = File(root, "pending")
        requireOwned(pending)
        if (!pending.exists()) return emptyList()
        if (!pending.isDirectory) throw Issue("storage")
        val entries = children(pending)
        // Keep old installations readable without migrating their published copy.
        if (entries.any { it.name == "receipt.json" || it.name == "payload" }) {
            if (entries.map { it.name }.toSet() != setOf("receipt.json", "payload")) throw Issue("storage")
            return listOf(readReceipt(pending, legacy = true))
        }
        if (entries.size > maxFiles) throw Issue("storage")
        val receipts = entries.map {
            if (!ITEM_NAME.matches(it.name)) throw Issue("storage")
            readReceipt(it, legacy = false)
        }
        if (receipts.map { it.id }.toSet().size != receipts.size ||
            receipts.map { it.order }.toSet().size != receipts.size ||
            receipts.sumOf { it.size } > maxBatchBytes) throw Issue("storage")
        return receipts.sortedBy { it.order }
    }

    private fun readReceipt(directory: File, legacy: Boolean): Receipt {
        requireOwned(directory)
        if (!directory.isDirectory) throw Issue("storage")
        if (children(directory).map { it.name }.toSet() != setOf("receipt.json", "payload")) throw Issue("storage")
        val metadata = File(directory, "receipt.json")
        val payload = File(directory, "payload")
        requireOwned(metadata)
        requireOwned(payload)
        if (!metadata.isFile || metadata.length() !in 1..MAX_RECEIPT_BYTES || !payload.isFile) throw Issue("storage")
        val json = JSONObject(metadata.readText(Charsets.UTF_8))
        val id = json.get("id") as? String ?: throw Issue("storage")
        val name = json.get("name") as? String ?: throw Issue("storage")
        val size = integer(json.get("size"))
        val order = if (legacy) 0L else integer(json.get("order"))
        if (id.isEmpty() || name.isEmpty() || size !in 1..maxFileBytes ||
            order !in 0 until maxFiles || payload.length() != size) throw Issue("storage")
        return Receipt(directory, id, name, size, order.toInt())
    }

    private fun integer(value: Any): Long = when (value) {
        is Int -> value.toLong()
        is Long -> value
        else -> throw Issue("storage")
    }

    private fun requireOwned(file: File) {
        if (file.canonicalFile != file.absoluteFile) throw Issue("storage")
    }

    private fun children(directory: File): List<File> = directory.listFiles()?.toList() ?: throw Issue("storage")

    /** Only called on fixed working or generated tombstone paths, never pending. */
    private fun deleteTree(file: File) {
        if (file.canonicalFile != file.absoluteFile) {
            if (!file.delete()) throw Issue("storage") // Unlink, do not follow symlinks.
            return
        }
        if (!file.exists()) return
        if (file.isDirectory) children(file).forEach { deleteTree(it) }
        if (!file.delete()) throw Issue("storage")
    }

    private fun syncDirectory(directory: File) {
        val fd = Os.open(directory.path, OsConstants.O_RDONLY, 0)
        try { Os.fsync(fd) } finally { Os.close(fd) }
    }
}
