package dev.shiori.reader

import android.app.Activity
import android.app.ActivityOptions
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import java.io.File
import java.security.MessageDigest

/** Owns only APK sessions. User databases and reading files are never touched. */
internal class UpdateInstaller(private val context: Context) {
    class Issue(val code: String) : Exception(code)
    private val manager get() = context.packageManager
    private val sessions get() = manager.packageInstaller
    private val record get() = context.getSharedPreferences("update-install", Context.MODE_PRIVATE)

    fun permission() = Build.VERSION.SDK_INT < 26 || manager.canRequestPackageInstalls()

    fun settings(activity: Activity) {
        if (Build.VERSION.SDK_INT >= 26) activity.startActivity(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
        )
    }

    @Suppress("DEPRECATION")
    private fun installed() = manager.getPackageInfo(context.packageName, PackageManager.GET_SIGNATURES)

    fun status(): String {
        val state = record.getString("state", "idle")!!
        if (state == "installing") {
            val current = installed()
            if (versionCode(current) >= record.getLong("build", Long.MAX_VALUE)) {
                saveState("installed")
                return "installed"
            }
            val id = record.getInt("session", -1)
            val info = sessions.mySessions.singleOrNull { it.sessionId == id }
            if (info == null) {
                saveState("cancelled")
                return "cancelled"
            }
            val sealed = if (Build.VERSION.SDK_INT >= 26) info.isSealed else legacySealed(id)
            if (!sealed) {
                sessions.abandonSession(id)
                saveState("cancelled")
                return "cancelled"
            }
            return state
        }
        return if (!permission()) "permissionRequired" else state
    }

    // API 24/25 do not expose SessionInfo.isSealed. Opening and closing an
    // existing write stream without writing is allowed only before sealing.
    // Other failures propagate; an ambiguous state must never abandon an install.
    internal fun legacySealed(id: Int): Boolean = try {
        sessions.openSession(id).use { it.openWrite("base.apk", 0, -1).close() }
        false
    } catch (_: SecurityException) {
        true
    }

    private fun saveState(state: String) {
        if (!record.edit().putString("state", state).commit()) throw Issue("storage")
    }

    @Suppress("DEPRECATION")
    internal fun verify(file: File, args: Map<*, *>) {
        val expectedSize = (args["size"] as? Number)?.toLong() ?: throw Issue("verification")
        val expectedBuild = (args["build"] as? Number)?.toLong() ?: throw Issue("verification")
        val expectedHash = args["sha256"] as? String ?: throw Issue("verification")
        val expectedCertificate = args["certificateSha256"] as? String ?: throw Issue("verification")
        if (expectedSize <= 0 || expectedSize > 2147483648L ||
            !HEX.matches(expectedHash) || !HEX.matches(expectedCertificate)) throw Issue("verification")
        if (!file.isFile || file.length() != expectedSize || digest(file) != expectedHash) {
            throw Issue("packageInvalid")
        }
        val apk = manager.getPackageArchiveInfo(file.path, PackageManager.GET_SIGNATURES)
            ?: throw Issue("verification")
        val current = installed()
        val incoming = apk.signatures?.map { hex(MessageDigest.getInstance("SHA-256").digest(it.toByteArray())) }
        val existing = current.signatures?.map { hex(MessageDigest.getInstance("SHA-256").digest(it.toByteArray())) }
        if (apk.packageName != context.packageName || apk.versionName != args["version"] ||
            versionCode(apk) != expectedBuild || expectedBuild <= versionCode(current) ||
            apk.applicationInfo?.minSdkVersion?.let { it > Build.VERSION.SDK_INT } == true ||
            incoming != listOf(expectedCertificate) || existing != incoming) throw Issue("verification")
    }

    internal fun stage(args: Map<*, *>): Int {
        val file = File(args["path"] as? String ?: throw Issue("verification")).canonicalFile
        // Method-channel callers cannot hand off shared/external storage or traverse out of the sandbox.
        if (!file.path.startsWith(context.filesDir.canonicalPath + File.separator) ||
            file.name != "package.bin" || file.parentFile?.name != "updates") throw Issue("verification")
        verify(file, args)
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(context.packageName)
            setSize(file.length())
            if (Build.VERSION.SDK_INT >= 31) setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
        }
        val id = sessions.createSession(params)
        var staged = false
        try {
            sessions.openSession(id).use { session ->
                val hash = MessageDigest.getInstance("SHA-256")
                var written = 0L
                session.openWrite("base.apk", 0, file.length()).use { output ->
                    file.inputStream().use { input ->
                        val buffer = ByteArray(65536)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            written += count
                            if (written > (args["size"] as Number).toLong()) throw Issue("packageInvalid")
                            hash.update(buffer, 0, count)
                            output.write(buffer, 0, count)
                        }
                    }
                    session.fsync(output)
                }
                if (written != (args["size"] as Number).toLong() || hex(hash.digest()) != args["sha256"]) {
                    throw Issue("packageInvalid")
                }
                if (!record.edit().putInt("session", id).putLong("build", (args["build"] as Number).toLong())
                        .putString("state", "installing").commit()) throw Issue("storage")
            }
            staged = true
            return id
        } finally {
            if (!staged) {
                try { sessions.abandonSession(id) } catch (_: Exception) { }
                saveState("failed")
            }
        }
    }

    @Suppress("DEPRECATION") // API 35 uses ALLOWED; API 36 narrows it to visible apps.
    fun install(args: Map<*, *>): String {
        if (status() == "installing") throw Issue("busy")
        if (!permission()) return "permissionRequired"
        val id = stage(args)
        var committed = false
        try {
            sessions.openSession(id).use { session ->
                val callback = Intent(context, UpdateInstallActivity::class.java).apply {
                    action = "${context.packageName}.UPDATE_RESULT.$id"
                    putExtra("session", id)
                }
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
                // An activity IntentSender delivers confirmation in the foreground; no background
                // receiver tries to launch an activity after the app has been suspended.
                val options = if (Build.VERSION.SDK_INT >= 35) ActivityOptions.makeBasic().apply {
                    setPendingIntentCreatorBackgroundActivityStartMode(
                        if (Build.VERSION.SDK_INT >= 36) ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOW_IF_VISIBLE
                        else ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
                    )
                }.toBundle() else null
                session.commit(PendingIntent.getActivity(context, id, callback, flags, options).intentSender)
                committed = true
            }
            return "installing"
        } finally {
            if (!committed) {
                try { sessions.abandonSession(id) } catch (_: Exception) { }
                saveState("failed")
            }
        }
    }

    @Suppress("DEPRECATION")
    fun receive(activity: Activity, intent: Intent): Boolean {
        val id = record.getInt("session", -1)
        if (id < 0 || intent.getIntExtra("session", -2) != id ||
            intent.action != "${context.packageName}.UPDATE_RESULT.$id" ||
            intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -2) != id) return false
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirmation = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                    ?: run { saveState("failed"); return false }
                try { activity.startActivityForResult(confirmation, 1) }
                catch (_: Exception) {
                    try { sessions.abandonSession(id) } catch (_: Exception) { }
                    saveState("failed")
                    return false
                }
                return true
            }
            PackageInstaller.STATUS_SUCCESS -> saveState("installed")
            PackageInstaller.STATUS_FAILURE_ABORTED -> saveState("cancelled")
            else -> saveState("failed")
        }
        return false
    }

    companion object {
        private val HEX = Regex("[0-9a-f]{64}")
        @Suppress("DEPRECATION")
        internal fun versionCode(info: PackageInfo): Long =
            if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
        internal fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }
        internal fun digest(file: File): String {
            val hash = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buffer = ByteArray(65536)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    hash.update(buffer, 0, count)
                }
            }
            return hex(hash.digest())
        }
    }
}
