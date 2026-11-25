/**
 * /momentum board client (#226). Reads the real momentum_board.json; fixtures
 * are deep copies of it with one field changed, used where today's data has no
 * example (no team currently carries last season's games, and every team has a
 * key-players value).
 */
import React from 'react';
import fs from 'fs';
import path from 'path';
import { describe, expect, it } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MomentumClient, carriedLabel, sortRows } from '@/components/MomentumClient';
import type { MomentumPayload } from '@/lib/momentumTypes';

const DATA: MomentumPayload = JSON.parse(
  fs.readFileSync(path.join(process.cwd(), 'public', 'data', 'momentum_board.json'), 'utf8'),
);
const clone = (): MomentumPayload => JSON.parse(JSON.stringify(DATA));
const D = String(DATA.default_window);
const windowLabel = (w: number | string) => DATA.boards[String(w)].label;

const teamRows = () => Array.from(document.querySelectorAll<HTMLElement>('tbody tr[data-team]'));
const teamOrder = () => teamRows().map((r) => r.dataset.team);
const rowFor = (team: string) => document.querySelector<HTMLElement>(`tr[data-team="${team}"]`)!;
const expand = async (user: ReturnType<typeof userEvent.setup>, team: string) => {
  await user.click(within(rowFor(team)).getByRole('button', { expanded: false }));
  return screen.getByTestId('momentum-detail');
};

describe('MomentumClient: header and not-a-forecast', () => {
  it('says the board is recent play, not a forecast, using the JSON summary', () => {
    render(<MomentumClient data={DATA} />);
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Momentum Board');
    const note = screen.getByTestId('momentum-not-forecast');
    expect(note).toHaveTextContent('not a forecast');
    expect(note).toHaveTextContent(DATA.methods.summary);
  });

  it('links to the full methodology page', () => {
    render(<MomentumClient data={DATA} />);
    expect(screen.getByRole('link', { name: 'Full methodology and everything we tested' })).toHaveAttribute(
      'href',
      '/momentum/methodology',
    );
  });

  it('shows an unavailable message without data', () => {
    render(<MomentumClient data={null} />);
    expect(screen.getByText(/unavailable/)).toBeInTheDocument();
  });
});

describe('MomentumClient: windows', () => {
  it('opens on default_window with every team, ranked teams in rank order', () => {
    render(<MomentumClient data={DATA} />);
    expect(screen.getByRole('button', { name: windowLabel(D) })).toHaveAttribute('aria-pressed', 'true');
    expect(teamRows()).toHaveLength(DATA.boards[D].rows.length);
    const ranked = DATA.boards[D].rows.filter((r) => r.ranked).sort((a, b) => a.rank! - b.rank!);
    expect(teamOrder().slice(0, ranked.length)).toEqual(ranked.map((r) => r.team));
  });

  it('offers windows 3, 6 and 9 and labels the noisiest one', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    expect(DATA.windows).toEqual([3, 6, 9]);
    const noisiest = DATA.methods.windows.noisiest;
    expect(windowLabel(noisiest)).toMatch(/noisiest/);
    await user.click(screen.getByRole('button', { name: windowLabel(noisiest) }));
    expect(screen.getByRole('button', { name: windowLabel(noisiest) })).toHaveAttribute('aria-pressed', 'true');
    expect(screen.getByTestId('momentum-noisiest')).toHaveTextContent(DATA.methods.windows.note);
    for (const w of DATA.windows.filter((x) => x !== noisiest)) {
      await user.click(screen.getByRole('button', { name: windowLabel(w) }));
      expect(screen.queryByTestId('momentum-noisiest')).toBeNull();
      expect(teamRows()).toHaveLength(DATA.boards[String(w)].rows.length);
    }
  });
});

describe('MomentumClient: carried games', () => {
  it('labels a row whose window includes last season, regressed to the mean', () => {
    const data = clone();
    const row = data.boards[D].rows[0];
    row.carried_games = 2;
    row.current_season_games_in_window = row.games_in_window - 2;
    row.carried_from_season = data.season - 1;
    data.boards[D].carried_team_count = 1;
    render(<MomentumClient data={data} />);
    const label = within(rowFor(row.team)).getByTestId('carried-label');
    expect(label).toHaveTextContent(`Includes 2 games from ${data.season - 1}, regressed to the mean`);
    expect(screen.getByTestId('momentum-carried-note')).toHaveTextContent('1 team');
    expect(screen.getAllByTestId('carried-label')).toHaveLength(1);
  });

  it('shows no carried label when carried_games is 0', () => {
    render(<MomentumClient data={DATA} />);
    const carried = DATA.boards[D].rows.filter((r) => r.carried_games > 0).length;
    expect(screen.queryAllByTestId('carried-label')).toHaveLength(carried);
    expect(carriedLabel({ ...DATA.boards[D].rows[0], carried_games: 0 }, 'mean_regress')).toBeNull();
  });
});

describe('MomentumClient: sorting', () => {
  it.each(DATA.sort_options.map((o) => o.key))('sorts by %s from the select', async (key) => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    await user.selectOptions(screen.getByRole('combobox', { name: 'Sort by' }), key);
    const opt = DATA.sort_options.find((o) => o.key === key)!;
    expect(teamOrder()).toEqual(sortRows(DATA.boards[D].rows, key, opt.descending).map((r) => r.team));
  });

  it('has a sortable opponent-adjusted margin column', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    const label = DATA.sort_options.find((o) => o.key === 'opponent_adjusted_margin')!.label;
    const header = screen.getByRole('columnheader', { name: new RegExp(label) });
    expect(header).toHaveAttribute('aria-sort', 'none');
    await user.click(within(header).getByRole('button', { name: new RegExp(`^${label}`) }));
    expect(header).toHaveAttribute('aria-sort', 'descending');
    const vals = teamOrder()
      .map((t) => DATA.boards[D].rows.find((r) => r.team === t)!)
      .filter((r) => r.ranked)
      .map((r) => r.sort_keys.opponent_adjusted_margin)
      .filter((v): v is number => v !== null);
    expect([...vals].sort((a, b) => b - a)).toEqual(vals);
    await user.click(within(header).getByRole('button', { name: new RegExp(`^${label}`) }));
    expect(header).toHaveAttribute('aria-sort', 'ascending');
  });

  it('puts unranked teams last', () => {
    const rows = sortRows(DATA.boards['3'].rows, 'combined_score', true);
    const firstUnranked = rows.findIndex((r) => !r.ranked);
    if (firstUnranked >= 0) expect(rows.slice(firstUnranked).every((r) => !r.ranked)).toBe(true);
  });
});

describe('MomentumClient: expanded row', () => {
  const team = DATA.boards[D].rows.find((r) => r.ranked)!.team;

  it('shows raw flag values with no significance badge', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    const detail = await expand(user, team);
    expect(within(detail).getByRole('heading', { name: 'Key numbers' })).toBeInTheDocument();
    expect(within(detail).getByRole('heading', { name: 'EPA splits' })).toBeInTheDocument();
    const row = DATA.boards[D].rows.find((r) => r.team === team)!;
    for (const f of row.flags.filter((x) => x.group !== 'availability')) {
      const card = within(detail).getByTestId(`flag-${f.key}`);
      const def = DATA.methods.flags.definitions.find((d) => d.key === f.key)!;
      expect(card).toHaveTextContent(def.label);
      expect(card).toHaveTextContent(f.value === null ? `Missing: ${f.null_reason}` : `Raw value${f.value}`);
    }
    expect(detail.textContent).not.toMatch(/Significant/);
    expect(detail.textContent).toContain(DATA.methods.flags.significance_hidden_reason);
  });

  it('shows the starting-QB change as context only, with the current starter', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    const detail = await expand(user, team);
    const qb = within(detail).getByTestId('qb-change');
    const flag = DATA.boards[D].rows.find((r) => r.team === team)!.flags.find((f) => f.key === 'starting_qb_change')!;
    const starter = (flag.detail as { current_starter?: { name: string } }).current_starter;
    if (starter) expect(qb).toHaveTextContent(starter.name);
    expect(qb).toHaveTextContent('Context only');
  });

  it('shows key players missing as a raw value, or its null reason', async () => {
    const user = userEvent.setup();
    const data = clone();
    const kpm = data.boards[D].rows.find((r) => r.team === team)!.flags.find((f) => f.key === 'key_players_missing')!;
    const raw = kpm.value;
    render(<MomentumClient data={DATA} />);
    let detail = await expand(user, team);
    expect(within(detail).getByTestId('key-players-missing')).toHaveTextContent(`Raw value ${raw}`);
    document.body.innerHTML = '';

    kpm.value = null;
    kpm.null_reason = 'no injury report published for this window';
    render(<MomentumClient data={data} />);
    detail = await expand(user, team);
    expect(within(detail).getByTestId('key-players-missing')).toHaveTextContent(
      'Missing: no injury report published for this window',
    );
  });

  it('shows a missing value with its reason, never a filled number', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    await user.click(screen.getByRole('button', { name: windowLabel(3) }));
    const row = DATA.boards['3'].rows.find((r) => r.flags.some((f) => f.value === null && f.null_reason));
    if (!row) return;
    const flag = row.flags.find((f) => f.value === null && f.null_reason)!;
    const detail = await expand(user, row.team);
    expect(within(detail).getByTestId(`flag-${flag.key}`)).toHaveTextContent(`Missing: ${flag.null_reason}`);
  });
});

describe('MomentumClient: methods panel', () => {
  it('states the flat surface, the weights in use and why badges are hidden', async () => {
    const user = userEvent.setup();
    render(<MomentumClient data={DATA} />);
    await user.click(screen.getByRole('button', { name: 'How this is calculated' }));
    const panel = screen.getByTestId('methods-panel');
    expect(within(panel).getByTestId('flat-surface')).toHaveTextContent(DATA.methods.combined_score.flat_surface);
    expect(within(panel).getByTestId('badges-hidden')).toHaveTextContent(DATA.methods.flags.significance_hidden_reason);
    expect(panel).toHaveTextContent(DATA.methods.summary);
    const table = within(panel).getByTestId('weights-in-use');
    for (const w of DATA.windows) {
      const tr = within(table).getByRole('row', { name: new RegExp(`^${w} games`) });
      const weights = DATA.methods.combined_score.weights[String(w)];
      const cells = within(tr).getAllByRole('cell').map((c) => Number(c.textContent));
      expect(cells).toEqual([weights.form, weights.trend, weights.residual, weights.elo_change]);
    }
  });
});
