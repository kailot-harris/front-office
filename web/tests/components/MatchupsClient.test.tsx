import { describe, expect, it } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import { MatchupsClient } from '../../components/MatchupsClient';
import { matchups } from '../helpers/datasets';

const dataset = matchups();
const weekGames = (week: number) => dataset.matchups.filter((m) => m.week === week);

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
    const biggest = [...weekGames(dataset.active_week)].sort(
      (a, b) => Math.abs(b.projected_margin) - Math.abs(a.projected_margin),
    )[0];
    expect(container.textContent).toContain(Math.abs(biggest.projected_margin).toFixed(1));
  });

  it('identifies the closest projected game in the active week', () => {
    const { container } = render(<MatchupsClient dataset={dataset} />);
    const closest = [...weekGames(dataset.active_week)].sort(
      (a, b) => Math.abs(a.projected_margin) - Math.abs(b.projected_margin),
    )[0];
    expect(container.textContent).toContain(`Line: ${Math.abs(closest.projected_margin).toFixed(1)} pts`);
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
  const empty = { active_week: 99, available_weeks: [99] as [number], total_games: 0, matchups: [] };

  it('renders a week with no games without throwing', () => {
    expect(() => render(<MatchupsClient dataset={empty} />)).not.toThrow();
  });

  it('does not print NaN when the slate is empty', () => {
    const { container } = render(<MatchupsClient dataset={empty} />);
    expect(container.textContent).not.toMatch(/NaN/);
  });
});
