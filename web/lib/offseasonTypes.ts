export interface OffseasonTransaction {
  id: string;
  type: 'trade' | 'free_agency' | 'extension' | 'expansion_draft';
  date: string;
  player_name: string;
  player_id?: string;
  position: string;
  from_team?: string | null;
  to_team: string;
  contract_terms: string;
  trade_details?: {
    counterparts_received?: string[];
    draft_assets?: string;
  };
  player_bpm: number;
  player_pts: number;
  player_reb: number;
  player_ast: number;
  projected_minutes: number;
  delta_net_rating: number;
  delta_projected_wins: number;
  impact_tier: 'superstar' | 'all_star' | 'starter' | 'rotation';
  fit_score: number;
  age: number;
  headline: string;
  analysis: {
    summary: string;
    offensive_impact: string;
    defensive_impact: string;
    risk_factor: string;
  };
}

export interface OffseasonTeamAddition {
  name: string;
  type: string;
  bpm: number;
  pos: string;
}

export interface OffseasonTeamDeparture {
  name: string;
  type: string;
  bpm: number;
  pos: string;
}

export interface OffseasonTeamDraftPick {
  name: string;
  pick: number;
  school: string;
  archetype: string;
}

export interface OffseasonTeamProfile {
  team: string;
  team_name: string;
  conference: string;
  division: string;
  baseline_wins: number;
  projected_wins_with_moves: number;
  net_wins_change: number;
  net_bpm_added: number;
  roster_continuity_pct: number;
  grade: string;
  strategic_posture: string;
  additions: OffseasonTeamAddition[];
  departures: OffseasonTeamDeparture[];
  draft_picks: OffseasonTeamDraftPick[];
  offseason_verdict: string;
}

export interface OffseasonDraftProspect {
  pick: number;
  player_name: string;
  team: string;
  position: string;
  school_or_club: string;
  height: string;
  archetype: string;
  projected_bpm_prior: number;
  projected_mpg: number;
  upside_tier: string;
  trade_note?: string;
  strengths: string[];
  swing_skills: string[];
  comp: string;
}
