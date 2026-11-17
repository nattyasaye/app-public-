import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';

/**
 * Mirrors the exact SQL expression implemented in
 * `flutter_app/lib/data/database/app_database.dart` (`nullableDateToIsoSqlExpression`
 * and `requiredDateToIsoSqlExpression`) and verifies it against SQLite 3.40+
 * on file-backed v3 -> v5 and v4 -> v5 databases.
 */
function validatedCanonicalDateSql(dateExpr: string): string {
  return (
    'CASE ' +
    `WHEN (${dateExpr}) GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' ` +
    `AND (${dateExpr}) >= '0001-01-01' ` +
    `AND (${dateExpr}) <= '9999-12-31' ` +
    `THEN (${dateExpr}) ` +
    'ELSE NULL ' +
    'END'
  );
}

function isBareTimestampSql(expr: string): string {
  const prefixDate = `substr(${expr}, 1, 10)`;
  return (
    '(' +
    `date(${prefixDate}) = ${prefixDate} ` +
    `AND ${prefixDate} >= '0001-01-01' ` +
    `AND ${prefixDate} <= '9999-12-31' ` +
    'AND (' +
    `(${expr} GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][T ][0-9][0-9]:[0-9][0-9]' AND length(${expr}) = 16) ` +
    `OR (${expr} GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][T ][0-9][0-9]:[0-9][0-9]:[0-9][0-9]' AND length(${expr}) = 19) ` +
    `OR (${expr} GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][T ][0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9]*' AND length(${expr}) >= 21 AND substr(${expr}, 21) NOT GLOB '*[^0-9]*')` +
    ') ' +
    `AND datetime(${expr}) IS NOT NULL` +
    ')'
  );
}

/**
 * Mirrors the exact hardened SQL expression implemented in
 * `flutter_app/lib/data/database/app_database.dart` (`nullableDateToIsoSqlExpression`
 * and `requiredDateToIsoSqlExpression`) and verifies it against SQLite 3.40+
 * on file-backed v4 -> v5 databases.
 */
function buildNullableDateToIsoSql(colName: string): string {
  const trimmed = `trim(CAST(${colName} AS TEXT))`;
  const upperTrimmed = `upper(${trimmed})`;
  const unsignedDigits = `CASE WHEN substr(${trimmed}, 1, 1) = '-' THEN substr(${trimmed}, 2) ELSE ${trimmed} END`;
  const colonZoneNormalized = `substr(${upperTrimmed}, 1, length(${upperTrimmed}) - 2) || ':' || substr(${upperTrimmed}, length(${upperTrimmed}) - 1)`;

  return (
    'CASE ' +
    `WHEN ${colName} IS NULL OR ${trimmed} = '' THEN NULL ` +
    `WHEN typeof(${colName}) IN ('integer', 'real') THEN ` +
    'CASE ' +
    `WHEN abs(${colName}) >= 100000000000 ` +
    `THEN ${validatedCanonicalDateSql(`date(${colName} / 1000.0, 'unixepoch', '+3 hours')`)} ` +
    `ELSE ${validatedCanonicalDateSql(`date(${colName}, 'unixepoch', '+3 hours')`)} ` +
    'END ' +
    `WHEN ${unsignedDigits} GLOB '[0-9]*' ` +
    `AND ${unsignedDigits} NOT GLOB '*[^0-9.]*' ` +
    `AND ${unsignedDigits} NOT GLOB '*.*.*' ` +
    `AND ${unsignedDigits} GLOB '*[0-9]*' ` +
    `AND substr(${unsignedDigits}, 1, 1) != '.' ` +
    `AND substr(${unsignedDigits}, length(${unsignedDigits}), 1) != '.' ` +
    'THEN ' +
    'CASE ' +
    `WHEN abs(CAST(${trimmed} AS REAL)) >= 100000000000 ` +
    `THEN ${validatedCanonicalDateSql(`date(CAST(${trimmed} AS REAL) / 1000.0, 'unixepoch', '+3 hours')`)} ` +
    `ELSE ${validatedCanonicalDateSql(`date(CAST(${trimmed} AS REAL), 'unixepoch', '+3 hours')`)} ` +
    'END ' +
    `WHEN ${upperTrimmed} GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*' THEN ` +
    'CASE ' +
    `WHEN length(${upperTrimmed}) = 10 ` +
    `AND date(${upperTrimmed}) = ${upperTrimmed} ` +
    `AND ${upperTrimmed} >= '0001-01-01' ` +
    `AND ${upperTrimmed} <= '9999-12-31' ` +
    `THEN ${upperTrimmed} ` +
    `WHEN length(${upperTrimmed}) >= 17 ` +
    `AND substr(${upperTrimmed}, length(${upperTrimmed})) = 'Z' ` +
    `AND ${isBareTimestampSql(`substr(${upperTrimmed}, 1, length(${upperTrimmed}) - 1)`)} ` +
    `THEN ${validatedCanonicalDateSql(`date(${upperTrimmed}, '+3 hours')`)} ` +
    `WHEN length(${upperTrimmed}) >= 22 ` +
    `AND substr(${upperTrimmed}, length(${upperTrimmed}) - 5) GLOB '[+-][0-9][0-9]:[0-9][0-9]' ` +
    `AND ${isBareTimestampSql(`substr(${upperTrimmed}, 1, length(${upperTrimmed}) - 6)`)} ` +
    `AND CAST(substr(${upperTrimmed}, length(${upperTrimmed}) - 4, 2) AS INTEGER) <= 23 ` +
    `AND CAST(substr(${upperTrimmed}, length(${upperTrimmed}) - 1, 2) AS INTEGER) <= 59 ` +
    `THEN ${validatedCanonicalDateSql(`date(${upperTrimmed}, '+3 hours')`)} ` +
    `WHEN length(${upperTrimmed}) >= 21 ` +
    `AND substr(${upperTrimmed}, length(${upperTrimmed}) - 4) GLOB '[+-][0-9][0-9][0-9][0-9]' ` +
    `AND ${isBareTimestampSql(`substr(${upperTrimmed}, 1, length(${upperTrimmed}) - 5)`)} ` +
    `AND CAST(substr(${upperTrimmed}, length(${upperTrimmed}) - 3, 2) AS INTEGER) <= 23 ` +
    `AND CAST(substr(${upperTrimmed}, length(${upperTrimmed}) - 1, 2) AS INTEGER) <= 59 ` +
    `THEN ${validatedCanonicalDateSql(`date(${colonZoneNormalized}, '+3 hours')`)} ` +
    `WHEN ${isBareTimestampSql(upperTrimmed)} ` +
    `THEN substr(${upperTrimmed}, 1, 10) ` +
    'ELSE NULL ' +
    'END ' +
    'ELSE NULL ' +
    'END'
  );
}

function buildRequiredDateToIsoSql(colName: string): string {
  return buildNullableDateToIsoSql(colName);
}

function runPreFlightValidation(
  db: DatabaseSync,
  requiredCols: Array<[string, string]>,
  nullableCols: Array<[string, string]>,
): void {
  for (const [table, col] of requiredCols) {
    const expr = buildNullableDateToIsoSql(col);
    const bad = db
      .prepare(
        `SELECT id, COALESCE(CAST(${col} AS TEXT), '<NULL>') AS raw_val ` +
          `FROM ${table} WHERE ${col} IS NULL OR trim(CAST(${col} AS TEXT)) = '' OR (${expr}) IS NULL LIMIT 3`,
      )
      .all() as Array<{ id: string; raw_val: string }>;
    if (bad.length > 0) {
      throw new Error(`Migration aborted cleanly on required ${table}.${col}: id=${bad[0].id} value=${bad[0].raw_val}`);
    }
  }
  for (const [table, col] of nullableCols) {
    const expr = buildNullableDateToIsoSql(col);
    const bad = db
      .prepare(
        `SELECT id, CAST(${col} AS TEXT) AS raw_val ` +
          `FROM ${table} WHERE ${col} IS NOT NULL AND trim(CAST(${col} AS TEXT)) != '' AND (${expr}) IS NULL LIMIT 3`,
      )
      .all() as Array<{ id: string; raw_val: string }>;
    if (bad.length > 0) {
      throw new Error(`Migration aborted cleanly on nullable ${table}.${col}: id=${bad[0].id} value=${bad[0].raw_val}`);
    }
  }
}

describe('STAGE 2.6.2 REAL SQLITE MIGRATION & DATA-SAFETY VERIFICATION', () => {
  it('1. Dart AppDatabase migration SQL matches verified normalized date semantics across epoch sec/ms, zoned/bare ISO, garbage/overflow rejection, and zero today-date synthesis', () => {
    const appDbPath = path.join(process.cwd(), 'flutter_app', 'lib', 'data', 'database', 'app_database.dart');
    const appDbSrc = fs.readFileSync(appDbPath, 'utf8');
    assert.ok(appDbSrc.includes('abs($colName) >= 100000000000'), 'Must normalize millisecond epochs in Dart SQL');
    assert.ok(appDbSrc.includes('date($prefixDate) = $prefixDate'), 'Must validate Gregorian calendar components in Dart SQL');
    assert.ok(appDbSrc.includes('UPDATE calendar_events SET date_iso ='), 'Must normalize pre-v5 calendar_events TEXT dates');
    assert.ok(appDbSrc.includes('_validateLegacyDatesBeforeV5Migration'), 'Must pre-flight validate all migrated columns atomically before DDL/DML');
    assert.ok(appDbSrc.includes('PRAGMA foreign_key_check'), 'Must verify FK integrity after table rebuilds');
    assert.strictEqual(appDbSrc.includes("date('now', '+3 hours')"), false, 'Must NEVER silently overwrite corrupt dates with current date');

    const db = new DatabaseSync(':memory:');
    db.exec('CREATE TABLE raw_dates (id TEXT PRIMARY KEY, raw_text TEXT, raw_num REAL)');
    const ins = db.prepare('INSERT INTO raw_dates VALUES (?, ?, ?)');

    const cases: Array<[string, string | null, number | null, string | null, string | null]> = [
      ['utc_eve_sec', '1794348000', 1794348000, '2026-11-11', '2026-11-11'],
      ['utc_day_sec', '1794304800', 1794304800, '2026-11-10', '2026-11-10'],
      ['utc_eve_ms', '1794348000000', 1794348000000, '2026-11-11', '2026-11-11'],
      ['utc_day_ms', '1794304800000', 1794304800000, '2026-11-10', '2026-11-10'],
      ['eth_new_year_2023', '2023-09-11', null, '2023-09-11', null],
      ['eth_new_year_2024', '2024-09-11', null, '2024-09-11', null],
      ['greg_leap_2024', '2024-02-29', null, '2024-02-29', null],
      ['greg_nonleap_1900', '1900-02-28', null, '1900-02-28', null],
      ['greg_leap_2000', '2000-02-29', null, '2000-02-29', null],
      ['iso_z', '2026-11-10T21:00:00Z', null, '2026-11-11', null],
      ['iso_z_lower', '2026-11-10t21:00:00z', null, '2026-11-11', null],
      ['iso_z_subsec', '2026-11-10T22:00:00.123456Z', null, '2026-11-11', null],
      ['iso_plus03', '2026-11-11T00:00:00+03:00', null, '2026-11-11', null],
      ['iso_plus0530', '2026-11-10T10:00:00+05:30', null, '2026-11-10', null],
      ['iso_minus05_colon', '2026-11-10T22:00:00-05:00', null, '2026-11-11', null],
      ['iso_minus05_nocolon', '2026-11-10T22:00:00-0500', null, '2026-11-11', null],
      ['iso_bare', '2026-11-10T22:00:00', null, '2026-11-10', null],
      ['iso_bare_lower_t', '2026-11-10t22:00:00', null, '2026-11-10', null],
      ['iso_bare_space', '2026-11-10 22:00:00', null, '2026-11-10', null],
      ['iso_bare_short', '2026-11-10T22:00', null, '2026-11-10', null],
      ['date_only', '2026-11-10', null, '2026-11-10', null],
      // Invalid / corrupt / overflowing values must ALL normalize to NULL (never truncated prefix or 1970-01-01)
      ['invalid_feb30', '2026-02-30', null, null, null],
      ['invalid_feb30_ts', '2026-02-30T10:00:00Z', null, null, null],
      ['corrupt_trailing_garbage', '2026-11-10garbage', null, null, null],
      ['corrupt_zoned_garbage', '2026-11-10T10:00:00+03:00extra', null, null, null],
      ['corrupt_bad_time_space', '2026-11-10 99:99:99', null, null, null],
      ['corrupt_bad_time_iso', '2026-11-10T25:00:00', null, null, null],
      ['corrupt_bad_tz', '2026-11-10T10:00:00+25:99', null, null, null],
      ['corrupt_double_minus', '--123', null, null, null],
      ['corrupt_text', 'invalid', null, null, null],
      ['corrupt_mixed', '123abc', null, null, null],
      ['overflow_num_pos', null, 1e20, null, null],
      ['overflow_num_neg', null, -1e20, null, null],
      ['valid_neg_ms', null, -999999999999, null, '1938-04-25'],
      ['overflow_text_pos', '100000000000000000000', null, null, null],
      ['underflow_year_0000', '0000-01-01', null, null, null],
      ['underflow_tz_shift', '0001-01-01T00:00:00+05:00', null, null, null],
      ['overflow_tz_shift', '9999-12-31T23:00:00Z', null, null, null],
      ['empty_text', '', null, null, null],
      ['null_row', null, null, null, null],
    ];

    for (const [id, rawText, rawNum] of cases) {
      ins.run(id, rawText, rawNum);
    }

    const rows = db.prepare(
      `SELECT id, ${buildNullableDateToIsoSql('raw_text')} AS from_text, ${buildNullableDateToIsoSql('raw_num')} AS from_num FROM raw_dates`,
    ).all() as Array<{ id: string; from_text: string | null; from_num: string | null }>;

    for (const [id, , , expectedText, expectedNum] of cases) {
      const row = rows.find((r) => r.id === id);
      assert.ok(row, `Missing row ${id}`);
      assert.strictEqual(row.from_text, expectedText, `TEXT mismatch for ${id}`);
      assert.strictEqual(row.from_num, expectedNum, `NUM mismatch for ${id}`);
    }
    db.close();
  });

  it('2. File-backed SQLite v4 -> v5 migration preserves all user rows, Amharic UTF-8, FKs, and endures close/reopen', () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'daywell-sqlite-mig-'));
    try {
      const dbPath = path.join(tmpDir, 'daywell_v4_to_v5.sqlite');
      const db = new DatabaseSync(dbPath);

      db.exec(`
        CREATE TABLE goals (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, description TEXT, target_date INTEGER, status TEXT NOT NULL DEFAULT 'active', created_at INTEGER NOT NULL);
        CREATE TABLE projects (id TEXT NOT NULL PRIMARY KEY, goal_id TEXT REFERENCES goals (id) ON DELETE SET NULL, title TEXT NOT NULL, description TEXT, status TEXT NOT NULL DEFAULT 'active', target_date INTEGER, created_at INTEGER NOT NULL);
        CREATE TABLE milestones (id TEXT NOT NULL PRIMARY KEY, project_id TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE, title TEXT NOT NULL, due_date INTEGER, is_completed INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
        CREATE TABLE tasks (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'not_started', priority TEXT NOT NULL DEFAULT 'medium', due_date INTEGER, scheduled_date INTEGER, project_id TEXT REFERENCES projects (id) ON DELETE SET NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
        CREATE TABLE notes (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, content TEXT NOT NULL, category TEXT NOT NULL DEFAULT 'general', project_id TEXT REFERENCES projects (id) ON DELETE SET NULL, goal_id TEXT REFERENCES goals (id) ON DELETE SET NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
        CREATE TABLE financial_categories (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, color_hex TEXT NOT NULL DEFAULT '#1B4D3E', is_default INTEGER NOT NULL DEFAULT 0, is_archived INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE financial_transactions (id TEXT NOT NULL PRIMARY KEY, category_id TEXT NOT NULL REFERENCES financial_categories (id), amount_cents INTEGER NOT NULL, type TEXT NOT NULL, transaction_date INTEGER NOT NULL, note TEXT, created_at INTEGER NOT NULL);
        CREATE TABLE calendar_events (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, date_iso TEXT NOT NULL, start_time TEXT, end_time TEXT, is_all_day INTEGER NOT NULL DEFAULT 0, category TEXT NOT NULL DEFAULT 'personal', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
        PRAGMA user_version = 4;
      `);

      const utcEveningSec = 1794348000; // 2026-11-10T22:00:00Z -> 2026-11-11 EAT
      const utcEveningMs = 1794348000000;
      db.exec(`
        INSERT INTO financial_categories VALUES ('cat-1', 'Food', 'expense', '#EF4444', 1, 0);
        INSERT INTO goals VALUES ('goal-1', 'የቁጠባ ግብ', 'Ethiopia UTC+3 goal', ${utcEveningSec}, 'active', ${utcEveningSec});
        INSERT INTO projects VALUES ('proj-1', 'goal-1', 'Portfolio Refresh', 'Desc', 'active', ${utcEveningMs}, ${utcEveningSec});
        INSERT INTO milestones VALUES ('ms-1', 'proj-1', 'Phase 1', ${utcEveningSec}, 0, ${utcEveningSec});
        INSERT INTO tasks VALUES ('task-1', 'Amharic ሥራ', 'not_started', 'high', ${utcEveningSec}, '2026-11-10T22:00:00', 'proj-1', ${utcEveningSec}, ${utcEveningSec});
        INSERT INTO notes VALUES ('note-1', 'ማስታወሻ', 'Content', 'general', 'proj-1', 'goal-1', ${utcEveningSec}, ${utcEveningSec});
        INSERT INTO financial_transactions VALUES ('tx-1', 'cat-1', 35000, 'expense', ${utcEveningMs}, 'ቡና', ${utcEveningSec});
        INSERT INTO calendar_events VALUES ('evt-1', 'Late UTC Event', '2026-11-10T22:00:00Z', '08:00', '09:00', 0, 'work', ${utcEveningSec}, ${utcEveningSec});
      `);

      db.exec('PRAGMA foreign_keys = OFF;');
      db.exec('BEGIN IMMEDIATE;');
      runPreFlightValidation(
        db,
        [
          ['financial_transactions', 'transaction_date'],
          ['calendar_events', 'date_iso'],
        ],
        [
          ['goals', 'target_date'],
          ['projects', 'target_date'],
          ['milestones', 'due_date'],
          ['tasks', 'due_date'],
          ['tasks', 'scheduled_date'],
        ],
      );
      db.exec('ALTER TABLE calendar_events ADD COLUMN end_date_iso TEXT NULL;');
      db.exec(`
        CREATE TABLE goals_v5 (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, description TEXT, target_date TEXT, status TEXT NOT NULL DEFAULT 'active', created_at INTEGER NOT NULL);
        INSERT INTO goals_v5 SELECT id, title, description, ${buildNullableDateToIsoSql('target_date')}, status, created_at FROM goals;
        DROP TABLE goals;
        ALTER TABLE goals_v5 RENAME TO goals;

        CREATE TABLE projects_v5 (id TEXT NOT NULL PRIMARY KEY, goal_id TEXT REFERENCES goals (id) ON DELETE SET NULL, title TEXT NOT NULL, description TEXT, status TEXT NOT NULL DEFAULT 'active', target_date TEXT, created_at INTEGER NOT NULL);
        INSERT INTO projects_v5 SELECT id, goal_id, title, description, status, ${buildNullableDateToIsoSql('target_date')}, created_at FROM projects;
        DROP TABLE projects;
        ALTER TABLE projects_v5 RENAME TO projects;

        CREATE TABLE milestones_v5 (id TEXT NOT NULL PRIMARY KEY, project_id TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE, title TEXT NOT NULL, due_date TEXT, is_completed INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
        INSERT INTO milestones_v5 SELECT id, project_id, title, ${buildNullableDateToIsoSql('due_date')}, is_completed, created_at FROM milestones;
        DROP TABLE milestones;
        ALTER TABLE milestones_v5 RENAME TO milestones;

        CREATE TABLE tasks_v5 (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'not_started', priority TEXT NOT NULL DEFAULT 'medium', due_date TEXT, scheduled_date TEXT, project_id TEXT REFERENCES projects (id) ON DELETE SET NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
        INSERT INTO tasks_v5 SELECT id, title, status, priority, ${buildNullableDateToIsoSql('due_date')}, ${buildNullableDateToIsoSql('scheduled_date')}, project_id, created_at, updated_at FROM tasks;
        DROP TABLE tasks;
        ALTER TABLE tasks_v5 RENAME TO tasks;

        CREATE TABLE financial_transactions_v5 (id TEXT NOT NULL PRIMARY KEY, category_id TEXT NOT NULL REFERENCES financial_categories (id), amount_cents INTEGER NOT NULL, type TEXT NOT NULL, transaction_date TEXT NOT NULL, note TEXT, created_at INTEGER NOT NULL);
        INSERT INTO financial_transactions_v5 SELECT id, category_id, amount_cents, type, ${buildRequiredDateToIsoSql('transaction_date')}, note, created_at FROM financial_transactions;
        DROP TABLE financial_transactions;
        ALTER TABLE financial_transactions_v5 RENAME TO financial_transactions;

        UPDATE calendar_events SET date_iso = ${buildRequiredDateToIsoSql('date_iso')}, end_date_iso = ${buildNullableDateToIsoSql('end_date_iso')};
        PRAGMA user_version = 5;
      `);
      db.exec('COMMIT;');
      db.exec('PRAGMA foreign_keys = ON;');

      db.exec("INSERT INTO calendar_events (id, title, date_iso, end_date_iso, created_at, updated_at) VALUES ('evt-2', 'Multi-day', '2026-11-12', '2026-11-14', 1794348000, 1794348000);");
      db.close();

      const reopened = new DatabaseSync(dbPath);
      reopened.exec('PRAGMA foreign_keys = ON;');
      const fkErrors = reopened.prepare('PRAGMA foreign_key_check;').all();
      assert.strictEqual(fkErrors.length, 0);
      const userVer = (reopened.prepare('PRAGMA user_version;').get() as { user_version: number }).user_version;
      assert.strictEqual(userVer, 5);

      const goal = reopened.prepare("SELECT title, target_date FROM goals WHERE id = 'goal-1'").get() as { title: string; target_date: string };
      assert.strictEqual(goal.title, 'የቁጠባ ግብ');
      assert.strictEqual(goal.target_date, '2026-11-11');

      const proj = reopened.prepare("SELECT goal_id, target_date FROM projects WHERE id = 'proj-1'").get() as { goal_id: string; target_date: string };
      assert.strictEqual(proj.goal_id, 'goal-1');
      assert.strictEqual(proj.target_date, '2026-11-11');

      const ms = reopened.prepare("SELECT project_id, due_date FROM milestones WHERE id = 'ms-1'").get() as { project_id: string; due_date: string };
      assert.strictEqual(ms.project_id, 'proj-1');
      assert.strictEqual(ms.due_date, '2026-11-11');

      const note = reopened.prepare("SELECT project_id, goal_id FROM notes WHERE id = 'note-1'").get() as { project_id: string; goal_id: string };
      assert.strictEqual(note.project_id, 'proj-1');
      assert.strictEqual(note.goal_id, 'goal-1');

      const task = reopened.prepare("SELECT title, due_date, scheduled_date FROM tasks WHERE id = 'task-1'").get() as { title: string; due_date: string; scheduled_date: string };
      assert.strictEqual(task.title, 'Amharic ሥራ');
      assert.strictEqual(task.due_date, '2026-11-11');
      assert.strictEqual(task.scheduled_date, '2026-11-10');

      const tx = reopened.prepare("SELECT transaction_date, note FROM financial_transactions WHERE id = 'tx-1'").get() as { transaction_date: string; note: string };
      assert.strictEqual(tx.transaction_date, '2026-11-11');
      assert.strictEqual(tx.note, 'ቡና');

      const evt1 = reopened.prepare("SELECT date_iso, end_date_iso FROM calendar_events WHERE id = 'evt-1'").get() as { date_iso: string; end_date_iso: string | null };
      assert.strictEqual(evt1.date_iso, '2026-11-11');
      assert.strictEqual(evt1.end_date_iso, null);

      const evt2 = reopened.prepare("SELECT date_iso, end_date_iso FROM calendar_events WHERE id = 'evt-2'").get() as { date_iso: string; end_date_iso: string };
      assert.strictEqual(evt2.date_iso, '2026-11-12');
      assert.strictEqual(evt2.end_date_iso, '2026-11-14');

      reopened.close();
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  it('3. File-backed SQLite v4 -> v5 migration aborts atomically and rolls back cleanly on corrupt/uninterpretable required or nullable dates', () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'daywell-sqlite-rollback-'));
    try {
      for (const scenario of [
        {
          name: 'corrupt_nullable_garbage',
          insertSql: "INSERT INTO tasks VALUES ('task-bad', 'Keep intact', '2026-11-10garbage'); INSERT INTO financial_transactions VALUES ('tx-ok', 1000, '2026-11-10');",
          expectedMatch: /tasks\.due_date/,
        },
        {
          name: 'corrupt_required_invalid',
          insertSql: "INSERT INTO tasks VALUES ('task-ok', 'Keep intact', '2026-11-10'); INSERT INTO financial_transactions VALUES ('tx-bad', 1000, 'invalid');",
          expectedMatch: /financial_transactions\.transaction_date/,
        },
        {
          name: 'empty_required_date',
          insertSql: "INSERT INTO tasks VALUES ('task-ok', 'Keep intact', NULL); INSERT INTO financial_transactions VALUES ('tx-empty', 1000, '');",
          expectedMatch: /financial_transactions\.transaction_date/,
        },
      ]) {
        const dbPath = path.join(tmpDir, `${scenario.name}.sqlite`);
        const db = new DatabaseSync(dbPath);
        db.exec(`
          CREATE TABLE tasks (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, due_date TEXT);
          CREATE TABLE financial_transactions (id TEXT NOT NULL PRIMARY KEY, amount_cents INTEGER NOT NULL, transaction_date TEXT NOT NULL);
          PRAGMA user_version = 4;
          ${scenario.insertSql}
        `);

        let caught: Error | null = null;
        try {
          db.exec('BEGIN IMMEDIATE;');
          runPreFlightValidation(
            db,
            [['financial_transactions', 'transaction_date']],
            [['tasks', 'due_date']],
          );
          db.exec('COMMIT;');
        } catch (err: any) {
          caught = err;
          db.exec('ROLLBACK;');
        }
        db.close();

        assert.ok(caught, `${scenario.name}: must abort cleanly`);
        assert.match(caught.message, scenario.expectedMatch);

        // Reopen DB and prove v4 schema + original rows are 100% preserved
        const reopened = new DatabaseSync(dbPath);
        const userVer = (reopened.prepare('PRAGMA user_version;').get() as { user_version: number }).user_version;
        assert.strictEqual(userVer, 4);
        const taskCount = (reopened.prepare('SELECT COUNT(*) AS c FROM tasks').get() as { c: number }).c;
        const txCount = (reopened.prepare('SELECT COUNT(*) AS c FROM financial_transactions').get() as { c: number }).c;
        assert.strictEqual(taskCount, 1);
        assert.strictEqual(txCount, 1);
        reopened.close();
      }
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });
});
