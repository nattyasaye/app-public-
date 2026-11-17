import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';

/// Accessible, themed text field backed by [TextFormField] and Stage 3.3
/// [InputDecorationTheme].
class DaywellTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? initialValue;
  final String? label;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool enabled;
  final bool readOnly;
  final bool isRequired;
  final bool obscureText;
  final bool autofocus;
  final int? maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final String? semanticLabel;

  const DaywellTextField({
    super.key,
    this.controller,
    this.initialValue,
    this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.enabled = true,
    this.readOnly = false,
    this.isRequired = false,
    this.obscureText = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.onTap,
    this.focusNode,
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

    final Widget textFormField = TextFormField(
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      focusNode: focusNode,
      enabled: enabled,
      readOnly: readOnly,
      obscureText: obscureText,
      autofocus: autofocus,
      maxLines: obscureText ? 1 : maxLines,
      minLines: minLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      onTap: onTap,
      style: textTheme.bodyMedium?.copyWith(
        color: enabled ? semantic.textPrimary : semantic.textDisabled,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        helperText: helperText,
        helperMaxLines: 2,
        errorText: errorText,
        errorMaxLines: 2,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
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
            child: textFormField,
          )
        else
          textFormField,
      ],
    );
  }
}
