import { describe, expect, it } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { TeamLogo } from '@/components/TeamLogo';
import { Sidebar } from '@/components/Sidebar';
import { VariantsClient } from '@/components/VariantsClient';
import { DiagnosticsClient } from '@/components/DiagnosticsClient';
import { CapSheetClient } from '@/components/CapSheetClient';
import { ClutchClient } from '@/components/ClutchClient';
import { CoachesClient } from '@/components/CoachesClient';
import { DefenseClient } from '@/components/DefenseClient';
import { PlayerDnaClient } from '@/components/PlayerDnaClient';
import { OffseasonClient } from '@/components/OffseasonClient';
import { NBA_TEAMS_METADATA } from '@/lib/teams';
import { loadAllDatasets } from '../helpers/datasets';

const {
  teams,
  metadata,
  diagnostics,
  cbaCapSheet,
  clutch,
  coaches,
  defense,
  playerDna,
  offseasonDraft,
  offseasonTeams,
  offseasonTransactions,
  players,
} = loadAllDatasets();

describe('TeamLogo component', () => {
  it('renders image logo with alt text for every team', () => {
    for (const abbr of Object.keys(NBA_TEAMS_METADATA)) {
      const { container, unmount } = render(<TeamLogo team={abbr} />);
      const img = container.querySelector('img');
      expect(img).not.toBeNull();
      expect(img!.getAttribute('alt')).toContain(NBA_TEAMS_METADATA[abbr].fullName);
      unmount();
    }
  });

  it('renders fallback badge on image error', () => {
    const { container } = render(<TeamLogo team="BOS" />);
    const img = container.querySelector('img')!;
    fireEvent.error(img);
    expect(container.textContent).toContain('BOS');
  });
});

describe('Sidebar navigation', () => {
  const ROUTES = [
    '/',
    '/offseason',
    '/cap-sheet',
    '/variants',
    '/players',
    '/player-dna',
    '/defense',
    '/clutch',
    '/shots',
    '/coaches',
    '/series',
    '/diagnostics',
  ];

  it('links to all 12 primary routes', () => {
    const { container } = render(<Sidebar />);
    const hrefs = Array.from(container.querySelectorAll('a')).map((a) => a.getAttribute('href'));
    for (const r of ROUTES) {
      expect(hrefs).toContain(r);
    }
  });

  it('toggles margin sigma popover', () => {
    render(<Sidebar />);
    const explainerBtn = screen.getByLabelText(/what does margin sigma mean/i);
    fireEvent.click(explainerBtn);
    expect(screen.getByText(/standard deviation of single-game score differentials/i)).toBeInTheDocument();
  });
});

describe('Page Clients mount on real data', () => {
  it('VariantsClient mounts without error', () => {
    expect(() => render(<VariantsClient teams={teams} metadata={metadata} />)).not.toThrow();
  });

  it('DiagnosticsClient mounts without error', () => {
    expect(() => render(<DiagnosticsClient diagnostics={diagnostics} metadata={metadata} />)).not.toThrow();
  });

  it('CapSheetClient mounts without error', () => {
    expect(() => render(<CapSheetClient initialData={cbaCapSheet} />)).not.toThrow();
  });

  it('ClutchClient mounts without error', () => {
    expect(() => render(<ClutchClient initialProfiles={clutch} />)).not.toThrow();
  });

  it('CoachesClient mounts without error', () => {
    expect(() => render(<CoachesClient initialData={coaches} />)).not.toThrow();
  });

  it('DefenseClient mounts without error', () => {
    expect(() => render(<DefenseClient initialProfiles={defense} />)).not.toThrow();
  });

  it('PlayerDnaClient mounts without error', () => {
    expect(() => render(<PlayerDnaClient initialProfiles={playerDna} />)).not.toThrow();
  });

  it('OffseasonClient mounts without error', () => {
    expect(() =>
      render(
        <OffseasonClient
          transactions={offseasonTransactions}
          teams={offseasonTeams}
          draftProspects={offseasonDraft}
          allPlayers={players}
        />
      )
    ).not.toThrow();
  });
});
