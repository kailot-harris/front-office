import { describe, expect, it } from 'vitest';
import { getActualTeamRecords, getTeamsData } from '@/lib/data';
import { enrichTeamsWithActuals, MLB_REGULAR_SEASON_GAMES } from '@/lib/standings';

describe('Standings actuals contract (real 2026 matchups + projections)', () => {
  it('derives regular-season records for all 30 MLB teams with GP <= 162 and exact 162G pace', () => {
    const teams = getTeamsData();
    const actualRecords = getActualTeamRecords();
    const enriched = enrichTeamsWithActuals(teams, actualRecords);

    expect(enriched).toHaveLength(30);
    for (const team of enriched) {
      expect(team.actual_gp).toBeGreaterThan(0);
      expect(team.actual_gp).toBeLessThanOrEqual(MLB_REGULAR_SEASON_GAMES);
      if (team.actual_gp === MLB_REGULAR_SEASON_GAMES) {
        expect(team.current_pace).toBe(team.actual.wins);
      }
      expect(Number.isFinite(team.performance_delta)).toBe(true);
      expect(Number.isFinite(team.actual_run_diff)).toBe(true);
    }
  });
});
