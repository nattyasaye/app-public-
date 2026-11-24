import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../application/calendar/calendar_controller.dart';
import '../application/daily_rhythm/daily_rhythm_controller.dart';
import '../application/finance/finance_controller.dart';
import '../application/inbox/inbox_controller.dart';
import '../application/notes/notes_controller.dart';
import '../application/projects/projects_controller.dart';
import '../application/tasks/tasks_controller.dart';
import '../core/date/shared_date.dart';
import '../core/interfaces/platform_service_interfaces.dart';
import '../data/database/app_database.dart';
import '../data/database/database_persistence_coordinator.dart';
import '../data/database/raw_database_recovery_exporter.dart';
import '../data/repositories/calendar_repository.dart';
import '../data/repositories/daily_rhythm_repository.dart';
import '../data/repositories/finance_repository.dart';
import '../data/repositories/inbox_repository.dart';
import '../data/repositories/notes_repository.dart';
import '../data/repositories/projects_repository.dart';
import '../data/repositories/search_repository.dart';
import '../data/repositories/tasks_repository.dart';
import '../services/backup/encryption_backup_service.dart';
import '../services/notifications/local_notification_service.dart';

export '../domain/finance/finance_models.dart';

/// Read-only compatibility adapter model for legacy Task consumers.
class TaskModel {
  final String id;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final CalendarDate? dueDate;
  final CalendarDate? scheduledDate;
  final String? projectId;
  final DateTime createdAt;

  TaskModel({
    required this.id,
    required this.title,
    this.description,
    this.status = 'not_started',
    this.priority = 'medium',
    this.dueDate,
    this.scheduledDate,
    this.projectId,
    DateTime? createdAt,
  }) : createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'status': status,
        'completed': status == 'completed',
        'priority': priority,
        'dueDate': dueDate?.toIsoString(),
        'scheduledDate': scheduledDate?.toIsoString(),
        'projectId': projectId,
        'createdAt': EthiopiaClock.toUtcIsoString(createdAt),
      };

  factory TaskModel.fromJson(Map<String, dynamic> json) => TaskModel(
        id: json['id'],
        title: json['title'],
        description: json['description'],
        status: json['status'] ??
            (json['completed'] == true ? 'completed' : 'not_started'),
        priority: json['priority'] ?? 'medium',
        dueDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
          json['dueDate']?.toString(),
        ),
        scheduledDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
          json['scheduledDate']?.toString(),
        ),
        projectId: json['projectId'],
        createdAt:
            EthiopiaClock.tryParseInstantUtc(json['createdAt']?.toString()),
      );
}

/// Read-only compatibility adapter model for legacy Project consumers.
class ProjectModel {
  final String id;
  final String title;
  final String? description;
  final String status;
  final CalendarDate? targetDate;
  final DateTime createdAt;

  ProjectModel({
    required this.id,
    required this.title,
    this.description,
    this.status = 'active',
    this.targetDate,
    DateTime? createdAt,
  }) : createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'status': status,
        'targetDate': targetDate?.toIsoString(),
        'createdAt': EthiopiaClock.toUtcIsoString(createdAt),
      };

  factory ProjectModel.fromJson(Map<String, dynamic> json) => ProjectModel(
        id: json['id'],
        title: json['title'],
        description: json['description'],
        status: json['status'] ?? 'active',
        targetDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
          json['targetDate']?.toString(),
        ),
        createdAt:
            EthiopiaClock.tryParseInstantUtc(json['createdAt']?.toString()),
      );
}

/// Read-only compatibility adapter model for legacy Note consumers.
class NoteModel {
  final String id;
  final String title;
  final String content;
  final String category;
  final String? projectId;
  final String? linkedModule;
  final String? linkedId;
  final List<String> tags;
  final bool isPinned;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;

  NoteModel({
    required this.id,
    required this.title,
    required this.content,
    this.category = 'general',
    this.projectId,
    this.linkedModule,
    this.linkedId,
    this.tags = const [],
    this.isPinned = false,
    this.isArchived = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc(),
        updatedAt = (updatedAt ?? EthiopiaClock.nowUtc()).toUtc();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'body': content,
        'category': category,
        'folder': category,
        'projectId': projectId,
        'linkedModule': linkedModule,
        'linkedId': linkedId,
        'tags': tags,
        'isPinned': isPinned,
        'isArchived': isArchived,
        'createdAt': EthiopiaClock.toUtcIsoString(createdAt),
        'updatedAt': EthiopiaClock.toUtcIsoString(updatedAt),
      };

  factory NoteModel.fromJson(Map<String, dynamic> json) => NoteModel(
        id: json['id'],
        title: json['title'],
        content: json['content'] ?? json['body'] ?? '',
        category: json['category'] ?? json['folder'] ?? 'general',
        projectId: json['projectId'],
        linkedModule: json['linkedModule']?.toString(),
        linkedId: json['linkedId']?.toString(),
        tags: json['tags'] is List
            ? (json['tags'] as List).map((e) => e.toString()).toList()
            : const [],
        isPinned: json['isPinned'] ?? false,
        isArchived: json['isArchived'] ?? false,
        createdAt:
            EthiopiaClock.tryParseInstantUtc(json['createdAt']?.toString()),
        updatedAt:
            EthiopiaClock.tryParseInstantUtc(json['updatedAt']?.toString()),
      );
}

/// Read-only compatibility adapter model for legacy Inbox consumers.
class InboxItemModel {
  final String id;
  final String rawText;
  final String category;
  final bool isProcessed;
  final DateTime createdAt;

  InboxItemModel({
    required this.id,
    required this.rawText,
    this.category = 'general',
    this.isProcessed = false,
    DateTime? createdAt,
  }) : createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc();

  Map<String, dynamic> toJson() => {
        'id': id,
        'rawText': rawText,
        'category': category,
        'isProcessed': isProcessed,
        'createdAt': EthiopiaClock.toUtcIsoString(createdAt),
      };

  factory InboxItemModel.fromJson(Map<String, dynamic> json) => InboxItemModel(
        id: json['id'],
        rawText: json['rawText'],
        category: json['category'] ?? 'general',
        isProcessed: json['isProcessed'] ?? false,
        createdAt:
            EthiopiaClock.tryParseInstantUtc(json['createdAt']?.toString()),
      );
}

/// Thin composition root orchestrating Daywell's module controllers and
/// authoritative Drift SQLite persistence lifecycle.
///
/// Zero duplicated mutable domain collections live here; every module's state
/// is owned exclusively by its controller and backed by SQLite.
class AppStateManager extends ChangeNotifier {
  late AppDatabase _db;
  final AppDatabase Function()? _databaseBuilder;
  final RawDatabaseRecoveryExporter _recoveryExporter;
  final INotificationService _notificationService;
  late DatabasePersistenceCoordinator _persistenceCoordinator;
  final EncryptionBackupService _backupService = EncryptionBackupService();

  late FinanceController financeController;
  late DailyRhythmController dailyRhythmController;
  late TasksController tasksController;
  late ProjectsController projectsController;
  late NotesController notesController;
  late InboxController inboxController;
  late CalendarController calendarController;
  late DriftSearchRepository searchRepository;

  bool _hasFinanceLedgerBaseline = false;
  List<JournalEntryModel> _lastObservedFinanceEntries = const [];
  List<PostingModel> _lastObservedFinancePostings = const [];

  bool _isInitializing = false;
  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _controllersDisposed = false;
  bool _dbClosed = false;
  bool _notificationServiceReady = false;
  bool _isRestoreInProgress = false;
  String? _initializationError;
  DatabaseStartupFailure? _startupFailure;
  bool _diagnosticFilePersisted = true;
  RawRecoveryExportResult? _lastRecoveryExportResult;
  String? _lastRecoveryExportError;
  BackupRestoreResult? _lastBackupResult;
  Future<void>? _initFuture;
  Future<void>? _disposeFuture;
  final Set<String> _scheduledCommitmentReminders = <String>{};

  static const String _restoreInProgressMessage =
      'A database restore or import operation is already in progress.';

  @visibleForTesting
  Future<void> Function()? preQuarantineDeleteHookForTesting;

  AppStateManager({
    AppDatabase? db,
    AppDatabase Function()? databaseBuilder,
    RawDatabaseRecoveryExporter? recoveryExporter,
    INotificationService? notificationService,
  })  : _databaseBuilder =
            databaseBuilder ?? (db == null ? AppDatabase.new : null),
        _recoveryExporter = recoveryExporter ?? RawDatabaseRecoveryExporter(),
        _notificationService =
            notificationService ?? LocalNotificationService() {
    _db = db ?? _databaseBuilder!();
    _bindControllersForDb(_db);
  }

  bool get _canRebuildDatabase => _databaseBuilder != null;

  void _bindControllersForDb(AppDatabase db) {
    _persistenceCoordinator = DatabasePersistenceCoordinator(db);
    financeController = FinanceController(
      repository: DriftFinanceRepository(db),
    );
    dailyRhythmController = DailyRhythmController(
      repository: DriftDailyRhythmRepository(db),
    );
    tasksController = TasksController(
      repository: DriftTasksRepository(db),
      notificationService: _notificationService,
      onTaskDeleted: _handleTaskDeleted,
    );
    projectsController = ProjectsController(
      repository: DriftProjectsRepository(db),
    );
    notesController = NotesController(
      repository: DriftNotesRepository(db),
      loadCustomFolders: () async {
        final raw = await db.readAppSetting(
          NotesController.customFoldersSettingKey,
        );
        if (raw == null || raw.trim().isEmpty) return const <String>[];
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! List) return const <String>[];
          return decoded.map((e) => e.toString()).toList(growable: false);
        } catch (_) {
          return const <String>[];
        }
      },
      saveCustomFolders: (folders) async {
        await db.writeAppSetting(
          NotesController.customFoldersSettingKey,
          jsonEncode(folders),
        );
      },
    );
    inboxController = InboxController(
      repository: DriftInboxRepository(db),
      onTriageCapture: _handleInboxCaptureTriage,
    );
    calendarController = CalendarController(
      repository: DriftCalendarRepository(db),
    );
    searchRepository = DriftSearchRepository(db);

    _hasFinanceLedgerBaseline = false;
    _lastObservedFinanceEntries = const [];
    _lastObservedFinancePostings = const [];

    financeController.addListener(_onFinanceStateChanged);
    dailyRhythmController.addListener(notifyListeners);
    tasksController.addListener(notifyListeners);
    projectsController.addListener(notifyListeners);
    notesController.addListener(notifyListeners);
    inboxController.addListener(notifyListeners);
    calendarController.addListener(notifyListeners);
    _controllersDisposed = false;
  }

  void _syncObservedFinanceLedgerBaseline() {
    _lastObservedFinanceEntries = List<JournalEntryModel>.unmodifiable(
      financeController.state.journalEntries,
    );
    _lastObservedFinancePostings = List<PostingModel>.unmodifiable(
      financeController.state.postings,
    );
    _hasFinanceLedgerBaseline = true;
  }

  void _onFinanceStateChanged() {
    if (_isDisposed) return;
    final financeState = financeController.state;
    if (!financeState.isLoading && _hasFinanceLedgerBaseline) {
      final nextEntries = financeState.journalEntries;
      final nextPostings = financeState.postings;
      if (!_isRestoreInProgress && !dailyRhythmController.state.isLoading) {
        unawaited(
          dailyRhythmController.handleFinanceLedgerMutation(
            prevEntries: _lastObservedFinanceEntries,
            prevPostings: _lastObservedFinancePostings,
            nextEntries: nextEntries,
            nextPostings: nextPostings,
          ),
        );
      }
      _lastObservedFinanceEntries =
          List<JournalEntryModel>.unmodifiable(nextEntries);
      _lastObservedFinancePostings =
          List<PostingModel>.unmodifiable(nextPostings);
    }
    if (_isInitialized) {
      unawaited(syncFinanceDueReminders());
    }
    notifyListeners();
  }

  Future<void> _handleTaskDeleted(String taskId) async {
    await notesController.clearLinksForTarget(
      module: NoteEntity.taskLinkModule,
      targetId: taskId,
    );
  }

  Future<void> _rebindDatabase(AppDatabase newDb) async {
    _disposeControllersOnly();
    try {
      await inboxController.disposeAsync();
    } catch (_) {}
    _db = newDb;
    _dbClosed = false;
    _bindControllersForDb(newDb);
  }

  bool get isInitializing => _isInitializing;
  bool get isInitialized => _isInitialized;
  bool get isDisposed => _isDisposed;
  bool get isRestoreInProgress => _isRestoreInProgress;
  String? get initializationError => _initializationError;
  DatabaseStartupFailure? get startupFailure => _startupFailure;
  bool get diagnosticFilePersisted => _diagnosticFilePersisted;
  RawRecoveryExportResult? get lastRecoveryExportResult =>
      _lastRecoveryExportResult;
  String? get lastRecoveryExportError => _lastRecoveryExportError;
  BackupRestoreResult? get lastBackupResult => _lastBackupResult;
  BackupValidationException? get lastBackupError {
    final res = _lastBackupResult;
    if (res == null || res.success || res.failureKind == null) return null;
    return BackupValidationException(
      res.failureKind!,
      res.message ?? 'Backup or import failed.',
    );
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  /// Deterministic, idempotent async startup and module hydration pipeline.
  Future<void> initialize() {
    if (_isDisposed || _isInitialized) return Future.value();
    if (_initFuture != null) return _initFuture!;

    final future = _runInitialize();
    _initFuture = future;
    return future;
  }

  /// Re-attempts startup cleanly using a fresh database connection if the
  /// previous handle was closed during failure inspection.
  Future<void> retryInitialize() async {
    if (_isDisposed || _isInitialized) return;
    if (_startupFailure != null && !_startupFailure!.canRetryUpgrade) {
      return;
    }
    return initialize();
  }

  Future<void> _closeDbSafely([AppDatabase? target]) async {
    final dbToClose = target ?? _db;
    if (identical(dbToClose, _db) && _dbClosed) return;
    try {
      await dbToClose.close().timeout(const Duration(seconds: 3));
    } catch (_) {}
    if (identical(dbToClose, _db)) {
      _dbClosed = true;
    }
  }

  Future<void> _runInitialize() async {
    if (_dbClosed && _canRebuildDatabase) {
      await _rebindDatabase(_databaseBuilder!());
    }
    _isInitializing = true;
    _initializationError = null;
    notifyListeners();

    try {
      if (_canRebuildDatabase) {
        await _verifySqliteHeaderColdIfPresent();
      }
      await _db.ensureInitialized();
      if (_isDisposed) {
        _isInitializing = false;
        _initFuture = null;
        return;
      }

      await _rehydrateAllControllers();
      if (_isDisposed) {
        _isInitializing = false;
        _initFuture = null;
        return;
      }

      await financeController.processDueRecurringRules();
      if (_isDisposed) {
        _isInitializing = false;
        _initFuture = null;
        return;
      }

      inboxController.startWatchingUnprocessed();
      _isInitialized = true;
      _isInitializing = false;
      _startupFailure = null;
      _diagnosticFilePersisted = true;
      await _recoveryExporter.clearFailureDiagnostic();
      unawaited(syncFinanceDueReminders());
      notifyListeners();
    } catch (e) {
      _isInitializing = false;
      _isInitialized = false;
      _initFuture = null;

      if (_canRebuildDatabase && !_dbClosed) {
        await _closeDbSafely();
      }

      final prevAttempts = _startupFailure?.attemptCount ?? 0;
      DatabaseSidecarInventory? inventory;
      try {
        inventory = await _recoveryExporter.inspectDatabaseFilesCold();
      } catch (_) {}

      final classified = RawDatabaseRecoveryExporter.classifyStartupError(
        e,
        previousAttemptCount: prevAttempts,
        fileInventory: inventory,
      );
      final persisted =
          await _recoveryExporter.persistFailureDiagnosticAtomic(classified);

      if (!_isDisposed) {
        _startupFailure = classified;
        _diagnosticFilePersisted = persisted;
        _initializationError = classified.message;
        notifyListeners();
      }
    }
  }

  Future<void> _verifySqliteHeaderColdIfPresent() async {
    File dbFile;
    try {
      dbFile = await _recoveryExporter.resolveDatabaseFile();
    } catch (_) {
      return;
    }
    if (!await dbFile.exists()) return;
    final length = await dbFile.length();
    if (length == 0) return;

    const sqliteMagic = <int>[
      0x53,
      0x51,
      0x4c,
      0x69,
      0x74,
      0x65,
      0x20,
      0x66,
      0x6f,
      0x72,
      0x6d,
      0x61,
      0x74,
      0x20,
      0x33,
      0x00,
    ];
    if (length < sqliteMagic.length) {
      throw const DatabaseCorruptionException(
        'SQLite database file is truncated and missing a valid SQLite header.',
      );
    }
    final raf = await dbFile.open(mode: FileMode.read);
    final header = await raf.read(sqliteMagic.length);
    await raf.close();
    if (header.length < sqliteMagic.length) {
      throw const DatabaseCorruptionException(
        'SQLite database file header could not be read.',
      );
    }
    for (var i = 0; i < sqliteMagic.length; i++) {
      if (header[i] != sqliteMagic[i]) {
        throw const DatabaseCorruptionException(
          'SQLite database header mismatch (file is not a valid SQLite 3 database).',
        );
      }
    }
  }

  Future<void> _rehydrateAllControllers() async {
    _hasFinanceLedgerBaseline = false;
    await Future.wait([
      financeController.loadAll(),
      dailyRhythmController.loadAll(),
      tasksController.loadAll(),
      projectsController.loadAll(),
      notesController.loadNotes(),
      inboxController.loadItems(includeProcessed: true),
      calendarController.loadAll(),
    ]);
    _syncObservedFinanceLedgerBaseline();
  }

  Future<void> _rehydrateAllControllersStrict() async {
    await _rehydrateAllControllers();
    final controllerErrors = <String>[
      if (financeController.state.errorMessage != null &&
          financeController.state.errorMessage!.isNotEmpty)
        'finance: ${financeController.state.errorMessage}',
      if (dailyRhythmController.state.errorMessage != null &&
          dailyRhythmController.state.errorMessage!.isNotEmpty)
        'daily_rhythm: ${dailyRhythmController.state.errorMessage}',
      if (tasksController.state.errorMessage != null &&
          tasksController.state.errorMessage!.isNotEmpty)
        'tasks: ${tasksController.state.errorMessage}',
      if (projectsController.state.errorMessage != null &&
          projectsController.state.errorMessage!.isNotEmpty)
        'projects: ${projectsController.state.errorMessage}',
      if (notesController.state.errorMessage != null &&
          notesController.state.errorMessage!.isNotEmpty)
        'notes: ${notesController.state.errorMessage}',
      if (inboxController.errorMessage != null &&
          inboxController.errorMessage!.isNotEmpty)
        'inbox: ${inboxController.errorMessage}',
      if (calendarController.state.errorMessage != null &&
          calendarController.state.errorMessage!.isNotEmpty)
        'calendar: ${calendarController.state.errorMessage}',
    ];
    if (controllerErrors.isNotEmpty) {
      throw BackupValidationException(
        BackupFailureKind.databaseImportFailure,
        'Controller rehydration failed after restore (${controllerErrors.join('; ')}).',
      );
    }
  }

  Future<void> _processDueRecurringRulesStrict() async {
    await financeController.processDueRecurringRules();
    final err = financeController.state.errorMessage;
    if (err != null && err.isNotEmpty) {
      throw BackupValidationException(
        BackupFailureKind.databaseImportFailure,
        'Recurring rule processing failed after restore: $err',
      );
    }
  }

  /// Application composition triage bridge for Quick Capture items.
  /// Keeps InboxController decoupled from TasksController and NotesController.
  void _handleInboxCaptureTriage(InboxItemEntity captured) {
    if (_isDisposed) return;
    unawaited(_triageAsync(captured));
  }

  Future<void> _triageAsync(InboxItemEntity captured) async {
    if (_isDisposed) return;
    try {
      if (captured.category == 'note') {
        final firstLine = captured.rawText
            .split('\n')
            .map((line) => line.trim())
            .firstWhere((line) => line.isNotEmpty, orElse: () => '');
        final title =
            firstLine.length > 40 ? firstLine.substring(0, 40) : firstLine;
        final created = await notesController.createNote(
          title: title,
          content: captured.rawText,
          category: 'general',
        );
        if (notesController.state.errorMessage == null &&
            notesController.state.findById(created.id) != null) {
          await inboxController.markProcessed(captured.id);
        }
      } else if (captured.category == 'expense') {
        await _triageExpenseCapture(captured);
      }
      // 'task', 'idea', 'problem', 'decision', and 'general' captures remain in
      // InboxItems (isProcessed: false) until the user edits, dismisses, or
      // converts them into Task records.
    } catch (_) {
      // Safe no-op if database closes mid-triage during teardown.
    }
  }

  Future<void> _triageExpenseCapture(InboxItemEntity captured) async {
    final parsed = parseQuickCaptureExpense(captured.rawText);
    if (parsed == null || parsed.amountCents <= 0) return;

    final financeState = financeController.state;
    final candidates = financeState.liquidAssetAccounts.isNotEmpty
        ? financeState.liquidAssetAccounts
        : financeState.activeEtbSpendableAccounts;
    if (candidates.isEmpty) return;

    final expenseCats = financeState.activeCategories
        .where((c) => c.type == 'expense')
        .toList();
    if (expenseCats.isEmpty) return;

    final defaultCat = expenseCats.firstWhere(
      (c) => c.id == 'cat-other-exp',
      orElse: () => expenseCats.first,
    );

    final entry = await financeController.recordDirectExpense(
      accountId: candidates.first.id,
      categoryId: defaultCat.id,
      amountCents: parsed.amountCents,
      date: CalendarDate.fromUtcInstantInEthiopia(captured.createdAt),
      description: parsed.description,
      note: 'Triaged from Quick Capture',
    );
    if (entry != null) {
      await inboxController.markProcessed(captured.id);
    }
  }

  static final RegExp _unsafeForeignCurrencySymbolRegex =
      RegExp(r'(\$|€|£|¥|₹|₦|₩|₽|₺|₴|₫|₱|₪|฿|₵|₮)');
  static final RegExp _unambiguousForeignCurrencyCodeRegex = RegExp(
    r'\b(USD|EUR|GBP|KES|KSH|AED|SAR|JPY|CNY|RMB|CHF|CAD|AUD|ZAR|INR|UGX|TZS|RWF|ERN|DJF|SDG|SOS|EGP|NGN|GHS|USDT|USDC)\b',
    caseSensitive: false,
  );
  static final RegExp _adjacentUpperIsoRegex = RegExp(
    r'(?:(?:\d[\d,]*(?:\.\d{1,2})?\s*([A-Z]{3}))|(?:([A-Z]{3})\s*\d[\d,]*(?:\.\d{1,2})?))\b',
  );

  /// Detects explicit non-ETB currency tokens/symbols so quick-capture expense
  /// triage never silently reinterprets foreign amounts as ETB.
  static String? detectQuickCaptureUnsupportedCurrency(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) return null;

    final symbolMatch = _unsafeForeignCurrencySymbolRegex.firstMatch(text);
    if (symbolMatch != null) {
      final sym = symbolMatch.group(1)!;
      if (sym == r'$') return r'USD ($)';
      if (sym == '€') return 'EUR (€)';
      if (sym == '£') return 'GBP (£)';
      return sym;
    }

    final fxMatch = _unambiguousForeignCurrencyCodeRegex.firstMatch(text);
    if (fxMatch != null) {
      return fxMatch.group(1)!.toUpperCase();
    }

    for (final adjMatch in _adjacentUpperIsoRegex.allMatches(text)) {
      final code = (adjMatch.group(1) ?? adjMatch.group(2) ?? '').trim();
      if (code.isNotEmpty &&
          code != 'ETB' &&
          DoubleEntryEngine.classifyCurrencyCode(code) ==
              CurrencyValidationTier.verifiedNonEtb) {
        return code;
      }
    }

    return null;
  }

  /// Parses an optional decimal amount (ETB -> integer cents) and description
  /// from quick-capture expense text such as `"Coffee 120"` or `"450.50 Lunch"`.
  /// Returns `null` when foreign currency markers are detected.
  static ({int amountCents, String description})? parseQuickCaptureExpense(
    String rawText,
  ) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return null;
    if (detectQuickCaptureUnsupportedCurrency(trimmed) != null) return null;
    final match = RegExp(r'(?:^|\s)(\d+(?:\.\d{1,2})?)(?=\s|$|etb|ETB)')
        .firstMatch(trimmed);
    if (match == null) return null;
    final numStr = match.group(1)!;
    final parts = numStr.split('.');
    final whole = int.tryParse(parts[0]);
    if (whole == null) return null;
    final frac =
        parts.length > 1 ? int.tryParse(parts[1].padRight(2, '0')) ?? 0 : 0;
    final cents = (whole * 100) + frac;
    if (cents <= 0) return null;
    final cleanedDesc = trimmed
        .replaceFirst(match.group(0)!, ' ')
        .replaceAll(RegExp(r'\b(etb|ETB)\b'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return (
      amountCents: cents,
      description: cleanedDesc.isEmpty ? trimmed : cleanedDesc,
    );
  }

  void _disposeControllersOnly() {
    if (_controllersDisposed) return;
    _controllersDisposed = true;

    financeController.removeListener(_onFinanceStateChanged);
    dailyRhythmController.removeListener(notifyListeners);
    tasksController.removeListener(notifyListeners);
    projectsController.removeListener(notifyListeners);
    notesController.removeListener(notifyListeners);
    inboxController.removeListener(notifyListeners);
    calendarController.removeListener(notifyListeners);

    financeController.dispose();
    dailyRhythmController.dispose();
    tasksController.dispose();
    projectsController.dispose();
    notesController.dispose();
    inboxController.dispose();
    calendarController.dispose();
  }

  Future<void> _closeDatabaseAfterPendingInit() async {
    final activeInit = _initFuture;
    if (activeInit != null) {
      try {
        await activeInit;
      } catch (_) {}
    }
    try {
      await inboxController.disposeAsync();
    } catch (_) {}
    if (!_dbClosed) {
      await _closeDbSafely();
    }
  }

  /// Explicit async teardown that awaits any in-flight startup work and
  /// closes the underlying Drift database cleanly. Safe and idempotent.
  Future<void> disposeAsync() {
    if (_disposeFuture != null) return _disposeFuture!;
    final alreadySuperDisposed = _isDisposed;
    _isDisposed = true;
    _disposeControllersOnly();
    final service = _notificationService;
    if (service is LocalNotificationService) {
      service.dispose();
    }
    if (!alreadySuperDisposed) {
      super.dispose();
    }
    _disposeFuture = _closeDatabaseAfterPendingInit();
    return _disposeFuture!;
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _disposeControllersOnly();
    final service = _notificationService;
    if (service is LocalNotificationService) {
      service.dispose();
    }
    super.dispose();
    _disposeFuture ??= _closeDatabaseAfterPendingInit();
    unawaited(_disposeFuture!);
  }

  /// Cold-copies `.sqlite`, `-wal`, `-shm`, diagnostics, and SHA-256
  /// `manifest.json` using pure `dart:io` without opening SQLite.
  Future<RawRecoveryExportResult> exportRawRecoveryBundle(
    Directory destinationParentDir,
  ) async {
    if (!_dbClosed) {
      await _closeDbSafely();
    }
    try {
      final result = await _recoveryExporter.exportColdBundle(
        destinationParentDir: destinationParentDir,
        failure: _startupFailure,
      );
      _lastRecoveryExportResult = result;
      _lastRecoveryExportError = null;
      notifyListeners();
      return result;
    } catch (e) {
      _lastRecoveryExportError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  static BackupValidationException _classifyError(Object error) {
    if (error is BackupValidationException) return error;
    if (error is FormatException) {
      return BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Invalid backup or snapshot format: ${error.message}',
      );
    }
    if (error is ArgumentError) {
      return BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Invalid snapshot data: ${error.message ?? error.toString()}',
      );
    }
    return BackupValidationException(
      BackupFailureKind.databaseImportFailure,
      'Database import failed: $error',
    );
  }

  /// Quarantines live DB/WAL/SHM files, opens a fresh v9 database, imports
  /// an encrypted `.daywell` backup atomically, verifies reopened SQLite &
  /// ledger invariants + controller rehydration BEFORE removing quarantine,
  /// and executes the full 8-step rollback if any restore-critical step aborts.
  Future<bool> restoreEncryptedBackupInRecovery({
    required String encryptedEnvelopeJson,
    required String passphrase,
  }) async {
    if (_isRestoreInProgress) {
      throw const BackupValidationException(
        BackupFailureKind.databaseImportFailure,
        _restoreInProgressMessage,
      );
    }
    _isRestoreInProgress = true;
    try {
      return await _restoreEncryptedBackupInRecoveryInternal(
        encryptedEnvelopeJson: encryptedEnvelopeJson,
        passphrase: passphrase,
      );
    } finally {
      _isRestoreInProgress = false;
    }
  }

  Future<bool> _restoreEncryptedBackupInRecoveryInternal({
    required String encryptedEnvelopeJson,
    required String passphrase,
  }) async {
    _lastBackupResult = null;
    final ValidatedBackupEnvelope validatedEnvelope;
    final String decryptedJson;
    final Map<String, dynamic> decoded;
    final PreparedSnapshotImport prepared;
    try {
      validatedEnvelope = EncryptionBackupService.validateAndParseEnvelope(
        encryptedEnvelopeJson,
      );
      decryptedJson = await _backupService.decryptDatabasePayload(
        encryptedEnvelopeJson: encryptedEnvelopeJson,
        passphrase: passphrase,
      );
      final dynamic parsed = jsonDecode(decryptedJson);
      if (parsed is! Map<String, dynamic>) {
        throw const BackupValidationException(
          BackupFailureKind.invalidPayload,
          'Decrypted backup payload is not a JSON map.',
        );
      }
      prepared = DatabasePersistenceCoordinator.validateAndPrepareSnapshot(
        parsed,
        expectedHeaderVersion: validatedEnvelope.schemaVersion,
      );
      decoded = parsed;
    } catch (e) {
      final classified = _classifyError(e);
      _lastBackupResult = BackupRestoreResult.failure(
        classified.kind,
        classified.message,
      );
      notifyListeners();
      throw classified;
    }

    final wasInitializedBeforeRestore = _isInitialized && !_dbClosed;

    if (!_dbClosed) {
      await _closeDbSafely();
    }

    final quarantine = await _recoveryExporter.quarantineLiveDatabaseFiles();
    final builder = _databaseBuilder ?? AppDatabase.new;
    AppDatabase? freshDb;
    AppDatabase? verifiedDb;
    final SnapshotImportReport importReport;
    try {
      freshDb = builder();
      await freshDb.ensureInitialized();
      importReport =
          await DatabasePersistenceCoordinator(freshDb).importSnapshotDetailed(
        decoded,
        prepared: prepared,
      );

      if (_canRebuildDatabase) {
        await _closeDbSafely(freshDb);
        freshDb = null;
        verifiedDb = builder();
        await verifiedDb.ensureInitialized();
      } else {
        verifiedDb = freshDb;
        freshDb = null;
      }

      await DatabasePersistenceCoordinator.verifyRestoredDatabaseInvariants(
        verifiedDb,
      );

      try {
        await _notificationService.cancelAllReminders();
      } catch (_) {}

      await _rebindDatabase(verifiedDb);
      verifiedDb = null;
      await _rehydrateAllControllersStrict();
      await _processDueRecurringRulesStrict();

      if (preQuarantineDeleteHookForTesting != null) {
        await preQuarantineDeleteHookForTesting!();
      }
    } catch (e) {
      // 1. Cancel active stream watchers
      try {
        await inboxController.disposeAsync();
      } catch (_) {}
      // 2. Detach listeners & dispose controllers bound to failed DB
      _disposeControllersOnly();
      // 3. Close every candidate DB connection & await completion
      if (verifiedDb != null) {
        await _closeDbSafely(verifiedDb);
        verifiedDb = null;
      }
      if (freshDb != null) {
        await _closeDbSafely(freshDb);
        freshDb = null;
      }
      if (!_dbClosed) {
        await _closeDbSafely();
      }
      _dbClosed = true;

      // 4. Preserve quarantine artifacts & 5. Copy-back original DB + WAL/SHM
      await _recoveryExporter.restoreFromQuarantine(quarantine);

      // 6. Restore prior DB/AppState cleanly according to pre-restore health
      if (wasInitializedBeforeRestore) {
        try {
          final restoredOrigDb = builder();
          await restoredOrigDb.ensureInitialized();
          await _rebindDatabase(restoredOrigDb);
          await _rehydrateAllControllersStrict();
          inboxController.startWatchingUnprocessed();
        } catch (origErr) {
          DatabaseSidecarInventory? inventory;
          try {
            inventory = await _recoveryExporter.inspectDatabaseFilesCold();
          } catch (_) {}
          final origClassified =
              RawDatabaseRecoveryExporter.classifyStartupError(
            origErr,
            previousAttemptCount: (_startupFailure?.attemptCount ?? 0) + 1,
            fileInventory: inventory,
          );
          final persisted = await _recoveryExporter
              .persistFailureDiagnosticAtomic(origClassified);
          if (!_isDisposed) {
            _startupFailure = origClassified;
            _diagnosticFilePersisted = persisted;
            _initializationError = origClassified.message;
            _isInitialized = false;
            if (!_dbClosed) {
              await _closeDbSafely();
            }
            _dbClosed = true;
          }
        }
      } else {
        _isInitialized = false;
        _dbClosed = true;
      }

      // 7. Preserve recovery & backup diagnostics
      final classified = _classifyError(e);
      _lastBackupResult = BackupRestoreResult.failure(
        classified.kind,
        '${classified.message} Original database was restored from quarantine.',
      );
      // 8. Notify UI cleanly & rethrow classified
      notifyListeners();
      throw classified;
    }

    // State promotion happens strictly once restore-critical swap and
    // verification pass; non-critical cleanup never reverses a committed restore.
    _startupFailure = null;
    _initializationError = null;
    _diagnosticFilePersisted = true;
    _isInitialized = true;
    _isInitializing = false;

    final postCommitWarnings = List<String>.from(importReport.warnings);
    final postCommitDiagnostics = List<SnapshotImportDiagnostic>.from(
      importReport.diagnostics,
    );

    try {
      await _recoveryExporter.deleteQuarantine(quarantine);
    } catch (cleanupErr) {
      final diag = SnapshotImportDiagnostic(
        code: 'QUARANTINE_CLEANUP_WARNING',
        message:
            'Database restore succeeded, but quarantine cleanup failed: $cleanupErr',
        table: 'recovery_quarantine',
        severity: SnapshotDiagnosticSeverity.warning,
      );
      postCommitDiagnostics.add(diag);
      postCommitWarnings.add(diag.toWarningString());
    }

    try {
      await _recoveryExporter.clearFailureDiagnostic();
    } catch (diagErr) {
      final diag = SnapshotImportDiagnostic(
        code: 'FAILURE_DIAGNOSTIC_CLEANUP_WARNING',
        message:
            'Database restore succeeded, but startup diagnostic cleanup failed: $diagErr',
        table: 'startup_diagnostic',
        severity: SnapshotDiagnosticSeverity.warning,
      );
      postCommitDiagnostics.add(diag);
      postCommitWarnings.add(diag.toWarningString());
    }

    _lastBackupResult = BackupRestoreResult.success(
      'Database restored cleanly via quarantine swap and verified!',
      List<String>.unmodifiable(postCommitWarnings),
      List<SnapshotImportDiagnostic>.unmodifiable(postCommitDiagnostics),
    );

    // Best-effort post-commit wiring: never triggers rollback
    try {
      inboxController.startWatchingUnprocessed();
    } catch (_) {}
    try {
      _scheduledCommitmentReminders.clear();
      await syncFinanceDueReminders();
      await tasksController.syncTaskReminders();
    } catch (_) {}
    notifyListeners();
    return true;
  }

  /// Non-throwing recovery restore variant returning structured failure details.
  Future<BackupRestoreResult> restoreEncryptedBackupInRecoveryDetailed({
    required String encryptedEnvelopeJson,
    required String passphrase,
  }) async {
    if (_isRestoreInProgress) {
      return const BackupRestoreResult.failure(
        BackupFailureKind.databaseImportFailure,
        _restoreInProgressMessage,
      );
    }
    try {
      await restoreEncryptedBackupInRecovery(
        encryptedEnvelopeJson: encryptedEnvelopeJson,
        passphrase: passphrase,
      );
      return _lastBackupResult ??
          const BackupRestoreResult.success(
            'Database restored cleanly via quarantine swap and verified!',
          );
    } catch (e) {
      final classified = _classifyError(e);
      final failure = _lastBackupResult != null && !_lastBackupResult!.success
          ? _lastBackupResult!
          : BackupRestoreResult.failure(
              classified.kind,
              classified.message,
            );
      _lastBackupResult = failure;
      return failure;
    }
  }

  /// Schedules local notifications for upcoming or due unpaid outflow bills
  /// and expected inflow income commitments (`dueDate <= today + 1 day`).
  Future<void> syncFinanceDueReminders({CalendarDate? asOfDate}) async {
    if (_isDisposed) return;
    final today = asOfDate ?? CalendarDate.today();
    final cutoffJdn = today.jdn + 1;

    final dueCommitments = financeController.state.pendingCommitments
        .where((c) =>
            !c.isPaid && !c.legacyPaidUnverified && c.dueDate.jdn <= cutoffJdn)
        .toList();
    if (dueCommitments.isEmpty) return;

    try {
      if (!_notificationServiceReady) {
        await _notificationService.initialize();
        _notificationServiceReady = true;
      }

      for (final c in dueCommitments) {
        final key =
            '${c.id}:${c.dueDate.toIsoString()}:${c.verifiedSettledCents}:${c.direction.name}';
        if (_scheduledCommitmentReminders.contains(key)) continue;
        _scheduledCommitmentReminders.add(key);

        final isInflow = c.direction == CommitmentDirection.inflow;
        final title = isInflow
            ? 'Expected Income Due: ${c.title}'
            : 'Bill Due: ${c.title}';
        final currencyRes = financeController.state.classifyCommitment(c);
        final displayCurrency = currencyRes.isEligibleEtb
            ? 'ETB'
            : (currencyRes.currencyCode ?? '');
        final formattedAmount = FinancialEngine.formatBirr(
          c.remainingCents,
          currencyCode: displayCurrency,
        );
        final formattedDate =
            SharedDateFormatter.formatDual(c.dueDate, useAmharic: false);
        final body = isInflow
            ? 'Expected $formattedAmount ($formattedDate)'
            : 'Remaining $formattedAmount ($formattedDate)';
        final notifId = 'fin_commitment_${c.id}';
        final payload = 'finance:${c.direction.name}:${c.id}';

        final service = _notificationService;
        if (service is LocalNotificationService) {
          await service.scheduleFinanceDueReminder(
            id: notifId,
            title: title,
            body: body,
            payload: payload,
          );
        } else {
          await service.scheduleReminder(
            id: notifId,
            title: title,
            body: body,
            scheduledDateUtc: EthiopiaClock.nowUtc(),
            payload: payload,
          );
        }
      }
    } catch (_) {
      // Safe no-op on environments without notification plugin bindings.
    }
  }

  Future<bool> requestNotificationPermission() async {
    try {
      if (!_notificationServiceReady) {
        await _notificationService.initialize();
        _notificationServiceReady = true;
      }
      return await _notificationService.requestPermissions();
    } catch (_) {
      return false;
    }
  }

  // --- Read-Only Views Backed Exclusively by Authoritative Controllers ---

  int get openingBalanceCents => financeController.state.openingBalanceCents;
  bool get isFinanceSetupCompleted => financeController.state.isSetupCompleted;

  List<AccountModel> get accounts => financeController.state.accounts;
  List<TransactionCategoryModel> get categories =>
      financeController.state.categories;
  List<PartyModel> get parties => financeController.state.parties;
  List<JournalEntryModel> get journalEntries =>
      financeController.state.journalEntries;
  List<PostingModel> get postings => financeController.state.postings;
  List<DebtModel> get debts => financeController.state.debts;
  List<SettlementAllocationModel> get settlementAllocations =>
      financeController.state.settlementAllocations;
  List<TransactionModel> get transactions =>
      financeController.state.transactions;
  List<CommitmentModel> get commitments => financeController.state.commitments;
  List<SavingsGoalModel> get savingsGoals =>
      financeController.state.savingsGoals;

  List<TaskModel> get tasks => tasksController.state.tasks
      .map(
        (t) => TaskModel(
          id: t.id,
          title: t.title,
          description: t.description,
          status: t.status,
          priority: t.priority,
          dueDate: t.dueDate,
          scheduledDate: t.scheduledDate,
          projectId: t.projectId,
          createdAt: t.createdAt,
        ),
      )
      .toList(growable: false);

  List<ProjectModel> get projects => tasksController.state.projects
      .map(
        (p) => ProjectModel(
          id: p.id,
          title: p.title,
          description: p.description,
          status: p.status,
          targetDate: p.targetDate,
          createdAt: p.createdAt,
        ),
      )
      .toList(growable: false);

  List<NoteModel> get notes => notesController.state.notes
      .map(
        (n) => NoteModel(
          id: n.id,
          title: n.title,
          content: n.content,
          category: n.category,
          projectId: n.projectId,
          linkedModule: n.linkedModule,
          linkedId: n.linkedId,
          tags: n.tags,
          isPinned: n.isPinned,
          isArchived: n.isArchived,
          createdAt: n.createdAt,
          updatedAt: n.updatedAt,
        ),
      )
      .toList(growable: false);

  List<InboxItemModel> get inboxItems => inboxController.state.items
      .map(
        (i) => InboxItemModel(
          id: i.id,
          rawText: i.rawText,
          category: i.category,
          isProcessed: i.isProcessed,
          createdAt: i.createdAt,
        ),
      )
      .toList(growable: false);

  List<CalendarEventEntity> get calendarEvents =>
      calendarController.state.events;

  // --- Computed Metrics Delegated to Controllers ---

  FinancialSnapshot get financialSnapshot =>
      financeController.state.financialSnapshot;
  AvailableToSpendBreakdown get availableToSpendBreakdown =>
      financeController.state.availableToSpendBreakdown;
  CalendarDate get planningPeriodEnd =>
      financeController.state.effectivePlanningPeriodEnd;
  int get liquidCashCents => financeController.state.liquidCashCents;
  int get prepaidCardCreditCents =>
      financeController.state.prepaidCardCreditCents;
  int get netFinancialPositionCents =>
      financeController.state.netFinancialPositionCents;
  int get totalReceivablesCents =>
      financeController.state.totalReceivablesCents;
  int get totalPayablesCents => financeController.state.totalPayablesCents;
  int get availableToSpendCents =>
      financeController.state.availableToSpendCents;
  bool get isFinanceShortfall => financeController.state.isShortfall;
  int get nonEtbAccountCount => financeController.state.nonEtbAccountCount;
  int get unverifiedLegacyPaidCount =>
      financeController.state.unverifiedLegacyPaidCount;
  int get combinedBalanceCents => financeController.state.combinedBalanceCents;
  int get totalIncomeCents => financeController.state.totalIncomeCents;
  int get totalExpenseCents => financeController.state.totalExpenseCents;

  int getAccountBalanceCents(AccountModel account) =>
      financeController.state.getAccountBalanceCents(account);

  int getProjectProgress(String projectId) =>
      tasksController.state.getProjectProgress(projectId);

  // --- Canonical Snapshot, Backup, Restore & Seed Purge ---

  Future<Map<String, dynamic>> exportSnapshot() =>
      _persistenceCoordinator.exportSnapshot();

  /// Imports a canonical snapshot and returns structured success/failure details.
  Future<BackupRestoreResult> importCanonicalSnapshotDetailed(
    Map<String, dynamic> snapshot,
  ) async {
    if (_isRestoreInProgress) {
      return const BackupRestoreResult.failure(
        BackupFailureKind.databaseImportFailure,
        _restoreInProgressMessage,
      );
    }
    _isRestoreInProgress = true;
    _lastBackupResult = null;
    try {
      final prepared =
          DatabasePersistenceCoordinator.validateAndPrepareSnapshot(snapshot);
      final report = await _persistenceCoordinator.importSnapshotDetailed(
        snapshot,
        prepared: prepared,
      );
      await _rehydrateAllControllersStrict();
      await _processDueRecurringRulesStrict();
      try {
        _scheduledCommitmentReminders.clear();
        await syncFinanceDueReminders();
        await tasksController.syncTaskReminders();
      } catch (_) {}
      final ok = BackupRestoreResult.success(
        'Successfully loaded canonical snapshot state!',
        report.warnings,
        report.diagnostics,
      );
      _lastBackupResult = ok;
      notifyListeners();
      return ok;
    } catch (e) {
      final classified = _classifyError(e);
      final failure = BackupRestoreResult.failure(
        classified.kind,
        classified.message,
      );
      _lastBackupResult = failure;
      notifyListeners();
      return failure;
    } finally {
      _isRestoreInProgress = false;
    }
  }

  Future<bool> importCanonicalSnapshot(Map<String, dynamic> snapshot) async {
    final result = await importCanonicalSnapshotDetailed(snapshot);
    return result.success;
  }

  Future<int> purgeKnownSeedData() async {
    final purged = await _persistenceCoordinator.purgeKnownSeedData();
    await _rehydrateAllControllers();
    try {
      await tasksController.syncTaskReminders();
    } catch (_) {}
    notifyListeners();
    return purged;
  }

  Future<String> exportEncryptedBackup(String passphrase) async {
    final stateMap = await _persistenceCoordinator.exportSnapshot();
    final rawJson = jsonEncode(stateMap);
    final exchangeSchemaVersion = (stateMap['schemaVersion'] as int?) ??
        DatabasePersistenceCoordinator.canonicalExchangeSchemaVersion;
    return _backupService.encryptDatabasePayload(
      rawDatabaseJson: rawJson,
      passphrase: passphrase,
      schemaVersion: exchangeSchemaVersion,
    );
  }

  /// Validates, decrypts, and restores an encrypted `.daywell` backup,
  /// returning structured failure diagnostics on rejection.
  Future<BackupRestoreResult> restoreFromEncryptedBackupDetailed(
    String encryptedEnvelopeJson,
    String passphrase,
  ) async {
    if (_isRestoreInProgress) {
      return const BackupRestoreResult.failure(
        BackupFailureKind.databaseImportFailure,
        _restoreInProgressMessage,
      );
    }
    if (_canRebuildDatabase) {
      return await restoreEncryptedBackupInRecoveryDetailed(
        encryptedEnvelopeJson: encryptedEnvelopeJson,
        passphrase: passphrase,
      );
    }
    _isRestoreInProgress = true;
    _lastBackupResult = null;
    try {
      final validatedEnvelope =
          EncryptionBackupService.validateAndParseEnvelope(
        encryptedEnvelopeJson,
      );
      final decryptedJson = await _backupService.decryptDatabasePayload(
        encryptedEnvelopeJson: encryptedEnvelopeJson,
        passphrase: passphrase,
      );
      final dynamic decoded = jsonDecode(decryptedJson);
      if (decoded is! Map<String, dynamic>) {
        const failure = BackupRestoreResult.failure(
          BackupFailureKind.invalidPayload,
          'Decrypted backup payload must be a JSON object.',
        );
        _lastBackupResult = failure;
        notifyListeners();
        return failure;
      }
      final prepared =
          DatabasePersistenceCoordinator.validateAndPrepareSnapshot(
        decoded,
        expectedHeaderVersion: validatedEnvelope.schemaVersion,
      );
      final report = await _persistenceCoordinator.importSnapshotDetailed(
        decoded,
        prepared: prepared,
      );
      await _rehydrateAllControllersStrict();
      await _processDueRecurringRulesStrict();
      final ok = BackupRestoreResult.success(
        'Database restored cleanly and verified!',
        report.warnings,
        report.diagnostics,
      );
      _lastBackupResult = ok;
      try {
        _scheduledCommitmentReminders.clear();
        await syncFinanceDueReminders();
        await tasksController.syncTaskReminders();
      } catch (_) {}
      notifyListeners();
      return ok;
    } catch (e) {
      final classified = _classifyError(e);
      final failure = BackupRestoreResult.failure(
        classified.kind,
        classified.message,
      );
      _lastBackupResult = failure;
      notifyListeners();
      return failure;
    } finally {
      _isRestoreInProgress = false;
    }
  }

  Future<bool> restoreFromEncryptedBackup(
    String encryptedEnvelopeJson,
    String passphrase,
  ) async {
    final result = await restoreFromEncryptedBackupDetailed(
      encryptedEnvelopeJson,
      passphrase,
    );
    return result.success;
  }
}
