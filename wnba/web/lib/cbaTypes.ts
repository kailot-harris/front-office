// ==============================================================================
// cbaTypes.ts
// Type definitions for WNBA Hard Salary Cap, Rookie Scale & Roster Crunch
// ==============================================================================

export type WnbaCbaTier =
  | 'Hard Cap Squeeze (11 Roster)'
  | 'Cap Compliant (12 Roster)'
  | 'Flexible Cap Room'
  | 'Maximum Cap Space';

export interface WnbaPlayerContract {
  playerId: string;
  playerName: string;
  position: string;
  salary2026: number; // in $M (e.g. 0.2445 = $244,500)
  salary2027: number;
  salary2028: number;
  contractType: string;
  notes: string;
}

export interface WnbaFranchiseCbaProfile {
  teamAbbr: string;
  teamName: string;
  conference: string;
  totalPayroll2026: number;
  totalPayroll2027: number;
  totalPayroll2028: number;
  hardSalaryCap: number; // 1.52 ($1.52M)
  capFloor: number;      // 1.368 ($1.368M)
  capSpace2026: number;
  rosterCount: number;   // 11 or 12
  twelfthSpotAvailable: boolean;
  cbaTier: WnbaCbaTier;
  corePlayer: string;
  projectedCapSpace2027: number;
  projectedCapSpace2028: number;
  hardCapCrunchIndex: number; // percentage of cap consumed (e.g. 99.7)
  contracts: WnbaPlayerContract[];
}

export interface WnbaCbaLeagueOverview {
  /**
   * UTC ISO-8601 stamp written by the R exporter for publish_web.R's assertion
   * F. Optional because payloads written before the stamp landed do not carry
   * it; declared here because tests/contracts/types-vs-data.test.ts fails any
   * payload key absent from this interface, so an undeclared stamp would turn
   * the contract suite -- and therefore the fatal publish gate -- red the first
   * time a stamped payload was written. Distinct from the camelCase
   * `generatedAt` some of these payloads already carry: assertion F only ever
   * matches the snake_case key.
   */
  generated_at?: string;
  season: string;
  hardSalaryCap: number;
  capFloor: number;
  supermaxSalary: number;
  vetMaxSalary: number;
  vetMinSalary: number;
  rookieMinSalary: number;
  averagePayroll: number;
  hardCapSqueezeTeamCount: number;
  twelvePlayerTeamCount: number;
  maxCapSpaceTeamCount: number;
  teams: WnbaFranchiseCbaProfile[];
}
