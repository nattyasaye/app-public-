package com.example.personalmanagement

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.work.Worker
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Unique one-time WorkManager worker triggered by [SmsReceivedBroadcastReceiver].
 *
 * Reuses the Stage 5 parser + Stage 6 deduplication pipeline via Dart without
 * ever scheduling or altering the daily periodic scan worker.
 */
class SmsImmediateScanWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : Worker(appContext, workerParams) {

    companion object {
        private const val MAX_IMMEDIATE_RETRY_ATTEMPTS = 5
    }

    private fun retryOrUnblockResult(): Result {
        // After bounded retries (~5 minutes across backoff attempts), unblock
        // any downstream incoming SMS in the APPEND_OR_REPLACE chain; daily
        // WorkManager and foreground catch-up serve as backup recovery.
        return if (runAttemptCount >= MAX_IMMEDIATE_RETRY_ATTEMPTS) {
            Result.success()
        } else {
            Result.retry()
        }
    }

    override fun doWork(): Result {
        if (!SmsInboxBridge.hasReceiveSmsPermission(applicationContext)) {
            return Result.success()
        }

        val sender = inputData.getString(SmsInboxBridge.KEY_INPUT_SENDER) ?: ""
        val body = inputData.getString(SmsInboxBridge.KEY_INPUT_BODY) ?: ""
        val receivedAtUtcMillis = inputData.getLong(
            SmsInboxBridge.KEY_INPUT_RECEIVED_AT_UTC_MILLIS,
            System.currentTimeMillis()
        )
        val fallbackToInbox = inputData.getBoolean(
            SmsInboxBridge.KEY_INPUT_FALLBACK_TO_INBOX,
            false
        ) || body.isBlank()

        if (fallbackToInbox && !SmsInboxBridge.hasReadSmsPermission(applicationContext)) {
            // Cannot query Telephony.Sms.Inbox without READ_SMS.
            return Result.success()
        }

        if (!SmsInboxBridge.tryAcquireScanLock()) {
            // Retry shortly so an active periodic/foreground scan never drops this event.
            return retryOrUnblockResult()
        }

        val payload = mapOf<String, Any?>(
            SmsInboxBridge.KEY_INPUT_SENDER to sender,
            SmsInboxBridge.KEY_INPUT_BODY to body,
            SmsInboxBridge.KEY_INPUT_RECEIVED_AT_UTC_MILLIS to receivedAtUtcMillis,
            SmsInboxBridge.KEY_INPUT_FALLBACK_TO_INBOX to fallbackToInbox
        )

        val mainHandler = Handler(Looper.getMainLooper())
        val latch = CountDownLatch(1)
        SmsInboxBridge.registerImmediateWorkerLatch(latch)

        var headlessEngine: FlutterEngine? = null

        try {
            val fgChannel = SmsInboxBridge.getForegroundChannel()
            if (fgChannel != null) {
                mainHandler.post {
                    fgChannel.invokeMethod(
                        "onIncomingSmsReceived",
                        payload,
                        object : MethodChannel.Result {
                            override fun success(result: Any?) {
                                val ok = result as? Boolean ?: true
                                SmsInboxBridge.completeImmediateWorkerRun(ok)
                            }

                            override fun error(
                                errorCode: String,
                                errorMessage: String?,
                                errorDetails: Any?
                            ) {
                                SmsInboxBridge.completeImmediateWorkerRun(false)
                            }

                            override fun notImplemented() {
                                SmsInboxBridge.completeImmediateWorkerRun(false)
                            }
                        }
                    )
                }
            } else {
                SmsInboxBridge.registerPendingImmediatePayload(payload)
                val initLatch = CountDownLatch(1)
                mainHandler.post {
                    try {
                        val loader = FlutterInjector.instance().flutterLoader()
                        loader.startInitialization(applicationContext)
                        loader.ensureInitializationComplete(applicationContext, null)

                        val engine = FlutterEngine(applicationContext)
                        headlessEngine = engine

                        val channel = MethodChannel(
                            engine.dartExecutor.binaryMessenger,
                            SmsInboxBridge.CHANNEL_NAME
                        )
                        channel.setMethodCallHandler { call, result ->
                            SmsInboxBridge.handleCommonMethodCall(
                                context = applicationContext,
                                activity = null,
                                call = call,
                                result = result,
                                onRequestPermission = null,
                                onRequestReceivePermission = null
                            )
                        }

                        val entrypoint = DartExecutor.DartEntrypoint(
                            loader.findAppBundlePath(),
                            "smsBackgroundImmediateProcessMain"
                        )
                        engine.dartExecutor.executeDartEntrypoint(entrypoint)
                    } catch (_: Exception) {
                        SmsInboxBridge.completeImmediateWorkerRun(false)
                    } finally {
                        initLatch.countDown()
                    }
                }
                initLatch.await(15, TimeUnit.SECONDS)
            }

            val completedInTime = latch.await(90, TimeUnit.SECONDS)
            val succeeded = completedInTime && SmsInboxBridge.consumeImmediateWorkerResult()
            return if (succeeded) Result.success() else retryOrUnblockResult()
        } catch (_: Exception) {
            return retryOrUnblockResult()
        } finally {
            SmsInboxBridge.clearPendingImmediateWorkerState()
            val engineToDestroy = headlessEngine
            if (engineToDestroy != null) {
                val destroyLatch = CountDownLatch(1)
                mainHandler.post {
                    try {
                        engineToDestroy.destroy()
                    } catch (_: Exception) {
                    } finally {
                        destroyLatch.countDown()
                    }
                }
                try {
                    destroyLatch.await(5, TimeUnit.SECONDS)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                }
            }
            SmsInboxBridge.releaseScanLock()
        }
    }
}
