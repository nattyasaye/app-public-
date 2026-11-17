import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/shared_foundation.dart';
import '../../application/inbox/inbox_controller.dart';
import '../app_state.dart';

class QuickCaptureDialog extends StatefulWidget {
  final AppStateManager? state;
  final InboxController? controller;
  final String? initialText;
  final void Function(String rawText)? onOpenExpenseComposer;

  const QuickCaptureDialog({
    super.key,
    this.state,
    this.controller,
    this.initialText,
    this.onOpenExpenseComposer,
  }) : assert(state != null || controller != null,
            'Either state or controller must be provided to QuickCaptureDialog');

  InboxController get effectiveController =>
      controller ?? state!.inboxController;

  @override
  State<QuickCaptureDialog> createState() => _QuickCaptureDialogState();
}

class _QuickCaptureDialogState extends State<QuickCaptureDialog> {
  late TextEditingController _controller;
  String _category = 'task';
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    if (_category == 'expense') {
      final rejected =
          AppStateManager.detectQuickCaptureUnsupportedCurrency(text);
      if (rejected != null) {
        setState(() {
          _errorText =
              'Only ETB amounts are supported in Quick Capture (detected $rejected).';
        });
        return;
      }
    }

    await widget.effectiveController.captureQuickThought(
      text,
      category: _category,
    );

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Captured into Inbox & ${_category.toUpperCase()}!'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openInComposer() {
    final text = _controller.text.trim();
    final rejected =
        AppStateManager.detectQuickCaptureUnsupportedCurrency(text);
    if (rejected != null) {
      setState(() {
        _errorText =
            'Only ETB amounts are supported in Quick Capture (detected $rejected).';
      });
      return;
    }
    final callback = widget.onOpenExpenseComposer;
    if (callback == null) return;
    Navigator.pop(context);
    callback(text);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SharedDesignTokens.radiusXl)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.flash_on_rounded,
                    color: SharedDesignTokens.primaryEmerald),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '1-Tap Quick Capture (<3s)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: (_) {
                if (_errorText != null) {
                  setState(() => _errorText = null);
                }
              },
              decoration: const InputDecoration(
                hintText: 'What is on your mind? (Idea, task, expense...)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text('Save as:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Task'),
                  selected: _category == 'task',
                  onSelected: (sel) => setState(() {
                    _category = 'task';
                    _errorText = null;
                  }),
                ),
                ChoiceChip(
                  label: const Text('Expense'),
                  selected: _category == 'expense',
                  onSelected: (sel) => setState(() {
                    _category = 'expense';
                    _errorText = null;
                  }),
                ),
                ChoiceChip(
                  label: const Text('Note'),
                  selected: _category == 'note',
                  onSelected: (sel) => setState(() {
                    _category = 'note';
                    _errorText = null;
                  }),
                ),
                ChoiceChip(
                  label: const Text('Idea'),
                  selected: _category == 'idea',
                  onSelected: (sel) => setState(() {
                    _category = 'idea';
                    _errorText = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  if (_category == 'expense' &&
                      widget.onOpenExpenseComposer != null)
                    OutlinedButton.icon(
                      onPressed: _openInComposer,
                      icon: const Icon(Icons.account_balance_wallet_outlined,
                          size: 18),
                      label: const Text('Open in Composer'),
                    ),
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SharedDesignTokens.primaryEmerald,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Capture'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
