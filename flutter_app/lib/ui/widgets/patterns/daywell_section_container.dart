import 'package:flutter/material.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../cards/daywell_card.dart';
import '../cards/daywell_section_header.dart';

/// Composed section wrapper pairing an optional [DaywellSectionHeader] and
/// subtitle with optional [DaywellCard] surface framing and footer content.
///
/// Leaves navigation, persistence, and screen state entirely to callers.
class DaywellSectionContainer extends StatelessWidget {
  final String? title;
  final int? count;
  final String? actionLabel;
  final VoidCallback? onActionPressed;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  final bool useCard;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? contentPadding;

  const DaywellSectionContainer({
    super.key,
    required this.child,
    this.title,
    this.count,
    this.actionLabel,
    this.onActionPressed,
    this.subtitle,
    this.footer,
    this.useCard = false,
    this.padding,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final hasTitle = title != null && title!.trim().isNotEmpty;
    final hasSubtitle = subtitle != null && subtitle!.trim().isNotEmpty;

    final Widget body = useCard
        ? DaywellCard(
            padding: contentPadding ??
                const EdgeInsets.all(SharedDesignTokens.spacingMd),
            child: child,
          )
        : (contentPadding != null
            ? Padding(padding: contentPadding!, child: child)
            : child);

    final Widget column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasTitle)
          DaywellSectionHeader(
            title: title!,
            count: count,
            actionLabel: actionLabel,
            onActionPressed: onActionPressed,
          ),
        if (hasSubtitle) ...[
          if (hasTitle) const SizedBox(height: SharedDesignTokens.spacingXs),
          Text(
            subtitle!,
            style: textTheme.bodySmall?.copyWith(
              color: semantic.textSecondary,
            ),
          ),
        ],
        if (hasTitle || hasSubtitle)
          const SizedBox(height: SharedDesignTokens.spacingSm),
        body,
        if (footer != null) ...[
          const SizedBox(height: SharedDesignTokens.spacingSm),
          footer!,
        ],
      ],
    );

    if (padding != null) {
      return Padding(padding: padding!, child: column);
    }

    return column;
  }
}
