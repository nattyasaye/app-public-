package com.example.personalmanagement

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import androidx.core.app.ActivityCompat
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
    private var smsInboxChannel: MethodChannel? = null
    private var pendingPackagePickResult: MethodChannel.Result? = null
    private var pendingSmsPermissionResult: MethodChannel.Result? = null
    private var pendingReceiveSmsPermissionResult: MethodChannel.Result? = null

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

        smsInboxChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SmsInboxBridge.CHANNEL_NAME
        ).also { channel ->
            SmsInboxBridge.registerForegroundChannel(channel)
            channel.setMethodCallHandler { call, result ->
                SmsInboxBridge.handleCommonMethodCall(
                    context = this,
                    activity = this,
                    call = call,
                    result = result,
                    onRequestPermission = {
                        if (SmsInboxBridge.hasReadSmsPermission(this)) {
                            result.success("granted")
                            return@handleCommonMethodCall
                        }
                        if (pendingSmsPermissionResult != null) {
                            result.error(
                                "PERMISSION_IN_PROGRESS",
                                "A READ_SMS permission request is already active.",
                                null
                            )
                            return@handleCommonMethodCall
                        }
                        pendingSmsPermissionResult = result
                        SmsInboxBridge.markPermissionRequested(this)
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(android.Manifest.permission.READ_SMS),
                            SmsInboxBridge.REQUEST_READ_SMS
                        )
                    },
                    onRequestReceivePermission = {
                        if (SmsInboxBridge.hasReceiveSmsPermission(this)) {
                            result.success("granted")
                            return@handleCommonMethodCall
                        }
                        if (pendingReceiveSmsPermissionResult != null) {
                            result.error(
                                "PERMISSION_IN_PROGRESS",
                                "A RECEIVE_SMS permission request is already active.",
                                null
                            )
                            return@handleCommonMethodCall
                        }
                        pendingReceiveSmsPermissionResult = result
                        SmsInboxBridge.markReceivePermissionRequested(this)
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(android.Manifest.permission.RECEIVE_SMS),
                            SmsInboxBridge.REQUEST_RECEIVE_SMS
                        )
                    }
                )
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

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        smsInboxChannel?.let { SmsInboxBridge.unregisterForegroundChannel(it) }
        smsInboxChannel?.setMethodCallHandler(null)
        smsInboxChannel = null
        pendingSmsPermissionResult = null
        pendingReceiveSmsPermissionResult = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (requestCode == SmsInboxBridge.REQUEST_READ_SMS) {
            val pending = pendingSmsPermissionResult
            pendingSmsPermissionResult = null
            pending?.success(SmsInboxBridge.getPermissionStatus(this, this))
            return
        }
        if (requestCode == SmsInboxBridge.REQUEST_RECEIVE_SMS) {
            val pending = pendingReceiveSmsPermissionResult
            pendingReceiveSmsPermissionResult = null
            pending?.success(SmsInboxBridge.getReceivePermissionStatus(this, this))
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
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
