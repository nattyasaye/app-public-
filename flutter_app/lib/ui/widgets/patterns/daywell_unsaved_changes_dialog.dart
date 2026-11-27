import 'package:flutter/material.dart';

import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../buttons/daywell_button.dart';
import '../constants/daywell_icon_size.dart';

/// User choice resolved from [DaywellUnsavedChangesDialog].
enum DaywellUnsavedChangesAction {
  save,
  discard,
  cancel,
}

/// Shared 3-way prompt (Save / Discard / Cancel) protecting forms and editors
/// from accidental loss on Android Back or dismiss actions.
class DaywellUnsavedChangesDialog extends StatelessWidget {
  final String title;
  final String message;
  final bool showSave;
  final String saveLabel;
  final String discardLabel;
  final String cancelLabel;
  final VoidCallback? onSave;
  final VoidCallback? onDiscard;
  final VoidCallback? onCancel;

  const DaywellUnsavedChangesDialog({
    super.key,
    this.title = 'Unsaved Changes',
    this.message = 'You have unsaved changes. Save before leaving?',
    this.showSave = true,
    this.saveLabel = 'Save',
    this.discardLabel = 'Discard',
    this.cancelLabel = 'Cancel',
    this.onSave,
    this.onDiscard,
    this.onCancel,
  });

  /// Shows [DaywellUnsavedChangesDialog] and resolves to [DaywellUnsavedChangesAction.cancel]
  /// if dismissed via barrier tap or system back.
  static Future<DaywellUnsavedChangesAction> show(
    BuildContext context, {
    String title = 'Unsaved Changes',
    String message = 'You have unsaved changes. Save before leaving?',
    bool showSave = true,
    String saveLabel = 'Save',
    String discardLabel = 'Discard',
    String cancelLabel = 'Cancel',
    bool barrierDismissible = true,
  }) async {
    final result = await showDialog<DaywellUnsavedChangesAction>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (BuildContext dialogContext) => DaywellUnsavedChangesDialog(
        title: title,
        message: message,
        showSave: showSave,
        saveLabel: saveLabel,
        discardLabel: discardLabel,
        cancelLabel: cancelLabel,
        onSave: showSave
            ? () => Navigator.of(dialogContext).pop(
                  DaywellUnsavedChangesAction.save,
                )
            : null,
        onDiscard: () => Navigator.of(dialogContext).pop(
          DaywellUnsavedChangesAction.discard,
        ),
        onCancel: () => Navigator.of(dialogContext).pop(
          DaywellUnsavedChangesAction.cancel,
        ),
      ),
    );
    return result ?? DaywellUnsavedChangesAction.cancel;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.daywellColors;
    final textTheme = theme.textTheme;

    return AlertDialog(
      scrollable: true,
      actionsOverflowButtonSpacing: SharedDesignTokens.spacingSm,
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: ExcludeSemantics(
              child: Icon(
                Icons.warning_amber_rounded,
                size: DaywellIconSize.lg,
                color: semantic.warning,
              ),
            ),
          ),
          const SizedBox(width: SharedDesignTokens.spacingCompact),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title),
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: textTheme.bodyMedium?.copyWith(
          color: semantic.textSecondary,
        ),
      ),
      actions: [
        DaywellButton(
          label: cancelLabel,
          variant: DaywellButtonVariant.text,
          size: DaywellButtonSize.compact,
          onPressed: onCancel ??
              () => Navigator.of(context).pop(
                    DaywellUnsavedChangesAction.cancel,
                  ),
        ),
        DaywellButton(
          label: discardLabel,
          variant: DaywellButtonVariant.destructive,
          size: DaywellButtonSize.compact,
          onPressed: onDiscard ??
              () => Navigator.of(context).pop(
                    DaywellUnsavedChangesAction.discard,
                  ),
        ),
        if (showSave)
          DaywellButton(
            label: saveLabel,
            variant: DaywellButtonVariant.primary,
            size: DaywellButtonSize.compact,
            onPressed: onSave ??
                () => Navigator.of(context).pop(
                      DaywellUnsavedChangesAction.save,
                    ),
          ),
      ],
    );
  }
}
