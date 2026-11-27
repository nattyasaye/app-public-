import 'dart:async';

/// Abstract contract for local device notifications across Android and iOS.
///
/// Android: Implemented via [AndroidNotificationChannel] with exact alarm permissions
/// iOS: Implemented via [UNUserNotificationCenter]
abstract class INotificationService {
  Future<void> initialize();
  Future<bool> requestPermissions();
  Future<void> scheduleReminder({
    required String id,
    required String title,
    required String body,
    required DateTime scheduledDateUtc,
    String? payload,
  });
  Future<void> cancelReminder(String id);
  Future<void> cancelAllReminders();
}

/// Abstract contract for secure credential and key storage.
///
/// Android: Hardware-backed Android Keystore
/// iOS: Apple Keychain Services
abstract class ISecureStorageService {
  Future<void> writeSecret(String key, String value);
  Future<String?> readSecret(String key);
  Future<void> deleteSecret(String key);
  Future<bool> hasKey(String key);
}

/// Abstract contract for encrypted database backup and restoration.
abstract class IBackupService {
  /// Generates an encrypted snapshot archive of the local SQLite database.
  Future<String> createEncryptedBackup({
    required String passphrase,
    required String destinationDirectoryPath,
  });

  /// Restores database state from an encrypted archive using the user's passphrase.
  Future<bool> restoreFromEncryptedBackup({
    required String archiveFilePath,
    required String passphrase,
  });

  /// Verifies integrity and header metadata of an archive without applying it.
  Future<BackupMetadata> inspectBackupArchive(String archiveFilePath);
}

/// Metadata header stored inside a backup archive.
class BackupMetadata {
  final int schemaVersion;
  final String appVersion;
  final DateTime createdAtUtc;
  final String saltHex;
  final String ivHex;
  final String sha256Checksum;

  const BackupMetadata({
    required this.schemaVersion,
    required this.appVersion,
    required this.createdAtUtc,
    required this.saltHex,
    required this.ivHex,
    required this.sha256Checksum,
  });
}

/// Abstract contract for syncing state with Home-Screen widgets.
///
/// Android: AppWidgetProvider / Glance
/// iOS: WidgetKit (TimelineProvider)
abstract class IWidgetSyncService {
  Future<void> updateQuickCaptureWidget();
  Future<void> updateTodayTasksWidget(
      {required int taskCount, required List<String> taskTitles});
}

/// Structured classification for snapshot import and encrypted backup restore failures.
enum BackupFailureKind {
  authenticationFailure,
  invalidBackupHeader,
  unsupportedFormatVersion,
  unsupportedKdf,
  unsupportedFutureSchema,
  invalidSnapshotVersion,
  invalidPayload,
  integrityFailure,
  databaseImportFailure,
}

/// Typed exception carrying a safe, user-presentable validation or restore error.
class BackupValidationException implements Exception {
  final BackupFailureKind kind;
  final String message;

  const BackupValidationException(this.kind, this.message);

  @override
  String toString() => 'BackupValidationException(${kind.name}): $message';
}

/// Severity level for structured snapshot import diagnostics.
enum SnapshotDiagnosticSeverity {
  info,
  warning,
}

/// Structured non-fatal warning or informational note produced during snapshot
/// pre-validation, repair, or import.
class SnapshotImportDiagnostic {
  final String code;
  final String message;
  final String table;
  final String? recordId;
  final String? field;
  final SnapshotDiagnosticSeverity severity;

  const SnapshotImportDiagnostic({
    required this.code,
    required this.message,
    required this.table,
    this.recordId,
    this.field,
    this.severity = SnapshotDiagnosticSeverity.warning,
  });

  String toWarningString() {
    final hasRecordId = recordId != null && recordId!.isNotEmpty;
    final target = hasRecordId ? '$table[$recordId]' : table;
    final hasField = field != null && field!.isNotEmpty;
    final fieldPart = hasField ? '.$field' : '';
    return '$code ($target$fieldPart): $message';
  }
}

/// Structured summary of an executed snapshot import or restore operation.
class SnapshotImportReport {
  final List<String> warnings;
  final List<SnapshotImportDiagnostic> diagnostics;
  final Map<String, int> restoredRecordCounts;

  const SnapshotImportReport({
    this.warnings = const <String>[],
    this.diagnostics = const <SnapshotImportDiagnostic>[],
    this.restoredRecordCounts = const <String, int>{},
  });
}

/// Non-throwing structured result for snapshot import and backup restore operations.
class BackupRestoreResult {
  final bool success;
  final BackupFailureKind? failureKind;
  final String? message;
  final List<String> warnings;
  final List<SnapshotImportDiagnostic> diagnostics;

  const BackupRestoreResult.success([
    this.message,
    this.warnings = const <String>[],
    this.diagnostics = const <SnapshotImportDiagnostic>[],
  ])  : success = true,
        failureKind = null;

  const BackupRestoreResult.failure(
    BackupFailureKind this.failureKind,
    String this.message, [
    this.warnings = const <String>[],
    this.diagnostics = const <SnapshotImportDiagnostic>[],
  ]) : success = false;
}

/// Typed exception thrown when opening a local SQLite database created by a
/// newer schema version than this application build supports (`from > to`).
class UnsupportedDatabaseVersionException implements Exception {
  final int fromVersion;
  final int toVersion;
  final String message;

  UnsupportedDatabaseVersionException({
    required this.fromVersion,
    required this.toVersion,
    String? message,
  }) : message = message ??
            'Local database schema version v$fromVersion is newer than this '
                'Daywell version supports (max schema v$toVersion). Update '
                'Daywell to open this database safely.';

  @override
  String toString() => 'UnsupportedDatabaseVersionException: $message';
}

/// Runtime permission state for read-only local Android SMS inbox scanning.
enum DeviceSmsPermissionStatus {
  granted,
  notRequested,
  denied,
  permanentlyDenied,
  unavailable,
}

/// Raw read-only SMS row read from Android's `Telephony.Sms.Inbox` provider.
class RawDeviceSmsMessage {
  final String deviceMessageId;
  final String senderAddress;
  final String body;
  final DateTime receivedAtUtc;

  const RawDeviceSmsMessage({
    required this.deviceMessageId,
    required this.senderAddress,
    required this.body,
    required this.receivedAtUtc,
  });
}

/// Event payload delivered when Android's `SMS_RECEIVED` broadcast triggers
/// immediate one-time Finance SMS detection.
class IncomingDeviceSmsEvent {
  final RawDeviceSmsMessage? message;
  final DateTime? eventReceivedAtUtc;
  final bool fallbackToInbox;

  const IncomingDeviceSmsEvent({
    this.message,
    this.eventReceivedAtUtc,
    this.fallbackToInbox = false,
  });
}

/// Abstract contract for read-only local SMS inbox access, incoming `SMS_RECEIVED`
/// permission management, and daily background scanning (Android WorkManager).
abstract class ISmsInboxService {
  Future<DeviceSmsPermissionStatus> getPermissionStatus();
  Future<DeviceSmsPermissionStatus> requestPermission();
  Future<DeviceSmsPermissionStatus> getReceivePermissionStatus();
  Future<DeviceSmsPermissionStatus> requestReceivePermission();
  Future<bool> openAppSettings();
  Future<List<RawDeviceSmsMessage>> readInboxMessages({
    DateTime? sinceUtc,
    int limit = 500,
  });
  Future<void> scheduleDailyScan();
  Future<void> cancelDailyScan();
  Future<bool> isDailyScanScheduled();
  Future<bool> tryAcquireScanLock();
  Future<void> releaseScanLock();
}
