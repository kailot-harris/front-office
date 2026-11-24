import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { deriveActualTeamRecords, enrichTeamsWithActuals } from '@/lib/standings';
import { getTeamsData, getActualTeamRecords, getVisualMediaIndex } from '@/lib/data';
import { toVisualMediaItems } from '@/lib/visualMedia';
import { StandingsClient } from '@/components/StandingsClient';
import StandingsPage from '@/app/standings/page';
import type { Matchup } from '@/lib/matchupTypes';

const makeMatchup = (overrides: Partial<Matchup>): Matchup => ({
  game_pk: 1,
  game_date: '2026-06-01',
  week: 10,
  game_type: 'R',
  series_description: 'Regular Season',
  status_detail: 'Final',
  venue_name: 'Ballpark',
  home_team_id: 158,
  home_team_name: 'Brewers',
  home_team: 'MIL',
  away_team_id: 112,
  away_team_name: 'Cubs',
  away_team: 'CHC',
  is_completed: true,
  home_win_prob: 0.55,
  away_win_prob: 0.45,
  projection_source: 'walk_forward',
  home_score: 5,
  away_score: 2,
  prediction_correct: true,
  ...overrides,
});

describe('lib/standings.ts', () => {
  it('deriveActualTeamRecords counts only completed regular-season games and excludes postseason/incomplete', () => {
    const games: Matchup[] = [
      makeMatchup({ game_pk: 1, game_type: 'R', home_team: 'MIL', away_team: 'CHC', home_score: 6, away_score: 2 }),
      makeMatchup({ game_pk: 2, game_type: 'R', home_team: 'CHC', away_team: 'MIL', home_score: 1, away_score: 4 }),
      // Postseason game should be excluded
      makeMatchup({ game_pk: 3, game_type: 'W', home_team: 'MIL', away_team: 'NYY', home_score: 7, away_score: 3 }),
      // Incomplete game should be excluded
      makeMatchup({ game_pk: 4, game_type: 'R', is_completed: false, home_score: null, away_score: null }),
    ];

    const records = deriveActualTeamRecords(games);
    expect(records.MIL).toEqual({ wins: 2, losses: 0, runsFor: 10, runsAgainst: 3 });
    expect(records.CHC).toEqual({ wins: 0, losses: 2, runsFor: 3, runsAgainst: 10 });
    expect(records.NYY).toBeUndefined();
  });

  it('enrichTeamsWithActuals computes 162G pace in-season and equals final wins at 162G', () => {
    const teams = getTeamsData().slice(0, 3);
    const [t0, t1, t2] = teams;

    const enriched = enrichTeamsWithActuals(teams, {
      // In-season: 50-31 (81 GP) -> 100.0W pace
      [t0.team]: { wins: 50, losses: 31, runsFor: 410, runsAgainst: 350 },
      // Full 162G season: 103-59 -> exact 103W pace
      [t1.team]: { wins: 103, losses: 59, runsFor: 832, runsAgainst: 618 },
      // 0 GP (preseason)
    });

    expect(enriched[0].actual_gp).toBe(81);
    expect(enriched[0].current_pace).toBeCloseTo(100, 6);
    expect(enriched[0].actual_run_diff).toBe(60);
    expect(enriched[0].performance_delta).toBeCloseTo(100 - t0.ensemble_mean_wins, 6);

    expect(enriched[1].actual_gp).toBe(162);
    expect(enriched[1].current_pace).toBe(103);
    expect(enriched[1].performance_delta).toBeCloseTo(103 - t1.ensemble_mean_wins, 6);

    expect(enriched[2].actual_gp).toBe(0);
    expect(enriched[2].current_pace).toBe(0);
    expect(enriched[2].performance_delta).toBe(0);
  });
});

describe('StandingsClient Projections vs. Actual UI & /standings route', () => {
  it('renders Projections vs. Actual toggle, columns, sort controls, filters, and green/red delta badges', () => {
    const teams = getTeamsData();
    const mediaItems = toVisualMediaItems(getVisualMediaIndex());
    const actualRecords = getActualTeamRecords();

    const html = renderToStaticMarkup(
      createElement(StandingsClient, {
        teams,
        mediaItems,
        actualRecords,
        initialTab: 'table',
        initialTableMode: 'reality',
      }),
    );

    expect(html).toContain('Projections vs. Actual');
    expect(html).toContain('Actual Record (W-L)');
    expect(html).toContain('162G Win Pace');
    expect(html).toContain('Performance Delta');
    expect(html).toContain('Run Diff');
    expect(html).toContain('All MLB');
    expect(html).toContain('All 6 Divisions');
    // Green and red delta badges
    expect(html).toContain('bg-emerald-500/20');
    expect(html).toContain('bg-rose-500/20');
  });

  it('renders /standings page with real 2026 MLB data', () => {
    const html = renderToStaticMarkup(createElement(StandingsPage));
    expect(html).toContain('Standings');
    expect(html).toContain('Projections vs. Actual');
    expect(html).toContain('Milwaukee Brewers');
  });
});
