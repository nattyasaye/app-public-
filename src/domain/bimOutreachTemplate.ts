import { CalendarDate } from './date';
import { DaywellProjectPackageV1 } from './projectPackage';
import {
  SHARED_PROJECT_PACKAGE_SPEC,
  SharedProjectTrackingBlock,
  SharedProjectTrackingRecord,
} from './sharedFoundation';

export type UsCensusRegion = 'Northeast' | 'Midwest' | 'South' | 'West';

export interface BimOutreachCityTarget {
  readonly city: string;
  readonly state: string;
  readonly target: number;
  readonly region: UsCensusRegion;
}

export const US_CENSUS_REGION_ORDER: readonly UsCensusRegion[] = [
  'Northeast',
  'Midwest',
  'South',
  'West',
] as const;

export const BIM_OUTREACH_CAMPAIGN_PROJECT_ID = 'fx-proj-bim-outreach-2019';
export const BIM_OUTREACH_CAMPAIGN_BLOCK_ID = 'fx-blk-bim-outreach-cities';
export const BIM_OUTREACH_CAMPAIGN_TITLE = 'BIM Company Outreach — 1,000 Companies';
export const BIM_OUTREACH_CAMPAIGN_FILENAME =
  'bim-company-outreach-1000-companies.daywellproject';
export const BIM_OUTREACH_CAMPAIGN_TARGET_TOTAL = 1000;
export const BIM_OUTREACH_CAMPAIGN_DAILY_TARGET = 46;

const TEMPLATE_TIMESTAMP_ISO = '2026-11-17T08:00:00.000Z';

export const BIM_OUTREACH_CITIES: readonly BimOutreachCityTarget[] = [
  { city: 'New York', state: 'NY', target: 30, region: 'Northeast' },
  { city: 'Los Angeles', state: 'CA', target: 30, region: 'West' },
  { city: 'Chicago', state: 'IL', target: 30, region: 'Midwest' },
  { city: 'Houston', state: 'TX', target: 30, region: 'South' },
  { city: 'Dallas', state: 'TX', target: 25, region: 'South' },
  { city: 'Washington', state: 'DC', target: 25, region: 'South' },
  { city: 'Atlanta', state: 'GA', target: 25, region: 'South' },
  { city: 'Boston', state: 'MA', target: 20, region: 'Northeast' },
  { city: 'Seattle', state: 'WA', target: 20, region: 'West' },
  { city: 'San Francisco', state: 'CA', target: 20, region: 'West' },
  { city: 'Phoenix', state: 'AZ', target: 20, region: 'West' },
  { city: 'Miami', state: 'FL', target: 20, region: 'South' },
  { city: 'Denver', state: 'CO', target: 20, region: 'West' },
  { city: 'Philadelphia', state: 'PA', target: 15, region: 'Northeast' },
  { city: 'Austin', state: 'TX', target: 15, region: 'South' },
  { city: 'Minneapolis', state: 'MN', target: 15, region: 'Midwest' },
  { city: 'San Diego', state: 'CA', target: 15, region: 'West' },
  { city: 'Tampa', state: 'FL', target: 15, region: 'South' },
  { city: 'Orlando', state: 'FL', target: 15, region: 'South' },
  { city: 'Charlotte', state: 'NC', target: 15, region: 'South' },
  { city: 'Portland', state: 'OR', target: 15, region: 'West' },
  { city: 'Baltimore', state: 'MD', target: 12, region: 'South' },
  { city: 'Nashville', state: 'TN', target: 12, region: 'South' },
  { city: 'Raleigh', state: 'NC', target: 12, region: 'South' },
  { city: 'Detroit', state: 'MI', target: 12, region: 'Midwest' },
  { city: 'Pittsburgh', state: 'PA', target: 12, region: 'Northeast' },
  { city: 'St. Louis', state: 'MO', target: 12, region: 'Midwest' },
  { city: 'Kansas City', state: 'MO', target: 12, region: 'Midwest' },
  { city: 'Salt Lake City', state: 'UT', target: 12, region: 'West' },
  { city: 'San Jose', state: 'CA', target: 10, region: 'West' },
  { city: 'Newark', state: 'NJ', target: 10, region: 'Northeast' },
  { city: 'Irvine', state: 'CA', target: 10, region: 'West' },
  { city: 'Sacramento', state: 'CA', target: 10, region: 'West' },
  { city: 'Las Vegas', state: 'NV', target: 10, region: 'West' },
  { city: 'San Antonio', state: 'TX', target: 10, region: 'South' },
  { city: 'Columbus', state: 'OH', target: 10, region: 'Midwest' },
  { city: 'Indianapolis', state: 'IN', target: 10, region: 'Midwest' },
  { city: 'Cincinnati', state: 'OH', target: 10, region: 'Midwest' },
  { city: 'Cleveland', state: 'OH', target: 10, region: 'Midwest' },
  { city: 'Milwaukee', state: 'WI', target: 8, region: 'Midwest' },
  { city: 'Jacksonville', state: 'FL', target: 8, region: 'South' },
  { city: 'Richmond', state: 'VA', target: 8, region: 'South' },
  { city: 'Virginia Beach', state: 'VA', target: 8, region: 'South' },
  { city: 'Fort Worth', state: 'TX', target: 8, region: 'South' },
  { city: 'Oklahoma City', state: 'OK', target: 8, region: 'South' },
  { city: 'New Orleans', state: 'LA', target: 8, region: 'South' },
  { city: 'Louisville', state: 'KY', target: 8, region: 'South' },
  { city: 'Hartford', state: 'CT', target: 8, region: 'Northeast' },
  { city: 'Oakland', state: 'CA', target: 8, region: 'West' },
  { city: 'Tulsa', state: 'OK', target: 7, region: 'South' },
  { city: 'Memphis', state: 'TN', target: 7, region: 'South' },
  { city: 'Birmingham', state: 'AL', target: 7, region: 'South' },
  { city: 'Providence', state: 'RI', target: 7, region: 'Northeast' },
  { city: 'Albuquerque', state: 'NM', target: 7, region: 'West' },
  { city: 'Tucson', state: 'AZ', target: 7, region: 'West' },
  { city: 'Boise', state: 'ID', target: 7, region: 'West' },
  { city: 'Omaha', state: 'NE', target: 7, region: 'Midwest' },
  { city: 'Fort Lauderdale', state: 'FL', target: 7, region: 'South' },
  { city: 'Greenville', state: 'SC', target: 7, region: 'South' },
  { city: 'Des Moines', state: 'IA', target: 6, region: 'Midwest' },
  { city: 'Madison', state: 'WI', target: 6, region: 'Midwest' },
  { city: 'Charleston', state: 'SC', target: 6, region: 'South' },
  { city: 'Riverside', state: 'CA', target: 6, region: 'West' },
  { city: 'West Palm Beach', state: 'FL', target: 6, region: 'South' },
  { city: 'Stamford', state: 'CT', target: 6, region: 'Northeast' },
  { city: 'Colorado Springs', state: 'CO', target: 6, region: 'West' },
  { city: 'Albany', state: 'NY', target: 6, region: 'Northeast' },
  { city: 'Buffalo', state: 'NY', target: 6, region: 'Northeast' },
  { city: 'Rochester', state: 'NY', target: 6, region: 'Northeast' },
  { city: 'Knoxville', state: 'TN', target: 6, region: 'South' },
  { city: 'Grand Rapids', state: 'MI', target: 6, region: 'Midwest' },
  { city: 'Wilmington', state: 'DE', target: 6, region: 'South' },
  { city: 'Harrisburg', state: 'PA', target: 6, region: 'Northeast' },
  { city: 'Columbia', state: 'SC', target: 5, region: 'South' },
  { city: 'Greensboro', state: 'NC', target: 5, region: 'South' },
  { city: 'Lexington', state: 'KY', target: 5, region: 'South' },
  { city: 'Dayton', state: 'OH', target: 5, region: 'Midwest' },
  { city: 'Chattanooga', state: 'TN', target: 5, region: 'South' },
  { city: 'Huntsville', state: 'AL', target: 5, region: 'South' },
  { city: 'Baton Rouge', state: 'LA', target: 5, region: 'South' },
  { city: 'Little Rock', state: 'AR', target: 5, region: 'South' },
  { city: 'Jackson', state: 'MS', target: 5, region: 'South' },
  { city: 'Wichita', state: 'KS', target: 5, region: 'Midwest' },
  { city: 'El Paso', state: 'TX', target: 5, region: 'South' },
  { city: 'Corpus Christi', state: 'TX', target: 5, region: 'South' },
  { city: 'Tallahassee', state: 'FL', target: 5, region: 'South' },
  { city: 'Sarasota', state: 'FL', target: 5, region: 'South' },
  { city: 'Savannah', state: 'GA', target: 5, region: 'South' },
  { city: 'Spokane', state: 'WA', target: 5, region: 'West' },
  { city: 'Tacoma', state: 'WA', target: 5, region: 'West' },
  { city: 'Reno', state: 'NV', target: 5, region: 'West' },
  { city: 'Fresno', state: 'CA', target: 5, region: 'West' },
  { city: 'Manchester', state: 'NH', target: 5, region: 'Northeast' },
  { city: 'Syracuse', state: 'NY', target: 5, region: 'Northeast' },
  { city: 'Worcester', state: 'MA', target: 5, region: 'Northeast' },
  { city: 'Portland', state: 'ME', target: 5, region: 'Northeast' },
  { city: 'Sioux Falls', state: 'SD', target: 5, region: 'Midwest' },
  { city: 'Billings', state: 'MT', target: 5, region: 'West' },
  { city: 'Cedar Rapids', state: 'IA', target: 5, region: 'Midwest' },
  { city: 'Fargo', state: 'ND', target: 5, region: 'Midwest' },
] as const;

export function getBimOutreachCampaignDates(): {
  startDate: CalendarDate;
  targetDate: CalendarDate;
  startIso: string;
  targetIso: string;
  durationDays: number;
} {
  const startDate = CalendarDate.fromEthiopian(2019, 3, 9);
  const targetDate = CalendarDate.fromEthiopian(2019, 3, 30);
  return {
    startDate,
    targetDate,
    startIso: startDate.toIsoString(),
    targetIso: targetDate.toIsoString(),
    durationDays: targetDate.differenceInDays(startDate) + 1,
  };
}

function slugifyCityKey(city: string, state: string): string {
  const base = `${city}-${state}`
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return base;
}

export function buildBimOutreachPackage(): DaywellProjectPackageV1 {
  const { startIso, targetIso } = getBimOutreachCampaignDates();

  const regionGroupId = (region: UsCensusRegion): string =>
    `fx-rec-bim-region-${region.toLowerCase()}`;

  const regionTargets = new Map<UsCensusRegion, number>(
    US_CENSUS_REGION_ORDER.map((region) => [region, 0])
  );
  for (const entry of BIM_OUTREACH_CITIES) {
    regionTargets.set(
      entry.region,
      (regionTargets.get(entry.region) ?? 0) + entry.target
    );
  }

  const block: SharedProjectTrackingBlock = {
    id: BIM_OUTREACH_CAMPAIGN_BLOCK_ID,
    projectId: BIM_OUTREACH_CAMPAIGN_PROJECT_ID,
    blockType: 'grouped_list',
    title: 'US City Outreach Targets',
    sortOrder: 0,
    unitLabel: 'emails',
    targetValue: BIM_OUTREACH_CAMPAIGN_TARGET_TOTAL,
    dailyTargetValue: BIM_OUTREACH_CAMPAIGN_DAILY_TARGET,
    config: {
      showGroupTotals: true,
      showDailyTotals: true,
      groupLabel: 'Region',
      itemLabel: 'City',
    },
    isArchived: false,
    createdAt: TEMPLATE_TIMESTAMP_ISO,
    updatedAt: TEMPLATE_TIMESTAMP_ISO,
  };

  const groupRecords: SharedProjectTrackingRecord[] = US_CENSUS_REGION_ORDER.map(
    (region, idx) => ({
      id: regionGroupId(region),
      projectId: BIM_OUTREACH_CAMPAIGN_PROJECT_ID,
      blockId: BIM_OUTREACH_CAMPAIGN_BLOCK_ID,
      recordType: 'group',
      title: region,
      sortOrder: idx,
      targetValue: regionTargets.get(region) ?? 0,
      isCompleted: false,
      metadata: {},
      createdAt: TEMPLATE_TIMESTAMP_ISO,
      updatedAt: TEMPLATE_TIMESTAMP_ISO,
    })
  );

  const cityRecords: SharedProjectTrackingRecord[] = BIM_OUTREACH_CITIES.map(
    (entry, idx) => ({
      id: `fx-rec-bim-city-${String(idx + 1).padStart(3, '0')}-${slugifyCityKey(
        entry.city,
        entry.state
      )}`,
      projectId: BIM_OUTREACH_CAMPAIGN_PROJECT_ID,
      blockId: BIM_OUTREACH_CAMPAIGN_BLOCK_ID,
      parentRecordId: regionGroupId(entry.region),
      recordType: 'grouped_item',
      title: `${entry.city}, ${entry.state}`,
      sortOrder: idx,
      targetValue: entry.target,
      isCompleted: false,
      metadata: {},
      createdAt: TEMPLATE_TIMESTAMP_ISO,
      updatedAt: TEMPLATE_TIMESTAMP_ISO,
    })
  );

  return {
    formatId: SHARED_PROJECT_PACKAGE_SPEC.formatId,
    formatVersion: SHARED_PROJECT_PACKAGE_SPEC.currentFormatVersion,
    exportedAt: TEMPLATE_TIMESTAMP_ISO,
    sourcePlatform: 'daywell_template',
    project: {
      id: BIM_OUTREACH_CAMPAIGN_PROJECT_ID,
      title: BIM_OUTREACH_CAMPAIGN_TITLE,
      description:
        '22-day BIM company outreach campaign across 100 US cities grouped by US Census region (1,000 target emails; 46/day target average; Hidar 9–30, 2019 E.C.). Log daily batch counts per city.',
      status: 'active',
      startDate: startIso,
      targetDate: targetIso,
      isArchived: false,
      customFields: {
        primaryBlockId: BIM_OUTREACH_CAMPAIGN_BLOCK_ID,
      },
      createdAt: TEMPLATE_TIMESTAMP_ISO,
      updatedAt: TEMPLATE_TIMESTAMP_ISO,
    },
    trackingBlocks: [block],
    trackingRecords: [...groupRecords, ...cityRecords],
  };
}

export function serializeBimOutreachTemplateJson(): string {
  return `${JSON.stringify(buildBimOutreachPackage(), null, 2)}\n`;
}
