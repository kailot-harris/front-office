import React from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MatchupCard } from '@/components/MatchupCard';
import { MatchupsClient } from '@/components/MatchupsClient';
import { BASE_PATH } from '@/lib/basePath';
import type { GameDetailEnvelope } from '@/lib/gameDetailTypes';
import type { MatchupGame, MatchupsDataset } from '@/lib/matchupTypes';
import { loadAllDatasets } from '../helpers/datasets';

const { mockUseSearchParams } = vi.hoisted(() => ({
  mockUseSearchParams: vi.fn(() => new URLSearchParams()),
}));

vi.mock('next/navigation', () => ({
  usePathname: () => '/matchups',
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), prefetch: vi.fn(), back: vi.fn() }),
  useSearchParams: mockUseSearchParams,
}));

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

function makeDataset(): MatchupsDataset {
  const slate1Game = makeMatchup({
    game_id: '401909089',
    slate: 1,
    game_date: '2026-10-20',
    weekday: 'Tue',
    away_team: 'PHI',
    away_team_name: '76ers',
    home_team: 'NYK',
    home_team_name: 'Knicks',
    is_completed: true,
    has_box_score: true,
    has_game_detail: true,
  });

  const slate2Completed = makeMatchup({
    game_id: '401909150',
    slate: 2,
    game_date: '2026-10-28',
    weekday: 'Wed',
    away_team: 'BOS',
    away_team_name: 'Celtics',
    home_team: 'LAL',
    home_team_name: 'Lakers',
    predicted_margin: -3.2,
    predicted_home_win_prob: 0.39,
    predicted_away_win_prob: 0.61,
    predicted_winner: 'BOS',
    home_score: 110,
    away_score: 118,
    actual_margin: -8,
    actual_winner: 'BOS',
    prediction_correct: true,
    has_box_score: true,
    has_game_detail: true,
  });

  const slate2Scheduled = makeMatchup({
    game_id: '401909151',
    slate: 2,
    game_date: '2026-10-30',
    weekday: 'Fri',
    away_team: 'DEN',
    away_team_name: 'Nuggets',
    home_team: 'MIN',
    home_team_name: 'Timberwolves',
    projection_basis: 'primary_ensemble',
    predicted_margin: 1.8,
    predicted_home_win_prob: 0.56,
    predicted_away_win_prob: 0.44,
    predicted_winner: 'MIN',
    is_completed: false,
    home_score: null,
    away_score: null,
    actual_margin: null,
    actual_winner: null,
    prediction_correct: null,
    has_box_score: false,
    has_game_detail: false,
  });

  return {
    season: 2027,
    season_label: '2026-2027',
    generated_at: '2026-11-15T14:00:00Z',
    slate_granularity: 'week_of_season',
    season_start_date: '2026-10-20',
    season_end_date: '2027-04-11',
    schedule_source: 'hoopR::load_nba_schedule(seasons = 2027)',
    active_slate: 2,
    available_slates: [1, 2],
    total_games: 3,
    completed_games: 2,
    pending_games: 1,
    games_with_projection: 3,
    games_without_projection: 0,
    games_logged_basis: 2,
    games_ratings_basis: 1,
    games_ensemble_basis: 1,
    ratings_source: 'Primary 4-Model Ensemble Blend',
    rating_match_rate_pct: 100,
    logged_predictions_in_season: 2,
    logged_predictions_matched: 2,
    join_match_rate_pct: 100,
    graded_games_available: true,
    grading_state: 'graded',
    slates: [
      {
        slate: 1,
        label: 'Week 1 · Oct 20 – Oct 26',
        start_date: '2026-10-20',
        end_date: '2026-10-26',
        status: 'past',
        games_total: 1,
        logged_projection_total: 1,
        ratings_projection_total: 0,
        ensemble_projection_total: 0,
        graded_total: 1,
        correct_total: 0,
        accuracy_pct: 0,
      },
      {
        slate: 2,
        label: 'Week 2 · Oct 27 – Nov 2',
        start_date: '2026-10-27',
        end_date: '2026-11-02',
        status: 'active',
        games_total: 2,
        logged_projection_total: 1,
        ratings_projection_total: 1,
        ensemble_projection_total: 1,
        graded_total: 1,
        correct_total: 1,
        accuracy_pct: 100,
      },
    ],
    matchups: [slate1Game, slate2Completed, slate2Scheduled],
  };
}

function makeDetailEnvelope(game: MatchupGame, slateLabel: string): GameDetailEnvelope {
  return {
    schema_version: '1.0',
    generated_at: '2026-11-15T14:00:00Z',
    sport: 'nba',
    endpoint: 'game_detail',
    season: 2027,
    season_label: '2026-2027',
    data: {
      game_id: game.game_id,
      slate: game.slate,
      slate_label: slateLabel,
      game_date: game.game_date,
      weekday: game.weekday,
      is_completed: game.is_completed,
      has_box_score: false,
      away_team: {
        teamAbbr: game.away_team,
        teamName: game.away_team_name,
        score: game.away_score,
        is_winner: game.actual_winner === game.away_team,
      },
      home_team: {
        teamAbbr: game.home_team,
        teamName: game.home_team_name,
        score: game.home_score,
        is_winner: game.actual_winner === game.home_team,
      },
      efficiency_factors: null,
      context_splits: null,
      box_score: null,
      explainability: null,
      game_flow: null,
    },
  };
}

function stubDetailFetch(dataset: MatchupsDataset) {
  const fetchMock = vi.fn<typeof fetch>().mockImplementation(async (input) => {
    const url = typeof input === 'string' ? input : input.toString();
    const match = url.match(/\/data\/games\/([^/?]+)\.json/);
    if (match) {
      const game = dataset.matchups.find((m) => m.game_id === match[1]);
      if (game) {
        const label = dataset.slates.find((s) => s.slate === game.slate)?.label ?? `Week ${game.slate}`;
        return {
          ok: true,
          status: 200,
          json: async () => makeDetailEnvelope(game, label),
        } as Response;
      }
    }
    return {
      ok: false,
      status: 404,
      json: async () => ({ error: 'Not found' }),
    } as Response;
  });
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

const originalFetch = global.fetch;

beforeEach(() => {
  mockUseSearchParams.mockImplementation(() => new URLSearchParams());
  window.history.replaceState(null, '', '/matchups');
});

afterEach(() => {
  vi.unstubAllGlobals();
  global.fetch = originalFetch;
  vi.restoreAllMocks();
  window.history.replaceState(null, '', '/matchups');
});

describe('MatchupCard interactive trigger', () => {
  it('renders non-interactive card by default and exposes accessible button semantics when onSelect is passed', () => {
    const game = makeMatchup();
    const { rerender } = render(<MatchupCard matchup={game} />);
    const staticCard = screen.getByTestId('matchup-card');
    expect(staticCard).not.toHaveAttribute('role');
    expect(staticCard).not.toHaveAttribute('tabindex');

    const onSelect = vi.fn();
    rerender(<MatchupCard matchup={game} onSelect={onSelect} />);

    const cardBtn = screen.getByRole('button', {
      name: 'Inspect game detail: 76ers (PHI) at Knicks (NYK) on 2026-10-20',
    });
    // A native <button> stretched over the card (WCAG 2.5.3): focusable and
    // Enter/Space-activated by the browser, so only the click is simulated here.
    expect(cardBtn.tagName).toBe('BUTTON');

    fireEvent.click(cardBtn);

    expect(onSelect).toHaveBeenCalledTimes(1);
    expect(onSelect).toHaveBeenNthCalledWith(1, game, cardBtn);
  });
});

describe('MatchupsClient real dataset smoke', () => {
  it('mounts cleanly on real matchups_slates.json without NaN or undefined', () => {
    const { matchups } = loadAllDatasets();
    const { container } = render(<MatchupsClient dataset={matchups} />);
    expect(container.textContent).not.toMatch(/NaN|undefined/);
    expect(screen.getAllByTestId('matchup-card').length).toBeGreaterThan(0);
  });
});

describe('MatchupsClient Grid & Table GameDetailModal integration', () => {
  it('opens GameDetailModal from Grid card click, preserves extra query params, and restores focus + clears ?game= on Escape', async () => {
    const user = userEvent.setup();
    const dataset = makeDataset();
    const fetchMock = stubDetailFetch(dataset);
    window.history.replaceState(null, '', '/matchups?view=compact');

    render(<MatchupsClient dataset={dataset} />);

    const card = screen.getByRole('button', {
      name: 'Inspect game detail: Celtics (BOS) at Lakers (LAL) on 2026-10-28',
    });
    await user.click(card);

    const dialog = await screen.findByRole('dialog');
    expect(dialog).toHaveAttribute('aria-modal', 'true');
    expect(screen.getByText('Celtics @ Lakers')).toBeInTheDocument();
    expect(screen.getByText('Week 2 · Oct 27 – Nov 2')).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledWith(`${BASE_PATH}/data/games/401909150.json`);
    expect(window.location.search).toBe('?view=compact&game=401909150');

    await user.keyboard('{Escape}');
    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });
    expect(window.location.search).toBe('?view=compact');
    expect(document.activeElement).toBe(card);
  });

  it('opens GameDetailModal via keyboard Enter and Space in Grid view and clears ?game= without trailing ? on Close click', async () => {
    const user = userEvent.setup();
    const dataset = makeDataset();
    const fetchMock = stubDetailFetch(dataset);

    render(<MatchupsClient dataset={dataset} />);

    const scheduledCard = screen.getByRole('button', {
      name: 'Inspect game detail: Nuggets (DEN) at Timberwolves (MIN) on 2026-10-30',
    });
    scheduledCard.focus();
    await user.keyboard('{Enter}');

    expect(await screen.findByRole('dialog')).toBeInTheDocument();
    expect(screen.getByText('Box score appears after the game.')).toBeInTheDocument();
    expect(fetchMock).not.toHaveBeenCalled();
    expect(window.location.search).toBe('?game=401909151');

    const closeBtn = screen.getByRole('button', { name: /close game detail modal/i });
    await user.click(closeBtn);
    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });
    expect(window.location.pathname).toBe('/matchups');
    expect(window.location.search).toBe('');
    expect(window.location.href.endsWith('?')).toBe(false);
    expect(document.activeElement).toBe(scheduledCard);

    // Space also activates the focused card.
    await user.keyboard(' ');
    expect(await screen.findByRole('dialog')).toBeInTheDocument();
    expect(window.location.search).toBe('?game=401909151');
  });

  it('opens GameDetailModal from Table row click and keyboard Enter, syncs ?game=, and restores focus to the row on Escape', async () => {
    const user = userEvent.setup();
    const dataset = makeDataset();
    const fetchMock = stubDetailFetch(dataset);

    render(<MatchupsClient dataset={dataset} />);

    await user.click(screen.getByRole('tab', { name: 'Compact table view' }));

    const row = screen.getByRole('row', {
      name: 'Inspect game detail: Celtics (BOS) at Lakers (LAL) on 2026-10-28',
    });
    await user.click(row);

    expect(await screen.findByRole('dialog')).toBeInTheDocument();
    expect(screen.getByText('Celtics @ Lakers')).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledWith(`${BASE_PATH}/data/games/401909150.json`);
    expect(window.location.search).toBe('?game=401909150');

    await user.keyboard('{Escape}');
    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });
    expect(window.location.search).toBe('');
    expect(document.activeElement).toBe(row);

    // Keyboard activation from the focused table row also opens the modal.
    row.focus();
    await user.keyboard('{Enter}');
    expect(await screen.findByRole('dialog')).toBeInTheDocument();
    expect(window.location.search).toBe('?game=401909150');

    await user.click(screen.getByRole('button', { name: /close game detail modal/i }));
    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });
    expect(document.activeElement).toBe(row);
    expect(window.location.search).toBe('');

    // Spacebar also activates the focused table row.
    await user.keyboard(' ');
    expect(await screen.findByRole('dialog')).toBeInTheDocument();
    expect(window.location.search).toBe('?game=401909150');
  });
});

describe('MatchupsClient ?game= URL deep-linking', () => {
  it('switches selectedSlate and opens GameDetailModal on initial load from window.location.search', async () => {
    const user = userEvent.setup();
    const dataset = makeDataset();
    const fetchMock = stubDetailFetch(dataset);
    window.history.replaceState(null, '', '/matchups?game=401909089');

    render(<MatchupsClient dataset={dataset} />);

    const dialog = await screen.findByRole('dialog');
    expect(dialog).toBeInTheDocument();
    expect(screen.getByText('76ers @ Knicks')).toBeInTheDocument();
    expect(screen.getByText('Week 1 · Oct 20 – Oct 26')).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledWith(`${BASE_PATH}/data/games/401909089.json`);

    // Selected slate switched from active_slate (2) to game's slate (1).
    const wk1Btn = screen.getByRole('button', { name: /Wk 1/i });
    const wk2Btn = screen.getByRole('button', { name: /Wk 2/i });
    expect(wk1Btn).toHaveAttribute('aria-pressed', 'true');
    expect(wk2Btn).toHaveAttribute('aria-pressed', 'false');

    await user.keyboard('{Escape}');
    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });
    expect(window.location.search).toBe('');
    expect(window.location.href.endsWith('?')).toBe(false);
  });

  it('switches selectedSlate and opens GameDetailModal from useSearchParams and stays closed after Escape', async () => {
    const user = userEvent.setup();
    const dataset = makeDataset();
    stubDetailFetch(dataset);
    mockUseSearchParams.mockImplementation(() => new URLSearchParams('game=401909089'));

    render(<MatchupsClient dataset={dataset} />);

    expect(await screen.findByRole('dialog')).toBeInTheDocument();
    expect(screen.getByText('76ers @ Knicks')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Wk 1/i })).toHaveAttribute('aria-pressed', 'true');

    await user.keyboard('{Escape}');
    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });
    expect(window.location.search).toBe('');
  });

  it('ignores unknown ?game= ids cleanly without opening a modal or changing selectedSlate', () => {
    const dataset = makeDataset();
    stubDetailFetch(dataset);
    window.history.replaceState(null, '', '/matchups?game=nonexistent-game');

    render(<MatchupsClient dataset={dataset} />);

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Wk 2/i })).toHaveAttribute('aria-pressed', 'true');
  });

  it('contains zero betting terms in new interactive card/row labels', () => {
    const dataset = makeDataset();
    render(<MatchupsClient dataset={dataset} />);

    const triggers = screen.getAllByRole('button', { name: /Inspect game detail:/i });
    expect(triggers.length).toBeGreaterThan(0);
    for (const el of triggers) {
      const label = el.getAttribute('aria-label') ?? '';
      expect(label).not.toMatch(
        /\b(odds|spread|moneyline|over_under|kelly|sportsbook|sharp_book|implied_probability|market_odds|value_bets|covered|upset)\b/i,
      );
    }
  });
});
