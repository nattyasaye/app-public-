import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/services/backup/encryption_backup_service.dart';

void main() {
  group('Stage 6 Passphrase-Derived Encrypted Backup & Restore Tests', () {
    late EncryptionBackupService backupService;

    setUp(() {
      backupService = EncryptionBackupService();
    });

    test(
        'Passphrase-derived AES-GCM-256 generates complete authenticated envelope',
        () async {
      const sampleDbPayload =
          '{"version":4,"tasks":[{"id":"t1","title":"Inspect solar"}],"incomesCents":[3500000]}';
      const passphrase = 'MySecurePassphrase!2026';

      final encryptedEnvelope = await backupService.encryptDatabasePayload(
        rawDatabaseJson: sampleDbPayload,
        passphrase: passphrase,
        schemaVersion: 4,
      );

      final Map<String, dynamic> parsed = jsonDecode(encryptedEnvelope);
      expect(parsed.containsKey('header'), isTrue);
      expect(parsed.containsKey('ciphertext_base64'), isTrue);

      final header = parsed['header'] as Map<String, dynamic>;
      expect(header['format'], 'personal_mgmt_encrypted_backup');
      expect(header['kdf'], 'PBKDF2-HMAC-SHA256');
      expect(header['iterations'], 100000);
      expect(header['salt_base64'], isNotEmpty);
      expect(header['nonce_base64'], isNotEmpty);
      expect(header['mac_base64'], isNotEmpty);
      expect(header['checksum_sha256'], isNotEmpty);
    });

    test(
        'Decryption with correct passphrase restores identical plaintext and verifies SHA-256',
        () async {
      final sampleDatabase = {
        'version': 4,
        'tasks': [
          {
            'id': 'task-101',
            'title': 'Audit monthly living expenses',
            'status': 'in_progress',
            'priority': 'urgent',
          }
        ],
        'transactions': [
          {
            'id': 'tx-1',
            'amountCents': 3500000,
            'note': 'Monthly salary in ETB (ደመወዝ)',
          }
        ],
        'notes': [
          {
            'id': 'note-1',
            'title': 'የዕለት ማስታወሻ',
            'content': 'ትኩረት ማድረግ ያለብኝ ዋና ዋና ጉዳዮች።',
          }
        ],
      };
      final rawJson = jsonEncode(sampleDatabase);
      const passphrase = 'PassphraseForRestoration#77';

      final encryptedEnvelope = await backupService.encryptDatabasePayload(
        rawDatabaseJson: rawJson,
        passphrase: passphrase,
        schemaVersion: 4,
      );

      final decryptedJson = await backupService.decryptDatabasePayload(
        encryptedEnvelopeJson: encryptedEnvelope,
        passphrase: passphrase,
      );

      expect(decryptedJson, rawJson);

      final restoredMap = jsonDecode(decryptedJson) as Map<String, dynamic>;
      expect(restoredMap['version'], 4);
      expect(restoredMap['tasks'], isNotEmpty);
      expect(restoredMap['transactions'], isNotEmpty);
      expect(restoredMap['notes'][0]['title'], 'የዕለት ማስታወሻ');
    });

    test('Decryption fails when an incorrect passphrase is supplied', () async {
      const samplePayload = '{"database":"active_user_data"}';
      const correctPassphrase = 'CorrectPassword123';
      const wrongPassphrase = 'WrongPassword456';

      final encrypted = await backupService.encryptDatabasePayload(
        rawDatabaseJson: samplePayload,
        passphrase: correctPassphrase,
        schemaVersion: 4,
      );

      expect(
        () async => await backupService.decryptDatabasePayload(
          encryptedEnvelopeJson: encrypted,
          passphrase: wrongPassphrase,
        ),
        throwsA(anything),
      );
    });

    test(
        'Tampering with ciphertext or authentication tag triggers integrity failure',
        () async {
      const samplePayload = '{"secret_records":[{"amount":50000}]}';
      const passphrase = 'TamperVerificationSecret';

      final encryptedJson = await backupService.encryptDatabasePayload(
        rawDatabaseJson: samplePayload,
        passphrase: passphrase,
        schemaVersion: 4,
      );

      final Map<String, dynamic> envelope = jsonDecode(encryptedJson);
      // Tamper with the base64 ciphertext
      final validCipher = envelope['ciphertext_base64'] as String;
      final tamperedCipher =
          '${validCipher.substring(0, validCipher.length - 4)}AAAA';
      envelope['ciphertext_base64'] = tamperedCipher;

      expect(
        () async => await backupService.decryptDatabasePayload(
          encryptedEnvelopeJson: jsonEncode(envelope),
          passphrase: passphrase,
        ),
        throwsA(anything),
      );
    });

    test(
        'Multi-device full restore equivalence test on clean secondary instance',
        () async {
      // Primary device database state
      final primaryDeviceState = {
        'version': 4,
        'inboxCount': 3,
        'recordedBalanceCents': 4370000,
        'tasks': [
          {'id': 'task-1', 'title': 'Inspect backup solar'}
        ],
        'notes': [
          {'id': 'note-1', 'title': 'Medical info'}
        ],
        'commitments': [
          {'id': 'c-1', 'amountCents': 800000, 'isPaid': false}
        ],
      };
      final serializedPrimary = jsonEncode(primaryDeviceState);
      const crossDevicePassphrase = 'CrossDeviceSyncKey_2026';

      // 1. Export from Primary Device
      final backupEnvelope = await backupService.encryptDatabasePayload(
        rawDatabaseJson: serializedPrimary,
        passphrase: crossDevicePassphrase,
        schemaVersion: 4,
      );

      // 2. Simulate Secondary Device starting with zero data
      final cleanSecondaryState = <String, dynamic>{};
      expect(cleanSecondaryState.isEmpty, isTrue);

      // 3. Restore on Secondary Device
      final restoredPayload = await backupService.decryptDatabasePayload(
        encryptedEnvelopeJson: backupEnvelope,
        passphrase: crossDevicePassphrase,
      );
      final restoredMap = jsonDecode(restoredPayload) as Map<String, dynamic>;

      // 4. Validate exact equivalence
      expect(restoredMap['version'], primaryDeviceState['version']);
      expect(restoredMap['recordedBalanceCents'],
          primaryDeviceState['recordedBalanceCents']);
      expect(restoredMap['tasks'], primaryDeviceState['tasks']);
      expect(restoredMap['commitments'], primaryDeviceState['commitments']);
      expect(restoredMap['notes'], primaryDeviceState['notes']);
    });
  });
}
