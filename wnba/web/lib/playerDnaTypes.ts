export type DnaSource = 'observed_pbp_box' | 'projection_prior_fallback';

export interface HistoricalTwin {
  compName: string;
  era: string;
  archetype: string;
  position: string;
  similarityPct: number;
  keySharedTrait: string;
}

export interface SimilarPlayerPeer {
  playerId: string;
  playerName: string;
  team: string;
  position: string;
  similarityPct: number;
}

export interface SkillVector {
  rim_fg: number;
  paint_power: number;
  cns_3p: number;
  pullup_3p: number;
  ft_pct: number;
  ast_pct: number;
  tov_control: number;
  rim_protection: number;
  perimeter_havoc: number;
  d_rapm: number;
  oreb: number;
  dreb: number;
}

export interface CategoryScores {
  finishing: number;
  shooting: number;
  playmaking: number;
  defense: number;
  rebounding: number;
}

export interface PlayerDnaProfile {
  season?: number;
  playerId: string;
  playerName: string;
  team: string;
  position: string;
  archetype: string;
  dnaSource: DnaSource;
  projPts: number;
  projReb: number;
  projAst: number;
  projMpg: number;
  overallRating: number;
  manifoldX: number;
  manifoldY: number;
  skillVector: SkillVector;
  categoryScores: CategoryScores;
  similarPlayers: SimilarPlayerPeer[];
}
