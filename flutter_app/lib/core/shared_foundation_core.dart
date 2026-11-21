// SHARED FOUNDATION CORE — PURE DART (Single Source of Truth)
// Generated automatically from /shared_foundation/*.json
// DO NOT EDIT DIRECTLY. Run "npm run sync-foundation" to regenerate.

import 'dart:convert';

class CanonicalSeedDatabase {
  static const int schemaVersion = 5;
  static const String appVersion = "1.0.2+3";
  static const String rawJson = r'''{
  "schemaVersion": 5,
  "appVersion": "1.0.2+3",
  "exportedAt": "2026-11-11T00:00:00.000Z",
  "isFinanceSetupCompleted": false,
  "openingBalanceCents": 0,
  "accounts": [],
  "categories": [
    {
      "id": "cat-food",
      "name": "Food",
      "type": "expense",
      "colorHex": "#EF4444",
      "isDefault": false,
      "isArchived": false
    },
    {
      "id": "cat-transport",
      "name": "Transport",
      "type": "expense",
      "colorHex": "#F97316",
      "isDefault": false,
      "isArchived": false
    },
    {
      "id": "cat-housing",
      "name": "Housing",
      "type": "expense",
      "colorHex": "#F59E0B",
      "isDefault": false,
      "isArchived": false
    },
    {
      "id": "cat-utilities",
      "name": "Utilities",
      "type": "expense",
      "colorHex": "#EAB308",
      "isDefault": false,
      "isArchived": false
    },
    {
      "id": "cat-comm",
      "name": "Communication",
      "type": "expense",
      "colorHex": "#84CC16",
      "isDefault": false,
      "isArchived": false
    },
    {
      "id": "cat-other-exp",
      "name": "Other",
      "type": "expense",
      "colorHex": "#94A3B8",
      "isDefault": true,
      "isArchived": false
    },
    {
      "id": "cat-salary",
      "name": "Salary",
      "type": "income",
      "colorHex": "#10B981",
      "isDefault": false,
      "isArchived": false
    },
    {
      "id": "cat-freelance",
      "name": "Freelance & Business",
      "type": "income",
      "colorHex": "#06B6D4",
      "isDefault": false,
      "isArchived": false
    },
    {
      "id": "cat-asaye",
      "name": "From Asaye",
      "type": "income",
      "colorHex": "#3B82F6",
      "isDefault": false,
      "isArchived": false
    },
    {
      "id": "cat-invest",
      "name": "Investments & Returns",
      "type": "income",
      "colorHex": "#8B5CF6",
      "isDefault": false,
      "isArchived": false
    },
    {
      "id": "cat-other-inc",
      "name": "Other Income",
      "type": "income",
      "colorHex": "#64748B",
      "isDefault": true,
      "isArchived": false
    }
  ],
  "transactions": [],
  "tasks": [],
  "notes": [],
  "projects": [],
  "goals": [],
  "inboxItems": [],
  "calendarEvents": []
}''';

  static Map<String, dynamic> get state =>
      jsonDecode(rawJson) as Map<String, dynamic>;
}

class SharedBusinessRules {
  static const String currencyCode = 'ETB';
  static const int minorUnitsPerMajor = 100;
  static const int defaultTxDisplayLimit = 25;

  /// Balance = Opening + Income - Expenses + Incoming - Outgoing Transfers
  static int calculateAccountBalance({
    required int openingBalanceCents,
    required String accountId,
    required List<Map<String, dynamic>> transactions,
  }) {
    int balance = openingBalanceCents;
    for (final tx in transactions) {
      if (tx['isSuperseded'] == true) continue;
      final type = tx['type'];
      final amount = tx['amountCents'] as int;
      if (type == 'income' && tx['accountId'] == accountId) {
        balance += amount;
      } else if (type == 'expense' && tx['accountId'] == accountId) {
        balance -= amount;
      } else if (type == 'transfer') {
        if (tx['accountId'] == accountId) {
          balance -= amount;
        }
        if (tx['destinationAccountId'] == accountId) {
          balance += amount;
        }
      }
    }
    return balance;
  }

  /// Combined balance of active Verified ETB non-system asset accounts
  static int calculateCombinedBalance({
    required List<Map<String, dynamic>> accounts,
    required List<Map<String, dynamic>> transactions,
  }) {
    int total = 0;
    for (final acc in accounts) {
      if (acc['isArchived'] == true) continue;
      if (acc['isSystem'] == true) continue;
      if (acc['type'] != null && acc['type'] != 'asset') continue;
      final code = (acc['currencyCode']?.toString() ?? '').trim().toUpperCase();
      if (code != 'ETB') continue;
      total += calculateAccountBalance(
        openingBalanceCents: (acc['openingBalanceCents'] as int?) ?? 0,
        accountId: acc['id'] as String,
        transactions: transactions,
      );
    }
    return total;
  }

  /// Total income from income transactions (excluding transfers)
  static int calculateTotalIncome({
    required List<Map<String, dynamic>> transactions,
    String? accountId,
  }) {
    int total = 0;
    for (final tx in transactions) {
      if (tx['isSuperseded'] == true) continue;
      if (tx['type'] == 'income') {
        if (accountId == null || tx['accountId'] == accountId) {
          total += (tx['amountCents'] as int?) ?? 0;
        }
      }
    }
    return total;
  }

  /// Total expense from expense transactions (excluding transfers)
  static int calculateTotalExpense({
    required List<Map<String, dynamic>> transactions,
    String? accountId,
  }) {
    int total = 0;
    for (final tx in transactions) {
      if (tx['isSuperseded'] == true) continue;
      if (tx['type'] == 'expense') {
        if (accountId == null || tx['accountId'] == accountId) {
          total += (tx['amountCents'] as int?) ?? 0;
        }
      }
    }
    return total;
  }

  /// Safe deletion guard for accounts
  static bool canDeleteAccount({
    required String accountId,
    required List<Map<String, dynamic>> transactions,
  }) {
    return !transactions.any((t) =>
        t['isSuperseded'] != true &&
        (t['accountId'] == accountId ||
            t['destinationAccountId'] == accountId));
  }

  /// Safe deletion guard for categories
  static bool canDeleteCategory({
    required String categoryId,
    required String categoryName,
    required List<Map<String, dynamic>> transactions,
  }) {
    return !transactions.any((t) =>
        t['isSuperseded'] != true &&
        (t['categoryId'] == categoryId || t['categoryName'] == categoryName));
  }

  /// Transfer validation
  static String? validateTransfer({
    required String fromAccountId,
    required String toAccountId,
    required int amountCents,
  }) {
    if (fromAccountId.isEmpty || toAccountId.isEmpty) {
      return 'Source and destination accounts are required.';
    }
    if (fromAccountId == toAccountId) {
      return 'Source and destination accounts cannot be identical.';
    }
    if (amountCents <= 0) {
      return 'Transfer amount must be greater than zero.';
    }
    return null;
  }
}

class SharedFinanceContracts {
  static const List<String> canonicalEntryTypes = [
    'standard',
    'transfer',
    'debt_issuance',
    'settlement',
    'split_expense',
    'adjustment',
    'write_off',
  ];

  static const List<String> canonicalDebtStatuses = [
    'active',
    'settled',
    'written_off',
    'voided',
  ];
}

class SharedTaskContracts {
  static const List<String> canonicalStatuses = [
    'not_started',
    'in_progress',
    'completed',
    'cancelled',
    'inbox',
  ];

  static const List<String> canonicalPriorities = [
    'low',
    'medium',
    'high',
    'urgent',
  ];

  static const List<String> canonicalRecurrenceFrequencies = [
    'daily',
    'weekly',
    'monthly',
    'yearly',
  ];

  static const List<String> canonicalDailyPlanningActions = [
    'planned',
    'carried_forward',
    'completed',
    'dismissed',
  ];

  static const String defaultStatus =
      'not_started';
  static const String defaultPriority =
      'medium';

  static const Map<String, int> priorityWeights = {
    'urgent': 4,
    'high': 3,
    'medium': 2,
    'low': 1,
  };

  static const bool deriveReminderStateFromReminders = true;
  static const bool singleCompletionSourceInStatus = true;
  static const bool utcIsoCompletedAt = true;
  static const bool preserveMyDayPlanningHistory = true;
}

class SharedProjectRules {
  static const List<String> statuses = ['active', 'completed', 'on_hold'];
  static const List<String> blockTypes = [
    'counter',
    'grouped_list',
    'checklist',
    'schedule',
  ];
  static const List<String> recordTypes = [
    'group',
    'grouped_item',
    'checklist_item',
    'schedule_item',
    'progress_log',
  ];
  static const List<String> customFieldTypes = [
    'text',
    'number',
    'date',
    'boolean',
    'select',
  ];
  static const int maxBlocksPerProject = 32;
  static const int maxCustomFieldDefinitions = 24;
  static const int maxCustomFieldSelectOptions = 50;
  static const int maxCustomFieldIdLength = 64;
  static const int maxCustomFieldTextLength = 1000;
  static const int maxTrackingRecordTitleLength = 300;
  static const int maxHierarchyDepth = 3;
  static const bool appendOnlyProgressLogs = true;
  static const bool allowCompensatingCorrections = true;
  static const bool allowMultipleIndependentMetrics = true;
  static const bool disallowImplicitMetricAveraging = true;
  static const bool requiresExplicitPrimaryBlockForOverallPercent = true;
  static const bool requirePositiveProgressLogDelta = true;
  static const bool preventDuplicateRollupLogging = true;
  static const bool enforceParentChildOwnership = true;
}

class SharedProjectPackageSpec {
  static const String formatId = 'daywell_project_package';
  static const int currentFormatVersion = 1;
  static const int minSupportedFormatVersion = 1;
  static const String fileExtension = '.daywellproject';
}

class KnownSeedIds {
  static const Set<String> accounts = {
    'acc-cbe',
    'acc-boa',
    'acc-dashen',
    'acc-telebirr',
    'acc-cash'
  };
  static const Set<String> transactions = {
    'tx-seed-1',
    'tx-seed-2',
    'tx-seed-3'
  };
  static const Set<String> tasks = {
    'task-seed-1',
    'task-seed-2',
    't-1',
    't-2',
    't-3',
    't-4',
    't-5',
    't-6',
    't-7'
  };
  static const Set<String> notes = {
    'note-seed-1',
    'note-1',
    'note-2',
    'note-3'
  };
  static const Set<String> projects = {
    'proj-seed-1',
    'proj-1',
    'proj-2',
    'proj-3'
  };
  static const Set<String> goals = {'goal-seed-1', 'goal-1', 'goal-2'};
  static const Set<String> events = {'evt-1', 'evt-2', 'evt-3', 'evt-4'};
  static const Set<String> commitments = {'com-1', 'com-2'};
  static const Set<String> savingsGoals = {'sav-1', 'sav-2'};
  static const Set<String> inboxItems = {'inbox-1'};
  static const Set<String> parties = {
    'party-abebe',
    'party-landlord',
    'party-boss'
  };

  static bool isKnownSeedId(String id) {
    return accounts.contains(id) ||
        transactions.contains(id) ||
        tasks.contains(id) ||
        notes.contains(id) ||
        projects.contains(id) ||
        goals.contains(id) ||
        events.contains(id) ||
        commitments.contains(id) ||
        savingsGoals.contains(id) ||
        inboxItems.contains(id) ||
        parties.contains(id);
  }
}
