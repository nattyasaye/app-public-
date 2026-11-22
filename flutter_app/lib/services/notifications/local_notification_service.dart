import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../core/date/shared_date.dart';
import '../../core/interfaces/platform_service_interfaces.dart';

/// Offline-first implementation of [INotificationService] for local reminders.
///
/// Features:
/// - 100% offline operation: no cloud push servers or internet dependency
/// - Android 13+ (API 33) notification permission handling
/// - Deterministic notification IDs across app restarts
/// - In-session timed delivery via `flutter_local_notifications` and native
///   channels for Tasks, Commitments, and Custom Reminders
class LocalNotificationService implements INotificationService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final Map<String, Timer> _scheduledTimers = <String, Timer>{};
  bool _isInitialized = false;

  static const String taskChannelId = 'task_reminders_channel';
  static const String commitmentChannelId = 'commitment_reminders_channel';
  static const String customChannelId = 'custom_reminders_channel';

  /// Safe positive 32-bit FNV-1a integer ID deterministic across Dart VM runs.
  static int deterministicNotificationId(String id) {
    var hash = 0x811c9dc5;
    for (final unit in id.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    final positive = hash & 0x7FFFFFFF;
    return positive == 0 ? 1 : positive;
  }

  @visibleForTesting
  int get activeScheduledTimerCount => _scheduledTimers.length;

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        // Handle in-app navigation when notification is tapped
      },
    );

    await _createNotificationChannels();
    _isInitialized = true;
  }

  Future<void> _createNotificationChannels() async {
    final androidPlugin =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          taskChannelId,
          'Task Reminders',
          description:
              'Local offline alerts for scheduled tasks and upcoming deadlines',
          importance: Importance.high,
          playSound: true,
        ),
      );

      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          commitmentChannelId,
          'Financial Commitment Alerts',
          description:
              'Offline reminders for rent, bills, and payment due dates',
          importance: Importance.high,
          playSound: true,
        ),
      );

      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          customChannelId,
          'General Reminders',
          description: 'Personal custom reminders and daily check-ins',
          importance: Importance.defaultImportance,
        ),
      );
    }
  }

  @override
  Future<bool> requestPermissions() async {
    final androidPlugin =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      return granted ?? false;
    }

    final iosPlugin =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();

    if (iosPlugin != null) {
      final granted = await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    return true;
  }

  Future<void> _showTaskNotification({
    required int notificationId,
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      taskChannelId,
      'Task Reminders',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      notificationId,
      title,
      body,
      details,
      payload: payload,
    );
  }

  void _armTimerStep({
    required String id,
    required int notificationId,
    required String title,
    required String body,
    required DateTime targetUtc,
    String? payload,
  }) {
    final remaining = targetUtc.difference(EthiopiaClock.nowUtc());
    if (remaining <= Duration.zero) {
      _scheduledTimers.remove(id);
      unawaited(
        _showTaskNotification(
          notificationId: notificationId,
          title: title,
          body: body,
          payload: payload,
        ),
      );
      return;
    }

    // Clamp single Timer delay to 20 days to avoid 32-bit timer overflow.
    const maxStep = Duration(days: 20);
    final stepDelay = remaining > maxStep ? maxStep : remaining;
    _scheduledTimers[id] = Timer(stepDelay, () {
      _scheduledTimers.remove(id);
      if (remaining > maxStep) {
        _armTimerStep(
          id: id,
          notificationId: notificationId,
          title: title,
          body: body,
          targetUtc: targetUtc,
          payload: payload,
        );
      } else {
        unawaited(
          _showTaskNotification(
            notificationId: notificationId,
            title: title,
            body: body,
            payload: payload,
          ),
        );
      }
    });
  }

  @override
  Future<void> scheduleReminder({
    required String id,
    required String title,
    required String body,
    required DateTime scheduledDateUtc,
    String? payload,
  }) async {
    _scheduledTimers.remove(id)?.cancel();
    final notificationId = deterministicNotificationId(id);
    final targetUtc = scheduledDateUtc.toUtc();
    final delay = targetUtc.difference(EthiopiaClock.nowUtc());

    if (delay <= Duration.zero) {
      await _showTaskNotification(
        notificationId: notificationId,
        title: title,
        body: body,
        payload: payload,
      );
      return;
    }

    _armTimerStep(
      id: id,
      notificationId: notificationId,
      title: title,
      body: body,
      targetUtc: targetUtc,
      payload: payload,
    );
  }

  Future<void> scheduleFinanceDueReminder({
    required String id,
    required String title,
    required String body,
    String? payload,
  }) async {
    final int notificationId = deterministicNotificationId(id);
    const androidDetails = AndroidNotificationDetails(
      commitmentChannelId,
      'Financial Commitment Alerts',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    await _notificationsPlugin.show(
      notificationId,
      title,
      body,
      details,
      payload: payload ?? 'finance',
    );
  }

  @override
  Future<void> cancelReminder(String id) async {
    _scheduledTimers.remove(id)?.cancel();
    await _notificationsPlugin.cancel(deterministicNotificationId(id));
  }

  @override
  Future<void> cancelAllReminders() async {
    for (final timer in _scheduledTimers.values) {
      timer.cancel();
    }
    _scheduledTimers.clear();
    await _notificationsPlugin.cancelAll();
  }

  void dispose() {
    for (final timer in _scheduledTimers.values) {
      timer.cancel();
    }
    _scheduledTimers.clear();
  }
}
