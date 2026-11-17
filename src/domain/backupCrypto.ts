/**
 * Passphrase-Derived AES-GCM-256 and PBKDF2 Backup Encryption Engine.
 * 100% Offline-First, standard Web Cryptography API implementation compatible
 * with the Flutter/Dart EncryptionBackupService envelope format.
 */

import {
  BackupFailureKind,
  BackupValidationError,
  LocalDatabaseState,
} from './backupTypes';
import { EthiopiaClock } from './date';

export { BackupValidationError } from './backupTypes';
export type {
  BackupErrorInfo,
  BackupFailureKind,
  LocalDatabaseState,
} from './backupTypes';

export const ENCRYPTED_BACKUP_FORMAT = 'personal_mgmt_encrypted_backup' as const;
export const SUPPORTED_BACKUP_FORMAT_VERSION = 1;
export const SUPPORTED_BACKUP_KDF = 'PBKDF2-HMAC-SHA256' as const;
export const SUPPORTED_BACKUP_PBKDF2_ITERATIONS = 100000;
export const SUPPORTED_WEB_LOCAL_BACKUP_VERSION = 3;
export const AUTHENTICATION_FAILURE_MESSAGE =
  'Backup authentication failed. Check the passphrase and ensure the backup file has not been modified.';

const SHA256_HEX_REGEX = /^[0-9a-fA-F]{64}$/;

export interface BackupEnvelopeHeader {
  format: 'personal_mgmt_encrypted_backup';
  format_version: number;
  app_version: string;
  schema_version: number;
  created_at_utc: string;
  kdf: 'PBKDF2-HMAC-SHA256';
  iterations: number;
  salt_base64: string;
  nonce_base64: string;
  mac_base64: string;
  checksum_sha256: string;
}

export interface BackupEnvelope {
  header: BackupEnvelopeHeader;
  ciphertext_base64: string;
}

export interface ValidatedBackupEnvelope {
  envelope: BackupEnvelope;
  salt: Uint8Array;
  iv: Uint8Array;
  mac: Uint8Array;
  ciphertext: Uint8Array;
  checksumSha256: string;
}

export interface BackupHistoryItem {
  id: string;
  timestampUtc: string;
  filename: string;
  sizeBytes: number;
  checksumSha256: string;
  isEncrypted: boolean;
  type: 'export' | 'restore';
  status: 'verified' | 'restored' | 'failed';
  entityCounts: {
    tasks: number;
    projects: number;
    transactions: number;
    commitments: number;
    notes: number;
    reminders: number;
  };
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

// Convert Uint8Array to base64
function toBase64(bytes: Uint8Array): string {
  let binary = '';
  const len = bytes.byteLength;
  for (let i = 0; i < len; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

// Strict Base64 decode with byte-length bounds
function decodeRequiredBase64(
  value: unknown,
  fieldName: string,
  options: { expectedLength?: number; minLength?: number }
): Uint8Array {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new BackupValidationError(
      'invalid_backup_header',
      `Backup envelope is missing a valid "${fieldName}" field.`
    );
  }
  let binary: string;
  try {
    binary = atob(value.trim());
  } catch {
    throw new BackupValidationError(
      'invalid_backup_header',
      `Backup field "${fieldName}" is not valid Base64.`
    );
  }
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  if (options.expectedLength !== undefined && bytes.length !== options.expectedLength) {
    throw new BackupValidationError(
      'invalid_backup_header',
      `Backup header "${fieldName}" has invalid byte length (${bytes.length}, expected ${options.expectedLength}).`
    );
  }
  if (options.minLength !== undefined && bytes.length < options.minLength) {
    throw new BackupValidationError(
      'invalid_backup_header',
      `Backup field "${fieldName}" cannot be empty.`
    );
  }
  return bytes;
}

// Convert ArrayBuffer to hex string
function toHex(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * Computes SHA-256 checksum hex string for raw plaintext bytes.
 */
export async function computeSha256Bytes(bytes: Uint8Array): Promise<string> {
  const buffer = await crypto.subtle.digest('SHA-256', bytes.buffer as ArrayBuffer);
  return toHex(buffer);
}

/**
 * Computes SHA-256 checksum hex string for a given text payload.
 */
export async function computeSha256(text: string): Promise<string> {
  const enc = new TextEncoder();
  return computeSha256Bytes(enc.encode(text));
}

/**
 * Validates `.daywell` encrypted backup envelope headers fail-closed before
 * deriving keys or decrypting ciphertext.
 */
export function validateBackupEnvelopeHeader(
  envelopeString: string
): ValidatedBackupEnvelope {
  let parsedEnvelope: unknown;
  try {
    parsedEnvelope = JSON.parse(envelopeString);
  } catch {
    throw new BackupValidationError(
      'invalid_backup_header',
      'Invalid backup file format: Not a valid JSON envelope.'
    );
  }

  if (!isPlainObject(parsedEnvelope)) {
    throw new BackupValidationError(
      'invalid_backup_header',
      'Invalid backup envelope: Expected a JSON object.'
    );
  }

  const rawHeader = parsedEnvelope.header;
  if (!isPlainObject(rawHeader)) {
    throw new BackupValidationError(
      'invalid_backup_header',
      'Backup envelope is missing a valid header object.'
    );
  }

  const format = rawHeader.format;
  if (typeof format !== 'string' || format.trim().length === 0) {
    throw new BackupValidationError(
      'invalid_backup_header',
      'Backup header is missing a valid format identifier.'
    );
  }
  if (format !== ENCRYPTED_BACKUP_FORMAT) {
    throw new BackupValidationError(
      'invalid_backup_header',
      `Unsupported backup format "${format}". Expected "${ENCRYPTED_BACKUP_FORMAT}".`
    );
  }

  if (!Object.prototype.hasOwnProperty.call(rawHeader, 'format_version')) {
    throw new BackupValidationError(
      'invalid_backup_header',
      'Backup header is missing format_version.'
    );
  }
  const formatVersion = rawHeader.format_version;
  if (typeof formatVersion !== 'number' || !Number.isInteger(formatVersion)) {
    throw new BackupValidationError(
      'invalid_backup_header',
      'Backup header format_version must be an integer.'
    );
  }
  if (formatVersion !== SUPPORTED_BACKUP_FORMAT_VERSION) {
    throw new BackupValidationError(
      'unsupported_format_version',
      `Unsupported encrypted backup format_version ${formatVersion}. Only format_version ${SUPPORTED_BACKUP_FORMAT_VERSION} is supported.`
    );
  }

  const kdf = rawHeader.kdf;
  if (typeof kdf !== 'string' || kdf.trim().length === 0) {
    throw new BackupValidationError(
      'unsupported_kdf',
      `Backup header is missing a valid KDF identifier. Expected "${SUPPORTED_BACKUP_KDF}".`
    );
  }
  if (kdf !== SUPPORTED_BACKUP_KDF) {
    throw new BackupValidationError(
      'unsupported_kdf',
      `Unsupported key derivation function "${kdf}". Only "${SUPPORTED_BACKUP_KDF}" is supported.`
    );
  }

  if (!Object.prototype.hasOwnProperty.call(rawHeader, 'iterations')) {
    throw new BackupValidationError(
      'unsupported_kdf',
      `Backup header is missing KDF iterations. Expected exactly ${SUPPORTED_BACKUP_PBKDF2_ITERATIONS}.`
    );
  }
  const iterations = rawHeader.iterations;
  if (
    typeof iterations !== 'number' ||
    !Number.isInteger(iterations) ||
    iterations !== SUPPORTED_BACKUP_PBKDF2_ITERATIONS
  ) {
    throw new BackupValidationError(
      'unsupported_kdf',
      `Unsupported KDF iterations ${String(iterations)}. Format version ${SUPPORTED_BACKUP_FORMAT_VERSION} requires exactly ${SUPPORTED_BACKUP_PBKDF2_ITERATIONS}.`
    );
  }

  if (!Object.prototype.hasOwnProperty.call(rawHeader, 'schema_version')) {
    throw new BackupValidationError(
      'invalid_backup_header',
      'Backup header is missing schema_version.'
    );
  }
  const schemaVersion = rawHeader.schema_version;
  if (typeof schemaVersion !== 'number' || !Number.isInteger(schemaVersion)) {
    throw new BackupValidationError(
      'invalid_snapshot_version',
      'Backup header schema_version must be an integer.'
    );
  }
  if (schemaVersion < 0) {
    throw new BackupValidationError(
      'invalid_snapshot_version',
      `Invalid backup schema_version ${schemaVersion}: cannot be negative.`
    );
  }
  if (schemaVersion > SUPPORTED_WEB_LOCAL_BACKUP_VERSION) {
    throw new BackupValidationError(
      'unsupported_future_schema',
      `Unsupported future Web backup schema_version ${schemaVersion}. Web encrypted backups support LocalDatabaseState version ${SUPPORTED_WEB_LOCAL_BACKUP_VERSION} only.`
    );
  }
  if (schemaVersion < SUPPORTED_WEB_LOCAL_BACKUP_VERSION) {
    throw new BackupValidationError(
      'invalid_snapshot_version',
      `Unsupported Web backup schema_version ${schemaVersion}. Only LocalDatabaseState version ${SUPPORTED_WEB_LOCAL_BACKUP_VERSION} is supported.`
    );
  }

  if (
    rawHeader.app_version !== undefined &&
    rawHeader.app_version !== null &&
    typeof rawHeader.app_version !== 'string'
  ) {
    throw new BackupValidationError(
      'invalid_backup_header',
      'Backup header app_version must be a string.'
    );
  }

  const salt = decodeRequiredBase64(rawHeader.salt_base64, 'salt_base64', {
    expectedLength: 16,
  });
  const iv = decodeRequiredBase64(rawHeader.nonce_base64, 'nonce_base64', {
    expectedLength: 12,
  });
  const mac = decodeRequiredBase64(rawHeader.mac_base64, 'mac_base64', {
    expectedLength: 16,
  });
  const ciphertext = decodeRequiredBase64(
    parsedEnvelope.ciphertext_base64,
    'ciphertext_base64',
    { minLength: 1 }
  );

  const rawChecksum = rawHeader.checksum_sha256;
  if (typeof rawChecksum !== 'string' || !SHA256_HEX_REGEX.test(rawChecksum.trim())) {
    throw new BackupValidationError(
      'invalid_backup_header',
      'Backup header checksum_sha256 must be a valid 64-character SHA-256 hex digest.'
    );
  }

  const normalizedChecksum = rawChecksum.trim().toLowerCase();
  const envelope: BackupEnvelope = {
    header: {
      format: ENCRYPTED_BACKUP_FORMAT,
      format_version: SUPPORTED_BACKUP_FORMAT_VERSION,
      app_version:
        typeof rawHeader.app_version === 'string' ? rawHeader.app_version : '1.0.0',
      schema_version: schemaVersion,
      created_at_utc:
        typeof rawHeader.created_at_utc === 'string' ? rawHeader.created_at_utc : '',
      kdf: SUPPORTED_BACKUP_KDF,
      iterations: SUPPORTED_BACKUP_PBKDF2_ITERATIONS,
      salt_base64: String(rawHeader.salt_base64).trim(),
      nonce_base64: String(rawHeader.nonce_base64).trim(),
      mac_base64: String(rawHeader.mac_base64).trim(),
      checksum_sha256: normalizedChecksum,
    },
    ciphertext_base64: String(parsedEnvelope.ciphertext_base64).trim(),
  };

  return {
    envelope,
    salt,
    iv,
    mac,
    ciphertext,
    checksumSha256: normalizedChecksum,
  };
}

/**
 * Encrypts a full LocalDatabaseState (v3) using a passphrase.
 * Produces an authenticated AES-GCM-256 envelope matching Dart specification.
 */
export async function encryptDatabaseBackup(
  state: LocalDatabaseState,
  passphrase: string
): Promise<string> {
  if (!passphrase || passphrase.trim().length === 0) {
    throw new BackupValidationError('authentication_failure', AUTHENTICATION_FAILURE_MESSAGE);
  }
  if (
    typeof state.version !== 'number' ||
    !Number.isInteger(state.version) ||
    state.version !== SUPPORTED_WEB_LOCAL_BACKUP_VERSION
  ) {
    throw new BackupValidationError(
      'invalid_snapshot_version',
      `Unsupported LocalDatabaseState version ${String(state.version)}; Web encrypted backups require version ${SUPPORTED_WEB_LOCAL_BACKUP_VERSION}.`
    );
  }

  const rawJson = JSON.stringify(state, null, 2);
  const enc = new TextEncoder();
  const plaintextBytes = enc.encode(rawJson);

  // 1. Generate 16-byte random salt and 12-byte random IV/Nonce
  const salt = new Uint8Array(16);
  crypto.getRandomValues(salt);

  const iv = new Uint8Array(12);
  crypto.getRandomValues(iv);

  // 2. Compute SHA-256 checksum of plaintext
  const checksumHex = await computeSha256(rawJson);

  // 3. Import passphrase as key material
  const baseKey = await crypto.subtle.importKey(
    'raw',
    enc.encode(passphrase),
    { name: 'PBKDF2' },
    false,
    ['deriveKey']
  );

  // 4. Derive AES-GCM 256-bit key with PBKDF2 (100,000 iterations)
  const iterations = SUPPORTED_BACKUP_PBKDF2_ITERATIONS;
  const derivedKey = await crypto.subtle.deriveKey(
    {
      name: 'PBKDF2',
      salt: salt.buffer as ArrayBuffer,
      iterations,
      hash: 'SHA-256',
    },
    baseKey,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt']
  );

  // 5. Encrypt with AES-GCM (appends 16-byte authentication tag at the end in Web Crypto)
  const encryptedBuffer = await crypto.subtle.encrypt(
    {
      name: 'AES-GCM',
      iv: iv.buffer as ArrayBuffer,
      tagLength: 128,
    },
    derivedKey,
    plaintextBytes.buffer as ArrayBuffer
  );

  const encryptedBytes = new Uint8Array(encryptedBuffer);
  const ciphertextBytes = encryptedBytes.slice(0, encryptedBytes.length - 16);
  const tagBytes = encryptedBytes.slice(encryptedBytes.length - 16);

  // 6. Build portable envelope
  const envelope: BackupEnvelope = {
    header: {
      format: ENCRYPTED_BACKUP_FORMAT,
      format_version: SUPPORTED_BACKUP_FORMAT_VERSION,
      app_version: '1.0.0',
      schema_version: state.version,
      created_at_utc: EthiopiaClock.nowUtc().toISOString(),
      kdf: SUPPORTED_BACKUP_KDF,
      iterations,
      salt_base64: toBase64(salt),
      nonce_base64: toBase64(iv),
      mac_base64: toBase64(tagBytes),
      checksum_sha256: checksumHex,
    },
    ciphertext_base64: toBase64(ciphertextBytes),
  };

  return JSON.stringify(envelope, null, 2);
}

/**
 * Decrypts and verifies an encrypted backup envelope using user's passphrase.
 * Enforces fail-closed envelope header validation and LocalDatabaseState v3 bounds.
 */
export async function decryptDatabaseBackup(
  envelopeString: string,
  passphrase: string
): Promise<{ state: LocalDatabaseState; checksum: string; header: BackupEnvelopeHeader }> {
  const validated = validateBackupEnvelopeHeader(envelopeString);
  const { envelope, salt, iv, mac, ciphertext, checksumSha256 } = validated;
  const { header } = envelope;

  if (!passphrase || passphrase.trim().length === 0) {
    throw new BackupValidationError(
      'authentication_failure',
      AUTHENTICATION_FAILURE_MESSAGE
    );
  }

  const enc = new TextEncoder();

  // Combine ciphertext and 16-byte MAC for Web Crypto AES-GCM
  const combined = new Uint8Array(ciphertext.length + mac.length);
  combined.set(ciphertext, 0);
  combined.set(mac, ciphertext.length);

  // 1. Re-derive key using exact validated parameters (no default fallback)
  const baseKey = await crypto.subtle.importKey(
    'raw',
    enc.encode(passphrase),
    { name: 'PBKDF2' },
    false,
    ['deriveKey']
  );

  const derivedKey = await crypto.subtle.deriveKey(
    {
      name: 'PBKDF2',
      salt: salt.buffer as ArrayBuffer,
      iterations: header.iterations,
      hash: 'SHA-256',
    },
    baseKey,
    { name: 'AES-GCM', length: 256 },
    false,
    ['decrypt']
  );

  // 2. Decrypt
  let decryptedBuffer: ArrayBuffer;
  try {
    decryptedBuffer = await crypto.subtle.decrypt(
      {
        name: 'AES-GCM',
        iv: iv.buffer as ArrayBuffer,
        tagLength: 128,
      },
      derivedKey,
      combined.buffer as ArrayBuffer
    );
  } catch {
    throw new BackupValidationError(
      'authentication_failure',
      AUTHENTICATION_FAILURE_MESSAGE
    );
  }

  // 3. Cryptographic integrity check against decrypted bytes BEFORE UTF-8 decoding
  const decryptedBytes = new Uint8Array(decryptedBuffer);
  const actualChecksum = (await computeSha256Bytes(decryptedBytes)).toLowerCase();
  if (actualChecksum !== checksumSha256) {
    throw new BackupValidationError(
      'integrity_failure',
      `Integrity check failed: Expected SHA-256 ${checksumSha256.slice(0, 8)}... but got ${actualChecksum.slice(0, 8)}...`
    );
  }

  let decryptedJson: string;
  try {
    const dec = new TextDecoder('utf-8', { fatal: true });
    decryptedJson = dec.decode(decryptedBytes);
  } catch {
    throw new BackupValidationError(
      'invalid_payload',
      'Decrypted backup payload is not valid UTF-8.'
    );
  }

  // 4. Parse database state & validate LocalDatabaseState v3
  let parsedState: unknown;
  try {
    parsedState = JSON.parse(decryptedJson);
  } catch {
    throw new BackupValidationError(
      'invalid_payload',
      'Decrypted backup payload is not valid JSON.'
    );
  }

  if (!isPlainObject(parsedState)) {
    throw new BackupValidationError(
      'invalid_payload',
      'Decrypted backup payload must be a JSON object.'
    );
  }

  if (!Object.prototype.hasOwnProperty.call(parsedState, 'version')) {
    throw new BackupValidationError(
      'invalid_snapshot_version',
      'Decrypted LocalDatabaseState payload is missing required version field.'
    );
  }

  const innerVersion = parsedState.version;
  if (typeof innerVersion !== 'number' || !Number.isInteger(innerVersion)) {
    throw new BackupValidationError(
      'invalid_snapshot_version',
      'Decrypted LocalDatabaseState version must be an integer.'
    );
  }
  if (innerVersion < 0) {
    throw new BackupValidationError(
      'invalid_snapshot_version',
      `Invalid LocalDatabaseState version ${innerVersion}: cannot be negative.`
    );
  }
  if (innerVersion > SUPPORTED_WEB_LOCAL_BACKUP_VERSION) {
    throw new BackupValidationError(
      'unsupported_future_schema',
      `Unsupported future LocalDatabaseState version ${innerVersion}. Web encrypted backups support version ${SUPPORTED_WEB_LOCAL_BACKUP_VERSION} only.`
    );
  }
  if (innerVersion < SUPPORTED_WEB_LOCAL_BACKUP_VERSION) {
    throw new BackupValidationError(
      'invalid_snapshot_version',
      `Unsupported LocalDatabaseState version ${innerVersion}. Only version ${SUPPORTED_WEB_LOCAL_BACKUP_VERSION} is supported.`
    );
  }
  if (innerVersion !== header.schema_version) {
    throw new BackupValidationError(
      'invalid_snapshot_version',
      `Backup header schema_version (${header.schema_version}) does not match inner payload version (${innerVersion}).`
    );
  }

  return {
    state: parsedState as unknown as LocalDatabaseState,
    checksum: actualChecksum,
    header,
  };
}

export function classifyBackupError(error: unknown): {
  kind: BackupFailureKind;
  message: string;
} {
  if (error instanceof BackupValidationError) {
    return { kind: error.kind, message: error.message };
  }
  if (error instanceof Error) {
    return { kind: 'invalid_payload', message: error.message };
  }
  return { kind: 'invalid_payload', message: 'Backup validation failed.' };
}
