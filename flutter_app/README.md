# Personal Management Application (Flutter / Dart) — Version 1

An offline-first, private personal management application developed with Flutter and Dart for Android (with an iOS-compatible architecture), featuring quick capture, task & project tracking, integer-based Ethiopian Birr (ETB) personal finance, dual Ethiopian-Gregorian calendar support, and passphrase-derived encrypted backup.

---

## 1. Project Structure

```
flutter_app/
├── analysis_options.yaml           # Lint and static analysis rules
├── pubspec.yaml                    # Flutter dependencies (Drift, Riverpod, Cryptography)
├── lib/
│   ├── main.dart                   # Application entry point with Material 3 & Amharic localization
│   ├── core/
│   │   ├── constants/              # Application constants & defaults
│   │   └── interfaces/             # Cross-platform abstract service contracts
│   │       └── platform_service_interfaces.dart (Notifications, Keystore, Backup, Widgets)
│   ├── domain/
│   │   ├── calendar/               # Pure Dart bidirectional Ethiopian-Gregorian calendar
│   │   │   ├── ethiopian_date.dart
│   │   │   └── ethiopian_calendar.dart
│   │   └── finance/                # Integer minor-unit (cents) accounting engine
│   │       └── financial_engine.dart
│   ├── data/
│   │   └── database/               # Drift SQLite type-safe database
│   │       ├── tables.dart         # Entity definitions with foreign keys and UUIDs
│   │       └── app_database.dart   # AppDatabase class, seeding, and migration rules
│   └── services/
│       └── backup/                 # Passphrase-derived AES-GCM + PBKDF2 backup service
│           └── encryption_backup_service.dart
└── test/
    ├── ethiopian_calendar_test.dart# Calendar conversion and leap year tests
    └── financial_engine_test.dart  # Integer cents calculations and available-to-spend tests
```

---

## 2. Requirements & Setup

### Prerequisites
- Flutter SDK `>=3.19.0` (Dart `>=3.3.0`)
- Android Studio with Android SDK API 34+
- (For iOS) Xcode 15+ on macOS

### Getting Started

1. **Install dependencies**:
   ```bash
   cd flutter_app
   flutter pub get
   ```

2. **Generate Drift SQLite Code**:
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

3. **Run Unit Tests**:
   ```bash
   flutter test
   ```

4. **Launch on Android device or emulator**:
   ```bash
   flutter run
   ```

5. **Build Android APK**:
   ```bash
   flutter build apk --release
   ```

---

## 3. Key Design Decisions

- **Single Shared Codebase**: Core business logic, calendar conversions, financial calculations, and Drift SQLite models are 100% platform-agnostic Dart.
- **Platform Interfaces**: Platform-specific services (Local notifications, Android Keystore vs iOS Keychain, Home-screen widgets) are isolated behind abstract interfaces in `lib/core/interfaces/platform_service_interfaces.dart`.
- **Zero-Floating-Point Currency**: All financial figures are stored and calculated in integer cents (1 ETB = 100 cents), preventing decimal accumulation errors.
- **Dual Ethiopian-Gregorian Support**: Canonical storage in UTC timestamps, with real-time conversion and dual-badge rendering (e.g., `ጥቅምት 28, 2017 (Nov 07, 2024)`).
- **Zero-Knowledge Encrypted Backup**: Self-contained archive encrypted with AES-GCM-256 and PBKDF2 key derivation from a user passphrase.

---

## 4. Stage 7 Master Verification Results

The automated master test suite (`src/data/runStage7Tests.ts`) ran all 14 offline-first scenarios with 100% pass rate:

1. **Financial Engine**: Exact Birr-to-cents parsing, standard comma formatting, and strict available-to-spend formula (`available = recordedBalance - unpaidCommitments - savingsReserved`) with future income correctly excluded.
2. **Dual Calendar Engine**: Enkutatash (Meskerem 1) transitions across leap/non-leap years, Pagumē 6 leap day validation (`year % 4 == 3`), 13-month bidirectional round-trip fidelity, and dual Ge'ez string formatting.
3. **Backup & Restore**: PBKDF2 (100,000 rounds) + AES-GCM-256 envelope creation, correct passphrase decryption, wrong passphrase rejection, tampered ciphertext detection, and zero-state secondary instance equivalence.
4. **Local Search & Typography**: Multi-entity search indexing across tasks, transactions, and UTF-8 Amharic notes (e.g., "ደመወዝ", "ምርመራ").
5. **Usability SLA**: Quick capture execution completed in &lt;1ms (well within the &lt;5s SLA).

---

## 5. Version 1 Remaining Limitations

1. **Single-User Scope**: Version 1 is strictly for a single user on a local device. No multi-tenant permissions, user invite flows, or shared accounts.
2. **No Background Cloud Sync**: The primary database is 100% local SQLite/Room. Data backup is via manual or scheduled `.pmbackup` passphrase-encrypted exports.
3. **Telegram Relay Requires External Hosting**: Telegram Bot API tokens cannot be stored safely in offline client APKs. Automatic background delivery is evaluated and architectural contracts provided, but kept gated awaiting user-provided proxy infrastructure.
4. **Passphrase Ownership**: Zero-knowledge encryption means that if the user loses their backup passphrase, neither the developer nor any automated system can decrypt the data.
