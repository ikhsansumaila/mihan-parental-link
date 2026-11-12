package com.mihan.parentallink

import android.Manifest
import android.app.NotificationManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val admin by lazy { ComponentName(this, AdminReceiver::class.java) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mihan_parental_link/enforcer").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getDeviceId" -> result.success(Prefs.deviceId(this))
                    "getModel" -> result.success("${Build.MANUFACTURER} ${Build.MODEL}".trim())
                    "activate" -> {
                        Prefs.setDeviceId(this, call.argument<String>("deviceId"))
                        LockState.refresh(this)
                        EnforcerService.start(this)
                        result.success(null)
                    }
                    "status" -> result.success(status())
                    "openAccessibility" -> {
                        Prefs.pauseGuard(this, 120_000)
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(null)
                    }
                    "requestAdmin" -> {
                        Prefs.pauseGuard(this, 120_000)
                        startActivity(Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
                            putExtra(
                                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                "Mencegah aplikasi pengawasan dihapus tanpa izin orang tua.",
                            )
                        })
                        result.success(null)
                    }
                    "requestBattery" -> {
                        Prefs.pauseGuard(this, 60_000)
                        @Suppress("BatteryLife")
                        startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
                        result.success(null)
                    }
                    "requestNotifications" -> {
                        if (Build.VERSION.SDK_INT >= 33) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                        } else {
                            startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("ERR", e.message, null)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (Prefs.deviceId(this) != null) EnforcerService.start(this)
    }

    private fun status(): Map<String, Any?> {
        LockState.refresh(this)
        val d = LockState.decision
        return mapOf(
            "deviceId" to Prefs.deviceId(this),
            "accessibility" to GuardService.isEnabled(this),
            "admin" to getSystemService(DevicePolicyManager::class.java).isAdminActive(admin),
            "battery" to getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName),
            "notifications" to getSystemService(NotificationManager::class.java).areNotificationsEnabled(),
            "locked" to d.locked,
            "reason" to d.reason,
            "nextChange" to d.nextChange,
        )
    }
}
