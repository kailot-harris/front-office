import { describe, it, expect } from 'vitest';
import { simulateClientSeries, mulberry32, hashSeedString, matchupSeedKey } from '@/components/PlayoffSeriesClient';
import type { TeamPlayoffProfile } from '@/lib/playoffTypes';

// Issue #128: the simulator used to call Math.random() directly, so the same
// matchup produced a different series outcome on every click and results
// could not be reproduced or shared. These tests prove the mulberry32-seeded
// replacement: the same matchup key always replays identical results, and
// advancing the reroll nonce ("re-roll") produces a different, but still
// deterministic, result.

function makeTeam(overrides: Partial<TeamPlayoffProfile> = {}): TeamPlayoffProfile {
  return {
    teamAbbr: 'NY',
    teamName: 'New York Liberty',
    conference: 'East',
    regularWins: 30,
    regularNetRtg: 8.5,
    playoffNetRtg: 7.2,
    top3TalentBump: 4.1,
    tacticalRatings: {
      perimeterCreation: 60,
      dropVulnerability: 50,
      interiorDominance: 55,
      clutchExecution: 58,
    },
    rotation: [],
    ...overrides,
  };
}

const TEAM_A = makeTeam();
const TEAM_B = makeTeam({ teamAbbr: 'MIN', teamName: 'Minnesota Lynx', conference: 'West' });

describe('mulberry32 seeded PRNG', () => {
  it('is deterministic for a given seed', () => {
    const rngA = mulberry32(12345);
    const rngB = mulberry32(12345);
    const seqA = [rngA(), rngA(), rngA()];
    const seqB = [rngB(), rngB(), rngB()];
    expect(seqA).toEqual(seqB);
  });

  it('produces different streams for different seeds', () => {
    const rngA = mulberry32(1);
    const rngB = mulberry32(2);
    expect(rngA()).not.toBe(rngB());
  });

  it('always returns values in [0, 1)', () => {
    const rng = mulberry32(999);
    for (let i = 0; i < 100; i++) {
      const v = rng();
      expect(v).toBeGreaterThanOrEqual(0);
      expect(v).toBeLessThan(1);
    }
  });
});

describe('hashSeedString / matchupSeedKey', () => {
  it('hashes identical keys identically', () => {
    const key = matchupSeedKey('NY', 'MIN', 'NY', 'bo7', 0);
    expect(hashSeedString(key)).toBe(hashSeedString(matchupSeedKey('NY', 'MIN', 'NY', 'bo7', 0)));
  });

  it('hashes a different reroll nonce to a different seed', () => {
    const seed0 = hashSeedString(matchupSeedKey('NY', 'MIN', 'NY', 'bo7', 0));
    const seed1 = hashSeedString(matchupSeedKey('NY', 'MIN', 'NY', 'bo7', 1));
    expect(seed0).not.toBe(seed1);
  });
});

describe('simulateClientSeries — issue #128 seeded reproducibility', () => {
  it('returns identical results for the same matchup key (no reroll)', () => {
    const r1 = simulateClientSeries(TEAM_A, TEAM_B, 'NY', 'bo7', 2000, 0);
    const r2 = simulateClientSeries(TEAM_A, TEAM_B, 'NY', 'bo7', 2000, 0);
    expect(r1.winProbA).toBe(r2.winProbA);
    expect(r1.winProbB).toBe(r2.winProbB);
    expect(r1.avgGames).toBe(r2.avgGames);
    expect(r1.gameDistributions).toEqual(r2.gameDistributions);
  });

  it('changes results when the reroll nonce advances', () => {
    const r1 = simulateClientSeries(TEAM_A, TEAM_B, 'NY', 'bo7', 2000, 0);
    const r2 = simulateClientSeries(TEAM_A, TEAM_B, 'NY', 'bo7', 2000, 1);
    // With 2000 sims, the Monte Carlo noise floor virtually guarantees a
    // different sampled outcome for an independent seed.
    const differs =
      r1.winProbA !== r2.winProbA || r1.avgGames !== r2.avgGames || r1.sweepProb !== r2.sweepProb;
    expect(differs).toBe(true);
  });

  it('is independent of a prior re-roll once the matchup key changes', () => {
    const rerolled = simulateClientSeries(TEAM_A, TEAM_B, 'NY', 'bo7', 2000, 5);
    const freshSameSeed = simulateClientSeries(TEAM_A, TEAM_B, 'NY', 'bo7', 2000, 5);
    expect(rerolled.winProbA).toBe(freshSameSeed.winProbA);
  });
});
