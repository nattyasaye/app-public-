import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:personal_management_app/application/projects/projects_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/shared_foundation_core.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/repositories/projects_repository.dart';
import 'package:personal_management_app/domain/projects/project_models.dart';
import 'package:personal_management_app/domain/projects/project_package_codec.dart';

import 'support/sqlite_test_helper.dart';

void main() {
  setUpAll(configureSqliteForHostTests);

  String readSharedFixtureJson() {
    final candidates = [
      p.join(
        Directory.current.path,
        '..',
        'shared_foundation',
        'fixtures',
        'sample_project_package_v1.json',
      ),
      p.join(
        Directory.current.path,
        'shared_foundation',
        'fixtures',
        'sample_project_package_v1.json',
      ),
    ];
    for (final candidate in candidates) {
      final file = File(candidate);
      if (file.existsSync()) {
        return file.readAsStringSync();
      }
    }
    throw StateError(
      'Unable to locate shared_foundation/fixtures/sample_project_package_v1.json from ${Directory.current.path}',
    );
  }

  group('Projects Stage 3 — ProjectPackageCodec Unit Tests', () {
    test(
      'parses shared canonical v1 fixture, remaps IDs without collision, and clears cross-module refs',
      () {
        final fixtureJson = readSharedFixtureJson();
        final parsed = ProjectPackageCodec.parseAndValidate(fixtureJson);

        expect(parsed.formatId, SharedProjectPackageSpec.formatId);
        expect(
          parsed.formatVersion,
          SharedProjectPackageSpec.currentFormatVersion,
        );
        expect(parsed.trackingBlocks.length, 6);
        expect(parsed.trackingRecords.length, 11);

        final prepared = ProjectPackageCodec.prepareForImport(
          fixtureJson,
          existingProjectIds: const ['fx-proj-studio'],
          existingBlockIds: const ['fx-blk-counter'],
          existingRecordIds: const ['fx-rec-grp-1'],
        );

        expect(prepared.project.id, isNot('fx-proj-studio'));
        expect(prepared.project.title, 'Home Studio Build & Curriculum');
        expect(prepared.project.goalId, isNull);
        expect(prepared.trackingBlocks.length, 6);
        expect(prepared.trackingRecords.length, 11);

        final newBlockIds = prepared.trackingBlocks.map((b) => b.id).toSet();
        expect(newBlockIds.contains('fx-blk-counter'), isFalse);

        final rollup = prepared.trackingBlocks.firstWhere(
          (b) => b.blockType == ProjectBlockType.counter &&
              b.config['rollupSourceBlockId'] != null,
        );
        final grouped = prepared.trackingBlocks.firstWhere(
          (b) => b.blockType == ProjectBlockType.groupedList,
        );
        expect(rollup.config['rollupSourceBlockId'], grouped.id);
        expect(prepared.project.customFields['primaryBlockId'], rollup.id);

        for (final rec in prepared.trackingRecords) {
          expect(rec.projectId, prepared.project.id);
          expect(rec.linkedTaskId, isNull);
          expect(newBlockIds.contains(rec.blockId), isTrue);
        }
      },
    );

    test(
      'buildFilename sanitizes project titles and rejects unsupported versions/malformed payloads',
      () {
        expect(
          ProjectPackageCodec.buildFilename('Video Learning Plan (v1)!'),
          'video-learning-plan-v1.daywellproject',
        );
        expect(
          ProjectPackageCodec.buildFilename('   '),
          'daywell-project.daywellproject',
        );

        expect(
          () => ProjectPackageCodec.parseAndValidate(''),
          throwsA(
            isA<ProjectPackageException>().having(
              (e) => e.kind,
              'kind',
              ProjectPackageErrorKind.malformedJson,
            ),
          ),
        );

        final validMap =
            jsonDecode(readSharedFixtureJson()) as Map<String, dynamic>;

        final futureMap = Map<String, dynamic>.from(validMap)
          ..['formatVersion'] = 99;
        expect(
          () => ProjectPackageCodec.parseAndValidate(jsonEncode(futureMap)),
          throwsA(
            isA<ProjectPackageException>().having(
              (e) => e.kind,
              'kind',
              ProjectPackageErrorKind.unsupportedVersion,
            ),
          ),
        );

        final wrongFormatMap = Map<String, dynamic>.from(validMap)
          ..['formatId'] = 'not_a_project_pkg';
        expect(
          () => ProjectPackageCodec.parseAndValidate(jsonEncode(wrongFormatMap)),
          throwsA(
            isA<ProjectPackageException>().having(
              (e) => e.kind,
              'kind',
              ProjectPackageErrorKind.invalidFormat,
            ),
          ),
        );
      },
    );
  });

  group(
    'Projects Stage 3 — DriftProjectsRepository & ProjectsController Import/Export',
    () {
      late Directory tempDir;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('daywell_proj_stage3_');
      });

      tearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      test(
        'imports shared fixture twice keeping original title, preserves history & metrics, and exports portable JSON without goalId/linkedTaskId',
        () async {
          final dbFile = File(p.join(tempDir.path, 'stage3_pkg.sqlite'));
          final db = AppDatabase(NativeDatabase(dbFile));
          await db.ensureInitialized();

          await db.into(db.goals).insert(
                GoalsCompanion.insert(
                  id: 'goal-local',
                  title: 'Local Goal',
                  createdAt: DateTime.utc(2026, 11, 1),
                ),
              );
          await db.into(db.tasks).insert(
                TasksCompanion.insert(
                  id: 'task-local',
                  title: 'Local Task',
                  createdAt: DateTime.utc(2026, 11, 1),
                  updatedAt: DateTime.utc(2026, 11, 1),
                ),
              );

          final repo = DriftProjectsRepository(db);
          final controller = ProjectsController(repository: repo);

          final fixtureJson = readSharedFixtureJson();
          final import1 = await controller.importProjectPackageJson(fixtureJson);
          final import2 = await controller.importProjectPackageJson(fixtureJson);

          expect(import1, isNotNull);
          expect(import2, isNotNull);
          expect(import1!.project.id, isNot(import2!.project.id));
          expect(import1.project.title, 'Home Studio Build & Curriculum');
          expect(import2.project.title, 'Home Studio Build & Curriculum');
          expect(import1.project.goalId, isNull);

          final summary1 = await controller.loadProjectSummary(
            import1.project.id,
            asOfDate: CalendarDate(year: 2026, month: 11, day: 12),
          );
          expect(summary1, isNotNull);
          expect(summary1!.blockMetrics.length, 6);
          expect(summary1.overallPercentage?.round(), 33);
          expect(summary1.primaryMetric?.loggedTotal, 10);

          final archivedMetric = summary1.blockMetrics.firstWhere(
            (m) => m.isArchived,
          );
          expect(archivedMetric.loggedTotal, 3);

          // Export from controller -> strip check & re-import parity
          final reExportJson =
              await controller.exportProjectPackageJson(import1.project.id);
          expect(reExportJson, isNotNull);
          final reDecoded = jsonDecode(reExportJson!) as Map<String, dynamic>;
          expect(reDecoded['formatId'], SharedProjectPackageSpec.formatId);
          expect(
            reDecoded['formatVersion'],
            SharedProjectPackageSpec.currentFormatVersion,
          );
          expect(reDecoded['sourcePlatform'], 'android');
          final projJson = reDecoded['project'] as Map<String, dynamic>;
          expect(projJson.containsKey('goalId'), isFalse);
          for (final rec in reDecoded['trackingRecords'] as List) {
            expect(
              (rec as Map<String, dynamic>).containsKey('linkedTaskId'),
              isFalse,
            );
          }

          // Rejecting an invalid package leaves existing projects untouched
          final countBefore = controller.state.projects.length;
          final invalidFuture = Map<String, dynamic>.from(reDecoded)
            ..['formatVersion'] = 2;
          final failedImport = await controller.importProjectPackageJson(
            jsonEncode(invalidFuture),
          );
          expect(failedImport, isNull);
          expect(controller.state.errorMessage, contains('formatVersion 2'));
          expect(controller.state.projects.length, countBefore);

          // Also verify source project with goalId & linkedTaskId exports cleanly without them
          final sourceProj = await controller.createProject(
            id: 'proj-with-refs',
            title: 'Local Refs Project',
            goalId: 'goal-local',
          );
          expect(sourceProj, isNotNull);
          final blk = await controller.createBlock(
            id: 'blk-with-ref',
            projectId: 'proj-with-refs',
            blockType: ProjectBlockType.schedule,
            title: 'Sessions',
          );
          expect(blk, isNotNull);
          await controller.createRecord(
            id: 'rec-with-ref',
            projectId: 'proj-with-refs',
            blockId: 'blk-with-ref',
            recordType: ProjectRecordType.scheduleItem,
            title: 'Session 1',
            durationMinutes: 45,
            linkedTaskId: 'task-local',
          );

          final refExportJson =
              await controller.exportProjectPackageJson('proj-with-refs');
          final refExportMap =
              jsonDecode(refExportJson!) as Map<String, dynamic>;
          expect(
            (refExportMap['project'] as Map<String, dynamic>).containsKey(
              'goalId',
            ),
            isFalse,
          );
          final exportedRec =
              (refExportMap['trackingRecords'] as List).single
                  as Map<String, dynamic>;
          expect(exportedRec.containsKey('linkedTaskId'), isFalse);

          controller.dispose();
          await db.close();
        },
      );
    },
  );
}
