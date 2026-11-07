// web/lib/offseasonTypes.ts
// MLB 2026-2027 Off-Season Dynamics Monitor TypeScript Contract Types
// Conforms to MLB Off-Season Dynamics Monitor Blueprint §§ 3 and 6

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
  asOfDate: string; // 'YYYY-MM-DD'
  confidenceTier: 'CONFIRMED';
  origin: Origin;
}

export interface CoverageReport {
  rosters40: 'POPULATED' | 'PARTIAL' | 'UNAVAILABLE';
  contracts: 'POPULATED' | 'PARTIAL' | 'UNAVAILABLE';
  arbitration: 'POPULATED' | 'PARTIAL' | 'UNAVAILABLE';
  cbtPayroll: 'POPULATED' | 'PARTIAL' | 'UNAVAILABLE';
  notes: string;
}

export interface PlayerState {
  playerId: string;
  mlbamId: string;
  displayName: string; // identity, not state
  team: Provenanced<string | null>; // 3-letter abbr; null = unsigned FA
  rosterStatus: Provenanced<
    | '40_MAN'
    | 'ACTIVE_26'
    | '60_DAY_IL'
    | 'NON_ROSTER_INVITEE'
    | 'FREE_AGENT'
    | 'OUTRIGHTED'
  >;
  contractStatus: Provenanced<
    | 'GUARANTEED'
    | 'ARBITRATION_ELIGIBLE'
    | 'PRE_ARBITRATION'
    | 'UNRESTRICTED_FA'
    | 'OPTION_PENDING'
    | 'RETIRED'
  >;
  contractTerms: Provenanced<{
    aav: number;
    throughSeason: number;
    optionYear?: number;
    optionType?: 'CLUB' | 'PLAYER' | 'MUTUAL' | 'VESTING';
  } | null>;
  arbitrationClass: Provenanced<
    | 'SUPER_TWO'
    | 'ARB_1'
    | 'ARB_2'
    | 'ARB_3'
    | 'ARB_4'
    | 'PRE_ARB'
    | 'NONE'
  >;
  serviceYears: Provenanced<number | null>; // e.g. 4.125 = 4 years, 125 days
  qualifyingOfferStatus: Provenanced<
    'INELIGIBLE' | 'TENDERED' | 'ACCEPTED' | 'REJECTED' | 'NONE'
  >;
  winterLeague: Provenanced<{
    league: 'AFL' | 'LIDOM' | 'LBPRC' | 'LMP' | 'LVBP' | 'OTHER';
    team: string;
  } | null>;
  healthStatus: Provenanced<'HEALTHY' | 'REHAB_POST_OP' | 'INJURED' | 'UNKNOWN'>;
}

export interface TeamDraftPick {
  round: number;
  pickType:
    | 'REGULAR'
    | 'COMPENSATION_QO'
    | 'COMPETITIVE_BALANCE_A'
    | 'COMPETITIVE_BALANCE_B';
  originTeam?: string;
}

export interface TeamState {
  teamAbbrev: string;
  displayName: string;
  roster40Count: Provenanced<number>;
  cbtPayrollCommitted: Provenanced<number>; // $M; the attestable figure
  draftPicks2027: Provenanced<TeamDraftPick[]>;
  manager: Provenanced<string | null>;
  generalManager: Provenanced<string | null>;
  presidentOfBaseballOps: Provenanced<string | null>;
  // cbtTaxEstimated and cbtSpaceRemaining are DERIVED from cbtPayrollCommitted
  // and league thresholds - computed on read, never stored or diffed (rule 4)
}

export interface CalendarMilestone {
  date: string | null;
  event: string;
  status: 'Confirmed' | 'Tentative' | 'Unannounced' | 'Suspended';
}

export interface LeagueState {
  seasonYear: 2027;
  cbaStatus: Provenanced<string>;
  leagueOperatingStatus: Provenanced<'NORMAL' | 'TRANSACTION_FREEZE'>;
  freezeStartDate: Provenanced<string | null>; // drives the memo day counter
  cbtBaseThreshold: Provenanced<number | null>; // null for 2027: no CBA governs it yet; origin: 'UNPOPULATED'
  cbtSurchargeThresholds: Provenanced<{
    tier1: number;
    tier2: number;
    tier3: number;
  }>;
  qualifyingOfferAmount: Provenanced<number>; // 23.15 ($23.15M) — confirmed record high
  activeFranchises: Provenanced<number>; // 30
  calendarMilestones: Provenanced<CalendarMilestone[]>;
}

export interface LeagueStateBaseline {
  schemaVersion: '1.0.0';
  asOf: string; // UTC ISO, final out (2026-10-29T03:13:00Z)
  seasonStatus:
    | '2026_WORLD_SERIES_CONCLUDED'
    | '2027_OFFSEASON'
    | '2027_SPRING_TRAINING';
  worldSeriesChampion: 'MIL';
  generatedBy: string; // script name + git sha
  coverage: CoverageReport;
  players: Record<string, PlayerState>;
  teams: Record<string, TeamState>;
  league: LeagueState;
}

export interface OffseasonEditionSummary {
  weekNumber: number;
  publishDate: string;
  isQuietWeek: boolean;
  isFrozenWeek: boolean;
  isArchived: boolean;
}

export type SeasonMode = 'offseason' | 'inseason';


export interface OffseasonMonitorDataset {
  version: '2026-2027.1.0';
  lastPublished: string; // UTC ISO timestamp
  currentWeekNumber: number; // monotonically increasing
  baselineAsOfDate: string;
  elapsedDaysSinceLastPublish: number;
  leagueOperatingStatus: 'NORMAL' | 'TRANSACTION_FREEZE';
  freezeDayCount: number | null; // null when NORMAL
  activePhase:
    | 'Post-World Series Review'
    | 'Option & Qualifying Offer Window'
    | 'Pre-Lockout Surge'
    | 'Transaction Freeze'
    | 'Winter Meetings & Rule 5 Draft'
    | 'Arbitration Exchange & Hearings'
    | 'Spring Training Transition';

  availableEditions: OffseasonEditionSummary[];

  editions: Array<{
    weekNumber: number;
    publishDate: string;
    isQuietWeek: boolean;
    isFrozenWeek: boolean;
    freezeDayCount?: number | null;
    freezeStartDate?: string | null;
    stateOfPlay: string;
    confirmedChanges: Array<{
      date: string;
      team: string;
      playerName: string;
      playerId?: string;
      rosterTier: 'MAJOR_40_MAN' | 'MINOR_LEAGUE';
      transactionType:
        | 'FREE_AGENCY'
        | 'TRADE'
        | 'OPTION_EXERCISED'
        | 'OPTION_DECLINED'
        | 'QUALIFYING_OFFER'
        | 'NON_TENDER'
        | 'WAIVER_CLAIM'
        | 'OUTRIGHT'
        | 'DFA'
        | 'RELEASE'
        | 'CONTRACT_SELECTED'
        | 'FREE_AGENT_SIGNING'
        | 'MAJOR_40_MAN';
      priorValue: string;
      newValue: string;
      contractTerms?: string;
      sourceUrl: string;
    }>;
    reportedClaims: Array<{
      id: string;
      team: string;
      claim: string;
      sourceCategory: 'National Beat' | 'Team Beat Wire' | 'Trade Speculation';
      firstReportedDate: string;
      daysPending: number;
    }>;
    expiredClaims: Array<{
      team: string;
      claim: string;
      sourceCategory: string;
      firstReportedDate: string;
      expiredDate: string;
    }>;
    laborEvents: Array<{ // Block 8; empty array when NORMAL
      date: string;
      event: string;
      parties: string;
      sourceCategory: string;
      outcome: string;
      sourceUrl: string;
    }>;
    upcomingMilestones: Array<{
      date: string | null;
      event: string;
      status: 'Confirmed' | 'Tentative' | 'Unannounced' | 'Suspended';
    }>;
    modelPriorImpact: {
      hasChanges: boolean;
      summary: string;
      adjustedTeams?: Record<
        string,
        {
          deltaWins: number;
          netWarAdded: number;
          rationale: string;
        }
      >;
    };
    winterLeagueNotes: Array<{
      playerName: string;
      mlbTeam: string;
      league: 'AFL' | 'LIDOM' | 'LBPRC' | 'LMP' | 'LVBP' | 'Rehab';
      notes: string;
    }>;
    sourcesVisited: string[];
  }>;

  currentStateSummary: {
    totalConfirmedTransactions: number;
    pendingReportedRumors: number;
    expiredRumorCount: number;
    cbtPayrollLeader: string;
  };
}
