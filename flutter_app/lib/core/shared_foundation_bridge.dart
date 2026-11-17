// SHARED FOUNDATION BRIDGE (Flutter Android)
// Handles bi-directional synchronization with the canonical shared database JSON payload.

import 'dart:convert';
import '../domain/finance/double_entry_engine.dart';
import '../ui/app_state.dart';
import 'date/shared_date.dart';
import 'interfaces/platform_service_interfaces.dart';
import 'shared_foundation_core.dart';

class SharedFoundationBridge {
  static const int schemaVersion = 5;
  static const int snapshotFormatVersion = 2;
  static const String appVersion = '1.0.2+3';

  /// Exports the complete authoritative SQLite database snapshot as canonical
  /// JSON, preserving life Goals, goalId links, double-entry ledger, and multi-day events.
  static Future<String> exportCanonicalSnapshotJson(
    AppStateManager state,
  ) async {
    final snapshot = await state.exportSnapshot();
    return const JsonEncoder.withIndent('  ').convert(snapshot);
  }

  /// Synchronous controller-state serializer retained for callers without async context.
  /// Prefer [exportCanonicalSnapshotJson] for full SQLite persistence fidelity.
  static String exportToCanonicalJson(
    AppStateManager state, {
    List<Map<String, dynamic>> goals = const [],
  }) {
    final Map<String, dynamic> payload = {
      'schemaVersion': schemaVersion,
      'snapshotFormatVersion': snapshotFormatVersion,
      'appVersion': appVersion,
      'exportedAt': LocalDateTime.now().toEthiopiaIsoString(),
      'isFinanceSetupCompleted': state.financeController.state.isSetupCompleted,
      'openingBalanceCents': state.financeController.state.openingBalanceCents,
      'accounts': state.financeController.state.accounts
          .map((a) => a.toJson())
          .toList(),
      'categories': state.financeController.state.categories
          .map((c) => c.toJson())
          .toList(),
      'transactions': state.financeController.state.transactions
          .map((t) => t.toJson())
          .toList(),
      'commitments': state.financeController.state.commitments
          .map((c) => c.toJson())
          .toList(),
      'tasks':
          state.tasksController.state.tasks.map((t) => t.toJson()).toList(),
      'projects':
          state.tasksController.state.projects.map((p) => p.toJson()).toList(),
      'milestones': state.tasksController.state.milestones
          .map((m) => m.toJson())
          .toList(),
      'goals': goals,
      'savingsGoals': state.financeController.state.savingsGoals
          .map((g) => g.toJson())
          .toList(),
      'notes':
          state.notesController.state.notes.map((n) => n.toJson()).toList(),
      'inboxItems':
          state.inboxController.state.items.map((i) => i.toJson()).toList(),
      'calendarEvents':
          state.calendarController.state.events.map((e) => e.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Imports a canonical shared database JSON payload atomically into SQLite
  /// and returns structured validation/import diagnostics.
  static Future<BackupRestoreResult> importFromCanonicalJsonDetailed(
    AppStateManager state,
    String jsonString,
  ) async {
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonString);
    } on FormatException catch (e) {
      return BackupRestoreResult.failure(
        BackupFailureKind.invalidPayload,
        'Invalid JSON payload: ${e.message}',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      return const BackupRestoreResult.failure(
        BackupFailureKind.invalidPayload,
        'Canonical JSON payload must be a JSON object.',
      );
    }
    return await state.importCanonicalSnapshotDetailed(decoded);
  }

  /// Imports a canonical shared database JSON payload atomically into SQLite
  /// and rehydrates all module controllers.
  static Future<bool> importFromCanonicalJson(
    AppStateManager state,
    String jsonString,
  ) async {
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonString);
    } on FormatException catch (_) {
      return false;
    }
    if (decoded is! Map<String, dynamic>) {
      return false;
    }
    return await state.importCanonicalSnapshot(decoded);
  }

  /// Verifies mathematical consistency of the state against SharedBusinessRules.
  static Map<String, dynamic> auditConsistency(AppStateManager state) {
    final activeAssetAccs = state.financeController.state.accounts
        .where(
          (a) =>
              DoubleEntryEngine.isActiveVerifiedEtbAccount(a) &&
              a.type == AccountType.asset &&
              (a.subType.isLiquid || a.subType.isSavingsVault) &&
              !a.name.toLowerCase().contains('receivable'),
        )
        .toList();

    int computedCombinedCents = 0;
    final Map<String, int> accountBalances = {};

    for (final acc in activeAssetAccs) {
      final bal = state.financeController.state.getAccountBalanceCents(acc);
      accountBalances[acc.id] = bal;
      computedCombinedCents += bal;
    }

    final combinedBalance = state.financeController.state.combinedBalanceCents;
    final isBalanced = computedCombinedCents == combinedBalance;

    return {
      'isConsistent': isBalanced,
      'activeAccountsCount': activeAssetAccs.length,
      'combinedBalanceCents': combinedBalance,
      'computedCombinedCents': computedCombinedCents,
      'accountBalances': accountBalances,
      'currency': SharedBusinessRules.currencyCode,
    };
  }
}
