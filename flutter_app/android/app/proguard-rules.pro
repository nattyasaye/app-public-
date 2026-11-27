# Flutter Wrapper and Embedder rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.**

# Drift and native SQLite3 JNI bindings
-keep class org.sqlite.** { *; }
-keep class eu.simonbinder.sqlite3.** { *; }
-dontwarn eu.simonbinder.sqlite3.**

# Flutter Local Notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver { *; }
-keep class com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**

# Android App Widget for Quick Capture
-keep class com.example.personalmanagement.QuickCaptureWidgetProvider { *; }

# Android WorkManager Daily Finance SMS Scanner
-keep class com.example.personalmanagement.SmsInboxScanWorker { *; }
-keep class com.example.personalmanagement.SmsInboxBridge { *; }

# Security and Encrypted SharedPreferences
-keep class androidx.security.crypto.** { *; }
-dontwarn androidx.security.crypto.**

# Desugaring and Java 17 library warnings
-dontwarn java.lang.invoke.**
