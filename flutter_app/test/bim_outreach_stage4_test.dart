import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/repositories/projects_repository.dart';
import 'package:personal_management_app/domain/projects/bim_outreach_template.dart';
import 'package:personal_management_app/domain/projects/progress_engine.dart';
import 'package:personal_management_app/domain/projects/project_package_codec.dart';

import 'support/sqlite_test_helper.dart';

void main() {
  setUpAll(configureSqliteForHostTests);

  String readBimFixtureJson() {
    final candidates = [
      p.join(
        Directory.current.path,
        '..',
        'shared_foundation',
        'fixtures',
        'bim_outreach_campaign_v1.daywellproject',
      ),
      p.join(
        Directory.current.path,
        'shared_foundation',
        'fixtures',
        'bim_outreach_campaign_v1.daywellproject',
      ),
    ];
    for (final candidate in candidates) {
      final file = File(candidate);
      if (file.existsSync()) {
        return file.readAsStringSync();
      }
    }
    throw StateError(
      'Unable to locate shared_foundation/fixtures/bim_outreach_campaign_v1.daywellproject from ${Directory.current.path}',
    );
  }

  group('Projects Stage 4 — BIM Company Outreach Campaign Template', () {
    test(
      'defines 100 unique US cities summing to 1,000 across 4 regions and Hidar 9–30, 2019 E.C.',
      () {
        expect(BimOutreachTemplate.cities.length, 100);
        final uniqueTitles =
            BimOutreachTemplate.cities.map((c) => c.displayTitle).toSet();
        expect(uniqueTitles.length, 100);
        expect(uniqueTitles.contains('Portland, OR'), isTrue);
        expect(uniqueTitles.contains('Portland, ME'), isTrue);

        final total = BimOutreachTemplate.cities.fold<int>(
          0,
          (sum, c) => sum + c.target,
        );
        expect(total, 1000);

        final regionCounts = <String, int>{};
        final regionSums = <String, int>{};
        for (final c in BimOutreachTemplate.cities) {
          regionCounts[c.region] = (regionCounts[c.region] ?? 0) + 1;
          regionSums[c.region] = (regionSums[c.region] ?? 0) + c.target;
        }
        expect(regionCounts, {
          'Northeast': 16,
          'Midwest': 19,
          'South': 42,
          'West': 23,
        });
        expect(regionSums, {
          'Northeast': 152,
          'Midwest': 179,
          'South': 411,
          'West': 258,
        });

        final dates = BimOutreachTemplate.campaignDates();
        expect(dates.startDate.toIsoString(), '2026-11-18');
        expect(dates.targetDate.toIsoString(), '2026-12-09');
        expect(dates.durationDays, 22);
        final ethStart = dates.startDate.toEthiopian();
        final ethEnd = dates.targetDate.toEthiopian();
        expect(ethStart.year, 2019);
        expect(ethStart.month, 3);
        expect(ethStart.day, 9);
        expect(ethEnd.year, 2019);
        expect(ethEnd.month, 3);
        expect(ethEnd.day, 30);
      },
    );

    test(
      'imports shared .daywellproject fixture into Drift, caps city over-targets while preserving actual sent counts, and round-trips export',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final repo = ProjectsRepository(db);

        final fixtureJson = readBimFixtureJson();
        final parsed = ProjectPackageCodec.parseAndValidate(fixtureJson);
        expect(parsed.project.title, BimOutreachTemplate.projectTitle);
        expect(parsed.trackingBlocks.length, 1);
        expect(parsed.trackingRecords.length, 104);

        final imported = await repo.importProjectPackage(fixtureJson);
        expect(imported.project.title, BimOutreachTemplate.projectTitle);
        expect(imported.project.startDate?.toIsoString(), '2026-11-18');
        expect(imported.project.targetDate?.toIsoString(), '2026-12-09');

        final span = ProgressEngine.computeScheduleSpan(
          startDate: imported.project.startDate,
          targetDate: imported.project.targetDate,
          asOfDate: CalendarDate.parse('2026-11-18'),
        );
        expect(span.totalDays, 22);
        expect(span.remainingDays, 22);
        expect(span.elapsedDays, 1);

        final block = imported.trackingBlocks.first;
        final nyc = imported.trackingRecords.firstWhere(
          (r) => r.title == 'New York, NY',
        );
        final boston = imported.trackingRecords.firstWhere(
          (r) => r.title == 'Boston, MA',
        );

        final batch1 = await repo.appendProgressLog(
          projectId: imported.project.id,
          blockId: block.id,
          parentRecordId: nyc.id,
          deltaValue: 20,
          recordedDate: CalendarDate.parse('2026-11-18'),
        );
        await repo.appendProgressLog(
          projectId: imported.project.id,
          blockId: block.id,
          parentRecordId: nyc.id,
          deltaValue: 15,
          recordedDate: CalendarDate.parse('2026-11-18'),
        );
        await repo.appendProgressLog(
          projectId: imported.project.id,
          blockId: block.id,
          parentRecordId: boston.id,
          deltaValue: 12,
          recordedDate: CalendarDate.parse('2026-11-19'),
        );

        final summary = await repo.getProjectProgressSummary(
          imported.project.id,
          asOfDate: CalendarDate.parse('2026-11-19'),
        );
        final pm = summary!.primaryMetric!;
        expect(pm.loggedTotal, 47);
        expect(pm.targetCompletedTotal, 42);
        expect(pm.overTargetAmount, 5);
        expect(pm.overTargetItemCount, 1);
        expect(pm.todayTotal, 12);
        expect(pm.completedCount, 1);
        expect(summary.overallPercentage, closeTo(4.2, 1e-6));

        final northeast = pm.groupMetrics.firstWhere(
          (g) => g.title == 'Northeast',
        );
        expect(northeast.loggedTotal, 47);
        expect(northeast.targetCompletedTotal, 42);
        expect(northeast.overTargetAmount, 5);
        expect(northeast.overTargetItemCount, 1);

        await repo.appendProgressCorrection(
          targetLogId: batch1.id,
          correctionDelta: -8,
          recordedDate: CalendarDate.parse('2026-11-19'),
          reason: 'Bounced test batch adjustment',
        );

        final corrected = await repo.getProjectProgressSummary(
          imported.project.id,
          asOfDate: CalendarDate.parse('2026-11-19'),
        );
        expect(corrected!.primaryMetric!.loggedTotal, 39);
        expect(corrected.primaryMetric!.targetCompletedTotal, 39);
        expect(corrected.primaryMetric!.overTargetAmount, 0);
        expect(corrected.overallPercentage, closeTo(3.9, 1e-6));

        final exportedJson = await repo.exportProjectPackageJson(
          imported.project.id,
        );
        final reimported = await repo.importProjectPackage(exportedJson);
        final reimportedSummary = await repo.getProjectProgressSummary(
          reimported.project.id,
          asOfDate: CalendarDate.parse('2026-11-19'),
        );
        expect(reimportedSummary!.primaryMetric!.loggedTotal, 39);
        expect(reimportedSummary.primaryMetric!.targetCompletedTotal, 39);
      },
    );
  });
}
