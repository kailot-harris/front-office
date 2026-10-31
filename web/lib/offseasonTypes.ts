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

export type Origin =
  | 'SEASON_END_PULL'
  | 'TRANSACTION_WIRE'
  | 'TEAM_RELEASE'
  | 'FILED_CONTRACT'
  | 'BACKFILL'
  | 'UNPOPULATED';

export interface Provenanced<T> {
  value: T;
  sourceUrl: string | null;
  asOfDate: string;
  confidenceTier: 'CONFIRMED';
  origin: Origin;
}

export interface CoverageReport {
  rosters: 'POPULATED' | 'PARTIAL' | 'UNAVAILABLE';
  contracts: 'POPULATED' | 'PARTIAL' | 'UNAVAILABLE';
  serviceYears: 'POPULATED' | 'PARTIAL' | 'UNAVAILABLE';
  capSheet: 'POPULATED' | 'PARTIAL' | 'UNAVAILABLE';
  notes: string;
}

export interface PlayerState {
  playerId: string;
  displayName: string;
  team: Provenanced<string | null>;
  contractStatus: Provenanced<
    | 'UNDER_CONTRACT'
    | 'UNRESTRICTED_FA'
    | 'RESTRICTED_FA'
    | 'RESERVED'
    | 'UNSIGNED'
    | 'UNKNOWN'
  >;
  contractThroughSeason: Provenanced<number | null>;
  serviceYears: Provenanced<number | null>;
  coreEligible: Provenanced<boolean | null>;
  designation: Provenanced<'NONE' | 'CORED' | 'QUALIFYING_OFFER' | 'UNKNOWN'>;
  winterLeague: Provenanced<{ league: string; team: string } | null>;
  availabilityStatus: Provenanced<'ACTIVE' | 'REHAB' | 'OUT' | 'UNKNOWN'>;
}

export interface TeamDraftPick {
  round: 1 | 2 | 3;
  originTeam: string;
}

export interface TeamState {
  teamAbbrev: string;
  displayName: string;
  rosterCount: Provenanced<number>;
  capCommitted: Provenanced<number | null>;
  draftPicks2027: Provenanced<TeamDraftPick[]>;
  headCoach: Provenanced<string | null>;
  generalManager: Provenanced<string | null>;
}

export interface CalendarMilestone {
  date: string | null;
  event: string;
  status: 'Confirmed' | 'Tentative' | 'Unannounced';
}

export interface LeagueState {
  seasonYear: 2027;
  cbaStatus: Provenanced<string>;
  salaryCapCeiling: Provenanced<number | null>;
  coreEligibilityRule: Provenanced<string>;
  activeFranchises: Provenanced<number>;
  calendarMilestones: Provenanced<CalendarMilestone[]>;
}

export interface LeagueStateBaseline {
  schemaVersion: '1.0.0';
  asOf: string;
  seasonStatus: '2026_FINALS_CONCLUDED' | '2026_FINALS_IN_PROGRESS' | '2027_OFFSEASON' | '2027_CAMP_OPEN';
  finalsChampion: string;
  generatedBy: string;
  coverage: CoverageReport;
  players: Record<string, PlayerState>;
  teams: Record<string, TeamState>;
  league: LeagueState;
}

// ==============================================================================
// 2026-2027 Off-Season Dynamics Monitor Dataset (Issue #122 / Blueprint §6)
// ==============================================================================

export interface ConfirmedChange {
  date: string;
  entityId: string;
  entityName: string;
  field: string;
  priorValue: string;
  newValue: string;
  sourceUrl: string;
}

export interface ReportedClaim {
  id: string;
  entityName: string;
  claim: string;
  sourceCategory: 'National Beat' | 'Team Beat Wire' | 'Trade Speculation';
  firstReportedDate: string;
  daysPending: number;
}

export interface ExpiredClaim {
  entityName: string;
  claim: string;
  sourceCategory: string;
  firstReportedDate: string;
  expiredDate: string;
}

export interface UpcomingMilestone {
  date: string | null;
  event: string;
  status: 'Confirmed' | 'Tentative';
}

export interface ModelPriorImpact {
  hasChanges: boolean;
  summary: string;
  adjustedTeams?: Record<string, { deltaNetRating: number; rationale: string }>;
}

export interface WinterLeagueNote {
  playerName: string;
  wnbaTeam: string;
  league: 'Unrivaled' | 'EuroLeague' | 'Rehab';
  healthStatus: string;
}

export interface OffseasonEdition {
  weekNumber: number;
  publishDate: string;
  isQuietWeek: boolean;
  stateOfPlay: string;
  memoMarkdown: string;
  confirmedChanges: ConfirmedChange[];
  reportedClaims: ReportedClaim[];
  expiredClaims: ExpiredClaim[];
  upcomingMilestones: UpcomingMilestone[];
  modelPriorImpact: ModelPriorImpact;
  winterLeagueNotes: WinterLeagueNote[];
  sourcesVisited: string[];
}

export interface CurrentStateSummary {
  totalConfirmedTransactions: number;
  pendingReportedRumors: number;
  expiredRumorCount: number;
  cbaLaborStatus: string;
}

export interface OffseasonMonitorDataset {
  version: '2026-2027.1.0';
  lastPublished: string;
  currentWeekNumber: number;
  baselineAsOfDate: string;
  elapsedDaysSinceLastPublish: number;
  activePhase:
    | 'Post-Finals Review'
    | 'Draft Lottery & Overseas Tracking'
    | 'Qualifying Offers & Core Window'
    | 'Free Agency Signings'
    | 'NCAA Tournament & Draft Prep'
    | '2027 Draft'
    | 'Training Camp Transition';
  editions: OffseasonEdition[];
  currentStateSummary: CurrentStateSummary;
}



