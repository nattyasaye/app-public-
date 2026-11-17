import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/domain/finance/financial_engine.dart';

void main() {
  group('FinancialEngine Integer Calculation Tests', () {
    test('Calculates recorded balance accurately without floating point error',
        () {
      // Opening balance: 10,000.00 ETB = 1,000,000 cents
      const opening = 1000000;
      // Income received: 25,000.50 ETB = 2,500,050 cents
      final income = [2500050];
      // Expenses: 3,450.25 ETB + 1,200.00 ETB = 465,025 cents
      final expenses = [345025, 120000];

      final recorded = FinancialEngine.calculateRecordedBalance(
        openingBalanceCents: opening,
        receivedIncomeCents: income,
        recordedExpenseCents: expenses,
      );

      // Expected: 1,000,000 + 2,500,050 - 465,025 = 3,035,025 cents (30,350.25 ETB)
      expect(recorded, 3035025);
      expect(FinancialEngine.formatBirr(recorded), '30350.25 ETB');
    });

    test('Computes Available-to-Spend subtracting commitments and savings', () {
      final snapshot = FinancialEngine.computeSnapshot(
        openingBalanceCents: 500000, // 5,000.00 ETB
        receivedIncomeCents: [2000000], // 20,000.00 ETB
        recordedExpenseCents: [800000], // 8,000.00 ETB
        // Unpaid commitments due this month: Rent (4,000.00) + Internet (1,000.00) = 5,000.00 ETB
        unpaidCommitmentsInPeriodCents: [400000, 100000],
        // Savings reserve allocation: 3,000.00 ETB
        savingsAllocationsInPeriodCents: [300000],
        // Expected future income (must NOT boost balance): 15,000.00 ETB
        expectedFutureIncomeCents: [1500000],
      );

      // Recorded balance: 5,000 + 20,000 - 8,000 = 17,000.00 ETB (1,700,000 cents)
      expect(snapshot.recordedBalanceCents, 1700000);

      // Available to spend: 17,000 - 5,000 (commitments) - 3,000 (savings) = 9,000.00 ETB (900,000 cents)
      expect(snapshot.availableToSpendCents, 900000);

      // Expected future income is tracked separately but does not inflate recorded balance
      expect(snapshot.expectedFutureIncomeCents, 1500000);
      expect(snapshot.formattedAvailable, '9000.00 ETB');
    });

    test('String parsing handles fractional cents and negative values safely',
        () {
      expect(FinancialEngine.parseToCents('1250.50'), 125050);
      expect(FinancialEngine.parseToCents('1250.5'), 125050);
      expect(FinancialEngine.parseToCents('1250'), 125000);
      expect(FinancialEngine.parseToCents('-450.75'), -45075);
    });
  });
}
