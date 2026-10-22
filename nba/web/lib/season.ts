export type SeasonKind =
  | 'projection'
  | 'observed'
  | 'fallback'
  | 'backtest'
  | 'mixed';

export interface SeasonSource {
  /** Full display span, e.g. '2026-2027' or '2024-2025 + 2025-2026'. */
  season: string;
  kind: SeasonKind;
  /** Short reader-facing explanation of what the span means. */
  note: string;
}

/**
 * Normalize a season label to full calendar years.
 *
 * Accepts a hoopR end-year (2026 -> 2025-2026), a short span
 * ('2025-26' -> '2025-2026'), a full span ('2025-2026'), or several spans
 * joined by ' + '. Labels that are already full years are left alone.
 */
export function formatSeasonLabel(
  value: string | number | null | undefined
): string | null {
  if (value == null || value === '') return null;
  if (typeof value === 'number') {
    return Number.isFinite(value) ? `${value - 1}-${value}` : null;
  }
  const trimmed = String(value).trim();
  if (!trimmed) return null;
  return trimmed.replace(
    /\b(\d{4})-(\d{2})\b/g,
    (_match, start: string, end: string) =>
      `${start}-${start.slice(0, 2)}${end}`
  );
}

/** Convert a hoopR season end year (2026) to a full display span (2025-2026). */
export function seasonEndYearLabel(endYear: number): string {
  return `${endYear - 1}-${endYear}`;
}

/**
 * Canonical season source for each dataset/page. Keeping these in one place
 * makes the fallback explicit: anything not yet generated for 2026-2027 points
 * at the last completed season (2025-2026) instead of silently implying the
 * projected season.
 */
export const SEASON_SOURCES = {
  teamProjections: {
    season: '2026-2027',
    kind: 'projection',
    note: '1,000-season Monte Carlo projection. RAPM and shot-quality inputs are observed 2025-2026 data.',
  },
  playerProjections: {
    season: '2026-2027',
    kind: 'projection',
    note: 'Projected 2026-2027 per-game rates and season totals.',
  },
  clutch: {
    season: '2026-2027',
    kind: 'projection',
    note: 'Projected 2026-2027 clutch profile derived from the player projection set.',
  },
  defense: {
    season: '2026-2027',
    kind: 'projection',
    note: 'Projected 2026-2027 defensive role and matchup metrics.',
  },
  playerDna: {
    season: '2026-2027',
    kind: 'projection',
    note: 'Projected 2026-2027 skill vector; historical comparables span 1990-2025.',
  },
  coachesObserved: {
    season: '2025-2026',
    kind: 'fallback',
    note: 'ATO and challenge events observed in the last completed season; the 2026-2027 sample is too small.',
  },
  offseason: {
    season: '2026-2027',
    kind: 'projection',
    note: '2026-2027 offseason transactions, roster moves, and draft class.',
  },
  capSheet: {
    season: '2026-2027',
    kind: 'projection',
    note: '2026-2027 league-year salary cap, apron, and payroll.',
  },
  matchups: {
    season: '2026-2027',
    kind: 'projection',
    note: '2026-2027 schedule and per-game projections.',
  },
  playoffSeries: {
    season: '2026-2027',
    kind: 'projection',
    note: '2026-2027 projected playoff matchups and series simulations.',
  },
  diagnostics: {
    season: '2024-2025 + 2025-2026',
    kind: 'backtest',
    note: 'Historical calibration over two completed seasons.',
  },
  variants: {
    season: '2026-2027',
    kind: 'projection',
    note: 'Projected 2026-2027 team outcomes. Each tab shows the season its inputs were observed in.',
  },
  shots: {
    season: '2025-2026',
    kind: 'fallback',
    note: 'The 2026-2027 shot sample is not yet large enough; this page shows the completed 2025-2026 season.',
  },
  brier: {
    season: '2024-2025 + 2025-2026',
    kind: 'backtest',
    note: 'Historical cross-validation over two completed seasons.',
  },
} as const satisfies Record<string, SeasonSource>;
