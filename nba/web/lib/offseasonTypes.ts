export type TransactionType = 'trade' | 'free_agency' | 'draft';
export type ImpactTier = 'superstar' | 'starter' | 'rotation' | 'depth' | 'prospect';

export interface TransactionAnalysis {
  summary: string;
  offensive_impact: string;
  defensive_impact: string;
  risk_factor: string;
}

export interface DraftPickMeta {
  round: number;
  pick: number;
  school_or_club: string;
}

export interface TradeDetailsMeta {
  counterparts_received?: string[];
  draft_assets?: string[];
}

export interface OffseasonTransaction {
  id: string;
  type: TransactionType;
  date: string;
  player_name: string;
  player_id?: string;
  position: string;
  from_team?: string;
  to_team: string;
  contract_terms?: string;
  draft_pick?: DraftPickMeta;
  trade_details?: TradeDetailsMeta;
  player_bpm: number;
  player_pts: number;
  player_reb: number;
  player_ast: number;
  projected_minutes: number;
  delta_net_rating: number;
  delta_projected_wins: number;
  impact_tier: ImpactTier;
  fit_score: number;
  age: number;
  headline: string;
  analysis: TransactionAnalysis;
}

export interface TeamTransactionSummary {
  name: string;
  type: TransactionType;
  bpm: number;
  pos: string;
}

export interface TeamDraftSummary {
  name: string;
  pick: number;
  school: string;
  archetype: string;
}

export interface TeamOffseasonProfile {
  team: string;
  team_name: string;
  conference: 'East' | 'West';
  division: string;
  baseline_wins: number;
  projected_wins_with_moves: number;
  net_wins_change: number;
  net_bpm_added: number;
  roster_continuity_pct: number;
  grade: 'A+' | 'A' | 'A-' | 'B+' | 'B' | 'B-' | 'C+' | 'C' | 'C-' | 'D+' | 'D';
  strategic_posture: string;
  additions: TeamTransactionSummary[];
  departures: TeamTransactionSummary[];
  draft_picks: TeamDraftSummary[];
  offseason_verdict: string;
}

export interface RookieDraftProfile {
  round?: number;
  pick: number;
  player_name: string;
  original_team?: string;
  team: string;
  position: string;
  school_or_club: string;
  height: string;
  archetype: string;
  projected_bpm_prior: number;
  projected_mpg: number;
  upside_tier: 'Franchise Pillar' | 'Core Starter' | 'Specialist' | 'Developmental';
  trade_note?: string | null;
  strengths: string[];
  swing_skills: string[];
  comp: string;
}
