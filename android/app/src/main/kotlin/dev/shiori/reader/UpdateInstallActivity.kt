package dev.shiori.reader

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/** Explicit, non-exported PackageInstaller callback; no Flutter engine is created here. */
class UpdateInstallActivity : Activity() {
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        if (state == null && UpdateInstaller(this).receive(this, intent)) return
        if (state == null) finish()
    }

    @Deprecated("System installer confirmation callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        // The session's final callback records success/failure, including cancellation.
        finish()
    }
}
