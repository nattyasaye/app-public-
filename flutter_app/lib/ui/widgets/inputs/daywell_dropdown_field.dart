import 'package:flutter/material.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';

/// Accessible, themed dropdown field backed by [DropdownButtonFormField].
class DaywellDropdownField<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? label;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final Widget? prefixIcon;
  final bool enabled;
  final bool isRequired;
  final bool isExpanded;
  final FormFieldValidator<T>? validator;
  final String? semanticLabel;

  const DaywellDropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.prefixIcon,
    this.enabled = true,
    this.isRequired = false,
    this.isExpanded = true,
    this.validator,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.daywellColors;
    final textTheme = theme.textTheme;
    final effectiveLabel = label != null && isRequired ? '$label *' : label;
    final hasCustomSemanticLabel =
        semanticLabel != null && semanticLabel!.trim().isNotEmpty;

    final Widget labelWidget = Text(
      effectiveLabel ?? '',
      style: textTheme.labelMedium?.copyWith(
        color: enabled ? semantic.textSecondary : semantic.textDisabled,
      ),
    );

    final Widget dropdownField = DropdownButtonFormField<T>(
      value: value,
      items: items,
      isExpanded: isExpanded,
      validator: validator,
      onChanged: enabled ? onChanged : null,
      style: textTheme.bodyMedium?.copyWith(
        color: enabled ? semantic.textPrimary : semantic.textDisabled,
      ),
      dropdownColor: semantic.elevated,
      decoration: InputDecoration(
        enabled: enabled,
        hintText: hintText,
        helperText: helperText,
        helperMaxLines: 2,
        errorText: errorText,
        errorMaxLines: 2,
        prefixIcon: prefixIcon,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (effectiveLabel != null && effectiveLabel.isNotEmpty) ...[
          if (hasCustomSemanticLabel)
            ExcludeSemantics(child: labelWidget)
          else
            labelWidget,
          const SizedBox(height: SharedDesignTokens.spacingXs),
        ],
        if (hasCustomSemanticLabel)
          Semantics(
            label: semanticLabel!.trim(),
            child: dropdownField,
          )
        else
          dropdownField,
      ],
    );
  }
}
