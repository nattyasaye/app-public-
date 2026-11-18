import 'dart:math';
import '../../core/date/shared_date.dart';
import 'finance_models.dart';

/// Domain models and business logic for the Simplified Double-Entry Accounting Ledger.
///
/// Invariant: For every Journal Entry, Sum of Debits == Sum of Credits.
/// Units: Integer Minor Units (1 ETB = 100 cents / ሳንቲም).

enum AccountType { asset, liability, equity, income, expense }

enum AccountSubType {
  cash('cash'),
  bank('bank'),
  mobileMoney('mobile_money'),
  savingsVault('savings_vault'),
  creditCard('credit_card'),
  receivable('receivable'),
  payable('payable'),
  openingEquity('opening_equity'),
  nominalIncome('nominal_income'),
  nominalExpense('nominal_expense'),
  legacyClearing('legacy_clearing');

  final String dbValue;
  const AccountSubType(this.dbValue);

  bool get isLiquid =>
      this == AccountSubType.cash ||
      this == AccountSubType.bank ||
      this == AccountSubType.mobileMoney;

  bool get isSavingsVault => this == AccountSubType.savingsVault;

  bool get isCreditCard => this == AccountSubType.creditCard;

  bool get isSystemControl =>
      this == AccountSubType.receivable ||
      this == AccountSubType.payable ||
      this == AccountSubType.openingEquity ||
      this == AccountSubType.nominalIncome ||
      this == AccountSubType.nominalExpense ||
      this == AccountSubType.legacyClearing;

  static AccountSubType fromDbValue(
    String? raw, {
    AccountType fallbackType = AccountType.asset,
  }) {
    if (raw != null && raw.trim().isNotEmpty) {
      for (final value in AccountSubType.values) {
        if (value.dbValue == raw || value.name == raw) {
          return value;
        }
      }
    }
    return defaultForType(fallbackType);
  }

  static AccountSubType defaultForType(AccountType type) {
    switch (type) {
      case AccountType.asset:
        return AccountSubType.cash;
      case AccountType.liability:
        return AccountSubType.creditCard;
      case AccountType.equity:
        return AccountSubType.openingEquity;
      case AccountType.income:
        return AccountSubType.nominalIncome;
      case AccountType.expense:
        return AccountSubType.nominalExpense;
    }
  }
}

class SystemControlAccounts {
  static const String equity = 'acc-sys-equity';
  static const String income = 'acc-sys-income';
  static const String expense = 'acc-sys-expense';
  static const String receivable = 'acc-sys-receivable';
  static const String payable = 'acc-sys-payable';
  static const String legacyOffset = 'acc-sys-legacy-offset';

  static const String feeCategoryId = 'cat-fees';
  static const String interestExpenseCategoryId = 'cat-interest-exp';
  static const String interestIncomeCategoryId = 'cat-interest-inc';

  static const Set<String> allIds = {
    equity,
    income,
    expense,
    receivable,
    payable,
    legacyOffset,
  };

  static bool isSystemControlId(String id) => allIds.contains(id);
}

enum EntryType {
  standard('standard'),
  transfer('transfer'),
  debtIssuance('debt_issuance'),
  settlement('settlement'),
  splitExpense('split_expense'),
  adjustment('adjustment'),
  writeOff('write_off');

  final String dbValue;
  const EntryType(this.dbValue);

  static const Map<String, EntryType> legacyAliases = {
    'debtIssuance': EntryType.debtIssuance,
    'splitExpense': EntryType.splitExpense,
    'writeOff': EntryType.writeOff,
    'debt_origin': EntryType.debtIssuance,
    'debt_settlement': EntryType.settlement,
    'opening_balance': EntryType.adjustment,
    'opening': EntryType.adjustment,
    'correction': EntryType.adjustment,
    'void_reversal': EntryType.adjustment,
  };

  static EntryType? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim();
    if (normalized.isEmpty) return null;
    for (final value in EntryType.values) {
      if (value.dbValue == normalized) {
        return value;
      }
    }
    return legacyAliases[normalized];
  }

  static EntryType fromDbValue(String? raw) {
    final parsed = tryParse(raw);
    if (parsed == null) {
      throw ArgumentError.value(
        raw,
        'entryType',
        'Unsupported EntryType value',
      );
    }
    return parsed;
  }
}

enum PostingDirection { debit, credit }

enum DebtType { receivable, payable }

enum DebtStatus {
  active('active'),
  settled('settled'),
  writtenOff('written_off'),
  voided('voided');

  final String dbValue;
  const DebtStatus(this.dbValue);

  static const Map<String, DebtStatus> legacyAliases = {
    'partially_settled': DebtStatus.active,
    'writtenOff': DebtStatus.writtenOff,
  };

  static DebtStatus? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim();
    if (normalized.isEmpty) return null;
    for (final s in DebtStatus.values) {
      if (s.dbValue == normalized) {
        return s;
      }
    }
    return legacyAliases[normalized];
  }

  static DebtStatus fromDbValue(String? raw) {
    final parsed = tryParse(raw);
    if (parsed == null) {
      throw ArgumentError.value(
        raw,
        'status',
        'Unsupported DebtStatus value',
      );
    }
    return parsed;
  }
}

class DoubleEntryValidationError extends StateError {
  DoubleEntryValidationError(super.message);
}

class LedgerMigrationException implements Exception {
  final String message;
  final Object? cause;
  final Map<String, dynamic>? report;

  const LedgerMigrationException(this.message, {this.cause, this.report});

  @override
  String toString() => 'LedgerMigrationException: $message';
}

class DatabaseCorruptionException implements Exception {
  final String message;
  final String? recoveryBundlePath;
  final Object? cause;

  const DatabaseCorruptionException(
    this.message, {
    this.recoveryBundlePath,
    this.cause,
  });

  @override
  String toString() => 'DatabaseCorruptionException: $message';
}

class MigrationDiagnosticReport {
  final int fromVersion;
  final int toVersion;
  final String migratedAtIso;
  final int accountsAudited;
  final int entriesCreated;
  final int legacyPaidFlaggedCount;
  final List<String> warnings;
  final List<String> errors;
  final String summary;

  const MigrationDiagnosticReport({
    required this.fromVersion,
    required this.toVersion,
    required this.migratedAtIso,
    required this.accountsAudited,
    required this.entriesCreated,
    this.legacyPaidFlaggedCount = 0,
    this.warnings = const [],
    this.errors = const [],
    required this.summary,
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'fromVersion': fromVersion,
        'toVersion': toVersion,
        'migratedAtIso': migratedAtIso,
        'accountsAudited': accountsAudited,
        'entriesCreated': entriesCreated,
        'legacyPaidFlaggedCount': legacyPaidFlaggedCount,
        'warnings': warnings,
        'errors': errors,
        'summary': summary,
      };

  factory MigrationDiagnosticReport.fromJson(Map<String, dynamic> json) {
    return MigrationDiagnosticReport(
      fromVersion: (json['fromVersion'] as int?) ?? 0,
      toVersion: (json['toVersion'] as int?) ?? 7,
      migratedAtIso: json['migratedAtIso']?.toString() ?? '',
      accountsAudited: (json['accountsAudited'] as int?) ?? 0,
      entriesCreated: (json['entriesCreated'] as int?) ?? 0,
      legacyPaidFlaggedCount: (json['legacyPaidFlaggedCount'] as int?) ?? 0,
      warnings: (json['warnings'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const [],
      errors: (json['errors'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const [],
      summary: json['summary']?.toString() ?? '',
    );
  }
}

class DebtControlAuditReport {
  final int receivableControlBalanceCents;
  final int activeReceivableSumCents;
  final int payableControlBalanceCents;
  final int activePayableSumCents;
  final List<String> mismatchDetails;

  const DebtControlAuditReport({
    required this.receivableControlBalanceCents,
    required this.activeReceivableSumCents,
    required this.payableControlBalanceCents,
    required this.activePayableSumCents,
    this.mismatchDetails = const [],
  });

  bool get isTierABalanced =>
      receivableControlBalanceCents == activeReceivableSumCents &&
      payableControlBalanceCents == activePayableSumCents &&
      mismatchDetails.isEmpty;

  int get receivableDeltaCents =>
      receivableControlBalanceCents - activeReceivableSumCents;
  int get payableDeltaCents =>
      payableControlBalanceCents - activePayableSumCents;
}

class ExpenseRefundSummary {
  final bool eligible;
  final String? reason;
  final int originalAmountCents;
  final int refundedCents;
  final int remainingRefundableCents;
  final String? categoryId;
  final String? originalAccountId;
  final String? originalOccurrenceDate;

  const ExpenseRefundSummary({
    required this.eligible,
    this.reason,
    required this.originalAmountCents,
    required this.refundedCents,
    required this.remainingRefundableCents,
    this.categoryId,
    this.originalAccountId,
    this.originalOccurrenceDate,
  });
}

class AccountModel {
  final String id;
  final String name;
  final AccountType type;
  final AccountSubType subType;
  final bool isSystem;
  final String currencyCode; // Default 'ETB'
  final bool isArchived;
  final int openingBalanceCents;
  final String openingBalanceDate;
  final DateTime createdAt;

  AccountModel({
    required this.id,
    required this.name,
    required this.type,
    AccountSubType? subType,
    bool? isSystem,
    this.currencyCode = 'ETB',
    this.isArchived = false,
    this.openingBalanceCents = 0,
    String? openingBalanceDate,
    DateTime? createdAt,
  })  : subType = subType ?? AccountSubType.defaultForType(type),
        isSystem = isSystem ?? SystemControlAccounts.isSystemControlId(id),
        openingBalanceDate = _normalizeOptionalOpeningDate(openingBalanceDate),
        createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc();

  static String _normalizeOptionalOpeningDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return CalendarDate.today().toIsoString();
    }
    return SharedDateFormatter.parseFlexibleToCalendarDate(raw).toIsoString();
  }

  AccountModel copyWith({
    String? name,
    AccountType? type,
    AccountSubType? subType,
    bool? isSystem,
    String? currencyCode,
    bool? isArchived,
    int? openingBalanceCents,
    String? openingBalanceDate,
  }) {
    return AccountModel(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      subType: subType ?? this.subType,
      isSystem: isSystem ?? this.isSystem,
      currencyCode: currencyCode ?? this.currencyCode,
      isArchived: isArchived ?? this.isArchived,
      openingBalanceCents: openingBalanceCents ?? this.openingBalanceCents,
      openingBalanceDate: openingBalanceDate ?? this.openingBalanceDate,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'subType': subType.dbValue,
        'isSystem': isSystem,
        'currencyCode': currencyCode,
        'isArchived': isArchived,
        'openingBalanceCents': openingBalanceCents,
        'openingBalanceDate': openingBalanceDate,
        'createdAt': EthiopiaClock.toUtcIsoString(createdAt),
      };

  factory AccountModel.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final type = AccountType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => AccountType.asset,
    );
    final rawIsSystem = json['isSystem'] as bool?;
    final resolvedIsSystem =
        rawIsSystem ?? SystemControlAccounts.isSystemControlId(id);
    return AccountModel(
      id: id,
      name: json['name']?.toString() ?? '',
      type: type,
      subType: AccountSubType.fromDbValue(
        json['subType']?.toString(),
        fallbackType: type,
      ),
      isSystem: rawIsSystem,
      currencyCode:
          json['currencyCode']?.toString() ?? (resolvedIsSystem ? 'ETB' : ''),
      isArchived: (json['isArchived'] as bool?) ?? false,
      openingBalanceCents: (json['openingBalanceCents'] as int?) ?? 0,
      openingBalanceDate: json['openingBalanceDate']?.toString(),
      createdAt: EthiopiaClock.tryParseInstantUtc(
        json['createdAt']?.toString(),
      ),
    );
  }
}

class PartyModel {
  final String id;
  final String name;
  final String? phone;
  final String? notes;
  final bool isArchived;
  final DateTime createdAt;

  PartyModel({
    required this.id,
    required this.name,
    this.phone,
    this.notes,
    this.isArchived = false,
    DateTime? createdAt,
  }) : createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc();

  PartyModel copyWith({
    String? name,
    String? phone,
    String? notes,
    bool? isArchived,
  }) {
    return PartyModel(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      notes: notes ?? this.notes,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'notes': notes,
        'isArchived': isArchived,
        'createdAt': EthiopiaClock.toUtcIsoString(createdAt),
      };

  factory PartyModel.fromJson(Map<String, dynamic> json) => PartyModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        phone: json['phone']?.toString(),
        notes: json['notes']?.toString(),
        isArchived: (json['isArchived'] as bool?) ?? false,
        createdAt:
            EthiopiaClock.tryParseInstantUtc(json['createdAt']?.toString()),
      );
}

class JournalEntryModel {
  final String id;
  final EntryType entryType;
  final String description;
  final String occurrenceDate; // YYYY-MM-DD
  final bool isVoided;
  final String? voidReason;
  final String? legacySourceTxId;
  final String? correctedFromEntryId;
  final DateTime createdAt;

  JournalEntryModel({
    required this.id,
    required this.entryType,
    required this.description,
    required String occurrenceDate,
    this.isVoided = false,
    this.voidReason,
    this.legacySourceTxId,
    this.correctedFromEntryId,
    DateTime? createdAt,
  })  : occurrenceDate =
            SharedDateFormatter.parseFlexibleToCalendarDate(occurrenceDate)
                .toIsoString(),
        createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc();

  JournalEntryModel copyWith({
    bool? isVoided,
    String? voidReason,
    String? legacySourceTxId,
    String? correctedFromEntryId,
  }) {
    return JournalEntryModel(
      id: id,
      entryType: entryType,
      description: description,
      occurrenceDate: occurrenceDate,
      isVoided: isVoided ?? this.isVoided,
      voidReason: voidReason ?? this.voidReason,
      legacySourceTxId: legacySourceTxId ?? this.legacySourceTxId,
      correctedFromEntryId: correctedFromEntryId ?? this.correctedFromEntryId,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'entryType': entryType.dbValue,
        'description': description,
        'occurrenceDate': occurrenceDate,
        'isVoided': isVoided,
        'voidReason': voidReason,
        'legacySourceTxId': legacySourceTxId,
        'correctedFromEntryId': correctedFromEntryId,
        'createdAt': EthiopiaClock.toUtcIsoString(createdAt),
      };

  factory JournalEntryModel.fromJson(Map<String, dynamic> json) {
    final rawEntryType = json['entryType'];
    if (rawEntryType != null && rawEntryType is! String) {
      throw ArgumentError.value(
        rawEntryType,
        'entryType',
        'Expected string for entryType',
      );
    }
    final parsedEntryType = rawEntryType == null
        ? EntryType.standard
        : EntryType.fromDbValue(rawEntryType as String);
    return JournalEntryModel(
      id: json['id']?.toString() ?? '',
      entryType: parsedEntryType,
      description: json['description']?.toString() ?? '',
      occurrenceDate: json['occurrenceDate'].toString(),
      isVoided: (json['isVoided'] as bool?) ?? false,
      voidReason: json['voidReason']?.toString(),
      legacySourceTxId: json['legacySourceTxId']?.toString(),
      correctedFromEntryId: json['correctedFromEntryId']?.toString(),
      createdAt:
          EthiopiaClock.tryParseInstantUtc(json['createdAt']?.toString()),
    );
  }
}

class PostingModel {
  final String id;
  final String entryId;
  final String accountId;
  final int amountCents; // Strictly > 0
  final PostingDirection direction;
  final String accountMovementDate; // YYYY-MM-DD
  final String? categoryId;
  final String? note;

  PostingModel({
    required this.id,
    required this.entryId,
    required this.accountId,
    required this.amountCents,
    required this.direction,
    required String accountMovementDate,
    this.categoryId,
    this.note,
  }) : accountMovementDate =
            SharedDateFormatter.parseFlexibleToCalendarDate(accountMovementDate)
                .toIsoString() {
    if (amountCents <= 0) {
      throw ArgumentError(
          'Posting amount must be strictly greater than 0, got $amountCents');
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'entryId': entryId,
        'accountId': accountId,
        'amountCents': amountCents,
        'direction': direction.name,
        'accountMovementDate': accountMovementDate,
        'categoryId': categoryId,
        'note': note,
      };

  factory PostingModel.fromJson(Map<String, dynamic> json) => PostingModel(
        id: json['id'],
        entryId: json['entryId'],
        accountId: json['accountId'],
        amountCents: json['amountCents'],
        direction: PostingDirection.values
            .firstWhere((e) => e.name == json['direction']),
        accountMovementDate: json['accountMovementDate'].toString(),
        categoryId: json['categoryId'],
        note: json['note'],
      );
}

class DebtModel {
  final String id;
  final String originEntryId;
  final String partyId;
  final DebtType debtType;
  final int principalCents;
  final int outstandingCents;
  final String? dueDate;
  final DebtStatus status;
  final String? writeOffEntryId;
  final DateTime createdAt;

  DebtModel({
    required this.id,
    required this.originEntryId,
    required this.partyId,
    required this.debtType,
    required this.principalCents,
    required this.outstandingCents,
    String? dueDate,
    this.status = DebtStatus.active,
    this.writeOffEntryId,
    DateTime? createdAt,
  })  : dueDate = _normalizeOptionalDueDate(dueDate),
        createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc();

  static String? _normalizeOptionalDueDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return SharedDateFormatter.parseFlexibleToCalendarDate(raw).toIsoString();
  }

  DebtModel copyWith({
    int? outstandingCents,
    String? dueDate,
    bool clearDueDate = false,
    DebtStatus? status,
    String? writeOffEntryId,
    bool clearWriteOffEntryId = false,
  }) {
    return DebtModel(
      id: id,
      originEntryId: originEntryId,
      partyId: partyId,
      debtType: debtType,
      principalCents: principalCents,
      outstandingCents: outstandingCents ?? this.outstandingCents,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      status: status ?? this.status,
      writeOffEntryId: clearWriteOffEntryId
          ? null
          : (writeOffEntryId ?? this.writeOffEntryId),
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'originEntryId': originEntryId,
        'partyId': partyId,
        'debtType': debtType.name,
        'principalCents': principalCents,
        'outstandingCents': outstandingCents,
        'dueDate': dueDate,
        'status': status.dbValue,
        'writeOffEntryId': writeOffEntryId,
        'createdAt': EthiopiaClock.toUtcIsoString(createdAt),
      };

  factory DebtModel.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'];
    if (rawStatus != null && rawStatus is! String) {
      throw ArgumentError.value(
        rawStatus,
        'status',
        'Expected string for status',
      );
    }
    final parsedStatus = rawStatus == null
        ? DebtStatus.active
        : DebtStatus.fromDbValue(rawStatus as String);
    return DebtModel(
      id: json['id'],
      originEntryId: json['originEntryId'],
      partyId: json['partyId'],
      debtType: DebtType.values.firstWhere((e) => e.name == json['debtType']),
      principalCents: json['principalCents'],
      outstandingCents: json['outstandingCents'],
      dueDate: json['dueDate']?.toString(),
      status: parsedStatus,
      writeOffEntryId: json['writeOffEntryId']?.toString(),
      createdAt:
          EthiopiaClock.tryParseInstantUtc(json['createdAt']?.toString()),
    );
  }
}

class SettlementAllocationModel {
  final String id;
  final String settlementEntryId;
  final String debtId;
  final int allocatedCents;
  final String settlementDate;

  SettlementAllocationModel({
    required this.id,
    required this.settlementEntryId,
    required this.debtId,
    required this.allocatedCents,
    required String settlementDate,
  }) : settlementDate =
            SharedDateFormatter.parseFlexibleToCalendarDate(settlementDate)
                .toIsoString();

  Map<String, dynamic> toJson() => {
        'id': id,
        'settlementEntryId': settlementEntryId,
        'debtId': debtId,
        'allocatedCents': allocatedCents,
        'settlementDate': settlementDate,
      };

  factory SettlementAllocationModel.fromJson(Map<String, dynamic> json) =>
      SettlementAllocationModel(
        id: json['id'],
        settlementEntryId: json['settlementEntryId'],
        debtId: json['debtId'],
        allocatedCents: json['allocatedCents'],
        settlementDate: json['settlementDate'].toString(),
      );
}

// ----------------------------------------------------------------------------
// Double-Entry Engine & Calculation Formulas
// ----------------------------------------------------------------------------

enum CurrencyValidationTier {
  verifiedEtb,
  verifiedNonEtb,
  unverified,
}

enum EntryCurrencyStatus {
  eligibleEtb,
  excludedNonEtb,
  mixedOrAmbiguous,
  inactiveOrVoided,
}

enum CommitmentCurrencyStatus {
  eligibleEtb,
  excludedNonEtb,
  needsReview,
}

class CommitmentCurrencyResolution {
  final CommitmentCurrencyStatus status;
  final String? currencyCode;
  final bool isUnlinkedAssumedEtb;
  final bool isExpectedIncome;
  final String? reason;

  const CommitmentCurrencyResolution({
    required this.status,
    this.currencyCode,
    this.isUnlinkedAssumedEtb = false,
    this.isExpectedIncome = false,
    this.reason,
  });

  bool get isEligibleEtb => status == CommitmentCurrencyStatus.eligibleEtb;
  bool get isExcludedNonEtb =>
      status == CommitmentCurrencyStatus.excludedNonEtb;
  bool get needsReview => status == CommitmentCurrencyStatus.needsReview;
}

class EntryCurrencyClassification {
  final String entryId;
  final EntryCurrencyStatus status;
  final String? nativeCurrencyCode;
  final Set<String> touchedCurrencies;
  final String? reason;

  const EntryCurrencyClassification({
    required this.entryId,
    required this.status,
    this.nativeCurrencyCode,
    this.touchedCurrencies = const {},
    this.reason,
  });

  bool get isEligibleEtb => status == EntryCurrencyStatus.eligibleEtb;
  bool get isExcludedNonEtb => status == EntryCurrencyStatus.excludedNonEtb;
  bool get needsCurrencyReview =>
      status == EntryCurrencyStatus.mixedOrAmbiguous;
  bool get isInactiveOrVoided => status == EntryCurrencyStatus.inactiveOrVoided;
}

class CurrencyIsolationAudit {
  final Map<String, EntryCurrencyClassification> classificationsByEntryId;
  final int nonEtbAccountCount;
  final int unverifiedAccountCount;
  final int excludedNonEtbEntryCount;
  final int currencyReviewEntryCount;
  final int excludedNonEtbDebtCount;
  final int excludedNonEtbCommitmentCount;
  final int excludedVaultGoalCount;
  final List<String> warnings;

  const CurrencyIsolationAudit({
    required this.classificationsByEntryId,
    required this.nonEtbAccountCount,
    this.unverifiedAccountCount = 0,
    required this.excludedNonEtbEntryCount,
    required this.currencyReviewEntryCount,
    this.excludedNonEtbDebtCount = 0,
    this.excludedNonEtbCommitmentCount = 0,
    this.excludedVaultGoalCount = 0,
    this.warnings = const [],
  });

  bool get hasCurrencyReviewIssues =>
      currencyReviewEntryCount > 0 ||
      unverifiedAccountCount > 0 ||
      excludedVaultGoalCount > 0;
}

class _FinancialCurrencyScan {
  final int financialLegCount;
  final List<String> financialCurrencies;
  final bool hasUnverifiedFinancial;
  final bool touchesLegacyClearing;
  final String? missingAccountId;

  const _FinancialCurrencyScan({
    required this.financialLegCount,
    required this.financialCurrencies,
    required this.hasUnverifiedFinancial,
    required this.touchesLegacyClearing,
    this.missingAccountId,
  });
}

class DoubleEntryEngine {
  static const Set<String> _iso4217RecognizedCodes = {
    'AED',
    'AFN',
    'ALL',
    'AMD',
    'ANG',
    'AOA',
    'ARS',
    'AUD',
    'AWG',
    'AZN',
    'BAM',
    'BBD',
    'BDT',
    'BGN',
    'BHD',
    'BIF',
    'BMD',
    'BND',
    'BOB',
    'BRL',
    'BSD',
    'BTN',
    'BWP',
    'BYN',
    'BZD',
    'CAD',
    'CDF',
    'CHF',
    'CLP',
    'CNY',
    'COP',
    'CRC',
    'CUP',
    'CVE',
    'CZK',
    'DJF',
    'DKK',
    'DOP',
    'DZD',
    'EGP',
    'ERN',
    'ETB',
    'EUR',
    'FJD',
    'FKP',
    'GBP',
    'GEL',
    'GHS',
    'GIP',
    'GMD',
    'GNF',
    'GTQ',
    'GYD',
    'HKD',
    'HNL',
    'HTG',
    'HUF',
    'IDR',
    'ILS',
    'INR',
    'IQD',
    'IRR',
    'ISK',
    'JMD',
    'JOD',
    'JPY',
    'KES',
    'KGS',
    'KHR',
    'KMF',
    'KPW',
    'KRW',
    'KWD',
    'KYD',
    'KZT',
    'LAK',
    'LBP',
    'LKR',
    'LRD',
    'LSL',
    'LYD',
    'MAD',
    'MDL',
    'MGA',
    'MKD',
    'MMK',
    'MNT',
    'MOP',
    'MRU',
    'MUR',
    'MVR',
    'MWK',
    'MXN',
    'MYR',
    'MZN',
    'NAD',
    'NGN',
    'NIO',
    'NOK',
    'NPR',
    'NZD',
    'OMR',
    'PAB',
    'PEN',
    'PGK',
    'PHP',
    'PKR',
    'PLN',
    'PYG',
    'QAR',
    'RON',
    'RSD',
    'RUB',
    'RWF',
    'SAR',
    'SBD',
    'SCR',
    'SDG',
    'SEK',
    'SGD',
    'SHP',
    'SLE',
    'SLL',
    'SOS',
    'SRD',
    'SSP',
    'STN',
    'SYP',
    'SZL',
    'THB',
    'TJS',
    'TMT',
    'TND',
    'TOP',
    'TRY',
    'TTD',
    'TWD',
    'TZS',
    'UAH',
    'UGX',
    'USD',
    'UYU',
    'UZS',
    'VES',
    'VND',
    'VUV',
    'WST',
    'XAF',
    'XCD',
    'XOF',
    'XPF',
    'YER',
    'ZAR',
    'ZMW',
    'ZWL',
  };

  static String normalizeCurrencyCode(String? currencyCode) =>
      (currencyCode ?? '').trim().toUpperCase();

  static CurrencyValidationTier classifyCurrencyCode(String? currencyCode) {
    final norm = normalizeCurrencyCode(currencyCode);
    if (norm == 'ETB') return CurrencyValidationTier.verifiedEtb;
    if (norm.length == 3 && _iso4217RecognizedCodes.contains(norm)) {
      return CurrencyValidationTier.verifiedNonEtb;
    }
    return CurrencyValidationTier.unverified;
  }

  static bool isValidCurrencyCode(String? currencyCode) =>
      classifyCurrencyCode(currencyCode) != CurrencyValidationTier.unverified;

  static bool isEtb(String? currencyCode) =>
      classifyCurrencyCode(currencyCode) == CurrencyValidationTier.verifiedEtb;

  static bool isActiveVerifiedEtbAccount(AccountModel? account) {
    if (account == null) return false;
    if (account.isSystem || account.isArchived) return false;
    if (SystemControlAccounts.isSystemControlId(account.id)) return false;
    if (account.subType.isSystemControl) return false;
    return isEtb(account.currencyCode);
  }

  static void assertVerifiedEtbAccount(
    AccountModel? account, {
    String roleLabel = 'Account',
  }) {
    if (account == null) {
      throw DoubleEntryValidationError('$roleLabel not found.');
    }
    if (account.isArchived) {
      throw DoubleEntryValidationError(
        '$roleLabel "${account.name}" is archived or inactive.',
      );
    }
    if (account.isSystem ||
        SystemControlAccounts.isSystemControlId(account.id)) {
      throw DoubleEntryValidationError(
        '$roleLabel "${account.name}" is a system control account.',
      );
    }
    final tier = classifyCurrencyCode(account.currencyCode);
    if (tier != CurrencyValidationTier.verifiedEtb) {
      final codeLabel = tier == CurrencyValidationTier.verifiedNonEtb
          ? normalizeCurrencyCode(account.currencyCode)
          : 'Unverified';
      throw DoubleEntryValidationError(
        'First-release reporting supports ETB writes only; '
        '${roleLabel.toLowerCase()} "${account.name}" ($codeLabel) '
        'cannot receive new postings.',
      );
    }
  }

  static void assertEtbPostingAccounts({
    required List<AccountModel> accounts,
    required Iterable<String?> accountIds,
    List<String>? roleLabels,
  }) {
    final byId = {for (final a in accounts) a.id: a};
    var idx = 0;
    for (final id in accountIds) {
      final label = (roleLabels != null && idx < roleLabels.length)
          ? roleLabels[idx]
          : 'Account';
      idx++;
      if (id == null) continue;
      final acc = byId[id];
      if (_isLegacyClearingAccount(acc, id)) {
        throw DoubleEntryValidationError(
          'Legacy clearing offset account (acc-sys-legacy-offset) cannot receive new postings.',
        );
      }
      if (SystemControlAccounts.isSystemControlId(id)) continue;
      assertVerifiedEtbAccount(acc, roleLabel: label);
    }
  }

  static void assertEtbDebtEligible({
    required DebtModel debt,
    required List<AccountModel> accounts,
    required List<JournalEntryModel> entries,
    required List<PostingModel> postings,
    List<SettlementAllocationModel>? allocations,
  }) {
    final classifications = classifyAllEntries(
      accounts: accounts,
      entries: entries,
      postings: postings,
      debts: [debt],
      allocations: allocations,
    );
    final originClass = classifications[debt.originEntryId];
    if (originClass == null || !originClass.isEligibleEtb) {
      throw DoubleEntryValidationError(
        'Cannot settle or write off a non-ETB or currency-review debt '
        'in first-release ETB mode.',
      );
    }
  }

  static int countNonEtbAccounts(List<AccountModel> accounts) => accounts
      .where((a) => !a.isSystem && !a.isArchived && !isEtb(a.currencyCode))
      .length;

  static int countUnverifiedAccounts(List<AccountModel> accounts) => accounts
      .where((a) =>
          !a.isSystem &&
          !a.isArchived &&
          classifyCurrencyCode(a.currencyCode) ==
              CurrencyValidationTier.unverified)
      .length;

  static bool _isLegacyClearingAccount(AccountModel? acc, String accountId) {
    return acc?.subType == AccountSubType.legacyClearing ||
        accountId == SystemControlAccounts.legacyOffset;
  }

  static bool _isSystemNominalOrControlAccount(
    AccountModel? acc,
    String accountId,
  ) {
    if (_isLegacyClearingAccount(acc, accountId)) return false;
    if (acc == null) return SystemControlAccounts.isSystemControlId(accountId);
    if (SystemControlAccounts.isSystemControlId(acc.id)) return true;
    if (acc.subType == AccountSubType.nominalIncome ||
        acc.subType == AccountSubType.nominalExpense ||
        acc.subType == AccountSubType.openingEquity ||
        acc.subType == AccountSubType.receivable ||
        acc.subType == AccountSubType.payable) {
      return true;
    }
    if (acc.isSystem &&
        (acc.type == AccountType.income ||
            acc.type == AccountType.expense ||
            acc.type == AccountType.equity)) {
      return true;
    }
    return false;
  }

  static _FinancialCurrencyScan _collectFinancialCurrenciesForEntry(
    List<PostingModel> entryPostings,
    Map<String, AccountModel> accountById,
  ) {
    var financialLegCount = 0;
    final currencySet = <String>{};
    var hasUnverifiedFinancial = false;
    var touchesLegacyClearing = false;
    String? missingAccountId;

    for (final p in entryPostings) {
      final acc = accountById[p.accountId];
      if (_isLegacyClearingAccount(acc, p.accountId)) {
        touchesLegacyClearing = true;
        continue;
      }
      if (_isSystemNominalOrControlAccount(acc, p.accountId)) {
        continue;
      }
      if (acc == null) {
        missingAccountId ??= p.accountId;
        continue;
      }
      financialLegCount += 1;
      final tier = classifyCurrencyCode(acc.currencyCode);
      if (tier == CurrencyValidationTier.unverified) {
        hasUnverifiedFinancial = true;
        currencySet.add('UNVERIFIED');
      } else {
        currencySet.add(normalizeCurrencyCode(acc.currencyCode));
      }
    }

    final sorted = currencySet.toList()..sort();
    return _FinancialCurrencyScan(
      financialLegCount: financialLegCount,
      financialCurrencies: sorted,
      hasUnverifiedFinancial: hasUnverifiedFinancial,
      touchesLegacyClearing: touchesLegacyClearing,
      missingAccountId: missingAccountId,
    );
  }

  static EntryCurrencyClassification _classifyEntryCurrencyInternal({
    required JournalEntryModel entry,
    required Map<String, List<PostingModel>> postingsByEntry,
    required Map<String, AccountModel> accountById,
    Map<String, JournalEntryModel>? entryById,
    Map<String, DebtModel>? debtById,
    Map<String, DebtModel>? debtByOriginEntryId,
    Map<String, DebtModel>? debtByWriteOffEntryId,
    Map<String, List<SettlementAllocationModel>>?
        allocationsBySettlementEntryId,
    Map<String, List<SettlementAllocationModel>>? allocationsByDebtId,
    Map<String, EntryCurrencyClassification>? cache,
    required Set<String> visiting,
    bool ignoreVoidFlag = false,
  }) {
    if (!ignoreVoidFlag && cache != null && cache.containsKey(entry.id)) {
      return cache[entry.id]!;
    }

    final entryPostings = postingsByEntry[entry.id] ?? const <PostingModel>[];

    // [1] Voided entry priority (skipped only when resolving replaced original lineage)
    if (!ignoreVoidFlag && entry.isVoided) {
      final scanned =
          _collectFinancialCurrenciesForEntry(entryPostings, accountById);
      final singleNative = !scanned.hasUnverifiedFinancial &&
              scanned.financialCurrencies.length == 1
          ? scanned.financialCurrencies.first
          : null;
      final res = EntryCurrencyClassification(
        entryId: entry.id,
        status: EntryCurrencyStatus.inactiveOrVoided,
        nativeCurrencyCode: singleNative,
        touchedCurrencies: scanned.financialCurrencies.toSet(),
        reason: entry.voidReason != null
            ? 'Voided: ${entry.voidReason}'
            : 'Voided journal entry.',
      );
      cache?[entry.id] = res;
      return res;
    }

    if (visiting.contains(entry.id)) {
      return EntryCurrencyClassification(
        entryId: entry.id,
        status: EntryCurrencyStatus.mixedOrAmbiguous,
        reason: 'Cyclic entry lineage detected.',
      );
    }
    final nextVisiting = {...visiting, entry.id};

    // [2] Structural checks (< 2 postings, legacy clearing, missing account)
    if (entryPostings.length < 2) {
      final res = EntryCurrencyClassification(
        entryId: entry.id,
        status: EntryCurrencyStatus.mixedOrAmbiguous,
        reason: 'Entry has fewer than 2 postings.',
      );
      if (!ignoreVoidFlag) cache?[entry.id] = res;
      return res;
    }

    final scanned =
        _collectFinancialCurrenciesForEntry(entryPostings, accountById);
    if (scanned.touchesLegacyClearing) {
      final res = EntryCurrencyClassification(
        entryId: entry.id,
        status: EntryCurrencyStatus.mixedOrAmbiguous,
        touchedCurrencies: scanned.financialCurrencies.toSet(),
        reason: 'References legacy clearing offset account.',
      );
      if (!ignoreVoidFlag) cache?[entry.id] = res;
      return res;
    }

    if (scanned.missingAccountId != null) {
      final res = EntryCurrencyClassification(
        entryId: entry.id,
        status: EntryCurrencyStatus.mixedOrAmbiguous,
        touchedCurrencies: scanned.financialCurrencies.toSet(),
        reason:
            'References missing or unknown account "${scanned.missingAccountId}".',
      );
      if (!ignoreVoidFlag) cache?[entry.id] = res;
      return res;
    }

    // [3A] Has real financial account leg(s)
    if (scanned.financialLegCount >= 1) {
      if (scanned.hasUnverifiedFinancial) {
        final res = EntryCurrencyClassification(
          entryId: entry.id,
          status: EntryCurrencyStatus.mixedOrAmbiguous,
          touchedCurrencies: scanned.financialCurrencies.toSet(),
          reason:
              'References financial account with missing or unverified currency code.',
        );
        if (!ignoreVoidFlag) cache?[entry.id] = res;
        return res;
      }

      if (scanned.financialCurrencies.length > 1) {
        final res = EntryCurrencyClassification(
          entryId: entry.id,
          status: EntryCurrencyStatus.mixedOrAmbiguous,
          touchedCurrencies: scanned.financialCurrencies.toSet(),
          reason:
              'Cross-currency entry (${scanned.financialCurrencies.join(' / ')}).',
        );
        if (!ignoreVoidFlag) cache?[entry.id] = res;
        return res;
      }

      final primaryCurrency = scanned.financialCurrencies.first;

      // Verify debt settlement lineage consistency if context is available
      if (entry.entryType == EntryType.settlement &&
          allocationsBySettlementEntryId != null &&
          debtById != null) {
        final allocs = allocationsBySettlementEntryId[entry.id] ?? const [];
        for (final alloc in allocs) {
          final debt = debtById[alloc.debtId];
          if (debt == null) {
            final res = EntryCurrencyClassification(
              entryId: entry.id,
              status: EntryCurrencyStatus.mixedOrAmbiguous,
              touchedCurrencies: scanned.financialCurrencies.toSet(),
              reason: 'Settlement references missing debt record.',
            );
            if (!ignoreVoidFlag) cache?[entry.id] = res;
            return res;
          }
          final originEntry = entryById?[debt.originEntryId];
          if (originEntry == null || originEntry.isVoided) {
            final res = EntryCurrencyClassification(
              entryId: entry.id,
              status: EntryCurrencyStatus.mixedOrAmbiguous,
              touchedCurrencies: scanned.financialCurrencies.toSet(),
              reason:
                  'Settlement references debt with missing or voided origin entry.',
            );
            if (!ignoreVoidFlag) cache?[entry.id] = res;
            return res;
          }
          final originClass = _classifyEntryCurrencyInternal(
            entry: originEntry,
            postingsByEntry: postingsByEntry,
            accountById: accountById,
            entryById: entryById,
            debtById: debtById,
            debtByOriginEntryId: debtByOriginEntryId,
            debtByWriteOffEntryId: debtByWriteOffEntryId,
            allocationsBySettlementEntryId: allocationsBySettlementEntryId,
            allocationsByDebtId: allocationsByDebtId,
            cache: cache,
            visiting: nextVisiting,
          );
          if (originClass.status == EntryCurrencyStatus.mixedOrAmbiguous ||
              originClass.status == EntryCurrencyStatus.inactiveOrVoided ||
              originClass.nativeCurrencyCode == null) {
            final res = EntryCurrencyClassification(
              entryId: entry.id,
              status: EntryCurrencyStatus.mixedOrAmbiguous,
              touchedCurrencies: scanned.financialCurrencies.toSet(),
              reason:
                  'Settlement linked to debt with ambiguous origin currency.',
            );
            if (!ignoreVoidFlag) cache?[entry.id] = res;
            return res;
          }
          if (originClass.nativeCurrencyCode != primaryCurrency) {
            final res = EntryCurrencyClassification(
              entryId: entry.id,
              status: EntryCurrencyStatus.mixedOrAmbiguous,
              touchedCurrencies: {
                primaryCurrency,
                originClass.nativeCurrencyCode!,
              },
              reason:
                  'Cross-currency debt settlement: settled in $primaryCurrency for ${originClass.nativeCurrencyCode} debt.',
            );
            if (!ignoreVoidFlag) cache?[entry.id] = res;
            return res;
          }
        }
      }

      final res = primaryCurrency == 'ETB'
          ? EntryCurrencyClassification(
              entryId: entry.id,
              status: EntryCurrencyStatus.eligibleEtb,
              nativeCurrencyCode: 'ETB',
              touchedCurrencies: const {'ETB'},
            )
          : EntryCurrencyClassification(
              entryId: entry.id,
              status: EntryCurrencyStatus.excludedNonEtb,
              nativeCurrencyCode: primaryCurrency,
              touchedCurrencies: {primaryCurrency},
              reason: 'Non-ETB ($primaryCurrency) native transaction.',
            );
      if (!ignoreVoidFlag) cache?[entry.id] = res;
      return res;
    }

    // [3B] System-only entry (financialLegCount == 0)
    // 1) Write-off entry -> inherit Debt.originEntryId
    final writeOffDebt = debtByWriteOffEntryId?[entry.id];
    if (entry.entryType == EntryType.writeOff || writeOffDebt != null) {
      if (writeOffDebt == null || entryById == null) {
        final res = EntryCurrencyClassification(
          entryId: entry.id,
          status: EntryCurrencyStatus.mixedOrAmbiguous,
          reason: 'Write-off entry has no verifiable linked debt.',
        );
        if (!ignoreVoidFlag) cache?[entry.id] = res;
        return res;
      }
      final originEntry = entryById[writeOffDebt.originEntryId];
      if (originEntry == null || originEntry.isVoided) {
        final res = EntryCurrencyClassification(
          entryId: entry.id,
          status: EntryCurrencyStatus.mixedOrAmbiguous,
          reason:
              'Write-off references debt with missing or voided origin entry.',
        );
        if (!ignoreVoidFlag) cache?[entry.id] = res;
        return res;
      }
      final originClass = _classifyEntryCurrencyInternal(
        entry: originEntry,
        postingsByEntry: postingsByEntry,
        accountById: accountById,
        entryById: entryById,
        debtById: debtById,
        debtByOriginEntryId: debtByOriginEntryId,
        debtByWriteOffEntryId: debtByWriteOffEntryId,
        allocationsBySettlementEntryId: allocationsBySettlementEntryId,
        allocationsByDebtId: allocationsByDebtId,
        cache: cache,
        visiting: nextVisiting,
      );
      final EntryCurrencyClassification res;
      if (originClass.status == EntryCurrencyStatus.eligibleEtb) {
        res = EntryCurrencyClassification(
          entryId: entry.id,
          status: EntryCurrencyStatus.eligibleEtb,
          nativeCurrencyCode: 'ETB',
          touchedCurrencies: const {'ETB'},
        );
      } else if (originClass.status == EntryCurrencyStatus.excludedNonEtb &&
          originClass.nativeCurrencyCode != null) {
        res = EntryCurrencyClassification(
          entryId: entry.id,
          status: EntryCurrencyStatus.excludedNonEtb,
          nativeCurrencyCode: originClass.nativeCurrencyCode,
          touchedCurrencies: {originClass.nativeCurrencyCode!},
          reason: 'Write-off for ${originClass.nativeCurrencyCode} debt.',
        );
      } else {
        res = EntryCurrencyClassification(
          entryId: entry.id,
          status: EntryCurrencyStatus.mixedOrAmbiguous,
          touchedCurrencies: originClass.touchedCurrencies,
          reason: 'Write-off inherits ambiguous debt origin currency.',
        );
      }
      if (!ignoreVoidFlag) cache?[entry.id] = res;
      return res;
    }

    // 2) Corrected replacement entry -> inherit original entry's economic legs
    if (entry.correctedFromEntryId != null &&
        entry.correctedFromEntryId!.isNotEmpty) {
      final original = entryById?[entry.correctedFromEntryId!];
      if (original == null) {
        final res = EntryCurrencyClassification(
          entryId: entry.id,
          status: EntryCurrencyStatus.mixedOrAmbiguous,
          reason: 'Correction entry references missing original entry.',
        );
        if (!ignoreVoidFlag) cache?[entry.id] = res;
        return res;
      }
      final origClass = _classifyEntryCurrencyInternal(
        entry: original,
        postingsByEntry: postingsByEntry,
        accountById: accountById,
        entryById: entryById,
        debtById: debtById,
        debtByOriginEntryId: debtByOriginEntryId,
        debtByWriteOffEntryId: debtByWriteOffEntryId,
        allocationsBySettlementEntryId: allocationsBySettlementEntryId,
        allocationsByDebtId: allocationsByDebtId,
        cache: cache,
        visiting: nextVisiting,
        ignoreVoidFlag: true,
      );
      final EntryCurrencyClassification res;
      if (origClass.status == EntryCurrencyStatus.eligibleEtb) {
        res = EntryCurrencyClassification(
          entryId: entry.id,
          status: EntryCurrencyStatus.eligibleEtb,
          nativeCurrencyCode: 'ETB',
          touchedCurrencies: const {'ETB'},
        );
      } else if (origClass.status == EntryCurrencyStatus.excludedNonEtb &&
          origClass.nativeCurrencyCode != null) {
        res = EntryCurrencyClassification(
          entryId: entry.id,
          status: EntryCurrencyStatus.excludedNonEtb,
          nativeCurrencyCode: origClass.nativeCurrencyCode,
          touchedCurrencies: {origClass.nativeCurrencyCode!},
          reason: 'Inherited from ${origClass.nativeCurrencyCode} entry.',
        );
      } else {
        res = EntryCurrencyClassification(
          entryId: entry.id,
          status: EntryCurrencyStatus.mixedOrAmbiguous,
          touchedCurrencies: origClass.touchedCurrencies,
          reason: origClass.reason ?? 'Correction inherits ambiguous currency.',
        );
      }
      if (!ignoreVoidFlag) cache?[entry.id] = res;
      return res;
    }

    // 3) Third-party-paid expense backed by Debt(originEntryId == entry.id)
    final originDebt = debtByOriginEntryId?[entry.id];
    if (originDebt != null && entry.entryType == EntryType.debtIssuance) {
      final linkedAllocs = allocationsByDebtId?[originDebt.id] ?? const [];
      final settlementCurrencies = <String>{};
      for (final alloc in linkedAllocs) {
        final settleEntry = entryById?[alloc.settlementEntryId];
        if (settleEntry == null || settleEntry.isVoided) continue;
        final settlePostings =
            postingsByEntry[settleEntry.id] ?? const <PostingModel>[];
        final settleScan =
            _collectFinancialCurrenciesForEntry(settlePostings, accountById);
        if (settleScan.touchesLegacyClearing ||
            settleScan.missingAccountId != null ||
            settleScan.hasUnverifiedFinancial ||
            settleScan.financialCurrencies.length != 1) {
          final res = EntryCurrencyClassification(
            entryId: entry.id,
            status: EntryCurrencyStatus.mixedOrAmbiguous,
            touchedCurrencies: settleScan.financialCurrencies.toSet(),
            reason: 'Third-party expense has ambiguous settlement currency.',
          );
          if (!ignoreVoidFlag) cache?[entry.id] = res;
          return res;
        }
        settlementCurrencies.add(settleScan.financialCurrencies.first);
      }

      if (settlementCurrencies.length > 1) {
        final list = settlementCurrencies.toList()..sort();
        final res = EntryCurrencyClassification(
          entryId: entry.id,
          status: EntryCurrencyStatus.mixedOrAmbiguous,
          touchedCurrencies: list.toSet(),
          reason:
              'Third-party expense has conflicting settlement currencies (${list.join(' / ')}).',
        );
        if (!ignoreVoidFlag) cache?[entry.id] = res;
        return res;
      }

      if (settlementCurrencies.length == 1) {
        final sc = settlementCurrencies.first;
        final res = sc == 'ETB'
            ? EntryCurrencyClassification(
                entryId: entry.id,
                status: EntryCurrencyStatus.eligibleEtb,
                nativeCurrencyCode: 'ETB',
                touchedCurrencies: const {'ETB'},
              )
            : EntryCurrencyClassification(
                entryId: entry.id,
                status: EntryCurrencyStatus.excludedNonEtb,
                nativeCurrencyCode: sc,
                touchedCurrencies: {sc},
                reason: 'Third-party expense settled in $sc.',
              );
        if (!ignoreVoidFlag) cache?[entry.id] = res;
        return res;
      }

      // Unsettled debt-backed third-party expense has 0 financial legs and no
      // persisted entry currency in Schema v7 -> Currency Review until settled.
      final res = EntryCurrencyClassification(
        entryId: entry.id,
        status: EntryCurrencyStatus.mixedOrAmbiguous,
        reason: 'Unsettled third-party entry requires Currency Review.',
      );
      if (!ignoreVoidFlag) cache?[entry.id] = res;
      return res;
    }

    // 4) Unlinked system-only entry -> NEVER silently classify as ETB
    final res = EntryCurrencyClassification(
      entryId: entry.id,
      status: EntryCurrencyStatus.mixedOrAmbiguous,
      reason: 'Unlinked system-only entry without financial account leg.',
    );
    if (!ignoreVoidFlag) cache?[entry.id] = res;
    return res;
  }

  /// Classifies a single journal entry by currency compatibility across its financial legs & lineage.
  static EntryCurrencyClassification classifyEntryCurrency({
    required JournalEntryModel entry,
    required List<PostingModel> entryPostings,
    required Map<String, AccountModel> accountById,
    List<DebtModel>? debts,
    List<SettlementAllocationModel>? allocations,
    List<JournalEntryModel>? allEntries,
    List<PostingModel>? allPostings,
  }) {
    final postingsByEntry = <String, List<PostingModel>>{};
    if (allPostings != null) {
      for (final p in allPostings) {
        postingsByEntry.putIfAbsent(p.entryId, () => <PostingModel>[]).add(p);
      }
    }
    postingsByEntry.putIfAbsent(entry.id, () => entryPostings);

    final entryById = allEntries != null
        ? {for (final e in allEntries) e.id: e}
        : {entry.id: entry};
    final debtById = debts != null ? {for (final d in debts) d.id: d} : null;
    final debtByOriginEntryId =
        debts != null ? {for (final d in debts) d.originEntryId: d} : null;
    final debtByWriteOffEntryId = debts != null
        ? {
            for (final d in debts)
              if (d.writeOffEntryId != null) d.writeOffEntryId!: d,
          }
        : null;

    Map<String, List<SettlementAllocationModel>>?
        allocationsBySettlementEntryId;
    Map<String, List<SettlementAllocationModel>>? allocationsByDebtId;
    if (allocations != null) {
      allocationsBySettlementEntryId =
          <String, List<SettlementAllocationModel>>{};
      allocationsByDebtId = <String, List<SettlementAllocationModel>>{};
      for (final a in allocations) {
        allocationsBySettlementEntryId
            .putIfAbsent(a.settlementEntryId, () => [])
            .add(a);
        allocationsByDebtId.putIfAbsent(a.debtId, () => []).add(a);
      }
    }

    return _classifyEntryCurrencyInternal(
      entry: entry,
      postingsByEntry: postingsByEntry,
      accountById: accountById,
      entryById: entryById,
      debtById: debtById,
      debtByOriginEntryId: debtByOriginEntryId,
      debtByWriteOffEntryId: debtByWriteOffEntryId,
      allocationsBySettlementEntryId: allocationsBySettlementEntryId,
      allocationsByDebtId: allocationsByDebtId,
      visiting: <String>{},
    );
  }

  static Map<String, EntryCurrencyClassification> classifyAllEntries({
    required List<AccountModel> accounts,
    required List<JournalEntryModel> entries,
    required List<PostingModel> postings,
    List<DebtModel>? debts,
    List<SettlementAllocationModel>? allocations,
  }) {
    final accountById = {for (final a in accounts) a.id: a};
    final entryById = {for (final e in entries) e.id: e};
    final postingsByEntry = <String, List<PostingModel>>{};
    for (final p in postings) {
      postingsByEntry.putIfAbsent(p.entryId, () => <PostingModel>[]).add(p);
    }

    final debtById = debts != null ? {for (final d in debts) d.id: d} : null;
    final debtByOriginEntryId =
        debts != null ? {for (final d in debts) d.originEntryId: d} : null;
    final debtByWriteOffEntryId = debts != null
        ? {
            for (final d in debts)
              if (d.writeOffEntryId != null) d.writeOffEntryId!: d,
          }
        : null;

    Map<String, List<SettlementAllocationModel>>?
        allocationsBySettlementEntryId;
    Map<String, List<SettlementAllocationModel>>? allocationsByDebtId;
    if (allocations != null) {
      allocationsBySettlementEntryId =
          <String, List<SettlementAllocationModel>>{};
      allocationsByDebtId = <String, List<SettlementAllocationModel>>{};
      for (final a in allocations) {
        allocationsBySettlementEntryId
            .putIfAbsent(a.settlementEntryId, () => [])
            .add(a);
        allocationsByDebtId.putIfAbsent(a.debtId, () => []).add(a);
      }
    }

    final cache = <String, EntryCurrencyClassification>{};
    for (final entry in entries) {
      _classifyEntryCurrencyInternal(
        entry: entry,
        postingsByEntry: postingsByEntry,
        accountById: accountById,
        entryById: entryById,
        debtById: debtById,
        debtByOriginEntryId: debtByOriginEntryId,
        debtByWriteOffEntryId: debtByWriteOffEntryId,
        allocationsBySettlementEntryId: allocationsBySettlementEntryId,
        allocationsByDebtId: allocationsByDebtId,
        cache: cache,
        visiting: <String>{},
      );
    }
    return cache;
  }

  static CommitmentCurrencyResolution resolveCommitmentCurrencyStatus({
    required CommitmentModel commitment,
    required Map<String, AccountModel> accountById,
    Map<String, DebtModel>? debtById,
    Map<String, JournalEntryModel>? entryById,
    Map<String, EntryCurrencyClassification>? classificationsByEntryId,
    Map<String, RecurringRuleModel>? ruleById,
    Map<String, List<CommitmentSettlementModel>>? settlementsByCommitmentId,
  }) {
    final res = _resolveCommitmentCurrencyStatusCore(
      commitment: commitment,
      accountById: accountById,
      debtById: debtById,
      entryById: entryById,
      classificationsByEntryId: classificationsByEntryId,
      ruleById: ruleById,
      settlementsByCommitmentId: settlementsByCommitmentId,
    );
    return CommitmentCurrencyResolution(
      status: res.status,
      currencyCode: res.currencyCode,
      isUnlinkedAssumedEtb: res.isUnlinkedAssumedEtb,
      isExpectedIncome: commitment.direction == CommitmentDirection.inflow,
      reason: res.reason,
    );
  }

  static CommitmentCurrencyResolution _resolveCommitmentCurrencyStatusCore({
    required CommitmentModel commitment,
    required Map<String, AccountModel> accountById,
    Map<String, DebtModel>? debtById,
    Map<String, JournalEntryModel>? entryById,
    Map<String, EntryCurrencyClassification>? classificationsByEntryId,
    Map<String, RecurringRuleModel>? ruleById,
    Map<String, List<CommitmentSettlementModel>>? settlementsByCommitmentId,
  }) {
    // (1) Direct linkedAccountId
    if (commitment.linkedAccountId != null &&
        commitment.linkedAccountId!.trim().isNotEmpty) {
      final acc = accountById[commitment.linkedAccountId!];
      if (acc == null) {
        return const CommitmentCurrencyResolution(
          status: CommitmentCurrencyStatus.needsReview,
          reason: 'References missing account.',
        );
      }
      final tier = classifyCurrencyCode(acc.currencyCode);
      if (tier == CurrencyValidationTier.verifiedEtb) {
        return const CommitmentCurrencyResolution(
          status: CommitmentCurrencyStatus.eligibleEtb,
          currencyCode: 'ETB',
        );
      }
      if (tier == CurrencyValidationTier.verifiedNonEtb) {
        final code = normalizeCurrencyCode(acc.currencyCode);
        return CommitmentCurrencyResolution(
          status: CommitmentCurrencyStatus.excludedNonEtb,
          currencyCode: code,
          reason: 'Linked to $code account.',
        );
      }
      return const CommitmentCurrencyResolution(
        status: CommitmentCurrencyStatus.needsReview,
        reason: 'Linked to account with unverified currency.',
      );
    }

    // (2) Linked Debt
    if (commitment.linkedDebtId != null &&
        debtById != null &&
        classificationsByEntryId != null &&
        entryById != null) {
      final debt = debtById[commitment.linkedDebtId!];
      if (debt == null || !entryById.containsKey(debt.originEntryId)) {
        return const CommitmentCurrencyResolution(
          status: CommitmentCurrencyStatus.needsReview,
          reason: 'Linked debt or origin entry is missing.',
        );
      }
      final cls = classificationsByEntryId[debt.originEntryId];
      if (cls == null || cls.needsCurrencyReview || cls.isInactiveOrVoided) {
        return const CommitmentCurrencyResolution(
          status: CommitmentCurrencyStatus.needsReview,
          reason: 'Linked debt requires currency review.',
        );
      }
      if (cls.isExcludedNonEtb) {
        return CommitmentCurrencyResolution(
          status: CommitmentCurrencyStatus.excludedNonEtb,
          currencyCode: cls.nativeCurrencyCode,
          reason: 'Linked to ${cls.nativeCurrencyCode ?? 'non-ETB'} debt.',
        );
      }
      return const CommitmentCurrencyResolution(
        status: CommitmentCurrencyStatus.eligibleEtb,
        currencyCode: 'ETB',
      );
    }

    // (3) Recurring Rule
    if (commitment.recurringRuleId != null && ruleById != null) {
      final rule = ruleById[commitment.recurringRuleId!];
      if (rule != null) {
        final ruleAccIds = <String>[
          if (rule.accountId != null && rule.accountId!.trim().isNotEmpty)
            rule.accountId!,
          if (rule.destinationAccountId != null &&
              rule.destinationAccountId!.trim().isNotEmpty)
            rule.destinationAccountId!,
        ];
        if (ruleAccIds.isNotEmpty) {
          String? foreignCode;
          for (final accId in ruleAccIds) {
            final acc = accountById[accId];
            if (acc == null) {
              return const CommitmentCurrencyResolution(
                status: CommitmentCurrencyStatus.needsReview,
                reason: 'Linked recurring rule references missing account.',
              );
            }
            final tier = classifyCurrencyCode(acc.currencyCode);
            if (tier == CurrencyValidationTier.unverified) {
              return const CommitmentCurrencyResolution(
                status: CommitmentCurrencyStatus.needsReview,
                reason:
                    'Linked recurring rule references unverified account currency.',
              );
            }
            if (tier == CurrencyValidationTier.verifiedNonEtb) {
              final code = normalizeCurrencyCode(acc.currencyCode);
              if (foreignCode != null && foreignCode != code) {
                return const CommitmentCurrencyResolution(
                  status: CommitmentCurrencyStatus.needsReview,
                  reason: 'Linked recurring rule spans conflicting currencies.',
                );
              }
              foreignCode = code;
            }
          }
          if (foreignCode != null) {
            return CommitmentCurrencyResolution(
              status: CommitmentCurrencyStatus.excludedNonEtb,
              currencyCode: foreignCode,
              reason: 'Linked to $foreignCode recurring rule.',
            );
          }
          return const CommitmentCurrencyResolution(
            status: CommitmentCurrencyStatus.eligibleEtb,
            currencyCode: 'ETB',
          );
        }
        if (rule.linkedDebtId != null &&
            debtById != null &&
            classificationsByEntryId != null &&
            entryById != null) {
          final debt = debtById[rule.linkedDebtId!];
          if (debt == null || !entryById.containsKey(debt.originEntryId)) {
            return const CommitmentCurrencyResolution(
              status: CommitmentCurrencyStatus.needsReview,
              reason: 'Linked recurring debt is missing.',
            );
          }
          final cls = classificationsByEntryId[debt.originEntryId];
          if (cls == null ||
              cls.needsCurrencyReview ||
              cls.isInactiveOrVoided) {
            return const CommitmentCurrencyResolution(
              status: CommitmentCurrencyStatus.needsReview,
              reason: 'Linked recurring debt requires currency review.',
            );
          }
          if (cls.isExcludedNonEtb) {
            return CommitmentCurrencyResolution(
              status: CommitmentCurrencyStatus.excludedNonEtb,
              currencyCode: cls.nativeCurrencyCode,
              reason:
                  'Linked recurring rule references ${cls.nativeCurrencyCode ?? 'non-ETB'} debt.',
            );
          }
          return const CommitmentCurrencyResolution(
            status: CommitmentCurrencyStatus.eligibleEtb,
            currencyCode: 'ETB',
          );
        }
      }
    }

    // (4) Active CommitmentSettlement entries
    if (settlementsByCommitmentId != null && classificationsByEntryId != null) {
      final sets = settlementsByCommitmentId[commitment.id] ?? const [];
      final seen = <String>{};
      for (final s in sets) {
        final cls = classificationsByEntryId[s.entryId];
        if (cls == null || cls.isInactiveOrVoided) continue;
        if (cls.needsCurrencyReview) {
          return const CommitmentCurrencyResolution(
            status: CommitmentCurrencyStatus.needsReview,
            reason: 'Commitment settlement requires currency review.',
          );
        }
        seen.add(cls.nativeCurrencyCode ?? 'ETB');
      }
      if (seen.length > 1) {
        return const CommitmentCurrencyResolution(
          status: CommitmentCurrencyStatus.needsReview,
          reason: 'Commitment has conflicting settlement currencies.',
        );
      }
      if (seen.length == 1) {
        final code = seen.first;
        if (code != 'ETB') {
          return CommitmentCurrencyResolution(
            status: CommitmentCurrencyStatus.excludedNonEtb,
            currencyCode: code,
            reason: 'Partially settled in $code.',
          );
        }
        return const CommitmentCurrencyResolution(
          status: CommitmentCurrencyStatus.eligibleEtb,
          currencyCode: 'ETB',
        );
      }
    }

    // (5) Unlinked commitment cannot assume ETB silently under Stage 2.2
    return const CommitmentCurrencyResolution(
      status: CommitmentCurrencyStatus.needsReview,
      reason:
          'Unlinked commitment has no verified currency source; link an active ETB account to include in ETB Safe Harbor.',
    );
  }

  static CurrencyIsolationAudit auditCurrencyIsolation({
    required List<AccountModel> accounts,
    required List<JournalEntryModel> entries,
    required List<PostingModel> postings,
    List<DebtModel> debts = const [],
    List<SettlementAllocationModel> allocations = const [],
    List<CommitmentModel> commitments = const [],
    List<RecurringRuleModel> recurringRules = const [],
    List<CommitmentSettlementModel> commitmentSettlements = const [],
    List<SavingsGoalModel> savingsGoals = const [],
  }) {
    final classifications = classifyAllEntries(
      accounts: accounts,
      entries: entries,
      postings: postings,
      debts: debts,
      allocations: allocations,
    );
    final accountById = {for (final a in accounts) a.id: a};
    final entryById = {for (final e in entries) e.id: e};
    final debtById = {for (final d in debts) d.id: d};
    final ruleById = {for (final r in recurringRules) r.id: r};
    final settlementsByCommitmentId =
        <String, List<CommitmentSettlementModel>>{};
    for (final s in commitmentSettlements) {
      settlementsByCommitmentId.putIfAbsent(s.commitmentId, () => []).add(s);
    }

    var excludedNonEtbEntryCount = 0;
    var currencyReviewEntryCount = 0;
    for (final entry in entries) {
      if (entry.isVoided) continue;
      final c = classifications[entry.id];
      if (c == null || c.isInactiveOrVoided) continue;
      if (c.isExcludedNonEtb) excludedNonEtbEntryCount++;
      if (c.needsCurrencyReview) currencyReviewEntryCount++;
    }

    var excludedNonEtbDebtCount = 0;
    for (final d in debts) {
      if (d.status != DebtStatus.active) continue;
      if (!entryById.containsKey(d.originEntryId)) {
        excludedNonEtbDebtCount++;
        continue;
      }
      final c = classifications[d.originEntryId];
      if (c == null || !c.isEligibleEtb) {
        excludedNonEtbDebtCount++;
      }
    }

    var excludedNonEtbCommitmentCount = 0;
    for (final cm in commitments) {
      if (cm.isPaid || cm.legacyPaidUnverified) continue;
      final res = resolveCommitmentCurrencyStatus(
        commitment: cm,
        accountById: accountById,
        debtById: debtById,
        entryById: entryById,
        classificationsByEntryId: classifications,
        ruleById: ruleById,
        settlementsByCommitmentId: settlementsByCommitmentId,
      );
      if (!res.isEligibleEtb) {
        excludedNonEtbCommitmentCount++;
      }
    }

    var verifiedNonEtbAccCount = 0;
    var unverifiedAccCount = 0;
    for (final a in accounts) {
      if (a.isSystem || a.isArchived) continue;
      final tier = classifyCurrencyCode(a.currencyCode);
      if (tier == CurrencyValidationTier.verifiedNonEtb) {
        verifiedNonEtbAccCount++;
      } else if (tier == CurrencyValidationTier.unverified) {
        unverifiedAccCount++;
      }
    }
    final nonEtbAccCount = verifiedNonEtbAccCount + unverifiedAccCount;

    final excludedVaultGoalsCount = savingsGoals.where((g) {
      if (!g.isVaultLinked || g.isArchived) return false;
      final acc = accountById[g.linkedAccountId];
      return !isActiveVerifiedEtbAccount(acc) ||
          acc!.subType != AccountSubType.savingsVault;
    }).length;

    final warnings = <String>[];
    if (verifiedNonEtbAccCount > 0) {
      warnings.add(
        '$verifiedNonEtbAccCount non-ETB account(s) are excluded from ETB Safe Harbor, P&L, and Net Worth.',
      );
    }
    if (unverifiedAccCount > 0) {
      warnings.add(
        '$unverifiedAccCount account(s) have missing or unverified currency metadata and are excluded under Currency Review.',
      );
    }
    if (excludedNonEtbEntryCount > 0) {
      warnings.add(
        '$excludedNonEtbEntryCount non-ETB transaction(s) are excluded from ETB P&L, cashflow, and budgets.',
      );
    }
    if (currencyReviewEntryCount > 0) {
      warnings.add(
        '$currencyReviewEntryCount mixed-currency or ambiguous entry(ies) require currency review and are excluded from ETB reports.',
      );
    }
    if (excludedNonEtbDebtCount > 0) {
      warnings.add(
        '$excludedNonEtbDebtCount non-ETB, mixed, or missing-origin debt(s) are excluded from ETB Safe Harbor receivables/payables.',
      );
    }
    if (excludedNonEtbCommitmentCount > 0) {
      warnings.add(
        '$excludedNonEtbCommitmentCount commitment(s) linked to non-ETB, unverified, or missing references are excluded from ETB Safe Harbor.',
      );
    }
    if (excludedVaultGoalsCount > 0) {
      warnings.add(
        '$excludedVaultGoalsCount vault-linked savings goal(s) reference non-ETB, archived, or missing vault accounts and are excluded from ETB totals.',
      );
    }

    return CurrencyIsolationAudit(
      classificationsByEntryId: classifications,
      nonEtbAccountCount: nonEtbAccCount,
      unverifiedAccountCount: unverifiedAccCount,
      excludedNonEtbEntryCount: excludedNonEtbEntryCount,
      currencyReviewEntryCount: currencyReviewEntryCount,
      excludedNonEtbDebtCount: excludedNonEtbDebtCount,
      excludedNonEtbCommitmentCount: excludedNonEtbCommitmentCount,
      excludedVaultGoalCount: excludedVaultGoalsCount,
      warnings: warnings,
    );
  }

  /// Validates that a journal entry is perfectly balanced: Sum Debits == Sum Credits
  static void validateBalancedEntry(List<PostingModel> postings) {
    if (postings.length < 2) {
      throw DoubleEntryValidationError(
        'A balanced journal entry must contain at least 2 postings.',
      );
    }

    int totalDebits = 0;
    int totalCredits = 0;

    for (final p in postings) {
      if (p.direction == PostingDirection.debit) {
        totalDebits += p.amountCents;
      } else {
        totalCredits += p.amountCents;
      }
    }

    if (totalDebits != totalCredits) {
      throw DoubleEntryValidationError(
        'Ledger Invariant Violated: Debits ($totalDebits) != Credits ($totalCredits). '
        'Difference: ${(totalDebits - totalCredits).abs()} cents',
      );
    }
  }

  /// Calculates the real reconstructed balance of an account from postings.
  /// If [entries] or [voidedEntryIds] is provided, postings from voided entries are strictly ignored.
  static int calculateAccountBalance({
    required AccountModel account,
    required List<PostingModel> postings,
    String? asOfDate,
    List<JournalEntryModel>? entries,
    Set<String>? voidedEntryIds,
  }) {
    final effectiveVoidedIds = voidedEntryIds ??
        (entries != null
            ? entries.where((e) => e.isVoided).map((e) => e.id).toSet()
            : const <String>{});

    int balance = 0;
    for (final p in postings) {
      if (p.accountId != account.id) continue;
      if (effectiveVoidedIds.contains(p.entryId)) continue;
      if (asOfDate != null && p.accountMovementDate.compareTo(asOfDate) > 0) {
        continue;
      }

      if (account.type == AccountType.asset ||
          account.type == AccountType.expense) {
        balance += (p.direction == PostingDirection.debit)
            ? p.amountCents
            : -p.amountCents;
      } else {
        balance += (p.direction == PostingDirection.credit)
            ? p.amountCents
            : -p.amountCents;
      }
    }
    return balance;
  }

  /// Total liquid cash across active ETB bank, cash, and mobile money asset accounts.
  /// Strictly excludes `savings_vault`, `receivable`, and non-ETB accounts.
  static int calculateLiquidCash({
    required List<AccountModel> accounts,
    required List<PostingModel> postings,
    List<JournalEntryModel>? entries,
  }) {
    final effectiveVoidedIds = entries != null
        ? entries.where((e) => e.isVoided).map((e) => e.id).toSet()
        : const <String>{};

    final liquidAccounts = accounts.where(
      (a) =>
          a.type == AccountType.asset &&
          !a.isArchived &&
          !a.isSystem &&
          isEtb(a.currencyCode) &&
          a.subType.isLiquid &&
          !a.name.toLowerCase().contains('receivable'),
    );
    int sum = 0;
    for (final acc in liquidAccounts) {
      sum += calculateAccountBalance(
        account: acc,
        postings: postings,
        voidedEntryIds: effectiveVoidedIds,
      );
    }
    return sum;
  }

  /// Total balance held inside active ETB dedicated savings vault accounts.
  static int calculateVaultSavingsTotal({
    required List<AccountModel> accounts,
    required List<PostingModel> postings,
    List<JournalEntryModel>? entries,
  }) {
    final effectiveVoidedIds = entries != null
        ? entries.where((e) => e.isVoided).map((e) => e.id).toSet()
        : const <String>{};

    final vaultAccounts = accounts.where(
      (a) =>
          a.type == AccountType.asset &&
          !a.isArchived &&
          !a.isSystem &&
          isEtb(a.currencyCode) &&
          a.subType.isSavingsVault,
    );
    int sum = 0;
    for (final acc in vaultAccounts) {
      sum += calculateAccountBalance(
        account: acc,
        postings: postings,
        voidedEntryIds: effectiveVoidedIds,
      );
    }
    return sum;
  }

  /// Total short-term credit card / overdraft balances owed (ETB only).
  static int calculateShortTermCreditOwed({
    required List<AccountModel> accounts,
    required List<PostingModel> postings,
    List<JournalEntryModel>? entries,
  }) {
    final effectiveVoidedIds = entries != null
        ? entries.where((e) => e.isVoided).map((e) => e.id).toSet()
        : const <String>{};

    final creditAccounts = accounts.where(
      (a) =>
          a.type == AccountType.liability &&
          !a.isArchived &&
          !a.isSystem &&
          isEtb(a.currencyCode) &&
          a.subType.isCreditCard,
    );
    int sum = 0;
    for (final acc in creditAccounts) {
      final owed = calculateAccountBalance(
        account: acc,
        postings: postings,
        voidedEntryIds: effectiveVoidedIds,
      );
      if (owed > 0) sum += owed;
    }
    return sum;
  }

  /// Option 1 (Approved Stage 4.0.5):
  /// Positive prepaid credit from overpaid active ETB credit card accounts (balance < 0).
  static int calculatePrepaidCardCredit({
    required List<AccountModel> accounts,
    required List<PostingModel> postings,
    List<JournalEntryModel>? entries,
  }) {
    final effectiveVoidedIds = entries != null
        ? entries.where((e) => e.isVoided).map((e) => e.id).toSet()
        : const <String>{};

    final creditAccounts = accounts.where(
      (a) =>
          a.type == AccountType.liability &&
          !a.isArchived &&
          !a.isSystem &&
          isEtb(a.currencyCode) &&
          a.subType.isCreditCard,
    );
    int sum = 0;
    for (final acc in creditAccounts) {
      final bal = calculateAccountBalance(
        account: acc,
        postings: postings,
        voidedEntryIds: effectiveVoidedIds,
      );
      if (bal < 0) sum += -bal;
    }
    return sum;
  }

  /// ETB-only Net Financial Position = Total Active ETB Assets - Total Active ETB Liabilities.
  /// Prepaid Card Credit (< 0 on credit card liability) increases Net Position via reduced liabilities.
  /// When [entries] is provided, system control account balances ignore postings from
  /// non-ETB or mixed-currency entries so foreign debt postings cannot distort ETB Net Worth.
  static int calculateNetPosition({
    required List<AccountModel> accounts,
    required List<PostingModel> postings,
    List<JournalEntryModel>? entries,
    List<DebtModel> debts = const [],
    List<SettlementAllocationModel> allocations = const [],
  }) {
    final effectiveVoidedIds = entries != null
        ? entries.where((e) => e.isVoided).map((e) => e.id).toSet()
        : const <String>{};
    final classifications = entries != null
        ? classifyAllEntries(
            accounts: accounts,
            entries: entries,
            postings: postings,
            debts: debts,
            allocations: allocations,
          )
        : null;

    int totalAssets = 0;
    int totalLiabilities = 0;

    for (final acc in accounts) {
      if (acc.isArchived) continue;
      if (acc.subType == AccountSubType.legacyClearing) continue;
      if (!isEtb(acc.currencyCode)) continue;

      final int bal;
      if (acc.isSystem && classifications != null) {
        int sysBal = 0;
        for (final p in postings) {
          if (p.accountId != acc.id) continue;
          if (effectiveVoidedIds.contains(p.entryId)) continue;
          if (!(classifications[p.entryId]?.isEligibleEtb ?? false)) continue;
          if (acc.type == AccountType.asset ||
              acc.type == AccountType.expense) {
            sysBal += p.direction == PostingDirection.debit
                ? p.amountCents
                : -p.amountCents;
          } else {
            sysBal += p.direction == PostingDirection.credit
                ? p.amountCents
                : -p.amountCents;
          }
        }
        bal = sysBal;
      } else {
        bal = calculateAccountBalance(
          account: acc,
          postings: postings,
          voidedEntryIds: effectiveVoidedIds,
        );
      }

      if (acc.type == AccountType.asset) {
        totalAssets += bal;
      } else if (acc.type == AccountType.liability) {
        totalLiabilities += bal;
      }
    }
    return totalAssets - totalLiabilities;
  }

  static bool isDebtEligibleEtb(
    DebtModel debt, {
    Map<String, JournalEntryModel>? entryById,
    Map<String, EntryCurrencyClassification>? classifications,
  }) {
    if (entryById == null || classifications == null) return true;
    if (!entryById.containsKey(debt.originEntryId)) return false;
    return classifications[debt.originEntryId]?.isEligibleEtb ?? false;
  }

  /// Active ETB receivables owed TO the user (excluded from AvailableToSpend).
  static int calculateTotalReceivables(
    List<DebtModel> debts, {
    List<AccountModel>? accounts,
    List<JournalEntryModel>? entries,
    List<PostingModel>? postings,
    List<SettlementAllocationModel>? allocations,
  }) {
    Map<String, JournalEntryModel>? entryById;
    Map<String, EntryCurrencyClassification>? classifications;
    if (accounts != null && entries != null && postings != null) {
      entryById = {for (final e in entries) e.id: e};
      classifications = classifyAllEntries(
        accounts: accounts,
        entries: entries,
        postings: postings,
        debts: debts,
        allocations: allocations,
      );
    }
    return debts
        .where((d) =>
            d.debtType == DebtType.receivable &&
            d.status == DebtStatus.active &&
            isDebtEligibleEtb(
              d,
              entryById: entryById,
              classifications: classifications,
            ))
        .fold<int>(0, (sum, d) => sum + max(0, d.outstandingCents));
  }

  /// Active ETB payables owed BY the user.
  static int calculateTotalPayables(
    List<DebtModel> debts, {
    List<AccountModel>? accounts,
    List<JournalEntryModel>? entries,
    List<PostingModel>? postings,
    List<SettlementAllocationModel>? allocations,
  }) {
    Map<String, JournalEntryModel>? entryById;
    Map<String, EntryCurrencyClassification>? classifications;
    if (accounts != null && entries != null && postings != null) {
      entryById = {for (final e in entries) e.id: e};
      classifications = classifyAllEntries(
        accounts: accounts,
        entries: entries,
        postings: postings,
        debts: debts,
        allocations: allocations,
      );
    }
    return debts
        .where((d) =>
            d.debtType == DebtType.payable &&
            d.status == DebtStatus.active &&
            isDebtEligibleEtb(
              d,
              entryById: entryById,
              classifications: classifications,
            ))
        .fold<int>(0, (sum, d) => sum + max(0, d.outstandingCents));
  }

  /// Active ETB payables due on or before [periodEndIso] (undated IOUs are due on demand).
  static int calculateDuePayables({
    required List<DebtModel> debts,
    required String periodEndIso,
    List<AccountModel>? accounts,
    List<JournalEntryModel>? entries,
    List<PostingModel>? postings,
    List<SettlementAllocationModel>? allocations,
  }) {
    Map<String, JournalEntryModel>? entryById;
    Map<String, EntryCurrencyClassification>? classifications;
    if (accounts != null && entries != null && postings != null) {
      entryById = {for (final e in entries) e.id: e};
      classifications = classifyAllEntries(
        accounts: accounts,
        entries: entries,
        postings: postings,
        debts: debts,
        allocations: allocations,
      );
    }
    return debts
        .where((d) =>
            d.debtType == DebtType.payable &&
            d.status == DebtStatus.active &&
            (d.dueDate == null || d.dueDate!.compareTo(periodEndIso) <= 0) &&
            isDebtEligibleEtb(
              d,
              entryById: entryById,
              classifications: classifications,
            ))
        .fold<int>(0, (sum, d) => sum + max(0, d.outstandingCents));
  }

  /// Unpaid/partially-paid ETB outflow commitments due on or before [periodEndIso]
  /// that are NOT linked to a tracked debt, NOT marked legacyPaidUnverified,
  /// and NOT linked to a non-ETB, unverified, or missing reference.
  /// Pending inflow commitments contribute 0.
  static int calculateDueNonDebtCommitments({
    required List<CommitmentModel> commitments,
    required String periodEndIso,
    List<AccountModel>? accounts,
    List<DebtModel>? debts,
    List<JournalEntryModel>? entries,
    List<PostingModel>? postings,
    List<SettlementAllocationModel>? allocations,
    List<RecurringRuleModel>? recurringRules,
    List<CommitmentSettlementModel>? commitmentSettlements,
  }) {
    final accountById = accounts == null
        ? const <String, AccountModel>{}
        : {for (final a in accounts) a.id: a};
    final debtById = debts == null ? null : {for (final d in debts) d.id: d};
    final entryById =
        entries == null ? null : {for (final e in entries) e.id: e};
    final ruleById = recurringRules == null
        ? null
        : {for (final r in recurringRules) r.id: r};
    final classifications =
        (accounts != null && entries != null && postings != null)
            ? classifyAllEntries(
                accounts: accounts,
                entries: entries,
                postings: postings,
                debts: debts,
                allocations: allocations,
              )
            : null;
    Map<String, List<CommitmentSettlementModel>>? settlementsByCommitmentId;
    if (commitmentSettlements != null) {
      settlementsByCommitmentId = {};
      for (final s in commitmentSettlements) {
        settlementsByCommitmentId.putIfAbsent(s.commitmentId, () => []).add(s);
      }
    }

    return commitments.where((c) {
      if (c.direction != CommitmentDirection.outflow) return false;
      if (c.isPaid || c.legacyPaidUnverified || c.linkedDebtId != null) {
        return false;
      }
      if (c.dueDate.toIsoString().compareTo(periodEndIso) > 0) return false;
      if (accounts != null) {
        final res = resolveCommitmentCurrencyStatus(
          commitment: c,
          accountById: accountById,
          debtById: debtById,
          entryById: entryById,
          classificationsByEntryId: classifications,
          ruleById: ruleById,
          settlementsByCommitmentId: settlementsByCommitmentId,
        );
        if (!res.isEligibleEtb) return false;
      }
      return true;
    }).fold<int>(0, (sum, c) => sum + max(0, c.remainingCents));
  }

  /// Virtual savings earmarked inside liquid cash (active/completed non-archived
  /// goals without a linked vault account). Overfunded allocations remain reserved
  /// until withdrawn or released to archive.
  static int calculateVirtualSavingsReserve(
    List<SavingsGoalModel> savingsGoals,
  ) {
    return savingsGoals
        .where((s) => !s.isVaultLinked && !s.isArchived)
        .fold<int>(0, (sum, s) => sum + max(0, s.currentAllocatedCents));
  }

  /// Authoritative Safe Harbor Available-to-Spend(H) breakdown (Approved Option 1):
  /// LiquidCash + PrepaidCardCredit - ShortTermCreditOwed - DuePayables(H)
  ///            - DueOutflowNonDebtCommitments(H) - VirtualSavingsReserve
  static AvailableToSpendBreakdown calculateAvailableToSpendBreakdown({
    required List<AccountModel> accounts,
    required List<PostingModel> postings,
    required List<JournalEntryModel> entries,
    required List<DebtModel> debts,
    required List<CommitmentModel> commitments,
    required List<SavingsGoalModel> savingsGoals,
    required String periodEndIso,
    List<SettlementAllocationModel> allocations = const [],
    List<RecurringRuleModel> recurringRules = const [],
    List<CommitmentSettlementModel> commitmentSettlements = const [],
  }) {
    final audit = auditCurrencyIsolation(
      accounts: accounts,
      entries: entries,
      postings: postings,
      debts: debts,
      allocations: allocations,
      commitments: commitments,
      recurringRules: recurringRules,
      commitmentSettlements: commitmentSettlements,
      savingsGoals: savingsGoals,
    );
    final liquidCash = calculateLiquidCash(
      accounts: accounts,
      postings: postings,
      entries: entries,
    );
    final prepaidCardCredit = calculatePrepaidCardCredit(
      accounts: accounts,
      postings: postings,
      entries: entries,
    );
    final creditOwed = calculateShortTermCreditOwed(
      accounts: accounts,
      postings: postings,
      entries: entries,
    );
    final duePayables = calculateDuePayables(
      debts: debts,
      periodEndIso: periodEndIso,
      accounts: accounts,
      entries: entries,
      postings: postings,
      allocations: allocations,
    );
    final dueCommitments = calculateDueNonDebtCommitments(
      commitments: commitments,
      periodEndIso: periodEndIso,
      accounts: accounts,
      debts: debts,
      entries: entries,
      postings: postings,
      allocations: allocations,
      recurringRules: recurringRules,
      commitmentSettlements: commitmentSettlements,
    );
    final virtualSavings = calculateVirtualSavingsReserve(savingsGoals);
    final vaultSavings = calculateVaultSavingsTotal(
      accounts: accounts,
      postings: postings,
      entries: entries,
    );
    final receivables = calculateTotalReceivables(
      debts,
      accounts: accounts,
      entries: entries,
      postings: postings,
      allocations: allocations,
    );
    final unverifiedLegacyCount =
        commitments.where((c) => c.legacyPaidUnverified).length;

    final available = liquidCash +
        prepaidCardCredit -
        creditOwed -
        duePayables -
        dueCommitments -
        virtualSavings;

    return AvailableToSpendBreakdown(
      liquidCashCents: liquidCash,
      prepaidCardCreditCents: prepaidCardCredit,
      shortTermCreditOwedCents: creditOwed,
      duePayablesCents: duePayables,
      dueNonDebtCommitmentsCents: dueCommitments,
      virtualSavingsReservedCents: virtualSavings,
      vaultSavingsCents: vaultSavings,
      receivablesCents: receivables,
      availableToSpendCents: available,
      periodEndIso: periodEndIso,
      nonEtbAccountCount: audit.nonEtbAccountCount,
      unverifiedAccountCount: audit.unverifiedAccountCount,
      unverifiedLegacyPaidCount: unverifiedLegacyCount,
      excludedNonEtbEntryCount: audit.excludedNonEtbEntryCount,
      currencyReviewEntryCount: audit.currencyReviewEntryCount,
    );
  }

  /// Available to Spend Safe Harbor Formula:
  /// Available to Spend = Total Liquid Cash
  ///                     - Unpaid Payables Due in Current Period
  ///                     - Reserved Savings Allocations
  /// Note: Receivables are STRICTLY EXCLUDED.
  static int calculateAvailableToSpend({
    required int liquidCashCents,
    required int unpaidPayablesDueInPeriodCents,
    required int reservedSavingsCents,
  }) {
    return liquidCashCents -
        unpaidPayablesDueInPeriodCents -
        reservedSavingsCents;
  }

  /// Occurrence P&L totals for [startDateIso]..[endDateIso] filtered strictly by
  /// [JournalEntryModel.occurrenceDate] across active, ETB-eligible entries
  /// hitting nominal income/expense accounts.
  static ({int incomeCents, int expenseCents, int netCashflowCents})
      calculateOccurrencePnlTotals({
    required List<AccountModel> accounts,
    required List<PostingModel> postings,
    required List<JournalEntryModel> entries,
    required String startDateIso,
    required String endDateIso,
    List<DebtModel>? debts,
    List<SettlementAllocationModel>? allocations,
  }) {
    final entryById = {for (final e in entries) e.id: e};
    final classifications = classifyAllEntries(
      accounts: accounts,
      entries: entries,
      postings: postings,
      debts: debts,
      allocations: allocations,
    );
    final accountTypes = {for (final a in accounts) a.id: a.type};

    int incomeCents = 0;
    int expenseCents = 0;

    for (final p in postings) {
      final entry = entryById[p.entryId];
      if (entry == null || entry.isVoided) continue;
      if (!(classifications[p.entryId]?.isEligibleEtb ?? false)) continue;
      if (entry.occurrenceDate.compareTo(startDateIso) < 0 ||
          entry.occurrenceDate.compareTo(endDateIso) > 0) {
        continue;
      }
      final accType = accountTypes[p.accountId];
      if (accType == AccountType.income ||
          p.accountId == SystemControlAccounts.income) {
        incomeCents += p.direction == PostingDirection.credit
            ? p.amountCents
            : -p.amountCents;
      } else if (accType == AccountType.expense ||
          p.accountId == SystemControlAccounts.expense) {
        expenseCents += p.direction == PostingDirection.debit
            ? p.amountCents
            : -p.amountCents;
      }
    }

    return (
      incomeCents: incomeCents,
      expenseCents: expenseCents,
      netCashflowCents: incomeCents - expenseCents,
    );
  }

  /// Backward-compatible Occurrence P&L totals alias (filtered by occurrenceDate).
  static ({int incomeCents, int expenseCents, int netCashflowCents})
      calculatePeriodCashflowTotals({
    required List<AccountModel> accounts,
    required List<PostingModel> postings,
    required List<JournalEntryModel> entries,
    required String startDateIso,
    required String endDateIso,
    List<DebtModel>? debts,
    List<SettlementAllocationModel>? allocations,
  }) {
    return calculateOccurrencePnlTotals(
      accounts: accounts,
      postings: postings,
      entries: entries,
      startDateIso: startDateIso,
      endDateIso: endDateIso,
      debts: debts,
      allocations: allocations,
    );
  }

  /// Liquid Cash Flow totals for [startDateIso]..[endDateIso] filtered strictly
  /// by [PostingModel.accountMovementDate] on active, ETB-eligible postings
  /// touching active Verified ETB liquid asset accounts.
  static ({int inflowCents, int outflowCents, int netCashflowCents})
      calculateLiquidCashflowTotals({
    required List<AccountModel> accounts,
    required List<PostingModel> postings,
    required List<JournalEntryModel> entries,
    required String startDateIso,
    required String endDateIso,
    List<DebtModel>? debts,
    List<SettlementAllocationModel>? allocations,
  }) {
    final voidedIds = entries.where((e) => e.isVoided).map((e) => e.id).toSet();
    final classifications = classifyAllEntries(
      accounts: accounts,
      entries: entries,
      postings: postings,
      debts: debts,
      allocations: allocations,
    );
    final accountById = {for (final a in accounts) a.id: a};

    int inflowCents = 0;
    int outflowCents = 0;

    for (final p in postings) {
      if (voidedIds.contains(p.entryId)) continue;
      if (!(classifications[p.entryId]?.isEligibleEtb ?? false)) continue;
      if (p.accountMovementDate.compareTo(startDateIso) < 0 ||
          p.accountMovementDate.compareTo(endDateIso) > 0) {
        continue;
      }
      final acc = accountById[p.accountId];
      if (!isActiveVerifiedEtbAccount(acc) ||
          acc!.type != AccountType.asset ||
          acc.subType.isSavingsVault ||
          acc.subType == AccountSubType.receivable ||
          acc.name.toLowerCase().contains('receivable')) {
        continue;
      }
      if (p.direction == PostingDirection.debit) {
        inflowCents += p.amountCents;
      } else {
        outflowCents += p.amountCents;
      }
    }

    return (
      inflowCents: inflowCents,
      outflowCents: outflowCents,
      netCashflowCents: inflowCents - outflowCents,
    );
  }

  /// Computes net ETB spend per category ID over [startDateIso]..[endDateIso]
  /// by [JournalEntryModel.occurrenceDate] (for Occurrence P&L & Monthly Budgets),
  /// excluding voided entries, non-ETB/mixed-currency entries, transfers, and debt principal movements.
  static Map<String, int> calculateCategorySpendForPeriod({
    required List<PostingModel> postings,
    required List<JournalEntryModel> entries,
    required String startDateIso,
    required String endDateIso,
    List<TransactionCategoryModel>? categories,
    List<AccountModel>? accounts,
    List<DebtModel>? debts,
    List<SettlementAllocationModel>? allocations,
    bool rollupToParents = false,
  }) {
    final entryById = {for (final e in entries) e.id: e};
    final classifications = accounts == null
        ? null
        : classifyAllEntries(
            accounts: accounts,
            entries: entries,
            postings: postings,
            debts: debts,
            allocations: allocations,
          );
    final categoryTypes =
        categories == null ? null : {for (final c in categories) c.id: c.type};
    final accountTypes =
        accounts == null ? null : {for (final a in accounts) a.id: a.type};

    final totals = <String, int>{};

    for (final p in postings) {
      final entry = entryById[p.entryId];
      if (entry == null || entry.isVoided) continue;
      if (classifications != null &&
          !(classifications[p.entryId]?.isEligibleEtb ?? false)) {
        continue;
      }
      final catId = p.categoryId;
      if (catId == null) continue;
      if (entry.occurrenceDate.compareTo(startDateIso) < 0 ||
          entry.occurrenceDate.compareTo(endDateIso) > 0) {
        continue;
      }

      if (categoryTypes != null) {
        final type = categoryTypes[catId];
        if (type != null && type != 'expense') continue;
      }
      if (accountTypes != null) {
        final accType = accountTypes[p.accountId];
        if (accType != null && accType != AccountType.expense) continue;
      } else if (p.accountId == SystemControlAccounts.income ||
          p.accountId == SystemControlAccounts.receivable ||
          p.accountId == SystemControlAccounts.payable ||
          p.accountId == SystemControlAccounts.equity) {
        continue;
      }

      final delta = p.direction == PostingDirection.debit
          ? p.amountCents
          : -p.amountCents;
      totals[catId] = (totals[catId] ?? 0) + delta;
    }

    if (rollupToParents && categories != null) {
      final parentById = {for (final c in categories) c.id: c.parentId};
      final rolledUp = Map<String, int>.from(totals);
      for (final entry in totals.entries) {
        final parentId = parentById[entry.key];
        if (parentId != null && parentId.isNotEmpty) {
          rolledUp[parentId] = (rolledUp[parentId] ?? 0) + entry.value;
        }
      }
      return rolledUp;
    }

    return totals;
  }

  // --------------------------------------------------------------------------
  // Plain-Language Transaction Constructors (Double-Entry Under the Hood)
  // --------------------------------------------------------------------------

  /// Example A: Someone pays my expense on Day 1
  /// Debit Expense, Credit Liability (Payable).
  static Map<String, dynamic> buildThirdPartyPaidExpense({
    required String entryId,
    required String debtId,
    required String partyId,
    required String expenseAccountId,
    required String payableAccountId,
    required int amountCents,
    required String occurrenceDate,
    String? dueDate,
    required String description,
    String? categoryId,
  }) {
    final entry = JournalEntryModel(
      id: entryId,
      entryType: EntryType.debtIssuance,
      description: description,
      occurrenceDate: occurrenceDate,
    );

    final postings = [
      PostingModel(
        id: '$entryId-dr-exp',
        entryId: entryId,
        accountId: expenseAccountId,
        amountCents: amountCents,
        direction: PostingDirection.debit,
        accountMovementDate: occurrenceDate,
        categoryId: categoryId,
      ),
      PostingModel(
        id: '$entryId-cr-payable',
        entryId: entryId,
        accountId: payableAccountId,
        amountCents: amountCents,
        direction: PostingDirection.credit,
        accountMovementDate: occurrenceDate,
      ),
    ];

    validateBalancedEntry(postings);

    final debt = DebtModel(
      id: debtId,
      originEntryId: entryId,
      partyId: partyId,
      debtType: DebtType.payable,
      principalCents: amountCents,
      outstandingCents: amountCents,
      dueDate: dueDate,
      status: DebtStatus.active,
    );

    return {'entry': entry, 'postings': postings, 'debt': debt};
  }

  /// Example B: I lend money
  /// Debit Asset (Receivable), Credit Asset (Cash). Zero expense!
  static Map<String, dynamic> buildLendMoney({
    required String entryId,
    required String debtId,
    required String partyId,
    required String receivableAccountId,
    required String sourceAssetAccountId,
    required int amountCents,
    required String date,
    String? dueDate,
    required String description,
  }) {
    final entry = JournalEntryModel(
      id: entryId,
      entryType: EntryType.debtIssuance,
      description: description,
      occurrenceDate: date,
    );

    final postings = [
      PostingModel(
        id: '$entryId-dr-rec',
        entryId: entryId,
        accountId: receivableAccountId,
        amountCents: amountCents,
        direction: PostingDirection.debit,
        accountMovementDate: date,
      ),
      PostingModel(
        id: '$entryId-cr-cash',
        entryId: entryId,
        accountId: sourceAssetAccountId,
        amountCents: amountCents,
        direction: PostingDirection.credit,
        accountMovementDate: date,
      ),
    ];

    validateBalancedEntry(postings);

    final debt = DebtModel(
      id: debtId,
      originEntryId: entryId,
      partyId: partyId,
      debtType: DebtType.receivable,
      principalCents: amountCents,
      outstandingCents: amountCents,
      dueDate: dueDate,
      status: DebtStatus.active,
    );

    return {'entry': entry, 'postings': postings, 'debt': debt};
  }

  /// Example C: I borrow money
  /// Debit Asset (Telebirr/Cash), Credit Liability (Payable). Zero income!
  static Map<String, dynamic> buildBorrowMoney({
    required String entryId,
    required String debtId,
    required String partyId,
    required String destAssetAccountId,
    required String payableAccountId,
    required int amountCents,
    required String date,
    String? dueDate,
    required String description,
  }) {
    final entry = JournalEntryModel(
      id: entryId,
      entryType: EntryType.debtIssuance,
      description: description,
      occurrenceDate: date,
    );

    final postings = [
      PostingModel(
        id: '$entryId-dr-asset',
        entryId: entryId,
        accountId: destAssetAccountId,
        amountCents: amountCents,
        direction: PostingDirection.debit,
        accountMovementDate: date,
      ),
      PostingModel(
        id: '$entryId-cr-payable',
        entryId: entryId,
        accountId: payableAccountId,
        amountCents: amountCents,
        direction: PostingDirection.credit,
        accountMovementDate: date,
      ),
    ];

    validateBalancedEntry(postings);

    final debt = DebtModel(
      id: debtId,
      originEntryId: entryId,
      partyId: partyId,
      debtType: DebtType.payable,
      principalCents: amountCents,
      outstandingCents: amountCents,
      dueDate: dueDate,
      status: DebtStatus.active,
    );

    return {'entry': entry, 'postings': postings, 'debt': debt};
  }

  /// Example D: Split expense
  /// Debit Expense (myShare), Debit Receivable (theirShare), Credit Asset (total paid).
  static Map<String, dynamic> buildSplitExpense({
    required String entryId,
    required String debtId,
    required String partyId,
    required String myExpenseAccountId,
    required String receivableAccountId,
    required String paidAssetAccountId,
    required int myShareCents,
    required int theirShareCents,
    required String occurrenceDate,
    String? dueDate,
    required String description,
    String? categoryId,
  }) {
    final total = myShareCents + theirShareCents;
    final entry = JournalEntryModel(
      id: entryId,
      entryType: EntryType.splitExpense,
      description: description,
      occurrenceDate: occurrenceDate,
    );

    final postings = [
      PostingModel(
        id: '$entryId-dr-exp',
        entryId: entryId,
        accountId: myExpenseAccountId,
        amountCents: myShareCents,
        direction: PostingDirection.debit,
        accountMovementDate: occurrenceDate,
        categoryId: categoryId,
      ),
      PostingModel(
        id: '$entryId-dr-rec',
        entryId: entryId,
        accountId: receivableAccountId,
        amountCents: theirShareCents,
        direction: PostingDirection.debit,
        accountMovementDate: occurrenceDate,
      ),
      PostingModel(
        id: '$entryId-cr-cash',
        entryId: entryId,
        accountId: paidAssetAccountId,
        amountCents: total,
        direction: PostingDirection.credit,
        accountMovementDate: occurrenceDate,
      ),
    ];

    validateBalancedEntry(postings);

    final debt = DebtModel(
      id: debtId,
      originEntryId: entryId,
      partyId: partyId,
      debtType: DebtType.receivable,
      principalCents: theirShareCents,
      outstandingCents: theirShareCents,
      dueDate: dueDate,
      status: DebtStatus.active,
    );

    return {'entry': entry, 'postings': postings, 'debt': debt};
  }

  /// Account Transfer with optional transaction fee
  /// Generates balanced postings:
  /// Dr Destination (transfer amount)
  /// Dr Bank Fee Expense (fee amount, if any)
  /// Cr Source (transfer amount + fee)
  static Map<String, dynamic> buildTransfer({
    required String entryId,
    required String fromAssetAccountId,
    required String toAssetAccountId,
    required int amountCents,
    required String date,
    String? movementDate,
    required String description,
    int transferFeeCents = 0,
    String? feeExpenseAccountId,
    String? feeCategoryId,
    String? note,
  }) {
    final effectiveMovementDate = movementDate ?? date;
    final entry = JournalEntryModel(
      id: entryId,
      entryType: EntryType.transfer,
      description: transferFeeCents > 0
          ? '$description (Fee: ${(transferFeeCents / 100).toStringAsFixed(2)} ETB)'
          : description,
      occurrenceDate: date,
    );

    final postings = <PostingModel>[
      PostingModel(
        id: '$entryId-dr-dest',
        entryId: entryId,
        accountId: toAssetAccountId,
        amountCents: amountCents,
        direction: PostingDirection.debit,
        accountMovementDate: effectiveMovementDate,
        note: note,
      ),
    ];

    if (transferFeeCents > 0 && feeExpenseAccountId != null) {
      postings.add(
        PostingModel(
          id: '$entryId-dr-fee',
          entryId: entryId,
          accountId: feeExpenseAccountId,
          amountCents: transferFeeCents,
          direction: PostingDirection.debit,
          accountMovementDate: effectiveMovementDate,
          categoryId: feeCategoryId,
          note: 'Transfer service fee',
        ),
      );
    }

    postings.add(
      PostingModel(
        id: '$entryId-cr-source',
        entryId: entryId,
        accountId: fromAssetAccountId,
        amountCents: amountCents + transferFeeCents,
        direction: PostingDirection.credit,
        accountMovementDate: effectiveMovementDate,
        note: note,
      ),
    );

    validateBalancedEntry(postings);
    return {'entry': entry, 'postings': postings};
  }

  /// Voids an existing journal entry with an audit reason
  static JournalEntryModel buildVoidEntry({
    required JournalEntryModel entry,
    required String reason,
  }) {
    return entry.copyWith(
      isVoided: true,
      voidReason: reason,
    );
  }

  /// Example E: Debt Settlement with optional separate interest and settlement fee.
  static Map<String, dynamic> buildDebtSettlement({
    required String settlementEntryId,
    required DebtModel debt,
    required String settlementAssetAccountId,
    required String debtAccountId, // Receivable (Asset) or Payable (Liability)
    required int allocatedPrincipalCents,
    int interestCents = 0,
    String? interestAccountId,
    int feeCents = 0,
    String? feeAccountId,
    required String settlementDate,
    required String description,
  }) {
    if (debt.status != DebtStatus.active) {
      throw DoubleEntryValidationError(
        'Cannot settle debt in status "${debt.status.name}".',
      );
    }
    if (allocatedPrincipalCents <= 0) {
      throw DoubleEntryValidationError(
        'Allocated principal must be positive, got $allocatedPrincipalCents.',
      );
    }
    if (allocatedPrincipalCents > debt.outstandingCents) {
      throw DoubleEntryValidationError(
        'Over-allocation rejected: $allocatedPrincipalCents exceeds '
        'outstanding ${debt.outstandingCents}.',
      );
    }
    if (interestCents < 0 || feeCents < 0) {
      throw DoubleEntryValidationError(
        'Interest and fee cents must be non-negative.',
      );
    }
    if (interestCents > 0 && interestAccountId == null) {
      throw DoubleEntryValidationError(
        'interestAccountId is required when interestCents > 0.',
      );
    }
    if (feeCents > 0 && feeAccountId == null) {
      throw DoubleEntryValidationError(
        'feeAccountId is required when feeCents > 0.',
      );
    }

    final entry = JournalEntryModel(
      id: settlementEntryId,
      entryType: EntryType.settlement,
      description: description,
      occurrenceDate: settlementDate,
    );

    final postings = <PostingModel>[];
    final isPayable = debt.debtType == DebtType.payable;

    if (isPayable) {
      postings.add(
        PostingModel(
          id: '$settlementEntryId-dr-payable',
          entryId: settlementEntryId,
          accountId: debtAccountId,
          amountCents: allocatedPrincipalCents,
          direction: PostingDirection.debit,
          accountMovementDate: settlementDate,
        ),
      );

      if (interestCents > 0 && interestAccountId != null) {
        postings.add(
          PostingModel(
            id: '$settlementEntryId-dr-interest',
            entryId: settlementEntryId,
            accountId: interestAccountId,
            amountCents: interestCents,
            direction: PostingDirection.debit,
            accountMovementDate: settlementDate,
            categoryId: SystemControlAccounts.interestExpenseCategoryId,
          ),
        );
      }

      if (feeCents > 0 && feeAccountId != null) {
        postings.add(
          PostingModel(
            id: '$settlementEntryId-dr-fee',
            entryId: settlementEntryId,
            accountId: feeAccountId,
            amountCents: feeCents,
            direction: PostingDirection.debit,
            accountMovementDate: settlementDate,
            categoryId: SystemControlAccounts.feeCategoryId,
          ),
        );
      }

      postings.add(
        PostingModel(
          id: '$settlementEntryId-cr-asset',
          entryId: settlementEntryId,
          accountId: settlementAssetAccountId,
          amountCents: allocatedPrincipalCents + interestCents + feeCents,
          direction: PostingDirection.credit,
          accountMovementDate: settlementDate,
        ),
      );
    } else {
      postings.add(
        PostingModel(
          id: '$settlementEntryId-dr-asset',
          entryId: settlementEntryId,
          accountId: settlementAssetAccountId,
          amountCents: allocatedPrincipalCents + interestCents,
          direction: PostingDirection.debit,
          accountMovementDate: settlementDate,
        ),
      );

      postings.add(
        PostingModel(
          id: '$settlementEntryId-cr-rec',
          entryId: settlementEntryId,
          accountId: debtAccountId,
          amountCents: allocatedPrincipalCents,
          direction: PostingDirection.credit,
          accountMovementDate: settlementDate,
        ),
      );

      if (interestCents > 0 && interestAccountId != null) {
        postings.add(
          PostingModel(
            id: '$settlementEntryId-cr-interest',
            entryId: settlementEntryId,
            accountId: interestAccountId,
            amountCents: interestCents,
            direction: PostingDirection.credit,
            accountMovementDate: settlementDate,
            categoryId: SystemControlAccounts.interestIncomeCategoryId,
          ),
        );
      }

      if (feeCents > 0 && feeAccountId != null) {
        postings.add(
          PostingModel(
            id: '$settlementEntryId-dr-fee',
            entryId: settlementEntryId,
            accountId: feeAccountId,
            amountCents: feeCents,
            direction: PostingDirection.debit,
            accountMovementDate: settlementDate,
            categoryId: SystemControlAccounts.feeCategoryId,
          ),
        );
        postings.add(
          PostingModel(
            id: '$settlementEntryId-cr-fee-asset',
            entryId: settlementEntryId,
            accountId: settlementAssetAccountId,
            amountCents: feeCents,
            direction: PostingDirection.credit,
            accountMovementDate: settlementDate,
          ),
        );
      }
    }

    validateBalancedEntry(postings);

    final allocation = SettlementAllocationModel(
      id: 'alloc-$settlementEntryId',
      settlementEntryId: settlementEntryId,
      debtId: debt.id,
      allocatedCents: allocatedPrincipalCents,
      settlementDate: settlementDate,
    );

    final newOutstanding =
        max(0, debt.outstandingCents - allocatedPrincipalCents);
    final updatedDebt = debt.copyWith(
      outstandingCents: newOutstanding,
      status: newOutstanding == 0 ? DebtStatus.settled : DebtStatus.active,
    );

    return {
      'entry': entry,
      'postings': postings,
      'allocation': allocation,
      'updatedDebt': updatedDebt,
    };
  }

  /// Direct Expense: Dr Expense Control (categoryId), Cr Cash/Bank/Card.
  static Map<String, dynamic> buildDirectExpense({
    required String entryId,
    required String paidAccountId,
    String expenseAccountId = SystemControlAccounts.expense,
    required String categoryId,
    required int amountCents,
    required String date,
    required String description,
    String? note,
    String? correctedFromEntryId,
  }) {
    final entry = JournalEntryModel(
      id: entryId,
      entryType: EntryType.standard,
      description: description,
      occurrenceDate: date,
      correctedFromEntryId: correctedFromEntryId,
    );
    final postings = [
      PostingModel(
        id: '$entryId-dr-exp',
        entryId: entryId,
        accountId: expenseAccountId,
        amountCents: amountCents,
        direction: PostingDirection.debit,
        accountMovementDate: date,
        categoryId: categoryId,
        note: note,
      ),
      PostingModel(
        id: '$entryId-cr-acc',
        entryId: entryId,
        accountId: paidAccountId,
        amountCents: amountCents,
        direction: PostingDirection.credit,
        accountMovementDate: date,
        note: note,
      ),
    ];
    validateBalancedEntry(postings);
    return {'entry': entry, 'postings': postings};
  }

  /// Direct Income: Dr Cash/Bank, Cr Income Control (categoryId).
  static Map<String, dynamic> buildDirectIncome({
    required String entryId,
    required String destAccountId,
    String incomeAccountId = SystemControlAccounts.income,
    required String categoryId,
    required int amountCents,
    required String date,
    required String description,
    String? note,
    String? correctedFromEntryId,
  }) {
    final entry = JournalEntryModel(
      id: entryId,
      entryType: EntryType.standard,
      description: description,
      occurrenceDate: date,
      correctedFromEntryId: correctedFromEntryId,
    );
    final postings = [
      PostingModel(
        id: '$entryId-dr-acc',
        entryId: entryId,
        accountId: destAccountId,
        amountCents: amountCents,
        direction: PostingDirection.debit,
        accountMovementDate: date,
        note: note,
      ),
      PostingModel(
        id: '$entryId-cr-inc',
        entryId: entryId,
        accountId: incomeAccountId,
        amountCents: amountCents,
        direction: PostingDirection.credit,
        accountMovementDate: date,
        categoryId: categoryId,
        note: note,
      ),
    ];
    validateBalancedEntry(postings);
    return {'entry': entry, 'postings': postings};
  }

  /// Opening Balance Entry (supports revisions via [correctedFromEntryId] and provenance tag).
  /// Positive asset -> Dr Account / Cr acc-sys-equity.
  /// Positive liability (credit card owed) -> Dr acc-sys-equity / Cr Account.
  /// Negative credit card balance (prepaid credit) -> Dr Account / Cr acc-sys-equity.
  static Map<String, dynamic> buildOpeningBalance({
    required String entryId,
    required AccountModel account,
    int? overrideAmountCents,
    String? date,
    String equityAccountId = SystemControlAccounts.equity,
    String? legacySourceTxId,
    String? correctedFromEntryId,
    String? description,
  }) {
    final amountCents = overrideAmountCents ?? account.openingBalanceCents;
    if (amountCents == 0) {
      throw ArgumentError('Opening balance must be non-zero.');
    }
    final absAmount = amountCents.abs();
    final effectiveDate = date ?? account.openingBalanceDate;
    final isDebitNormal = account.type == AccountType.asset ||
        account.type == AccountType.expense;
    final accountDebit = (isDebitNormal && amountCents > 0) ||
        (!isDebitNormal && amountCents < 0);

    final entry = JournalEntryModel(
      id: entryId,
      entryType: EntryType.adjustment,
      description: description ?? 'Opening Balance for ${account.name}',
      occurrenceDate: effectiveDate,
      legacySourceTxId: legacySourceTxId ?? 'open:${account.id}',
      correctedFromEntryId: correctedFromEntryId,
    );

    final postings = [
      PostingModel(
        id: '$entryId-acc',
        entryId: entryId,
        accountId: account.id,
        amountCents: absAmount,
        direction:
            accountDebit ? PostingDirection.debit : PostingDirection.credit,
        accountMovementDate: effectiveDate,
        note: 'Opening balance',
      ),
      PostingModel(
        id: '$entryId-eq',
        entryId: entryId,
        accountId: equityAccountId,
        amountCents: absAmount,
        direction:
            accountDebit ? PostingDirection.credit : PostingDirection.debit,
        accountMovementDate: effectiveDate,
        note: 'Opening equity offset',
      ),
    ];
    validateBalancedEntry(postings);
    return {'entry': entry, 'postings': postings};
  }

  /// Paying an Outflow Commitment: Dr Expense Control (categoryId), Cr Asset/Card.
  static Map<String, dynamic> buildCommitmentPayment({
    required String entryId,
    required String paidAccountId,
    String expenseAccountId = SystemControlAccounts.expense,
    String? categoryId,
    required int amountCents,
    required String date,
    required String commitmentTitle,
    String? note,
  }) {
    final entry = JournalEntryModel(
      id: entryId,
      entryType: EntryType.standard,
      description: 'Commitment Paid: $commitmentTitle',
      occurrenceDate: date,
    );
    final postings = [
      PostingModel(
        id: '$entryId-dr-exp',
        entryId: entryId,
        accountId: expenseAccountId,
        amountCents: amountCents,
        direction: PostingDirection.debit,
        accountMovementDate: date,
        categoryId: categoryId,
        note: note ?? commitmentTitle,
      ),
      PostingModel(
        id: '$entryId-cr-acc',
        entryId: entryId,
        accountId: paidAccountId,
        amountCents: amountCents,
        direction: PostingDirection.credit,
        accountMovementDate: date,
        note: note ?? commitmentTitle,
      ),
    ];
    validateBalancedEntry(postings);
    return {'entry': entry, 'postings': postings};
  }

  /// Receiving an Inflow Expected-Income Commitment: Dr Asset, Cr Income Control (categoryId).
  static Map<String, dynamic> buildCommitmentReceipt({
    required String entryId,
    required String destAccountId,
    String incomeAccountId = SystemControlAccounts.income,
    String? categoryId,
    required int amountCents,
    required String date,
    required String commitmentTitle,
    String? note,
  }) {
    final entry = JournalEntryModel(
      id: entryId,
      entryType: EntryType.standard,
      description: 'Income Received: $commitmentTitle',
      occurrenceDate: date,
    );
    final postings = [
      PostingModel(
        id: '$entryId-dr-acc',
        entryId: entryId,
        accountId: destAccountId,
        amountCents: amountCents,
        direction: PostingDirection.debit,
        accountMovementDate: date,
        note: note ?? commitmentTitle,
      ),
      PostingModel(
        id: '$entryId-cr-inc',
        entryId: entryId,
        accountId: incomeAccountId,
        amountCents: amountCents,
        direction: PostingDirection.credit,
        accountMovementDate: date,
        categoryId: categoryId,
        note: note ?? commitmentTitle,
      ),
    ];
    validateBalancedEntry(postings);
    return {'entry': entry, 'postings': postings};
  }

  /// Vault Transfer: Dr Vault Account / Cr Source Account.
  static Map<String, dynamic> buildVaultTransfer({
    required String entryId,
    required String fromAccountId,
    required String vaultAccountId,
    required int amountCents,
    required String date,
    required String goalTitle,
    String? note,
  }) {
    return buildTransfer(
      entryId: entryId,
      fromAssetAccountId: fromAccountId,
      toAssetAccountId: vaultAccountId,
      amountCents: amountCents,
      date: date,
      description: 'Savings Funding: $goalTitle',
      note: note,
    );
  }

  // --------------------------------------------------------------------------
  // Stage B: Mutation Guards & Expense Refund Workflow
  // --------------------------------------------------------------------------

  static const String refundTagPrefix = 'refund:';

  static String? extractRefundOriginEntryId(JournalEntryModel entry) {
    final tag = entry.legacySourceTxId;
    if (tag == null || !tag.startsWith(refundTagPrefix)) return null;
    final remainder = tag.substring(refundTagPrefix.length).trim();
    if (remainder.isEmpty) return null;
    final sepIndex = remainder.indexOf(':');
    final originId =
        sepIndex == -1 ? remainder : remainder.substring(0, sepIndex).trim();
    return originId.isEmpty ? null : originId;
  }

  static bool isRefundEntry(JournalEntryModel entry) =>
      extractRefundOriginEntryId(entry) != null;

  static bool isCorrectableEntryType(EntryType type) =>
      type == EntryType.standard || type == EntryType.transfer;

  static ExpenseRefundSummary getExpenseRefundSummary({
    required String originalEntryId,
    required List<JournalEntryModel> entries,
    required List<PostingModel> postings,
    required List<AccountModel> accounts,
    List<DebtModel>? debts,
    List<SettlementAllocationModel>? allocations,
  }) {
    final matches = entries.where((e) => e.id == originalEntryId);
    if (matches.isEmpty) {
      return const ExpenseRefundSummary(
        eligible: false,
        reason: 'Expense entry not found.',
        originalAmountCents: 0,
        refundedCents: 0,
        remainingRefundableCents: 0,
      );
    }
    final original = matches.first;
    if (original.isVoided) {
      return const ExpenseRefundSummary(
        eligible: false,
        reason: 'Voided expenses cannot be refunded.',
        originalAmountCents: 0,
        refundedCents: 0,
        remainingRefundableCents: 0,
      );
    }
    if (original.entryType != EntryType.standard) {
      return const ExpenseRefundSummary(
        eligible: false,
        reason: 'Only standard direct expense entries can be refunded.',
        originalAmountCents: 0,
        refundedCents: 0,
        remainingRefundableCents: 0,
      );
    }
    if (isRefundEntry(original)) {
      return const ExpenseRefundSummary(
        eligible: false,
        reason: 'A refund entry cannot itself be refunded.',
        originalAmountCents: 0,
        refundedCents: 0,
        remainingRefundableCents: 0,
      );
    }
    if (original.legacySourceTxId?.startsWith('open:') ?? false) {
      return const ExpenseRefundSummary(
        eligible: false,
        reason: 'Opening balance adjustments cannot be refunded.',
        originalAmountCents: 0,
        refundedCents: 0,
        remainingRefundableCents: 0,
      );
    }

    final classifications = classifyAllEntries(
      accounts: accounts,
      entries: entries,
      postings: postings,
      debts: debts,
      allocations: allocations,
    );
    if (!(classifications[original.id]?.isEligibleEtb ?? false)) {
      return const ExpenseRefundSummary(
        eligible: false,
        reason:
            'Only active Verified ETB expenses can be refunded in first-release mode.',
        originalAmountCents: 0,
        refundedCents: 0,
        remainingRefundableCents: 0,
      );
    }

    final accountById = {for (final a in accounts) a.id: a};
    bool isExpenseAcc(String id) =>
        id == SystemControlAccounts.expense ||
        accountById[id]?.type == AccountType.expense;
    bool isIncomeOrDebtAcc(String id) {
      final acc = accountById[id];
      return id == SystemControlAccounts.income ||
          id == SystemControlAccounts.receivable ||
          id == SystemControlAccounts.payable ||
          acc?.type == AccountType.income ||
          acc?.subType == AccountSubType.receivable ||
          acc?.subType == AccountSubType.payable;
    }

    final origPostings =
        postings.where((p) => p.entryId == original.id).toList();
    if (origPostings.any((p) => isIncomeOrDebtAcc(p.accountId))) {
      return const ExpenseRefundSummary(
        eligible: false,
        reason:
            'Income and receivable/payable entries cannot be refunded as direct expenses.',
        originalAmountCents: 0,
        refundedCents: 0,
        remainingRefundableCents: 0,
      );
    }

    final expenseDebits = origPostings
        .where(
          (p) =>
              p.direction == PostingDirection.debit &&
              isExpenseAcc(p.accountId),
        )
        .toList();
    final expenseCredits = origPostings
        .where(
          (p) =>
              p.direction == PostingDirection.credit &&
              isExpenseAcc(p.accountId),
        )
        .toList();
    PostingModel? paidCreditPosting;
    for (final p in origPostings) {
      final isSys = SystemControlAccounts.isSystemControlId(p.accountId) ||
          (accountById[p.accountId]?.isSystem ?? false);
      if (p.direction == PostingDirection.credit && !isSys) {
        paidCreditPosting = p;
        break;
      }
    }

    if (expenseDebits.isEmpty ||
        expenseCredits.isNotEmpty ||
        paidCreditPosting == null) {
      return const ExpenseRefundSummary(
        eligible: false,
        reason: 'Entry is not a standard direct expense.',
        originalAmountCents: 0,
        refundedCents: 0,
        remainingRefundableCents: 0,
      );
    }

    final originalAmountCents =
        expenseDebits.fold<int>(0, (sum, p) => sum + p.amountCents);
    var refundedCents = 0;
    for (final e in entries) {
      if (e.isVoided || extractRefundOriginEntryId(e) != original.id) {
        continue;
      }
      for (final p in postings) {
        if (p.entryId == e.id &&
            p.direction == PostingDirection.credit &&
            isExpenseAcc(p.accountId)) {
          refundedCents += p.amountCents;
        }
      }
    }

    final remainingRefundableCents = max(0, originalAmountCents - refundedCents);
    String? categoryId;
    for (final p in expenseDebits) {
      if (p.categoryId != null && p.categoryId!.isNotEmpty) {
        categoryId = p.categoryId;
        break;
      }
    }

    return ExpenseRefundSummary(
      eligible: true,
      originalAmountCents: originalAmountCents,
      refundedCents: refundedCents,
      remainingRefundableCents: remainingRefundableCents,
      categoryId: categoryId,
      originalAccountId: paidCreditPosting.accountId,
      originalOccurrenceDate: original.occurrenceDate,
    );
  }

  static ({bool ok, String? error}) canCorrectEntry({
    required JournalEntryModel entry,
    required List<JournalEntryModel> entries,
    required List<PostingModel> postings,
    required List<AccountModel> accounts,
    List<DebtModel> debts = const [],
    List<SettlementAllocationModel> allocations = const [],
    List<CommitmentSettlementModel> commitmentSettlements = const [],
  }) {
    if (entry.isVoided) {
      return (ok: false, error: 'Voided entries cannot be replaced.');
    }
    final alreadySuperseded = entries.any(
      (e) => !e.isVoided && e.correctedFromEntryId == entry.id,
    );
    if (alreadySuperseded) {
      return (
        ok: false,
        error: 'This entry already has an active replacement.',
      );
    }

    final accountById = {for (final a in accounts) a.id: a};
    final entryPostings =
        postings.where((p) => p.entryId == entry.id).toList(growable: false);
    final cls = classifyEntryCurrency(
      entry: entry,
      entryPostings: entryPostings,
      accountById: accountById,
      debts: debts,
      allocations: allocations,
      allEntries: entries,
      allPostings: postings,
    );
    if (!cls.isEligibleEtb) {
      return (
        ok: false,
        error:
            'Excluded non-ETB or currency-review entries cannot be replaced in first-release ETB mode.',
      );
    }
    if (!isCorrectableEntryType(entry.entryType)) {
      return (
        ok: false,
        error:
            'Cannot replace ${entry.entryType.dbValue} entries directly. Void the entry safely and record a new transaction instead.',
      );
    }
    if (entry.legacySourceTxId?.startsWith('open:') ?? false) {
      return (
        ok: false,
        error:
            'Opening balance adjustments must be revised via the account opening balance editor.',
      );
    }
    if (isRefundEntry(entry)) {
      return (
        ok: false,
        error:
            'Expense refund entries cannot be replaced directly. Void the refund and record a new refund if needed.',
      );
    }
    if (commitmentSettlements.any((s) => s.entryId == entry.id)) {
      return (
        ok: false,
        error:
            'Commitment settlement entries cannot be replaced directly. Void the installment in Plan and record a new settlement.',
      );
    }
    final hasActiveRefund = entries.any(
      (e) => !e.isVoided && extractRefundOriginEntryId(e) == entry.id,
    );
    if (hasActiveRefund) {
      return (
        ok: false,
        error:
            'Cannot replace an expense that has active refunds. Void the active refund(s) first.',
      );
    }
    if (debts.any((d) => d.originEntryId == entry.id)) {
      return (
        ok: false,
        error:
            'Cannot replace a debt-linked entry directly. Void the debt origin and re-issue.',
      );
    }
    return (ok: true, error: null);
  }

  static Map<String, dynamic> buildExpenseRefund({
    required String refundEntryId,
    required String originalEntryId,
    required String refundAccountId,
    required int refundCents,
    required String refundDateIso,
    String? note,
    required List<JournalEntryModel> entries,
    required List<PostingModel> postings,
    required List<AccountModel> accounts,
    List<DebtModel>? debts,
    List<SettlementAllocationModel>? allocations,
  }) {
    if (refundCents <= 0) {
      throw DoubleEntryValidationError(
        'Refund amount must be a positive integer in cents.',
      );
    }
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(refundDateIso) ||
        SharedDateFormatter.tryParseFlexibleToCalendarDate(refundDateIso) ==
            null) {
      throw DoubleEntryValidationError(
        'Refund date must be a valid YYYY-MM-DD civil date.',
      );
    }

    final summary = getExpenseRefundSummary(
      originalEntryId: originalEntryId,
      entries: entries,
      postings: postings,
      accounts: accounts,
      debts: debts,
      allocations: allocations,
    );
    if (!summary.eligible) {
      throw DoubleEntryValidationError(
        summary.reason ?? 'Original entry is not refundable.',
      );
    }
    if (summary.remainingRefundableCents <= 0) {
      throw DoubleEntryValidationError(
        'This expense has already been fully refunded.',
      );
    }
    if (refundCents > summary.remainingRefundableCents) {
      throw DoubleEntryValidationError(
        'Refund amount ($refundCents) exceeds remaining refundable balance (${summary.remainingRefundableCents}).',
      );
    }
    if (summary.originalOccurrenceDate != null &&
        refundDateIso.compareTo(summary.originalOccurrenceDate!) < 0) {
      throw DoubleEntryValidationError(
        'Refund date ($refundDateIso) cannot precede the original expense date (${summary.originalOccurrenceDate}).',
      );
    }

    final accMatches = accounts.where((a) => a.id == refundAccountId);
    if (accMatches.isEmpty) {
      throw DoubleEntryValidationError(
        'Refund destination account "$refundAccountId" not found.',
      );
    }
    final destAcc = accMatches.first;
    assertVerifiedEtbAccount(destAcc, roleLabel: 'Refund destination account');
    if (destAcc.isArchived) {
      throw DoubleEntryValidationError(
        'Refund destination account "${destAcc.name}" is archived.',
      );
    }
    if (destAcc.subType.isSavingsVault ||
        destAcc.subType == AccountSubType.receivable ||
        destAcc.subType == AccountSubType.payable ||
        (destAcc.type != AccountType.asset &&
            !(destAcc.type == AccountType.liability &&
                destAcc.subType == AccountSubType.creditCard))) {
      throw DoubleEntryValidationError(
        'Refunds must return to an active Verified ETB liquid asset or credit card account.',
      );
    }

    final original = entries.firstWhere((e) => e.id == originalEntryId);
    final entry = JournalEntryModel(
      id: refundEntryId,
      entryType: EntryType.standard,
      description: 'Refund: ${original.description}',
      occurrenceDate: refundDateIso,
      legacySourceTxId: '$refundTagPrefix${original.id}:$refundEntryId',
    );
    final cleanNote =
        (note != null && note.trim().isNotEmpty) ? note.trim() : null;
    final refundPostings = [
      PostingModel(
        id: '$refundEntryId-post-dr',
        entryId: refundEntryId,
        accountId: refundAccountId,
        amountCents: refundCents,
        direction: PostingDirection.debit,
        accountMovementDate: refundDateIso,
        note: cleanNote ?? 'Refund for ${original.description}',
      ),
      PostingModel(
        id: '$refundEntryId-post-cr',
        entryId: refundEntryId,
        accountId: SystemControlAccounts.expense,
        amountCents: refundCents,
        direction: PostingDirection.credit,
        accountMovementDate: refundDateIso,
        categoryId: summary.categoryId,
        note: cleanNote ?? 'Refund for ${original.description}',
      ),
    ];
    validateBalancedEntry(refundPostings);

    return {
      'entry': entry,
      'postings': refundPostings,
      'summary': summary,
    };
  }
}
