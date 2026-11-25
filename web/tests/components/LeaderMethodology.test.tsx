/**
 * /players/leaders/methodology component unit test (NBA_analytics#258),
 * against the real web/public/data/leader_methodology.json.
 */
import React from 'react';
import fs from 'fs';
import path from 'path';
import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { LeaderMethodology } from '@/components/LeaderMethodology';
import type { LeaderMethodologyPayload } from '@/lib/leaderMethodologyTypes';

const DATA: LeaderMethodologyPayload = JSON.parse(
  fs.readFileSync(path.join(process.cwd(), 'public', 'data', 'leader_methodology.json'), 'utf8'),
);

describe('LeaderMethodology', () => {
  it('renders all 4 reliability charts and all 21 minimum rows', () => {
    render(<LeaderMethodology data={DATA} />);
    expect(screen.getByRole('heading', { name: /League Leaders Methodology/ })).toBeInTheDocument();
    for (const group of ['counting', 'shooting', 'rates', 'rapm']) {
      expect(screen.getByTestId(`leader-chart-${group}`)).toBeInTheDocument();
    }
    for (const m of DATA.minimums) {
      expect(screen.getByTestId(`minimum-row-${m.key}`)).toBeInTheDocument();
    }
  });

  it('toggles between Split-half r and Spearman-Brown curves', async () => {
    render(<LeaderMethodology data={DATA} />);
    const sbBtn = screen.getByRole('button', { name: /Spearman-Brown/ });
    await userEvent.click(sbBtn);
    expect(sbBtn).toHaveAttribute('aria-pressed', 'true');
  });

  it('states the owner chose the minimums and shows source provenance', () => {
    render(<LeaderMethodology data={DATA} />);
    expect(screen.getByText(/owner chose each minimum/i)).toBeInTheDocument();
    expect(screen.getByText(DATA.source_commit)).toBeInTheDocument();
  });
});
