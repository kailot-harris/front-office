// ==============================================================================
// web/lib/playerDnaTypes.ts
// Type definitions for MLB Player DNA & same-season peer comps (/player-dna).
// Written by mlb_player_dna_engine.R. Every dimension is a within-pool percentile
// (0-100) of one real FanGraphs column for the published season; null = missing input.
// team is null when FanGraphs reports no single club (the player played for 2+ teams
// that season); the page shows MULTI_TEAM_LABEL for it and never looks up a logo.
// ==============================================================================

export type DnaPlayerType = 'Batter' | 'Pitcher';

/** Shown wherever a null team is displayed. Not a team code. */
export const MULTI_TEAM_LABEL = '2+ teams';
export const MULTI_TEAM_NOTE = 'Played for more than one club this season; FanGraphs reports no single team.';

/** One published skill dimension (envelope `dimensions`). */
export interface DnaDimension {
  key: string;
  label: string;
  category: string;
}

/** One published category (envelope `categories`); its score is the mean of its dimensions. */
export interface DnaCategory {
  key: string;
  label: string;
}

export interface PeerComp {
  playerId: string;
  compName: string;
  team: string | null;
  position: string | null;
  archetype: string | null;
  similarityPct: number;
  keySharedTrait: string;
}

export interface BatterSkillVector {
  exit_velo_90: number | null;
  barrel_pct: number | null;
  hard_hit_pct: number | null;
  iso_power: number | null;
  zone_contact: number | null;
  whiff_avoidance: number | null;
  strikeout_avoidance: number | null;
  chase_discipline: number | null;
  walk_rate: number | null;
  squared_up_pct: number | null;
  pull_air_pct: number | null;
  all_fields_spray: number | null;
  speed_score: number | null;
  baserunning_val: number | null;
  fielding_range: number | null;
  clutch_resilience: number | null;
}

export interface PitcherSkillVector {
  fastball_velo: number | null;
  fastball_ivb: number | null;
  horizontal_break: number | null;
  stuff_plus: number | null;
  arsenal_diversity: number | null;
  swinging_strike_rate: number | null;
  location_plus: number | null;
  zone_rate: number | null;
  strikeout_rate: number | null;
  walk_suppression: number | null;
  hard_hit_suppression: number | null;
  barrel_suppression: number | null;
  groundball_rate: number | null;
  workload_stamina: number | null;
  clutch_resilience: number | null;
}

export interface BatterCategoryScores {
  power: number | null;
  contact: number | null;
  discipline: number | null;
  batted_ball: number | null;
  athleticism: number | null;
}

export interface PitcherCategoryScores {
  velocity_physics: number | null;
  arsenal_stuff: number | null;
  command_k: number | null;
  batted_ball: number | null;
  workload_leverage: number | null;
}

export interface HeadlineStats {
  stat1Label: string;
  stat1Val: string | number | null;
  stat2Label: string;
  stat2Val: string | number | null;
  stat3Label: string;
  stat3Val: string | number | null;
  countLabel: string;
  countVal: string | number | null;
}

export interface PlayerDnaProfile {
  playerId: string;
  mlbamId: string | null;
  playerName: string;
  team: string | null;
  playerType: DnaPlayerType;
  position: string | null;
  age: number | null;
  archetype: string | null;
  headlineStats: HeadlineStats;
  overallRating: number | null;
  manifoldX: number | null;
  manifoldY: number | null;
  skillVector: BatterSkillVector | PitcherSkillVector;
  categoryScores: BatterCategoryScores | PitcherCategoryScores;
  peerComps: PeerComp[];
}

export interface PlayerDnaCatalog {
  generated_at: string; // publish gate stamp (tools/publish_web.R assertion F)
  season: number | null; // null only in the missing-file fallback of getPlayerDnaCatalog()
  throughDate: string | null; // last regular-season date with a final game in the window
  generatedAt: string;
  dimensions: Record<DnaPlayerType, DnaDimension[]>;
  categories: Record<DnaPlayerType, DnaCategory[]>;
  profiles: PlayerDnaProfile[];
}

/**
 * Whole-dataset facts the page needs before the full profile list has been fetched
 * (the static HTML embeds only the first screen of profiles).
 */
export interface PlayerDnaSummary {
  totalProfiles: number;
  counts: Record<DnaPlayerType, number>;
  plotted: Record<DnaPlayerType, number>;
  archetypes: Record<DnaPlayerType, string[]>;
}

export function summarizePlayerDna(profiles: PlayerDnaProfile[]): PlayerDnaSummary {
  const types: DnaPlayerType[] = ['Batter', 'Pitcher'];
  const counts = { Batter: 0, Pitcher: 0 };
  const plotted = { Batter: 0, Pitcher: 0 };
  const archetypes = { Batter: new Set<string>(), Pitcher: new Set<string>() };
  for (const p of profiles) {
    counts[p.playerType] += 1;
    if (p.manifoldX !== null && p.manifoldY !== null) plotted[p.playerType] += 1;
    if (p.archetype) archetypes[p.playerType].add(p.archetype);
  }
  return {
    totalProfiles: profiles.length,
    counts,
    plotted,
    archetypes: Object.fromEntries(types.map((t) => [t, Array.from(archetypes[t]).sort()])) as Record<DnaPlayerType, string[]>,
  };
}
