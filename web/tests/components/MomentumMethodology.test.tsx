import React from 'react';
import fs from 'fs';
import path from 'path';
import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { METHODOLOGY_SECTIONS, MomentumMethodology } from '@/components/MomentumMethodology';
import type { MomentumMethodologyPayload } from '@/lib/momentumMethodologyTypes';

const DATA: MomentumMethodologyPayload = JSON.parse(
  fs.readFileSync(path.join(process.cwd(), 'public', 'data', 'momentum_methodology.json'), 'utf8'),
);
const PRIMARY = DATA.targets.find((t) => t.primary)!.id;
const triedRows = () => screen.getAllByTestId('tried-row');

describe('MomentumMethodology page', () => {
  it('renders every section heading in order', () => {
    render(<MomentumMethodology data={DATA} />);
    const h2s = screen.getAllByRole('heading', { level: 2 }).map((h) => h.textContent);
    expect(h2s).toEqual(METHODOLOGY_SECTIONS.map((s) => s.title));
  });

  it('opens the everything-tried table on the primary target', () => {
    render(<MomentumMethodology data={DATA} />);
    const expected = DATA.single_feature_results.filter((r) => r.target === PRIMARY).length;
    expect(triedRows()).toHaveLength(expected);
    expect(screen.getByLabelText('What it tries to predict')).toHaveValue(PRIMARY);
  });

  it('shows every row of single_feature_results when all targets are selected', async () => {
    const user = userEvent.setup();
    render(<MomentumMethodology data={DATA} />);
    await user.selectOptions(screen.getByLabelText('What it tries to predict'), 'All targets');
    expect(triedRows()).toHaveLength(DATA.single_feature_results.length);
    expect(screen.getByTestId('tried-count')).toHaveTextContent(
      `Showing ${DATA.single_feature_results.length} of ${DATA.single_feature_results.length} rows`,
    );
  });

  it('filters by verdict, inconclusive and discarded rows alike', async () => {
    const user = userEvent.setup();
    render(<MomentumMethodology data={DATA} />);
    for (const v of ['inconclusive', 'discarded'] as const) {
      await user.selectOptions(screen.getByLabelText('Verdict'), v);
      const n = DATA.single_feature_results.filter((r) => r.target === PRIMARY && r.verdict === v).length;
      expect(screen.queryAllByTestId('tried-row')).toHaveLength(n);
    }
  });

  it('has one card per measure', () => {
    render(<MomentumMethodology data={DATA} />);
    expect(screen.getAllByTestId('measure-card')).toHaveLength(DATA.measures.length);
    for (const m of DATA.measures) expect(screen.getAllByText(m.name).length).toBeGreaterThan(0);
  });

  it('links back to the board and names the source commit', () => {
    render(<MomentumMethodology data={DATA} />);
    expect(screen.getByRole('link', { name: /Back to the Momentum Board/ })).toHaveAttribute('href', '/momentum');
    expect(document.body.textContent).toContain(DATA.source_commit);
  });
});
