import '../../core/date/shared_date.dart';

/// Pure domain models for Finance categories, transactions, commitments,
/// savings goals, budgets, recurring rules, and Safe Harbor breakdown.
///
/// Invariants:
/// - Zero dependencies on Flutter widgets or Drift SQLite.
/// - Amounts are strictly stored as integer minor units (1 ETB = 100 cents).

class TransactionCategoryModel {
  final String id;
  final String name;
  final String type; // 'expense', 'income'
  final String colorHex;
  final String? parentId;
  final int sortOrder;
  final bool isDefault;
  final bool isArchived;

  TransactionCategoryModel({
    required this.id,
    required this.name,
    required this.type,
    this.colorHex = '#1B4D3E',
    this.parentId,
    this.sortOrder = 0,
    this.isDefault = false,
    this.isArchived = false,
  });

  TransactionCategoryModel copyWith({
    String? name,
    String? type,
    String? colorHex,
    String? parentId,
    bool clearParentId = false,
    int? sortOrder,
    bool? isDefault,
    bool? isArchived,
  }) {
    return TransactionCategoryModel(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      colorHex: colorHex ?? this.colorHex,
      parentId: clearParentId ? null : (parentId ?? this.parentId),
      sortOrder: sortOrder ?? this.sortOrder,
      isDefault: isDefault ?? this.isDefault,
      isArchived: isArchived ?? this.isArchived,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'colorHex': colorHex,
        'parentId': parentId,
        'sortOrder': sortOrder,
        'isDefault': isDefault,
        'isArchived': isArchived,
      };

  factory TransactionCategoryModel.fromJson(Map<String, dynamic> json) =>
      TransactionCategoryModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        type: json['type']?.toString() ?? 'expense',
        colorHex: json['colorHex']?.toString() ?? '#1B4D3E',
        parentId: json['parentId']?.toString(),
        sortOrder: (json['sortOrder'] as int?) ?? 0,
        isDefault: (json['isDefault'] as bool?) ?? false,
        isArchived: (json['isArchived'] as bool?) ?? false,
      );
}

class TransactionModel {
  final String id;
  final String categoryId;
  final String categoryName;
  final int amountCents;
  final String type; // 'income', 'expense', 'transfer'
  final CalendarDate transactionDate;
  final String? note;
  final String? payee;
  final bool isSuperseded;
  final String? correctedFromId;
  final String? correctionReason;
  final String? accountId;
  final String? accountName;
  final String? destinationAccountId;
  final String? destinationAccountName;

  TransactionModel({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.amountCents,
    required this.type,
    required this.transactionDate,
    this.note,
    this.payee,
    this.isSuperseded = false,
    this.correctedFromId,
    this.correctionReason,
    this.accountId,
    this.accountName,
    this.destinationAccountId,
    this.destinationAccountName,
  });

  TransactionModel copyWith({
    bool? isSuperseded,
    String? note,
    String? categoryId,
    String? categoryName,
    int? amountCents,
    String? type,
    CalendarDate? transactionDate,
    String? payee,
    String? correctedFromId,
    String? correctionReason,
    String? accountId,
    String? accountName,
    String? destinationAccountId,
    String? destinationAccountName,
  }) {
    return TransactionModel(
      id: id,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      amountCents: amountCents ?? this.amountCents,
      type: type ?? this.type,
      transactionDate: transactionDate ?? this.transactionDate,
      note: note ?? this.note,
      payee: payee ?? this.payee,
      isSuperseded: isSuperseded ?? this.isSuperseded,
      correctedFromId: correctedFromId ?? this.correctedFromId,
      correctionReason: correctionReason ?? this.correctionReason,
      accountId: accountId ?? this.accountId,
      accountName: accountName ?? this.accountName,
      destinationAccountId: destinationAccountId ?? this.destinationAccountId,
      destinationAccountName:
          destinationAccountName ?? this.destinationAccountName,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'categoryId': categoryId,
        'categoryName': categoryName,
        'amountCents': amountCents,
        'type': type,
        'transactionDate': transactionDate.toIsoString(),
        'note': note,
        'payee': payee,
        'isSuperseded': isSuperseded,
        'correctedFromId': correctedFromId,
        'correctionReason': correctionReason,
        'accountId': accountId,
        'accountName': accountName,
        'destinationAccountId': destinationAccountId,
        'destinationAccountName': destinationAccountName,
      };

  factory TransactionModel.fromJson(Map<String, dynamic> json) =>
      TransactionModel(
        id: json['id']?.toString() ?? '',
        categoryId: json['categoryId']?.toString() ?? 'cat-other-exp',
        categoryName: json['categoryName']?.toString() ?? 'General',
        amountCents: (json['amountCents'] as int?) ?? 0,
        type: json['type']?.toString() ?? 'expense',
        transactionDate: SharedDateFormatter.parseFlexibleToCalendarDate(
          json['transactionDate']?.toString() ?? '',
        ),
        note: json['note']?.toString(),
        payee: json['payee']?.toString(),
        isSuperseded: (json['isSuperseded'] as bool?) ?? false,
        correctedFromId: json['correctedFromId']?.toString(),
        correctionReason: json['correctionReason']?.toString(),
        accountId: json['accountId']?.toString(),
        accountName: json['accountName']?.toString(),
        destinationAccountId: json['destinationAccountId']?.toString(),
        destinationAccountName: json['destinationAccountName']?.toString(),
      );
}

enum CommitmentDirection { outflow, inflow }

enum CommitmentStatus { unpaid, partial, paid, legacyUnverifiedPaid }

class CommitmentSettlementModel {
  final String id;
  final String commitmentId;
  final String entryId;
  final int amountCents;
  final CalendarDate settledDate;
  final DateTime createdAt;

  CommitmentSettlementModel({
    required this.id,
    required this.commitmentId,
    required this.entryId,
    required this.amountCents,
    required this.settledDate,
    DateTime? createdAt,
  }) : createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc();

  CommitmentSettlementModel copyWith({
    int? amountCents,
    CalendarDate? settledDate,
  }) {
    return CommitmentSettlementModel(
      id: id,
      commitmentId: commitmentId,
      entryId: entryId,
      amountCents: amountCents ?? this.amountCents,
      settledDate: settledDate ?? this.settledDate,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'commitmentId': commitmentId,
        'entryId': entryId,
        'amountCents': amountCents,
        'settledDate': settledDate.toIsoString(),
        'createdAt': EthiopiaClock.toUtcIsoString(createdAt),
      };

  factory CommitmentSettlementModel.fromJson(Map<String, dynamic> json) =>
      CommitmentSettlementModel(
        id: json['id']?.toString() ?? '',
        commitmentId: json['commitmentId']?.toString() ?? '',
        entryId: json['entryId']?.toString() ?? '',
        amountCents: (json['amountCents'] as int?) ?? 0,
        settledDate: SharedDateFormatter.parseFlexibleToCalendarDate(
          json['settledDate']?.toString() ?? '',
        ),
        createdAt: EthiopiaClock.tryParseInstantUtc(
          json['createdAt']?.toString(),
        ),
      );
}

class CommitmentModel {
  final String id;
  final String title;
  final int amountCents;
  final CalendarDate dueDate;
  final bool isPaid;
  final CommitmentDirection direction;
  final bool legacyPaidUnverified;
  final int verifiedSettledCents;
  final String? recurringRule;
  final String? linkedAccountId;
  final String? categoryId;
  final String? linkedDebtId;
  final String? settlementEntryId;
  final String? recurringRuleId;

  CommitmentModel({
    required this.id,
    required this.title,
    required this.amountCents,
    required this.dueDate,
    this.isPaid = false,
    this.direction = CommitmentDirection.outflow,
    this.legacyPaidUnverified = false,
    this.verifiedSettledCents = 0,
    this.recurringRule = 'monthly',
    this.linkedAccountId,
    this.categoryId,
    this.linkedDebtId,
    this.settlementEntryId,
    this.recurringRuleId,
  });

  bool get isInflow => direction == CommitmentDirection.inflow;
  bool get isOutflow => direction == CommitmentDirection.outflow;

  CommitmentStatus get status {
    if (legacyPaidUnverified) return CommitmentStatus.legacyUnverifiedPaid;
    if (isPaid || (amountCents > 0 && verifiedSettledCents >= amountCents)) {
      return CommitmentStatus.paid;
    }
    if (verifiedSettledCents > 0) return CommitmentStatus.partial;
    return CommitmentStatus.unpaid;
  }

  int get remainingCents {
    if (legacyPaidUnverified || isPaid) return 0;
    final rem = amountCents - verifiedSettledCents;
    return rem < 0 ? 0 : rem;
  }

  CommitmentModel copyWith({
    String? title,
    int? amountCents,
    CalendarDate? dueDate,
    bool? isPaid,
    CommitmentDirection? direction,
    bool? legacyPaidUnverified,
    int? verifiedSettledCents,
    String? recurringRule,
    String? linkedAccountId,
    bool clearLinkedAccountId = false,
    String? categoryId,
    bool clearCategoryId = false,
    String? linkedDebtId,
    bool clearLinkedDebtId = false,
    String? settlementEntryId,
    bool clearSettlementEntryId = false,
    String? recurringRuleId,
    bool clearRecurringRuleId = false,
  }) {
    return CommitmentModel(
      id: id,
      title: title ?? this.title,
      amountCents: amountCents ?? this.amountCents,
      dueDate: dueDate ?? this.dueDate,
      isPaid: isPaid ?? this.isPaid,
      direction: direction ?? this.direction,
      legacyPaidUnverified: legacyPaidUnverified ?? this.legacyPaidUnverified,
      verifiedSettledCents: verifiedSettledCents ?? this.verifiedSettledCents,
      recurringRule: recurringRule ?? this.recurringRule,
      linkedAccountId: clearLinkedAccountId
          ? null
          : (linkedAccountId ?? this.linkedAccountId),
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      linkedDebtId:
          clearLinkedDebtId ? null : (linkedDebtId ?? this.linkedDebtId),
      settlementEntryId: clearSettlementEntryId
          ? null
          : (settlementEntryId ?? this.settlementEntryId),
      recurringRuleId: clearRecurringRuleId
          ? null
          : (recurringRuleId ?? this.recurringRuleId),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'amountCents': amountCents,
        'dueDate': dueDate.toIsoString(),
        'isPaid': isPaid,
        'direction': direction.name,
        'legacyPaidUnverified': legacyPaidUnverified,
        'verifiedSettledCents': verifiedSettledCents,
        'recurringRule': recurringRule,
        'linkedAccountId': linkedAccountId,
        'categoryId': categoryId,
        'linkedDebtId': linkedDebtId,
        'settlementEntryId': settlementEntryId,
        'recurringRuleId': recurringRuleId,
      };

  factory CommitmentModel.fromJson(Map<String, dynamic> json) =>
      CommitmentModel(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        amountCents: (json['amountCents'] as int?) ?? 0,
        dueDate: SharedDateFormatter.parseFlexibleToCalendarDate(
          json['dueDate']?.toString() ?? '',
        ),
        isPaid: (json['isPaid'] as bool?) ?? false,
        direction: json['direction']?.toString() == 'inflow'
            ? CommitmentDirection.inflow
            : CommitmentDirection.outflow,
        legacyPaidUnverified: (json['legacyPaidUnverified'] as bool?) ?? false,
        verifiedSettledCents: (json['verifiedSettledCents'] as int?) ?? 0,
        recurringRule: json['recurringRule']?.toString(),
        linkedAccountId: json['linkedAccountId']?.toString(),
        categoryId: json['categoryId']?.toString(),
        linkedDebtId: json['linkedDebtId']?.toString(),
        settlementEntryId: json['settlementEntryId']?.toString(),
        recurringRuleId: json['recurringRuleId']?.toString(),
      );
}

enum SavingsGoalStatus { active, completed, archived }

class SavingsGoalModel {
  final String id;
  final String title;
  final int targetCents;
  final int currentAllocatedCents;
  final CalendarDate? targetDate;
  final String? linkedAccountId;
  final SavingsGoalStatus status;

  SavingsGoalModel({
    required this.id,
    required this.title,
    required this.targetCents,
    this.currentAllocatedCents = 0,
    this.targetDate,
    this.linkedAccountId,
    this.status = SavingsGoalStatus.active,
  });

  bool get isVaultLinked =>
      linkedAccountId != null && linkedAccountId!.trim().isNotEmpty;

  bool get isArchived => status == SavingsGoalStatus.archived;

  bool get isCompleted =>
      status == SavingsGoalStatus.completed ||
      (!isArchived && targetCents > 0 && currentAllocatedCents >= targetCents);

  bool get isOverfunded => currentAllocatedCents > targetCents;

  SavingsGoalModel copyWith({
    String? title,
    int? targetCents,
    int? currentAllocatedCents,
    CalendarDate? targetDate,
    bool clearTargetDate = false,
    String? linkedAccountId,
    bool clearLinkedAccountId = false,
    SavingsGoalStatus? status,
  }) {
    return SavingsGoalModel(
      id: id,
      title: title ?? this.title,
      targetCents: targetCents ?? this.targetCents,
      currentAllocatedCents:
          currentAllocatedCents ?? this.currentAllocatedCents,
      targetDate: clearTargetDate ? null : (targetDate ?? this.targetDate),
      linkedAccountId: clearLinkedAccountId
          ? null
          : (linkedAccountId ?? this.linkedAccountId),
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'targetCents': targetCents,
        'currentAllocatedCents': currentAllocatedCents,
        'targetDate': targetDate?.toIsoString(),
        'linkedAccountId': linkedAccountId,
        'status': status.name,
      };

  factory SavingsGoalModel.fromJson(Map<String, dynamic> json) =>
      SavingsGoalModel(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        targetCents: (json['targetCents'] as int?) ?? 0,
        currentAllocatedCents: (json['currentAllocatedCents'] as int?) ?? 0,
        targetDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
          json['targetDate']?.toString(),
        ),
        linkedAccountId: json['linkedAccountId']?.toString(),
        status: SavingsGoalStatus.values.firstWhere(
          (e) => e.name == json['status']?.toString(),
          orElse: () => SavingsGoalStatus.active,
        ),
      );
}

class BudgetModel {
  final String id;
  final String categoryId;
  final String monthIso; // YYYY-MM
  final int limitCents;
  final bool rolloverEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  BudgetModel({
    required this.id,
    required this.categoryId,
    required this.monthIso,
    required this.limitCents,
    this.rolloverEnabled = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc(),
        updatedAt = (updatedAt ?? EthiopiaClock.nowUtc()).toUtc();

  BudgetModel copyWith({
    String? categoryId,
    String? monthIso,
    int? limitCents,
    bool? rolloverEnabled,
    DateTime? updatedAt,
  }) {
    return BudgetModel(
      id: id,
      categoryId: categoryId ?? this.categoryId,
      monthIso: monthIso ?? this.monthIso,
      limitCents: limitCents ?? this.limitCents,
      rolloverEnabled: rolloverEnabled ?? this.rolloverEnabled,
      createdAt: createdAt,
      updatedAt: updatedAt ?? EthiopiaClock.nowUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'categoryId': categoryId,
        'monthIso': monthIso,
        'limitCents': limitCents,
        'rolloverEnabled': rolloverEnabled,
        'createdAt': EthiopiaClock.toUtcIsoString(createdAt),
        'updatedAt': EthiopiaClock.toUtcIsoString(updatedAt),
      };

  factory BudgetModel.fromJson(Map<String, dynamic> json) => BudgetModel(
        id: json['id']?.toString() ?? '',
        categoryId: json['categoryId']?.toString() ?? '',
        monthIso: json['monthIso']?.toString() ?? '',
        limitCents: (json['limitCents'] as int?) ?? 0,
        rolloverEnabled: (json['rolloverEnabled'] as bool?) ?? false,
        createdAt:
            EthiopiaClock.tryParseInstantUtc(json['createdAt']?.toString()),
        updatedAt:
            EthiopiaClock.tryParseInstantUtc(json['updatedAt']?.toString()),
      );
}

enum RecurringRuleType { expense, income, transfer, commitment }

enum RecurrenceFrequency { weekly, biweekly, monthly, quarterly, yearly }

class RecurringRuleModel {
  final String id;
  final String title;
  final RecurringRuleType ruleType;
  final int amountCents;
  final RecurrenceFrequency frequency;
  final int interval;
  final CalendarDate startDate;
  final CalendarDate nextOccurrenceDate;
  final CalendarDate? endDate;
  final String? accountId;
  final String? destinationAccountId;
  final String? categoryId;
  final String? linkedDebtId;
  final bool isActive;
  final bool autoPost;
  final DateTime createdAt;

  RecurringRuleModel({
    required this.id,
    required this.title,
    required this.ruleType,
    required this.amountCents,
    required this.frequency,
    this.interval = 1,
    required this.startDate,
    required this.nextOccurrenceDate,
    this.endDate,
    this.accountId,
    this.destinationAccountId,
    this.categoryId,
    this.linkedDebtId,
    this.isActive = true,
    this.autoPost = false,
    DateTime? createdAt,
  }) : createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc();

  RecurringRuleModel copyWith({
    String? title,
    RecurringRuleType? ruleType,
    int? amountCents,
    RecurrenceFrequency? frequency,
    int? interval,
    CalendarDate? startDate,
    CalendarDate? nextOccurrenceDate,
    CalendarDate? endDate,
    bool clearEndDate = false,
    String? accountId,
    bool clearAccountId = false,
    String? destinationAccountId,
    bool clearDestinationAccountId = false,
    String? categoryId,
    bool clearCategoryId = false,
    String? linkedDebtId,
    bool clearLinkedDebtId = false,
    bool? isActive,
    bool? autoPost,
  }) {
    return RecurringRuleModel(
      id: id,
      title: title ?? this.title,
      ruleType: ruleType ?? this.ruleType,
      amountCents: amountCents ?? this.amountCents,
      frequency: frequency ?? this.frequency,
      interval: interval ?? this.interval,
      startDate: startDate ?? this.startDate,
      nextOccurrenceDate: nextOccurrenceDate ?? this.nextOccurrenceDate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      accountId: clearAccountId ? null : (accountId ?? this.accountId),
      destinationAccountId: clearDestinationAccountId
          ? null
          : (destinationAccountId ?? this.destinationAccountId),
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      linkedDebtId:
          clearLinkedDebtId ? null : (linkedDebtId ?? this.linkedDebtId),
      isActive: isActive ?? this.isActive,
      autoPost: autoPost ?? this.autoPost,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'ruleType': ruleType.name,
        'amountCents': amountCents,
        'frequency': frequency.name,
        'interval': interval,
        'startDate': startDate.toIsoString(),
        'nextOccurrenceDate': nextOccurrenceDate.toIsoString(),
        'endDate': endDate?.toIsoString(),
        'accountId': accountId,
        'destinationAccountId': destinationAccountId,
        'categoryId': categoryId,
        'linkedDebtId': linkedDebtId,
        'isActive': isActive,
        'autoPost': autoPost,
        'createdAt': EthiopiaClock.toUtcIsoString(createdAt),
      };

  factory RecurringRuleModel.fromJson(Map<String, dynamic> json) =>
      RecurringRuleModel(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        ruleType: RecurringRuleType.values.firstWhere(
          (e) => e.name == json['ruleType'],
          orElse: () => RecurringRuleType.commitment,
        ),
        amountCents: (json['amountCents'] as int?) ?? 0,
        frequency: RecurrenceFrequency.values.firstWhere(
          (e) => e.name == json['frequency'],
          orElse: () => RecurrenceFrequency.monthly,
        ),
        interval: (json['interval'] as int?) ?? 1,
        startDate: SharedDateFormatter.parseFlexibleToCalendarDate(
          json['startDate']?.toString() ?? '',
        ),
        nextOccurrenceDate: SharedDateFormatter.parseFlexibleToCalendarDate(
          json['nextOccurrenceDate']?.toString() ?? '',
        ),
        endDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
          json['endDate']?.toString(),
        ),
        accountId: json['accountId']?.toString(),
        destinationAccountId: json['destinationAccountId']?.toString(),
        categoryId: json['categoryId']?.toString(),
        linkedDebtId: json['linkedDebtId']?.toString(),
        isActive: (json['isActive'] as bool?) ?? true,
        autoPost: (json['autoPost'] as bool?) ?? false,
        createdAt:
            EthiopiaClock.tryParseInstantUtc(json['createdAt']?.toString()),
      );
}

class AvailableToSpendBreakdown {
  final int liquidCashCents;
  final int prepaidCardCreditCents;
  final int shortTermCreditOwedCents;
  final int duePayablesCents;
  final int dueNonDebtCommitmentsCents;
  final int virtualSavingsReservedCents;
  final int vaultSavingsCents;
  final int receivablesCents;
  final int availableToSpendCents;
  final String periodEndIso;
  final int nonEtbAccountCount;
  final int unverifiedAccountCount;
  final int unverifiedLegacyPaidCount;
  final int excludedNonEtbEntryCount;
  final int currencyReviewEntryCount;

  const AvailableToSpendBreakdown({
    required this.liquidCashCents,
    this.prepaidCardCreditCents = 0,
    required this.shortTermCreditOwedCents,
    required this.duePayablesCents,
    required this.dueNonDebtCommitmentsCents,
    required this.virtualSavingsReservedCents,
    required this.vaultSavingsCents,
    required this.receivablesCents,
    required this.availableToSpendCents,
    required this.periodEndIso,
    this.nonEtbAccountCount = 0,
    this.unverifiedAccountCount = 0,
    this.unverifiedLegacyPaidCount = 0,
    this.excludedNonEtbEntryCount = 0,
    this.currencyReviewEntryCount = 0,
  });

  int get totalDueObligationsCents =>
      shortTermCreditOwedCents + duePayablesCents + dueNonDebtCommitmentsCents;

  bool get isInShortfall => availableToSpendCents < 0;

  Map<String, dynamic> toJson() => {
        'liquidCashCents': liquidCashCents,
        'prepaidCardCreditCents': prepaidCardCreditCents,
        'shortTermCreditOwedCents': shortTermCreditOwedCents,
        'duePayablesCents': duePayablesCents,
        'dueNonDebtCommitmentsCents': dueNonDebtCommitmentsCents,
        'virtualSavingsReservedCents': virtualSavingsReservedCents,
        'vaultSavingsCents': vaultSavingsCents,
        'receivablesCents': receivablesCents,
        'availableToSpendCents': availableToSpendCents,
        'periodEndIso': periodEndIso,
        'nonEtbAccountCount': nonEtbAccountCount,
        'unverifiedAccountCount': unverifiedAccountCount,
        'unverifiedLegacyPaidCount': unverifiedLegacyPaidCount,
        'excludedNonEtbEntryCount': excludedNonEtbEntryCount,
        'currencyReviewEntryCount': currencyReviewEntryCount,
      };
}
