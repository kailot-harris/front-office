import { describe, it, expect } from 'vitest';
import { simulateClientSeries } from '@/components/PlayoffSeriesClient';
import type { TeamPlayoffProfile } from '@/lib/playoffTypes';

// Issue #111: a missing or non-numeric `playoffNetRtg` made every probability
// NaN, and because `Math.random() < NaN` is always false, the simulator used
// to silently report the opponent winning 100% of series instead of flagging
// missing data. These tests prove the fix: undefined, NaN and a string value
// for `playoffNetRtg` (on either team) must always come back flagged as
// "insufficient data" rather than as a probability, across bo3/bo5/bo7.

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

const VALID_TEAM_B = makeTeam({ teamAbbr: 'MIN', teamName: 'Minnesota Lynx', conference: 'West' });

const BAD_VALUES: Array<{ label: string; value: unknown }> = [
  { label: 'undefined', value: undefined },
  { label: 'NaN', value: NaN },
  { label: 'a string', value: 'N/A' },
];

describe('simulateClientSeries — issue #111 missing-rating guard', () => {
  for (const format of ['bo3', 'bo5', 'bo7'] as const) {
    describe(`format=${format}`, () => {
      for (const { label, value } of BAD_VALUES) {
        it(`flags insufficient data (not a probability) when teamA.playoffNetRtg is ${label}`, () => {
          const teamA = makeTeam({ playoffNetRtg: value as unknown as number });
          const result = simulateClientSeries(teamA, VALID_TEAM_B, teamA.teamAbbr, format);

          expect(result.insufficientData).toBe(true);
          expect(result.insufficientDataReason).toBeTruthy();
          expect(Number.isFinite(result.winProbA)).toBe(false);
          expect(Number.isFinite(result.winProbB)).toBe(false);
          // The old bug reported the opponent (team B) winning 100% of series —
          // guard explicitly against ever seeing that value again.
          expect(result.winProbB).not.toBe(1);
        });

        it(`flags insufficient data (not a probability) when teamB.playoffNetRtg is ${label}`, () => {
          const teamB = makeTeam({
            teamAbbr: 'MIN',
            teamName: 'Minnesota Lynx',
            conference: 'West',
            playoffNetRtg: value as unknown as number,
          });
          const teamA = makeTeam();
          const result = simulateClientSeries(teamA, teamB, teamA.teamAbbr, format);

          expect(result.insufficientData).toBe(true);
          expect(result.insufficientDataReason).toBeTruthy();
          expect(Number.isFinite(result.winProbA)).toBe(false);
          expect(Number.isFinite(result.winProbB)).toBe(false);
          expect(result.winProbA).not.toBe(1);
        });
      }

      it('runs a real simulation and returns real probabilities when both ratings are valid numbers', () => {
        const teamA = makeTeam();
        const result = simulateClientSeries(teamA, VALID_TEAM_B, teamA.teamAbbr, format);

        expect(result.insufficientData).toBeFalsy();
        expect(Number.isFinite(result.winProbA)).toBe(true);
        expect(Number.isFinite(result.winProbB)).toBe(true);
        expect(result.winProbA + result.winProbB).toBeCloseTo(1, 2);
      });
    });
  }
});
