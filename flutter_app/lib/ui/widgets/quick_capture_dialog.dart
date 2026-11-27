import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/shared_foundation.dart';
import '../../application/inbox/inbox_controller.dart';
import '../app_state.dart';
import 'shared_ui_widgets.dart';

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
  bool _didSave = false;
  bool _isPromptingDiscard = false;
  bool _lastHasUnsaved = false;

  bool get _hasUnsavedUserInput =>
      !_didSave &&
      _controller.text.trim().isNotEmpty &&
      _controller.text.trim() != (widget.initialText ?? '').trim();

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
              'Daywell Finance supports ETB only. Please enter this amount in ETB (detected $rejected).';
        });
        return;
      }
    }

    await widget.effectiveController.captureQuickThought(
      text,
      category: _category,
    );

    if (!mounted) return;
    _didSave = true;
    Navigator.pop(context);
    final confirmation = (_category == 'task' || _category == 'idea')
        ? 'Captured to Inbox — convert to Task anytime'
        : _category == 'note'
            ? 'Captured & saved to Notes'
            : _category == 'expense'
                ? 'Captured into Inbox & Expense'
                : 'Captured to Inbox';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(confirmation),
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
            'Daywell Finance supports ETB only. Please enter this amount in ETB (detected $rejected).';
      });
      return;
    }
    final callback = widget.onOpenExpenseComposer;
    if (callback == null) return;
    _didSave = true;
    Navigator.pop(context);
    callback(text);
  }

  Future<void> _handleDiscardPrompt() async {
    if (_isPromptingDiscard || !mounted) return;
    _isPromptingDiscard = true;
    try {
      final action = await DaywellUnsavedChangesDialog.show(
        context,
        title: 'Discard Quick Capture?',
        message: 'Capture this thought before closing, or discard your edits?',
        saveLabel: 'Capture',
        discardLabel: 'Discard',
      );
      if (!mounted) return;
      if (action == DaywellUnsavedChangesAction.save) {
        await _save();
      } else if (action == DaywellUnsavedChangesAction.discard) {
        setState(() => _didSave = true);
        Navigator.of(context).pop();
      }
    } finally {
      _isPromptingDiscard = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_hasUnsavedUserInput,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) {
          unawaited(_handleDiscardPrompt());
        }
      },
      child: Dialog(
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
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                onChanged: (_) {
                  final nextHasUnsaved = _hasUnsavedUserInput;
                  if (_errorText != null || nextHasUnsaved != _lastHasUnsaved) {
                    setState(() {
                      _errorText = null;
                      _lastHasUnsaved = nextHasUnsaved;
                    });
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
                      onPressed: () => Navigator.of(context).maybePop(),
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
      ),
    );
  }
}
