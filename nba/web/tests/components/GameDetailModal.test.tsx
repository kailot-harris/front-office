import React, { useRef, useState } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { GameDetailModal } from '@/components/GameDetailModal';
import { BASE_PATH } from '@/lib/basePath';
import type {
  GameDetailEnvelope,
  GameExplainabilityEnvelope,
  GameExplainabilityPayload,
  PlayerBoxRow,
  XgboostShapPayload,
} from '@/lib/gameDetailTypes';
import type { MatchupGame } from '@/lib/matchupTypes';

function makeMatchup(overrides: Partial<MatchupGame> = {}): MatchupGame {
  return {
    game_id: '401909089',
    slate: 1,
    game_date: '2026-10-20',
    weekday: 'Tue',
    season: 2027,
    home_team: 'NYK',
    away_team: 'PHI',
    home_team_name: 'Knicks',
    away_team_name: '76ers',
    is_completed: true,
    has_projection: true,
    projection_basis: 'logged_model_margin',
    predicted_margin: 4.4,
    predicted_home_win_prob: 0.644,
    predicted_away_win_prob: 0.356,
    predicted_winner: 'NYK',
    home_score: 100,
    away_score: 106,
    actual_margin: -6,
    actual_winner: 'PHI',
    prediction_correct: false,
    has_box_score: true,
    has_game_detail: true,
    ...overrides,
  };
}

function makePlayer(overrides: Partial<PlayerBoxRow> = {}): PlayerBoxRow {
  return {
    playerId: '1001',
    playerName: 'Tyrese Maxey',
    short_name: 'T. Maxey',
    jersey: '0',
    position: 'G',
    starter: true,
    minutes: 36,
    points: 28,
    oreb: 1,
    dreb: 4,
    reb: 5,
    ast: 7,
    stl: 2,
    blk: 0,
    tov: 2,
    pf: 2,
    plus_minus: 11,
    fgm: 10,
    fga: 20,
    fg_pct: 50.0,
    fg3m: 4,
    fg3a: 9,
    fg3_pct: 44.4,
    ftm: 4,
    fta: 4,
    ft_pct: 100.0,
    efg_pct: 60.0,
    ts_pct: 64.3,
    game_score: 24.5,
    ...overrides,
  };
}

function makeDetailEnvelope(overrides: Partial<GameDetailEnvelope['data']> = {}): GameDetailEnvelope {
  return {
    schema_version: '1.0',
    generated_at: '2026-11-15T14:00:00Z',
    sport: 'nba',
    endpoint: 'game_detail',
    season: 2027,
    season_label: '2026-2027',
    data: {
      game_id: '401909089',
      slate: 1,
      slate_label: 'Week 1 · Oct 20 – Oct 26',
      game_date: '2026-10-20',
      weekday: 'Tue',
      is_completed: true,
      has_box_score: true,
      away_team: {
        teamAbbr: 'PHI',
        teamName: '76ers',
        score: 106,
        is_winner: true,
      },
      home_team: {
        teamAbbr: 'NYK',
        teamName: 'Knicks',
        score: 100,
        is_winner: false,
      },
      efficiency_factors: [
        {
          key: 'efg_pct',
          label: 'Effective FG%',
          away_value: 54.2,
          home_value: 49.8,
          unit: 'pct',
          higher_is_better: true,
          description: '(FGM + 0.5 * 3PM) / FGA * 100.',
        },
        {
          key: 'ts_pct',
          label: 'True Shooting%',
          away_value: 58.1,
          home_value: 54.0,
          unit: 'pct',
          higher_is_better: true,
          description: 'PTS / (2 * (FGA + 0.44 * FTA)) * 100.',
        },
        {
          key: 'tov_pct',
          label: 'Turnover Rate',
          away_value: 11.4,
          home_value: 14.2,
          unit: 'pct',
          higher_is_better: false,
          description: 'Turnovers per 100 offensive plays.',
        },
        {
          key: 'oreb_pct',
          label: 'Offensive Rebound%',
          away_value: 24.5,
          home_value: 27.1,
          unit: 'pct',
          higher_is_better: true,
          description: 'Share of available offensive rebounds secured.',
        },
        {
          key: 'fta_rate',
          label: 'Free-throw attempt rate (attempts per 100 field-goal attempts)',
          away_value: 26.8,
          home_value: 22.1,
          unit: 'per100fga',
          higher_is_better: true,
          description: 'FTA / FGA * 100.',
        },
        {
          key: 'ortg',
          label: 'Offensive Rating',
          away_value: 113.5,
          home_value: 107.1,
          unit: 'per100poss',
          higher_is_better: true,
          description: 'Points scored per 100 possessions.',
        },
        {
          key: 'drtg',
          label: 'Defensive Rating',
          away_value: 107.1,
          home_value: 113.5,
          unit: 'per100poss',
          higher_is_better: false,
          description: 'Points allowed per 100 possessions (opponent ORtg).',
        },
        {
          key: 'pace',
          label: 'Pace',
          away_value: null,
          home_value: 93.4,
          unit: 'poss48',
          higher_is_better: null,
          description: 'Estimated possessions per 48 game minutes.',
        },
      ],
      context_splits: [
        { key: 'points_in_paint', label: 'Points in the Paint', away_value: 46, home_value: 42 },
        { key: 'fast_break_points', label: 'Fast Break Points', away_value: 18, home_value: 11 },
        { key: 'turnover_points', label: 'Points Off Turnovers', away_value: 20, home_value: 13 },
        { key: 'bench_points', label: 'Bench Points', away_value: 34, home_value: 22 },
        { key: 'largest_lead', label: 'Largest Lead', away_value: 12, home_value: 7 },
        { key: 'assists', label: 'Assists', away_value: 25, home_value: 21 },
        { key: 'steals', label: 'Steals', away_value: 9, home_value: 6 },
        { key: 'blocks', label: 'Blocks', away_value: 5, home_value: null },
      ],
      box_score: {
        away_totals: {
          minutes: 240,
          points: 106,
          fgm: 39,
          fga: 83,
          fg_pct: 47.0,
          fg3m: 12,
          fg3a: 31,
          fg3_pct: 38.7,
          ftm: 16,
          fta: 20,
          ft_pct: 80.0,
          oreb: 9,
          dreb: 33,
          reb: 42,
          ast: 25,
          stl: 9,
          blk: 5,
          tov: 11,
          team_tov: 1,
          total_tov: 12,
          pf: 19,
          efg_pct: 54.2,
          ts_pct: 58.1,
          possessions_est: 93.4,
          ortg: 113.5,
          drtg: 107.1,
          pace: 93.4,
        },
        home_totals: {
          minutes: 240,
          points: 100,
          fgm: 37,
          fga: 84,
          fg_pct: 44.0,
          fg3m: 10,
          fg3a: 29,
          fg3_pct: 34.5,
          ftm: 16,
          fta: 19,
          ft_pct: 84.2,
          oreb: 10,
          dreb: 30,
          reb: 40,
          ast: 21,
          stl: 6,
          blk: 4,
          tov: 14,
          team_tov: 0,
          total_tov: 14,
          pf: 18,
          efg_pct: 49.8,
          ts_pct: 54.0,
          possessions_est: 93.4,
          ortg: 107.1,
          drtg: 113.5,
          pace: 93.4,
        },
        away_players: [
          makePlayer({
            playerId: '1001',
            playerName: 'Tyrese Maxey',
            short_name: 'T. Maxey',
            starter: true,
            minutes: 36,
            points: 28,
            reb: 5,
            ast: 7,
            plus_minus: 11,
            game_score: 24.5,
          }),
          makePlayer({
            playerId: '1002',
            playerName: 'Paul George',
            short_name: 'P. George',
            position: 'F',
            starter: true,
            minutes: 32,
            points: 19,
            reb: 6,
            ast: 4,
            plus_minus: -3,
            fgm: 7,
            fga: 15,
            fg_pct: 46.7,
            fg3m: 3,
            fg3a: 7,
            fg3_pct: 42.9,
            ftm: 2,
            fta: 2,
            ft_pct: 100.0,
            efg_pct: 56.7,
            ts_pct: 59.8,
            game_score: 14.8,
          }),
          makePlayer({
            playerId: '1003',
            playerName: 'Kelly Oubre Jr.',
            short_name: 'K. Oubre Jr.',
            position: 'F',
            starter: false,
            minutes: 24,
            points: 31,
            reb: 4,
            ast: 2,
            plus_minus: 8,
            fgm: 11,
            fga: 16,
            fg_pct: 68.8,
            fg3m: 5,
            fg3a: 8,
            fg3_pct: 62.5,
            ftm: 4,
            fta: 4,
            ft_pct: 100.0,
            efg_pct: 84.4,
            ts_pct: 87.3,
            game_score: 26.2,
          }),
          makePlayer({
            playerId: '1004',
            playerName: 'Jared McCain',
            short_name: 'J. McCain',
            position: 'G',
            starter: false,
            minutes: 0,
            points: 0,
            oreb: 0,
            dreb: 0,
            reb: 0,
            ast: 1,
            stl: 0,
            blk: 0,
            tov: 0,
            pf: 0,
            plus_minus: null,
            fgm: 0,
            fga: 0,
            fg_pct: null,
            fg3m: 0,
            fg3a: 0,
            fg3_pct: null,
            ftm: 0,
            fta: 0,
            ft_pct: null,
            efg_pct: null,
            ts_pct: null,
            game_score: 0.7,
          }),
        ],
        home_players: [
          makePlayer({
            playerId: '2001',
            playerName: 'Jalen Brunson',
            short_name: 'J. Brunson',
            position: 'G',
            starter: true,
            minutes: 38,
            points: 30,
            reb: 3,
            ast: 8,
            plus_minus: -4,
            game_score: 23.1,
          }),
        ],
        away_inactive: [
          {
            playerId: '1099',
            playerName: 'Joel Embiid',
            position: 'C',
            reason: 'Left Knee Management',
          },
          {
            playerId: '1100',
            playerName: 'Kyle Lowry',
            position: 'G',
            reason: null,
          },
        ],
        home_inactive: [
          {
            playerId: '2099',
            playerName: 'Mitchell Robinson',
            position: 'C',
            reason: 'Ankle Sprain',
          },
        ],
        top_performers: [
          {
            teamAbbr: 'PHI',
            playerId: '1003',
            playerName: 'Kelly Oubre Jr.',
            points: 31,
            reb: 4,
            ast: 2,
            game_score: 26.2,
          },
          {
            teamAbbr: 'PHI',
            playerId: '1001',
            playerName: 'Tyrese Maxey',
            points: 28,
            reb: 5,
            ast: 7,
            game_score: 24.5,
          },
          {
            teamAbbr: 'NYK',
            playerId: '2001',
            playerName: 'Jalen Brunson',
            points: 30,
            reb: 3,
            ast: 8,
            game_score: 23.1,
          },
        ],
      },
      explainability: null,
      game_flow: null,
      ...overrides,
    },
  };
}

function makeXgboostShap(overrides: Partial<XgboostShapPayload> = {}): XgboostShapPayload {
  return {
    model_id: 'xgboost_feature_fusion_v1',
    model_label: 'XGBoost Feature Fusion (v1)',
    train_seasons_label: '2021–24',
    window_games: 10,
    away_prior_games_n: 14,
    home_prior_games_n: 15,
    base_value_log_odds: 0.125,
    total_log_odds: 0.742,
    predicted_home_win_prob: 0.677,
    factors: [
      {
        feature: 'diff_roll_efg',
        label: 'Rolling eFG% Diff',
        feature_value: 2.84,
        z_score: 1.42,
        shap_log_odds: 0.245,
        shap_prob_approx: 0.059,
      },
      {
        feature: 'diff_roll_pts',
        label: 'Rolling Points Diff',
        feature_value: 4.1,
        z_score: 1.18,
        shap_log_odds: 0.192,
        shap_prob_approx: 0.046,
      },
      {
        feature: 'diff_roll_tovp',
        label: 'Rolling TOV% Diff',
        feature_value: -1.65,
        z_score: 0.91,
        shap_log_odds: 0.138,
        shap_prob_approx: 0.033,
      },
      {
        feature: 'diff_fatigue_index',
        label: 'Fatigue Index Diff',
        feature_value: 0.75,
        z_score: -0.64,
        shap_log_odds: -0.098,
        shap_prob_approx: -0.024,
      },
      {
        feature: 'diff_roll_ts',
        label: 'Rolling TS% Diff',
        feature_value: 1.92,
        z_score: 0.72,
        shap_log_odds: 0.084,
        shap_prob_approx: 0.02,
      },
      {
        feature: 'diff_roll_oreb',
        label: 'Rolling OREB% Diff',
        feature_value: 1.3,
        z_score: 0.55,
        shap_log_odds: 0.067,
        shap_prob_approx: 0.016,
      },
      {
        feature: 'diff_roll_dreb',
        label: 'Rolling DREB% Diff',
        feature_value: -0.8,
        z_score: -0.41,
        shap_log_odds: -0.052,
        shap_prob_approx: -0.013,
      },
      {
        feature: 'diff_roll_ast',
        label: 'Rolling Assists Diff',
        feature_value: 1.45,
        z_score: 0.36,
        shap_log_odds: 0.041,
        shap_prob_approx: 0.01,
      },
      {
        feature: 'diff_days_rest',
        label: 'Days Rest Diff',
        feature_value: 1,
        z_score: 0.5,
        shap_log_odds: 0.033,
        shap_prob_approx: 0.008,
      },
      {
        feature: 'diff_is_b2b',
        label: 'Back-to-Back Indicator Diff',
        feature_value: 0,
        z_score: 0,
        shap_log_odds: 0.018,
        shap_prob_approx: 0.004,
      },
      {
        feature: 'diff_roll_stl',
        label: 'Rolling Steals Diff',
        feature_value: -0.4,
        z_score: -0.22,
        shap_log_odds: -0.016,
        shap_prob_approx: -0.004,
      },
      {
        feature: 'diff_roll_blk',
        label: 'Rolling Blocks Diff',
        feature_value: 0.35,
        z_score: 0.19,
        shap_log_odds: 0.011,
        shap_prob_approx: 0.003,
      },
      {
        feature: 'style_similarity',
        label: 'Matchup Style Similarity',
        feature_value: 0.84,
        z_score: 0.14,
        shap_log_odds: -0.006,
        shap_prob_approx: -0.001,
      },
    ],
    ...overrides,
  };
}

function makeExplainability(
  overrides: Partial<GameExplainabilityPayload> = {},
): GameExplainabilityPayload {
  return {
    projection_basis: 'logged_model_margin',
    predicted_margin: 4.4,
    predicted_home_win_prob: 0.644,
    sigma_game: 11.8,
    margin_waterfall: [
      {
        key: 'bottom_up',
        label: 'Bottom-Up Player Net',
        points: 2.1,
        detail: 'NYK starters +2.1 net pts',
      },
      {
        key: 'rapm',
        label: 'Regularized Adjusted Plus-Minus',
        points: 1.45,
        detail: 'Lineup priors +1.45 pts',
      },
      {
        key: 'shot_fatigue',
        label: 'Shot Profile & Fatigue',
        points: -0.85,
        detail: 'Away rest edge -0.85 pts',
      },
      {
        key: 'embeddings',
        label: 'Playstyle Embeddings',
        points: 0.35,
        detail: 'Perimeter matchup +0.35 pts',
      },
      {
        key: 'home_court',
        label: 'Home Court Advantage',
        points: 1.5,
        detail: 'Baseline arena factor +1.50 pts',
      },
      {
        key: 'schedule',
        label: 'Schedule Context',
        points: -0.16,
        detail: 'Travel distance adjustment -0.16 pts',
      },
      {
        key: 'rounding',
        label: 'Display Rounding Adjustment',
        points: 0.01,
        detail: 'Sum reconciliation +0.01 pts',
      },
    ],
    logged_forecast: {
      prediction_timestamp: '2026-10-20T17:15:00Z',
      log_source: 'LOGGED_PREGAME',
      brier_component: 0.4147,
      log_loss_component: 1.0328,
    },
    entering_baselines: [
      {
        teamAbbr: 'PHI',
        prior_games_n: 14,
        factors: [
          { key: 'efg_pct', entering: 52.4, realized: 54.2, difference: 1.8 },
          { key: 'tov_pct', entering: 13.8, realized: 12.1, difference: -1.7 },
          { key: 'oreb_pct', entering: 24.5, realized: 26.0, difference: 1.5 },
          { key: 'fta_rate', entering: 24.1, realized: 22.0, difference: -2.1 },
          { key: 'ortg', entering: 112.4, realized: 113.5, difference: 1.1 },
        ],
      },
      {
        teamAbbr: 'NYK',
        prior_games_n: 15,
        factors: [
          { key: 'efg_pct', entering: 53.9, realized: 49.8, difference: -4.1 },
          { key: 'tov_pct', entering: 12.6, realized: 14.0, difference: 1.4 },
          { key: 'oreb_pct', entering: 27.1, realized: 25.0, difference: -2.1 },
          { key: 'fta_rate', entering: 25.3, realized: 22.6, difference: -2.7 },
          { key: 'ortg', entering: 116.2, realized: 107.1, difference: -9.1 },
        ],
      },
    ],
    xgboost_shap: makeXgboostShap(),
    ...overrides,
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

function makeExplainabilityEnvelope(
  gameId: string,
  data: GameExplainabilityPayload,
): GameExplainabilityEnvelope {
  return { schema_version: '1.0', game_id: gameId, generated_at: '2026-11-16T17:00:00Z', data };
}

const explainabilityUrl = (gameId: string) => `${BASE_PATH}/data/explainability/${gameId}.json`;

/** Serve JSON by exact URL; anything else answers 404. */
function stubFetchByUrl(routes: Record<string, unknown>) {
  const fetchMock = vi.fn<typeof fetch>().mockImplementation(async (input) => {
    const url = String(input);
    const hit = Object.prototype.hasOwnProperty.call(routes, url);
    return {
      ok: hit,
      status: hit ? 200 : 404,
      json: async () => (hit ? routes[url] : {}),
    } as Response;
  });
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe('GameDetailModal closed & missing-data states', () => {
  it('renders nothing and issues no fetch when matchup is null', () => {
    const fetchMock = vi.fn<typeof fetch>();
    vi.stubGlobal('fetch', fetchMock);
    const { container } = render(<GameDetailModal matchup={null} onClose={vi.fn()} />);
    expect(container).toBeEmptyDOMElement();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('makes no fetch and renders unplayed missing-data message when !is_completed and !has_game_detail', () => {
    const fetchMock = vi.fn<typeof fetch>();
    vi.stubGlobal('fetch', fetchMock);
    const matchup = makeMatchup({
      is_completed: false,
      has_box_score: false,
      has_game_detail: false,
      home_score: null,
      away_score: null,
      actual_margin: null,
      actual_winner: null,
      prediction_correct: null,
    });

    render(<GameDetailModal matchup={matchup} slateLabel="Week 1 · Oct 20 – Oct 26" onClose={vi.fn()} />);

    expect(fetchMock).not.toHaveBeenCalled();
    expect(screen.getByRole('dialog')).toBeInTheDocument();
    expect(screen.getByText('Box score appears after the game.')).toBeInTheDocument();
    expect(screen.getByText('76ers @ Knicks')).toBeInTheDocument();
    expect(
      screen.queryByRole('tablist', { name: /Game detail sections/i }),
    ).not.toBeInTheDocument();
  });

  it('makes no fetch when has_game_detail is omitted (undefined)', () => {
    const fetchMock = vi.fn<typeof fetch>();
    vi.stubGlobal('fetch', fetchMock);
    const matchup = makeMatchup({
      is_completed: false,
      has_box_score: undefined,
      has_game_detail: undefined,
    });

    render(<GameDetailModal matchup={matchup} onClose={vi.fn()} />);

    expect(fetchMock).not.toHaveBeenCalled();
    expect(screen.getByText('Box score appears after the game.')).toBeInTheDocument();
    expect(
      screen.queryByRole('tablist', { name: /Game detail sections/i }),
    ).not.toBeInTheDocument();
  });

  it('makes no fetch and renders delayed box score message when is_completed && !has_box_score && !has_game_detail', () => {
    const fetchMock = vi.fn<typeof fetch>();
    vi.stubGlobal('fetch', fetchMock);
    const matchup = makeMatchup({
      is_completed: true,
      has_box_score: false,
      has_game_detail: false,
    });

    render(<GameDetailModal matchup={matchup} onClose={vi.fn()} />);

    expect(fetchMock).not.toHaveBeenCalled();
    expect(
      screen.getByText(
        'Final score recorded. The full box score is added on a later data refresh, usually within a day.',
      ),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole('tablist', { name: /Game detail sections/i }),
    ).not.toBeInTheDocument();
  });
});

describe('GameDetailModal fetch error & retry', () => {
  it('logs a console.error contract violation on 404 when has_game_detail is true and retries on click', async () => {
    const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const envelope = makeDetailEnvelope();
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce({
        ok: false,
        status: 404,
        json: async () => ({ error: 'Not found' }),
      } as Response)
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => envelope,
      } as Response);
    vi.stubGlobal('fetch', fetchMock);

    const matchup = makeMatchup({ game_id: '401909089', has_game_detail: true });
    render(<GameDetailModal matchup={matchup} onClose={vi.fn()} />);

    const retryBtn = await screen.findByRole('button', { name: /retry/i });
    expect(retryBtn).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledWith(`${BASE_PATH}/data/games/401909089.json`);
    expect(consoleSpy).toHaveBeenCalledWith(expect.stringMatching(/contract violation/i));

    fireEvent.click(retryBtn);

    await waitFor(() => {
      expect(screen.getByText('Player Box Score')).toBeInTheDocument();
    });
    expect(screen.getByRole('tab', { name: /Four Factors/i })).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('renders error alert and Retry button on network failure and reloads when Retry is clicked', async () => {
    const envelope = makeDetailEnvelope();
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockRejectedValueOnce(new Error('Network offline'))
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => envelope,
      } as Response);
    vi.stubGlobal('fetch', fetchMock);

    render(<GameDetailModal matchup={makeMatchup()} onClose={vi.fn()} />);

    expect(await screen.findByRole('alert')).toHaveTextContent('Network offline');
    const retryBtn = screen.getByRole('button', { name: /retry/i });
    fireEvent.click(retryBtn);

    await waitFor(() => {
      expect(screen.getByText('Player Box Score')).toBeInTheDocument();
    });
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });
});

describe('GameDetailModal accessibility, focus trap & restoration', () => {
  it('exposes ARIA dialog attributes, traps Tab/Shift+Tab inside the modal, and restores focus on Escape', async () => {
    const user = userEvent.setup();
    stubFetchJson(makeDetailEnvelope());

    const Harness: React.FC = () => {
      const [openMatchup, setOpenMatchup] = useState<MatchupGame | null>(null);
      const openerRef = useRef<HTMLButtonElement | null>(null);
      return (
        <div>
          <button
            ref={openerRef}
            type="button"
            onClick={() => setOpenMatchup(makeMatchup())}
          >
            Open game detail
          </button>
          <button type="button">Outside button</button>
          <GameDetailModal
            matchup={openMatchup}
            onClose={() => setOpenMatchup(null)}
            returnFocusTo={openerRef.current}
          />
        </div>
      );
    };

    render(<Harness />);

    const opener = screen.getByRole('button', { name: 'Open game detail' });
    opener.focus();
    await user.click(opener);

    const dialog = await screen.findByRole('dialog');
    expect(dialog).toHaveAttribute('aria-modal', 'true');
    expect(dialog).toHaveAttribute('aria-labelledby', 'game-detail-modal-title');
    expect(document.getElementById('game-detail-modal-title')).toHaveTextContent('76ers @ Knicks');

    await screen.findByText('Player Box Score');

    const closeBtn = screen.getByRole('button', { name: /close game detail modal/i });
    expect(document.activeElement).toBe(closeBtn);

    // Shift+Tab from first focusable element inside the modal wraps to the last focusable element inside the modal.
    await user.tab({ shift: true });
    const allButtons = within(dialog).getAllByRole('button');
    const lastBtn = allButtons[allButtons.length - 1];
    expect(document.activeElement).toBe(lastBtn);
    expect(dialog.contains(document.activeElement)).toBe(true);

    // Tab from the last focusable element wraps back to the first focusable element (closeBtn).
    await user.tab();
    expect(document.activeElement).toBe(closeBtn);

    // Pressing Escape closes the modal and restores focus to the opener button.
    await user.keyboard('{Escape}');
    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });
    expect(document.activeElement).toBe(opener);
  });

  it('captures document.activeElement automatically when returnFocusTo is omitted and restores on backdrop click', async () => {
    stubFetchJson(makeDetailEnvelope());

    const Harness: React.FC = () => {
      const [openMatchup, setOpenMatchup] = useState<MatchupGame | null>(null);
      return (
        <div>
          <button type="button" onClick={() => setOpenMatchup(makeMatchup())}>
            Inspect matchup
          </button>
          <GameDetailModal matchup={openMatchup} onClose={() => setOpenMatchup(null)} />
        </div>
      );
    };

    render(<Harness />);
    const trigger = screen.getByRole('button', { name: 'Inspect matchup' });
    trigger.focus();
    fireEvent.click(trigger);

    await screen.findByText('Player Box Score');

    // Clicking inside the dialog does not close it.
    fireEvent.click(screen.getByRole('dialog'));
    expect(screen.getByRole('dialog')).toBeInTheDocument();

    // Clicking the backdrop closes it and restores focus to the opener.
    fireEvent.click(screen.getByTestId('game-detail-backdrop'));
    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });
    expect(document.activeElement).toBe(trigger);
  });
});

describe('GameDetailModal empirical Phase 1 views & box score sorting', () => {
  it('renders 3 section tabs, Box Score by default, Four Factors with exact fta_rate label, context splits, <1 min, em-dash nulls, totals, and collapsible inactive list', async () => {
    stubFetchJson(makeDetailEnvelope());
    const { container } = render(<GameDetailModal matchup={makeMatchup()} onClose={vi.fn()} />);

    await screen.findByText('Player Box Score');

    // Section tabs: Box Score is active by default alongside Four Factors & Context Splits
    const sectionTabs = screen.getByRole('tablist', { name: /Game detail sections/i });
    const boxScoreTab = within(sectionTabs).getByRole('tab', { name: /Box Score/i });
    const fourFactorsTab = within(sectionTabs).getByRole('tab', { name: /Four Factors/i });
    const contextSplitsTab = within(sectionTabs).getByRole('tab', { name: /Context Splits/i });

    expect(boxScoreTab).toHaveAttribute('aria-selected', 'true');
    expect(fourFactorsTab).toHaveAttribute('aria-selected', 'false');
    expect(contextSplitsTab).toHaveAttribute('aria-selected', 'false');

    // Non-active section headings are hidden while Box Score tab is selected
    expect(screen.queryByRole('heading', { name: /Efficiency & Four Factors/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: /Play-Style & Context Splits/i })).not.toBeInTheDocument();

    // Model ahead + actual winner copy + Top Performers inside Box Score tab (without forbidden verdict words)
    expect(screen.getByText(/Model had/i)).toBeInTheDocument();
    expect(screen.getByText(/Top Performers/i)).toBeInTheDocument();
    expect(screen.getAllByText('26.2').length).toBeGreaterThanOrEqual(2);
    expect(container.textContent).not.toMatch(/NaN|undefined/);
    expect(container.textContent).not.toMatch(
      /\b(odds|spread|moneyline|over_under|kelly|sportsbook|sharp_book|implied_probability|market_odds|value_bets|favorite|upset|covered)\b/i,
    );

    // Player box score rows: Starters, Bench, <1 minutes, null percentages as "—"
    expect(screen.getByText('Starters')).toBeInTheDocument();
    expect(screen.getByText('Bench')).toBeInTheDocument();
    expect(screen.getByText('Team Totals')).toBeInTheDocument();
    expect(screen.getByText(/team turnover/i)).toBeInTheDocument();

    const mccainRow = screen.getByRole('row', { name: /Jared McCain/i });
    const mccainCells = within(mccainRow).getAllByRole('cell');
    // MIN cell is first <td> after player <th>
    expect(mccainCells[0]).toHaveTextContent('<1');
    // Null shooting percentages (FG%, 3P%, FT%, eFG%, TS%) and null +/- render "—"
    expect(within(mccainRow).getAllByText('—').length).toBeGreaterThanOrEqual(6);
    expect(mccainRow.textContent).not.toContain('0.0%');

    // Collapsible Inactive / Did Not Play disclosure with reason and fallback
    const inactiveSummary = screen.getByText(/Inactive \/ Did Not Play \(2\)/i);
    const inactiveDetails = inactiveSummary.closest('details');
    expect(inactiveDetails).not.toBeNull();
    expect(inactiveDetails).not.toHaveAttribute('open');
    fireEvent.click(inactiveSummary);
    expect(screen.getByText('Joel Embiid')).toBeInTheDocument();
    expect(screen.getByText('Left Knee Management')).toBeInTheDocument();
    expect(screen.getByText('Kyle Lowry')).toBeInTheDocument();
    expect(screen.getByText('No reason listed')).toBeInTheDocument();

    // Switch to Home team box score tab (team_tov === 0, so no team turnover note)
    fireEvent.click(screen.getByRole('tab', { name: /NYK · Knicks/i }));
    expect(screen.getAllByText('Jalen Brunson').length).toBeGreaterThanOrEqual(1);
    expect(screen.getByText('Mitchell Robinson')).toBeInTheDocument();
    expect(screen.getByText('Ankle Sprain')).toBeInTheDocument();
    expect(screen.queryByText(/team turnover/i)).not.toBeInTheDocument();

    // Switch to Four Factors section tab
    fireEvent.click(fourFactorsTab);
    expect(fourFactorsTab).toHaveAttribute('aria-selected', 'true');
    expect(boxScoreTab).toHaveAttribute('aria-selected', 'false');

    const factorsSection = screen
      .getByRole('heading', { name: /Efficiency & Four Factors/i })
      .closest('section')!;
    const factorsTable = within(factorsSection).getByRole('table');
    expect(
      within(factorsTable).getByText(
        'Free-throw attempt rate (attempts per 100 field-goal attempts)',
      ),
    ).toBeInTheDocument();
    expect(within(factorsTable).getByText('54.2%')).toBeInTheDocument();
    expect(within(factorsTable).getByText('26.8')).toBeInTheDocument();
    expect(within(factorsTable).getByText('—')).toBeInTheDocument();

    // Switch to Context Splits section tab
    fireEvent.click(contextSplitsTab);
    expect(contextSplitsTab).toHaveAttribute('aria-selected', 'true');
    expect(screen.getByRole('heading', { name: /Play-Style & Context Splits/i })).toBeInTheDocument();
    expect(screen.getByText('Points in the Paint')).toBeInTheDocument();
    expect(screen.getByText('Fast Break Points')).toBeInTheDocument();
    expect(screen.getByText('Points Off Turnovers')).toBeInTheDocument();
    expect(screen.getByText('Bench Points')).toBeInTheDocument();
    expect(screen.getByText('Largest Lead')).toBeInTheDocument();
    expect(screen.getByText('Assists')).toBeInTheDocument();
    expect(screen.getByText('Steals')).toBeInTheDocument();
    expect(screen.getByText('Blocks')).toBeInTheDocument();
  });

  it('supports sortable columns with aria-sort state transitions and proper row ordering', async () => {
    stubFetchJson(makeDetailEnvelope());
    render(<GameDetailModal matchup={makeMatchup()} onClose={vi.fn()} />);

    await screen.findByText('Player Box Score');

    const boxRegion = screen.getByRole('tabpanel');
    const boxTable = within(boxRegion).getByRole('table');

    // Check all 11 required sortable columns exist with initial aria-sort="none"
    const requiredButtonNames = [
      /Minutes \(MIN\)/i,
      /Points \(PTS\)/i,
      /Rebounds \(REB\)/i,
      /Assists \(AST\)/i,
      /Steals \(STL\)/i,
      /Blocks \(BLK\)/i,
      /Turnovers \(TOV\)/i,
      /Plus-minus/i,
      /Effective field goal percentage \(eFG%\)/i,
      /True shooting percentage \(TS%\)/i,
      /Game Score \(GmSc\)/i,
    ];
    for (const pattern of requiredButtonNames) {
      const btn = within(boxTable).getByRole('button', { name: pattern });
      expect(btn.closest('th')).toHaveAttribute('aria-sort', 'none');
    }

    const ptsBtn = within(boxTable).getByRole('button', { name: /Points \(PTS\)/i });
    const ptsHeader = ptsBtn.closest('th')!;

    // Click PTS once -> descending
    fireEvent.click(ptsBtn);
    expect(ptsHeader).toHaveAttribute('aria-sort', 'descending');

    const getPlayerOrder = () =>
      Array.from(boxTable.querySelectorAll('tbody tr th[scope="row"]')).map((th) =>
        th.textContent?.trim() ?? '',
      );

    let names = getPlayerOrder();
    expect(names[0]).toContain('Kelly Oubre Jr.');
    expect(names[1]).toContain('Tyrese Maxey');
    expect(names[2]).toContain('Paul George');
    expect(names[3]).toContain('Jared McCain');

    // Click PTS again -> ascending
    fireEvent.click(ptsBtn);
    expect(ptsHeader).toHaveAttribute('aria-sort', 'ascending');

    names = getPlayerOrder();
    expect(names[0]).toContain('Jared McCain');
    expect(names[1]).toContain('Paul George');
    expect(names[2]).toContain('Tyrese Maxey');
    expect(names[3]).toContain('Kelly Oubre Jr.');

    // Sorting a nullable column (eFG%) keeps null values at the bottom even in ascending order
    const efgBtn = within(boxTable).getByRole('button', {
      name: /Effective field goal percentage \(eFG%\)/i,
    });
    fireEvent.click(efgBtn); // descending
    expect(efgBtn.closest('th')).toHaveAttribute('aria-sort', 'descending');
    expect(ptsHeader).toHaveAttribute('aria-sort', 'none');

    fireEvent.click(efgBtn); // ascending
    expect(efgBtn.closest('th')).toHaveAttribute('aria-sort', 'ascending');
    names = getPlayerOrder();
    expect(names[0]).toContain('Paul George'); // 56.7%
    expect(names[1]).toContain('Tyrese Maxey'); // 60.0%
    expect(names[2]).toContain('Kelly Oubre Jr.'); // 84.4%
    expect(names[3]).toContain('Jared McCain'); // null -> bottom

    // Clicking "Group: Starters / Bench" restores grouped order and resets aria-sort
    fireEvent.click(screen.getByRole('button', { name: /Group: Starters \/ Bench/i }));
    expect(efgBtn.closest('th')).toHaveAttribute('aria-sort', 'none');
    expect(screen.getByText('Starters')).toBeInTheDocument();
    expect(screen.getByText('Bench')).toBeInTheDocument();
  });

  it('handles null efficiency_factors and context_splits without crashing and restores focus on close button click', async () => {
    stubFetchJson(
      makeDetailEnvelope({
        efficiency_factors: null,
        context_splits: null,
      }),
    );

    const Harness: React.FC = () => {
      const [openMatchup, setOpenMatchup] = useState<MatchupGame | null>(null);
      return (
        <div>
          <button type="button" onClick={() => setOpenMatchup(makeMatchup())}>
            Open modal
          </button>
          <GameDetailModal matchup={openMatchup} onClose={() => setOpenMatchup(null)} />
        </div>
      );
    };

    render(<Harness />);
    const opener = screen.getByRole('button', { name: 'Open modal' });
    opener.focus();
    fireEvent.click(opener);

    await screen.findByText('Player Box Score');
    expect(screen.getByRole('tab', { name: /Box Score/i })).toBeInTheDocument();
    expect(screen.queryByRole('tab', { name: /Four Factors/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('tab', { name: /Context Splits/i })).not.toBeInTheDocument();
    expect(screen.queryByText(/Efficiency & Four Factors/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/Play-Style & Context Splits/i)).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /close game detail modal/i }));
    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });
    expect(document.activeElement).toBe(opener);
  });

  it('renders 4 tabs for completed game with explainability, defaulting to Box Score and opening Attribution & SHAP', async () => {
    const user = userEvent.setup();
    const explainability = makeExplainability();
    stubFetchJson(makeDetailEnvelope({ explainability }));

    render(
      <GameDetailModal
        matchup={makeMatchup({ has_game_detail: true })}
        onClose={vi.fn()}
      />,
    );

    await screen.findByText('Player Box Score');
    const boxTab = screen.getByRole('tab', { name: /Box Score/i });
    const fourTab = screen.getByRole('tab', { name: /Four Factors/i });
    const contextTab = screen.getByRole('tab', { name: /Context Splits/i });
    const attributionTab = screen.getByRole('tab', { name: /Attribution & SHAP/i });

    expect(boxTab).toHaveAttribute('aria-selected', 'true');
    expect(fourTab).toHaveAttribute('aria-selected', 'false');
    expect(contextTab).toHaveAttribute('aria-selected', 'false');
    expect(attributionTab).toHaveAttribute('aria-selected', 'false');

    await user.click(attributionTab);
    expect(attributionTab).toHaveAttribute('aria-selected', 'true');
    expect(screen.getByText('Primary Ensemble Margin Waterfall')).toBeInTheDocument();
    expect(
      screen.getByText('Secondary Diagnostic Model: XGBoost Feature Fusion (TreeSHAP)'),
    ).toBeInTheDocument();
    expect(screen.getByText('Entering Baselines vs Realized Four Factors')).toBeInTheDocument();
  });

  it('shows "Travel data unavailable" instead of a number for the schedule step when travel context is missing', async () => {
    const user = userEvent.setup();
    const base = makeExplainability();
    const explainability = makeExplainability({
      schedule_context_available: false,
      margin_waterfall: (base.margin_waterfall ?? []).map((st) =>
        st.key === 'schedule'
          ? { ...st, points: 0, detail: 'Travel data unavailable' }
          : st,
      ),
    });
    stubFetchJson(makeDetailEnvelope({ explainability }));

    render(
      <GameDetailModal matchup={makeMatchup({ has_game_detail: true })} onClose={vi.fn()} />,
    );
    await screen.findByText('Player Box Score');
    await user.click(screen.getByRole('tab', { name: /Attribution & SHAP/i }));

    expect(screen.getAllByText('Travel data unavailable').length).toBeGreaterThanOrEqual(2);
    expect(screen.queryByLabelText(/Schedule Context: [+-−]?0\.00 points/)).toBeNull();
  });

  it('displays verbatim provenance banners for LOGGED_PREGAME, missing-waterfall LOGGED_PREGAME, BACKTEST_PREWEEK, BACKTEST_SEEDED, and primary_ensemble basis', async () => {
    const user = userEvent.setup();

    const pregameExplainability = makeExplainability({
      logged_forecast: {
        prediction_timestamp: '2026-10-20T17:15:00Z',
        log_source: 'LOGGED_PREGAME',
        brier_component: 0.4147,
        log_loss_component: 1.0328,
      },
    });
    const missingWaterfallExplainability = makeExplainability({
      margin_waterfall: null,
      predicted_margin: 3.75,
      predicted_home_win_prob: 0.625,
      logged_forecast: {
        prediction_timestamp: '2026-10-21T16:00:00Z',
        log_source: 'LOGGED_PREGAME',
        brier_component: null,
        log_loss_component: null,
      },
    });
    const preweekExplainability = makeExplainability({
      logged_forecast: {
        prediction_timestamp: '2026-10-22T12:00:00Z',
        log_source: 'BACKTEST_PREWEEK',
        brier_component: null,
        log_loss_component: null,
      },
    });
    const seededExplainability = makeExplainability({
      projection_basis: 'primary_ensemble',
      logged_forecast: {
        prediction_timestamp: '2026-10-23T09:00:00Z',
        log_source: 'BACKTEST_SEEDED',
        brier_component: null,
        log_loss_component: null,
      },
    });
    // Games without a detail file fetch explainability/<id>.json on open (issue #147).
    stubFetchByUrl({
      [`${BASE_PATH}/data/games/401909089.json`]: makeDetailEnvelope({ explainability: pregameExplainability }),
      [explainabilityUrl('401909090')]: makeExplainabilityEnvelope('401909090', missingWaterfallExplainability),
      [explainabilityUrl('401909091')]: makeExplainabilityEnvelope('401909091', preweekExplainability),
      [explainabilityUrl('401909092')]: makeExplainabilityEnvelope('401909092', seededExplainability),
    });
    const { rerender } = render(
      <GameDetailModal matchup={makeMatchup({ has_game_detail: true })} onClose={vi.fn()} />,
    );

    await screen.findByText('Player Box Score');
    await user.click(screen.getByRole('tab', { name: /Attribution & SHAP/i }));
    expect(screen.getByText('Forecast recorded before the game.')).toBeInTheDocument();
    expect(screen.getByText('Logged Pre-Game')).toBeInTheDocument();
    expect(screen.getByText(/Recorded: 2026-10-20T17:15:00Z/)).toBeInTheDocument();
    expect(screen.getByText(/Brier: 0\.4147/)).toBeInTheDocument();
    expect(screen.getByText(/Log Loss: 1\.0328/)).toBeInTheDocument();

    // Switch to LOGGED_PREGAME with margin_waterfall: null (still preserves recorded forecast)
    rerender(
      <GameDetailModal
        matchup={makeMatchup({
          game_id: '401909090',
          has_game_detail: false,
          has_explainability: true,
          is_completed: true,
        })}
        onClose={vi.fn()}
      />,
    );

    expect(
      await screen.findByText(
        'Forecast recorded before the game. The ratings behind it were not stored, so only the recorded forecast is shown.',
      ),
    ).toBeInTheDocument();
    expect(screen.getByText(/NYK Margin: \+3\.75 pts/)).toBeInTheDocument();
    expect(screen.getByText(/NYK Win Prob: 62\.5%/)).toBeInTheDocument();

    // Switch to BACKTEST_PREWEEK
    rerender(
      <GameDetailModal
        matchup={makeMatchup({
          game_id: '401909091',
          has_game_detail: false,
          has_explainability: true,
          is_completed: false,
        })}
        onClose={vi.fn()}
      />,
    );
    expect(
      await screen.findByText(
        'Backtest. Logging was unavailable that day; this forecast was rebuilt afterwards from ratings published before the game.',
      ),
    ).toBeInTheDocument();
    expect(screen.getByText('Backtest · Pre-Week')).toBeInTheDocument();

    // Switch to BACKTEST_SEEDED with projection_basis: 'primary_ensemble'
    rerender(
      <GameDetailModal
        matchup={makeMatchup({
          game_id: '401909092',
          has_game_detail: false,
          is_completed: false,
          projection_basis: 'primary_ensemble',
          has_explainability: true,
        })}
        onClose={vi.fn()}
      />,
    );
    expect(
      await screen.findByText('Backtest computed after the game from later ratings. Not a pre-game forecast.'),
    ).toBeInTheDocument();
    expect(screen.getByText('Backtest · Seeded')).toBeInTheDocument();
    expect(screen.getByText('Live Primary Ensemble Ratings')).toBeInTheDocument();
  });

  it('renders Primary Ensemble waterfall bars, rounding residual, separate Secondary Diagnostic Model TreeSHAP with 6->13 toggle, Entering Baselines, and passes forbidden copy check', async () => {
    const user = userEvent.setup();
    const explainability = makeExplainability();
    stubFetchJson(makeDetailEnvelope({ explainability }));

    const { container } = render(
      <GameDetailModal
        matchup={makeMatchup({ has_game_detail: true })}
        onClose={vi.fn()}
      />,
    );

    await screen.findByText('Player Box Score');
    await user.click(screen.getByRole('tab', { name: /Attribution & SHAP/i }));

    // Primary Ensemble badge and conversion notation
    expect(screen.getByText('Primary Ensemble')).toBeInTheDocument();
    expect(screen.getByText(/σ = 11\.8 · Φ\(margin \/ sigma_game\)/)).toBeInTheDocument();
    expect(screen.getByText('Bottom-Up Player Net')).toBeInTheDocument();
    expect(screen.getByText('NYK starters +2.1 net pts')).toBeInTheDocument();
    expect(screen.getByText('Display Rounding Adjustment')).toBeInTheDocument();
    expect(screen.getByText('Arithmetic residual')).toBeInTheDocument();

    // Secondary Diagnostic Model distinctly badged and showing its own win prob
    expect(screen.getByText('Secondary Diagnostic Model')).toBeInTheDocument();
    expect(screen.getByText(/NYK Diagnostic Win Prob: 67\.7%/)).toBeInTheDocument();
    expect(screen.getByText(/Trained: 2021–24/)).toBeInTheDocument();
    expect(screen.getByText(/Base logit \+0\.125 → Total logit \+0\.742/)).toBeInTheDocument();

    const shapTable = screen.getByRole('table', {
      name: /Secondary Diagnostic Model TreeSHAP feature contributions/i,
    });
    // Initially top 6 feature rows + 1 header row = 7
    expect(within(shapTable).getAllByRole('row')).toHaveLength(7);
    expect(within(shapTable).getByText('Rolling eFG% Diff')).toBeInTheDocument();
    expect(within(shapTable).getByText('+5.9 pp')).toBeInTheDocument();
    expect(within(shapTable).queryByText('Matchup Style Similarity')).not.toBeInTheDocument();

    // Expand all 13 TreeSHAP factors
    const expandBtn = screen.getByRole('button', { name: /Show all 13/i });
    expect(expandBtn).toHaveAttribute('aria-expanded', 'false');
    await user.click(expandBtn);
    expect(expandBtn).toHaveAttribute('aria-expanded', 'true');
    expect(within(shapTable).getAllByRole('row')).toHaveLength(14);
    expect(within(shapTable).getByText('Matchup Style Similarity')).toBeInTheDocument();
    expect(within(shapTable).getByText('-0.1 pp')).toBeInTheDocument();

    // Collapse back to top 6
    await user.click(screen.getByRole('button', { name: /Show top 6/i }));
    expect(within(shapTable).getAllByRole('row')).toHaveLength(7);

    // Expand again before checking full modal text for forbidden terms
    await user.click(screen.getByRole('button', { name: /Show all 13/i }));

    // Entering Baselines table verification
    const nykBaselineTable = screen.getByRole('table', {
      name: /NYK entering baselines vs realized Four Factors/i,
    });
    expect(within(nykBaselineTable).getByText('Effective FG% (eFG%)')).toBeInTheDocument();
    expect(within(nykBaselineTable).getByText('53.9%')).toBeInTheDocument();
    expect(within(nykBaselineTable).getByText('49.8%')).toBeInTheDocument();
    expect(within(nykBaselineTable).getByText('-4.1%')).toBeInTheDocument();
    expect(within(nykBaselineTable).getByText('Offensive Rating (ORtg)')).toBeInTheDocument();
    expect(screen.getByText('Prior games: 14')).toBeInTheDocument();
    expect(screen.getByText('Prior games: 15')).toBeInTheDocument();

    expect(container.textContent).not.toMatch(
      /\b(odds|spread|moneyline|over_under|kelly|sportsbook|sharp_book|implied_probability|market_odds|value_bets|favorite|upset|covered)\b/i,
    );
    expect(container.textContent).not.toContain('NaN');
    expect(container.textContent).not.toContain('undefined');
  });

  it('colors Entering Baselines diffs by favorable direction: TOV% is lower-is-better, other factors unchanged (#129)', async () => {
    const user = userEvent.setup();
    const explainability = makeExplainability();
    stubFetchJson(makeDetailEnvelope({ explainability }));

    render(
      <GameDetailModal
        matchup={makeMatchup({ has_game_detail: true })}
        onClose={vi.fn()}
      />,
    );

    await screen.findByText('Player Box Score');
    await user.click(screen.getByRole('tab', { name: /Attribution & SHAP/i }));

    const diffCell = (teamAbbr: string, factorLabel: string) => {
      const table = screen.getByRole('table', {
        name: new RegExp(`${teamAbbr} entering baselines vs realized Four Factors`, 'i'),
      });
      const row = within(table).getByText(factorLabel).closest('tr');
      expect(row).not.toBeNull();
      const cells = within(row as HTMLTableRowElement).getAllByRole('cell');
      return cells[cells.length - 1];
    };

    // TOV%: negative diff (fewer turnovers) is favorable -> emerald; sign/number unchanged.
    const phiTov = diffCell('PHI', 'Turnover Rate (TOV%)');
    expect(phiTov).toHaveTextContent('-1.7%');
    expect(phiTov).toHaveClass('text-emerald-300');
    expect(phiTov).not.toHaveClass('text-sky-300');

    // TOV%: positive diff (more turnovers) is unfavorable -> sky.
    const nykTov = diffCell('NYK', 'Turnover Rate (TOV%)');
    expect(nykTov).toHaveTextContent('+1.4%');
    expect(nykTov).toHaveClass('text-sky-300');
    expect(nykTov).not.toHaveClass('text-emerald-300');

    // Higher-is-better factors keep sign-based coloring.
    expect(diffCell('PHI', 'FT Attempt Rate (FTA/FGA)')).toHaveClass('text-sky-300');
    expect(diffCell('PHI', 'Effective FG% (eFG%)')).toHaveClass('text-emerald-300');
    expect(diffCell('NYK', 'Effective FG% (eFG%)')).toHaveClass('text-sky-300');
    expect(diffCell('PHI', 'Offensive Rating (ORtg)')).toHaveClass('text-emerald-300');
  });

  it('renders a collapsed-by-default "How to read this" explainer in the TreeSHAP card (#129)', async () => {
    const user = userEvent.setup();
    const explainability = makeExplainability();
    stubFetchJson(makeDetailEnvelope({ explainability }));

    render(
      <GameDetailModal
        matchup={makeMatchup({ has_game_detail: true })}
        onClose={vi.fn()}
      />,
    );

    await screen.findByText('Player Box Score');
    await user.click(screen.getByRole('tab', { name: /Attribution & SHAP/i }));

    const explainer = screen.getByTestId('shap-explainer');
    expect(explainer.tagName).toBe('DETAILS');
    expect(explainer).not.toHaveAttribute('open');
    expect((explainer as HTMLDetailsElement).open).toBe(false);

    const summary = within(explainer).getByText('How to read this').closest('summary');
    expect(summary).not.toBeNull();

    const text = explainer.textContent ?? '';
    expect(text).toMatch(/home team/i);
    expect(text).toMatch(/Raw Value/);
    expect(text).toMatch(/home minus away/i);
    expect(text).toMatch(/L10 games/);
    expect(text).toMatch(/SHAP Logit/);
    expect(text).toMatch(/base logit/i);
    expect(text).toMatch(/Δ Prob \(pp\)/);
    expect(text).toMatch(/do not add up exactly/i);
    expect(text).toMatch(/never blended/i);

    await user.click(summary as HTMLElement);
    expect((explainer as HTMLDetailsElement).open).toBe(true);
  });

  it('fetches explainability/<id>.json for an upcoming game, shows a loading state, then opens Attribution & SHAP with the missing-box notice (#147)', async () => {
    const user = userEvent.setup();

    const upcomingExplainability = makeExplainability({
      projection_basis: 'primary_ensemble',
      xgboost_shap: null,
      entering_baselines: null,
      logged_forecast: null,
    });
    const fetchSpy = stubFetchByUrl({
      [explainabilityUrl('0022600999')]: makeExplainabilityEnvelope('0022600999', upcomingExplainability),
    });

    const unplayedMatchup = makeMatchup({
      game_id: '0022600999',
      is_completed: false,
      has_box_score: false,
      has_game_detail: false,
      has_explainability: true,
      projection_basis: 'primary_ensemble',
      home_score: null,
      away_score: null,
      actual_margin: null,
      actual_winner: null,
      prediction_correct: null,
    });

    render(<GameDetailModal matchup={unplayedMatchup} onClose={vi.fn()} />);

    // Loading state is visible while the file is in flight; never a blank body.
    expect(screen.getByRole('status')).toHaveTextContent('Loading attribution...');

    const attributionTab = await screen.findByRole('tab', { name: /Attribution & SHAP/i });
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    expect(fetchSpy).toHaveBeenCalledWith(explainabilityUrl('0022600999'));
    expect(screen.queryByRole('status')).not.toBeInTheDocument();

    const boxTab = screen.getByRole('tab', { name: /Box Score/i });
    expect(attributionTab).toHaveAttribute('aria-selected', 'true');
    expect(boxTab).toHaveAttribute('aria-selected', 'false');

    expect(screen.getByText('Box score appears after the game.')).toBeInTheDocument();
    expect(screen.getByText('Live Primary Ensemble Ratings')).toBeInTheDocument();
    expect(screen.getByText('Primary Ensemble Margin Waterfall')).toBeInTheDocument();
    expect(
      screen.getByText(/Secondary XGBoost TreeSHAP diagnostic is unavailable/i),
    ).toBeInTheDocument();
    expect(
      screen.getByText(/Entering baselines are unavailable for season openers/i),
    ).toBeInTheDocument();

    await user.click(boxTab);
    expect(boxTab).toHaveAttribute('aria-selected', 'true');
    expect(screen.getByText('Box score appears after the game.')).toBeInTheDocument();
    expect(fetchSpy).toHaveBeenCalledTimes(1);
  });

  it('reads attribution for a completed game with a detail file from games/<id>.json only, never explainability/<id>.json (#147)', async () => {
    const user = userEvent.setup();
    const explainability = makeExplainability();
    const fetchSpy = stubFetchByUrl({
      [`${BASE_PATH}/data/games/401909089.json`]: makeDetailEnvelope({ explainability }),
    });

    render(
      <GameDetailModal
        matchup={makeMatchup({ has_game_detail: true, has_explainability: false })}
        onClose={vi.fn()}
      />,
    );

    expect(screen.getByRole('status')).toHaveTextContent(/Loading empirical box score/);
    await screen.findByText('Player Box Score');
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    expect(fetchSpy).toHaveBeenCalledWith(`${BASE_PATH}/data/games/401909089.json`);

    await user.click(screen.getByRole('tab', { name: /Attribution & SHAP/i }));
    expect(screen.getByText('Primary Ensemble Margin Waterfall')).toBeInTheDocument();
    expect(
      screen.getByText('Secondary Diagnostic Model: XGBoost Feature Fusion (TreeSHAP)'),
    ).toBeInTheDocument();
    expect(screen.getByText('Entering Baselines vs Realized Four Factors')).toBeInTheDocument();
    expect(fetchSpy).toHaveBeenCalledTimes(1);
  });

  it('keeps Final score recorded notice accessible when a completed game lacks a box score and its attribution comes from explainability/<id>.json', async () => {
    const fetchSpy = stubFetchByUrl({
      [explainabilityUrl('0022600888')]: makeExplainabilityEnvelope('0022600888', makeExplainability()),
    });

    const completedNoDetail = makeMatchup({
      game_id: '0022600888',
      is_completed: true,
      has_box_score: false,
      has_game_detail: false,
      has_explainability: true,
    });

    render(<GameDetailModal matchup={completedNoDetail} onClose={vi.fn()} />);

    expect(await screen.findByRole('tab', { name: /Attribution & SHAP/i })).toHaveAttribute(
      'aria-selected',
      'true',
    );
    expect(fetchSpy).toHaveBeenCalledWith(explainabilityUrl('0022600888'));
    expect(
      screen.getByText(
        'Final score recorded. The full box score is added on a later data refresh, usually within a day.',
      ),
    ).toBeInTheDocument();
    expect(screen.getByText('Entering Baselines vs Realized Four Factors')).toBeInTheDocument();
  });

  it('shows a visible error with Retry when the attribution fetch returns 404, and recovers on Retry (#147)', async () => {
    const user = userEvent.setup();
    const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const envelope = makeExplainabilityEnvelope('0022600777', makeExplainability());
    let calls = 0;
    const fetchMock = vi.fn<typeof fetch>().mockImplementation(async () => {
      calls += 1;
      return (calls === 1
        ? { ok: false, status: 404, json: async () => ({}) }
        : { ok: true, status: 200, json: async () => envelope }) as Response;
    });
    vi.stubGlobal('fetch', fetchMock);

    render(
      <GameDetailModal
        matchup={makeMatchup({
          game_id: '0022600777',
          is_completed: false,
          has_box_score: false,
          has_game_detail: false,
          has_explainability: true,
        })}
        onClose={vi.fn()}
      />,
    );

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('Unable to load attribution (HTTP 404).');
    expect(alert).toHaveTextContent('Attribution file could not be retrieved for PHI @ NYK.');
    expect(screen.queryByRole('tab', { name: /Attribution & SHAP/i })).not.toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledWith(explainabilityUrl('0022600777'));
    expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('has_explainability is true'));

    await user.click(within(alert).getByRole('button', { name: /Retry/i }));
    expect(await screen.findByText('Primary Ensemble Margin Waterfall')).toBeInTheDocument();
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('shows a visible error when the attribution fetch fails on the network or the file is malformed (#147)', async () => {
    const networkFail = vi.fn<typeof fetch>().mockRejectedValue(new Error('Network down'));
    vi.stubGlobal('fetch', networkFail);
    const matchup = makeMatchup({
      game_id: '0022600666',
      is_completed: false,
      has_box_score: false,
      has_game_detail: false,
      has_explainability: true,
    });
    const { rerender } = render(<GameDetailModal matchup={matchup} onClose={vi.fn()} />);
    expect(await screen.findByRole('alert')).toHaveTextContent('Network down');

    stubFetchByUrl({ [explainabilityUrl('0022600665')]: { schema_version: '1.0', game_id: '0022600665' } });
    rerender(
      <GameDetailModal matchup={{ ...matchup, game_id: '0022600665' }} onClose={vi.fn()} />,
    );
    await waitFor(() => {
      expect(screen.getByRole('alert')).toHaveTextContent('Attribution file is malformed.');
    });
    expect(screen.queryByRole('tab', { name: /Attribution & SHAP/i })).not.toBeInTheDocument();
  });
});
