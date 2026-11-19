/** Nearest current-season (2025-26) peer by cosine similarity of skill vectors. */
export interface PeerComp {
  compName: string;
  playerId: string;
  era: string;
  archetype: string;
  position: string;
  similarityPct: number;
  keySharedTrait: string;
}

/** Each dimension is null when its inputs are unavailable (no box-score row, RAPM or defensive metric). */
export interface SkillVector {
  rim_fg: number | null;
  dunks: number | null;
  paint_touches: number | null;
  cns_3p: number | null;
  pullup_3p: number | null;
  ft_pct: number | null;
  ast_pct: number | null;
  tov_control: number | null;
  drive_ast: number | null;
  switchability: number | null;
  rim_protection: number | null;
  perimeter_havoc: number | null;
  d_rapm: number | null;
  oreb: number | null;
  dreb: number | null;
}

export interface CategoryScores {
  /** null when every dimension in the category is null (player has no 2025-26 box-score row) */
  finishing: number | null;
  shooting: number | null;
  playmaking: number | null;
  defense: number | null;
  rebounding: number | null;
}

export interface PlayerDnaProfile {
  playerId: string;
  playerName: string;
  team: string;
  position: string;
  /** null when the player has no 2025-26 box-score row */
  archetype: string | null;
  projPts: number;
  projReb: number;
  projAst: number;
  projMpg: number;
  overallRating: number | null;
  /** null when any contributing category is null */
  manifoldX: number | null;
  manifoldY: number | null;
  skillVector: SkillVector;
  categoryScores: CategoryScores;
  peerComps: PeerComp[];
}
