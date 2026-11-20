import type { UpcomingMilestone } from './offseasonTypes';

/**
 * Groups an edition's milestones relative to its publishDate, with the same
 * rules as the memo's Block 4 (`render_block_4_milestones` in
 * tools/offseason/render_memo.R):
 *
 *   - recentlyPassed: dated before publishDate and at most `recentDays` before it
 *   - next30Days:     dated from publishDate to publishDate + `horizonDays`
 *                     (inclusive), then undated items ("Date TBD")
 *   - later:          dated after publishDate + `horizonDays`
 *
 * Dated items more than `recentDays` before publishDate are dropped. Each
 * dated group is in date order; input order breaks ties and orders TBD items.
 *
 * The reference date is the edition's publishDate, never the browser clock, so
 * the pre-rendered HTML and the hydrated page always agree.
 */
export interface MilestoneBuckets {
  recentlyPassed: UpcomingMilestone[];
  next30Days: UpcomingMilestone[];
  later: UpcomingMilestone[];
}

export const MILESTONE_HORIZON_DAYS = 30;
export const MILESTONE_RECENT_DAYS = 14;

const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})/;

/** Whole days since 1970-01-01 for a YYYY-MM-DD string, or null if not a date. */
export function isoDayNumber(value: string | null | undefined): number | null {
  if (typeof value !== 'string') return null;
  const m = ISO_DATE.exec(value.trim());
  if (!m) return null;
  const ms = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return Number.isNaN(ms) ? null : Math.round(ms / 86_400_000);
}

export function bucketMilestones(
  milestones: readonly UpcomingMilestone[],
  publishDate: string,
  horizonDays: number = MILESTONE_HORIZON_DAYS,
  recentDays: number = MILESTONE_RECENT_DAYS,
): MilestoneBuckets {
  const ref = isoDayNumber(publishDate);
  if (ref === null) {
    throw new Error(`bucketMilestones: publishDate "${publishDate}" is not a YYYY-MM-DD date`);
  }

  type Dated = { m: UpcomingMilestone; day: number; idx: number };
  const recent: Dated[] = [];
  const soon: Dated[] = [];
  const later: Dated[] = [];
  const tbd: UpcomingMilestone[] = [];

  milestones.forEach((m, idx) => {
    const day = isoDayNumber(m.date);
    if (day === null) {
      tbd.push(m);
    } else if (day < ref) {
      if (day >= ref - recentDays) recent.push({ m, day, idx });
    } else if (day <= ref + horizonDays) {
      soon.push({ m, day, idx });
    } else {
      later.push({ m, day, idx });
    }
  });

  const byDate = (a: Dated, b: Dated) => a.day - b.day || a.idx - b.idx;
  const unwrap = (xs: Dated[]) => xs.sort(byDate).map((x) => x.m);

  return {
    recentlyPassed: unwrap(recent),
    next30Days: [...unwrap(soon), ...tbd],
    later: unwrap(later),
  };
}
