export interface OffseasonTransaction {
  id: string;
  type: 'trade' | 'free_agency' | 'waiver' | 'release' | 'waiver_claim';
  date: string;
  player_name: string;
  player_id?: string;
  position: string;
  from_team?: string | null;
  to_team: string;
  contract_terms: string;
  headline: string;
  source_url: string;
}

export interface OffseasonTeamMove {
  name: string;
  type: string;
  pos: string;
}

export interface OffseasonTeamProfile {
  team: string;
  team_name: string;
  conference: string;
  division: string;
  baseline_wins: number;
  projected_wins_with_moves: number;
  net_wins_change: number;
  roster_count: number;
  confirmed_transactions_count: number;
  additions: OffseasonTeamMove[];
  departures: OffseasonTeamMove[];
  draft_picks: Record<string, unknown>[];
}

/** Draft-order slot only; no prospect data (no real scouting feed). */
export interface OffseasonDraftProspect {
  pick: number;
  team: string;
  team_name: string;
  conference: string;
  proj_wins: number;
  proj_losses: number;
  win_pct: number;
  prospect_status: 'UNPOPULATED_NO_SCOUTING_FEED';
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

export enum OffseasonChangeType {
  SIGNING = 'SIGNING',
  WAIVER = 'WAIVER',
  RELEASE = 'RELEASE',
  TRADE = 'TRADE',
  WAIVER_CLAIM = 'WAIVER_CLAIM',
  CONTRACT_OFFER = 'CONTRACT_OFFER',
  OFFER_MATCH = 'OFFER_MATCH',
  ROSTER_STATUS = 'ROSTER_STATUS',
  FRONT_OFFICE = 'FRONT_OFFICE',
  CORE_DESIGNATION = 'CORE_DESIGNATION',
  RESERVED_PLAYER = 'RESERVED_PLAYER',
  QUALIFYING_OFFER = 'QUALIFYING_OFFER',
  PRIORITIZATION = 'PRIORITIZATION',
  RETIREMENT = 'RETIREMENT',
  SUSPENSION = 'SUSPENSION',
  DRAFT_RIGHTS = 'DRAFT_RIGHTS',
  EXPANSION_DRAFT = 'EXPANSION_DRAFT',
  UNCLASSIFIED = 'UNCLASSIFIED',
}

export interface ConfirmedChange {
  date: string;
  entityId: string;
  entityName: string;
  field: string;
  priorValue: string;
  newValue: string;
  sourceUrl: string;
  changeType?: OffseasonChangeType;
  team?: string;
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

// Issue #156: optional weekly beat-feed sentiment summary. Absent on editions
// published before #156 and on any week where scoring was unavailable.
export interface MediaSentimentWord {
  word: string;
  n: number;
}

export interface MediaSentimentHeadline {
  headline: string;
  score: number;
  rawScore?: number;
  words?: number;
  sourceId?: string;
  url?: string | null;
  bodyScraped?: boolean;
}

export interface MediaSentimentPulse {
  available: boolean;
  reason?: string | null;
  articleCount: number;
  beatItemsSeen?: number;
  meanSentiment?: number | null;
  scrapedCount: number;
  fallbackCount: number;
  mostPositive?: MediaSentimentHeadline | null;
  mostNegative?: MediaSentimentHeadline | null;
  wordBreakdown?: {
    available: boolean;
    reason?: string | null;
    positive: MediaSentimentWord[];
    negative: MediaSentimentWord[];
    matchedWords?: number;
  };
  lexicon?: string;
  method?: string;
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
  mediaSentimentPulse?: MediaSentimentPulse;
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



