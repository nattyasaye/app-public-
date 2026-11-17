import 'package:flutter/material.dart';
import '../../../core/theme/daywell_theme.dart';

enum DaywellStatusTone {
  info,
  success,
  warning,
  error,
}

class DaywellStatusTonePalette {
  final Color background;
  final Color foreground;
  final Color border;
  final IconData defaultIcon;
  final String semanticPrefix;

  const DaywellStatusTonePalette({
    required this.background,
    required this.foreground,
    required this.border,
    required this.defaultIcon,
    required this.semanticPrefix,
  });

  static DaywellStatusTonePalette resolve(
    BuildContext context,
    DaywellStatusTone tone,
  ) {
    final semantic = context.daywellColors;
    switch (tone) {
      case DaywellStatusTone.info:
        return DaywellStatusTonePalette(
          background: semantic.infoContainer,
          foreground: semantic.onInfoContainer,
          border: semantic.onInfoContainer.withOpacity(0.24),
          defaultIcon: Icons.info_outline,
          semanticPrefix: 'Info',
        );
      case DaywellStatusTone.success:
        return DaywellStatusTonePalette(
          background: semantic.successContainer,
          foreground: semantic.onSuccessContainer,
          border: semantic.onSuccessContainer.withOpacity(0.24),
          defaultIcon: Icons.check_circle_outline,
          semanticPrefix: 'Success',
        );
      case DaywellStatusTone.warning:
        return DaywellStatusTonePalette(
          background: semantic.warningContainer,
          foreground: semantic.onWarningContainer,
          border: semantic.onWarningContainer.withOpacity(0.28),
          defaultIcon: Icons.warning_amber_rounded,
          semanticPrefix: 'Warning',
        );
      case DaywellStatusTone.error:
        return DaywellStatusTonePalette(
          background: semantic.errorContainer,
          foreground: semantic.onErrorContainer,
          border: semantic.onErrorContainer.withOpacity(0.28),
          defaultIcon: Icons.error_outline,
          semanticPrefix: 'Error',
        );
    }
  }
}
