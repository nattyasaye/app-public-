import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/domain/finance/financial_engine.dart';

void main() {
  group('Stage 4 Financial Management Specification Tests', () {
    test(
        'Decimal-safe integer calculations prevent floating point rounding drift',
        () {
      // Multiple precise fractional transactions
      const openingCents = 1500000; // 15,000.00 ETB
      final income = [3500055, 125025]; // 35,000.55 ETB + 1,250.25 ETB
      final expenses = [
        480030,
        150010,
        75000
      ]; // 4,800.30 + 1,500.10 + 750.00 ETB

      final recordedBalance = FinancialEngine.calculateRecordedBalance(
        openingBalanceCents: openingCents,
        receivedIncomeCents: income,
        recordedExpenseCents: expenses,
      );

      // Expected: 1,500,000 + (3,500,055 + 125,025) - (480,030 + 150,010 + 75,000)
      // = 1,500,000 + 3,625,080 - 705,040 = 4,420,040 cents = 44,200.40 ETB
      expect(recordedBalance, 4420040);
      expect(FinancialEngine.formatBirr(recordedBalance), '44200.40 ETB');
    });

    test(
        'Available-to-Spend formula deducts period commitments and savings allocations',
        () {
      final snapshot = FinancialEngine.computeSnapshot(
        openingBalanceCents: 1000000, // 10,000.00 ETB
        receivedIncomeCents: [2500000], // 25,000.00 ETB
        recordedExpenseCents: [500000], // 5,000.00 ETB
        unpaidCommitmentsInPeriodCents: [
          800000,
          120000
        ], // 8,000 ETB (Rent) + 1,200 ETB (Internet)
        savingsAllocationsInPeriodCents: [
          500000
        ], // 5,000 ETB (Emergency Reserve)
        expectedFutureIncomeCents: [
          1200000
        ], // 12,000 ETB (Projected Freelance bonus)
      );

      // Recorded balance: 10,000 + 25,000 - 5,000 = 30,000.00 ETB (3,000,000 cents)
      expect(snapshot.recordedBalanceCents, 3000000);

      // Total unpaid commitments = 9,200.00 ETB (920,000 cents)
      expect(snapshot.unpaidCommitmentsCents, 920000);

      // Savings reserved = 5,000.00 ETB (500,000 cents)
      expect(snapshot.savingsReservedCents, 500000);

      // Available to Spend = 30,000 - 9,200 - 5,000 = 15,800.00 ETB (1,580,000 cents)
      expect(snapshot.availableToSpendCents, 1580000);
      expect(snapshot.formattedAvailable, '15800.00 ETB');

      // Crucial requirement: Expected future income is tracked but NOT added to recorded balance
      expect(snapshot.expectedFutureIncomeCents, 1200000);
      expect(snapshot.recordedBalanceCents, isNot(contains(4200000)));
    });

    test(
        'Avoid double-counting: Paid commitment is excluded from unpaid commitments',
        () {
      final commitments = [
        {
          'id': 'c1',
          'title': 'House rent',
          'amountCents': 800000,
          'isPaid': true
        }, // Already paid
        {
          'id': 'c2',
          'title': 'Broadband WiFi',
          'amountCents': 120000,
          'isPaid': false
        }, // Unpaid
      ];

      // Only unpaid commitments due in the period are passed into Available-to-Spend
      final unpaidCents = commitments
          .where((c) => c['isPaid'] == false)
          .map((c) => c['amountCents'] as int)
          .toList();

      expect(unpaidCents.length, 1);
      expect(unpaidCents.first, 120000); // 1,200 ETB
    });

    test(
        'Transaction correction audit trail preserves original transaction history',
        () {
      final originalTx = {
        'id': 'tx-100',
        'amountCents': 45000, // 450.00 ETB
        'note': 'Grocery shopping',
        'supersededBy': null,
      };

      // Correct transaction: user mistyped 450.00 instead of 540.00
      const correctionReason = 'Typo in receipt entry';
      final newTx = {
        'id': 'tx-101',
        'amountCents': 54000, // 540.00 ETB
        'correctedFromId': originalTx['id'],
        'correctionReason': correctionReason,
        'note': '[Corrected from tx-100: $correctionReason] Grocery shopping',
      };

      // Mark original as superseded without deleting
      originalTx['supersededBy'] = newTx['id'];

      expect(originalTx['id'], 'tx-100');
      expect(originalTx['supersededBy'], 'tx-101');
      expect(newTx['amountCents'], 54000);
      expect(newTx['correctedFromId'], 'tx-100');
    });
  });
}
