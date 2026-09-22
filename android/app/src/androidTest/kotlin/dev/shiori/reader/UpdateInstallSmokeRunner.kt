package dev.shiori.reader

import android.content.Intent
import android.content.pm.PackageManager
import android.os.SystemClock
import android.app.Instrumentation
import android.os.Bundle
import junit.framework.Assert.*
import android.view.accessibility.AccessibilityNodeInfo
import java.io.File

/** Explicit device smoke. Stage a higher-build, same-signer APK under files/update-smoke/updates.
 * Run an explicit mode through UpdateInstallSmokeRunner; confirm replaces/kills the target app.
 * No uninstall, data clear, signing key, network source or production Dart bypass is involved.
 */
@Suppress("DEPRECATION")
internal class UpdateInstallProbe(private val instrumentation: Instrumentation) {
    private val app get() = instrumentation.targetContext
    private val updater get() = UpdateInstaller(app)
    private val candidate get() = File(app.filesDir, "update-smoke/updates/package.bin")
    private fun args(file: File = candidate): Map<String, Any> {
        val apk = app.packageManager.getPackageArchiveInfo(file.path, PackageManager.GET_SIGNATURES)!!
        val signature = java.security.MessageDigest.getInstance("SHA-256").digest(apk.signatures!![0].toByteArray())
        return mapOf("path" to file.path, "size" to file.length(), "sha256" to UpdateInstaller.digest(file),
            "version" to apk.versionName!!, "build" to UpdateInstaller.versionCode(apk),
            "certificateSha256" to UpdateInstaller.hex(signature))
    }
    private fun reject(values: Map<String, Any>, file: File = candidate, code: String = "verification") {
        try { updater.verify(file, values); fail("Expected verification rejection") }
        catch (error: UpdateInstaller.Issue) { assertEquals(code, error.code) }
    }
    fun testMetadata() {
        val values = args()
        updater.verify(candidate, values)
        reject(values + ("sha256" to "0".repeat(64)), code = "packageInvalid")
        reject(values + ("size" to candidate.length() + 1), code = "packageInvalid")
        reject(values + ("certificateSha256" to "0".repeat(64)))
        reject(values + ("version" to "0.0.0"))
        reject(values + ("build" to 1))
        val old = File(app.applicationInfo.sourceDir)
        reject(args(old), old)
    }
    fun testWrongSigner() {
        val wrong = File(app.filesDir, "update-smoke/wrong.apk")
        // Metadata truthfully names the other signer: it still must match the installed app.
        reject(args(wrong), wrong)
    }
    fun testPermissionDenied() {
        assertFalse(updater.permission())
        assertEquals("permissionRequired", updater.install(args()))
    }
    fun testPrecommit() {
        File(app.filesDir, "update-smoke/precommit").delete()
        val id = updater.stage(args())
        val info = app.packageManager.packageInstaller.getSessionInfo(id)!!
        if (android.os.Build.VERSION.SDK_INT >= 26) {
            assertFalse(info.isSealed)
        }
        assertFalse(updater.legacySealed(id))
        File(app.filesDir, "update-smoke/precommit").writeText(id.toString())
        // The external harness kills this process; production has no pause hook.
        java.util.concurrent.CountDownLatch(1).await()
    }
    fun testRecover() {
        val id = File(app.filesDir, "update-smoke/precommit").readText().toInt()
        val sessions = app.packageManager.packageInstaller
        val record = app.getSharedPreferences("update-install", 0)
        assertEquals("installing", record.getString("state", null))
        assertEquals(id, record.getInt("session", -1))
        val retained = sessions.getSessionInfo(id) != null
        instrumentation.sendStatus(0, Bundle().apply {
            putString("stream", "Uncommitted session retained after process death: $retained\n")
        })
        assertEquals("cancelled", updater.status())
        assertNull(sessions.getSessionInfo(id))
        assertTrue(candidate.exists())
        testCancel()
    }
    fun testUncommitted() {
        val id = updater.stage(args())
        val sessions = app.packageManager.packageInstaller
        assertNotNull(sessions.getSessionInfo(id))
        assertFalse(updater.legacySealed(id))
        // Explicitly exercise a retained session even on systems that abandon
        // sessions automatically when their owner process dies.
        assertEquals("cancelled", UpdateInstaller(app).status())
        assertNull(sessions.getSessionInfo(id))
        testCancel()
    }
    private fun foreground() {
        // A killed smoke process may leave its system dialog in a separate task.
        // Dismiss only an observed installer dialog before starting the next session.
        val automation = instrumentation.uiAutomation
        repeat(5) {
            val root = automation.rootInActiveWindow
            if (root?.packageName?.toString()?.contains("packageinstaller") == true) {
                button(root, false)?.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                SystemClock.sleep(500)
            }
        }
        instrumentation.runOnMainSync {
            app.startActivity(Intent(app, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
        SystemClock.sleep(1500)
    }
    private fun button(root: AccessibilityNodeInfo?, accept: Boolean): AccessibilityNodeInfo? {
        if (root == null) return null
        val labels = if (accept) listOf("安装", "更新", "Install", "Update", "INSTALL", "UPDATE")
            else listOf("取消", "Cancel", "CANCEL")
        if (root.isVisibleToUser && root.isClickable && root.isEnabled && root.text?.toString() in labels) return root
        for (i in 0 until root.childCount) button(root.getChild(i), accept)?.let { return it }
        return null
    }
    private fun confirm(accept: Boolean) {
        val automation = instrumentation.uiAutomation
        automation.serviceInfo = automation.serviceInfo.apply {
            flags = flags or android.accessibilityservice.AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        }
        val deadline = SystemClock.uptimeMillis() + 20000
        while (SystemClock.uptimeMillis() < deadline) {
            val roots = listOf(automation.rootInActiveWindow) + automation.windows.filter { it.isActive || it.isFocused }.map { it.root }
            for (root in roots) {
                if (root?.packageName?.toString()?.contains("packageinstaller") == true) {
                    button(root, accept)?.let {
                        assertTrue(it.performAction(AccessibilityNodeInfo.ACTION_CLICK))
                        return
                    }
                }
            }
            SystemClock.sleep(200)
        }
        fun describe(node: AccessibilityNodeInfo?): String = if (node == null) "null" else
            "[${node.packageName}: ${node.text} clickable=${node.isClickable}]" +
                (0 until node.childCount).joinToString { describe(node.getChild(it)) }
        fail("No system installation confirmation: ${describe(automation.rootInActiveWindow)}")
    }
    private fun stage() {
        // Wait for this session's new window event, not a cached accessibility tree
        // from a previous installer dialog in MuMu's separate activity task.
        instrumentation.uiAutomation.executeAndWaitForEvent(
            { assertEquals("installing", updater.install(args())) },
            { it.eventType == android.view.accessibility.AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
                it.packageName?.toString()?.contains("packageinstaller") == true },
            20000
        )
        SystemClock.sleep(500)
        assertEquals("installing", updater.status())
        val id = app.getSharedPreferences("update-install", 0).getInt("session", -1)
        assertTrue(updater.legacySealed(id))
    }
    fun testCancel() {
        foreground()
        stage()
        confirm(false)
        val deadline = SystemClock.uptimeMillis() + 10000
        while (updater.status() == "installing" && SystemClock.uptimeMillis() < deadline) SystemClock.sleep(100)
        assertEquals("cancelled", updater.status())
        assertTrue(candidate.exists())
    }
    fun testConfirm() {
        foreground()
        stage()
        confirm(true)
        // The harness checks actual installed version and saved user data after process death.
        SystemClock.sleep(15000)
    }
    fun testInstalled() {
        val expected = args()
        val current = app.packageManager.getPackageInfo(app.packageName, 0)
        assertEquals(expected["version"], current.versionName)
        assertEquals(expected["build"], UpdateInstaller.versionCode(current))
        assertEquals("installed", updater.status())
    }
}

/** Dedicated runner: ordinary instrumentation discovery never initiates installation. */
class UpdateInstallSmokeRunner : Instrumentation() {
    private var mode: String? = null
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        mode = arguments?.getString("mode")
        start()
    }
    override fun onStart() {
        val result = Bundle()
        try {
            val probe = UpdateInstallProbe(this)
            when (mode) {
                "metadata" -> probe.testMetadata()
                "wrong-signer" -> probe.testWrongSigner()
                "permission-denied" -> probe.testPermissionDenied()
                "precommit" -> probe.testPrecommit()
                "recover" -> probe.testRecover()
                "uncommitted" -> probe.testUncommitted()
                "cancel" -> probe.testCancel()
                "confirm" -> probe.testConfirm()
                "installed" -> probe.testInstalled()
                else -> error("An explicit smoke mode is required")
            }
            result.putString("stream", "PASS: $mode\n")
            finish(-1, result)
        } catch (error: Throwable) {
            result.putString("stream", "FAIL: $mode $error\n")
            finish(0, result)
        }
    }
}
