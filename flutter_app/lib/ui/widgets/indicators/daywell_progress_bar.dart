import 'package:flutter/material.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../feedback/daywell_status_tone.dart';

/// Accessible themed linear progress bar supporting determinate and
/// indeterminate states with optional label and value readout.
class DaywellProgressBar extends StatelessWidget {
  final double? value;
  final String? label;
  final String? valueText;
  final DaywellStatusTone? tone;
  final double minHeight;
  final String? semanticLabel;

  const DaywellProgressBar({
    super.key,
    this.value,
    this.label,
    this.valueText,
    this.tone,
    this.minHeight = 8.0,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final semantic = context.daywellColors;
    final textTheme = theme.textTheme;

    final double? clampedValue =
        (value != null && value!.isFinite) ? value!.clamp(0.0, 1.0) : null;
    final palette =
        tone != null ? DaywellStatusTonePalette.resolve(context, tone!) : null;

    final indicatorColor = palette?.foreground ?? colorScheme.primary;
    final trackColor = palette?.background ?? semantic.surfaceSubtle;

    final String? computedSemanticValue = valueText ??
        (clampedValue != null ? '${(clampedValue * 100).round()}%' : null);

    final double? mediaWidth = MediaQuery.maybeSizeOf(context)?.width;
    final double maxFallbackWidth =
        (mediaWidth != null && mediaWidth > 0) ? mediaWidth : 360.0;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final hasLabel = label != null && label!.isNotEmpty;
    final hasValueText = valueText != null && valueText!.isNotEmpty;

    return Semantics(
      label: semanticLabel ?? label ?? 'Progress',
      value: computedSemanticValue,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxFallbackWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasLabel || hasValueText) ...[
              if (textScale >= 1.6 && hasLabel && hasValueText)
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: SharedDesignTokens.spacingSm,
                    runSpacing: SharedDesignTokens.spacingXs,
                    children: [
                      Text(
                        label!,
                        style: textTheme.labelMedium?.copyWith(
                          color: semantic.textSecondary,
                        ),
                      ),
                      Text(
                        valueText!,
                        style: DaywellTypography.label(
                            color: semantic.textPrimary),
                      ),
                    ],
                  ),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    if (hasLabel)
                      Expanded(
                        child: Text(
                          label!,
                          style: textTheme.labelMedium?.copyWith(
                            color: semantic.textSecondary,
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    if (hasValueText) ...[
                      const SizedBox(width: SharedDesignTokens.spacingSm),
                      Flexible(
                        child: Text(
                          valueText!,
                          textAlign: TextAlign.end,
                          style: DaywellTypography.label(
                            color: semantic.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              const SizedBox(height: SharedDesignTokens.spacingXs),
            ],
            ClipRRect(
              borderRadius:
                  BorderRadius.circular(SharedDesignTokens.radiusFull),
              child: LinearProgressIndicator(
                value: clampedValue,
                minHeight: minHeight,
                backgroundColor: trackColor,
                valueColor: AlwaysStoppedAnimation<Color>(indicatorColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
