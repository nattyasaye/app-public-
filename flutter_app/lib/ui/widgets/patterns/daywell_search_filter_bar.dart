import 'package:flutter/material.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../buttons/daywell_button.dart';
import '../inputs/daywell_search_field.dart';

/// Layout strategy for filter controls rendered inside [DaywellSearchFilterBar].
enum DaywellFilterLayout {
  wrap,
  horizontalScroll,
}

/// Composed search + filter bar combining a controlled [DaywellSearchField],
/// optional inline trailing action, module-supplied filter controls, and an
/// optional active-filter summary with clear action.
class DaywellSearchFilterBar extends StatelessWidget {
  final TextEditingController? searchController;
  final String searchHintText;
  final String? searchSemanticLabel;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onSearchCleared;
  final Widget? trailingAction;
  final List<Widget> filterControls;
  final DaywellFilterLayout filterLayout;
  final String? activeSummary;
  final bool hasActiveFilters;
  final String clearFiltersLabel;
  final VoidCallback? onClearFilters;
  final bool showBottomDivider;
  final EdgeInsetsGeometry padding;

  const DaywellSearchFilterBar({
    super.key,
    this.searchController,
    this.searchHintText = 'Search...',
    this.searchSemanticLabel,
    this.onSearchChanged,
    this.onSearchCleared,
    this.trailingAction,
    this.filterControls = const [],
    this.filterLayout = DaywellFilterLayout.wrap,
    this.activeSummary,
    this.hasActiveFilters = false,
    this.clearFiltersLabel = 'Clear filters',
    this.onClearFilters,
    this.showBottomDivider = true,
    this.padding = const EdgeInsets.symmetric(
      horizontal: SharedDesignTokens.spacingMd,
      vertical: SharedDesignTokens.spacingCompact,
    ),
  });

  Widget _buildFilterSection() {
    if (filterLayout == DaywellFilterLayout.horizontalScroll) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (int i = 0; i < filterControls.length; i++) ...[
              if (i > 0) const SizedBox(width: SharedDesignTokens.spacingSm),
              filterControls[i],
            ],
          ],
        ),
      );
    }

    return Wrap(
      spacing: SharedDesignTokens.spacingSm,
      runSpacing: SharedDesignTokens.spacingSm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: filterControls,
    );
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final hasSummaryText =
        activeSummary != null && activeSummary!.trim().isNotEmpty;
    final showClearAction = hasActiveFilters &&
        onClearFilters != null &&
        clearFiltersLabel.trim().isNotEmpty;

    final double? mediaWidth = MediaQuery.maybeSizeOf(context)?.width;
    final double maxFallbackWidth =
        (mediaWidth != null && mediaWidth > 0) ? mediaWidth : 360.0;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxFallbackWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: DaywellSearchField(
                        controller: searchController,
                        hintText: searchHintText,
                        semanticLabel: searchSemanticLabel,
                        onChanged: onSearchChanged,
                        onCleared: onSearchCleared,
                      ),
                    ),
                    if (trailingAction != null) ...[
                      const SizedBox(width: SharedDesignTokens.spacingSm),
                      trailingAction!,
                    ],
                  ],
                ),
                if (filterControls.isNotEmpty) ...[
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  _buildFilterSection(),
                ],
                if (hasSummaryText || showClearAction) ...[
                  const SizedBox(height: SharedDesignTokens.spacingSm),
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: SharedDesignTokens.spacingSm,
                      runSpacing: SharedDesignTokens.spacingXs,
                      children: [
                        if (hasSummaryText)
                          Text(
                            activeSummary!,
                            style: textTheme.bodySmall?.copyWith(
                              color: semantic.textSecondary,
                            ),
                          ),
                        if (showClearAction)
                          DaywellButton(
                            label: clearFiltersLabel,
                            variant: DaywellButtonVariant.text,
                            size: DaywellButtonSize.compact,
                            onPressed: onClearFilters,
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (showBottomDivider) const Divider(height: 1),
        ],
      ),
    );
  }
}
