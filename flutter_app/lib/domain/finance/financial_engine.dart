import 'double_entry_engine.dart';

/// Core financial calculation engine operating strictly with integer minor units (cents).
///
/// Prevents floating-point precision loss.
/// 1 Ethiopian Birr (ETB) = 100 cents (ሳንቲም).
class FinancialEngine {
  /// Formats an integer amount of cents into a currency-labeled display string.
  /// Example: 25050 cents -> "250.50 ETB"
  static String formatBirr(int amountCents, {String currencyCode = 'ETB'}) {
    final isNegative = amountCents < 0;
    final absCents = amountCents.abs();
    final whole = absCents ~/ 100;
    final cents = (absCents % 100).toString().padLeft(2, '0');
    final sign = isNegative ? '-' : '';
    final tier = DoubleEntryEngine.classifyCurrencyCode(currencyCode);
    switch (tier) {
      case CurrencyValidationTier.verifiedEtb:
        return '$sign$whole.$cents ETB';
      case CurrencyValidationTier.verifiedNonEtb:
        return '$sign$whole.$cents ${DoubleEntryEngine.normalizeCurrencyCode(currencyCode)}';
      case CurrencyValidationTier.unverified:
        return '$sign$whole.$cents (Unverified)';
    }
  }

  /// Parses a string representation (e.g. "1250.75" or "1250") into integer cents.
  static int parseToCents(String input) {
    final cleaned = input.trim().replaceAll(',', '');
    if (cleaned.isEmpty) return 0;

    final parts = cleaned.split('.');
    final whole = int.tryParse(parts[0]) ?? 0;
    int cents = 0;

    if (parts.length > 1) {
      final decimalPart = parts[1].padRight(2, '0').substring(0, 2);
      cents = int.tryParse(decimalPart) ?? 0;
    }

    final total = (whole.abs() * 100) + cents;
    return whole < 0 || cleaned.startsWith('-') ? -total : total;
  }

  /// Calculates the actual recorded balance from real recorded transactions.
  ///
  /// Formula:
  /// Recorded Balance = Opening Balance + Received Income - Recorded Expenses
  ///
  /// Note: Expected or projected future income is strictly excluded from this calculation.
  static int calculateRecordedBalance({
    required int openingBalanceCents,
    required List<int> receivedIncomeCents,
    required List<int> recordedExpenseCents,
  }) {
    final totalIncome =
        receivedIncomeCents.fold<int>(0, (sum, val) => sum + val);
    final totalExpenses =
        recordedExpenseCents.fold<int>(0, (sum, val) => sum + val);
    return openingBalanceCents + totalIncome - totalExpenses;
  }

  /// Calculates the Available-to-Spend estimate for the current planning period.
  ///
  /// Formula:
  /// Available to Spend = Recorded Balance
  ///                     - Unpaid Commitments Due in Period
  ///                     - Savings Allocations Reserved for Period
  ///
  /// Note: Commitments that have already been paid (marked as paid or recorded
  /// as expenses) MUST NOT be subtracted again to avoid double-counting.
  static FinancialSnapshot computeSnapshot({
    required int openingBalanceCents,
    required List<int> receivedIncomeCents,
    required List<int> recordedExpenseCents,
    required List<int> unpaidCommitmentsInPeriodCents,
    required List<int> savingsAllocationsInPeriodCents,
    required List<int> expectedFutureIncomeCents,
  }) {
    final totalIncome =
        receivedIncomeCents.fold<int>(0, (sum, val) => sum + val);
    final totalExpenses =
        recordedExpenseCents.fold<int>(0, (sum, val) => sum + val);
    final recordedBalance = openingBalanceCents + totalIncome - totalExpenses;

    final totalUnpaidCommitments =
        unpaidCommitmentsInPeriodCents.fold<int>(0, (sum, val) => sum + val);
    final totalSavingsReserved =
        savingsAllocationsInPeriodCents.fold<int>(0, (sum, val) => sum + val);
    final totalExpectedIncome =
        expectedFutureIncomeCents.fold<int>(0, (sum, val) => sum + val);

    final availableToSpend =
        recordedBalance - totalUnpaidCommitments - totalSavingsReserved;

    return FinancialSnapshot(
      openingBalanceCents: openingBalanceCents,
      totalIncomeCents: totalIncome,
      totalExpensesCents: totalExpenses,
      recordedBalanceCents: recordedBalance,
      unpaidCommitmentsCents: totalUnpaidCommitments,
      savingsReservedCents: totalSavingsReserved,
      expectedFutureIncomeCents: totalExpectedIncome,
      availableToSpendCents: availableToSpend,
    );
  }
}

/// Immutable snapshot representing current financial truth.
class FinancialSnapshot {
  final int openingBalanceCents;
  final int totalIncomeCents;
  final int totalExpensesCents;
  final int recordedBalanceCents;
  final int unpaidCommitmentsCents;
  final int savingsReservedCents;
  final int expectedFutureIncomeCents;
  final int availableToSpendCents;

  const FinancialSnapshot({
    required this.openingBalanceCents,
    required this.totalIncomeCents,
    required this.totalExpensesCents,
    required this.recordedBalanceCents,
    required this.unpaidCommitmentsCents,
    required this.savingsReservedCents,
    required this.expectedFutureIncomeCents,
    required this.availableToSpendCents,
  });

  String get formattedBalance =>
      FinancialEngine.formatBirr(recordedBalanceCents);
  String get formattedAvailable =>
      FinancialEngine.formatBirr(availableToSpendCents);
  String get formattedIncome => FinancialEngine.formatBirr(totalIncomeCents);
  String get formattedExpenses =>
      FinancialEngine.formatBirr(totalExpensesCents);
  String get formattedCommitments =>
      FinancialEngine.formatBirr(unpaidCommitmentsCents);
}
