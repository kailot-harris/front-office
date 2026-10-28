// ==============================================================================
// cbaTypes.ts
// Type definitions for CBA Salary Cap, Apron & Luxury Tax Architect
// ==============================================================================

export type CbaTier =
  | 'Under Cap Room'
  | 'Over Cap (Non-Taxpayer)'
  | 'Taxpayer (Below Apron 1)'
  | 'First Apron Team'
  | 'Second Apron Restricted';

export interface PlayerContract {
  playerId: number;
  playerName: string;
  position: string;
  salary2026: number;      // e.g. 48.5 ($M)
  salary2027: number;      // e.g. 52.3 ($M) or 0 if expiring
  salary2028: number;      // e.g. 56.1 ($M) or 0 if expiring
  contractType: 'Guaranteed' | 'Player Option' | 'Team Option' | 'Qualifying Offer' | 'Two-Way';
  notes?: string;
}

export interface CbaHandcuffs {
  frozenPick7Years: boolean;       // True if > 2nd apron
  noSalaryAggregation: boolean;    // Cannot combine 2+ outgoing salaries in trades
  noCashInTrades: boolean;         // Cannot send cash in trades
  noTpmle: boolean;                // Loss of Taxpayer Mid-Level Exception
  tradeSalaryMatchingPct: number;  // 100% if > 1st apron, 125% or 200% under cap
  signAndTradeHardCapped: boolean; // Triggered if acquiring S&T player
}

export interface FranchiseCbaProfile {
  teamAbbr: string;
  teamName: string;
  conference: 'East' | 'West';
  totalPayroll2026: number;        // in millions (e.g. 192.4)
  totalPayroll2027: number;
  totalPayroll2028: number;
  salaryCap: number;               // 140.6
  luxuryTaxThreshold: number;      // 170.8
  firstApron: number;              // 178.1
  secondApron: number;             // 188.9
  capSpace2026: number;            // max(0, cap - payroll)
  taxSpace2026: number;            // tax - payroll (negative = in tax)
  firstApronSpace2026: number;     // apron1 - payroll
  secondApronSpace2026: number;    // apron2 - payroll
  cbaTier: CbaTier;
  isRepeaterTax: boolean;
  luxuryTaxBill: number;           // in millions
  totalFinancialCommitment: number;// payroll + tax bill
  projectedCapSpace2027: number;   // cap room in 2027 offseason
  projectedCapSpace2028: number;   // cap room in 2028 offseason
  handcuffs: CbaHandcuffs;
  contracts: PlayerContract[];
}

export interface CbaLeagueOverview {
  /**
   * UTC ISO-8601 stamp written by the R exporter for publish_web.R's assertion
   * F. Optional because payloads written before the stamp landed do not carry
   * it; declared here because tests/contracts/types-vs-data.test.ts fails any
   * payload key absent from this interface, so an undeclared stamp would turn
   * the contract suite -- and therefore the fatal publish gate -- red the first
   * time a stamped payload was written.
   */
  generated_at: string;
  /** League year in full-year form, e.g. '2026-2027'. */
  season: string;
  /** Where the cap/apron thresholds were cross-checked. */
  cbaThresholdSources?: string;
  salaryCap: number;
  luxuryTaxThreshold: number;
  firstApron: number;
  secondApron: number;
  averagePayroll: number;
  totalLeagueTaxRevenue: number;
  secondApronTeamCount: number;
  firstApronTeamCount: number;
  taxTeamCount: number;
  capRoomTeamCount: number;
  teams: FranchiseCbaProfile[];
}
