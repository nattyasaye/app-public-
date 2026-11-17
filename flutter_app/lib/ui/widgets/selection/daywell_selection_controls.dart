import 'package:flutter/material.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';

/// Labeled switch tile wrapped around Material [SwitchListTile] with accessible
/// full-row touch interaction and Stage 3.3 theme integration.
class DaywellSwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? leading;
  final bool enabled;
  final String? semanticLabel;
  final EdgeInsetsGeometry? contentPadding;

  const DaywellSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.leading,
    this.enabled = true,
    this.semanticLabel,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final semantic = context.daywellColors;
    final textTheme = theme.textTheme;
    final isInteractive = enabled && onChanged != null;

    final Widget titleWidget = Text(
      title,
      style: textTheme.bodyMedium?.copyWith(
        color: isInteractive ? semantic.textPrimary : semantic.textDisabled,
        fontWeight: FontWeight.w500,
      ),
    );

    return SwitchListTile(
      value: value,
      onChanged: isInteractive ? onChanged : null,
      secondary: leading,
      activeColor: colorScheme.onPrimary,
      activeTrackColor: colorScheme.primary,
      inactiveThumbColor: semantic.textSecondary,
      inactiveTrackColor: semantic.surfaceSubtle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SharedDesignTokens.radiusMd),
      ),
      contentPadding: contentPadding ??
          const EdgeInsets.symmetric(
            horizontal: SharedDesignTokens.spacingCompact,
            vertical: SharedDesignTokens.spacingXs,
          ),
      title: semanticLabel != null
          ? Semantics(
              label: semanticLabel,
              excludeSemantics: true,
              child: titleWidget,
            )
          : titleWidget,
      subtitle: subtitle != null && subtitle!.isNotEmpty
          ? Text(
              subtitle!,
              style: textTheme.bodySmall?.copyWith(
                color: isInteractive
                    ? semantic.textSecondary
                    : semantic.textDisabled,
              ),
            )
          : null,
    );
  }
}

/// Labeled checkbox tile wrapped around Material [CheckboxListTile] with
/// accessible full-row interaction and Stage 3.3 theme integration.
class DaywellCheckboxTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool? value;
  final bool tristate;
  final ValueChanged<bool?>? onChanged;
  final Widget? secondary;
  final ListTileControlAffinity controlAffinity;
  final bool enabled;
  final String? semanticLabel;
  final EdgeInsetsGeometry? contentPadding;

  const DaywellCheckboxTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.tristate = false,
    this.secondary,
    this.controlAffinity = ListTileControlAffinity.leading,
    this.enabled = true,
    this.semanticLabel,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final semantic = context.daywellColors;
    final textTheme = theme.textTheme;
    final isInteractive = enabled && onChanged != null;

    final Widget titleWidget = Text(
      title,
      style: textTheme.bodyMedium?.copyWith(
        color: isInteractive ? semantic.textPrimary : semantic.textDisabled,
        fontWeight: FontWeight.w500,
      ),
    );

    return CheckboxListTile(
      value: value,
      tristate: tristate,
      onChanged: isInteractive ? onChanged : null,
      secondary: secondary,
      controlAffinity: controlAffinity,
      activeColor: colorScheme.primary,
      checkColor: colorScheme.onPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SharedDesignTokens.radiusMd),
      ),
      contentPadding: contentPadding ??
          const EdgeInsets.symmetric(
            horizontal: SharedDesignTokens.spacingCompact,
            vertical: SharedDesignTokens.spacingXs,
          ),
      title: semanticLabel != null
          ? Semantics(
              label: semanticLabel,
              excludeSemantics: true,
              child: titleWidget,
            )
          : titleWidget,
      subtitle: subtitle != null && subtitle!.isNotEmpty
          ? Text(
              subtitle!,
              style: textTheme.bodySmall?.copyWith(
                color: isInteractive
                    ? semantic.textSecondary
                    : semantic.textDisabled,
              ),
            )
          : null,
    );
  }
}

/// Labeled radio tile wrapped around Material [RadioListTile] with accessible
/// full-row interaction and Stage 3.3 theme integration.
class DaywellRadioTile<T> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final T value;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final Widget? secondary;
  final ListTileControlAffinity controlAffinity;
  final bool enabled;
  final String? semanticLabel;
  final EdgeInsetsGeometry? contentPadding;

  const DaywellRadioTile({
    super.key,
    required this.title,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.subtitle,
    this.secondary,
    this.controlAffinity = ListTileControlAffinity.leading,
    this.enabled = true,
    this.semanticLabel,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final semantic = context.daywellColors;
    final textTheme = theme.textTheme;
    final isInteractive = enabled && onChanged != null;
    final Widget titleWidget = Text(
      title,
      style: textTheme.bodyMedium?.copyWith(
        color: isInteractive ? semantic.textPrimary : semantic.textDisabled,
        fontWeight: FontWeight.w500,
      ),
    );

    return RadioListTile<T>(
      value: value,
      groupValue: groupValue,
      onChanged: isInteractive ? onChanged : null,
      secondary: secondary,
      controlAffinity: controlAffinity,
      activeColor: colorScheme.primary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SharedDesignTokens.radiusMd),
      ),
      contentPadding: contentPadding ??
          const EdgeInsets.symmetric(
            horizontal: SharedDesignTokens.spacingCompact,
            vertical: SharedDesignTokens.spacingXs,
          ),
      title: semanticLabel != null
          ? Semantics(
              label: semanticLabel,
              excludeSemantics: true,
              child: titleWidget,
            )
          : titleWidget,
      subtitle: subtitle != null && subtitle!.isNotEmpty
          ? Text(
              subtitle!,
              style: textTheme.bodySmall?.copyWith(
                color: isInteractive
                    ? semantic.textSecondary
                    : semantic.textDisabled,
              ),
            )
          : null,
    );
  }
}
