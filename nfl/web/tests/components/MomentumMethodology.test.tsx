/**
 * /momentum/methodology (#226). Every figure the page shows is read from
 * momentum_methodology.json; these tests check the page against that file.
 */
import React from 'react';
import fs from 'fs';
import path from 'path';
import { describe, expect, it } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { METHODOLOGY_SECTIONS, MomentumMethodology } from '@/components/MomentumMethodology';
import type { MomentumMethodologyPayload } from '@/lib/momentumMethodologyTypes';

const DATA: MomentumMethodologyPayload = JSON.parse(
  fs.readFileSync(path.join(process.cwd(), 'public', 'data', 'momentum_methodology.json'), 'utf8'),
);
const MM = DATA.momentum_measures;
const RW = DATA.rolling_window;
const PRIMARY = MM.targets.find((t) => t.primary)!.id;
const pct = (v: number) => `${Math.round(v * 100)}%`;

describe('MomentumMethodology page', () => {
  it('renders every section heading in order', () => {
    render(<MomentumMethodology data={DATA} />);
    const h2s = screen
      .getAllByRole('heading', { level: 2 })
      .map((h) => h.textContent)
      .filter((t) => t !== 'On this page');
    expect(h2s).toEqual(METHODOLOGY_SECTIONS.map((s) => s.title));
  });

  it('states the not-a-forecast headline with counts computed from the results', () => {
    render(<MomentumMethodology data={DATA} />);
    const head = screen.getByTestId('methodology-headline');
    const scored = RW.stronger_arm.table.filter((r) => r.n > 0 && r.lo !== null);
    const above = scored.filter((r) => r.lo! > 0).length;
    expect(head).toHaveTextContent(`${above} of ${scored.length} scored`);
    expect(head).toHaveTextContent(MM.combination_search.final_verdict);
  });

  it('shows the board weights from weights.detail at each board window', () => {
    render(<MomentumMethodology data={DATA} />);
    const table = screen.getByTestId('methodology-weights');
    for (const w of DATA.board.windows) {
      const r = RW.weights.detail.find(
        (x) => x.method === DATA.board.carry_method && x.window === String(w) && x.target === DATA.board.weights_target,
      )!;
      const tr = within(table).getByRole('row', { name: new RegExp(`^${w} games`) });
      const cells = within(tr).getAllByRole('cell').slice(0, r.best_weights.length).map((c) => c.textContent);
      expect(cells).toEqual(r.best_weights.map(pct));
    }
  });

  it('explains the flat surface and names the NBA-style weights with their provenance', () => {
    render(<MomentumMethodology data={DATA} />);
    const flat = screen.getByTestId('methodology-flat');
    const nba = DATA.sources.rolling_window.nba_comparison_weights;
    expect(flat).toHaveTextContent('flat');
    expect(flat).toHaveTextContent(
      `form ${pct(nba.form)} / trend ${pct(nba.trend)} / margin vs Elo ${pct(nba.residual)} / Elo change ${pct(nba.elo_change)}`,
    );
    expect(screen.getByTestId('nba-weights-provenance')).toHaveTextContent(`line ${nba.provenance.line}`);
  });

  it('explains why badges are hidden from the simulated detection rates', () => {
    render(<MomentumMethodology data={DATA} />);
    const text = screen.getByTestId('methodology-badges');
    expect(text).toHaveTextContent(pct(RW.flags.power_threshold));
    for (const w of DATA.board.windows) {
      const max = Math.max(...RW.flags.detection.filter((d) => d.window === String(w)).map((d) => d.simulated_detection_rate));
      expect(text).toHaveTextContent(`${pct(max)} at ${w} games`);
    }
  });

  it('lists every measures-study flag row, descriptive rows included', () => {
    render(<MomentumMethodology data={DATA} />);
    const table = screen.getByTestId('methodology-flag-rows');
    expect(within(table).getAllByRole('row')).toHaveLength(MM.flags.rows.length + 1);
  });

  it('opens the everything-tried table on the primary target and shows every row for all targets', async () => {
    const user = userEvent.setup();
    render(<MomentumMethodology data={DATA} />);
    expect(screen.getByLabelText('What it tries to predict')).toHaveValue(PRIMARY);
    expect(screen.getAllByTestId('tried-row')).toHaveLength(MM.single_feature_results.filter((r) => r.target === PRIMARY).length);
    await user.selectOptions(screen.getByLabelText('What it tries to predict'), 'All targets');
    expect(screen.getAllByTestId('tried-row')).toHaveLength(MM.single_feature_results.length);
    expect(screen.getByTestId('tried-count')).toHaveTextContent(
      `Showing ${MM.single_feature_results.length} of ${MM.single_feature_results.length} rows`,
    );
  });

  it('filters by verdict', async () => {
    const user = userEvent.setup();
    render(<MomentumMethodology data={DATA} />);
    for (const v of ['inconclusive', 'discarded'] as const) {
      await user.selectOptions(screen.getByLabelText('Verdict'), v);
      const n = MM.single_feature_results.filter((r) => r.target === PRIMARY && r.verdict === v).length;
      expect(screen.queryAllByTestId('tried-row')).toHaveLength(n);
    }
  });

  it('links back to the board and names both source commits', () => {
    render(<MomentumMethodology data={DATA} />);
    for (const l of screen.getAllByRole('link', { name: 'Back to the Momentum Board' })) expect(l).toHaveAttribute('href', '/momentum');
    const sources = screen.getByTestId('methodology-sources');
    expect(sources).toHaveTextContent(DATA.sources.rolling_window.commit.slice(0, 7));
    expect(sources).toHaveTextContent(DATA.sources.momentum_measures.commit.slice(0, 7));
  });

  it('uses no betting vocabulary', () => {
    render(<MomentumMethodology data={DATA} />);
    expect(document.body.textContent).not.toMatch(/\b(odds|spreads?|picks?|props?|wagers?|edges?|bets?|betting|sportsbook)\b/i);
  });
});
