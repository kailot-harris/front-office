import React from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {
  MatchupCard,
  clearGameDetailCache,
  formatMatchupInspectLabel,
} from '../../components/MatchupCard';
import type { GameDetailEnvelope, NflGameDetailPayload } from '../../lib/gameDetailTypes';
import type { MatchupGame } from '../../lib/types';

function makeMatchup(overrides: Partial<MatchupGame> = {}): MatchupGame {
  return {
    game_id: '2026_01_BUF_NYJ',
    season: 2026,
    week: 1,
    gameday: '2026-09-13',
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

function stubDetailFetch(leaders?: NflGameDetailPayload['leaders']) {
  const payload: GameDetailEnvelope = {
    schema_version: '1.0',
    generated_at: '2026-11-16T00:00:00Z',
    sport: 'nfl',
    endpoint: 'game_detail',
    season: 2026,
    season_label: '2026-2027',
    game_id: '2026_01_BUF_NYJ',
    data: {
      game_id: '2026_01_BUF_NYJ',
      season: 2026,
      season_label: '2026-2027',
      week: 1,
      week_label: 'Week 1',
      gameday: '2026-09-13',
      weekday: 'Sunday',
      gametime: '13:00',
      is_completed: true,
      has_box_score: true,
      away_team: { teamAbbr: 'BUF', teamName: 'Buffalo Bills', score: 31, is_winner: true },
      home_team: { teamAbbr: 'NYJ', teamName: 'New York Jets', score: 12, is_winner: false },
      forecast: null,
      efficiency_factors: null,
      team_stats: null,
      leaders: leaders ?? [
        {
          category: 'passing',
          teamAbbr: 'BUF',
          playerId: '00-0034857',
          playerName: 'Josh Allen',
          stat_line: '18/25, 232 YDS, 2 TD',
        },
        {
          category: 'passing',
          teamAbbr: 'NYJ',
          playerId: '00-0023459',
          playerName: 'Aaron Rodgers',
          stat_line: '15/28, 178 YDS, 1 TD',
        },
      ],
      box_score: null,
      injury_designations: null,
      explainability: null,
    },
  };

  const fetchMock = vi.fn<typeof fetch>().mockResolvedValue({
    ok: true,
    status: 200,
    json: async () => payload,
  } as Response);

  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

const originalFetch = global.fetch;

beforeEach(() => {
  clearGameDetailCache();
});

afterEach(() => {
  vi.unstubAllGlobals();
  global.fetch = originalFetch;
  clearGameDetailCache();
});

describe('MatchupCard interactive trigger', () => {
  it('renders non-interactive card when onSelect is not passed', () => {
    const game = makeMatchup();
    render(<MatchupCard matchup={game} />);

    const card = screen.getByTestId('matchup-card');
    expect(card).not.toHaveAttribute('role');
    expect(card).not.toHaveAttribute('tabindex');
    expect(card).not.toHaveAttribute('aria-label');
  });

  it('renders non-interactive card when onSelect is passed but matchup is not completed', () => {
    const onSelect = vi.fn();
    const game = makeMatchup({ is_completed: false });
    render(<MatchupCard matchup={game} onSelect={onSelect} />);

    const card = screen.getByTestId('matchup-card');
    expect(card).not.toHaveAttribute('role');
    expect(card).not.toHaveAttribute('tabindex');
    expect(card).not.toHaveAttribute('aria-label');
  });

  it('renders accessible button when completed and onSelect is passed', () => {
    const onSelect = vi.fn();
    const game = makeMatchup({ is_completed: true });
    render(<MatchupCard matchup={game} onSelect={onSelect} />);

    const cardBtn = screen.getByRole('button', {
      name: formatMatchupInspectLabel(game),
    });
    expect(cardBtn).toHaveAttribute('tabindex', '0');

    fireEvent.click(cardBtn);
    fireEvent.keyDown(cardBtn, { key: 'Enter' });
    fireEvent.keyDown(cardBtn, { key: ' ' });

    expect(onSelect).toHaveBeenCalledTimes(3);
    expect(onSelect).toHaveBeenNthCalledWith(1, game, cardBtn);
    expect(onSelect).toHaveBeenNthCalledWith(2, game, cardBtn);
    expect(onSelect).toHaveBeenNthCalledWith(3, game, cardBtn);
  });
});

describe('MatchupCard passing leader strip', () => {
  it('renders passing leader summary strip for completed games when detail data is loaded', async () => {
    stubDetailFetch();
    const game = makeMatchup({ is_completed: true });
    render(<MatchupCard matchup={game} />);

    const strip = await screen.findByTestId('passing-leaders-strip');
    expect(strip).toBeInTheDocument();
    expect(screen.getByText('Josh Allen')).toBeInTheDocument();
    expect(screen.getByText('18/25, 232 YDS, 2 TD')).toBeInTheDocument();
    expect(screen.getByText('Aaron Rodgers')).toBeInTheDocument();
    expect(screen.getByText('15/28, 178 YDS, 1 TD')).toBeInTheDocument();
  });

  it('does not render passing leader summary strip for scheduled / uncompleted games', () => {
    const fetchMock = stubDetailFetch();
    const game = makeMatchup({ is_completed: false });
    render(<MatchupCard matchup={game} />);

    expect(screen.queryByTestId('passing-leaders-strip')).not.toBeInTheDocument();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe('MatchupCard zero-betting policy guard', () => {
  it('contains zero betting terms in inspect labels or rendered copy', () => {
    const game = makeMatchup({ is_completed: true });
    const label = formatMatchupInspectLabel(game);

    expect(label).not.toMatch(
      /\b(odds|spread|moneyline|over_under|kelly|sportsbook|sharp_book|implied_probability|market_odds|value_bets|covered|total)\b/i,
    );
  });
});
