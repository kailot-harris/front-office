export interface MatchupDist {
  pgPct: number;
  sgPct: number;
  sfPct: number;
  pfPct: number;
  cPct: number;
}

export type DRapmSource =
  | 'rapm_ridge_pooled'
  | 'rapm_ridge_pooled_low_sample'
  | 'heuristic_fallback';

export interface DefensiveProfile {
  season?: number;
  playerId: string;
  playerName: string;
  team: string;
  position: string;
  projMpg: number;
  defensiveRole: string;
  versatilityScore: number; // Shannon Entropy [0-100]
  rimDfgDelta: number; // Opponent Rim FG% delta (negative is elite)
  rimDeterrenceIndex: number; // Rim attempts suppressed
  poaNavigation: number; // Screen navigation [0-100]
  dRapm: number;
  /**
   * Provenance of `dRapm` (issue #83):
   *  - 'rapm_ridge_pooled'            real ridge dRAPM, pooled over 2019-2026
   *  - 'rapm_ridge_pooled_low_sample' same, but flagged low-possession
   *  - 'heuristic_fallback'           rebound/assist proxy, not RAPM
   * Never label a 'heuristic_fallback' value as RAPM in the UI.
   */
  dRapmSource: DRapmSource;
  /** Ridge fit matched, but on few possessions. */
  dRapmLowSample: boolean;
  /** Matched through a same-surname collision resolved by possession count. */
  dRapmAmbiguous: boolean;
  matchupDist: MatchupDist;
}

/**
 * The seasons cache/rapm_ratings.rds is fitted over. The ridge fit is a SINGLE
 * pooled fit with no `season` column, and there is no 2026-only snapshot, so the
 * shipped rating must be presented as a multi-season career-to-date number and
 * never as "2026 dRAPM" (issue #83).
 */
export const DRAPM_POOLED_SEASON_LABEL = '2019-2026 pooled';

export interface DRapmMeta {
  /** Column header / card title. Says "RAPM" only for genuinely RAPM-sourced values. */
  label: string;
  /** Short caption spelling out the source and the zero-centred scale. */
  caption: string;
  /** Compact badge text for dense list rows. */
  badge: string;
  /** True when the value came from the ridge fit rather than the heuristic. */
  isReal: boolean;
}

/** Per-player provenance copy for `dRapm`. */
export function dRapmMeta(p: DefensiveProfile): DRapmMeta {
  if (p.dRapmSource === 'heuristic_fallback') {
    return {
      label: 'Defensive Rating (estimate)',
      caption:
        'Heuristic estimate from rebounds/assists — not RAPM. No ridge RAPM row matched this player.',
      badge: 'est.',
      isReal: false,
    };
  }
  if (p.dRapmSource === 'rapm_ridge_pooled_low_sample') {
    return {
      label: `Defensive RAPM (${DRAPM_POOLED_SEASON_LABEL}, low sample)`,
      caption: `Ridge-fitted dRAPM, ${DRAPM_POOLED_SEASON_LABEL} — not a 2026-only rating. Few possessions, so treat with caution. 0 = league average, higher is better defence.`,
      badge: 'RAPM · low n',
      isReal: true,
    };
  }
  return {
    label: `Defensive RAPM (${DRAPM_POOLED_SEASON_LABEL})`,
    caption: `Ridge-fitted dRAPM, ${DRAPM_POOLED_SEASON_LABEL} — not a 2026-only rating. 0 = league average, higher is better defence.`,
    badge: 'RAPM',
    isReal: true,
  };
}

/**
 * Colour for a zero-centred rating: league average is 0, so roughly half the
 * league is legitimately negative and a negative value is not an error state.
 */
export function dRapmColorClass(p: DefensiveProfile): string {
  if (p.dRapmSource === 'heuristic_fallback') return 'text-amber-400';
  if (p.dRapm >= 1.0) return 'text-emerald-400';
  if (p.dRapm <= -1.0) return 'text-rose-400';
  return 'text-slate-300';
}
