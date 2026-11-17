package com.example.personalmanagement

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val QUICK_CAPTURE_CHANNEL = "com.example.personalmanagement/quick_capture"
    private var pendingQuickCapture: Boolean = false
    private var sharedText: String? = null
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return

        when (intent.action) {
            "com.example.personalmanagement.ACTION_QUICK_CAPTURE" -> {
                pendingQuickCapture = true
                methodChannel?.invokeMethod("onQuickCaptureTriggered", null)
            }
            Intent.ACTION_SEND -> {
                if (intent.type == "text/plain") {
                    sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
                    methodChannel?.invokeMethod("onTextShared", sharedText)
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, QUICK_CAPTURE_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkQuickCaptureTrigger" -> {
                        val trigger = pendingQuickCapture
                        pendingQuickCapture = false
                        result.success(trigger)
                    }
                    "getSharedText" -> {
                        val text = sharedText
                        sharedText = null
                        result.success(text)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // If an intent was received before the engine was attached, dispatch now
        if (pendingQuickCapture) {
            methodChannel?.invokeMethod("onQuickCaptureTriggered", null)
        }
        if (sharedText != null) {
            methodChannel?.invokeMethod("onTextShared", sharedText)
        }
    }
}
