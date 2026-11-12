package com.octalink.octalink

import android.app.admin.DeviceAdminReceiver
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Device admin: mencegah uninstall langsung & memungkinkan lockNow(). */
class AdminReceiver : DeviceAdminReceiver() {
    override fun onDisableRequested(context: Context, intent: Intent): CharSequence =
        "Menonaktifkan ini akan mematikan pengawasan orang tua. Orang tua akan diberi tahu."
}

/** Nyalakan lagi service setelah HP restart atau aplikasi di-update. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        LockState.refresh(context)
        EnforcerService.start(context)
    }
}
