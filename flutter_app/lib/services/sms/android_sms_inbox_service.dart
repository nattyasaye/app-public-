import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/interfaces/platform_service_interfaces.dart';

/// Read-only Android SMS inbox & WorkManager daily scheduler service backed by
/// [MethodChannel] (`com.example.personalmanagement/sms_inbox`).
///
/// Fails gracefully with `unavailable` / empty results when running on Web,
/// desktop, or widget-test hosts without Android platform channels.
class AndroidSmsInboxService implements ISmsInboxService {
  static const String channelName = 'com.example.personalmanagement/sms_inbox';

  final MethodChannel _channel;
  final bool _hasCustomChannel;
  Future<bool> Function()? _backgroundScanHandler;
  Future<bool> Function(IncomingDeviceSmsEvent event)? _incomingSmsHandler;

  AndroidSmsInboxService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName),
        _hasCustomChannel = channel != null;

  bool get _hasPlatformChannelBinding {
    if (_hasCustomChannel) return true;
    var hasBinding = true;
    assert(() {
      hasBinding = BindingBase.debugBindingType() != null;
      return true;
    }());
    return hasBinding;
  }

  bool get _isAndroidSupported =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      _hasPlatformChannelBinding;

  IncomingDeviceSmsEvent? _parseIncomingEvent(dynamic rawArgs) {
    if (rawArgs is! Map) return null;
    final sender = rawArgs['sender']?.toString() ?? '';
    final body = rawArgs['body']?.toString() ?? '';
    final millisRaw = rawArgs['receivedAtUtcMillis'];
    final millis = millisRaw is int
        ? millisRaw
        : (millisRaw is num ? millisRaw.toInt() : 0);
    final eventReceivedAtUtc = millis > 0
        ? DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true)
        : null;
    final fallbackToInbox =
        rawArgs['fallbackToInbox'] == true || body.trim().isEmpty;
    final message = (!fallbackToInbox &&
            body.trim().isNotEmpty &&
            eventReceivedAtUtc != null)
        ? RawDeviceSmsMessage(
            deviceMessageId: 'broadcast-$millis',
            senderAddress: sender,
            body: body,
            receivedAtUtc: eventReceivedAtUtc,
          )
        : null;
    return IncomingDeviceSmsEvent(
      message: message,
      eventReceivedAtUtc: eventReceivedAtUtc,
      fallbackToInbox: fallbackToInbox || message == null,
    );
  }

  void _ensureChannelHandlerRegistered() {
    if (!_isAndroidSupported) return;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onBackgroundScanRequested') {
        final activeHandler = _backgroundScanHandler;
        if (activeHandler == null) return false;
        return await activeHandler();
      }
      if (call.method == 'onIncomingSmsReceived') {
        final activeHandler = _incomingSmsHandler;
        if (activeHandler == null) return false;
        final event = _parseIncomingEvent(call.arguments) ??
            const IncomingDeviceSmsEvent(fallbackToInbox: true);
        return await activeHandler(event);
      }
      return null;
    });
  }

  void registerBackgroundScanHandler(Future<bool> Function() handler) {
    _backgroundScanHandler = handler;
    _ensureChannelHandlerRegistered();
  }

  void registerIncomingSmsHandler(
    Future<bool> Function(IncomingDeviceSmsEvent event) handler,
  ) {
    _incomingSmsHandler = handler;
    _ensureChannelHandlerRegistered();
  }

  void dispose() {
    _backgroundScanHandler = null;
    _incomingSmsHandler = null;
    if (_isAndroidSupported) {
      _channel.setMethodCallHandler(null);
    }
  }

  Future<IncomingDeviceSmsEvent?> consumePendingIncomingSms() async {
    if (!_isAndroidSupported) return null;
    try {
      final raw = await _channel.invokeMethod<dynamic>(
        'consumePendingIncomingSms',
      );
      return _parseIncomingEvent(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> completeBackgroundScan(bool success) async {
    if (!_isAndroidSupported) return;
    try {
      await _channel.invokeMethod<bool>(
        'completeBackgroundScan',
        <String, dynamic>{'success': success},
      );
    } catch (_) {
      // Safe no-op when channel is absent during teardown.
    }
  }

  Future<void> completeBackgroundIncomingSms(bool success) async {
    if (!_isAndroidSupported) return;
    try {
      await _channel.invokeMethod<bool>(
        'completeBackgroundIncomingSms',
        <String, dynamic>{'success': success},
      );
    } catch (_) {
      // Safe no-op when channel is absent during teardown.
    }
  }

  static DeviceSmsPermissionStatus _parsePermissionStatus(String? raw) {
    switch (raw?.trim()) {
      case 'granted':
        return DeviceSmsPermissionStatus.granted;
      case 'notRequested':
        return DeviceSmsPermissionStatus.notRequested;
      case 'denied':
        return DeviceSmsPermissionStatus.denied;
      case 'permanentlyDenied':
        return DeviceSmsPermissionStatus.permanentlyDenied;
      default:
        return DeviceSmsPermissionStatus.unavailable;
    }
  }

  @override
  Future<DeviceSmsPermissionStatus> getPermissionStatus() async {
    if (!_isAndroidSupported) return DeviceSmsPermissionStatus.unavailable;
    try {
      final status = await _channel.invokeMethod<String>('getPermissionStatus');
      return _parsePermissionStatus(status);
    } on MissingPluginException {
      return DeviceSmsPermissionStatus.unavailable;
    } on PlatformException {
      return DeviceSmsPermissionStatus.unavailable;
    }
  }

  @override
  Future<DeviceSmsPermissionStatus> requestPermission() async {
    if (!_isAndroidSupported) return DeviceSmsPermissionStatus.unavailable;
    try {
      final status = await _channel.invokeMethod<String>('requestPermission');
      return _parsePermissionStatus(status);
    } on MissingPluginException {
      return DeviceSmsPermissionStatus.unavailable;
    } on PlatformException {
      return DeviceSmsPermissionStatus.denied;
    }
  }

  @override
  Future<DeviceSmsPermissionStatus> getReceivePermissionStatus() async {
    if (!_isAndroidSupported) return DeviceSmsPermissionStatus.unavailable;
    try {
      final status =
          await _channel.invokeMethod<String>('getReceivePermissionStatus');
      return _parsePermissionStatus(status);
    } on MissingPluginException {
      return DeviceSmsPermissionStatus.unavailable;
    } on PlatformException {
      return DeviceSmsPermissionStatus.unavailable;
    }
  }

  @override
  Future<DeviceSmsPermissionStatus> requestReceivePermission() async {
    if (!_isAndroidSupported) return DeviceSmsPermissionStatus.unavailable;
    try {
      final status =
          await _channel.invokeMethod<String>('requestReceivePermission');
      return _parsePermissionStatus(status);
    } on MissingPluginException {
      return DeviceSmsPermissionStatus.unavailable;
    } on PlatformException {
      return DeviceSmsPermissionStatus.denied;
    }
  }

  @override
  Future<bool> openAppSettings() async {
    if (!_isAndroidSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('openAppSettings') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<List<RawDeviceSmsMessage>> readInboxMessages({
    DateTime? sinceUtc,
    int limit = 500,
  }) async {
    if (!_isAndroidSupported) return const <RawDeviceSmsMessage>[];
    try {
      final rawList = await _channel.invokeMethod<List<dynamic>>(
        'readInboxMessages',
        <String, dynamic>{
          if (sinceUtc != null)
            'sinceUtcMillis': sinceUtc.toUtc().millisecondsSinceEpoch,
          'limit': limit,
        },
      );
      if (rawList == null) return const <RawDeviceSmsMessage>[];
      final parsed = <RawDeviceSmsMessage>[];
      for (final item in rawList) {
        if (item is! Map) continue;
        final id = item['id']?.toString() ?? '';
        final sender = item['sender']?.toString() ?? '';
        final body = item['body']?.toString() ?? '';
        final millisRaw = item['receivedAtUtcMillis'];
        final millis = millisRaw is int
            ? millisRaw
            : (millisRaw is num ? millisRaw.toInt() : 0);
        if (body.trim().isEmpty || millis <= 0) continue;
        parsed.add(
          RawDeviceSmsMessage(
            deviceMessageId: id,
            senderAddress: sender,
            body: body,
            receivedAtUtc: DateTime.fromMillisecondsSinceEpoch(
              millis,
              isUtc: true,
            ),
          ),
        );
      }
      return List<RawDeviceSmsMessage>.unmodifiable(parsed);
    } on MissingPluginException {
      return const <RawDeviceSmsMessage>[];
    }
  }

  @override
  Future<void> scheduleDailyScan() async {
    if (!_isAndroidSupported) return;
    try {
      await _channel.invokeMethod<bool>('scheduleDailyScan');
    } on MissingPluginException {
      // Safe no-op in tests or unsupported environments.
    }
  }

  @override
  Future<void> cancelDailyScan() async {
    if (!_isAndroidSupported) return;
    try {
      await _channel.invokeMethod<bool>('cancelDailyScan');
    } on MissingPluginException {
      // Safe no-op in tests or unsupported environments.
    }
  }

  @override
  Future<bool> isDailyScanScheduled() async {
    if (!_isAndroidSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isDailyScanScheduled') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> tryAcquireScanLock() async {
    if (!_isAndroidSupported) return true;
    try {
      return await _channel.invokeMethod<bool>('tryAcquireScanLock') ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> releaseScanLock() async {
    if (!_isAndroidSupported) return;
    try {
      await _channel.invokeMethod<bool>('releaseScanLock');
    } on MissingPluginException {
      // Safe no-op.
    }
  }
}
