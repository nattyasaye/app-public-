import 'dart:convert';

import '../../core/date/shared_date.dart';
import '../../core/shared_foundation_core.dart';
import 'project_models.dart';
import 'project_package_codec.dart';

class BimOutreachCityTarget {
  final String city;
  final String state;
  final int target;
  final String region;

  const BimOutreachCityTarget({
    required this.city,
    required this.state,
    required this.target,
    required this.region,
  });

  String get displayTitle => '$city, $state';
}

class BimOutreachTemplate {
  BimOutreachTemplate._();

  static const String projectId = 'fx-proj-bim-outreach-2019';
  static const String blockId = 'fx-blk-bim-outreach-cities';
  static const String projectTitle = 'BIM Company Outreach — 1,000 Companies';
  static const String packageFilename =
      'bim-company-outreach-1000-companies.daywellproject';
  static const int totalTargetEmails = 1000;
  static const int dailyTargetEmails = 46;

  static const List<String> regionOrder = <String>[
    'Northeast',
    'Midwest',
    'South',
    'West',
  ];

  static final DateTime _templateTimestamp =
      DateTime.utc(2026, 11, 17, 8, 0, 0);

  static const List<BimOutreachCityTarget> cities = <BimOutreachCityTarget>[
    BimOutreachCityTarget(city: 'New York', state: 'NY', target: 30, region: 'Northeast'),
    BimOutreachCityTarget(city: 'Los Angeles', state: 'CA', target: 30, region: 'West'),
    BimOutreachCityTarget(city: 'Chicago', state: 'IL', target: 30, region: 'Midwest'),
    BimOutreachCityTarget(city: 'Houston', state: 'TX', target: 30, region: 'South'),
    BimOutreachCityTarget(city: 'Dallas', state: 'TX', target: 25, region: 'South'),
    BimOutreachCityTarget(city: 'Washington', state: 'DC', target: 25, region: 'South'),
    BimOutreachCityTarget(city: 'Atlanta', state: 'GA', target: 25, region: 'South'),
    BimOutreachCityTarget(city: 'Boston', state: 'MA', target: 20, region: 'Northeast'),
    BimOutreachCityTarget(city: 'Seattle', state: 'WA', target: 20, region: 'West'),
    BimOutreachCityTarget(city: 'San Francisco', state: 'CA', target: 20, region: 'West'),
    BimOutreachCityTarget(city: 'Phoenix', state: 'AZ', target: 20, region: 'West'),
    BimOutreachCityTarget(city: 'Miami', state: 'FL', target: 20, region: 'South'),
    BimOutreachCityTarget(city: 'Denver', state: 'CO', target: 20, region: 'West'),
    BimOutreachCityTarget(city: 'Philadelphia', state: 'PA', target: 15, region: 'Northeast'),
    BimOutreachCityTarget(city: 'Austin', state: 'TX', target: 15, region: 'South'),
    BimOutreachCityTarget(city: 'Minneapolis', state: 'MN', target: 15, region: 'Midwest'),
    BimOutreachCityTarget(city: 'San Diego', state: 'CA', target: 15, region: 'West'),
    BimOutreachCityTarget(city: 'Tampa', state: 'FL', target: 15, region: 'South'),
    BimOutreachCityTarget(city: 'Orlando', state: 'FL', target: 15, region: 'South'),
    BimOutreachCityTarget(city: 'Charlotte', state: 'NC', target: 15, region: 'South'),
    BimOutreachCityTarget(city: 'Portland', state: 'OR', target: 15, region: 'West'),
    BimOutreachCityTarget(city: 'Baltimore', state: 'MD', target: 12, region: 'South'),
    BimOutreachCityTarget(city: 'Nashville', state: 'TN', target: 12, region: 'South'),
    BimOutreachCityTarget(city: 'Raleigh', state: 'NC', target: 12, region: 'South'),
    BimOutreachCityTarget(city: 'Detroit', state: 'MI', target: 12, region: 'Midwest'),
    BimOutreachCityTarget(city: 'Pittsburgh', state: 'PA', target: 12, region: 'Northeast'),
    BimOutreachCityTarget(city: 'St. Louis', state: 'MO', target: 12, region: 'Midwest'),
    BimOutreachCityTarget(city: 'Kansas City', state: 'MO', target: 12, region: 'Midwest'),
    BimOutreachCityTarget(city: 'Salt Lake City', state: 'UT', target: 12, region: 'West'),
    BimOutreachCityTarget(city: 'San Jose', state: 'CA', target: 10, region: 'West'),
    BimOutreachCityTarget(city: 'Newark', state: 'NJ', target: 10, region: 'Northeast'),
    BimOutreachCityTarget(city: 'Irvine', state: 'CA', target: 10, region: 'West'),
    BimOutreachCityTarget(city: 'Sacramento', state: 'CA', target: 10, region: 'West'),
    BimOutreachCityTarget(city: 'Las Vegas', state: 'NV', target: 10, region: 'West'),
    BimOutreachCityTarget(city: 'San Antonio', state: 'TX', target: 10, region: 'South'),
    BimOutreachCityTarget(city: 'Columbus', state: 'OH', target: 10, region: 'Midwest'),
    BimOutreachCityTarget(city: 'Indianapolis', state: 'IN', target: 10, region: 'Midwest'),
    BimOutreachCityTarget(city: 'Cincinnati', state: 'OH', target: 10, region: 'Midwest'),
    BimOutreachCityTarget(city: 'Cleveland', state: 'OH', target: 10, region: 'Midwest'),
    BimOutreachCityTarget(city: 'Milwaukee', state: 'WI', target: 8, region: 'Midwest'),
    BimOutreachCityTarget(city: 'Jacksonville', state: 'FL', target: 8, region: 'South'),
    BimOutreachCityTarget(city: 'Richmond', state: 'VA', target: 8, region: 'South'),
    BimOutreachCityTarget(city: 'Virginia Beach', state: 'VA', target: 8, region: 'South'),
    BimOutreachCityTarget(city: 'Fort Worth', state: 'TX', target: 8, region: 'South'),
    BimOutreachCityTarget(city: 'Oklahoma City', state: 'OK', target: 8, region: 'South'),
    BimOutreachCityTarget(city: 'New Orleans', state: 'LA', target: 8, region: 'South'),
    BimOutreachCityTarget(city: 'Louisville', state: 'KY', target: 8, region: 'South'),
    BimOutreachCityTarget(city: 'Hartford', state: 'CT', target: 8, region: 'Northeast'),
    BimOutreachCityTarget(city: 'Oakland', state: 'CA', target: 8, region: 'West'),
    BimOutreachCityTarget(city: 'Tulsa', state: 'OK', target: 7, region: 'South'),
    BimOutreachCityTarget(city: 'Memphis', state: 'TN', target: 7, region: 'South'),
    BimOutreachCityTarget(city: 'Birmingham', state: 'AL', target: 7, region: 'South'),
    BimOutreachCityTarget(city: 'Providence', state: 'RI', target: 7, region: 'Northeast'),
    BimOutreachCityTarget(city: 'Albuquerque', state: 'NM', target: 7, region: 'West'),
    BimOutreachCityTarget(city: 'Tucson', state: 'AZ', target: 7, region: 'West'),
    BimOutreachCityTarget(city: 'Boise', state: 'ID', target: 7, region: 'West'),
    BimOutreachCityTarget(city: 'Omaha', state: 'NE', target: 7, region: 'Midwest'),
    BimOutreachCityTarget(city: 'Fort Lauderdale', state: 'FL', target: 7, region: 'South'),
    BimOutreachCityTarget(city: 'Greenville', state: 'SC', target: 7, region: 'South'),
    BimOutreachCityTarget(city: 'Des Moines', state: 'IA', target: 6, region: 'Midwest'),
    BimOutreachCityTarget(city: 'Madison', state: 'WI', target: 6, region: 'Midwest'),
    BimOutreachCityTarget(city: 'Charleston', state: 'SC', target: 6, region: 'South'),
    BimOutreachCityTarget(city: 'Riverside', state: 'CA', target: 6, region: 'West'),
    BimOutreachCityTarget(city: 'West Palm Beach', state: 'FL', target: 6, region: 'South'),
    BimOutreachCityTarget(city: 'Stamford', state: 'CT', target: 6, region: 'Northeast'),
    BimOutreachCityTarget(city: 'Colorado Springs', state: 'CO', target: 6, region: 'West'),
    BimOutreachCityTarget(city: 'Albany', state: 'NY', target: 6, region: 'Northeast'),
    BimOutreachCityTarget(city: 'Buffalo', state: 'NY', target: 6, region: 'Northeast'),
    BimOutreachCityTarget(city: 'Rochester', state: 'NY', target: 6, region: 'Northeast'),
    BimOutreachCityTarget(city: 'Knoxville', state: 'TN', target: 6, region: 'South'),
    BimOutreachCityTarget(city: 'Grand Rapids', state: 'MI', target: 6, region: 'Midwest'),
    BimOutreachCityTarget(city: 'Wilmington', state: 'DE', target: 6, region: 'South'),
    BimOutreachCityTarget(city: 'Harrisburg', state: 'PA', target: 6, region: 'Northeast'),
    BimOutreachCityTarget(city: 'Columbia', state: 'SC', target: 5, region: 'South'),
    BimOutreachCityTarget(city: 'Greensboro', state: 'NC', target: 5, region: 'South'),
    BimOutreachCityTarget(city: 'Lexington', state: 'KY', target: 5, region: 'South'),
    BimOutreachCityTarget(city: 'Dayton', state: 'OH', target: 5, region: 'Midwest'),
    BimOutreachCityTarget(city: 'Chattanooga', state: 'TN', target: 5, region: 'South'),
    BimOutreachCityTarget(city: 'Huntsville', state: 'AL', target: 5, region: 'South'),
    BimOutreachCityTarget(city: 'Baton Rouge', state: 'LA', target: 5, region: 'South'),
    BimOutreachCityTarget(city: 'Little Rock', state: 'AR', target: 5, region: 'South'),
    BimOutreachCityTarget(city: 'Jackson', state: 'MS', target: 5, region: 'South'),
    BimOutreachCityTarget(city: 'Wichita', state: 'KS', target: 5, region: 'Midwest'),
    BimOutreachCityTarget(city: 'El Paso', state: 'TX', target: 5, region: 'South'),
    BimOutreachCityTarget(city: 'Corpus Christi', state: 'TX', target: 5, region: 'South'),
    BimOutreachCityTarget(city: 'Tallahassee', state: 'FL', target: 5, region: 'South'),
    BimOutreachCityTarget(city: 'Sarasota', state: 'FL', target: 5, region: 'South'),
    BimOutreachCityTarget(city: 'Savannah', state: 'GA', target: 5, region: 'South'),
    BimOutreachCityTarget(city: 'Spokane', state: 'WA', target: 5, region: 'West'),
    BimOutreachCityTarget(city: 'Tacoma', state: 'WA', target: 5, region: 'West'),
    BimOutreachCityTarget(city: 'Reno', state: 'NV', target: 5, region: 'West'),
    BimOutreachCityTarget(city: 'Fresno', state: 'CA', target: 5, region: 'West'),
    BimOutreachCityTarget(city: 'Manchester', state: 'NH', target: 5, region: 'Northeast'),
    BimOutreachCityTarget(city: 'Syracuse', state: 'NY', target: 5, region: 'Northeast'),
    BimOutreachCityTarget(city: 'Worcester', state: 'MA', target: 5, region: 'Northeast'),
    BimOutreachCityTarget(city: 'Portland', state: 'ME', target: 5, region: 'Northeast'),
    BimOutreachCityTarget(city: 'Sioux Falls', state: 'SD', target: 5, region: 'Midwest'),
    BimOutreachCityTarget(city: 'Billings', state: 'MT', target: 5, region: 'West'),
    BimOutreachCityTarget(city: 'Cedar Rapids', state: 'IA', target: 5, region: 'Midwest'),
    BimOutreachCityTarget(city: 'Fargo', state: 'ND', target: 5, region: 'Midwest'),
  ];

  static ({
    CalendarDate startDate,
    CalendarDate targetDate,
    int durationDays,
  }) campaignDates() {
    final start = CalendarDate.fromEthiopian(2019, 3, 9);
    final end = CalendarDate.fromEthiopian(2019, 3, 30);
    return (
      startDate: start,
      targetDate: end,
      durationDays: end.differenceInDays(start) + 1,
    );
  }

  static String _regionGroupId(String region) =>
      'fx-rec-bim-region-${region.toLowerCase()}';

  static String _slugifyCityKey(String city, String state) {
    return '$city-$state'
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  static DaywellProjectPackage buildPackage() {
    final dates = campaignDates();
    final regionTargets = <String, int>{
      for (final region in regionOrder) region: 0,
    };
    for (final city in cities) {
      regionTargets[city.region] = (regionTargets[city.region] ?? 0) + city.target;
    }

    final project = ProjectEntity(
      id: projectId,
      title: projectTitle,
      description:
          '22-day BIM company outreach campaign across 100 US cities grouped by US Census region (1,000 target emails; 46/day target average; Hidar 9–30, 2019 E.C.). Log daily batch counts per city.',
      status: 'active',
      startDate: dates.startDate,
      targetDate: dates.targetDate,
      isArchived: false,
      customFields: const <String, dynamic>{
        'primaryBlockId': blockId,
      },
      createdAt: _templateTimestamp,
      updatedAt: _templateTimestamp,
    );

    final block = ProjectTrackingBlockEntity(
      id: blockId,
      projectId: projectId,
      blockType: ProjectBlockType.groupedList,
      title: 'US City Outreach Targets',
      sortOrder: 0,
      unitLabel: 'emails',
      targetValue: totalTargetEmails.toDouble(),
      dailyTargetValue: dailyTargetEmails.toDouble(),
      config: const <String, dynamic>{
        'showGroupTotals': true,
        'showDailyTotals': true,
        'groupLabel': 'Region',
        'itemLabel': 'City',
      },
      isArchived: false,
      createdAt: _templateTimestamp,
      updatedAt: _templateTimestamp,
    );

    final groupRecords = <ProjectTrackingRecordEntity>[
      for (var i = 0; i < regionOrder.length; i++)
        ProjectTrackingRecordEntity(
          id: _regionGroupId(regionOrder[i]),
          projectId: projectId,
          blockId: blockId,
          recordType: ProjectRecordType.group,
          title: regionOrder[i],
          sortOrder: i,
          targetValue: (regionTargets[regionOrder[i]] ?? 0).toDouble(),
          isCompleted: false,
          metadata: const <String, dynamic>{},
          createdAt: _templateTimestamp,
          updatedAt: _templateTimestamp,
        ),
    ];

    final cityRecords = <ProjectTrackingRecordEntity>[
      for (var i = 0; i < cities.length; i++)
        ProjectTrackingRecordEntity(
          id:
              'fx-rec-bim-city-${(i + 1).toString().padLeft(3, '0')}-${_slugifyCityKey(cities[i].city, cities[i].state)}',
          projectId: projectId,
          blockId: blockId,
          parentRecordId: _regionGroupId(cities[i].region),
          recordType: ProjectRecordType.groupedItem,
          title: cities[i].displayTitle,
          sortOrder: i,
          targetValue: cities[i].target.toDouble(),
          isCompleted: false,
          metadata: const <String, dynamic>{},
          createdAt: _templateTimestamp,
          updatedAt: _templateTimestamp,
        ),
    ];

    return DaywellProjectPackage(
      formatId: SharedProjectPackageSpec.formatId,
      formatVersion: SharedProjectPackageSpec.currentFormatVersion,
      exportedAt: _templateTimestamp,
      sourcePlatform: 'daywell_template',
      project: project,
      trackingBlocks: <ProjectTrackingBlockEntity>[block],
      trackingRecords: <ProjectTrackingRecordEntity>[
        ...groupRecords,
        ...cityRecords,
      ],
    );
  }

  static String buildPackageJson({bool pretty = false}) {
    final map = buildPackage().toJson();
    if (pretty) {
      return '${const JsonEncoder.withIndent('  ').convert(map)}\n';
    }
    return jsonEncode(map);
  }
}
