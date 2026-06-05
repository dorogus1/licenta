package com.example.focus_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.ActivityManager
import android.content.Context

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.focus_app/app_killer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "killProcess") {
                val packageName = call.argument<String>("packageName")
                if (packageName != null) {
                    killProcess(packageName)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGUMENT", "Package name is null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun killProcess(packageName: String) {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        try {
            am.killBackgroundProcesses(packageName)
        } catch (e: Exception) {
            // Log or ignore
        }
    }
}
