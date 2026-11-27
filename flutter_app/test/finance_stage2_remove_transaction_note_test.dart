import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/finance/finance_controller.dart';
import 'package:personal_management_app/application/notes/notes_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/shared_foundation.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/v7_ledger_hardener.dart';
import 'package:personal_management_app/data/repositories/finance_repository.dart';
import 'package:personal_management_app/data/repositories/notes_repository.dart';
import 'package:personal_management_app/domain/finance/double_entry_engine.dart';
import 'package:personal_management_app/services/export/finance_export_service.dart';
import 'package:personal_management_app/ui/screens/finance/finance_composer_sheet.dart';
import 'package:personal_management_app/ui/widgets/shared_ui_widgets.dart';

import 'support/sqlite_test_helper.dart';

class _Stage2Fixture {
  final AppDatabase db;
  final DriftFinanceRepository repo;
  final FinanceController controller;

  const _Stage2Fixture({
    required this.db,
    required this.repo,
    required this.controller,
  });
}

Future<_Stage2Fixture> _createFixture() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.ensureInitialized();
  final repo = DriftFinanceRepository(db);
  final controller = FinanceController(repository: repo);
  await controller.completeSetup([
    AccountModel(
      id: 'acc-cbe',
      name: 'CBE',
      type: AccountType.asset,
      subType: AccountSubType.bank,
      currencyCode: 'ETB',
      openingBalanceCents: 500000,
      openingBalanceDate: '2026-11-01',
    ),
    AccountModel(
      id: 'acc-telebirr',
      name: 'Telebirr',
      type: AccountType.asset,
      subType: AccountSubType.mobileMoney,
      currencyCode: 'ETB',
      openingBalanceCents: 100000,
      openingBalanceDate: '2026-11-01',
    ),
  ]);
  await controller.loadAll();
  return _Stage2Fixture(db: db, repo: repo, controller: controller);
}

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Finance Stage 2 — Remove Transaction-Level Note Functionality', () {
    late AppDatabase db;
    late DriftFinanceRepository repo;
    late FinanceController controller;

    setUp(() async {
      final fixture = await _createFixture();
      db = fixture.db;
      repo = fixture.repo;
      controller = fixture.controller;
    });

    tearDown(() async {
      controller.dispose();
      await db.close();
    });

    testWidgets(
      '1. FinanceComposerSheet exposes Description and omits transaction Note field across all modes; Finance UI removes transaction Note inputs',
      (tester) async {
        final fixture = await tester.runAsync(_createFixture);
        final localDb = fixture!.db;
        final localCtrl = fixture.controller;

        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 20));
          localCtrl.dispose();
          await localDb.close();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: FinanceComposerSheet(controller: localCtrl),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.widgetWithText(DaywellTextField, 'Description'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(DaywellTextField, 'Note (optional)'),
          findsNothing,
        );

        for (final modeLabel in [
          'Income',
          'Transfer',
          'Split Expense',
          'Lend',
          'Borrow',
        ]) {
          await tester.tap(find.widgetWithText(ChoiceChip, modeLabel));
          await tester.pumpAndSettle();
          expect(
            find.widgetWithText(DaywellTextField, 'Description'),
            findsOneWidget,
            reason: '$modeLabel should expose Description',
          );
          expect(
            find.widgetWithText(DaywellTextField, 'Note (optional)'),
            findsNothing,
            reason: '$modeLabel must not expose Note (optional)',
          );
        }

        // Verify FinanceTransactionsTab and FinancePlanTab omit transaction Note UI while retaining Party Notes & voidReason
        final txTabSource = File(
          'lib/ui/screens/finance/finance_transactions_tab.dart',
        ).readAsStringSync();
        final planTabSource = File(
          'lib/ui/screens/finance/finance_plan_tab.dart',
        ).readAsStringSync();
        expect(txTabSource.contains('Note (optional)'), isFalse);
        expect(txTabSource.contains('entry.voidReason'), isTrue);
        expect(planTabSource.contains('Payment Note (optional)'), isFalse);
        expect(planTabSource.contains("label: 'Notes (optional)'"), isTrue);
      },
    );

    test(
      '2. Creating, editing/correcting, and refunding transactions preserve Description without writing new transaction posting notes',
      () async {
        final created = await controller.recordDirectExpense(
          accountId: 'acc-cbe',
          categoryId: 'cat-food',
          amountCents: 100000,
          feeCents: 1500,
          feeCategoryId: SystemControlAccounts.feeCategoryId,
          date: CalendarDate(year: 2026, month: 11, day: 12),
          description: 'Groceries at Shoa',
        );
        expect(created, isNotNull);
        expect(created!.description, 'Groceries at Shoa');

        final createdPostings = controller.state.postings
            .where((p) => p.entryId == created.id)
            .toList();
        // Principal & cash legs do not write transaction-level notes
        expect(
          createdPostings
              .where((p) => !DoubleEntryEngine.isExpenseFeePosting(p))
              .every((p) => p.note == null),
          isTrue,
        );

        // Refund no longer writes default 'Refund for ...' note
        final refund = await controller.recordExpenseRefund(
          originalEntryId: created.id,
          refundAccountId: 'acc-cbe',
          refundCents: 30000,
          date: CalendarDate(year: 2026, month: 11, day: 13),
        );
        expect(refund, isNotNull);
        expect(refund!.description, 'Refund: Groceries at Shoa');
        final refundPostings = controller.state.postings
            .where((p) => p.entryId == refund.id)
            .toList();
        expect(refundPostings.every((p) => p.note == null), isTrue);

        // Edit/replace preserves new Description
        final replacementBuilt = DoubleEntryEngine.buildDirectExpense(
          entryId: 'exp-repl-stage2',
          paidAccountId: 'acc-cbe',
          categoryId: 'cat-food',
          amountCents: 95000,
          date: '2026-11-12',
          description: 'Groceries updated',
          correctedFromEntryId: created.id,
        );
        final replacement = await controller.correctJournalEntry(
          originalEntryId: created.id,
          replacementEntry: replacementBuilt['entry'] as JournalEntryModel,
          replacementPostings:
              replacementBuilt['postings'] as List<PostingModel>,
          correctionReason: 'Updated description',
        );
        expect(replacement, isNotNull);
        expect(replacement!.description, 'Groceries updated');
      },
    );

    test(
      '3. FinanceExportService.exportPostingsCsv omits transaction Note column while exportPartiesCsv keeps Notes',
      () {
        final built = DoubleEntryEngine.buildDirectExpense(
          entryId: 'exp-csv',
          paidAccountId: 'acc-cbe',
          categoryId: 'cat-food',
          amountCents: 25000,
          date: '2026-11-12',
          description: 'Lunch',
        );
        final postingsWithNote = (built['postings'] as List<PostingModel>)
            .map((p) => PostingModel(
                  id: p.id,
                  entryId: p.entryId,
                  accountId: p.accountId,
                  amountCents: p.amountCents,
                  direction: p.direction,
                  accountMovementDate: p.accountMovementDate,
                  categoryId: p.categoryId,
                  note: 'Legacy posting memo',
                ))
            .toList();

        final postingsCsv = FinanceExportService.exportPostingsCsv(
          postingsWithNote,
        ).replaceFirst('\uFEFF', '');
        final header = postingsCsv.split(RegExp(r'\r?\n')).first;
        expect(
          header,
          '"Posting ID","Entry ID","Account ID","Amount Cents","Amount Decimal","Direction","Movement Date","Category ID"',
        );
        expect(postingsCsv.contains('Legacy posting memo'), isFalse);

        final partiesCsv = FinanceExportService.exportPartiesCsv([
          PartyModel(
            id: 'party-1',
            name: 'Abebe',
            phone: '+251911000000',
            notes: 'Friend from college',
          ),
        ]);
        expect(partiesCsv.contains('"Notes"'), isTrue);
        expect(partiesCsv.contains('Friend from college'), isTrue);
      },
    );

    test(
      '4. Historical notes are preserved, unambiguous notes backfill empty descriptions, and non-empty descriptions are never overwritten or duplicated',
      () async {
        // Pure domain resolution safety checks
        expect(
          DoubleEntryEngine.resolveDescriptionPreservingLegacyNote(
            description: '',
            legacyNote: 'Historical taxi fare',
          ),
          'Historical taxi fare',
        );
        expect(
          DoubleEntryEngine.resolveDescriptionPreservingLegacyNote(
            description: 'Existing coffee description',
            legacyNote: 'Old historical note',
          ),
          'Existing coffee description',
        );
        expect(
          DoubleEntryEngine.resolveUnambiguousHistoricalPostingNote([
            PostingModel(
              id: 'p-1',
              entryId: 'e-ambig',
              accountId: 'acc-cbe',
              amountCents: 1000,
              direction: PostingDirection.credit,
              accountMovementDate: '2026-11-01',
              note: 'Note one',
            ),
            PostingModel(
              id: 'p-2',
              entryId: 'e-ambig',
              accountId: SystemControlAccounts.expense,
              amountCents: 1000,
              direction: PostingDirection.debit,
              accountMovementDate: '2026-11-01',
              note: 'Note two',
            ),
          ]),
          isNull,
        );

        // Database backfill verification via V7LedgerHardener
        final now = DateTime.utc(2026, 11, 10, 12, 0);
        await db.into(db.journalEntriesTable).insert(
              JournalEntriesTableCompanion.insert(
                id: 'je-blank-posting-note',
                entryType: 'standard',
                description: '',
                occurrenceDate: '2026-11-10',
                createdAt: now,
              ),
            );
        await db.into(db.postingsTable).insert(
              PostingsTableCompanion.insert(
                id: 'post-bp-1',
                entryId: 'je-blank-posting-note',
                accountId: SystemControlAccounts.expense,
                amountCents: 5000,
                direction: 'debit',
                accountMovementDate: '2026-11-10',
                categoryId: const Value('cat-food'),
                note: const Value('Copied legacy food note'),
              ),
            );
        await db.into(db.postingsTable).insert(
              PostingsTableCompanion.insert(
                id: 'post-bp-2',
                entryId: 'je-blank-posting-note',
                accountId: 'acc-cbe',
                amountCents: 5000,
                direction: 'credit',
                accountMovementDate: '2026-11-10',
              ),
            );

        // Entry with existing non-empty description + historical note must NOT be overwritten
        await db.into(db.journalEntriesTable).insert(
              JournalEntriesTableCompanion.insert(
                id: 'je-keep-existing',
                entryType: 'standard',
                description: 'Official receipt',
                occurrenceDate: '2026-11-11',
                createdAt: now,
              ),
            );
        await db.into(db.postingsTable).insert(
              PostingsTableCompanion.insert(
                id: 'post-ke-1',
                entryId: 'je-keep-existing',
                accountId: SystemControlAccounts.expense,
                amountCents: 7500,
                direction: 'debit',
                accountMovementDate: '2026-11-11',
                categoryId: const Value('cat-food'),
                note: const Value('Separate historical note'),
              ),
            );
        await db.into(db.postingsTable).insert(
              PostingsTableCompanion.insert(
                id: 'post-ke-2',
                entryId: 'je-keep-existing',
                accountId: 'acc-cbe',
                amountCents: 7500,
                direction: 'credit',
                accountMovementDate: '2026-11-11',
              ),
            );

        final updatedCount = await V7LedgerHardener
            .backfillBlankDescriptionsFromHistoricalNotesInTx(
          db,
        );
        expect(updatedCount, 1);

        final entries = await db.select(db.journalEntriesTable).get();
        final backfilled =
            entries.firstWhere((e) => e.id == 'je-blank-posting-note');
        final preserved = entries.firstWhere((e) => e.id == 'je-keep-existing');
        expect(backfilled.description, 'Copied legacy food note');
        expect(preserved.description, 'Official receipt');

        // Historical posting.note values remain preserved in postings_table
        final postings = await db.select(db.postingsTable).get();
        expect(
          postings.firstWhere((p) => p.id == 'post-bp-1').note,
          'Copied legacy food note',
        );
        expect(
          postings.firstWhere((p) => p.id == 'post-ke-1').note,
          'Separate historical note',
        );

        // Verify transactions search relies on resolved Description, not unmigrated note
        final searchQuery = 'Separate historical note'.toLowerCase();
        final resolvedKept =
            DoubleEntryEngine.resolveDescriptionPreservingLegacyNote(
          description: preserved.description,
          legacyNote: postings.firstWhere((p) => p.id == 'post-ke-1').note,
        );
        expect(resolvedKept.toLowerCase().contains(searchQuery), isFalse);
        expect(resolvedKept.toLowerCase().contains('official receipt'), isTrue);
      },
    );

    test(
      '5. Separate Daywell Notes module continues to create, read, and search notes normally',
      () async {
        final notesRepo = DriftNotesRepository(db);
        final notesCtrl = NotesController(repository: notesRepo);
        addTearDown(notesCtrl.dispose);

        await notesRepo.createNote(
          NoteEntity(
            id: 'note-standalone-1',
            title: 'Weekly Study Plan',
            content: 'Unrelated standalone note remains intact',
          ),
        );
        final results = await notesRepo.searchNotes('standalone note remains');
        expect(results.length, 1);
        expect(results.first.title, 'Weekly Study Plan');
      },
    );
  });
}
