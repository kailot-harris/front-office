import React, { useRef, useState } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { GameDetailModal } from '@/components/GameDetailModal';
import { BASE_PATH } from '@/lib/basePath';
import type { GameDetailEnvelope, PlayerBoxRow } from '@/lib/gameDetailTypes';
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
});
