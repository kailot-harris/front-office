import { describe, expect, it } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import { StandingsClient } from '@/components/StandingsClient';
import { loadAllDatasets } from '../helpers/datasets';

const { teams, metadata } = loadAllDatasets();
const TEAM_NAMES = new Set(teams.map((t) => t.team_name));

function renderTable() {
  const { container } = render(
    <StandingsClient teams={teams} metadata={metadata} initialTab="table" />
  );
  const table = container.querySelector('table');
  if (!table) throw new Error('table view rendered without a <table>');
  return { container, table: table as HTMLTableElement };
}

function rowOrder(table: HTMLTableElement): string[] {
  return Array.from(table.querySelectorAll('tbody tr'))
    .map((row) =>
      Array.from(row.querySelectorAll('*'))
        .map((el) => el.textContent?.trim())
        .find((text) => text && TEAM_NAMES.has(text))
    )
    .filter((name): name is string => Boolean(name));
}

describe('StandingsClient renders', () => {
  it('mounts on the real dataset without throwing', () => {
    expect(() =>
      render(<StandingsClient teams={teams} metadata={metadata} />)
    ).not.toThrow();
  });

  it('shows visualizer and table view tabs', () => {
    render(<StandingsClient teams={teams} metadata={metadata} />);
    expect(screen.getByRole('tab', { name: /visualizer/i })).toBeInTheDocument();
    expect(screen.getByRole('tab', { name: /full standings table/i })).toBeInTheDocument();
  });

  it('lists all 30 teams in table view', () => {
    const { table } = renderTable();
    expect(rowOrder(table).sort()).toEqual([...TEAM_NAMES].sort());
  });

  it('renders title probability as percentage', () => {
    render(<StandingsClient teams={teams} metadata={metadata} />);
    const favourite = [...teams].sort((a, b) => b.ensemble_title_prob - a.ensemble_title_prob)[0];
    const pct = `${(favourite.ensemble_title_prob * 100).toFixed(1)}%`;
    expect(screen.getAllByText(pct).length).toBeGreaterThan(0);
  });

  it('never prints NaN or undefined in the container', () => {
    const { container } = renderTable();
    expect(container.textContent).not.toMatch(/NaN|undefined/);
  });
});

describe('StandingsClient conference filter', () => {
  it('narrows the table to East conference (15 teams)', () => {
    const { table } = renderTable();
    fireEvent.click(screen.getByRole('button', { name: /east conf/i }));
    const shown = new Set(rowOrder(table));
    expect(shown.size).toBe(15);
    for (const t of teams) {
      expect(shown.has(t.team_name), `${t.team} (${t.conference})`).toBe(t.conference === 'East');
    }
  });

  it('restores all teams when switching back to All', () => {
    const { table } = renderTable();
    fireEvent.click(screen.getByRole('button', { name: /west conf/i }));
    fireEvent.click(screen.getByRole('button', { name: /all leagues/i }));
    expect(rowOrder(table)).toHaveLength(30);
  });
});

describe('StandingsClient division filter', () => {
  it('narrows to a single division via dropdown', () => {
    const { table, container } = renderTable();
    const select = container.querySelector('select');
    expect(select, 'division dropdown missing').not.toBeNull();
    fireEvent.change(select!, { target: { value: 'Atlantic' } });
    const shown = rowOrder(table);
    expect(shown).toHaveLength(5);
    for (const name of shown) {
      expect(teams.find((t) => t.team_name === name)!.division).toBe('Atlantic');
    }
  });
});
