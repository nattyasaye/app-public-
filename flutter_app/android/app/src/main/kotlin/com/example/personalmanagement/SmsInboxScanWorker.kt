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

class SmsInboxScanWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : Worker(appContext, workerParams) {

    override fun doWork(): Result {
        if (!SmsInboxBridge.hasReadSmsPermission(applicationContext)) {
            SmsInboxBridge.cancelDailyScan(applicationContext)
            return Result.success()
        }

        if (!SmsInboxBridge.tryAcquireScanLock()) {
            // Another scan (e.g. foreground catch-up) is already in progress.
            return Result.success()
        }

        val mainHandler = Handler(Looper.getMainLooper())
        val latch = CountDownLatch(1)
        SmsInboxBridge.registerWorkerLatch(latch)

        var headlessEngine: FlutterEngine? = null

        try {
            val fgChannel = SmsInboxBridge.getForegroundChannel()
            if (fgChannel != null) {
                mainHandler.post {
                    fgChannel.invokeMethod(
                        "onBackgroundScanRequested",
                        null,
                        object : MethodChannel.Result {
                            override fun success(result: Any?) {
                                val ok = result as? Boolean ?: true
                                SmsInboxBridge.completeWorkerRun(ok)
                            }

                            override fun error(
                                errorCode: String,
                                errorMessage: String?,
                                errorDetails: Any?
                            ) {
                                SmsInboxBridge.completeWorkerRun(false)
                            }

                            override fun notImplemented() {
                                SmsInboxBridge.completeWorkerRun(false)
                            }
                        }
                    )
                }
            } else {
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
                                onRequestPermission = null
                            )
                        }

                        val entrypoint = DartExecutor.DartEntrypoint(
                            loader.findAppBundlePath(),
                            "smsBackgroundScanMain"
                        )
                        engine.dartExecutor.executeDartEntrypoint(entrypoint)
                    } catch (_: Exception) {
                        SmsInboxBridge.completeWorkerRun(false)
                    } finally {
                        initLatch.countDown()
                    }
                }
                initLatch.await(15, TimeUnit.SECONDS)
            }

            val completedInTime = latch.await(90, TimeUnit.SECONDS)
            val succeeded = completedInTime && SmsInboxBridge.consumeWorkerResult()
            return if (succeeded) Result.success() else Result.retry()
        } catch (_: Exception) {
            return Result.retry()
        } finally {
            SmsInboxBridge.clearPendingWorkerCompletion()
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
