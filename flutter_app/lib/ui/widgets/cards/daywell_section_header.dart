import 'package:flutter/material.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../buttons/daywell_button.dart';

/// Section header displaying uniform title typography, optional count badge,
/// and trailing navigation action button.
class DaywellSectionHeader extends StatelessWidget {
  final String title;
  final int? count;
  final String? actionLabel;
  final VoidCallback? onActionPressed;

  const DaywellSectionHeader({
    super.key,
    required this.title,
    this.count,
    this.actionLabel,
    this.onActionPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final hasAction = actionLabel != null &&
        actionLabel!.trim().isNotEmpty &&
        onActionPressed != null;

    Widget buildTitleCluster({required bool isBounded}) {
      final titleText = Semantics(
        header: true,
        child: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      );

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          isBounded ? Flexible(child: titleText) : titleText,
          if (count != null) ...[
            const SizedBox(width: SharedDesignTokens.spacingSm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: SharedDesignTokens.spacingSm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(
                  SharedDesignTokens.radiusSm,
                ),
              ),
              child: Text(
                '$count',
                style: DaywellTypography.caption(
                  color: colorScheme.onPrimaryContainer,
                ).copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isBounded = constraints.hasBoundedWidth;
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        final shouldStack = isBounded &&
            hasAction &&
            (constraints.maxWidth < 260 ||
                (constraints.maxWidth < 360 && textScale >= 1.6));

        final Widget? actionButton = hasAction
            ? DaywellButton(
                label: actionLabel!,
                onPressed: onActionPressed,
                variant: DaywellButtonVariant.text,
                size: DaywellButtonSize.compact,
              )
            : null;

        if (!isBounded) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildTitleCluster(isBounded: false),
              if (actionButton != null) ...[
                const SizedBox(width: SharedDesignTokens.spacingSm),
                actionButton,
              ],
            ],
          );
        }

        if (shouldStack && actionButton != null) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildTitleCluster(isBounded: true),
              const SizedBox(height: SharedDesignTokens.spacingXs),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: actionButton,
              ),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: buildTitleCluster(isBounded: true)),
            if (actionButton != null) ...[
              const SizedBox(width: SharedDesignTokens.spacingSm),
              ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: constraints.maxWidth * 0.45),
                child: actionButton,
              ),
            ],
          ],
        );
      },
    );
  }
}
