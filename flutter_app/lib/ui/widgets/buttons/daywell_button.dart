import 'package:flutter/material.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../constants/daywell_icon_size.dart';

enum DaywellButtonVariant {
  primary,
  secondary,
  outlined,
  text,
  destructive,
}

enum DaywellButtonSize {
  regular,
  compact,
}

/// Unified Daywell button built on Material 3 button widgets and Stage 3.3 themes.
class DaywellButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final DaywellButtonVariant variant;
  final DaywellButtonSize size;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool isLoading;
  final bool fullWidth;
  final String? semanticLabel;
  final String? tooltip;

  const DaywellButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = DaywellButtonVariant.primary,
    this.size = DaywellButtonSize.regular,
    this.leadingIcon,
    this.trailingIcon,
    this.isLoading = false,
    this.fullWidth = false,
    this.semanticLabel,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final semantic = context.daywellColors;
    final isDark = theme.brightness == Brightness.dark;
    final isInteractive = onPressed != null && !isLoading;
    final effectiveOnPressed = isInteractive ? onPressed : null;

    final padding = size == DaywellButtonSize.compact
        ? const EdgeInsets.symmetric(
            horizontal: SharedDesignTokens.spacingCompact,
            vertical: SharedDesignTokens.spacingSm,
          )
        : const EdgeInsets.symmetric(
            horizontal: SharedDesignTokens.spacingMd,
            vertical: SharedDesignTokens.spacingCompact,
          );

    final minimumSize = fullWidth
        ? Size(double.infinity, size == DaywellButtonSize.compact ? 40 : 48)
        : Size(48, size == DaywellButtonSize.compact ? 40 : 48);

    final double iconSize = size == DaywellButtonSize.compact
        ? DaywellIconSize.sm
        : DaywellIconSize.md;

    final Color contentColor;
    switch (variant) {
      case DaywellButtonVariant.primary:
        contentColor =
            isInteractive ? colorScheme.onPrimary : semantic.textDisabled;
      case DaywellButtonVariant.secondary:
        contentColor = isInteractive
            ? colorScheme.onPrimaryContainer
            : semantic.textDisabled;
      case DaywellButtonVariant.outlined:
      case DaywellButtonVariant.text:
        contentColor =
            isInteractive ? colorScheme.primary : semantic.textDisabled;
      case DaywellButtonVariant.destructive:
        contentColor = isInteractive
            ? (isDark ? semantic.onErrorContainer : semantic.onError)
            : semantic.textDisabled;
    }

    final String? overrideSemanticLabel =
        semanticLabel ?? (isLoading ? '$label, loading' : null);

    final double? mediaWidth = MediaQuery.maybeSizeOf(context)?.width;
    final double maxFallbackWidth =
        (mediaWidth != null && mediaWidth > 0) ? mediaWidth : 360.0;

    final Widget rawChildContent = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            width: iconSize,
            height: iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              valueColor: AlwaysStoppedAnimation<Color>(contentColor),
            ),
          ),
          const SizedBox(width: SharedDesignTokens.spacingSm),
        ] else if (leadingIcon != null) ...[
          Icon(leadingIcon, size: iconSize),
          const SizedBox(width: SharedDesignTokens.spacingSm),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
        if (!isLoading && trailingIcon != null) ...[
          const SizedBox(width: SharedDesignTokens.spacingSm),
          Icon(trailingIcon, size: iconSize),
        ],
      ],
    );

    final Widget boundedChildContent = fullWidth
        ? rawChildContent
        : ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxFallbackWidth),
            child: rawChildContent,
          );

    final Widget childContent = overrideSemanticLabel != null
        ? Semantics(
            label: overrideSemanticLabel,
            excludeSemantics: true,
            child: boundedChildContent,
          )
        : boundedChildContent;

    final ButtonStyle baseStyle = ButtonStyle(
      minimumSize: WidgetStatePropertyAll<Size>(minimumSize),
      tapTargetSize: MaterialTapTargetSize.padded,
      padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(padding),
    );

    final Widget button;
    switch (variant) {
      case DaywellButtonVariant.primary:
        button = FilledButton(
          onPressed: effectiveOnPressed,
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            disabledBackgroundColor: colorScheme.onSurface.withOpacity(0.12),
            disabledForegroundColor: semantic.textDisabled,
          ).merge(baseStyle),
          child: childContent,
        );
      case DaywellButtonVariant.secondary:
        button = FilledButton.tonal(
          onPressed: effectiveOnPressed,
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primaryContainer,
            foregroundColor: colorScheme.onPrimaryContainer,
            disabledBackgroundColor: colorScheme.onSurface.withOpacity(0.12),
            disabledForegroundColor: semantic.textDisabled,
          ).merge(baseStyle),
          child: childContent,
        );
      case DaywellButtonVariant.outlined:
        button = OutlinedButton(
          onPressed: effectiveOnPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: colorScheme.primary,
            disabledForegroundColor: semantic.textDisabled,
            side: BorderSide(
              color: isInteractive ? colorScheme.outline : semantic.border,
              width: 1.0,
            ),
          ).merge(baseStyle),
          child: childContent,
        );
      case DaywellButtonVariant.text:
        button = TextButton(
          onPressed: effectiveOnPressed,
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.primary,
            disabledForegroundColor: semantic.textDisabled,
          ).merge(baseStyle),
          child: childContent,
        );
      case DaywellButtonVariant.destructive:
        final bg = isDark ? semantic.errorContainer : semantic.error;
        final fg = isDark ? semantic.onErrorContainer : semantic.onError;
        button = FilledButton(
          onPressed: effectiveOnPressed,
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            disabledBackgroundColor: colorScheme.onSurface.withOpacity(0.12),
            disabledForegroundColor: semantic.textDisabled,
            side: isDark && isInteractive
                ? BorderSide(
                    color: semantic.onErrorContainer.withOpacity(0.35),
                    width: 1.0,
                  )
                : BorderSide.none,
          ).merge(baseStyle),
          child: childContent,
        );
    }

    Widget result =
        fullWidth ? SizedBox(width: double.infinity, child: button) : button;

    if (tooltip != null && tooltip!.isNotEmpty) {
      result = Tooltip(message: tooltip!, child: result);
    }

    return result;
  }
}

/// Accessible icon-only button enforcing minimum 48x48 touch targets and tooltips.
class DaywellIconButton extends StatelessWidget {
  final IconData icon;
  final IconData? selectedIcon;
  final String tooltip;
  final String? semanticLabel;
  final VoidCallback? onPressed;
  final bool isSelected;
  final bool isDestructive;
  final double iconSize;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const DaywellIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selectedIcon,
    this.semanticLabel,
    this.isSelected = false,
    this.isDestructive = false,
    this.iconSize = DaywellIconSize.lg,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final semantic = context.daywellColors;

    final Color effectiveForeground = foregroundColor ??
        (isDestructive
            ? colorScheme.error
            : isSelected
                ? colorScheme.primary
                : semantic.textSecondary);

    final Color? effectiveBackground =
        backgroundColor ?? (isSelected ? colorScheme.primaryContainer : null);

    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      isSelected: isSelected,
      iconSize: iconSize,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        tapTargetSize: MaterialTapTargetSize.padded,
        backgroundColor: effectiveBackground,
        foregroundColor: effectiveForeground,
        disabledForegroundColor: semantic.textDisabled,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SharedDesignTokens.radiusSm),
        ),
      ),
      icon: Icon(
        isSelected && selectedIcon != null ? selectedIcon : icon,
        semanticLabel: semanticLabel,
      ),
    );
  }
}
