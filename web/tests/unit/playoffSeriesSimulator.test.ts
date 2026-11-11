import { describe, expect, it } from 'vitest';
import { simulateClientSeries, playoffSeriesSeedKey } from '@/components/PlayoffSeriesClient';
import type { TeamPlayoffProfile } from '@/lib/playoffTypes';

/**
 * Regression coverage for #111: a missing or non-numeric playoffNetRtg used
 * to make every simulated-game probability NaN. Since `Math.random() < NaN`
 * is always false, the series simulator silently reported the opponent
 * winning every single game -- a false 100% result -- instead of surfacing
 * that the input data was missing.
 *
 * simulateClientSeries always runs a 2-2-1-1-1 best-of-7 series (the
 * component is fixed-format; it has no bo3/bo5 mode), so this suite exercises
 * the guard against every invalid-input shape the function can receive
 * rather than against alternate series lengths.
 */

function baseProfile(overrides: Partial<TeamPlayoffProfile> = {}): TeamPlayoffProfile {
  return {
    teamAbbr: 'AAA',
    teamName: 'Team AAA',
    conference: 'East',
    regularWins: 50,
    regularNetRtg: 5,
    playoffNetRtg: 5,
    top3TalentBump: 2,
    tacticalRatings: {
      perimeterCreation: 50,
      dropVulnerability: 50,
      interiorDominance: 50,
      switchability: 50,
      clutchExecution: 50,
    },
    rotation: [],
    ...overrides,
  };
}

const VALID_OPPONENT = baseProfile({ teamAbbr: 'BBB', teamName: 'Team BBB', playoffNetRtg: -3 });

describe('simulateClientSeries missing-data guard (#111)', () => {
  const invalidValues: Array<{ label: string; value: unknown }> = [
    { label: 'undefined', value: undefined },
    { label: 'NaN', value: NaN },
    { label: 'string', value: 'DNP' },
  ];

  for (const { label, value } of invalidValues) {
    it(`flags insufficient data instead of a probability when teamA.playoffNetRtg is ${label}`, () => {
      const teamA = baseProfile({ playoffNetRtg: value as number });
      const result = simulateClientSeries(teamA, VALID_OPPONENT, teamA.teamAbbr);

      expect(result.insufficientData).toBe(true);
      expect(typeof result.insufficientDataReason).toBe('string');
      // Never a fake probability (e.g. the opponent silently "winning" 100%).
      expect(result.winProbA).not.toBeNaN();
      expect(result.winProbB).not.toBeNaN();
      expect(result.winProbB).not.toBe(1);
      expect(result.winProbA).not.toBe(1);
    });

    it(`flags insufficient data instead of a probability when teamB.playoffNetRtg is ${label}`, () => {
      const teamB = baseProfile({ teamAbbr: 'CCC', teamName: 'Team CCC', playoffNetRtg: value as number });
      const result = simulateClientSeries(VALID_OPPONENT, teamB, VALID_OPPONENT.teamAbbr);

      expect(result.insufficientData).toBe(true);
      expect(typeof result.insufficientDataReason).toBe('string');
      expect(result.winProbA).not.toBeNaN();
      expect(result.winProbB).not.toBeNaN();
      expect(result.winProbA).not.toBe(1);
      expect(result.winProbB).not.toBe(1);
    });
  }

  it('still produces a real, non-flagged probability when both ratings are finite', () => {
    const teamA = baseProfile();
    const result = simulateClientSeries(teamA, VALID_OPPONENT, teamA.teamAbbr);

    expect(result.insufficientData).toBeFalsy();
    expect(result.winProbA).toBeGreaterThan(0);
    expect(result.winProbA).toBeLessThan(1);
    expect(result.winProbA + result.winProbB).toBeCloseTo(1, 1);
  });
});

/**
 * Regression coverage for #128: the client simulator called `Math.random()`
 * directly, so the same matchup gave a different answer every click and
 * results could not be reproduced or shared. simulateClientSeries now seeds
 * a mulberry32 PRNG from a hash of both team IDs + series length (+ an
 * explicit reroll counter), so the same matchup/reroll-nonce pair always
 * reproduces the same result, and a different reroll nonce reliably changes
 * it ("re-roll" in the UI).
 */
describe('simulateClientSeries deterministic seeding (#128)', () => {
  const teamA = baseProfile({ teamAbbr: 'OKC', teamName: 'Team OKC', playoffNetRtg: 8 });
  const teamB = baseProfile({ teamAbbr: 'BOS', teamName: 'Team BOS', playoffNetRtg: 3 });

  it('produces identical results for the same matchup + reroll nonce across repeated calls', () => {
    const first = simulateClientSeries(teamA, teamB, 'OKC', 2000, 0);
    const second = simulateClientSeries(teamA, teamB, 'OKC', 2000, 0);
    expect(second).toEqual(first);
  });

  it('is deterministic regardless of call order / other matchups run in between', () => {
    const first = simulateClientSeries(teamA, teamB, 'OKC', 2000, 0);
    // Run an unrelated matchup in between to confirm no shared/global RNG state leaks.
    simulateClientSeries(VALID_OPPONENT, teamB, VALID_OPPONENT.teamAbbr, 2000, 5);
    const second = simulateClientSeries(teamA, teamB, 'OKC', 2000, 0);
    expect(second).toEqual(first);
  });

  it('changes the result when the reroll nonce advances (the "re-roll" control)', () => {
    const base = simulateClientSeries(teamA, teamB, 'OKC', 2000, 0);
    const rerolled = simulateClientSeries(teamA, teamB, 'OKC', 2000, 1);
    // winProbA is a coarse aggregate that can coincidentally match; compare
    // the full per-game-count distribution, which is astronomically unlikely
    // to be byte-identical across two independent seeds.
    expect(rerolled.gameDistributions).not.toEqual(base.gameDistributions);
  });

  it('derives different seed keys for different reroll nonces, same matchup', () => {
    const keyA = playoffSeriesSeedKey('OKC', 'BOS', 'OKC', 7, 0);
    const keyB = playoffSeriesSeedKey('OKC', 'BOS', 'OKC', 7, 1);
    expect(keyA).not.toBe(keyB);
  });
});
