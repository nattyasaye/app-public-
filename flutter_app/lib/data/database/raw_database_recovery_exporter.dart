import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/date/shared_date.dart';
import '../../core/interfaces/platform_service_interfaces.dart';
import '../../domain/finance/double_entry_engine.dart';

enum DatabaseFailureCategory {
  migrationInvariant,
  unsupportedSchemaVersion,
  sqliteCorruption,
  fileSystemIo,
}

/// Sanitized startup/migration failure descriptor persisted both in memory and
/// atomically on disk (with in-memory fallback when disk writes fail).
class DatabaseStartupFailure {
  final DatabaseFailureCategory category;
  final String userTitle;
  final String message;
  final String userGuidance;
  final int attemptCount;
  final String timestampUtcIso;
  final Map<String, dynamic>? reportJson;
  final DatabaseSidecarInventory? fileInventory;

  const DatabaseStartupFailure({
    required this.category,
    required this.userTitle,
    required this.message,
    required this.userGuidance,
    this.attemptCount = 1,
    required this.timestampUtcIso,
    this.reportJson,
    this.fileInventory,
  });

  bool get isCorruption => category == DatabaseFailureCategory.sqliteCorruption;

  bool get isUnsupportedSchemaVersion =>
      category == DatabaseFailureCategory.unsupportedSchemaVersion;

  bool get canRetryUpgrade => !isCorruption && !isUnsupportedSchemaVersion;

  bool get rawExportRecommended =>
      isCorruption ||
      isUnsupportedSchemaVersion ||
      attemptCount >= 2 ||
      category == DatabaseFailureCategory.migrationInvariant;

  DatabaseStartupFailure copyWith({
    int? attemptCount,
    DatabaseSidecarInventory? fileInventory,
    Map<String, dynamic>? reportJson,
  }) {
    return DatabaseStartupFailure(
      category: category,
      userTitle: userTitle,
      message: message,
      userGuidance: userGuidance,
      attemptCount: attemptCount ?? this.attemptCount,
      timestampUtcIso: timestampUtcIso,
      reportJson: reportJson ?? this.reportJson,
      fileInventory: fileInventory ?? this.fileInventory,
    );
  }

  Map<String, dynamic> toJson() => {
        'category': category.name,
        'userTitle': userTitle,
        'message': message,
        'userGuidance': userGuidance,
        'attemptCount': attemptCount,
        'timestampUtcIso': timestampUtcIso,
        'canRetryUpgrade': canRetryUpgrade,
        'isCorruption': isCorruption,
        'rawExportRecommended': rawExportRecommended,
        if (reportJson != null) 'report': reportJson,
        if (fileInventory != null) 'fileInventory': fileInventory!.toJson(),
      };

  factory DatabaseStartupFailure.fromJson(Map<String, dynamic> json) {
    final categoryName = json['category']?.toString() ?? '';
    final cat = DatabaseFailureCategory.values.firstWhere(
      (c) => c.name == categoryName,
      orElse: () => DatabaseFailureCategory.fileSystemIo,
    );
    return DatabaseStartupFailure(
      category: cat,
      userTitle: json['userTitle']?.toString() ??
          'Unable to initialize local database',
      message: json['message']?.toString() ?? '',
      userGuidance: json['userGuidance']?.toString() ?? '',
      attemptCount: (json['attemptCount'] as int?) ?? 1,
      timestampUtcIso: json['timestampUtcIso']?.toString() ?? '',
      reportJson: json['report'] is Map<String, dynamic>
          ? json['report'] as Map<String, dynamic>
          : null,
      fileInventory: json['fileInventory'] is Map<String, dynamic>
          ? DatabaseSidecarInventory.fromJson(
              json['fileInventory'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

/// Cold inspection inventory of SQLite main database + WAL/SHM sidecars.
class DatabaseSidecarInventory {
  final String databasePath;
  final bool mainDbExists;
  final int mainDbBytes;
  final bool walExists;
  final int walBytes;
  final bool shmExists;
  final int shmBytes;

  const DatabaseSidecarInventory({
    required this.databasePath,
    required this.mainDbExists,
    required this.mainDbBytes,
    required this.walExists,
    required this.walBytes,
    required this.shmExists,
    required this.shmBytes,
  });

  int get totalBytes => mainDbBytes + walBytes + shmBytes;

  Map<String, dynamic> toJson() => {
        'databasePath': databasePath,
        'mainDbExists': mainDbExists,
        'mainDbBytes': mainDbBytes,
        'walExists': walExists,
        'walBytes': walBytes,
        'shmExists': shmExists,
        'shmBytes': shmBytes,
        'totalBytes': totalBytes,
      };

  factory DatabaseSidecarInventory.fromJson(Map<String, dynamic> json) {
    return DatabaseSidecarInventory(
      databasePath: json['databasePath']?.toString() ?? '',
      mainDbExists: (json['mainDbExists'] as bool?) ?? false,
      mainDbBytes: (json['mainDbBytes'] as int?) ?? 0,
      walExists: (json['walExists'] as bool?) ?? false,
      walBytes: (json['walBytes'] as int?) ?? 0,
      shmExists: (json['shmExists'] as bool?) ?? false,
      shmBytes: (json['shmBytes'] as int?) ?? 0,
    );
  }
}

class RawRecoveryBundleManifestEntry {
  final String fileName;
  final int byteLength;
  final String sha256Hex;

  const RawRecoveryBundleManifestEntry({
    required this.fileName,
    required this.byteLength,
    required this.sha256Hex,
  });

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'byteLength': byteLength,
        'sha256Hex': sha256Hex,
      };
}

class RawRecoveryExportResult {
  final String bundleDirectoryPath;
  final String manifestPath;
  final List<RawRecoveryBundleManifestEntry> entries;
  final bool verified;

  const RawRecoveryExportResult({
    required this.bundleDirectoryPath,
    required this.manifestPath,
    required this.entries,
    required this.verified,
  });
}

class QuarantineResult {
  final String quarantineDirectoryPath;
  final Map<String, String> originalToQuarantinedPaths;

  const QuarantineResult({
    required this.quarantineDirectoryPath,
    required this.originalToQuarantinedPaths,
  });

  List<String> get movedFiles => originalToQuarantinedPaths.values.toList();
}

/// Pure `dart:io` + SHA-256 cold recovery exporter and quarantine coordinator.
///
/// Strictly executes ZERO Drift/SQLite queries so failed or corrupt database
/// handles are never reopened during inspection, raw backup export, or
/// quarantine cleanup.
class RawDatabaseRecoveryExporter {
  static const String defaultDbFileName = 'personal_management.sqlite';
  static const String diagnosticFileName = 'migration_last_failure.json';
  static const String manifestFileName = 'manifest.json';

  final Future<Directory> Function() _documentsDirProvider;
  final Future<Directory> Function() _supportDirProvider;
  final String dbFileName;

  RawDatabaseRecoveryExporter({
    Future<Directory> Function()? documentsDirProvider,
    Future<Directory> Function()? supportDirProvider,
    this.dbFileName = defaultDbFileName,
  })  : _documentsDirProvider =
            documentsDirProvider ?? getApplicationDocumentsDirectory,
        _supportDirProvider =
            supportDirProvider ?? getApplicationSupportDirectory;

  Future<File> resolveDatabaseFile() async {
    final dir = await _documentsDirProvider();
    return File(p.join(dir.path, dbFileName));
  }

  Future<File> resolveFailureDiagnosticFile() async {
    final dir = await _supportDirProvider();
    return File(p.join(dir.path, diagnosticFileName));
  }

  List<File> _candidateDatabaseFiles(String mainDbPath) => <File>[
        File(mainDbPath),
        File('$mainDbPath-wal'),
        File('$mainDbPath-shm'),
      ];

  /// Classifies database/startup failures cleanly for recovery UX.
  static DatabaseStartupFailure classifyStartupError(
    Object error, {
    int previousAttemptCount = 0,
    DatabaseSidecarInventory? fileInventory,
  }) {
    final attemptCount = previousAttemptCount + 1;
    final nowIso = EthiopiaClock.toUtcIsoString(EthiopiaClock.nowUtc());

    if (error is UnsupportedDatabaseVersionException) {
      return DatabaseStartupFailure(
        category: DatabaseFailureCategory.unsupportedSchemaVersion,
        userTitle: 'Newer database version unsupported',
        message: error.message,
        userGuidance: 'This local database uses schema v${error.fromVersion}, '
            'which is newer than this Daywell build supports (max schema '
            'v${error.toVersion}). Update Daywell before opening it, or '
            'export a raw database backup first.',
        attemptCount: attemptCount,
        timestampUtcIso: nowIso,
        fileInventory: fileInventory,
      );
    }

    if (error is LedgerMigrationException) {
      return DatabaseStartupFailure(
        category: DatabaseFailureCategory.migrationInvariant,
        userTitle: 'Unable to initialize local database',
        message: error.message,
        userGuidance: attemptCount >= 2
            ? 'Migration invariant check failed multiple times. Export a '
                'raw database backup before retrying or restoring.'
            : 'The ledger upgrade rolled back safely without modifying '
                'your existing database. You can export a raw backup or retry.',
        attemptCount: attemptCount,
        timestampUtcIso: nowIso,
        reportJson: error.report,
        fileInventory: fileInventory,
      );
    }

    if (error is DatabaseCorruptionException) {
      return DatabaseStartupFailure(
        category: DatabaseFailureCategory.sqliteCorruption,
        userTitle: 'Local database integrity error',
        message: error.message,
        userGuidance: 'The local SQLite database file appears damaged. '
            'Export a cold raw backup first, then restore from your '
            'encrypted .daywell backup.',
        attemptCount: attemptCount,
        timestampUtcIso: nowIso,
        fileInventory: fileInventory,
      );
    }

    final lower = error.toString().toLowerCase();
    final isSqliteCorrupt = lower.contains('sqlite_corrupt') ||
        lower.contains('sqlite_notadb') ||
        lower.contains('disk image is malformed') ||
        lower.contains('file is not a database') ||
        lower.contains('quick_check') ||
        lower.contains('database corruption');
    if (isSqliteCorrupt) {
      return DatabaseStartupFailure(
        category: DatabaseFailureCategory.sqliteCorruption,
        userTitle: 'Local database integrity error',
        message: error.toString(),
        userGuidance: 'SQLite reported file corruption. Blind retries are '
            'disabled to prevent further damage. Export a raw backup, then '
            'restore an encrypted .daywell backup.',
        attemptCount: attemptCount,
        timestampUtcIso: nowIso,
        fileInventory: fileInventory,
      );
    }

    final isInvariant = lower.contains('foreign key') ||
        lower.contains('invariant') ||
        lower.contains('migration') ||
        lower.contains('unbalanced');
    if (isInvariant) {
      return DatabaseStartupFailure(
        category: DatabaseFailureCategory.migrationInvariant,
        userTitle: 'Unable to initialize local database',
        message: error.toString(),
        userGuidance: 'Schema upgrade rolled back safely. Export a raw backup '
            'or retry initialization.',
        attemptCount: attemptCount,
        timestampUtcIso: nowIso,
        fileInventory: fileInventory,
      );
    }

    return DatabaseStartupFailure(
      category: DatabaseFailureCategory.fileSystemIo,
      userTitle: 'Unable to initialize local database',
      message: error.toString(),
      userGuidance: 'Storage I/O or lock error occurred while opening the '
          'database. Ensure storage space is available and retry.',
      attemptCount: attemptCount,
      timestampUtcIso: nowIso,
      fileInventory: fileInventory,
    );
  }

  /// Inspects `.sqlite`, `-wal`, and `-shm` sizes purely via `dart:io`.
  /// Caller MUST have closed any active database handle before calling.
  Future<DatabaseSidecarInventory> inspectDatabaseFilesCold() async {
    final mainFile = await resolveDatabaseFile();
    final walFile = File('${mainFile.path}-wal');
    final shmFile = File('${mainFile.path}-shm');

    final mainExists = await mainFile.exists();
    final walExists = await walFile.exists();
    final shmExists = await shmFile.exists();

    return DatabaseSidecarInventory(
      databasePath: mainFile.path,
      mainDbExists: mainExists,
      mainDbBytes: mainExists ? await mainFile.length() : 0,
      walExists: walExists,
      walBytes: walExists ? await walFile.length() : 0,
      shmExists: shmExists,
      shmBytes: shmExists ? await shmFile.length() : 0,
    );
  }

  /// Atomically writes `migration_last_failure.json` (`.tmp -> rename`).
  /// Returns `false` if disk-full or I/O failure occurs so callers can keep
  /// the failure payload intact in memory.
  Future<bool> persistFailureDiagnosticAtomic(
    DatabaseStartupFailure failure,
  ) async {
    try {
      final target = await resolveFailureDiagnosticFile();
      await target.parent.create(recursive: true);
      final tmp = File('${target.path}.tmp');
      final encoded = jsonEncode(failure.toJson());
      await tmp.writeAsString(encoded, flush: true);
      if (await target.exists()) {
        await target.delete();
      }
      await tmp.rename(target.path);
      return true;
    } on FileSystemException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<DatabaseStartupFailure?> readFailureDiagnostic() async {
    try {
      final file = await resolveFailureDiagnosticFile();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return DatabaseStartupFailure.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearFailureDiagnostic() async {
    try {
      final file = await resolveFailureDiagnosticFile();
      if (await file.exists()) {
        await file.delete();
      }
      final tmp = File('${file.path}.tmp');
      if (await tmp.exists()) {
        await tmp.delete();
      }
    } catch (_) {}
  }

  Future<String> computeFileSha256(File file) async {
    final sha256 = Sha256();
    final bytes = await file.readAsBytes();
    final digest = await sha256.hash(bytes);
    return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Cold-copies `.sqlite`, `-wal`, `-shm`, and failure diagnostics to
  /// [destinationParentDir] alongside a verified SHA-256 `manifest.json`.
  ///
  /// Throws on verification failure while keeping live files and diagnostics
  /// completely untouched.
  Future<RawRecoveryExportResult> exportColdBundle({
    required Directory destinationParentDir,
    DatabaseStartupFailure? failure,
    String? bundleFolderName,
  }) async {
    final mainFile = await resolveDatabaseFile();
    final candidates = _candidateDatabaseFiles(mainFile.path);
    final existingDbFiles = <File>[];
    for (final f in candidates) {
      if (await f.exists()) {
        existingDbFiles.add(f);
      }
    }

    final diagFile = await resolveFailureDiagnosticFile();
    final diagOnDisk = await diagFile.exists();
    if (existingDbFiles.isEmpty && !diagOnDisk && failure == null) {
      throw StateError(
        'No database or diagnostic files found to export at ${mainFile.path}.',
      );
    }

    final timestampTag = EthiopiaClock.nowUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final folderName = bundleFolderName ?? 'daywell_raw_recovery_$timestampTag';
    final destDir = Directory(p.join(destinationParentDir.path, folderName));
    await destDir.create(recursive: true);

    final manifestEntries = <RawRecoveryBundleManifestEntry>[];

    // 1. Pre-compute source hashes/sizes and raw-copy each existing DB/sidecar.
    for (final src in existingDbFiles) {
      final fileName = p.basename(src.path);
      final expectedBytes = await src.length();
      final expectedSha = await computeFileSha256(src);
      final destFile = File(p.join(destDir.path, fileName));
      await src.copy(destFile.path);
      manifestEntries.add(
        RawRecoveryBundleManifestEntry(
          fileName: fileName,
          byteLength: expectedBytes,
          sha256Hex: expectedSha,
        ),
      );
    }

    // 2. Include diagnostic report (disk file preferred, memory fallback).
    if (diagOnDisk || failure != null) {
      final destDiag = File(p.join(destDir.path, diagnosticFileName));
      if (diagOnDisk) {
        await diagFile.copy(destDiag.path);
      } else {
        await destDiag.writeAsString(
          jsonEncode(failure!.toJson()),
          flush: true,
        );
      }
      final diagBytes = await destDiag.length();
      final diagSha = await computeFileSha256(destDiag);
      manifestEntries.add(
        RawRecoveryBundleManifestEntry(
          fileName: diagnosticFileName,
          byteLength: diagBytes,
          sha256Hex: diagSha,
        ),
      );
    }

    // 3. Write manifest.json.
    final manifestFile = File(p.join(destDir.path, manifestFileName));
    final manifestPayload = {
      'exportedAtUtc': EthiopiaClock.toUtcIsoString(EthiopiaClock.nowUtc()),
      'dbFileName': dbFileName,
      'entries': manifestEntries.map((e) => e.toJson()).toList(growable: false),
    };
    await manifestFile.writeAsString(jsonEncode(manifestPayload), flush: true);

    // 4. Verify every written bundle file exists with matching size & SHA-256.
    if (!await manifestFile.exists()) {
      throw StateError(
          'Recovery export verification failed: manifest missing.');
    }
    for (final entry in manifestEntries) {
      final copied = File(p.join(destDir.path, entry.fileName));
      if (!await copied.exists()) {
        throw StateError(
          'Recovery export verification failed: missing ${entry.fileName}.',
        );
      }
      final actualLen = await copied.length();
      if (actualLen != entry.byteLength) {
        throw StateError(
          'Recovery export size mismatch for ${entry.fileName}: '
          'expected ${entry.byteLength}, got $actualLen.',
        );
      }
      final actualSha = await computeFileSha256(copied);
      if (actualSha != entry.sha256Hex) {
        throw StateError(
          'Recovery export SHA-256 mismatch for ${entry.fileName}.',
        );
      }
    }

    return RawRecoveryExportResult(
      bundleDirectoryPath: destDir.path,
      manifestPath: manifestFile.path,
      entries:
          List<RawRecoveryBundleManifestEntry>.unmodifiable(manifestEntries),
      verified: true,
    );
  }

  /// Moves damaged `.sqlite`, `-wal`, and `-shm` into `recovery_quarantine/`.
  /// Caller MUST have closed any active database handle before calling.
  Future<QuarantineResult> quarantineLiveDatabaseFiles({
    String? quarantineLabel,
  }) async {
    final mainFile = await resolveDatabaseFile();
    final label = quarantineLabel ??
        EthiopiaClock.nowUtc()
            .toIso8601String()
            .replaceAll(':', '-')
            .replaceAll('.', '-');
    final quarantineDir = Directory(
      p.join(mainFile.parent.path, 'recovery_quarantine', label),
    );
    await quarantineDir.create(recursive: true);

    final movedMap = <String, String>{};
    for (final src in _candidateDatabaseFiles(mainFile.path)) {
      if (!await src.exists()) continue;
      final destPath = p.join(quarantineDir.path, p.basename(src.path));
      await _moveFileSafely(src, File(destPath));
      movedMap[src.path] = destPath;
    }

    return QuarantineResult(
      quarantineDirectoryPath: quarantineDir.path,
      originalToQuarantinedPaths: Map<String, String>.unmodifiable(movedMap),
    );
  }

  /// Restores previously quarantined files if a backup restore fails mid-way.
  ///
  /// Copies quarantined files back to their original paths and leaves the
  /// quarantine directory intact until the caller explicitly calls
  /// [deleteQuarantine].
  Future<void> restoreFromQuarantine(QuarantineResult quarantine) async {
    final mainFile = await resolveDatabaseFile();
    final liveCandidates = <String>{
      for (final f in _candidateDatabaseFiles(mainFile.path)) f.path,
      ...quarantine.originalToQuarantinedPaths.keys,
    };
    for (final path in liveCandidates) {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
    }
    for (final entry in quarantine.originalToQuarantinedPaths.entries) {
      final quarantined = File(entry.value);
      if (await quarantined.exists()) {
        final dest = File(entry.key);
        await dest.parent.create(recursive: true);
        await quarantined.copy(dest.path);
      }
    }
  }

  Future<void> deleteQuarantine(QuarantineResult quarantine) async {
    final qDir = Directory(quarantine.quarantineDirectoryPath);
    if (await qDir.exists()) {
      await qDir.delete(recursive: true);
    }
    final parent = qDir.parent;
    try {
      if (p.basename(parent.path) == 'recovery_quarantine' &&
          await parent.exists() &&
          await parent.list().isEmpty) {
        await parent.delete();
      }
    } on FileSystemException {
      // Best-effort cleanup of the empty quarantine container directory.
    }
  }

  Future<void> _moveFileSafely(File src, File dest) async {
    await dest.parent.create(recursive: true);
    try {
      await src.rename(dest.path);
    } on FileSystemException {
      await src.copy(dest.path);
      await src.delete();
    }
  }
}
