import '../../core/date/shared_date.dart';

/// Pure domain models for Finance SMS Drafts (Stage 5).
///
/// Invariants:
/// - Zero dependencies on Flutter widgets or Drift SQLite.
/// - SMS messages NEVER post automatically to the double-entry ledger.
/// - Amounts are strictly stored as integer minor units (1 ETB = 100 cents).
/// - `rawSmsText` is local-only and excluded from portable backups/exports.

enum SmsProvider {
  cbe('cbe', 'CBE'),
  telebirr('telebirr', 'Telebirr'),
  boa('boa', 'Bank of Abyssinia (BOA)'),
  unknown('unknown', 'Unknown');

  final String dbValue;
  final String displayName;
  const SmsProvider(this.dbValue, this.displayName);

  static SmsProvider fromDbValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'cbe':
        return SmsProvider.cbe;
      case 'telebirr':
        return SmsProvider.telebirr;
      case 'boa':
        return SmsProvider.boa;
      default:
        return SmsProvider.unknown;
    }
  }
}

enum SmsDirection {
  incoming('incoming'),
  outgoing('outgoing'),
  uncertain('uncertain');

  final String dbValue;
  const SmsDirection(this.dbValue);

  static SmsDirection fromDbValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'incoming':
        return SmsDirection.incoming;
      case 'outgoing':
        return SmsDirection.outgoing;
      default:
        return SmsDirection.uncertain;
    }
  }
}

enum SmsSuggestedTransactionType {
  expense('expense'),
  income('income'),
  transfer('transfer'),
  unknown('unknown');

  final String dbValue;
  const SmsSuggestedTransactionType(this.dbValue);

  static SmsSuggestedTransactionType fromDbValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'expense':
        return SmsSuggestedTransactionType.expense;
      case 'income':
        return SmsSuggestedTransactionType.income;
      case 'transfer':
        return SmsSuggestedTransactionType.transfer;
      default:
        return SmsSuggestedTransactionType.unknown;
    }
  }
}

enum SmsDraftStatus {
  needsReview('needs_review'),
  approved('approved'),
  dismissed('dismissed'),
  unrecognized('unrecognized');

  final String dbValue;
  const SmsDraftStatus(this.dbValue);

  static SmsDraftStatus fromDbValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'needs_review':
        return SmsDraftStatus.needsReview;
      case 'approved':
        return SmsDraftStatus.approved;
      case 'dismissed':
        return SmsDraftStatus.dismissed;
      default:
        return SmsDraftStatus.unrecognized;
    }
  }
}

enum SmsParseConfidence {
  high('high'),
  medium('medium'),
  low('low'),
  unrecognized('unrecognized');

  final String dbValue;
  const SmsParseConfidence(this.dbValue);

  static SmsParseConfidence fromDbValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'high':
        return SmsParseConfidence.high;
      case 'medium':
        return SmsParseConfidence.medium;
      case 'low':
        return SmsParseConfidence.low;
      default:
        return SmsParseConfidence.unrecognized;
    }
  }
}

class FinanceSmsDraftModel {
  final String id;
  final SmsProvider provider;
  final String fingerprint;
  final String? transactionReference;
  final String? receiptUrl;
  final SmsSuggestedTransactionType suggestedType;
  final SmsDirection direction;
  final int principalCents;
  final int serviceFeeCents;
  final int vatCents;
  final int otherChargesCents;
  final int? totalAmountCents;
  final bool hasAmountMismatch;
  final String currencyCode;
  final String? accountHint;
  final String? counterpartyName;
  final String? counterpartyHint;
  final int? reportedBalanceCents;
  final DateTime? transactionTimestampUtc;
  final String? transactionDateIso;
  final DateTime receivedAtUtc;
  final SmsParseConfidence confidence;
  final SmsDraftStatus status;
  final bool isNonLedgerNotice;
  final String? parseNotes;
  final String? suggestedAccountId;
  final String? suggestedCategoryId;
  final String? approvedEntryId;
  final String rawSmsText;
  final DateTime createdAt;
  final DateTime updatedAt;

  FinanceSmsDraftModel({
    required this.id,
    required this.provider,
    required this.fingerprint,
    this.transactionReference,
    this.receiptUrl,
    required this.suggestedType,
    required this.direction,
    required this.principalCents,
    this.serviceFeeCents = 0,
    this.vatCents = 0,
    this.otherChargesCents = 0,
    this.totalAmountCents,
    this.hasAmountMismatch = false,
    this.currencyCode = 'ETB',
    this.accountHint,
    this.counterpartyName,
    this.counterpartyHint,
    this.reportedBalanceCents,
    DateTime? transactionTimestampUtc,
    this.transactionDateIso,
    required DateTime receivedAtUtc,
    required this.confidence,
    required this.status,
    this.isNonLedgerNotice = false,
    this.parseNotes,
    this.suggestedAccountId,
    this.suggestedCategoryId,
    this.approvedEntryId,
    required this.rawSmsText,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : transactionTimestampUtc = transactionTimestampUtc?.toUtc(),
        receivedAtUtc = receivedAtUtc.toUtc(),
        createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc(),
        updatedAt = (updatedAt ?? EthiopiaClock.nowUtc()).toUtc();

  int get totalFeesCents =>
      serviceFeeCents + vatCents + otherChargesCents;

  bool get canApprove =>
      status == SmsDraftStatus.needsReview &&
      !isNonLedgerNotice &&
      suggestedType != SmsSuggestedTransactionType.unknown &&
      principalCents > 0;

  FinanceSmsDraftModel copyWith({
    SmsDraftStatus? status,
    SmsSuggestedTransactionType? suggestedType,
    String? suggestedAccountId,
    bool clearSuggestedAccountId = false,
    String? suggestedCategoryId,
    bool clearSuggestedCategoryId = false,
    String? approvedEntryId,
    String? parseNotes,
    DateTime? updatedAt,
  }) {
    return FinanceSmsDraftModel(
      id: id,
      provider: provider,
      fingerprint: fingerprint,
      transactionReference: transactionReference,
      receiptUrl: receiptUrl,
      suggestedType: suggestedType ?? this.suggestedType,
      direction: direction,
      principalCents: principalCents,
      serviceFeeCents: serviceFeeCents,
      vatCents: vatCents,
      otherChargesCents: otherChargesCents,
      totalAmountCents: totalAmountCents,
      hasAmountMismatch: hasAmountMismatch,
      currencyCode: currencyCode,
      accountHint: accountHint,
      counterpartyName: counterpartyName,
      counterpartyHint: counterpartyHint,
      reportedBalanceCents: reportedBalanceCents,
      transactionTimestampUtc: transactionTimestampUtc,
      transactionDateIso: transactionDateIso,
      receivedAtUtc: receivedAtUtc,
      confidence: confidence,
      status: status ?? this.status,
      isNonLedgerNotice: isNonLedgerNotice,
      parseNotes: parseNotes ?? this.parseNotes,
      suggestedAccountId: clearSuggestedAccountId
          ? null
          : (suggestedAccountId ?? this.suggestedAccountId),
      suggestedCategoryId: clearSuggestedCategoryId
          ? null
          : (suggestedCategoryId ?? this.suggestedCategoryId),
      approvedEntryId: approvedEntryId ?? this.approvedEntryId,
      rawSmsText: rawSmsText,
      createdAt: createdAt,
      updatedAt: updatedAt ?? EthiopiaClock.nowUtc(),
    );
  }
}

class SmsParseOutcome {
  final bool isIgnoredNonTransactional;
  final SmsProvider? provider;
  final String? ignoreReason;
  final FinanceSmsDraftModel? draft;

  const SmsParseOutcome.draft(FinanceSmsDraftModel this.draft, {this.provider})
      : isIgnoredNonTransactional = false,
        ignoreReason = null;

  const SmsParseOutcome.ignored({
    this.provider,
    required this.ignoreReason,
  })  : isIgnoredNonTransactional = true,
        draft = null;
}

class SmsDeduplicationResult {
  final bool isDuplicate;
  final FinanceSmsDraftModel? existingDraft;
  final String? matchedBy; // 'provider_reference' | 'fingerprint'

  const SmsDeduplicationResult({
    required this.isDuplicate,
    this.existingDraft,
    this.matchedBy,
  });
}

class SmsImportBatchResult {
  final int importedCount;
  final int unrecognizedCount;
  final int duplicateCount;
  final int ignoredCount;
  final List<FinanceSmsDraftModel> importedDrafts;
  final List<String> ignoredReasons;

  const SmsImportBatchResult({
    required this.importedCount,
    required this.unrecognizedCount,
    required this.duplicateCount,
    required this.ignoredCount,
    this.importedDrafts = const <FinanceSmsDraftModel>[],
    this.ignoredReasons = const <String>[],
  });
}

enum SmsScanTrigger {
  manual('manual'),
  foregroundCatchUp('foreground_catch_up'),
  backgroundWorker('background_worker'),
  permissionGrant('permission_grant');

  final String dbValue;
  const SmsScanTrigger(this.dbValue);
}

class SmsInboxMessage {
  final String deviceMessageId;
  final String senderAddress;
  final String body;
  final DateTime receivedAtUtc;

  SmsInboxMessage({
    required this.deviceMessageId,
    required this.senderAddress,
    required this.body,
    required DateTime receivedAtUtc,
  }) : receivedAtUtc = receivedAtUtc.toUtc();
}

class SmsSenderIdentification {
  final bool isTargetFinancialMessage;
  final SmsProvider? provider;
  final String? matchedBy; // 'sender_alias' | 'canonical_sender' | 'message_body'
  final String? rejectReason;

  const SmsSenderIdentification.accepted({
    required SmsProvider this.provider,
    required String this.matchedBy,
  })  : isTargetFinancialMessage = true,
        rejectReason = null;

  const SmsSenderIdentification.rejected(String this.rejectReason)
      : isTargetFinancialMessage = false,
        provider = null,
        matchedBy = null;
}

class SmsScanCheckpointState {
  final DateTime? lastProcessedReceivedAtUtc;
  final DateTime? lastScanAttemptUtc;
  final DateTime? lastSuccessUtc;
  final bool permissionAsked;
  final bool dailyScanEnabled;
  final Map<String, SmsProvider> senderAliases;

  const SmsScanCheckpointState({
    this.lastProcessedReceivedAtUtc,
    this.lastScanAttemptUtc,
    this.lastSuccessUtc,
    this.permissionAsked = false,
    this.dailyScanEnabled = true,
    this.senderAliases = const <String, SmsProvider>{},
  });

  SmsScanCheckpointState copyWith({
    DateTime? lastProcessedReceivedAtUtc,
    bool clearLastProcessedReceivedAtUtc = false,
    DateTime? lastScanAttemptUtc,
    bool clearLastScanAttemptUtc = false,
    DateTime? lastSuccessUtc,
    bool clearLastSuccessUtc = false,
    bool? permissionAsked,
    bool? dailyScanEnabled,
    Map<String, SmsProvider>? senderAliases,
  }) {
    return SmsScanCheckpointState(
      lastProcessedReceivedAtUtc: clearLastProcessedReceivedAtUtc
          ? null
          : (lastProcessedReceivedAtUtc ?? this.lastProcessedReceivedAtUtc),
      lastScanAttemptUtc: clearLastScanAttemptUtc
          ? null
          : (lastScanAttemptUtc ?? this.lastScanAttemptUtc),
      lastSuccessUtc:
          clearLastSuccessUtc ? null : (lastSuccessUtc ?? this.lastSuccessUtc),
      permissionAsked: permissionAsked ?? this.permissionAsked,
      dailyScanEnabled: dailyScanEnabled ?? this.dailyScanEnabled,
      senderAliases: senderAliases ?? this.senderAliases,
    );
  }
}

class SmsInboxScanResult {
  final SmsScanTrigger trigger;
  final bool executed;
  final bool skippedBecauseLocked;
  final bool skippedBecausePermission;
  final bool skippedBecauseFresh;
  final int scannedMessageCount;
  final int importedCount;
  final int unrecognizedCount;
  final int duplicateCount;
  final int ignoredCount;
  final DateTime? windowStartUtc;
  final DateTime? checkpointBeforeUtc;
  final DateTime? checkpointAfterUtc;
  final String? errorMessage;

  const SmsInboxScanResult({
    required this.trigger,
    this.executed = true,
    this.skippedBecauseLocked = false,
    this.skippedBecausePermission = false,
    this.skippedBecauseFresh = false,
    this.scannedMessageCount = 0,
    this.importedCount = 0,
    this.unrecognizedCount = 0,
    this.duplicateCount = 0,
    this.ignoredCount = 0,
    this.windowStartUtc,
    this.checkpointBeforeUtc,
    this.checkpointAfterUtc,
    this.errorMessage,
  });
}
