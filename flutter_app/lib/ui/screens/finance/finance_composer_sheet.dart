import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../application/finance/finance_controller.dart';
import '../../../core/date/shared_date.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/finance/double_entry_engine.dart';
import '../../widgets/shared_ui_widgets.dart';
import 'finance_formatters.dart';

enum FinanceComposerMode { expense, income, transfer, split }

/// Unified double-entry composer modal supporting Expense, Income, Transfer
/// (with optional bank fee), Split Expense (with counterparty receivable),
/// and Correct/Replace Journal Entry mode.
class FinanceComposerSheet extends StatefulWidget {
  final FinanceController controller;
  final FinanceComposerMode initialMode;
  final JournalEntryModel? editingEntry;
  final String? initialDescription;
  final String? initialAmountText;

  const FinanceComposerSheet({
    super.key,
    required this.controller,
    this.initialMode = FinanceComposerMode.expense,
    this.editingEntry,
    this.initialDescription,
    this.initialAmountText,
  });

  static Future<bool?> show(
    BuildContext context, {
    required FinanceController controller,
    FinanceComposerMode initialMode = FinanceComposerMode.expense,
    JournalEntryModel? editingEntry,
    String? initialDescription,
    String? initialAmountText,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FinanceComposerSheet(
        controller: controller,
        initialMode: initialMode,
        editingEntry: editingEntry,
        initialDescription: initialDescription,
        initialAmountText: initialAmountText,
      ),
    );
  }

  @override
  State<FinanceComposerSheet> createState() => _FinanceComposerSheetState();
}

class _FinanceComposerSheetState extends State<FinanceComposerSheet> {
  static const Uuid _uuid = Uuid();

  late FinanceComposerMode _mode;
  late CalendarDate _selectedDate;
  CalendarDate? _splitDueDate;

  String? _accountId;
  String? _destinationAccountId;
  String? _categoryId;
  String? _partyId;

  late final TextEditingController _amountCtrl;
  late final TextEditingController _feeCtrl;
  late final TextEditingController _theirShareCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _payeeCtrl;
  late final TextEditingController _noteCtrl;
  late final TextEditingController _correctionReasonCtrl;
  late final TextEditingController _newPartyCtrl;

  bool _showNewPartyField = false;
  bool _isSaving = false;
  String? _validationError;

  bool get _isEditing => widget.editingEntry != null;

  @override
  void initState() {
    super.initState();
    final state = widget.controller.state;
    _mode = widget.initialMode;
    _selectedDate = CalendarDate.today();

    _amountCtrl = TextEditingController(text: widget.initialAmountText ?? '');
    _feeCtrl = TextEditingController();
    _theirShareCtrl = TextEditingController();
    _descriptionCtrl =
        TextEditingController(text: widget.initialDescription ?? '');
    _payeeCtrl = TextEditingController();
    _noteCtrl = TextEditingController();
    _correctionReasonCtrl = TextEditingController();
    _newPartyCtrl = TextEditingController();

    final accounts = state.activeEtbUserAccounts;
    final liquidAccounts = state.liquidAssetAccounts
        .where(DoubleEntryEngine.isActiveVerifiedEtbAccount)
        .toList();
    if (accounts.isNotEmpty) {
      _accountId =
          (liquidAccounts.isNotEmpty ? liquidAccounts.first : accounts.first)
              .id;
      if (accounts.length > 1) {
        _destinationAccountId = accounts
            .firstWhere(
              (a) => a.id != _accountId,
              orElse: () => accounts.first,
            )
            .id;
      }
    }
    if (state.parties.where((p) => !p.isArchived).isNotEmpty) {
      _partyId = state.parties.where((p) => !p.isArchived).first.id;
    }

    if (_isEditing) {
      _prefillFromEditingEntry(widget.editingEntry!);
    } else {
      _syncDefaultCategory();
    }
  }

  void _prefillFromEditingEntry(JournalEntryModel entry) {
    final state = widget.controller.state;
    _selectedDate = SharedDateFormatter.parseFlexibleToCalendarDate(
      entry.occurrenceDate,
    );
    _descriptionCtrl.text = entry.description;
    final entryPostings =
        state.postings.where((p) => p.entryId == entry.id).toList();

    if (entry.entryType == EntryType.transfer) {
      _mode = FinanceComposerMode.transfer;
      PostingModel? src;
      PostingModel? dst;
      PostingModel? fee;
      for (final p in entryPostings) {
        if (p.accountId == SystemControlAccounts.expense) {
          fee = p;
        } else if (p.direction == PostingDirection.credit) {
          src = p;
        } else if (p.direction == PostingDirection.debit) {
          dst = p;
        }
      }
      _accountId = src?.accountId ?? _accountId;
      _destinationAccountId = dst?.accountId ?? _destinationAccountId;
      if (dst != null) {
        _amountCtrl.text =
            FinanceUiFormatters.formatCentsAsInput(dst.amountCents);
      }
      if (fee != null && fee.amountCents > 0) {
        _feeCtrl.text = FinanceUiFormatters.formatCentsAsInput(fee.amountCents);
      }
      _noteCtrl.text = src?.note ?? dst?.note ?? '';
      return;
    }

    final isIncome = entryPostings.any(
      (p) =>
          p.accountId == SystemControlAccounts.income &&
          p.direction == PostingDirection.credit,
    );
    if (isIncome) {
      _mode = FinanceComposerMode.income;
      final drAcc = entryPostings.firstWhere(
        (p) =>
            p.direction == PostingDirection.debit &&
            !SystemControlAccounts.isSystemControlId(p.accountId),
        orElse: () => entryPostings.first,
      );
      final crInc = entryPostings.firstWhere(
        (p) => p.accountId == SystemControlAccounts.income,
        orElse: () => entryPostings.first,
      );
      _accountId = drAcc.accountId;
      _categoryId = crInc.categoryId;
      _amountCtrl.text =
          FinanceUiFormatters.formatCentsAsInput(drAcc.amountCents);
      _noteCtrl.text = drAcc.note ?? crInc.note ?? '';
    } else {
      _mode = FinanceComposerMode.expense;
      final drExp = entryPostings.firstWhere(
        (p) => p.accountId == SystemControlAccounts.expense,
        orElse: () => entryPostings.first,
      );
      final crAcc = entryPostings.firstWhere(
        (p) =>
            p.direction == PostingDirection.credit &&
            !SystemControlAccounts.isSystemControlId(p.accountId),
        orElse: () => entryPostings.first,
      );
      _accountId = crAcc.accountId;
      _categoryId = drExp.categoryId;
      _amountCtrl.text =
          FinanceUiFormatters.formatCentsAsInput(drExp.amountCents);
      _noteCtrl.text = drExp.note ?? crAcc.note ?? '';
    }
    _syncDefaultCategory(onlyIfMissing: true);
  }

  void _syncDefaultCategory({bool onlyIfMissing = false}) {
    final catType = _mode == FinanceComposerMode.income ? 'income' : 'expense';
    final candidates = widget.controller.state.activeCategories
        .where((c) => c.type == catType)
        .toList();
    if (onlyIfMissing &&
        _categoryId != null &&
        candidates.any((c) => c.id == _categoryId)) {
      return;
    }
    if (candidates.isNotEmpty) {
      _categoryId = candidates.first.id;
    } else {
      _categoryId = null;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _feeCtrl.dispose();
    _theirShareCtrl.dispose();
    _descriptionCtrl.dispose();
    _payeeCtrl.dispose();
    _noteCtrl.dispose();
    _correctionReasonCtrl.dispose();
    _newPartyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amountCents = FinanceUiFormatters.parseEtbToCents(_amountCtrl.text);
    if (amountCents == null || amountCents <= 0) {
      setState(() => _validationError = 'Enter a valid amount greater than 0.');
      return;
    }
    if (_accountId == null) {
      setState(() => _validationError = 'Select an account.');
      return;
    }
    final description = _descriptionCtrl.text.trim().isEmpty
        ? _defaultDescription()
        : _descriptionCtrl.text.trim();

    if (_isEditing && _correctionReasonCtrl.text.trim().isEmpty) {
      setState(
        () => _validationError =
            'Provide a reason for correcting this ledger entry.',
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _validationError = null;
    });

    try {
      if (_isEditing) {
        await _submitCorrection(
          original: widget.editingEntry!,
          amountCents: amountCents,
          description: description,
        );
      } else {
        await _submitNew(amountCents: amountCents, description: description);
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _validationError = e.toString();
        });
      }
    }
  }

  String _defaultDescription() {
    switch (_mode) {
      case FinanceComposerMode.expense:
        return 'Expense';
      case FinanceComposerMode.income:
        return 'Income';
      case FinanceComposerMode.transfer:
        return 'Account Transfer';
      case FinanceComposerMode.split:
        return 'Split Expense';
    }
  }

  Future<void> _submitNew({
    required int amountCents,
    required String description,
  }) async {
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
    final payee =
        _payeeCtrl.text.trim().isEmpty ? null : _payeeCtrl.text.trim();

    switch (_mode) {
      case FinanceComposerMode.expense:
        if (_categoryId == null) {
          throw ArgumentError('Select an expense category.');
        }
        await widget.controller.recordDirectExpense(
          accountId: _accountId!,
          categoryId: _categoryId!,
          amountCents: amountCents,
          date: _selectedDate,
          description: description,
          payee: payee,
          note: note,
        );
      case FinanceComposerMode.income:
        if (_categoryId == null) {
          throw ArgumentError('Select an income category.');
        }
        await widget.controller.recordDirectIncome(
          accountId: _accountId!,
          categoryId: _categoryId!,
          amountCents: amountCents,
          date: _selectedDate,
          description: description,
          payee: payee,
          note: note,
        );
      case FinanceComposerMode.transfer:
        if (_destinationAccountId == null ||
            _destinationAccountId == _accountId) {
          throw ArgumentError('Select a different destination account.');
        }
        final feeText = _feeCtrl.text.trim();
        final feeCents =
            feeText.isEmpty ? 0 : FinanceUiFormatters.parseEtbToCents(feeText);
        if (feeCents == null || feeCents < 0) {
          throw ArgumentError('Enter a valid non-negative transfer fee.');
        }
        await widget.controller.recordTransfer(
          fromAssetAccountId: _accountId!,
          toAssetAccountId: _destinationAccountId!,
          amountCents: amountCents,
          transferFeeCents: feeCents,
          date: _selectedDate.toIsoString(),
          description: description,
          note: note,
        );
      case FinanceComposerMode.split:
        if (_categoryId == null) {
          throw ArgumentError('Select an expense category for your share.');
        }
        final theirCents =
            FinanceUiFormatters.parseEtbToCents(_theirShareCtrl.text);
        if (theirCents == null || theirCents <= 0) {
          throw ArgumentError('Enter the counterparty share amount (> 0).');
        }
        String? resolvedPartyId = _partyId;
        if (_showNewPartyField || resolvedPartyId == null) {
          final partyName = _newPartyCtrl.text.trim();
          if (partyName.isEmpty) {
            throw ArgumentError('Select or add a person/party for the split.');
          }
          resolvedPartyId = await widget.controller.ensurePartyId(partyName);
        }
        await widget.controller.recordSplitExpense(
          paidAccountId: _accountId!,
          myCategoryId: _categoryId!,
          myShareCents: amountCents,
          theirShareCents: theirCents,
          partyId: resolvedPartyId,
          date: _selectedDate,
          dueDate: _splitDueDate,
          description: description,
          note: note,
        );
    }

    final controllerError = widget.controller.state.errorMessage;
    if (controllerError != null) {
      throw StateError(controllerError);
    }
  }

  Future<void> _submitCorrection({
    required JournalEntryModel original,
    required int amountCents,
    required String description,
  }) async {
    final replacementId = 'entry-corr-${_uuid.v4()}';
    final dateIso = _selectedDate.toIsoString();
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();

    Map<String, dynamic> built;
    if (_mode == FinanceComposerMode.transfer) {
      if (_destinationAccountId == null ||
          _destinationAccountId == _accountId) {
        throw ArgumentError('Select a different destination account.');
      }
      final feeText = _feeCtrl.text.trim();
      final feeCents =
          feeText.isEmpty ? 0 : FinanceUiFormatters.parseEtbToCents(feeText);
      if (feeCents == null || feeCents < 0) {
        throw ArgumentError('Enter a valid non-negative transfer fee.');
      }
      built = DoubleEntryEngine.buildTransfer(
        entryId: replacementId,
        fromAssetAccountId: _accountId!,
        toAssetAccountId: _destinationAccountId!,
        amountCents: amountCents,
        transferFeeCents: feeCents,
        feeExpenseAccountId:
            feeCents > 0 ? SystemControlAccounts.expense : null,
        date: dateIso,
        description: description,
        note: note,
      );
      final rawEntry = built['entry'] as JournalEntryModel;
      built['entry'] = rawEntry.copyWith(correctedFromEntryId: original.id);
    } else if (_mode == FinanceComposerMode.income) {
      if (_categoryId == null) {
        throw ArgumentError('Select an income category.');
      }
      built = DoubleEntryEngine.buildDirectIncome(
        entryId: replacementId,
        destAccountId: _accountId!,
        categoryId: _categoryId!,
        amountCents: amountCents,
        date: dateIso,
        description: description,
        note: note,
        correctedFromEntryId: original.id,
      );
    } else {
      if (_categoryId == null) {
        throw ArgumentError('Select an expense category.');
      }
      built = DoubleEntryEngine.buildDirectExpense(
        entryId: replacementId,
        paidAccountId: _accountId!,
        categoryId: _categoryId!,
        amountCents: amountCents,
        date: dateIso,
        description: description,
        note: note,
        correctedFromEntryId: original.id,
      );
    }

    await widget.controller.correctJournalEntry(
      originalEntryId: original.id,
      replacementEntry: built['entry'] as JournalEntryModel,
      replacementPostings: built['postings'] as List<PostingModel>,
      correctionReason: _correctionReasonCtrl.text.trim(),
    );

    final controllerError = widget.controller.state.errorMessage;
    if (controllerError != null) {
      throw StateError(controllerError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final accounts = state.activeEtbUserAccounts;
    final activeParties = state.parties.where((p) => !p.isArchived).toList();
    final catType = _mode == FinanceComposerMode.income ? 'income' : 'expense';
    final categoryItems = FinanceUiFormatters.buildCategoryDropdownItems(
      state.activeCategories,
      type: catType,
    );
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isEditing ? 'Correct Ledger Entry' : 'Record Ledger Entry',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                DaywellIconButton(
                  icon: Icons.close,
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            if (!_isEditing) ...[
              const SizedBox(height: SharedDesignTokens.spacingSm),
              Wrap(
                spacing: SharedDesignTokens.spacingSm,
                runSpacing: SharedDesignTokens.spacingSm,
                children: [
                  ChoiceChip(
                    label: const Text('Expense'),
                    selected: _mode == FinanceComposerMode.expense,
                    onSelected: (_) => setState(() {
                      _mode = FinanceComposerMode.expense;
                      _syncDefaultCategory();
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('Income'),
                    selected: _mode == FinanceComposerMode.income,
                    onSelected: (_) => setState(() {
                      _mode = FinanceComposerMode.income;
                      _syncDefaultCategory();
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('Transfer'),
                    selected: _mode == FinanceComposerMode.transfer,
                    onSelected: (_) => setState(() {
                      _mode = FinanceComposerMode.transfer;
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('Split Expense'),
                    selected: _mode == FinanceComposerMode.split,
                    onSelected: (_) => setState(() {
                      _mode = FinanceComposerMode.split;
                      _syncDefaultCategory();
                    }),
                  ),
                ],
              ),
            ],
            if (_validationError != null) ...[
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              DaywellStatusBanner(
                message: _validationError!,
                tone: DaywellStatusTone.error,
                onDismiss: () => setState(() => _validationError = null),
              ),
            ],
            if (state.nonEtbAccountCount > 0) ...[
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              DaywellStatusBanner(
                tone: DaywellStatusTone.warning,
                message:
                    'First-release posting supports ETB accounts only; ${state.nonEtbAccountCount} non-ETB or unverified account(s) are hidden.',
              ),
            ],
            const SizedBox(height: SharedDesignTokens.spacingCompact),
            if (accounts.isEmpty)
              const DaywellStatusBanner(
                title: 'No Active ETB Accounts Available',
                message:
                    'Create or restore an active ETB account before recording ledger entries.',
                tone: DaywellStatusTone.warning,
              )
            else ...[
              DaywellDropdownField<String>(
                label: _mode == FinanceComposerMode.income
                    ? 'Deposit Account'
                    : _mode == FinanceComposerMode.transfer
                        ? 'From Account'
                        : 'Paid From Account',
                value: accounts.any((a) => a.id == _accountId)
                    ? _accountId
                    : accounts.first.id,
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(
                      value: a.id,
                      child: Text(
                        '${a.name} (${FinanceUiFormatters.formatCurrencyCents(state.getAccountBalanceCents(a), currencyCode: a.currencyCode)})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (val) => setState(() => _accountId = val),
              ),
              if (_mode == FinanceComposerMode.transfer) ...[
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellDropdownField<String>(
                  label: 'Destination Account',
                  value: accounts.any((a) => a.id == _destinationAccountId)
                      ? _destinationAccountId
                      : accounts.first.id,
                  items: [
                    for (final a in accounts)
                      DropdownMenuItem(
                        value: a.id,
                        child: Text(
                          '${a.name} (${FinanceUiFormatters.formatCurrencyCents(state.getAccountBalanceCents(a), currencyCode: a.currencyCode)})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (val) =>
                      setState(() => _destinationAccountId = val),
                ),
              ],
              if (_mode != FinanceComposerMode.transfer) ...[
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellDropdownField<String>(
                  label: _mode == FinanceComposerMode.split
                      ? 'My Share Category'
                      : 'Category',
                  value: categoryItems.any((i) => i.value == _categoryId)
                      ? _categoryId
                      : (categoryItems.isNotEmpty
                          ? categoryItems.first.value
                          : null),
                  items: categoryItems,
                  onChanged: (val) => setState(() => _categoryId = val),
                ),
              ],
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              DaywellTextField(
                controller: _amountCtrl,
                label: _mode == FinanceComposerMode.split
                    ? 'My Share Amount (ETB)'
                    : 'Amount (ETB)',
                hintText: '0.00',
                isRequired: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              if (_mode == FinanceComposerMode.transfer) ...[
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellTextField(
                  controller: _feeCtrl,
                  label: 'Bank / Service Fee (ETB, optional)',
                  hintText: '0.00',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
              if (_mode == FinanceComposerMode.split) ...[
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellTextField(
                  controller: _theirShareCtrl,
                  label: 'Their Share / Receivable (ETB)',
                  hintText: '0.00',
                  isRequired: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                if (activeParties.isNotEmpty && !_showNewPartyField) ...[
                  DaywellDropdownField<String>(
                    label: 'Split With (Person / Party)',
                    value: activeParties.any((p) => p.id == _partyId)
                        ? _partyId
                        : activeParties.first.id,
                    items: [
                      for (final p in activeParties)
                        DropdownMenuItem(
                          value: p.id,
                          child: Text(p.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (val) => setState(() => _partyId = val),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: DaywellButton(
                      label: '+ New Person',
                      variant: DaywellButtonVariant.text,
                      size: DaywellButtonSize.compact,
                      onPressed: () =>
                          setState(() => _showNewPartyField = true),
                    ),
                  ),
                ] else ...[
                  DaywellTextField(
                    controller: _newPartyCtrl,
                    label: 'New Person / Party Name',
                    hintText: 'e.g. Abebe',
                    isRequired: true,
                  ),
                  if (activeParties.isNotEmpty)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: DaywellButton(
                        label: 'Choose Existing Party',
                        variant: DaywellButtonVariant.text,
                        size: DaywellButtonSize.compact,
                        onPressed: () =>
                            setState(() => _showNewPartyField = false),
                      ),
                    ),
                ],
                const SizedBox(height: SharedDesignTokens.spacingXs),
                Wrap(
                  spacing: SharedDesignTokens.spacingSm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _splitDueDate == null
                          ? 'Repayment Due Date: Optional'
                          : 'Due: ${SharedDateFormatter.formatDual(_splitDueDate!, useAmharic: false)}',
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textSecondary,
                      ),
                    ),
                    DaywellButton(
                      label: _splitDueDate == null ? 'Set Due Date' : 'Change',
                      variant: DaywellButtonVariant.text,
                      size: DaywellButtonSize.compact,
                      onPressed: () async {
                        final picked =
                            await FinanceUiFormatters.pickCalendarDate(
                          context,
                          initialDate:
                              _splitDueDate ?? _selectedDate.addDays(7),
                        );
                        if (picked != null && mounted) {
                          setState(() => _splitDueDate = picked);
                        }
                      },
                    ),
                  ],
                ),
              ],
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              DaywellTextField(
                controller: _descriptionCtrl,
                label: 'Description',
                hintText: 'e.g. Weekly groceries at Shoa',
              ),
              if (_mode == FinanceComposerMode.expense ||
                  _mode == FinanceComposerMode.income) ...[
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellTextField(
                  controller: _payeeCtrl,
                  label: _mode == FinanceComposerMode.income
                      ? 'Source / Payer (optional)'
                      : 'Merchant / Payee (optional)',
                  hintText: 'Optional',
                ),
              ],
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              DaywellTextField(
                controller: _noteCtrl,
                label: 'Note (optional)',
                maxLines: 2,
              ),
              if (_isEditing) ...[
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellTextField(
                  controller: _correctionReasonCtrl,
                  label: 'Correction Reason',
                  hintText: 'e.g. Receipt showed 540 ETB instead of 450 ETB',
                  isRequired: true,
                ),
              ],
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              Wrap(
                spacing: SharedDesignTokens.spacingSm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Date: ${SharedDateFormatter.formatDual(_selectedDate, useAmharic: false)}',
                    style: textTheme.bodySmall?.copyWith(
                      color: semantic.textSecondary,
                    ),
                  ),
                  DaywellButton(
                    label: 'Pick Date',
                    variant: DaywellButtonVariant.text,
                    size: DaywellButtonSize.compact,
                    onPressed: () async {
                      final picked = await FinanceUiFormatters.pickCalendarDate(
                        context,
                        initialDate: _selectedDate,
                      );
                      if (picked != null && mounted) {
                        setState(() => _selectedDate = picked);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: SharedDesignTokens.spacingMd),
              DaywellButton(
                label: _isEditing
                    ? 'Save Correction'
                    : _mode == FinanceComposerMode.transfer
                        ? 'Post Transfer'
                        : _mode == FinanceComposerMode.split
                            ? 'Post Split Expense'
                            : 'Post Ledger Entry',
                leadingIcon: Icons.check,
                isLoading: _isSaving,
                fullWidth: true,
                onPressed: _isSaving ? null : _submit,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
