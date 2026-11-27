import 'package:flutter/material.dart';

import '../../../application/finance/finance_controller.dart';
import '../../../core/date/shared_date.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/finance/double_entry_engine.dart';
import '../../widgets/shared_ui_widgets.dart';
import 'finance_formatters.dart';

class _SetupAccountDraft {
  final String id;
  final String name;
  final AccountSubType subType;
  final TextEditingController balanceController;
  CalendarDate openingDate;
  bool isSelected;

  _SetupAccountDraft({
    required this.id,
    required this.name,
    required this.subType,
    required this.openingDate,
    String initialBalanceText = '',
    this.isSelected = true,
  }) : balanceController = TextEditingController(text: initialBalanceText);

  AccountType get accountType => subType == AccountSubType.creditCard
      ? AccountType.liability
      : AccountType.asset;

  void dispose() => balanceController.dispose();
}

/// Stage 4.7 3-step interactive onboarding wizard for Daywell Finance accounts
/// and opening ledger balances.
class FinanceSetupWizard extends StatefulWidget {
  final FinanceController controller;

  const FinanceSetupWizard({
    super.key,
    required this.controller,
  });

  @override
  State<FinanceSetupWizard> createState() => _FinanceSetupWizardState();
}

class _FinanceSetupWizardState extends State<FinanceSetupWizard> {
  int _step = 1;
  bool _isSaving = false;
  String? _errorText;
  late final List<_SetupAccountDraft> _drafts;
  final TextEditingController _customNameController = TextEditingController();
  final TextEditingController _customBalanceController =
      TextEditingController();
  AccountSubType _customSubType = AccountSubType.bank;

  @override
  void initState() {
    super.initState();
    final today = CalendarDate.today();
    _drafts = [
      _SetupAccountDraft(
        id: 'acc-cbe',
        name: 'CBE',
        subType: AccountSubType.bank,
        openingDate: today,
      ),
      _SetupAccountDraft(
        id: 'acc-boa',
        name: 'Bank of Abyssinia',
        subType: AccountSubType.bank,
        openingDate: today,
      ),
      _SetupAccountDraft(
        id: 'acc-telebirr',
        name: 'Telebirr',
        subType: AccountSubType.mobileMoney,
        openingDate: today,
      ),
      _SetupAccountDraft(
        id: 'acc-cash',
        name: 'Cash Wallet',
        subType: AccountSubType.cash,
        openingDate: today,
      ),
      _SetupAccountDraft(
        id: 'acc-vault',
        name: 'Emergency Vault',
        subType: AccountSubType.savingsVault,
        openingDate: today,
        isSelected: false,
      ),
    ];
  }

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    _customNameController.dispose();
    _customBalanceController.dispose();
    super.dispose();
  }

  void _addCustomAccount() {
    final name = _customNameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = 'Enter a name for your custom account.');
      return;
    }
    final balanceText = _customBalanceController.text.trim();
    if (balanceText.isNotEmpty &&
        FinanceUiFormatters.parseEtbToCents(balanceText) == null) {
      setState(
          () => _errorText = 'Enter a valid decimal amount (e.g. 2500.50).');
      return;
    }
    setState(() {
      _errorText = null;
      _drafts.add(
        _SetupAccountDraft(
          id: 'acc-custom-${EthiopiaClock.nowUtc().microsecondsSinceEpoch}',
          name: name,
          subType: _customSubType,
          openingDate: CalendarDate.today(),
          initialBalanceText: balanceText,
        ),
      );
      _customNameController.clear();
      _customBalanceController.clear();
    });
  }

  Future<void> _finishSetup() async {
    final selected = _drafts.where((d) => d.isSelected).toList();
    if (selected.isEmpty) {
      setState(
          () => _errorText = 'Select at least one account or tap Skip Setup.');
      return;
    }

    final models = <AccountModel>[];
    for (final d in selected) {
      final raw = d.balanceController.text.trim();
      final cents = raw.isEmpty ? 0 : FinanceUiFormatters.parseEtbToCents(raw);
      if (cents == null) {
        setState(
          () => _errorText =
              'Invalid opening balance for "${d.name}". Use numbers like 1500.00.',
        );
        return;
      }
      models.add(
        AccountModel(
          id: d.id,
          name: d.name,
          type: d.accountType,
          subType: d.subType,
          currencyCode: 'ETB',
          openingBalanceCents: cents,
          openingBalanceDate: d.openingDate.toIsoString(),
        ),
      );
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });
    await widget.controller.completeSetup(models);
    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.daywellColors;
    final textTheme = theme.textTheme;
    final selectedDrafts = _drafts.where((d) => d.isSelected).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DaywellCard(
            padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: SharedDesignTokens.spacingSm,
                  runSpacing: SharedDesignTokens.spacingSm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    DaywellStatusBadge(
                      label: 'Step $_step of 3',
                      tone: DaywellStatusTone.info,
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                    DaywellButton(
                      label: 'Skip Setup',
                      variant: DaywellButtonVariant.text,
                      size: DaywellButtonSize.compact,
                      onPressed: _isSaving
                          ? null
                          : widget.controller.dismissSetupWizard,
                    ),
                  ],
                ),
                const SizedBox(height: SharedDesignTokens.spacingSm),
                Text(
                  'Set up your personal ledger',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: SharedDesignTokens.spacingXs),
                Text(
                  _step == 1
                      ? 'Choose the bank, cash, mobile money, savings vault, or credit card accounts you track.'
                      : _step == 2
                          ? 'Enter each account\'s opening balance and starting date. Opening balances post atomically to equity.'
                          : 'Review your opening balances and ledger classification before starting.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: semantic.textSecondary,
                  ),
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellProgressBar(
                  value: _step / 3.0,
                  label: 'Onboarding Progress',
                  valueText: '${((_step / 3.0) * 100).round()}%',
                ),
              ],
            ),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: SharedDesignTokens.spacingCompact),
            DaywellStatusBanner(
              title: 'Check Setup Details',
              message: _errorText!,
              tone: DaywellStatusTone.error,
              onDismiss: () => setState(() => _errorText = null),
            ),
          ],
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          if (_step == 1) _buildStepOne(context),
          if (_step == 2) _buildStepTwo(context, selectedDrafts),
          if (_step == 3) _buildStepThree(context, selectedDrafts),
          const SizedBox(height: SharedDesignTokens.spacingMd),
          Wrap(
            spacing: SharedDesignTokens.spacingSm,
            runSpacing: SharedDesignTokens.spacingSm,
            alignment: WrapAlignment.spaceBetween,
            children: [
              if (_step > 1)
                DaywellButton(
                  label: 'Back',
                  variant: DaywellButtonVariant.outlined,
                  onPressed: _isSaving
                      ? null
                      : () => setState(() {
                            _errorText = null;
                            _step--;
                          }),
                )
              else
                const SizedBox.shrink(),
              if (_step < 3)
                DaywellButton(
                  label: 'Continue',
                  trailingIcon: Icons.arrow_forward,
                  onPressed: selectedDrafts.isEmpty
                      ? () => setState(
                            () => _errorText = 'Select at least one account.',
                          )
                      : () => setState(() {
                            _errorText = null;
                            _step++;
                          }),
                )
              else
                DaywellButton(
                  label: 'Initialize Ledger',
                  leadingIcon: Icons.check_circle_outline,
                  isLoading: _isSaving,
                  onPressed: _finishSetup,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepOne(BuildContext context) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DaywellCard(
          padding: const EdgeInsets.all(SharedDesignTokens.spacingSm),
          child: Column(
            children: [
              for (final draft in _drafts)
                DaywellCheckboxTile(
                  title: draft.name,
                  subtitle: FinanceUiFormatters.accountSubTypeLabel(
                    draft.subType,
                  ),
                  secondary: Icon(
                    FinanceUiFormatters.accountSubTypeIcon(draft.subType),
                    color: semantic.textSecondary,
                  ),
                  value: draft.isSelected,
                  onChanged: (val) =>
                      setState(() => draft.isSelected = val ?? false),
                ),
            ],
          ),
        ),
        const SizedBox(height: SharedDesignTokens.spacingCompact),
        DaywellCard(
          padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Custom Account',
                style:
                    textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              DaywellTextField(
                controller: _customNameController,
                label: 'Account Name',
                hintText: 'e.g. Nib Bank or Household Cash',
              ),
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              DaywellDropdownField<AccountSubType>(
                label: 'Account Kind',
                value: _customSubType,
                items: const [
                  DropdownMenuItem(
                    value: AccountSubType.bank,
                    child: Text('Bank Account (Liquid)'),
                  ),
                  DropdownMenuItem(
                    value: AccountSubType.cash,
                    child: Text('Cash Wallet (Liquid)'),
                  ),
                  DropdownMenuItem(
                    value: AccountSubType.mobileMoney,
                    child: Text('Mobile Money (Liquid)'),
                  ),
                  DropdownMenuItem(
                    value: AccountSubType.savingsVault,
                    child: Text('Savings Vault (Protected)'),
                  ),
                  DropdownMenuItem(
                    value: AccountSubType.creditCard,
                    child: Text('Credit Card (Short-Term Liability)'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _customSubType = val);
                },
              ),
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              DaywellTextField(
                controller: _customBalanceController,
                label: 'Initial Balance (ETB, optional)',
                hintText: '0.00',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              DaywellButton(
                label: 'Add Account',
                leadingIcon: Icons.add,
                variant: DaywellButtonVariant.secondary,
                onPressed: _addCustomAccount,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepTwo(
    BuildContext context,
    List<_SetupAccountDraft> selectedDrafts,
  ) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        for (final draft in selectedDrafts) ...[
          DaywellCard(
            padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      FinanceUiFormatters.accountSubTypeIcon(draft.subType),
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: SharedDesignTokens.spacingSm),
                    Expanded(
                      child: Text(
                        draft.name,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DaywellStatusBadge(
                      label: FinanceUiFormatters.accountSubTypeLabel(
                        draft.subType,
                      ),
                      tone: draft.subType == AccountSubType.creditCard
                          ? DaywellStatusTone.warning
                          : DaywellStatusTone.info,
                      showIcon: false,
                    ),
                  ],
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellTextField(
                  controller: draft.balanceController,
                  label: draft.subType == AccountSubType.creditCard
                      ? 'Current Amount Owed (ETB)'
                      : 'Opening Balance (ETB)',
                  hintText: '0.00',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: SharedDesignTokens.spacingSm),
                Wrap(
                  spacing: SharedDesignTokens.spacingSm,
                  runSpacing: SharedDesignTokens.spacingXs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Opening Date: ${SharedDateFormatter.formatDual(draft.openingDate, useAmharic: false)}',
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textSecondary,
                      ),
                    ),
                    DaywellButton(
                      label: 'Change Date',
                      variant: DaywellButtonVariant.text,
                      size: DaywellButtonSize.compact,
                      onPressed: () async {
                        final picked =
                            await FinanceUiFormatters.pickCalendarDate(
                          context,
                          initialDate: draft.openingDate,
                        );
                        if (picked != null && mounted) {
                          setState(() => draft.openingDate = picked);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: SharedDesignTokens.spacingSm),
        ],
      ],
    );
  }

  Widget _buildStepThree(
    BuildContext context,
    List<_SetupAccountDraft> selectedDrafts,
  ) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;

    int totalLiquid = 0;
    int totalVault = 0;
    int totalCredit = 0;
    for (final d in selectedDrafts) {
      final raw = d.balanceController.text.trim();
      final cents =
          raw.isEmpty ? 0 : (FinanceUiFormatters.parseEtbToCents(raw) ?? 0);
      if (d.subType.isLiquid) totalLiquid += cents;
      if (d.subType.isSavingsVault) totalVault += cents;
      if (d.subType.isCreditCard) totalCredit += cents;
    }

    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ledger Opening Summary',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          _summaryRow(
            context,
            'Liquid Cash',
            FinanceUiFormatters.formatEtbCents(totalLiquid),
          ),
          _summaryRow(
            context,
            'Savings Vaults (Excluded from Safe-to-Spend)',
            FinanceUiFormatters.formatEtbCents(totalVault),
          ),
          if (totalCredit > 0)
            _summaryRow(
              context,
              'Credit Card Liability',
              '-${FinanceUiFormatters.formatEtbCents(totalCredit)}',
            ),
          const Divider(),
          for (final d in selectedDrafts)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: SharedDesignTokens.spacingXs,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${d.name} (${FinanceUiFormatters.accountSubTypeLabel(d.subType)})',
                      style: textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    FinanceUiFormatters.formatEtbCents(
                      d.balanceController.text.trim().isEmpty
                          ? 0
                          : (FinanceUiFormatters.parseEtbToCents(
                                d.balanceController.text,
                              ) ??
                              0),
                    ),
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: semantic.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryRow(BuildContext context, String label, String value) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style:
                  textTheme.bodySmall?.copyWith(color: semantic.textSecondary),
            ),
          ),
          const SizedBox(width: SharedDesignTokens.spacingSm),
          Text(
            value,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
