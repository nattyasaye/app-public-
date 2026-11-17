import 'package:flutter/material.dart';
import '../../core/shared_foundation.dart';
import '../../data/database/raw_database_recovery_exporter.dart';
import '../widgets/shared_ui_widgets.dart';

/// Shared startup loading and initialization error/recovery gate styled with
/// Stage 3.4-3.6 shared UI components. Never executes Drift queries.
class DaywellShellStatusView extends StatelessWidget {
  final String? errorMessage;
  final VoidCallback? onRetry;
  final Widget? retryButton;
  final DatabaseStartupFailure? startupFailure;
  final bool diagnosticFilePersisted;
  final VoidCallback? onExportRawBackup;
  final VoidCallback? onRestoreEncryptedBackup;
  final String? recoveryNotice;
  final bool isRecoveryBusy;

  const DaywellShellStatusView({
    super.key,
    required this.errorMessage,
    this.onRetry,
    this.retryButton,
    this.startupFailure,
    this.diagnosticFilePersisted = true,
    this.onExportRawBackup,
    this.onRestoreEncryptedBackup,
    this.recoveryNotice,
    this.isRecoveryBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorMessage != null && errorMessage!.trim().isNotEmpty;
    final failure = startupFailure;
    final isCorruption = failure?.isCorruption ?? false;
    final canRetry = failure?.canRetryUpgrade ?? true;
    final exportRecommended = failure?.rawExportRecommended ?? false;
    final title = failure?.userTitle ?? 'Unable to initialize local database';
    final inv = failure?.fileInventory;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: hasError
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(SharedDesignTokens.spacingLg),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DaywellStatusBanner(
                          title: title,
                          message: failure?.userGuidance.isNotEmpty == true
                              ? '${failure!.userGuidance}\n\n${errorMessage!}'
                              : errorMessage!,
                          tone: DaywellStatusTone.error,
                        ),
                        if (!diagnosticFilePersisted) ...[
                          const SizedBox(
                            height: SharedDesignTokens.spacingSm,
                          ),
                          const DaywellStatusBanner(
                            title: 'Storage nearly full',
                            message: 'Diagnostic details are held in memory '
                                'because disk write failed.',
                            tone: DaywellStatusTone.warning,
                          ),
                        ],
                        if (inv != null) ...[
                          const SizedBox(
                            height: SharedDesignTokens.spacingSm,
                          ),
                          DaywellCard(
                            padding: const EdgeInsets.all(
                              SharedDesignTokens.spacingMd,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Cold Database Snapshot',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(
                                  height: SharedDesignTokens.spacingXs,
                                ),
                                Text(
                                  'Attempts: ${failure!.attemptCount} • '
                                  'DB: ${inv.mainDbBytes} B • '
                                  'WAL: ${inv.walBytes} B • '
                                  'SHM: ${inv.shmBytes} B',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (recoveryNotice != null &&
                            recoveryNotice!.trim().isNotEmpty) ...[
                          const SizedBox(
                            height: SharedDesignTokens.spacingSm,
                          ),
                          DaywellStatusBanner(
                            title: 'Recovery status',
                            message: recoveryNotice!,
                            tone: DaywellStatusTone.info,
                          ),
                        ],
                        if (onExportRawBackup != null) ...[
                          const SizedBox(
                            height: SharedDesignTokens.spacingMd,
                          ),
                          DaywellButton(
                            label: exportRecommended
                                ? 'Export Raw DB Backup (Recommended)'
                                : 'Export Raw DB Backup',
                            leadingIcon: Icons.save_alt,
                            onPressed:
                                isRecoveryBusy ? null : onExportRawBackup,
                            variant: isCorruption
                                ? DaywellButtonVariant.primary
                                : DaywellButtonVariant.secondary,
                            fullWidth: true,
                          ),
                        ],
                        if (onRestoreEncryptedBackup != null) ...[
                          const SizedBox(
                            height: SharedDesignTokens.spacingSm,
                          ),
                          DaywellButton(
                            label: 'Restore Encrypted .daywell Backup',
                            leadingIcon: Icons.restore_page_outlined,
                            onPressed: isRecoveryBusy
                                ? null
                                : onRestoreEncryptedBackup,
                            variant: DaywellButtonVariant.secondary,
                            fullWidth: true,
                          ),
                        ],
                        if (canRetry &&
                            (retryButton != null || onRetry != null)) ...[
                          const SizedBox(
                            height: SharedDesignTokens.spacingSm,
                          ),
                          retryButton ??
                              DaywellButton(
                                label: 'Retry',
                                leadingIcon: Icons.refresh,
                                onPressed: isRecoveryBusy ? null : onRetry,
                                variant: DaywellButtonVariant.primary,
                                fullWidth: true,
                              ),
                        ],
                      ],
                    ),
                  ),
                )
              : const Padding(
                  padding: EdgeInsets.all(SharedDesignTokens.spacingLg),
                  child: DaywellLoadingIndicator(
                    label: 'Loading Daywell workspace...',
                    semanticLabel: 'Loading Daywell workspace',
                    size: 32.0,
                  ),
                ),
        ),
      ),
    );
  }
}
