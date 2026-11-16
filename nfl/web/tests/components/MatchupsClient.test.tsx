import React from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MatchupsClient } from '../../components/MatchupsClient';
import { clearGameDetailCache, formatMatchupInspectLabel } from '../../components/MatchupCard';
import { matchups } from '../helpers/datasets';
import type { GameDetailEnvelope } from '../../lib/gameDetailTypes';

const { mockUseSearchParams } = vi.hoisted(() => ({
  mockUseSearchParams: vi.fn(() => new URLSearchParams(typeof window !== 'undefined' ? window.location.search : '')),
}));

vi.mock('next/navigation', () => ({
  usePathname: () => '/matchups',
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), prefetch: vi.fn(), back: vi.fn() }),
  useSearchParams: mockUseSearchParams,
}));

const dataset = matchups();
const weekGames = (week: number) => dataset.matchups.filter((m) => m.week === week);

function stubDetailFetch() {
  const fetchMock = vi.fn<typeof fetch>().mockImplementation(async (input) => {
    const url = typeof input === 'string' ? input : input.toString();
    const match = url.match(/\/data\/games\/([^/?]+)\.json/);
    if (match) {
      const gameId = match[1];
      const game = dataset.matchups.find((m) => m.game_id === gameId);
      const awayTeam = game ? game.away_team : 'BUF';
      const homeTeam = game ? game.home_team : 'MIA';
      const awayName = game ? game.away_team_name : 'Buffalo Bills';
      const homeName = game ? game.home_team_name : 'Miami Dolphins';

      const payload: GameDetailEnvelope = {
        schema_version: '1.0',
        generated_at: '2026-11-16T00:00:00Z',
        sport: 'nfl',
        endpoint: 'game_detail',
        season: 2026,
        season_label: '2026-2027',
        game_id: gameId,
        data: {
          game_id: gameId,
          season: 2026,
          season_label: '2026-2027',
          week: game ? game.week : 1,
          week_label: `Week ${game ? game.week : 1}`,
          gameday: game ? game.gameday : '2026-09-13',
          weekday: game ? game.weekday : 'Sunday',
          gametime: game ? game.gametime : '13:00',
          is_completed: game ? (game.is_completed ?? true) : true,
          has_box_score: true,
          away_team: { teamAbbr: awayTeam, teamName: awayName, score: game?.away_score ?? 24, is_winner: true },
          home_team: { teamAbbr: homeTeam, teamName: homeName, score: game?.home_score ?? 17, is_winner: false },
          forecast: null,
          efficiency_factors: null,
          team_stats: null,
          leaders: [
            {
              category: 'passing',
              teamAbbr: awayTeam,
              playerId: '00-01',
              playerName: `${awayTeam} Passer`,
              stat_line: '22/30, 280 YDS, 2 TD',
            },
            {
              category: 'passing',
              teamAbbr: homeTeam,
              playerId: '00-02',
              playerName: `${homeTeam} Passer`,
              stat_line: '18/28, 210 YDS, 1 TD',
            },
          ],
          box_score: null,
          injury_designations: null,
          explainability: null,
        },
      };

      return {
        ok: true,
        status: 200,
        json: async () => payload,
      } as Response;
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
  mockUseSearchParams.mockImplementation(() => new URLSearchParams(typeof window !== 'undefined' ? window.location.search : ''));
  window.history.replaceState(null, '', '/matchups');
  clearGameDetailCache();
});

afterEach(() => {
  vi.unstubAllGlobals();
  global.fetch = originalFetch;
  vi.restoreAllMocks();
  window.history.replaceState(null, '', '/matchups');
  clearGameDetailCache();
});

/** The week rail labels buttons "Week 6★ Active" / "Week 5Final", not "6". */
function clickWeek(week: number) {
  // "Week 1Final" has no word boundary between "1" and "F", so match on
  // "not followed by another digit" instead (otherwise week 1 matches week 18).
  const btn = screen
    .getAllByRole('button')
    .find((b) => new RegExp(`^Week ${week}(?!\\d)`).test(b.textContent?.trim() ?? ''));
  expect(btn, `no week ${week} button in the rail`).toBeTruthy();
  fireEvent.click(btn!);
}

function chip(label: string) {
  return screen.getAllByRole('button').find((b) => b.textContent?.trim() === label);
}

describe('MatchupsClient initial state', () => {
  it('opens on the active week', () => {
    const { container } = render(<MatchupsClient dataset={dataset} />);
    const games = weekGames(dataset.active_week);
    expect(games.length, 'active week has no games').toBeGreaterThan(0);
    for (const g of games.slice(0, 4)) {
      expect(container.textContent, `${g.game_id} not on the active slate`).toContain(g.home_team_name);
    }
  });

  it('renders a selector button for every available week', () => {
    render(<MatchupsClient dataset={dataset} />);
    const labels = screen.getAllByRole('button').map((b) => b.textContent?.trim() ?? '');
    for (const wk of dataset.available_weeks) {
      expect(labels.some((l) => new RegExp(`^Week ${wk}(?!\\d)`).test(l)), `no button for week ${wk}`).toBe(true);
    }
  });

  it('marks the active week and past weeks distinctly', () => {
    render(<MatchupsClient dataset={dataset} />);
    const labels = screen.getAllByRole('button').map((b) => b.textContent?.trim() ?? '');
    expect(labels.some((l) => l.startsWith(`Week ${dataset.active_week}`) && /active/i.test(l))).toBe(true);
    const past = dataset.available_weeks.find((w) => w < dataset.active_week);
    if (past) expect(labels.some((l) => l === `Week ${past}Final`)).toBe(true);
  });

  it('never prints NaN or undefined', () => {
    const { container } = render(<MatchupsClient dataset={dataset} />);
    expect(container.textContent).not.toMatch(/NaN|undefined/);
  });
});

describe('MatchupsClient week switching', () => {
  it('switching weeks swaps the slate', () => {
    const { container } = render(<MatchupsClient dataset={dataset} />);
    const other = dataset.available_weeks.find((w) => w !== dataset.active_week)!;
    clickWeek(other);
    const game = weekGames(other)[0];
    expect(container.textContent).toContain(game.home_team_name);
  });

  it('every week renders a non-empty slate with no NaN', () => {
    const { container } = render(<MatchupsClient dataset={dataset} />);
    for (const wk of dataset.available_weeks) {
      clickWeek(wk);
      const text = container.textContent ?? '';
      expect(text, `week ${wk} printed NaN/undefined`).not.toMatch(/NaN|undefined/);
      for (const g of weekGames(wk).slice(0, 3)) {
        expect(text, `week ${wk} is missing ${g.game_id}`).toContain(g.home_team_name);
      }
    }
  });

  it('a past week shows final scores', () => {
    const past = dataset.available_weeks.find((w) => w < dataset.active_week);
    if (!past) return;
    const { container } = render(<MatchupsClient dataset={dataset} />);
    clickWeek(past);
    const g = weekGames(past).find((x) => x.is_completed)!;
    expect(container.textContent).toContain(`${g.away_score}-${g.home_score}`);
  });

  it('a future week shows no final scores', () => {
    const future = dataset.available_weeks.find((w) => w > dataset.active_week);
    if (!future) return;
    const { container } = render(<MatchupsClient dataset={dataset} />);
    clickWeek(future);
    expect(container.textContent).not.toMatch(/FINAL/);
  });
});

describe('MatchupsClient team filter', () => {
  const filter = () => screen.getByPlaceholderText(/filter team/i);

  it('keeps games involving the searched team and drops the rest', () => {
    const { container } = render(<MatchupsClient dataset={dataset} />);
    const games = weekGames(dataset.active_week);
    const target = games[0];
    fireEvent.change(filter(), { target: { value: target.home_team_name } });
    const text = container.textContent ?? '';
    expect(text).toContain(target.home_team_name);
    for (const g of games) {
      if (g.home_team_name === target.home_team_name || g.away_team_name === target.home_team_name) continue;
      expect(text.includes(g.home_team_name), `${g.game_id} survived the filter`).toBe(false);
    }
  });

  it('matches on team abbreviation', () => {
    const { container } = render(<MatchupsClient dataset={dataset} />);
    const game = weekGames(dataset.active_week)[0];
    fireEvent.change(filter(), { target: { value: game.away_team } });
    expect(container.textContent).toContain(game.away_team_name);
  });

  it('is case-insensitive', () => {
    const { container } = render(<MatchupsClient dataset={dataset} />);
    const game = weekGames(dataset.active_week)[0];
    fireEvent.change(filter(), { target: { value: game.away_team.toLowerCase() } });
    expect(container.textContent).toContain(game.away_team_name);
  });

  it('an unmatched query empties the slate without crashing', () => {
    const { container } = render(<MatchupsClient dataset={dataset} />);
    fireEvent.change(filter(), { target: { value: 'zzzznotateam' } });
    const text = container.textContent ?? '';
    expect(text).not.toMatch(/NaN|undefined/);
    for (const g of weekGames(dataset.active_week)) {
      expect(text.includes(g.home_team_name), `${g.game_id} survived`).toBe(false);
    }
  });
});

describe('MatchupsClient weekday filter', () => {
  it('offers an All chip plus every weekday in the slate', () => {
    render(<MatchupsClient dataset={dataset} />);
    expect(chip('All'), 'no All chip').toBeTruthy();
    for (const day of new Set(weekGames(dataset.active_week).map((m) => m.weekday))) {
      expect(chip(day), `${day} chip missing`).toBeTruthy();
    }
  });

  it('filtering by a weekday keeps only that day', () => {
    const { container } = render(<MatchupsClient dataset={dataset} />);
    const games = weekGames(dataset.active_week);
    const day = games[0].weekday;
    fireEvent.click(chip(day)!);
    const text = container.textContent ?? '';
    for (const g of games.filter((x) => x.weekday !== day)) {
      expect(text.includes(g.home_team_name), `${g.game_id} (${g.weekday}) survived a ${day} filter`).toBe(false);
    }
    for (const g of games.filter((x) => x.weekday === day)) {
      expect(text, `${g.game_id} (${day}) was filtered out`).toContain(g.home_team_name);
    }
  });

  it('the All chip restores the full slate', () => {
    const { container } = render(<MatchupsClient dataset={dataset} />);
    const games = weekGames(dataset.active_week);
    fireEvent.click(chip(games[0].weekday)!);
    fireEvent.click(chip('All')!);
    for (const g of games.slice(0, 5)) expect(container.textContent).toContain(g.home_team_name);
  });
});

describe('MatchupsClient derived statistics', () => {
  it('reports the graded record for a completed week', () => {
    const completed = dataset.available_weeks.find((w) =>
      weekGames(w).every((g) => g.prediction_correct !== null && g.prediction_correct !== undefined),
    );
    expect(completed, 'no fully graded week in the dataset').toBeDefined();
    const { container } = render(<MatchupsClient dataset={dataset} />);
    clickWeek(completed!);
    const games = weekGames(completed!);
    const correct = games.filter((g) => g.prediction_correct).length;
    expect(container.textContent).toContain(`${correct} / ${games.length} Correct`);
  });

  it('identifies the largest projected favourite in the active week', () => {
    const { container } = render(<MatchupsClient dataset={dataset} />);
    const biggest = [...weekGames(dataset.active_week)]
      .filter((g) => g.has_projection && g.projected_margin != null)
      .sort((a, b) => Math.abs(b.projected_margin!) - Math.abs(a.projected_margin!))[0];
    expect(container.textContent).toContain(Math.abs(biggest.projected_margin!).toFixed(1));
  });

  it('identifies the closest projected game in the active week', () => {
    const { container } = render(<MatchupsClient dataset={dataset} />);
    const closest = [...weekGames(dataset.active_week)]
      .filter((g) => g.has_projection && g.projected_margin != null)
      .sort((a, b) => Math.abs(a.projected_margin!) - Math.abs(b.projected_margin!))[0];
    expect(container.textContent).toContain(`Margin: ${Math.abs(closest.projected_margin!).toFixed(1)} pts`);
  });
});

describe('MatchupsClient result badges agree with the projection on the same card', () => {
  /**
   * The UI-level counterpart of the `prediction_correct` invariant test.
   * A card shows, in one block: the final score, "Proj: <TEAM> +N" naming the
   * projected favourite, and a "✓ Model Correct" / "✗ Upset" badge. Those three
   * must tell the same story — a reader cannot reconcile "DEN won 17-14",
   * "Proj: DEN +3.1" and "✗ Upset".
   */
  /** Card roots that carry a result badge, for the currently selected week. */
  function badgedCards(container: HTMLElement) {
    return Array.from(container.querySelectorAll('div[class*="rounded-xl"]')).filter((el) => {
      const t = el.textContent ?? '';
      return /FINAL/.test(t) && /Proj:/.test(t) && /(Model Correct|Upset)/.test(t);
    });
  }

  it('no completed card pairs a correct projection with an Upset badge', () => {
    const { container } = render(<MatchupsClient dataset={dataset} />);
    const offenders: string[] = [];
    let inspected = 0;

    for (const wk of dataset.available_weeks.filter((w) => w <= dataset.active_week)) {
      clickWeek(wk);
      for (const card of badgedCards(container)) {
        const t = card.textContent ?? '';
        const proj = t.match(/Proj:\s*([A-Z]{2,3})\s*\+/);
        const score = t.match(/Final(\d+)-(\d+)/);
        if (!proj || !score) continue;
        const favourite = proj[1];
        const awayScore = Number(score[1]);
        const homeScore = Number(score[2]);
        const game = weekGames(wk).find(
          (g) =>
            g.away_score === awayScore &&
            g.home_score === homeScore &&
            (g.home_team === favourite || g.away_team === favourite),
        );
        if (!game || game.home_score === game.away_score) continue;
        inspected++;
        const winner = game.home_score! > game.away_score! ? game.home_team : game.away_team;
        const badgeSaysCorrect = /Model Correct/.test(t);
        if (badgeSaysCorrect !== (winner === favourite)) {
          offenders.push(
            `week ${wk} ${game.game_id}: card reads "Proj: ${favourite}", final ${awayScore}-${homeScore} ` +
              `(${winner} won), badge "${badgeSaysCorrect ? 'Model Correct' : 'Upset'}"`,
          );
        }
      }
    }

    // Guard against the test passing because it found nothing to look at.
    expect(inspected, 'no completed matchup cards were inspected — the selector is stale').toBeGreaterThan(50);
    expect(
      offenders.slice(0, 6),
      `${offenders.length} of ${inspected} completed matchup cards contradict themselves on screen. ` +
        `The projected favourite, the final score and the correctness badge come from three different ` +
        `fields in tools/export_web_datasets.R and do not agree.`,
    ).toEqual([]);
  });
});

describe('MatchupsClient resilience', () => {
  const empty = { generated_at: '2026-10-28T00:00:00Z', active_week: 99, available_weeks: [99] as [number], total_games: 0, matchups: [] };

  it('renders a week with no games without throwing', () => {
    expect(() => render(<MatchupsClient dataset={empty} />)).not.toThrow();
  });

  it('does not print NaN when the slate is empty', () => {
    const { container } = render(<MatchupsClient dataset={empty} />);
    expect(container.textContent).not.toMatch(/NaN/);
  });
});

describe('MatchupsClient Grid & Table GameDetailModal integration', () => {
  it('opens GameDetailModal from completed card click, syncs ?game=, and closes on close button', async () => {
    const user = userEvent.setup();
    stubDetailFetch();

    const completedWeek = dataset.available_weeks.find((w) =>
      weekGames(w).some((g) => g.is_completed)
    )!;
    const completedGame = weekGames(completedWeek).find((g) => g.is_completed)!;

    render(<MatchupsClient dataset={dataset} />);
    if (completedWeek !== dataset.active_week) {
      clickWeek(completedWeek);
    }

    const card = screen.getByRole('button', {
      name: formatMatchupInspectLabel(completedGame),
    });
    expect(card).toHaveAttribute('tabindex', '0');

    await user.click(card);

    const dialog = await screen.findByRole('dialog');
    expect(dialog).toBeInTheDocument();
    expect(dialog).toHaveAttribute('aria-modal', 'true');
    expect(within(dialog).getByText(completedGame.away_team_name)).toBeInTheDocument();
    expect(within(dialog).getByText(completedGame.home_team_name)).toBeInTheDocument();
    expect(window.location.search).toBe(`?game=${completedGame.game_id}`);

    const closeBtn = screen.getByRole('button', { name: /close modal/i });
    await user.click(closeBtn);

    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });
    expect(window.location.search).toBe('');
    expect(window.location.href.endsWith('?')).toBe(false);
  });

  it('opens GameDetailModal from unplayed card with projection, defaulting to Tab 4', async () => {
    const user = userEvent.setup();
    stubDetailFetch();

    const futureWeek = dataset.available_weeks.find((w) =>
      weekGames(w).some((g) => !g.is_completed && g.has_projection !== false && g.projected_margin != null)
    )!;
    const unplayedGame = weekGames(futureWeek).find(
      (g) => !g.is_completed && g.has_projection !== false && g.projected_margin != null
    )!;

    render(<MatchupsClient dataset={dataset} />);
    if (futureWeek !== dataset.active_week) {
      clickWeek(futureWeek);
    }

    const card = screen.getByRole('button', {
      name: formatMatchupInspectLabel(unplayedGame),
    });
    expect(card).toHaveAttribute('tabindex', '0');

    await user.click(card);

    const dialog = await screen.findByRole('dialog');
    expect(dialog).toBeInTheDocument();
    expect(window.location.search).toBe(`?game=${unplayedGame.game_id}`);

    // Tab 4 (Model Attribution) is active
    const tabAttribution = within(dialog).getByRole('tab', { name: /model attribution/i });
    expect(tabAttribution).toHaveAttribute('aria-selected', 'true');

    // Tabs 1-3 are disabled
    const tabOverview = within(dialog).getByRole('tab', { name: /overview & efficiency/i });
    expect(tabOverview).toBeDisabled();

    const closeBtn = within(dialog).getByRole('button', { name: /close modal/i });
    await user.click(closeBtn);

    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });
    expect(window.location.search).toBe('');
  });

  it('opens GameDetailModal via keyboard Enter and Space on focused completed card', async () => {
    const user = userEvent.setup();
    stubDetailFetch();

    const completedWeek = dataset.available_weeks.find((w) =>
      weekGames(w).some((g) => g.is_completed)
    )!;
    const completedGame = weekGames(completedWeek).find((g) => g.is_completed)!;

    render(<MatchupsClient dataset={dataset} />);
    if (completedWeek !== dataset.active_week) {
      clickWeek(completedWeek);
    }

    const card = screen.getByRole('button', {
      name: formatMatchupInspectLabel(completedGame),
    });
    card.focus();
    await user.keyboard('{Enter}');

    expect(await screen.findByRole('dialog')).toBeInTheDocument();
    expect(window.location.search).toBe(`?game=${completedGame.game_id}`);

    await user.keyboard('{Escape}');
    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });
    expect(window.location.search).toBe('');
  });

  it('opens GameDetailModal from completed table row click and syncs ?game=', async () => {
    const user = userEvent.setup();
    stubDetailFetch();

    const completedWeek = dataset.available_weeks.find((w) =>
      weekGames(w).some((g) => g.is_completed)
    )!;
    const completedGame = weekGames(completedWeek).find((g) => g.is_completed)!;

    render(<MatchupsClient dataset={dataset} />);
    if (completedWeek !== dataset.active_week) {
      clickWeek(completedWeek);
    }

    // Switch to table view
    const tableBtn = screen.getByTitle('Compact Table View');
    await user.click(tableBtn);

    const row = screen.getByRole('row', {
      name: formatMatchupInspectLabel(completedGame),
    });
    expect(row).toHaveAttribute('tabindex', '0');

    fireEvent.click(row);

    const dialog = await screen.findByRole('dialog');
    expect(dialog).toBeInTheDocument();
    expect(within(dialog).getByText(completedGame.away_team_name)).toBeInTheDocument();
    expect(within(dialog).getByText(completedGame.home_team_name)).toBeInTheDocument();
    expect(window.location.search).toBe(`?game=${completedGame.game_id}`);

    const closeBtn = screen.getByRole('button', { name: /close modal/i });
    await user.click(closeBtn);

    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });
    expect(window.location.search).toBe('');
  });
});

describe('MatchupsClient ?game= URL deep-linking', () => {
  it('switches selectedWeek and opens GameDetailModal when ?game= is in useSearchParams', async () => {
    stubDetailFetch();

    const targetWeek = dataset.available_weeks.find((w) => w !== dataset.active_week && weekGames(w).length > 0)!;
    const targetGame = weekGames(targetWeek)[0];

    mockUseSearchParams.mockImplementation(() => new URLSearchParams(`game=${targetGame.game_id}`));
    window.history.replaceState(null, '', `/matchups?game=${targetGame.game_id}`);

    render(<MatchupsClient dataset={dataset} />);

    const dialog = await screen.findByRole('dialog');
    expect(dialog).toBeInTheDocument();
    expect(within(dialog).getByText(targetGame.away_team_name)).toBeInTheDocument();
    expect(within(dialog).getByText(targetGame.home_team_name)).toBeInTheDocument();
  });

  it('switches selectedWeek and opens GameDetailModal from window.location.search on initial load', async () => {
    stubDetailFetch();

    const targetWeek = dataset.available_weeks.find((w) => w !== dataset.active_week && weekGames(w).length > 0)!;
    const targetGame = weekGames(targetWeek)[0];

    window.history.replaceState(null, '', `/matchups?game=${targetGame.game_id}`);

    render(<MatchupsClient dataset={dataset} />);

    const dialog = await screen.findByRole('dialog');
    expect(dialog).toBeInTheDocument();
    expect(within(dialog).getByText(targetGame.away_team_name)).toBeInTheDocument();
    expect(within(dialog).getByText(targetGame.home_team_name)).toBeInTheDocument();
  });

  it('responds to popstate events to sync modal state', async () => {
    stubDetailFetch();

    const targetGame = dataset.matchups[0];

    render(<MatchupsClient dataset={dataset} />);
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();

    act(() => {
      window.history.replaceState(null, '', `/matchups?game=${targetGame.game_id}`);
      window.dispatchEvent(new PopStateEvent('popstate'));
    });

    expect(await screen.findByRole('dialog')).toBeInTheDocument();

    act(() => {
      window.history.replaceState(null, '', '/matchups');
      window.dispatchEvent(new PopStateEvent('popstate'));
    });

    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });
  });
});
