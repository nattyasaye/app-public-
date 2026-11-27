import 'package:flutter/material.dart';

import '../../../application/finance/finance_controller.dart';
import '../../../core/date/shared_date.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/finance/finance_contracts.dart';
import '../../widgets/shared_ui_widgets.dart';
import 'finance_formatters.dart';

enum _SmsDraftFilter {
  needsReview('Needs Review'),
  unrecognized('Unrecognized'),
  approved('Approved'),
  dismissed('Dismissed'),
  all('All');

  final String label;
  const _SmsDraftFilter(this.label);
}

class _DraftEditState {
  SmsSuggestedTransactionType? finalType;
  String? accountId;
  String? destinationAccountId;
  String? categoryId;
  String feeCategoryId;
  CalendarDate occurrenceDate;
  String description;
  String payee;

  _DraftEditState({
    required this.finalType,
    required this.accountId,
    required this.destinationAccountId,
    required this.categoryId,
    required this.feeCategoryId,
    required this.occurrenceDate,
    required this.description,
    required this.payee,
  });
}

/// Stage 5 Financial SMS Draft Review & Import Sheet.
///
/// Enforces explicit user review and approval before creating any ledger entry.
class FinanceSmsDraftsSheet extends StatefulWidget {
  final FinanceController controller;

  const FinanceSmsDraftsSheet({
    super.key,
    required this.controller,
  });

  static Future<void> show(
    BuildContext context, {
    required FinanceController controller,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FinanceSmsDraftsSheet(controller: controller),
    );
  }

  @override
  State<FinanceSmsDraftsSheet> createState() => _FinanceSmsDraftsSheetState();
}

class _FinanceSmsDraftsSheetState extends State<FinanceSmsDraftsSheet> {
  final TextEditingController _pasteCtrl = TextEditingController();
  _SmsDraftFilter _filter = _SmsDraftFilter.needsReview;
  SmsProvider? _providerHint;
  SmsImportBatchResult? _lastImportResult;
  String? _globalError;
  final Map<String, String> _draftErrors = {};
  final Set<String> _expandedRawIds = <String>{};
  final Map<String, _DraftEditState> _editMap = {};
  bool _isBusy = false;

  @override
  void dispose() {
    _pasteCtrl.dispose();
    super.dispose();
  }

  List<String> _splitBatchMessages(String raw) {
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (normalized.isEmpty) return const [];
    return normalized
        .split(RegExp(r'\n\s*---+\s*\n|\n\s*\n+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  _DraftEditState _editStateFor(
    FinanceSmsDraftModel draft, {
    required List<AccountModel> allAccounts,
    required List<AccountModel> spendableAccounts,
    required List<AccountModel> transferableAccounts,
    required List<TransactionCategoryModel> categories,
  }) {
    final existing = _editMap[draft.id];
    if (existing != null) return existing;

    final SmsSuggestedTransactionType? finalType =
        (draft.suggestedType == SmsSuggestedTransactionType.expense ||
                draft.suggestedType == SmsSuggestedTransactionType.income ||
                draft.suggestedType == SmsSuggestedTransactionType.transfer)
            ? draft.suggestedType
            : null;

    final pool = finalType == SmsSuggestedTransactionType.transfer
        ? transferableAccounts
        : spendableAccounts;

    final suggestedAcc = draft.suggestedAccountId != null &&
            pool.any((a) => a.id == draft.suggestedAccountId)
        ? draft.suggestedAccountId
        : (pool.isNotEmpty ? pool.first.id : null);

    final destSuggestion = FinanceSmsParsers.suggestTransferDestinationAccount(
          draft.copyWith(suggestedAccountId: suggestedAcc),
          allAccounts,
        ) ??
        transferableAccounts
            .where((a) => a.id != suggestedAcc)
            .firstOrNull
            ?.id;

    final catType = finalType == SmsSuggestedTransactionType.income
        ? 'income'
        : 'expense';
    final catPool = categories
        .where((c) => !c.isArchived && c.type == catType)
        .toList(growable: false);
    final suggestedCat = draft.suggestedCategoryId != null &&
            catPool.any((c) => c.id == draft.suggestedCategoryId)
        ? draft.suggestedCategoryId
        : (catPool.isNotEmpty
            ? catPool.first.id
            : (catType == 'income' ? 'cat-other-inc' : 'cat-other-exp'));

    final state = _DraftEditState(
      finalType: finalType,
      accountId: suggestedAcc,
      destinationAccountId: destSuggestion,
      categoryId: suggestedCat,
      feeCategoryId: SystemControlAccounts.feeCategoryId,
      occurrenceDate: FinanceSmsParsers.resolveDefaultDraftOccurrenceDate(draft),
      description: FinanceSmsParsers.buildDefaultDraftDescription(draft),
      payee: draft.counterpartyName ?? '',
    );
    _editMap[draft.id] = state;
    return state;
  }

  DaywellStatusTone _statusTone(SmsDraftStatus status) {
    switch (status) {
      case SmsDraftStatus.needsReview:
        return DaywellStatusTone.warning;
      case SmsDraftStatus.approved:
        return DaywellStatusTone.success;
      case SmsDraftStatus.dismissed:
        return DaywellStatusTone.neutral;
      case SmsDraftStatus.unrecognized:
        return DaywellStatusTone.info;
    }
  }

  String _statusLabel(SmsDraftStatus status) {
    switch (status) {
      case SmsDraftStatus.needsReview:
        return 'Needs Review';
      case SmsDraftStatus.approved:
        return 'Approved';
      case SmsDraftStatus.dismissed:
        return 'Dismissed';
      case SmsDraftStatus.unrecognized:
        return 'Unrecognized / Notice';
    }
  }

  DaywellStatusTone _directionTone(SmsDirection dir) {
    switch (dir) {
      case SmsDirection.incoming:
        return DaywellStatusTone.income;
      case SmsDirection.outgoing:
        return DaywellStatusTone.expense;
      case SmsDirection.uncertain:
        return DaywellStatusTone.neutral;
    }
  }

  String _directionLabel(SmsDirection dir) {
    switch (dir) {
      case SmsDirection.incoming:
        return 'Incoming';
      case SmsDirection.outgoing:
        return 'Outgoing';
      case SmsDirection.uncertain:
        return 'Uncertain';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        final semantic = context.daywellColors;
        final textTheme = Theme.of(context).textTheme;

        final activeEtbAccounts = state.accounts
            .where((a) => DoubleEntryEngine.isActiveVerifiedEtbAccount(a))
            .toList(growable: false);
        final spendableAccounts = activeEtbAccounts
            .where(
              (a) =>
                  (a.type == AccountType.asset &&
                      !a.subType.isSavingsVault &&
                      a.subType != AccountSubType.receivable) ||
                  (a.type == AccountType.liability &&
                      a.subType == AccountSubType.creditCard),
            )
            .toList(growable: false);
        final transferableAccounts = activeEtbAccounts
            .where(
              (a) =>
                  (a.type == AccountType.asset &&
                      a.subType != AccountSubType.receivable) ||
                  (a.type == AccountType.liability &&
                      a.subType == AccountSubType.creditCard),
            )
            .toList(growable: false);

        final drafts = state.smsDrafts;
        final needsReviewCount =
            drafts.where((d) => d.status == SmsDraftStatus.needsReview).length;
        final unrecognizedCount =
            drafts.where((d) => d.status == SmsDraftStatus.unrecognized).length;
        final approvedCount =
            drafts.where((d) => d.status == SmsDraftStatus.approved).length;
        final dismissedCount =
            drafts.where((d) => d.status == SmsDraftStatus.dismissed).length;

        final filteredDrafts = switch (_filter) {
          _SmsDraftFilter.needsReview => drafts
              .where((d) => d.status == SmsDraftStatus.needsReview)
              .toList(growable: false),
          _SmsDraftFilter.unrecognized => drafts
              .where((d) => d.status == SmsDraftStatus.unrecognized)
              .toList(growable: false),
          _SmsDraftFilter.approved => drafts
              .where((d) => d.status == SmsDraftStatus.approved)
              .toList(growable: false),
          _SmsDraftFilter.dismissed => drafts
              .where((d) => d.status == SmsDraftStatus.dismissed)
              .toList(growable: false),
          _SmsDraftFilter.all => drafts,
        };

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.92,
          minChildSize: 0.55,
          maxChildSize: 0.96,
          builder: (sheetContext, scrollController) {
            return Padding(
              padding: EdgeInsets.only(
                left: SharedDesignTokens.spacingMd,
                right: SharedDesignTokens.spacingMd,
                top: SharedDesignTokens.spacingMd,
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom +
                    SharedDesignTokens.spacingMd,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Financial SMS Drafts',
                              style: textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'CBE · Telebirr · Bank of Abyssinia (BOA)',
                              style: textTheme.bodySmall?.copyWith(
                                color: semantic.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DaywellIconButton(
                        icon: Icons.close,
                        tooltip: 'Close SMS drafts',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingSm),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        const DaywellStatusBanner(
                          tone: DaywellStatusTone.info,
                          title: 'Review Required Before Ledger Posting',
                          message:
                              'Imported SMS messages remain local drafts only. Balances, budgets, and reports are untouched until you explicitly tap Approve & Post.',
                        ),
                        if (_globalError != null) ...[
                          const SizedBox(height: SharedDesignTokens.spacingSm),
                          DaywellStatusBanner(
                            tone: DaywellStatusTone.error,
                            message: _globalError!,
                            onDismiss: () => setState(() => _globalError = null),
                          ),
                        ],
                        const SizedBox(height: SharedDesignTokens.spacingSm),
                        DaywellCard(
                          color: semantic.surfaceSubtle,
                          padding: const EdgeInsets.all(
                            SharedDesignTokens.spacingCompact,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              DaywellDropdownField<SmsProvider?>(
                                label: 'Provider Hint',
                                value: _providerHint,
                                items: const [
                                  DropdownMenuItem<SmsProvider?>(
                                    value: null,
                                    child: Text('Auto-detect (CBE / Telebirr / BOA)'),
                                  ),
                                  DropdownMenuItem<SmsProvider?>(
                                    value: SmsProvider.cbe,
                                    child: Text('CBE'),
                                  ),
                                  DropdownMenuItem<SmsProvider?>(
                                    value: SmsProvider.telebirr,
                                    child: Text('Telebirr'),
                                  ),
                                  DropdownMenuItem<SmsProvider?>(
                                    value: SmsProvider.boa,
                                    child: Text('Bank of Abyssinia (BOA)'),
                                  ),
                                ],
                                onChanged: (val) =>
                                    setState(() => _providerHint = val),
                              ),
                              const SizedBox(
                                height: SharedDesignTokens.spacingSm,
                              ),
                              DaywellTextField(
                                controller: _pasteCtrl,
                                label: 'Paste SMS Message(s)',
                                hintText:
                                    'Paste CBE, Telebirr, or BOA SMS text. Separate multiple messages with a blank line or ---',
                                maxLines: 4,
                                minLines: 3,
                              ),
                              const SizedBox(
                                height: SharedDesignTokens.spacingSm,
                              ),
                              DaywellButton(
                                label: 'Import as Drafts',
                                leadingIcon: Icons.sms_outlined,
                                fullWidth: true,
                                isLoading: _isBusy,
                                onPressed: _isBusy
                                    ? null
                                    : () async {
                                        final msgs =
                                            _splitBatchMessages(_pasteCtrl.text);
                                        if (msgs.isEmpty) {
                                          setState(() {
                                            _globalError =
                                                'Paste one or more CBE, Telebirr, or BOA SMS messages first.';
                                          });
                                          return;
                                        }
                                        setState(() {
                                          _isBusy = true;
                                          _globalError = null;
                                        });
                                        final res = await widget.controller
                                            .importSmsMessages(
                                          rawMessages: msgs,
                                          providerHint: _providerHint,
                                        );
                                        if (!mounted) return;
                                        setState(() {
                                          _isBusy = false;
                                          _lastImportResult = res;
                                          if (res == null) {
                                            _globalError = widget.controller
                                                    .state.errorMessage ??
                                                'Failed to import SMS messages.';
                                          } else {
                                            _pasteCtrl.clear();
                                            if (res.importedCount > 0) {
                                              _filter =
                                                  _SmsDraftFilter.needsReview;
                                            } else if (res.unrecognizedCount >
                                                0) {
                                              _filter =
                                                  _SmsDraftFilter.unrecognized;
                                            }
                                          }
                                        });
                                      },
                              ),
                              if (_lastImportResult != null) ...[
                                const SizedBox(
                                  height: SharedDesignTokens.spacingSm,
                                ),
                                DaywellStatusBanner(
                                  tone: _lastImportResult!.importedCount > 0
                                      ? DaywellStatusTone.success
                                      : DaywellStatusTone.info,
                                  message:
                                      '${_lastImportResult!.importedCount} ready for review · ${_lastImportResult!.unrecognizedCount} unrecognized/notices · ${_lastImportResult!.duplicateCount} duplicates skipped · ${_lastImportResult!.ignoredCount} non-transactional ignored.',
                                  onDismiss: () =>
                                      setState(() => _lastImportResult = null),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: SharedDesignTokens.spacingSm),
                        Wrap(
                          spacing: SharedDesignTokens.spacingSm,
                          runSpacing: SharedDesignTokens.spacingXs,
                          children: [
                            for (final tab in _SmsDraftFilter.values)
                              FilterChip(
                                label: Text(
                                  switch (tab) {
                                    _SmsDraftFilter.needsReview =>
                                      '${tab.label} ($needsReviewCount)',
                                    _SmsDraftFilter.unrecognized =>
                                      '${tab.label} ($unrecognizedCount)',
                                    _SmsDraftFilter.approved =>
                                      '${tab.label} ($approvedCount)',
                                    _SmsDraftFilter.dismissed =>
                                      '${tab.label} ($dismissedCount)',
                                    _SmsDraftFilter.all =>
                                      '${tab.label} (${drafts.length})',
                                  },
                                ),
                                selected: _filter == tab,
                                onSelected: (_) =>
                                    setState(() => _filter = tab),
                              ),
                          ],
                        ),
                        const SizedBox(height: SharedDesignTokens.spacingSm),
                        if (filteredDrafts.isEmpty)
                          const DaywellEmptyState(
                            icon: Icons.mark_email_read_outlined,
                            message: 'No SMS drafts in this view',
                            subtitle:
                                'Paste a CBE, Telebirr, or BOA SMS above to parse and review before posting.',
                          )
                        else
                          for (final draft in filteredDrafts) ...[
                            _buildDraftCard(
                              context,
                              draft: draft,
                              allAccounts: state.accounts,
                              spendableAccounts: spendableAccounts,
                              transferableAccounts: transferableAccounts,
                              categories: state.categories,
                            ),
                            const SizedBox(
                              height: SharedDesignTokens.spacingSm,
                            ),
                          ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDraftCard(
    BuildContext context, {
    required FinanceSmsDraftModel draft,
    required List<AccountModel> allAccounts,
    required List<AccountModel> spendableAccounts,
    required List<AccountModel> transferableAccounts,
    required List<TransactionCategoryModel> categories,
  }) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final feesCents = draft.totalFeesCents;
    final isRawExpanded = _expandedRawIds.contains(draft.id);
    final edit = _editStateFor(
      draft,
      allAccounts: allAccounts,
      spendableAccounts: spendableAccounts,
      transferableAccounts: transferableAccounts,
      categories: categories,
    );
    final pool = edit.finalType == SmsSuggestedTransactionType.transfer
        ? transferableAccounts
        : spendableAccounts;
    final catType = edit.finalType == SmsSuggestedTransactionType.income
        ? 'income'
        : 'expense';
    final categoryItems =
        FinanceUiFormatters.buildCategoryDropdownItemsWithPreserved(
      categories,
      type: catType,
      preserveCategoryId: edit.categoryId,
    );
    final feeCategoryItems = FinanceUiFormatters.buildFeeCategoryDropdownItems(
      categories,
      preserveCategoryId: edit.feeCategoryId,
    );
    final draftError = _draftErrors[draft.id];

    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: SharedDesignTokens.spacingXs,
            runSpacing: SharedDesignTokens.spacingXs,
            children: [
              DaywellStatusBadge(
                label: draft.provider.displayName,
                tone: DaywellStatusTone.info,
                showIcon: false,
              ),
              DaywellStatusBadge(
                label: _directionLabel(draft.direction),
                tone: _directionTone(draft.direction),
              ),
              DaywellStatusBadge(
                label: _statusLabel(draft.status),
                tone: _statusTone(draft.status),
              ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          Container(
            padding: const EdgeInsets.all(SharedDesignTokens.spacingSm),
            decoration: BoxDecoration(
              color: semantic.surfaceSubtle,
              borderRadius:
                  BorderRadius.circular(SharedDesignTokens.radiusSm),
              border: Border.all(color: semantic.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Principal',
                      style: textTheme.bodySmall
                          ?.copyWith(color: semantic.textSecondary),
                    ),
                    Text(
                      FinanceUiFormatters.formatEtbCents(draft.principalCents),
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (feesCents > 0) ...[
                  const SizedBox(height: SharedDesignTokens.spacingXs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Fees & Charges',
                        style: textTheme.bodySmall
                            ?.copyWith(color: semantic.textSecondary),
                      ),
                      Text(
                        FinanceUiFormatters.formatEtbCents(feesCents),
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
                if (draft.totalAmountCents != null) ...[
                  const SizedBox(height: SharedDesignTokens.spacingXs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Reported',
                        style: textTheme.bodySmall
                            ?.copyWith(color: semantic.textSecondary),
                      ),
                      Text(
                        FinanceUiFormatters.formatEtbCents(
                          draft.totalAmountCents!,
                        ),
                        style: textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
                if (draft.reportedBalanceCents != null) ...[
                  const SizedBox(height: SharedDesignTokens.spacingXs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Reported Balance',
                        style: textTheme.bodySmall
                            ?.copyWith(color: semantic.textSecondary),
                      ),
                      Text(
                        FinanceUiFormatters.formatEtbCents(
                          draft.reportedBalanceCents!,
                        ),
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (draft.counterpartyName != null ||
              draft.accountHint != null ||
              draft.transactionReference != null ||
              draft.receiptUrl != null) ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            if (draft.counterpartyName != null)
              Text(
                'Counterparty: ${draft.counterpartyName}${draft.counterpartyHint != null ? ' (${draft.counterpartyHint})' : ''}',
                style: textTheme.bodySmall,
              ),
            if (draft.accountHint != null)
              Text(
                'Account hint: ${draft.accountHint}',
                style:
                    textTheme.bodySmall?.copyWith(color: semantic.textSecondary),
              ),
            if (draft.transactionReference != null)
              Text(
                'Reference: ${draft.transactionReference}',
                style:
                    textTheme.bodySmall?.copyWith(color: semantic.textSecondary),
              ),
            if (draft.receiptUrl != null)
              Text(
                'Receipt URL (offline ref): ${draft.receiptUrl}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    textTheme.bodySmall?.copyWith(color: semantic.textSecondary),
              ),
          ],
          if (draft.hasAmountMismatch) ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            DaywellStatusBanner(
              tone: DaywellStatusTone.warning,
              title: 'Total Mismatch Detected',
              message: draft.parseNotes ??
                  'Principal + fees differs from the SMS reported total. Verify before approving.',
            ),
          ] else if ((draft.isNonLedgerNotice ||
                  draft.status == SmsDraftStatus.unrecognized ||
                  draft.confidence == SmsParseConfidence.low ||
                  draft.direction == SmsDirection.uncertain) &&
              draft.parseNotes != null) ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            DaywellStatusBanner(
              tone: draft.isNonLedgerNotice
                  ? DaywellStatusTone.info
                  : DaywellStatusTone.warning,
              message: draft.parseNotes!,
            ),
          ],
          const SizedBox(height: SharedDesignTokens.spacingXs),
          Align(
            alignment: Alignment.centerLeft,
            child: DaywellButton(
              label: isRawExpanded
                  ? 'Hide local raw SMS text'
                  : 'View local raw SMS text',
              variant: DaywellButtonVariant.text,
              size: DaywellButtonSize.compact,
              onPressed: () {
                setState(() {
                  if (isRawExpanded) {
                    _expandedRawIds.remove(draft.id);
                  } else {
                    _expandedRawIds.add(draft.id);
                  }
                });
              },
            ),
          ),
          if (isRawExpanded)
            Container(
              padding: const EdgeInsets.all(SharedDesignTokens.spacingSm),
              decoration: BoxDecoration(
                color: semantic.surfaceSubtle,
                borderRadius:
                    BorderRadius.circular(SharedDesignTokens.radiusSm),
                border: Border.all(color: semantic.border),
              ),
              child: Text(
                draft.rawSmsText,
                style: textTheme.bodySmall?.copyWith(
                  color: semantic.textSecondary,
                ),
              ),
            ),
          if (draft.status == SmsDraftStatus.needsReview &&
              !draft.isNonLedgerNotice) ...[
            const Divider(height: SharedDesignTokens.spacingMd),
            if (draftError != null) ...[
              DaywellStatusBanner(
                tone: DaywellStatusTone.error,
                message: draftError,
                onDismiss: () => setState(() => _draftErrors.remove(draft.id)),
              ),
              const SizedBox(height: SharedDesignTokens.spacingSm),
            ],
            DaywellDropdownField<SmsSuggestedTransactionType>(
              label: 'Post As',
              value: edit.finalType,
              hintText: 'Select Expense, Income, or Transfer',
              items: const [
                DropdownMenuItem(
                  value: SmsSuggestedTransactionType.expense,
                  child: Text('Expense'),
                ),
                DropdownMenuItem(
                  value: SmsSuggestedTransactionType.income,
                  child: Text('Income'),
                ),
                DropdownMenuItem(
                  value: SmsSuggestedTransactionType.transfer,
                  child: Text('Transfer'),
                ),
              ],
              onChanged: (nextType) {
                if (nextType == null) return;
                final nextPool = nextType == SmsSuggestedTransactionType.transfer
                    ? transferableAccounts
                    : spendableAccounts;
                final nextAccountId =
                    nextPool.any((a) => a.id == edit.accountId)
                        ? edit.accountId
                        : nextPool.firstOrNull?.id;
                final nextCatType =
                    nextType == SmsSuggestedTransactionType.income
                        ? 'income'
                        : 'expense';
                final nextCatPool = categories
                    .where((c) => !c.isArchived && c.type == nextCatType)
                    .toList(growable: false);
                final nextCatId = nextCatPool.firstOrNull?.id ??
                    (nextCatType == 'income'
                        ? 'cat-other-inc'
                        : 'cat-other-exp');
                setState(() {
                  edit.finalType = nextType;
                  edit.accountId = nextAccountId;
                  edit.categoryId = nextCatId;
                  if (nextType == SmsSuggestedTransactionType.transfer) {
                    edit.destinationAccountId =
                        FinanceSmsParsers.suggestTransferDestinationAccount(
                              draft.copyWith(suggestedAccountId: nextAccountId),
                              allAccounts,
                            ) ??
                            transferableAccounts
                                .where((a) => a.id != nextAccountId)
                                .firstOrNull
                                ?.id;
                  }
                });
              },
            ),
            const SizedBox(height: SharedDesignTokens.spacingSm),
            DaywellDropdownField<String>(
              label: edit.finalType == SmsSuggestedTransactionType.transfer
                  ? 'From ETB Account'
                  : (edit.finalType == SmsSuggestedTransactionType.income
                      ? 'Deposit ETB Account'
                      : 'Paid ETB Account'),
              value: pool.any((a) => a.id == edit.accountId)
                  ? edit.accountId
                  : null,
              items: [
                for (final acc in pool)
                  DropdownMenuItem(
                    value: acc.id,
                    child: Text(acc.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (val) => setState(() => edit.accountId = val),
            ),
            const SizedBox(height: SharedDesignTokens.spacingSm),
            if (edit.finalType == SmsSuggestedTransactionType.transfer) ...[
              DaywellDropdownField<String>(
                label: 'To ETB Account',
                value: transferableAccounts
                        .where((a) => a.id != edit.accountId)
                        .any((a) => a.id == edit.destinationAccountId)
                    ? edit.destinationAccountId
                    : null,
                items: [
                  for (final acc in transferableAccounts
                      .where((a) => a.id != edit.accountId))
                    DropdownMenuItem(
                      value: acc.id,
                      child: Text(acc.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (val) =>
                    setState(() => edit.destinationAccountId = val),
              ),
              const SizedBox(height: SharedDesignTokens.spacingSm),
            ] else ...[
              DaywellDropdownField<String>(
                label: 'Category',
                value: categoryItems.any((i) => i.value == edit.categoryId)
                    ? edit.categoryId
                    : null,
                items: categoryItems,
                onChanged: (val) => setState(() => edit.categoryId = val),
              ),
              const SizedBox(height: SharedDesignTokens.spacingSm),
            ],
            if (feesCents > 0) ...[
              DaywellDropdownField<String>(
                label: 'Fee Category',
                value: feeCategoryItems.any((i) => i.value == edit.feeCategoryId)
                    ? edit.feeCategoryId
                    : null,
                items: feeCategoryItems,
                onChanged: (val) {
                  if (val != null) setState(() => edit.feeCategoryId = val);
                },
              ),
              const SizedBox(height: SharedDesignTokens.spacingSm),
            ],
            DaywellTextField(
              initialValue: edit.description,
              label: 'Description',
              onChanged: (val) => edit.description = val,
            ),
            if (edit.finalType != SmsSuggestedTransactionType.transfer) ...[
              const SizedBox(height: SharedDesignTokens.spacingSm),
              DaywellTextField(
                initialValue: edit.payee,
                label: 'Payee / Counterparty (optional)',
                onChanged: (val) => edit.payee = val,
              ),
            ],
            const SizedBox(height: SharedDesignTokens.spacingSm),
            Wrap(
              spacing: SharedDesignTokens.spacingSm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Date: ${SharedDateFormatter.formatDual(edit.occurrenceDate, useAmharic: false)}',
                  style: textTheme.bodySmall
                      ?.copyWith(color: semantic.textSecondary),
                ),
                DaywellButton(
                  label: 'Pick Date',
                  variant: DaywellButtonVariant.text,
                  size: DaywellButtonSize.compact,
                  onPressed: () async {
                    final picked = await FinanceUiFormatters.pickCalendarDate(
                      context,
                      initialDate: edit.occurrenceDate,
                    );
                    if (picked != null && mounted) {
                      setState(() => edit.occurrenceDate = picked);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: SharedDesignTokens.spacingSm),
            Row(
              children: [
                Expanded(
                  child: DaywellButton(
                    label: 'Dismiss',
                    variant: DaywellButtonVariant.outlined,
                    size: DaywellButtonSize.compact,
                    onPressed: _isBusy
                        ? null
                        : () async {
                            setState(() => _isBusy = true);
                            final dismissed = await widget.controller
                                .dismissSmsDraft(draft.id);
                            if (!mounted) return;
                            setState(() {
                              _isBusy = false;
                              if (dismissed == null) {
                                _draftErrors[draft.id] =
                                    widget.controller.state.errorMessage ??
                                        'Could not dismiss draft.';
                              }
                            });
                          },
                  ),
                ),
                const SizedBox(width: SharedDesignTokens.spacingSm),
                Expanded(
                  child: DaywellButton(
                    label: 'Approve & Post',
                    variant: DaywellButtonVariant.primary,
                    size: DaywellButtonSize.compact,
                    leadingIcon: Icons.check,
                    onPressed: (_isBusy || edit.finalType == null)
                        ? null
                        : () async {
                            final selectedType = edit.finalType;
                            if (selectedType == null ||
                                selectedType ==
                                    SmsSuggestedTransactionType.unknown) {
                              setState(() {
                                _draftErrors[draft.id] =
                                    'Select Expense, Income, or Transfer after reviewing before approving.';
                              });
                              return;
                            }
                            if (edit.accountId == null ||
                                edit.accountId!.trim().isEmpty) {
                              setState(() {
                                _draftErrors[draft.id] =
                                    'Select an active ETB account before approving.';
                              });
                              return;
                            }
                            setState(() {
                              _isBusy = true;
                              _draftErrors.remove(draft.id);
                            });
                            final entry =
                                await widget.controller.approveSmsDraft(
                              draftId: draft.id,
                              finalType: selectedType,
                              accountId: edit.accountId!,
                              destinationAccountId:
                                  selectedType == SmsSuggestedTransactionType.transfer
                                      ? edit.destinationAccountId
                                      : null,
                              categoryId:
                                  selectedType == SmsSuggestedTransactionType.transfer
                                      ? null
                                      : edit.categoryId,
                              feeCategoryId:
                                  feesCents > 0 ? edit.feeCategoryId : null,
                              occurrenceDate: edit.occurrenceDate,
                              description: edit.description,
                              payee: selectedType !=
                                          SmsSuggestedTransactionType.transfer &&
                                      edit.payee.trim().isNotEmpty
                                  ? edit.payee.trim()
                                  : null,
                            );
                            if (!mounted) return;
                            setState(() {
                              _isBusy = false;
                              if (entry == null) {
                                _draftErrors[draft.id] =
                                    widget.controller.state.errorMessage ??
                                        'Failed to post SMS draft.';
                              }
                            });
                          },
                  ),
                ),
              ],
            ),
          ] else if (draft.status == SmsDraftStatus.unrecognized) ...[
            const Divider(height: SharedDesignTokens.spacingMd),
            Align(
              alignment: Alignment.centerRight,
              child: DaywellButton(
                label: 'Dismiss Notice',
                variant: DaywellButtonVariant.outlined,
                size: DaywellButtonSize.compact,
                onPressed: _isBusy
                    ? null
                    : () async {
                        setState(() => _isBusy = true);
                        await widget.controller.dismissSmsDraft(draft.id);
                        if (mounted) setState(() => _isBusy = false);
                      },
              ),
            ),
          ] else if (draft.status == SmsDraftStatus.approved &&
              draft.approvedEntryId != null) ...[
            const SizedBox(height: SharedDesignTokens.spacingXs),
            Text(
              'Posted Ledger Entry: ${draft.approvedEntryId}',
              style:
                  textTheme.bodySmall?.copyWith(color: semantic.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
