import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import '../../core/date/shared_date.dart';
import '../../core/interfaces/platform_service_interfaces.dart';

/// Validated metadata extracted from a `.daywell` encrypted envelope header.
class ValidatedBackupEnvelope {
  final String format;
  final int formatVersion;
  final String appVersion;
  final int schemaVersion;
  final String kdf;
  final int iterations;
  final List<int> salt;
  final List<int> nonce;
  final List<int> macBytes;
  final List<int> ciphertext;
  final String checksumSha256;

  const ValidatedBackupEnvelope({
    required this.format,
    required this.formatVersion,
    required this.appVersion,
    required this.schemaVersion,
    required this.kdf,
    required this.iterations,
    required this.salt,
    required this.nonce,
    required this.macBytes,
    required this.ciphertext,
    required this.checksumSha256,
  });
}

/// Passphrase-derived encrypted backup engine.
///
/// Implements:
/// - Key Derivation: PBKDF2-HMAC-SHA256 with exactly 100,000 iterations and a cryptographically random 16-byte salt
/// - Authenticated Encryption: AES-GCM-256 with a unique 12-byte Nonce/IV
/// - Integrity: SHA-256 digest of original plaintext database payload verified after decryption
/// - Portability: Self-contained envelope format readable across Android and iOS
class EncryptionBackupService {
  static const String supportedFormat = 'personal_mgmt_encrypted_backup';
  static const int supportedFormatVersion = 1;
  static const String supportedKdf = 'PBKDF2-HMAC-SHA256';
  static const int _pbkdf2Iterations = 100000;
  static const int _keyLengthBits = 256;
  static const int minSupportedCanonicalSchemaVersion = 4;
  static const int maxSupportedCanonicalSchemaVersion = 8;
  static const int legacyOmittedSnapshotVersion = 5;
  static const String currentAppVersion = '1.0.2+3';
  static const String authenticationFailureMessage =
      'Backup authentication failed. Check the passphrase and ensure the backup file has not been modified.';
  static final RegExp _sha256HexPattern = RegExp(r'^[0-9a-fA-F]{64}$');

  final AesGcm _cipher = AesGcm.with256bits();
  final Pbkdf2 _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _pbkdf2Iterations,
    bits: _keyLengthBits,
  );

  /// Encrypts database JSON export payload using user's secret passphrase.
  Future<String> encryptDatabasePayload({
    required String rawDatabaseJson,
    required String passphrase,
    required int schemaVersion,
  }) async {
    // 1. Generate random 16-byte salt and 12-byte IV/Nonce
    final salt = SecretKeyData.random(length: 16).bytes;
    final nonce = _cipher.newNonce();

    // 2. Derive SecretKey using PBKDF2
    final derivedSecretKey = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );

    // 3. Compute SHA-256 checksum of plaintext for post-restore verification
    final sha256 = Sha256();
    final checksumSink = await sha256.hash(utf8.encode(rawDatabaseJson));
    final checksumHex = checksumSink.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    // 4. Encrypt with AES-GCM-256
    final secretBox = await _cipher.encrypt(
      utf8.encode(rawDatabaseJson),
      secretKey: derivedSecretKey,
      nonce: nonce,
    );

    // 5. Structure portable encrypted envelope
    final envelope = {
      'header': {
        'format': supportedFormat,
        'format_version': supportedFormatVersion,
        'app_version': currentAppVersion,
        'schema_version': schemaVersion,
        'created_at_utc': EthiopiaClock.nowUtc().toIso8601String(),
        'kdf': supportedKdf,
        'iterations': _pbkdf2Iterations,
        'salt_base64': base64Encode(salt),
        'nonce_base64': base64Encode(nonce),
        'mac_base64': base64Encode(secretBox.mac.bytes),
        'checksum_sha256': checksumHex,
      },
      'ciphertext_base64': base64Encode(secretBox.cipherText),
    };

    return jsonEncode(envelope);
  }

  /// Validates the complete `.daywell` envelope header fail-closed before
  /// attempting key derivation, decryption, or database quarantine.
  static ValidatedBackupEnvelope validateAndParseEnvelope(
    String encryptedEnvelopeJson,
  ) {
    dynamic decodedEnvelope;
    try {
      decodedEnvelope = jsonDecode(encryptedEnvelopeJson);
    } on FormatException {
      throw const BackupValidationException(
        BackupFailureKind.invalidBackupHeader,
        'Invalid backup file: not a valid JSON envelope.',
      );
    }

    if (decodedEnvelope is! Map<String, dynamic>) {
      throw const BackupValidationException(
        BackupFailureKind.invalidBackupHeader,
        'Invalid backup envelope: expected a JSON object.',
      );
    }

    final rawHeader = decodedEnvelope['header'];
    if (rawHeader is! Map<String, dynamic>) {
      throw const BackupValidationException(
        BackupFailureKind.invalidBackupHeader,
        'Backup envelope is missing a valid header object.',
      );
    }

    final format = rawHeader['format'];
    if (format is! String || format.trim().isEmpty) {
      throw const BackupValidationException(
        BackupFailureKind.invalidBackupHeader,
        'Backup header is missing a valid format identifier.',
      );
    }
    if (format != supportedFormat) {
      throw BackupValidationException(
        BackupFailureKind.invalidBackupHeader,
        'Unsupported backup format "$format". Expected "$supportedFormat".',
      );
    }

    if (!rawHeader.containsKey('format_version')) {
      throw const BackupValidationException(
        BackupFailureKind.invalidBackupHeader,
        'Backup header is missing format_version.',
      );
    }
    final formatVersion = rawHeader['format_version'];
    if (formatVersion is! int) {
      throw const BackupValidationException(
        BackupFailureKind.invalidBackupHeader,
        'Backup header format_version must be an integer.',
      );
    }
    if (formatVersion != supportedFormatVersion) {
      throw BackupValidationException(
        BackupFailureKind.unsupportedFormatVersion,
        'Unsupported encrypted backup format_version $formatVersion. '
        'Only format_version $supportedFormatVersion is supported.',
      );
    }

    final kdf = rawHeader['kdf'];
    if (kdf is! String || kdf.trim().isEmpty) {
      throw const BackupValidationException(
        BackupFailureKind.unsupportedKdf,
        'Backup header is missing a valid KDF identifier. '
        'Expected "$supportedKdf".',
      );
    }
    if (kdf != supportedKdf) {
      throw BackupValidationException(
        BackupFailureKind.unsupportedKdf,
        'Unsupported key derivation function "$kdf". '
        'Only "$supportedKdf" is supported.',
      );
    }

    if (!rawHeader.containsKey('iterations')) {
      throw const BackupValidationException(
        BackupFailureKind.unsupportedKdf,
        'Backup header is missing KDF iterations. '
        'Expected exactly $_pbkdf2Iterations.',
      );
    }
    final iterations = rawHeader['iterations'];
    if (iterations is! int) {
      throw const BackupValidationException(
        BackupFailureKind.unsupportedKdf,
        'Backup header KDF iterations must be an integer equal to $_pbkdf2Iterations.',
      );
    }
    if (iterations != _pbkdf2Iterations) {
      throw BackupValidationException(
        BackupFailureKind.unsupportedKdf,
        'Unsupported KDF iteration count $iterations. '
        'Format version $supportedFormatVersion requires exactly $_pbkdf2Iterations.',
      );
    }

    if (!rawHeader.containsKey('schema_version')) {
      throw const BackupValidationException(
        BackupFailureKind.invalidBackupHeader,
        'Backup header is missing schema_version.',
      );
    }
    final schemaVersion = rawHeader['schema_version'];
    if (schemaVersion is! int) {
      throw const BackupValidationException(
        BackupFailureKind.invalidSnapshotVersion,
        'Backup header schema_version must be a valid integer.',
      );
    }
    if (schemaVersion < 0) {
      throw BackupValidationException(
        BackupFailureKind.invalidSnapshotVersion,
        'Invalid backup schema_version $schemaVersion: cannot be negative.',
      );
    }
    if (schemaVersion > maxSupportedCanonicalSchemaVersion) {
      throw BackupValidationException(
        BackupFailureKind.unsupportedFutureSchema,
        'Unsupported future backup schema_version $schemaVersion '
        '(maximum supported version is $maxSupportedCanonicalSchemaVersion). '
        'Update Daywell before restoring this backup.',
      );
    }
    if (schemaVersion < minSupportedCanonicalSchemaVersion) {
      throw BackupValidationException(
        BackupFailureKind.invalidSnapshotVersion,
        'Unsupported backup schema_version $schemaVersion '
        '(supported canonical versions are '
        '$minSupportedCanonicalSchemaVersion..$maxSupportedCanonicalSchemaVersion).',
      );
    }

    final appVersion = rawHeader['app_version'];
    if (appVersion != null && appVersion is! String) {
      throw const BackupValidationException(
        BackupFailureKind.invalidBackupHeader,
        'Backup header app_version must be a string.',
      );
    }

    final salt = _decodeRequiredBase64(
      rawHeader['salt_base64'],
      fieldName: 'salt_base64',
      expectedLength: 16,
    );
    final nonce = _decodeRequiredBase64(
      rawHeader['nonce_base64'],
      fieldName: 'nonce_base64',
      expectedLength: 12,
    );
    final macBytes = _decodeRequiredBase64(
      rawHeader['mac_base64'],
      fieldName: 'mac_base64',
      expectedLength: 16,
    );
    final ciphertext = _decodeRequiredBase64(
      decodedEnvelope['ciphertext_base64'],
      fieldName: 'ciphertext_base64',
      minLength: 1,
    );

    final rawChecksum = rawHeader['checksum_sha256'];
    if (rawChecksum is! String ||
        !_sha256HexPattern.hasMatch(rawChecksum.trim())) {
      throw const BackupValidationException(
        BackupFailureKind.invalidBackupHeader,
        'Backup header checksum_sha256 must be a valid 64-character SHA-256 hex digest.',
      );
    }

    return ValidatedBackupEnvelope(
      format: format,
      formatVersion: formatVersion,
      appVersion: (appVersion as String?) ?? currentAppVersion,
      schemaVersion: schemaVersion,
      kdf: kdf,
      iterations: iterations,
      salt: salt,
      nonce: nonce,
      macBytes: macBytes,
      ciphertext: ciphertext,
      checksumSha256: rawChecksum.trim().toLowerCase(),
    );
  }

  static List<int> _decodeRequiredBase64(
    dynamic value, {
    required String fieldName,
    int? expectedLength,
    int? minLength,
  }) {
    if (value is! String || value.trim().isEmpty) {
      throw BackupValidationException(
        BackupFailureKind.invalidBackupHeader,
        'Backup envelope is missing a valid "$fieldName" field.',
      );
    }
    try {
      final bytes = base64Decode(value.trim());
      if (expectedLength != null && bytes.length != expectedLength) {
        throw BackupValidationException(
          BackupFailureKind.invalidBackupHeader,
          'Backup header "$fieldName" has invalid byte length '
          '(${bytes.length}, expected $expectedLength).',
        );
      }
      if (minLength != null && bytes.length < minLength) {
        throw BackupValidationException(
          BackupFailureKind.invalidBackupHeader,
          'Backup field "$fieldName" cannot be empty.',
        );
      }
      return bytes;
    } on BackupValidationException {
      rethrow;
    } on FormatException {
      throw BackupValidationException(
        BackupFailureKind.invalidBackupHeader,
        'Backup field "$fieldName" is not valid Base64.',
      );
    }
  }

  /// Decrypts backup archive using user's passphrase, verifies header,
  /// integrity checksum, and inner canonical snapshot schema bounds.
  Future<String> decryptDatabasePayload({
    required String encryptedEnvelopeJson,
    required String passphrase,
  }) async {
    final envelope = validateAndParseEnvelope(encryptedEnvelopeJson);

    if (passphrase.trim().isEmpty) {
      throw const BackupValidationException(
        BackupFailureKind.authenticationFailure,
        authenticationFailureMessage,
      );
    }

    // 1. Re-derive key from passphrase and salt (exact PBKDF2-HMAC-SHA256, 100,000 rounds)
    final derivedSecretKey = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: envelope.salt,
    );

    // 2. Decrypt SecretBox
    final secretBox = SecretBox(
      envelope.ciphertext,
      nonce: envelope.nonce,
      mac: Mac(envelope.macBytes),
    );

    final List<int> decryptedBytes;
    try {
      decryptedBytes = await _cipher.decrypt(
        secretBox,
        secretKey: derivedSecretKey,
      );
    } on SecretBoxAuthenticationError {
      throw const BackupValidationException(
        BackupFailureKind.authenticationFailure,
        authenticationFailureMessage,
      );
    } catch (_) {
      throw const BackupValidationException(
        BackupFailureKind.authenticationFailure,
        authenticationFailureMessage,
      );
    }

    // 3. Verify cryptographic SHA-256 checksum on authenticated plaintext bytes
    // before decoding UTF-8/JSON so corrupted UTF-8 classifies as invalidPayload.
    final sha256 = Sha256();
    final checksumSink = await sha256.hash(decryptedBytes);
    final actualChecksum = checksumSink.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toLowerCase();

    if (actualChecksum != envelope.checksumSha256) {
      throw const BackupValidationException(
        BackupFailureKind.integrityFailure,
        'Backup integrity check failed: SHA-256 checksum mismatch.',
      );
    }

    final String decryptedJson;
    try {
      decryptedJson = utf8.decode(decryptedBytes);
    } on FormatException {
      throw const BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Decrypted backup payload is not valid UTF-8.',
      );
    }

    // 4. Validate inner JSON payload and effective inner schema/version bounds
    final dynamic decodedInner;
    try {
      decodedInner = jsonDecode(decryptedJson);
    } on FormatException {
      throw const BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Decrypted backup payload is not valid JSON.',
      );
    }
    if (decodedInner is! Map<String, dynamic>) {
      throw const BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Decrypted backup payload must be a JSON object.',
      );
    }

    _validateInnerPayloadVersion(
      decodedInner,
      headerSchemaVersion: envelope.schemaVersion,
    );

    return decryptedJson;
  }

  static void _validateInnerPayloadVersion(
    Map<String, dynamic> payload, {
    required int headerSchemaVersion,
  }) {
    final hasSchemaVersion = payload.containsKey('schemaVersion');
    final hasVersion = payload.containsKey('version');

    int? sv;
    if (hasSchemaVersion) {
      final rawSv = payload['schemaVersion'];
      if (rawSv is! int) {
        throw const BackupValidationException(
          BackupFailureKind.invalidSnapshotVersion,
          'Decrypted backup payload schemaVersion must be an integer.',
        );
      }
      sv = rawSv;
    }

    int? v;
    if (hasVersion) {
      final rawV = payload['version'];
      if (rawV is! int) {
        throw const BackupValidationException(
          BackupFailureKind.invalidSnapshotVersion,
          'Decrypted backup payload version must be an integer.',
        );
      }
      v = rawV;
    }

    if (sv != null && v != null && sv != v) {
      throw BackupValidationException(
        BackupFailureKind.invalidSnapshotVersion,
        'Contradictory inner backup payload versions: '
        'schemaVersion=$sv does not match version=$v.',
      );
    }

    final innerVersion = sv ?? v ?? legacyOmittedSnapshotVersion;
    if (innerVersion < 0) {
      throw BackupValidationException(
        BackupFailureKind.invalidSnapshotVersion,
        'Invalid inner backup version $innerVersion: cannot be negative.',
      );
    }
    if (innerVersion > maxSupportedCanonicalSchemaVersion) {
      throw BackupValidationException(
        BackupFailureKind.unsupportedFutureSchema,
        'Unsupported future inner backup schemaVersion $innerVersion '
        '(maximum supported version is $maxSupportedCanonicalSchemaVersion).',
      );
    }
    if (innerVersion < minSupportedCanonicalSchemaVersion) {
      throw BackupValidationException(
        BackupFailureKind.invalidSnapshotVersion,
        'Unsupported inner backup schema version $innerVersion '
        '(supported canonical versions are '
        '$minSupportedCanonicalSchemaVersion..$maxSupportedCanonicalSchemaVersion).',
      );
    }
    if (innerVersion != headerSchemaVersion) {
      throw BackupValidationException(
        BackupFailureKind.invalidSnapshotVersion,
        'Backup header schema_version ($headerSchemaVersion) does not match '
        'effective inner snapshot version ($innerVersion).',
      );
    }
  }
}
