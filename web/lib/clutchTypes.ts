// ==============================================================================
// web/lib/clutchTypes.ts
// Type definitions for True Clutch & Leverage Index Engine (/clutch)
// ==============================================================================

export interface LeverageBreakdown {
  lowPct: number | null;      // LI < 0.85
  medPct: number | null;      // 0.85 <= LI < 1.50
  highPct: number | null;     // 1.50 <= LI < 2.50
  extremePct: number | null;  // LI >= 2.50
}

export interface SituationSplit {
  pa: number | null;
  avg: number | null;
  obp: number | null;
  slg: number | null;
  wOBA: number | null;
  ops: number | null;
}

export interface FiremanRelieverStats {
  inheritedRunners: number;
  inheritedScored: number;
  strandRatePct: number; // IRS%
  shutdowns: number | null;    // WPA > +0.06
  meltdowns: number | null;    // WPA < -0.06
  firemanIndex: number | null; // Composite fireman rating
}

export interface ClutchProfile {
  playerId: string;
  mlbamId: string;
  playerName: string;
  team: string;
  playerType: 'Batter' | 'Pitcher';
  position: string | null;
  clutchArchetype: string;
  
  // Core sabermetric leverage ratings
  baseMetricLabel: string;
  baseMetricVal: number | null;    // e.g. base wOBA or base xFIP
  clutchMetricLabel: string;
  clutchMetricVal: number | null;  // e.g. high-LI wOBA or high-LI wOBA against
  deltaClutch: number | null;      // clutch - base (positive is good for batters, negative good for pitchers)
  
  clutchScore: number;      // Tango Clutch = (WPA / pLI) - WPA_base
  wpaTotal: number | null;         // Total Win Probability Added
  highLiWpa: number | null;        // WPA generated strictly in LI >= 1.50
  avgLeverageIndex: number | null; // pLI or gmLI
  
  leverageBreakdown: LeverageBreakdown;
  rispSplit: SituationSplit;
  firemanStats?: FiremanRelieverStats;
}

export interface ClutchCatalog {
  generated_at: string;
  updatedAt: string;
  totalProfiles: number;
  clutchLeaderBatters: string[];
  clutchLeaderPitchers: string[];
  profiles: ClutchProfile[];
}
