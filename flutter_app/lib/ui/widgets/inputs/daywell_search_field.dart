import 'package:flutter/material.dart';
import '../../../core/theme/daywell_theme.dart';
import '../buttons/daywell_button.dart';
import '../constants/daywell_icon_size.dart';

/// Reusable search input with safe controller lifecycle, replacement handling,
/// and non-duplicating clear behavior.
class DaywellSearchField extends StatefulWidget {
  final TextEditingController? controller;
  final String hintText;
  final String? semanticLabel;
  final bool enabled;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onCleared;

  const DaywellSearchField({
    super.key,
    this.controller,
    this.hintText = 'Search...',
    this.semanticLabel,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.onCleared,
  });

  @override
  State<DaywellSearchField> createState() => _DaywellSearchFieldState();
}

class _DaywellSearchFieldState extends State<DaywellSearchField> {
  TextEditingController? _internalController;
  late TextEditingController _activeController;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _attachController(widget.controller);
  }

  @override
  void didUpdateWidget(covariant DaywellSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _detachController(oldWidget.controller);
      _attachController(widget.controller);
    }
  }

  @override
  void dispose() {
    _detachController(widget.controller);
    super.dispose();
  }

  void _attachController(TextEditingController? externalController) {
    if (externalController == null) {
      _internalController = TextEditingController();
      _activeController = _internalController!;
    } else {
      _internalController = null;
      _activeController = externalController;
    }
    _hasText = _activeController.text.isNotEmpty;
    _activeController.addListener(_handleControllerChanged);
  }

  void _detachController(TextEditingController? externalController) {
    _activeController.removeListener(_handleControllerChanged);
    if (externalController == null) {
      _internalController?.dispose();
      _internalController = null;
    }
  }

  void _handleControllerChanged() {
    final nowHasText = _activeController.text.isNotEmpty;
    if (nowHasText != _hasText && mounted) {
      setState(() => _hasText = nowHasText);
    }
  }

  void _handleClear() {
    if (!_activeController.text.isNotEmpty) return;
    _activeController.clear();
    widget.onChanged?.call('');
    widget.onCleared?.call();
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;

    final Widget field = TextField(
      controller: _activeController,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      textInputAction: TextInputAction.search,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      style: textTheme.bodyMedium?.copyWith(
        color: widget.enabled ? semantic.textPrimary : semantic.textDisabled,
      ),
      decoration: InputDecoration(
        hintText: widget.hintText,
        prefixIcon: Icon(
          Icons.search,
          size: DaywellIconSize.md,
          color: widget.enabled ? semantic.textMuted : semantic.textDisabled,
        ),
        suffixIcon: _hasText && widget.enabled
            ? DaywellIconButton(
                icon: Icons.clear,
                tooltip: 'Clear search',
                iconSize: DaywellIconSize.md,
                onPressed: _handleClear,
              )
            : null,
      ),
    );

    if (widget.semanticLabel != null &&
        widget.semanticLabel!.trim().isNotEmpty) {
      return Semantics(
        label: widget.semanticLabel!.trim(),
        child: field,
      );
    }

    return field;
  }
}
