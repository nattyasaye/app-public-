import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:personal_management_app/core/interfaces/platform_service_interfaces.dart';
import 'package:personal_management_app/core/shared_foundation_bridge.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/database_persistence_coordinator.dart';
import 'package:personal_management_app/data/database/raw_database_recovery_exporter.dart';
import 'package:personal_management_app/data/repositories/finance_repository.dart';
import 'package:personal_management_app/services/backup/encryption_backup_service.dart';
import 'package:personal_management_app/ui/app_state.dart';
import 'package:personal_management_app/ui/screens/backup_view.dart';

import 'support/sqlite_test_helper.dart';

class _NoOpNotificationService implements INotificationService {
  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<void> scheduleReminder({
    required String id,
    required String title,
    required String body,
    required DateTime scheduledDateUtc,
    String? payload,
  }) async {}

  @override
  Future<void> cancelReminder(String id) async {}

  @override
  Future<void> cancelAllReminders() async {}
}

Map<String, dynamic> _minimalValidSnapshot({
  Object? schemaVersion = 7,
  bool includeSchemaVersion = true,
  Object? version,
  bool includeVersion = false,
}) {
  return <String, dynamic>{
    if (includeSchemaVersion) 'schemaVersion': schemaVersion,
    if (includeVersion) 'version': version,
    'isFinanceSetupCompleted': true,
    'openingBalanceCents': 100000,
    'accounts': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'acc-snap-1',
        'name': 'Snapshot Cash',
        'type': 'asset',
        'subType': 'cash',
        'isSystem': false,
        'currencyCode': 'ETB',
        'isArchived': false,
        'openingBalanceCents': 100000,
        'openingBalanceDate': '2026-11-01',
        'createdAt': '2026-11-01T00:00:00.000Z',
      },
    ],
    'categories': <Map<String, dynamic>>[],
    'transactions': <Map<String, dynamic>>[],
    'tasks': <Map<String, dynamic>>[],
    'notes': <Map<String, dynamic>>[],
  };
}

Future<Map<String, Object?>> _captureDbSnapshotForAssertion(
  AppDatabase db,
) async {
  final accounts = await db.select(db.accountsTable).get();
  final reminders = await db.select(db.reminders).get();
  final settings = await db.select(db.appSettings).get();
  final tasks = await db.select(db.tasks).get();
  final notes = await db.select(db.notes).get();
  final accountIds =
      accounts.map((a) => '${a.id}:${a.openingBalanceCents}').toList();
  accountIds.sort();
  final reminderIds =
      reminders.map((r) => '${r.id}:${r.targetId}:${r.isActive}').toList();
  reminderIds.sort();
  final settingsPairs = settings.map((s) => '${s.key}=${s.value}').toList();
  settingsPairs.sort();
  final taskIds = tasks.map((t) => '${t.id}:${t.title}').toList();
  taskIds.sort();
  final noteIds = notes.map((n) => '${n.id}:${n.title}').toList();
  noteIds.sort();
  return <String, Object?>{
    'accountIds': accountIds,
    'reminderIds': reminderIds,
    'settingsPairs': settingsPairs,
    'taskIds': taskIds,
    'noteIds': noteIds,
  };
}

Future<void> _seedProtectedData(AppDatabase db) async {
  final repo = DriftFinanceRepository(db);
  await repo.completeFinanceSetup([
    AccountModel(
      id: 'acc-protected',
      name: 'Protected CBE',
      type: AccountType.asset,
      subType: AccountSubType.bank,
      openingBalanceCents: 450000,
      openingBalanceDate: '2026-11-01',
    ),
  ]);
  final now = DateTime.utc(2026, 11, 10, 9, 0);
  await db.into(db.tasks).insert(
        TasksCompanion.insert(
          id: 'task-protected',
          title: 'Protected Task',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db.into(db.notes).insert(
        NotesCompanion.insert(
          id: 'note-protected',
          title: 'Protected Note',
          content: 'Must survive rejected imports',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db.into(db.reminders).insert(
        RemindersCompanion.insert(
          id: 'rem-protected',
          targetId: 'task-protected',
          targetType: 'task',
          triggerTimeUtc: DateTime.utc(2026, 11, 20, 8, 0),
          createdAt: now,
        ),
      );
  await db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: 'calendar_preference',
          value: 'ethiopian',
          updatedAt: now,
        ),
      );
  await db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: 'default_currency',
          value: 'ETB',
          updatedAt: now,
        ),
      );
}

Future<String> _encryptRawBytesEnvelopeWithHeaderOverrides({
  required List<int> plaintextBytes,
  required String passphrase,
  int headerSchemaVersion = 7,
  String format = 'personal_mgmt_encrypted_backup',
  int formatVersion = 1,
  String kdf = 'PBKDF2-HMAC-SHA256',
  int iterations = 100000,
}) async {
  final cipher = AesGcm.with256bits();
  final pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 100000,
    bits: 256,
  );
  final salt = SecretKeyData.random(length: 16).bytes;
  final nonce = cipher.newNonce();
  final key = await pbkdf2.deriveKey(
    secretKey: SecretKey(utf8.encode(passphrase)),
    nonce: salt,
  );
  final box = await cipher.encrypt(
    plaintextBytes,
    secretKey: key,
    nonce: nonce,
  );
  final digest = await Sha256().hash(plaintextBytes);
  final checksumHex =
      digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return jsonEncode({
    'header': {
      'format': format,
      'format_version': formatVersion,
      'app_version': '1.0.2+3',
      'schema_version': headerSchemaVersion,
      'created_at_utc': '2026-11-10T08:00:00.000Z',
      'kdf': kdf,
      'iterations': iterations,
      'salt_base64': base64Encode(salt),
      'nonce_base64': base64Encode(nonce),
      'mac_base64': base64Encode(box.mac.bytes),
      'checksum_sha256': checksumHex,
    },
    'ciphertext_base64': base64Encode(box.cipherText),
  });
}

Future<String> _encryptRawEnvelopeWithHeaderOverrides({
  required String plaintext,
  required String passphrase,
  int headerSchemaVersion = 7,
  String format = 'personal_mgmt_encrypted_backup',
  int formatVersion = 1,
  String kdf = 'PBKDF2-HMAC-SHA256',
  int iterations = 100000,
}) {
  return _encryptRawBytesEnvelopeWithHeaderOverrides(
    plaintextBytes: utf8.encode(plaintext),
    passphrase: passphrase,
    headerSchemaVersion: headerSchemaVersion,
    format: format,
    formatVersion: formatVersion,
    kdf: kdf,
    iterations: iterations,
  );
}

Matcher _throwsValidation(BackupFailureKind kind, [String? message]) {
  final matcher =
      isA<BackupValidationException>().having((e) => e.kind, 'kind', kind);
  if (message == null) return throwsA(matcher);
  return throwsA(matcher.having((e) => e.message, 'message', message));
}

void main() {
  configureSqliteForHostTests();

  group('Stage 3.4.2 Flutter Fail-Closed Snapshot & Backup Validation', () {
    test(
        'Accepts canonical snapshots v4..v8 and omitted-version legacy default 5',
        () async {
      for (final version in [4, 5, 6, 7, 8]) {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        final coordinator = DatabasePersistenceCoordinator(db);
        final snap = _minimalValidSnapshot(schemaVersion: version);
        await coordinator.importSnapshot(snap);
        final accounts = await db.select(db.accountsTable).get();
        expect(accounts.any((a) => a.id == 'acc-snap-1'), isTrue);
        await db.close();
      }

      // Omitted schemaVersion & version falls back to legacy default 5
      final db = AppDatabase(NativeDatabase.memory());
      await db.ensureInitialized();
      final coordinator = DatabasePersistenceCoordinator(db);
      final omitted = _minimalValidSnapshot(includeSchemaVersion: false);
      expect(
        DatabasePersistenceCoordinator.validateCanonicalSnapshot(omitted),
        5,
      );
      await coordinator.importSnapshot(omitted);
      final accounts = await db.select(db.accountsTable).get();
      expect(accounts.any((a) => a.id == 'acc-snap-1'), isTrue);
      await db.close();
    });

    test(
        'Rejects 0..3, 9, 99, negative, non-int, null, contradictory, and malformed snapshots with zero data/reminder/settings loss',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.ensureInitialized();
      await _seedProtectedData(db);
      final baseline = await _captureDbSnapshotForAssertion(db);
      final coordinator = DatabasePersistenceCoordinator(db);

      final rejectedCases = <({
        String name,
        dynamic payload,
        BackupFailureKind kind,
      })>[
        (
          name: 'schemaVersion 0',
          payload: _minimalValidSnapshot(schemaVersion: 0),
          kind: BackupFailureKind.invalidSnapshotVersion,
        ),
        (
          name: 'schemaVersion 2',
          payload: _minimalValidSnapshot(schemaVersion: 2),
          kind: BackupFailureKind.invalidSnapshotVersion,
        ),
        (
          name: 'schemaVersion 3',
          payload: _minimalValidSnapshot(schemaVersion: 3),
          kind: BackupFailureKind.invalidSnapshotVersion,
        ),
        (
          name: 'future schemaVersion 9',
          payload: _minimalValidSnapshot(schemaVersion: 9),
          kind: BackupFailureKind.unsupportedFutureSchema,
        ),
        (
          name: 'future schemaVersion 99',
          payload: _minimalValidSnapshot(schemaVersion: 99),
          kind: BackupFailureKind.unsupportedFutureSchema,
        ),
        (
          name: 'negative schemaVersion -1',
          payload: _minimalValidSnapshot(schemaVersion: -1),
          kind: BackupFailureKind.invalidSnapshotVersion,
        ),
        (
          name: 'string schemaVersion "7"',
          payload: _minimalValidSnapshot(schemaVersion: '7'),
          kind: BackupFailureKind.invalidSnapshotVersion,
        ),
        (
          name: 'double schemaVersion 7.5',
          payload: _minimalValidSnapshot(schemaVersion: 7.5),
          kind: BackupFailureKind.invalidSnapshotVersion,
        ),
        (
          name: 'boolean schemaVersion true',
          payload: _minimalValidSnapshot(schemaVersion: true),
          kind: BackupFailureKind.invalidSnapshotVersion,
        ),
        (
          name: 'explicit null schemaVersion',
          payload: _minimalValidSnapshot(schemaVersion: null),
          kind: BackupFailureKind.invalidSnapshotVersion,
        ),
        (
          name: 'contradictory schemaVersion 5 and version 7',
          payload: _minimalValidSnapshot(
            schemaVersion: 5,
            version: 7,
            includeVersion: true,
          ),
          kind: BackupFailureKind.invalidSnapshotVersion,
        ),
        (
          name: 'malformed tasks list field',
          payload: {
            ..._minimalValidSnapshot(schemaVersion: 7),
            'tasks': 'not-a-list',
          },
          kind: BackupFailureKind.invalidPayload,
        ),
        (
          name: 'malformed account element',
          payload: {
            ..._minimalValidSnapshot(schemaVersion: 7),
            'accounts': ['not-an-object'],
          },
          kind: BackupFailureKind.invalidPayload,
        ),
      ];

      for (final tc in rejectedCases) {
        await expectLater(
          () async => coordinator.importSnapshot(tc.payload),
          throwsA(
            isA<BackupValidationException>()
                .having((e) => e.kind, 'kind', tc.kind),
          ),
          reason: '${tc.name} must throw BackupValidationException(${tc.kind})',
        );
        expect(
          await _captureDbSnapshotForAssertion(db),
          equals(baseline),
          reason:
              '${tc.name} must preserve all live tables, Reminders, and AppSettings',
        );
      }

      await db.close();
    });

    test(
        'EncryptionBackupService validates format_version, KDF, iterations, headers, checksums, and inner snapshot bounds fail-closed',
        () async {
      final service = EncryptionBackupService();
      final validInner = jsonEncode(_minimalValidSnapshot(schemaVersion: 7));
      final validEnvelope = await service.encryptDatabasePayload(
        rawDatabaseJson: validInner,
        passphrase: 'Passphrase#Stage342',
        schemaVersion: 7,
      );

      final decrypted = await service.decryptDatabasePayload(
        encryptedEnvelopeJson: validEnvelope,
        passphrase: 'Passphrase#Stage342',
      );
      expect(decrypted, validInner);

      final parsedValid = jsonDecode(validEnvelope) as Map<String, dynamic>;

      final invalidEnvelopeCases = <({
        String name,
        Map<String, dynamic> Function(Map<String, dynamic>) mutate,
        BackupFailureKind kind,
      })>[
        (
          name: 'wrong format identifier',
          mutate: (m) {
            (m['header'] as Map<String, dynamic>)['format'] = 'wrong_format';
            return m;
          },
          kind: BackupFailureKind.invalidBackupHeader,
        ),
        (
          name: 'missing format identifier',
          mutate: (m) {
            (m['header'] as Map<String, dynamic>).remove('format');
            return m;
          },
          kind: BackupFailureKind.invalidBackupHeader,
        ),
        (
          name: 'unsupported format_version 2',
          mutate: (m) {
            (m['header'] as Map<String, dynamic>)['format_version'] = 2;
            return m;
          },
          kind: BackupFailureKind.unsupportedFormatVersion,
        ),
        (
          name: 'unsupported format_version 99',
          mutate: (m) {
            (m['header'] as Map<String, dynamic>)['format_version'] = 99;
            return m;
          },
          kind: BackupFailureKind.unsupportedFormatVersion,
        ),
        (
          name: 'unknown KDF',
          mutate: (m) {
            (m['header'] as Map<String, dynamic>)['kdf'] = 'scrypt';
            return m;
          },
          kind: BackupFailureKind.unsupportedKdf,
        ),
        (
          name: 'missing KDF',
          mutate: (m) {
            (m['header'] as Map<String, dynamic>).remove('kdf');
            return m;
          },
          kind: BackupFailureKind.unsupportedKdf,
        ),
        (
          name: 'iterations 99999',
          mutate: (m) {
            (m['header'] as Map<String, dynamic>)['iterations'] = 99999;
            return m;
          },
          kind: BackupFailureKind.unsupportedKdf,
        ),
        (
          name: 'iterations 100001',
          mutate: (m) {
            (m['header'] as Map<String, dynamic>)['iterations'] = 100001;
            return m;
          },
          kind: BackupFailureKind.unsupportedKdf,
        ),
        (
          name: 'missing iterations',
          mutate: (m) {
            (m['header'] as Map<String, dynamic>).remove('iterations');
            return m;
          },
          kind: BackupFailureKind.unsupportedKdf,
        ),
        (
          name: 'future header schema_version 9',
          mutate: (m) {
            (m['header'] as Map<String, dynamic>)['schema_version'] = 9;
            return m;
          },
          kind: BackupFailureKind.unsupportedFutureSchema,
        ),
        (
          name: 'future header schema_version 99',
          mutate: (m) {
            (m['header'] as Map<String, dynamic>)['schema_version'] = 99;
            return m;
          },
          kind: BackupFailureKind.unsupportedFutureSchema,
        ),
        (
          name: 'legacy header schema_version 3',
          mutate: (m) {
            (m['header'] as Map<String, dynamic>)['schema_version'] = 3;
            return m;
          },
          kind: BackupFailureKind.invalidSnapshotVersion,
        ),
        (
          name: 'invalid salt byte length',
          mutate: (m) {
            (m['header'] as Map<String, dynamic>)['salt_base64'] =
                base64Encode([1, 2, 3]);
            return m;
          },
          kind: BackupFailureKind.invalidBackupHeader,
        ),
        (
          name: 'invalid checksum_sha256',
          mutate: (m) {
            (m['header'] as Map<String, dynamic>)['checksum_sha256'] = 'bad';
            return m;
          },
          kind: BackupFailureKind.invalidBackupHeader,
        ),
      ];

      for (final tc in invalidEnvelopeCases) {
        final copy =
            jsonDecode(jsonEncode(parsedValid)) as Map<String, dynamic>;
        final mutated = tc.mutate(copy);
        await expectLater(
          () async => service.decryptDatabasePayload(
            encryptedEnvelopeJson: jsonEncode(mutated),
            passphrase: 'Passphrase#Stage342',
          ),
          _throwsValidation(tc.kind),
          reason: '${tc.name} must throw ${tc.kind}',
        );
      }

      // Empty passphrase -> authenticationFailure with neutral message
      await expectLater(
        () async => service.decryptDatabasePayload(
          encryptedEnvelopeJson: validEnvelope,
          passphrase: '   ',
        ),
        _throwsValidation(
          BackupFailureKind.authenticationFailure,
          EncryptionBackupService.authenticationFailureMessage,
        ),
      );

      // Wrong passphrase -> authenticationFailure with neutral message
      await expectLater(
        () async => service.decryptDatabasePayload(
          encryptedEnvelopeJson: validEnvelope,
          passphrase: 'WrongPassword!',
        ),
        _throwsValidation(
          BackupFailureKind.authenticationFailure,
          EncryptionBackupService.authenticationFailureMessage,
        ),
      );

      // Tampered ciphertext -> authenticationFailure with identical neutral message
      final tamperedCipher =
          jsonDecode(jsonEncode(parsedValid)) as Map<String, dynamic>;
      final cipherBytes =
          base64Decode(tamperedCipher['ciphertext_base64'] as String).toList();
      cipherBytes[0] = cipherBytes[0] ^ 0xff;
      tamperedCipher['ciphertext_base64'] = base64Encode(cipherBytes);
      await expectLater(
        () async => service.decryptDatabasePayload(
          encryptedEnvelopeJson: jsonEncode(tamperedCipher),
          passphrase: 'Passphrase#Stage342',
        ),
        _throwsValidation(
          BackupFailureKind.authenticationFailure,
          EncryptionBackupService.authenticationFailureMessage,
        ),
      );

      // Tampered MAC tag -> authenticationFailure with identical neutral message
      final tamperedMac =
          jsonDecode(jsonEncode(parsedValid)) as Map<String, dynamic>;
      final macBytes = base64Decode(
        (tamperedMac['header'] as Map<String, dynamic>)['mac_base64'] as String,
      ).toList();
      macBytes[0] = macBytes[0] ^ 0xff;
      (tamperedMac['header'] as Map<String, dynamic>)['mac_base64'] =
          base64Encode(macBytes);
      await expectLater(
        () async => service.decryptDatabasePayload(
          encryptedEnvelopeJson: jsonEncode(tamperedMac),
          passphrase: 'Passphrase#Stage342',
        ),
        _throwsValidation(
          BackupFailureKind.authenticationFailure,
          EncryptionBackupService.authenticationFailureMessage,
        ),
      );

      // SHA-256 mismatch after valid AES-GCM decryption -> integrityFailure
      final checksumMismatch =
          jsonDecode(jsonEncode(parsedValid)) as Map<String, dynamic>;
      (checksumMismatch['header'] as Map<String, dynamic>)['checksum_sha256'] =
          '0' * 64;
      await expectLater(
        () async => service.decryptDatabasePayload(
          encryptedEnvelopeJson: jsonEncode(checksumMismatch),
          passphrase: 'Passphrase#Stage342',
        ),
        _throwsValidation(BackupFailureKind.integrityFailure),
      );

      // Authenticated & SHA-256-matched invalid UTF-8 bytes -> invalidPayload (not integrityFailure)
      final badUtf8Env = await _encryptRawBytesEnvelopeWithHeaderOverrides(
        plaintextBytes: [0xff, 0xfe, 0xfd],
        passphrase: 'Passphrase#Stage342',
        headerSchemaVersion: 7,
      );
      await expectLater(
        () async => service.decryptDatabasePayload(
          encryptedEnvelopeJson: badUtf8Env,
          passphrase: 'Passphrase#Stage342',
        ),
        _throwsValidation(BackupFailureKind.invalidPayload),
      );

      // Encrypted non-JSON payload -> invalidPayload
      final nonJsonEnvelope = await _encryptRawEnvelopeWithHeaderOverrides(
        plaintext: 'not-valid-json{{{',
        passphrase: 'Passphrase#Stage342',
        headerSchemaVersion: 7,
      );
      await expectLater(
        () async => service.decryptDatabasePayload(
          encryptedEnvelopeJson: nonJsonEnvelope,
          passphrase: 'Passphrase#Stage342',
        ),
        _throwsValidation(BackupFailureKind.invalidPayload),
      );

      // Encrypted JSON array (non-object) -> invalidPayload
      final nonObjectEnvelope = await _encryptRawEnvelopeWithHeaderOverrides(
        plaintext: '[1, 2, 3]',
        passphrase: 'Passphrase#Stage342',
        headerSchemaVersion: 7,
      );
      await expectLater(
        () async => service.decryptDatabasePayload(
          encryptedEnvelopeJson: nonObjectEnvelope,
          passphrase: 'Passphrase#Stage342',
        ),
        _throwsValidation(BackupFailureKind.invalidPayload),
      );

      // Valid header schema 7 wrapping mismatched inner version 8 -> invalidSnapshotVersion
      final mismatchedInnerV8Envelope =
          await _encryptRawEnvelopeWithHeaderOverrides(
        plaintext: jsonEncode(_minimalValidSnapshot(schemaVersion: 8)),
        passphrase: 'Passphrase#Stage342',
        headerSchemaVersion: 7,
      );
      await expectLater(
        () async => service.decryptDatabasePayload(
          encryptedEnvelopeJson: mismatchedInnerV8Envelope,
          passphrase: 'Passphrase#Stage342',
        ),
        _throwsValidation(BackupFailureKind.invalidSnapshotVersion),
      );

      // Valid header schema 8 wrapping inner future version 9 -> unsupportedFutureSchema
      final innerFutureEnvelope = await _encryptRawEnvelopeWithHeaderOverrides(
        plaintext: jsonEncode(_minimalValidSnapshot(schemaVersion: 9)),
        passphrase: 'Passphrase#Stage342',
        headerSchemaVersion: 8,
      );
      await expectLater(
        () async => service.decryptDatabasePayload(
          encryptedEnvelopeJson: innerFutureEnvelope,
          passphrase: 'Passphrase#Stage342',
        ),
        _throwsValidation(BackupFailureKind.unsupportedFutureSchema),
      );
    });

    test(
        'Enforces strict header vs effective inner-version matrix across EncryptionBackupService, DatabasePersistenceCoordinator, and AppStateManager restore/recovery paths',
        () async {
      final service = EncryptionBackupService();

      // Accepted (Header, Inner) cases
      final acceptedCases = <({
        String name,
        int headerVersion,
        Map<String, dynamic> innerPayload,
        int expectedResolved,
      })>[
        (
          name: '(5, Omitted)',
          headerVersion: 5,
          innerPayload: _minimalValidSnapshot(includeSchemaVersion: false),
          expectedResolved: 5,
        ),
        (
          name: '(5, 5)',
          headerVersion: 5,
          innerPayload: _minimalValidSnapshot(schemaVersion: 5),
          expectedResolved: 5,
        ),
        (
          name: '(5, version: 5)',
          headerVersion: 5,
          innerPayload: _minimalValidSnapshot(
            includeSchemaVersion: false,
            includeVersion: true,
            version: 5,
          ),
          expectedResolved: 5,
        ),
        (
          name: '(4, 4)',
          headerVersion: 4,
          innerPayload: _minimalValidSnapshot(schemaVersion: 4),
          expectedResolved: 4,
        ),
        (
          name: '(6, 6)',
          headerVersion: 6,
          innerPayload: _minimalValidSnapshot(schemaVersion: 6),
          expectedResolved: 6,
        ),
        (
          name: '(7, 7)',
          headerVersion: 7,
          innerPayload: _minimalValidSnapshot(schemaVersion: 7),
          expectedResolved: 7,
        ),
        (
          name: '(8, 8)',
          headerVersion: 8,
          innerPayload: _minimalValidSnapshot(schemaVersion: 8),
          expectedResolved: 8,
        ),
        (
          name: '(9, 9)',
          headerVersion: 9,
          innerPayload: _minimalValidSnapshot(schemaVersion: 9),
          expectedResolved: 9,
        ),
      ];

      for (final tc in acceptedCases) {
        final rawJson = jsonEncode(tc.innerPayload);
        final envelope = await service.encryptDatabasePayload(
          rawDatabaseJson: rawJson,
          passphrase: 'MatrixPass#3421',
          schemaVersion: tc.headerVersion,
        );
        final decrypted = await service.decryptDatabasePayload(
          encryptedEnvelopeJson: envelope,
          passphrase: 'MatrixPass#3421',
        );
        expect(decrypted, rawJson, reason: '${tc.name} must decrypt');
        expect(
          DatabasePersistenceCoordinator.validateCanonicalSnapshot(
            tc.innerPayload,
            expectedHeaderVersion: tc.headerVersion,
          ),
          tc.expectedResolved,
          reason: '${tc.name} must resolve to ${tc.expectedResolved}',
        );
      }

      // Rejected (Header, Inner) cases
      final rejectedMatrixCases = <({
        String name,
        int headerVersion,
        Map<String, dynamic> innerPayload,
        BackupFailureKind kind,
      })>[
        (
          name: '(4, Omitted)',
          headerVersion: 4,
          innerPayload: _minimalValidSnapshot(includeSchemaVersion: false),
          kind: BackupFailureKind.invalidSnapshotVersion,
        ),
        (
          name: '(6, Omitted)',
          headerVersion: 6,
          innerPayload: _minimalValidSnapshot(includeSchemaVersion: false),
          kind: BackupFailureKind.invalidSnapshotVersion,
        ),
        (
          name: '(6, 5)',
          headerVersion: 6,
          innerPayload: _minimalValidSnapshot(schemaVersion: 5),
          kind: BackupFailureKind.invalidSnapshotVersion,
        ),
        (
          name: '(7, 6)',
          headerVersion: 7,
          innerPayload: _minimalValidSnapshot(schemaVersion: 6),
          kind: BackupFailureKind.invalidSnapshotVersion,
        ),
        (
          name: '(7, 8)',
          headerVersion: 7,
          innerPayload: _minimalValidSnapshot(schemaVersion: 8),
          kind: BackupFailureKind.invalidSnapshotVersion,
        ),
        (
          name: '(10, 10)',
          headerVersion: 10,
          innerPayload: _minimalValidSnapshot(schemaVersion: 10),
          kind: BackupFailureKind.unsupportedFutureSchema,
        ),
        (
          name: '(99, 99)',
          headerVersion: 99,
          innerPayload: _minimalValidSnapshot(schemaVersion: 99),
          kind: BackupFailureKind.unsupportedFutureSchema,
        ),
        (
          name: '(5, contradictory 5 vs 6)',
          headerVersion: 5,
          innerPayload: _minimalValidSnapshot(
            schemaVersion: 5,
            includeVersion: true,
            version: 6,
          ),
          kind: BackupFailureKind.invalidSnapshotVersion,
        ),
        (
          name: '(5, explicit null schemaVersion)',
          headerVersion: 5,
          innerPayload: _minimalValidSnapshot(schemaVersion: null),
          kind: BackupFailureKind.invalidSnapshotVersion,
        ),
      ];

      final tempDir = Directory.systemTemp.createTempSync('daywell_s3421_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final dbFile = File(p.join(tempDir.path, 'live.sqlite'));
      final docsDir = Directory(p.join(tempDir.path, 'docs'))..createSync();
      final supportDir = Directory(p.join(tempDir.path, 'support'))
        ..createSync();
      final quarantineDir =
          Directory(p.join(docsDir.path, 'recovery_quarantine'));

      final manager = AppStateManager(
        databaseBuilder: () => AppDatabase(NativeDatabase(dbFile)),
        recoveryExporter: RawDatabaseRecoveryExporter(
          documentsDirProvider: () async => docsDir,
          supportDirProvider: () async => supportDir,
        ),
        notificationService: _NoOpNotificationService(),
      );
      await manager.initialize();
      await manager.financeController.addAccount(
        name: 'Protected Matrix Cash',
        type: AccountType.asset,
        subType: AccountSubType.cash,
        openingBalanceCents: 275000,
      );
      expect(manager.liquidCashCents, 275000);

      for (final tc in rejectedMatrixCases) {
        final envelope = await _encryptRawEnvelopeWithHeaderOverrides(
          plaintext: jsonEncode(tc.innerPayload),
          passphrase: 'MatrixPass#3421',
          headerSchemaVersion: tc.headerVersion,
        );

        await expectLater(
          () async => service.decryptDatabasePayload(
            encryptedEnvelopeJson: envelope,
            passphrase: 'MatrixPass#3421',
          ),
          _throwsValidation(tc.kind),
          reason: 'EncryptionBackupService ${tc.name} must throw ${tc.kind}',
        );

        expect(
          () => DatabasePersistenceCoordinator.validateCanonicalSnapshot(
            tc.innerPayload,
            expectedHeaderVersion: tc.headerVersion,
          ),
          _throwsValidation(tc.kind),
          reason:
              'DatabasePersistenceCoordinator ${tc.name} must throw ${tc.kind}',
        );

        final resRestore = await manager.restoreFromEncryptedBackupDetailed(
          envelope,
          'MatrixPass#3421',
        );
        expect(
          resRestore.success,
          isFalse,
          reason: '${tc.name} restore rejected',
        );
        expect(resRestore.failureKind, tc.kind, reason: tc.name);
        expect(quarantineDir.existsSync(), isFalse, reason: tc.name);
        expect(manager.liquidCashCents, 275000, reason: tc.name);

        final resRec = await manager.restoreEncryptedBackupInRecoveryDetailed(
          encryptedEnvelopeJson: envelope,
          passphrase: 'MatrixPass#3421',
        );
        expect(
          resRec.success,
          isFalse,
          reason: '${tc.name} recovery rejected',
        );
        expect(resRec.failureKind, tc.kind, reason: tc.name);
        expect(quarantineDir.existsSync(), isFalse, reason: tc.name);
        expect(manager.liquidCashCents, 275000, reason: tc.name);
      }

      // Verify accepted (5, Omitted) restores cleanly end-to-end
      final omittedJson =
          jsonEncode(_minimalValidSnapshot(includeSchemaVersion: false));
      final omittedV5Envelope = await _encryptRawEnvelopeWithHeaderOverrides(
        plaintext: omittedJson,
        passphrase: 'MatrixPass#3421',
        headerSchemaVersion: 5,
      );
      final acceptedResult = await manager.restoreFromEncryptedBackupDetailed(
        omittedV5Envelope,
        'MatrixPass#3421',
      );
      expect(acceptedResult.success, isTrue);
      expect(manager.accounts.any((a) => a.id == 'acc-snap-1'), isTrue);

      await manager.disposeAsync();
    });

    test(
        'AppStateManager restore and SharedFoundationBridge reject unsupported backups BEFORE quarantine or DB replacement and expose detailed errors',
        () async {
      final tempDir = Directory.systemTemp.createTempSync('daywell_s342_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final dbFile = File(p.join(tempDir.path, 'live.sqlite'));
      final docsDir = Directory(p.join(tempDir.path, 'docs'))..createSync();
      final supportDir = Directory(p.join(tempDir.path, 'support'))
        ..createSync();

      final manager = AppStateManager(
        databaseBuilder: () => AppDatabase(NativeDatabase(dbFile)),
        recoveryExporter: RawDatabaseRecoveryExporter(
          documentsDirProvider: () async => docsDir,
          supportDirProvider: () async => supportDir,
        ),
        notificationService: _NoOpNotificationService(),
      );
      await manager.initialize();
      await manager.financeController.addAccount(
        name: 'Original Cash',
        type: AccountType.asset,
        subType: AccountSubType.cash,
        openingBalanceCents: 330000,
      );
      expect(manager.liquidCashCents, 330000);

      final validBackup = await manager.exportEncryptedBackup('SecretKey#342');
      final quarantineDir =
          Directory(p.join(docsDir.path, 'recovery_quarantine'));

      // 1. Future header schemaVersion rejected BEFORE quarantine
      final futureEnvelope = jsonDecode(validBackup) as Map<String, dynamic>;
      (futureEnvelope['header'] as Map<String, dynamic>)['schema_version'] = 99;
      final resFuture = await manager.restoreFromEncryptedBackupDetailed(
        jsonEncode(futureEnvelope),
        'SecretKey#342',
      );
      expect(resFuture.success, isFalse);
      expect(resFuture.failureKind, BackupFailureKind.unsupportedFutureSchema);
      expect(manager.lastBackupError?.kind, resFuture.failureKind);
      expect(manager.lastBackupError?.message, resFuture.message);
      expect(quarantineDir.existsSync(), isFalse);
      expect(manager.liquidCashCents, 330000);

      // 2. Wrong passphrase rejected BEFORE quarantine with neutral authenticationFailure message
      final resPass = await manager.restoreFromEncryptedBackupDetailed(
        validBackup,
        'WrongPassword!',
      );
      expect(resPass.success, isFalse);
      expect(resPass.failureKind, BackupFailureKind.authenticationFailure);
      expect(
        resPass.message,
        EncryptionBackupService.authenticationFailureMessage,
      );
      expect(quarantineDir.existsSync(), isFalse);
      expect(manager.liquidCashCents, 330000);

      // 3. SharedFoundationBridge detailed import distinguishes invalid JSON vs future schema
      final r1 = await SharedFoundationBridge.importFromCanonicalJsonDetailed(
        manager,
        '{{{broken',
      );
      expect(r1.success, isFalse);
      expect(r1.failureKind, BackupFailureKind.invalidPayload);

      final r2 = await SharedFoundationBridge.importFromCanonicalJsonDetailed(
        manager,
        jsonEncode(_minimalValidSnapshot(schemaVersion: 10)),
      );
      expect(r2.success, isFalse);
      expect(r2.failureKind, BackupFailureKind.unsupportedFutureSchema);
      expect(manager.liquidCashCents, 330000);

      // 4. SharedFoundationBridge detailed import accepts v8 & v9 snapshots
      final r3 = await SharedFoundationBridge.importFromCanonicalJsonDetailed(
        manager,
        jsonEncode(_minimalValidSnapshot(schemaVersion: 8)),
      );
      expect(r3.success, isTrue);
      expect(manager.accounts.any((a) => a.id == 'acc-snap-1'), isTrue);

      final r4 = await SharedFoundationBridge.importFromCanonicalJsonDetailed(
        manager,
        jsonEncode(_minimalValidSnapshot(schemaVersion: 9)),
      );
      expect(r4.success, isTrue);

      await manager.disposeAsync();
    });

    testWidgets(
        'BackupView surfaces distinct error SnackBars for authentication failure, unsupported format, unsupported KDF, unsupported future schema, and invalid canonical payload',
        (WidgetTester tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final manager = AppStateManager(
        db: db,
        notificationService: _NoOpNotificationService(),
      );
      late String validEnvelope;
      await tester.runAsync(() async {
        await db.ensureInitialized();
        await _seedProtectedData(db);
        await manager.initialize();
        validEnvelope = await manager.exportEncryptedBackup('BackupPass#1');
      });

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 20));
        var disposed = false;
        final disposeFuture = manager.disposeAsync().whenComplete(() {
          disposed = true;
        });
        final watch = Stopwatch()..start();
        while (!disposed && watch.elapsed < const Duration(seconds: 10)) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
        if (disposed) {
          await disposeFuture;
        } else {
          await tester.runAsync(
            () => disposeFuture.timeout(const Duration(seconds: 5)),
          );
        }
      });

      await tester.pumpWidget(
        MaterialApp(
          home: BackupView(state: manager),
        ),
      );
      await tester.pumpAndSettle();

      // Test 1: Canonical future schema rejection SnackBar
      final canonicalInput = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText ==
                'Paste shared canonical JSON payload here...',
      );
      expect(canonicalInput, findsOneWidget);
      await tester.enterText(
        canonicalInput,
        jsonEncode(_minimalValidSnapshot(schemaVersion: 10)),
      );
      await tester.tap(find.text('Import Pasted JSON'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Unsupported future snapshot'),
        findsOneWidget,
      );

      ScaffoldMessenger.of(tester.element(find.byType(BackupView)))
          .clearSnackBars();
      await tester.pumpAndSettle();

      // Test 1b: Invalid canonical JSON payload rejection SnackBar
      await tester.enterText(canonicalInput, '{{{broken');
      await tester.tap(find.text('Import Pasted JSON'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Invalid JSON payload'),
        findsOneWidget,
      );

      ScaffoldMessenger.of(tester.element(find.byType(BackupView)))
          .clearSnackBars();
      await tester.pumpAndSettle();

      // Scroll to encrypted restore section and ensure controls are visible
      final listScrollable = find.byType(Scrollable).first;
      final restorePayloadField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Paste Encrypted Backup JSON',
      );
      final restorePassField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Passphrase *',
      );
      final restoreButton = find.text('Decrypt & Restore State');
      await tester.scrollUntilVisible(
        restoreButton,
        200,
        scrollable: listScrollable,
      );
      await tester.ensureVisible(restoreButton);
      await tester.pumpAndSettle();
      await tester.ensureVisible(restorePayloadField);
      await tester.pumpAndSettle();

      // Test 2: Unsupported format_version rejects BEFORE confirmation dialog
      final badFormat = jsonDecode(validEnvelope) as Map<String, dynamic>;
      (badFormat['header'] as Map<String, dynamic>)['format_version'] = 99;
      await tester.enterText(restorePayloadField, jsonEncode(badFormat));
      await tester.ensureVisible(restorePassField);
      await tester.pumpAndSettle();
      await tester.enterText(restorePassField, 'BackupPass#1');
      await tester.ensureVisible(restoreButton);
      await tester.pumpAndSettle();
      await tester.tap(restoreButton);
      await tester.pumpAndSettle();
      expect(find.text('Quarantine & Restore Backup?'), findsNothing);
      expect(find.textContaining('format_version 99'), findsOneWidget);

      ScaffoldMessenger.of(tester.element(find.byType(BackupView)))
          .clearSnackBars();
      await tester.pumpAndSettle();

      // Test 3: Unsupported KDF rejects BEFORE confirmation dialog
      final badKdf = jsonDecode(validEnvelope) as Map<String, dynamic>;
      (badKdf['header'] as Map<String, dynamic>)['kdf'] = 'Argon2';
      await tester.ensureVisible(restorePayloadField);
      await tester.pumpAndSettle();
      await tester.enterText(restorePayloadField, jsonEncode(badKdf));
      await tester.ensureVisible(restoreButton);
      await tester.pumpAndSettle();
      await tester.tap(restoreButton);
      await tester.pumpAndSettle();
      expect(find.text('Quarantine & Restore Backup?'), findsNothing);
      expect(find.textContaining('Unsupported key derivation'), findsOneWidget);

      ScaffoldMessenger.of(tester.element(find.byType(BackupView)))
          .clearSnackBars();
      await tester.pumpAndSettle();

      // Test 4: Authentication failure opens dialog, confirms, and surfaces
      // neutral authenticationFailure SnackBar.
      await tester.ensureVisible(restorePayloadField);
      await tester.pumpAndSettle();
      await tester.enterText(restorePayloadField, validEnvelope);
      await tester.ensureVisible(restorePassField);
      await tester.pumpAndSettle();
      await tester.enterText(restorePassField, 'WrongPass#99');
      await tester.ensureVisible(restoreButton);
      await tester.pumpAndSettle();
      await tester.tap(restoreButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quarantine & Restore'));

      final expectedFinder = find.textContaining(
        EncryptionBackupService.authenticationFailureMessage,
      );
      final stopwatch = Stopwatch()..start();
      while (expectedFinder.evaluate().isEmpty) {
        if (stopwatch.elapsed > const Duration(seconds: 30)) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      await tester.pumpAndSettle();
      expect(expectedFinder, findsOneWidget);

      ScaffoldMessenger.of(tester.element(find.byType(BackupView)))
          .clearSnackBars();
      await tester.pumpAndSettle();
    });
  });
}
