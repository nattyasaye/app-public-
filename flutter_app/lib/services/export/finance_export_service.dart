import '../../core/date/shared_date.dart';
import '../../domain/finance/double_entry_engine.dart';
import '../../domain/finance/finance_models.dart';

class FinanceExportService {
  static String _csvCell(String? value) {
    final safe = (value ?? '').replaceAll('"', '""');
    return '"$safe"';
  }

  static String _sqlText(String? value) {
    if (value == null) return 'NULL';
    final safe = value.replaceAll('\'', '\'\'');
    return '\'$safe\'';
  }

  /// Generates UTF-8 with BOM (\uFEFF) CSV string so spreadsheets render Amharic cleanly.
  static String exportAccountsCsv(
    List<AccountModel> accounts,
    List<PostingModel> postings, {
    List<JournalEntryModel>? entries,
  }) {
    final buffer = StringBuffer('\uFEFF');
    buffer.writeln(
      '"Account ID","Account Name","Type","Sub Type","Is System","Currency","Reporting Status","Is Archived","Balance (Native Cents)","Balance (Native Decimal)","Created At"',
    );

    for (final a in accounts) {
      final bal = DoubleEntryEngine.calculateAccountBalance(
        account: a,
        postings: postings,
        entries: entries,
      );
      final tier = DoubleEntryEngine.classifyCurrencyCode(a.currencyCode);
      final normCode = DoubleEntryEngine.normalizeCurrencyCode(a.currencyCode);
      final statusLabel = a.isSystem
          ? 'SYSTEM'
          : tier == CurrencyValidationTier.verifiedEtb
              ? 'ELIGIBLE_ETB'
              : tier == CurrencyValidationTier.verifiedNonEtb
                  ? 'EXCLUDED_$normCode'
                  : 'CURRENCY_REVIEW';
      buffer.writeln(
        '${_csvCell(a.id)},${_csvCell(a.name)},${_csvCell(a.type.name)},${_csvCell(a.subType.dbValue)},${a.isSystem ? 'TRUE' : 'FALSE'},${_csvCell(normCode.isEmpty ? 'UNVERIFIED' : normCode)},${_csvCell(statusLabel)},${a.isArchived ? 'TRUE' : 'FALSE'},$bal,"${(bal / 100).toStringAsFixed(2)}",${_csvCell(EthiopiaClock.toUtcIsoString(a.createdAt))}',
      );
    }
    return buffer.toString();
  }

  static String exportCategoriesCsv(List<TransactionCategoryModel> categories) {
    final buffer = StringBuffer('\uFEFF');
    buffer.writeln(
      '"Category ID","Name","Type","Parent ID","Color Hex","Sort Order","Is Default","Is Archived"',
    );
    for (final c in categories) {
      buffer.writeln(
        '${_csvCell(c.id)},${_csvCell(c.name)},${_csvCell(c.type)},${_csvCell(c.parentId)},${_csvCell(c.colorHex)},${c.sortOrder},${c.isDefault ? 'TRUE' : 'FALSE'},${c.isArchived ? 'TRUE' : 'FALSE'}',
      );
    }
    return buffer.toString();
  }

  static String exportPartiesCsv(List<PartyModel> parties) {
    final buffer = StringBuffer('\uFEFF');
    buffer.writeln(
      '"Party ID","Party Name","Phone","Notes","Is Archived","Created At"',
    );

    for (final p in parties) {
      buffer.writeln(
        '${_csvCell(p.id)},${_csvCell(p.name)},${_csvCell(p.phone)},${_csvCell(p.notes)},${p.isArchived ? 'TRUE' : 'FALSE'},${_csvCell(EthiopiaClock.toUtcIsoString(p.createdAt))}',
      );
    }
    return buffer.toString();
  }

  static String exportJournalEntriesCsv(
    List<JournalEntryModel> entries, {
    List<PostingModel> postings = const [],
    List<AccountModel> accounts = const [],
    List<DebtModel> debts = const [],
    List<SettlementAllocationModel> allocations = const [],
  }) {
    final classifications = (postings.isNotEmpty && accounts.isNotEmpty)
        ? DoubleEntryEngine.classifyAllEntries(
            accounts: accounts,
            entries: entries,
            postings: postings,
            debts: debts,
            allocations: allocations,
          )
        : const <String, EntryCurrencyClassification>{};
    final buffer = StringBuffer('\uFEFF');
    buffer.writeln(
      '"Entry ID","Entry Type","Description","Occurrence Date","Currency","Reporting Status","Is Voided","Void Reason","Corrected From Entry ID","Legacy Source Tx ID","Created At"',
    );

    for (final j in entries) {
      final cls = classifications[j.id];
      final currency = cls != null
          ? (cls.nativeCurrencyCode ??
              (cls.touchedCurrencies.isNotEmpty
                  ? cls.touchedCurrencies.join('/')
                  : 'UNVERIFIED'))
          : 'UNVERIFIED';
      final reportingStatus = cls == null
          ? (j.isVoided ? 'INACTIVE_OR_VOIDED' : 'UNCLASSIFIED')
          : cls.isEligibleEtb
              ? 'ELIGIBLE_ETB'
              : cls.isExcludedNonEtb
                  ? 'EXCLUDED_${cls.nativeCurrencyCode ?? 'FOREIGN'}'
                  : cls.isInactiveOrVoided
                      ? 'INACTIVE_OR_VOIDED'
                      : 'CURRENCY_REVIEW';
      buffer.writeln(
        '${_csvCell(j.id)},${_csvCell(j.entryType.dbValue)},${_csvCell(j.description)},${_csvCell(j.occurrenceDate)},${_csvCell(currency)},${_csvCell(reportingStatus)},${j.isVoided ? 'TRUE' : 'FALSE'},${_csvCell(j.voidReason)},${_csvCell(j.correctedFromEntryId)},${_csvCell(j.legacySourceTxId)},${_csvCell(EthiopiaClock.toUtcIsoString(j.createdAt))}',
      );
    }
    return buffer.toString();
  }

  static String exportPostingsCsv(List<PostingModel> postings) {
    final buffer = StringBuffer('\uFEFF');
    buffer.writeln(
      '"Posting ID","Entry ID","Account ID","Amount Cents","Amount Decimal","Direction","Movement Date","Category ID","Note"',
    );

    for (final p in postings) {
      buffer.writeln(
        '${_csvCell(p.id)},${_csvCell(p.entryId)},${_csvCell(p.accountId)},${p.amountCents},"${(p.amountCents / 100).toStringAsFixed(2)}",${_csvCell(p.direction.name)},${_csvCell(p.accountMovementDate)},${_csvCell(p.categoryId)},${_csvCell(p.note)}',
      );
    }
    return buffer.toString();
  }

  static String exportDebtsCsv(
    List<DebtModel> debts, {
    List<JournalEntryModel> entries = const [],
    List<PostingModel> postings = const [],
    List<AccountModel> accounts = const [],
    List<SettlementAllocationModel> allocations = const [],
  }) {
    final hasContext =
        entries.isNotEmpty && postings.isNotEmpty && accounts.isNotEmpty;
    final entryMap = {for (final e in entries) e.id: e};
    final classifications = hasContext
        ? DoubleEntryEngine.classifyAllEntries(
            accounts: accounts,
            entries: entries,
            postings: postings,
            debts: debts,
            allocations: allocations,
          )
        : const <String, EntryCurrencyClassification>{};
    final buffer = StringBuffer('\uFEFF');
    buffer.writeln(
      '"Debt ID","Origin Entry ID","Party ID","Debt Type","Currency","Reporting Status","Principal Cents","Principal Decimal","Outstanding Cents","Outstanding Decimal","Due Date","Status","Created At"',
    );

    for (final d in debts) {
      final originCls = classifications[d.originEntryId];
      final eligible = hasContext
          ? DoubleEntryEngine.isDebtEligibleEtb(
              d,
              entryById: entryMap,
              classifications: classifications,
            )
          : false;
      final currency = !hasContext
          ? 'UNCLASSIFIED'
          : (originCls?.nativeCurrencyCode ??
              (originCls != null &&
                      originCls.touchedCurrencies.length == 1 &&
                      originCls.touchedCurrencies.first != 'UNVERIFIED'
                  ? originCls.touchedCurrencies.first
                  : (eligible ? 'ETB' : 'UNVERIFIED')));
      final reportingStatus = !hasContext
          ? 'UNCLASSIFIED'
          : (eligible
              ? 'ELIGIBLE_ETB'
              : (originCls?.isExcludedNonEtb ?? false)
                  ? 'EXCLUDED_${originCls!.nativeCurrencyCode ?? 'FOREIGN'}'
                  : 'CURRENCY_REVIEW');
      buffer.writeln(
        '${_csvCell(d.id)},${_csvCell(d.originEntryId)},${_csvCell(d.partyId)},${_csvCell(d.debtType.name)},${_csvCell(currency)},${_csvCell(reportingStatus)},${d.principalCents},"${(d.principalCents / 100).toStringAsFixed(2)}",${d.outstandingCents},"${(d.outstandingCents / 100).toStringAsFixed(2)}",${_csvCell(d.dueDate)},${_csvCell(d.status.dbValue)},${_csvCell(EthiopiaClock.toUtcIsoString(d.createdAt))}',
      );
    }
    return buffer.toString();
  }

  static String exportSettlementAllocationsCsv(
    List<SettlementAllocationModel> allocations,
  ) {
    final buffer = StringBuffer('\uFEFF');
    buffer.writeln(
      '"Allocation ID","Settlement Entry ID","Debt ID","Allocated Cents","Allocated Decimal","Settlement Date"',
    );

    for (final a in allocations) {
      buffer.writeln(
        '${_csvCell(a.id)},${_csvCell(a.settlementEntryId)},${_csvCell(a.debtId)},${a.allocatedCents},"${(a.allocatedCents / 100).toStringAsFixed(2)}",${_csvCell(a.settlementDate)}',
      );
    }
    return buffer.toString();
  }

  static String exportBudgetsCsv(List<BudgetModel> budgets) {
    final buffer = StringBuffer('\uFEFF');
    buffer.writeln(
      '"Budget ID","Month ISO","Category ID","Limit Cents","Limit Decimal","Rollover Enabled","Created At","Updated At"',
    );
    for (final b in budgets) {
      buffer.writeln(
        '${_csvCell(b.id)},${_csvCell(b.monthIso)},${_csvCell(b.categoryId)},${b.limitCents},"${(b.limitCents / 100).toStringAsFixed(2)}",${b.rolloverEnabled ? 'TRUE' : 'FALSE'},${_csvCell(EthiopiaClock.toUtcIsoString(b.createdAt))},${_csvCell(EthiopiaClock.toUtcIsoString(b.updatedAt))}',
      );
    }
    return buffer.toString();
  }

  static String exportRecurringRulesCsv(List<RecurringRuleModel> rules) {
    final buffer = StringBuffer('\uFEFF');
    buffer.writeln(
      '"Rule ID","Title","Rule Type","Amount Cents","Amount Decimal","Frequency","Interval","Start Date","Next Occurrence","End Date","Account ID","Destination Account ID","Category ID","Linked Debt ID","Auto Post","Is Active","Created At"',
    );
    for (final r in rules) {
      buffer.writeln(
        '${_csvCell(r.id)},${_csvCell(r.title)},${_csvCell(r.ruleType.name)},${r.amountCents},"${(r.amountCents / 100).toStringAsFixed(2)}",${_csvCell(r.frequency.name)},${r.interval},${_csvCell(r.startDate.toIsoString())},${_csvCell(r.nextOccurrenceDate.toIsoString())},${_csvCell(r.endDate?.toIsoString())},${_csvCell(r.accountId)},${_csvCell(r.destinationAccountId)},${_csvCell(r.categoryId)},${_csvCell(r.linkedDebtId)},${r.autoPost ? 'TRUE' : 'FALSE'},${r.isActive ? 'TRUE' : 'FALSE'},${_csvCell(EthiopiaClock.toUtcIsoString(r.createdAt))}',
      );
    }
    return buffer.toString();
  }

  static String exportCommitmentsCsv(
    List<CommitmentModel> commitments, {
    List<AccountModel> accounts = const [],
    List<DebtModel> debts = const [],
    List<JournalEntryModel> entries = const [],
    List<PostingModel> postings = const [],
    List<SettlementAllocationModel> allocations = const [],
    List<RecurringRuleModel> recurringRules = const [],
    List<CommitmentSettlementModel> settlements = const [],
  }) {
    final hasContext = accounts.isNotEmpty;
    final accountById = {for (final a in accounts) a.id: a};
    final debtById = {for (final d in debts) d.id: d};
    final entryById = {for (final e in entries) e.id: e};
    final ruleById = {for (final r in recurringRules) r.id: r};
    final classifications = (postings.isNotEmpty && accounts.isNotEmpty)
        ? DoubleEntryEngine.classifyAllEntries(
            accounts: accounts,
            entries: entries,
            postings: postings,
            debts: debts,
            allocations: allocations,
          )
        : const <String, EntryCurrencyClassification>{};
    final settlementsByCommitment = <String, List<CommitmentSettlementModel>>{};
    for (final s in settlements) {
      settlementsByCommitment.putIfAbsent(s.commitmentId, () => []).add(s);
    }

    final buffer = StringBuffer('\uFEFF');
    buffer.writeln(
      '"Commitment ID","Title","Direction","Currency","Reporting Status","Amount Cents","Amount Decimal","Due Date","Status","Is Paid","Verified Settled Cents","Legacy Paid Unverified","Linked Account ID","Category ID"',
    );
    for (final c in commitments) {
      String currency = 'UNCLASSIFIED';
      String reportingStatus = 'UNCLASSIFIED';
      if (hasContext) {
        final res = DoubleEntryEngine.resolveCommitmentCurrencyStatus(
          commitment: c,
          accountById: accountById,
          debtById: debtById,
          entryById: entryById,
          classificationsByEntryId: classifications,
          ruleById: ruleById,
          settlementsByCommitmentId: settlementsByCommitment,
        );
        currency =
            res.currencyCode ?? (res.isEligibleEtb ? 'ETB' : 'UNVERIFIED');
        reportingStatus = (res.isEligibleEtb && res.isExpectedIncome)
            ? 'EXPECTED_INCOME_ETB'
            : res.isEligibleEtb
                ? 'ELIGIBLE_ETB'
                : res.isExcludedNonEtb
                    ? 'EXCLUDED_${res.currencyCode ?? 'FOREIGN'}'
                    : 'CURRENCY_REVIEW';
      }
      buffer.writeln(
        '${_csvCell(c.id)},${_csvCell(c.title)},${_csvCell(c.direction.name)},${_csvCell(currency)},${_csvCell(reportingStatus)},${c.amountCents},"${(c.amountCents / 100).toStringAsFixed(2)}",${_csvCell(c.dueDate.toIsoString())},${_csvCell(c.status.name)},${c.isPaid ? 'TRUE' : 'FALSE'},${c.verifiedSettledCents},${c.legacyPaidUnverified ? 'TRUE' : 'FALSE'},${_csvCell(c.linkedAccountId)},${_csvCell(c.categoryId)}',
      );
    }
    return buffer.toString();
  }

  static String exportSqliteAnalyticalScript({
    required List<AccountModel> accounts,
    required List<PartyModel> parties,
    required List<JournalEntryModel> entries,
    required List<PostingModel> postings,
    required List<DebtModel> debts,
    required List<SettlementAllocationModel> allocations,
    List<TransactionCategoryModel> categories = const [],
    List<BudgetModel> budgets = const [],
    List<RecurringRuleModel> recurringRules = const [],
  }) {
    final buffer = StringBuffer();
    buffer.writeln(
      '-- Daywell Personal Finance - Standalone SQLite Analytical Schema & Export (v7)',
    );
    buffer.writeln(
      '-- Generated: ${EthiopiaClock.toUtcIsoString(EthiopiaClock.nowUtc())}',
    );
    buffer.writeln('PRAGMA foreign_keys = ON;\n');

    buffer.writeln(
      'CREATE TABLE IF NOT EXISTS accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, sub_type TEXT NOT NULL, is_system INTEGER NOT NULL, currency_code TEXT NOT NULL, is_archived INTEGER NOT NULL, opening_balance_cents INTEGER NOT NULL, opening_balance_date TEXT NOT NULL, created_at TEXT NOT NULL);',
    );
    buffer.writeln(
      'CREATE TABLE IF NOT EXISTS categories (id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, parent_id TEXT, color_hex TEXT NOT NULL, sort_order INTEGER NOT NULL, is_default INTEGER NOT NULL, is_archived INTEGER NOT NULL);',
    );
    buffer.writeln(
      'CREATE TABLE IF NOT EXISTS parties (id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT, notes TEXT, is_archived INTEGER NOT NULL, created_at TEXT NOT NULL);',
    );
    buffer.writeln(
      'CREATE TABLE IF NOT EXISTS journal_entries (id TEXT PRIMARY KEY, entry_type TEXT NOT NULL, description TEXT NOT NULL, occurrence_date TEXT NOT NULL, is_voided INTEGER NOT NULL, void_reason TEXT, corrected_from_entry_id TEXT, legacy_source_tx_id TEXT, created_at TEXT NOT NULL);',
    );
    buffer.writeln(
      'CREATE TABLE IF NOT EXISTS postings (id TEXT PRIMARY KEY, entry_id TEXT NOT NULL, account_id TEXT NOT NULL, amount_cents INTEGER NOT NULL, direction TEXT NOT NULL, account_movement_date TEXT NOT NULL, category_id TEXT, note TEXT);',
    );
    buffer.writeln(
      'CREATE TABLE IF NOT EXISTS debts (id TEXT PRIMARY KEY, origin_entry_id TEXT NOT NULL, party_id TEXT NOT NULL, debt_type TEXT NOT NULL, principal_cents INTEGER NOT NULL, outstanding_cents INTEGER NOT NULL, due_date TEXT, status TEXT NOT NULL, created_at TEXT NOT NULL);',
    );
    buffer.writeln(
      'CREATE TABLE IF NOT EXISTS settlement_allocations (id TEXT PRIMARY KEY, settlement_entry_id TEXT NOT NULL, debt_id TEXT NOT NULL, allocated_cents INTEGER NOT NULL, settlement_date TEXT NOT NULL);',
    );
    buffer.writeln(
      'CREATE TABLE IF NOT EXISTS budgets (id TEXT PRIMARY KEY, category_id TEXT NOT NULL, month_iso TEXT NOT NULL, limit_cents INTEGER NOT NULL, rollover_enabled INTEGER NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);',
    );
    buffer.writeln(
      'CREATE TABLE IF NOT EXISTS recurring_rules (id TEXT PRIMARY KEY, title TEXT NOT NULL, rule_type TEXT NOT NULL, amount_cents INTEGER NOT NULL, frequency TEXT NOT NULL, interval INTEGER NOT NULL, start_date TEXT NOT NULL, next_occurrence_date TEXT NOT NULL, end_date TEXT, account_id TEXT, destination_account_id TEXT, category_id TEXT, linked_debt_id TEXT, is_active INTEGER NOT NULL, auto_post INTEGER NOT NULL, created_at TEXT NOT NULL);\n',
    );

    buffer.writeln(
      'CREATE VIEW IF NOT EXISTS view_account_balances AS SELECT a.id, a.name, a.type, a.sub_type, a.is_system, a.currency_code, COALESCE(SUM(CASE WHEN j.is_voided = 0 THEN CASE WHEN a.type IN (\'asset\', \'expense\') THEN CASE WHEN p.direction = \'debit\' THEN p.amount_cents ELSE -p.amount_cents END ELSE CASE WHEN p.direction = \'credit\' THEN p.amount_cents ELSE -p.amount_cents END END ELSE 0 END), 0) AS balance_cents FROM accounts a LEFT JOIN postings p ON a.id = p.account_id LEFT JOIN journal_entries j ON p.entry_id = j.id GROUP BY a.id;',
    );
    buffer.writeln(
      'CREATE VIEW IF NOT EXISTS view_occurrence_pnl AS SELECT j.occurrence_date, c.name AS category_name, a.type AS account_type, j.description, p.amount_cents, ROUND(p.amount_cents / 100.0, 2) AS amount_decimal FROM postings p JOIN accounts a ON p.account_id = a.id JOIN journal_entries j ON p.entry_id = j.id LEFT JOIN categories c ON p.category_id = c.id WHERE a.type IN (\'income\', \'expense\') AND j.is_voided = 0 AND (SELECT COUNT(*) FROM postings pc WHERE pc.entry_id = j.id) >= 2 AND NOT EXISTS (SELECT 1 FROM postings px LEFT JOIN accounts ax ON px.account_id = ax.id WHERE px.entry_id = j.id AND (px.account_id = \'acc-sys-legacy-offset\' OR ax.id IS NULL OR (ax.type IN (\'asset\', \'liability\') AND LOWER(COALESCE(ax.name, \'\')) NOT LIKE \'%receivable%\' AND LOWER(COALESCE(ax.name, \'\')) NOT LIKE \'%payable%\' AND UPPER(TRIM(COALESCE(ax.currency_code, \'\'))) != \'ETB\'))) AND (EXISTS (SELECT 1 FROM postings pr JOIN accounts ar ON pr.account_id = ar.id WHERE pr.entry_id = j.id AND ar.type IN (\'asset\', \'liability\') AND LOWER(COALESCE(ar.name, \'\')) NOT LIKE \'%receivable%\' AND LOWER(COALESCE(ar.name, \'\')) NOT LIKE \'%payable%\' AND UPPER(TRIM(COALESCE(ar.currency_code, \'\'))) = \'ETB\') OR EXISTS (SELECT 1 FROM debts d JOIN settlement_allocations sa ON sa.debt_id = d.id JOIN journal_entries sj ON sa.settlement_entry_id = sj.id JOIN postings sp ON sp.entry_id = sj.id JOIN accounts sax ON sp.account_id = sax.id WHERE d.origin_entry_id = j.id AND sj.is_voided = 0 AND sax.type IN (\'asset\', \'liability\') AND LOWER(COALESCE(sax.name, \'\')) NOT LIKE \'%receivable%\' AND LOWER(COALESCE(sax.name, \'\')) NOT LIKE \'%payable%\' AND UPPER(TRIM(COALESCE(sax.currency_code, \'\'))) = \'ETB\')) AND NOT EXISTS (SELECT 1 FROM debts d JOIN settlement_allocations sa ON sa.debt_id = d.id JOIN journal_entries sj ON sa.settlement_entry_id = sj.id JOIN postings sp ON sp.entry_id = sj.id JOIN accounts sax ON sp.account_id = sax.id WHERE d.origin_entry_id = j.id AND sj.is_voided = 0 AND sax.type IN (\'asset\', \'liability\') AND LOWER(COALESCE(sax.name, \'\')) NOT LIKE \'%receivable%\' AND LOWER(COALESCE(sax.name, \'\')) NOT LIKE \'%payable%\' AND UPPER(TRIM(COALESCE(sax.currency_code, \'\'))) != \'ETB\');',
    );
    buffer.writeln(
      'CREATE VIEW IF NOT EXISTS view_cash_flow AS SELECT p.account_movement_date, a.name AS account_name, p.direction, CASE WHEN p.direction = \'debit\' THEN p.amount_cents ELSE 0 END AS inflow_cents, CASE WHEN p.direction = \'credit\' THEN p.amount_cents ELSE 0 END AS outflow_cents, ROUND(CASE WHEN p.direction = \'debit\' THEN p.amount_cents ELSE 0 END / 100.0, 2) AS inflow_decimal, ROUND(CASE WHEN p.direction = \'credit\' THEN p.amount_cents ELSE 0 END / 100.0, 2) AS outflow_decimal, j.description FROM postings p JOIN accounts a ON p.account_id = a.id JOIN journal_entries j ON p.entry_id = j.id WHERE a.type = \'asset\' AND a.sub_type NOT IN (\'receivable\', \'savings_vault\') AND LOWER(a.name) NOT LIKE \'%receivable%\' AND j.is_voided = 0 AND UPPER(TRIM(COALESCE(a.currency_code, \'\'))) = \'ETB\' AND (SELECT COUNT(*) FROM postings pc WHERE pc.entry_id = j.id) >= 2 AND NOT EXISTS (SELECT 1 FROM postings px LEFT JOIN accounts ax ON px.account_id = ax.id WHERE px.entry_id = j.id AND (px.account_id = \'acc-sys-legacy-offset\' OR ax.id IS NULL OR (ax.type IN (\'asset\', \'liability\') AND LOWER(COALESCE(ax.name, \'\')) NOT LIKE \'%receivable%\' AND LOWER(COALESCE(ax.name, \'\')) NOT LIKE \'%payable%\' AND UPPER(TRIM(COALESCE(ax.currency_code, \'\'))) != \'ETB\')));',
    );
    buffer.writeln('');

    buffer.writeln('BEGIN TRANSACTION;');
    for (final a in accounts) {
      buffer.writeln(
        'INSERT INTO accounts VALUES (${_sqlText(a.id)}, ${_sqlText(a.name)}, ${_sqlText(a.type.name)}, ${_sqlText(a.subType.dbValue)}, ${a.isSystem ? 1 : 0}, ${_sqlText(a.currencyCode)}, ${a.isArchived ? 1 : 0}, ${a.openingBalanceCents}, ${_sqlText(a.openingBalanceDate)}, ${_sqlText(EthiopiaClock.toUtcIsoString(a.createdAt))});',
      );
    }
    for (final c in categories) {
      buffer.writeln(
        'INSERT INTO categories VALUES (${_sqlText(c.id)}, ${_sqlText(c.name)}, ${_sqlText(c.type)}, ${_sqlText(c.parentId)}, ${_sqlText(c.colorHex)}, ${c.sortOrder}, ${c.isDefault ? 1 : 0}, ${c.isArchived ? 1 : 0});',
      );
    }
    for (final p in parties) {
      buffer.writeln(
        'INSERT INTO parties VALUES (${_sqlText(p.id)}, ${_sqlText(p.name)}, ${_sqlText(p.phone)}, ${_sqlText(p.notes)}, ${p.isArchived ? 1 : 0}, ${_sqlText(EthiopiaClock.toUtcIsoString(p.createdAt))});',
      );
    }
    for (final j in entries) {
      buffer.writeln(
        'INSERT INTO journal_entries VALUES (${_sqlText(j.id)}, ${_sqlText(j.entryType.dbValue)}, ${_sqlText(j.description)}, ${_sqlText(j.occurrenceDate)}, ${j.isVoided ? 1 : 0}, ${_sqlText(j.voidReason)}, ${_sqlText(j.correctedFromEntryId)}, ${_sqlText(j.legacySourceTxId)}, ${_sqlText(EthiopiaClock.toUtcIsoString(j.createdAt))});',
      );
    }
    for (final p in postings) {
      buffer.writeln(
        'INSERT INTO postings VALUES (${_sqlText(p.id)}, ${_sqlText(p.entryId)}, ${_sqlText(p.accountId)}, ${p.amountCents}, ${_sqlText(p.direction.name)}, ${_sqlText(p.accountMovementDate)}, ${_sqlText(p.categoryId)}, ${_sqlText(p.note)});',
      );
    }
    for (final d in debts) {
      buffer.writeln(
        'INSERT INTO debts VALUES (${_sqlText(d.id)}, ${_sqlText(d.originEntryId)}, ${_sqlText(d.partyId)}, ${_sqlText(d.debtType.name)}, ${d.principalCents}, ${d.outstandingCents}, ${_sqlText(d.dueDate)}, ${_sqlText(d.status.dbValue)}, ${_sqlText(EthiopiaClock.toUtcIsoString(d.createdAt))});',
      );
    }
    for (final s in allocations) {
      buffer.writeln(
        'INSERT INTO settlement_allocations VALUES (${_sqlText(s.id)}, ${_sqlText(s.settlementEntryId)}, ${_sqlText(s.debtId)}, ${s.allocatedCents}, ${_sqlText(s.settlementDate)});',
      );
    }
    for (final b in budgets) {
      buffer.writeln(
        'INSERT INTO budgets VALUES (${_sqlText(b.id)}, ${_sqlText(b.categoryId)}, ${_sqlText(b.monthIso)}, ${b.limitCents}, ${b.rolloverEnabled ? 1 : 0}, ${_sqlText(EthiopiaClock.toUtcIsoString(b.createdAt))}, ${_sqlText(EthiopiaClock.toUtcIsoString(b.updatedAt))});',
      );
    }
    for (final r in recurringRules) {
      buffer.writeln(
        'INSERT INTO recurring_rules VALUES (${_sqlText(r.id)}, ${_sqlText(r.title)}, ${_sqlText(r.ruleType.name)}, ${r.amountCents}, ${_sqlText(r.frequency.name)}, ${r.interval}, ${_sqlText(r.startDate.toIsoString())}, ${_sqlText(r.nextOccurrenceDate.toIsoString())}, ${_sqlText(r.endDate?.toIsoString())}, ${_sqlText(r.accountId)}, ${_sqlText(r.destinationAccountId)}, ${_sqlText(r.categoryId)}, ${_sqlText(r.linkedDebtId)}, ${r.isActive ? 1 : 0}, ${r.autoPost ? 1 : 0}, ${_sqlText(EthiopiaClock.toUtcIsoString(r.createdAt))});',
      );
    }
    buffer.writeln('COMMIT;');
    return buffer.toString();
  }
}
