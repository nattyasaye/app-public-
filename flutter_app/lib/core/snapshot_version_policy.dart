import 'interfaces/platform_service_interfaces.dart';

/// Resolved, validated snapshot version metadata separated across exchange format,
/// snapshot container format, local SQLite database schema, and Finance rules.
class SnapshotVersionInterpretation {
  final int schemaVersion;
  final int snapshotFormatVersion;
  final int? databaseSchemaVersion;
  final int? financeSchemaVersion;

  const SnapshotVersionInterpretation({
    required this.schemaVersion,
    required this.snapshotFormatVersion,
    this.databaseSchemaVersion,
    this.financeSchemaVersion,
  });

  /// Modern Finance v7+ invariant and strict ETB/category validation rules apply
  /// to format-2 snapshots, legacy snapshots at exchange schemaVersion 7..9,
  /// or legacy snapshots explicitly tagged with financeSchemaVersion >= 7.
  /// Never derived from databaseSchemaVersion alone.
  bool get usesModernFinanceV7Rules =>
      snapshotFormatVersion >=
          SnapshotVersionPolicy.supportedSnapshotFormatVersion ||
      schemaVersion >= SnapshotVersionPolicy.supportedFinanceSchemaVersion ||
      (financeSchemaVersion != null &&
          financeSchemaVersion! >=
              SnapshotVersionPolicy.supportedFinanceSchemaVersion);

  /// Whether legacy SQLite pre-v6 ledger migration applies during restore.
  bool get requiresLegacyPreV6Migration =>
      !usesModernFinanceV7Rules && schemaVersion < 6;

  /// Whether legacy v6 -> v7 hardening rebuild applies during restore.
  bool get requiresLegacyV6Hardening =>
      !usesModernFinanceV7Rules && schemaVersion == 6;
}

/// Shared fail-closed snapshot version interpretation and validation policy
/// used by both DatabasePersistenceCoordinator and EncryptionBackupService.
class SnapshotVersionPolicy {
  SnapshotVersionPolicy._();

  static const int canonicalExchangeSchemaVersion = 5;
  static const int supportedSnapshotFormatVersion = 2;
  static const int legacyOmittedSnapshotFormatVersion = 1;
  static const int minSupportedSnapshotFormatVersion = 1;
  static const int maxSupportedSnapshotFormatVersion = 2;
  static const int supportedFinanceSchemaVersion = 7;
  static const int supportedDatabaseSchemaVersion = 9;
  static const int maxSupportedDatabaseSchemaVersion = 9;
  static const int minSupportedCanonicalSchemaVersion = 4;
  static const int maxSupportedCanonicalSchemaVersion = 9;
  static const int legacyOmittedSnapshotVersion = 5;

  /// Validates and interprets snapshot version metadata fail-closed.
  ///
  /// Rules:
  /// - Legacy format-1 snapshots (`snapshotFormatVersion == 1` or omitted)
  ///   accept `schemaVersion` `4..9` (or omitted -> `5`), optional
  ///   `databaseSchemaVersion` `1..9`, and optional `financeSchemaVersion == 7`.
  /// - Format-2 snapshots (`snapshotFormatVersion == 2`) require explicit
  ///   canonical exchange `schemaVersion == 5`, optional `databaseSchemaVersion == 9`
  ///   (when present), and optional `financeSchemaVersion == 7` (when present).
  /// - When [expectedHeaderVersion] is provided (for `.daywell` envelopes), the
  ///   resolved exchange schemaVersion must match it exactly.
  static SnapshotVersionInterpretation parseAndValidate(
    Map<String, dynamic> rawSnapshot, {
    int? expectedHeaderVersion,
  }) {
    final hasSchemaVersion = rawSnapshot.containsKey('schemaVersion');
    final hasVersion = rawSnapshot.containsKey('version');

    int? parsedSchemaVersion;
    if (hasSchemaVersion) {
      final rawSv = rawSnapshot['schemaVersion'];
      if (rawSv is! int) {
        throw const BackupValidationException(
          BackupFailureKind.invalidSnapshotVersion,
          'Snapshot schemaVersion must be a valid integer.',
        );
      }
      parsedSchemaVersion = rawSv;
    }

    int? parsedVersion;
    if (hasVersion) {
      final rawV = rawSnapshot['version'];
      if (rawV is! int) {
        throw const BackupValidationException(
          BackupFailureKind.invalidSnapshotVersion,
          'Snapshot version must be a valid integer.',
        );
      }
      parsedVersion = rawV;
    }

    if (parsedSchemaVersion != null &&
        parsedVersion != null &&
        parsedSchemaVersion != parsedVersion) {
      throw BackupValidationException(
        BackupFailureKind.invalidSnapshotVersion,
        'Contradictory snapshot version metadata: '
        'schemaVersion=$parsedSchemaVersion does not match version=$parsedVersion.',
      );
    }

    int resolvedSnapshotFormatVersion = legacyOmittedSnapshotFormatVersion;
    if (rawSnapshot.containsKey('snapshotFormatVersion')) {
      final rawFormatVersion = rawSnapshot['snapshotFormatVersion'];
      if (rawFormatVersion is! int) {
        throw const BackupValidationException(
          BackupFailureKind.invalidSnapshotVersion,
          'Snapshot snapshotFormatVersion must be a valid integer.',
        );
      }
      if (rawFormatVersion > maxSupportedSnapshotFormatVersion) {
        throw BackupValidationException(
          BackupFailureKind.unsupportedFutureSchema,
          'Unsupported future snapshotFormatVersion $rawFormatVersion '
          '(maximum supported version is $maxSupportedSnapshotFormatVersion). '
          'Update Daywell before importing this snapshot.',
        );
      }
      if (rawFormatVersion < minSupportedSnapshotFormatVersion) {
        throw BackupValidationException(
          BackupFailureKind.invalidSnapshotVersion,
          'Unsupported snapshotFormatVersion $rawFormatVersion '
          '(supported versions are $minSupportedSnapshotFormatVersion..'
          '$maxSupportedSnapshotFormatVersion).',
        );
      }
      resolvedSnapshotFormatVersion = rawFormatVersion;
    }

    final resolvedVersion =
        parsedSchemaVersion ?? parsedVersion ?? legacyOmittedSnapshotVersion;

    if (resolvedVersion < 0) {
      throw BackupValidationException(
        BackupFailureKind.invalidSnapshotVersion,
        'Invalid snapshot version $resolvedVersion: version cannot be negative.',
      );
    }

    if (resolvedVersion > maxSupportedCanonicalSchemaVersion) {
      throw BackupValidationException(
        BackupFailureKind.unsupportedFutureSchema,
        'Unsupported future snapshot schemaVersion $resolvedVersion '
        '(maximum supported version is $maxSupportedCanonicalSchemaVersion). '
        'Update Daywell before importing this snapshot.',
      );
    }

    if (resolvedVersion < minSupportedCanonicalSchemaVersion) {
      throw BackupValidationException(
        BackupFailureKind.invalidSnapshotVersion,
        'Unsupported canonical snapshot version $resolvedVersion '
        '(supported versions are $minSupportedCanonicalSchemaVersion..'
        '$maxSupportedCanonicalSchemaVersion).',
      );
    }

    if (resolvedSnapshotFormatVersion >= supportedSnapshotFormatVersion) {
      if (!hasSchemaVersion) {
        throw const BackupValidationException(
          BackupFailureKind.invalidSnapshotVersion,
          'Snapshot format v2 requires explicit canonical exchange schemaVersion 5.',
        );
      }
      if (resolvedVersion != canonicalExchangeSchemaVersion) {
        throw BackupValidationException(
          BackupFailureKind.invalidSnapshotVersion,
          'Snapshot format v2 requires canonical exchange schemaVersion '
          '$canonicalExchangeSchemaVersion (got $resolvedVersion).',
        );
      }
    }

    if (expectedHeaderVersion != null &&
        resolvedVersion != expectedHeaderVersion) {
      throw BackupValidationException(
        BackupFailureKind.invalidSnapshotVersion,
        'Backup header schema_version ($expectedHeaderVersion) does not match '
        'effective inner snapshot version ($resolvedVersion).',
      );
    }

    int? resolvedDatabaseSchemaVersion;
    if (rawSnapshot.containsKey('databaseSchemaVersion')) {
      final rawDbVersion = rawSnapshot['databaseSchemaVersion'];
      if (rawDbVersion is! int) {
        throw const BackupValidationException(
          BackupFailureKind.invalidSnapshotVersion,
          'Snapshot databaseSchemaVersion must be a valid integer.',
        );
      }
      if (rawDbVersion < 1) {
        throw BackupValidationException(
          BackupFailureKind.invalidSnapshotVersion,
          'Invalid databaseSchemaVersion $rawDbVersion: must be >= 1.',
        );
      }
      if (rawDbVersion > maxSupportedDatabaseSchemaVersion) {
        throw BackupValidationException(
          BackupFailureKind.unsupportedFutureSchema,
          'Unsupported future databaseSchemaVersion $rawDbVersion '
          '(maximum supported version is $maxSupportedDatabaseSchemaVersion). '
          'Update Daywell before importing this snapshot.',
        );
      }
      if (resolvedSnapshotFormatVersion >= supportedSnapshotFormatVersion &&
          rawDbVersion != supportedDatabaseSchemaVersion) {
        throw BackupValidationException(
          BackupFailureKind.invalidSnapshotVersion,
          'Snapshot format v2 requires databaseSchemaVersion '
          '$supportedDatabaseSchemaVersion when specified (got $rawDbVersion).',
        );
      }
      resolvedDatabaseSchemaVersion = rawDbVersion;
    }

    int? resolvedFinanceSchemaVersion;
    if (rawSnapshot.containsKey('financeSchemaVersion')) {
      final rawFinanceVersion = rawSnapshot['financeSchemaVersion'];
      if (rawFinanceVersion is! int) {
        throw const BackupValidationException(
          BackupFailureKind.invalidSnapshotVersion,
          'Snapshot financeSchemaVersion must be a valid integer.',
        );
      }
      if (rawFinanceVersion < 0) {
        throw BackupValidationException(
          BackupFailureKind.invalidSnapshotVersion,
          'Invalid financeSchemaVersion $rawFinanceVersion: cannot be negative.',
        );
      }
      if (rawFinanceVersion > supportedFinanceSchemaVersion) {
        throw BackupValidationException(
          BackupFailureKind.unsupportedFutureSchema,
          'Unsupported future financeSchemaVersion $rawFinanceVersion '
          '(maximum supported version is $supportedFinanceSchemaVersion). '
          'Update Daywell before importing this snapshot.',
        );
      }
      if (rawFinanceVersion < supportedFinanceSchemaVersion) {
        throw BackupValidationException(
          BackupFailureKind.invalidSnapshotVersion,
          'Unsupported financeSchemaVersion $rawFinanceVersion '
          '(expected $supportedFinanceSchemaVersion).',
        );
      }
      resolvedFinanceSchemaVersion = rawFinanceVersion;
    }

    return SnapshotVersionInterpretation(
      schemaVersion: resolvedVersion,
      snapshotFormatVersion: resolvedSnapshotFormatVersion,
      databaseSchemaVersion: resolvedDatabaseSchemaVersion,
      financeSchemaVersion: resolvedFinanceSchemaVersion,
    );
  }
}
