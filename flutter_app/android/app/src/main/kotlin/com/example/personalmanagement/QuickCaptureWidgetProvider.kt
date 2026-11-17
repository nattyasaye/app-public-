package com.example.personalmanagement

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Android Home-Screen Quick Capture Widget Provider.
 * Provides a minimal, 1-tap entry point from the phone's home screen
 * directly into the quick capture dialog without opening full application screens.
 */
class QuickCaptureWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_quick_capture)

            // Intent to launch MainActivity with instant Quick Capture action flag
            val intent = Intent(context, MainActivity::class.java).apply {
                action = "com.example.personalmanagement.ACTION_QUICK_CAPTURE"
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }

            val pendingIntent = PendingIntent.getActivity(
                context,
                appWidgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            views.setOnClickPendingIntent(R.id.btn_widget_capture, pendingIntent)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
