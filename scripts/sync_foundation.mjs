#!/usr/bin/env node
import fs from 'fs';
import path from 'path';
import { execFileSync } from 'child_process';
import { fileURLToPath, pathToFileURL } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const defaultRootDir = path.resolve(__dirname, '..');

const HEX_COLOR_REGEX = /^#[0-9A-Fa-f]{6}$/;

const COLOR_SCHEMA = {
  primary: ['emerald', 'emeraldDark', 'emeraldLight', 'darkMode', 'onLight', 'onDark'],
  secondary: ['mint', 'mintDark', 'mintLight', 'onLight', 'onDark'],
  surface: [
    'canvasLight',
    'canvasDark',
    'subtleLight',
    'subtleDark',
    'cardLight',
    'cardDark',
    'elevatedLight',
    'elevatedDark',
    'borderLight',
    'borderDark',
    'dividerLight',
    'dividerDark',
  ],
  text: [
    'primaryLight',
    'primaryDark',
    'secondaryLight',
    'secondaryDark',
    'mutedLight',
    'mutedDark',
    'disabledLight',
    'disabledDark',
  ],
  semantic: [
    'income',
    'onIncome',
    'incomeContainerLight',
    'onIncomeContainerLight',
    'incomeContainerDark',
    'onIncomeContainerDark',
    'expense',
    'onExpense',
    'expenseContainerLight',
    'onExpenseContainerLight',
    'expenseContainerDark',
    'onExpenseContainerDark',
    'transfer',
    'onTransfer',
    'transferContainerLight',
    'onTransferContainerLight',
    'transferContainerDark',
    'onTransferContainerDark',
    'success',
    'onSuccess',
    'successContainerLight',
    'onSuccessContainerLight',
    'successContainerDark',
    'onSuccessContainerDark',
    'error',
    'onError',
    'errorContainerLight',
    'onErrorContainerLight',
    'errorContainerDark',
    'onErrorContainerDark',
    'warning',
    'onWarning',
    'warningContainerLight',
    'onWarningContainerLight',
    'warningContainerDark',
    'onWarningContainerDark',
    'info',
    'onInfo',
    'infoContainerLight',
    'onInfoContainerLight',
    'infoContainerDark',
    'onInfoContainerDark',
  ],
};

const TYPOGRAPHY_SCALE_KEYS = [
  'display',
  'heading',
  'title',
  'body',
  'bodyCompact',
  'label',
  'caption',
  'numericHero',
  'numericBody',
  'mono',
];

const SPACING_KEYS = ['xs', 'sm', 'compact', 'md', 'lg', 'xl'];
const RADII_KEYS = ['sm', 'md', 'lg', 'xl', 'sheet', 'full'];
const ELEVATION_KEYS = ['none', 'low', 'medium', 'high'];
const BREAKPOINT_KEYS = ['medium', 'expanded', 'maxContentWidth', 'maxWideWidth'];
const ALLOWED_FONT_ROLES = new Set(['serif', 'sans', 'mono']);
const ALLOWED_FONT_WEIGHTS = new Set([100, 200, 300, 400, 500, 600, 700, 800, 900]);

const ISO_DATE_REGEX = /^\d{4}-\d{2}-\d{2}$/;
const ALLOWED_SCHEMA_TYPES = new Set(['string', 'number', 'integer', 'boolean', 'array', 'object']);

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function assertNonEmptyString(value, label) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error(`Invalid token "${label}": expected non-empty string.`);
  }
}

function assertFieldNonEmptyString(value, fileLabel, fieldLabel) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error(`Invalid ${fileLabel} field "${fieldLabel}": expected non-empty string.`);
  }
}

function assertFieldBoolean(value, fileLabel, fieldLabel) {
  if (typeof value !== 'boolean') {
    throw new Error(
      `Invalid ${fileLabel} field "${fieldLabel}": expected boolean, got ${typeof value}.`
    );
  }
}

function assertFieldInteger(value, fileLabel, fieldLabel, { min = -Infinity, max = Infinity } = {}) {
  if (typeof value !== 'number' || !Number.isInteger(value)) {
    throw new Error(
      `Invalid ${fileLabel} field "${fieldLabel}": expected integer, got ${JSON.stringify(value)}.`
    );
  }
  if (value < min || value > max) {
    throw new Error(
      `Invalid ${fileLabel} field "${fieldLabel}": expected integer in [${min}, ${max}], got ${value}.`
    );
  }
}

function assertValidIsoDate(value, fileLabel, fieldLabel) {
  assertFieldNonEmptyString(value, fileLabel, fieldLabel);
  if (!ISO_DATE_REGEX.test(value)) {
    throw new Error(
      `Invalid ${fileLabel} field "${fieldLabel}": expected YYYY-MM-DD, got ${JSON.stringify(value)}.`
    );
  }
  const [yStr, mStr, dStr] = value.split('-');
  const year = Number(yStr);
  const month = Number(mStr);
  const day = Number(dStr);
  if (month < 1 || month > 12) {
    throw new Error(`Invalid ${fileLabel} field "${fieldLabel}": month out of range in "${value}".`);
  }
  const maxDay = daysInGregorianMonth(year, month);
  if (day < 1 || day > maxDay) {
    throw new Error(`Invalid ${fileLabel} field "${fieldLabel}": day out of range in "${value}".`);
  }
}

function isGregorianLeapYear(year) {
  return (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
}

function daysInGregorianMonth(year, month) {
  if (month === 2) return isGregorianLeapYear(year) ? 29 : 28;
  if ([4, 6, 9, 11].includes(month)) return 30;
  return 31;
}

function isEthiopianLeapYear(year) {
  return year % 4 === 3;
}

function assertValidEthiopianDateObj(value, fileLabel, fieldLabel) {
  if (!isPlainObject(value)) {
    throw new Error(`Invalid ${fileLabel} field "${fieldLabel}": expected Ethiopian date object.`);
  }
  assertFieldInteger(value.year, fileLabel, `${fieldLabel}.year`, { min: 1 });
  assertFieldInteger(value.month, fileLabel, `${fieldLabel}.month`, { min: 1, max: 13 });
  const maxDay = value.month === 13 ? (isEthiopianLeapYear(value.year) ? 6 : 5) : 30;
  assertFieldInteger(value.day, fileLabel, `${fieldLabel}.day`, { min: 1, max: maxDay });
}

function assertFiniteNumber(value, label, { min = -Infinity, exclusiveMin = false } = {}) {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new Error(`Invalid token "${label}": expected finite number, got ${typeof value}.`);
  }
  if (exclusiveMin ? value <= min : value < min) {
    throw new Error(
      `Invalid token "${label}": expected number ${exclusiveMin ? '>' : '>='} ${min}, got ${value}.`
    );
  }
}

function assertHexColor(value, label) {
  if (typeof value !== 'string' || !HEX_COLOR_REGEX.test(value)) {
    throw new Error(`Invalid color token "${label}": expected #RRGGBB hex string, got ${JSON.stringify(value)}.`);
  }
}

export function validateDesignTokens(tokens, { allowedRemovals = new Set() } = {}) {
  if (!isPlainObject(tokens)) {
    throw new Error('Design tokens root must be a JSON object.');
  }
  assertNonEmptyString(tokens.version, 'version');
  assertNonEmptyString(tokens.name, 'name');

  if (!isPlainObject(tokens.colors)) {
    throw new Error('Missing or invalid "colors" object in design tokens.');
  }

  for (const [group, keys] of Object.entries(COLOR_SCHEMA)) {
    const groupObj = tokens.colors[group];
    if (!isPlainObject(groupObj)) {
      throw new Error(`Missing or invalid "colors.${group}" object in design tokens.`);
    }
    for (const key of keys) {
      const target = `design_tokens.colors.${group}.${key}`;
      if (!(key in groupObj)) {
        if (allowedRemovals.has(target)) {
          continue;
        }
        throw new Error(`Missing required color token "colors.${group}.${key}".`);
      }
      assertHexColor(groupObj[key], `colors.${group}.${key}`);
    }
    for (const key of Object.keys(groupObj)) {
      assertHexColor(groupObj[key], `colors.${group}.${key}`);
    }
  }

  if (!isPlainObject(tokens.typography)) {
    throw new Error('Missing or invalid "typography" object in design tokens.');
  }
  if (!allowedRemovals.has('design_tokens.typography.fontFamilySerif')) {
    assertNonEmptyString(tokens.typography.fontFamilySerif, 'typography.fontFamilySerif');
  }
  if (!allowedRemovals.has('design_tokens.typography.fontFamilySans')) {
    assertNonEmptyString(tokens.typography.fontFamilySans, 'typography.fontFamilySans');
  }
  if (!allowedRemovals.has('design_tokens.typography.fontFamilyMono')) {
    assertNonEmptyString(tokens.typography.fontFamilyMono, 'typography.fontFamilyMono');
  }

  if (!isPlainObject(tokens.typography.scale)) {
    throw new Error('Missing or invalid "typography.scale" object in design tokens.');
  }
  for (const role of TYPOGRAPHY_SCALE_KEYS) {
    const target = `design_tokens.typography.scale.${role}`;
    if (!(role in tokens.typography.scale) && allowedRemovals.has(target)) {
      continue;
    }
    const entry = tokens.typography.scale[role];
    if (!isPlainObject(entry)) {
      throw new Error(`Missing or invalid "typography.scale.${role}" object.`);
    }
    assertFiniteNumber(entry.fontSize, `typography.scale.${role}.fontSize`, { min: 0, exclusiveMin: true });
    assertFiniteNumber(entry.lineHeight, `typography.scale.${role}.lineHeight`, { min: entry.fontSize });
    if (typeof entry.fontWeight !== 'number' || !ALLOWED_FONT_WEIGHTS.has(entry.fontWeight)) {
      throw new Error(
        `Invalid token "typography.scale.${role}.fontWeight": expected 100..900 step 100, got ${JSON.stringify(entry.fontWeight)}.`
      );
    }
    assertFiniteNumber(entry.letterSpacing, `typography.scale.${role}.letterSpacing`);
    if (typeof entry.fontFamily !== 'string' || !ALLOWED_FONT_ROLES.has(entry.fontFamily)) {
      throw new Error(
        `Invalid token "typography.scale.${role}.fontFamily": expected serif|sans|mono, got ${JSON.stringify(entry.fontFamily)}.`
      );
    }
    if (typeof entry.tabularFigures !== 'boolean') {
      throw new Error(
        `Invalid token "typography.scale.${role}.tabularFigures": expected boolean, got ${typeof entry.tabularFigures}.`
      );
    }
  }

  for (const [sectionName, requiredKeys, minOpts] of [
    ['spacing', SPACING_KEYS, { min: 0 }],
    ['radii', RADII_KEYS, { min: 0 }],
    ['elevation', ELEVATION_KEYS, { min: 0 }],
    ['breakpoints', BREAKPOINT_KEYS, { min: 0, exclusiveMin: true }],
  ]) {
    const sectionObj = tokens[sectionName];
    if (!isPlainObject(sectionObj)) {
      throw new Error(`Missing or invalid "${sectionName}" object in design tokens.`);
    }
    for (const key of requiredKeys) {
      const target = `design_tokens.${sectionName}.${key}`;
      if (!(key in sectionObj)) {
        if (allowedRemovals.has(target)) {
          continue;
        }
        throw new Error(`Missing required token "${sectionName}.${key}".`);
      }
      assertFiniteNumber(sectionObj[key], `${sectionName}.${key}`, minOpts);
    }
  }

  if (
    typeof tokens.breakpoints.expanded === 'number' &&
    typeof tokens.breakpoints.medium === 'number' &&
    tokens.breakpoints.expanded <= tokens.breakpoints.medium
  ) {
    throw new Error('Invalid breakpoints: "breakpoints.expanded" must exceed "breakpoints.medium".');
  }
  if (
    typeof tokens.breakpoints.maxWideWidth === 'number' &&
    typeof tokens.breakpoints.maxContentWidth === 'number' &&
    tokens.breakpoints.maxWideWidth < tokens.breakpoints.maxContentWidth
  ) {
    throw new Error('Invalid breakpoints: "breakpoints.maxWideWidth" must be >= "breakpoints.maxContentWidth".');
  }

  return tokens;
}

export function validateBusinessRules(rules) {
  const fileLabel = 'business_rules.json';
  if (!isPlainObject(rules)) {
    throw new Error(`${fileLabel} root must be a JSON object.`);
  }
  assertFieldNonEmptyString(rules.version, fileLabel, 'version');

  if (!isPlainObject(rules.finance)) {
    throw new Error(`Missing or invalid "finance" object in ${fileLabel}.`);
  }
  assertFieldNonEmptyString(rules.finance.currencyCode, fileLabel, 'finance.currencyCode');
  if (rules.finance.currencyCode !== 'ETB') {
    throw new Error(
      `Invalid ${fileLabel} field "finance.currencyCode": expected "ETB", got ${JSON.stringify(rules.finance.currencyCode)}.`
    );
  }
  assertFieldInteger(rules.finance.minorUnitsPerMajor, fileLabel, 'finance.minorUnitsPerMajor', {
    min: 100,
    max: 100,
  });

  if (!isPlainObject(rules.finance.rules)) {
    throw new Error(`Missing or invalid "finance.rules" object in ${fileLabel}.`);
  }
  for (const ruleFlag of [
    'integerCentsOnly',
    'rejectZeroOrNegativeAmount',
    'rejectIdenticalTransferAccounts',
    'transferPreservesCombinedBalance',
    'guardAccountDeletionIfTransactionsExist',
    'guardCategoryDeletionIfTransactionsExist',
  ]) {
    assertFieldBoolean(rules.finance.rules[ruleFlag], fileLabel, `finance.rules.${ruleFlag}`);
  }

  if (!isPlainObject(rules.finance.formulas)) {
    throw new Error(`Missing or invalid "finance.formulas" object in ${fileLabel}.`);
  }
  assertFieldNonEmptyString(
    rules.finance.formulas.accountBalance,
    fileLabel,
    'finance.formulas.accountBalance'
  );
  assertFieldNonEmptyString(
    rules.finance.formulas.combinedBalance,
    fileLabel,
    'finance.formulas.combinedBalance'
  );

  if (!isPlainObject(rules.tasks)) {
    throw new Error(`Missing or invalid "tasks" object in ${fileLabel}.`);
  }
  if (!isPlainObject(rules.tasks.priorityWeights)) {
    throw new Error(`Missing or invalid "tasks.priorityWeights" object in ${fileLabel}.`);
  }
  for (const p of ['urgent', 'high', 'medium', 'low']) {
    assertFieldInteger(rules.tasks.priorityWeights[p], fileLabel, `tasks.priorityWeights.${p}`, {
      min: 1,
    });
  }
  const pw = rules.tasks.priorityWeights;
  if (!(pw.urgent > pw.high && pw.high > pw.medium && pw.medium > pw.low)) {
    throw new Error(
      `Invalid ${fileLabel} field "tasks.priorityWeights": expected urgent > high > medium > low.`
    );
  }
  assertFieldNonEmptyString(rules.tasks.defaultPriority, fileLabel, 'tasks.defaultPriority');
  if (!(rules.tasks.defaultPriority in pw)) {
    throw new Error(
      `Invalid ${fileLabel} field "tasks.defaultPriority": "${rules.tasks.defaultPriority}" is not in priorityWeights.`
    );
  }
  assertFieldNonEmptyString(rules.tasks.defaultStatus, fileLabel, 'tasks.defaultStatus');

  if (!isPlainObject(rules.calendar)) {
    throw new Error(`Missing or invalid "calendar" object in ${fileLabel}.`);
  }
  assertFieldNonEmptyString(rules.calendar.system, fileLabel, 'calendar.system');
  assertFieldInteger(rules.calendar.monthsCount, fileLabel, 'calendar.monthsCount', { min: 13, max: 13 });
  assertFieldInteger(rules.calendar.standardMonthDays, fileLabel, 'calendar.standardMonthDays', {
    min: 30,
    max: 30,
  });
  assertFieldInteger(rules.calendar.pagumeStandardDays, fileLabel, 'calendar.pagumeStandardDays', {
    min: 5,
    max: 5,
  });
  assertFieldInteger(rules.calendar.pagumeLeapDays, fileLabel, 'calendar.pagumeLeapDays', {
    min: 6,
    max: 6,
  });
  assertFieldNonEmptyString(rules.calendar.pagumeLeapRule, fileLabel, 'calendar.pagumeLeapRule');
  if (rules.calendar.canonicalDateFormat !== 'YYYY-MM-DD') {
    throw new Error(
      `Invalid ${fileLabel} field "calendar.canonicalDateFormat": expected "YYYY-MM-DD", got ${JSON.stringify(rules.calendar.canonicalDateFormat)}.`
    );
  }
  assertFieldNonEmptyString(rules.calendar.timeConvention, fileLabel, 'calendar.timeConvention');
  assertFieldInteger(rules.calendar.fixedUtcOffsetMinutes, fileLabel, 'calendar.fixedUtcOffsetMinutes', {
    min: 180,
    max: 180,
  });

  if (!isPlainObject(rules.projects)) {
    throw new Error(`Missing or invalid "projects" object in ${fileLabel}.`);
  }
  for (const listKey of ['statuses', 'blockTypes', 'recordTypes', 'customFieldTypes']) {
    if (!Array.isArray(rules.projects[listKey]) || rules.projects[listKey].length === 0) {
      throw new Error(`Missing or empty "${fileLabel}" array "projects.${listKey}".`);
    }
    for (let i = 0; i < rules.projects[listKey].length; i += 1) {
      assertFieldNonEmptyString(rules.projects[listKey][i], fileLabel, `projects.${listKey}[${i}]`);
    }
  }
  if (!isPlainObject(rules.projects.bounds)) {
    throw new Error(`Missing or invalid "projects.bounds" object in ${fileLabel}.`);
  }
  for (const boundKey of [
    'maxBlocksPerProject',
    'maxCustomFieldDefinitions',
    'maxCustomFieldSelectOptions',
    'maxCustomFieldIdLength',
    'maxCustomFieldTextLength',
    'maxHierarchyDepth',
  ]) {
    assertFieldInteger(rules.projects.bounds[boundKey], fileLabel, `projects.bounds.${boundKey}`, {
      min: 1,
    });
  }
  if (!isPlainObject(rules.projects.rules)) {
    throw new Error(`Missing or invalid "projects.rules" object in ${fileLabel}.`);
  }
  for (const flagKey of [
    'appendOnlyProgressLogs',
    'allowCompensatingCorrections',
    'allowMultipleIndependentMetrics',
    'disallowImplicitMetricAveraging',
    'requiresExplicitPrimaryBlockForOverallPercent',
    'requirePositiveProgressLogDelta',
    'preventDuplicateRollupLogging',
    'enforceParentChildOwnership',
  ]) {
    assertFieldBoolean(rules.projects.rules[flagKey], fileLabel, `projects.rules.${flagKey}`);
  }

  return rules;
}

export function validateSchemaContracts(contracts) {
  const fileLabel = 'schema_contracts.json';
  if (!isPlainObject(contracts)) {
    throw new Error(`${fileLabel} root must be a JSON object.`);
  }
  assertFieldNonEmptyString(contracts.version, fileLabel, 'version');
  assertFieldInteger(contracts.schemaVersion, fileLabel, 'schemaVersion', { min: 1 });

  if (!isPlainObject(contracts.timeConvention)) {
    throw new Error(`Missing or invalid "timeConvention" object in ${fileLabel}.`);
  }
  assertFieldNonEmptyString(contracts.timeConvention.id, fileLabel, 'timeConvention.id');
  assertFieldInteger(
    contracts.timeConvention.fixedUtcOffsetMinutes,
    fileLabel,
    'timeConvention.fixedUtcOffsetMinutes',
    { min: 180, max: 180 }
  );
  assertFieldNonEmptyString(
    contracts.timeConvention.fixedUtcOffsetLabel,
    fileLabel,
    'timeConvention.fixedUtcOffsetLabel'
  );
  assertFieldBoolean(contracts.timeConvention.observesDst, fileLabel, 'timeConvention.observesDst');
  if (contracts.timeConvention.observesDst !== false) {
    throw new Error(`Invalid ${fileLabel} field "timeConvention.observesDst": Ethiopia UTC+3 must be false.`);
  }

  if (!isPlainObject(contracts.entities) || Object.keys(contracts.entities).length === 0) {
    throw new Error(`Missing or empty "entities" object in ${fileLabel}.`);
  }

  for (const [entityName, entityDef] of Object.entries(contracts.entities)) {
    if (!isPlainObject(entityDef)) {
      throw new Error(`Invalid ${fileLabel} entity "entities.${entityName}": expected object.`);
    }
    if (!isPlainObject(entityDef.fields) || Object.keys(entityDef.fields).length === 0) {
      throw new Error(`Missing or empty "entities.${entityName}.fields" in ${fileLabel}.`);
    }
    for (const [fieldName, fieldDef] of Object.entries(entityDef.fields)) {
      const fieldPath = `entities.${entityName}.fields.${fieldName}`;
      if (!isPlainObject(fieldDef)) {
        throw new Error(`Invalid ${fileLabel} field "${fieldPath}": expected object.`);
      }
      if (typeof fieldDef.type !== 'string' || !ALLOWED_SCHEMA_TYPES.has(fieldDef.type)) {
        throw new Error(
          `Invalid ${fileLabel} field "${fieldPath}.type": expected one of ${Array.from(ALLOWED_SCHEMA_TYPES).join('|')}, got ${JSON.stringify(fieldDef.type)}.`
        );
      }
      if (fieldDef.required !== undefined && typeof fieldDef.required !== 'boolean') {
        throw new Error(`Invalid ${fileLabel} field "${fieldPath}.required": expected boolean.`);
      }
      if (fieldDef.enum !== undefined) {
        if (!Array.isArray(fieldDef.enum) || fieldDef.enum.length === 0) {
          throw new Error(`Invalid ${fileLabel} field "${fieldPath}.enum": expected non-empty array.`);
        }
        if (new Set(fieldDef.enum).size !== fieldDef.enum.length) {
          throw new Error(`Invalid ${fileLabel} field "${fieldPath}.enum": contains duplicate values.`);
        }
        if (fieldDef.default !== undefined && !fieldDef.enum.includes(fieldDef.default)) {
          throw new Error(
            `Invalid ${fileLabel} field "${fieldPath}.default": "${fieldDef.default}" must exist in enum.`
          );
        }
      }
      if (fieldDef.minimum !== undefined) {
        if (fieldDef.type !== 'number' && fieldDef.type !== 'integer') {
          throw new Error(
            `Invalid ${fileLabel} field "${fieldPath}.minimum": only valid on numeric types.`
          );
        }
        if (typeof fieldDef.minimum !== 'number' || !Number.isFinite(fieldDef.minimum)) {
          throw new Error(`Invalid ${fileLabel} field "${fieldPath}.minimum": expected finite number.`);
        }
      }
      if (fieldDef.format !== undefined) {
        assertFieldNonEmptyString(fieldDef.format, fileLabel, `${fieldPath}.format`);
      }
      if (fieldDef.items !== undefined) {
        if (fieldDef.type !== 'array' || !isPlainObject(fieldDef.items)) {
          throw new Error(`Invalid ${fileLabel} field "${fieldPath}.items": expected object on array field.`);
        }
        if (typeof fieldDef.items.type !== 'string' || !ALLOWED_SCHEMA_TYPES.has(fieldDef.items.type)) {
          throw new Error(
            `Invalid ${fileLabel} field "${fieldPath}.items.type": invalid type ${JSON.stringify(fieldDef.items.type)}.`
          );
        }
      }
    }
  }

  return contracts;
}

export function validateCanonicalSeedDatabase(seedDb) {
  const fileLabel = 'canonical_seed_database.json';
  if (!isPlainObject(seedDb)) {
    throw new Error(`${fileLabel} root must be a JSON object.`);
  }
  assertFieldInteger(seedDb.schemaVersion, fileLabel, 'schemaVersion', { min: 1 });
  assertFieldNonEmptyString(seedDb.appVersion, fileLabel, 'appVersion');
  assertFieldNonEmptyString(seedDb.exportedAt, fileLabel, 'exportedAt');
  if (Number.isNaN(Date.parse(seedDb.exportedAt))) {
    throw new Error(
      `Invalid ${fileLabel} field "exportedAt": expected valid ISO-8601 timestamp, got ${JSON.stringify(seedDb.exportedAt)}.`
    );
  }
  assertFieldBoolean(seedDb.isFinanceSetupCompleted, fileLabel, 'isFinanceSetupCompleted');
  if (seedDb.isFinanceSetupCompleted !== false) {
    throw new Error(
      `Invalid ${fileLabel} field "isFinanceSetupCompleted": clean startup seed must be false.`
    );
  }
  assertFieldInteger(seedDb.openingBalanceCents, fileLabel, 'openingBalanceCents', { min: 0, max: 0 });

  for (const emptyArrayField of [
    'accounts',
    'transactions',
    'tasks',
    'notes',
    'projects',
    'goals',
    'inboxItems',
    'calendarEvents',
  ]) {
    if (!Array.isArray(seedDb[emptyArrayField])) {
      throw new Error(`Missing or invalid ${fileLabel} array "${emptyArrayField}".`);
    }
    if (seedDb[emptyArrayField].length !== 0) {
      throw new Error(
        `Invalid ${fileLabel} field "${emptyArrayField}": clean startup seed must start empty ([]).`
      );
    }
  }

  if (!Array.isArray(seedDb.categories) || seedDb.categories.length === 0) {
    throw new Error(`Missing or empty ${fileLabel} array "categories".`);
  }
  const seenCategoryIds = new Set();
  for (let i = 0; i < seedDb.categories.length; i += 1) {
    const cat = seedDb.categories[i];
    const prefix = `categories[${i}]`;
    if (!isPlainObject(cat)) {
      throw new Error(`Invalid ${fileLabel} item "${prefix}": expected object.`);
    }
    assertFieldNonEmptyString(cat.id, fileLabel, `${prefix}.id`);
    if (seenCategoryIds.has(cat.id)) {
      throw new Error(`Duplicate ${fileLabel} category id "${cat.id}".`);
    }
    seenCategoryIds.add(cat.id);
    assertFieldNonEmptyString(cat.name, fileLabel, `${prefix}.name`);
    if (cat.type !== 'income' && cat.type !== 'expense') {
      throw new Error(
        `Invalid ${fileLabel} field "${prefix}.type": expected "income" or "expense", got ${JSON.stringify(cat.type)}.`
      );
    }
    if (typeof cat.colorHex !== 'string' || !HEX_COLOR_REGEX.test(cat.colorHex)) {
      throw new Error(
        `Invalid ${fileLabel} field "${prefix}.colorHex": expected #RRGGBB hex string, got ${JSON.stringify(cat.colorHex)}.`
      );
    }
    assertFieldBoolean(cat.isDefault, fileLabel, `${prefix}.isDefault`);
    assertFieldBoolean(cat.isArchived, fileLabel, `${prefix}.isArchived`);
  }

  return seedDb;
}

export function validateCalendarTestVectors(vectors) {
  const fileLabel = 'calendar_test_vectors.json';
  if (!isPlainObject(vectors)) {
    throw new Error(`${fileLabel} root must be a JSON object.`);
  }
  assertFieldNonEmptyString(vectors.version, fileLabel, 'version');
  assertFieldNonEmptyString(vectors.source, fileLabel, 'source');

  if (!Array.isArray(vectors.conversionVectors) || vectors.conversionVectors.length === 0) {
    throw new Error(`Missing or empty ${fileLabel} array "conversionVectors".`);
  }
  for (let i = 0; i < vectors.conversionVectors.length; i += 1) {
    const v = vectors.conversionVectors[i];
    const prefix = `conversionVectors[${i}]`;
    if (!isPlainObject(v)) {
      throw new Error(`Invalid ${fileLabel} item "${prefix}": expected object.`);
    }
    assertValidIsoDate(v.gregorian, fileLabel, `${prefix}.gregorian`);
    assertValidEthiopianDateObj(v.ethiopian, fileLabel, `${prefix}.ethiopian`);
    assertFieldInteger(v.weekday, fileLabel, `${prefix}.weekday`, { min: 1, max: 7 });
    assertFieldBoolean(v.gregorianLeap, fileLabel, `${prefix}.gregorianLeap`);
    const gregYear = Number(v.gregorian.slice(0, 4));
    if (v.gregorianLeap !== isGregorianLeapYear(gregYear)) {
      throw new Error(
        `Invalid ${fileLabel} field "${prefix}.gregorianLeap": inconsistent with year ${gregYear}.`
      );
    }
    assertFieldBoolean(v.ethiopianLeap, fileLabel, `${prefix}.ethiopianLeap`);
    if (v.ethiopianLeap !== isEthiopianLeapYear(v.ethiopian.year)) {
      throw new Error(
        `Invalid ${fileLabel} field "${prefix}.ethiopianLeap": inconsistent with Ethiopian year ${v.ethiopian.year}.`
      );
    }
    assertFieldNonEmptyString(v.label, fileLabel, `${prefix}.label`);
  }

  if (!Array.isArray(vectors.invalidGregorianDates) || vectors.invalidGregorianDates.length === 0) {
    throw new Error(`Missing or empty ${fileLabel} array "invalidGregorianDates".`);
  }
  for (let i = 0; i < vectors.invalidGregorianDates.length; i += 1) {
    assertFieldNonEmptyString(
      vectors.invalidGregorianDates[i],
      fileLabel,
      `invalidGregorianDates[${i}]`
    );
  }

  if (!Array.isArray(vectors.invalidEthiopianDates) || vectors.invalidEthiopianDates.length === 0) {
    throw new Error(`Missing or empty ${fileLabel} array "invalidEthiopianDates".`);
  }
  for (let i = 0; i < vectors.invalidEthiopianDates.length; i += 1) {
    const item = vectors.invalidEthiopianDates[i];
    if (!isPlainObject(item)) {
      throw new Error(`Invalid ${fileLabel} item "invalidEthiopianDates[${i}]": expected object.`);
    }
    assertFieldInteger(item.year, fileLabel, `invalidEthiopianDates[${i}].year`);
    assertFieldInteger(item.month, fileLabel, `invalidEthiopianDates[${i}].month`);
    assertFieldInteger(item.day, fileLabel, `invalidEthiopianDates[${i}].day`);
  }

  if (!Array.isArray(vectors.arithmeticVectors) || vectors.arithmeticVectors.length === 0) {
    throw new Error(`Missing or empty ${fileLabel} array "arithmeticVectors".`);
  }
  for (let i = 0; i < vectors.arithmeticVectors.length; i += 1) {
    const a = vectors.arithmeticVectors[i];
    const prefix = `arithmeticVectors[${i}]`;
    if (!isPlainObject(a)) {
      throw new Error(`Invalid ${fileLabel} item "${prefix}": expected object.`);
    }
    assertValidIsoDate(a.startGregorian, fileLabel, `${prefix}.startGregorian`);
    assertFieldInteger(a.addDays, fileLabel, `${prefix}.addDays`);
    assertValidIsoDate(a.expectedGregorian, fileLabel, `${prefix}.expectedGregorian`);
    assertValidEthiopianDateObj(a.expectedEthiopian, fileLabel, `${prefix}.expectedEthiopian`);
  }

  return vectors;
}

function hexToDartColor(hex) {
  return `Color(0xFF${hex.slice(1).toUpperCase()})`;
}

function toDartDouble(value) {
  const num = Number(value);
  return Number.isInteger(num) ? `${num}.0` : String(num);
}

function toDartFontWeight(weight) {
  return `FontWeight.w${weight}`;
}

function escapeDartString(value) {
  return String(value).replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

function capitalize(value) {
  return value.charAt(0).toUpperCase() + value.slice(1);
}

function formatDartConst(type, name, expr) {
  const singleLine = `  static const ${type} ${name} = ${expr};`;
  if (singleLine.length <= 80) {
    return singleLine;
  }
  return `  static const ${type} ${name} =\n      ${expr};`;
}

function renderDartTypographyToken(roleName, token) {
  const fieldName = `type${capitalize(roleName)}`;
  return `  static const SharedTextStyleToken ${fieldName} = SharedTextStyleToken(
    fontSize: ${toDartDouble(token.fontSize)},
    lineHeight: ${toDartDouble(token.lineHeight)},
    fontWeight: ${toDartFontWeight(token.fontWeight)},
    letterSpacing: ${toDartDouble(token.letterSpacing)},
    fontFamilyRole: '${escapeDartString(token.fontFamily)}',
    tabularFigures: ${token.tabularFigures},
  );`;
}

export function buildTypeScriptFoundation({ tokens, rules, seedDb }) {
  return `/**
 * SHARED FOUNDATION CORE (Single Source of Truth)
 * Generated automatically from /shared_foundation/*.json
 * DO NOT EDIT DIRECTLY. Run "npm run sync-foundation" to regenerate.
 */

export const SHARED_DESIGN_TOKENS = ${JSON.stringify(tokens, null, 2)} as const;

export type DaywellDesignTokens = typeof SHARED_DESIGN_TOKENS;

export const SHARED_BUSINESS_RULES = ${JSON.stringify(rules, null, 2)} as const;

export const CANONICAL_SEED_DATABASE = ${JSON.stringify(seedDb, null, 2)} as const;

export interface SharedTask {
  id: string;
  title: string;
  description?: string;
  status: 'not_started' | 'in_progress' | 'completed' | 'cancelled' | 'inbox';
  priority: 'low' | 'medium' | 'high' | 'urgent';
  dueDate?: string;
  scheduledDate?: string;
  projectId?: string;
  milestoneId?: string;
  estimatedDurationMinutes?: number;
  subtasks?: Array<{ title: string; done: boolean }>;
  labels?: string[];
  isPinned?: boolean;
  isMyDay?: boolean;
  recurrenceRule?: string;
  createdAt: string;
  updatedAt?: string;
}

export interface SharedNote {
  id: string;
  title: string;
  body: string;
  folder?: string;
  tags: string[];
  isPinned: boolean;
  isFavorite?: boolean;
  isArchived: boolean;
  isTrashed?: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface SharedCalendarEvent {
  id: string;
  title: string;
  date: string;
  endDate?: string;
  startTime?: string;
  endTime?: string;
  isAllDay: boolean;
  category: string;
  colorHex: string;
  hasReminder: boolean;
  notes?: string;
  createdAt: string;
  updatedAt: string;
}

export type SharedAccountSubType =
  | 'cash'
  | 'bank'
  | 'mobile_money'
  | 'savings_vault'
  | 'credit_card'
  | 'receivable'
  | 'payable'
  | 'opening_equity'
  | 'nominal_income'
  | 'nominal_expense'
  | 'legacy_clearing';

export const SYSTEM_CONTROL_ACCOUNT_IDS = {
  equity: 'acc-sys-equity',
  income: 'acc-sys-income',
  expense: 'acc-sys-expense',
  receivable: 'acc-sys-receivable',
  payable: 'acc-sys-payable',
  legacyOffset: 'acc-sys-legacy-offset',
} as const;

export interface SharedAccount {
  id: string;
  name: string;
  type: 'asset' | 'liability' | 'equity' | 'revenue' | 'income' | 'expense';
  subType?: SharedAccountSubType;
  isSystem?: boolean;
  currencyCode: string;
  openingBalanceCents: number;
  openingBalanceDate?: string;
  isArchived: boolean;
}

export interface SharedCategory {
  id: string;
  name: string;
  type: 'income' | 'expense';
  colorHex: string;
  parentId?: string;
  sortOrder?: number;
  isDefault: boolean;
  isArchived: boolean;
}

export interface SharedTransaction {
  id: string;
  amountCents: number;
  type: 'income' | 'expense' | 'transfer';
  categoryId?: string;
  categoryName?: string;
  accountId: string;
  accountName?: string;
  destinationAccountId?: string;
  destinationAccountName?: string;
  transactionDate: string;
  note?: string;
  payee?: string;
  isSuperseded?: boolean;
}

export interface SharedCommitment {
  id: string;
  title: string;
  amountCents: number;
  dueDate: string;
  isPaid: boolean;
  recurringRule?: string;
  linkedAccountId?: string;
  categoryId?: string;
  linkedDebtId?: string;
  settlementEntryId?: string;
  recurringRuleId?: string;
  direction?: 'outflow' | 'inflow';
  legacyPaidUnverified?: boolean;
}

export interface SharedCommitmentSettlement {
  id: string;
  commitmentId: string;
  entryId: string;
  amountCents: number;
  settledDate: string;
  createdAt: string;
}

export interface SharedSavingsGoal {
  id: string;
  title: string;
  targetCents: number;
  currentAllocatedCents: number;
  targetDate?: string;
  linkedAccountId?: string;
  status?: 'active' | 'completed' | 'archived';
}

export interface SharedBudget {
  id: string;
  categoryId: string;
  monthIso: string;
  limitCents: number;
  rolloverEnabled: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface SharedRecurringRule {
  id: string;
  title: string;
  ruleType: 'expense' | 'income' | 'transfer' | 'commitment';
  amountCents: number;
  frequency: 'weekly' | 'biweekly' | 'monthly' | 'quarterly' | 'yearly';
  interval: number;
  startDate: string;
  nextOccurrenceDate: string;
  endDate?: string;
  accountId?: string;
  destinationAccountId?: string;
  categoryId?: string;
  linkedDebtId?: string;
  isActive: boolean;
  autoPost: boolean;
  createdAt: string;
}

export type SharedProjectBlockType = 'counter' | 'grouped_list' | 'checklist' | 'schedule';

export type SharedProjectRecordType =
  | 'group'
  | 'grouped_item'
  | 'checklist_item'
  | 'schedule_item'
  | 'progress_log';

export type SharedProjectCustomFieldType = 'text' | 'number' | 'date' | 'boolean' | 'select';

export type SharedProjectCustomFieldValue = string | number | boolean | null;

export interface SharedProjectCustomFieldDefinition {
  id: string;
  label: string;
  type: SharedProjectCustomFieldType;
  required?: boolean;
  options?: string[];
}

export interface SharedProjectCustomFieldsPayload {
  definitions?: SharedProjectCustomFieldDefinition[];
  values?: Record<string, SharedProjectCustomFieldValue>;
  primaryBlockId?: string;
}

export interface SharedProject {
  id: string;
  title: string;
  description?: string;
  status: 'active' | 'completed' | 'on_hold';
  targetDate?: string;
  goalId?: string;
  isArchived?: boolean;
  startDate?: string;
  customFields?: SharedProjectCustomFieldsPayload | Record<string, unknown>;
  createdAt?: string;
  updatedAt?: string;
}

export interface SharedProjectTrackingBlock {
  id: string;
  projectId: string;
  blockType: SharedProjectBlockType;
  title: string;
  sortOrder: number;
  unitLabel?: string;
  targetValue?: number;
  dailyTargetValue?: number;
  config?: Record<string, unknown>;
  isArchived: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface SharedProjectTrackingRecord {
  id: string;
  projectId: string;
  blockId: string;
  parentRecordId?: string;
  recordType: SharedProjectRecordType;
  title?: string;
  sortOrder: number;
  targetValue?: number;
  deltaValue?: number;
  durationMinutes?: number;
  isCompleted: boolean;
  completedAt?: string;
  recordedDate?: string;
  scheduledDate?: string;
  linkedTaskId?: string;
  metadata?: Record<string, unknown>;
  createdAt: string;
  updatedAt: string;
}

export interface SharedGoal {
  id: string;
  title: string;
  description?: string;
  status: 'active' | 'achieved' | 'archived';
  targetDate?: string;
}

export interface SharedInboxItem {
  id: string;
  rawText: string;
  category: 'task' | 'idea' | 'expense' | 'note' | 'problem' | 'decision' | 'general';
  isProcessed: boolean;
  createdAt: string;
}

export interface SharedReminder {
  id: string;
  targetId: string;
  targetType: 'task' | 'commitment' | 'calendar_event' | 'note' | 'custom';
  triggerTimeUtc: string;
  isActive: boolean;
  createdAt: string;
  title?: string;
  channelId?: string;
}

export interface SharedAppSetting {
  key: string;
  value: string;
  updatedAt?: string;
}

export interface SharedDatabaseState {
  schemaVersion: number;
  appVersion: string;
  exportedAt: string;
  isFinanceSetupCompleted: boolean;
  openingBalanceCents: number;
  accounts: SharedAccount[];
  categories: SharedCategory[];
  transactions: SharedTransaction[];
  commitments?: SharedCommitment[];
  commitmentSettlements?: SharedCommitmentSettlement[];
  savingsGoals?: SharedSavingsGoal[];
  budgets?: SharedBudget[];
  recurringRules?: SharedRecurringRule[];
  tasks: SharedTask[];
  notes: SharedNote[];
  projects: SharedProject[];
  projectTrackingBlocks?: SharedProjectTrackingBlock[];
  projectTrackingRecords?: SharedProjectTrackingRecord[];
  goals: SharedGoal[];
  inboxItems: SharedInboxItem[];
  calendarEvents?: SharedCalendarEvent[];
  reminders?: SharedReminder[];
  appSettings?: SharedAppSetting[];
}

/**
 * Shared Business Rule: Account Balance Calculation
 * Balance = Opening Balance + Income - Expenses + Incoming Transfers - Outgoing Transfers
 */
export function calculateSharedAccountBalance(
  account: SharedAccount,
  transactions: SharedTransaction[]
): number {
  let balance = account.openingBalanceCents || 0;
  for (const tx of transactions) {
    if (tx.isSuperseded) continue;
    if (tx.type === 'income' && tx.accountId === account.id) {
      balance += tx.amountCents;
    } else if (tx.type === 'expense' && tx.accountId === account.id) {
      balance -= tx.amountCents;
    } else if (tx.type === 'transfer') {
      if (tx.accountId === account.id) {
        balance -= tx.amountCents;
      }
      if (tx.destinationAccountId === account.id) {
        balance += tx.amountCents;
      }
    }
  }
  return balance;
}

/**
 * Shared Business Rule: Combined Active Asset Balance
 */
export function calculateSharedCombinedBalance(
  accounts: SharedAccount[],
  transactions: SharedTransaction[]
): number {
  return accounts
    .filter(
      (a) =>
        !a.isArchived &&
        !((a as unknown as { isSystem?: boolean }).isSystem === true) &&
        a.type === 'asset' &&
        (a.currencyCode ?? '').trim().toUpperCase() === 'ETB'
    )
    .reduce((sum, a) => sum + calculateSharedAccountBalance(a, transactions), 0);
}

/**
 * Shared Business Rule: Safe Account Deletion Guard
 */
export function canDeleteSharedAccount(
  accountId: string,
  transactions: SharedTransaction[]
): boolean {
  return !transactions.some(
    (t) => !t.isSuperseded && (t.accountId === accountId || t.destinationAccountId === accountId)
  );
}

/**
 * Shared Business Rule: Safe Category Deletion Guard
 */
export function canDeleteSharedCategory(
  categoryId: string,
  categoryName: string,
  transactions: SharedTransaction[]
): boolean {
  return !transactions.some(
    (t) =>
      !t.isSuperseded && (t.categoryId === categoryId || t.categoryName === categoryName)
  );
}

/**
 * Shared Business Rule: Validate Transfer
 */
export function validateSharedTransfer(
  fromAccountId: string,
  toAccountId: string,
  amountCents: number
): { valid: boolean; error?: string } {
  if (!fromAccountId || !toAccountId) {
    return { valid: false, error: 'Source and destination accounts are required.' };
  }
  if (fromAccountId === toAccountId) {
    return { valid: false, error: 'Source and destination accounts cannot be identical.' };
  }
  if (!Number.isInteger(amountCents) || amountCents <= 0) {
    return { valid: false, error: 'Transfer amount must be a positive integer in cents.' };
  }
  return { valid: true };
}
/**
 * Shared Business Rule: Total Income Calculation
 */
export function calculateSharedTotalIncome(
  transactions: SharedTransaction[],
  accountId?: string
): number {
  return transactions
    .filter((t) => !t.isSuperseded && t.type === 'income' && (!accountId || t.accountId === accountId))
    .reduce((sum, t) => sum + t.amountCents, 0);
}

/**
 * Shared Business Rule: Total Expense Calculation
 */
export function calculateSharedTotalExpense(
  transactions: SharedTransaction[],
  accountId?: string
): number {
  return transactions
    .filter((t) => !t.isSuperseded && t.type === 'expense' && (!accountId || t.accountId === accountId))
    .reduce((sum, t) => sum + t.amountCents, 0);
}

/**
 * Known demonstration seed record identifiers to safely purge from legacy storage
 */
export const KNOWN_SEED_IDS = {
  accounts: ['acc-cbe', 'acc-boa', 'acc-dashen', 'acc-telebirr', 'acc-cash'],
  transactions: ['tx-seed-1', 'tx-seed-2', 'tx-seed-3'],
  tasks: ['task-seed-1', 'task-seed-2', 't-1', 't-2', 't-3', 't-4', 't-5', 't-6', 't-7'],
  notes: ['note-seed-1', 'note-1', 'note-2', 'note-3'],
  projects: ['proj-seed-1', 'proj-1', 'proj-2', 'proj-3'],
  goals: ['goal-seed-1', 'goal-1', 'goal-2'],
  events: ['evt-1', 'evt-2', 'evt-3', 'evt-4'],
  commitments: ['com-1', 'com-2'],
  savingsGoals: ['sav-1', 'sav-2'],
  inboxItems: ['inbox-1'],
  parties: ['party-abebe', 'party-landlord', 'party-boss'],
} as const;

export function isKnownSeedId(id: string): boolean {
  return Object.values(KNOWN_SEED_IDS).some((ids) => (ids as readonly string[]).includes(id));
}
`;
}

export function buildCssTokensFoundation({ tokens }) {
  const c = tokens.colors;
  const t = tokens.typography;
  const s = tokens.spacing;
  const r = tokens.radii;
  const b = tokens.breakpoints;

  const fontForRole = (role) => {
    if (role === 'serif') return 'var(--dw-font-serif)';
    if (role === 'mono') return 'var(--dw-font-mono)';
    return 'var(--dw-font-sans)';
  };

  const typeClass = (className, spec) => `.${className} {
  font-family: ${fontForRole(spec.fontFamily)};
  font-size: ${spec.fontSize}px;
  line-height: ${spec.lineHeight}px;
  font-weight: ${spec.fontWeight};
  letter-spacing: ${spec.letterSpacing}px;${spec.tabularFigures ? '\n  font-variant-numeric: tabular-nums;' : ''}
}`;

  return `/**
 * DAYWELL CANONICAL CSS DESIGN TOKENS (Single Source of Truth)
 * Generated automatically from /shared_foundation/design_tokens.json (v${tokens.version})
 * DO NOT EDIT DIRECTLY. Run "npm run sync-foundation" to regenerate.
 */

:root {
  /* Primary & Secondary */
  --dw-primary: ${c.primary.emerald};
  --dw-primary-hover: ${c.primary.emeraldDark};
  --dw-primary-deep: ${c.primary.emeraldDark};
  --dw-primary-brand: ${c.primary.emerald};
  --dw-on-primary: ${c.primary.onLight};
  --dw-primary-container: ${c.secondary.mint};
  --dw-primary-container-subtle: ${c.secondary.mintLight};
  --dw-on-primary-container: ${c.secondary.onLight};

  /* Surfaces & Borders */
  --dw-canvas: ${c.surface.canvasLight};
  --dw-surface-subtle: ${c.surface.subtleLight};
  --dw-card: ${c.surface.cardLight};
  --dw-elevated: ${c.surface.elevatedLight};
  --dw-border: ${c.surface.borderLight};
  --dw-divider: ${c.surface.dividerLight};

  /* Text Hierarchy */
  --dw-text-primary: ${c.text.primaryLight};
  --dw-text-secondary: ${c.text.secondaryLight};
  --dw-text-muted: ${c.text.mutedLight};
  --dw-text-disabled: ${c.text.disabledLight};

  /* Semantic Finance & Status */
  --dw-income: ${c.semantic.income};
  --dw-on-income: ${c.semantic.onIncome};
  --dw-income-container: ${c.semantic.incomeContainerLight};
  --dw-on-income-container: ${c.semantic.onIncomeContainerLight};

  --dw-expense: ${c.semantic.expense};
  --dw-on-expense: ${c.semantic.onExpense};
  --dw-expense-container: ${c.semantic.expenseContainerLight};
  --dw-on-expense-container: ${c.semantic.onExpenseContainerLight};

  --dw-transfer: ${c.semantic.transfer};
  --dw-on-transfer: ${c.semantic.onTransfer};
  --dw-transfer-container: ${c.semantic.transferContainerLight};
  --dw-on-transfer-container: ${c.semantic.onTransferContainerLight};

  --dw-success: ${c.semantic.success};
  --dw-on-success: ${c.semantic.onSuccess};
  --dw-success-container: ${c.semantic.successContainerLight};
  --dw-on-success-container: ${c.semantic.onSuccessContainerLight};

  --dw-error: ${c.semantic.error};
  --dw-on-error: ${c.semantic.onError};
  --dw-error-container: ${c.semantic.errorContainerLight};
  --dw-on-error-container: ${c.semantic.onErrorContainerLight};

  --dw-warning: ${c.semantic.warning};
  --dw-on-warning: ${c.semantic.onWarning};
  --dw-warning-container: ${c.semantic.warningContainerLight};
  --dw-on-warning-container: ${c.semantic.onWarningContainerLight};

  --dw-info: ${c.semantic.info};
  --dw-on-info: ${c.semantic.onInfo};
  --dw-info-container: ${c.semantic.infoContainerLight};
  --dw-on-info-container: ${c.semantic.onInfoContainerLight};

  /* Typography Families */
  --dw-font-serif: ${t.fontFamilySerif};
  --dw-font-sans: ${t.fontFamilySans};
  --dw-font-mono: ${t.fontFamilyMono};

  /* Spacing Scale */
  --dw-space-xs: ${s.xs}px;
  --dw-space-sm: ${s.sm}px;
  --dw-space-compact: ${s.compact}px;
  --dw-space-md: ${s.md}px;
  --dw-space-lg: ${s.lg}px;
  --dw-space-xl: ${s.xl}px;

  /* Corner Radii */
  --dw-radius-sm: ${r.sm}px;
  --dw-radius-md: ${r.md}px;
  --dw-radius-lg: ${r.lg}px;
  --dw-radius-xl: ${r.xl}px;
  --dw-radius-sheet: ${r.sheet}px;
  --dw-radius-full: ${r.full}px;

  /* Layout Breakpoints */
  --dw-breakpoint-medium: ${b.medium}px;
  --dw-breakpoint-expanded: ${b.expanded}px;
  --dw-max-content-width: ${b.maxContentWidth}px;
  --dw-max-wide-width: ${b.maxWideWidth}px;
}

.dark {
  /* Primary & Secondary (Dark Mode) */
  --dw-primary: ${c.primary.darkMode};
  --dw-primary-hover: ${c.secondary.mint};
  --dw-primary-deep: ${c.primary.emeraldLight};
  --dw-primary-brand: ${c.primary.emeraldLight};
  --dw-on-primary: ${c.primary.onDark};
  --dw-primary-container: ${c.secondary.mintDark};
  --dw-primary-container-subtle: ${c.secondary.mintDark};
  --dw-on-primary-container: ${c.secondary.onDark};

  /* Surfaces & Borders (Dark Mode) */
  --dw-canvas: ${c.surface.canvasDark};
  --dw-surface-subtle: ${c.surface.subtleDark};
  --dw-card: ${c.surface.cardDark};
  --dw-elevated: ${c.surface.elevatedDark};
  --dw-border: ${c.surface.borderDark};
  --dw-divider: ${c.surface.dividerDark};

  /* Text Hierarchy (Dark Mode) */
  --dw-text-primary: ${c.text.primaryDark};
  --dw-text-secondary: ${c.text.secondaryDark};
  --dw-text-muted: ${c.text.mutedDark};
  --dw-text-disabled: ${c.text.disabledDark};

  /* Semantic Containers (Dark Mode) */
  --dw-income-container: ${c.semantic.incomeContainerDark};
  --dw-on-income-container: ${c.semantic.onIncomeContainerDark};

  --dw-expense-container: ${c.semantic.expenseContainerDark};
  --dw-on-expense-container: ${c.semantic.onExpenseContainerDark};

  --dw-transfer-container: ${c.semantic.transferContainerDark};
  --dw-on-transfer-container: ${c.semantic.onTransferContainerDark};

  --dw-success-container: ${c.semantic.successContainerDark};
  --dw-on-success-container: ${c.semantic.onSuccessContainerDark};

  --dw-error-container: ${c.semantic.errorContainerDark};
  --dw-on-error-container: ${c.semantic.onErrorContainerDark};

  --dw-warning-container: ${c.semantic.warningContainerDark};
  --dw-on-warning-container: ${c.semantic.onWarningContainerDark};

  --dw-info-container: ${c.semantic.infoContainerDark};
  --dw-on-info-container: ${c.semantic.onInfoContainerDark};
}

${typeClass('dw-type-display', t.scale.display)}
${typeClass('dw-type-heading', t.scale.heading)}
${typeClass('dw-type-title', t.scale.title)}
${typeClass('dw-type-body', t.scale.body)}
${typeClass('dw-type-body-compact', t.scale.bodyCompact)}
${typeClass('dw-type-label', t.scale.label)}
${typeClass('dw-type-caption', t.scale.caption)}
${typeClass('dw-type-numeric-hero', t.scale.numericHero)}
${typeClass('dw-type-numeric-body', t.scale.numericBody)}
${typeClass('dw-type-mono', t.scale.mono)}
`;
}

export function buildDartFoundationCore({ seedDb }) {
  return `// SHARED FOUNDATION CORE — PURE DART (Single Source of Truth)
// Generated automatically from /shared_foundation/*.json
// DO NOT EDIT DIRECTLY. Run "npm run sync-foundation" to regenerate.

import 'dart:convert';

class CanonicalSeedDatabase {
  static const int schemaVersion = ${seedDb.schemaVersion};
  static const String appVersion = "${seedDb.appVersion}";
  static const String rawJson = r'''${JSON.stringify(seedDb, null, 2)}''';

  static Map<String, dynamic> get state =>
      jsonDecode(rawJson) as Map<String, dynamic>;
}

class SharedBusinessRules {
  static const String currencyCode = 'ETB';
  static const int minorUnitsPerMajor = 100;
  static const int defaultTxDisplayLimit = 25;

  /// Balance = Opening + Income - Expenses + Incoming - Outgoing Transfers
  static int calculateAccountBalance({
    required int openingBalanceCents,
    required String accountId,
    required List<Map<String, dynamic>> transactions,
  }) {
    int balance = openingBalanceCents;
    for (final tx in transactions) {
      if (tx['isSuperseded'] == true) continue;
      final type = tx['type'];
      final amount = tx['amountCents'] as int;
      if (type == 'income' && tx['accountId'] == accountId) {
        balance += amount;
      } else if (type == 'expense' && tx['accountId'] == accountId) {
        balance -= amount;
      } else if (type == 'transfer') {
        if (tx['accountId'] == accountId) {
          balance -= amount;
        }
        if (tx['destinationAccountId'] == accountId) {
          balance += amount;
        }
      }
    }
    return balance;
  }

  /// Combined balance of active Verified ETB non-system asset accounts
  static int calculateCombinedBalance({
    required List<Map<String, dynamic>> accounts,
    required List<Map<String, dynamic>> transactions,
  }) {
    int total = 0;
    for (final acc in accounts) {
      if (acc['isArchived'] == true) continue;
      if (acc['isSystem'] == true) continue;
      if (acc['type'] != null && acc['type'] != 'asset') continue;
      final code = (acc['currencyCode']?.toString() ?? '').trim().toUpperCase();
      if (code != 'ETB') continue;
      total += calculateAccountBalance(
        openingBalanceCents: (acc['openingBalanceCents'] as int?) ?? 0,
        accountId: acc['id'] as String,
        transactions: transactions,
      );
    }
    return total;
  }

  /// Total income from income transactions (excluding transfers)
  static int calculateTotalIncome({
    required List<Map<String, dynamic>> transactions,
    String? accountId,
  }) {
    int total = 0;
    for (final tx in transactions) {
      if (tx['isSuperseded'] == true) continue;
      if (tx['type'] == 'income') {
        if (accountId == null || tx['accountId'] == accountId) {
          total += (tx['amountCents'] as int?) ?? 0;
        }
      }
    }
    return total;
  }

  /// Total expense from expense transactions (excluding transfers)
  static int calculateTotalExpense({
    required List<Map<String, dynamic>> transactions,
    String? accountId,
  }) {
    int total = 0;
    for (final tx in transactions) {
      if (tx['isSuperseded'] == true) continue;
      if (tx['type'] == 'expense') {
        if (accountId == null || tx['accountId'] == accountId) {
          total += (tx['amountCents'] as int?) ?? 0;
        }
      }
    }
    return total;
  }

  /// Safe deletion guard for accounts
  static bool canDeleteAccount({
    required String accountId,
    required List<Map<String, dynamic>> transactions,
  }) {
    return !transactions.any((t) =>
        t['isSuperseded'] != true &&
        (t['accountId'] == accountId ||
            t['destinationAccountId'] == accountId));
  }

  /// Safe deletion guard for categories
  static bool canDeleteCategory({
    required String categoryId,
    required String categoryName,
    required List<Map<String, dynamic>> transactions,
  }) {
    return !transactions.any((t) =>
        t['isSuperseded'] != true &&
        (t['categoryId'] == categoryId || t['categoryName'] == categoryName));
  }

  /// Transfer validation
  static String? validateTransfer({
    required String fromAccountId,
    required String toAccountId,
    required int amountCents,
  }) {
    if (fromAccountId.isEmpty || toAccountId.isEmpty) {
      return 'Source and destination accounts are required.';
    }
    if (fromAccountId == toAccountId) {
      return 'Source and destination accounts cannot be identical.';
    }
    if (amountCents <= 0) {
      return 'Transfer amount must be greater than zero.';
    }
    return null;
  }
}

class SharedProjectRules {
  static const List<String> statuses = ['active', 'completed', 'on_hold'];
  static const List<String> blockTypes = [
    'counter',
    'grouped_list',
    'checklist',
    'schedule',
  ];
  static const List<String> recordTypes = [
    'group',
    'grouped_item',
    'checklist_item',
    'schedule_item',
    'progress_log',
  ];
  static const List<String> customFieldTypes = [
    'text',
    'number',
    'date',
    'boolean',
    'select',
  ];
  static const int maxBlocksPerProject = 32;
  static const int maxCustomFieldDefinitions = 24;
  static const int maxCustomFieldSelectOptions = 50;
  static const int maxCustomFieldIdLength = 64;
  static const int maxCustomFieldTextLength = 1000;
  static const int maxHierarchyDepth = 3;
  static const bool appendOnlyProgressLogs = true;
  static const bool allowCompensatingCorrections = true;
  static const bool allowMultipleIndependentMetrics = true;
  static const bool disallowImplicitMetricAveraging = true;
  static const bool requiresExplicitPrimaryBlockForOverallPercent = true;
  static const bool requirePositiveProgressLogDelta = true;
  static const bool preventDuplicateRollupLogging = true;
  static const bool enforceParentChildOwnership = true;
}

class KnownSeedIds {
  static const Set<String> accounts = {
    'acc-cbe',
    'acc-boa',
    'acc-dashen',
    'acc-telebirr',
    'acc-cash'
  };
  static const Set<String> transactions = {
    'tx-seed-1',
    'tx-seed-2',
    'tx-seed-3'
  };
  static const Set<String> tasks = {
    'task-seed-1',
    'task-seed-2',
    't-1',
    't-2',
    't-3',
    't-4',
    't-5',
    't-6',
    't-7'
  };
  static const Set<String> notes = {
    'note-seed-1',
    'note-1',
    'note-2',
    'note-3'
  };
  static const Set<String> projects = {
    'proj-seed-1',
    'proj-1',
    'proj-2',
    'proj-3'
  };
  static const Set<String> goals = {'goal-seed-1', 'goal-1', 'goal-2'};
  static const Set<String> events = {'evt-1', 'evt-2', 'evt-3', 'evt-4'};
  static const Set<String> commitments = {'com-1', 'com-2'};
  static const Set<String> savingsGoals = {'sav-1', 'sav-2'};
  static const Set<String> inboxItems = {'inbox-1'};
  static const Set<String> parties = {
    'party-abebe',
    'party-landlord',
    'party-boss'
  };

  static bool isKnownSeedId(String id) {
    return accounts.contains(id) ||
        transactions.contains(id) ||
        tasks.contains(id) ||
        notes.contains(id) ||
        projects.contains(id) ||
        goals.contains(id) ||
        events.contains(id) ||
        commitments.contains(id) ||
        savingsGoals.contains(id) ||
        inboxItems.contains(id) ||
        parties.contains(id);
  }
}
`;
}

export function buildDartFoundation({ tokens }) {
  const { primary, secondary, surface, text, semantic } = tokens.colors;
  const { typography, spacing, radii, elevation, breakpoints } = tokens;

  const semanticRoles = ['income', 'expense', 'transfer', 'success', 'error', 'warning', 'info'];
  const semanticLines = semanticRoles.flatMap((role) => {
    const cap = capitalize(role);
    const entries = [
      ['semantic' + cap, semantic[role]],
      ['onSemantic' + cap, semantic[`on${cap}`]],
      ['semantic' + cap + 'ContainerLight', semantic[`${role}ContainerLight`]],
      ['onSemantic' + cap + 'ContainerLight', semantic[`on${cap}ContainerLight`]],
      ['semantic' + cap + 'ContainerDark', semantic[`${role}ContainerDark`]],
      ['onSemantic' + cap + 'ContainerDark', semantic[`on${cap}ContainerDark`]],
    ];
    return entries
      .filter(([, hex]) => typeof hex === 'string')
      .map(([name, hex]) => formatDartConst('Color', name, hexToDartColor(hex)));
  });

  const typographyScaleBlocks = TYPOGRAPHY_SCALE_KEYS
    .filter((role) => isPlainObject(typography.scale[role]))
    .map((role) => renderDartTypographyToken(role, typography.scale[role]));

  const dartColorIfPresent = (name, hex) =>
    typeof hex === 'string' ? formatDartConst('Color', name, hexToDartColor(hex)) : '';
  const dartStringIfPresent = (name, str) =>
    typeof str === 'string' ? formatDartConst('String', name, `'${escapeDartString(str)}'`) : '';
  const dartDoubleIfPresent = (name, num) =>
    typeof num === 'number' ? formatDartConst('double', name, toDartDouble(num)) : '';

  return `// SHARED FOUNDATION DESIGN TOKENS (Single Source of Truth)
// Generated automatically from /shared_foundation/*.json
// DO NOT EDIT DIRECTLY. Run "npm run sync-foundation" to regenerate.
// Re-exports pure-Dart CanonicalSeedDatabase, SharedBusinessRules (ETB),
// and KnownSeedIds.

import 'package:flutter/material.dart';

export 'shared_foundation_core.dart';

class SharedTextStyleToken {
  final double fontSize;
  final double lineHeight;
  final FontWeight fontWeight;
  final double letterSpacing;
  final String fontFamilyRole;
  final bool tabularFigures;

  const SharedTextStyleToken({
    required this.fontSize,
    required this.lineHeight,
    required this.fontWeight,
    required this.letterSpacing,
    required this.fontFamilyRole,
    this.tabularFigures = false,
  });

  double get height => lineHeight / fontSize;

  TextStyle toTextStyle({Color? color, String? fontFamily}) {
    return TextStyle(
      fontSize: fontSize,
      height: height,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: color,
      fontFamily: fontFamily,
      fontFeatures:
          tabularFigures ? const [FontFeature.tabularFigures()] : null,
    );
  }
}

class SharedDesignTokens {
${formatDartConst('String', 'tokenVersion', `'${escapeDartString(tokens.version)}'`)}

  // Brand Primary
${dartColorIfPresent('primaryEmerald', primary.emerald)}
${dartColorIfPresent('primaryEmeraldDark', primary.emeraldDark)}
${dartColorIfPresent('primaryEmeraldLight', primary.emeraldLight)}
${dartColorIfPresent('primaryDarkMode', primary.darkMode)}
${dartColorIfPresent('onPrimaryLight', primary.onLight)}
${dartColorIfPresent('onPrimaryDark', primary.onDark)}

  // Brand Secondary
${dartColorIfPresent('secondaryMint', secondary.mint)}
${dartColorIfPresent('secondaryMintDark', secondary.mintDark)}
${dartColorIfPresent('secondaryMintLight', secondary.mintLight)}
${dartColorIfPresent('onSecondaryLight', secondary.onLight)}
${dartColorIfPresent('onSecondaryDark', secondary.onDark)}

  // Surfaces & Borders
${dartColorIfPresent('canvasLight', surface.canvasLight)}
${dartColorIfPresent('canvasDark', surface.canvasDark)}
${dartColorIfPresent('surfaceSubtleLight', surface.subtleLight)}
${dartColorIfPresent('surfaceSubtleDark', surface.subtleDark)}
${dartColorIfPresent('cardLight', surface.cardLight)}
${dartColorIfPresent('cardDark', surface.cardDark)}
${dartColorIfPresent('elevatedLight', surface.elevatedLight)}
${dartColorIfPresent('elevatedDark', surface.elevatedDark)}
${dartColorIfPresent('borderLight', surface.borderLight)}
${dartColorIfPresent('borderDark', surface.borderDark)}
${dartColorIfPresent('dividerLight', surface.dividerLight)}
${dartColorIfPresent('dividerDark', surface.dividerDark)}

  // Text Hierarchy
${dartColorIfPresent('textPrimaryLight', text.primaryLight)}
${dartColorIfPresent('textPrimaryDark', text.primaryDark)}
${dartColorIfPresent('textSecondaryLight', text.secondaryLight)}
${dartColorIfPresent('textSecondaryDark', text.secondaryDark)}
${dartColorIfPresent('textMutedLight', text.mutedLight)}
${dartColorIfPresent('textMutedDark', text.mutedDark)}
${dartColorIfPresent('textDisabledLight', text.disabledLight)}
${dartColorIfPresent('textDisabledDark', text.disabledDark)}

  // Semantic Roles (Finance & System States)
${semanticLines.join('\n')}

  // Typography Families
${dartStringIfPresent('fontFamilySerif', typography.fontFamilySerif)}
${dartStringIfPresent('fontFamilySans', typography.fontFamilySans)}
${dartStringIfPresent('fontFamilyMono', typography.fontFamilyMono)}

  // Typography Scale
${typographyScaleBlocks.join('\n\n')}

  // Spacing Scale
${dartDoubleIfPresent('spacingXs', spacing.xs)}
${dartDoubleIfPresent('spacingSm', spacing.sm)}
${dartDoubleIfPresent('spacingCompact', spacing.compact)}
${dartDoubleIfPresent('spacingMd', spacing.md)}
${dartDoubleIfPresent('spacingLg', spacing.lg)}
${dartDoubleIfPresent('spacingXl', spacing.xl)}

  // Corner Radii
${dartDoubleIfPresent('radiusSm', radii.sm)}
${dartDoubleIfPresent('radiusMd', radii.md)}
${dartDoubleIfPresent('radiusLg', radii.lg)}
${dartDoubleIfPresent('radiusXl', radii.xl)}
${dartDoubleIfPresent('radiusSheet', radii.sheet)}
${dartDoubleIfPresent('radiusFull', radii.full)}

  // Elevation Levels
${dartDoubleIfPresent('elevationNone', elevation.none)}
${dartDoubleIfPresent('elevationLow', elevation.low)}
${dartDoubleIfPresent('elevationMedium', elevation.medium)}
${dartDoubleIfPresent('elevationHigh', elevation.high)}

  // Responsive Breakpoints & Content Caps
${dartDoubleIfPresent('breakpointMedium', breakpoints.medium)}
${dartDoubleIfPresent('breakpointExpanded', breakpoints.expanded)}
${dartDoubleIfPresent('breakpointMaxContentWidth', breakpoints.maxContentWidth)}
${dartDoubleIfPresent('breakpointMaxWideWidth', breakpoints.maxWideWidth)}
}
`;
}

function readJsonStrict(filePath, label) {
  let raw;
  try {
    raw = fs.readFileSync(filePath, 'utf8');
  } catch (err) {
    throw new Error(`Failed to read ${label} at ${filePath}: ${err.message}`);
  }
  try {
    return JSON.parse(raw);
  } catch (err) {
    throw new Error(`Invalid JSON in ${label} (${filePath}): ${err.message}`);
  }
}

const ADR_PATH_REGEX = /^docs\/architecture\/decisions\/ADR-[A-Za-z0-9_-]+\.md$/;
const ZERO_SHA_REGEX = /^0+$/;

function normalizeRelPath(relPath) {
  return relPath.replace(/\\/g, '/').replace(/^\/+/, '');
}

const GENERATED_FOUNDATION_OUTPUTS = new Set([
  'src/domain/sharedFoundation.ts',
  'src/styles/daywellTokens.css',
  'flutter_app/lib/core/shared_foundation_core.dart',
  'flutter_app/lib/core/shared_foundation.dart',
]);

function assertSafeExistingRepoFile(rootDir, relPath, errorPrefix, { allowMissing = false } = {}) {
  const resolved = path.resolve(rootDir, relPath);
  const relative = path.relative(rootDir, resolved);
  if (relative.startsWith('..') || path.isAbsolute(relative)) {
    throw new Error(`${errorPrefix}: "${relPath}" resolves outside ${rootDir}.`);
  }
  if (!fs.existsSync(resolved)) {
    if (allowMissing) return resolved;
    throw new Error(`${errorPrefix}: "${relPath}" does not resolve to an existing file under ${rootDir}.`);
  }
  if (!fs.statSync(resolved).isFile()) {
    throw new Error(`${errorPrefix}: "${relPath}" is not a file.`);
  }
  return resolved;
}

export function validateAuthorizedAdrDocument(adrRelPath, rootDir) {
  const normalized = normalizeRelPath(adrRelPath);
  if (!ADR_PATH_REGEX.test(normalized)) {
    throw new Error(
      `Invalid intentionalRemovals adrOrDoc "${adrRelPath}": must reference an ADR markdown file under docs/architecture/decisions/ADR-*.md (structural ADR checks do not replace human approval).`
    );
  }
  const absPath = assertSafeExistingRepoFile(
    rootDir,
    normalized,
    `Invalid foundation_compatibility_baseline.json entry "adrOrDoc"`
  );
  const content = fs.readFileSync(absPath, 'utf8');

  // Verify explicit `Status: accepted` (reject proposed, superseded, deprecated, draft, or missing)
  const statusMatch = content.match(
    /^\s*(?:[-*]\s*)?(?:\*\*)?Status(?:\*\*)?\s*:\s*(?:\*\*)?\s*`?([A-Za-z-]+)`?/im
  );
  const statusValue = statusMatch ? statusMatch[1].trim().toLowerCase() : null;
  if (statusValue !== 'accepted') {
    throw new Error(
      `Authorizing ADR "${normalized}" is not accepted (found status=${JSON.stringify(statusValue)}). ` +
        `Only explicitly "accepted" ADRs can authorize breaking contract removals (structural validation does not replace human review).`
    );
  }

  // Parse Markdown sections (`## Heading` / `### Heading`) and require non-empty Justification, Migration Strategy, Affected Consumers
  const sections = new Map();
  let currentHeading = null;
  let currentLines = [];
  for (const rawLine of content.split(/\r?\n/)) {
    const headingMatch = rawLine.match(/^#{2,3}\s+(.+?)\s*$/);
    if (headingMatch) {
      if (currentHeading !== null) {
        sections.set(currentHeading, currentLines.join('\n').trim());
      }
      currentHeading = headingMatch[1].replace(/\s+/g, ' ').trim().toLowerCase();
      currentLines = [];
    } else if (currentHeading !== null) {
      currentLines.push(rawLine);
    }
  }
  if (currentHeading !== null) {
    sections.set(currentHeading, currentLines.join('\n').trim());
  }

  for (const requiredSection of ['justification', 'migration strategy', 'affected consumers']) {
    const sectionBody = sections.get(requiredSection);
    if (!sectionBody || sectionBody.replace(/[-*\s]/g, '').length === 0) {
      throw new Error(
        `Authorizing ADR "${normalized}" must contain a non-empty "## ${requiredSection
          .split(' ')
          .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
          .join(' ')}" section (structural ADR checks do not replace human review).`
      );
    }
  }

  return normalized;
}

function parseIntentionalRemovals(baseline, rootDir) {
  const fileLabel = 'foundation_compatibility_baseline.json';
  if (!isPlainObject(baseline)) {
    throw new Error(`${fileLabel} root must be a JSON object.`);
  }
  assertFieldNonEmptyString(baseline.version, fileLabel, 'version');
  assertFieldNonEmptyString(baseline.governedBy, fileLabel, 'governedBy');

  if (!Array.isArray(baseline.intentionalRemovals)) {
    throw new Error(`Invalid ${fileLabel} field "intentionalRemovals": expected array.`);
  }

  const removalMap = new Map();
  for (let i = 0; i < baseline.intentionalRemovals.length; i += 1) {
    const entry = baseline.intentionalRemovals[i];
    const prefix = `intentionalRemovals[${i}]`;
    if (!isPlainObject(entry)) {
      throw new Error(`Invalid ${fileLabel} entry "${prefix}": expected object.`);
    }
    assertFieldNonEmptyString(entry.target, fileLabel, `${prefix}.target`);
    assertFieldNonEmptyString(entry.adrOrDoc, fileLabel, `${prefix}.adrOrDoc`);
    assertFieldNonEmptyString(entry.justification, fileLabel, `${prefix}.justification`);
    assertFieldNonEmptyString(entry.migrationStrategy, fileLabel, `${prefix}.migrationStrategy`);
    assertFieldNonEmptyString(entry.approvedBy, fileLabel, `${prefix}.approvedBy`);
    if (
      !Array.isArray(entry.coordinatedConsumers) ||
      entry.coordinatedConsumers.length === 0 ||
      entry.coordinatedConsumers.some((c) => typeof c !== 'string' || c.trim().length === 0)
    ) {
      throw new Error(
        `Invalid ${fileLabel} entry "${prefix}.coordinatedConsumers": expected non-empty string array.`
      );
    }
    for (const consumerRel of entry.coordinatedConsumers) {
      const normalizedConsumer = normalizeRelPath(consumerRel);
      assertSafeExistingRepoFile(
        rootDir,
        consumerRel,
        `Invalid ${fileLabel} entry "${prefix}.coordinatedConsumers"`,
        { allowMissing: GENERATED_FOUNDATION_OUTPUTS.has(normalizedConsumer) }
      );
    }

    if (
      !Array.isArray(entry.verificationTests) ||
      entry.verificationTests.length === 0 ||
      entry.verificationTests.some((t) => typeof t !== 'string' || t.trim().length === 0)
    ) {
      throw new Error(
        `Invalid ${fileLabel} entry "${prefix}.verificationTests": expected non-empty array of existing verification test file paths.`
      );
    }
    for (const testRel of entry.verificationTests) {
      assertSafeExistingRepoFile(
        rootDir,
        testRel,
        `Invalid ${fileLabel} entry "${prefix}.verificationTests"`
      );
    }

    validateAuthorizedAdrDocument(entry.adrOrDoc, rootDir);

    if (removalMap.has(entry.target)) {
      throw new Error(
        `Duplicate ${fileLabel} entry in intentionalRemovals for target "${entry.target}".`
      );
    }
    removalMap.set(entry.target, entry);
  }

  return removalMap;
}

export function compareCompatibilityBaselines(baseBaseline, currentBaseline, intentionalRemovals = new Map()) {
  const regressions = [];
  const check = (target, condition, detail) => {
    if (condition || intentionalRemovals.has(target)) return;
    regressions.push(`${target} (${detail})`);
  };

  // 1. Protected Design Tokens
  const baseTokens = baseBaseline?.protectedDesignTokens ?? {};
  const curTokens = currentBaseline?.protectedDesignTokens ?? {};
  for (const [group, keys] of Object.entries(baseTokens.colors ?? {})) {
    const curSet = new Set(curTokens.colors?.[group] ?? []);
    for (const key of keys) {
      check(
        `design_tokens.colors.${group}.${key}`,
        curSet.has(key),
        'removed from compatibility baseline'
      );
    }
  }
  const curFamilies = new Set(curTokens.typography?.families ?? []);
  for (const fam of baseTokens.typography?.families ?? []) {
    check(`design_tokens.typography.${fam}`, curFamilies.has(fam), 'removed from compatibility baseline');
  }
  const curScale = new Set(curTokens.typography?.scale ?? []);
  for (const role of baseTokens.typography?.scale ?? []) {
    check(
      `design_tokens.typography.scale.${role}`,
      curScale.has(role),
      'removed from compatibility baseline'
    );
  }
  for (const section of ['spacing', 'radii', 'elevation', 'breakpoints']) {
    const curSectionSet = new Set(curTokens[section] ?? []);
    for (const key of baseTokens[section] ?? []) {
      check(
        `design_tokens.${section}.${key}`,
        curSectionSet.has(key),
        'removed from compatibility baseline'
      );
    }
  }

  // 2. Protected KnownSeedIds
  for (const [group, ids] of Object.entries(baseBaseline?.protectedKnownSeedIds ?? {})) {
    const curSet = new Set(currentBaseline?.protectedKnownSeedIds?.[group] ?? []);
    for (const id of ids) {
      check(`known_seed_ids.${group}.${id}`, curSet.has(id), 'removed from compatibility baseline');
    }
  }

  // 3. Protected System Control Account IDs
  for (const [key, expectedId] of Object.entries(baseBaseline?.protectedSystemControlAccountIds ?? {})) {
    check(
      `system_control_account_ids.${key}`,
      currentBaseline?.protectedSystemControlAccountIds?.[key] === expectedId,
      `modified or removed from compatibility baseline (expected "${expectedId}")`
    );
  }

  // 4. Protected Business Rule Keys
  for (const [section, keys] of Object.entries(baseBaseline?.protectedBusinessRuleKeys ?? {})) {
    const curSet = new Set(currentBaseline?.protectedBusinessRuleKeys?.[section] ?? []);
    for (const key of keys) {
      check(`business_rules.${section}.${key}`, curSet.has(key), 'removed from compatibility baseline');
    }
  }

  // 5. Protected Schema Contracts
  for (const [entityName, baseEntity] of Object.entries(baseBaseline?.protectedSchemaContracts ?? {})) {
    const curEntity = currentBaseline?.protectedSchemaContracts?.[entityName];
    check(
      `schema_contracts.entities.${entityName}`,
      Boolean(curEntity),
      'entity removed from compatibility baseline'
    );
    if (!curEntity) continue;

    for (const [fieldName, baseField] of Object.entries(baseEntity.fields ?? {})) {
      const curField = curEntity.fields?.[fieldName];
      check(
        `schema_contracts.entities.${entityName}.fields.${fieldName}`,
        Boolean(curField),
        'field removed from compatibility baseline'
      );
      if (!curField) continue;

      check(
        `schema_contracts.entities.${entityName}.fields.${fieldName}.type`,
        curField.type === baseField.type,
        `field type changed from "${baseField.type}" to ${JSON.stringify(curField.type)}`
      );
      if (baseField.required === true) {
        check(
          `schema_contracts.entities.${entityName}.fields.${fieldName}.required`,
          curField.required === true,
          'required constraint weakened in compatibility baseline'
        );
      }
      const curEnumSet = new Set(curField.enum ?? []);
      for (const enumVal of baseField.enum ?? []) {
        check(
          `schema_contracts.entities.${entityName}.fields.${fieldName}.enum.${enumVal}`,
          curEnumSet.has(enumVal),
          `enum value "${enumVal}" removed from compatibility baseline`
        );
      }
    }
  }

  if (regressions.length > 0) {
    throw new Error(
      `ADR-007 compatibility baseline modification/removal blocked against base revision:\n  - ${regressions.join('\n  - ')}\n` +
        `Breaking baseline changes require an accepted ADR under docs/architecture/decisions/ (with Justification, Migration Strategy, and Affected Consumers sections) and matching intentionalRemovals + verificationTests metadata.`
    );
  }
}

function runGit(rootDir, args) {
  return execFileSync('git', args, {
    cwd: rootDir,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
}

/**
 * @param {{ rootDir?: string; baseRev?: string | null; requireGitBase?: boolean; useCiEventEnv?: boolean }} [options]
 */
export function resolveBaselineGitComparison({
  rootDir = defaultRootDir,
  baseRev = null,
  requireGitBase = false,
  useCiEventEnv = false,
} = {}) {
  const isDefaultRoot = path.resolve(rootDir) === path.resolve(defaultRootDir);
  const inGitHubActions =
    process.env.GITHUB_ACTIONS === 'true' && (isDefaultRoot || Boolean(useCiEventEnv));
  const mustHaveGitBase = inGitHubActions || Boolean(requireGitBase) || Boolean(baseRev);

  let authoritativeRev = baseRev;

  if (inGitHubActions) {
    const eventPath = process.env.GITHUB_EVENT_PATH;
    if (!eventPath || !fs.existsSync(eventPath)) {
      throw new Error(
        'CI baseline diff failed closed: GITHUB_EVENT_PATH is missing or unreadable in GitHub Actions.'
      );
    }
    let eventPayload;
    try {
      eventPayload = JSON.parse(fs.readFileSync(eventPath, 'utf8'));
    } catch (err) {
      throw new Error(`CI baseline diff failed closed: invalid GITHUB_EVENT_PATH JSON (${err.message}).`);
    }

    const eventName = process.env.GITHUB_EVENT_NAME || '';
    let trustedBaseRef = null;
    if (eventName === 'pull_request' || eventName === 'pull_request_target') {
      trustedBaseRef = eventPayload?.pull_request?.base?.sha || null;
      if (!trustedBaseRef || ZERO_SHA_REGEX.test(trustedBaseRef)) {
        throw new Error(
          'CI baseline diff failed closed: pull_request base SHA is missing from GitHub event payload.'
        );
      }
    } else if (eventName === 'push') {
      const beforeSha = eventPayload?.before || '';
      if (beforeSha && !ZERO_SHA_REGEX.test(beforeSha)) {
        trustedBaseRef = beforeSha;
      } else {
        let countStr;
        try {
          countStr = runGit(rootDir, ['rev-list', '--count', 'HEAD']);
        } catch (err) {
          throw new Error(`CI baseline diff failed closed: unable to inspect push parent commit (${err.message}).`);
        }
        if (Number(countStr) <= 1) {
          return { status: 'initial-commit', baseCommitSha: null, baseBaseline: null };
        }
        trustedBaseRef = 'HEAD^';
      }
    } else {
      let countStr;
      try {
        countStr = runGit(rootDir, ['rev-list', '--count', 'HEAD']);
      } catch (err) {
        throw new Error(`CI baseline diff failed closed: unable to inspect Git history (${err.message}).`);
      }
      if (Number(countStr) <= 1) {
        return { status: 'initial-commit', baseCommitSha: null, baseBaseline: null };
      }
      trustedBaseRef = 'HEAD^';
    }

    let trustedSha;
    try {
      trustedSha = runGit(rootDir, ['rev-parse', '--verify', `${trustedBaseRef}^{commit}`]);
    } catch (err) {
      throw new Error(
        `CI baseline diff failed closed: authoritative base revision "${trustedBaseRef}" is unavailable in Git history ` +
          `(ensure checkout uses fetch-depth: 0). Git error: ${err.message}`
      );
    }

    if (baseRev) {
      let callerSha;
      try {
        callerSha = runGit(rootDir, ['rev-parse', '--verify', `${baseRev}^{commit}`]);
      } catch (err) {
        throw new Error(`CI baseline diff failed closed: invalid --base-rev "${baseRev}": ${err.message}`);
      }
      if (callerSha !== trustedSha) {
        throw new Error(
          `CI baseline diff failed closed: --base-rev "${baseRev}" (${callerSha}) cannot override CI event base revision (${trustedSha}).`
        );
      }
    }

    authoritativeRev = trustedSha;
  } else {
    let isGitRepo = false;
    try {
      isGitRepo = runGit(rootDir, ['rev-parse', '--is-inside-work-tree']) === 'true';
    } catch {
      isGitRepo = false;
    }

    if (!isGitRepo) {
      if (mustHaveGitBase) {
        throw new Error(
          `Git baseline comparison failed closed: "${rootDir}" is not inside a Git repository.`
        );
      }
      return { status: 'skipped-no-git', baseCommitSha: null, baseBaseline: null };
    }

    if (!authoritativeRev) {
      let countStr;
      try {
        countStr = runGit(rootDir, ['rev-list', '--count', 'HEAD']);
      } catch (err) {
        if (mustHaveGitBase) {
          throw new Error(`Git baseline comparison failed closed: ${err.message}`);
        }
        return { status: 'skipped-no-git', baseCommitSha: null, baseBaseline: null };
      }
      if (Number(countStr) <= 1) {
        return { status: 'initial-commit', baseCommitSha: null, baseBaseline: null };
      }
      authoritativeRev = 'HEAD^';
    }
  }

  let baseCommitSha;
  try {
    baseCommitSha = runGit(rootDir, ['rev-parse', '--verify', `${authoritativeRev}^{commit}`]);
  } catch (err) {
    throw new Error(
      `Git baseline comparison failed closed: base revision "${authoritativeRev}" could not be resolved (${err.message}).`
    );
  }

  try {
    execFileSync(
      'git',
      ['cat-file', '-e', `${baseCommitSha}:scripts/foundation_compatibility_baseline.json`],
      { cwd: rootDir, stdio: ['ignore', 'ignore', 'ignore'] }
    );
  } catch {
    return { status: 'baseline-introduced', baseCommitSha, baseBaseline: null };
  }

  let baseRaw;
  try {
    baseRaw = runGit(rootDir, ['show', `${baseCommitSha}:scripts/foundation_compatibility_baseline.json`]);
  } catch (err) {
    throw new Error(
      `Git baseline comparison failed closed: unable to read baseline from ${baseCommitSha}: ${err.message}`
    );
  }

  let baseBaseline;
  try {
    baseBaseline = JSON.parse(baseRaw);
  } catch (err) {
    throw new Error(
      `Git baseline comparison failed closed: invalid JSON in baseline at ${baseCommitSha}: ${err.message}`
    );
  }

  return { status: 'compared', baseCommitSha, baseBaseline };
}

function parseTsKnownSeedIds(tsSource) {
  const blockMatch = tsSource.match(/export const KNOWN_SEED_IDS = \{([\s\S]*?)\} as const;/);
  if (!blockMatch) {
    throw new Error('Generated TS foundation is missing KNOWN_SEED_IDS block.');
  }
  const result = {};
  for (const lineMatch of blockMatch[1].matchAll(/([A-Za-z0-9_]+)\s*:\s*\[([^\]]*)\]/g)) {
    const group = lineMatch[1];
    const ids = Array.from(lineMatch[2].matchAll(/'([^']+)'/g), (m) => m[1]);
    result[group] = new Set(ids);
  }
  return result;
}

function parseDartKnownSeedIds(dartCoreSource) {
  const classMatch = dartCoreSource.match(/class KnownSeedIds \{([\s\S]*?)static bool isKnownSeedId/);
  if (!classMatch) {
    throw new Error('Generated Dart core foundation is missing KnownSeedIds class.');
  }
  const result = {};
  for (const fieldMatch of classMatch[1].matchAll(/static const Set<String> ([A-Za-z0-9_]+)\s*=\s*\{([\s\S]*?)\};/g)) {
    const group = fieldMatch[1];
    const ids = Array.from(fieldMatch[2].matchAll(/'([^']+)'/g), (m) => m[1]);
    result[group] = new Set(ids);
  }
  return result;
}

function parseTsSystemControlAccountIds(tsSource) {
  const blockMatch = tsSource.match(
    /export const SYSTEM_CONTROL_ACCOUNT_IDS = \{([\s\S]*?)\} as const;/
  );
  if (!blockMatch) {
    throw new Error('Generated TS foundation is missing SYSTEM_CONTROL_ACCOUNT_IDS block.');
  }
  const result = {};
  for (const propMatch of blockMatch[1].matchAll(/([A-Za-z0-9_]+)\s*:\s*'([^']+)'/g)) {
    result[propMatch[1]] = propMatch[2];
  }
  return result;
}

function parseDartSystemControlAccountIds(dartEngineSource) {
  const classMatch = dartEngineSource.match(
    /class SystemControlAccounts \{([\s\S]*?)static const String feeCategoryId/
  );
  if (!classMatch) {
    throw new Error(
      'Unable to locate SystemControlAccounts IDs in flutter_app/lib/domain/finance/double_entry_engine.dart.'
    );
  }
  const result = {};
  for (const propMatch of classMatch[1].matchAll(
    /static const String ([A-Za-z0-9_]+)\s*=\s*'([^']+)';/g
  )) {
    result[propMatch[1]] = propMatch[2];
  }
  return result;
}

export function validateSchemaVersionGuard({ rootDir, contracts, requireAppDatabase = false }) {
  const appDbPath = path.join(rootDir, 'flutter_app', 'lib', 'data', 'database', 'app_database.dart');
  if (!fs.existsSync(appDbPath)) {
    if (requireAppDatabase) {
      throw new Error(
        `Missing Flutter AppDatabase file required for schema-version guard: ${appDbPath}`
      );
    }
    return null;
  }
  const appDbSource = fs.readFileSync(appDbPath, 'utf8');
  const match = appDbSource.match(/int\s+get\s+schemaVersion\s*=>\s*(\d+)\s*;/);
  if (!match) {
    throw new Error(
      `Unable to parse AppDatabase.schemaVersion from ${appDbPath}. Expected "int get schemaVersion => <int>;".`
    );
  }
  const appDbVersion = Number(match[1]);
  if (appDbVersion !== contracts.schemaVersion) {
    throw new Error(
      `Schema version mismatch: shared_foundation/schema_contracts.json declares schemaVersion=${contracts.schemaVersion}, ` +
        `while flutter_app/lib/data/database/app_database.dart declares schemaVersion=${appDbVersion}. ` +
        `Keep AppDatabase.schemaVersion and schema_contracts.json.schemaVersion aligned (note: canonical_seed_database.json schemaVersion=5 and SharedStateBridge=5 are intentionally separate).`
    );
  }
  return appDbVersion;
}

export function validateContractNonRegression({
  rootDir,
  tokens,
  rules,
  contracts,
  baseline,
  tsSource,
  dartCoreSource,
  requireDartEngine = false,
}) {
  const intentionalRemovals = parseIntentionalRemovals(baseline, rootDir);
  const violations = [];

  const checkProtected = (target, condition, detail) => {
    if (condition) return;
    if (intentionalRemovals.has(target)) return;
    violations.push(`${target} (${detail})`);
  };

  // 1. Protected Design Tokens
  const protectedTokens = baseline.protectedDesignTokens ?? {};
  for (const [group, keys] of Object.entries(protectedTokens.colors ?? {})) {
    for (const key of keys) {
      checkProtected(
        `design_tokens.colors.${group}.${key}`,
        Boolean(tokens.colors?.[group] && key in tokens.colors[group]),
        'missing protected design color token'
      );
    }
  }
  for (const fam of protectedTokens.typography?.families ?? []) {
    checkProtected(
      `design_tokens.typography.${fam}`,
      Boolean(tokens.typography && fam in tokens.typography),
      'missing protected typography family token'
    );
  }
  for (const role of protectedTokens.typography?.scale ?? []) {
    checkProtected(
      `design_tokens.typography.scale.${role}`,
      Boolean(tokens.typography?.scale && role in tokens.typography.scale),
      'missing protected typography scale role'
    );
  }
  for (const section of ['spacing', 'radii', 'elevation', 'breakpoints']) {
    for (const key of protectedTokens[section] ?? []) {
      checkProtected(
        `design_tokens.${section}.${key}`,
        Boolean(tokens[section] && key in tokens[section]),
        `missing protected ${section} token`
      );
    }
  }

  // 2. Protected KnownSeedIds across TypeScript & Dart
  const tsSeedIds = parseTsKnownSeedIds(tsSource);
  const dartSeedIds = parseDartKnownSeedIds(dartCoreSource);
  for (const [group, ids] of Object.entries(baseline.protectedKnownSeedIds ?? {})) {
    for (const id of ids) {
      const inTs = Boolean(tsSeedIds[group]?.has(id));
      const inDart = Boolean(dartSeedIds[group]?.has(id));
      checkProtected(
        `known_seed_ids.${group}.${id}`,
        inTs && inDart,
        `missing from ${!inTs ? 'TS KNOWN_SEED_IDS' : ''}${!inTs && !inDart ? ' and ' : ''}${!inDart ? 'Dart KnownSeedIds' : ''}`
      );
    }
  }

  // 3. Protected SYSTEM_CONTROL_ACCOUNT_IDS across TypeScript & Dart
  const tsControlIds = parseTsSystemControlAccountIds(tsSource);
  const dartEnginePath = path.join(
    rootDir,
    'flutter_app',
    'lib',
    'domain',
    'finance',
    'double_entry_engine.dart'
  );
  let dartControlIds = null;
  if (fs.existsSync(dartEnginePath)) {
    dartControlIds = parseDartSystemControlAccountIds(fs.readFileSync(dartEnginePath, 'utf8'));
  } else if (requireDartEngine) {
    throw new Error(
      `Missing Dart DoubleEntryEngine file required for control-account guard: ${dartEnginePath}`
    );
  }

  for (const [key, expectedId] of Object.entries(baseline.protectedSystemControlAccountIds ?? {})) {
    const tsMatches = tsControlIds[key] === expectedId;
    const dartMatches = dartControlIds === null || dartControlIds[key] === expectedId;
    checkProtected(
      `system_control_account_ids.${key}`,
      tsMatches && dartMatches,
      `expected "${expectedId}" in TS (got ${JSON.stringify(tsControlIds[key])})${
        dartControlIds ? ` and Dart (got ${JSON.stringify(dartControlIds[key])})` : ''
      }`
    );
  }

  // 4. Protected Business Rules Keys
  for (const [section, keys] of Object.entries(baseline.protectedBusinessRuleKeys ?? {})) {
    for (const key of keys) {
      checkProtected(
        `business_rules.${section}.${key}`,
        Boolean(rules?.[section] && key in rules[section]),
        'missing protected business rule key'
      );
    }
  }

  // 5. Protected Schema Contracts (entities, fields, types, required flags, enum values)
  for (const [entityName, entitySpec] of Object.entries(baseline.protectedSchemaContracts ?? {})) {
    const actualEntity = contracts.entities?.[entityName];
    checkProtected(
      `schema_contracts.entities.${entityName}`,
      Boolean(actualEntity),
      'missing protected schema entity'
    );
    if (!actualEntity) continue;

    for (const [fieldName, fieldSpec] of Object.entries(entitySpec.fields ?? {})) {
      const actualField = actualEntity.fields?.[fieldName];
      checkProtected(
        `schema_contracts.entities.${entityName}.fields.${fieldName}`,
        Boolean(actualField),
        'missing protected schema field'
      );
      if (!actualField) continue;

      checkProtected(
        `schema_contracts.entities.${entityName}.fields.${fieldName}.type`,
        actualField.type === fieldSpec.type,
        `field type changed from "${fieldSpec.type}" to ${JSON.stringify(actualField.type)}`
      );

      if (fieldSpec.required === true) {
        checkProtected(
          `schema_contracts.entities.${entityName}.fields.${fieldName}.required`,
          actualField.required === true,
          'required field was weakened to optional'
        );
      }

      for (const enumValue of fieldSpec.enum ?? []) {
        checkProtected(
          `schema_contracts.entities.${entityName}.fields.${fieldName}.enum.${enumValue}`,
          Array.isArray(actualField.enum) && actualField.enum.includes(enumValue),
          `enum value "${enumValue}" was removed`
        );
      }
    }
  }

  if (violations.length > 0) {
    throw new Error(
      `ADR-007 contract non-regression violation(s) detected:\n  - ${violations.join('\n  - ')}\n` +
        `Restore the removed contract(s) or document an explicit ADR-justified removal in scripts/foundation_compatibility_baseline.json ("intentionalRemovals").`
    );
  }
}

function prepareAndValidateFoundation({
  rootDir = defaultRootDir,
  requireBaseline = rootDir === defaultRootDir,
  requireAppDatabase = rootDir === defaultRootDir,
  requireDartEngine = rootDir === defaultRootDir,
  baseRev = null,
  requireGitBase = false,
  useCiEventEnv = false,
} = {}) {
  const isDefaultRoot = path.resolve(rootDir) === path.resolve(defaultRootDir);
  const mustHaveBaseline = requireBaseline || isDefaultRoot;
  const mustHaveAppDb = requireAppDatabase || isDefaultRoot;
  const mustHaveDartEngine = requireDartEngine || isDefaultRoot;

  const baselinePath = path.join(rootDir, 'scripts', 'foundation_compatibility_baseline.json');
  let baseline = null;
  let intentionalRemovals = new Map();
  let allowedRemovals = new Set();
  if (fs.existsSync(baselinePath)) {
    baseline = readJsonStrict(baselinePath, 'foundation_compatibility_baseline.json');
    intentionalRemovals = parseIntentionalRemovals(baseline, rootDir);
    allowedRemovals = new Set(intentionalRemovals.keys());
  } else if (mustHaveBaseline) {
    throw new Error(
      `Missing compatibility baseline required by ADR-007: ${baselinePath}`
    );
  }

  let baselineDiffStatus = 'none';
  if (baseline) {
    const gitComparison = resolveBaselineGitComparison({
      rootDir,
      baseRev,
      requireGitBase,
      useCiEventEnv,
    });
    baselineDiffStatus = gitComparison.status;
    if (gitComparison.baseBaseline) {
      compareCompatibilityBaselines(gitComparison.baseBaseline, baseline, intentionalRemovals);
    }
  }

  const tokensPath = path.join(rootDir, 'shared_foundation', 'design_tokens.json');
  const schemasPath = path.join(rootDir, 'shared_foundation', 'schema_contracts.json');
  const rulesPath = path.join(rootDir, 'shared_foundation', 'business_rules.json');
  const seedDbPath = path.join(rootDir, 'shared_foundation', 'canonical_seed_database.json');
  const vectorsPath = path.join(rootDir, 'shared_foundation', 'calendar_test_vectors.json');

  // Validate design_tokens.json first to keep targeted parse/token error reporting predictable
  const tokens = validateDesignTokens(readJsonStrict(tokensPath, 'design_tokens.json'), {
    allowedRemovals,
  });
  const contracts = validateSchemaContracts(readJsonStrict(schemasPath, 'schema_contracts.json'));
  const rules = validateBusinessRules(readJsonStrict(rulesPath, 'business_rules.json'));
  const seedDb = validateCanonicalSeedDatabase(
    readJsonStrict(seedDbPath, 'canonical_seed_database.json')
  );
  const vectors = validateCalendarTestVectors(
    readJsonStrict(vectorsPath, 'calendar_test_vectors.json')
  );

  validateSchemaVersionGuard({ rootDir, contracts, requireAppDatabase: mustHaveAppDb });

  const tsContent = buildTypeScriptFoundation({ tokens, rules, seedDb });
  const cssContent = buildCssTokensFoundation({ tokens });
  const dartCoreContent = buildDartFoundationCore({ seedDb });
  const dartContent = buildDartFoundation({ tokens });

  if (baseline) {
    validateContractNonRegression({
      rootDir,
      tokens,
      rules,
      contracts,
      baseline,
      tsSource: tsContent,
      dartCoreSource: dartCoreContent,
      requireDartEngine: mustHaveDartEngine,
    });
  }

  const tsPath = path.join(rootDir, 'src', 'domain', 'sharedFoundation.ts');
  const cssPath = path.join(rootDir, 'src', 'styles', 'daywellTokens.css');
  const dartCorePath = path.join(
    rootDir,
    'flutter_app',
    'lib',
    'core',
    'shared_foundation_core.dart'
  );
  const dartPath = path.join(rootDir, 'flutter_app', 'lib', 'core', 'shared_foundation.dart');

  return {
    tokens,
    contracts,
    rules,
    seedDb,
    vectors,
    baselineDiffStatus,
    outputs: [
      { label: 'src/domain/sharedFoundation.ts', filePath: tsPath, content: tsContent },
      { label: 'src/styles/daywellTokens.css', filePath: cssPath, content: cssContent },
      {
        label: 'flutter_app/lib/core/shared_foundation_core.dart',
        filePath: dartCorePath,
        content: dartCoreContent,
      },
      { label: 'flutter_app/lib/core/shared_foundation.dart', filePath: dartPath, content: dartContent },
    ],
  };
}

/**
 * @param {{ rootDir?: string; silent?: boolean; requireBaseline?: boolean; requireAppDatabase?: boolean; requireDartEngine?: boolean; baseRev?: string | null; requireGitBase?: boolean; useCiEventEnv?: boolean }} [options]
 */
export function checkFoundation({
  rootDir = defaultRootDir,
  silent = false,
  requireBaseline,
  requireAppDatabase,
  requireDartEngine,
  baseRev = null,
  requireGitBase = false,
  useCiEventEnv = false,
} = {}) {
  const { outputs, tokens, baselineDiffStatus } = prepareAndValidateFoundation({
    rootDir,
    requireBaseline,
    requireAppDatabase,
    requireDartEngine,
    baseRev,
    requireGitBase,
    useCiEventEnv,
  });

  const staleFiles = [];
  for (const { label, filePath, content } of outputs) {
    if (!fs.existsSync(filePath)) {
      staleFiles.push(`${label} (missing)`);
      continue;
    }
    const existing = fs.readFileSync(filePath, 'utf8');
    if (existing !== content) {
      staleFiles.push(`${label} (stale or manually modified)`);
    }
  }

  if (staleFiles.length > 0) {
    throw new Error(
      `Generated Shared Foundation files are out of sync:\n  - ${staleFiles.join('\n  - ')}\n` +
        `Run "npm run sync-foundation" to regenerate.`
    );
  }

  if (!silent) {
    console.log(
      `[sync_foundation] Foundation freshness, schemas, contracts, and schemaVersion check passed (baselineDiff=${baselineDiffStatus}).`
    );
  }

  return {
    fresh: true,
    baselineDiffStatus,
    tsPath: outputs[0].filePath,
    cssPath: outputs[1].filePath,
    dartCorePath: outputs[2].filePath,
    dartPath: outputs[3].filePath,
    tokens,
  };
}

/**
 * @param {{ rootDir?: string; silent?: boolean; requireBaseline?: boolean; requireAppDatabase?: boolean; requireDartEngine?: boolean; baseRev?: string | null; requireGitBase?: boolean; useCiEventEnv?: boolean }} [options]
 */
export function syncFoundation({
  rootDir = defaultRootDir,
  silent = false,
  requireBaseline,
  requireAppDatabase,
  requireDartEngine,
  baseRev = null,
  requireGitBase = false,
  useCiEventEnv = false,
} = {}) {
  const { outputs, tokens, baselineDiffStatus } = prepareAndValidateFoundation({
    rootDir,
    requireBaseline,
    requireAppDatabase,
    requireDartEngine,
    baseRev,
    requireGitBase,
    useCiEventEnv,
  });

  if (!silent) {
    console.log('[sync_foundation] Reading shared foundation specifications...');
  }

  for (const { filePath, content } of outputs) {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, content, 'utf8');
    if (!silent) {
      console.log(`[sync_foundation] Generated: ${filePath}`);
    }
  }

  if (!silent) {
    console.log(
      `[sync_foundation] Shared foundation generation complete! (baselineDiff=${baselineDiffStatus})`
    );
  }

  return {
    tsPath: outputs[0].filePath,
    cssPath: outputs[1].filePath,
    dartCorePath: outputs[2].filePath,
    dartPath: outputs[3].filePath,
    baselineDiffStatus,
    tokens,
  };
}

const isCliEntry =
  Boolean(process.argv[1]) &&
  pathToFileURL(fs.realpathSync(process.argv[1])).href === pathToFileURL(fs.realpathSync(__filename)).href;

if (isCliEntry) {
  try {
    const rootFlagIdx = process.argv.indexOf('--root');
    const cliRootDir =
      rootFlagIdx !== -1 && process.argv[rootFlagIdx + 1]
        ? path.resolve(process.argv[rootFlagIdx + 1])
        : defaultRootDir;
    const baseRevFlagIdx = process.argv.indexOf('--base-rev');
    const cliBaseRev =
      baseRevFlagIdx !== -1 && process.argv[baseRevFlagIdx + 1]
        ? process.argv[baseRevFlagIdx + 1]
        : null;
    const cliCiFlag = process.argv.includes('--ci');
    const cliRequireGitBase = cliCiFlag || process.argv.includes('--require-git-base');
    const isCheckMode = process.argv.includes('--check');
    if (isCheckMode) {
      checkFoundation({
        rootDir: cliRootDir,
        baseRev: cliBaseRev,
        requireGitBase: cliRequireGitBase,
        useCiEventEnv: cliCiFlag,
      });
    } else {
      syncFoundation({
        rootDir: cliRootDir,
        baseRev: cliBaseRev,
        requireGitBase: cliRequireGitBase,
        useCiEventEnv: cliCiFlag,
      });
    }
  } catch (err) {
    console.error(`[sync_foundation] ERROR: ${err.message}`);
    process.exit(1);
  }
}
