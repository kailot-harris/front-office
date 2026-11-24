import React from 'react';
import fs from 'fs';
import path from 'path';
import { describe, expect, it } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MOMENTUM_COLUMN_COUNT, MomentumClient, sortRows } from '@/components/MomentumClient';
import type { MomentumPayload } from '@/lib/momentumTypes';

const DATA: MomentumPayload = JSON.parse(
  fs.readFileSync(path.join(process.cwd(), 'public', 'data', 'momentum_board.json'), 'utf8'),
);

const teamRows = () => Array.from(document.querySelectorAll<HTMLElement>('tbody tr[data-team]'));
const teamOrder = () => teamRows().map((r) => r.dataset.team);
const rowFor = (team: string) => document.querySelector<HTMLElement>(`tr[data-team="${team}"]`)!;
const expectedOrder = (key: string, w: number) =>
  sortRows(DATA.boards[String(w)].rows, DATA.sort_options.find((o) => o.key === key)!).map((r) => r.team);

describe('MomentumClient: board and window toggle', () => {
  it('opens at the default window on the combined score with all 30 teams', () => {
    render(<MomentumClient data={DATA} />);
    expect(teamRows()).toHaveLength(30);
    const d = DATA.default_window;
    expect(screen.getByRole('button', { name: `Last ${d}` })).toHaveAttribute('aria-pressed', 'true');
    expect(screen.getByRole('combobox', { name: 'Sort by' })).toHaveValue('combined_score');
    const ranked = DATA.boards[String(d)].rows.filter((r) => r.ranked).sort((a, b) => a.rank! - b.rank!);
    expect(teamOrder().slice(0, ranked.length)).toEqual(ranked.map((r) => r.team));
  });

  it('shows 30 teams for each window after toggling', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    for (const w of [5, 10, 18]) {
      await user.click(screen.getByRole('button', { name: `Last ${w}` }));
      expect(screen.getByRole('button', { name: `Last ${w}` })).toHaveAttribute('aria-pressed', 'true');
      expect(teamRows()).toHaveLength(30);
      expect(teamOrder()).toEqual(expectedOrder('combined_score', w));
    }
  });

  it('is operable from the keyboard', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    screen.getByRole('button', { name: 'Last 5' }).focus();
    await user.keyboard('{Enter}');
    expect(screen.getByRole('button', { name: 'Last 5' })).toHaveAttribute('aria-pressed', 'true');
    await user.keyboard('{Tab}');
    expect(screen.getByRole('button', { name: 'Last 10' })).toHaveFocus();
    await user.keyboard(' ');
    expect(screen.getByRole('button', { name: 'Last 10' })).toHaveAttribute('aria-pressed', 'true');
  });
});

describe('MomentumClient: sorting', () => {
  it.each(DATA.sort_options.map((o) => o.key))('sorts by %s', async (key) => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    await user.click(screen.getByRole('button', { name: 'Last 10' }));
    await user.selectOptions(screen.getByRole('combobox', { name: 'Sort by' }), key);
    const order = teamOrder();
    expect(order).toEqual(expectedOrder(key, 10));
    const vals = order.map((t) => DATA.boards['10'].rows.find((r) => r.team === t)!.sort_keys[key]);
    const present = vals.filter((v): v is number => v !== null);
    expect([...present].sort((a, b) => b - a)).toEqual(present);
  });

  it('uses a plain label for the model residual sort and shows its game count', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    await user.click(screen.getByRole('button', { name: 'Last 10' }));
    await user.selectOptions(screen.getByRole('combobox', { name: 'Sort by' }), 'model_residual');
    expect(screen.getByRole('option', { name: 'Beat model expectation by' })).toBeInTheDocument();
    const first = DATA.boards['10'].rows.find((r) => r.team === teamOrder()[0])!;
    expect(
      within(teamRows()[0]).getByText(`(${first.model_residual.residual_games_in_window} games)`),
    ).toBeInTheDocument();
  });

  it('puts unranked teams last for every sort', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    await user.click(screen.getByRole('button', { name: 'Last 18' }));
    for (const o of DATA.sort_options) {
      await user.selectOptions(screen.getByRole('combobox', { name: 'Sort by' }), o.key);
      const flags = teamRows().map((r) => r.dataset.ranked === 'true');
      expect(flags.lastIndexOf(true)).toBeLessThan(flags.indexOf(false));
    }
  });
});

describe('MomentumClient: every sort has a visible column', () => {
  it('keeps the same columns for every sort and marks the sorted one', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    const headerTexts = () => screen.getAllByRole('columnheader').map((th) => th.textContent ?? '');
    const first = headerTexts();
    for (const o of DATA.sort_options) {
      await user.selectOptions(screen.getByRole('combobox', { name: 'Sort by' }), o.key);
      expect(headerTexts()).toEqual(first);
      const sorted = screen.getAllByRole('columnheader').filter((th) => th.getAttribute('aria-sort') === 'descending');
      expect(sorted).toHaveLength(1);
    }
    for (const label of ['Momentum score', 'Elo 7d', 'Elo 14d', 'Beat model expectation by', 'Net rating change', 'Schedule strength faced']) {
      expect(first.some((t) => t.startsWith(label))).toBe(true);
    }
  });

  it('shows schedule strength faced next to the Elo 7d change', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    await user.selectOptions(screen.getByRole('combobox', { name: 'Sort by' }), 'elo_change_7d');
    const d = DATA.default_window;
    const top = sortRows(DATA.boards[String(d)].rows, DATA.sort_options.find((o) => o.key === 'elo_change_7d')!)[0];
    const cell = rowFor(top.team).querySelector('td[data-col="schedule_strength"]')!;
    expect(cell.textContent).toBe(`${(top.sort_keys.schedule_strength! * 100).toFixed(1)}%`);
  });
});

describe('MomentumClient: unranked teams and the board note', () => {
  const unranked = DATA.boards['18'].rows.filter((r) => !r.ranked);

  it('greys unranked teams, shows n of N games, and no rank', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    await user.click(screen.getByRole('button', { name: 'Last 18' }));
    expect(unranked.length).toBeGreaterThan(0);
    for (const u of unranked) {
      const tr = rowFor(u.team);
      expect(tr.dataset.ranked).toBe('false');
      expect(tr.className).toContain('text-slate-400');
      expect(within(tr).getByText(`${u.games_in_window} of 18 games`)).toBeInTheDocument();
      expect(tr.textContent).not.toMatch(/#\d+/);
    }
  });

  it('shows the board note when fewer than 30 teams are ranked, and not when all are', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    await user.click(screen.getByRole('button', { name: 'Last 18' }));
    expect(screen.getByTestId('momentum-note')).toHaveTextContent(DATA.boards['18'].note!);
    await user.click(screen.getByRole('button', { name: 'Last 5' }));
    expect(screen.queryByTestId('momentum-note')).toBeNull();
  });

  it('gives a missing score its reason as a tooltip and expands the row', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    await user.click(screen.getByRole('button', { name: 'Last 18' }));
    const u = unranked.find((r) => r.combined_score.null_reason)!;
    expect(rowFor(u.team).querySelector(`[title="${u.combined_score.null_reason}"]`)).not.toBeNull();
    await user.click(within(rowFor(u.team)).getByRole('button', { name: new RegExp(u.team_name) }));
    expect(screen.getByRole('region', { name: `${u.team_name} details` })).toBeInTheDocument();
  });

  it('shows why drivers and the net rating change are blank when a team has too few earlier games', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    await user.click(screen.getByRole('button', { name: 'Last 18' }));
    const r = DATA.boards['18'].rows.find((x) => x.ratings.net.change === null && x.ratings.net.change_null_reason);
    if (!r) return;
    await user.click(within(rowFor(r.team)).getByRole('button', { name: new RegExp(r.team_name) }));
    const region = screen.getByRole('region', { name: `${r.team_name} details` });
    expect(within(region).getAllByText(new RegExp(r.ratings.net.change_null_reason!)).length).toBeGreaterThan(0);
    expect(region.textContent).not.toContain('vs earlier games');
  });
});

describe('MomentumClient: expand and collapse', () => {
  it('expands and collapses a row with aria-expanded', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    await user.click(screen.getByRole('button', { name: 'Last 5' }));
    const top = DATA.boards['5'].rows.find((r) => r.rank === 1)!;
    const btn = within(rowFor(top.team)).getByRole('button', { name: new RegExp(top.team_name) });
    expect(btn).toHaveAttribute('aria-expanded', 'false');
    expect(screen.queryByRole('region', { name: `${top.team_name} details` })).toBeNull();
    await user.click(btn);
    expect(btn).toHaveAttribute('aria-expanded', 'true');
    const region = screen.getByRole('region', { name: `${top.team_name} details` });
    expect(within(region).getByText('What is driving it')).toBeInTheDocument();
    expect(within(region).getByText('Flags')).toBeInTheDocument();
    expect(within(region).getByText(/Next week.s schedule strength/)).toBeInTheDocument();
    expect(within(region).getByText('Rank history')).toBeInTheDocument();
    expect(within(region).getAllByRole('img').length).toBeGreaterThan(0);
    await user.click(btn);
    expect(screen.queryByRole('region', { name: `${top.team_name} details` })).toBeNull();
  });

  it('badges only significant flags, always shows raw values, and explains missing ones', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    await user.click(screen.getByRole('button', { name: 'Last 5' }));
    const row =
      DATA.boards['5'].rows.find((r) => r.flags.some((f) => f.significant) && r.flags.some((f) => f.value === null)) ??
      DATA.boards['5'].rows.find((r) => r.flags.some((f) => f.significant))!;
    await user.click(within(rowFor(row.team)).getByRole('button', { name: new RegExp(row.team_name) }));
    const region = screen.getByRole('region', { name: `${row.team_name} details` });
    const cards = within(region)
      .getAllByRole('listitem')
      .filter((li) => li.querySelector('dl'));
    expect(cards).toHaveLength(11);
    const defs = DATA.methods.flags.definitions;
    for (const f of row.flags) {
      const label = defs.find((d) => d.id === f.id)!.label;
      const card = cards.find((c) => within(c).queryByText(label))!;
      expect(card).toBeTruthy();
      expect(!!within(card).queryByText('Significant')).toBe(f.significant);
      if (f.value !== null) expect(within(card).getByText(String(f.value))).toBeInTheDocument();
      else expect(card.textContent).toContain(f.null_reason!);
    }
    expect(within(region).queryAllByText('Significant').length).toBe(row.flags.filter((f) => f.significant).length);
  });

  it('shows driver bars, next-week schedule and rank history', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    await user.click(screen.getByRole('button', { name: 'Last 5' }));
    const row = DATA.boards['5'].rows.find((r) => r.rank === 1)!;
    await user.click(within(rowFor(row.team)).getByRole('button', { name: new RegExp(row.team_name) }));
    const region = screen.getByRole('region', { name: `${row.team_name} details` });
    expect(within(region).getByText('Shooting efficiency (offense)')).toBeInTheDocument();
    for (const o of row.schedule_strength.next_week.opponents) {
      expect(region.textContent).toContain(o.opponent);
    }
    for (const h of row.rank_history) {
      expect(within(region).getByText(`Week of ${h.week_start}: rank ${h.rank}`)).toBeInTheDocument();
    }
  });
});

describe('MomentumClient: tooltips, methods panel, language', () => {
  it('has an info tooltip on every column header', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    const headers = screen.getAllByRole('columnheader');
    expect(headers).toHaveLength(MOMENTUM_COLUMN_COUNT);
    for (const th of headers) {
      await user.click(within(th).getByRole('button', { name: /^About / }));
      expect(within(th).getByRole('tooltip')).toBeInTheDocument();
      await user.keyboard('{Escape}');
      expect(within(th).queryByRole('tooltip')).toBeNull();
    }
  });

  it('has an info tooltip on every flag', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    const row = DATA.boards['18'].rows[0];
    await user.click(within(rowFor(row.team)).getByRole('button', { name: new RegExp(row.team_name) }));
    const region = screen.getByRole('region', { name: `${row.team_name} details` });
    for (const d of DATA.methods.flags.definitions) {
      expect(within(region).getByRole('button', { name: `About ${d.label}` })).toBeInTheDocument();
    }
  });

  it('builds the methods panel from the JSON and toggles it', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    const btn = screen.getByRole('button', { name: 'How this is calculated' });
    expect(btn).toHaveAttribute('aria-expanded', 'false');
    await user.click(btn);
    expect(btn).toHaveAttribute('aria-expanded', 'true');
    const panel = document.getElementById(btn.getAttribute('aria-controls')!)!;
    expect(panel.textContent).toContain(`K = ${DATA.methods.elo.k}`);
    expect(panel.textContent).toContain(DATA.methods.elo.margin_multiplier);
    expect(panel.textContent).toContain(`${Math.round(DATA.methods.combined_score.weights.form * 100)}% form`);
    expect(panel.textContent).toContain(DATA.methods.rank_history.starts);
    for (const d of DATA.methods.flags.definitions) expect(panel.textContent).toContain(d.label);
  });

  it('uses no betting terms or internal jargon in visible text, even fully expanded', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    await user.click(screen.getByRole('button', { name: 'How this is calculated' }));
    for (const r of DATA.boards['18'].rows.slice(0, 3)) {
      await user.click(within(rowFor(r.team)).getByRole('button', { name: new RegExp(r.team_name) }));
    }
    const text = document.body.textContent ?? '';
    const attrs = Array.from(document.querySelectorAll('[aria-label],[title]'))
      .map((e) => `${e.getAttribute('aria-label') ?? ''} ${e.getAttribute('title') ?? ''}`)
      .join(' ');
    expect(`${text} ${attrs}`).not.toMatch(
      /\b(odds|spread|bet|bets|betting|wager|parlay|sportsbook|moneyline|phase|slate|LOGGED_PREGAME|null_reason)\b|\.R\b/i,
    );
  });

  it('renders a message when the data file is unavailable', () => {
    render(<MomentumClient data={null} />);
    expect(screen.getByText(/unavailable/i)).toBeInTheDocument();
  });
});
