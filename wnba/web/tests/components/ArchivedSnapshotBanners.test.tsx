import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import React from 'react';
import CapSheetPage from '../../app/cap-sheet/page';
import OffseasonPage from '../../app/offseason/page';
import { CapSheetClient } from '../../components/CapSheetClient';
import type { WnbaCbaLeagueOverview } from '../../lib/cbaTypes';

const capOverviewFixture: WnbaCbaLeagueOverview = {
  generated_at: '2026-11-07T05:55:22Z',
  season: '2026',
  hardSalaryCap: 7,
  capFloor: 5.859,
  supermaxSalary: 1.4,
  vetMaxSalary: 1.19,
  vetMinSalary: 0.3,
  rookieMinSalary: 0.27,
  teams: [
    {
      teamAbbr: 'GS',
      teamName: 'Golden State Valkyries',
      conference: 'West',
      hardSalaryCap: 7,
      capFloor: 5.859,
      rosterCount: 15,
      corePlayer: 'Unassigned',
    },
  ],
};

describe('Archived static snapshot disclosures (#212)', () => {
  it('/cap-sheet renders an explicit Archived Static Snapshot banner with snapshot date and pipeline disclosure', () => {
    render(<CapSheetPage />);

    const banner = screen.getByTestId('archived-static-snapshot-banner');
    expect(banner.getAttribute('role')).toBe('note');
    expect(banner.textContent).toContain('Archived Static Snapshot');
    expect(banner.textContent).toContain('2026-11-07');
    expect(banner.textContent).toContain('cba_cap_sheet.json');
    expect(banner.textContent).toMatch(/No scheduled pipeline stage updates/i);
    expect(screen.getByRole('heading', { name: /CBA Cap Sheet Archived/i })).toBeDefined();
  });

  it('CapSheetClient renders the Archived Static Snapshot banner derived from initialData.generated_at', () => {
    render(<CapSheetClient initialData={capOverviewFixture} />);

    const banner = screen.getByTestId('archived-static-snapshot-banner');
    expect(banner.textContent).toContain('Archived Static Snapshot');
    expect(banner.textContent).toContain('2026-11-07');
    expect(banner.textContent).toContain('cba_cap_sheet.json');
    expect(banner.textContent).toMatch(/No scheduled pipeline stage updates/i);
  });

  it('/offseason renders an explicit Archived Static Snapshot banner disclosing frozen payloads and date', () => {
    render(<OffseasonPage />);

    const banner = screen.getByTestId('archived-static-snapshot-banner');
    expect(banner.getAttribute('role')).toBe('note');
    expect(banner.textContent).toContain('Archived Static Snapshot');
    expect(banner.textContent).toContain('2026-11-07');
    expect(banner.textContent).toContain('offseason_draft.json');
    expect(banner.textContent).toContain('offseason_teams.json');
    expect(banner.textContent).toContain('offseason_transactions.json');
    expect(banner.textContent).toMatch(/No scheduled pipeline stage updates/i);
    expect(screen.getByRole('heading', { name: /Offseason Moves Hub Archived/i })).toBeDefined();
  });
});
