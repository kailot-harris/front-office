// ==============================================================================
// web/lib/clutchTypes.ts
// Type definitions for True Clutch & Leverage Index Engine (/clutch)
// ==============================================================================

export interface LeverageBreakdown {
  lowPct: number;      // LI < 0.85
  medPct: number;      // 0.85 <= LI < 1.50
  highPct: number;     // 1.50 <= LI < 2.50
  extremePct: number;  // LI >= 2.50
}

export interface SituationSplit {
  pa: number;
  avg: number;
  obp: number;
  slg: number;
  wOBA: number;
  ops: number;
}

export interface FiremanRelieverStats {
  inheritedRunners: number;
  inheritedScored: number;
  strandRatePct: number; // IRS%
  shutdowns: number;    // WPA > +0.06
  meltdowns: number;    // WPA < -0.06
  firemanIndex: number; // Composite fireman rating
}

export interface ClutchProfile {
  playerId: string;
  mlbamId: string;
  playerName: string;
  team: string;
  playerType: 'Batter' | 'Pitcher';
  position: string;
  clutchArchetype: string;
  
  // Core sabermetric leverage ratings
  baseMetricLabel: string;
  baseMetricVal: number;    // e.g. base wOBA or base xFIP
  clutchMetricLabel: string;
  clutchMetricVal: number;  // e.g. high-LI wOBA or high-LI wOBA against
  deltaClutch: number;      // clutch - base (positive is good for batters, negative good for pitchers)
  
  clutchScore: number;      // Tango Clutch = (WPA / pLI) - WPA_base
  wpaTotal: number;         // Total Win Probability Added
  highLiWpa: number;        // WPA generated strictly in LI >= 1.50
  avgLeverageIndex: number; // pLI or gmLI
  
  leverageBreakdown: LeverageBreakdown;
  rispSplit: SituationSplit;
  firemanStats?: FiremanRelieverStats;
}

export interface ClutchCatalog {
  updatedAt: string;
  totalProfiles: number;
  clutchLeaderBatters: string[];
  clutchLeaderPitchers: string[];
  profiles: ClutchProfile[];
}
