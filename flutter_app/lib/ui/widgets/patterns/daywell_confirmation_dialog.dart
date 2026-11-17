import 'package:flutter/material.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../buttons/daywell_button.dart';
import '../constants/daywell_icon_size.dart';

/// Composed confirmation dialog built on [AlertDialog] (styled via centralized
/// [DialogTheme]) and [DaywellButton] actions for safe/destructive confirmation flows.
class DaywellConfirmationDialog extends StatelessWidget {
  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;
  final bool isDestructive;
  final IconData? icon;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;

  const DaywellConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    this.cancelLabel = 'Cancel',
    this.confirmLabel = 'Confirm',
    this.isDestructive = false,
    this.icon,
    this.onCancel,
    this.onConfirm,
  });

  /// Displays a [DaywellConfirmationDialog] and resolves to `true` when
  /// confirmed or `false` when cancelled or barrier-dismissed.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String cancelLabel = 'Cancel',
    String confirmLabel = 'Confirm',
    bool isDestructive = false,
    IconData? icon,
    bool barrierDismissible = true,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (dialogContext) => DaywellConfirmationDialog(
        title: title,
        message: message,
        cancelLabel: cancelLabel,
        confirmLabel: confirmLabel,
        isDestructive: isDestructive,
        icon: icon,
        onCancel: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final semantic = context.daywellColors;
    final textTheme = theme.textTheme;

    final Color effectiveIconColor =
        isDestructive ? colorScheme.error : colorScheme.primary;

    return AlertDialog(
      scrollable: true,
      actionsOverflowButtonSpacing: SharedDesignTokens.spacingSm,
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: ExcludeSemantics(
                child: Icon(
                  icon,
                  size: DaywellIconSize.lg,
                  color: effectiveIconColor,
                ),
              ),
            ),
            const SizedBox(width: SharedDesignTokens.spacingCompact),
          ],
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
          onPressed: onCancel ?? () => Navigator.of(context).maybePop(false),
        ),
        DaywellButton(
          label: confirmLabel,
          variant: isDestructive
              ? DaywellButtonVariant.destructive
              : DaywellButtonVariant.primary,
          size: DaywellButtonSize.compact,
          onPressed: onConfirm ?? () => Navigator.of(context).maybePop(true),
        ),
      ],
    );
  }
}
