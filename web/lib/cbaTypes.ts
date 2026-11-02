// ==============================================================================
// cbaTypes.ts
// Type definitions for WNBA CBA structural cap constants & real roster facts
//
// NOTE (2026-11-02, WNBA_analytics#128): this used to also carry a
// WnbaPlayerContract type and per-franchise totalPayroll/capSpace/cbaTier/
// hardCapCrunchIndex/projectedCapSpace fields. All of that was generated from
// unseeded runif() draws in build_cba_cap_dataset.R with no real WNBA
// contract/salary data behind it, and has been removed end-to-end (see that
// script's provenance comment for what was checked and why). Do not
// reintroduce those fields here unless build_cba_cap_dataset.R gains a real
// source for them.
// ==============================================================================

export interface WnbaFranchiseCbaProfile {
  teamAbbr: string;
  teamName: string;
  conference: string;
  hardSalaryCap: number; // 1.52 ($1.52M)
  capFloor: number;      // 1.368 ($1.368M)
  rosterCount: number;   // real count of rostered players
  corePlayer: string;    // deterministic lookup against a fixed editorial list, or "Unassigned"
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
  generated_at: string;
  season: string;
  hardSalaryCap: number;
  capFloor: number;
  supermaxSalary: number;
  vetMaxSalary: number;
  vetMinSalary: number;
  rookieMinSalary: number;
  teams: WnbaFranchiseCbaProfile[];
}
