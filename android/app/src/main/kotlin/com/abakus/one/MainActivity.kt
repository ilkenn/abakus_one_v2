package com.abakus.one

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // ADR-085 stage 2 (KVKK) — the staff panel, POS and courier screens ask
    // for FLAG_SECURE (no screenshots, recordings or recent-apps preview);
    // see lib/core/services/screen_capture/screen_capture_protection.dart.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "abakus/screen_capture")
            .setMethodCallHandler { call, result ->
                if (call.method != "setProtected") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val protect = call.arguments as? Boolean ?: false
                runOnUiThread {
                    if (protect) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                }
                result.success(null)
            }
    }
}
