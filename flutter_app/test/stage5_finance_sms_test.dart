import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/finance/finance_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/repositories/finance_repository.dart';
import 'package:personal_management_app/domain/finance/finance_contracts.dart';

import 'support/sqlite_test_helper.dart';

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Stage 5 — Finance SMS Draft Foundation & Provider Parsers', () {
    test(
      '1. Pure Dart parsers cover BOA (including POS lock), CBE fee breakdown, and Telebirr UTC+3',
      () {
        final receivedAt = DateTime.utc(2026, 11, 22, 10, 0, 0);
        final accounts = <AccountModel>[
          AccountModel(
            id: 'acc-cbe',
            name: 'CBE Checking 5678',
            type: AccountType.asset,
            subType: AccountSubType.bank,
            openingBalanceCents: 2000000,
          ),
          AccountModel(
            id: 'acc-boa',
            name: 'BOA Savings 4321',
            type: AccountType.asset,
            subType: AccountSubType.bank,
            openingBalanceCents: 1500000,
          ),
          AccountModel(
            id: 'acc-tb',
            name: 'Telebirr Wallet',
            type: AccountType.asset,
            subType: AccountSubType.mobileMoney,
            openingBalanceCents: 500000,
          ),
        ];

        // BOA debit
        final boaDebit = FinanceSmsParsers.parseFinancialSmsMessage(
          'Your account 1****4321 was debited with ETB 450.50 for Coffee Shop. Available Balance: ETB 14,549.50. https://cs.bankofabyssinia.com/slip/?trx=FT26326BOA01',
          receivedAtUtc: receivedAt,
          accounts: accounts,
        );
        expect(boaDebit.isIgnoredNonTransactional, isFalse);
        expect(boaDebit.draft?.provider, SmsProvider.boa);
        expect(boaDebit.draft?.status, SmsDraftStatus.needsReview);
        expect(boaDebit.draft?.suggestedType, SmsSuggestedTransactionType.expense);
        expect(boaDebit.draft?.principalCents, 45050);
        expect(boaDebit.draft?.reportedBalanceCents, 1454950);
        expect(boaDebit.draft?.transactionReference, 'FT26326BOA01');
        expect(boaDebit.draft?.suggestedAccountId, 'acc-boa');

        // BOA POS lock MUST NOT become an expense draft
        final boaPosLock = FinanceSmsParsers.parseFinancialSmsMessage(
          'ETB 240.00 is Locked From Your Account 1****4321 Due to POS TRANSACTION at KALDIS COFFEE. Your Available Balance is ETB 14,309.50.',
          receivedAtUtc: receivedAt,
          accounts: accounts,
        );
        expect(boaPosLock.isIgnoredNonTransactional, isFalse);
        expect(boaPosLock.draft?.status, SmsDraftStatus.unrecognized);
        expect(boaPosLock.draft?.isNonLedgerNotice, isTrue);
        expect(boaPosLock.draft?.suggestedType, SmsSuggestedTransactionType.unknown);
        expect(boaPosLock.draft?.canApprove, isFalse);

        // BOA security/promo ignored
        final boaPromo = FinanceSmsParsers.parseFinancialSmsMessage(
          'Bank of Abyssinia security alert: Never share your PIN or password with anyone.',
          receivedAtUtc: receivedAt,
          accounts: accounts,
        );
        expect(boaPromo.isIgnoredNonTransactional, isTrue);

        // CBE outgoing with principal vs fees separation
        final cbeOut = FinanceSmsParsers.parseFinancialSmsMessage(
          'You have successfully transferred ETB 2,000.00 from account 1****5678 to account 1****9900 (Dawit Bekele). Service charge of ETB 0.87 and VAT(15%) of ETB 0.13 and Disaster Recovery(5%) of ETB 0.20 with total of ETB 2,001.20. Your current balance is ETB 17,998.80. https://apps.cbe.com.et:100/?id=FT26326CBE01',
          receivedAtUtc: receivedAt,
          accounts: accounts,
        );
        expect(cbeOut.draft?.provider, SmsProvider.cbe);
        expect(cbeOut.draft?.principalCents, 200000);
        expect(cbeOut.draft?.serviceFeeCents, 87);
        expect(cbeOut.draft?.vatCents, 13);
        expect(cbeOut.draft?.otherChargesCents, 20);
        expect(cbeOut.draft?.totalFeesCents, 120);
        expect(cbeOut.draft?.totalAmountCents, 200120);
        expect(cbeOut.draft?.hasAmountMismatch, isFalse);
        expect(cbeOut.draft?.suggestedAccountId, 'acc-cbe');

        // Telebirr outgoing with Addis Ababa UTC+3 datetime & 15% VAT
        final tbOut = FinanceSmsParsers.parseFinancialSmsMessage(
          'You have paid ETB 500.00 to Ethio Telecom (251911223344) on 22/11/2026 01:30:00. Your transaction number is TB26326XYZ9. Service fee is ETB 2.00 and 15% VAT on service fee is ETB 0.30 with total paid is ETB 502.30. Your current E-Money Account balance is ETB 4,497.70.',
          receivedAtUtc: receivedAt,
          accounts: accounts,
        );
        expect(tbOut.draft?.provider, SmsProvider.telebirr);
        expect(tbOut.draft?.principalCents, 50000);
        expect(tbOut.draft?.totalFeesCents, 230);
        expect(tbOut.draft?.totalAmountCents, 50230);
        expect(tbOut.draft?.transactionDateIso, '2026-11-22');
        expect(
          tbOut.draft?.transactionTimestampUtc,
          DateTime.utc(2026, 11, 21, 22, 30, 0),
        );
        expect(tbOut.draft?.counterpartyHint, '****3344');
        expect(tbOut.draft?.suggestedAccountId, 'acc-tb');

        // Telebirr failed PIN & generic failed PIN messages ignored
        final tbFailedPin = FinanceSmsParsers.parseFinancialSmsMessage(
          'Telebirr: Your PIN is incorrect. Please check and try again.',
          receivedAtUtc: receivedAt,
          accounts: accounts,
        );
        expect(tbFailedPin.isIgnoredNonTransactional, isTrue);

        final genericFailedPin = FinanceSmsParsers.parseFinancialSmsMessage(
          'Your PIN is incorrect. Remaining attempts: 2.',
          receivedAtUtc: receivedAt,
          accounts: accounts,
        );
        expect(genericFailedPin.isIgnoredNonTransactional, isTrue);
      },
    );

    test(
      '2. End-to-end Drift & FinanceController lifecycle: zero auto-posting, deduplication, explicit approval, and privacy boundary',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        final repo = DriftFinanceRepository(db);
        final controller = FinanceController(repository: repo);
        await controller.loadAll();

        addTearDown(() async {
          controller.dispose();
          await db.close();
        });

        await controller.completeSetup([
          AccountModel(
            id: 'acc-cbe',
            name: 'CBE Checking 5678',
            type: AccountType.asset,
            subType: AccountSubType.bank,
            openingBalanceCents: 2000000,
            openingBalanceDate: '2026-11-01',
          ),
          AccountModel(
            id: 'acc-vault',
            name: 'Savings Vault',
            type: AccountType.asset,
            subType: AccountSubType.savingsVault,
            openingBalanceCents: 100000,
            openingBalanceDate: '2026-11-01',
          ),
        ]);

        final beforeLiquid = controller.state.liquidCashCents;
        final beforeEntries = controller.state.journalEntries.length;
        final beforePostings = controller.state.postings.length;

        final batchResult = await controller.importSmsMessages(
          rawMessages: <String>[
            'You have successfully transferred ETB 2,000.00 from account 1****5678 to account 1****9900 (Dawit). Service charge of ETB 0.87 and VAT(15%) of ETB 0.13 and Disaster Recovery(5%) of ETB 0.20 with total of ETB 2,001.20. Your current balance is ETB 17,998.80. https://apps.cbe.com.et:100/?id=FT26326HOST1',
            'ETB 240.00 is Locked From Your Account 1****5678 Due to POS TRANSACTION at KALDIS. Your Available Balance is ETB 19,760.00.',
            'Your account 1****5678 was credited with ETB 1,000.00 by Abebe. Available Balance: ETB 21,000.00.',
          ],
          receivedAtUtc: DateTime.utc(2026, 11, 22, 9, 0, 0),
        );

        expect(batchResult, isNotNull);
        expect(batchResult!.importedCount, 2);
        expect(batchResult.unrecognizedCount, 1);
        expect(controller.state.pendingSmsDraftCount, 2);

        // Core invariant: importing SMS drafts NEVER mutates ledger or balances
        expect(controller.state.liquidCashCents, beforeLiquid);
        expect(controller.state.journalEntries.length, beforeEntries);
        expect(controller.state.postings.length, beforePostings);

        // Dismiss credit draft and verify re-import suppresses duplicate
        final creditDraft = controller.state.smsDrafts
            .firstWhere((d) => d.direction == SmsDirection.incoming);
        await controller.dismissSmsDraft(creditDraft.id);
        expect(controller.state.pendingSmsDraftCount, 1);

        final reimport = await controller.importSmsMessages(
          rawMessages: <String>[
            'Your account 1****5678 was credited with ETB 1,000.00 by Abebe. Available Balance: ETB 21,000.00.',
          ],
          receivedAtUtc: DateTime.utc(2026, 11, 22, 10, 0, 0),
        );
        expect(reimport!.importedCount, 0);
        expect(reimport.duplicateCount, 1);

        // Attempting to approve POS lock must fail without mutating ledger
        final posDraft = controller.state.smsDrafts
            .firstWhere((d) => d.isNonLedgerNotice);
        final posRejected = await controller.approveSmsDraft(
          draftId: posDraft.id,
          finalType: SmsSuggestedTransactionType.expense,
          accountId: 'acc-cbe',
          categoryId: 'cat-other-exp',
          occurrenceDate: CalendarDate(year: 2026, month: 11, day: 22),
          description: 'POS Hold Attempt',
        );
        expect(posRejected, isNull);
        expect(controller.state.liquidCashCents, beforeLiquid);

        // Explicitly approve CBE outgoing draft as Expense -> deducts 2,001.20 ETB cleanly
        final cbeDraft = controller.state.smsDrafts
            .firstWhere((d) => d.provider == SmsProvider.cbe);
        final approvedEntry = await controller.approveSmsDraft(
          draftId: cbeDraft.id,
          finalType: SmsSuggestedTransactionType.expense,
          accountId: 'acc-cbe',
          categoryId: 'cat-other-exp',
          occurrenceDate: CalendarDate(year: 2026, month: 11, day: 22),
          description: 'CBE Payment to Dawit',
        );
        expect(approvedEntry, isNotNull);
        expect(controller.state.liquidCashCents, beforeLiquid - 200120);
        expect(controller.state.pendingSmsDraftCount, 0);

        // Verify fee separation onto cat-fees & zero rawSmsText leakage
        final entryPostings = controller.state.postings
            .where((p) => p.entryId == approvedEntry!.id)
            .toList();
        expect(
          entryPostings
              .firstWhere((p) => p.categoryId == 'cat-other-exp')
              .amountCents,
          200000,
        );
        final feePosting =
            entryPostings.firstWhere((p) => p.categoryId == 'cat-fees');
        expect(feePosting.amountCents, 120);
        expect(feePosting.note, contains('Service fee: ETB 0.87'));
        expect(feePosting.note, contains('VAT: ETB 0.13'));
        expect(feePosting.note, contains('Disaster Recovery / Other: ETB 0.20'));
        expect(
          approvedEntry!.description.contains('Service charge of ETB'),
          isFalse,
        );

        // Two distinct transactions with identical amounts (500 ETB) are both retained
        final sameAmtBatch = await controller.importSmsMessages(
          rawMessages: <String>[
            'You have paid ETB 500.00 to Cafe One (251911000001) on 22/11/2026 09:00:00. Your transaction number is TB500A. Your current E-Money Account balance is ETB 4,500.00.',
            'You have paid ETB 500.00 to Cafe One (251911000001) on 22/11/2026 14:00:00. Your transaction number is TB500B. Your current E-Money Account balance is ETB 4,000.00.',
          ],
          receivedAtUtc: DateTime.utc(2026, 11, 22, 14, 5, 0),
        );
        expect(sameAmtBatch?.importedCount, 2);
        expect(sameAmtBatch?.duplicateCount, 0);

        // Export Finance-only JSON must NOT include smsDrafts or raw SMS text
        final exportedRaw = await controller.exportFinanceOnlyJson();
        final exportedMap = jsonDecode(exportedRaw) as Map<String, dynamic>;
        expect(exportedMap.containsKey('smsDrafts'), isFalse);
        expect(exportedRaw.contains('Service charge of ETB 0.87'), isFalse);
      },
    );
  });
}
