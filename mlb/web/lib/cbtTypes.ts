// ==============================================================================
// web/lib/cbtTypes.ts
// Type definitions for MLB Competitive Balance Tax (CBT) & Payroll Architect (/cap-sheet)
// ==============================================================================

export type CbtTier =
  | 'Under CBT Threshold'
  | 'Tier 1 Surcharge ($244M-$264M)'
  | 'Tier 2 Draft Penalty ($264M-$284M)'
  | 'Tier 3 Cohen Tax ($284M-$304M)'
  | 'Tier 4 Mega Tax (> $304M)';

export interface MlbPlayerContract {
  playerId: string;
  playerName: string;
  position: string;
  salary2026: number;      // in millions (e.g. 40.0)
  salary2027: number;      // in millions or 0 if expiring
  salary2028: number;      // in millions or 0 if expiring
  contractType: 'Guaranteed' | 'Player Option' | 'Club Option' | 'Arbitration' | 'Pre-Arb';
  projectedWar: number;
  surplusValue: number;    // (WAR * $8.5M) - salary2026
  notes?: string;
}

export interface CbtPenalties {
  draftPickDrop10: boolean;            // Triggered if payroll > $284M (Tier 2)
  internationalPoolReduction: boolean; // Triggered if payroll > $304M (Tier 3)
  taxRateDescription: string;         // e.g. "80% (1st time)" or "110% (Repeater)"
  revenueShareEligible: boolean;      // True if below CBT line
}

export interface FranchiseCbtProfile {
  teamAbbr: string;
  teamName: string;
  fullName: string;
  league: 'AL' | 'NL';
  division: string;
  
  // Payroll figures in Millions
  payroll2026: number;
  payroll2027: number;
  payroll2028: number;
  
  baseThreshold: number;   // $244.0M
  tier1Threshold: number;  // $264.0M
  tier2Threshold: number;  // $284.0M
  tier3Threshold: number;  // $304.0M
  
  cbtSpace2026: number;    // max(0, base - payroll)
  cbtTaxBill: number;      // in Millions
  totalCommitment: number; // payroll2026 + cbtTaxBill
  
  cbtTier: CbtTier;
  isRepeater: boolean;
  penalties: CbtPenalties;
  
  contracts: MlbPlayerContract[];
}

export interface CbtLeagueOverview {
  season: string;
  baseThreshold: number;
  tier1Threshold: number;
  tier2Threshold: number;
  tier3Threshold: number;
  totalLeaguePayroll: number;
  totalLuxuryTaxCollected: number;
  teams: FranchiseCbtProfile[];
}
