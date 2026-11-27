package com.example.personalmanagement

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.provider.Telephony
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.WorkRequest
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

object SmsInboxBridge {
    const val CHANNEL_NAME = "com.example.personalmanagement/sms_inbox"
    const val REQUEST_READ_SMS = 9104
    const val REQUEST_RECEIVE_SMS = 9105

    const val KEY_INPUT_SENDER = "sender"
    const val KEY_INPUT_BODY = "body"
    const val KEY_INPUT_RECEIVED_AT_UTC_MILLIS = "receivedAtUtcMillis"
    const val KEY_INPUT_FALLBACK_TO_INBOX = "fallbackToInbox"

    private const val UNIQUE_WORK_NAME = "daywell_daily_finance_sms_scan"
    private const val UNIQUE_IMMEDIATE_WORK_NAME = "daywell_immediate_finance_sms_process"
    private const val PREFS_NAME = "daywell_sms_inbox_prefs"
    private const val KEY_PERMISSION_REQUESTED_ONCE = "sms_permission_requested_once"
    private const val KEY_RECEIVE_PERMISSION_REQUESTED_ONCE = "sms_receive_permission_requested_once"
    private const val DEFAULT_QUERY_LIMIT = 500
    private const val MAX_WORK_DATA_BODY_BYTES = 7500

    private val scanInProgress = AtomicBoolean(false)
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var foregroundChannel: MethodChannel? = null

    @Volatile
    private var activeWorkerLatch: CountDownLatch? = null

    @Volatile
    private var activeWorkerSucceeded: Boolean = false

    @Volatile
    private var activeImmediateWorkerLatch: CountDownLatch? = null

    @Volatile
    private var activeImmediateWorkerSucceeded: Boolean = false

    @Volatile
    private var pendingImmediatePayload: Map<String, Any?>? = null

    fun registerForegroundChannel(channel: MethodChannel) {
        foregroundChannel = channel
    }

    fun unregisterForegroundChannel(channel: MethodChannel) {
        if (foregroundChannel === channel) {
            foregroundChannel = null
        }
    }

    fun getForegroundChannel(): MethodChannel? = foregroundChannel

    fun tryAcquireScanLock(): Boolean = scanInProgress.compareAndSet(false, true)

    fun releaseScanLock() {
        scanInProgress.set(false)
    }

    fun registerWorkerLatch(latch: CountDownLatch) {
        activeWorkerSucceeded = false
        activeWorkerLatch = latch
    }

    fun completeWorkerRun(success: Boolean) {
        activeWorkerSucceeded = success
        activeWorkerLatch?.countDown()
    }

    fun consumeWorkerResult(): Boolean = activeWorkerSucceeded

    fun clearPendingWorkerCompletion() {
        activeWorkerLatch = null
    }

    fun registerImmediateWorkerLatch(latch: CountDownLatch) {
        activeImmediateWorkerSucceeded = false
        activeImmediateWorkerLatch = latch
    }

    fun completeImmediateWorkerRun(success: Boolean) {
        activeImmediateWorkerSucceeded = success
        activeImmediateWorkerLatch?.countDown()
    }

    fun consumeImmediateWorkerResult(): Boolean = activeImmediateWorkerSucceeded

    fun registerPendingImmediatePayload(payload: Map<String, Any?>) {
        pendingImmediatePayload = payload
    }

    fun consumePendingImmediatePayload(): Map<String, Any?>? {
        val payload = pendingImmediatePayload
        pendingImmediatePayload = null
        return payload
    }

    fun clearPendingImmediateWorkerState() {
        activeImmediateWorkerLatch = null
        pendingImmediatePayload = null
    }

    fun hasReadSmsPermission(context: Context): Boolean {
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.READ_SMS
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun hasReceiveSmsPermission(context: Context): Boolean {
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.RECEIVE_SMS
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun markPermissionRequested(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_PERMISSION_REQUESTED_ONCE, true)
            .apply()
    }

    fun wasPermissionRequestedBefore(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_PERMISSION_REQUESTED_ONCE, false)
    }

    fun markReceivePermissionRequested(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_RECEIVE_PERMISSION_REQUESTED_ONCE, true)
            .apply()
    }

    fun wasReceivePermissionRequestedBefore(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_RECEIVE_PERMISSION_REQUESTED_ONCE, false)
    }

    fun getPermissionStatus(context: Context, activity: Activity? = null): String {
        if (hasReadSmsPermission(context)) {
            return "granted"
        }
        if (!wasPermissionRequestedBefore(context)) {
            return "notRequested"
        }
        if (activity != null &&
            ActivityCompat.shouldShowRequestPermissionRationale(
                activity,
                Manifest.permission.READ_SMS
            )
        ) {
            return "denied"
        }
        return if (activity != null) "permanentlyDenied" else "denied"
    }

    fun getReceivePermissionStatus(context: Context, activity: Activity? = null): String {
        if (hasReceiveSmsPermission(context)) {
            return "granted"
        }
        if (!wasReceivePermissionRequestedBefore(context)) {
            return "notRequested"
        }
        if (activity != null &&
            ActivityCompat.shouldShowRequestPermissionRationale(
                activity,
                Manifest.permission.RECEIVE_SMS
            )
        ) {
            return "denied"
        }
        return if (activity != null) "permanentlyDenied" else "denied"
    }

    fun readInboxMessages(
        context: Context,
        sinceUtcMillis: Long?,
        limit: Int
    ): List<Map<String, Any?>> {
        if (!hasReadSmsPermission(context)) {
            return emptyList()
        }

        val cappedLimit = limit.coerceIn(1, 2000)
        val projection = arrayOf(
            Telephony.Sms._ID,
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE,
            Telephony.Sms.TYPE
        )

        val selection: String
        val selectionArgs: Array<String>
        if (sinceUtcMillis != null && sinceUtcMillis > 0L) {
            selection = "${Telephony.Sms.TYPE} = ? AND ${Telephony.Sms.DATE} >= ?"
            selectionArgs = arrayOf(
                Telephony.Sms.MESSAGE_TYPE_INBOX.toString(),
                sinceUtcMillis.toString()
            )
        } else {
            selection = "${Telephony.Sms.TYPE} = ?"
            selectionArgs = arrayOf(Telephony.Sms.MESSAGE_TYPE_INBOX.toString())
        }

        val sortOrder = "${Telephony.Sms.DATE} ASC, ${Telephony.Sms._ID} ASC"
        val results = ArrayList<Map<String, Any?>>()

        // Read-only query. Never modifies, deletes, sends, or updates read/unread status.
        context.contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            sortOrder
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndex(Telephony.Sms._ID)
            val addrIdx = cursor.getColumnIndex(Telephony.Sms.ADDRESS)
            val bodyIdx = cursor.getColumnIndex(Telephony.Sms.BODY)
            val dateIdx = cursor.getColumnIndex(Telephony.Sms.DATE)

            while (cursor.moveToNext() && results.size < cappedLimit) {
                val id = if (idIdx >= 0) cursor.getLong(idIdx).toString() else ""
                val sender = if (addrIdx >= 0) (cursor.getString(addrIdx) ?: "") else ""
                val body = if (bodyIdx >= 0) (cursor.getString(bodyIdx) ?: "") else ""
                val dateMs = if (dateIdx >= 0) cursor.getLong(dateIdx) else 0L
                if (body.isBlank() || dateMs <= 0L) {
                    continue
                }
                results.add(
                    mapOf(
                        "id" to id,
                        "sender" to sender,
                        "body" to body,
                        "receivedAtUtcMillis" to dateMs
                    )
                )
            }
        }

        return results
    }

    fun scheduleDailyScan(context: Context) {
        val workRequest = PeriodicWorkRequestBuilder<SmsInboxScanWorker>(
            24,
            TimeUnit.HOURS
        )
            .setConstraints(Constraints.NONE)
            .setBackoffCriteria(
                BackoffPolicy.EXPONENTIAL,
                15,
                TimeUnit.MINUTES
            )
            .build()

        WorkManager.getInstance(context.applicationContext)
            .enqueueUniquePeriodicWork(
                UNIQUE_WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                workRequest
            )
    }

    fun cancelDailyScan(context: Context) {
        WorkManager.getInstance(context.applicationContext)
            .cancelUniqueWork(UNIQUE_WORK_NAME)
    }

    fun enqueueImmediateSmsProcessing(
        context: Context,
        sender: String,
        body: String,
        receivedAtUtcMillis: Long,
        fallbackToInbox: Boolean = false
    ) {
        if (!hasReceiveSmsPermission(context)) {
            return
        }

        val bodyBytes = body.toByteArray(Charsets.UTF_8).size
        val useInboxFallback = fallbackToInbox ||
            body.isBlank() ||
            bodyBytes > MAX_WORK_DATA_BODY_BYTES

        val inputData = Data.Builder()
            .putString(KEY_INPUT_SENDER, if (useInboxFallback) "" else sender.take(128))
            .putString(KEY_INPUT_BODY, if (useInboxFallback) "" else body)
            .putLong(KEY_INPUT_RECEIVED_AT_UTC_MILLIS, receivedAtUtcMillis)
            .putBoolean(KEY_INPUT_FALLBACK_TO_INBOX, useInboxFallback)
            .build()

        // Unique one-time work request ONLY — never touches or duplicates the daily periodic scan.
        val workRequest = OneTimeWorkRequestBuilder<SmsImmediateScanWorker>()
            .setConstraints(Constraints.NONE)
            .setInputData(inputData)
            .setBackoffCriteria(
                BackoffPolicy.EXPONENTIAL,
                WorkRequest.MIN_BACKOFF_MILLIS,
                TimeUnit.MILLISECONDS
            )
            .build()

        WorkManager.getInstance(context.applicationContext)
            .enqueueUniqueWork(
                UNIQUE_IMMEDIATE_WORK_NAME,
                ExistingWorkPolicy.APPEND_OR_REPLACE,
                workRequest
            )
    }

    fun isDailyScanScheduledAsync(
        context: Context,
        callback: (Boolean) -> Unit
    ) {
        val future = WorkManager.getInstance(context.applicationContext)
            .getWorkInfosForUniqueWork(UNIQUE_WORK_NAME)
        future.addListener(
            {
                val scheduled = try {
                    val infos = future.get()
                    infos.any { info ->
                        info.state == WorkInfo.State.ENQUEUED ||
                            info.state == WorkInfo.State.RUNNING ||
                            info.state == WorkInfo.State.BLOCKED
                    }
                } catch (_: Exception) {
                    false
                }
                mainHandler.post { callback(scheduled) }
            },
            ioExecutor
        )
    }

    fun openAppSettings(context: Context): Boolean {
        return try {
            val intent = Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", context.packageName, null)
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    fun handleCommonMethodCall(
        context: Context,
        activity: Activity?,
        call: MethodCall,
        result: MethodChannel.Result,
        onRequestPermission: (() -> Unit)? = null,
        onRequestReceivePermission: (() -> Unit)? = null
    ) {
        when (call.method) {
            "getPermissionStatus" -> {
                result.success(getPermissionStatus(context, activity))
            }
            "requestPermission" -> {
                if (onRequestPermission != null) {
                    onRequestPermission()
                } else {
                    result.success(getPermissionStatus(context, activity))
                }
            }
            "getReceivePermissionStatus" -> {
                result.success(getReceivePermissionStatus(context, activity))
            }
            "requestReceivePermission" -> {
                if (onRequestReceivePermission != null) {
                    onRequestReceivePermission()
                } else {
                    result.success(getReceivePermissionStatus(context, activity))
                }
            }
            "openAppSettings" -> {
                result.success(openAppSettings(context))
            }
            "readInboxMessages" -> {
                val sinceRaw = call.argument<Number>("sinceUtcMillis")
                val sinceUtcMillis = sinceRaw?.toLong()
                val limit = call.argument<Number>("limit")?.toInt() ?: DEFAULT_QUERY_LIMIT
                ioExecutor.execute {
                    try {
                        val messages = readInboxMessages(context, sinceUtcMillis, limit)
                        mainHandler.post { result.success(messages) }
                    } catch (e: Exception) {
                        mainHandler.post {
                            result.error(
                                "SMS_READ_FAILED",
                                e.message ?: "Unable to read Android SMS inbox.",
                                null
                            )
                        }
                    }
                }
            }
            "scheduleDailyScan" -> {
                try {
                    scheduleDailyScan(context)
                    result.success(true)
                } catch (e: Exception) {
                    result.error(
                        "WORKMANAGER_SCHEDULE_FAILED",
                        e.message ?: "Unable to schedule daily SMS scan.",
                        null
                    )
                }
            }
            "cancelDailyScan" -> {
                try {
                    cancelDailyScan(context)
                    result.success(true)
                } catch (e: Exception) {
                    result.error(
                        "WORKMANAGER_CANCEL_FAILED",
                        e.message ?: "Unable to cancel daily SMS scan.",
                        null
                    )
                }
            }
            "isDailyScanScheduled" -> {
                isDailyScanScheduledAsync(context) { scheduled ->
                    result.success(scheduled)
                }
            }
            "tryAcquireScanLock" -> {
                result.success(tryAcquireScanLock())
            }
            "releaseScanLock" -> {
                releaseScanLock()
                result.success(true)
            }
            "completeBackgroundScan" -> {
                val success = call.argument<Boolean>("success") ?: false
                completeWorkerRun(success)
                result.success(true)
            }
            "consumePendingIncomingSms" -> {
                result.success(consumePendingImmediatePayload())
            }
            "completeBackgroundIncomingSms" -> {
                val success = call.argument<Boolean>("success") ?: false
                completeImmediateWorkerRun(success)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }
}
