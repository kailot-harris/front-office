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
  frozenPick7Years: boolean | null;       // True if > 2nd apron
  noSalaryAggregation: boolean | null;    // Cannot combine 2+ outgoing salaries in trades
  noCashInTrades: boolean | null;         // Cannot send cash in trades
  noTpmle: boolean | null;                // Loss of Taxpayer Mid-Level Exception
  tradeSalaryMatchingPct: number | null;  // 100% if > 1st apron, 125% or 200% under cap
  signAndTradeHardCapped: boolean | null; // Triggered if acquiring S&T player
}

export interface FranchiseCbaProfile {
  teamAbbr: string;
  teamName: string;
  conference: 'East' | 'West';
  totalPayroll2026: number | null;        // in millions (e.g. 192.4), null if BBRef cache unavailable
  totalPayroll2027: number | null;
  totalPayroll2028: number | null;
  salaryCap: number;                      // 165.0
  luxuryTaxThreshold: number;             // 200.4
  firstApron: number;                     // 209.0
  secondApron: number;                    // 221.7
  capSpace2026: number | null;            // max(0, cap - payroll)
  taxSpace2026: number | null;            // tax - payroll (negative = in tax)
  firstApronSpace2026: number | null;     // apron1 - payroll
  secondApronSpace2026: number | null;    // apron2 - payroll
  cbaTier: CbaTier | null;
  isRepeaterTax: boolean;
  luxuryTaxBill: number | null;           // in millions
  totalFinancialCommitment: number | null;// payroll + tax bill
  projectedCapSpace2027: number | null;   // cap room in 2027 offseason
  projectedCapSpace2028: number | null;   // cap room in 2028 offseason
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
  averagePayroll: number | null;
  totalLeagueTaxRevenue: number | null;
  secondApronTeamCount: number | null;
  firstApronTeamCount: number | null;
  taxTeamCount: number | null;
  capRoomTeamCount: number | null;
  teams: FranchiseCbaProfile[];
}
