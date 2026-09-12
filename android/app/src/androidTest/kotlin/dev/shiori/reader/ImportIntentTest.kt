package dev.shiori.reader

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import junit.framework.TestCase

class ImportIntentTest : TestCase() {
    private val a = Uri.parse("content://offline/a")
    private val b = Uri.parse("content://offline/b")
    private fun clip(vararg uris: Uri): ClipData = ClipData.newRawUri("offline", uris[0]).apply {
        uris.drop(1).forEach { addItem(ClipData.Item(it)) }
    }
    private fun issue(code: String, action: () -> Unit) {
        try { action(); fail("Expected $code") }
        catch (e: ImportInbox.Issue) { assertEquals(code, e.code) }
    }
    fun testPickerConfigurationAndClipOrder() {
        val picker = MainActivity.pickerIntent()
        assertEquals(Intent.ACTION_OPEN_DOCUMENT, picker.action)
        assertTrue(picker.hasCategory(Intent.CATEGORY_OPENABLE))
        assertTrue(picker.getBooleanExtra(Intent.EXTRA_ALLOW_MULTIPLE, false))
        assertEquals(listOf("text/plain", "application/epub+zip"), picker.getStringArrayExtra(Intent.EXTRA_MIME_TYPES)!!.toList())
        assertEquals(listOf(b, a, b), MainActivity.pickerUris(Intent().apply { data = a; clipData = clip(b, a, b) }))
        assertEquals(listOf(a), MainActivity.pickerUris(Intent().setData(a)))
    }
    fun testSendPrefersStreamWithoutDuplicatingClipData() {
        val send = Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, a).apply { clipData = clip(b, a) }
        assertEquals(listOf(a), MainActivity.incomingUris(send))
        send.removeExtra(Intent.EXTRA_STREAM)
        assertEquals(listOf(b, a), MainActivity.incomingUris(send))
    }
    fun testSendMultiplePreservesDuplicatesAndFallsBackToClip() {
        val send = Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(Intent.EXTRA_STREAM, arrayListOf(b, a, b))
            .apply { clipData = clip(a, b) }
        assertEquals(listOf(b, a, b), MainActivity.incomingUris(send))
        send.removeExtra(Intent.EXTRA_STREAM)
        assertEquals(listOf(a, b), MainActivity.incomingUris(send))
    }
    fun testViewOnlyUsesItsDataUri() {
        assertEquals(listOf(a), MainActivity.incomingUris(Intent(Intent.ACTION_VIEW, a).apply { clipData = clip(b) }))
    }
    fun testEmptyAndCountLimits() {
        issue("unreadable") { MainActivity.pickerUris(Intent()) }
        issue("unreadable") { MainActivity.incomingUris(Intent(Intent.ACTION_SEND)) }
        issue("batchLimit") { MainActivity.incomingUris(Intent(Intent.ACTION_SEND_MULTIPLE)
            .putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(List(65) { a }))) }
        issue("batchLimit") { MainActivity.pickerUris(Intent().apply { clipData = clip(*Array(65) { a }) }) }
    }
}
