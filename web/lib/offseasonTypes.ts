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

// ==============================================================================
// League State Baseline S0 Contract (Issue #117 / Blueprint §3)
// ==============================================================================

export interface Provenanced<T> {
  value: T;
  source?: string;
  origin?: 'POPULATED' | 'UNAVAILABLE' | 'UNPOPULATED' | 'POSTSEASON_CONCLUDED';
  recorded_at?: string;
}

export interface CoverageReport {
  rosters: 'POPULATED' | 'UNAVAILABLE';
  capSheet: 'POPULATED' | 'UNAVAILABLE';
  contracts: 'POPULATED' | 'UNAVAILABLE';
  serviceYears: 'POPULATED' | 'UNAVAILABLE';
}

export interface BaselinePlayerContract {
  player_id: string;
  player_name: string;
  position: string;
  salary_2026: number;
  salary_2027: number;
  contract_type: string;
  protected: boolean;
  free_agent_year: number;
}

export interface BaselineTeamProfile {
  team_abbrev: string;
  team_name: string;
  conference: string;
  total_payroll_2026: number;
  total_payroll_2027: number;
  hard_salary_cap: number;
  cap_floor: number;
  cap_space_2026: number;
  projected_cap_space_2027: number;
  roster_count: number;
  twelfth_spot_available: boolean;
  cba_tier: string;
  hard_cap_crunch_index: number;
  core_player: string;
  roster: BaselinePlayerContract[];
}

export interface BaselinePlayerProfile {
  player_id: string;
  player_name: string;
  team: string;
  position: string;
  age: number;
  minutes_per_game: number;
  bpm: number;
  pts: number;
  reb: number;
  ast: number;
  net_rating: number;
}

export interface CalendarMilestone {
  date: string;
  event: string;
}

export interface LeagueStateBaseline {
  asOf: string;
  seasonStatus: '2026_FINALS_CONCLUDED' | '2026_FINALS_IN_PROGRESS';
  finalsChampion: string;
  coverageReport: CoverageReport;
  provenance: {
    source: string;
    origin: string;
    generator: string;
    recorded_at: string;
  };
  cbaConstants: {
    hardSalaryCap: number;
    capFloor: number;
    supermaxSalary: number;
    vetMaxSalary: number;
    vetMinSalary: number;
    rookieMinSalary: number;
  };
  draftPicks2027: unknown[];
  calendarMilestones: CalendarMilestone[];
  teams: Record<string, BaselineTeamProfile>;
  players: Record<string, BaselinePlayerProfile>;
}

