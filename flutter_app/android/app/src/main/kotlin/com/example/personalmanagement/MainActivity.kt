package com.example.personalmanagement

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val QUICK_CAPTURE_CHANNEL = "com.example.personalmanagement/quick_capture"
    private val PROJECT_PACKAGE_CHANNEL = "com.example.personalmanagement/project_package"
    private val REQUEST_PICK_PROJECT_PACKAGE = 9103

    private var pendingQuickCapture: Boolean = false
    private var sharedText: String? = null
    private var methodChannel: MethodChannel? = null
    private var pendingPackagePickResult: MethodChannel.Result? = null

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PROJECT_PACKAGE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickProjectPackageFile" -> {
                    if (pendingPackagePickResult != null) {
                        result.error(
                            "PICK_IN_PROGRESS",
                            "A file picker dialog is already active.",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    pendingPackagePickResult = result
                    try {
                        val pickerIntent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                        }
                        startActivityForResult(pickerIntent, REQUEST_PICK_PROJECT_PACKAGE)
                    } catch (e: Exception) {
                        val pending = pendingPackagePickResult
                        pendingPackagePickResult = null
                        pending?.error(
                            "PICK_LAUNCH_FAILED",
                            e.message ?: "Unable to launch system file picker.",
                            null
                        )
                    }
                }
                else -> result.notImplemented()
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_PICK_PROJECT_PACKAGE) {
            val pending = pendingPackagePickResult
            pendingPackagePickResult = null
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                pending?.success(null)
                return
            }
            val uri: Uri = data.data!!
            try {
                val displayName = resolveDisplayName(uri) ?: "project.daywellproject"
                val content = contentResolver.openInputStream(uri)?.use { stream ->
                    stream.bufferedReader(Charsets.UTF_8).readText()
                }
                if (content == null) {
                    pending?.error(
                        "READ_ERROR",
                        "Unable to open selected file stream.",
                        null
                    )
                    return
                }
                pending?.success(
                    mapOf(
                        "filename" to displayName,
                        "content" to content
                    )
                )
            } catch (e: Exception) {
                pending?.error(
                    "READ_ERROR",
                    e.message ?: "Failed to read selected .daywellproject file.",
                    null
                )
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun resolveDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null
            )?.use { cursor ->
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && cursor.moveToFirst()) {
                    cursor.getString(idx)
                } else {
                    null
                }
            }
        } catch (_: Exception) {
            uri.lastPathSegment
        }
    }
}
