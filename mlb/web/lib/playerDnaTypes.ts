// ==============================================================================
// web/lib/playerDnaTypes.ts
// Type definitions for High-Dimensional MLB Player DNA & Historical Twins (/player-dna)
// ==============================================================================

export interface HistoricalTwin {
  compName: string;
  era: string;
  archetype: string;
  position: string;
  similarityPct: number;
  keySharedTrait: string;
}

export interface BatterSkillVector {
  exit_velo_90: number;
  barrel_pct: number;
  hard_hit_pct: number;
  iso_power: number;
  zone_contact: number;
  whiff_avoidance: number;
  strikeout_avoidance: number;
  chase_discipline: number;
  walk_rate: number;
  sweet_spot_pct: number;
  pull_air_pct: number;
  all_fields_spray: number;
  sprint_speed: number;
  baserunning_val: number;
  fielding_range: number;
  clutch_resilience: number;
}

export interface PitcherSkillVector {
  fastball_velo: number;
  fastball_ivb: number;
  horizontal_break: number;
  extension_release: number;
  stuff_plus: number;
  arsenal_diversity: number;
  secondary_whiff: number;
  location_plus: number;
  zone_rate: number;
  strikeout_rate: number;
  walk_suppression: number;
  hard_hit_suppression: number;
  barrel_suppression: number;
  groundball_rate: number;
  workload_stamina: number;
  high_leverage_shutdown: number;
}

export interface BatterCategoryScores {
  power: number;
  contact: number;
  discipline: number;
  batted_ball: number;
  athleticism: number;
}

export interface PitcherCategoryScores {
  velocity_physics: number;
  arsenal_stuff: number;
  command_k: number;
  batted_ball: number;
  workload_leverage: number;
}

export interface HeadlineStats {
  stat1Label: string;
  stat1Val: string | number;
  stat2Label: string;
  stat2Val: string | number;
  stat3Label: string;
  stat3Val: string | number;
  countLabel: string;
  countVal: string | number;
}

export interface PlayerDnaProfile {
  playerId: string;
  mlbamId: string;
  playerName: string;
  team: string;
  playerType: 'Batter' | 'Pitcher';
  position: string;
  age: number;
  archetype: string;
  headlineStats: HeadlineStats;
  compositeZscore: number;
  overallRating: number;
  manifoldX: number;
  manifoldY: number;
  skillVector: BatterSkillVector | PitcherSkillVector;
  categoryScores: BatterCategoryScores | PitcherCategoryScores;
  historicalTwins: HistoricalTwin[];
}

export interface PlayerDnaCatalog {
  updatedAt: string;
  eraBaseline: string; // "1980-2026"
  totalPlayers: number;
  batterArchetypes: string[];
  pitcherArchetypes: string[];
  profiles: PlayerDnaProfile[];
}
