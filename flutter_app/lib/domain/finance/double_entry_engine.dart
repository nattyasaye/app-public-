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

  static const String canonicalDefaultExpenseCategoryId = 'cat-other-exp';
  static const String canonicalDefaultIncomeCategoryId = 'cat-other-inc';

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

const Map<String, String> kLegacyCategoryIdAliases = {
  'cat-other': SystemControlAccounts.canonicalDefaultExpenseCategoryId,
  'cat-misc': SystemControlAccounts.canonicalDefaultExpenseCategoryId,
  'cat-exp-other': SystemControlAccounts.canonicalDefaultExpenseCategoryId,
  'cat-inc-other': SystemControlAccounts.canonicalDefaultIncomeCategoryId,
  'cat-from-asaye': 'cat-asaye',
  'cat-communication': 'cat-comm',
};

const Map<String, ({String name, String type})> kCanonicalCategoryFallbacks = {
  'cat-food': (name: 'Food', type: 'expense'),
  'cat-transport': (name: 'Transport', type: 'expense'),
  'cat-housing': (name: 'Housing', type: 'expense'),
  'cat-utilities': (name: 'Utilities', type: 'expense'),
  'cat-comm': (name: 'Communication', type: 'expense'),
  'cat-other-exp': (name: 'Other', type: 'expense'),
  'cat-fees': (name: 'Financial Fees', type: 'expense'),
  'cat-salary': (name: 'Salary', type: 'income'),
  'cat-freelance': (name: 'Freelance & Business', type: 'income'),
  'cat-asaye': (name: 'From Asaye', type: 'income'),
  'cat-invest': (name: 'Investments & Returns', type: 'income'),
  'cat-other-inc': (name: 'Other Income', type: 'income'),
};

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
  final int originalFeeCents;
  final int refundedCents;
  final int remainingRefundableCents;
  final String? categoryId;
  final String? originalAccountId;
  final String? originalOccurrenceDate;

  const ExpenseRefundSummary({
    required this.eligible,
    this.reason,
    required this.originalAmountCents,
    this.originalFeeCents = 0,
    required this.refundedCents,
    required this.remainingRefundableCents,
    this.categoryId,
    this.originalAccountId,
    this.originalOccurrenceDate,
  });
}

class TransferDisplayEndpoints {
  final String? sourceAccountId;
  final String? destinationAccountId;
  final String? sourceName;
  final String? destinationName;
  final List<String> fallbackAccountNames;
  final bool isUnambiguous;

  const TransferDisplayEndpoints({
    this.sourceAccountId,
    this.destinationAccountId,
    this.sourceName,
    this.destinationName,
    this.fallbackAccountNames = const [],
    required this.isUnambiguous,
  });

  String get displayLabel {
    if (isUnambiguous && sourceName != null && destinationName != null) {
      return '$sourceName → $destinationName';
    }
    return fallbackAccountNames.join(' · ');
  }
}

class DirectExpenseSummary {
  final bool isDirectExpense;
  final int principalCents;
  final int feeCents;
  final int totalOutflowCents;
  final String? primaryCategoryId;
  final String? feeCategoryId;
  final String? paidAccountId;

  const DirectExpenseSummary({
    required this.isDirectExpense,
    required this.principalCents,
    required this.feeCents,
    required this.totalOutflowCents,
    this.primaryCategoryId,
    this.feeCategoryId,
    this.paidAccountId,
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

  PostingModel copyWith({
    String? id,
    String? entryId,
    String? accountId,
    int? amountCents,
    PostingDirection? direction,
    String? accountMovementDate,
    String? categoryId,
    bool clearCategoryId = false,
    String? note,
    bool clearNote = false,
  }) {
    return PostingModel(
      id: id ?? this.id,
      entryId: entryId ?? this.entryId,
      accountId: accountId ?? this.accountId,
      amountCents: amountCents ?? this.amountCents,
      direction: direction ?? this.direction,
      accountMovementDate: accountMovementDate ?? this.accountMovementDate,
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      note: clearNote ? null : (note ?? this.note),
    );
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

enum ReportPeriodMode {
  thisMonth,
  ethiopianMonth,
  last30Days,
  thisYear,
  custom,
}

class ResolvedReportPeriod {
  final ReportPeriodMode mode;
  final String currentStart;
  final String currentEnd;
  final String previousStart;
  final String previousEnd;
  final String label;
  final String baselineLabel;
  final int daysInCurrent;
  final int daysInPrevious;

  const ResolvedReportPeriod({
    required this.mode,
    required this.currentStart,
    required this.currentEnd,
    required this.previousStart,
    required this.previousEnd,
    required this.label,
    required this.baselineLabel,
    required this.daysInCurrent,
    required this.daysInPrevious,
  });
}

class SafePercentageChangeResult {
  final double? percentageChange;
  final String percentageDisplay;

  const SafePercentageChangeResult({
    required this.percentageChange,
    required this.percentageDisplay,
  });
}

class MetricComparisonDelta {
  final int currentCents;
  final int previousCents;
  final int deltaCents;
  final double? percentageChange;
  final String percentageDisplay;
  final bool? isPositiveOutcome;

  const MetricComparisonDelta({
    required this.currentCents,
    required this.previousCents,
    required this.deltaCents,
    required this.percentageChange,
    required this.percentageDisplay,
    required this.isPositiveOutcome,
  });
}

class PeriodComparisonReport {
  final ResolvedReportPeriod period;
  final ({
    int incomeCents,
    int expenseCents,
    int netCashflowCents
  }) currentOccurrence;
  final ({
    int incomeCents,
    int expenseCents,
    int netCashflowCents
  }) previousOccurrence;
  final ({
    int inflowCents,
    int outflowCents,
    int netCashflowCents
  }) currentLiquidCash;
  final ({
    int inflowCents,
    int outflowCents,
    int netCashflowCents
  }) previousLiquidCash;
  final MetricComparisonDelta occurrenceIncome;
  final MetricComparisonDelta occurrenceExpense;
  final MetricComparisonDelta occurrenceNet;
  final MetricComparisonDelta cashInflow;
  final MetricComparisonDelta cashOutflow;
  final MetricComparisonDelta cashNet;

  const PeriodComparisonReport({
    required this.period,
    required this.currentOccurrence,
    required this.previousOccurrence,
    required this.currentLiquidCash,
    required this.previousLiquidCash,
    required this.occurrenceIncome,
    required this.occurrenceExpense,
    required this.occurrenceNet,
    required this.cashInflow,
    required this.cashOutflow,
    required this.cashNet,
  });
}

class CategorySpendRow {
  final String categoryId;
  final String categoryName;
  final String? parentId;
  final int directCents;
  final int rollupCents;
  final int sharePercent;
  final double exactShareRatio;
  final bool isArchived;
  final List<CategorySpendRow> children;

  const CategorySpendRow({
    required this.categoryId,
    required this.categoryName,
    this.parentId,
    required this.directCents,
    required this.rollupCents,
    required this.sharePercent,
    required this.exactShareRatio,
    required this.isArchived,
    this.children = const [],
  });
}

class CanonicalCategorySpendReport {
  final String startDate;
  final String endDate;
  final int totalExpenseCents;
  final Map<String, int> directSpendByCategoryId;
  final Map<String, int> rollupSpendByCategoryId;
  final List<CategorySpendRow> rows;

  const CanonicalCategorySpendReport({
    required this.startDate,
    required this.endDate,
    required this.totalExpenseCents,
    required this.directSpendByCategoryId,
    required this.rollupSpendByCategoryId,
    required this.rows,
  });
}

class AccountBalanceReportItem {
  final String accountId;
  final String name;
  final AccountType type;
  final AccountSubType subType;
  final String currencyCode;
  final int balanceCents;
  final int owedCents;
  final int prepaidCents;
  final bool isArchived;
  final CurrencyValidationTier currencyTier;

  const AccountBalanceReportItem({
    required this.accountId,
    required this.name,
    required this.type,
    required this.subType,
    required this.currencyCode,
    required this.balanceCents,
    required this.owedCents,
    required this.prepaidCents,
    required this.isArchived,
    required this.currencyTier,
  });
}

class AccountBalancesReport {
  final List<AccountBalanceReportItem> liquidAccounts;
  final List<AccountBalanceReportItem> vaultAccounts;
  final List<AccountBalanceReportItem> creditCardAccounts;
  final List<AccountBalanceReportItem> nonEtbReviewAccounts;
  final int archivedCount;
  final int liquidTotalCents;
  final int vaultTotalCents;
  final int creditCardOwedTotalCents;
  final int prepaidCardCreditTotalCents;

  const AccountBalancesReport({
    required this.liquidAccounts,
    required this.vaultAccounts,
    required this.creditCardAccounts,
    required this.nonEtbReviewAccounts,
    required this.archivedCount,
    required this.liquidTotalCents,
    required this.vaultTotalCents,
    required this.creditCardOwedTotalCents,
    required this.prepaidCardCreditTotalCents,
  });
}

class SavingsGoalReportItem {
  final String goalId;
  final String title;
  final int targetCents;
  final int allocatedCents;
  final int remainingCents;
  final int percentComplete;
  final String? targetDate;
  final SavingsGoalStatus status;
  final String? linkedAccountId;
  final String? linkedAccountName;
  final bool isVaultLinked;
  final bool isExcludedNonEtbVault;

  const SavingsGoalReportItem({
    required this.goalId,
    required this.title,
    required this.targetCents,
    required this.allocatedCents,
    required this.remainingCents,
    required this.percentComplete,
    this.targetDate,
    required this.status,
    this.linkedAccountId,
    this.linkedAccountName,
    required this.isVaultLinked,
    required this.isExcludedNonEtbVault,
  });
}

class SavingsVaultsReport {
  final List<AccountBalanceReportItem> vaults;
  final List<SavingsGoalReportItem> goals;
  final int totalVaultBalanceCents;
  final int totalGoalTargetCents;
  final int totalGoalAllocatedCents;

  const SavingsVaultsReport({
    required this.vaults,
    required this.goals,
    required this.totalVaultBalanceCents,
    required this.totalGoalTargetCents,
    required this.totalGoalAllocatedCents,
  });
}

class MonthlyBudgetReportItem {
  final String budgetId;
  final String categoryId;
  final String categoryName;
  final String monthIso;
  final int limitCents;
  final int spentCents;
  final int remainingCents;
  final int percentUsed;
  final bool isOverBudget;
  final bool rolloverEnabled;

  const MonthlyBudgetReportItem({
    required this.budgetId,
    required this.categoryId,
    required this.categoryName,
    required this.monthIso,
    required this.limitCents,
    required this.spentCents,
    required this.remainingCents,
    required this.percentUsed,
    required this.isOverBudget,
    required this.rolloverEnabled,
  });
}

class MonthlyBudgetProgressReport {
  final String monthIso;
  final int totalLimitCents;
  final int totalSpentCents;
  final List<MonthlyBudgetReportItem> items;

  const MonthlyBudgetProgressReport({
    required this.monthIso,
    required this.totalLimitCents,
    required this.totalSpentCents,
    required this.items,
  });
}

class AlignedBalanceSheetReport {
  final String planningPeriodEndIso;
  final int liquidCashCents;
  final int vaultSavingsCents;
  final int receivablesCents;
  final int prepaidCardCreditCents;
  final int shortTermCreditOwedCents;
  final int activePayablesCents;
  final int duePayablesCents;
  final int netFinancialPositionCents;

  const AlignedBalanceSheetReport({
    required this.planningPeriodEndIso,
    required this.liquidCashCents,
    required this.vaultSavingsCents,
    required this.receivablesCents,
    required this.prepaidCardCreditCents,
    required this.shortTermCreditOwedCents,
    required this.activePayablesCents,
    required this.duePayablesCents,
    required this.netFinancialPositionCents,
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
        'Legacy non-ETB debts are read-only and cannot be settled or written off in ETB Finance.',
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
      if (cache != null) cache[entry.id] = res;
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
      if (!ignoreVoidFlag && cache != null) cache[entry.id] = res;
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
      if (!ignoreVoidFlag && cache != null) cache[entry.id] = res;
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
      if (!ignoreVoidFlag && cache != null) cache[entry.id] = res;
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
        if (!ignoreVoidFlag && cache != null) cache[entry.id] = res;
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
        if (!ignoreVoidFlag && cache != null) cache[entry.id] = res;
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
            if (!ignoreVoidFlag && cache != null) cache[entry.id] = res;
            return res;
          }
          final originEntry =
              entryById != null ? entryById[debt.originEntryId] : null;
          if (originEntry == null || originEntry.isVoided) {
            final res = EntryCurrencyClassification(
              entryId: entry.id,
              status: EntryCurrencyStatus.mixedOrAmbiguous,
              touchedCurrencies: scanned.financialCurrencies.toSet(),
              reason:
                  'Settlement references debt with missing or voided origin entry.',
            );
            if (!ignoreVoidFlag && cache != null) cache[entry.id] = res;
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
            if (!ignoreVoidFlag && cache != null) cache[entry.id] = res;
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
            if (!ignoreVoidFlag && cache != null) cache[entry.id] = res;
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
      if (!ignoreVoidFlag && cache != null) cache[entry.id] = res;
      return res;
    }

    // [3B] System-only entry (financialLegCount == 0)
    // 1) Write-off entry -> inherit Debt.originEntryId
    final writeOffDebt =
        debtByWriteOffEntryId != null ? debtByWriteOffEntryId[entry.id] : null;
    if (entry.entryType == EntryType.writeOff || writeOffDebt != null) {
      if (writeOffDebt == null || entryById == null) {
        final res = EntryCurrencyClassification(
          entryId: entry.id,
          status: EntryCurrencyStatus.mixedOrAmbiguous,
          reason: 'Write-off entry has no verifiable linked debt.',
        );
        if (!ignoreVoidFlag && cache != null) cache[entry.id] = res;
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
        if (!ignoreVoidFlag && cache != null) cache[entry.id] = res;
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
      if (!ignoreVoidFlag && cache != null) cache[entry.id] = res;
      return res;
    }

    // 2) Corrected replacement entry -> inherit original entry's economic legs
    if (entry.correctedFromEntryId != null &&
        entry.correctedFromEntryId!.isNotEmpty) {
      final original =
          entryById != null ? entryById[entry.correctedFromEntryId!] : null;
      if (original == null) {
        final res = EntryCurrencyClassification(
          entryId: entry.id,
          status: EntryCurrencyStatus.mixedOrAmbiguous,
          reason: 'Correction entry references missing original entry.',
        );
        if (!ignoreVoidFlag && cache != null) cache[entry.id] = res;
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
      if (!ignoreVoidFlag && cache != null) cache[entry.id] = res;
      return res;
    }

    // 3) Third-party-paid expense backed by Debt(originEntryId == entry.id)
    final originDebt =
        debtByOriginEntryId != null ? debtByOriginEntryId[entry.id] : null;
    if (originDebt != null && entry.entryType == EntryType.debtIssuance) {
      final List<SettlementAllocationModel> linkedAllocs =
          allocationsByDebtId != null
              ? (allocationsByDebtId[originDebt.id] ?? const [])
              : const [];
      final settlementCurrencies = <String>{};
      for (final alloc in linkedAllocs) {
        final settleEntry =
            entryById != null ? entryById[alloc.settlementEntryId] : null;
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
          if (!ignoreVoidFlag && cache != null) cache[entry.id] = res;
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
        if (!ignoreVoidFlag && cache != null) cache[entry.id] = res;
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
        if (!ignoreVoidFlag && cache != null) cache[entry.id] = res;
        return res;
      }

      // Unsettled debt-backed third-party expense has 0 financial legs and no
      // persisted entry currency in Schema v7 -> Currency Review until settled.
      final res = EntryCurrencyClassification(
        entryId: entry.id,
        status: EntryCurrencyStatus.mixedOrAmbiguous,
        reason: 'Unsettled third-party entry requires Currency Review.',
      );
      if (!ignoreVoidFlag && cache != null) cache[entry.id] = res;
      return res;
    }

    // 4) Unlinked system-only entry -> NEVER silently classify as ETB
    final res = EntryCurrencyClassification(
      entryId: entry.id,
      status: EntryCurrencyStatus.mixedOrAmbiguous,
      reason: 'Unlinked system-only entry without financial account leg.',
    );
    if (!ignoreVoidFlag && cache != null) cache[entry.id] = res;
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
      final rawCatId = p.categoryId;
      if (rawCatId == null || rawCatId.trim().isEmpty) continue;
      if (entry.occurrenceDate.compareTo(startDateIso) < 0 ||
          entry.occurrenceDate.compareTo(endDateIso) > 0) {
        continue;
      }

      final matchedCat = categories == null
          ? null
          : findCategoryByIdOrAlias(categories, rawCatId);
      final bucketId = matchedCat?.id ?? resolveCanonicalCategoryId(rawCatId);

      if (matchedCat != null && matchedCat.type != 'expense') continue;
      if (matchedCat == null && categoryTypes != null) {
        final type = categoryTypes[bucketId] ?? categoryTypes[rawCatId];
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
      totals[bucketId] = (totals[bucketId] ?? 0) + delta;
    }

    if (rollupToParents && categories != null) {
      String? resolveParentBucketId(String catId) {
        final cat = findCategoryByIdOrAlias(categories, catId);
        final rawParent = cat?.parentId;
        if (rawParent == null || rawParent.trim().isEmpty) return null;
        final matchedParent = findCategoryByIdOrAlias(categories, rawParent);
        return matchedParent?.id ?? resolveCanonicalCategoryId(rawParent);
      }

      final rolledUp = Map<String, int>.from(totals);
      for (final entry in totals.entries) {
        if (entry.value == 0) continue;
        final visited = <String>{entry.key};
        var parentId = resolveParentBucketId(entry.key);
        while (parentId != null && !visited.contains(parentId)) {
          visited.add(parentId);
          rolledUp[parentId] = (rolledUp[parentId] ?? 0) + entry.value;
          parentId = resolveParentBucketId(parentId);
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

  /// Resolves a legacy category ID alias to its canonical category ID without mutating stored data.
  static String resolveCanonicalCategoryId(String categoryId) {
    final trimmed = categoryId.trim();
    return kLegacyCategoryIdAliases[trimmed] ?? trimmed;
  }

  /// Checks whether two category IDs match directly or via canonical alias equivalence.
  static bool categoryIdsMatchOrAlias(String? a, String? b) {
    if (a == null || b == null) return false;
    final cleanA = a.trim();
    final cleanB = b.trim();
    if (cleanA.isEmpty || cleanB.isEmpty) return false;
    if (cleanA == cleanB) return true;
    return resolveCanonicalCategoryId(cleanA) ==
        resolveCanonicalCategoryId(cleanB);
  }

  /// Finds a matching category by exact ID or canonical alias equivalence.
  static TransactionCategoryModel? findCategoryByIdOrAlias(
    List<TransactionCategoryModel> categories,
    String? categoryId, {
    String? expectedType,
  }) {
    if (categoryId == null || categoryId.trim().isEmpty) return null;
    final cleanId = categoryId.trim();
    bool matchesType(TransactionCategoryModel c) =>
        expectedType == null || c.type == expectedType;

    for (final c in categories) {
      if (c.id == cleanId && matchesType(c)) return c;
    }
    final canonicalId = resolveCanonicalCategoryId(cleanId);
    for (final c in categories) {
      if (c.id == canonicalId && matchesType(c)) return c;
    }
    for (final c in categories) {
      if (resolveCanonicalCategoryId(c.id) == canonicalId && matchesType(c)) {
        return c;
      }
    }
    return null;
  }

  /// Resolves a human-readable category display name across active/archived categories and canonical aliases.
  static String resolveCategoryDisplayName(
    List<TransactionCategoryModel> categories,
    String? categoryId,
  ) {
    if (categoryId == null || categoryId.trim().isEmpty) return 'Uncategorized';
    final cleanId = categoryId.trim();
    final found = findCategoryByIdOrAlias(categories, cleanId);
    if (found != null) return found.name;
    final canonicalId = resolveCanonicalCategoryId(cleanId);
    return kCanonicalCategoryFallbacks[canonicalId]?.name ?? cleanId;
  }

  static String canonicalCategoryNameForSeed(
    String categoryId, {
    String fallback = 'General',
  }) {
    final canonicalId = resolveCanonicalCategoryId(categoryId);
    return kCanonicalCategoryFallbacks[canonicalId]?.name ?? fallback;
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
    String? movementDate,
    String? dueDate,
    required String description,
    String? note,
  }) {
    final effectiveMovementDate = movementDate ?? date;
    final cleanNote =
        (note != null && note.trim().isNotEmpty) ? note.trim() : null;
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
        accountMovementDate: effectiveMovementDate,
        note: cleanNote,
      ),
      PostingModel(
        id: '$entryId-cr-cash',
        entryId: entryId,
        accountId: sourceAssetAccountId,
        amountCents: amountCents,
        direction: PostingDirection.credit,
        accountMovementDate: effectiveMovementDate,
        note: cleanNote,
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
    String? movementDate,
    String? dueDate,
    required String description,
    String? note,
  }) {
    final effectiveMovementDate = movementDate ?? date;
    final cleanNote =
        (note != null && note.trim().isNotEmpty) ? note.trim() : null;
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
        accountMovementDate: effectiveMovementDate,
        note: cleanNote,
      ),
      PostingModel(
        id: '$entryId-cr-payable',
        entryId: entryId,
        accountId: payableAccountId,
        amountCents: amountCents,
        direction: PostingDirection.credit,
        accountMovementDate: effectiveMovementDate,
        note: cleanNote,
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
    String? movementDate,
    String? dueDate,
    required String description,
    String? categoryId,
    String? note,
  }) {
    final total = myShareCents + theirShareCents;
    final effectiveMovementDate = movementDate ?? occurrenceDate;
    final cleanNote =
        (note != null && note.trim().isNotEmpty) ? note.trim() : null;
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
        note: cleanNote,
      ),
      PostingModel(
        id: '$entryId-dr-rec',
        entryId: entryId,
        accountId: receivableAccountId,
        amountCents: theirShareCents,
        direction: PostingDirection.debit,
        accountMovementDate: effectiveMovementDate,
        note: cleanNote,
      ),
      PostingModel(
        id: '$entryId-cr-cash',
        entryId: entryId,
        accountId: paidAssetAccountId,
        amountCents: total,
        direction: PostingDirection.credit,
        accountMovementDate: effectiveMovementDate,
        note: cleanNote,
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

  static bool isExpenseFeePosting(PostingModel posting) {
    return posting.id.endsWith('-dr-fee') ||
        posting.id.endsWith('-post-dr-fee');
  }

  static const Set<String> _systemPostingNoteMarkers = {
    'Bank / transaction fee',
    'Transfer service fee',
    'Opening balance',
    'Opening equity offset',
  };

  /// Returns a single unambiguous non-empty historical user note from [postings],
  /// ignoring fee postings and system marker strings. Returns null when zero or
  /// conflicting distinct notes exist.
  static String? resolveUnambiguousHistoricalPostingNote(
    List<PostingModel> postings,
  ) {
    final distinct = <String>{};
    for (final p in postings) {
      if (isExpenseFeePosting(p)) continue;
      final trimmed = p.note?.trim() ?? '';
      if (trimmed.isEmpty || _systemPostingNoteMarkers.contains(trimmed)) {
        continue;
      }
      distinct.add(trimmed);
      if (distinct.length > 1) return null;
    }
    return distinct.length == 1 ? distinct.first : null;
  }

  /// Resolves the single user-facing description while preserving historical note safety:
  /// - Never overwrites an existing non-empty [description].
  /// - Never duplicates text when both [description] and [legacyNote] contain data.
  /// - Copies non-empty [legacyNote] into blank [description] when available.
  static String resolveDescriptionPreservingLegacyNote({
    String? description,
    String? legacyNote,
    String fallback = '',
  }) {
    final trimmedDesc = description?.trim() ?? '';
    if (trimmedDesc.isNotEmpty) return trimmedDesc;
    final trimmedNote = legacyNote?.trim() ?? '';
    if (trimmedNote.isNotEmpty &&
        !_systemPostingNoteMarkers.contains(trimmedNote)) {
      return trimmedNote;
    }
    return fallback;
  }

  /// Resolves transfer display endpoints strictly from posting directions:
  /// - Source account: non-system account with a credit posting.
  /// - Destination account: non-system account with a debit posting.
  /// Returns [isUnambiguous] == true only when there is exactly one unique
  /// non-system source and one unique, distinct non-system destination.
  static TransferDisplayEndpoints resolveTransferDisplayEndpoints({
    required List<PostingModel> postings,
    required Iterable<AccountModel> accounts,
  }) {
    final accountById = {for (final a in accounts) a.id: a};
    bool isSystemAccountId(String id) =>
        SystemControlAccounts.isSystemControlId(id) ||
        (accountById[id]?.isSystem ?? false);

    final creditAccountIds = <String>[];
    final debitAccountIds = <String>[];
    final fallbackNames = <String>[];

    for (final p in postings) {
      if (isSystemAccountId(p.accountId)) continue;
      final displayName = accountById[p.accountId]?.name ?? p.accountId;
      if (!fallbackNames.contains(displayName)) {
        fallbackNames.add(displayName);
      }
      if (p.direction == PostingDirection.credit &&
          !creditAccountIds.contains(p.accountId)) {
        creditAccountIds.add(p.accountId);
      } else if (p.direction == PostingDirection.debit &&
          !debitAccountIds.contains(p.accountId)) {
        debitAccountIds.add(p.accountId);
      }
    }

    if (creditAccountIds.length == 1 &&
        debitAccountIds.length == 1 &&
        creditAccountIds.first != debitAccountIds.first) {
      final srcId = creditAccountIds.first;
      final dstId = debitAccountIds.first;
      return TransferDisplayEndpoints(
        sourceAccountId: srcId,
        destinationAccountId: dstId,
        sourceName: accountById[srcId]?.name ?? srcId,
        destinationName: accountById[dstId]?.name ?? dstId,
        fallbackAccountNames: fallbackNames,
        isUnambiguous: true,
      );
    }

    return TransferDisplayEndpoints(
      sourceAccountId:
          creditAccountIds.length == 1 ? creditAccountIds.first : null,
      destinationAccountId:
          debitAccountIds.length == 1 ? debitAccountIds.first : null,
      sourceName: creditAccountIds.length == 1
          ? (accountById[creditAccountIds.first]?.name ??
              creditAccountIds.first)
          : null,
      destinationName: debitAccountIds.length == 1
          ? (accountById[debitAccountIds.first]?.name ?? debitAccountIds.first)
          : null,
      fallbackAccountNames: fallbackNames,
      isUnambiguous: false,
    );
  }

  /// Summarizes a direct expense entry, separating merchant principal from
  /// optional bank/transaction fee postings (`-dr-fee` / `-post-dr-fee`).
  /// Historical expenses without fee postings always yield `feeCents == 0`.
  static DirectExpenseSummary summarizeDirectExpense({
    required JournalEntryModel entry,
    required List<PostingModel> postings,
    required Iterable<AccountModel> accounts,
  }) {
    if (entry.entryType != EntryType.standard || isRefundEntry(entry)) {
      return const DirectExpenseSummary(
        isDirectExpense: false,
        principalCents: 0,
        feeCents: 0,
        totalOutflowCents: 0,
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

    if (postings.any((p) => isIncomeOrDebtAcc(p.accountId))) {
      return const DirectExpenseSummary(
        isDirectExpense: false,
        principalCents: 0,
        feeCents: 0,
        totalOutflowCents: 0,
      );
    }

    final expenseDebits = postings
        .where(
          (p) =>
              p.direction == PostingDirection.debit &&
              isExpenseAcc(p.accountId),
        )
        .toList(growable: false);
    final expenseCredits = postings
        .where(
          (p) =>
              p.direction == PostingDirection.credit &&
              isExpenseAcc(p.accountId),
        )
        .toList(growable: false);

    PostingModel? paidCreditPosting;
    for (final p in postings) {
      final isSys = SystemControlAccounts.isSystemControlId(p.accountId) ||
          (accountById[p.accountId]?.isSystem ?? false);
      if (p.direction == PostingDirection.credit && !isSys) {
        paidCreditPosting = p;
        break;
      }
    }

    final principalDebits = expenseDebits
        .where((p) => !isExpenseFeePosting(p))
        .toList(growable: false);
    if (principalDebits.isEmpty ||
        expenseCredits.isNotEmpty ||
        paidCreditPosting == null) {
      return const DirectExpenseSummary(
        isDirectExpense: false,
        principalCents: 0,
        feeCents: 0,
        totalOutflowCents: 0,
      );
    }

    final feeDebits =
        expenseDebits.where(isExpenseFeePosting).toList(growable: false);
    final principalCents =
        principalDebits.fold<int>(0, (sum, p) => sum + p.amountCents);
    final feeCents = feeDebits.fold<int>(0, (sum, p) => sum + p.amountCents);
    final totalOutflowCents = principalCents + feeCents;

    String? primaryCategoryId;
    for (final p in principalDebits) {
      if (p.categoryId != null && p.categoryId!.trim().isNotEmpty) {
        primaryCategoryId = p.categoryId;
        break;
      }
    }
    String? feeCategoryId;
    for (final p in feeDebits) {
      if (p.categoryId != null && p.categoryId!.trim().isNotEmpty) {
        feeCategoryId = p.categoryId;
        break;
      }
    }

    return DirectExpenseSummary(
      isDirectExpense: true,
      principalCents: principalCents,
      feeCents: feeCents,
      totalOutflowCents: totalOutflowCents,
      primaryCategoryId: primaryCategoryId,
      feeCategoryId: feeCategoryId,
      paidAccountId: paidCreditPosting.accountId,
    );
  }

  /// Direct Expense: Dr Expense Control (categoryId), optional Dr Fee
  /// Category (`cat-fees`) when [feeCents] > 0, Cr Cash/Bank/Card.
  static Map<String, dynamic> buildDirectExpense({
    required String entryId,
    required String paidAccountId,
    String expenseAccountId = SystemControlAccounts.expense,
    required String categoryId,
    required int amountCents,
    int feeCents = 0,
    String? feeCategoryId,
    required String date,
    String? movementDate,
    required String description,
    String? note,
    String? correctedFromEntryId,
  }) {
    if (feeCents < 0) {
      throw DoubleEntryValidationError(
        'Expense fee must be non-negative, got $feeCents.',
      );
    }
    final effectiveMovementDate = movementDate ?? date;
    final entry = JournalEntryModel(
      id: entryId,
      entryType: EntryType.standard,
      description: description,
      occurrenceDate: date,
      correctedFromEntryId: correctedFromEntryId,
    );
    final postings = <PostingModel>[
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
    ];
    if (feeCents > 0) {
      final effectiveFeeCat =
          (feeCategoryId != null && feeCategoryId.trim().isNotEmpty)
              ? feeCategoryId.trim()
              : SystemControlAccounts.feeCategoryId;
      postings.add(
        PostingModel(
          id: '$entryId-dr-fee',
          entryId: entryId,
          accountId: expenseAccountId,
          amountCents: feeCents,
          direction: PostingDirection.debit,
          accountMovementDate: date,
          categoryId: effectiveFeeCat,
          note: 'Bank / transaction fee',
        ),
      );
    }
    postings.add(
      PostingModel(
        id: '$entryId-cr-acc',
        entryId: entryId,
        accountId: paidAccountId,
        amountCents: amountCents + feeCents,
        direction: PostingDirection.credit,
        accountMovementDate: effectiveMovementDate,
        note: note,
      ),
    );
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
    String? movementDate,
    required String description,
    String? note,
    String? correctedFromEntryId,
  }) {
    final effectiveMovementDate = movementDate ?? date;
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
        accountMovementDate: effectiveMovementDate,
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
        reason: 'Only active ETB expenses can be refunded.',
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

    final principalExpenseDebits = expenseDebits
        .where((p) => !isExpenseFeePosting(p))
        .toList(growable: false);
    final feeCents = expenseDebits
        .where(isExpenseFeePosting)
        .fold<int>(0, (sum, p) => sum + p.amountCents);

    if (principalExpenseDebits.isEmpty ||
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
        principalExpenseDebits.fold<int>(0, (sum, p) => sum + p.amountCents);
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

    final remainingRefundableCents =
        max(0, originalAmountCents - refundedCents);
    String? categoryId;
    for (final p in principalExpenseDebits) {
      if (p.categoryId != null && p.categoryId!.isNotEmpty) {
        categoryId = p.categoryId;
        break;
      }
    }

    return ExpenseRefundSummary(
      eligible: true,
      originalAmountCents: originalAmountCents,
      originalFeeCents: feeCents,
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
        error: 'Legacy non-ETB entries are read-only and cannot be replaced.',
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
        note: cleanNote,
      ),
      PostingModel(
        id: '$refundEntryId-post-cr',
        entryId: refundEntryId,
        accountId: SystemControlAccounts.expense,
        amountCents: refundCents,
        direction: PostingDirection.credit,
        accountMovementDate: refundDateIso,
        categoryId: summary.categoryId,
        note: cleanNote,
      ),
    ];
    validateBalancedEntry(refundPostings);

    return {
      'entry': entry,
      'postings': refundPostings,
      'summary': summary,
    };
  }

  // --------------------------------------------------------------------------
  // Stage F4: Reporting, Period Comparison, Hierarchical Category Spend &
  // Consolidated Position Builders
  // --------------------------------------------------------------------------

  static int getSavingsGoalEffectiveBalance({
    required SavingsGoalModel goal,
    required List<AccountModel> accounts,
    required List<JournalEntryModel> entries,
    required List<PostingModel> postings,
  }) {
    if (!goal.isVaultLinked) {
      return max(0, goal.currentAllocatedCents);
    }
    final vaultMatches = accounts.where((a) => a.id == goal.linkedAccountId);
    if (vaultMatches.isEmpty) {
      return max(0, goal.currentAllocatedCents);
    }
    return max(
      0,
      calculateAccountBalance(
        account: vaultMatches.first,
        postings: postings,
        entries: entries,
      ),
    );
  }

  static SafePercentageChangeResult calculateSafePercentageChange(
    int previousCents,
    int currentCents,
  ) {
    if (previousCents == 0 && currentCents == 0) {
      return const SafePercentageChangeResult(
        percentageChange: 0,
        percentageDisplay: '0.0%',
      );
    }
    if (previousCents == 0) {
      if (currentCents > 0) {
        return const SafePercentageChangeResult(
          percentageChange: 100,
          percentageDisplay: '+100% (New)',
        );
      }
      return const SafePercentageChangeResult(
        percentageChange: -100,
        percentageDisplay: '-100%',
      );
    }
    final change = ((currentCents - previousCents) / previousCents.abs()) * 100;
    final sign = change > 0 ? '+' : '';
    final rounded = (change * 10).roundToDouble() / 10;
    return SafePercentageChangeResult(
      percentageChange: rounded,
      percentageDisplay: '$sign${change.toStringAsFixed(1)}%',
    );
  }

  static ResolvedReportPeriod resolveReportPeriodWithComparison({
    required ReportPeriodMode mode,
    int? ethYear,
    int? ethMonth,
    String? customStartIso,
    String? customEndIso,
    String? todayIso,
  }) {
    final today = CalendarDate.tryParse(todayIso) ?? CalendarDate.today();

    if (mode == ReportPeriodMode.thisMonth) {
      final currStart = today.startOfGregorianMonth;
      final currEnd = today.endOfGregorianMonth;
      final prevRef = today.previousGregorianMonth();
      final prevStart = prevRef.startOfGregorianMonth;
      final prevEnd = prevRef.endOfGregorianMonth;
      return ResolvedReportPeriod(
        mode: ReportPeriodMode.thisMonth,
        currentStart: currStart.toIsoString(),
        currentEnd: currEnd.toIsoString(),
        previousStart: prevStart.toIsoString(),
        previousEnd: prevEnd.toIsoString(),
        label: '${today.gregorianFullMonthName} ${today.year}',
        baselineLabel: '${prevRef.gregorianFullMonthName} ${prevRef.year}',
        daysInCurrent: currEnd.differenceInDays(currStart) + 1,
        daysInPrevious: prevEnd.differenceInDays(prevStart) + 1,
      );
    }

    if (mode == ReportPeriodMode.ethiopianMonth) {
      final ethToday = today.toEthiopian();
      final y = ethYear ?? ethToday.year;
      final rawM = ethMonth ?? ethToday.month;
      final m = rawM < 1 ? 1 : (rawM > 13 ? 13 : rawM);
      final ethStart = EthiopianDate(year: y, month: m, day: 1);
      final ethEnd = ethStart.endOfMonth;
      final prevEthStart = ethStart.previousMonth().startOfMonth;
      final prevEthEnd = prevEthStart.endOfMonth;
      final currStartCal = ethStart.toCalendarDate();
      final currEndCal = ethEnd.toCalendarDate();
      final prevStartCal = prevEthStart.toCalendarDate();
      final prevEndCal = prevEthEnd.toCalendarDate();
      return ResolvedReportPeriod(
        mode: ReportPeriodMode.ethiopianMonth,
        currentStart: currStartCal.toIsoString(),
        currentEnd: currEndCal.toIsoString(),
        previousStart: prevStartCal.toIsoString(),
        previousEnd: prevEndCal.toIsoString(),
        label:
            '${ethStart.englishMonthName} (${ethStart.amharicMonthName}) $y E.C.',
        baselineLabel:
            '${prevEthStart.englishMonthName} ${prevEthStart.year} E.C.',
        daysInCurrent: ethStart.daysInMonth,
        daysInPrevious: prevEthStart.daysInMonth,
      );
    }

    if (mode == ReportPeriodMode.last30Days) {
      final currStart = today.subtractDays(29);
      final currEnd = today;
      final prevEnd = currStart.subtractDays(1);
      final prevStart = prevEnd.subtractDays(29);
      return ResolvedReportPeriod(
        mode: ReportPeriodMode.last30Days,
        currentStart: currStart.toIsoString(),
        currentEnd: currEnd.toIsoString(),
        previousStart: prevStart.toIsoString(),
        previousEnd: prevEnd.toIsoString(),
        label:
            'Last 30 Days (${currStart.toIsoString()} - ${currEnd.toIsoString()})',
        baselineLabel:
            'Prior 30 Days (${prevStart.toIsoString()} - ${prevEnd.toIsoString()})',
        daysInCurrent: 30,
        daysInPrevious: 30,
      );
    }

    if (mode == ReportPeriodMode.thisYear) {
      final currStart = CalendarDate(year: today.year, month: 1, day: 1);
      final currEnd = CalendarDate(year: today.year, month: 12, day: 31);
      final prevStart = CalendarDate(year: today.year - 1, month: 1, day: 1);
      final prevEnd = CalendarDate(year: today.year - 1, month: 12, day: 31);
      return ResolvedReportPeriod(
        mode: ReportPeriodMode.thisYear,
        currentStart: currStart.toIsoString(),
        currentEnd: currEnd.toIsoString(),
        previousStart: prevStart.toIsoString(),
        previousEnd: prevEnd.toIsoString(),
        label: 'Gregorian Year ${today.year}',
        baselineLabel: 'Gregorian Year ${today.year - 1}',
        daysInCurrent: currEnd.differenceInDays(currStart) + 1,
        daysInPrevious: prevEnd.differenceInDays(prevStart) + 1,
      );
    }

    final parsedStart =
        CalendarDate.tryParse(customStartIso) ?? today.subtractDays(29);
    final parsedEnd = CalendarDate.tryParse(customEndIso) ?? today;
    final startCal = parsedStart.isAfter(parsedEnd) ? parsedEnd : parsedStart;
    final endCal = parsedStart.isAfter(parsedEnd) ? parsedStart : parsedEnd;
    final nDays = endCal.differenceInDays(startCal) + 1;
    final prevEnd = startCal.subtractDays(1);
    final prevStart = prevEnd.subtractDays(nDays - 1);

    return ResolvedReportPeriod(
      mode: ReportPeriodMode.custom,
      currentStart: startCal.toIsoString(),
      currentEnd: endCal.toIsoString(),
      previousStart: prevStart.toIsoString(),
      previousEnd: prevEnd.toIsoString(),
      label: '${startCal.toIsoString()} to ${endCal.toIsoString()}',
      baselineLabel:
          'Prior ${nDays}d (${prevStart.toIsoString()} - ${prevEnd.toIsoString()})',
      daysInCurrent: nDays,
      daysInPrevious: nDays,
    );
  }

  static MetricComparisonDelta _buildMetricDelta(
    int previousCents,
    int currentCents, {
    required bool higherIsBetter,
  }) {
    final deltaCents = currentCents - previousCents;
    final pct = calculateSafePercentageChange(previousCents, currentCents);
    bool? isPositiveOutcome;
    if (deltaCents != 0) {
      isPositiveOutcome = higherIsBetter ? deltaCents > 0 : deltaCents < 0;
    }
    return MetricComparisonDelta(
      currentCents: currentCents,
      previousCents: previousCents,
      deltaCents: deltaCents,
      percentageChange: pct.percentageChange,
      percentageDisplay: pct.percentageDisplay,
      isPositiveOutcome: isPositiveOutcome,
    );
  }

  static PeriodComparisonReport calculatePeriodComparisonReport({
    required ResolvedReportPeriod period,
    required List<AccountModel> accounts,
    required List<JournalEntryModel> entries,
    required List<PostingModel> postings,
    List<DebtModel>? debts,
    List<SettlementAllocationModel>? allocations,
  }) {
    final currentOccurrence = calculateOccurrencePnlTotals(
      accounts: accounts,
      postings: postings,
      entries: entries,
      startDateIso: period.currentStart,
      endDateIso: period.currentEnd,
      debts: debts,
      allocations: allocations,
    );
    final previousOccurrence = calculateOccurrencePnlTotals(
      accounts: accounts,
      postings: postings,
      entries: entries,
      startDateIso: period.previousStart,
      endDateIso: period.previousEnd,
      debts: debts,
      allocations: allocations,
    );
    final currentLiquidCash = calculateLiquidCashflowTotals(
      accounts: accounts,
      postings: postings,
      entries: entries,
      startDateIso: period.currentStart,
      endDateIso: period.currentEnd,
      debts: debts,
      allocations: allocations,
    );
    final previousLiquidCash = calculateLiquidCashflowTotals(
      accounts: accounts,
      postings: postings,
      entries: entries,
      startDateIso: period.previousStart,
      endDateIso: period.previousEnd,
      debts: debts,
      allocations: allocations,
    );

    return PeriodComparisonReport(
      period: period,
      currentOccurrence: currentOccurrence,
      previousOccurrence: previousOccurrence,
      currentLiquidCash: currentLiquidCash,
      previousLiquidCash: previousLiquidCash,
      occurrenceIncome: _buildMetricDelta(
        previousOccurrence.incomeCents,
        currentOccurrence.incomeCents,
        higherIsBetter: true,
      ),
      occurrenceExpense: _buildMetricDelta(
        previousOccurrence.expenseCents,
        currentOccurrence.expenseCents,
        higherIsBetter: false,
      ),
      occurrenceNet: _buildMetricDelta(
        previousOccurrence.netCashflowCents,
        currentOccurrence.netCashflowCents,
        higherIsBetter: true,
      ),
      cashInflow: _buildMetricDelta(
        previousLiquidCash.inflowCents,
        currentLiquidCash.inflowCents,
        higherIsBetter: true,
      ),
      cashOutflow: _buildMetricDelta(
        previousLiquidCash.outflowCents,
        currentLiquidCash.outflowCents,
        higherIsBetter: false,
      ),
      cashNet: _buildMetricDelta(
        previousLiquidCash.netCashflowCents,
        currentLiquidCash.netCashflowCents,
        higherIsBetter: true,
      ),
    );
  }

  static CanonicalCategorySpendReport calculateCanonicalCategorySpend({
    required List<JournalEntryModel> entries,
    required List<PostingModel> postings,
    required List<AccountModel> accounts,
    required List<TransactionCategoryModel> categories,
    List<DebtModel>? debts,
    List<SettlementAllocationModel>? allocations,
    required String startDateIso,
    required String endDateIso,
  }) {
    final accountById = {for (final a in accounts) a.id: a};
    final entryById = {for (final e in entries) e.id: e};
    final classifications = classifyAllEntries(
      accounts: accounts,
      entries: entries,
      postings: postings,
      debts: debts,
      allocations: allocations,
    );

    final categoryMeta = <String, TransactionCategoryModel>{};
    for (final entry in kCanonicalCategoryFallbacks.entries) {
      categoryMeta[entry.key] = TransactionCategoryModel(
        id: entry.key,
        name: entry.value.name,
        type: entry.value.type,
        isDefault: true,
      );
    }
    for (final c in categories) {
      categoryMeta[c.id] = c;
    }

    final directSpend = <String, int>{};
    for (final p in postings) {
      final entry = entryById[p.entryId];
      if (entry == null || entry.isVoided) continue;
      if (!(classifications[entry.id]?.isEligibleEtb ?? false)) continue;
      if (entry.occurrenceDate.compareTo(startDateIso) < 0 ||
          entry.occurrenceDate.compareTo(endDateIso) > 0) {
        continue;
      }
      final acc = accountById[p.accountId];
      final isExpenseAcc = acc != null
          ? acc.type == AccountType.expense
          : p.accountId == SystemControlAccounts.expense;
      if (!isExpenseAcc) continue;

      final netExpense = p.direction == PostingDirection.debit
          ? p.amountCents
          : -p.amountCents;
      final rawCatId = (p.categoryId != null && p.categoryId!.trim().isNotEmpty)
          ? p.categoryId!.trim()
          : SystemControlAccounts.canonicalDefaultExpenseCategoryId;
      final matched = findCategoryByIdOrAlias(categories, rawCatId);
      final bucketId = matched?.id ?? resolveCanonicalCategoryId(rawCatId);
      directSpend[bucketId] = (directSpend[bucketId] ?? 0) + netExpense;
    }

    final totalExpenseCents =
        directSpend.values.fold<int>(0, (sum, val) => sum + val);

    String? resolveParentCanonicalId(String catId) {
      final cat =
          categoryMeta[catId] ?? findCategoryByIdOrAlias(categories, catId);
      final rawParent = cat?.parentId;
      if (rawParent == null || rawParent.trim().isEmpty) return null;
      final matchedParent = findCategoryByIdOrAlias(categories, rawParent);
      return matchedParent?.id ?? resolveCanonicalCategoryId(rawParent);
    }

    final rollupSpend = Map<String, int>.from(directSpend);
    for (final entry in directSpend.entries) {
      if (entry.value == 0) continue;
      final visited = <String>{entry.key};
      var currParentId = resolveParentCanonicalId(entry.key);
      while (currParentId != null && !visited.contains(currParentId)) {
        visited.add(currParentId);
        rollupSpend[currParentId] =
            (rollupSpend[currParentId] ?? 0) + entry.value;
        currParentId = resolveParentCanonicalId(currParentId);
      }
    }

    final allBucketIds = <String>{
      ...directSpend.keys,
      ...rollupSpend.keys,
    };
    final childrenByParent = <String, List<String>>{};
    for (final id in allBucketIds) {
      if ((rollupSpend[id] ?? 0) <= 0 && (directSpend[id] ?? 0) <= 0) {
        continue;
      }
      final parentId = resolveParentCanonicalId(id);
      if (parentId != null &&
          allBucketIds.contains(parentId) &&
          parentId != id) {
        childrenByParent.putIfAbsent(parentId, () => []).add(id);
      }
    }

    final denominator = max(0, totalExpenseCents);
    CategorySpendRow buildRow(String id, int depth, Set<String> seen) {
      final cat = categoryMeta[id] ?? findCategoryByIdOrAlias(categories, id);
      final parentId = resolveParentCanonicalId(id);
      final direct = directSpend[id] ?? 0;
      final rollup = rollupSpend[id] ?? direct;
      final ratio = denominator > 0 ? max(0.0, rollup / denominator) : 0.0;
      final childIds = (!seen.contains(id) && depth < 4)
          ? (childrenByParent[id] ?? const <String>[])
          : const <String>[];
      final nextSeen = {...seen, id};
      final children = childIds
          .map((cid) => buildRow(cid, depth + 1, nextSeen))
          .where((c) => c.rollupCents > 0)
          .toList()
        ..sort((a, b) => b.rollupCents.compareTo(a.rollupCents));

      return CategorySpendRow(
        categoryId: id,
        categoryName: cat?.name ?? resolveCategoryDisplayName(categories, id),
        parentId: parentId,
        directCents: direct,
        rollupCents: rollup,
        sharePercent: denominator > 0 ? (ratio * 100).round() : 0,
        exactShareRatio: ratio,
        isArchived: cat?.isArchived ?? false,
        children: List<CategorySpendRow>.unmodifiable(children),
      );
    }

    final topRows = <CategorySpendRow>[];
    for (final id in allBucketIds) {
      final rollup = rollupSpend[id] ?? 0;
      if (rollup <= 0) continue;
      final parentId = resolveParentCanonicalId(id);
      if (parentId == null ||
          parentId == id ||
          !allBucketIds.contains(parentId) ||
          (rollupSpend[parentId] ?? 0) <= 0) {
        topRows.add(buildRow(id, 0, const <String>{}));
      }
    }
    topRows.sort((a, b) => b.rollupCents.compareTo(a.rollupCents));

    return CanonicalCategorySpendReport(
      startDate: startDateIso,
      endDate: endDateIso,
      totalExpenseCents: totalExpenseCents,
      directSpendByCategoryId: Map<String, int>.unmodifiable(directSpend),
      rollupSpendByCategoryId: Map<String, int>.unmodifiable(rollupSpend),
      rows: List<CategorySpendRow>.unmodifiable(topRows),
    );
  }

  static int getCanonicalBudgetSpentCents(
    CanonicalCategorySpendReport spendReport,
    String budgetCategoryId,
    List<TransactionCategoryModel> categories,
  ) {
    final matched = findCategoryByIdOrAlias(categories, budgetCategoryId);
    final resolvedId =
        matched?.id ?? resolveCanonicalCategoryId(budgetCategoryId);
    return spendReport.rollupSpendByCategoryId[resolvedId] ??
        spendReport.directSpendByCategoryId[resolvedId] ??
        0;
  }

  static AccountBalancesReport buildAccountBalancesReport({
    required List<AccountModel> accounts,
    required List<JournalEntryModel> entries,
    required List<PostingModel> postings,
  }) {
    final liquidAccounts = <AccountBalanceReportItem>[];
    final vaultAccounts = <AccountBalanceReportItem>[];
    final creditCardAccounts = <AccountBalanceReportItem>[];
    final nonEtbReviewAccounts = <AccountBalanceReportItem>[];
    var archivedCount = 0;

    for (final acc in accounts) {
      if (acc.isSystem) continue;
      if (acc.isArchived) {
        archivedCount += 1;
        continue;
      }
      final tier = classifyCurrencyCode(acc.currencyCode);
      final normCurrency = normalizeCurrencyCode(acc.currencyCode);
      final bal = calculateAccountBalance(
        account: acc,
        postings: postings,
        entries: entries,
      );
      final item = AccountBalanceReportItem(
        accountId: acc.id,
        name: acc.name,
        type: acc.type,
        subType: acc.subType,
        currencyCode: normCurrency.isEmpty ? 'UNVERIFIED' : normCurrency,
        balanceCents: bal,
        owedCents: acc.type == AccountType.liability && bal > 0 ? bal : 0,
        prepaidCents: acc.type == AccountType.liability && bal < 0 ? -bal : 0,
        isArchived: acc.isArchived,
        currencyTier: tier,
      );

      if (tier != CurrencyValidationTier.verifiedEtb) {
        nonEtbReviewAccounts.add(item);
        continue;
      }

      if (acc.type == AccountType.asset) {
        if (acc.subType.isSavingsVault) {
          vaultAccounts.add(item);
        } else if (acc.subType != AccountSubType.receivable &&
            !acc.name.toLowerCase().contains('receivable')) {
          liquidAccounts.add(item);
        }
      } else if (acc.type == AccountType.liability &&
          acc.subType.isCreditCard) {
        creditCardAccounts.add(item);
      }
    }

    return AccountBalancesReport(
      liquidAccounts:
          List<AccountBalanceReportItem>.unmodifiable(liquidAccounts),
      vaultAccounts: List<AccountBalanceReportItem>.unmodifiable(vaultAccounts),
      creditCardAccounts:
          List<AccountBalanceReportItem>.unmodifiable(creditCardAccounts),
      nonEtbReviewAccounts:
          List<AccountBalanceReportItem>.unmodifiable(nonEtbReviewAccounts),
      archivedCount: archivedCount,
      liquidTotalCents:
          liquidAccounts.fold<int>(0, (s, a) => s + a.balanceCents),
      vaultTotalCents: vaultAccounts.fold<int>(0, (s, a) => s + a.balanceCents),
      creditCardOwedTotalCents:
          creditCardAccounts.fold<int>(0, (s, a) => s + a.owedCents),
      prepaidCardCreditTotalCents:
          creditCardAccounts.fold<int>(0, (s, a) => s + a.prepaidCents),
    );
  }

  static SavingsVaultsReport buildSavingsVaultsAndGoalsReport({
    required List<AccountModel> accounts,
    required List<JournalEntryModel> entries,
    required List<PostingModel> postings,
    required List<SavingsGoalModel> savingsGoals,
  }) {
    final accountById = {for (final a in accounts) a.id: a};
    final balances = buildAccountBalancesReport(
      accounts: accounts,
      entries: entries,
      postings: postings,
    );

    final goals = savingsGoals.map((g) {
      final linkedAcc =
          g.linkedAccountId != null ? accountById[g.linkedAccountId] : null;
      final isVaultLinked = g.isVaultLinked;
      final isExcludedNonEtbVault = isVaultLinked &&
          (linkedAcc == null ||
              !isActiveVerifiedEtbAccount(linkedAcc) ||
              !linkedAcc.subType.isSavingsVault);
      final allocatedCents = getSavingsGoalEffectiveBalance(
        goal: g,
        accounts: accounts,
        entries: entries,
        postings: postings,
      );
      final remainingCents = max(0, g.targetCents - allocatedCents);
      final percentComplete = g.targetCents > 0
          ? min(100, ((allocatedCents / g.targetCents) * 100).round())
          : 0;
      return SavingsGoalReportItem(
        goalId: g.id,
        title: g.title,
        targetCents: g.targetCents,
        allocatedCents: allocatedCents,
        remainingCents: remainingCents,
        percentComplete: percentComplete,
        targetDate: g.targetDate?.toIsoString(),
        status: g.status,
        linkedAccountId: g.linkedAccountId,
        linkedAccountName: linkedAcc?.name,
        isVaultLinked: isVaultLinked,
        isExcludedNonEtbVault: isExcludedNonEtbVault,
      );
    }).toList(growable: false);

    final activeNonExcluded = goals.where(
      (g) => g.status != SavingsGoalStatus.archived && !g.isExcludedNonEtbVault,
    );

    return SavingsVaultsReport(
      vaults: balances.vaultAccounts,
      goals: List<SavingsGoalReportItem>.unmodifiable(goals),
      totalVaultBalanceCents: balances.vaultTotalCents,
      totalGoalTargetCents:
          activeNonExcluded.fold<int>(0, (s, g) => s + g.targetCents),
      totalGoalAllocatedCents:
          activeNonExcluded.fold<int>(0, (s, g) => s + g.allocatedCents),
    );
  }

  static String resolveActiveReportMonthIso({
    required ReportPeriodMode mode,
    required String startDateIso,
    required String endDateIso,
    String? todayIso,
  }) {
    final effectiveTodayIso = todayIso ?? CalendarDate.today().toIsoString();
    if (mode == ReportPeriodMode.thisMonth ||
        (startDateIso.length >= 7 &&
            endDateIso.length >= 7 &&
            startDateIso.substring(0, 7) == endDateIso.substring(0, 7))) {
      return startDateIso.substring(0, 7);
    }
    return effectiveTodayIso.substring(0, 7);
  }

  static MonthlyBudgetProgressReport buildMonthlyBudgetProgressReport({
    required List<BudgetModel> budgets,
    required List<TransactionCategoryModel> categories,
    required List<JournalEntryModel> entries,
    required List<PostingModel> postings,
    required List<AccountModel> accounts,
    List<DebtModel>? debts,
    List<SettlementAllocationModel>? allocations,
    required String monthIso,
  }) {
    final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(monthIso.trim());
    final today = CalendarDate.today();
    final y = match != null ? int.parse(match.group(1)!) : today.year;
    final rawM = match != null ? int.parse(match.group(2)!) : today.month;
    final m = rawM < 1 ? 1 : (rawM > 12 ? 12 : rawM);
    final bounds = CalendarDate.monthBounds(CalendarSystem.gregorian, y, m);

    final spendReport = calculateCanonicalCategorySpend(
      entries: entries,
      postings: postings,
      accounts: accounts,
      categories: categories,
      debts: debts,
      allocations: allocations,
      startDateIso: bounds.start.toIsoString(),
      endDateIso: bounds.end.toIsoString(),
    );

    final matching = budgets.where((b) => b.monthIso == monthIso);
    final items = matching.map((b) {
      final spentCents = getCanonicalBudgetSpentCents(
        spendReport,
        b.categoryId,
        categories,
      );
      final remainingCents = b.limitCents - spentCents;
      final percentUsed = b.limitCents > 0
          ? min(100, ((spentCents / b.limitCents) * 100).round())
          : 0;
      return MonthlyBudgetReportItem(
        budgetId: b.id,
        categoryId: b.categoryId,
        categoryName: resolveCategoryDisplayName(categories, b.categoryId),
        monthIso: b.monthIso,
        limitCents: b.limitCents,
        spentCents: spentCents,
        remainingCents: remainingCents,
        percentUsed: percentUsed,
        isOverBudget: spentCents > b.limitCents,
        rolloverEnabled: b.rolloverEnabled,
      );
    }).toList(growable: false);

    return MonthlyBudgetProgressReport(
      monthIso: monthIso,
      totalLimitCents: items.fold<int>(0, (s, i) => s + i.limitCents),
      totalSpentCents: items.fold<int>(0, (s, i) => s + i.spentCents),
      items: List<MonthlyBudgetReportItem>.unmodifiable(items),
    );
  }

  static AlignedBalanceSheetReport buildAlignedBalanceSheetReport({
    required List<AccountModel> accounts,
    required List<JournalEntryModel> entries,
    required List<PostingModel> postings,
    required List<DebtModel> debts,
    List<SettlementAllocationModel>? allocations,
    required AvailableToSpendBreakdown breakdown,
  }) {
    final activePayablesCents = calculateTotalPayables(
      debts,
      accounts: accounts,
      entries: entries,
      postings: postings,
      allocations: allocations,
    );
    final netFinancialPositionCents = calculateNetPosition(
      accounts: accounts,
      postings: postings,
      entries: entries,
      debts: debts,
      allocations: allocations ?? const [],
    );
    return AlignedBalanceSheetReport(
      planningPeriodEndIso: breakdown.periodEndIso,
      liquidCashCents: breakdown.liquidCashCents,
      vaultSavingsCents: breakdown.vaultSavingsCents,
      receivablesCents: breakdown.receivablesCents,
      prepaidCardCreditCents: breakdown.prepaidCardCreditCents,
      shortTermCreditOwedCents: breakdown.shortTermCreditOwedCents,
      activePayablesCents: activePayablesCents,
      duePayablesCents: breakdown.duePayablesCents,
      netFinancialPositionCents: netFinancialPositionCents,
    );
  }
}
