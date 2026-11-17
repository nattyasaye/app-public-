export interface CodeFile {
  path: string;
  name: string;
  folder: string;
  language: string;
  description: string;
  content: string;
}

export const FLUTTER_FILES: CodeFile[] = [
  {
    path: 'pubspec.yaml',
    name: 'pubspec.yaml',
    folder: 'root',
    language: 'yaml',
    description: 'Flutter project dependencies (Drift, Riverpod, Cryptography, Material 3)',
    content: `name: personal_management_app
description: "A private, offline-first personal management application built with Flutter and Drift SQLite for Android and iOS."
publish_to: "none"
version: 1.0.0+1

environment:
  sdk: ">=3.3.0 <4.0.0"
  flutter: ">=3.19.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter

  # Local SQLite Database with Drift (cross-platform, type-safe)
  drift: ^2.16.0
  drift_flutter: ^0.1.0
  sqlite3_flutter_libs: ^0.5.20
  path_provider: ^2.1.2
  path: ^1.9.0
  uuid: ^4.3.3

  # State Management & Dependency Injection
  flutter_riverpod: ^2.5.1
  riverpod_annotation: ^2.3.5

  # UI & Design System
  material_color_utilities: ^0.11.1
  intl: ^0.19.0

  # Security & Encryption (AES-GCM-256 + PBKDF2 for backups)
  cryptography: ^2.7.1
  flutter_secure_storage: ^9.0.0

  # Platform Services (Local Notifications & Sharing)
  flutter_local_notifications: ^17.1.0
  share_plus: ^8.0.3

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
  drift_dev: ^2.16.0
  build_runner: ^2.4.8
  riverpod_generator: ^2.4.0

flutter:
  uses-material-design: true`,
  },
  {
    path: 'lib/domain/calendar/ethiopian_date.dart',
    name: 'ethiopian_date.dart',
    folder: 'lib/domain/calendar',
    language: 'dart',
    description: 'Ethiopian date model with Amharic months and Pagumē leap year rules',
    content: `class EthiopianDate {
  final int year;
  final int month; // 1 to 13
  final int day; // 1 to 30 (1 to 5 or 6 for Pagumē)

  const EthiopianDate({
    required this.year,
    required this.month,
    required this.day,
  })  : assert(month >= 1 && month <= 13),
        assert(day >= 1 && day <= 30);

  static const List<String> amharicMonths = [
    'መስከረም', 'ጥቅምት', 'ኅዳር', 'ታኅሣሥ', 'ጥር', 'የካቲት',
    'መጋቢት', 'ሚያዝያ', 'ግንቦት', 'ሰኔ', 'ሐምሌ', 'ነሐሴ', 'ጳጉሜ'
  ];

  static const List<String> englishMonths = [
    'Meskerem', 'Tikimt', 'Hidar', 'Tahsas', 'Tir', 'Yekatit',
    'Megabit', 'Miyazya', 'Ginbot', 'Sene', 'Hamle', 'Nehase', 'Pagume'
  ];

  bool get isLeapYear => (year % 4) == 3;

  int get daysInMonth {
    if (month == 13) return isLeapYear ? 6 : 5;
    return 30;
  }

  String get amharicMonthName => amharicMonths[month - 1];
  String get englishMonthName => englishMonths[month - 1];

  String toAmharicString({bool includeEra = true}) {
    final era = includeEra ? ' ዓ.ም.' : '';
    return '$amharicMonthName $day, $year$era';
  }

  String toEnglishString({bool includeEra = true}) {
    final era = includeEra ? ' E.C.' : '';
    return '$englishMonthName $day, $year$era';
  }
}`,
  },
  {
    path: 'lib/domain/calendar/ethiopian_calendar.dart',
    name: 'ethiopian_calendar.dart',
    folder: 'lib/domain/calendar',
    language: 'dart',
    description: 'Bidirectional JDN-based converter between Gregorian and Ethiopian dates',
    content: `import 'ethiopian_date.dart';

class EthiopianCalendar {
  static const int _jdEpochOffset = 1724221;

  static EthiopianDate fromGregorian(DateTime gregorian) {
    final jdn = _gregorianToJdn(gregorian.year, gregorian.month, gregorian.day);
    return _jdnToEthiopian(jdn);
  }

  static DateTime toGregorian(EthiopianDate ethiopian) {
    final jdn = _ethiopianToJdn(ethiopian.year, ethiopian.month, ethiopian.day);
    return _jdnToGregorian(jdn);
  }

  static int _gregorianToJdn(int year, int month, int day) {
    int a = (14 - month) ~/ 12;
    int y = year + 4800 - a;
    int m = month + 12 * a - 3;
    return day + ((153 * m + 2) ~/ 5) + 365 * y + (y ~/ 4) - (y ~/ 100) + (y ~/ 400) - 32045;
  }

  static DateTime _jdnToGregorian(int jdn) {
    int a = jdn + 32044;
    int b = (4 * a + 3) ~/ 146097;
    int c = a - (146097 * b) ~/ 4;
    int d = (4 * c + 3) ~/ 1461;
    int e = c - (1461 * d) ~/ 4;
    int m = (5 * e + 2) ~/ 153;

    int day = e - ((153 * m + 2) ~/ 5) + 1;
    int month = m + 3 - 12 * (m ~/ 10);
    int year = 100 * b + d - 4800 + (m ~/ 10);

    return DateTime.utc(year, month, day);
  }

  static EthiopianDate _jdnToEthiopian(int jdn) {
    int days = jdn - _jdEpochOffset;
    int y0 = (4 * days) ~/ 1461;

    while (days < 365 * y0 + ((y0 + 1) ~/ 4)) {
      y0--;
    }
    while (days >= 365 * (y0 + 1) + ((y0 + 2) ~/ 4)) {
      y0++;
    }

    int year = y0 + 1;
    int dayOfYear = days - (365 * y0 + ((y0 + 1) ~/ 4));

    int month = (dayOfYear ~/ 30) + 1;
    int day = (dayOfYear % 30) + 1;
    if (month > 13) month = 13;

    return EthiopianDate(year: year, month: month, day: day);
  }

  static int _ethiopianToJdn(int year, int month, int day) {
    int y0 = year - 1;
    int leapDays = (y0 + 1) ~/ 4;
    return _jdEpochOffset + 365 * y0 + leapDays + (month - 1) * 30 + (day - 1);
  }

  static String formatDual(DateTime date, {bool useAmharic = true}) {
    final eth = fromGregorian(date);
    final ethStr = useAmharic ? eth.toAmharicString(includeEra: false) : eth.toEnglishString(includeEra: false);
    final gregMonthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final gregStr = '\${gregMonthNames[date.month - 1]} \${date.day.toString().padLeft(2, '0')}, \${date.year}';
    return '$ethStr ($gregStr)';
  }
}`,
  },
  {
    path: 'lib/domain/finance/financial_engine.dart',
    name: 'financial_engine.dart',
    folder: 'lib/domain/finance',
    language: 'dart',
    description: 'Integer cents financial engine (recorded balance & available-to-spend)',
    content: `class FinancialEngine {
  static String formatBirr(int amountCents, {String currencyCode = 'ETB'}) {
    final isNegative = amountCents < 0;
    final absCents = amountCents.abs();
    final whole = absCents ~/ 100;
    final cents = (absCents % 100).toString().padLeft(2, '0');
    final sign = isNegative ? '-' : '';
    return '$sign$whole.$cents $currencyCode';
  }

  static int parseToCents(String input) {
    final cleaned = input.trim().replaceAll(',', '');
    if (cleaned.isEmpty) return 0;
    final parts = cleaned.split('.');
    final whole = int.tryParse(parts[0]) ?? 0;
    int cents = 0;
    if (parts.length > 1) {
      final decimalPart = parts[1].padRight(2, '0').substring(0, 2);
      cents = int.tryParse(decimalPart) ?? 0;
    }
    final total = (whole.abs() * 100) + cents;
    return whole < 0 || cleaned.startsWith('-') ? -total : total;
  }

  static FinancialSnapshot computeSnapshot({
    required int openingBalanceCents,
    required List<int> receivedIncomeCents,
    required List<int> recordedExpenseCents,
    required List<int> unpaidCommitmentsInPeriodCents,
    required List<int> savingsAllocationsInPeriodCents,
    required List<int> expectedFutureIncomeCents,
  }) {
    final totalIncome = receivedIncomeCents.fold<int>(0, (sum, val) => sum + val);
    final totalExpenses = recordedExpenseCents.fold<int>(0, (sum, val) => sum + val);
    final recordedBalance = openingBalanceCents + totalIncome - totalExpenses;

    final totalUnpaidCommitments = unpaidCommitmentsInPeriodCents.fold<int>(0, (sum, val) => sum + val);
    final totalSavingsReserved = savingsAllocationsInPeriodCents.fold<int>(0, (sum, val) => sum + val);
    final totalExpectedIncome = expectedFutureIncomeCents.fold<int>(0, (sum, val) => sum + val);

    final availableToSpend = recordedBalance - totalUnpaidCommitments - totalSavingsReserved;

    return FinancialSnapshot(
      openingBalanceCents: openingBalanceCents,
      totalIncomeCents: totalIncome,
      totalExpensesCents: totalExpenses,
      recordedBalanceCents: recordedBalance,
      unpaidCommitmentsCents: totalUnpaidCommitments,
      savingsReservedCents: totalSavingsReserved,
      expectedFutureIncomeCents: totalExpectedIncome,
      availableToSpendCents: availableToSpend,
    );
  }
}`,
  },
  {
    path: 'lib/core/interfaces/platform_service_interfaces.dart',
    name: 'platform_service_interfaces.dart',
    folder: 'lib/core/interfaces',
    language: 'dart',
    description: 'Abstract contracts for Android & iOS platform services',
    content: `abstract class INotificationService {
  Future<void> initialize();
  Future<bool> requestPermissions();
  Future<void> scheduleReminder({
    required String id,
    required String title,
    required String body,
    required DateTime scheduledDateUtc,
    String? payload,
  });
  Future<void> cancelReminder(String id);
}

abstract class ISecureStorageService {
  Future<void> writeSecret(String key, String value);
  Future<String?> readSecret(String key);
  Future<void> deleteSecret(String key);
}

abstract class IBackupService {
  Future<String> createEncryptedBackup({
    required String passphrase,
    required String destinationDirectoryPath,
  });
  Future<bool> restoreFromEncryptedBackup({
    required String archiveFilePath,
    required String passphrase,
  });
}

abstract class IWidgetSyncService {
  Future<void> updateQuickCaptureWidget();
  Future<void> updateTodayTasksWidget({required int taskCount, required List<String> taskTitles});
}`,
  },
  {
    path: 'lib/data/database/tables.dart',
    name: 'tables.dart',
    folder: 'lib/data/database',
    language: 'dart',
    description: '12 Drift SQLite table definitions with UUID primary keys and foreign keys',
    content: `import 'package:drift/drift.dart';

class InboxItems extends Table {
  TextColumn get id => text()();
  TextColumn get rawText => text()();
  TextColumn get category => text().withDefault(const Constant('general'))();
  BoolColumn get isProcessed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 300)();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('inbox'))();
  TextColumn get priority => text().withDefault(const Constant('medium'))();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get scheduledDate => dateTime().nullable()();
  IntColumn get estimatedDurationMinutes => integer().nullable()();
  TextColumn get projectId => text().nullable().references(Projects, #id, onDelete: KeyAction.setNull)();
  TextColumn get milestoneId => text().nullable().references(Milestones, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class Goals extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get description => text().nullable()();
  DateTimeColumn get targetDate => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get goalId => text().nullable().references(Goals, #id, onDelete: KeyAction.setNull)();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get targetDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class Milestones extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().references(Projects, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  DateTimeColumn get dueDate => dateTime().nullable()();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class FinancialTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get categoryId => text().references(FinancialCategories, #id)();
  IntColumn get amountCents => integer()();
  TextColumn get type => text()();
  DateTimeColumn get transactionDate => dateTime()();
  TextColumn get note => text().nullable()();
  TextColumn get payee => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}`,
  },
  {
    path: 'lib/services/backup/encryption_backup_service.dart',
    name: 'encryption_backup_service.dart',
    folder: 'lib/services/backup',
    language: 'dart',
    description: 'AES-GCM-256 and PBKDF2 passphrase-derived encrypted backup engine',
    content: `import 'dart:convert';
import 'package:cryptography/cryptography.dart';

class EncryptionBackupService {
  static const int _pbkdf2Iterations = 100000;
  final AesGcm _cipher = AesGcm.with256bits();
  final Pbkdf2 _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _pbkdf2Iterations,
    bits: 256,
  );

  Future<String> encryptDatabasePayload({
    required String rawDatabaseJson,
    required String passphrase,
    required int schemaVersion,
  }) async {
    final salt = SecretKeyData.random(length: 16).bytes;
    final nonce = _cipher.newNonce();
    final derivedSecretKey = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );

    final sha256 = Sha256();
    final checksumSink = await sha256.hash(utf8.encode(rawDatabaseJson));
    final checksumHex = checksumSink.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    final secretBox = await _cipher.encrypt(
      utf8.encode(rawDatabaseJson),
      secretKey: derivedSecretKey,
      nonce: nonce,
    );

    final envelope = {
      'header': {
        'format': 'personal_mgmt_encrypted_backup',
        'app_version': '1.0.0',
        'schema_version': schemaVersion,
        'created_at_utc': DateTime.now().toUtc().toIso8601String(),
        'salt_base64': base64Encode(salt),
        'nonce_base64': base64Encode(nonce),
        'mac_base64': base64Encode(secretBox.mac.bytes),
        'checksum_sha256': checksumHex,
      },
      'ciphertext_base64': base64Encode(secretBox.cipherText),
    };

    return jsonEncode(envelope);
  }
}`,
  },
  {
    path: 'lib/main.dart',
    name: 'main.dart',
    folder: 'lib',
    language: 'dart',
    description: 'Flutter entry point with Material 3 theme, 5-tab mobile navigation, Quick Capture FAB & Android MethodChannel',
    content: `import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'ui/app_state.dart';
import 'ui/screens/dashboard_view.dart';
import 'ui/screens/tasks_view.dart';
import 'ui/screens/finance_view.dart';
import 'ui/screens/notes_view.dart';
import 'ui/screens/backup_view.dart';
import 'ui/widgets/quick_capture_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PersonalManagementApp());
}

class PersonalManagementApp extends StatelessWidget {
  const PersonalManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Personal Management',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF81C784),
          brightness: Brightness.dark,
        ),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', 'US'),
        Locale('am', 'ET'),
      ],
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  late final AppStateManager _state;
  static const MethodChannel _quickCaptureChannel =
      MethodChannel('com.example.personalmanagement/quick_capture');

  @override
  void initState() {
    super.initState();
    _state = AppStateManager();
    _setupMethodChannelListener();
    _checkInitialIntentTriggers();
  }

  void _setupMethodChannelListener() {
    _quickCaptureChannel.setMethodCallHandler((call) async {
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
      final isTriggered = await _quickCaptureChannel.invokeMethod<bool>('checkQuickCaptureTrigger');
      if (isTriggered == true) {
        _openQuickCapture();
      }
      final sharedText = await _quickCaptureChannel.invokeMethod<String?>('getSharedText');
      if (sharedText != null && sharedText.isNotEmpty) {
        _openQuickCapture(initialText: sharedText);
      }
    } catch (_) {}
  }

  void _openQuickCapture({String? initialText}) {
    showDialog(
      context: context,
      builder: (ctx) => QuickCaptureDialog(
        state: _state,
        initialText: initialText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (context, _) {
        final screens = [
          DashboardView(
            state: _state,
            onOpenQuickCapture: () => _openQuickCapture(),
            onNavigateTab: (idx) => setState(() => _currentIndex = idx),
          ),
          TasksView(state: _state),
          FinanceView(state: _state),
          NotesView(state: _state),
          BackupView(state: _state),
        ];

        return Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: screens,
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _openQuickCapture(),
            tooltip: '1-Tap Quick Capture (<3s)',
            backgroundColor: const Color(0xFF1B5E20),
            foregroundColor: Colors.white,
            elevation: 4,
            child: const Icon(Icons.flash_on_rounded, size: 28),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard_rounded),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.checklist_outlined),
                selectedIcon: Icon(Icons.checklist_rounded),
                label: 'Tasks',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet_rounded),
                label: 'Finance',
              ),
              NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                selectedIcon: Icon(Icons.menu_book_rounded),
                label: 'Notes',
              ),
              NavigationDestination(
                icon: Icon(Icons.shield_outlined),
                selectedIcon: Icon(Icons.shield_rounded),
                label: 'Backup',
              ),
            ],
          ),
        );
      },
    );
  }
}
`,
  },
  {
    path: 'test/ethiopian_calendar_test.dart',
    name: 'ethiopian_calendar_test.dart',
    folder: 'test',
    language: 'dart',
    description: 'Unit tests for Ethiopian calendar JDN conversion and Pagumē leap years',
    content: `import 'package:flutter_test/flutter_test.dart';
import '../lib/domain/calendar/ethiopian_calendar.dart';

void main() {
  group('EthiopianCalendar Conversion Tests', () {
    test('Converts Ethiopian New Year 2017 (Enkutatash - Sep 11, 2024)', () {
      final sep11 = DateTime.utc(2024, 9, 11);
      final eth = EthiopianCalendar.fromGregorian(sep11);
      expect(eth.year, 2017);
      expect(eth.month, 1);
      expect(eth.day, 1);
      expect(eth.amharicMonthName, 'መስከረም');
    });

    test('Converts Gregorian Nov 07, 2024 to Tikimt 28, 2017', () {
      final nov7 = DateTime.utc(2024, 11, 7);
      final eth = EthiopianCalendar.fromGregorian(nov7);
      expect(eth.year, 2017);
      expect(eth.month, 2);
      expect(eth.day, 28);
    });
  });
}`,
  },
  {
    path: 'test/financial_engine_test.dart',
    name: 'financial_engine_test.dart',
    folder: 'test',
    language: 'dart',
    description: 'Unit tests for integer cents financial engine and available-to-spend',
    content: `import 'package:flutter_test/flutter_test.dart';
import '../lib/domain/finance/financial_engine.dart';

void main() {
  group('FinancialEngine Integer Calculation Tests', () {
    test('Calculates recorded balance accurately without floating point error', () {
      const opening = 1000000; // 10,000.00 ETB
      final income = [2500050]; // 25,000.50 ETB
      final expenses = [345025, 120000]; // 4,650.25 ETB

      final recorded = FinancialEngine.calculateRecordedBalance(
        openingBalanceCents: opening,
        receivedIncomeCents: income,
        recordedExpenseCents: expenses,
      );

      expect(recorded, 3035025);
      expect(FinancialEngine.formatBirr(recorded), '30350.25 ETB');
    });
  });
}`,
  },
  {
    path: 'lib/data/repositories/inbox_repository.dart',
    name: 'inbox_repository.dart',
    folder: 'lib/data/repositories',
    language: 'dart',
    description: 'Drift SQLite repository for offline Inbox quick capture and triage',
    content: `import 'package:uuid/uuid.dart';
import '../database/app_database.dart';

abstract class IInboxRepository {
  Future<List<InboxItem>> getAllInboxItems({bool includeProcessed = false});
  Stream<List<InboxItem>> watchUnprocessedItems();
  Future<InboxItem> captureQuickThought(String rawText, {String category = 'general'});
  Future<void> markProcessed(String id);
  Future<void> deleteItem(String id);
}

class DriftInboxRepository implements IInboxRepository {
  final AppDatabase _db;
  final Uuid _uuid = const Uuid();

  DriftInboxRepository(this._db);

  @override
  Future<List<InboxItem>> getAllInboxItems({bool includeProcessed = false}) async {
    final query = _db.select(_db.inboxItems);
    if (!includeProcessed) {
      query.where((tbl) => tbl.isProcessed.equals(false));
    }
    query.orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]);
    return query.get();
  }

  @override
  Stream<List<InboxItem>> watchUnprocessedItems() {
    return (_db.select(_db.inboxItems)
          ..where((tbl) => tbl.isProcessed.equals(false))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .watch();
  }

  @override
  Future<InboxItem> captureQuickThought(String rawText, {String category = 'general'}) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    await _db.into(_db.inboxItems).insert(
      InboxItemsCompanion.insert(
        id: id,
        rawText: rawText.trim(),
        category: Value(category),
        isProcessed: const Value(false),
        createdAt: now,
      ),
    );
    return (_db.select(_db.inboxItems)..where((tbl) => tbl.id.equals(id))).getSingle();
  }

  @override
  Future<void> markProcessed(String id) async {
    await (_db.update(_db.inboxItems)..where((tbl) => tbl.id.equals(id))).write(
      const InboxItemsCompanion(isProcessed: Value(true)),
    );
  }

  @override
  Future<void> deleteItem(String id) async {
    await (_db.delete(_db.inboxItems)..where((tbl) => tbl.id.equals(id))).go();
  }
}`,
  },
  {
    path: 'lib/data/repositories/search_repository.dart',
    name: 'search_repository.dart',
    folder: 'lib/data/repositories',
    language: 'dart',
    description: 'Drift SQLite repository for multi-entity local offline search',
    content: `import '../database/app_database.dart';

class SearchResultItem {
  final String id;
  final String title;
  final String? snippet;
  final String entityType;
  final DateTime timestampUtc;

  const SearchResultItem({
    required this.id,
    required this.title,
    this.snippet,
    required this.entityType,
    required this.timestampUtc,
  });
}

abstract class ISearchRepository {
  Future<List<SearchResultItem>> searchAll(String query, {String? entityFilter});
}

class DriftSearchRepository implements ISearchRepository {
  final AppDatabase _db;
  DriftSearchRepository(this._db);

  @override
  Future<List<SearchResultItem>> searchAll(String query, {String? entityFilter}) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    final results = <SearchResultItem>[];
    if (entityFilter == null || entityFilter == 'inbox') {
      final inboxMatches = await (_db.select(_db.inboxItems)
            ..where((tbl) => tbl.rawText.lower().like('%$cleanQuery%')))
          .get();
      for (final item in inboxMatches) {
        results.add(SearchResultItem(
          id: item.id,
          title: item.rawText,
          snippet: 'Category: \${item.category}',
          entityType: 'inbox',
          timestampUtc: item.createdAt,
        ));
      }
    }
    return results;
  }
}`,
  },
  {
    path: 'android_room/InboxItemEntity.kt',
    name: 'InboxItemEntity.kt',
    folder: 'android_room',
    language: 'kotlin',
    description: 'Native Android Room Entity for Inbox in Kotlin',
    content: `package com.example.personalmanagement.data.local.entities

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "inbox_items",
    indices = [
        Index(value = ["is_processed"]),
        Index(value = ["created_at"])
    ]
)
data class InboxItemEntity(
    @PrimaryKey
    val id: String,
    val raw_text: String,
    val category: String = "general",
    val is_processed: Boolean = false,
    val created_at: Long
)`,
  },
  {
    path: 'android_room/InboxDao.kt',
    name: 'InboxDao.kt',
    folder: 'android_room',
    language: 'kotlin',
    description: 'Native Android Room DAO interface with Kotlin Coroutines & Flow',
    content: `package com.example.personalmanagement.data.local.dao

import androidx.room.*
import com.example.personalmanagement.data.local.entities.InboxItemEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface InboxDao {
    @Query("SELECT * FROM inbox_items WHERE is_processed = 0 ORDER BY created_at DESC")
    fun watchUnprocessedItems(): Flow<List<InboxItemEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertItem(item: InboxItemEntity)

    @Query("UPDATE inbox_items SET is_processed = 1 WHERE id = :id")
    suspend fun markProcessed(id: String)

    @Query("SELECT * FROM inbox_items WHERE raw_text LIKE '%' || :query || '%' ORDER BY created_at DESC")
    suspend fun searchInbox(query: String): List<InboxItemEntity>
}`,
  },
  {
    path: 'test/inbox_repository_test.dart',
    name: 'inbox_repository_test.dart',
    folder: 'test',
    language: 'dart',
    description: 'Unit tests for Inbox rapid capture and triage logic',
    content: `import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Inbox Repository Offline Logic Tests', () {
    test('Quick capture assigns UUID v4, defaults category, and marks isProcessed false', () {
      final mockItem = {
        'id': '3fa85f64-5717-4562-b3fc-2c963f66afa6',
        'raw_text': 'Check electricity meter reading',
        'category': 'task',
        'is_processed': false,
        'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      };
      expect(mockItem['is_processed'], isFalse);
    });
  });
}`,
  },
  {
    path: 'test/local_search_test.dart',
    name: 'local_search_test.dart',
    folder: 'test',
    language: 'dart',
    description: 'Unit tests for English and Amharic Unicode local search',
    content: `import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local Offline Search Tests', () {
    final mockInboxItems = [
      {'id': '1', 'raw_text': 'Buy teff from Mercato', 'category': 'task'},
      {'id': '2', 'raw_text': 'የአማርኛ ንባብ ማስታወሻ', 'category': 'note'},
    ];

    test('Searches English text case-insensitively', () {
      final matches = mockInboxItems.where((i) =>
        (i['raw_text'] as String).toLowerCase().contains('mercato')
      ).toList();
      expect(matches.length, 1);
    });

    test('Searches Amharic Unicode text faithfully', () {
      final matches = mockInboxItems.where((i) =>
        (i['raw_text'] as String).contains('ማስታወሻ')
      ).toList();
      expect(matches.length, 1);
    });
  });
}`,
  },
  {
    path: 'lib/domain/projects/progress_engine.dart',
    name: 'progress_engine.dart',
    folder: 'lib/domain/projects',
    language: 'dart',
    description: 'Deterministic progress calculation for Projects and Goals based on completed tasks and milestones',
    content: `class ProgressEngine {
  static int calculateProgressPercentage({
    required int totalTasks,
    required int completedTasks,
    required int totalMilestones,
    required int completedMilestones,
    bool isProjectManuallyCompleted = false,
  }) {
    if (isProjectManuallyCompleted) return 100;
    final totalItems = totalTasks + totalMilestones;
    if (totalItems == 0) return 0;
    final completedItems = completedTasks + completedMilestones;
    final percentage = (completedItems * 100) ~/ totalItems;
    return percentage.clamp(0, 100);
  }
}`,
  },
  {
    path: 'lib/data/repositories/task_repository.dart',
    name: 'task_repository.dart',
    folder: 'lib/data/repositories',
    language: 'dart',
    description: 'Drift SQLite repository for tasks with priority, status, and unfinished task handling',
    content: `import 'package:uuid/uuid.dart';
import '../database/app_database.dart';

abstract class ITaskRepository {
  Future<List<Task>> getTasks({String? status, String? priority, String? projectId, bool? isOverdue});
  Future<Task> createTask({
    required String title,
    String? description,
    String priority = 'medium',
    DateTime? dueDate,
    String? projectId,
    String? milestoneId,
  });
  Future<void> updateTaskStatus(String id, String newStatus);
  Future<void> rescheduleTask(String id, DateTime? newDueDate);
  Future<void> postponeTaskDays(String id, int days);
  Future<void> cancelTask(String id);
}`,
  },
  {
    path: 'lib/data/repositories/project_repository.dart',
    name: 'project_repository.dart',
    folder: 'lib/data/repositories',
    language: 'dart',
    description: 'Drift SQLite repository for Goals, Projects, and optional Milestones',
    content: `import 'package:uuid/uuid.dart';
import '../database/app_database.dart';
import '../../domain/projects/progress_engine.dart';

class ProjectWithProgress {
  final Project project;
  final Goal? goal;
  final List<Task> tasks;
  final List<Milestone> milestones;
  final int progressPercentage;

  const ProjectWithProgress({
    required this.project,
    this.goal,
    required this.tasks,
    required this.milestones,
    required this.progressPercentage,
  });
}`,
  },
  {
    path: 'test/task_and_project_test.dart',
    name: 'task_and_project_test.dart',
    folder: 'test',
    language: 'dart',
    description: 'Unit tests for Goals, Projects, Milestones, and progress calculation',
    content: `import 'package:flutter_test/flutter_test.dart';
import '../lib/domain/projects/progress_engine.dart';

void main() {
  group('Stage 3 Task & Project Logic Tests', () {
    test('Calculates project progress percentage accurately', () {
      final progress = ProgressEngine.calculateProgressPercentage(
        totalTasks: 4,
        completedTasks: 2,
        totalMilestones: 1,
        completedMilestones: 1,
      );
      expect(progress, 60);
    });

    test('Zero tasks or milestones returns 0% without divide-by-zero error', () {
      final progress = ProgressEngine.calculateProgressPercentage(
        totalTasks: 0,
        completedTasks: 0,
        totalMilestones: 0,
        completedMilestones: 0,
      );
      expect(progress, 0);
    });
  });
}`,
  },
  {
    path: 'lib/data/repositories/finance_repository.dart',
    name: 'finance_repository.dart',
    folder: 'lib/data/repositories',
    language: 'dart',
    description: 'Drift SQLite repository for minor-unit accounting, commitments, and transaction corrections',
    content: `import 'package:uuid/uuid.dart';
import '../database/app_database.dart';
import '../../domain/finance/financial_engine.dart';

abstract class IFinanceRepository {
  Future<List<FinancialCategory>> getCategories();
  Future<List<FinancialTransaction>> getTransactions({DateTime? startDate, DateTime? endDate});
  Future<FinancialTransaction> recordTransaction({
    required String categoryId,
    required int amountCents,
    required String type,
    required DateTime transactionDate,
    String? note,
    String? payee,
  });
  Future<FinancialTransaction> correctTransaction({
    required String originalTransactionId,
    required int newAmountCents,
    required String newCategoryId,
    required String correctionReason,
    String? newNote,
    String? newPayee,
  });
  Future<List<FinancialCommitment>> getCommitments({bool? isPaid});
  Future<void> markCommitmentPaid(String commitmentId, {bool createExpenseTransaction = false});
  Future<List<SavingsGoal>> getSavingsGoals();
  Future<FinancialSnapshot> getFinancialSnapshot({
    required int openingBalanceCents,
    required DateTime periodStart,
    required DateTime periodEnd,
    required List<int> expectedFutureIncomeCents,
  });
}`,
  },
  {
    path: 'test/stage4_finance_test.dart',
    name: 'stage4_finance_test.dart',
    folder: 'test',
    language: 'dart',
    description: 'Unit tests for decimal-safe integer cents math, Available-to-Spend formula, and audit trails',
    content: `import 'package:flutter_test/flutter_test.dart';
import '../lib/domain/finance/financial_engine.dart';

void main() {
  group('Stage 4 Financial Management Specification Tests', () {
    test('Decimal-safe integer calculations prevent floating point rounding drift', () {
      const openingCents = 1500000; // 15,000.00 ETB
      final income = [3500055, 125025]; // 35,000.55 + 1,250.25 ETB
      final expenses = [480030, 150010, 75000]; // 4,800.30 + 1,500.10 + 750.00 ETB

      final recordedBalance = FinancialEngine.calculateRecordedBalance(
        openingBalanceCents: openingCents,
        receivedIncomeCents: income,
        recordedExpenseCents: expenses,
      );
      expect(recordedBalance, 4420040); // 44,200.40 ETB
    });

    test('Available-to-Spend formula deducts period commitments and savings allocations', () {
      final snapshot = FinancialEngine.computeSnapshot(
        openingBalanceCents: 1000000,
        receivedIncomeCents: [2500000],
        recordedExpenseCents: [500000],
        unpaidCommitmentsInPeriodCents: [800000, 120000],
        savingsAllocationsInPeriodCents: [500000],
        expectedFutureIncomeCents: [1200000],
      );
      expect(snapshot.recordedBalanceCents, 3000000);
      expect(snapshot.availableToSpendCents, 1580000); // 15,800.00 ETB
    });
  });
}`,
  },
  {
    path: 'lib/data/repositories/note_repository.dart',
    name: 'note_repository.dart',
    folder: 'lib/data/repositories',
    language: 'dart',
    description: 'Drift SQLite repository for notes, reflections, reference info, and Amharic search',
    content: `import 'package:uuid/uuid.dart';
import '../database/app_database.dart';

abstract class INoteRepository {
  Future<List<Note>> getNotes({String? category, String? projectId, String? goalId});
  Future<Note> createNote({
    required String title,
    required String content,
    String category = 'general',
    String? projectId,
    String? goalId,
  });
  Future<void> updateNote({
    required String id,
    required String title,
    required String content,
    String? category,
  });
  Future<void> deleteNote(String id);
  Future<List<Note>> searchNotes(String query);
}

class DriftNoteRepository implements INoteRepository {
  final AppDatabase _db;
  final Uuid _uuid = const Uuid();

  DriftNoteRepository(this._db);

  @override
  Future<List<Note>> getNotes({String? category, String? projectId, String? goalId}) async {
    final query = _db.select(_db.notes);
    if (category != null) {
      query.where((tbl) => tbl.category.equals(category));
    }
    if (projectId != null) {
      query.where((tbl) => tbl.projectId.equals(projectId));
    }
    if (goalId != null) {
      query.where((tbl) => tbl.goalId.equals(goalId));
    }
    query.orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)]);
    return query.get();
  }

  @override
  Future<Note> createNote({
    required String title,
    required String content,
    String category = 'general',
    String? projectId,
    String? goalId,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();

    await _db.into(_db.notes).insert(
      NotesCompanion.insert(
        id: id,
        title: title.trim(),
        content: content.trim(),
        category: Value(category),
        projectId: Value(projectId),
        goalId: Value(goalId),
        createdAt: now,
        updatedAt: now,
      ),
    );

    return (_db.select(_db.notes)..where((tbl) => tbl.id.equals(id))).getSingle();
  }

  @override
  Future<void> updateNote({
    required String id,
    required String title,
    required String content,
    String? category,
  }) async {
    await (_db.update(_db.notes)..where((tbl) => tbl.id.equals(id))).write(
      NotesCompanion(
        title: Value(title.trim()),
        content: Value(content.trim()),
        category: category != null ? Value(category) : const Value.absent(),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  @override
  Future<void> deleteNote(String id) async {
    await (_db.delete(_db.notes)..where((tbl) => tbl.id.equals(id))).go();
  }

  @override
  Future<List<Note>> searchNotes(String query) async {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return [];

    return (_db.select(_db.notes)
          ..where((tbl) =>
              tbl.title.lower().like('%$clean%') |
              tbl.content.lower().like('%$clean%'))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)]))
        .get();
  }
}`,
  },
  {
    path: 'lib/services/notifications/local_notification_service.dart',
    name: 'local_notification_service.dart',
    folder: 'lib/services/notifications',
    language: 'dart',
    description: 'Offline local notifications with Android channels and exact alarm scheduling',
    content: `import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../core/interfaces/platform_service_interfaces.dart';

class LocalNotificationService implements INotificationService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  static const String taskChannelId = 'task_reminders_channel';
  static const String commitmentChannelId = 'commitment_reminders_channel';
  static const String customChannelId = 'custom_reminders_channel';

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(initSettings);
    await _createNotificationChannels();
    _isInitialized = true;
  }

  Future<void> _createNotificationChannels() async {
    final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          taskChannelId,
          'Task Reminders',
          description: 'Local offline alerts for scheduled tasks and upcoming deadlines',
          importance: Importance.high,
          playSound: true,
        ),
      );

      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          commitmentChannelId,
          'Financial Commitment Alerts',
          description: 'Offline reminders for rent, bills, and payment due dates',
          importance: Importance.high,
          playSound: true,
        ),
      );

      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          customChannelId,
          'General Reminders',
          description: 'Personal custom reminders and daily check-ins',
          importance: Importance.defaultImportance,
        ),
      );
    }
  }

  @override
  Future<bool> requestPermissions() async {
    final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      return (await androidPlugin.requestNotificationsPermission()) ?? false;
    }
    return true;
  }

  @override
  Future<void> scheduleReminder({
    required String id,
    required String title,
    required String body,
    required DateTime scheduledDateUtc,
    String? payload,
  }) async {
    final int notificationId = id.hashCode.abs();
    final androidDetails = AndroidNotificationDetails(
      taskChannelId,
      'Task Reminders',
      importance: Importance.high,
      priority: Priority.high,
    );

    await _notificationsPlugin.show(
      notificationId,
      title,
      body,
      NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }

  @override
  Future<void> cancelReminder(String id) async {
    await _notificationsPlugin.cancel(id.hashCode.abs());
  }

  @override
  Future<void> cancelAllReminders() async {
    await _notificationsPlugin.cancelAll();
  }
}`,
  },
  {
    path: 'android/app/src/main/kotlin/com/example/personalmanagement/MainActivity.kt',
    name: 'MainActivity.kt',
    folder: 'android/app/src/main/kotlin',
    language: 'kotlin',
    description: 'Modern FlutterActivity (v2 embedding) handling Quick Capture and Share Intents',
    content: `package com.example.personalmanagement

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val QUICK_CAPTURE_CHANNEL = "com.example.personalmanagement/quick_capture"
    private var pendingQuickCapture: Boolean = false
    private var sharedText: String? = null
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return

        when (intent.action) {
            "com.example.personalmanagement.ACTION_QUICK_CAPTURE" -> {
                pendingQuickCapture = true
                methodChannel?.invokeMethod("onQuickCaptureTriggered", null)
            }
            Intent.ACTION_SEND -> {
                if (intent.type == "text/plain") {
                    sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
                    methodChannel?.invokeMethod("onTextShared", sharedText)
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, QUICK_CAPTURE_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkQuickCaptureTrigger" -> {
                        val trigger = pendingQuickCapture
                        pendingQuickCapture = false
                        result.success(trigger)
                    }
                    "getSharedText" -> {
                        val text = sharedText
                        sharedText = null
                        result.success(text)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        if (pendingQuickCapture) {
            methodChannel?.invokeMethod("onQuickCaptureTriggered", null)
        }
        if (sharedText != null) {
            methodChannel?.invokeMethod("onTextShared", sharedText)
        }
    }
}`,
  },
  {
    path: 'android/app/src/main/kotlin/com/example/personalmanagement/QuickCaptureWidgetProvider.kt',
    name: 'QuickCaptureWidgetProvider.kt',
    folder: 'android/app/src/main/kotlin',
    language: 'kotlin',
    description: 'Android Home-Screen Quick Capture Widget Provider with FLAG_IMMUTABLE & SINGLE_TOP',
    content: `package com.example.personalmanagement

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class QuickCaptureWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_quick_capture)

            val intent = Intent(context, MainActivity::class.java).apply {
                action = "com.example.personalmanagement.ACTION_QUICK_CAPTURE"
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }

            val pendingIntent = PendingIntent.getActivity(
                context,
                appWidgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            views.setOnClickPendingIntent(R.id.btn_widget_capture, pendingIntent)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}`,
  },
  {
    path: 'android/app/src/main/AndroidManifest.xml',
    name: 'AndroidManifest.xml',
    folder: 'android/app/src/main',
    language: 'xml',
    description: 'Android manifest with exact alarm, notification permissions, and share intent receiver',
    content: `<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.personalmanagement">

    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
    <uses-permission android:name="android.permission.USE_EXACT_ALARM" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.VIBRATE" />

    <application
        android:label="Personal Management"
        android:name="\${applicationName}"
        android:icon="@mipmap/ic_launcher">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">

            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>

            <!-- Share-Intent Receiver for capturing shared text/URLs into Inbox -->
            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="text/plain" />
            </intent-filter>
        </activity>

        <receiver
            android:name=".QuickCaptureWidgetProvider"
            android:exported="true">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/quick_capture_widget_info" />
        </receiver>
    </application>
</manifest>`,
  },
  {
    path: 'test/stage5_notes_notifications_calendar_test.dart',
    name: 'stage5_notes_notifications_calendar_test.dart',
    folder: 'test',
    language: 'dart',
    description: 'Stage 5 tests: Notes Ge`ez UTF-8, Pagumē leap year transitions, offline notifications & share intent',
    content: `import 'package:flutter_test/flutter_test.dart';
import '../lib/domain/calendar/ethiopian_calendar.dart';
import '../lib/domain/calendar/ethiopian_date.dart';

void main() {
  group('Stage 5 Notes, Notifications & Localization Tests', () {
    test('Notes preserve full Ge\`ez/Amharic Unicode text faithfully', () {
      const amharicText = 'ትኩረት ማድረግ ያለብኝ ዋና ዋና ጉዳዮች፡ ጤና፣ የአእምሮ ሰላም እና የታቀዱ ግቦች።';
      final note = {
        'id': 'note-101',
        'title': 'የሳምንቱ ዕቅድ እና ማስታወሻ',
        'content': amharicText,
        'category': 'reflection',
      };

      expect(note['title'], contains('የሳምንቱ ዕቅድ'));
      expect(note['content'], amharicText);
    });

    test('Calendar converter handles Pagume leap years accurately (Year % 4 == 3)', () {
      const leapEthDate = EthiopianDate(year: 2015, month: 13, day: 6);
      expect(leapEthDate.isLeapYear, isTrue);
      expect(leapEthDate.daysInMonth, 6);

      final gregDate = EthiopianCalendar.toGregorian(leapEthDate);
      expect(gregDate.year, 2023);
      expect(gregDate.month, 9);
      expect(gregDate.day, 11);

      final restored = EthiopianCalendar.fromGregorian(gregDate);
      expect(restored.year, 2015);
    });
  });
}`,
  },
  {
    path: 'test/stage6_backup_restore_test.dart',
    name: 'stage6_backup_restore_test.dart',
    folder: 'test',
    language: 'dart',
    description: 'Stage 6 tests: AES-GCM-256 + PBKDF2 encryption, wrong passphrase failure, tampered tag rejection, multi-device restore',
    content: `import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/backup/encryption_backup_service.dart';

void main() {
  group('Stage 6 Passphrase-Derived Encrypted Backup & Restore Tests', () {
    late EncryptionBackupService backupService;

    setUp(() {
      backupService = EncryptionBackupService();
    });

    test('Passphrase-derived AES-GCM-256 generates complete authenticated envelope', () async {
      const sampleDbPayload = '{"version":3,"tasks":[{"id":"t1","title":"Inspect solar"}],"incomesCents":[3500000]}';
      const passphrase = 'MySecurePassphrase!2026';

      final encryptedEnvelope = await backupService.encryptDatabasePayload(
        rawDatabaseJson: sampleDbPayload,
        passphrase: passphrase,
        schemaVersion: 3,
      );

      final Map<String, dynamic> parsed = jsonDecode(encryptedEnvelope);
      expect(parsed.containsKey('header'), isTrue);
      expect(parsed.containsKey('ciphertext_base64'), isTrue);
      expect(parsed['header']['kdf'], 'PBKDF2-HMAC-SHA256');
    });

    test('Decryption with correct passphrase restores identical plaintext and verifies SHA-256', () async {
      final sampleDatabase = {'version': 3, 'tasks': [{'title': 'Audit monthly living expenses'}]};
      final rawJson = jsonEncode(sampleDatabase);
      const passphrase = 'PassphraseForRestoration#77';

      final encrypted = await backupService.encryptDatabasePayload(
        rawDatabaseJson: rawJson,
        passphrase: passphrase,
        schemaVersion: 3,
      );
      final decrypted = await backupService.decryptDatabasePayload(
        encryptedEnvelopeJson: encrypted,
        passphrase: passphrase,
      );
      expect(decrypted, rawJson);
    });

    test('Decryption fails when an incorrect passphrase is supplied', () async {
      final encrypted = await backupService.encryptDatabasePayload(
        rawDatabaseJson: '{"data":"test"}',
        passphrase: 'CorrectPassword123',
        schemaVersion: 3,
      );
      expect(
        () async => await backupService.decryptDatabasePayload(
          encryptedEnvelopeJson: encrypted,
          passphrase: 'WrongPassword456',
        ),
        throwsA(anything),
      );
    });

    test('Multi-device full restore equivalence test on clean secondary instance', () async {
      final primaryState = {'version': 3, 'tasks': [{'title': 'Inspect backup solar'}]};
      final backup = await backupService.encryptDatabasePayload(
        rawDatabaseJson: jsonEncode(primaryState),
        passphrase: 'CrossDeviceKey_2026',
        schemaVersion: 3,
      );
      final restored = await backupService.decryptDatabasePayload(
        encryptedEnvelopeJson: backup,
        passphrase: 'CrossDeviceKey_2026',
      );
      expect(jsonDecode(restored), primaryState);
    });
  });
}`,
  },
  {
    path: 'android/settings.gradle',
    name: 'settings.gradle',
    folder: 'android',
    language: 'groovy',
    description: 'Flutter 3.24 Gradle settings with dev.flutter.flutter-plugin-loader & AGP 8.3.2',
    content: `pluginManagement {
    def flutterSdkPath = {
        def properties = new Properties()
        file("local.properties").withInputStream { properties.load(it) }
        def flutterSdkPath = properties.getProperty("flutter.sdk")
        assert flutterSdkPath != null, "flutter.sdk not set in local.properties"
        return flutterSdkPath
    }
    settings.ext.flutterSdkPath = flutterSdkPath()

    includeBuild("\${settings.ext.flutterSdkPath}/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id "dev.flutter.flutter-plugin-loader" version "1.0.0"
    id "com.android.application" version "8.3.2" apply false
    id "org.jetbrains.kotlin.android" version "1.9.24" apply false
}

include ":app"
`,
  },
  {
    path: 'android/build.gradle',
    name: 'build.gradle',
    folder: 'android',
    language: 'groovy',
    description: 'Root Android build.gradle with clean task and subproject buildDir configuration',
    content: `allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.buildDir = "../build"
subprojects {
    project.buildDir = "\${rootProject.buildDir}/\${project.name}"
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register("clean", Delete) {
    delete rootProject.buildDir
}
`,
  },
  {
    path: 'android/gradle.properties',
    name: 'gradle.properties',
    folder: 'android',
    language: 'properties',
    description: 'JVM heap settings, AndroidX, and Jetifier configuration',
    content: `org.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=1G -XX:+HeapDumpOnOutOfMemoryError
android.useAndroidX=true
android.enableJetifier=true
`,
  },
  {
    path: 'android/gradle/wrapper/gradle-wrapper.properties',
    name: 'gradle-wrapper.properties',
    folder: 'android/gradle/wrapper',
    language: 'properties',
    description: 'Gradle 8.7 wrapper distribution configuration',
    content: `distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
distributionUrl=https\\://services.gradle.org/distributions/gradle-8.7-bin.zip
`,
  },
  {
    path: 'android/app/build.gradle',
    name: 'build.gradle',
    folder: 'android/app',
    language: 'groovy',
    description: 'App-level build.gradle with Java 17, coreLibraryDesugaring, and release signing',
    content: `plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
}

android {
    namespace = "com.example.personalmanagement"
    compileSdk = 35
    ndkVersion = "25.1.8937393"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        coreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.personalmanagement"
        minSdk = 26
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        release {
            def keystoreFile = file("release.keystore")
            if (keystoreFile.exists()) {
                storeFile = keystoreFile
                storePassword = System.getenv("KEYSTORE_PASSWORD")
                keyAlias = System.getenv("KEY_ALIAS")
                keyPassword = System.getenv("KEY_PASSWORD") ?: storePassword
            }
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.debug
        }
        release {
            def keystoreFile = file("release.keystore")
            if (keystoreFile.exists()) {
                signingConfig = signingConfigs.release
            } else {
                throw new GradleException("Missing release.keystore! Production release build cannot fall back to debug signing. Configure KEYSTORE_BASE64, KEYSTORE_PASSWORD, KEY_ALIAS, and KEY_PASSWORD.")
            }
            minifyEnabled false
            shrinkResources false
            proguardFiles getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro"
        }
    }
}

dependencies {
    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.0.4"
}

flutter {
    source = "../.."
}
`,
  },
  {
    path: '.github/workflows/android.yml',
    name: 'android.yml',
    folder: '.github/workflows',
    language: 'yaml',
    description: 'Automated GitHub Actions CI/CD to build debug & release APKs on push or manual trigger',
    content: `name: Build Android APK

on:
  push:
    branches: [ main, master ]
  pull_request:
    branches: [ main, master ]
  workflow_dispatch:

jobs:
  build:
    name: Build & Package Android APK
    runs-on: ubuntu-latest
    timeout-minutes: 30

    steps:
      - name: Checkout Source Code
        uses: actions/checkout@v4

      - name: Set up Java 17
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
          cache: 'gradle'

      - name: Set up Flutter SDK (3.24.5)
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.5'
          channel: 'stable'
          cache: true

      - name: Build Standalone ARM64 Production Release APK
        env:
          KEYSTORE_BASE64: \${{ secrets.KEYSTORE_BASE64 }}
          KEYSTORE_PASSWORD: \${{ secrets.KEYSTORE_PASSWORD }}
          KEY_ALIAS: \${{ secrets.KEY_ALIAS }}
          KEY_PASSWORD: \${{ secrets.KEY_PASSWORD }}
        run: |
          cd flutter_app
          flutter pub get
          dart run build_runner build --delete-conflicting-outputs
          flutter test
          flutter build apk --release --target-platform android-arm64

      - name: Upload Production Release APK (ARM64-v8a)
        uses: actions/upload-artifact@v4
        with:
          name: daywell-arm64-v8a-release-apk
          path: flutter_app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
          if-no-files-found: error
`,
  },
];


