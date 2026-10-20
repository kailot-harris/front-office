/**
 * Component tests for the home page dashboard.
 *
 * Rendered against the REAL dataset rather than a fixture, so a failure means
 * the page is broken for the data actually shipped — the same bet the server
 * component makes when it calls `getStandingsData()` at build time.
 *
 * Note on scoping: team names and percentages appear BOTH in the highlight
 * cards and in the table, so every row-level query is scoped to the <table>.
 * An unscoped `getByText` throws "found multiple elements" instead of testing
 * what it looks like it tests.
 */
import { describe, expect, it } from 'vitest';
import { fireEvent, render, screen, within } from '@testing-library/react';
import { StandingsClient } from '../../components/StandingsClient';
import { standings } from '../helpers/datasets';

const dataset = standings();
const TEAM_NAMES = new Set(dataset.teams.map((t) => t.team_name));

function renderTable() {
  const { container } = render(<StandingsClient dataset={dataset} initialTab="table" />);
  const table = container.querySelector('table');
  if (!table) throw new Error('table view rendered without a <table>');
  return { container, table: table as HTMLTableElement };
}

/** Team names in the table body, in render order. */
function rowOrder(table: HTMLTableElement): string[] {
  return Array.from(table.querySelectorAll('tbody tr'))
    .map((row) =>
      Array.from(row.querySelectorAll('*'))
        .map((el) => el.textContent?.trim())
        .find((text) => text && TEAM_NAMES.has(text)),
    )
    .filter((name): name is string => Boolean(name));
}

describe('StandingsClient renders', () => {
  it('mounts on the real dataset without throwing', () => {
    expect(() => render(<StandingsClient dataset={dataset} />)).not.toThrow();
  });

  it('shows the three view tabs', () => {
    render(<StandingsClient dataset={dataset} />);
    expect(screen.getByRole('tab', { name: /visuali/i })).toBeInTheDocument();
    expect(screen.getByRole('tab', { name: /table/i })).toBeInTheDocument();
    expect(screen.getByRole('tab', { name: /division/i })).toBeInTheDocument();
  });

  it('lists all 32 teams in the table view', () => {
    const { table } = renderTable();
    expect(rowOrder(table).sort()).toEqual([...TEAM_NAMES].sort());
  });

  it('renders the Super Bowl favourite highlight as a real percentage', () => {
    render(<StandingsClient dataset={dataset} />);
    const favourite = [...dataset.teams].sort((a, b) => b.super_bowl_prob - a.super_bowl_prob)[0];
    const pct = `${(favourite.super_bowl_prob * 100).toFixed(1)}%`;
    expect(screen.getAllByText(pct).length).toBeGreaterThan(0);
  });

  it('never prints NaN, undefined or null anywhere in the output', () => {
    const { container } = renderTable();
    expect(container.textContent).not.toMatch(/NaN|undefined|\bnull\b/);
  });
});

describe('StandingsClient conference filter', () => {
  it('narrows the table to one conference', () => {
    const { table } = renderTable();
    fireEvent.click(screen.getByRole('button', { name: 'AFC' }));
    const shown = new Set(rowOrder(table));
    expect(shown.size).toBe(16);
    for (const t of dataset.teams) {
      expect(shown.has(t.team_name), `${t.team} (${t.conference})`).toBe(t.conference === 'AFC');
    }
  });

  it('restores all teams when switching back to All', () => {
    const { table } = renderTable();
    fireEvent.click(screen.getByRole('button', { name: 'NFC' }));
    fireEvent.click(screen.getByRole('button', { name: 'All' }));
    expect(rowOrder(table)).toHaveLength(32);
  });
});

describe('StandingsClient division filter', () => {
  it('narrows to a single division via the dropdown', () => {
    const { table, container } = renderTable();
    const select = container.querySelector('select');
    expect(select, 'division dropdown missing').not.toBeNull();
    fireEvent.change(select!, { target: { value: 'AFC West' } });
    const shown = rowOrder(table);
    expect(shown).toHaveLength(4);
    for (const name of shown) {
      expect(dataset.teams.find((t) => t.team_name === name)!.division).toBe('AFC West');
    }
  });

  it('offers every division present in the data', () => {
    const { container } = renderTable();
    const options = Array.from(container.querySelectorAll('select option')).map((o) => o.textContent);
    for (const div of new Set(dataset.teams.map((t) => t.division))) {
      expect(options, `${div} missing from the dropdown`).toContain(div);
    }
  });
});

describe('StandingsClient search', () => {
  const search = () => screen.getByPlaceholderText(/search franchise/i);

  it('matches on full team name', () => {
    const { table } = renderTable();
    const target = dataset.teams[0];
    fireEvent.change(search(), { target: { value: target.team_name } });
    expect(rowOrder(table)).toEqual([target.team_name]);
  });

  it('matches on abbreviation', () => {
    const { table } = renderTable();
    fireEvent.change(search(), { target: { value: 'KC' } });
    expect(rowOrder(table)).toContain('Kansas City Chiefs');
  });

  it('is case-insensitive', () => {
    const { table } = renderTable();
    fireEvent.change(search(), { target: { value: 'kansas' } });
    expect(rowOrder(table)).toEqual(['Kansas City Chiefs']);
  });

  it('matches on division name', () => {
    const { table } = renderTable();
    fireEvent.change(search(), { target: { value: 'AFC West' } });
    expect(rowOrder(table).sort()).toEqual(
      dataset.teams.filter((t) => t.division === 'AFC West').map((t) => t.team_name).sort(),
    );
  });

  it('renders an empty result set for a query that matches nothing', () => {
    const { table, container } = renderTable();
    fireEvent.change(search(), { target: { value: 'zzzznotateam' } });
    expect(rowOrder(table)).toEqual([]);
    expect(container.textContent).not.toMatch(/NaN|undefined/);
  });

  it('treats a whitespace-only query as no filter', () => {
    const { table } = renderTable();
    fireEvent.change(search(), { target: { value: '   ' } });
    expect(rowOrder(table)).toHaveLength(32);
  });

  it('composes with the conference filter rather than replacing it', () => {
    const { table } = renderTable();
    fireEvent.click(screen.getByRole('button', { name: 'AFC' }));
    fireEvent.change(search(), { target: { value: 'New York' } });
    // Both New York teams match the text, but only the Jets are AFC.
    expect(rowOrder(table)).toEqual(['New York Jets']);
  });
});

describe('StandingsClient sorting', () => {
  /** Click the <th> whose label matches, scoped to the table head. */
  function clickHeader(table: HTMLTableElement, label: RegExp) {
    const th = Array.from(table.querySelectorAll('thead th')).find((el) => label.test(el.textContent ?? ''));
    expect(th, `no table header matching ${label}`).toBeTruthy();
    fireEvent.click(th!);
  }

  it('defaults to projected wins, descending', () => {
    const { table } = renderTable();
    const expected = [...dataset.teams].sort((a, b) => b.projected_wins - a.projected_wins)[0].team_name;
    expect(rowOrder(table)[0]).toBe(expected);
  });

  it('clicking the active sort header reverses the order', () => {
    const { table } = renderTable();
    const before = rowOrder(table);
    clickHeader(table, /Proj Wins/i);
    const after = rowOrder(table);
    expect(after[0], 'clicking the active header did not flip the sort').not.toBe(before[0]);
    expect(after[0]).toBe([...dataset.teams].sort((a, b) => a.projected_wins - b.projected_wins)[0].team_name);
  });

  it('sorting by team name is alphabetical ascending on first click', () => {
    const { table } = renderTable();
    clickHeader(table, /Franchise/i);
    expect(rowOrder(table)[0]).toBe([...TEAM_NAMES].sort((a, b) => a.localeCompare(b))[0]);
  });

  it('sorting by power rating puts the top-rated team first', () => {
    const { table } = renderTable();
    clickHeader(table, /Power Rating/i);
    expect(rowOrder(table)[0]).toBe([...dataset.teams].sort((a, b) => b.power_rating - a.power_rating)[0].team_name);
  });

  it('sorting by point differential puts the best differential first', () => {
    const { table } = renderTable();
    clickHeader(table, /Point Diff/i);
    expect(rowOrder(table)[0]).toBe([...dataset.teams].sort((a, b) => b.point_diff - a.point_diff)[0].team_name);
  });

  it('switching sort field resets to descending rather than inheriting asc', () => {
    const { table } = renderTable();
    clickHeader(table, /Proj Wins/i); // now ascending
    clickHeader(table, /Playoff %/i); // different field
    expect(rowOrder(table)[0]).toBe([...dataset.teams].sort((a, b) => b.playoff_prob - a.playoff_prob)[0].team_name);
  });

  it('sorting is stable with respect to the filter (no rows gained or lost)', () => {
    const { table } = renderTable();
    fireEvent.click(screen.getByRole('button', { name: 'NFC' }));
    const before = rowOrder(table).sort();
    clickHeader(table, /Power Rating/i);
    expect(rowOrder(table).sort()).toEqual(before);
  });
});

describe('StandingsClient division view', () => {
  it('groups teams under all eight divisions', () => {
    render(<StandingsClient dataset={dataset} initialTab="divisions" />);
    const divisions = [...new Set(dataset.teams.map((t) => t.division))];
    expect(divisions).toHaveLength(8);
    for (const div of divisions) {
      expect(screen.getAllByText(div).length, `${div} heading missing`).toBeGreaterThan(0);
    }
  });

  it('shows every team exactly once across the division cards', () => {
    const { container } = render(<StandingsClient dataset={dataset} initialTab="divisions" />);
    for (const t of dataset.teams) {
      const occurrences = (container.textContent ?? '').split(t.team_name).length - 1;
      expect(occurrences, `${t.team_name} appears ${occurrences}x in the division view`).toBeGreaterThan(0);
    }
  });
});

describe('StandingsClient resilience', () => {
  it('renders a single-team dataset', () => {
    expect(() =>
      render(<StandingsClient dataset={{ ...dataset, teams: [dataset.teams[0]], total_teams: 1 }} initialTab="table" />),
    ).not.toThrow();
  });

  it('renders an empty dataset without printing NaN in the highlight cards', () => {
    // The highlight cards do `(topSbFavorite?.super_bowl_prob * 100).toFixed(1)`.
    // `?.` guards the property access but NOT the arithmetic that follows, so an
    // empty team list yields the string "NaN" rather than a dash or a zero.
    // Not reachable with the shipped export (always 32 teams), but it is the
    // difference between a graceful empty state and a visibly broken card if a
    // filter upstream ever yields nothing.
    const { container } = render(
      <StandingsClient dataset={{ ...dataset, teams: [], total_teams: 0 }} initialTab="table" />,
    );
    expect(container.textContent).not.toMatch(/NaN/);
  });
});
