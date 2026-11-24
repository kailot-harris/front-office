import { describe, it, expect, beforeEach } from 'vitest';
import { render, screen, fireEvent, within } from '@testing-library/react';
import React from 'react';
import { StandingsClient } from '@/components/StandingsClient';
import { ActualTeamRecord, TeamProjection } from '@/lib/types';

function makeTeam(overrides: Partial<TeamProjection>): TeamProjection {
  return {
    rank: 1,
    team_id: 1,
    team: 'NY',
    team_name: 'Liberty',
    conference: 'East',
    division: 'Eastern',
    proj_wins: 28,
    proj_losses: 16,
    win_pct: 28 / 44,
    ensemble_mean_wins: 28,
    ensemble_median_wins: 28,
    ensemble_sd_wins: 3,
    ensemble_p10: 24,
    ensemble_p25: 26,
    ensemble_p50: 28,
    ensemble_p75: 30,
    ensemble_p90: 32,
    ensemble_playoff_prob: 0.95,
    ensemble_title_prob: 0.2,
    variant_bottom_up_mean_wins: 28,
    variant_bottom_up_median_wins: 28,
    variant_bottom_up_sd_wins: 3,
    variant_bottom_up_p10: 24,
    variant_bottom_up_p25: 26,
    variant_bottom_up_p50: 28,
    variant_bottom_up_p75: 30,
    variant_bottom_up_p90: 32,
    variant_bottom_up_playoff_prob: 0.95,
    variant_bottom_up_title_prob: 0.2,
    variant_rapm_mean_wins: 28,
    variant_rapm_median_wins: 28,
    variant_rapm_sd_wins: 3,
    variant_rapm_p10: 24,
    variant_rapm_p25: 26,
    variant_rapm_p50: 28,
    variant_rapm_p75: 30,
    variant_rapm_p90: 32,
    variant_rapm_playoff_prob: 0.95,
    variant_rapm_title_prob: 0.2,
    variant_shot_fatigue_mean_wins: 28,
    variant_shot_fatigue_median_wins: 28,
    variant_shot_fatigue_sd_wins: 3,
    variant_shot_fatigue_p10: 24,
    variant_shot_fatigue_p25: 26,
    variant_shot_fatigue_p50: 28,
    variant_shot_fatigue_p75: 30,
    variant_shot_fatigue_p90: 32,
    variant_shot_fatigue_playoff_prob: 0.95,
    variant_shot_fatigue_title_prob: 0.2,
    variant_embeddings_mean_wins: 28,
    variant_embeddings_median_wins: 28,
    variant_embeddings_sd_wins: 3,
    variant_embeddings_p10: 24,
    variant_embeddings_p25: 26,
    variant_embeddings_p50: 28,
    variant_embeddings_p75: 30,
    variant_embeddings_p90: 32,
    variant_embeddings_playoff_prob: 0.95,
    variant_embeddings_title_prob: 0.2,
    ...overrides,
  };
}

const TEAMS: TeamProjection[] = [
  makeTeam({ rank: 1, team: 'NY', team_name: 'Liberty', conference: 'East', division: 'Eastern', ensemble_mean_wins: 30 }),
  makeTeam({ rank: 2, team: 'MIN', team_name: 'Lynx', conference: 'West', division: 'Western', ensemble_mean_wins: 22 }),
  makeTeam({ rank: 3, team: 'GS', team_name: 'Valkyries', conference: 'West', division: 'Western', ensemble_mean_wins: 18 }),
];

const ACTUAL: Record<string, ActualTeamRecord> = {
  NY: { wins: 24, losses: 20, pointsFor: 3600, pointsAgainst: 3550 }, // 44G pace 24.0 -> delta -6.0 (red)
  MIN: { wins: 30, losses: 14, pointsFor: 3800, pointsAgainst: 3450 }, // 44G pace 30.0 -> delta +8.0 (green)
  GS: { wins: 15, losses: 7, pointsFor: 1850, pointsAgainst: 1700 }, // 22 GP -> 44G pace 30.0 -> delta +12.0 (green)
};

describe('StandingsClient Projections vs. Actual tracker', () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it('toggles into Projections vs. Actual view and displays 44G pace, delta indicators, and columns', () => {
    render(<StandingsClient teams={TEAMS} actualRecords={ACTUAL} initialTab="visualizer" />);

    const toggleBtn = screen.getByRole('button', { name: /Projections vs\. Actual/i });
    fireEvent.click(toggleBtn);

    const table = screen.getByRole('table');
    expect(within(table).getByText('Actual Rec (W-L)')).toBeInTheDocument();
    expect(within(table).getByText('Point Diff')).toBeInTheDocument();
    expect(within(table).getByText('Proj Wins (44G)')).toBeInTheDocument();
    expect(within(table).getByText('44G Win Pace')).toBeInTheDocument();
    expect(within(table).getByText('Performance Delta')).toBeInTheDocument();

    const rows = within(table).getAllByRole('row').slice(1);
    // Default sort in reality mode is performance_delta desc: GS (+12.0), MIN (+8.0), NY (-6.0)
    expect(rows[0]).toHaveTextContent('Valkyries');
    expect(rows[1]).toHaveTextContent('Lynx');
    expect(rows[2]).toHaveTextContent('Liberty');

    // Green badge for positive delta, red badge for negative delta
    const gsDelta = within(rows[0]).getByText('+12.0');
    expect(gsDelta.className).toContain('emerald');
    const nyDelta = within(rows[2]).getByText('-6.0');
    expect(nyDelta.className).toContain('rose');
  });

  it('supports conference filtering and sort controls (win %, point diff, delta)', () => {
    render(
      <StandingsClient
        teams={TEAMS}
        actualRecords={ACTUAL}
        initialTab="table"
        initialMode="reality"
      />,
    );

    // Filter to East Conf -> only Liberty
    fireEvent.click(screen.getByRole('button', { name: 'East Conf' }));
    let rows = within(screen.getByRole('table')).getAllByRole('row').slice(1);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toHaveTextContent('Liberty');

    // Back to All League
    fireEvent.click(screen.getByRole('button', { name: 'All League' }));
    rows = within(screen.getByRole('table')).getAllByRole('row').slice(1);
    expect(rows).toHaveLength(3);

    // Sort by Point Diff descending: MIN (+350), GS (+150), NY (+50)
    const quickSort = screen.getByRole('group', { name: 'Quick sort controls' });
    fireEvent.click(within(quickSort).getByRole('button', { name: 'Point Diff' }));
    rows = within(screen.getByRole('table')).getAllByRole('row').slice(1);
    expect(rows[0]).toHaveTextContent('Lynx');
    expect(rows[1]).toHaveTextContent('Valkyries');
    expect(rows[2]).toHaveTextContent('Liberty');

    // Sort by Win % descending: MIN (68.2%) / GS (68.2%), NY (54.5%)
    fireEvent.click(within(quickSort).getByRole('button', { name: 'Win %' }));
    rows = within(screen.getByRole('table')).getAllByRole('row').slice(1);
    expect(rows[2]).toHaveTextContent('Liberty');
  });
});
