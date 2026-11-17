import 'package:flutter/material.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../constants/daywell_icon_size.dart';
import 'daywell_status_tone.dart';

/// Compact semantic status badge displaying both icon and label text for
/// accessible non-color-only status communication.
class DaywellStatusBadge extends StatelessWidget {
  final String label;
  final DaywellStatusTone tone;
  final IconData? icon;
  final bool showIcon;
  final String? semanticLabel;

  const DaywellStatusBadge({
    super.key,
    required this.label,
    this.tone = DaywellStatusTone.info,
    this.icon,
    this.showIcon = true,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final palette = DaywellStatusTonePalette.resolve(context, tone);
    final effectiveIcon = icon ?? palette.defaultIcon;

    final double? mediaWidth = MediaQuery.maybeSizeOf(context)?.width;
    final double maxFallbackWidth =
        (mediaWidth != null && mediaWidth > 0) ? mediaWidth : 360.0;

    return Semantics(
      label: semanticLabel ?? '${palette.semanticPrefix}: $label',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxFallbackWidth),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SharedDesignTokens.spacingSm,
            vertical: SharedDesignTokens.spacingXs,
          ),
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(SharedDesignTokens.radiusSm),
            border: Border.all(color: palette.border, width: 1.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showIcon) ...[
                ExcludeSemantics(
                  child: Icon(
                    effectiveIcon,
                    size: DaywellIconSize.xs,
                    color: palette.foreground,
                  ),
                ),
                const SizedBox(width: SharedDesignTokens.spacingXs),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DaywellTypography.label(color: palette.foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
