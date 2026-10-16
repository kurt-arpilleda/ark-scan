package com.example.arkscan

import android.content.Context
import android.content.Intent
import android.content.ComponentName
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "input_method_channel"
    private val NOTIF_PACKAGE = "com.example.ark_notif"
    private val NOTIF_SERVICE = "com.example.ark_notif.RingMonitoringService"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Start your notification service
        startNotificationService()

        // Check and prompt for unknown app sources permission
        checkInstallUnknownAppsPermission()

        // Setup your method channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "showInputMethodPicker") {
                val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
                imm.showInputMethodPicker()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun startNotificationService() {
        try {
            val intent = Intent().apply {
                component = ComponentName(NOTIF_PACKAGE, NOTIF_SERVICE)
                action = "START_MONITORING"
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun checkInstallUnknownAppsPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (!packageManager.canRequestPackageInstalls()) {
                // Open settings so user can enable permission
                val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                    data = Uri.parse("package:$packageName")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(intent)
            }
        }
    }
}

