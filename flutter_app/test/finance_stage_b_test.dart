import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/database_persistence_coordinator.dart';
import 'package:personal_management_app/data/repositories/finance_repository.dart';

import 'support/sqlite_test_helper.dart';

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Finance Stage B (F1) — Ledger Mutation Guards, Vault Sync & Refunds',
      () {
    late AppDatabase db;
    late DriftFinanceRepository repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.ensureInitialized();
      repo = DriftFinanceRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> seedEtbSetup() async {
      await repo.completeFinanceSetup([
        AccountModel(
          id: 'acc-bank',
          name: 'CBE Bank',
          type: AccountType.asset,
          subType: AccountSubType.bank,
          openingBalanceCents: 1000000,
          openingBalanceDate: '2026-11-01',
        ),
        AccountModel(
          id: 'acc-cash',
          name: 'Cash Wallet',
          type: AccountType.asset,
          subType: AccountSubType.cash,
          openingBalanceCents: 200000,
          openingBalanceDate: '2026-11-01',
        ),
        AccountModel(
          id: 'acc-vault',
          name: 'Emergency Vault',
          type: AccountType.asset,
          subType: AccountSubType.savingsVault,
          openingBalanceCents: 25000,
          openingBalanceDate: '2026-11-01',
        ),
        AccountModel(
          id: 'acc-card',
          name: 'Abyssinia Card',
          type: AccountType.liability,
          subType: AccountSubType.creditCard,
          openingBalanceCents: 40000,
          openingBalanceDate: '2026-11-01',
        ),
      ]);
    }

    test(
      '1. Prevents voiding debt-origin entries with active settlements/write-offs and reconciles debts across void/unvoid',
      () async {
        await seedEtbSetup();
        final party = await repo.createParty(
          PartyModel(id: 'party-1', name: 'Abebe'),
        );

        final lendBuilt = DoubleEntryEngine.buildLendMoney(
          entryId: 'entry-lend-1',
          debtId: 'debt-1',
          partyId: party.id,
          sourceAssetAccountId: 'acc-bank',
          receivableAccountId: SystemControlAccounts.receivable,
          amountCents: 100000,
          date: '2026-11-05',
          description: 'Loan to Abebe',
        );
        final debt = await repo.recordDebtWithEntry(
          entry: lendBuilt['entry'] as JournalEntryModel,
          postings: lendBuilt['postings'] as List<PostingModel>,
          debt: lendBuilt['debt'] as DebtModel,
        );

        final settleBuilt = DoubleEntryEngine.buildDebtSettlement(
          settlementEntryId: 'entry-settle-1',
          debt: debt,
          settlementAssetAccountId: 'acc-bank',
          debtAccountId: SystemControlAccounts.receivable,
          allocatedPrincipalCents: 40000,
          settlementDate: '2026-11-06',
          description: 'Partial repayment',
        );
        await repo.recordSettlement(
          allocation: settleBuilt['allocation'] as SettlementAllocationModel,
          settlementEntry: settleBuilt['entry'] as JournalEntryModel,
          settlementPostings: settleBuilt['postings'] as List<PostingModel>,
          updatedDebt: settleBuilt['updatedDebt'] as DebtModel,
        );

        // Cannot void debt origin while active settlement exists
        await expectLater(
          repo.voidJournalEntry(
            entryId: 'entry-lend-1',
            voidReason: 'Mistake',
          ),
          throwsA(isA<DoubleEntryValidationError>()),
        );

        // Void settlement first -> debt becomes active with full 100,000
        await repo.voidJournalEntry(
          entryId: 'entry-settle-1',
          voidReason: 'Reverted payment',
        );
        var currentDebt = (await repo.getDebts()).single;
        expect(currentDebt.outstandingCents, 100000);
        expect(currentDebt.status, DebtStatus.active);

        // Now void debt origin -> debt becomes voided
        final voidedOrigin = await repo.voidDebtOrigin(
          debtId: debt.id,
          reason: 'Cancelled loan',
        );
        expect(voidedOrigin.status, DebtStatus.voided);
        expect(voidedOrigin.outstandingCents, 0);

        // Cannot unvoid settlement while debt origin is voided
        await expectLater(
          repo.unvoidJournalEntry('entry-settle-1'),
          throwsA(isA<DoubleEntryValidationError>()),
        );

        // Unvoid debt origin -> write off -> settlement unvoid & origin void both blocked
        await repo.unvoidJournalEntry('entry-lend-1');
        currentDebt = (await repo.getDebts()).single;
        expect(currentDebt.status, DebtStatus.active);
        expect(currentDebt.outstandingCents, 100000);

        await repo.writeOffDebt(
          debtId: debt.id,
          reason: 'Uncollectible',
          date: CalendarDate(year: 2026, month: 11, day: 10),
        );
        await expectLater(
          repo.unvoidJournalEntry('entry-settle-1'),
          throwsA(isA<DoubleEntryValidationError>()),
        );
        await expectLater(
          repo.voidJournalEntry(
            entryId: 'entry-lend-1',
            voidReason: 'Try void under writeoff',
          ),
          throwsA(isA<DoubleEntryValidationError>()),
        );
      },
    );

    test(
      '2. Blocks unsafe corrections, commitment over-settlement unvoids, and preserves feeCategoryId, movementDate, and dual-write rows',
      () async {
        await seedEtbSetup();
        final categories = await repo.getCategories();
        final expCat = categories.firstWhere((c) => c.type == 'expense');
        final party = await repo.createParty(
          PartyModel(id: 'party-2', name: 'Selam'),
        );

        // Split expense cannot be corrected
        final splitEntry = await repo.recordSplitExpense(
          paidAccountId: 'acc-bank',
          myCategoryId: expCat.id,
          myShareCents: 15000,
          theirShareCents: 15000,
          partyId: party.id,
          date: CalendarDate(year: 2026, month: 11, day: 5),
          description: 'Team lunch',
        );
        final allEntries = await repo.getJournalEntries(includeVoided: true);
        final allPostings = await repo.getPostings();
        final accounts =
            await repo.getAccounts(includeArchived: true, includeSystem: true);
        final debts = await repo.getDebts();
        final allocations = await repo.getSettlementAllocations();

        final splitCheck = DoubleEntryEngine.canCorrectEntry(
          entry: splitEntry,
          entries: allEntries,
          postings: allPostings,
          accounts: accounts,
          debts: debts,
          allocations: allocations,
        );
        expect(splitCheck.ok, isFalse);

        // Commitment settlement cannot be corrected, and cannot unvoid if it would over-settle
        final commitment = await repo.addCommitment(
          CommitmentModel(
            id: 'com-1',
            title: 'Internet',
            amountCents: 10000,
            dueDate: CalendarDate(year: 2026, month: 11, day: 10),
            direction: CommitmentDirection.outflow,
            linkedAccountId: 'acc-bank',
            categoryId: expCat.id,
          ),
        );
        final cs1 = await repo.recordCommitmentSettlement(
          commitmentId: commitment.id,
          accountId: 'acc-bank',
          amountCents: 6000,
          settledDate: CalendarDate(year: 2026, month: 11, day: 8),
        );
        final cmCheck = DoubleEntryEngine.canCorrectEntry(
          entry: (await repo.getJournalEntries())
              .firstWhere((e) => e.id == cs1.entryId),
          entries: await repo.getJournalEntries(includeVoided: true),
          postings: await repo.getPostings(),
          accounts: accounts,
          debts: debts,
          allocations: allocations,
          commitmentSettlements: await repo.getCommitmentSettlements(),
        );
        expect(cmCheck.ok, isFalse);

        await repo.voidCommitmentSettlement(
          settlementId: cs1.id,
          reason: 'Retry payment',
        );
        await repo.recordCommitmentSettlement(
          commitmentId: commitment.id,
          accountId: 'acc-bank',
          amountCents: 10000,
          settledDate: CalendarDate(year: 2026, month: 11, day: 9),
        );
        await expectLater(
          repo.unvoidJournalEntry(cs1.entryId),
          throwsA(isA<DoubleEntryValidationError>()),
        );

        // Transfer correction via correctTransaction preserves transfer fee, feeCategoryId, and custom movementDate
        final feeEntry = await repo.recordAccountTransfer(
          fromAccountId: 'acc-bank',
          toAccountId: 'acc-cash',
          amountCents: 50000,
          transferFeeCents: 500,
          feeCategoryId: SystemControlAccounts.feeCategoryId,
          date: CalendarDate(year: 2026, month: 11, day: 5),
          description: 'ATM pull',
        );
        // Set distinct movementDate on the original transfer postings & attach a dual-write TransactionModel row
        await db.customStatement(
          "UPDATE postings_table SET account_movement_date = '2026-11-06' WHERE entry_id = ?;",
          [feeEntry.id],
        );
        // Direct expense dual-write consistency across correctJournalEntry, deleteTransaction, and unvoidJournalEntry
        final expTx = TransactionModel(
          id: 'tx-exp-dual',
          categoryId: expCat.id,
          categoryName: expCat.name,
          amountCents: 12000,
          type: 'expense',
          transactionDate: CalendarDate(year: 2026, month: 11, day: 4),
          accountId: 'acc-bank',
          payee: 'Tomoca',
          note: 'Coffee',
        );
        await repo.recordTransaction(expTx);

        // correctJournalEntry supersedes original FinancialTransactions row AND inserts replacement row
        final origExpEntry = (await repo.getJournalEntries())
            .firstWhere((e) => e.legacySourceTxId == 'tx-exp-dual');
        final replBuilt = DoubleEntryEngine.buildDirectExpense(
          entryId: 'entry-exp-corr-1',
          paidAccountId: 'acc-bank',
          categoryId: expCat.id,
          amountCents: 14000,
          date: '2026-11-04',
          movementDate: '2026-11-05',
          description: 'Tomoca — Coffee',
          note: 'Double shot',
        );
        final corrEntry = await repo.correctJournalEntry(
          originalEntryId: origExpEntry.id,
          replacementEntry: replBuilt['entry'] as JournalEntryModel,
          replacementPostings: replBuilt['postings'] as List<PostingModel>,
          correctionReason: 'Updated receipt',
        );
        final txsAfterCorr = await repo.getTransactions();
        final origTxAfter =
            txsAfterCorr.firstWhere((t) => t.id == 'tx-exp-dual');
        final newTxAfter =
            txsAfterCorr.firstWhere((t) => t.id == corrEntry.legacySourceTxId);
        expect(origTxAfter.isSuperseded, isTrue);
        expect(newTxAfter.isSuperseded, isFalse);
        expect(newTxAfter.amountCents, 14000);
        expect(newTxAfter.payee, 'Tomoca');

        // Preserved movementDate on direct expense posting
        final corrExpPostings = await repo.getPostings(entryId: corrEntry.id);
        final corrBankPosting =
            corrExpPostings.firstWhere((p) => p.accountId == 'acc-bank');
        expect(corrBankPosting.accountMovementDate, '2026-11-05');

        // deleteTransaction removes FinancialTransactions row and voids ledger entry;
        // unvoidJournalEntry recreates the dual-write mirror row cleanly
        await repo.deleteTransaction(newTxAfter.id);
        final entriesAfterDel =
            await repo.getJournalEntries(includeVoided: true);
        expect(
          entriesAfterDel.firstWhere((e) => e.id == corrEntry.id).isVoided,
          isTrue,
        );
        expect(
          (await repo.getTransactions()).any((t) => t.id == newTxAfter.id),
          isFalse,
        );
        await repo.unvoidJournalEntry(corrEntry.id);
        final txsAfterUnvoid = await repo.getTransactions();
        final restoredDual =
            txsAfterUnvoid.firstWhere((t) => t.id == newTxAfter.id);
        expect(restoredDual.isSuperseded, isFalse);
        expect(restoredDual.amountCents, 14000);

        // correctTransaction preserves fee & movementDate from linked ledger entry
        await db.customStatement(
          "UPDATE journal_entries_table SET legacy_source_tx_id = 'tx-xfer-dual-link' WHERE id = ?;",
          [feeEntry.id],
        );
        await repo.recordTransaction(
          TransactionModel(
            id: 'tx-xfer-dual-link',
            categoryId: expCat.id,
            categoryName: 'Transfer',
            amountCents: 50000,
            type: 'transfer',
            transactionDate: CalendarDate(year: 2026, month: 11, day: 5),
            accountId: 'acc-bank',
            destinationAccountId: 'acc-cash',
            note: 'ATM pull',
          ),
        );
        final corrXferTx = await repo.correctTransaction(
          originalId: 'tx-xfer-dual-link',
          newAmountCents: 55000,
          newCategoryId: expCat.id,
          newCategoryName: 'Transfer',
          correctionReason: 'Updated cash amount',
        );
        final corrXferEntry = (await repo.getJournalEntries())
            .firstWhere((e) => e.legacySourceTxId == corrXferTx.id);
        final corrXferPostings =
            await repo.getPostings(entryId: corrXferEntry.id);
        final feePosting = corrXferPostings.firstWhere(
          (p) => p.accountId == SystemControlAccounts.expense,
        );
        final dstPosting = corrXferPostings.firstWhere(
          (p) => p.accountId == 'acc-cash',
        );
        expect(feePosting.amountCents, 500);
        expect(feePosting.categoryId, SystemControlAccounts.feeCategoryId);
        expect(dstPosting.accountMovementDate, '2026-11-06');
      },
    );

    test(
      '3. Vault SavingsGoals synchronize across deposits, withdrawals, voids, unvoids, opening edits, and block nonzero archiving',
      () async {
        await seedEtbSetup();
        var goal = await repo.createSavingsGoal(
          SavingsGoalModel(
            id: 'goal-vault',
            title: 'Emergency Vault',
            targetCents: 100000,
            currentAllocatedCents: 0,
            linkedAccountId: 'acc-vault',
          ),
        );
        // Opening balance of acc-vault is 25,000
        expect(goal.currentAllocatedCents, 25000);
        expect(goal.status, SavingsGoalStatus.active);

        // Fund +75,000 -> 100,000 completed
        goal = await repo.fundSavingsGoal(
          goalId: goal.id,
          deltaCents: 75000,
          sourceAccountId: 'acc-bank',
          date: CalendarDate(year: 2026, month: 11, day: 5),
        );
        expect(goal.currentAllocatedCents, 100000);
        expect(goal.status, SavingsGoalStatus.completed);

        // Cannot archive vault goal or vault account while balance > 0
        await expectLater(
          repo.releaseAndArchiveSavingsGoal(goal.id),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          repo.updateSavingsGoal(
            goal.copyWith(status: SavingsGoalStatus.archived),
          ),
          throwsA(isA<DoubleEntryValidationError>()),
        );
        await expectLater(
          repo.archiveAccount('acc-vault'),
          throwsA(isA<DoubleEntryValidationError>()),
        );

        // Voiding transfer returns goal to active 25,000; unvoiding restores completed 100,000
        final fundEntries = (await repo.getJournalEntries())
            .where((e) => e.entryType == EntryType.transfer)
            .toList();
        await repo.voidJournalEntry(
          entryId: fundEntries.first.id,
          voidReason: 'Undo vault deposit',
        );
        var goals = await repo.getSavingsGoals();
        expect(goals.single.currentAllocatedCents, 25000);
        expect(goals.single.status, SavingsGoalStatus.active);

        await repo.unvoidJournalEntry(fundEntries.first.id);
        goals = await repo.getSavingsGoals();
        expect(goals.single.currentAllocatedCents, 100000);
        expect(goals.single.status, SavingsGoalStatus.completed);

        // Opening balance edit on vault synchronizes vault goal
        await repo.reviseOpeningBalance(
          accountId: 'acc-vault',
          newOpeningBalanceCents: 10000,
          reason: 'Reconcile vault opening',
        );
        goals = await repo.getSavingsGoals();
        expect(goals.single.currentAllocatedCents, 85000);
        expect(goals.single.status, SavingsGoalStatus.active);

        // Withdraw all 85,000 -> now archiving succeeds
        goal = await repo.fundSavingsGoal(
          goalId: goal.id,
          deltaCents: -85000,
          sourceAccountId: 'acc-bank',
          date: CalendarDate(year: 2026, month: 11, day: 6),
        );
        expect(goal.currentAllocatedCents, 0);
        final archivedGoal = await repo.releaseAndArchiveSavingsGoal(goal.id);
        expect(archivedGoal.status, SavingsGoalStatus.archived);
        await repo.archiveAccount('acc-vault');
      },
    );

    test(
      '4. Expense refund supports active cash/bank/card destinations, caps totals, blocks voiding refunded expenses, and syncs on snapshot restore',
      () async {
        await seedEtbSetup();
        final categories = await repo.getCategories();
        final expCat = categories.firstWhere((c) => c.type == 'expense');

        final expEntry = await repo.recordDirectExpense(
          accountId: 'acc-bank',
          categoryId: expCat.id,
          amountCents: 50000,
          date: CalendarDate(year: 2026, month: 11, day: 5),
          description: 'Electronics',
        );

        // Vault disallowed as refund destination
        await expectLater(
          repo.recordExpenseRefund(
            originalEntryId: expEntry.id,
            refundAccountId: 'acc-vault',
            refundCents: 10000,
            date: CalendarDate(year: 2026, month: 11, day: 6),
          ),
          throwsA(isA<DoubleEntryValidationError>()),
        );

        // Credit card liability allowed as refund destination
        final r1 = await repo.recordExpenseRefund(
          originalEntryId: expEntry.id,
          refundAccountId: 'acc-card',
          refundCents: 20000,
          date: CalendarDate(year: 2026, month: 11, day: 6),
        );

        // Original expense cannot be voided while refund is active
        await expectLater(
          repo.voidJournalEntry(
            entryId: expEntry.id,
            voidReason: 'Cannot void refunded',
          ),
          throwsA(isA<DoubleEntryValidationError>()),
        );

        // Second refund up to remaining 30,000 succeeds; over-refund fails
        await repo.recordExpenseRefund(
          originalEntryId: expEntry.id,
          refundAccountId: 'acc-bank',
          refundCents: 30000,
          date: CalendarDate(year: 2026, month: 11, day: 7),
        );
        await expectLater(
          repo.recordExpenseRefund(
            originalEntryId: expEntry.id,
            refundAccountId: 'acc-bank',
            refundCents: 1,
            date: CalendarDate(year: 2026, month: 11, day: 8),
          ),
          throwsA(isA<DoubleEntryValidationError>()),
        );

        // Voiding first refund restores 20,000 refundable headroom
        await repo.voidJournalEntry(
          entryId: r1.id,
          voidReason: 'Reversed refund',
        );
        final summary = DoubleEntryEngine.getExpenseRefundSummary(
          originalEntryId: expEntry.id,
          entries: await repo.getJournalEntries(includeVoided: true),
          postings: await repo.getPostings(),
          accounts: await repo.getAccounts(
            includeArchived: true,
            includeSystem: true,
          ),
          debts: await repo.getDebts(),
          allocations: await repo.getSettlementAllocations(),
        );
        expect(summary.remainingRefundableCents, 20000);

        // Snapshot restore synchronizes vault-linked SavingsGoals & debts
        final db2 = AppDatabase(NativeDatabase.memory());
        addTearDown(db2.close);
        await db2.ensureInitialized();
        final coordinator = DatabasePersistenceCoordinator(db2);
        await coordinator.importSnapshotDetailed({
          'schemaVersion': 9,
          'isFinanceSetupCompleted': true,
          'openingBalanceCents': 80000,
          'categories': [
            {
              'id': 'cat-food',
              'name': 'Food',
              'type': 'expense',
              'sortOrder': 1,
            },
          ],
          'accounts': [
            {
              'id': 'acc-vault-r',
              'name': 'Vault Restore',
              'type': 'asset',
              'subType': 'savings_vault',
              'isSystem': false,
              'currencyCode': 'ETB',
              'openingBalanceCents': 80000,
              'openingBalanceDate': '2026-11-01',
              'isArchived': false,
              'createdAt': '2026-11-01T08:00:00.000Z',
            },
          ],
          'parties': [],
          'goals': [],
          'projects': [],
          'milestones': [],
          'tasks': [],
          'notes': [],
          'inboxItems': [],
          'calendarEvents': [],
          'transactions': [],
          'journalEntries': [],
          'postings': [],
          'debts': [],
          'settlementAllocations': [],
          'commitments': [],
          'commitmentSettlements': [],
          'savingsGoals': [
            {
              'id': 'goal-vault-r',
              'title': 'Vault Restore Goal',
              'targetCents': 80000,
              'currentAllocatedCents': 10000,
              'linkedAccountId': 'acc-vault-r',
              'status': 'active',
            },
          ],
          'budgets': [],
          'recurringRules': [],
        });
        final repo2 = DriftFinanceRepository(db2);
        final restoredGoals = await repo2.getSavingsGoals();
        expect(restoredGoals.single.currentAllocatedCents, 80000);
        expect(restoredGoals.single.status, SavingsGoalStatus.completed);
      },
    );
  });
}
