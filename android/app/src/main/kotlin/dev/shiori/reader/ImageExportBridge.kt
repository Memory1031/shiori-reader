package dev.shiori.reader

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** One owner per request. A submitted write retains staging until its real reply. */
class ImageExportBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "dev.shiori.reader/image_export")
    private val worker = Executors.newSingleThreadExecutor()
    private var pending: Request? = null
    private var destroyed = false
    private class Request(val id: String, val result: MethodChannel.Result) {
        val cancelled = AtomicBoolean(false)
        var file: File? = null
        var mime = ""
        var picking = false
    }
    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "cancel" -> {
                    pending?.takeIf { it.id == call.argument<String>("id") }?.let {
                        it.cancelled.set(true)
                        if (it.picking) {
                            activity.finishActivity(REQUEST_CODE)
                            finish(it, "cancelled")
                        }
                    }
                    result.success(null)
                }
                "save" -> {
                    if (pending != null || destroyed) result.success("unavailable")
                    else {
                        val args = call.arguments as? Map<*, *>
                        val request = Request(args?.get("id") as? String ?: "", result)
                        pending = request
                        worker.execute {
                            try {
                                val file = validate(activity.cacheDir, args)
                                val mime = args!!["mime"] as String
                                activity.runOnUiThread {
                                    if (request.cancelled.get() || destroyed) finish(request, "cancelled")
                                    else {
                                        request.file = file
                                        request.mime = mime
                                        if (args["asFile"] == true || Build.VERSION.SDK_INT < 29) pick(request)
                                        else if (mime == "image/avif" && Build.VERSION.SDK_INT < 31) {
                                            finish(request, "unsupportedFormat")
                                        } else writeGallery(request)
                                    }
                                }
                            } catch (_: Exception) {
                                activity.runOnUiThread { finish(request, "invalidFormat") }
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun finish(request: Request, value: String) {
        if (pending !== request) return
        pending = null
        request.result.success(value)
    }
    private fun pick(request: Request) {
        try {
            request.picking = true
            activity.startActivityForResult(pickerIntent(request.file!!.name, request.mime), REQUEST_CODE)
        } catch (_: Exception) { finish(request, "unavailable") }
    }
    fun onActivityResult(code: Int, result: Int, data: Intent?): Boolean {
        if (code != REQUEST_CODE) return false
        val request = pending ?: return true
        if (!request.picking) return true
        request.picking = false
        if (result != Activity.RESULT_OK || request.cancelled.get()) finish(request, "cancelled")
        else {
            val uri = data?.data
            if (uri == null || uri.scheme != "content") finish(request, "storageFailure")
            else writeDocument(request, uri)
        }
        return true
    }
    private fun writeDocument(request: Request, uri: Uri) {
        worker.execute {
            val value = try {
                activity.contentResolver.openOutputStream(uri, "w")?.use { output ->
                    request.file!!.inputStream().use { copy(it, output) }
                } ?: throw IllegalStateException()
                "savedFile"
            } catch (_: Exception) {
                // ACTION_CREATE_DOCUMENT creates a new document; never touch other URIs.
                try { DocumentsContract.deleteDocument(activity.contentResolver, uri) } catch (_: Exception) {}
                "storageFailure"
            }
            activity.runOnUiThread { finish(request, value) }
        }
    }
    @android.annotation.TargetApi(29)
    private fun writeGallery(request: Request) {
        worker.execute {
            val value = if (request.cancelled.get()) "cancelled" else try {
                saveGallery(activity.contentResolver, request.file!!, request.mime)
                "savedPhotos"
            } catch (_: Exception) { "storageFailure" }
            activity.runOnUiThread { finish(request, value) }
        }
    }
    fun close() {
        destroyed = true
        channel.setMethodCallHandler(null)
        pending?.let {
            it.cancelled.set(true)
            if (it.picking) activity.finishActivity(REQUEST_CODE)
            // A worker already consuming the file owns completion, even after
            // Activity/engine detach. Replying here would free staging too soon.
            if (it.picking) finish(it, "unavailable")
        }
        worker.shutdown() // Drains an already submitted validation/write.
    }
    companion object {
        const val REQUEST_CODE = 4827
        const val MAX_BYTES = 20L * 1024 * 1024
        @android.annotation.TargetApi(29)
        fun saveGallery(resolver: android.content.ContentResolver, file: File, mime: String): Uri {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, file.name)
                put(MediaStore.Images.Media.MIME_TYPE, mime)
                put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Shiori")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException()
            publish(
                write = {
                    resolver.openOutputStream(uri, "w")?.use { output ->
                        file.inputStream().use { copy(it, output) }
                    } ?: throw IllegalStateException()
                },
                commit = {
                    check(resolver.update(uri, ContentValues().apply {
                        put(MediaStore.Images.Media.IS_PENDING, 0)
                    }, null, null) == 1)
                },
                rollback = { resolver.delete(uri, null, null) }
            )
            return uri
        }
        // Both stream close and publication must succeed before reporting save.
        fun publish(write: () -> Unit, commit: () -> Unit, rollback: () -> Unit) {
            try { write(); commit() }
            catch (error: Exception) {
                try { rollback() } catch (_: Exception) {}
                throw error
            }
        }
        fun pickerIntent(name: String, mime: String) = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mime
            putExtra(Intent.EXTRA_TITLE, name)
        }
        fun validate(cache: File, args: Map<*, *>?): File {
            val raw = File(args?.get("path") as? String ?: throw IllegalArgumentException())
            val root = File(cache, "shiori-image-export").canonicalFile
            val file = raw.canonicalFile
            val name = args["name"] as? String ?: throw IllegalArgumentException()
            require(file.path == raw.absolutePath && file.parentFile?.parentFile == root)
            require(file.parentFile!!.name.startsWith("export-") && file.name == name)
            require(Regex("shiori-[a-f0-9]{12}-[0-9]{1,16}\\.(jpg|png|gif|webp|avif)").matches(name))
            require(file.isFile && file.length() in 1..MAX_BYTES)
            require((args["size"] as? Number)?.toLong() == file.length())
            val header = ByteArray(4096)
            val count = file.inputStream().use { it.read(header) }
            val format = format(header.copyOf(count))
            require(format != null && name.endsWith(".${format.first}") && args["mime"] == format.second)
            return file
        }
        fun format(bytes: ByteArray): Pair<String, String>? {
            fun prefix(vararg values: Int) = bytes.size >= values.size &&
                values.indices.all { (bytes[it].toInt() and 255) == values[it] }
            fun text(offset: Int, length: Int) = if (bytes.size >= offset + length)
                String(bytes, offset, length, Charsets.US_ASCII) else ""
            return when {
                prefix(137,80,78,71,13,10,26,10) -> "png" to "image/png"
                prefix(255,216,255) -> "jpg" to "image/jpeg"
                text(0,6) in listOf("GIF87a", "GIF89a") -> "gif" to "image/gif"
                text(0,4) == "RIFF" && text(8,4) == "WEBP" -> "webp" to "image/webp"
                text(4,4) == "ftyp" && text(8,4) in listOf("avif", "avis") -> "avif" to "image/avif"
                else -> null
            }
        }
        fun copy(input: InputStream, output: OutputStream) {
            val buffer = ByteArray(64 * 1024)
            var total = 0L
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                total += count
                require(total <= MAX_BYTES)
                output.write(buffer, 0, count)
            }
            require(total > 0)
            output.flush()
        }
    }
}
