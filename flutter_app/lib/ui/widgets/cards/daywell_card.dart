import 'package:flutter/material.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';

/// Standardized card container respecting theme brightness and Daywell design tokens.
class DaywellCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Color? borderColor;
  final double? elevation;
  final VoidCallback? onTap;
  final double borderRadius;

  const DaywellCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.borderColor,
    this.elevation,
    this.onTap,
    this.borderRadius = SharedDesignTokens.radiusMd,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final cardBg = color ?? semantic.card;
    final effectiveBorderColor = borderColor ?? semantic.border;
    final effectiveElevation = elevation ?? SharedDesignTokens.elevationNone;

    final Widget paddedChild =
        padding != null ? Padding(padding: padding!, child: child) : child;

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      side: BorderSide(color: effectiveBorderColor, width: 1.0),
    );

    final colorScheme = Theme.of(context).colorScheme;

    final Widget cardWidget = Material(
      color: cardBg,
      surfaceTintColor: Colors.transparent,
      elevation: effectiveElevation,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap != null
          ? InkWell(
              onTap: onTap,
              focusColor: colorScheme.primary.withOpacity(0.12),
              hoverColor: colorScheme.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(borderRadius),
              child: paddedChild,
            )
          : paddedChild,
    );

    if (margin != null) {
      return Padding(padding: margin!, child: cardWidget);
    }

    return cardWidget;
  }
}
