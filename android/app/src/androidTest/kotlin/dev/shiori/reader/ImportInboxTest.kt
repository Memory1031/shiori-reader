package dev.shiori.reader

import android.system.Os
import android.test.AndroidTestCase
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.RandomAccessFile
import java.util.UUID

/** Offline filesystem protocol tests; each method owns an isolated cache tree. */
@Suppress("DEPRECATION")
class ImportInboxTest : AndroidTestCase() {
    private lateinit var root: File
    private lateinit var inbox: ImportInbox
    private val testMaxFiles = 8
    private val testMaxFileBytes = 128L * 1024
    private val testMaxBatchBytes = 512L * 1024
    private fun newInbox() = ImportInbox(root, testMaxFiles, testMaxFileBytes, testMaxBatchBytes)

    override fun setUp() {
        super.setUp()
        root = File(context.cacheDir, "inbox-test-${UUID.randomUUID()}").apply { mkdirs() }
        inbox = newInbox()
    }
    override fun tearDown() {
        root.deleteRecursively()
        super.tearDown()
    }
    private fun input(name: String = "book.txt", bytes: ByteArray = byteArrayOf(1, 2, 3)): () -> ImportInbox.Input = {
        ImportInbox.Input(name) { ByteArrayInputStream(bytes) }
    }
    private fun issue(code: String, action: () -> Unit) {
        try { action(); fail("Expected $code") }
        catch (e: ImportInbox.Issue) { assertEquals(code, e.code) }
    }
    private fun unpublished() {
        assertFalse(File(root, "working").exists())
        assertFalse(File(root, "pending").exists())
        assertTrue(inbox.pending().isEmpty())
    }
    private fun sized(bytes: Long, declared: Long? = null): () -> ImportInbox.Input = {
        ImportInbox.Input("generated.txt", declared) {
            object : InputStream() {
                var remaining = bytes
                override fun read(): Int = if (remaining-- > 0) 1 else -1
                override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                    if (remaining <= 0) return -1
                    val count = minOf(remaining, length.toLong()).toInt()
                    buffer.fill(1, offset, offset + count)
                    remaining -= count
                    return count
                }
            }
        }
    }

    fun testThreeFilesPublishInOrderAndSurviveReopen() {
        inbox.stage(listOf(input("z.TXT"), input("same.epub"), input("same.epub")), { false })
        val receipts = newInbox().pending()
        assertEquals(listOf("z.TXT", "same.epub", "same.epub"), receipts.map { it["name"] })
        assertEquals(3, receipts.map { it["id"] }.toSet().size)
        assertEquals(listOf(0, 1, 2), receipts.map {
            JSONObject(File(File(it["path"] as String).parentFile, "receipt.json").readText()).getInt("order")
        })
        assertFalse(File(root, "working").exists())
    }
    fun testOneFileAndUntrustedDisplayNameNeverBecomePaths() {
        inbox.stage(listOf(input("../../outside.TXT")), { false })
        val receipt = inbox.pending().single()
        assertEquals("../../outside.TXT", receipt["name"])
        assertTrue((receipt["path"] as String).startsWith(File(root, "pending/item-0000-").path))
        assertEquals(3L, receipt["size"])
    }
    fun testSecondFileReadFailureRollsBackWholeBatch() {
        val broken = { ImportInbox.Input("bad.txt") { object : InputStream() {
            override fun read(): Int = throw IOException("synthetic read failure")
        } } }
        issue("unreadable") { inbox.stage(listOf(input(), broken, input()), { false }) }
        unpublished()
    }
    fun testLaterMetadataFailuresNeverOpenStreamsOrCreateWorking() {
        for (code in listOf("unreadable", "unsupported", "tooLarge")) {
            var opened = 0
            val first = { ImportInbox.Input("first.txt") { opened++; ByteArrayInputStream(byteArrayOf(1)) } }
            val later = {
                assertFalse(File(root, "working").exists())
                when (code) {
                    "unreadable" -> throw ImportInbox.Issue(code)
                    "unsupported" -> ImportInbox.Input("bad.pdf") { opened++; ByteArrayInputStream(byteArrayOf(1)) }
                    else -> ImportInbox.Input("large.txt", testMaxFileBytes + 1) { opened++; ByteArrayInputStream(byteArrayOf(1)) }
                }
            }
            issue(code) { inbox.stage(listOf(first, later), { false }) }
            assertEquals(0, opened)
            unpublished()
        }
    }
    fun testCancellationInMetadataPreflightNeverOpensStreams() {
        var cancelled = false
        var opened = 0
        val first = { ImportInbox.Input("first.txt") { opened++; ByteArrayInputStream(byteArrayOf(1)) } }
        val later = {
            cancelled = true
            ImportInbox.Input("later.txt") { opened++; ByteArrayInputStream(byteArrayOf(1)) }
        }
        issue("cancelled") { inbox.stage(listOf(first, later), { cancelled }) }
        assertEquals(0, opened)
        unpublished()
    }
    fun testAllMetadataIsPreparedBeforeAnyStreamOpens() {
        val sequence = mutableListOf<String>()
        inbox.stage((1..3).map { index -> {
            assertFalse(File(root, "working").exists())
            sequence.add("prepare$index")
            ImportInbox.Input("book$index.txt") {
                sequence.add("open$index")
                ByteArrayInputStream(byteArrayOf(1))
            }
        } }, { false })
        assertEquals(listOf("prepare1", "prepare2", "prepare3", "open1", "open2", "open3"), sequence)
    }
    fun testUnsupportedAndEmptyFilesRollBack() {
        issue("unsupported") { inbox.stage(listOf(input(), input("bad.pdf")), { false }) }
        unpublished()
        issue("unreadable") { inbox.stage(listOf(input(), input(bytes = byteArrayOf())), { false }) }
        unpublished()
        issue("unreadable") { inbox.stage(emptyList(), { false }) }
    }
    fun testCancellationDuringSecondFileClosesStreamAndRollsBack() {
        var cancelled = false
        var closed = false
        val second = { ImportInbox.Input("second.txt") { object : InputStream() {
            override fun read(): Int { cancelled = true; return 1 }
            override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                cancelled = true
                return 1
            }
            override fun close() { closed = true }
        } } }
        issue("cancelled") { inbox.stage(listOf(input(), second, input()), { cancelled }) }
        assertTrue(closed)
        unpublished()
    }
    fun testCancellationBeforePublicationLeavesNoReceipts() {
        var cancelled = false
        val last = { ImportInbox.Input("last.txt") { object : ByteArrayInputStream(byteArrayOf(1)) {
            override fun close() { super.close(); cancelled = true }
        } } }
        issue("cancelled") { inbox.stage(listOf(input(), last), { cancelled }) }
        unpublished()
    }
    fun testCountBoundBeforeOpeningAnyInput() {
        issue("batchLimit") {
            inbox.stage(List(testMaxFiles + 1) { { fail("Must not prepare"); input()() } }, { false })
        }
        unpublished()
        inbox.stage(List(testMaxFiles) { input() }, { false })
        assertEquals(testMaxFiles, inbox.pending().size)
    }
    fun testProductionLimitsRemainExplicit() {
        assertEquals(64, ImportInbox.MAX_FILES)
        assertEquals(128L * 1024 * 1024, ImportInbox.MAX_FILE_BYTES)
        assertEquals(512L * 1024 * 1024, ImportInbox.MAX_BATCH_BYTES)
    }
    fun testPerFileBoundUsesActualBytesDespiteIncorrectMetadata() {
        issue("tooLarge") { inbox.stage(listOf(sized(testMaxFileBytes + 1, 1)), { false }) }
        unpublished()
    }
    fun testTotalBoundUsesActualBytesAndAcceptsExactLimit() {
        val full = List(4) { sized(testMaxFileBytes) }
        issue("batchLimit") { inbox.stage(full + input(), { false }) }
        unpublished()
        inbox.stage(full, { false })
        assertEquals(testMaxBatchBytes, inbox.pending().sumOf { it["size"] as Long })
    }
    fun testDeclaredOversizeRejectedBeforeOpen() {
        issue("tooLarge") { inbox.stage(listOf({ ImportInbox.Input("large.txt", testMaxFileBytes + 1) {
            fail("Must not open"); ByteArrayInputStream(byteArrayOf())
        } }), { false }) }
        unpublished()
    }
    fun testProgressIsAggregateAndThrottled() {
        inbox = ImportInbox(root, maxFiles = 3, maxFileBytes = 2L * 1024 * 1024, maxBatchBytes = 6L * 1024 * 1024)
        val progress = mutableListOf<Long>()
        inbox.stage(List(3) { sized(2L * 1024 * 1024) }, { false }, progress::add)
        assertEquals((1L..6L).map { it * 1024 * 1024 }, progress)
    }
    fun testPendingCannotInspectWorkingWhileStageHoldsLock() {
        inbox.stage(listOf({
            issue("busy") { newInbox().pending() }
            assertFalse(File(root, "working").exists())
            ImportInbox.Input("book.txt") {
                issue("busy") { newInbox().pending() }
                assertTrue(File(root, "working").exists())
                ByteArrayInputStream(byteArrayOf(1))
            }
        }), { false })
        assertEquals(1, inbox.pending().size)
    }
    fun testExistingPendingCannotBeOverwritten() {
        inbox.stage(listOf(input()), { false })
        val before = inbox.pending()
        issue("busy") { inbox.stage(listOf(input("new.txt")), { false }) }
        assertEquals(before, inbox.pending())
    }
    fun testAcknowledgeMiddleUnknownAndLastPreservesOtherReceipts() {
        inbox.stage(List(3) { input() }, { false })
        val before = inbox.pending()
        inbox.acknowledge("../../pending")
        assertEquals(before, inbox.pending())
        inbox.acknowledge(before[1]["id"] as String)
        inbox.acknowledge(before[1]["id"] as String)
        assertEquals(listOf(before[0], before[2]), newInbox().pending())
        inbox.acknowledge(before[0]["id"] as String)
        inbox.acknowledge(before[2]["id"] as String)
        assertFalse(File(root, "pending").exists())
    }
    fun testLegacyReceiptIsBusyReadableAndAcknowledgedById() {
        val pending = File(root, "pending").apply { mkdir() }
        File(pending, "payload").writeBytes(byteArrayOf(1, 2, 3))
        File(pending, "receipt.json").writeText(JSONObject(mapOf("id" to "legacy-id", "name" to "old.txt", "size" to 3)).toString())
        assertEquals("legacy-id", inbox.pending().single()["id"])
        issue("busy") { inbox.stage(listOf(input()), { false }) }
        inbox.acknowledge("wrong")
        assertTrue(pending.exists())
        inbox.acknowledge("legacy-id")
        inbox.acknowledge("legacy-id")
        unpublished()
    }
    fun testRecoveryAfterDetachBeforeTrashDeletion() {
        inbox.stage(List(3) { input() }, { false })
        val before = inbox.pending()
        val item = File(before[1]["path"] as String).parentFile!!
        val trash = File(root, "ack-trash-${UUID.randomUUID()}")
        Os.rename(item.path, trash.path)
        File(trash, "receipt.json").delete() // Interrupted recursive trash cleanup.
        assertEquals(listOf(before[0], before[2]), newInbox().pending())
        assertFalse(trash.exists())
    }
    fun testWorkingTrashAndEmptyPendingRecoveryAllowsNextStage() {
        File(root, "working/partial").apply { parentFile!!.mkdirs(); writeText("incomplete") }
        val trash = File(root, "ack-trash-${UUID.randomUUID()}").apply { mkdir() }
        File(trash, "payload").writeText("detached")
        File(root, "pending").mkdir()
        inbox.stage(listOf(input()), { false })
        assertFalse(trash.exists())
        assertEquals(1, inbox.pending().size)
    }
    fun testMalformedPublishedMetadataIsPreserved() {
        inbox.stage(List(3) { input() }, { false })
        val receipt = inbox.pending()[1]
        val metadata = File(File(receipt["path"] as String).parentFile, "receipt.json")
        metadata.writeText("broken")
        issue("storage") { inbox.pending() }
        issue("storage") { inbox.stage(listOf(input()), { false }) }
        issue("storage") { inbox.acknowledge(receipt["id"] as String) }
        assertEquals("broken", metadata.readText())
        assertEquals(3, File(root, "pending").listFiles()!!.size)
    }
    fun testLockPreventsRecoveryDeletingActiveWorking() {
        File(root, "working").mkdir()
        RandomAccessFile(File(root, "lock"), "rw").use { file ->
            file.channel.lock().use {
                issue("busy") { inbox.pending() }
                issue("busy") { inbox.acknowledge("unknown") }
                assertTrue(File(root, "working").exists())
            }
        }
        assertTrue(inbox.pending().isEmpty())
    }
}
