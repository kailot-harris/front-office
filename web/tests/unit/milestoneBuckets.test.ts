import { describe, expect, it } from 'vitest';
import { bucketMilestones, isoDayNumber } from '../../lib/milestoneBuckets';
import type { UpcomingMilestone } from '../../lib/offseasonTypes';

// Milestones as published in Week 1 (offseason_monitor.json, publishDate
// 2026-11-17) plus the reported 2027 season window from the league state
// baseline (PR #219).
const LOTTERY: UpcomingMilestone = { date: '2026-11-15', event: '2027 WNBA Draft Lottery (ESPN)', status: 'Confirmed' };
const FA_FILING: UpcomingMilestone = {
  date: null,
  event: 'Free Agency Qualifying Offer & Core Designation Filing Window',
  status: 'Tentative',
};
const FA_NEGOTIATION: UpcomingMilestone = {
  date: null,
  event: 'Free Agency Negotiation & Contract Execution Period',
  status: 'Tentative',
};
const DRAFT: UpcomingMilestone = { date: '2027-04-12', event: '2027 WNBA Draft', status: 'Confirmed' };
const CAMPS: UpcomingMilestone = {
  date: '2027-04-25',
  event: '2027 Training Camps Open (Hand-off to Daily In-Season Pipeline)',
  status: 'Tentative',
};
const SEASON: UpcomingMilestone = {
  date: '2027-05-07',
  event: '2027 WNBA season window, reported, not confirmed: expected to open May 7 and end no later than Oct. 24',
  status: 'Reported',
};

// Input order deliberately not date order, to check sorting.
const MILESTONES = [SEASON, LOTTERY, FA_FILING, FA_NEGOTIATION, CAMPS, DRAFT];

const dates = (xs: UpcomingMilestone[]) => xs.map((m) => m.date);

describe('isoDayNumber', () => {
  it('counts whole UTC days and rejects non-dates', () => {
    expect(isoDayNumber('1970-01-02')).toBe(1);
    expect(isoDayNumber('2026-11-17')! - isoDayNumber('2026-11-15')!).toBe(2);
    expect(isoDayNumber(null)).toBeNull();
    expect(isoDayNumber('')).toBeNull();
    expect(isoDayNumber('Date TBD')).toBeNull();
  });
});

describe('bucketMilestones (same rules as the memo Block 4)', () => {
  it('Week 1 (2026-11-17): lottery recently passed, TBD items in the next 30 days, 2027 dates later', () => {
    const g = bucketMilestones(MILESTONES, '2026-11-17');
    expect(g.recentlyPassed).toEqual([LOTTERY]);
    expect(g.next30Days).toEqual([FA_FILING, FA_NEGOTIATION]);
    expect(g.later).toEqual([DRAFT, CAMPS, SEASON]);
    expect(g.next30Days.some((m) => m.date === '2026-11-15')).toBe(false);
  });

  it('Week 2 (2026-11-23): same grouping, lottery still within 14 days', () => {
    const g = bucketMilestones(MILESTONES, '2026-11-23');
    expect(g.recentlyPassed).toEqual([LOTTERY]);
    expect(g.next30Days).toEqual([FA_FILING, FA_NEGOTIATION]);
    expect(dates(g.later)).toEqual(['2027-04-12', '2027-04-25', '2027-05-07']);
  });

  it('14-day boundary: 14 days after is recently passed, 15 days after is dropped', () => {
    const at14 = bucketMilestones([LOTTERY], '2026-11-29');
    expect(at14.recentlyPassed).toEqual([LOTTERY]);
    const at15 = bucketMilestones([LOTTERY], '2026-11-30');
    expect(at15).toEqual({ recentlyPassed: [], next30Days: [], later: [] });
  });

  it('publishDate itself counts as the next 30 days, the day before as recently passed', () => {
    expect(bucketMilestones([LOTTERY], '2026-11-15').next30Days).toEqual([LOTTERY]);
    expect(bucketMilestones([LOTTERY], '2026-11-16').recentlyPassed).toEqual([LOTTERY]);
  });

  it('30-day boundary: 30 days ahead is in the next 30 days, 31 days ahead is later', () => {
    // 2027-04-12 is 30 days after 2027-03-13 and 31 days after 2027-03-12.
    expect(bucketMilestones([DRAFT], '2027-03-13').next30Days).toEqual([DRAFT]);
    expect(bucketMilestones([DRAFT], '2027-03-12').later).toEqual([DRAFT]);
  });

  it('memo spot checks: 2026-11-02 lottery upcoming; 2027-03-20 draft upcoming, camps later', () => {
    expect(bucketMilestones(MILESTONES, '2026-11-02').next30Days).toEqual([LOTTERY, FA_FILING, FA_NEGOTIATION]);
    const spring = bucketMilestones(MILESTONES, '2027-03-20');
    expect(spring.next30Days).toEqual([DRAFT, FA_FILING, FA_NEGOTIATION]);
    expect(spring.later).toEqual([CAMPS, SEASON]);
    expect(spring.recentlyPassed).toEqual([]);
  });

  it('empty input gives empty groups; a bad publishDate throws instead of guessing', () => {
    expect(bucketMilestones([], '2026-11-17')).toEqual({ recentlyPassed: [], next30Days: [], later: [] });
    expect(() => bucketMilestones(MILESTONES, 'not a date')).toThrow(/publishDate/);
  });
});
