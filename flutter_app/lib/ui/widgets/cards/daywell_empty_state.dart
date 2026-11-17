import 'package:flutter/material.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../buttons/daywell_button.dart';
import '../constants/daywell_icon_size.dart';

/// Reusable zero-state widget providing uniform typography, spacing, and CTA layout
/// across Daywell modules without forcing identical imagery or copy.
class DaywellEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onActionPressed;
  final double iconSize;

  const DaywellEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.subtitle,
    this.actionLabel,
    this.onActionPressed,
    this.iconSize = DaywellIconSize.hero,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SharedDesignTokens.spacingLg,
            vertical: SharedDesignTokens.spacingXl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Icon(
                  icon,
                  size: iconSize,
                  color: semantic.textMuted,
                ),
              ),
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              Text(
                message,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: semantic.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: SharedDesignTokens.spacingSm),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: semantic.textMuted,
                  ),
                ),
              ],
              if (actionLabel != null &&
                  actionLabel!.trim().isNotEmpty &&
                  onActionPressed != null) ...[
                const SizedBox(height: SharedDesignTokens.spacingMd),
                DaywellButton(
                  label: actionLabel!,
                  leadingIcon: Icons.add,
                  onPressed: onActionPressed,
                  variant: DaywellButtonVariant.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
