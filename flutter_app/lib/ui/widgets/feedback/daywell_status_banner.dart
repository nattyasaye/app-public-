import 'package:flutter/material.dart';
import '../../../core/shared_foundation.dart';
import '../buttons/daywell_button.dart';
import '../constants/daywell_icon_size.dart';
import 'daywell_status_tone.dart';

/// Semantic inline status banner with icon, optional title, message, optional
/// action button, and optional dismiss control.
class DaywellStatusBanner extends StatelessWidget {
  final String message;
  final String? title;
  final DaywellStatusTone tone;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onActionPressed;
  final VoidCallback? onDismiss;
  final String? semanticLabel;
  final bool liveRegion;

  const DaywellStatusBanner({
    super.key,
    required this.message,
    this.title,
    this.tone = DaywellStatusTone.info,
    this.icon,
    this.actionLabel,
    this.onActionPressed,
    this.onDismiss,
    this.semanticLabel,
    this.liveRegion = false,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = DaywellStatusTonePalette.resolve(context, tone);
    final effectiveIcon = icon ?? palette.defaultIcon;
    final effectiveMessageLabel = semanticLabel ??
        '${palette.semanticPrefix}: ${title != null && title!.isNotEmpty ? '$title. $message' : message}';

    final double? mediaWidth = MediaQuery.maybeSizeOf(context)?.width;
    final double maxFallbackWidth =
        (mediaWidth != null && mediaWidth > 0) ? mediaWidth : 360.0;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      liveRegion: liveRegion,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxFallbackWidth),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(SharedDesignTokens.radiusMd),
            border: Border.all(color: palette.border, width: 1.0),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: ExcludeSemantics(
                  child: Icon(
                    effectiveIcon,
                    size: DaywellIconSize.md,
                    color: palette.foreground,
                  ),
                ),
              ),
              const SizedBox(width: SharedDesignTokens.spacingCompact),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      label: effectiveMessageLabel,
                      excludeSemantics: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (title != null && title!.isNotEmpty) ...[
                            Text(
                              title!,
                              style: textTheme.titleSmall?.copyWith(
                                color: palette.foreground,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(
                                height: SharedDesignTokens.spacingXs),
                          ],
                          Text(
                            message,
                            style: textTheme.bodySmall?.copyWith(
                              color: palette.foreground,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (actionLabel != null &&
                        actionLabel!.trim().isNotEmpty &&
                        onActionPressed != null) ...[
                      const SizedBox(height: SharedDesignTokens.spacingSm),
                      TextButton(
                        onPressed: onActionPressed,
                        style: TextButton.styleFrom(
                          foregroundColor: palette.foreground,
                          minimumSize: const Size(48, 48),
                          tapTargetSize: MaterialTapTargetSize.padded,
                          padding: const EdgeInsets.symmetric(
                            horizontal: SharedDesignTokens.spacingSm,
                            vertical: SharedDesignTokens.spacingXs,
                          ),
                        ),
                        child: Text(
                          actionLabel!,
                          style: textTheme.labelLarge?.copyWith(
                            color: palette.foreground,
                            decoration: TextDecoration.underline,
                            decorationColor: palette.foreground,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onDismiss != null)
                DaywellIconButton(
                  icon: Icons.close,
                  tooltip: 'Dismiss',
                  iconSize: DaywellIconSize.md,
                  foregroundColor: palette.foreground,
                  onPressed: onDismiss,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
