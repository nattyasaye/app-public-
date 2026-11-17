import 'package:flutter/material.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';

/// Accessible themed loading indicator supporting inline and centered layouts.
class DaywellLoadingIndicator extends StatelessWidget {
  final String? label;
  final double size;
  final double strokeWidth;
  final bool inline;
  final String? semanticLabel;
  final bool liveRegion;

  const DaywellLoadingIndicator({
    super.key,
    this.label,
    this.size = 24.0,
    this.strokeWidth = 2.5,
    this.inline = false,
    this.semanticLabel,
    this.liveRegion = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final semantic = context.daywellColors;
    final textTheme = theme.textTheme;

    final spinner = SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
      ),
    );

    final effectiveLabel = semanticLabel ?? label ?? 'Loading';

    final double? mediaWidth = MediaQuery.maybeSizeOf(context)?.width;
    final double maxFallbackWidth =
        (mediaWidth != null && mediaWidth > 0) ? mediaWidth : 360.0;

    if (inline) {
      return Semantics(
        label: effectiveLabel,
        liveRegion: liveRegion,
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxFallbackWidth),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              spinner,
              if (label != null && label!.isNotEmpty) ...[
                const SizedBox(width: SharedDesignTokens.spacingCompact),
                Flexible(
                  child: Text(
                    label!,
                    style: textTheme.bodySmall?.copyWith(
                      color: semantic.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Semantics(
      label: effectiveLabel,
      liveRegion: liveRegion,
      excludeSemantics: true,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            spinner,
            if (label != null && label!.isNotEmpty) ...[
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              Text(
                label!,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: semantic.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
