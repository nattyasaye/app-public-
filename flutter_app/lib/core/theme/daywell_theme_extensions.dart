import 'package:flutter/material.dart';
import '../shared_foundation.dart';

/// Application-wide semantic color extension for tokens not directly modeled by
/// Material [ColorScheme], driven strictly by [SharedDesignTokens].
@immutable
class DaywellSemanticColors extends ThemeExtension<DaywellSemanticColors> {
  final Color income;
  final Color onIncome;
  final Color incomeContainer;
  final Color onIncomeContainer;

  final Color expense;
  final Color onExpense;
  final Color expenseContainer;
  final Color onExpenseContainer;

  final Color transfer;
  final Color onTransfer;
  final Color transferContainer;
  final Color onTransferContainer;

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;

  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;

  final Color canvas;
  final Color surfaceSubtle;
  final Color card;
  final Color elevated;
  final Color border;
  final Color divider;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textDisabled;

  const DaywellSemanticColors({
    required this.income,
    required this.onIncome,
    required this.incomeContainer,
    required this.onIncomeContainer,
    required this.expense,
    required this.onExpense,
    required this.expenseContainer,
    required this.onExpenseContainer,
    required this.transfer,
    required this.onTransfer,
    required this.transferContainer,
    required this.onTransferContainer,
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.canvas,
    required this.surfaceSubtle,
    required this.card,
    required this.elevated,
    required this.border,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textDisabled,
  });

  const DaywellSemanticColors.light()
      : income = SharedDesignTokens.semanticIncome,
        onIncome = SharedDesignTokens.onSemanticIncome,
        incomeContainer = SharedDesignTokens.semanticIncomeContainerLight,
        onIncomeContainer = SharedDesignTokens.onSemanticIncomeContainerLight,
        expense = SharedDesignTokens.semanticExpense,
        onExpense = SharedDesignTokens.onSemanticExpense,
        expenseContainer = SharedDesignTokens.semanticExpenseContainerLight,
        onExpenseContainer = SharedDesignTokens.onSemanticExpenseContainerLight,
        transfer = SharedDesignTokens.semanticTransfer,
        onTransfer = SharedDesignTokens.onSemanticTransfer,
        transferContainer = SharedDesignTokens.semanticTransferContainerLight,
        onTransferContainer =
            SharedDesignTokens.onSemanticTransferContainerLight,
        success = SharedDesignTokens.semanticSuccess,
        onSuccess = SharedDesignTokens.onSemanticSuccess,
        successContainer = SharedDesignTokens.semanticSuccessContainerLight,
        onSuccessContainer = SharedDesignTokens.onSemanticSuccessContainerLight,
        error = SharedDesignTokens.semanticError,
        onError = SharedDesignTokens.onSemanticError,
        errorContainer = SharedDesignTokens.semanticErrorContainerLight,
        onErrorContainer = SharedDesignTokens.onSemanticErrorContainerLight,
        warning = SharedDesignTokens.semanticWarning,
        onWarning = SharedDesignTokens.onSemanticWarning,
        warningContainer = SharedDesignTokens.semanticWarningContainerLight,
        onWarningContainer = SharedDesignTokens.onSemanticWarningContainerLight,
        info = SharedDesignTokens.semanticInfo,
        onInfo = SharedDesignTokens.onSemanticInfo,
        infoContainer = SharedDesignTokens.semanticInfoContainerLight,
        onInfoContainer = SharedDesignTokens.onSemanticInfoContainerLight,
        canvas = SharedDesignTokens.canvasLight,
        surfaceSubtle = SharedDesignTokens.surfaceSubtleLight,
        card = SharedDesignTokens.cardLight,
        elevated = SharedDesignTokens.elevatedLight,
        border = SharedDesignTokens.borderLight,
        divider = SharedDesignTokens.dividerLight,
        textPrimary = SharedDesignTokens.textPrimaryLight,
        textSecondary = SharedDesignTokens.textSecondaryLight,
        textMuted = SharedDesignTokens.textMutedLight,
        textDisabled = SharedDesignTokens.textDisabledLight;

  const DaywellSemanticColors.dark()
      : income = SharedDesignTokens.semanticIncome,
        onIncome = SharedDesignTokens.onSemanticIncome,
        incomeContainer = SharedDesignTokens.semanticIncomeContainerDark,
        onIncomeContainer = SharedDesignTokens.onSemanticIncomeContainerDark,
        expense = SharedDesignTokens.semanticExpense,
        onExpense = SharedDesignTokens.onSemanticExpense,
        expenseContainer = SharedDesignTokens.semanticExpenseContainerDark,
        onExpenseContainer = SharedDesignTokens.onSemanticExpenseContainerDark,
        transfer = SharedDesignTokens.semanticTransfer,
        onTransfer = SharedDesignTokens.onSemanticTransfer,
        transferContainer = SharedDesignTokens.semanticTransferContainerDark,
        onTransferContainer =
            SharedDesignTokens.onSemanticTransferContainerDark,
        success = SharedDesignTokens.semanticSuccess,
        onSuccess = SharedDesignTokens.onSemanticSuccess,
        successContainer = SharedDesignTokens.semanticSuccessContainerDark,
        onSuccessContainer = SharedDesignTokens.onSemanticSuccessContainerDark,
        error = SharedDesignTokens.semanticError,
        onError = SharedDesignTokens.onSemanticError,
        errorContainer = SharedDesignTokens.semanticErrorContainerDark,
        onErrorContainer = SharedDesignTokens.onSemanticErrorContainerDark,
        warning = SharedDesignTokens.semanticWarning,
        onWarning = SharedDesignTokens.onSemanticWarning,
        warningContainer = SharedDesignTokens.semanticWarningContainerDark,
        onWarningContainer = SharedDesignTokens.onSemanticWarningContainerDark,
        info = SharedDesignTokens.semanticInfo,
        onInfo = SharedDesignTokens.onSemanticInfo,
        infoContainer = SharedDesignTokens.semanticInfoContainerDark,
        onInfoContainer = SharedDesignTokens.onSemanticInfoContainerDark,
        canvas = SharedDesignTokens.canvasDark,
        surfaceSubtle = SharedDesignTokens.surfaceSubtleDark,
        card = SharedDesignTokens.cardDark,
        elevated = SharedDesignTokens.elevatedDark,
        border = SharedDesignTokens.borderDark,
        divider = SharedDesignTokens.dividerDark,
        textPrimary = SharedDesignTokens.textPrimaryDark,
        textSecondary = SharedDesignTokens.textSecondaryDark,
        textMuted = SharedDesignTokens.textMutedDark,
        textDisabled = SharedDesignTokens.textDisabledDark;

  @override
  DaywellSemanticColors copyWith({
    Color? income,
    Color? onIncome,
    Color? incomeContainer,
    Color? onIncomeContainer,
    Color? expense,
    Color? onExpense,
    Color? expenseContainer,
    Color? onExpenseContainer,
    Color? transfer,
    Color? onTransfer,
    Color? transferContainer,
    Color? onTransferContainer,
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? error,
    Color? onError,
    Color? errorContainer,
    Color? onErrorContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? canvas,
    Color? surfaceSubtle,
    Color? card,
    Color? elevated,
    Color? border,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textDisabled,
  }) {
    return DaywellSemanticColors(
      income: income ?? this.income,
      onIncome: onIncome ?? this.onIncome,
      incomeContainer: incomeContainer ?? this.incomeContainer,
      onIncomeContainer: onIncomeContainer ?? this.onIncomeContainer,
      expense: expense ?? this.expense,
      onExpense: onExpense ?? this.onExpense,
      expenseContainer: expenseContainer ?? this.expenseContainer,
      onExpenseContainer: onExpenseContainer ?? this.onExpenseContainer,
      transfer: transfer ?? this.transfer,
      onTransfer: onTransfer ?? this.onTransfer,
      transferContainer: transferContainer ?? this.transferContainer,
      onTransferContainer: onTransferContainer ?? this.onTransferContainer,
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      error: error ?? this.error,
      onError: onError ?? this.onError,
      errorContainer: errorContainer ?? this.errorContainer,
      onErrorContainer: onErrorContainer ?? this.onErrorContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      canvas: canvas ?? this.canvas,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      card: card ?? this.card,
      elevated: elevated ?? this.elevated,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textDisabled: textDisabled ?? this.textDisabled,
    );
  }

  @override
  DaywellSemanticColors lerp(
    covariant DaywellSemanticColors? other,
    double t,
  ) {
    if (other is! DaywellSemanticColors) {
      return this;
    }
    return DaywellSemanticColors(
      income: Color.lerp(income, other.income, t)!,
      onIncome: Color.lerp(onIncome, other.onIncome, t)!,
      incomeContainer: Color.lerp(incomeContainer, other.incomeContainer, t)!,
      onIncomeContainer:
          Color.lerp(onIncomeContainer, other.onIncomeContainer, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      onExpense: Color.lerp(onExpense, other.onExpense, t)!,
      expenseContainer:
          Color.lerp(expenseContainer, other.expenseContainer, t)!,
      onExpenseContainer:
          Color.lerp(onExpenseContainer, other.onExpenseContainer, t)!,
      transfer: Color.lerp(transfer, other.transfer, t)!,
      onTransfer: Color.lerp(onTransfer, other.onTransfer, t)!,
      transferContainer:
          Color.lerp(transferContainer, other.transferContainer, t)!,
      onTransferContainer:
          Color.lerp(onTransferContainer, other.onTransferContainer, t)!,
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      error: Color.lerp(error, other.error, t)!,
      onError: Color.lerp(onError, other.onError, t)!,
      errorContainer: Color.lerp(errorContainer, other.errorContainer, t)!,
      onErrorContainer:
          Color.lerp(onErrorContainer, other.onErrorContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surfaceSubtle: Color.lerp(surfaceSubtle, other.surfaceSubtle, t)!,
      card: Color.lerp(card, other.card, t)!,
      elevated: Color.lerp(elevated, other.elevated, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
    );
  }
}

extension DaywellSemanticColorsContext on BuildContext {
  DaywellSemanticColors get daywellColors {
    final ext = Theme.of(this).extension<DaywellSemanticColors>();
    if (ext != null) return ext;
    return Theme.of(this).brightness == Brightness.dark
        ? const DaywellSemanticColors.dark()
        : const DaywellSemanticColors.light();
  }
}
