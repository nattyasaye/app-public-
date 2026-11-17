import 'package:flutter/material.dart';
import '../cards/daywell_empty_state.dart';
import '../feedback/daywell_status_banner.dart';
import '../feedback/daywell_status_tone.dart';
import '../indicators/daywell_loading_indicator.dart';

/// Explicit view states supported by [DaywellContentState].
enum DaywellContentStatus {
  loading,
  empty,
  error,
  content,
}

/// Composed content-state shell switching cleanly between loading, empty,
/// error-with-retry, and loaded content without owning async or domain state.
class DaywellContentState extends StatelessWidget {
  final DaywellContentStatus status;
  final Widget? child;
  final WidgetBuilder? contentBuilder;

  final String? loadingLabel;
  final bool inlineLoading;

  final IconData emptyIcon;
  final String emptyMessage;
  final String? emptySubtitle;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;

  final String? errorTitle;
  final String errorMessage;
  final String retryLabel;
  final VoidCallback? onRetry;

  final EdgeInsetsGeometry? statePadding;

  const DaywellContentState({
    super.key,
    required this.status,
    this.child,
    this.contentBuilder,
    this.loadingLabel,
    this.inlineLoading = false,
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyMessage = 'Nothing to show yet',
    this.emptySubtitle,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.errorTitle,
    this.errorMessage = 'Something went wrong.',
    this.retryLabel = 'Retry',
    this.onRetry,
    this.statePadding,
  });

  Widget _wrapStatePadding(Widget widget) {
    if (statePadding == null) {
      return widget;
    }
    return Padding(padding: statePadding!, child: widget);
  }

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case DaywellContentStatus.loading:
        return _wrapStatePadding(
          DaywellLoadingIndicator(
            label: loadingLabel,
            inline: inlineLoading,
          ),
        );
      case DaywellContentStatus.empty:
        final hasEmptyAction = onEmptyAction != null &&
            emptyActionLabel != null &&
            emptyActionLabel!.trim().isNotEmpty;
        return _wrapStatePadding(
          DaywellEmptyState(
            icon: emptyIcon,
            message: emptyMessage,
            subtitle: emptySubtitle,
            actionLabel: hasEmptyAction ? emptyActionLabel : null,
            onActionPressed: hasEmptyAction ? onEmptyAction : null,
          ),
        );
      case DaywellContentStatus.error:
        final hasRetryAction = onRetry != null && retryLabel.trim().isNotEmpty;
        return _wrapStatePadding(
          DaywellStatusBanner(
            title: errorTitle,
            message: errorMessage,
            tone: DaywellStatusTone.error,
            actionLabel: hasRetryAction ? retryLabel : null,
            onActionPressed: hasRetryAction ? onRetry : null,
          ),
        );
      case DaywellContentStatus.content:
        if (contentBuilder != null) {
          return contentBuilder!(context);
        }
        return child ?? const SizedBox.shrink();
    }
  }
}
