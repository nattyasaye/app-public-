import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'core/date/shared_date.dart';
import 'core/theme/daywell_theme.dart';
import 'domain/calendar/calendar_models.dart';
import 'ui/app_state.dart';
import 'ui/screens/backup_view.dart';
import 'ui/screens/calendar_view.dart';
import 'ui/screens/dashboard_view.dart';
import 'ui/screens/finance/finance_composer_sheet.dart';
import 'ui/screens/finance/finance_formatters.dart';
import 'ui/screens/finance_view.dart';
import 'ui/screens/more_view.dart';
import 'ui/screens/notes_view.dart';
import 'ui/screens/tasks_view.dart';
import 'ui/shell/daywell_app_shell.dart';
import 'ui/shell/daywell_shell_routes.dart';
import 'ui/shell/daywell_shell_status_view.dart';
import 'ui/shell/daywell_theme_controller.dart';
import 'ui/widgets/quick_capture_dialog.dart';
import 'ui/widgets/shared_ui_widgets.dart';

typedef DaywellAppShell = MainDaywellScreen;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DaywellApp());
}

class DaywellApp extends StatefulWidget {
  final ThemeMode themeMode;
  final DaywellThemeController? themeController;
  final AppStateManager? stateManager;
  final DaywellShellController? shellController;

  const DaywellApp({
    super.key,
    this.themeMode = ThemeMode.system,
    this.themeController,
    this.stateManager,
    this.shellController,
  }) : assert(
          themeController == null || themeMode == ThemeMode.system,
          'Pass either themeMode or themeController to DaywellApp, not a non-system themeMode together with themeController.',
        );

  @override
  State<DaywellApp> createState() => _DaywellAppState();
}

class _DaywellAppState extends State<DaywellApp> {
  late DaywellThemeController _themeController;
  late bool _ownsThemeController;

  @override
  void initState() {
    super.initState();
    _ownsThemeController = widget.themeController == null;
    _themeController = widget.themeController ??
        DaywellThemeController(initialMode: widget.themeMode);
  }

  @override
  void didUpdateWidget(covariant DaywellApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.themeController != oldWidget.themeController) {
      if (_ownsThemeController) {
        _themeController.dispose();
      }
      _ownsThemeController = widget.themeController == null;
      _themeController = widget.themeController ??
          DaywellThemeController(initialMode: widget.themeMode);
    } else if (_ownsThemeController &&
        widget.themeMode != oldWidget.themeMode) {
      _themeController.setThemeMode(widget.themeMode);
    }
  }

  @override
  void dispose() {
    if (_ownsThemeController) {
      _themeController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _themeController,
      builder: (BuildContext context, Widget? _) {
        return MaterialApp(
          title: 'Daywell',
          debugShowCheckedModeBanner: false,
          themeMode: _themeController.themeMode,
          theme: DaywellTheme.light,
          darkTheme: DaywellTheme.dark,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en', 'US'),
            Locale('am', 'ET'),
          ],
          home: MainDaywellScreen(
            stateManager: widget.stateManager,
            shellController: widget.shellController,
            themeController: _themeController,
          ),
        );
      },
    );
  }
}

class MainDaywellScreen extends StatefulWidget {
  final AppStateManager? stateManager;
  final DaywellShellController? shellController;
  final DaywellThemeController? themeController;

  const MainDaywellScreen({
    super.key,
    this.stateManager,
    this.shellController,
    this.themeController,
  });

  @override
  State<MainDaywellScreen> createState() => _MainDaywellScreenState();
}

class _MainDaywellScreenState extends State<MainDaywellScreen> {
  static const MethodChannel _quickCaptureChannel =
      MethodChannel('com.example.personalmanagement/quick_capture');

  late AppStateManager _state;
  late bool _ownsState;
  late DaywellShellController _shellController;
  late bool _ownsShellController;
  late DaywellThemeController _themeController;
  late bool _ownsThemeController;

  bool _lastInitialized = false;
  String? _lastInitializationError;

  // Cold-start and duplicate-dialog guard state for Quick Capture & shared text
  bool _pendingQuickCapture = false;
  final List<String> _pendingSharedTexts = <String>[];
  bool _isQuickCaptureDialogOpen = false;
  String? _activeQuickCaptureText;
  bool _drainScheduled = false;
  bool _isRecoveryBusy = false;
  String? _recoveryNotice;
  ({String taskId, int nonce})? _requestedTaskFocus;
  int _taskFocusNonce = 0;
  ({String noteId, int nonce})? _requestedNoteFocus;
  int _noteFocusNonce = 0;
  ({int tabIndex, int nonce})? _requestedTasksSubTab;
  int _tasksSubTabNonce = 0;
  ({int tabIndex, int nonce})? _requestedFinanceTab;
  int _financeTabNonce = 0;
  Future<bool> Function()? _flushNotesPendingEdits;
  DaywellTabId _lastShellTab = DaywellTabId.today;
  bool _lastShellHasSecondary = false;

  @override
  void initState() {
    super.initState();
    _ownsState = widget.stateManager == null;
    _state = widget.stateManager ?? AppStateManager();
    _lastInitialized = _state.isInitialized;
    _lastInitializationError = _state.initializationError;
    _state.addListener(_onInitializationStateChanged);

    _ownsShellController = widget.shellController == null;
    _shellController = widget.shellController ?? DaywellShellController();
    _lastShellTab = _shellController.currentTab;
    _lastShellHasSecondary = _shellController.hasSecondaryRoute;
    _shellController.addListener(_onShellNavigationChanged);

    _ownsThemeController = widget.themeController == null;
    _themeController = widget.themeController ?? DaywellThemeController();

    unawaited(_state.initialize());
    _setupMethodChannelListener();
    unawaited(_checkInitialIntentTriggers());
  }

  @override
  void didUpdateWidget(covariant MainDaywellScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stateManager != oldWidget.stateManager) {
      _state.removeListener(_onInitializationStateChanged);
      if (_ownsState) {
        _state.dispose();
      }
      _ownsState = widget.stateManager == null;
      _state = widget.stateManager ?? AppStateManager();
      _lastInitialized = _state.isInitialized;
      _lastInitializationError = _state.initializationError;
      _state.addListener(_onInitializationStateChanged);
      unawaited(_state.initialize());
      if (_state.isInitialized) {
        _scheduleDrainPendingQuickCapture();
      }
    }

    if (widget.shellController != oldWidget.shellController) {
      _shellController.removeListener(_onShellNavigationChanged);
      if (_ownsShellController) {
        _shellController.dispose();
      }
      _ownsShellController = widget.shellController == null;
      _shellController = widget.shellController ?? DaywellShellController();
      _lastShellTab = _shellController.currentTab;
      _lastShellHasSecondary = _shellController.hasSecondaryRoute;
      _shellController.addListener(_onShellNavigationChanged);
    }

    if (widget.themeController != oldWidget.themeController) {
      if (_ownsThemeController) {
        _themeController.dispose();
      }
      _ownsThemeController = widget.themeController == null;
      _themeController = widget.themeController ?? DaywellThemeController();
    }
  }

  void _onShellNavigationChanged() {
    final nextTab = _shellController.currentTab;
    final nextHasSecondary = _shellController.hasSecondaryRoute;
    final leftNotesTab = _lastShellTab == DaywellTabId.notes &&
        (nextTab != DaywellTabId.notes ||
            (!_lastShellHasSecondary && nextHasSecondary));
    _lastShellTab = nextTab;
    _lastShellHasSecondary = nextHasSecondary;
    if (leftNotesTab) {
      final flush = _flushNotesPendingEdits;
      if (flush != null) {
        unawaited(flush());
      }
    }
  }

  @override
  void dispose() {
    _quickCaptureChannel.setMethodCallHandler(null);
    _state.removeListener(_onInitializationStateChanged);
    _shellController.removeListener(_onShellNavigationChanged);
    if (_ownsState) {
      _state.dispose();
    }
    if (_ownsShellController) {
      _shellController.dispose();
    }
    if (_ownsThemeController) {
      _themeController.dispose();
    }
    super.dispose();
  }

  /// Isolates shell rebuilds strictly to initialization and error transitions
  /// so domain mutations do not rebuild navigation chrome.
  void _onInitializationStateChanged() {
    final nextInitialized = _state.isInitialized;
    final nextError = _state.initializationError;
    if (nextInitialized != _lastInitialized ||
        nextError != _lastInitializationError) {
      _lastInitialized = nextInitialized;
      _lastInitializationError = nextError;
      if (mounted) {
        setState(() {});
      }
    }
    if (nextInitialized) {
      _scheduleDrainPendingQuickCapture();
    }
  }

  void _setupMethodChannelListener() {
    _quickCaptureChannel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onQuickCaptureTriggered') {
        _openQuickCapture();
      } else if (call.method == 'onTextShared') {
        final text = call.arguments as String?;
        if (text != null && text.isNotEmpty) {
          _openQuickCapture(initialText: text);
        }
      }
    });
  }

  Future<void> _checkInitialIntentTriggers() async {
    try {
      final isTriggered = await _quickCaptureChannel
          .invokeMethod<bool>('checkQuickCaptureTrigger');
      if (!mounted) return;
      if (isTriggered == true) {
        _openQuickCapture();
      }
      final sharedText =
          await _quickCaptureChannel.invokeMethod<String?>('getSharedText');
      if (!mounted) return;
      if (sharedText != null && sharedText.isNotEmpty) {
        _openQuickCapture(initialText: sharedText);
      }
    } catch (_) {}
  }

  void _openQuickCapture({String? initialText}) {
    if (!mounted) return;

    if (initialText != null && initialText.isNotEmpty) {
      // Avoid duplicating an identical shared-text payload already shown or queued.
      final alreadyActive =
          _isQuickCaptureDialogOpen && _activeQuickCaptureText == initialText;
      final alreadyQueued = _pendingSharedTexts.contains(initialText);
      if (!alreadyActive && !alreadyQueued) {
        _pendingSharedTexts.add(initialText);
      }
    } else if (!_isQuickCaptureDialogOpen && _pendingSharedTexts.isEmpty) {
      _pendingQuickCapture = true;
    }

    _scheduleDrainPendingQuickCapture();
  }

  void _scheduleDrainPendingQuickCapture() {
    if (!mounted || !_state.isInitialized || _isQuickCaptureDialogOpen) {
      return;
    }
    if (!_pendingQuickCapture && _pendingSharedTexts.isEmpty) {
      return;
    }
    if (_drainScheduled) return;
    _drainScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _drainScheduled = false;
      _drainPendingQuickCapture();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _drainPendingQuickCapture() {
    if (!mounted || !_state.isInitialized || _isQuickCaptureDialogOpen) {
      return;
    }

    final String? candidateText =
        _pendingSharedTexts.isNotEmpty ? _pendingSharedTexts.first : null;
    if (candidateText == null && !_pendingQuickCapture) {
      return;
    }

    _isQuickCaptureDialogOpen = true;
    _activeQuickCaptureText = candidateText;

    final Future<void> dialogFuture = showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => QuickCaptureDialog(
        state: _state,
        controller: _state.inboxController,
        initialText: candidateText,
        onOpenExpenseComposer: _openExpenseInFinanceComposer,
      ),
    );

    if (candidateText != null && _pendingSharedTexts.isNotEmpty) {
      _pendingSharedTexts.removeAt(0);
    }
    _pendingQuickCapture = false;

    unawaited(
      dialogFuture.whenComplete(() {
        _isQuickCaptureDialogOpen = false;
        _activeQuickCaptureText = null;
        if (mounted) {
          _scheduleDrainPendingQuickCapture();
        }
      }),
    );
  }

  void _openExpenseInFinanceComposer(String rawText) {
    if (!mounted) return;
    final parsed = AppStateManager.parseQuickCaptureExpense(rawText);
    final initialDesc = parsed?.description ?? rawText.trim();
    final initialAmount = parsed != null
        ? FinanceUiFormatters.formatCentsAsInput(parsed.amountCents)
        : null;

    _shellController.selectTab(DaywellTabId.finance);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        FinanceComposerSheet.show(
          context,
          controller: _state.financeController,
          initialMode: FinanceComposerMode.expense,
          initialDescription: initialDesc.isEmpty ? null : initialDesc,
          initialAmountText: initialAmount,
        ),
      );
    });
  }

  Widget _buildTabPage(DaywellTabId tab) {
    switch (tab) {
      case DaywellTabId.today:
        return DashboardView(
          state: _state,
          onOpenQuickCapture: () => _openQuickCapture(),
          onSelectTab: _shellController.selectTab,
          onOpenTasksSubTab: (int tabIndex) {
            setState(() {
              _requestedTasksSubTab = (
                tabIndex: tabIndex,
                nonce: ++_tasksSubTabNonce,
              );
            });
            _shellController.selectTab(DaywellTabId.tasks);
          },
          onOpenFinanceTab: (int tabIndex) {
            setState(() {
              _requestedFinanceTab = (
                tabIndex: tabIndex,
                nonce: ++_financeTabNonce,
              );
            });
            _shellController.selectTab(DaywellTabId.finance);
          },
          onOpenNote: (String noteId) {
            setState(() {
              _requestedNoteFocus = (noteId: noteId, nonce: ++_noteFocusNonce);
            });
            _shellController.selectTab(DaywellTabId.notes);
          },
          onOpenBackup: () =>
              _shellController.openSecondaryRoute(DaywellSecondaryRoute.backup),
        );
      case DaywellTabId.tasks:
        return TasksView(
          state: _state,
          controller: _state.tasksController,
          projectsController: _state.projectsController,
          inboxController: _state.inboxController,
          notesController: _state.notesController,
          calendarController: _state.calendarController,
          requestedTaskFocus: _requestedTaskFocus,
          requestedSubTab: _requestedTasksSubTab,
          onOpenCalendarDate: (CalendarDate date) {
            _state.calendarController.setSelectedCalendarDate(date);
            _shellController.selectTab(DaywellTabId.calendar);
          },
          onOpenNote: (String noteId) {
            setState(() {
              _requestedNoteFocus = (noteId: noteId, nonce: ++_noteFocusNonce);
            });
            _shellController.selectTab(DaywellTabId.notes);
          },
        );
      case DaywellTabId.calendar:
        return CalendarView(
          calendarController: _state.calendarController,
          tasksController: _state.tasksController,
          projectsController: _state.projectsController,
          dailyRhythmController: _state.dailyRhythmController,
          notesController: _state.notesController,
          onOpenTasks: () => _shellController.selectTab(DaywellTabId.tasks),
          onOpenTask: (String taskId) {
            setState(() {
              _requestedTaskFocus = (taskId: taskId, nonce: ++_taskFocusNonce);
            });
            _shellController.selectTab(DaywellTabId.tasks);
          },
          onOpenNote: (String noteId) {
            setState(() {
              _requestedNoteFocus = (noteId: noteId, nonce: ++_noteFocusNonce);
            });
            _shellController.selectTab(DaywellTabId.notes);
          },
        );
      case DaywellTabId.notes:
        return NotesView(
          state: _state,
          controller: _state.notesController,
          tasksController: _state.tasksController,
          projectsController: _state.projectsController,
          calendarController: _state.calendarController,
          requestedNoteFocus: _requestedNoteFocus,
          onRegisterPendingSaveFlush: (handler) {
            _flushNotesPendingEdits = handler;
          },
          onOpenTask: (String taskId) {
            setState(() {
              _requestedTaskFocus = (taskId: taskId, nonce: ++_taskFocusNonce);
            });
            _shellController.selectTab(DaywellTabId.tasks);
          },
          onOpenCalendarEvent: (CalendarEventEntity event) {
            _state.calendarController.setSelectedCalendarDate(event.startDate);
            _shellController.selectTab(DaywellTabId.calendar);
          },
        );
      case DaywellTabId.finance:
        return FinanceView(
          state: _state,
          controller: _state.financeController,
          dailyRhythmController: _state.dailyRhythmController,
          requestedTab: _requestedFinanceTab,
          onOpenQuickCapture: () => _openQuickCapture(),
        );
      case DaywellTabId.more:
        return MoreView(
          state: _state,
          onSelectTab: _shellController.selectTab,
          onOpenBackup: () =>
              _shellController.openSecondaryRoute(DaywellSecondaryRoute.backup),
          themeController: _themeController,
        );
    }
  }

  Widget _buildSecondaryRoute(DaywellSecondaryRoute route) {
    switch (route) {
      case DaywellSecondaryRoute.backup:
        return BackupView(
          state: _state,
          onBack: _shellController.handleBackNavigation,
        );
    }
  }

  Future<void> _handleRecoveryRawExport() async {
    if (_isRecoveryBusy) return;
    setState(() {
      _isRecoveryBusy = true;
      _recoveryNotice = null;
    });
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final exportRoot = Directory(p.join(docsDir.path, 'daywell_recovery'));
      final result = await _state.exportRawRecoveryBundle(exportRoot);
      if (!mounted) return;
      setState(() {
        _isRecoveryBusy = false;
        _recoveryNotice =
            'Verified cold backup (${result.entries.length} files, '
            'SHA-256 checked) saved to:\n${result.bundleDirectoryPath}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRecoveryBusy = false;
        _recoveryNotice = 'Raw export failed (live files untouched): $e';
      });
    }
  }

  Future<void> _handleRecoveryEncryptedRestore() async {
    if (_isRecoveryBusy) return;
    final payloadCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool confirmedQuarantine = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Restore Encrypted .daywell Backup'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'This will quarantine the damaged local database '
                      'files before importing your encrypted backup.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: payloadCtrl,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Encrypted Backup JSON (.daywell)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Backup Passphrase',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: confirmedQuarantine,
                      onChanged: (val) => setDialogState(
                        () => confirmedQuarantine = val ?? false,
                      ),
                      title: const Text(
                        'I understand damaged database files will be moved '
                        'to quarantine before restore.',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: confirmedQuarantine
                      ? () => Navigator.of(ctx).pop(true)
                      : null,
                  child: const Text('Quarantine & Restore'),
                ),
              ],
            );
          },
        );
      },
    );

    final payload = payloadCtrl.text.trim();
    final passphrase = passCtrl.text.trim();
    payloadCtrl.dispose();
    passCtrl.dispose();

    if (confirmed != true || payload.isEmpty || passphrase.isEmpty) {
      return;
    }

    setState(() {
      _isRecoveryBusy = true;
      _recoveryNotice = null;
    });
    final result = await _state.restoreEncryptedBackupInRecoveryDetailed(
      encryptedEnvelopeJson: payload,
      passphrase: passphrase,
    );
    if (!mounted) return;
    setState(() {
      _isRecoveryBusy = false;
      _recoveryNotice = result.success
          ? null
          : 'Restore failed (existing recovery state preserved): '
              '${result.message ?? 'Validation failed.'}';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_state.isInitialized) {
      if (_state.initializationError != null) {
        return DaywellShellStatusView(
          errorMessage: _state.initializationError,
          startupFailure: _state.startupFailure,
          diagnosticFilePersisted: _state.diagnosticFilePersisted,
          recoveryNotice: _recoveryNotice,
          isRecoveryBusy: _isRecoveryBusy,
          onExportRawBackup: _handleRecoveryRawExport,
          onRestoreEncryptedBackup: _handleRecoveryEncryptedRestore,
          onRetry: _state.retryInitialize,
          retryButton: (_state.startupFailure?.canRetryUpgrade ?? true)
              ? DaywellButton(
                  label: 'Retry',
                  leadingIcon: Icons.refresh,
                  onPressed: _isRecoveryBusy ? null : _state.retryInitialize,
                  variant: DaywellButtonVariant.primary,
                  fullWidth: true,
                )
              : null,
        );
      }

      return const DaywellShellStatusView(errorMessage: null);
    }

    return DaywellAdaptiveScaffold(
      shellController: _shellController,
      tabBuilder: _buildTabPage,
      secondaryRouteBuilder: _buildSecondaryRoute,
    );
  }
}
