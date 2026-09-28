package dev.shiori.reader

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.provider.MediaStore
import android.test.AndroidTestCase
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException

@Suppress("DEPRECATION")
class ImageExportTest : AndroidTestCase() {
    private lateinit var root: File
    private lateinit var file: File
    private val png = byteArrayOf(137.toByte(),80,78,71,13,10,26,10)
    override fun setUp() {
        super.setUp()
        root = File(context.cacheDir, "image-export-test-${System.nanoTime()}").canonicalFile.apply { mkdirs() }
        val directory = File(root, "shiori-image-export/export-test").apply { mkdirs() }
        file = File(directory, "shiori-0123456789ab-123.png").apply { writeBytes(png) }
    }
    override fun tearDown() { root.deleteRecursively(); super.tearDown() }
    private fun args() = mapOf("path" to file.path, "name" to file.name, "mime" to "image/png", "size" to file.length())
    fun testStagingValidationRejectsWrongSizeFormatAndEscape() {
        assertEquals(file, ImageExportBridge.validate(root, args()))
        for (bad in listOf(args() + ("size" to 1), args() + ("mime" to "image/jpeg"),
            args() + ("path" to File(root, file.name).path))) {
            try { ImageExportBridge.validate(root, bad); fail() } catch (_: IllegalArgumentException) {}
        }
    }
    fun testOldAndroidPickerUsesCreateDocumentAndSeparateRequestCode() {
        val intent = ImageExportBridge.pickerIntent(file.name, "image/png")
        assertEquals(Intent.ACTION_CREATE_DOCUMENT, intent.action)
        assertEquals("image/png", intent.type)
        assertTrue(intent.hasCategory(Intent.CATEGORY_OPENABLE))
        assertEquals(file.name, intent.getStringExtra(Intent.EXTRA_TITLE))
        assertTrue(ImageExportBridge.REQUEST_CODE != 6202)
    }
    fun testPublishFailureAndCloseFailureRollbackOnlyOwnedRow() {
        for (phase in listOf("write", "close", "publish")) {
            val events = mutableListOf<String>()
            try {
                ImageExportBridge.publish(
                    write = {
                        events += "write"
                        if (phase == "write") throw IOException()
                        events += "close"
                        if (phase == "close") throw IOException()
                    }, commit = { events += "publish"; throw IOException() },
                    rollback = { events += "rollback" })
                fail()
            } catch (_: IOException) {}
            assertEquals("rollback", events.last())
            assertEquals(1, events.count { it == "rollback" })
            if (phase != "publish") assertFalse(events.contains("publish"))
        }
        val events = mutableListOf<String>()
        ImageExportBridge.publish({ events += "write/close" }, { events += "publish" }, { events += "rollback" })
        assertEquals(listOf("write/close", "publish"), events)
    }
    fun testBoundedCopyPreservesEncodedBytes() {
        val output = ByteArrayOutputStream()
        ImageExportBridge.copy(ByteArrayInputStream(png), output)
        assertTrue(png.contentEquals(output.toByteArray()))
    }
    fun testMediaStoreSelfAuthoredPngAndJpegSmoke() {
        if (Build.VERSION.SDK_INT < 29) return
        // Only our own inserted URI is read/deleted. No gallery query or read permission.
        for ((format, extension, mime) in listOf(
            Triple(Bitmap.CompressFormat.PNG, "png", "image/png"),
            Triple(Bitmap.CompressFormat.JPEG, "jpg", "image/jpeg"))) {
            val source = File(root, "shiori-smoke-${System.nanoTime()}.$extension")
            val bitmap = Bitmap.createBitmap(16, 16, Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(android.graphics.Color.BLUE)
            source.outputStream().use { assertTrue(bitmap.compress(format, 100, it)) }
            bitmap.recycle()
            val uri = ImageExportBridge.saveGallery(context.contentResolver, source, mime)
            try {
                val bytes = context.contentResolver.openInputStream(uri)!!.use { it.readBytes() }
                assertTrue(source.readBytes().contentEquals(bytes))
                val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                assertNotNull(decoded)
                assertEquals(16, decoded.width)
                decoded.recycle()
                context.contentResolver.query(uri, arrayOf(MediaStore.Images.Media.IS_PENDING,
                    MediaStore.Images.Media.MIME_TYPE, MediaStore.Images.Media.RELATIVE_PATH), null, null, null)!!.use {
                    assertTrue(it.moveToFirst())
                    assertEquals(0, it.getInt(0))
                    assertEquals(mime, it.getString(1))
                    assertEquals("Pictures/Shiori/", it.getString(2))
                }
            } finally { context.contentResolver.delete(uri, null, null) }
        }
    }
}
