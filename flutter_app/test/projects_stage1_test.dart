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
import 'package:personal_management_app/domain/projects/progress_engine.dart';
import 'package:personal_management_app/domain/projects/project_models.dart';
import 'package:personal_management_app/domain/projects/project_validation_service.dart';
import 'package:personal_management_app/domain/tasks/task_models.dart';

import 'support/sqlite_test_helper.dart';

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Projects Stage 1 — Domain Validation', () {
    test('validates project lifecycle, dates, and typed customFields', () {
      final valid = ProjectEntity(
        id: 'proj-valid',
        title: 'BIM Company Outreach',
        status: 'active',
        isArchived: false,
        startDate: CalendarDate(year: 2026, month: 11, day: 1),
        targetDate: CalendarDate(year: 2026, month: 12, day: 15),
        customFields: {
          'primaryBlockId': 'blk-campaign-counter',
          'definitions': [
            {
              'id': 'channel',
              'label': 'Channel',
              'type': 'select',
              'required': true,
              'options': ['Email', 'LinkedIn'],
            },
            {
              'id': 'daily_goal',
              'label': 'Daily Goal',
              'type': 'number',
              'required': false,
            },
            {
              'id': 'kickoff',
              'label': 'Kickoff',
              'type': 'date',
              'required': false,
            },
            {
              'id': 'verified',
              'label': 'Verified',
              'type': 'boolean',
              'required': false,
            },
          ],
          'values': {
            'channel': 'Email',
            'daily_goal': 25,
            'kickoff': '2026-11-01',
            'verified': true,
          },
        },
      );

      expect(
        () => ProjectValidationService.validateProject(valid),
        returnsNormally,
      );

      // Invalid targetDate earlier than startDate
      expect(
        () => ProjectValidationService.validateProject(
          valid.copyWith(
            startDate: CalendarDate(year: 2026, month: 12, day: 1),
            targetDate: CalendarDate(year: 2026, month: 11, day: 15),
          ),
        ),
        throwsA(isA<ProjectValidationException>()),
      );

      // Unknown value without matching definition
      expect(
        () => ProjectValidationService.validateCustomFieldsMap({
          'definitions': [],
          'values': {'unknown_key': 'oops'},
        }),
        throwsA(isA<ProjectValidationException>()),
      );

      // Nested object inside customFields values
      expect(
        () => ProjectValidationService.validateCustomFieldsMap({
          'definitions': [
            {'id': 'meta', 'label': 'Meta', 'type': 'text'},
          ],
          'values': {
            'meta': {'nested': true},
          },
        }),
        throwsA(isA<ProjectValidationException>()),
      );

      // Missing required custom field
      expect(
        () => ProjectValidationService.validateCustomFieldsMap({
          'definitions': [
            {
              'id': 'tier',
              'label': 'Tier',
              'type': 'select',
              'required': true,
              'options': ['A', 'B'],
            },
          ],
          'values': {},
        }),
        throwsA(isA<ProjectValidationException>()),
      );
    });

    test('validates block configs, rollup guards, and max block count', () {
      final groupedBlock = ProjectTrackingBlockEntity(
        id: 'blk-cities',
        projectId: 'proj-1',
        blockType: ProjectBlockType.groupedList,
        title: 'Cities by Region',
        unitLabel: 'emails',
      );
      expect(
        () => ProjectValidationService.validateBlock(
          groupedBlock,
          expectedProjectId: 'proj-1',
          projectBlocks: const [],
        ),
        returnsNormally,
      );

      // Rollup counter referencing grouped_list with allowDirectLogging: false passes
      final validRollup = ProjectTrackingBlockEntity(
        id: 'blk-rollup',
        projectId: 'proj-1',
        blockType: ProjectBlockType.counter,
        title: 'Campaign Total',
        targetValue: 1000,
        config: const {
          'rollupSourceBlockId': 'blk-cities',
          'allowDirectLogging': false,
        },
      );
      expect(
        () => ProjectValidationService.validateBlock(
          validRollup,
          expectedProjectId: 'proj-1',
          projectBlocks: [groupedBlock],
        ),
        returnsNormally,
      );

      // Rollup counter with allowDirectLogging: true must fail closed
      expect(
        () => ProjectValidationService.validateBlock(
          validRollup.copyWith(
            id: 'blk-bad-rollup',
            config: const {
              'rollupSourceBlockId': 'blk-cities',
              'allowDirectLogging': true,
            },
          ),
          expectedProjectId: 'proj-1',
          projectBlocks: [groupedBlock],
        ),
        throwsA(isA<ProjectValidationException>()),
      );

      // Chained rollup counter referencing another rollup counter must fail
      expect(
        () => ProjectValidationService.validateBlock(
          ProjectTrackingBlockEntity(
            id: 'blk-chained',
            projectId: 'proj-1',
            blockType: ProjectBlockType.counter,
            title: 'Chained Rollup',
            config: const {
              'rollupSourceBlockId': 'blk-rollup',
              'allowDirectLogging': false,
            },
          ),
          expectedProjectId: 'proj-1',
          projectBlocks: [groupedBlock, validRollup],
        ),
        throwsA(isA<ProjectValidationException>()),
      );

      // Enforce maxBlocksPerProject (32)
      final fullBlocks = List<ProjectTrackingBlockEntity>.generate(
        SharedProjectRules.maxBlocksPerProject,
        (i) => ProjectTrackingBlockEntity(
          id: 'blk-$i',
          projectId: 'proj-1',
          blockType: ProjectBlockType.checklist,
          title: 'Block $i',
        ),
      );
      expect(
        () => ProjectValidationService.validateBlock(
          ProjectTrackingBlockEntity(
            id: 'blk-overflow',
            projectId: 'proj-1',
            blockType: ProjectBlockType.checklist,
            title: 'Overflow',
          ),
          expectedProjectId: 'proj-1',
          projectBlocks: fullBlocks,
        ),
        throwsA(isA<ProjectValidationException>()),
      );
    });

    test(
      'enforces record ownership, hierarchy cycles, checklist rules, and append-only logs',
      () {
        final groupedBlock = ProjectTrackingBlockEntity(
          id: 'blk-grouped',
          projectId: 'proj-1',
          blockType: ProjectBlockType.groupedList,
          title: 'Regions & Cities',
        );
        final checklistBlock = ProjectTrackingBlockEntity(
          id: 'blk-check',
          projectId: 'proj-1',
          blockType: ProjectBlockType.checklist,
          title: 'Prep Steps',
        );
        final rollupCounter = ProjectTrackingBlockEntity(
          id: 'blk-counter',
          projectId: 'proj-1',
          blockType: ProjectBlockType.counter,
          title: 'Total Counter',
          config: const {
            'rollupSourceBlockId': 'blk-grouped',
            'allowDirectLogging': false,
          },
        );

        final group = ProjectTrackingRecordEntity(
          id: 'grp-1',
          projectId: 'proj-1',
          blockId: 'blk-grouped',
          recordType: ProjectRecordType.group,
          title: 'Northeast',
        );
        final city = ProjectTrackingRecordEntity(
          id: 'city-nyc',
          projectId: 'proj-1',
          blockId: 'blk-grouped',
          parentRecordId: 'grp-1',
          recordType: ProjectRecordType.groupedItem,
          title: 'New York',
          targetValue: 20,
        );
        final log1 = ProjectTrackingRecordEntity(
          id: 'log-1',
          projectId: 'proj-1',
          blockId: 'blk-grouped',
          parentRecordId: 'city-nyc',
          recordType: ProjectRecordType.progressLog,
          deltaValue: 12,
          recordedDate: CalendarDate(year: 2026, month: 11, day: 18),
        );

        // Checklist block rejects progress logs
        expect(
          () => ProjectValidationService.validateRecord(
            ProjectTrackingRecordEntity(
              id: 'log-check',
              projectId: 'proj-1',
              blockId: 'blk-check',
              recordType: ProjectRecordType.progressLog,
              deltaValue: 1,
              recordedDate: CalendarDate(year: 2026, month: 11, day: 18),
            ),
            block: checklistBlock,
          ),
          throwsA(isA<ProjectValidationException>()),
        );

        // Direct logging on rollup counter rejects
        expect(
          () => ProjectValidationService.validateRecord(
            ProjectTrackingRecordEntity(
              id: 'log-rollup',
              projectId: 'proj-1',
              blockId: 'blk-counter',
              recordType: ProjectRecordType.progressLog,
              deltaValue: 10,
              recordedDate: CalendarDate(year: 2026, month: 11, day: 18),
            ),
            block: rollupCounter,
          ),
          throwsA(isA<ProjectValidationException>()),
        );

        // Non-correction negative delta rejected
        expect(
          () => ProjectValidationService.validateRecord(
            ProjectTrackingRecordEntity(
              id: 'log-neg',
              projectId: 'proj-1',
              blockId: 'blk-grouped',
              parentRecordId: 'city-nyc',
              recordType: ProjectRecordType.progressLog,
              deltaValue: -4,
              recordedDate: CalendarDate(year: 2026, month: 11, day: 18),
            ),
            block: groupedBlock,
            existingBlockRecords: [group, city],
          ),
          throwsA(isA<ProjectValidationException>()),
        );

        // Valid compensating correction passes
        final correction = ProjectTrackingRecordEntity(
          id: 'corr-1',
          projectId: 'proj-1',
          blockId: 'blk-grouped',
          parentRecordId: 'city-nyc',
          recordType: ProjectRecordType.progressLog,
          deltaValue: -2,
          recordedDate: CalendarDate(year: 2026, month: 11, day: 18),
          metadata: const {
            'isCorrection': true,
            'compensatesRecordId': 'log-1',
            'correctionReason': 'Removed 2 bounced addresses',
          },
        );
        expect(
          () => ProjectValidationService.validateRecord(
            correction,
            block: groupedBlock,
            existingBlockRecords: [group, city, log1],
          ),
          returnsNormally,
        );

        // Cyclic parentRecordId on update fails
        final cyclicA = ProjectTrackingRecordEntity(
          id: 'grp-a',
          projectId: 'proj-1',
          blockId: 'blk-grouped',
          parentRecordId: 'grp-b',
          recordType: ProjectRecordType.group,
          title: 'A',
        );
        final cyclicB = ProjectTrackingRecordEntity(
          id: 'grp-b',
          projectId: 'proj-1',
          blockId: 'blk-grouped',
          parentRecordId: 'grp-a',
          recordType: ProjectRecordType.group,
          title: 'B',
        );
        expect(
          () => ProjectValidationService.validateRecord(
            cyclicA,
            block: groupedBlock,
            existingBlockRecords: [cyclicA, cyclicB],
            isNew: false,
          ),
          throwsA(isA<ProjectValidationException>()),
        );

        // Append-only protection rejects update and delete of progress_log
        expect(
          () => ProjectValidationService.assertAppendOnlyLogProtection(
            existing: log1,
            isDelete: false,
          ),
          throwsA(isA<ProjectValidationException>()),
        );

        // Tracking record title enforces canonical 300-character limit
        expect(
          SharedProjectRules.maxTrackingRecordTitleLength,
          300,
        );
        expect(
          () => ProjectValidationService.validateRecord(
            ProjectTrackingRecordEntity(
              id: 'item-300',
              projectId: 'proj-1',
              blockId: 'blk-check',
              recordType: ProjectRecordType.checklistItem,
              title: List<String>.filled(300, 'a').join(),
            ),
            block: checklistBlock,
          ),
          returnsNormally,
        );
        expect(
          () => ProjectValidationService.validateRecord(
            ProjectTrackingRecordEntity(
              id: 'item-301',
              projectId: 'proj-1',
              blockId: 'blk-check',
              recordType: ProjectRecordType.checklistItem,
              title: List<String>.filled(301, 'a').join(),
            ),
            block: checklistBlock,
          ),
          throwsA(isA<ProjectValidationException>()),
        );
        expect(
          () => ProjectValidationService.assertAppendOnlyLogProtection(
            existing: log1,
            isDelete: true,
          ),
          throwsA(isA<ProjectValidationException>()),
        );
      },
    );
  });

  group('Projects Stage 1 — ProgressEngine Independent Metrics', () {
    test(
      'keeps metrics independent without primaryBlockId and respects explicit primary',
      () {
        final project = ProjectEntity(
          id: 'proj-video',
          title: 'Video Learning Plan',
          startDate: CalendarDate(year: 2026, month: 11, day: 1),
          targetDate: CalendarDate(year: 2026, month: 11, day: 20),
        );
        final scheduleBlock = ProjectTrackingBlockEntity(
          id: 'blk-videos',
          projectId: project.id,
          blockType: ProjectBlockType.schedule,
          title: 'Video Lessons',
          unitLabel: 'minutes',
          sortOrder: 0,
        );
        final checklistBlock = ProjectTrackingBlockEntity(
          id: 'blk-labs',
          projectId: project.id,
          blockType: ProjectBlockType.checklist,
          title: 'Practice Labs',
          sortOrder: 1,
        );

        final v1 = ProjectTrackingRecordEntity(
          id: 'vid-1',
          projectId: project.id,
          blockId: scheduleBlock.id,
          recordType: ProjectRecordType.scheduleItem,
          title: 'Lesson 1',
          durationMinutes: 60,
          isCompleted: false,
          scheduledDate: CalendarDate(year: 2026, month: 11, day: 10),
        );
        final v1WatchLog = ProjectTrackingRecordEntity(
          id: 'log-vid-1',
          projectId: project.id,
          blockId: scheduleBlock.id,
          parentRecordId: v1.id,
          recordType: ProjectRecordType.progressLog,
          deltaValue: 20,
          recordedDate: CalendarDate(year: 2026, month: 11, day: 18),
        );
        final lab1 = ProjectTrackingRecordEntity(
          id: 'lab-1',
          projectId: project.id,
          blockId: checklistBlock.id,
          recordType: ProjectRecordType.checklistItem,
          title: 'Lab 1',
          isCompleted: true,
        );
        final lab2 = ProjectTrackingRecordEntity(
          id: 'lab-2',
          projectId: project.id,
          blockId: checklistBlock.id,
          recordType: ProjectRecordType.checklistItem,
          title: 'Lab 2',
          isCompleted: false,
        );

        final tasks = [
          TaskEntity(
            id: 't-active',
            title: 'Active task',
            status: 'completed',
            projectId: project.id,
          ),
          TaskEntity(
            id: 't-cancelled',
            title: 'Cancelled task',
            status: 'cancelled',
            projectId: project.id,
          ),
        ];
        final milestones = [
          MilestoneEntity(
            id: 'm-1',
            projectId: project.id,
            title: 'Halfway',
            isCompleted: true,
          ),
        ];

        // Without primaryBlockId: no synthetic overallPercentage
        final summaryNoPrimary = ProgressEngine.calculateProjectProgressSummary(
          project: project,
          blocks: [scheduleBlock, checklistBlock],
          records: [v1, v1WatchLog, lab1, lab2],
          linkedTasks: tasks,
          milestones: milestones,
          asOfDate: CalendarDate(year: 2026, month: 11, day: 18),
        );
        expect(summaryNoPrimary.overallPercentage, isNull);
        expect(summaryNoPrimary.hasInvalidPrimaryBlockReference, isFalse);
        expect(summaryNoPrimary.linkedTasksTotal, 1);
        expect(summaryNoPrimary.linkedTasksCompleted, 1);
        expect(summaryNoPrimary.milestonesTotal, 1);
        expect(summaryNoPrimary.milestonesCompleted, 1);
        expect(summaryNoPrimary.blockMetrics[0].plannedDurationMinutes, 60);
        expect(
          summaryNoPrimary.blockMetrics[0].actualLoggedDurationMinutes,
          20,
        );
        expect(summaryNoPrimary.blockMetrics[0].completedCount, 0);
        expect(summaryNoPrimary.blockMetrics[0].daysRemaining, 3);
        expect(summaryNoPrimary.blockMetrics[1].progressPercent, 50.0);

        // Explicit valid primaryBlockId picks that block cleanly
        final summaryWithPrimary =
            ProgressEngine.calculateProjectProgressSummary(
          project: project.copyWith(
            customFields: {'primaryBlockId': checklistBlock.id},
          ),
          blocks: [scheduleBlock, checklistBlock],
          records: [v1, v1WatchLog, lab1, lab2],
          linkedTasks: tasks,
          milestones: milestones,
          asOfDate: CalendarDate(year: 2026, month: 11, day: 18),
        );
        expect(summaryWithPrimary.primaryBlockId, checklistBlock.id);
        expect(summaryWithPrimary.overallPercentage, 50.0);
        expect(summaryWithPrimary.hasInvalidPrimaryBlockReference, isFalse);

        // Archived primary block flags invalid reference safely
        final summaryArchivedPrimary =
            ProgressEngine.calculateProjectProgressSummary(
          project: project.copyWith(
            customFields: {'primaryBlockId': checklistBlock.id},
          ),
          blocks: [
            scheduleBlock,
            checklistBlock.copyWith(isArchived: true),
          ],
          records: [v1, v1WatchLog, lab1, lab2],
          asOfDate: CalendarDate(year: 2026, month: 11, day: 18),
        );
        expect(summaryArchivedPrimary.overallPercentage, isNull);
        expect(summaryArchivedPrimary.hasInvalidPrimaryBlockReference, isTrue);

        // Schedule duration completion rule helper
        expect(
          ProgressEngine.meetsScheduleDurationRule(
            plannedDurationMinutes: 60,
            actualLoggedMinutes: 60,
            config: const ScheduleBlockConfig(
              completionRule: ScheduleItemCompletionRule.manual,
            ),
          ),
          isFalse,
        );
        expect(
          ProgressEngine.meetsScheduleDurationRule(
            plannedDurationMinutes: 60,
            actualLoggedMinutes: 48,
            config: const ScheduleBlockConfig(
              completionRule: ScheduleItemCompletionRule.thresholdPercent,
              autoCompleteThresholdRatio: 0.8,
            ),
          ),
          isTrue,
        );
        expect(
          ProgressEngine.meetsScheduleDurationRule(
            plannedDurationMinutes: 60,
            actualLoggedMinutes: 59,
            config: const ScheduleBlockConfig(
              completionRule: ScheduleItemCompletionRule.exactDuration,
            ),
          ),
          isFalse,
        );
      },
    );
  });

  group(
    'Projects Stage 1 — DriftProjectsRepository & ProjectsController SQLite Persistence',
    () {
      late Directory tempDir;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('daywell_proj_stage1_');
      });

      tearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      test(
        'persists BIM outreach representative fixture across SQLite close & reopen',
        () async {
          final dbFile = File(p.join(tempDir.path, 'bim_outreach.sqlite'));
          final db1 = AppDatabase(NativeDatabase(dbFile));
          await db1.ensureInitialized();

          await db1.into(db1.goals).insert(
                GoalsCompanion.insert(
                  id: 'goal-biz',
                  title: 'Grow BIM Pipeline',
                  createdAt: DateTime.utc(2026, 11, 1),
                ),
              );

          final repo1 = DriftProjectsRepository(db1);
          final controller1 = ProjectsController(repository: repo1);

          final created = await controller1.createProject(
            id: 'proj-bim',
            title: 'BIM Company Outreach',
            status: 'active',
            goalId: 'goal-biz',
            startDate: CalendarDate(year: 2026, month: 11, day: 1),
            targetDate: CalendarDate(year: 2026, month: 11, day: 30),
            customFields: const {
              'primaryBlockId': 'blk-bim-counter',
              'definitions': [
                {
                  'id': 'campaign_owner',
                  'label': 'Owner',
                  'type': 'text',
                  'required': true,
                },
              ],
              'values': {
                'campaign_owner': 'Outreach Lead',
              },
            },
          );
          expect(created, isNotNull);

          final listBlock = await controller1.createBlock(
            id: 'blk-bim-cities',
            projectId: 'proj-bim',
            blockType: ProjectBlockType.groupedList,
            title: 'US Regions & Cities',
            unitLabel: 'emails',
            sortOrder: 0,
          );
          expect(listBlock, isNotNull);

          final rollupCounter = await controller1.createBlock(
            id: 'blk-bim-counter',
            projectId: 'proj-bim',
            blockType: ProjectBlockType.counter,
            title: 'Campaign Emails Sent',
            unitLabel: 'emails',
            targetValue: 1000,
            dailyTargetValue: 40,
            sortOrder: 1,
            config: const {
              'rollupSourceBlockId': 'blk-bim-cities',
              'allowDirectLogging': false,
            },
          );
          expect(rollupCounter, isNotNull);

          // Sample fixture: 2 regions, 3 cities (not full 100-city dataset)
          await controller1.createRecord(
            id: 'grp-ne',
            projectId: 'proj-bim',
            blockId: 'blk-bim-cities',
            recordType: ProjectRecordType.group,
            title: 'Northeast',
            sortOrder: 0,
          );
          await controller1.createRecord(
            id: 'grp-west',
            projectId: 'proj-bim',
            blockId: 'blk-bim-cities',
            recordType: ProjectRecordType.group,
            title: 'West',
            sortOrder: 1,
          );
          await controller1.createRecord(
            id: 'city-nyc',
            projectId: 'proj-bim',
            blockId: 'blk-bim-cities',
            parentRecordId: 'grp-ne',
            recordType: ProjectRecordType.groupedItem,
            title: 'New York',
            targetValue: 20,
            sortOrder: 0,
          );
          await controller1.createRecord(
            id: 'city-bos',
            projectId: 'proj-bim',
            blockId: 'blk-bim-cities',
            parentRecordId: 'grp-ne',
            recordType: ProjectRecordType.groupedItem,
            title: 'Boston',
            targetValue: 10,
            sortOrder: 1,
          );
          await controller1.createRecord(
            id: 'city-la',
            projectId: 'proj-bim',
            blockId: 'blk-bim-cities',
            parentRecordId: 'grp-west',
            recordType: ProjectRecordType.groupedItem,
            title: 'Los Angeles',
            targetValue: 15,
            sortOrder: 0,
          );

          final day1 = CalendarDate(year: 2026, month: 11, day: 18);
          final day2 = CalendarDate(year: 2026, month: 11, day: 19);
          await controller1.appendProgressLog(
            id: 'log-nyc-1',
            projectId: 'proj-bim',
            blockId: 'blk-bim-cities',
            parentRecordId: 'city-nyc',
            deltaValue: 12,
            recordedDate: day1,
          );
          await controller1.appendProgressLog(
            id: 'log-nyc-2',
            projectId: 'proj-bim',
            blockId: 'blk-bim-cities',
            parentRecordId: 'city-nyc',
            deltaValue: 10,
            recordedDate: day2,
          );
          await controller1.appendProgressLog(
            id: 'log-la-1',
            projectId: 'proj-bim',
            blockId: 'blk-bim-cities',
            parentRecordId: 'city-la',
            deltaValue: 8,
            recordedDate: day1,
          );

          // Compensating correction on NYC batch 2 (-2)
          final corr = await controller1.appendProgressCorrection(
            targetLogId: 'log-nyc-2',
            correctionDelta: -2,
            recordedDate: day2,
            reason: '2 bounced addresses',
            correctionId: 'corr-nyc-2',
          );
          expect(corr, isNotNull);

          // Archive lifecycle stays independent from status == 'active'
          await controller1.setProjectArchived('proj-bim', true);
          expect(
            controller1.state.findProjectById('proj-bim')?.status,
            'active',
          );
          expect(
            controller1.state.findProjectById('proj-bim')?.isArchived,
            isTrue,
          );
          await controller1.setProjectArchived('proj-bim', false);

          controller1.dispose();
          await db1.close();

          // Reopen from disk and hydrate fresh controller
          final db2 = AppDatabase(NativeDatabase(dbFile));
          await db2.ensureInitialized();
          final repo2 = DriftProjectsRepository(db2);
          final controller2 = ProjectsController(repository: repo2);
          await controller2.loadAll(asOfDate: day1);

          final reopenedSummary =
              controller2.state.summaryForProject('proj-bim');
          expect(reopenedSummary, isNotNull);
          // 12 + 10 - 2 + 8 = 28 total emails across cities
          expect(reopenedSummary!.primaryBlockId, 'blk-bim-counter');
          expect(reopenedSummary.primaryMetric!.loggedTotal, 28);
          expect(reopenedSummary.primaryMetric!.targetValue, 1000);
          expect(reopenedSummary.primaryMetric!.todayTotal, 20); // day1: 12 + 8
          expect(
            reopenedSummary.primaryMetric!.dailyTotalsByDate['2026-11-19'],
            8,
          );
          expect(reopenedSummary.primaryMetric!.groupMetrics.length, 2);
          expect(
            reopenedSummary.primaryMetric!.groupMetrics[0].loggedTotal,
            20,
          );
          expect(
            reopenedSummary.primaryMetric!.groupMetrics[0].completedItemCount,
            1, // New York reached 20/20
          );
          expect(
            reopenedSummary.primaryMetric!.groupMetrics[1].loggedTotal,
            8,
          );

          controller2.dispose();
          await db2.close();
        },
      );

      test(
        'enforces video learning fixture, append-only errors, FK validation, and task-preserving deletion',
        () async {
          final dbFile = File(p.join(tempDir.path, 'video_plan.sqlite'));
          final db = AppDatabase(NativeDatabase(dbFile));
          await db.ensureInitialized();
          final repo = DriftProjectsRepository(db);
          final controller = ProjectsController(repository: repo);

          // Missing goalId fails closed
          final missingGoalProject = await controller.createProject(
            id: 'proj-bad-goal',
            title: 'Invalid Goal Link',
            goalId: 'goal-does-not-exist',
          );
          expect(missingGoalProject, isNull);
          expect(controller.state.errorMessage, isNotNull);

          // Create valid video learning project + linked Task + Milestone
          final project = await controller.createProject(
            id: 'proj-video',
            title: 'Flutter Architecture Series',
            targetDate: CalendarDate(year: 2026, month: 11, day: 25),
          );
          expect(project, isNotNull);

          await db.into(db.tasks).insert(
                TasksCompanion.insert(
                  id: 'task-notes',
                  title: 'Summarize Video 1 notes',
                  status: const Value('in_progress'),
                  projectId: const Value('proj-video'),
                  createdAt: DateTime.utc(2026, 11, 10),
                  updatedAt: DateTime.utc(2026, 11, 10),
                ),
              );
          await db.into(db.milestones).insert(
                MilestonesCompanion.insert(
                  id: 'ms-module-1',
                  projectId: 'proj-video',
                  title: 'Core Foundations Done',
                  isCompleted: const Value(true),
                  createdAt: DateTime.utc(2026, 11, 10),
                ),
              );

          await controller.createBlock(
            id: 'blk-schedule',
            projectId: 'proj-video',
            blockType: ProjectBlockType.schedule,
            title: 'Video Curriculum',
            unitLabel: 'minutes',
          );

          final vid1 = await controller.createRecord(
            id: 'vid-1',
            projectId: 'proj-video',
            blockId: 'blk-schedule',
            recordType: ProjectRecordType.scheduleItem,
            title: '01 · Domain Modeling',
            durationMinutes: 60,
            scheduledDate: CalendarDate(year: 2026, month: 11, day: 18),
            linkedTaskId: 'task-notes',
          );
          expect(vid1, isNotNull);

          final watchLog = await controller.appendProgressLog(
            id: 'log-watch-1',
            projectId: 'proj-video',
            blockId: 'blk-schedule',
            parentRecordId: 'vid-1',
            deltaValue: 20,
            recordedDate: CalendarDate(year: 2026, month: 11, day: 18),
          );
          expect(watchLog, isNotNull);

          // Missing linkedTaskId fails closed
          final badTaskLink = await controller.createRecord(
            id: 'vid-bad-task',
            projectId: 'proj-video',
            blockId: 'blk-schedule',
            recordType: ProjectRecordType.scheduleItem,
            title: 'Bad link',
            linkedTaskId: 'task-missing',
          );
          expect(badTaskLink, isNull);
          expect(controller.state.errorMessage, isNotNull);

          // Direct update/delete of append-only log fails closed
          final mutated = await controller.updateRecord(
            watchLog!.copyWith(deltaValue: 99),
          );
          expect(mutated, isNull);
          expect(controller.state.errorMessage, contains('append-only'));

          final deletedLog =
              await controller.deleteRecord('proj-video', 'log-watch-1');
          expect(deletedLog, isFalse);
          expect(controller.state.errorMessage, contains('append-only'));

          final summary = await controller.loadProjectSummary(
            'proj-video',
            asOfDate: CalendarDate(year: 2026, month: 11, day: 18),
          );
          expect(summary, isNotNull);
          expect(summary!.blockMetrics.single.plannedDurationMinutes, 60);
          expect(summary.blockMetrics.single.actualLoggedDurationMinutes, 20);
          expect(summary.blockMetrics.single.completedCount, 0);
          expect(summary.linkedTasksTotal, 1);
          expect(summary.milestonesCompleted, 1);

          // Deleting project detaches linked Task rather than deleting it,
          // while cascading blocks, records, and milestones cleanly.
          final deletedProject = await controller.deleteProject('proj-video');
          expect(deletedProject, isTrue);

          final survivingTask = await (db.select(db.tasks)
                ..where((tbl) => tbl.id.equals('task-notes')))
              .getSingleOrNull();
          expect(survivingTask, isNotNull);
          expect(survivingTask!.projectId, isNull);

          final remainingBlocks =
              await repo.getBlocksForProject('proj-video');
          final remainingRecords =
              await repo.getRecordsForProject('proj-video');
          expect(remainingBlocks, isEmpty);
          expect(remainingRecords, isEmpty);

          controller.dispose();
          await db.close();
        },
      );
    },
  );
}
