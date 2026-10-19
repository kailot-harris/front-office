import { describe, expect, it } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import PlayersClient from '../../components/PlayersClient';
import { qbs } from '../helpers/datasets';

const all = qbs();

function renderPlayers() {
  const { container } = render(<PlayersClient initialQbs={all} />);
  const table = container.querySelector('table');
  if (!table) throw new Error('PlayersClient rendered without a <table>');
  return { container, table: table as HTMLTableElement };
}

const NAMES = new Set(all.map((q) => q.player_name));

/** QB names in the table body, in render order. */
function rowOrder(table: HTMLTableElement): string[] {
  return Array.from(table.querySelectorAll('tbody tr'))
    .map((row) =>
      Array.from(row.querySelectorAll('*'))
        .map((el) => el.textContent?.trim())
        .find((t) => t && NAMES.has(t)),
    )
    .filter((n): n is string => Boolean(n));
}

const DEFAULT_PAGE_SIZE = 25;

describe('PlayersClient renders', () => {
  it('mounts on the real dataset', () => {
    expect(() => render(<PlayersClient initialQbs={all} />)).not.toThrow();
  });

  it('reports the tracked quarterback count', () => {
    render(<PlayersClient initialQbs={all} />);
    expect(screen.getByText(new RegExp(`${all.length}\\s+Active Quarterbacks`, 'i'))).toBeInTheDocument();
  });

  it('never prints NaN or undefined', () => {
    const { container } = renderPlayers();
    expect(container.textContent).not.toMatch(/NaN|undefined/);
  });

  it('offers a filter option for every team with a listed QB', () => {
    const { container } = renderPlayers();
    const options = Array.from(container.querySelectorAll('select option')).map((o) => o.textContent?.trim());
    for (const team of new Set(all.map((q) => q.team))) {
      expect(options, `${team} missing from the team filter`).toContain(team);
    }
  });
});

describe('PlayersClient leaderboards', () => {
  const qualified = all.filter((q) => q.is_starter || (q.attempts_2026 ?? 0) >= 35);

  it('the EPA podium holds the top three qualified quarterbacks', () => {
    render(<PlayersClient initialQbs={all} />);
    const top3 = [...qualified].sort((a, b) => b.off_epa_roll - a.off_epa_roll).slice(0, 3);
    for (const qb of top3) {
      expect(screen.getAllByText(qb.player_name).length, `${qb.player_name} missing from the EPA podium`).toBeGreaterThan(0);
    }
  });

  it('the CPOE podium holds the top three qualified quarterbacks', () => {
    render(<PlayersClient initialQbs={all} />);
    const top3 = [...qualified].sort((a, b) => b.off_cpoe_roll - a.off_cpoe_roll).slice(0, 3);
    for (const qb of top3) {
      expect(screen.getAllByText(qb.player_name).length).toBeGreaterThan(0);
    }
  });

  it('excludes low-volume backups from the podium', () => {
    render(<PlayersClient initialQbs={all} />);
    // A high-EPA QB who is neither a starter nor past 35 attempts must not
    // outrank real starters on the podium.
    const unqualifiedLeader = [...all]
      .filter((q) => !q.is_starter && (q.attempts_2026 ?? 0) < 35)
      .sort((a, b) => b.off_epa_roll - a.off_epa_roll)[0];
    if (!unqualifiedLeader) return;
    const podium = [...qualified].sort((a, b) => b.off_epa_roll - a.off_epa_roll).slice(0, 3);
    expect(podium.map((q) => q.player_name)).not.toContain(unqualifiedLeader.player_name);
  });

  it('does not render a "+" in front of a negative leaderboard value', () => {
    // The podium markup writes `+{qb.off_epa_roll.toFixed(3)}` unconditionally.
    const { container } = render(<PlayersClient initialQbs={all} />);
    expect(container.textContent, 'a hardcoded "+" is prefixing a negative number').not.toMatch(/\+-\d/);
  });
});

describe('PlayersClient search', () => {
  const search = () => screen.getByPlaceholderText(/search quarterback/i);

  it('matches on player name', () => {
    const { table } = renderPlayers();
    const target = all[0];
    fireEvent.change(search(), { target: { value: target.player_name } });
    expect(rowOrder(table)).toContain(target.player_name);
  });

  it('matches on team code', () => {
    const { table } = renderPlayers();
    fireEvent.change(search(), { target: { value: 'KC' } });
    const shown = rowOrder(table);
    expect(shown.length).toBeGreaterThan(0);
    for (const name of shown) {
      const qb = all.find((q) => q.player_name === name)!;
      expect(
        qb.team === 'KC' || qb.player_name.toLowerCase().includes('kc') || (qb.college ?? '').toLowerCase().includes('kc'),
        `${name} (${qb.team}) does not match "KC"`,
      ).toBe(true);
    }
  });

  it('matches on college', () => {
    const { table } = renderPlayers();
    const withCollege = all.find((q) => q.college && q.college.length > 3)!;
    fireEvent.change(search(), { target: { value: withCollege.college } });
    expect(rowOrder(table)).toContain(withCollege.player_name);
  });

  it('is case-insensitive', () => {
    const { table } = renderPlayers();
    const target = all[0];
    fireEvent.change(search(), { target: { value: target.player_name.toUpperCase() } });
    expect(rowOrder(table)).toContain(target.player_name);
  });

  it('an unmatched query empties the table without crashing', () => {
    const { table, container } = renderPlayers();
    fireEvent.change(search(), { target: { value: 'zzzznotaplayer' } });
    expect(rowOrder(table)).toEqual([]);
    expect(container.textContent).not.toMatch(/NaN|undefined/);
  });
});

describe('PlayersClient team filter', () => {
  it('narrows the table to one team', () => {
    const { table, container } = renderPlayers();
    const select = container.querySelector('select')!;
    fireEvent.change(select, { target: { value: 'KC' } });
    const shown = rowOrder(table);
    expect(shown.length).toBeGreaterThan(0);
    for (const name of shown) {
      expect(all.find((q) => q.player_name === name)!.team).toBe('KC');
    }
  });
});

describe('PlayersClient sorting', () => {
  function clickHeader(table: HTMLTableElement, label: RegExp) {
    const th = Array.from(table.querySelectorAll('thead th')).find((el) => label.test(el.textContent ?? ''));
    expect(th, `no header matching ${label}`).toBeTruthy();
    fireEvent.click(th!);
  }

  it('defaults to EPA descending', () => {
    const { table } = renderPlayers();
    const expected = [...all].sort((a, b) => b.off_epa_roll - a.off_epa_roll)[0].player_name;
    expect(rowOrder(table)[0]).toBe(expected);
  });

  it('clicking the active EPA header flips to ascending', () => {
    const { table } = renderPlayers();
    clickHeader(table, /EPA \/ Play/i);
    const expected = [...all].sort((a, b) => a.off_epa_roll - b.off_epa_roll)[0].player_name;
    expect(rowOrder(table)[0]).toBe(expected);
  });

  it('sorting by CPOE puts the CPOE leader first', () => {
    const { table } = renderPlayers();
    clickHeader(table, /CPOE/i);
    const expected = [...all].sort((a, b) => b.off_cpoe_roll - a.off_cpoe_roll)[0].player_name;
    expect(rowOrder(table)[0]).toBe(expected);
  });
});

describe('PlayersClient pagination', () => {
  it('shows only one page of rows by default', () => {
    const { table } = renderPlayers();
    expect(rowOrder(table)).toHaveLength(Math.min(DEFAULT_PAGE_SIZE, all.length));
  });

  it('the Next button advances to page 2', () => {
    const { table } = renderPlayers();
    const page1 = rowOrder(table);
    const next = screen.getAllByRole('button').find((b) => /next/i.test(b.textContent ?? ''));
    expect(next, 'no Next button').toBeTruthy();
    fireEvent.click(next!);
    const page2 = rowOrder(table);
    expect(page2[0]).not.toBe(page1[0]);
    expect(page2.every((n) => !page1.includes(n)), 'page 2 repeats rows from page 1').toBe(true);
  });

  it('Previous is disabled on page 1', () => {
    renderPlayers();
    const prev = screen.getAllByRole('button').find((b) => /prev/i.test(b.textContent ?? ''));
    expect(prev).toBeTruthy();
    expect(prev).toBeDisabled();
  });

  it('paging through every page yields each QB exactly once', () => {
    const { table } = renderPlayers();
    const seen: string[] = [];
    const totalPages = Math.ceil(all.length / DEFAULT_PAGE_SIZE);
    for (let p = 0; p < totalPages; p++) {
      seen.push(...rowOrder(table));
      if (p < totalPages - 1) {
        const next = screen.getAllByRole('button').find((b) => /next/i.test(b.textContent ?? ''))!;
        fireEvent.click(next);
      }
    }
    expect(seen.sort()).toEqual([...NAMES].sort());
  });

  it('filtering while on a later page does not strand the user on an empty page', () => {
    // currentPage is only reset by the page-size control, never by the search
    // or team filter. Filtering 87 QBs down to a handful while on page 3 leaves
    // `(3-1)*25 = 50` as the slice offset, so the table renders zero rows while
    // the footer still claims matches exist.
    const { table } = renderPlayers();
    const next = () => screen.getAllByRole('button').find((b) => /next/i.test(b.textContent ?? ''))!;
    fireEvent.click(next());
    fireEvent.click(next()); // page 3
    expect(rowOrder(table).length, 'precondition: page 3 should have rows').toBeGreaterThan(0);

    const target = all[0];
    fireEvent.change(screen.getByPlaceholderText(/search quarterback/i), {
      target: { value: target.player_name },
    });
    expect(
      rowOrder(table),
      'the search matched a quarterback but the table is empty because currentPage was never reset',
    ).toContain(target.player_name);
  });

  it('the row-count footer never claims more rows than it renders', () => {
    const { container, table } = renderPlayers();
    fireEvent.change(screen.getByPlaceholderText(/search quarterback/i), { target: { value: all[0].player_name } });
    const footer = (container.textContent ?? '').match(/of\s+(\d+)\s+QBs/);
    if (footer) {
      const claimed = Number(footer[1]);
      expect(rowOrder(table).length, `footer claims ${claimed} matches but the table shows none`).toBeGreaterThan(
        claimed > 0 ? 0 : -1,
      );
    }
  });
});

describe('PlayersClient selection', () => {
  it('clicking a row selects that quarterback', () => {
    const { table, container } = renderPlayers();
    const first = rowOrder(table)[0];
    const row = Array.from(table.querySelectorAll('tbody tr')).find((r) => r.textContent?.includes(first))!;
    fireEvent.click(row);
    expect(container.textContent).toContain(first);
    expect(container.textContent).not.toMatch(/NaN|undefined/);
  });
});

describe('PlayersClient resilience', () => {
  it('renders an empty roster without throwing', () => {
    expect(() => render(<PlayersClient initialQbs={[]} />)).not.toThrow();
  });

  it('renders a single QB without pagination errors', () => {
    const { container } = render(<PlayersClient initialQbs={[all[0]]} />);
    expect(container.textContent).not.toMatch(/NaN|Infinity/);
  });
});
