import 'app_database.dart';
import 'v6_ledger_migrator.dart';
import 'v7_ledger_hardener.dart';

/// Central classification policy governing which `app_settings` keys are
/// serialized inside canonical snapshots and `.daywell` backups vs. exported as
/// typed root fields vs. excluded as internal sentinels or device secrets.
class AppSettingsBackupPolicy {
  /// Keys exported exclusively as typed root fields (`openingBalanceCents`,
  /// `isFinanceSetupCompleted`, `ledgerMigrationReportV7`) rather than in `appSettings`.
  static const Set<String> topLevelManagedKeys = <String>{
    AppDatabase.openingBalanceKey,
    AppDatabase.financeSetupKey,
    V7LedgerHardener.v7ReportKey,
  };

  /// Internal lifecycle sentinels never exported or imported via `appSettings`.
  static const Set<String> internalSentinelKeys = <String>{
    AppDatabase.seedSentinelKey,
    V6LedgerMigrator.v6MigratedSentinelKey,
  };

  /// Exact device-bound or credential keys never exported or imported.
  static const Set<String> exactExcludedDeviceOrSecretKeys = <String>{
    'push_token',
  };

  /// Key prefixes reserved for secrets, credentials, device-local caches,
  /// and transient operational state.
  static const List<String> excludedKeyPrefixes = <String>[
    'secret_',
    'token_',
    'auth_',
    'passphrase_',
    'device_',
    'local_cache_',
    'transient_',
  ];

  /// Documented well-known user-owned setting keys preserved across backup
  /// and cross-platform exchange alongside custom non-excluded user keys.
  static const Set<String> documentedUserOwnedKeys = <String>{
    'calendar_display_mode',
    'default_currency',
    'calendar_preference',
    'daywell_finance_planning_horizon',
    'daywell_user_profile',
  };

  static bool isTopLevelManagedKey(String key) =>
      topLevelManagedKeys.contains(key.trim().toLowerCase());

  static bool isInternalSentinelKey(String key) =>
      internalSentinelKeys.contains(key.trim().toLowerCase());

  static bool isSecretOrDeviceKey(String key) {
    final normalized = key.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (exactExcludedDeviceOrSecretKeys.contains(normalized)) return true;
    for (final prefix in excludedKeyPrefixes) {
      if (normalized.startsWith(prefix)) {
        return true;
      }
    }
    return false;
  }

  static bool isExcludedFromAppSettingsArray(String key) =>
      isTopLevelManagedKey(key) ||
      isInternalSentinelKey(key) ||
      isSecretOrDeviceKey(key);

  static bool isExportableUserSetting(String key) =>
      !isExcludedFromAppSettingsArray(key);

  static String? exclusionReason(String key) {
    if (isTopLevelManagedKey(key)) {
      return 'Managed via top-level typed snapshot field and ignored in appSettings.';
    }
    if (isInternalSentinelKey(key)) {
      return 'Internal database sentinel key is protected from snapshot import.';
    }
    if (isSecretOrDeviceKey(key)) {
      return 'Device-bound, secret, credential, or transient key is excluded.';
    }
    return null;
  }
}
