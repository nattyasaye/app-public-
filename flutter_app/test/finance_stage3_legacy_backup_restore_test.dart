import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/finance/finance_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/app_settings_policy.dart';
import 'package:personal_management_app/data/database/database_persistence_coordinator.dart';
import 'package:personal_management_app/data/repositories/finance_repository.dart';
import 'package:personal_management_app/services/backup/encryption_backup_service.dart';
import 'package:personal_management_app/ui/screens/finance/finance_overview_tab.dart';
import 'package:personal_management_app/ui/screens/finance/finance_transactions_tab.dart';

import 'support/sqlite_test_helper.dart';

Future<void> _seedMixedCurrencyDatabase(
  AppDatabase db,
  DriftFinanceRepository repo,
  FinanceController controller,
) async {
  await controller.completeSetup([
    AccountModel(
      id: 'acc-etb-cbe',
      name: 'CBE Checking ETB',
      type: AccountType.asset,
      subType: AccountSubType.bank,
      currencyCode: 'ETB',
      openingBalanceCents: 250000, // 2,500.00 ETB
      openingBalanceDate: '2026-11-01',
    ),
    AccountModel(
      id: 'acc-etb-vault',
      name: 'ETB Vault',
      type: AccountType.asset,
      subType: AccountSubType.savingsVault,
      currencyCode: 'ETB',
      openingBalanceCents: 100000, // 1,000.00 ETB
      openingBalanceDate: '2026-11-01',
    ),
  ]);

  // Ordinary ETB income + expense
  await controller.recordDirectIncome(
    accountId: 'acc-etb-cbe',
    categoryId: 'cat-salary',
    amountCents: 80000,
    date: CalendarDate(year: 2026, month: 11, day: 10),
    description: 'November ETB Stipend',
  );
  await controller.recordDirectExpense(
    accountId: 'acc-etb-cbe',
    categoryId: 'cat-food',
    amountCents: 30000,
    date: CalendarDate(year: 2026, month: 11, day: 11),
    description: 'ETB Groceries',
  );
  // Net ETB cash: 250,000 + 80,000 - 30,000 = 300,000 CBE + 100,000 Vault

  final legacyCreatedAt = DateTime.utc(2026, 10, 15, 9, 0);

  // Historical USD bank, EUR cash, and unclassified ("") accounts
  await db.into(db.accountsTable).insert(
        AccountsTableCompanion.insert(
          id: 'acc-usd-bank',
          name: 'USD Travel Account',
          type: 'asset',
          subType: const Value('bank'),
          currencyCode: const Value('USD'),
          openingBalanceCents: const Value(100000),
          openingBalanceDate: const Value('2026-10-01'),
          createdAt: legacyCreatedAt,
        ),
      );
  await db.into(db.accountsTable).insert(
        AccountsTableCompanion.insert(
          id: 'acc-eur-cash',
          name: 'EUR Envelope',
          type: 'asset',
          subType: const Value('cash'),
          currencyCode: const Value('EUR'),
          openingBalanceCents: const Value(60000),
          openingBalanceDate: const Value('2026-10-01'),
          createdAt: legacyCreatedAt,
        ),
      );
  await db.into(db.accountsTable).insert(
        AccountsTableCompanion.insert(
          id: 'acc-unclassified',
          name: 'Old Unclassified Pouch',
          type: 'asset',
          subType: const Value('cash'),
          currencyCode: const Value(''),
          openingBalanceCents: const Value(50000),
          openingBalanceDate: const Value('2026-10-01'),
          createdAt: legacyCreatedAt,
        ),
      );

  // Opening balance entries for historical non-ETB & unclassified accounts
  for (final openSpec in const <({
    String entryId,
    String accountId,
    int amountCents,
    String label,
  })>[
    (
      entryId: 'je-open-usd',
      accountId: 'acc-usd-bank',
      amountCents: 100000,
      label: 'Opening Balance: USD Travel Account',
    ),
    (
      entryId: 'je-open-eur',
      accountId: 'acc-eur-cash',
      amountCents: 60000,
      label: 'Opening Balance: EUR Envelope',
    ),
    (
      entryId: 'je-open-unclassified',
      accountId: 'acc-unclassified',
      amountCents: 50000,
      label: 'Opening Balance: Old Unclassified Pouch',
    ),
  ]) {
    await db.into(db.journalEntriesTable).insert(
          JournalEntriesTableCompanion.insert(
            id: openSpec.entryId,
            entryType: 'adjustment',
            description: openSpec.label,
            occurrenceDate: '2026-10-01',
            legacySourceTxId: Value('open:${openSpec.accountId}:rev:1'),
            createdAt: legacyCreatedAt,
          ),
        );
    await db.into(db.postingsTable).insert(
          PostingsTableCompanion.insert(
            id: 'post-${openSpec.entryId}-dr',
            entryId: openSpec.entryId,
            accountId: openSpec.accountId,
            amountCents: openSpec.amountCents,
            direction: 'debit',
            accountMovementDate: '2026-10-01',
          ),
        );
    await db.into(db.postingsTable).insert(
          PostingsTableCompanion.insert(
            id: 'post-${openSpec.entryId}-cr',
            entryId: openSpec.entryId,
            accountId: SystemControlAccounts.equity,
            amountCents: openSpec.amountCents,
            direction: 'credit',
            accountMovementDate: '2026-10-01',
          ),
        );
  }

  // Historical USD expense with preserved note
  await db.into(db.journalEntriesTable).insert(
        JournalEntriesTableCompanion.insert(
          id: 'je-usd-exp',
          entryType: 'standard',
          description: 'Airport Hotel USD',
          occurrenceDate: '2026-10-15',
          createdAt: legacyCreatedAt,
        ),
      );
  await db.into(db.postingsTable).insert(
        PostingsTableCompanion.insert(
          id: 'post-usd-exp-dr',
          entryId: 'je-usd-exp',
          accountId: SystemControlAccounts.expense,
          amountCents: 15000,
          direction: 'debit',
          accountMovementDate: '2026-10-15',
          categoryId: const Value('cat-food'),
          note: const Value('Historical USD lodging note'),
        ),
      );
  await db.into(db.postingsTable).insert(
        PostingsTableCompanion.insert(
          id: 'post-usd-exp-cr',
          entryId: 'je-usd-exp',
          accountId: 'acc-usd-bank',
          amountCents: 15000,
          direction: 'credit',
          accountMovementDate: '2026-10-15',
        ),
      );

  // Historical unclassified ("") expense
  await db.into(db.journalEntriesTable).insert(
        JournalEntriesTableCompanion.insert(
          id: 'je-unclassified-exp',
          entryType: 'standard',
          description: 'Legacy Unclassified Expense',
          occurrenceDate: '2026-10-16',
          createdAt: legacyCreatedAt,
        ),
      );
  await db.into(db.postingsTable).insert(
        PostingsTableCompanion.insert(
          id: 'post-uncl-exp-dr',
          entryId: 'je-unclassified-exp',
          accountId: SystemControlAccounts.expense,
          amountCents: 7500,
          direction: 'debit',
          accountMovementDate: '2026-10-16',
          categoryId: const Value('cat-other-exp'),
          note: const Value('Historical pouch note'),
        ),
      );
  await db.into(db.postingsTable).insert(
        PostingsTableCompanion.insert(
          id: 'post-uncl-exp-cr',
          entryId: 'je-unclassified-exp',
          accountId: 'acc-unclassified',
          amountCents: 7500,
          direction: 'credit',
          accountMovementDate: '2026-10-16',
        ),
      );

  // Historical USD receivable debt + partial settlement allocation
  await db.into(db.partiesTable).insert(
        PartiesTableCompanion.insert(
          id: 'party-usd-1',
          name: 'Abebe Overseas',
          phone: const Value('+251911000001'),
          notes: const Value('Preserved party note'),
          createdAt: legacyCreatedAt,
        ),
      );
  await db.into(db.journalEntriesTable).insert(
        JournalEntriesTableCompanion.insert(
          id: 'je-usd-debt-origin',
          entryType: 'debtIssuance',
          description: 'USD Loan to Abebe',
          occurrenceDate: '2026-10-18',
          createdAt: legacyCreatedAt,
        ),
      );
  await db.into(db.postingsTable).insert(
        PostingsTableCompanion.insert(
          id: 'post-usd-do-dr',
          entryId: 'je-usd-debt-origin',
          accountId: SystemControlAccounts.receivable,
          amountCents: 30000,
          direction: 'debit',
          accountMovementDate: '2026-10-18',
        ),
      );
  await db.into(db.postingsTable).insert(
        PostingsTableCompanion.insert(
          id: 'post-usd-do-cr',
          entryId: 'je-usd-debt-origin',
          accountId: 'acc-usd-bank',
          amountCents: 30000,
          direction: 'credit',
          accountMovementDate: '2026-10-18',
        ),
      );
  await db.into(db.debtsTable).insert(
        DebtsTableCompanion.insert(
          id: 'debt-usd-1',
          originEntryId: 'je-usd-debt-origin',
          partyId: 'party-usd-1',
          debtType: 'receivable',
          principalCents: 30000,
          outstandingCents: 20000,
          dueDate: const Value('2026-12-01'),
          createdAt: legacyCreatedAt,
        ),
      );
  await db.into(db.journalEntriesTable).insert(
        JournalEntriesTableCompanion.insert(
          id: 'je-usd-debt-settle',
          entryType: 'settlement',
          description: 'Partial USD Repayment',
          occurrenceDate: '2026-10-20',
          createdAt: legacyCreatedAt,
        ),
      );
  await db.into(db.postingsTable).insert(
        PostingsTableCompanion.insert(
          id: 'post-usd-ds-dr',
          entryId: 'je-usd-debt-settle',
          accountId: 'acc-usd-bank',
          amountCents: 10000,
          direction: 'debit',
          accountMovementDate: '2026-10-20',
        ),
      );
  await db.into(db.postingsTable).insert(
        PostingsTableCompanion.insert(
          id: 'post-usd-ds-cr',
          entryId: 'je-usd-debt-settle',
          accountId: SystemControlAccounts.receivable,
          amountCents: 10000,
          direction: 'credit',
          accountMovementDate: '2026-10-20',
        ),
      );
  await db.into(db.settlementAllocationsTable).insert(
        SettlementAllocationsTableCompanion.insert(
          id: 'alloc-usd-1',
          settlementEntryId: 'je-usd-debt-settle',
          debtId: 'debt-usd-1',
          allocatedCents: 10000,
          settlementDate: '2026-10-20',
        ),
      );

  // Historical EUR commitment + legacy USD recurring rules (auto-post and commitment)
  await db.into(db.financialCommitments).insert(
        FinancialCommitmentsCompanion.insert(
          id: 'com-eur-due',
          title: 'EUR Roaming Invoice',
          amountCents: 8500,
          dueDate: '2026-11-25',
          linkedAccountId: const Value('acc-eur-cash'),
          categoryId: const Value('cat-comm'),
          createdAt: legacyCreatedAt,
        ),
      );
  await db.into(db.recurringRulesTable).insert(
        RecurringRulesTableCompanion.insert(
          id: 'rule-usd-auto-due',
          title: 'Legacy USD Cloud Sub',
          ruleType: 'expense',
          amountCents: 2000,
          frequency: 'monthly',
          startDate: '2026-10-01',
          nextOccurrenceDate: '2026-11-01',
          accountId: const Value('acc-usd-bank'),
          categoryId: const Value('cat-comm'),
          isActive: const Value(true),
          autoPost: const Value(true),
          createdAt: legacyCreatedAt,
        ),
      );
  await db.into(db.recurringRulesTable).insert(
        RecurringRulesTableCompanion.insert(
          id: 'rule-unclassified-commitment-due',
          title: 'Legacy Pouch Monthly Fee',
          ruleType: 'commitment',
          amountCents: 1500,
          frequency: 'monthly',
          startDate: '2026-10-01',
          nextOccurrenceDate: '2026-11-01',
          accountId: const Value('acc-unclassified'),
          categoryId: const Value('cat-other-exp'),
          isActive: const Value(true),
          autoPost: const Value(false),
          createdAt: legacyCreatedAt,
        ),
      );

  await controller.dismissLegacyNonEtbNotice();
  await controller.loadAll();
}

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Stage 3 Follow-up — Legacy Currency Backup & Restore (Flutter)', () {
    test(
      'Points 1-5: Full, encrypted .daywell, and Finance-only backup/restore preserve non-ETB and unclassified records read-only without affecting ETB balances or triggering due legacy recurring rules',
      () async {
        final srcDb = AppDatabase(NativeDatabase.memory());
        await srcDb.ensureInitialized();
        final srcRepo = DriftFinanceRepository(srcDb);
        final srcCtrl = FinanceController(repository: srcRepo);
        addTearDown(() async {
          srcCtrl.dispose();
          await srcDb.close();
        });

        await _seedMixedCurrencyDatabase(srcDb, srcRepo, srcCtrl);
        expect(srcCtrl.state.availableToSpendCents, 300000);
        expect(srcCtrl.state.availableToSpendBreakdown.liquidCashCents, 300000);
        expect(
          srcCtrl.state.availableToSpendBreakdown.vaultSavingsCents,
          100000,
        );

        // Point 1 & 2: Export canonical full snapshot, encrypted .daywell envelope, and Finance-only snapshot
        final srcCoordinator = DatabasePersistenceCoordinator(srcDb);
        final fullSnapshot = await srcCoordinator.exportSnapshot();
        final financeOnlyMap = await srcCoordinator.exportFinanceOnlySnapshot();
        final encryptedPayload =
            await EncryptionBackupService().encryptDatabasePayload(
          rawDatabaseJson: jsonEncode(fullSnapshot),
          passphrase: 'DaywellLegacy#2026',
          schemaVersion:
              fullSnapshot['schemaVersion'] as int? ?? srcDb.schemaVersion,
        );

        final accountsExported =
            (fullSnapshot['accounts'] as List).cast<Map<String, dynamic>>();
        expect(
          accountsExported
              .firstWhere((a) => a['id'] == 'acc-usd-bank')['currencyCode'],
          'USD',
        );
        expect(
          accountsExported
              .firstWhere((a) => a['id'] == 'acc-eur-cash')['currencyCode'],
          'EUR',
        );
        expect(
          accountsExported
              .firstWhere((a) => a['id'] == 'acc-unclassified')['currencyCode'],
          '',
        );

        // Point 3: Decrypt and restore into a brand-new clean database
        final decryptedJson =
            await EncryptionBackupService().decryptDatabasePayload(
          encryptedEnvelopeJson: encryptedPayload,
          passphrase: 'DaywellLegacy#2026',
        );
        final restoredDb = AppDatabase(NativeDatabase.memory());
        await restoredDb.ensureInitialized();
        final restoredRepo = DriftFinanceRepository(restoredDb);
        final restoredCtrl = FinanceController(repository: restoredRepo);
        addTearDown(() async {
          restoredCtrl.dispose();
          await restoredDb.close();
        });

        await DatabasePersistenceCoordinator(restoredDb).importSnapshotDetailed(
          jsonDecode(decryptedJson) as Map<String, dynamic>,
        );

        // Regression Point: processing due recurring rules post-restore must pause legacy auto-post,
        // create ZERO entries and ZERO commitments, and leave nextOccurrenceDate untouched.
        final recCreated = await restoredRepo.processDueRecurringRules(
          asOfDate: CalendarDate(year: 2026, month: 11, day: 20),
        );
        expect(recCreated, 0);

        await restoredCtrl.loadAll();
        final state = restoredCtrl.state;

        // Verify original IDs, amounts, currencies, relationships, and dismissal survived
        expect(state.legacyNonEtbNoticeDismissed, isTrue);
        expect(
          state.etbUserAccounts.map((a) => a.id).toSet(),
          {'acc-etb-cbe', 'acc-etb-vault'},
        );
        expect(
          state.legacyNonEtbAccounts.map((a) => a.id).toSet(),
          {'acc-usd-bank', 'acc-eur-cash', 'acc-unclassified'},
        );
        expect(
          state.accounts.firstWhere((a) => a.id == 'acc-usd-bank').currencyCode,
          'USD',
        );
        expect(
          state.accounts.firstWhere((a) => a.id == 'acc-eur-cash').currencyCode,
          'EUR',
        );
        expect(
          state.accounts
              .firstWhere((a) => a.id == 'acc-unclassified')
              .currencyCode,
          '',
        );
        expect(
          state.postings.firstWhere((p) => p.id == 'post-usd-exp-dr').note,
          'Historical USD lodging note',
        );
        final restoredDebt =
            state.debts.firstWhere((d) => d.id == 'debt-usd-1');
        expect(restoredDebt.originEntryId, 'je-usd-debt-origin');
        expect(restoredDebt.outstandingCents, 20000);
        expect(
          state.settlementAllocations
              .firstWhere((a) => a.id == 'alloc-usd-1')
              .debtId,
          'debt-usd-1',
        );

        // Recurring rule regression assertions
        final restoredAutoRule =
            state.recurringRules.firstWhere((r) => r.id == 'rule-usd-auto-due');
        expect(restoredAutoRule.autoPost, isFalse);
        expect(restoredAutoRule.isActive, isTrue);
        expect(restoredAutoRule.nextOccurrenceDate.toIsoString(), '2026-11-01');
        final restoredComRule = state.recurringRules
            .firstWhere((r) => r.id == 'rule-unclassified-commitment-due');
        expect(restoredComRule.isActive, isTrue);
        expect(restoredComRule.nextOccurrenceDate.toIsoString(), '2026-11-01');
        expect(
          state.commitments.any(
            (c) => c.recurringRuleId == 'rule-usd-auto-due',
          ),
          isFalse,
        );
        expect(
          state.commitments.any(
            (c) => c.recurringRuleId == 'rule-unclassified-commitment-due',
          ),
          isFalse,
        );

        // Running processDueRecurringRules a second time remains idempotent & creates zero commitments
        final recSecond = await restoredRepo.processDueRecurringRules(
          asOfDate: CalendarDate(year: 2026, month: 11, day: 20),
        );
        expect(recSecond, 0);

        // Point 4 & 5: ETB calculations unaffected & legacy balances preserved natively
        expect(state.availableToSpendCents, 300000);
        expect(state.availableToSpendBreakdown.liquidCashCents, 300000);
        expect(state.availableToSpendBreakdown.vaultSavingsCents, 100000);
        expect(
          DoubleEntryEngine.calculateAccountBalance(
            account: state.accounts.firstWhere((a) => a.id == 'acc-usd-bank'),
            postings: state.postings,
            entries: state.journalEntries,
          ),
          // 100,000 - 15,000 (hotel) - 30,000 (loan) + 10,000 (repay) = 65,000
          65000,
        );
        expect(
          DoubleEntryEngine.calculateAccountBalance(
            account:
                state.accounts.firstWhere((a) => a.id == 'acc-unclassified'),
            postings: state.postings,
            entries: state.journalEntries,
          ),
          42500,
        );

        // Read-only mutation guards block voiding restored legacy USD & unclassified entries
        for (final legacyEntryId in <String>[
          'je-usd-exp',
          'je-unclassified-exp',
        ]) {
          await expectLater(
            restoredRepo.voidJournalEntry(
              entryId: legacyEntryId,
              voidReason: 'Must fail',
            ),
            throwsA(isA<DoubleEntryValidationError>()),
          );
        }

        // Ordinary ETB entry remains cleanly voidable & restorable
        final etbExp = state.journalEntries
            .firstWhere((e) => e.description == 'ETB Groceries');
        await restoredRepo.voidJournalEntry(
          entryId: etbExp.id,
          voidReason: 'Regression check void',
        );
        await restoredCtrl.loadAll();
        expect(restoredCtrl.state.availableToSpendCents, 330000);
        await restoredRepo.unvoidJournalEntry(etbExp.id);
        await restoredCtrl.loadAll();
        expect(restoredCtrl.state.availableToSpendCents, 300000);

        // Finance-only restore preserves legacy records & non-Finance settings intact
        await restoredDb.into(restoredDb.notes).insert(
              NotesCompanion.insert(
                id: 'note-keep-1',
                title: 'Keep Note',
                content: 'Preserved across Finance-only restore',
                createdAt: DateTime.utc(2026, 11, 15),
                updatedAt: DateTime.utc(2026, 11, 15),
              ),
            );
        await DatabasePersistenceCoordinator(restoredDb)
            .importFinanceOnlySnapshot(financeOnlyMap);
        final keptNote = await (restoredDb.select(restoredDb.notes)
              ..where((n) => n.id.equals('note-keep-1')))
            .getSingleOrNull();
        expect(keptNote, isNotNull);
        expect(
          await restoredRepo.getLegacyNonEtbNoticeDismissed(),
          isTrue,
        );
      },
    );

    test(
      'Point 6: Older pre-v6 and v6 backups without Stage 3 archive fields restore safely',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        final repo = DriftFinanceRepository(db);
        final controller = FinanceController(repository: repo);
        addTearDown(() async {
          controller.dispose();
          await db.close();
        });

        await controller.dismissLegacyNonEtbNotice();

        // Pre-v6 schemaVersion 4 backup (omitted currencyCode, isActive:false, omitted appSettings)
        final legacyV4Snapshot = <String, dynamic>{
          'schemaVersion': 4,
          'isFinanceSetupCompleted': true,
          'openingBalanceCents': 120000,
          'accounts': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'acc-etb-main',
              'name': 'Main ETB Cash',
              'type': 'asset',
              'currencyCode': 'ETB',
              'openingBalanceCents': 120000,
              'createdAt': '2026-09-01T00:00:00.000Z',
            },
            <String, dynamic>{
              'id': 'acc-old-usd',
              'name': 'Archived Dollar Card',
              'type': 'asset',
              'currencyCode': 'USD',
              'openingBalanceCents': 75000,
              'isActive': false,
              'createdAt': '2026-09-01T00:00:00.000Z',
            },
            <String, dynamic>{
              'id': 'acc-old-untyped',
              'name': 'Legacy No-Currency Pouch',
              'type': 'asset',
              'openingBalanceCents': 45000,
              'createdAt': '2026-09-01T00:00:00.000Z',
            },
          ],
          'categories': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'cat-food',
              'name': 'Food',
              'type': 'expense',
              'colorHex': '#EF4444',
            },
          ],
          'transactions': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'tx-v4-etb',
              'type': 'expense',
              'amountCents': 20000,
              'accountId': 'acc-etb-main',
              'categoryId': 'cat-food',
              'description': 'ETB Market',
              'transactionDate': '2026-09-05',
              'createdAt': '2026-09-05T10:00:00.000Z',
            },
            <String, dynamic>{
              'id': 'tx-v4-usd',
              'type': 'expense',
              'amountCents': 12000,
              'accountId': 'acc-old-usd',
              'categoryId': 'cat-food',
              'description': 'USD Duty Free',
              'transactionDate': '2026-09-06',
              'createdAt': '2026-09-06T10:00:00.000Z',
            },
            <String, dynamic>{
              'id': 'tx-v4-untyped',
              'type': 'expense',
              'amountCents': 5000,
              'accountId': 'acc-old-untyped',
              'categoryId': 'cat-food',
              'description': 'Untyped Cash Spend',
              'transactionDate': '2026-09-07',
              'createdAt': '2026-09-07T10:00:00.000Z',
            },
          ],
          'tasks': <Map<String, dynamic>>[],
          'projects': <Map<String, dynamic>>[],
          'milestones': <Map<String, dynamic>>[],
          'goals': <Map<String, dynamic>>[],
          'notes': <Map<String, dynamic>>[],
          'inboxItems': <Map<String, dynamic>>[],
          'calendarEvents': <Map<String, dynamic>>[],
          'commitments': <Map<String, dynamic>>[],
          'savingsGoals': <Map<String, dynamic>>[],
        };

        await DatabasePersistenceCoordinator(db)
            .importSnapshotDetailed(legacyV4Snapshot);
        await controller.loadAll();

        expect(controller.state.legacyNonEtbNoticeDismissed, isTrue);
        expect(controller.state.availableToSpendCents, 100000);
        expect(
          controller.state.accounts
              .firstWhere((a) => a.id == 'acc-old-usd')
              .isArchived,
          isTrue,
        );
        expect(
          controller.state.accounts
              .firstWhere((a) => a.id == 'acc-old-untyped')
              .currencyCode,
          '',
        );
        expect(
          AppSettingsBackupPolicy.isExportableUserSetting(
            DriftFinanceRepository.legacyNonEtbNoticeDismissedKey,
          ),
          isTrue,
        );
      },
    );

    testWidgets(
      'Restored UI omits Void Entry on inspected legacy non-ETB entries and preserves collapsed archive',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        await tester.runAsync(db.ensureInitialized);
        final repo = DriftFinanceRepository(db);
        final controller = FinanceController(repository: repo);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          controller.dispose();
          await tester.runAsync(
            () => db.close().timeout(const Duration(seconds: 10)),
          );
        });

        await tester.runAsync(
          () => _seedMixedCurrencyDatabase(db, repo, controller),
        );

        // Overview keeps dismissed notice hidden and renders collapsed Legacy Non-ETB Archive
        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: FinanceOverviewTab(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Historical Non-ETB Records Preserved'),
          findsNothing,
        );
        final legacyArchiveFinder = find.textContaining(
          'Legacy Non-ETB Archive (Read-Only)',
        );
        await tester.scrollUntilVisible(
          legacyArchiveFinder,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(legacyArchiveFinder, findsOneWidget);

        // Transactions tab: expand Legacy Non-ETB Entries, inspect USD entry, verify Void Entry is hidden
        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: FinanceTransactionsTab(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final txListScrollable = find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        );
        final legacySection = find.textContaining('Legacy Non-ETB Entries (');
        await tester.scrollUntilVisible(
          legacySection,
          200,
          scrollable: txListScrollable,
        );
        await tester.ensureVisible(legacySection);
        await tester.tap(legacySection);
        await tester.pumpAndSettle();

        final usdEntryTile = find.text('Airport Hotel USD');
        await tester.scrollUntilVisible(
          usdEntryTile,
          200,
          scrollable: txListScrollable,
        );
        expect(usdEntryTile, findsOneWidget);
        await tester.ensureVisible(usdEntryTile);
        await tester.tap(usdEntryTile);
        await tester.pumpAndSettle();

        expect(find.textContaining('Read-Only'), findsWidgets);
        expect(find.text('Void Entry'), findsNothing);
        expect(find.text('Correct / Edit'), findsNothing);
        expect(find.text('Refund Expense'), findsNothing);
      },
    );
  });
}
