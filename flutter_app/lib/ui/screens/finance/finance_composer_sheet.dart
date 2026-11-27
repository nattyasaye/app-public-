import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../application/finance/finance_controller.dart';
import '../../../application/finance/finance_state.dart';
import '../../../core/date/shared_date.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/finance/double_entry_engine.dart';
import '../../widgets/shared_ui_widgets.dart';
import 'finance_formatters.dart';

enum FinanceComposerMode { expense, income, transfer, split, lend, borrow }

/// Unified double-entry composer modal supporting Expense, Income, Transfer
/// (with optional bank fee + fee category), Split Expense, Lend, Borrow,
/// optional separate Cash Movement Date, and Correct/Replace Journal Entry mode.
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
  late CalendarDate _movementDate;
  bool _isMovementDateSynced = true;
  CalendarDate? _dueDate;

  String? _accountId;
  String? _destinationAccountId;
  String? _categoryId;
  String? _feeCategoryId;
  String? _partyId;

  late final TextEditingController _amountCtrl;
  late final TextEditingController _feeCtrl;
  late final TextEditingController _theirShareCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _payeeCtrl;
  late final TextEditingController _correctionReasonCtrl;
  late final TextEditingController _newPartyCtrl;

  bool _showNewPartyField = false;
  bool _isSaving = false;
  bool _didSubmit = false;
  bool _isPromptingDiscard = false;
  String? _validationError;

  late FinanceComposerMode _initialMode;
  late String _initialAmount;
  late String _initialFee;
  late String _initialTheirShare;
  late String _initialDescription;
  late String _initialPayee;
  late String _initialCorrectionReason;
  late String _initialNewParty;
  late CalendarDate _initialSelectedDate;
  late CalendarDate _initialMovementDate;
  late bool _initialIsMovementDateSynced;
  CalendarDate? _initialDueDate;
  String? _initialAccountId;
  String? _initialDestinationAccountId;
  String? _initialCategoryId;
  String? _initialFeeCategoryId;
  String? _initialPartyId;
  bool _lastHasUnsavedChanges = false;

  bool get _isEditing => widget.editingEntry != null;

  bool get _hasUnsavedChanges {
    if (_didSubmit) return false;
    final hasTextChanges = _amountCtrl.text.trim() != _initialAmount ||
        _feeCtrl.text.trim() != _initialFee ||
        _theirShareCtrl.text.trim() != _initialTheirShare ||
        _descriptionCtrl.text.trim() != _initialDescription ||
        _payeeCtrl.text.trim() != _initialPayee ||
        _correctionReasonCtrl.text.trim() != _initialCorrectionReason ||
        _newPartyCtrl.text.trim() != _initialNewParty;
    final hasDateChanges = _selectedDate != _initialSelectedDate ||
        _movementDate != _initialMovementDate ||
        _isMovementDateSynced != _initialIsMovementDateSynced ||
        _dueDate != _initialDueDate;
    if (_isEditing) {
      final hasSelectionChanges = _mode != _initialMode ||
          _accountId != _initialAccountId ||
          _destinationAccountId != _initialDestinationAccountId ||
          _categoryId != _initialCategoryId ||
          _feeCategoryId != _initialFeeCategoryId ||
          _partyId != _initialPartyId;
      return hasTextChanges || hasDateChanges || hasSelectionChanges;
    }
    return hasTextChanges || hasDateChanges;
  }

  bool get _modeUsesCategory =>
      _mode == FinanceComposerMode.expense ||
      _mode == FinanceComposerMode.income ||
      _mode == FinanceComposerMode.split;

  bool get _modeUsesFee =>
      _mode == FinanceComposerMode.expense ||
      _mode == FinanceComposerMode.transfer;

  bool get _modeUsesParty =>
      _mode == FinanceComposerMode.split ||
      _mode == FinanceComposerMode.lend ||
      _mode == FinanceComposerMode.borrow;

  bool get _modeUsesDueDate => _modeUsesParty;

  bool get _modeUsesPayee =>
      _mode == FinanceComposerMode.expense ||
      _mode == FinanceComposerMode.income;

  int get _parsedFeeCents {
    final text = _feeCtrl.text.trim();
    if (text.isEmpty) return 0;
    return FinanceUiFormatters.parseEtbToCents(text) ?? 0;
  }

  bool get _showFeeCategory => _modeUsesFee && _parsedFeeCents > 0;

  List<AccountModel> _eligibleAccountsForMode(
    FinanceModuleState state,
    FinanceComposerMode mode,
  ) {
    if (mode == FinanceComposerMode.transfer) {
      return [
        ...state.activeEtbSpendableAccounts,
        ...state.activeEtbVaultAccounts,
      ];
    }
    return state.activeEtbSpendableAccounts;
  }

  void _onControllerTextChanged() {
    if (!mounted) return;
    final nextHasUnsaved = _hasUnsavedChanges;
    if (_mode == FinanceComposerMode.expense ||
        _mode == FinanceComposerMode.transfer ||
        _mode == FinanceComposerMode.split ||
        nextHasUnsaved != _lastHasUnsavedChanges) {
      _lastHasUnsavedChanges = nextHasUnsaved;
      setState(() {});
    }
  }

  void _onSecondaryTextChanged() {
    if (!mounted) return;
    final nextHasUnsaved = _hasUnsavedChanges;
    if (nextHasUnsaved != _lastHasUnsavedChanges) {
      _lastHasUnsavedChanges = nextHasUnsaved;
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    final state = widget.controller.state;
    _mode = widget.initialMode;
    _selectedDate = CalendarDate.today();
    _movementDate = _selectedDate;
    _feeCategoryId = SystemControlAccounts.feeCategoryId;

    _amountCtrl = TextEditingController(text: widget.initialAmountText ?? '');
    _feeCtrl = TextEditingController(text: '0');
    _theirShareCtrl = TextEditingController();
    _descriptionCtrl =
        TextEditingController(text: widget.initialDescription ?? '');
    _payeeCtrl = TextEditingController();
    _correctionReasonCtrl = TextEditingController();
    _newPartyCtrl = TextEditingController();

    _amountCtrl.addListener(_onControllerTextChanged);
    _feeCtrl.addListener(_onControllerTextChanged);
    _theirShareCtrl.addListener(_onControllerTextChanged);
    _descriptionCtrl.addListener(_onSecondaryTextChanged);
    _payeeCtrl.addListener(_onSecondaryTextChanged);
    _correctionReasonCtrl.addListener(_onSecondaryTextChanged);
    _newPartyCtrl.addListener(_onSecondaryTextChanged);

    final activeParties =
        state.parties.where((p) => !p.isArchived).toList(growable: false);
    if (activeParties.isNotEmpty) {
      _partyId = activeParties.first.id;
    } else {
      _showNewPartyField = true;
    }

    if (_isEditing) {
      _prefillFromEditingEntry(widget.editingEntry!);
    } else {
      _syncAccountsForMode();
      _syncDefaultCategory();
    }

    _initialMode = _mode;
    _initialAmount = _amountCtrl.text.trim();
    _initialFee = _feeCtrl.text.trim();
    _initialTheirShare = _theirShareCtrl.text.trim();
    _initialDescription = _descriptionCtrl.text.trim();
    _initialPayee = _payeeCtrl.text.trim();
    _initialCorrectionReason = _correctionReasonCtrl.text.trim();
    _initialNewParty = _newPartyCtrl.text.trim();
    _initialSelectedDate = _selectedDate;
    _initialMovementDate = _movementDate;
    _initialIsMovementDateSynced = _isMovementDateSynced;
    _initialDueDate = _dueDate;
    _initialAccountId = _accountId;
    _initialDestinationAccountId = _destinationAccountId;
    _initialCategoryId = _categoryId;
    _initialFeeCategoryId = _feeCategoryId;
    _initialPartyId = _partyId;
  }

  void _syncAccountsForMode() {
    final eligible = _eligibleAccountsForMode(widget.controller.state, _mode);
    if (eligible.isEmpty) {
      _accountId = null;
      _destinationAccountId = null;
      return;
    }
    if (_accountId == null || !eligible.any((a) => a.id == _accountId)) {
      final liquid = eligible.where((a) => a.subType.isLiquid).toList();
      _accountId = (liquid.isNotEmpty ? liquid.first : eligible.first).id;
    }
    if (_mode == FinanceComposerMode.transfer) {
      if (eligible.length < 2) {
        _destinationAccountId = null;
      } else if (_destinationAccountId == null ||
          _destinationAccountId == _accountId ||
          !eligible.any((a) => a.id == _destinationAccountId)) {
        _destinationAccountId =
            eligible.firstWhere((a) => a.id != _accountId).id;
      }
    }
  }

  void _prefillFromEditingEntry(JournalEntryModel entry) {
    final state = widget.controller.state;
    _selectedDate = SharedDateFormatter.parseFlexibleToCalendarDate(
      entry.occurrenceDate,
    );
    final entryPostings =
        state.postings.where((p) => p.entryId == entry.id).toList();

    final resolvedEntryDescription =
        DoubleEntryEngine.resolveDescriptionPreservingLegacyNote(
      description: entry.description,
      legacyNote: DoubleEntryEngine.resolveUnambiguousHistoricalPostingNote(
        entryPostings,
      ),
    );

    if (entry.entryType == EntryType.transfer) {
      _mode = FinanceComposerMode.transfer;
      _descriptionCtrl.text = resolvedEntryDescription.replaceFirst(
        RegExp(r'\s*\(Fee:\s*[0-9.,]+\s*ETB\)\s*$'),
        '',
      );
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
      final feeCatRaw = fee?.categoryId;
      _feeCategoryId = feeCatRaw != null
          ? (FinanceUiFormatters.resolveCategorySelectionValue(
                feeCatRaw,
                state.categories,
                type: 'expense',
                preserveUnmatchedHistorical: true,
              ) ??
              SystemControlAccounts.feeCategoryId)
          : SystemControlAccounts.feeCategoryId;

      final movementIso = dst?.accountMovementDate ?? src?.accountMovementDate;
      _movementDate = (movementIso != null && movementIso.trim().isNotEmpty)
          ? SharedDateFormatter.parseFlexibleToCalendarDate(movementIso)
          : _selectedDate;
      _isMovementDateSynced =
          _movementDate.toIsoString() == _selectedDate.toIsoString();

      if (dst != null) {
        _amountCtrl.text =
            FinanceUiFormatters.formatCentsAsInput(dst.amountCents);
      }
      _feeCtrl.text = (fee != null && fee.amountCents > 0)
          ? FinanceUiFormatters.formatCentsAsInput(fee.amountCents)
          : '0';
      _syncAccountsForMode();
      return;
    }

    const payeeSep = ' — ';
    final sepIdx = resolvedEntryDescription.indexOf(payeeSep);
    if (sepIdx > 0) {
      _payeeCtrl.text = resolvedEntryDescription.substring(0, sepIdx).trim();
      _descriptionCtrl.text =
          resolvedEntryDescription.substring(sepIdx + payeeSep.length).trim();
    } else {
      _descriptionCtrl.text = resolvedEntryDescription;
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
      final movementIso = drAcc.accountMovementDate;
      _movementDate = movementIso.trim().isNotEmpty
          ? SharedDateFormatter.parseFlexibleToCalendarDate(movementIso)
          : _selectedDate;
      _isMovementDateSynced =
          _movementDate.toIsoString() == _selectedDate.toIsoString();
      _amountCtrl.text =
          FinanceUiFormatters.formatCentsAsInput(drAcc.amountCents);
    } else {
      _mode = FinanceComposerMode.expense;
      final expenseSummary = DoubleEntryEngine.summarizeDirectExpense(
        entry: entry,
        postings: entryPostings,
        accounts: state.accounts,
      );
      final drExp = entryPostings.firstWhere(
        (p) =>
            p.accountId == SystemControlAccounts.expense &&
            !DoubleEntryEngine.isExpenseFeePosting(p),
        orElse: () => entryPostings.first,
      );
      final crAcc = entryPostings.firstWhere(
        (p) =>
            p.direction == PostingDirection.credit &&
            !SystemControlAccounts.isSystemControlId(p.accountId),
        orElse: () => entryPostings.first,
      );
      _accountId =
          expenseSummary.isDirectExpense && expenseSummary.paidAccountId != null
              ? expenseSummary.paidAccountId
              : crAcc.accountId;
      _categoryId = expenseSummary.isDirectExpense
          ? expenseSummary.primaryCategoryId
          : drExp.categoryId;
      final feeCents =
          expenseSummary.isDirectExpense ? expenseSummary.feeCents : 0;
      _feeCtrl.text =
          feeCents > 0 ? FinanceUiFormatters.formatCentsAsInput(feeCents) : '0';
      final rawFeeCat =
          expenseSummary.isDirectExpense ? expenseSummary.feeCategoryId : null;
      _feeCategoryId = rawFeeCat != null
          ? (FinanceUiFormatters.resolveCategorySelectionValue(
                rawFeeCat,
                state.categories,
                type: 'expense',
                preserveUnmatchedHistorical: true,
              ) ??
              SystemControlAccounts.feeCategoryId)
          : SystemControlAccounts.feeCategoryId;
      final movementIso = crAcc.accountMovementDate;
      _movementDate = movementIso.trim().isNotEmpty
          ? SharedDateFormatter.parseFlexibleToCalendarDate(movementIso)
          : _selectedDate;
      _isMovementDateSynced =
          _movementDate.toIsoString() == _selectedDate.toIsoString();
      _amountCtrl.text = FinanceUiFormatters.formatCentsAsInput(
        expenseSummary.isDirectExpense
            ? expenseSummary.principalCents
            : drExp.amountCents,
      );
    }
    _syncAccountsForMode();
    _syncDefaultCategory(onlyIfMissing: true);
  }

  void _syncDefaultCategory({bool onlyIfMissing = false}) {
    if (!_modeUsesCategory) return;
    final state = widget.controller.state;
    final catType = _mode == FinanceComposerMode.income ? 'income' : 'expense';
    final resolved = FinanceUiFormatters.resolveCategorySelectionValue(
      _categoryId,
      state.categories,
      type: catType,
      preserveUnmatchedHistorical: _isEditing,
    );
    if (onlyIfMissing && resolved != null) {
      _categoryId = resolved;
      return;
    }
    if (!onlyIfMissing && resolved != null) {
      _categoryId = resolved;
      return;
    }
    final activeCandidates = state.activeCategories
        .where((c) => c.type == catType)
        .toList(growable: false);
    if (activeCandidates.isNotEmpty) {
      _categoryId = activeCandidates.first.id;
    } else {
      _categoryId = null;
    }
  }

  @override
  void dispose() {
    _amountCtrl.removeListener(_onControllerTextChanged);
    _feeCtrl.removeListener(_onControllerTextChanged);
    _theirShareCtrl.removeListener(_onControllerTextChanged);
    _descriptionCtrl.removeListener(_onSecondaryTextChanged);
    _payeeCtrl.removeListener(_onSecondaryTextChanged);
    _correctionReasonCtrl.removeListener(_onSecondaryTextChanged);
    _newPartyCtrl.removeListener(_onSecondaryTextChanged);
    _amountCtrl.dispose();
    _feeCtrl.dispose();
    _theirShareCtrl.dispose();
    _descriptionCtrl.dispose();
    _payeeCtrl.dispose();
    _correctionReasonCtrl.dispose();
    _newPartyCtrl.dispose();
    super.dispose();
  }

  Future<void> _handlePopBlocked() async {
    if (_isSaving || _isPromptingDiscard || !mounted) return;
    _isPromptingDiscard = true;
    try {
      final action = await DaywellUnsavedChangesDialog.show(
        context,
        title: _isEditing ? 'Discard Correction?' : 'Discard Entry?',
        message: _isEditing
            ? 'Save this ledger correction or discard your changes?'
            : 'Save this ledger entry or discard your changes?',
        saveLabel: _isEditing ? 'Save Correction' : 'Save',
        discardLabel: 'Discard',
      );
      if (!mounted) return;
      if (action == DaywellUnsavedChangesAction.save) {
        await _submit();
      } else if (action == DaywellUnsavedChangesAction.discard) {
        setState(() => _didSubmit = true);
        Navigator.of(context).pop(false);
      }
    } finally {
      _isPromptingDiscard = false;
    }
  }

  Future<void> _submit() async {
    if (_isSaving || _didSubmit) return;

    final state = widget.controller.state;
    final eligibleAccounts = _eligibleAccountsForMode(state, _mode);
    if (eligibleAccounts.isEmpty) {
      setState(() {
        _validationError = _mode == FinanceComposerMode.transfer
            ? 'Create or restore an active ETB account before recording a transfer.'
            : 'Create or restore an active spendable ETB account (savings vaults can only participate in transfers).';
      });
      return;
    }

    if (_accountId == null ||
        !eligibleAccounts.any((a) => a.id == _accountId)) {
      setState(
        () => _validationError = 'Select an active verified ETB account.',
      );
      return;
    }

    if (_mode == FinanceComposerMode.transfer) {
      if (eligibleAccounts.length < 2) {
        setState(() {
          _validationError =
              'Add at least 2 active ETB accounts (including savings vaults) to record a transfer.';
        });
        return;
      }
      if (_destinationAccountId == null ||
          !eligibleAccounts.any((a) => a.id == _destinationAccountId)) {
        setState(
          () => _validationError = 'Select an active ETB destination account.',
        );
        return;
      }
      if (_destinationAccountId == _accountId) {
        setState(
          () => _validationError =
              'Source and destination accounts must be different.',
        );
        return;
      }
    }

    if (_modeUsesFee) {
      final feeText = _feeCtrl.text.trim();
      if (feeText.isNotEmpty) {
        final feeCents = FinanceUiFormatters.parseEtbToCents(feeText);
        if (feeCents == null || feeCents < 0) {
          setState(() {
            _validationError = _mode == FinanceComposerMode.transfer
                ? 'Enter a valid non-negative transfer fee (up to 2 decimal places).'
                : 'Enter a valid non-negative bank/service fee (up to 2 decimal places).';
          });
          return;
        }
      }
    }

    final amountCents = FinanceUiFormatters.parseEtbToCents(_amountCtrl.text);
    if (amountCents == null || amountCents <= 0) {
      setState(() {
        _validationError =
            'Enter a valid ETB amount greater than 0 (up to 2 decimal places).';
      });
      return;
    }

    if (_modeUsesCategory &&
        (_categoryId == null || _categoryId!.trim().isEmpty)) {
      setState(() {
        _validationError = _mode == FinanceComposerMode.income
            ? 'Select an income category.'
            : 'Select an expense category.';
      });
      return;
    }

    if (_mode == FinanceComposerMode.split) {
      final theirCents =
          FinanceUiFormatters.parseEtbToCents(_theirShareCtrl.text);
      if (theirCents == null || theirCents <= 0) {
        setState(() {
          _validationError =
              'Enter the counterparty share amount greater than 0 (up to 2 decimal places).';
        });
        return;
      }
    }

    if (_modeUsesParty) {
      final activeParties = state.parties.where((p) => !p.isArchived).toList();
      final hasExistingParty = !_showNewPartyField &&
          _partyId != null &&
          activeParties.any((p) => p.id == _partyId);
      if (!hasExistingParty && _newPartyCtrl.text.trim().isEmpty) {
        setState(
          () => _validationError = 'Select or enter a person / counterparty.',
        );
        return;
      }
    }

    if (_isEditing && _correctionReasonCtrl.text.trim().isEmpty) {
      setState(
        () => _validationError =
            'Provide a reason for correcting this ledger entry.',
      );
      return;
    }

    final description = _descriptionCtrl.text.trim().isEmpty
        ? _defaultDescription()
        : _descriptionCtrl.text.trim();

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
        setState(() {
          _isSaving = false;
          _didSubmit = true;
        });
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
      case FinanceComposerMode.lend:
        return 'Money Lent';
      case FinanceComposerMode.borrow:
        return 'Money Borrowed';
    }
  }

  Future<String> _resolvePartyIdForSubmission() async {
    final activeParties =
        widget.controller.state.parties.where((p) => !p.isArchived).toList();
    if (!_showNewPartyField &&
        _partyId != null &&
        activeParties.any((p) => p.id == _partyId)) {
      return _partyId!;
    }
    final partyName = _newPartyCtrl.text.trim();
    if (partyName.isEmpty) {
      throw ArgumentError('Select or enter a person / counterparty.');
    }
    return widget.controller.ensurePartyId(partyName);
  }

  CalendarDate get _effectiveMovementDate =>
      _isMovementDateSynced ? _selectedDate : _movementDate;

  Future<void> _submitNew({
    required int amountCents,
    required String description,
  }) async {
    final payee =
        _payeeCtrl.text.trim().isEmpty ? null : _payeeCtrl.text.trim();
    final effectiveMovementDate = _effectiveMovementDate;

    switch (_mode) {
      case FinanceComposerMode.expense:
        final feeText = _feeCtrl.text.trim();
        final feeCents =
            feeText.isEmpty ? 0 : FinanceUiFormatters.parseEtbToCents(feeText)!;
        final feeCategoryId = feeCents > 0
            ? (_feeCategoryId ?? SystemControlAccounts.feeCategoryId)
            : null;
        final created = await widget.controller.recordDirectExpense(
          accountId: _accountId!,
          categoryId: _categoryId!,
          amountCents: amountCents,
          feeCents: feeCents,
          feeCategoryId: feeCategoryId,
          date: _selectedDate,
          movementDate: effectiveMovementDate,
          description: description,
          payee: payee,
        );
        if (created == null) {
          throw StateError(
            widget.controller.state.errorMessage ??
                'Unable to record expense entry.',
          );
        }
      case FinanceComposerMode.income:
        final created = await widget.controller.recordDirectIncome(
          accountId: _accountId!,
          categoryId: _categoryId!,
          amountCents: amountCents,
          date: _selectedDate,
          movementDate: effectiveMovementDate,
          description: description,
          payee: payee,
        );
        if (created == null) {
          throw StateError(
            widget.controller.state.errorMessage ??
                'Unable to record income entry.',
          );
        }
      case FinanceComposerMode.transfer:
        final feeText = _feeCtrl.text.trim();
        final feeCents =
            feeText.isEmpty ? 0 : FinanceUiFormatters.parseEtbToCents(feeText)!;
        final feeCategoryId = feeCents > 0
            ? (_feeCategoryId ?? SystemControlAccounts.feeCategoryId)
            : null;
        await widget.controller.recordTransfer(
          fromAssetAccountId: _accountId!,
          toAssetAccountId: _destinationAccountId!,
          amountCents: amountCents,
          transferFeeCents: feeCents,
          feeCategoryId: feeCategoryId,
          date: _selectedDate.toIsoString(),
          movementDate: effectiveMovementDate.toIsoString(),
          description: description,
        );
      case FinanceComposerMode.split:
        final theirCents =
            FinanceUiFormatters.parseEtbToCents(_theirShareCtrl.text)!;
        final resolvedPartyId = await _resolvePartyIdForSubmission();
        final created = await widget.controller.recordSplitExpense(
          paidAccountId: _accountId!,
          myCategoryId: _categoryId!,
          myShareCents: amountCents,
          theirShareCents: theirCents,
          partyId: resolvedPartyId,
          date: _selectedDate,
          movementDate: effectiveMovementDate,
          dueDate: _dueDate,
          description: description,
        );
        if (created == null) {
          throw StateError(
            widget.controller.state.errorMessage ??
                'Unable to record split expense.',
          );
        }
      case FinanceComposerMode.lend:
        final resolvedPartyId = await _resolvePartyIdForSubmission();
        final created = await widget.controller.lendMoney(
          partyId: resolvedPartyId,
          sourceAccountId: _accountId!,
          amountCents: amountCents,
          date: _selectedDate,
          movementDate: effectiveMovementDate,
          dueDate: _dueDate,
          description: description,
        );
        if (created == null) {
          throw StateError(
            widget.controller.state.errorMessage ??
                'Unable to record loan receivable.',
          );
        }
      case FinanceComposerMode.borrow:
        final resolvedPartyId = await _resolvePartyIdForSubmission();
        final created = await widget.controller.borrowMoney(
          partyId: resolvedPartyId,
          destinationAccountId: _accountId!,
          amountCents: amountCents,
          date: _selectedDate,
          movementDate: effectiveMovementDate,
          dueDate: _dueDate,
          description: description,
        );
        if (created == null) {
          throw StateError(
            widget.controller.state.errorMessage ??
                'Unable to record loan payable.',
          );
        }
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
    final movementDateIso = _effectiveMovementDate.toIsoString();
    final cleanPayee = _payeeCtrl.text.trim();
    final effectiveDescription = (cleanPayee.isNotEmpty &&
            _mode != FinanceComposerMode.transfer &&
            !description.toLowerCase().contains(cleanPayee.toLowerCase()))
        ? '$cleanPayee — $description'
        : description;

    Map<String, dynamic> built;
    if (_mode == FinanceComposerMode.transfer) {
      final feeText = _feeCtrl.text.trim();
      final feeCents =
          feeText.isEmpty ? 0 : FinanceUiFormatters.parseEtbToCents(feeText)!;
      final effectiveFeeCategoryId = feeCents > 0
          ? (_feeCategoryId ?? SystemControlAccounts.feeCategoryId)
          : null;
      built = DoubleEntryEngine.buildTransfer(
        entryId: replacementId,
        fromAssetAccountId: _accountId!,
        toAssetAccountId: _destinationAccountId!,
        amountCents: amountCents,
        transferFeeCents: feeCents,
        feeExpenseAccountId:
            feeCents > 0 ? SystemControlAccounts.expense : null,
        feeCategoryId: effectiveFeeCategoryId,
        date: dateIso,
        movementDate: movementDateIso,
        description: description,
      );
      final rawEntry = built['entry'] as JournalEntryModel;
      built['entry'] = rawEntry.copyWith(correctedFromEntryId: original.id);
    } else if (_mode == FinanceComposerMode.income) {
      built = DoubleEntryEngine.buildDirectIncome(
        entryId: replacementId,
        destAccountId: _accountId!,
        categoryId: _categoryId!,
        amountCents: amountCents,
        date: dateIso,
        movementDate: movementDateIso,
        description: effectiveDescription,
        correctedFromEntryId: original.id,
      );
    } else {
      final feeText = _feeCtrl.text.trim();
      final feeCents =
          feeText.isEmpty ? 0 : FinanceUiFormatters.parseEtbToCents(feeText)!;
      final effectiveFeeCategoryId = feeCents > 0
          ? (_feeCategoryId ?? SystemControlAccounts.feeCategoryId)
          : null;
      built = DoubleEntryEngine.buildDirectExpense(
        entryId: replacementId,
        paidAccountId: _accountId!,
        categoryId: _categoryId!,
        amountCents: amountCents,
        feeCents: feeCents,
        feeCategoryId: effectiveFeeCategoryId,
        date: dateIso,
        movementDate: movementDateIso,
        description: effectiveDescription,
        correctedFromEntryId: original.id,
      );
    }

    final corrected = await widget.controller.correctJournalEntry(
      originalEntryId: original.id,
      replacementEntry: built['entry'] as JournalEntryModel,
      replacementPostings: built['postings'] as List<PostingModel>,
      correctionReason: _correctionReasonCtrl.text.trim(),
    );

    final controllerError = widget.controller.state.errorMessage;
    if (corrected == null || controllerError != null) {
      throw StateError(
        controllerError ?? 'Unable to save journal entry correction.',
      );
    }
  }

  void _switchMode(FinanceComposerMode nextMode) {
    if (_mode == nextMode) return;
    setState(() {
      _mode = nextMode;
      _validationError = null;
      _syncAccountsForMode();
      _syncDefaultCategory();
    });
  }

  String _primaryAccountLabel() {
    switch (_mode) {
      case FinanceComposerMode.income:
      case FinanceComposerMode.borrow:
        return 'Deposit Account';
      case FinanceComposerMode.transfer:
        return 'From Account';
      case FinanceComposerMode.lend:
        return 'Source Account';
      case FinanceComposerMode.expense:
      case FinanceComposerMode.split:
        return 'Paid From Account';
    }
  }

  String _submitButtonLabel() {
    if (_isEditing) return 'Save Correction';
    switch (_mode) {
      case FinanceComposerMode.expense:
        return 'Post Expense';
      case FinanceComposerMode.income:
        return 'Post Income';
      case FinanceComposerMode.transfer:
        return 'Post Transfer';
      case FinanceComposerMode.split:
        return 'Post Split Expense';
      case FinanceComposerMode.lend:
        return 'Post Loan Out';
      case FinanceComposerMode.borrow:
        return 'Post Loan In';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final accounts = _eligibleAccountsForMode(state, _mode);
    final activeParties = state.parties.where((p) => !p.isArchived).toList();
    final catType = _mode == FinanceComposerMode.income ? 'income' : 'expense';
    final categoryItems =
        FinanceUiFormatters.buildCategoryDropdownItemsWithPreserved(
      state.categories,
      type: catType,
      preserveCategoryId: _isEditing ? _categoryId : null,
    );
    final feeCategoryItems = FinanceUiFormatters.buildFeeCategoryDropdownItems(
      state.categories,
      preserveCategoryId: _isEditing ? _feeCategoryId : null,
    );
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;

    final mySharePreviewCents =
        FinanceUiFormatters.parseEtbToCents(_amountCtrl.text) ?? 0;
    final theirSharePreviewCents =
        FinanceUiFormatters.parseEtbToCents(_theirShareCtrl.text) ?? 0;

    return PopScope<Object?>(
      canPop: !_hasUnsavedChanges && !_isSaving,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) {
          unawaited(_handlePopBlocked());
        }
      },
      child: Padding(
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
                      _isEditing
                          ? 'Correct Ledger Entry'
                          : 'Record Ledger Entry',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  DaywellIconButton(
                    icon: Icons.close,
                    tooltip: 'Close',
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).maybePop(false),
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
                      onSelected: (_) =>
                          _switchMode(FinanceComposerMode.expense),
                    ),
                    ChoiceChip(
                      label: const Text('Income'),
                      selected: _mode == FinanceComposerMode.income,
                      onSelected: (_) =>
                          _switchMode(FinanceComposerMode.income),
                    ),
                    ChoiceChip(
                      label: const Text('Transfer'),
                      selected: _mode == FinanceComposerMode.transfer,
                      onSelected: (_) =>
                          _switchMode(FinanceComposerMode.transfer),
                    ),
                    ChoiceChip(
                      label: const Text('Split Expense'),
                      selected: _mode == FinanceComposerMode.split,
                      onSelected: (_) => _switchMode(FinanceComposerMode.split),
                    ),
                    ChoiceChip(
                      label: const Text('Lend'),
                      selected: _mode == FinanceComposerMode.lend,
                      onSelected: (_) => _switchMode(FinanceComposerMode.lend),
                    ),
                    ChoiceChip(
                      label: const Text('Borrow'),
                      selected: _mode == FinanceComposerMode.borrow,
                      onSelected: (_) =>
                          _switchMode(FinanceComposerMode.borrow),
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
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              if (accounts.isEmpty)
                DaywellStatusBanner(
                  title: 'No Eligible Active ETB Accounts Available',
                  message: _mode == FinanceComposerMode.transfer
                      ? 'Create or restore an active ETB account before recording transfers.'
                      : 'Create or restore an active spendable ETB account (savings vaults can only participate in transfers).',
                  tone: DaywellStatusTone.warning,
                )
              else ...[
                DaywellDropdownField<String>(
                  label: _primaryAccountLabel(),
                  value: accounts.any((a) => a.id == _accountId)
                      ? _accountId
                      : accounts.first.id,
                  items: [
                    for (final a in accounts)
                      DropdownMenuItem(
                        value: a.id,
                        child: Text(
                          '${a.name}${a.subType.isSavingsVault ? ' [Vault]' : ''} (${FinanceUiFormatters.formatCurrencyCents(state.getAccountBalanceCents(a), currencyCode: a.currencyCode)})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (val) => setState(() {
                    _accountId = val;
                    if (_mode == FinanceComposerMode.transfer &&
                        _destinationAccountId == val &&
                        accounts.length > 1) {
                      _destinationAccountId =
                          accounts.firstWhere((a) => a.id != val).id;
                    }
                  }),
                ),
                if (_mode == FinanceComposerMode.transfer) ...[
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  if (accounts.length < 2)
                    const DaywellStatusBanner(
                      message:
                          'Add at least 2 active ETB accounts (including liquid or savings vault accounts) to transfer between accounts.',
                      tone: DaywellStatusTone.warning,
                    )
                  else
                    DaywellDropdownField<String>(
                      label: 'Destination Account',
                      value: accounts.any((a) => a.id == _destinationAccountId)
                          ? _destinationAccountId
                          : accounts
                              .firstWhere(
                                (a) => a.id != _accountId,
                                orElse: () => accounts.first,
                              )
                              .id,
                      items: [
                        for (final a in accounts)
                          DropdownMenuItem(
                            value: a.id,
                            child: Text(
                              '${a.name}${a.subType.isSavingsVault ? ' [Vault]' : ''} (${FinanceUiFormatters.formatCurrencyCents(state.getAccountBalanceCents(a), currencyCode: a.currencyCode)})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (val) =>
                          setState(() => _destinationAccountId = val),
                    ),
                ],
                if (_modeUsesCategory) ...[
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
                if (_modeUsesFee) ...[
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  DaywellTextField(
                    controller: _feeCtrl,
                    label: 'Bank / Service Fee (ETB, optional)',
                    hintText: '0.00',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  if (_showFeeCategory) ...[
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    DaywellDropdownField<String>(
                      label: 'Fee Category',
                      value:
                          feeCategoryItems.any((i) => i.value == _feeCategoryId)
                              ? _feeCategoryId
                              : (feeCategoryItems.isNotEmpty
                                  ? feeCategoryItems.first.value
                                  : null),
                      items: feeCategoryItems,
                      onChanged: (val) => setState(() => _feeCategoryId = val),
                    ),
                  ],
                  if (_mode == FinanceComposerMode.expense &&
                      _parsedFeeCents > 0 &&
                      mySharePreviewCents > 0) ...[
                    const SizedBox(height: SharedDesignTokens.spacingXs),
                    Text(
                      'Total deduction: ${FinanceUiFormatters.formatEtbCents(mySharePreviewCents + _parsedFeeCents)} '
                      '(Principal ${FinanceUiFormatters.formatEtbCents(mySharePreviewCents)} + '
                      'Fee ${FinanceUiFormatters.formatEtbCents(_parsedFeeCents)})',
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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
                  if (mySharePreviewCents > 0 ||
                      theirSharePreviewCents > 0) ...[
                    const SizedBox(height: SharedDesignTokens.spacingXs),
                    Text(
                      'Total Paid: ${FinanceUiFormatters.formatEtbCents(mySharePreviewCents + theirSharePreviewCents)}',
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
                if (_modeUsesParty) ...[
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  if (activeParties.isNotEmpty && !_showNewPartyField) ...[
                    DaywellDropdownField<String>(
                      label: _mode == FinanceComposerMode.split
                          ? 'Split With (Person / Party)'
                          : 'Person / Counterparty',
                      value: activeParties.any((p) => p.id == _partyId)
                          ? _partyId
                          : activeParties.first.id,
                      items: [
                        for (final p in activeParties)
                          DropdownMenuItem(
                            value: p.id,
                            child: Text(
                              p.name,
                              overflow: TextOverflow.ellipsis,
                            ),
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
                ],
                if (_modeUsesDueDate) ...[
                  const SizedBox(height: SharedDesignTokens.spacingXs),
                  Wrap(
                    spacing: SharedDesignTokens.spacingSm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _dueDate == null
                            ? 'Repayment Due Date: Optional'
                            : 'Due: ${SharedDateFormatter.formatDual(_dueDate!, useAmharic: false)}',
                        style: textTheme.bodySmall?.copyWith(
                          color: semantic.textSecondary,
                        ),
                      ),
                      DaywellButton(
                        label: _dueDate == null ? 'Set Due Date' : 'Change',
                        variant: DaywellButtonVariant.text,
                        size: DaywellButtonSize.compact,
                        onPressed: () async {
                          final picked =
                              await FinanceUiFormatters.pickCalendarDate(
                            context,
                            initialDate: _dueDate ?? _selectedDate.addDays(7),
                          );
                          if (picked != null && mounted) {
                            setState(() => _dueDate = picked);
                          }
                        },
                      ),
                      if (_dueDate != null)
                        DaywellButton(
                          label: 'Clear',
                          variant: DaywellButtonVariant.text,
                          size: DaywellButtonSize.compact,
                          onPressed: () => setState(() => _dueDate = null),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellTextField(
                  controller: _descriptionCtrl,
                  label: 'Description',
                  hintText: _mode == FinanceComposerMode.lend
                      ? 'e.g. Short-term loan to Abebe'
                      : _mode == FinanceComposerMode.borrow
                          ? 'e.g. Emergency advance from Dawit'
                          : 'e.g. Weekly groceries at Shoa',
                ),
                if (_modeUsesPayee) ...[
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  DaywellTextField(
                    controller: _payeeCtrl,
                    label: _mode == FinanceComposerMode.income
                        ? 'Source / Payer (optional)'
                        : 'Merchant / Payee (optional)',
                    hintText: 'Optional',
                  ),
                ],
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
                      'Occurrence Date: ${SharedDateFormatter.formatDual(_selectedDate, useAmharic: false)}',
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textSecondary,
                      ),
                    ),
                    DaywellButton(
                      label: 'Pick Date',
                      variant: DaywellButtonVariant.text,
                      size: DaywellButtonSize.compact,
                      onPressed: () async {
                        final picked =
                            await FinanceUiFormatters.pickCalendarDate(
                          context,
                          initialDate: _selectedDate,
                        );
                        if (picked != null && mounted) {
                          setState(() {
                            _selectedDate = picked;
                            if (_isMovementDateSynced) {
                              _movementDate = picked;
                            }
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: SharedDesignTokens.spacingXs),
                Wrap(
                  spacing: SharedDesignTokens.spacingSm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _isMovementDateSynced
                          ? 'Cash Movement Date: Same as occurrence date'
                          : 'Cash Movement Date: ${SharedDateFormatter.formatDual(_movementDate, useAmharic: false)}',
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textSecondary,
                      ),
                    ),
                    if (_isMovementDateSynced)
                      DaywellButton(
                        label: 'Separate Movement Date',
                        variant: DaywellButtonVariant.text,
                        size: DaywellButtonSize.compact,
                        onPressed: () {
                          setState(() {
                            _isMovementDateSynced = false;
                            _movementDate = _selectedDate;
                          });
                        },
                      )
                    else ...[
                      DaywellButton(
                        label: 'Pick Movement Date',
                        variant: DaywellButtonVariant.text,
                        size: DaywellButtonSize.compact,
                        onPressed: () async {
                          final picked =
                              await FinanceUiFormatters.pickCalendarDate(
                            context,
                            initialDate: _movementDate,
                          );
                          if (picked != null && mounted) {
                            setState(() => _movementDate = picked);
                          }
                        },
                      ),
                      DaywellButton(
                        label: 'Sync to Occurrence',
                        variant: DaywellButtonVariant.text,
                        size: DaywellButtonSize.compact,
                        onPressed: () {
                          setState(() {
                            _isMovementDateSynced = true;
                            _movementDate = _selectedDate;
                          });
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: SharedDesignTokens.spacingMd),
                DaywellButton(
                  label: _submitButtonLabel(),
                  leadingIcon: Icons.check,
                  isLoading: _isSaving,
                  fullWidth: true,
                  onPressed: (_isSaving || _didSubmit) ? null : _submit,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
