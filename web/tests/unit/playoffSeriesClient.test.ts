import { describe, it, expect } from 'vitest';
import { simulateClientFallback } from '@/components/PlayoffSeriesClient';
import type { TeamPlayoffProfile, PlayoffStarter } from '@/lib/playoffTypes';

function makeStarter(rGS: number, playerName = 'Test Starter'): PlayoffStarter {
  return {
    playerId: 'p1',
    mlbamId: '1',
    playerName,
    rGS,
    projEra: 3.5,
    xFip: 3.5,
    kPct: 0.25,
    bbPct: 0.07,
    role: 'SP',
  };
}

function makeProfile(overrides: Partial<TeamPlayoffProfile> = {}): TeamPlayoffProfile {
  return {
    teamAbbr: 'AAA',
    teamName: 'Alphas',
    fullName: 'Alpha Alphas',
    league: 'AL',
    division: 'AL East',
    regularWins: 95,
    baseElo: 1550,
    tacticalRatings: {
      rotationDepth: 60,
      bullpenLeverage: 55,
      powerIso: 50,
      contactDiscipline: 50,
      defenseFielding: 50,
    },
    starters: [makeStarter(5.0, 'Ace A'), makeStarter(4.5, 'Two A'), makeStarter(4.0, 'Three A'), makeStarter(3.5, 'Four A')],
    relievers: [],
    lineupCore: [],
    ...overrides,
  };
}

describe('simulateClientFallback (issues #127, #128)', () => {
  it('runs cleanly for well-formed input (sanity baseline)', () => {
    const a = makeProfile({ teamAbbr: 'AAA', baseElo: 1560 });
    const b = makeProfile({ teamAbbr: 'BBB', baseElo: 1500 });
    const result = simulateClientFallback(a, b, 'AAA', 7, 500, 0);
    expect(result.gameSchedule).toHaveLength(7);
    expect(result.winProbA + result.winProbB).toBeCloseTo(1, 2);
  });

  // ---- Issue #127: crash guards -----------------------------------------

  it('does not crash when a team has zero listed starters, and labels the fallback', () => {
    const a = makeProfile({ teamAbbr: 'AAA', starters: [] });
    const b = makeProfile({ teamAbbr: 'BBB' });
    expect(() => simulateClientFallback(a, b, 'AAA', 5, 200, 0)).not.toThrow();

    const result = simulateClientFallback(a, b, 'AAA', 5, 200, 0);
    expect(result.gameSchedule.length).toBeGreaterThan(0);
    for (const game of result.gameSchedule) {
      expect(Number.isFinite(game.starterArGS)).toBe(true);
      // @ts-expect-error -- additive diagnostic field, not in the base type
      expect(game.starterAIsFallback).toBe(true);
    }
  });

  it('does not crash when both teams have zero listed starters', () => {
    const a = makeProfile({ teamAbbr: 'AAA', starters: [] });
    const b = makeProfile({ teamAbbr: 'BBB', starters: [] });
    expect(() => simulateClientFallback(a, b, 'AAA', 3, 200, 0)).not.toThrow();
    const result = simulateClientFallback(a, b, 'AAA', 3, 200, 0);
    expect(Number.isFinite(result.winProbA)).toBe(true);
  });

  it('bails out with an insufficient-data result when baseElo is non-finite', () => {
    for (const badElo of [NaN, Infinity, -Infinity, undefined as unknown as number]) {
      const a = makeProfile({ teamAbbr: 'AAA', baseElo: badElo });
      const b = makeProfile({ teamAbbr: 'BBB' });
      expect(() => simulateClientFallback(a, b, 'AAA', 7, 200, 0)).not.toThrow();
      const result = simulateClientFallback(a, b, 'AAA', 7, 200, 0);
      expect(Number.isFinite(result.winProbA)).toBe(true);
      expect(Number.isFinite(result.winProbB)).toBe(true);
      expect(result.gameSchedule).toEqual([]);
      expect(result.tacticalEdges.some((e) => e.title === 'Insufficient Data')).toBe(true);
    }
  });

  it('rejects/flags a seriesLength outside 3/5/7 instead of silently defaulting to 7', () => {
    for (const badLength of [0, 1, 2, 4, 6, 8, -3, NaN]) {
      const a = makeProfile({ teamAbbr: 'AAA' });
      const b = makeProfile({ teamAbbr: 'BBB' });
      expect(() => simulateClientFallback(a, b, 'AAA', badLength, 200, 0)).not.toThrow();
      const result = simulateClientFallback(a, b, 'AAA', badLength, 200, 0);
      expect(result.tacticalEdges.some((e) => e.title === 'Insufficient Data')).toBe(true);
      expect(result.gameSchedule).toEqual([]);
    }
  });

  it('fuzz: zero crash rows across a grid of edge-case inputs', () => {
    const starterVariants: PlayoffStarter[][] = [
      [],
      [makeStarter(5.0)],
      [makeStarter(NaN)],
      [makeStarter(4.0), makeStarter(4.2), makeStarter(4.4), makeStarter(4.6)],
    ];
    const eloVariants = [1500, 1600, NaN, Infinity, -Infinity, 0];
    const lengthVariants = [3, 5, 7, 0, 4, 9, NaN];

    let crashes = 0;
    for (const sA of starterVariants) {
      for (const eloA of eloVariants) {
        for (const len of lengthVariants) {
          const a = makeProfile({ teamAbbr: 'AAA', starters: sA, baseElo: eloA });
          const b = makeProfile({ teamAbbr: 'BBB' });
          try {
            simulateClientFallback(a, b, 'AAA', len, 50, 0);
          } catch {
            crashes += 1;
          }
        }
      }
    }
    expect(crashes).toBe(0);
  });

  // ---- Issue #128: seeded/reproducible simulation ------------------------

  it('produces identical results for the same matchup key and reroll nonce', () => {
    const a = makeProfile({ teamAbbr: 'AAA', baseElo: 1560 });
    const b = makeProfile({ teamAbbr: 'BBB', baseElo: 1500 });
    const r1 = simulateClientFallback(a, b, 'AAA', 7, 2000, 0);
    const r2 = simulateClientFallback(a, b, 'AAA', 7, 2000, 0);
    expect(r1).toEqual(r2);
  });

  it('re-roll (bumping the nonce) changes the result', () => {
    const a = makeProfile({ teamAbbr: 'AAA', baseElo: 1560 });
    const b = makeProfile({ teamAbbr: 'BBB', baseElo: 1500 });
    const r1 = simulateClientFallback(a, b, 'AAA', 7, 2000, 0);
    const r2 = simulateClientFallback(a, b, 'AAA', 7, 2000, 1);
    // Overall win prob is a statistical draw from the same distribution, so
    // it CAN coincidentally match; the per-game schedule's win probabilities
    // are deterministic given the inputs, but avgGames/sweepProb are drawn
    // from the Monte Carlo loop and should differ between seeds in practice.
    expect(r1.avgGames === r2.avgGames && r1.sweepProb === r2.sweepProb).toBe(false);
  });

  it('a different matchup key changes the result even with the same nonce', () => {
    const a = makeProfile({ teamAbbr: 'AAA', baseElo: 1560 });
    const b = makeProfile({ teamAbbr: 'BBB', baseElo: 1500 });
    const c = makeProfile({ teamAbbr: 'CCC', baseElo: 1500 });
    const r1 = simulateClientFallback(a, b, 'AAA', 7, 2000, 0);
    const r2 = simulateClientFallback(a, c, 'AAA', 7, 2000, 0);
    expect(r1.avgGames === r2.avgGames && r1.sweepProb === r2.sweepProb).toBe(false);
  });
});
