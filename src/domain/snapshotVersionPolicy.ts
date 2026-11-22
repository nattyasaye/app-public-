import { BackupValidationError } from './backupTypes';

export const SNAPSHOT_VERSION_BOUNDS = {
  canonicalExchangeSchemaVersion: 5,
  supportedSnapshotFormatVersion: 2,
  legacyOmittedSnapshotFormatVersion: 1,
  minSupportedSnapshotFormatVersion: 1,
  maxSupportedSnapshotFormatVersion: 2,
  supportedFinanceSchemaVersion: 7,
  supportedDatabaseSchemaVersion: 10,
  maxSupportedDatabaseSchemaVersion: 10,
  minSupportedCanonicalSchemaVersion: 4,
  maxSupportedCanonicalSchemaVersion: 9,
  legacyOmittedSnapshotVersion: 5,
} as const;

export interface SnapshotVersionInterpretation {
  readonly schemaVersion: number;
  readonly snapshotFormatVersion: number;
  readonly databaseSchemaVersion?: number;
  readonly financeSchemaVersion?: number;
  readonly usesModernFinanceV7Rules: boolean;
}

/**
 * Interprets and validates canonical snapshot version metadata fail-closed.
 *
 * Separates exchange schemaVersion, snapshotFormatVersion, databaseSchemaVersion,
 * and financeSchemaVersion so format-2 snapshots (`snapshotFormatVersion: 2`)
 * enforce modern Finance v7 validation even when exchange `schemaVersion` is 5
 * and `financeSchemaVersion` is omitted (e.g. Android exports).
 */
export function interpretSnapshotVersions(
  record: Record<string, unknown>
): SnapshotVersionInterpretation {
  const hasSchemaVersion =
    Object.prototype.hasOwnProperty.call(record, 'schemaVersion') &&
    record.schemaVersion !== undefined;
  const hasVersion =
    Object.prototype.hasOwnProperty.call(record, 'version') &&
    record.version !== undefined;

  let parsedSchemaVersion: number | undefined;
  if (hasSchemaVersion) {
    const sv = record.schemaVersion;
    if (typeof sv !== 'number' || !Number.isInteger(sv)) {
      throw new BackupValidationError(
        'invalid_snapshot_version',
        'Snapshot schemaVersion must be a valid integer.'
      );
    }
    parsedSchemaVersion = sv;
  }

  let parsedVersion: number | undefined;
  if (hasVersion) {
    const v = record.version;
    if (typeof v !== 'number' || !Number.isInteger(v)) {
      throw new BackupValidationError(
        'invalid_snapshot_version',
        'Snapshot version must be a valid integer.'
      );
    }
    parsedVersion = v;
  }

  if (
    parsedSchemaVersion !== undefined &&
    parsedVersion !== undefined &&
    parsedSchemaVersion !== parsedVersion
  ) {
    throw new BackupValidationError(
      'invalid_snapshot_version',
      `Contradictory snapshot versions: schemaVersion=${parsedSchemaVersion} does not match version=${parsedVersion}.`
    );
  }

  let resolvedSnapshotFormatVersion: number =
    SNAPSHOT_VERSION_BOUNDS.legacyOmittedSnapshotFormatVersion;
  if (
    Object.prototype.hasOwnProperty.call(record, 'snapshotFormatVersion') &&
    record.snapshotFormatVersion !== undefined
  ) {
    const sfv = record.snapshotFormatVersion;
    if (typeof sfv !== 'number' || !Number.isInteger(sfv)) {
      throw new BackupValidationError(
        'invalid_snapshot_version',
        'Snapshot snapshotFormatVersion must be a valid integer.'
      );
    }
    if (sfv > SNAPSHOT_VERSION_BOUNDS.maxSupportedSnapshotFormatVersion) {
      throw new BackupValidationError(
        'unsupported_future_schema',
        `Unsupported future snapshotFormatVersion ${sfv} (maximum supported is ${SNAPSHOT_VERSION_BOUNDS.maxSupportedSnapshotFormatVersion}).`
      );
    }
    if (sfv < SNAPSHOT_VERSION_BOUNDS.minSupportedSnapshotFormatVersion) {
      throw new BackupValidationError(
        'invalid_snapshot_version',
        `Unsupported snapshotFormatVersion ${sfv}. Accepted values are ${SNAPSHOT_VERSION_BOUNDS.minSupportedSnapshotFormatVersion}..${SNAPSHOT_VERSION_BOUNDS.maxSupportedSnapshotFormatVersion}.`
      );
    }
    resolvedSnapshotFormatVersion = sfv;
  }

  const resolvedVersion =
    parsedSchemaVersion ??
    parsedVersion ??
    SNAPSHOT_VERSION_BOUNDS.legacyOmittedSnapshotVersion;

  if (resolvedVersion < 0) {
    throw new BackupValidationError(
      'invalid_snapshot_version',
      `Invalid snapshot version ${resolvedVersion}: cannot be negative.`
    );
  }
  if (resolvedVersion === 3) {
    throw new BackupValidationError(
      'invalid_snapshot_version',
      `Legacy LocalDatabaseState v3 payloads are distinct from SharedStateBridge canonical exchange snapshots (schemaVersion ${SNAPSHOT_VERSION_BOUNDS.minSupportedCanonicalSchemaVersion}..${SNAPSHOT_VERSION_BOUNDS.maxSupportedCanonicalSchemaVersion}) and cannot be imported here.`
    );
  }
  if (resolvedVersion > SNAPSHOT_VERSION_BOUNDS.maxSupportedCanonicalSchemaVersion) {
    throw new BackupValidationError(
      'unsupported_future_schema',
      `Unsupported future snapshot schemaVersion ${resolvedVersion} (maximum supported canonical version is ${SNAPSHOT_VERSION_BOUNDS.maxSupportedCanonicalSchemaVersion}).`
    );
  }
  if (resolvedVersion < SNAPSHOT_VERSION_BOUNDS.minSupportedCanonicalSchemaVersion) {
    throw new BackupValidationError(
      'invalid_snapshot_version',
      `Unsupported snapshot schemaVersion ${resolvedVersion}. Web SharedStateBridge accepts canonical schema versions ${SNAPSHOT_VERSION_BOUNDS.minSupportedCanonicalSchemaVersion}..${SNAPSHOT_VERSION_BOUNDS.maxSupportedCanonicalSchemaVersion}.`
    );
  }

  if (
    resolvedSnapshotFormatVersion >=
    SNAPSHOT_VERSION_BOUNDS.supportedSnapshotFormatVersion
  ) {
    if (!hasSchemaVersion) {
      throw new BackupValidationError(
        'invalid_snapshot_version',
        `Snapshot format v2 requires explicit canonical exchange schemaVersion ${SNAPSHOT_VERSION_BOUNDS.canonicalExchangeSchemaVersion}.`
      );
    }
    if (
      resolvedVersion !== SNAPSHOT_VERSION_BOUNDS.canonicalExchangeSchemaVersion
    ) {
      throw new BackupValidationError(
        'invalid_snapshot_version',
        `Snapshot format v2 requires canonical exchange schemaVersion ${SNAPSHOT_VERSION_BOUNDS.canonicalExchangeSchemaVersion} (got ${resolvedVersion}).`
      );
    }
  }

  let resolvedDatabaseSchemaVersion: number | undefined;
  if (
    Object.prototype.hasOwnProperty.call(record, 'databaseSchemaVersion') &&
    record.databaseSchemaVersion !== undefined
  ) {
    const dsv = record.databaseSchemaVersion;
    if (typeof dsv !== 'number' || !Number.isInteger(dsv)) {
      throw new BackupValidationError(
        'invalid_snapshot_version',
        'Snapshot databaseSchemaVersion must be a valid integer.'
      );
    }
    if (dsv < 1) {
      throw new BackupValidationError(
        'invalid_snapshot_version',
        `Invalid databaseSchemaVersion ${dsv}: must be >= 1.`
      );
    }
    if (dsv > SNAPSHOT_VERSION_BOUNDS.maxSupportedDatabaseSchemaVersion) {
      throw new BackupValidationError(
        'unsupported_future_schema',
        `Unsupported future databaseSchemaVersion ${dsv} (maximum supported is ${SNAPSHOT_VERSION_BOUNDS.maxSupportedDatabaseSchemaVersion}).`
      );
    }
    if (
      resolvedSnapshotFormatVersion >=
        SNAPSHOT_VERSION_BOUNDS.supportedSnapshotFormatVersion &&
      dsv !== 9 &&
      dsv !== SNAPSHOT_VERSION_BOUNDS.supportedDatabaseSchemaVersion
    ) {
      throw new BackupValidationError(
        'invalid_snapshot_version',
        `Snapshot format v2 requires databaseSchemaVersion 9 or ${SNAPSHOT_VERSION_BOUNDS.supportedDatabaseSchemaVersion} when specified (got ${dsv}).`
      );
    }
    resolvedDatabaseSchemaVersion = dsv;
  }

  let resolvedFinanceVersion: number | undefined;
  if (
    Object.prototype.hasOwnProperty.call(record, 'financeSchemaVersion') &&
    record.financeSchemaVersion !== undefined
  ) {
    const fv = record.financeSchemaVersion;
    if (typeof fv !== 'number' || !Number.isInteger(fv)) {
      throw new BackupValidationError(
        'invalid_snapshot_version',
        'Snapshot financeSchemaVersion must be a valid integer.'
      );
    }
    if (fv < 0) {
      throw new BackupValidationError(
        'invalid_snapshot_version',
        `Invalid financeSchemaVersion ${fv}: cannot be negative.`
      );
    }
    if (fv > SNAPSHOT_VERSION_BOUNDS.supportedFinanceSchemaVersion) {
      throw new BackupValidationError(
        'unsupported_future_schema',
        `Unsupported future financeSchemaVersion ${fv} (maximum supported is ${SNAPSHOT_VERSION_BOUNDS.supportedFinanceSchemaVersion}).`
      );
    }
    if (fv < SNAPSHOT_VERSION_BOUNDS.supportedFinanceSchemaVersion) {
      throw new BackupValidationError(
        'invalid_snapshot_version',
        `Unsupported financeSchemaVersion ${fv}. Expected ${SNAPSHOT_VERSION_BOUNDS.supportedFinanceSchemaVersion}.`
      );
    }
    resolvedFinanceVersion = fv;
  }

  const usesModernFinanceV7Rules =
    resolvedSnapshotFormatVersion >=
      SNAPSHOT_VERSION_BOUNDS.supportedSnapshotFormatVersion ||
    resolvedVersion >= SNAPSHOT_VERSION_BOUNDS.supportedFinanceSchemaVersion ||
    (resolvedFinanceVersion !== undefined &&
      resolvedFinanceVersion >=
        SNAPSHOT_VERSION_BOUNDS.supportedFinanceSchemaVersion);

  return {
    schemaVersion: resolvedVersion,
    snapshotFormatVersion: resolvedSnapshotFormatVersion,
    ...(resolvedDatabaseSchemaVersion !== undefined
      ? { databaseSchemaVersion: resolvedDatabaseSchemaVersion }
      : {}),
    ...(resolvedFinanceVersion !== undefined
      ? { financeSchemaVersion: resolvedFinanceVersion }
      : {}),
    usesModernFinanceV7Rules,
  };
}
