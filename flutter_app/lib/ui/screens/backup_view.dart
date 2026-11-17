import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_state.dart';
import '../../core/interfaces/platform_service_interfaces.dart';
import '../../core/shared_foundation.dart';
import '../../core/shared_foundation_bridge.dart';
import '../../services/backup/encryption_backup_service.dart';

class BackupView extends StatefulWidget {
  final AppStateManager state;
  final VoidCallback? onBack;

  const BackupView({
    super.key,
    required this.state,
    this.onBack,
  });

  @override
  State<BackupView> createState() => _BackupViewState();
}

class _BackupViewState extends State<BackupView> {
  final _passphraseController = TextEditingController();
  final _restorePayloadController = TextEditingController();
  final _restorePassphraseController = TextEditingController();
  final _canonicalJsonController = TextEditingController();

  bool _obscureExport = true;
  bool _obscureRestore = true;
  bool _isProcessing = false;
  String? _exportedPayload;

  @override
  void dispose() {
    _passphraseController.dispose();
    _restorePayloadController.dispose();
    _restorePassphraseController.dispose();
    _canonicalJsonController.dispose();
    super.dispose();
  }

  Future<void> _handleExportCanonical() async {
    setState(() => _isProcessing = true);
    try {
      final json = await SharedFoundationBridge.exportCanonicalSnapshotJson(
        widget.state,
      );
      if (!mounted) return;
      setState(() {
        _canonicalJsonController.text = json;
        _isProcessing = false;
      });
      unawaited(Clipboard.setData(ClipboardData(text: json)));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Canonical Shared Database copied to clipboard!')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Canonical export failed: $e')),
      );
    }
  }

  Future<void> _handleImportCanonical() async {
    final text = _canonicalJsonController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please paste a shared foundation JSON payload.')),
      );
      return;
    }
    setState(() => _isProcessing = true);
    final result = await SharedFoundationBridge.importFromCanonicalJsonDetailed(
      widget.state,
      text,
    );
    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (result.success) {
      final warningSuffix = result.warnings.isNotEmpty
          ? ' (${result.warnings.length} non-fatal warning(s))'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Successfully loaded shared foundation state!$warningSuffix',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Import rejected (existing data preserved): '
            '${result.message ?? 'Invalid canonical payload.'}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleExport() async {
    final pass = _passphraseController.text.trim();
    if (pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a secret passphrase')),
      );
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final encrypted = await widget.state.exportEncryptedBackup(pass);
      if (!mounted) return;
      setState(() {
        _exportedPayload = encrypted;
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Encrypted backup generated (AES-GCM-256)!')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  Future<void> _handleRestore() async {
    final payload = _restorePayloadController.text.trim();
    final pass = _restorePassphraseController.text.trim();

    if (payload.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Enter both encrypted backup payload and passphrase')),
      );
      return;
    }

    try {
      EncryptionBackupService.validateAndParseEnvelope(payload);
    } on BackupValidationException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Restore failed (original database preserved): ${e.message}',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quarantine & Restore Backup?'),
        content: const Text(
          'Your current local database files will be safely quarantined before importing this .daywell backup. If decryption or verification fails, your previous database is restored automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Quarantine & Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isProcessing = true);
    final result =
        await widget.state.restoreFromEncryptedBackupDetailed(payload, pass);
    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (result.success) {
      _restorePayloadController.clear();
      _restorePassphraseController.clear();
      final warningSuffix = result.warnings.isNotEmpty
          ? ' (${result.warnings.length} non-fatal warning(s))'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Database restored cleanly via quarantine swap and verified!$warningSuffix',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Restore failed (original database preserved): '
            '${result.message ?? 'Verification failed.'}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading:
            widget.onBack != null ? BackButton(onPressed: widget.onBack) : null,
        title: const Text('Backup & Offline Security'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Offline Security Badge
          Card(
            color: Colors.green.shade50,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.verified_user,
                      color: Colors.green, size: 36),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '100% Offline Sovereignty',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.green),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'No cloud servers, no trackers, zero remote dependencies. All data is kept locally on your phone.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.green.shade900),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Shared Foundation Cross-Platform Sync Card
          Card(
            color: SharedDesignTokens.secondaryMint.withOpacity(0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SharedDesignTokens.radiusLg),
              side: const BorderSide(
                  color: SharedDesignTokens.primaryEmerald, width: 1.2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: SharedDesignTokens.primaryEmerald,
                          borderRadius: BorderRadius.circular(
                              SharedDesignTokens.radiusSm),
                        ),
                        child: const Icon(Icons.sync_alt,
                            color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Shared Foundation Bridge',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: SharedDesignTokens.primaryEmerald),
                            ),
                            Text(
                              'AI Agent Web Preview & Android Bi-Directional Sync',
                              style:
                                  TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Sync your data directly between the AI Agent Web Preview and this Android app using the shared canonical database schema.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor:
                                  SharedDesignTokens.primaryEmerald),
                          onPressed: _handleExportCanonical,
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Export & Copy JSON',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  SharedDesignTokens.primaryEmerald),
                          onPressed: _handleImportCanonical,
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('Import Pasted JSON',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _canonicalJsonController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Paste shared canonical JSON payload here...',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Database Statistics
          Text('Local Database Statistics',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _StatRow(
                      label: 'Total Tasks',
                      value:
                          '${widget.state.tasksController.state.tasks.length}'),
                  const Divider(),
                  _StatRow(
                      label: 'Projects',
                      value:
                          '${widget.state.tasksController.state.projects.length}'),
                  const Divider(),
                  _StatRow(
                      label: 'Finance User Accounts',
                      value:
                          '${widget.state.financeController.state.activeUserAccounts.length}'),
                  const Divider(),
                  _StatRow(
                      label: 'Active Journal Entries',
                      value:
                          '${widget.state.financeController.state.activeJournalEntries.length}'),
                  const Divider(),
                  _StatRow(
                      label: 'Ledger Postings',
                      value:
                          '${widget.state.financeController.state.postings.length}'),
                  const Divider(),
                  _StatRow(
                      label: 'Monthly Category Budgets',
                      value:
                          '${widget.state.financeController.state.budgets.length}'),
                  const Divider(),
                  _StatRow(
                      label: 'Recurring Rules',
                      value:
                          '${widget.state.financeController.state.recurringRules.length}'),
                  const Divider(),
                  _StatRow(
                      label: 'Commitments & Bills',
                      value:
                          '${widget.state.financeController.state.commitments.length}'),
                  const Divider(),
                  _StatRow(
                      label: 'Savings Goals',
                      value:
                          '${widget.state.financeController.state.savingsGoals.length}'),
                  const Divider(),
                  _StatRow(
                      label: 'Notes & Reflections',
                      value:
                          '${widget.state.notesController.state.notes.length}'),
                  const Divider(),
                  _StatRow(
                      label: 'Calendar Events',
                      value:
                          '${widget.state.calendarController.state.events.length}'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Export Encrypted Backup Card
          Text('Export Encrypted Backup (.daywell)',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Derives an encryption key via PBKDF2 (100,000 rounds) and seals entire SQLite state with AES-GCM-256 authenticated encryption.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passphraseController,
                    obscureText: _obscureExport,
                    decoration: InputDecoration(
                      labelText: 'Master Passphrase *',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureExport
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () =>
                            setState(() => _obscureExport = !_obscureExport),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _handleExport,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.lock_outline),
                    label: const Text('Generate Encrypted Backup'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  if (_exportedPayload != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Text('Encrypted Envelope Ready',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12)),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy, size: 18),
                                tooltip: 'Copy to Clipboard',
                                onPressed: () {
                                  unawaited(
                                    Clipboard.setData(
                                      ClipboardData(text: _exportedPayload!),
                                    ),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Backup envelope copied to clipboard!')),
                                  );
                                },
                              ),
                            ],
                          ),
                          Text(
                            '${_exportedPayload!.substring(0, 120)}...',
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Restore Backup Card
          Text('Restore from Encrypted Backup',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _restorePayloadController,
                    decoration: const InputDecoration(
                      labelText: 'Paste Encrypted Backup JSON',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _restorePassphraseController,
                    obscureText: _obscureRestore,
                    decoration: InputDecoration(
                      labelText: 'Passphrase *',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureRestore
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () =>
                            setState(() => _obscureRestore = !_obscureRestore),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _handleRestore,
                    icon: const Icon(Icons.restore),
                    label: const Text('Decrypt & Restore State'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          const SizedBox(width: 8),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }
}
