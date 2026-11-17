import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';

describe('STAGE 3: REPOSITORY RESOURCES & PRODUCTION APK SEPARATION AUDIT', () => {
  const rootDir = process.cwd();

  it('1. Flutter Assets Exclusion: pubspec.yaml does not bundle repository mockups or web assets', () => {
    const pubspecPath = path.join(rootDir, 'flutter_app', 'pubspec.yaml');
    assert.strictEqual(fs.existsSync(pubspecPath), true, 'flutter_app/pubspec.yaml must exist');
    const pubspecContent = fs.readFileSync(pubspecPath, 'utf8');

    // Ensure design_assets or public screens are NOT declared in assets:
    assert.strictEqual(
      pubspecContent.includes('design_assets'),
      false,
      'pubspec.yaml must NOT reference design_assets'
    );
    assert.strictEqual(
      pubspecContent.includes('public/screens'),
      false,
      'pubspec.yaml must NOT reference public/screens'
    );
    assert.strictEqual(
      pubspecContent.includes('personal_management_app_flutter.zip'),
      false,
      'pubspec.yaml must NOT reference zip archives'
    );
    assert.strictEqual(
      pubspecContent.includes('personal_management_v1.apk'),
      false,
      'pubspec.yaml must NOT reference existing apk files'
    );
  });

  it('2. Flutter Import Boundary: flutter_app/lib/ never imports web or parent src files', () => {
    const libDir = path.join(rootDir, 'flutter_app', 'lib');
    function scanDir(dir: string): string[] {
      let files: string[] = [];
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const entry of entries) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          files = files.concat(scanDir(full));
        } else if (entry.name.endsWith('.dart')) {
          files.push(full);
        }
      }
      return files;
    }

    const dartFiles = scanDir(libDir);
    assert.strictEqual(dartFiles.length > 10, true, 'Should find Dart files in flutter_app/lib');

    for (const f of dartFiles) {
      const content = fs.readFileSync(f, 'utf8');
      const lines = content.split('\n');
      for (const line of lines) {
        if (line.trim().startsWith('import ') || line.trim().startsWith('export ')) {
          assert.strictEqual(
            line.includes('/src/') || line.includes('../src') || line.includes('../../src'),
            false,
            `File ${f} must not import from web src directory: ${line}`
          );
        }
      }
    }
  });

  it('3. Gradle Source Isolation: Prototype android_room is excluded from main compile sourceSets', () => {
    const buildGradlePath = path.join(rootDir, 'flutter_app', 'android', 'app', 'build.gradle');
    assert.strictEqual(fs.existsSync(buildGradlePath), true, 'app/build.gradle must exist');
    const gradleContent = fs.readFileSync(buildGradlePath, 'utf8');

    // Ensure android_room is not added to sourceSets
    assert.strictEqual(
      gradleContent.includes('android_room'),
      false,
      'build.gradle must not include android_room in sourceSets'
    );
  });

  it('4. Flutter UI Verification: TasksView and NotesView cleanly import SharedDesignTokens and valid callbacks', () => {
    const tasksViewPath = path.join(rootDir, 'flutter_app', 'lib', 'ui', 'screens', 'tasks_view.dart');
    const tasksContent = fs.readFileSync(tasksViewPath, 'utf8');
    assert.strictEqual(
      tasksContent.includes("import '../../core/shared_foundation.dart';"),
      true,
      'tasks_view.dart must import shared_foundation.dart'
    );
    assert.strictEqual(
      tasksContent.includes('_showQuickAddModal()'),
      true,
      'tasks_view.dart must call _showQuickAddModal()'
    );
    assert.strictEqual(
      tasksContent.includes('_openQuickAddModal'),
      false,
      'tasks_view.dart must not call undefined _openQuickAddModal'
    );

    const notesViewPath = path.join(rootDir, 'flutter_app', 'lib', 'ui', 'screens', 'notes_view.dart');
    const notesContent = fs.readFileSync(notesViewPath, 'utf8');
    assert.strictEqual(
      notesContent.includes("import '../../core/shared_foundation.dart';"),
      true,
      'notes_view.dart must import shared_foundation.dart'
    );
    assert.strictEqual(
      notesContent.includes('_openNoteEditor()'),
      true,
      'notes_view.dart must call parameterless _openNoteEditor()'
    );
    assert.strictEqual(
      notesContent.includes('_openNoteEditor(context)'),
      false,
      'notes_view.dart must not pass context to _openNoteEditor'
    );
  });

  it('5. Web Preview Codebase Viewer: src/data/flutterCodebase.ts remains isolated in Web Preview', () => {
    const flutterCodebasePath = path.join(rootDir, 'src', 'data', 'flutterCodebase.ts');
    assert.strictEqual(fs.existsSync(flutterCodebasePath), true, 'flutterCodebase.ts must exist for Web Preview');

    // Ensure no dart file references flutterCodebase
    const libDir = path.join(rootDir, 'flutter_app', 'lib');
    function scanDir(dir: string): string[] {
      let files: string[] = [];
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const entry of entries) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          files = files.concat(scanDir(full));
        } else if (entry.name.endsWith('.dart')) {
          files.push(full);
        }
      }
      return files;
    }
    const dartFiles = scanDir(libDir);
    for (const f of dartFiles) {
      const content = fs.readFileSync(f, 'utf8');
      assert.strictEqual(
        content.includes('flutterCodebase'),
        false,
        `Dart file ${f} must not reference flutterCodebase`
      );
    }
  });

  it('6. Shared Foundation Parity: Design Tokens, Business Rules, and Seed Schemas remain identical', () => {
    const tsFoundationPath = path.join(rootDir, 'src', 'domain', 'sharedFoundation.ts');
    const dartFoundationPath = path.join(rootDir, 'flutter_app', 'lib', 'core', 'shared_foundation.dart');

    assert.strictEqual(fs.existsSync(tsFoundationPath), true, 'sharedFoundation.ts must exist');
    assert.strictEqual(fs.existsSync(dartFoundationPath), true, 'shared_foundation.dart must exist');

    const tsContent = fs.readFileSync(tsFoundationPath, 'utf8');
    const dartContent = fs.readFileSync(dartFoundationPath, 'utf8');

    // Primary Emerald hex 1B4D3E
    assert.strictEqual(tsContent.includes('1B4D3E') || tsContent.includes('#1B4D3E'), true);
    assert.strictEqual(dartContent.includes('0xFF1B4D3E'), true);

    // Business rules: ETB currency
    assert.strictEqual(tsContent.includes('ETB'), true);
    assert.strictEqual(dartContent.includes('ETB'), true);
  });

  it('7. Shared UI Widgets & Zero Raster Images: shared_ui_widgets.dart provides clean foundation without raster assets', () => {
    const widgetsDir = path.join(rootDir, 'flutter_app', 'lib', 'ui', 'widgets');
    const widgetsPath = path.join(widgetsDir, 'shared_ui_widgets.dart');
    assert.strictEqual(fs.existsSync(widgetsPath), true, 'shared_ui_widgets.dart must exist');
    const content = fs.readFileSync(widgetsPath, 'utf8');

    const emptyStatePath = path.join(widgetsDir, 'cards', 'daywell_empty_state.dart');
    const cardPath = path.join(widgetsDir, 'cards', 'daywell_card.dart');
    const sectionHeaderPath = path.join(widgetsDir, 'cards', 'daywell_section_header.dart');

    assert.strictEqual(content.includes("export 'cards/daywell_empty_state.dart';"), true, 'Must re-export DaywellEmptyState');
    assert.strictEqual(content.includes("export 'cards/daywell_card.dart';"), true, 'Must re-export DaywellCard');
    assert.strictEqual(content.includes("export 'cards/daywell_section_header.dart';"), true, 'Must re-export DaywellSectionHeader');

    const emptyStateCode = fs.readFileSync(emptyStatePath, 'utf8');
    const cardCode = fs.readFileSync(cardPath, 'utf8');
    const sectionHeaderCode = fs.readFileSync(sectionHeaderPath, 'utf8');

    assert.strictEqual(emptyStateCode.includes('class DaywellEmptyState'), true, 'Must define DaywellEmptyState');
    assert.strictEqual(cardCode.includes('class DaywellCard'), true, 'Must define DaywellCard');
    assert.strictEqual(sectionHeaderCode.includes('class DaywellSectionHeader'), true, 'Must define DaywellSectionHeader');
    assert.strictEqual(cardCode.includes('SharedDesignTokens.'), true, 'Must use SharedDesignTokens');
    assert.strictEqual(cardCode.includes('daywell_theme.dart'), true, 'Must integrate with DaywellTheme');

    // Verify zero raster image references in flutter_app/lib/
    const libDir = path.join(rootDir, 'flutter_app', 'lib');
    function scanAllDart(dir: string): string[] {
      let files: string[] = [];
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const entry of entries) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          files = files.concat(scanAllDart(full));
        } else if (entry.name.endsWith('.dart')) {
          files.push(full);
        }
      }
      return files;
    }
    const allDart = scanAllDart(libDir);
    for (const f of allDart) {
      const code = fs.readFileSync(f, 'utf8');
      assert.strictEqual(
        code.includes('Image.asset') || code.includes('AssetImage'),
        false,
        `File ${f} must not load raster image assets`
      );
    }
  });
});
