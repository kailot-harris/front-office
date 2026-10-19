import { describe, expect, it } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import { TeamsClient } from '../../components/TeamsClient';
import { teamEpa } from '../helpers/datasets';

const teams = teamEpa();
const NAMES = new Set(teams.map((t) => t.team_name));

function renderTeams() {
  const { container } = render(<TeamsClient teams={teams} />);
  const table = container.querySelector('table');
  if (!table) throw new Error('TeamsClient rendered without a <table>');
  return { container, table: table as HTMLTableElement };
}

function rowOrder(table: HTMLTableElement): string[] {
  return Array.from(table.querySelectorAll('tbody tr'))
    .map((row) =>
      Array.from(row.querySelectorAll('*'))
        .map((el) => el.textContent?.trim())
        .find((t) => t && NAMES.has(t)),
    )
    .filter((n): n is string => Boolean(n));
}

/** Every All/AFC/NFC chip group in the component, in document order. */
function conferenceGroups(container: HTMLElement): HTMLElement[] {
  return Array.from(container.querySelectorAll('div')).filter((el) => {
    const labels = Array.from(el.querySelectorAll(':scope > button')).map((b) => b.textContent?.trim());
    return labels.length === 3 && labels.join(',') === 'All,AFC,NFC';
  }) as HTMLElement[];
}

/**
 * Click the conference chip that drives the TABLE.
 *
 * This page renders TWO independent All/AFC/NFC chip groups: one inside the
 * EPA quadrant scatter and one in the table's own filter bar. They hold
 * separate state, so clicking the scatter's chip leaves the table at 32 rows.
 * Tests must target the second (table) group explicitly.
 */
function clickConference(container: HTMLElement, label: 'All' | 'AFC' | 'NFC') {
  const groups = conferenceGroups(container);
  expect(groups.length, 'conference chip group not found').toBeGreaterThan(0);
  const group = groups[groups.length - 1];
  const btn = Array.from(group.querySelectorAll('button')).find((b) => b.textContent?.trim() === label);
  expect(btn, `no ${label} chip in the table filter bar`).toBeTruthy();
  fireEvent.click(btn!);
}

function clickHeader(table: HTMLTableElement, label: RegExp) {
  const th = Array.from(table.querySelectorAll('thead th')).find((el) => label.test(el.textContent ?? ''));
  expect(th, `no header matching ${label}`).toBeTruthy();
  fireEvent.click(th!);
}

describe('TeamsClient renders', () => {
  it('lists all 32 teams', () => {
    const { table } = renderTeams();
    expect(rowOrder(table).sort()).toEqual([...NAMES].sort());
  });

  it('never prints NaN or undefined', () => {
    const { container } = renderTeams();
    expect(container.textContent).not.toMatch(/NaN|undefined/);
  });

  it('renders success rates as percentages, not proportions', () => {
    // off_success_rate ships as 0-100. A regression to proportions would print
    // "0.5%" instead of "50.0%" with no type error.
    const { container } = renderTeams();
    const leader = [...teams].sort((a, b) => b.off_success_rate - a.off_success_rate)[0];
    expect(leader.off_success_rate).toBeGreaterThan(1);
    expect(container.textContent).toContain(`${leader.off_success_rate.toFixed(1)}%`);
  });

  it('signs CPOE explicitly for positive values', () => {
    const { container } = renderTeams();
    const positive = teams.find((t) => t.off_cpoe > 0);
    if (positive) expect(container.textContent).toContain(`+${positive.off_cpoe.toFixed(1)}`);
  });

  it('does not print a doubled sign like "+-"', () => {
    const { container } = renderTeams();
    expect(container.textContent).not.toMatch(/\+-\d/);
  });
});

describe('TeamsClient conference filter', () => {
  it('has two independent conference filters, which is a UX trap', () => {
    // Documents, rather than endorses, the current layout: the scatter and the
    // table each own a conference filter, so picking "AFC" in one leaves the
    // other showing all 32 teams. If these are ever unified, this test should
    // be updated to expect a single group.
    const { container, table } = renderTeams();
    const groups = conferenceGroups(container);
    expect(groups.length, 'expected the scatter filter and the table filter').toBe(2);

    const scatterAfc = Array.from(groups[0].querySelectorAll('button')).find((b) => b.textContent?.trim() === 'AFC')!;
    fireEvent.click(scatterAfc);
    expect(
      new Set(rowOrder(table)).size,
      'the scatter conference filter unexpectedly filtered the table too',
    ).toBe(32);
  });

  it('narrows to one conference', () => {
    const { table, container } = renderTeams();
    clickConference(container, 'AFC');
    const shown = new Set(rowOrder(table));
    expect(shown.size).toBe(16);
    for (const t of teams) expect(shown.has(t.team_name), t.team).toBe(t.conference === 'AFC');
  });

  it('All restores the full league', () => {
    const { table, container } = renderTeams();
    clickConference(container, 'NFC');
    clickConference(container, 'All');
    expect(rowOrder(table)).toHaveLength(32);
  });
});

describe('TeamsClient search', () => {
  const search = () => screen.getAllByPlaceholderText(/search/i)[0];

  it('matches on team name, abbreviation and division', () => {
    const { table } = renderTeams();
    fireEvent.change(search(), { target: { value: 'Chiefs' } });
    expect(rowOrder(table)).toEqual(['Kansas City Chiefs']);

    fireEvent.change(search(), { target: { value: 'KC' } });
    expect(rowOrder(table)).toContain('Kansas City Chiefs');

    fireEvent.change(search(), { target: { value: 'NFC West' } });
    expect(rowOrder(table).sort()).toEqual(
      teams.filter((t) => t.division === 'NFC West').map((t) => t.team_name).sort(),
    );
  });

  it('an unmatched query yields no rows without crashing', () => {
    const { table, container } = renderTeams();
    fireEvent.change(search(), { target: { value: 'zzzznotateam' } });
    expect(rowOrder(table)).toEqual([]);
    expect(container.textContent).not.toMatch(/NaN|undefined/);
  });
});

describe('TeamsClient sorting', () => {
  it('defaults to net EPA descending', () => {
    const { table } = renderTeams();
    expect(rowOrder(table)[0]).toBe([...teams].sort((a, b) => b.net_epa_per_play - a.net_epa_per_play)[0].team_name);
  });

  it('sorting by offensive EPA puts the best offence first', () => {
    const { table } = renderTeams();
    clickHeader(table, /Off\.? EPA/i);
    expect(rowOrder(table)[0]).toBe([...teams].sort((a, b) => b.off_epa_per_play - a.off_epa_per_play)[0].team_name);
  });

  it('sorting by defensive EPA puts the BEST defence first, not the worst', () => {
    // For defence, a lower EPA allowed is better. Two pieces cooperate to get
    // this right and both must stay in place: the comparator's dedicated
    // `def_epa_per_play` branch, AND `handleSort` defaulting this one field to
    // 'asc' instead of 'desc'. Drop either and the first click silently
    // surfaces the league's worst defence at the top of the table.
    const { table } = renderTeams();
    clickHeader(table, /Def\.? EPA/i);
    const best = [...teams].sort((a, b) => a.def_epa_per_play - b.def_epa_per_play)[0];
    const worst = [...teams].sort((a, b) => b.def_epa_per_play - a.def_epa_per_play)[0];
    expect(
      rowOrder(table)[0],
      `sorting by defensive EPA surfaced ${rowOrder(table)[0]} first; the best defence is ` +
        `${best.team_name} (${best.def_epa_per_play}) and the worst is ${worst.team_name} (${worst.def_epa_per_play})`,
    ).toBe(best.team_name);
  });

  it('clicking the active header reverses the order', () => {
    const { table } = renderTeams();
    const before = rowOrder(table)[0];
    clickHeader(table, /Net EPA/i);
    expect(rowOrder(table)[0]).not.toBe(before);
  });

  it('sorting preserves the active filter', () => {
    const { table, container } = renderTeams();
    clickConference(container, 'AFC');
    const before = rowOrder(table).sort();
    clickHeader(table, /Off\.? EPA/i);
    expect(rowOrder(table).sort()).toEqual(before);
  });
});

describe('TeamsClient team detail', () => {
  it('clicking a row opens that team without crashing', () => {
    const { table, container } = renderTeams();
    const name = rowOrder(table)[0];
    const row = Array.from(table.querySelectorAll('tbody tr')).find((r) => r.textContent?.includes(name))!;
    fireEvent.click(row);
    expect(container.textContent).toContain(name);
    expect(container.textContent).not.toMatch(/NaN|undefined/);
  });
});

describe('TeamsClient resilience', () => {
  it('renders an empty league without throwing', () => {
    expect(() => render(<TeamsClient teams={[]} />)).not.toThrow();
  });

  it('renders a single team without printing NaN', () => {
    const { container } = render(<TeamsClient teams={[teams[0]]} />);
    expect(container.textContent).not.toMatch(/NaN/);
  });
});
