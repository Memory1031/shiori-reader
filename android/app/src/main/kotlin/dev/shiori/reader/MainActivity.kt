package dev.shiori.reader

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException
import java.io.RandomAccessFile
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var events: EventChannel.EventSink? = null
    private var selection: MethodChannel.Result? = null
    private var cancelled = AtomicBoolean(false)
    private var copying = false
    private var deferredError: String? = null
    private val root get() = File(noBackupFilesDir, "import-inbox").apply { mkdirs() }
    private class Issue(val code: String) : Exception()
    private fun <T> locked(block: () -> T): T {
        RandomAccessFile(File(root, "lock"), "rw").use { file ->
            val lock = file.channel.tryLock() ?: throw Issue("busy")
            try { return block() } finally { lock.release() }
        }
    }
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        EventChannel(engine.dartExecutor.binaryMessenger, "dev.shiori.reader/import_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                    events = sink
                    deferredError?.let { sink.success(mapOf("error" to it)) }; deferredError = null
                    sink.success(emptyMap<String, Any>())
                }
                override fun onCancel(args: Any?) { events = null }
            })
        MethodChannel(engine.dartExecutor.binaryMessenger, "dev.shiori.reader/import")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pick" -> {
                        if (selection != null || copying) result.error("busy", null, null)
                        else {
                            selection = result
                            val picker = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE); type = "*/*"
                                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("text/plain", "application/epub+zip"))
                                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
                            }
                            try { startActivityForResult(picker, 6202) }
                            catch (_: Exception) { selection = null; result.error("unreadable", null, null) }
                        }
                    }
                    "cancel" -> { cancelled.set(true); if (!copying && selection != null) { finishActivity(6202); selection?.success(null); selection = null }; worker.execute { runOnUiThread { result.success(null) } } }
                    "pending", "ack" -> worker.execute {
                        try {
                            val value = locked {
                                File(root, "working").deleteRecursively()
                                val dir = File(root, "pending")
                                if (!dir.exists()) null else {
                                    val json = JSONObject(File(dir, "receipt.json").readText())
                                    if (call.method == "ack") {
                                        if (json.getString("id") == call.argument<String>("id") && !dir.deleteRecursively()) throw Issue("storage")
                                        null
                                    } else mapOf("id" to json.getString("id"), "name" to json.optString("name"),
                                        "size" to json.optLong("size"), "path" to File(dir, "payload").absolutePath)
                                }
                            }
                            runOnUiThread { result.success(value) }
                        } catch (_: Exception) { runOnUiThread { result.error("storage", null, null) } }
                    }
                    else -> result.notImplemented()
                }
            }
        accept(intent)
    }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); accept(intent) }
    override fun onResume() { super.onResume(); events?.success(emptyMap<String, Any>()) }
    private fun problem(code: String) {
        if (events == null) deferredError = code else events?.success(mapOf("error" to code))
    }
    @Suppress("DEPRECATION")
    private fun accept(input: Intent?) {
        if (input == null) return
        val action = input.action
        if (action !in listOf(Intent.ACTION_VIEW, Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE)) return
        val uris = mutableListOf<Uri>()
        if (action == Intent.ACTION_VIEW) input.data?.let { uris.add(it) }
        else if (action == Intent.ACTION_SEND) (input.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))?.let { uris.add(it) }
        else input.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.addAll(it) }
        if (uris.isEmpty()) input.clipData?.let { clip -> for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { uris.add(it) } }
        input.action = null // Do not process the same Activity intent twice.
        if (uris.size != 1 || (input.clipData?.itemCount ?: 0) > 1) { problem(if (uris.size > 1 || (input.clipData?.itemCount ?: 0) > 1) "multiple" else "unsupported"); return }
        receive(uris[0], false)
    }
    @Deprecated("Activity callback required by FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 6202) return
        if (resultCode != Activity.RESULT_OK) {
            selection?.success(null); selection = null; return
        }
        if ((data?.clipData?.itemCount ?: 0) > 1) { selection?.error("multiple", null, null); selection = null; return }
        val uri = data?.data ?: data?.clipData?.getItemAt(0)?.uri
        if (uri == null) { selection?.error("unreadable", null, null); selection = null; return }
        receive(uri, true)
    }
    private fun receive(uri: Uri, picked: Boolean) {
        if (copying) { if (picked) { selection?.error("busy", null, null); selection = null } else problem("busy"); return }
        copying = true; cancelled = AtomicBoolean(false); val token = cancelled
        worker.execute {
            var error: String? = null
            try { locked {
                if (uri.scheme != "content") throw Issue("unsupported")
                val final = File(root, "pending")
                if (final.exists()) throw Issue("busy")
                val name = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) it.getString(0) else null
                } ?: throw Issue("unreadable")
                if (name.substringAfterLast('.', "").lowercase() !in listOf("txt", "epub")) throw Issue("unsupported")
                val dir = File(root, "working"); dir.deleteRecursively(); dir.mkdirs()
                try {
                    var size = 0L
                    contentResolver.openInputStream(uri)?.use { input ->
                        File(dir, "payload").outputStream().use { output ->
                            val buffer = ByteArray(65536)
                            while (true) {
                                if (token.get()) throw Issue("cancelled")
                                val n = input.read(buffer); if (n < 0) break
                                size += n; if (size > 128L * 1024 * 1024) throw Issue("tooLarge")
                                output.write(buffer, 0, n)
                                if (size % (1024 * 1024) < 65536) { val progress = size; runOnUiThread { events?.success(mapOf("bytes" to progress)) } }
                            }
                            output.fd.sync()
                        }
                    } ?: throw Issue("unreadable")
                    if (size == 0L) throw Issue("unreadable")
                    if (token.get()) throw Issue("cancelled")
                    File(dir, "receipt.json").writeText(JSONObject(mapOf("id" to UUID.randomUUID().toString(), "name" to name, "size" to size)).toString())
                    if (!dir.renameTo(final)) throw Issue("storage")
                } finally { dir.deleteRecursively() }
            } } catch (e: Exception) { error = (e as? Issue)?.code ?: if (e is SecurityException || e is FileNotFoundException) "unreadable" else "storage" }
            runOnUiThread {
                copying = false
                if (picked) { if (error == null) selection?.success(null) else selection?.error(error!!, null, null); selection = null }
                else error?.let { problem(it) }
                events?.success(mapOf("done" to true))
            }
        }
    }
    override fun onDestroy() { cancelled.set(true); events = null; worker.shutdown(); super.onDestroy() }
}
