import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/interfaces/platform_service_interfaces.dart';
import 'package:personal_management_app/core/shared_foundation_core.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/database_persistence_coordinator.dart';
import 'package:personal_management_app/data/repositories/finance_repository.dart';
import 'package:personal_management_app/services/backup/encryption_backup_service.dart';

import 'support/sqlite_test_helper.dart';

Matcher _throwsInvalidPayload() => throwsA(
      isA<BackupValidationException>().having(
        (e) => e.kind,
        'kind',
        BackupFailureKind.invalidPayload,
      ),
    );

Map<String, dynamic> _stageASnapshot({
  required int schemaVersion,
  List<Map<String, dynamic>>? accounts,
  List<Map<String, dynamic>>? categories,
  List<Map<String, dynamic>>? transactions,
  List<Map<String, dynamic>>? parties,
  List<Map<String, dynamic>>? journalEntries,
  List<Map<String, dynamic>>? postings,
  List<Map<String, dynamic>>? debts,
}) {
  return <String, dynamic>{
    'schemaVersion': schemaVersion,
    'isFinanceSetupCompleted': true,
    'openingBalanceCents': 100000,
    'categories': categories ??
        const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'cat-food',
            'name': 'Food',
            'type': 'expense',
            'sortOrder': 1,
          },
        ],
    'accounts': accounts ??
        const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'acc-etb',
            'name': 'CBE Birr',
            'type': 'asset',
            'subType': 'bank',
            'isSystem': false,
            'currencyCode': 'ETB',
            'openingBalanceCents': 100000,
            'openingBalanceDate': '2026-11-01',
            'isArchived': false,
            'createdAt': '2026-11-01T08:00:00.000Z',
          },
        ],
    'parties': parties ?? const <Map<String, dynamic>>[],
    'goals': const <Map<String, dynamic>>[],
    'projects': const <Map<String, dynamic>>[],
    'milestones': const <Map<String, dynamic>>[],
    'tasks': const <Map<String, dynamic>>[],
    'notes': const <Map<String, dynamic>>[],
    'inboxItems': const <Map<String, dynamic>>[],
    'calendarEvents': const <Map<String, dynamic>>[],
    'transactions': transactions ?? const <Map<String, dynamic>>[],
    'journalEntries': journalEntries ?? const <Map<String, dynamic>>[],
    'postings': postings ?? const <Map<String, dynamic>>[],
    'debts': debts ?? const <Map<String, dynamic>>[],
    'settlementAllocations': const <Map<String, dynamic>>[],
    'commitments': const <Map<String, dynamic>>[],
    'commitmentSettlements': const <Map<String, dynamic>>[],
    'savingsGoals': const <Map<String, dynamic>>[],
    'budgets': const <Map<String, dynamic>>[],
    'recurringRules': const <Map<String, dynamic>>[],
  };
}

void main() {
  configureSqliteForHostTests();

  group('Finance Stage A — Cross-Platform Enums & Legacy Backup/Restore', () {
    test(
      '1. Every canonical EntryType serializes & deserializes cleanly across '
      'domain, snapshot coordinator, and DB round-trip',
      () async {
        expect(
          EntryType.values.map((e) => e.dbValue).toList(),
          SharedFinanceContracts.canonicalEntryTypes,
        );

        for (final value in EntryType.values) {
          expect(EntryType.tryParse(value.dbValue), value);
          expect(EntryType.fromDbValue(value.dbValue), value);

          final model = JournalEntryModel(
            id: 'je-${value.dbValue}',
            entryType: value,
            description: 'Test ${value.dbValue}',
            occurrenceDate: '2026-11-15',
          );
          final json = model.toJson();
          expect(json['entryType'], value.dbValue);
          final decoded = JournalEntryModel.fromJson(json);
          expect(decoded.entryType, value);
        }

        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        await db.ensureInitialized();
        final coordinator = DatabasePersistenceCoordinator(db);

        final snapshot = _stageASnapshot(
          schemaVersion: 8,
          journalEntries: EntryType.values
              .map(
                (t) => <String, dynamic>{
                  'id': 'je-${t.dbValue}',
                  'entryType': t.dbValue,
                  'description': 'Canonical ${t.dbValue}',
                  'occurrenceDate': '2026-11-15',
                  'isVoided': false,
                  'createdAt': '2026-11-15T08:00:00.000Z',
                },
              )
              .toList(),
        );

        await coordinator.importSnapshotDetailed(snapshot);
        final exported = await coordinator.exportSnapshot();
        final exportedTypes = (exported['journalEntries'] as List)
            .map((e) => (e as Map<String, dynamic>)['entryType'])
            .toList();
        expect(exportedTypes, SharedFinanceContracts.canonicalEntryTypes);

        final repo = DriftFinanceRepository(db);
        final rows = await repo.getJournalEntries();
        expect(
          rows.map((e) => e.entryType.dbValue).toSet(),
          SharedFinanceContracts.canonicalEntryTypes.toSet(),
        );
      },
    );

    test(
      '2. Every canonical DebtStatus serializes & deserializes cleanly across '
      'domain, snapshot coordinator, and DB round-trip',
      () async {
        expect(
          DebtStatus.values.map((s) => s.dbValue).toList(),
          SharedFinanceContracts.canonicalDebtStatuses,
        );

        for (final status in DebtStatus.values) {
          expect(DebtStatus.tryParse(status.dbValue), status);
          expect(DebtStatus.fromDbValue(status.dbValue), status);

          final debt = DebtModel(
            id: 'debt-${status.dbValue}',
            originEntryId: 'je-origin',
            partyId: 'party-1',
            debtType: DebtType.receivable,
            principalCents: 10000,
            outstandingCents: status == DebtStatus.active ? 5000 : 0,
            status: status,
          );
          final json = debt.toJson();
          expect(json['status'], status.dbValue);
          final decoded = DebtModel.fromJson(json);
          expect(decoded.status, status);
        }

        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        await db.ensureInitialized();
        final coordinator = DatabasePersistenceCoordinator(db);

        final snapshot = _stageASnapshot(
          schemaVersion: 8,
          parties: const <Map<String, dynamic>>[
            <String, dynamic>{'id': 'party-1', 'name': 'Dawit'},
          ],
          journalEntries: const <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'je-origin',
              'entryType': 'debt_issuance',
              'occurrenceDate': '2026-11-15',
            },
          ],
          debts: DebtStatus.values
              .map(
                (s) => <String, dynamic>{
                  'id': 'debt-${s.dbValue}',
                  'originEntryId': 'je-origin',
                  'partyId': 'party-1',
                  'debtType': 'receivable',
                  'principalCents': 10000,
                  'outstandingCents': s == DebtStatus.active ? 5000 : 0,
                  'status': s.dbValue,
                },
              )
              .toList(),
        );

        await coordinator.importSnapshotDetailed(snapshot);
        final exported = await coordinator.exportSnapshot();
        final exportedStatuses = (exported['debts'] as List)
            .map((d) => (d as Map<String, dynamic>)['status'])
            .toList();
        expect(
          exportedStatuses.toSet(),
          SharedFinanceContracts.canonicalDebtStatuses.toSet(),
        );
      },
    );

    test(
      '3 & 4. All documented EntryType and DebtStatus legacy aliases normalize '
      'to canonical snake_case matching SharedFinanceContracts',
      () {
        const entryAliases = <String, EntryType>{
          'debtIssuance': EntryType.debtIssuance,
          'splitExpense': EntryType.splitExpense,
          'writeOff': EntryType.writeOff,
          'debt_origin': EntryType.debtIssuance,
          'debt_settlement': EntryType.settlement,
          'opening_balance': EntryType.adjustment,
          'opening': EntryType.adjustment,
          'correction': EntryType.adjustment,
          'void_reversal': EntryType.adjustment,
        };
        expect(EntryType.legacyAliases, entryAliases);

        const debtAliases = <String, DebtStatus>{
          'partially_settled': DebtStatus.active,
          'writtenOff': DebtStatus.writtenOff,
        };
        expect(DebtStatus.legacyAliases, debtAliases);

        for (final entry in entryAliases.entries) {
          expect(EntryType.fromDbValue(entry.key), entry.value);
          expect(EntryType.fromDbValue(' ${entry.key} '), entry.value);
        }
        for (final entry in debtAliases.entries) {
          expect(DebtStatus.fromDbValue(entry.key), entry.value);
          expect(DebtStatus.fromDbValue(' ${entry.key} '), entry.value);
        }

        final prepared =
            DatabasePersistenceCoordinator.validateAndPrepareSnapshot(
          _stageASnapshot(
            schemaVersion: 7,
            parties: const <Map<String, dynamic>>[
              <String, dynamic>{'id': 'pa-1', 'name': 'Selam'},
            ],
            journalEntries: entryAliases.keys
                .toList()
                .asMap()
                .entries
                .map(
                  (kv) => <String, dynamic>{
                    'id': 'je-alias-${kv.key}',
                    'entryType': kv.value,
                    'occurrenceDate': '2026-11-10',
                  },
                )
                .toList(),
            debts: debtAliases.keys
                .toList()
                .asMap()
                .entries
                .map(
                  (kv) => <String, dynamic>{
                    'id': 'debt-alias-${kv.key}',
                    'originEntryId': 'je-alias-0',
                    'partyId': 'pa-1',
                    'debtType': 'payable',
                    'principalCents': 20000,
                    'outstandingCents':
                        kv.value == 'partially_settled' ? 5000 : 0,
                    'status': kv.value,
                  },
                )
                .toList(),
          ),
        );

        expect(
          prepared.journalEntries.map((e) => e.entryType.value).toList(),
          entryAliases.values.map((v) => v.dbValue).toList(),
        );
        expect(
          prepared.debts.map((d) => d.status.value).toList(),
          <String>['active', 'written_off'],
        );
      },
    );

    test(
      '5. Unknown, blank, and non-string enum values fail closed safely',
      () {
        for (final bad in const <String>[
          '',
          '   ',
          'expense',
          'unknown_entry',
          'cancelled',
          'settled_partially',
        ]) {
          expect(EntryType.tryParse(bad), isNull);
          expect(DebtStatus.tryParse(bad), isNull);
          expect(() => EntryType.fromDbValue(bad), throwsArgumentError);
          expect(() => DebtStatus.fromDbValue(bad), throwsArgumentError);

          expect(
            () => JournalEntryModel.fromJson(<String, dynamic>{
              'id': 'je-bad',
              'entryType': bad,
              'occurrenceDate': '2026-11-10',
            }),
            throwsArgumentError,
          );
          expect(
            () => DebtModel.fromJson(<String, dynamic>{
              'id': 'd-bad',
              'originEntryId': 'je-1',
              'partyId': 'pa-1',
              'debtType': 'payable',
              'principalCents': 1000,
              'outstandingCents': 1000,
              'status': bad,
            }),
            throwsArgumentError,
          );

          expect(
            () => DatabasePersistenceCoordinator.validateAndPrepareSnapshot(
              _stageASnapshot(
                schemaVersion: 8,
                journalEntries: <Map<String, dynamic>>[
                  <String, dynamic>{
                    'id': 'je-bad',
                    'entryType': bad,
                    'occurrenceDate': '2026-11-10',
                  },
                ],
              ),
            ),
            _throwsInvalidPayload(),
          );
          expect(
            () => DatabasePersistenceCoordinator.validateAndPrepareSnapshot(
              _stageASnapshot(
                schemaVersion: 8,
                parties: const <Map<String, dynamic>>[
                  <String, dynamic>{'id': 'pa-1', 'name': 'P'},
                ],
                journalEntries: const <Map<String, dynamic>>[
                  <String, dynamic>{
                    'id': 'je-ok',
                    'entryType': 'debt_issuance',
                    'occurrenceDate': '2026-11-10',
                  },
                ],
                debts: <Map<String, dynamic>>[
                  <String, dynamic>{
                    'id': 'debt-bad',
                    'originEntryId': 'je-ok',
                    'partyId': 'pa-1',
                    'debtType': 'payable',
                    'principalCents': 1000,
                    'outstandingCents': 1000,
                    'status': bad,
                  },
                ],
              ),
            ),
            _throwsInvalidPayload(),
          );
        }

        expect(
          () => JournalEntryModel.fromJson(const <String, dynamic>{
            'id': 'je-int',
            'entryType': 42,
            'occurrenceDate': '2026-11-10',
          }),
          throwsArgumentError,
        );
        expect(
          () => DebtModel.fromJson(const <String, dynamic>{
            'id': 'debt-bool',
            'originEntryId': 'je-1',
            'partyId': 'pa-1',
            'debtType': 'payable',
            'principalCents': 1000,
            'outstandingCents': 1000,
            'status': true,
          }),
          throwsArgumentError,
        );
      },
    );

    test(
      '6 & 7. v7 and v8 snapshots preserve isolated non-ETB & empty-currency '
      'accounts and relationships across export/import & encrypted restore',
      () async {
        for (final version in const <int>[7, 8]) {
          final sourceDb = AppDatabase(NativeDatabase.memory());
          final coordinator = DatabasePersistenceCoordinator(sourceDb);

          final snapshot = _stageASnapshot(
            schemaVersion: version,
            accounts: <Map<String, dynamic>>[
              const <String, dynamic>{
                'id': 'acc-etb',
                'name': 'CBE Birr',
                'type': 'asset',
                'subType': 'bank',
                'isSystem': false,
                'currencyCode': 'ETB',
                'openingBalanceCents': 100000,
                'openingBalanceDate': '2026-11-01',
                'isArchived': false,
                'createdAt': '2026-11-01T08:00:00.000Z',
              },
              const <String, dynamic>{
                'id': 'acc-usd',
                'name': 'USD Reserve',
                'type': 'asset',
                'subType': 'bank',
                'isSystem': false,
                'currencyCode': 'usd',
                'openingBalanceCents': 250000,
                'openingBalanceDate': '2026-11-01',
                'isArchived': false,
                'createdAt': '2026-11-01T08:00:00.000Z',
              },
              const <String, dynamic>{
                'id': 'acc-unv',
                'name': 'Legacy Wallet',
                'type': 'asset',
                'subType': 'cash',
                'isSystem': false,
                'currencyCode': '',
                'openingBalanceCents': 40000,
                'openingBalanceDate': '2026-11-01',
                'isArchived': false,
                'createdAt': '2026-11-01T08:00:00.000Z',
              },
              const <String, dynamic>{
                'id': SystemControlAccounts.expense,
                'name': 'Expense Control',
                'type': 'expense',
                'subType': 'nominal_expense',
                'isSystem': true,
                'currencyCode': 'ETB',
                'openingBalanceCents': 0,
                'isArchived': false,
                'createdAt': '2026-11-01T08:00:00.000Z',
              },
              const <String, dynamic>{
                'id': SystemControlAccounts.receivable,
                'name': 'Receivable Control',
                'type': 'asset',
                'subType': 'receivable',
                'isSystem': true,
                'currencyCode': 'ETB',
                'openingBalanceCents': 0,
                'isArchived': false,
                'createdAt': '2026-11-01T08:00:00.000Z',
              },
            ],
            transactions: const <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'tx-etb-1',
                'amountCents': 5000,
                'type': 'expense',
                'categoryId': 'cat-food',
                'accountId': 'acc-etb',
                'transactionDate': '2026-11-10',
                'createdAt': '2026-11-10T08:00:00.000Z',
              },
              <String, dynamic>{
                'id': 'tx-usd-1',
                'amountCents': 12000,
                'type': 'expense',
                'categoryId': 'cat-food',
                'accountId': 'acc-usd',
                'transactionDate': '2026-11-11',
                'createdAt': '2026-11-11T08:00:00.000Z',
              },
              <String, dynamic>{
                'id': 'tx-unv-1',
                'amountCents': 3000,
                'type': 'expense',
                'categoryId': 'cat-food',
                'accountId': 'acc-unv',
                'transactionDate': '2026-11-12',
                'createdAt': '2026-11-12T08:00:00.000Z',
              },
            ],
            parties: const <Map<String, dynamic>>[
              <String, dynamic>{'id': 'party-usd', 'name': 'Foreign Client'},
            ],
            journalEntries: const <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'je-usd-exp',
                'entryType': 'standard',
                'description': 'USD Tooling',
                'occurrenceDate': '2026-11-11',
                'isVoided': false,
                'createdAt': '2026-11-11T08:00:00.000Z',
              },
              <String, dynamic>{
                'id': 'je-usd-debt',
                'entryType': 'debt_origin',
                'description': 'USD Invoice',
                'occurrenceDate': '2026-11-12',
                'isVoided': false,
                'createdAt': '2026-11-12T08:00:00.000Z',
              },
            ],
            postings: const <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'p-u1',
                'entryId': 'je-usd-exp',
                'accountId': 'acc-usd',
                'amountCents': 12000,
                'direction': 'credit',
                'categoryId': 'cat-food',
                'accountMovementDate': '2026-11-11',
              },
              <String, dynamic>{
                'id': 'p-u2',
                'entryId': 'je-usd-exp',
                'accountId': SystemControlAccounts.expense,
                'amountCents': 12000,
                'direction': 'debit',
                'categoryId': 'cat-food',
                'accountMovementDate': '2026-11-11',
              },
              <String, dynamic>{
                'id': 'p-d1',
                'entryId': 'je-usd-debt',
                'accountId': 'acc-usd',
                'amountCents': 50000,
                'direction': 'credit',
                'accountMovementDate': '2026-11-12',
              },
              <String, dynamic>{
                'id': 'p-d2',
                'entryId': 'je-usd-debt',
                'accountId': SystemControlAccounts.receivable,
                'amountCents': 50000,
                'direction': 'debit',
                'accountMovementDate': '2026-11-12',
              },
            ],
            debts: const <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'debt-usd-1',
                'originEntryId': 'je-usd-debt',
                'partyId': 'party-usd',
                'debtType': 'receivable',
                'principalCents': 50000,
                'outstandingCents': 50000,
                'status': 'partially_settled',
                'createdAt': '2026-11-12T08:00:00.000Z',
              },
            ],
          );

          final importReport =
              await coordinator.importSnapshotDetailed(snapshot);
          expect(
            importReport.diagnostics.any(
              (d) => d.code == 'CURRENCY_UNVERIFIED_ON_LEGACY_IMPORT',
            ),
            isTrue,
          );

          final exported = await coordinator.exportSnapshot();
          await sourceDb.close();

          // Round-trip into a fresh DB instance via encrypted backup payload
          final backupService = EncryptionBackupService();
          final payloadJson = await backupService.encryptDatabasePayload(
            rawDatabaseJson: jsonEncode(exported),
            passphrase: 'stage-a-pass',
            schemaVersion: (exported['schemaVersion'] as int?) ?? 5,
          );
          final decryptedJson = await backupService.decryptDatabasePayload(
            encryptedEnvelopeJson: payloadJson,
            passphrase: 'stage-a-pass',
          );
          final decrypted = jsonDecode(decryptedJson) as Map<String, dynamic>;

          final targetDb = AppDatabase(NativeDatabase.memory());
          final targetCoord = DatabasePersistenceCoordinator(targetDb);
          await targetCoord.importSnapshotDetailed(decrypted);

          final repo = DriftFinanceRepository(targetDb);
          final accounts = await repo.getAccounts(
            includeArchived: true,
            includeSystem: true,
          );
          final byId = <String, AccountModel>{
            for (final a in accounts) a.id: a,
          };
          expect(byId['acc-etb']?.currencyCode, 'ETB');
          expect(byId['acc-usd']?.currencyCode, 'USD');
          expect(byId['acc-usd']?.openingBalanceCents, 250000);
          expect(byId['acc-unv']?.currencyCode, '');
          expect(byId['acc-unv']?.openingBalanceCents, 40000);

          final txs = await repo.getTransactions();
          expect(
            txs.map((t) => '${t.id}:${t.accountId}:${t.amountCents}').toSet(),
            const <String>{
              'tx-etb-1:acc-etb:5000',
              'tx-usd-1:acc-usd:12000',
              'tx-unv-1:acc-unv:3000',
            },
          );
          final entries = await repo.getJournalEntries();
          expect(
            entries.map((e) => '${e.id}:${e.entryType.dbValue}').toSet(),
            const <String>{
              'je-usd-exp:standard',
              'je-usd-debt:debt_issuance',
            },
          );
          final postings = await repo.getPostings();
          expect(postings.length, 4);
          final debts = await repo.getDebts();
          expect(debts.single.id, 'debt-usd-1');
          expect(debts.single.partyId, 'party-usd');
          expect(debts.single.status, DebtStatus.active);

          await targetDb.close();
        }
      },
    );

    test(
      '8. Preserved non-ETB and empty-currency accounts do not enter ETB '
      'calculations and reject new ETB ledger writes',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        await db.ensureInitialized();
        final repo = DriftFinanceRepository(db);

        final cbe = AccountModel(
          id: 'acc-etb',
          name: 'CBE Birr',
          type: AccountType.asset,
          subType: AccountSubType.bank,
          currencyCode: 'ETB',
        );
        final usd = AccountModel(
          id: 'acc-usd',
          name: 'USD Bank',
          type: AccountType.asset,
          subType: AccountSubType.bank,
          currencyCode: 'USD',
          openingBalanceCents: 250000,
        );
        final unv = AccountModel(
          id: 'acc-unv',
          name: 'Legacy Cash',
          type: AccountType.asset,
          subType: AccountSubType.cash,
          currencyCode: '',
          openingBalanceCents: 40000,
        );
        final sysEquity = AccountModel(
          id: SystemControlAccounts.equity,
          name: 'Opening Equity',
          type: AccountType.equity,
          subType: AccountSubType.openingEquity,
          isSystem: true,
        );
        final sysExpense = AccountModel(
          id: SystemControlAccounts.expense,
          name: 'Expense Control',
          type: AccountType.expense,
          subType: AccountSubType.nominalExpense,
          isSystem: true,
        );
        final sysReceivable = AccountModel(
          id: SystemControlAccounts.receivable,
          name: 'Receivable Control',
          type: AccountType.asset,
          subType: AccountSubType.receivable,
          isSystem: true,
        );

        final openEtb = DoubleEntryEngine.buildOpeningBalance(
          entryId: 'je-open-etb',
          account: cbe,
          overrideAmountCents: 100000,
          date: '2026-11-01',
        );
        final expEtb = DoubleEntryEngine.buildDirectExpense(
          entryId: 'je-exp-etb',
          paidAccountId: 'acc-etb',
          categoryId: 'cat-food',
          amountCents: 15000,
          date: '2026-11-05',
          description: 'Groceries',
        );

        final usdEntry = JournalEntryModel(
          id: 'je-usd',
          entryType: EntryType.standard,
          description: 'USD expense',
          occurrenceDate: '2026-11-06',
        );
        final usdDebtEntry = JournalEntryModel(
          id: 'je-usd-debt',
          entryType: EntryType.debtIssuance,
          description: 'USD receivable',
          occurrenceDate: '2026-11-07',
        );
        final unvEntry = JournalEntryModel(
          id: 'je-unv',
          entryType: EntryType.standard,
          description: 'Unverified cash spend',
          occurrenceDate: '2026-11-08',
        );

        final accounts = <AccountModel>[
          cbe,
          usd,
          unv,
          sysEquity,
          sysExpense,
          sysReceivable,
        ];
        final entries = <JournalEntryModel>[
          openEtb['entry'] as JournalEntryModel,
          expEtb['entry'] as JournalEntryModel,
          usdEntry,
          usdDebtEntry,
          unvEntry,
        ];
        final postings = <PostingModel>[
          ...openEtb['postings'] as List<PostingModel>,
          ...expEtb['postings'] as List<PostingModel>,
          PostingModel(
            id: 'p-usd-1',
            entryId: 'je-usd',
            accountId: 'acc-usd',
            amountCents: 20000,
            direction: PostingDirection.credit,
            accountMovementDate: '2026-11-06',
          ),
          PostingModel(
            id: 'p-usd-2',
            entryId: 'je-usd',
            accountId: SystemControlAccounts.expense,
            amountCents: 20000,
            direction: PostingDirection.debit,
            accountMovementDate: '2026-11-06',
          ),
          PostingModel(
            id: 'p-usdd-1',
            entryId: 'je-usd-debt',
            accountId: 'acc-usd',
            amountCents: 30000,
            direction: PostingDirection.credit,
            accountMovementDate: '2026-11-07',
          ),
          PostingModel(
            id: 'p-usdd-2',
            entryId: 'je-usd-debt',
            accountId: SystemControlAccounts.receivable,
            amountCents: 30000,
            direction: PostingDirection.debit,
            accountMovementDate: '2026-11-07',
          ),
          PostingModel(
            id: 'p-unv-1',
            entryId: 'je-unv',
            accountId: 'acc-unv',
            amountCents: 5000,
            direction: PostingDirection.credit,
            accountMovementDate: '2026-11-08',
          ),
          PostingModel(
            id: 'p-unv-2',
            entryId: 'je-unv',
            accountId: SystemControlAccounts.expense,
            amountCents: 5000,
            direction: PostingDirection.debit,
            accountMovementDate: '2026-11-08',
          ),
        ];
        final debts = <DebtModel>[
          DebtModel(
            id: 'debt-usd',
            originEntryId: 'je-usd-debt',
            partyId: 'party-1',
            debtType: DebtType.receivable,
            principalCents: 30000,
            outstandingCents: 30000,
            status: DebtStatus.active,
          ),
        ];

        final audit = DoubleEntryEngine.auditCurrencyIsolation(
          accounts: accounts,
          entries: entries,
          postings: postings,
          debts: debts,
        );
        expect(audit.nonEtbAccountCount, 2);
        expect(audit.unverifiedAccountCount, 1);
        expect(audit.excludedNonEtbEntryCount, 2);
        expect(audit.currencyReviewEntryCount, 1);
        expect(audit.excludedNonEtbDebtCount, 1);

        expect(
          DoubleEntryEngine.calculateLiquidCash(
            accounts: accounts,
            postings: postings,
            entries: entries,
          ),
          85000,
        );
        expect(
          DoubleEntryEngine.calculateAvailableToSpendBreakdown(
            accounts: accounts,
            postings: postings,
            entries: entries,
            debts: debts,
            commitments: const <CommitmentModel>[],
            savingsGoals: const <SavingsGoalModel>[],
            periodEndIso: '2026-11-30',
          ).availableToSpendCents,
          85000,
        );
        expect(
          DoubleEntryEngine.calculateTotalReceivables(
            debts,
            accounts: accounts,
            entries: entries,
            postings: postings,
          ),
          0,
        );
        expect(
          DoubleEntryEngine.calculateNetPosition(
            accounts: accounts,
            postings: postings,
            entries: entries,
            debts: debts,
          ),
          85000,
        );

        final pnl = DoubleEntryEngine.calculateOccurrencePnlTotals(
          accounts: accounts,
          postings: postings,
          entries: entries,
          startDateIso: '2026-11-01',
          endDateIso: '2026-11-30',
          debts: debts,
        );
        expect(pnl.expenseCents, 15000);

        final cashflow = DoubleEntryEngine.calculateLiquidCashflowTotals(
          accounts: accounts,
          postings: postings,
          entries: entries,
          startDateIso: '2026-11-01',
          endDateIso: '2026-11-30',
          debts: debts,
        );
        expect(cashflow.outflowCents, 15000);

        expect(
          () => DoubleEntryEngine.assertVerifiedEtbAccount(usd),
          throwsA(isA<DoubleEntryValidationError>()),
        );
        expect(
          () => DoubleEntryEngine.assertVerifiedEtbAccount(unv),
          throwsA(isA<DoubleEntryValidationError>()),
        );

        // Repository write against preserved USD/unverified account fails
        // closed once imported into SQLite.
        final coordinator = DatabasePersistenceCoordinator(db);
        await coordinator.importSnapshotDetailed(
          _stageASnapshot(
            schemaVersion: 8,
            accounts: const <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'acc-usd',
                'name': 'USD Bank',
                'type': 'asset',
                'subType': 'bank',
                'currencyCode': 'USD',
              },
              <String, dynamic>{
                'id': 'acc-unv',
                'name': 'Legacy Cash',
                'type': 'asset',
                'subType': 'cash',
                'currencyCode': '',
              },
            ],
          ),
        );
        await expectLater(
          () => repo.recordDirectExpense(
            accountId: 'acc-usd',
            categoryId: 'cat-food',
            amountCents: 1000,
            date: CalendarDate(year: 2026, month: 11, day: 15),
            description: 'Blocked USD write',
          ),
          throwsA(isA<DoubleEntryValidationError>()),
        );
        await expectLater(
          () => repo.recordDirectExpense(
            accountId: 'acc-unv',
            categoryId: 'cat-food',
            amountCents: 1000,
            date: CalendarDate(year: 2026, month: 11, day: 15),
            description: 'Blocked unverified write',
          ),
          throwsA(isA<DoubleEntryValidationError>()),
        );
      },
    );
  });
}
