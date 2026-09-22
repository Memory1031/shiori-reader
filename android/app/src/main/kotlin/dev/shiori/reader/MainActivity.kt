package dev.shiori.reader

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var events: EventChannel.EventSink? = null
    private var selection: MethodChannel.Result? = null
    private var cancelled = AtomicBoolean(false)
    private var copying = false
    private var deferredError: String? = null
    private val inbox by lazy { ImportInbox(File(noBackupFilesDir, "import-inbox")) }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        val updater = UpdateInstaller(this)
        MethodChannel(engine.dartExecutor.binaryMessenger, "dev.shiori.reader/update")
            .setMethodCallHandler { call, result ->
                if (call.method == "settings") {
                    try { updater.settings(this); result.success(null) }
                    catch (_: Exception) { result.error("installation", null, null) }
                } else if (call.method == "install" || call.method == "status") {
                    worker.execute {
                        try {
                            val value = if (call.method == "status") updater.status()
                                else updater.install(call.arguments as? Map<*, *> ?: throw UpdateInstaller.Issue("verification"))
                            runOnUiThread { result.success(value) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error((e as? UpdateInstaller.Issue)?.code ?: "installation", null, null) }
                        }
                    }
                } else result.notImplemented()
            }
        MethodChannel(engine.dartExecutor.binaryMessenger, "dev.shiori.reader/app")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "info" -> {
                        @Suppress("DEPRECATION")
                        val info = packageManager.getPackageInfo(packageName, 0)
                        @Suppress("DEPRECATION")
                        val build = if (android.os.Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                        result.success(mapOf("version" to info.versionName, "build" to build))
                    }
                    "openRelease" -> {
                        val uri = (call.arguments as? String)?.let(Uri::parse)
                        if (uri?.scheme != "https" || uri.host != "github.com" ||
                            uri.userInfo != null || uri.port != -1 ||
                            (uri.path != "/Memory1031/shiori-reader" &&
                                uri.path?.startsWith("/Memory1031/shiori-reader/releases/") != true) ||
                            uri.query != null || uri.fragment != null) {
                            result.success(false)
                        } else {
                            try {
                                startActivity(Intent(Intent.ACTION_VIEW, uri))
                                result.success(true)
                            } catch (_: Exception) { result.success(false) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(engine.dartExecutor.binaryMessenger, "dev.shiori.reader/import_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                    events = sink
                    deferredError?.let { sink.success(mapOf("error" to it)) }
                    deferredError = null
                    sink.success(emptyMap<String, Any>())
                }
                override fun onCancel(args: Any?) { events = null }
            })
        MethodChannel(engine.dartExecutor.binaryMessenger, "dev.shiori.reader/import")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pick" -> pick(result)
                    "cancel" -> {
                        cancelled.set(true)
                        if (!copying && selection != null) {
                            finishActivity(PICK_REQUEST)
                            selection?.success(null)
                            selection = null
                        }
                        // Queued behind the copy: success means its streams are closed
                        // and unpublished working data has been removed.
                        worker.execute { runOnUiThread { result.success(null) } }
                    }
                    "pending", "ack" -> worker.execute {
                        try {
                            val value = if (call.method == "pending") inbox.pending() else {
                                inbox.acknowledge(call.argument<String>("id") ?: throw ImportInbox.Issue("storage"))
                                null
                            }
                            runOnUiThread { result.success(value) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error(issueCode(e), null, null) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        accept(intent)
    }

    private fun pick(result: MethodChannel.Result) {
        if (selection != null || copying) {
            result.error("busy", null, null)
            return
        }
        selection = result
        worker.execute {
            val error = try {
                if (inbox.pending().isNotEmpty()) "busy" else null
            } catch (e: Exception) { issueCode(e) }
            runOnUiThread {
                if (selection !== result) return@runOnUiThread // Cancelled while checking.
                if (error != null) {
                    selection = null
                    result.error(error, null, null)
                } else {
                    try { startActivityForResult(pickerIntent(), PICK_REQUEST) }
                    catch (_: Exception) {
                        selection = null
                        result.error("unreadable", null, null)
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        accept(intent)
    }
    override fun onResume() { super.onResume(); events?.success(emptyMap<String, Any>()) }
    private fun problem(code: String) {
        if (code == "cancelled") return
        if (events == null) deferredError = code else events?.success(mapOf("error" to code))
    }
    private fun accept(input: Intent?) {
        if (input == null || input.action !in listOf(Intent.ACTION_VIEW, Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE)) return
        try { receive(incomingUris(input), false) }
        catch (e: Exception) { problem(issueCode(e)) }
        finally { input.action = null } // Do not consume this delivery twice.
    }

    @Deprecated("Activity callback required by FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_REQUEST || selection == null) return
        if (resultCode != Activity.RESULT_OK) {
            selection?.success(null)
            selection = null
            return
        }
        try { receive(pickerUris(data), true) }
        catch (e: Exception) {
            selection?.error(issueCode(e), null, null)
            selection = null
        }
    }

    private fun prepare(uri: Uri): ImportInbox.Input {
        if (uri.scheme != "content") throw ImportInbox.Issue("unsupported")
        val name = try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            }
        } catch (e: Exception) { throw ImportInbox.Issue("unreadable", e) }
        if (name.isNullOrEmpty()) throw ImportInbox.Issue("unreadable")
        // Providers may omit or lie about SIZE. The inbox enforces actual bytes.
        return ImportInbox.Input(name) {
            contentResolver.openInputStream(uri) ?: throw ImportInbox.Issue("unreadable")
        }
    }

    private fun receive(uris: List<Uri>, picked: Boolean) {
        if (copying || (!picked && selection != null)) {
            if (picked) {
                selection?.error("busy", null, null)
                selection = null
            } else problem("busy")
            return
        }
        copying = true
        cancelled = AtomicBoolean(false)
        val token = cancelled
        events?.success(mapOf("bytes" to 0L))
        worker.execute {
            val error = try {
                inbox.stage(uris.map { uri -> { prepare(uri) } }, token::get) { bytes ->
                    runOnUiThread { events?.success(mapOf("bytes" to bytes)) }
                }
                null
            } catch (e: Exception) { issueCode(e) }
            runOnUiThread {
                copying = false
                if (picked) {
                    if (error == null || error == "cancelled") selection?.success(null)
                    else selection?.error(error, null, null)
                    selection = null
                } else error?.let { problem(it) }
                events?.success(mapOf("done" to true))
            }
        }
    }

    override fun onDestroy() {
        cancelled.set(true)
        events = null
        worker.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val PICK_REQUEST = 6202
        private fun issueCode(error: Exception) = (error as? ImportInbox.Issue)?.code ?: "storage"

        internal fun pickerIntent() = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("text/plain", "application/epub+zip"))
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }

        private fun clipUris(input: Intent): List<Uri> {
            val clip = input.clipData ?: return emptyList()
            if (clip.itemCount > ImportInbox.MAX_FILES) throw ImportInbox.Issue("batchLimit")
            return (0 until clip.itemCount).map {
                clip.getItemAt(it).uri ?: throw ImportInbox.Issue("unreadable")
            }
        }
        private fun checked(uris: List<Uri>): List<Uri> {
            if (uris.isEmpty()) throw ImportInbox.Issue("unreadable")
            if (uris.size > ImportInbox.MAX_FILES) throw ImportInbox.Issue("batchLimit")
            return uris
        }
        internal fun pickerUris(input: Intent?): List<Uri> {
            if (input == null) throw ImportInbox.Issue("unreadable")
            return checked(if (input.clipData != null) clipUris(input) else listOfNotNull(input.data))
        }
        @Suppress("DEPRECATION")
        internal fun incomingUris(input: Intent): List<Uri> = checked(when (input.action) {
            Intent.ACTION_VIEW -> listOfNotNull(input.data)
            Intent.ACTION_SEND -> input.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let { listOf(it) }
                ?: clipUris(input)
            Intent.ACTION_SEND_MULTIPLE -> input.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                ?.takeIf { it.isNotEmpty() } ?: clipUris(input)
            else -> throw ImportInbox.Issue("unsupported")
        })
    }
}
