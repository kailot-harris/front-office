import React from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { GameDetailModal } from '@/components/GameDetailModal';
import { BASE_PATH } from '@/lib/basePath';
import type {
  GameDetailEnvelope,
  GameExplainabilityPayload,
  NflGameDetailPayload,
} from '@/lib/gameDetailTypes';
import type { MatchupGame } from '@/lib/types';

function makeMatchup(overrides: Partial<MatchupGame> = {}): MatchupGame {
  return {
    game_id: '2026_10_BUF_NYJ',
    season: 2026,
    week: 10,
    gameday: '2026-11-15',
    weekday: 'Sunday',
    gametime: '13:00',
    home_team: 'NYJ',
    home_team_name: 'New York Jets',
    away_team: 'BUF',
    away_team_name: 'Buffalo Bills',
    home_power_rating: -1.2,
    away_power_rating: 4.5,
    has_projection: true,
    projected_margin: -6.5,
    home_win_prob: 0.32,
    away_win_prob: 0.68,
    home_rest_days: 7,
    away_rest_days: 7,
    rest_diff: 0,
    home_travel_miles: 0,
    away_travel_miles: 350,
    is_completed: true,
    has_box_score: true,
    has_game_detail: true,
    home_score: 12,
    away_score: 31,
    actual_winner: 'BUF',
    prediction_correct: true,
    ...overrides,
  };
}

function makeDetailEnvelope(overrides: Partial<NflGameDetailPayload> = {}): GameDetailEnvelope {
  return {
    schema_version: '1.0',
    generated_at: '2026-11-16T05:33:37Z',
    sport: 'nfl',
    endpoint: 'game_detail',
    season: 2026,
    season_label: '2026-2027',
    game_id: '2026_10_BUF_NYJ',
    data: {
      game_id: '2026_10_BUF_NYJ',
      season: 2026,
      season_label: '2026-2027',
      week: 10,
      week_label: 'Week 10',
      gameday: '2026-11-15',
      weekday: 'Sunday',
      gametime: '13:00',
      is_completed: true,
      has_box_score: true,
      away_team: {
        teamAbbr: 'BUF',
        teamName: 'Buffalo Bills',
        score: 31,
        is_winner: true,
      },
      home_team: {
        teamAbbr: 'NYJ',
        teamName: 'New York Jets',
        score: 12,
        is_winner: false,
      },
      forecast: {
        projected_margin: -6.5,
        home_win_prob: 0.32,
        away_win_prob: 0.68,
        home_power_rating: -1.2,
        away_power_rating: 4.5,
        prediction_correct: true,
      },
      efficiency_factors: [
        {
          key: 'epa_per_play',
          label: 'EPA / Play',
          away_value: 0.12,
          home_value: -0.05,
          unit: 'epa',
          higher_is_better: true,
          description: 'Expected Points Added per offensive play',
        },
        {
          key: 'success_rate',
          label: 'Success Rate',
          away_value: 48.5,
          home_value: 39.2,
          unit: 'pct',
          higher_is_better: true,
          description: 'Percentage of plays with positive Expected Points Added',
        },
        {
          key: 'dropback_epa',
          label: 'Dropback EPA',
          away_value: 0.22,
          home_value: -0.08,
          unit: 'epa',
          higher_is_better: true,
          description: 'Expected Points Added per dropback pass play',
        },
        {
          key: 'rush_epa',
          label: 'Rush EPA',
          away_value: 0.04,
          home_value: -0.02,
          unit: 'epa',
          higher_is_better: true,
          description: 'Expected Points Added per rushing play',
        },
        {
          key: 'cpoe',
          label: 'CPOE',
          away_value: 5.1,
          home_value: -2.3,
          unit: 'pct',
          higher_is_better: true,
          description: 'Completion Percentage Over Expected on pass attempts',
        },
        {
          key: 'yards_per_play',
          label: 'Yards / Play',
          away_value: 5.8,
          home_value: 4.6,
          unit: 'yards',
          higher_is_better: true,
          description: 'Offensive yards gained per play',
        },
        {
          key: 'early_down_epa',
          label: 'Early Down EPA',
          away_value: 0.09,
          home_value: -0.04,
          unit: 'epa',
          higher_is_better: true,
          description: 'Expected Points Added on 1st and 2nd downs',
        },
        {
          key: 'late_down_success_rate',
          label: 'Late Down Success Rate',
          away_value: 50.0,
          home_value: 33.3,
          unit: 'pct',
          higher_is_better: true,
          description: 'Percentage of 3rd and 4th down plays converted successfully',
        },
      ],
      team_stats: [
        {
          stat_key: 'total_yards',
          label: 'Net Yards',
          away_value: 397,
          home_value: 394,
        },
        {
          stat_key: 'passing_yards',
          label: 'Passing Yards',
          away_value: 196,
          home_value: 285,
        },
        {
          stat_key: 'rushing_yards',
          label: 'Rushing Yards',
          away_value: 201,
          home_value: 109,
        },
        {
          stat_key: 'turnovers',
          label: 'Turnovers',
          away_value: 2,
          home_value: 2,
        },
        {
          stat_key: 'penalties_yards',
          label: 'Penalties - Yards',
          away_value: '7-35',
          home_value: '7-53',
        },
      ],
      leaders: [
        {
          category: 'passing',
          teamAbbr: 'BUF',
          playerId: '00-0034857',
          playerName: 'Josh Allen',
          stat_line: '11/21, 196 YDS, 1 TD',
        },
        {
          category: 'rushing',
          teamAbbr: 'BUF',
          playerId: '00-0037248',
          playerName: 'James Cook',
          stat_line: '18 CAR, 157 YDS, 1 TD',
        },
        {
          category: 'receiving',
          teamAbbr: 'BUF',
          playerId: '00-0034827',
          playerName: 'DJ Moore',
          stat_line: '4 REC, 90 YDS, 1 TD',
        },
        {
          category: 'defense',
          teamAbbr: 'BUF',
          playerId: '00-0041036',
          playerName: 'TJ Parker',
          stat_line: '2.0 SCK, 3 TKL',
        },
      ],
      box_score: {
        away_players: [
          {
            playerId: '00-0034857',
            playerName: 'Josh Allen',
            teamAbbr: 'BUF',
            position: 'QB',
            categories: ['passing'],
            snap_pct: 100,
            completions: 11,
            attempts: 21,
            passing_yards: 196,
            passing_tds: 1,
            passing_interceptions: 0,
            sacks_suffered: 1,
            sack_yards_lost: 8,
            passing_epa: 4.82,
            passing_cpoe: 2.1,
          },
          {
            playerId: '00-0037248',
            playerName: 'James Cook',
            teamAbbr: 'BUF',
            position: 'RB',
            categories: ['rushing'],
            snap_pct: 65,
            carries: 18,
            rushing_yards: 157,
            rushing_tds: 1,
            rushing_first_downs: 6,
            rushing_fumbles: 0,
            rushing_epa: 5.12,
          },
          {
            playerId: '00-0034827',
            playerName: 'DJ Moore',
            teamAbbr: 'BUF',
            position: 'WR',
            categories: ['receiving'],
            snap_pct: 88,
            receptions: 4,
            targets: 6,
            receiving_yards: 90,
            receiving_tds: 1,
            receiving_first_downs: 3,
            receiving_fumbles: 0,
            receiving_epa: 3.44,
          },
          {
            playerId: '00-0041036',
            playerName: 'TJ Parker',
            teamAbbr: 'BUF',
            position: 'DE',
            categories: ['defense'],
            snap_pct: 72,
            def_tackles_solo: 3,
            def_tackle_assists: 1,
            def_sacks: 2,
            def_tackles_for_loss: 2,
            def_qb_hits: 3,
            def_interceptions: 0,
            def_pass_defended: 0,
            def_fumbles_forced: 0,
          },
          {
            playerId: '00-0033100',
            playerName: 'Tyler Bass',
            teamAbbr: 'BUF',
            position: 'K',
            categories: ['kicking'],
            snap_pct: 20,
            fg_made: 1,
            fg_att: 1,
            fg_long: 42,
            pat_made: 4,
            pat_att: 4,
          },
        ],
        home_players: [
          {
            playerId: '00-0030565',
            playerName: 'Geno Smith',
            teamAbbr: 'NYJ',
            position: 'QB',
            categories: ['passing'],
            snap_pct: 100,
            completions: 24,
            attempts: 41,
            passing_yards: 285,
            passing_tds: 0,
            passing_interceptions: 2,
            sacks_suffered: 4,
            sack_yards_lost: 18,
            passing_epa: -3.21,
            passing_cpoe: -4.5,
          },
        ],
      },
      injury_designations: [
        {
          playerId: '00-0039347',
          playerName: 'Trevin Wallace',
          position: 'LB',
          designation: 'Out',
          body_part: 'Groin',
          played: false,
        },
        {
          playerId: '00-0037740',
          playerName: 'Garrett Wilson',
          position: 'WR',
          designation: 'Questionable',
          body_part: 'Concussion',
          played: true,
        },
      ],
      explainability: null,
      ...overrides,
    },
  };
}

function makeExplainabilityData(): GameExplainabilityPayload {
  return {
    game_id: '2026_10_BUF_NYJ',
    season: 2026,
    week: 10,
    projection_basis: 'logged_pregame',
    predicted_margin: -6.5,
    predicted_home_win_prob: 0.32,
    waterfall: {
      projected_margin: -6.5,
      home_win_prob: 0.32,
      steps: [
        {
          key: 'step_current_epa',
          label: 'Current-Season EPA',
          points: -1.85,
          description: 'Current season rolling EPA net differential',
        },
        {
          key: 'step_prior_epa',
          label: 'Pre-Season Prior',
          points: -0.95,
          description: 'Prior season baseline regressed to mean',
        },
        {
          key: 'step_elo_diff',
          label: 'Elo Differential',
          points: -3.8,
          description: 'Elo rating points differential',
        },
        {
          key: 'step_home_field',
          label: 'Home Field Advantage',
          points: 2.08,
          description: 'Neutral site and home field advantage blend',
        },
        {
          key: 'step_qb_adjustment',
          label: 'Starting Quarterback',
          points: -1.98,
          description: 'Quarterback availability and injury adjustment',
        },
        {
          key: 'step_rounding',
          label: 'Rounding',
          points: 0.0,
          description: 'Decomposition residual',
        },
      ],
      rounding: 0.0,
      sigma: 14.6,
    },
    secondary_model: {
      model_id: 'xgboost_treeshap_v1',
      model_label: 'Secondary Model (TreeSHAP)',
      model_win_prob: 0.285,
      logit: -0.92,
      base_value: 0.187,
      factors: [
        { feature: 'diff_raw', label: 'Overall EPA/Play Differential', value: -0.15, shap_value: -0.32 },
        { feature: 'diff_pass_epa', label: 'Passing EPA Differential', value: -0.22, shap_value: -0.28 },
        { feature: 'diff_rush_epa', label: 'Rushing EPA Differential', value: -0.05, shap_value: -0.11 },
        { feature: 'diff_cpoe', label: 'Completion % Over Expected Differential', value: -4.1, shap_value: -0.18 },
        { feature: 'elo_margin', label: 'Primary Elo Model Projection', value: -5.2, shap_value: -0.21 },
        { feature: 'ridge_margin', label: 'Primary Ridge Model Projection', value: -6.8, shap_value: -0.25 },
        { feature: 'rest_diff', label: 'Days Rest Differential', value: 0, shap_value: 0.02 },
        { feature: 'fatigue_adj', label: 'Schedule Rest & Travel Impact', value: 0, shap_value: 0.01 },
        { feature: 'diff_prior', label: 'Pre-Season Baseline Differential', value: -3.2, shap_value: -0.05 },
        { feature: 'qb_diff', label: 'Quarterback Status Differential', value: 0, shap_value: 0.0 },
        { feature: 'gp_avg', label: 'Sample Maturity (Avg Games Played)', value: 9, shap_value: 0.0 },
        { feature: 'gp_min', label: 'Minimum Team Games Played', value: 9, shap_value: 0.0 },
      ],
      out_of_sample_record: {
        n_games: 145,
        accuracy: 59.3,
        brier: 0.2232,
        logloss: 0.6348,
      },
      agreement: 'agree',
    },
    entering_baselines: [
      {
        metric_key: 'epa_per_play',
        metric_label: 'EPA / Play',
        team_abbr: 'BUF',
        entering_baseline: 0.125,
        realized_value: 0.12,
        delta: -0.005,
        prior_games_n: 9,
        is_low_sample: false,
      },
      {
        metric_key: 'success_rate',
        metric_label: 'Success Rate',
        team_abbr: 'BUF',
        entering_baseline: 49.2,
        realized_value: 48.5,
        delta: -0.7,
        prior_games_n: 9,
        is_low_sample: false,
      },
      {
        metric_key: 'dropback_epa',
        metric_label: 'Dropback EPA',
        team_abbr: 'BUF',
        entering_baseline: 0.24,
        realized_value: 0.22,
        delta: -0.02,
        prior_games_n: 9,
        is_low_sample: false,
      },
      {
        metric_key: 'rush_epa',
        metric_label: 'Rush EPA',
        team_abbr: 'BUF',
        entering_baseline: 0.05,
        realized_value: 0.04,
        delta: -0.01,
        prior_games_n: 9,
        is_low_sample: false,
      },
      {
        metric_key: 'cpoe',
        metric_label: 'CPOE',
        team_abbr: 'BUF',
        entering_baseline: 5.4,
        realized_value: 5.1,
        delta: -0.3,
        prior_games_n: 9,
        is_low_sample: false,
      },
      {
        metric_key: 'epa_per_play',
        metric_label: 'EPA / Play',
        team_abbr: 'NYJ',
        entering_baseline: -0.04,
        realized_value: -0.05,
        delta: -0.01,
        prior_games_n: 9,
        is_low_sample: false,
      },
      {
        metric_key: 'success_rate',
        metric_label: 'Success Rate',
        team_abbr: 'NYJ',
        entering_baseline: 40.1,
        realized_value: 39.2,
        delta: -0.9,
        prior_games_n: 9,
        is_low_sample: false,
      },
      {
        metric_key: 'dropback_epa',
        metric_label: 'Dropback EPA',
        team_abbr: 'NYJ',
        entering_baseline: -0.06,
        realized_value: -0.08,
        delta: -0.02,
        prior_games_n: 9,
        is_low_sample: false,
      },
      {
        metric_key: 'rush_epa',
        metric_label: 'Rush EPA',
        team_abbr: 'NYJ',
        entering_baseline: -0.01,
        realized_value: -0.02,
        delta: -0.01,
        prior_games_n: 9,
        is_low_sample: false,
      },
      {
        metric_key: 'cpoe',
        metric_label: 'CPOE',
        team_abbr: 'NYJ',
        entering_baseline: -2.0,
        realized_value: -2.3,
        delta: -0.3,
        prior_games_n: 9,
        is_low_sample: false,
      },
    ],
    divergence_note:
      'NYJ Success Rate (+39.200) showed the largest divergence from entering baseline (+40.100).',
  };
}

function stubFetchJson(payload: unknown, status = 200) {
  const fetchMock = vi.fn<typeof fetch>().mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    json: async () => payload,
  } as Response);
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  window.history.replaceState(null, '', '/');
});

describe('GameDetailModal Component Tests', () => {
  it('renders accessible dialog role, aria attributes, and header information', async () => {
    stubFetchJson(makeDetailEnvelope());
    const matchup = makeMatchup();

    render(<GameDetailModal matchup={matchup} onClose={vi.fn()} />);

    const dialog = screen.getByRole('dialog');
    expect(dialog).toBeInTheDocument();
    expect(dialog).toHaveAttribute('aria-modal', 'true');
    expect(dialog).toHaveAttribute('aria-labelledby', 'game-detail-modal-title');

    expect(screen.getByText('Buffalo Bills')).toBeInTheDocument();
    expect(screen.getByText('New York Jets')).toBeInTheDocument();
    expect(screen.getByText('31')).toBeInTheDocument();
    expect(screen.getByText('12')).toBeInTheDocument();
    expect(screen.getByText('FINAL')).toBeInTheDocument();
    expect(screen.getByText('Week 10')).toBeInTheDocument();

    await waitFor(() => {
      expect(screen.getByText('Efficiency Factors')).toBeInTheDocument();
    });
  });

  it('renders nothing when matchup is null', () => {
    const { container } = render(<GameDetailModal matchup={null} onClose={vi.fn()} />);
    expect(container).toBeEmptyDOMElement();
  });

  it('triggers onClose when Escape key is pressed', async () => {
    stubFetchJson(makeDetailEnvelope());
    const onClose = vi.fn();
    render(<GameDetailModal matchup={makeMatchup()} onClose={onClose} />);

    await waitFor(() => {
      expect(screen.getByRole('dialog')).toBeInTheDocument();
    });

    fireEvent.keyDown(document, { key: 'Escape' });
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('triggers onClose on close button click and backdrop click', async () => {
    stubFetchJson(makeDetailEnvelope());
    const onClose = vi.fn();
    render(<GameDetailModal matchup={makeMatchup()} onClose={onClose} />);

    await waitFor(() => {
      expect(screen.getByRole('dialog')).toBeInTheDocument();
    });

    const closeBtn = screen.getByRole('button', { name: /close modal/i });
    fireEvent.click(closeBtn);
    expect(onClose).toHaveBeenCalledTimes(1);

    const backdrop = screen.getByTestId('game-detail-backdrop');
    fireEvent.click(backdrop);
    expect(onClose).toHaveBeenCalledTimes(2);

    const dialog = screen.getByRole('dialog');
    fireEvent.click(dialog);
    expect(onClose).toHaveBeenCalledTimes(2);
  });

  it('traps Tab and Shift+Tab navigation inside modal', async () => {
    stubFetchJson(makeDetailEnvelope());
    render(<GameDetailModal matchup={makeMatchup()} onClose={vi.fn()} />);

    await waitFor(() => {
      expect(screen.getByRole('dialog')).toBeInTheDocument();
    });

    const dialog = screen.getByRole('dialog');
    const focusableElements = dialog.querySelectorAll<HTMLElement>(
      'button:not([disabled]), [tabindex]:not([tabindex="-1"])',
    );
    expect(focusableElements.length).toBeGreaterThan(1);

    const firstElement = focusableElements[0];
    const lastElement = focusableElements[focusableElements.length - 1];

    firstElement.focus();
    expect(document.activeElement).toBe(firstElement);

    fireEvent.keyDown(document, { key: 'Tab', shiftKey: true });
    expect(document.activeElement).toBe(lastElement);

    lastElement.focus();
    fireEvent.keyDown(document, { key: 'Tab' });
    expect(document.activeElement).toBe(firstElement);
  });

  it('returns focus to returnFocusTo element on close', async () => {
    stubFetchJson(makeDetailEnvelope());
    const opener = document.createElement('button');
    opener.textContent = 'Open Matchup';
    document.body.appendChild(opener);
    opener.focus();

    const onClose = vi.fn();
    const { unmount } = render(
      <GameDetailModal matchup={makeMatchup()} onClose={onClose} returnFocusTo={opener} />,
    );

    await waitFor(() => {
      expect(screen.getByRole('dialog')).toBeInTheDocument();
    });

    const closeBtn = screen.getByRole('button', { name: /close modal/i });
    fireEvent.click(closeBtn);

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(document.activeElement).toBe(opener);

    unmount();
    document.body.removeChild(opener);
  });

  it('syncs ?game= query parameter on open and clears on close', async () => {
    stubFetchJson(makeDetailEnvelope());
    window.history.replaceState(null, '', '/matchups?view=compact');

    const { unmount } = render(<GameDetailModal matchup={makeMatchup()} onClose={vi.fn()} />);

    expect(window.location.search).toContain('game=2026_10_BUF_NYJ');
    expect(window.location.search).toContain('view=compact');

    await waitFor(() => {
      expect(screen.getByRole('dialog')).toBeInTheDocument();
    });

    unmount();

    expect(window.location.search).not.toContain('game=');
    expect(window.location.search).toContain('view=compact');
  });

  it('switches between Tabs 1, 2, and 3 and renders respective content sections', async () => {
    stubFetchJson(makeDetailEnvelope());
    render(<GameDetailModal matchup={makeMatchup()} onClose={vi.fn()} />);

    await waitFor(() => {
      expect(screen.getByText('Efficiency Factors')).toBeInTheDocument();
    });
    expect(screen.getByText('EPA / Play')).toBeInTheDocument();
    expect(screen.getByText('Category Leaders')).toBeInTheDocument();
    expect(screen.getByText('Josh Allen')).toBeInTheDocument();

    const comparisonTab = screen.getByRole('tab', { name: /team comparison/i });
    fireEvent.click(comparisonTab);

    expect(screen.getByText('Team Statistics Comparison')).toBeInTheDocument();
    expect(screen.getByText('Net Yards')).toBeInTheDocument();
    expect(screen.getByText('Passing Yards')).toBeInTheDocument();

    const boxScoreTab = screen.getByRole('tab', { name: /player box score/i });
    fireEvent.click(boxScoreTab);

    expect(screen.getByText('Injury report designations entering the game')).toBeInTheDocument();
    expect(screen.getByText('Trevin Wallace')).toBeInTheDocument();
    expect(screen.getByText('Garrett Wilson')).toBeInTheDocument();
    expect(screen.getByText('Did Not Play')).toBeInTheDocument();
    expect(screen.getByText('Played')).toBeInTheDocument();
    expect(screen.getByText('Note: EPA is a model estimate published by nflreadr.')).toBeInTheDocument();

    const rushingCategoryBtn = screen.getByRole('button', { name: 'rushing' });
    fireEvent.click(rushingCategoryBtn);
    expect(screen.getByText('James Cook')).toBeInTheDocument();

    const receivingCategoryBtn = screen.getByRole('button', { name: 'receiving' });
    fireEvent.click(receivingCategoryBtn);
    expect(screen.getByText('DJ Moore')).toBeInTheDocument();

    const defenseCategoryBtn = screen.getByRole('button', { name: 'defense' });
    fireEvent.click(defenseCategoryBtn);
    expect(screen.getByText('TJ Parker')).toBeInTheDocument();

    const kickingCategoryBtn = screen.getByRole('button', { name: 'kicking' });
    fireEvent.click(kickingCategoryBtn);
    expect(screen.getByText('Tyler Bass')).toBeInTheDocument();
  });

  it('renders missing-data fallback copy when data is absent or 404', async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue({
      ok: false,
      status: 404,
      json: async () => ({ error: 'Not found' }),
    } as Response);
    vi.stubGlobal('fetch', fetchMock);

    render(
      <GameDetailModal
        matchup={makeMatchup({ has_box_score: false, is_completed: true })}
        onClose={vi.fn()}
      />,
    );

    await waitFor(() => {
      expect(
        screen.getByText('Final. Box score is added on a later data refresh.'),
      ).toBeInTheDocument();
    });
  });

  it('renders fallback when forecast is not available', async () => {
    stubFetchJson(makeDetailEnvelope());
    render(
      <GameDetailModal
        matchup={makeMatchup({
          has_projection: false,
          projected_margin: null,
          home_power_rating: null,
          away_power_rating: null,
          is_completed: false,
        })}
        onClose={vi.fn()}
      />,
    );

    expect(screen.getByText('No forecast recorded')).toBeInTheDocument();

    await waitFor(() => {
      expect(screen.getByRole('dialog')).toBeInTheDocument();
    });
  });

  it('opens directly to Tab 4 (Attribution) for unplayed games with Tabs 1-3 disabled', async () => {
    const explainData = makeExplainabilityData();
    const weeklyDataset = {
      schema_version: '1.0',
      generated_at: '2026-11-16T00:00:00Z',
      season: 2026,
      week: 10,
      games: [explainData],
    };

    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => weeklyDataset,
    } as Response);
    vi.stubGlobal('fetch', fetchMock);

    render(
      <GameDetailModal
        matchup={makeMatchup({
          is_completed: false,
          has_box_score: false,
          has_projection: true,
          projected_margin: -6.5,
          home_win_prob: 0.32,
          away_win_prob: 0.68,
        })}
        onClose={vi.fn()}
      />,
    );

    // Initial tab for unplayed game must be Tab 4 (Model Attribution)
    const tabAttribution = screen.getByRole('tab', { name: /model attribution/i });
    expect(tabAttribution).toHaveAttribute('aria-selected', 'true');

    // Tabs 1-3 must be disabled with (Post-Game) indicator
    const tabOverview = screen.getByRole('tab', { name: /overview & efficiency/i });
    const tabComparison = screen.getByRole('tab', { name: /team comparison/i });
    const tabBoxScore = screen.getByRole('tab', { name: /player box score/i });

    expect(tabOverview).toBeDisabled();
    expect(tabOverview).toHaveAttribute('aria-disabled', 'true');
    expect(tabOverview).toHaveTextContent('(Post-Game)');

    expect(tabComparison).toBeDisabled();
    expect(tabComparison).toHaveAttribute('aria-disabled', 'true');
    expect(tabComparison).toHaveTextContent('(Post-Game)');

    expect(tabBoxScore).toBeDisabled();
    expect(tabBoxScore).toHaveAttribute('aria-disabled', 'true');
    expect(tabBoxScore).toHaveTextContent('(Post-Game)');

    // Clicking a disabled tab must not change active tab
    fireEvent.click(tabOverview);
    expect(tabAttribution).toHaveAttribute('aria-selected', 'true');

    // Wait for attribution data to load and render
    await waitFor(() => {
      expect(screen.getByTestId('points-waterfall-card')).toBeInTheDocument();
    });

    // 5-step points waterfall verification
    expect(screen.getByText('5-Step Points Waterfall')).toBeInTheDocument();
    expect(screen.getByText('Current-Season EPA')).toBeInTheDocument();
    expect(screen.getByText('Pre-Season Prior')).toBeInTheDocument();
    expect(screen.getByText('Elo Differential')).toBeInTheDocument();
    expect(screen.getByText('Home Field Advantage')).toBeInTheDocument();
    expect(screen.getByText('Starting Quarterback')).toBeInTheDocument();
    expect(screen.getByText('Rounding')).toBeInTheDocument();
    expect(screen.getByText('Pre-Game Forecast')).toBeInTheDocument();
    expect(screen.getByText(/Additivity verified/)).toBeInTheDocument();
  });

  it('renders Secondary TreeSHAP card with agree/differ badge, win prob, out-of-sample track record, and feature toggle', async () => {
    const explainData = makeExplainabilityData();
    const weeklyDataset = {
      schema_version: '1.0',
      generated_at: '2026-11-16T00:00:00Z',
      season: 2026,
      week: 10,
      games: [explainData],
    };

    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => weeklyDataset,
    } as Response);
    vi.stubGlobal('fetch', fetchMock);

    render(
      <GameDetailModal
        matchup={makeMatchup({
          is_completed: false,
          has_box_score: false,
          has_projection: true,
        })}
        onClose={vi.fn()}
      />,
    );

    await waitFor(() => {
      expect(screen.getByTestId('secondary-shap-card')).toBeInTheDocument();
    });

    // Agreement badge
    const badge = screen.getByTestId('secondary-agreement-badge');
    expect(badge).toHaveTextContent(/agrees with primary pick/i);

    // Published out-of-sample track record
    const trackRecord = screen.getByTestId('secondary-track-record');
    expect(trackRecord).toHaveTextContent('145');
    expect(trackRecord).toHaveTextContent('59.3%');
    expect(trackRecord).toHaveTextContent('0.2232');
    expect(trackRecord).toHaveTextContent('0.6348');

    // Initial top 6 features shown
    expect(screen.getByText('Overall EPA/Play Differential')).toBeInTheDocument();
    expect(screen.getByText('Passing EPA Differential')).toBeInTheDocument();
    expect(screen.getByText('Rushing EPA Differential')).toBeInTheDocument();

    // Toggle to view all 12 features
    const toggleBtn = screen.getByRole('button', { name: /show all 12 features/i });
    expect(toggleBtn).toBeInTheDocument();

    fireEvent.click(toggleBtn);
    expect(screen.getByRole('button', { name: /show top 6 features/i })).toBeInTheDocument();
    expect(screen.getByText('Minimum Team Games Played')).toBeInTheDocument();
  });

  it('renders Entering Efficiency Baselines card with 10 rows and divergence note callout', async () => {
    const explainData = makeExplainabilityData();
    const weeklyDataset = {
      schema_version: '1.0',
      generated_at: '2026-11-16T00:00:00Z',
      season: 2026,
      week: 10,
      games: [explainData],
    };

    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => weeklyDataset,
    } as Response);
    vi.stubGlobal('fetch', fetchMock);

    render(
      <GameDetailModal
        matchup={makeMatchup({
          is_completed: false,
          has_box_score: false,
          has_projection: true,
        })}
        onClose={vi.fn()}
      />,
    );

    await waitFor(() => {
      expect(screen.getByTestId('entering-baselines-card')).toBeInTheDocument();
    });

    expect(screen.getByText('Entering Efficiency Baselines')).toBeInTheDocument();
    expect(screen.getByTestId('divergence-note-callout')).toBeInTheDocument();
    expect(
      screen.getByText(
        'NYJ Success Rate (+39.200) showed the largest divergence from entering baseline (+40.100).',
      ),
    ).toBeInTheDocument();
  });

  it('allows completed games to navigate between all 4 tabs seamlessly', async () => {
    const detailEnvelope = makeDetailEnvelope({
      explainability: makeExplainabilityData(),
    });
    stubFetchJson(detailEnvelope);

    render(<GameDetailModal matchup={makeMatchup({ is_completed: true })} onClose={vi.fn()} />);

    // Defaults to Tab 1 Overview
    await waitFor(() => {
      expect(screen.getByRole('tab', { name: /overview & efficiency/i })).toHaveAttribute(
        'aria-selected',
        'true',
      );
    });

    // Switch to Tab 4 Attribution
    const tabAttribution = screen.getByRole('tab', { name: /model attribution/i });
    fireEvent.click(tabAttribution);
    expect(tabAttribution).toHaveAttribute('aria-selected', 'true');
    expect(screen.getByTestId('points-waterfall-card')).toBeInTheDocument();

    // Switch to Tab 2 Team Comparison
    const tabComparison = screen.getByRole('tab', { name: /team comparison/i });
    fireEvent.click(tabComparison);
    expect(tabComparison).toHaveAttribute('aria-selected', 'true');
    expect(screen.getByText('Team Statistics Comparison')).toBeInTheDocument();

    // Switch to Tab 3 Player Box Score
    const tabBoxScore = screen.getByRole('tab', { name: /player box score/i });
    fireEvent.click(tabBoxScore);
    expect(tabBoxScore).toHaveAttribute('aria-selected', 'true');
    expect(screen.getByText('Injury report designations entering the game')).toBeInTheDocument();
  });

  it('contains zero betting terms across Tab 4 elements and copy', async () => {
    const explainData = makeExplainabilityData();
    const weeklyDataset = {
      schema_version: '1.0',
      generated_at: '2026-11-16T00:00:00Z',
      season: 2026,
      week: 10,
      games: [explainData],
    };

    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => weeklyDataset,
    } as Response);
    vi.stubGlobal('fetch', fetchMock);

    render(
      <GameDetailModal
        matchup={makeMatchup({
          is_completed: false,
          has_box_score: false,
          has_projection: true,
        })}
        onClose={vi.fn()}
      />,
    );

    await waitFor(() => {
      expect(screen.getByTestId('points-waterfall-card')).toBeInTheDocument();
    });

    const dialog = screen.getByRole('dialog');
    const fullText = dialog.textContent?.toLowerCase() || '';

    const bannedTerms = [
      'spread',
      'moneyline',
      'over_under',
      'over/under',
      'parlay',
      'wager',
      'sharp_book',
      'key_number_flag',
    ];

    for (const term of bannedTerms) {
      expect(fullText).not.toContain(term);
    }
  });
});
