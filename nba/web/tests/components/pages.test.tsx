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
  clutchWindow,
  defenseWindow,
  playerDnaWindow,
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

  it('highlights active nav item when pathname has a trailing slash', () => {
    const { container } = render(<Sidebar />);
    const activeLinks = container.querySelectorAll('aside a.bg-accent-600, div.space-y-1 a.bg-accent-600');
    expect(activeLinks.length).toBeGreaterThan(0);
    expect(activeLinks[0].getAttribute('href')).toBe('/');
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
    expect(() => render(<ClutchClient initialProfiles={clutch} seasonWindow={clutchWindow} />)).not.toThrow();
  });

  it('CoachesClient mounts without error', () => {
    expect(() => render(<CoachesClient initialData={coaches} />)).not.toThrow();
  });

  it('DefenseClient mounts without error', () => {
    expect(() => render(<DefenseClient initialProfiles={defense} seasonWindow={defenseWindow} />)).not.toThrow();
  });

  it('PlayerDnaClient mounts without error', () => {
    expect(() => render(<PlayerDnaClient initialProfiles={playerDna} seasonWindow={playerDnaWindow} />)).not.toThrow();
  });

  it('OffseasonClient mounts without error', () => {
    // allPlayers is no longer an initial-render prop (#134) — OffseasonClient fetches
    // the full player projections dataset client-side on demand instead.
    expect(() =>
      render(
        <OffseasonClient
          transactions={offseasonTransactions}
          teams={offseasonTeams}
          draftProspects={offseasonDraft}
        />
      )
    ).not.toThrow();
  });
});

describe('OffseasonClient Static Off-Season Snapshot notice (#193)', () => {
  it('renders the derived transaction end date and updates when a newer date is passed', () => {
    const expectedMaxDate = offseasonTransactions
      .map((t) => t.date)
      .reduce((max, cur) => (cur > max ? cur : max));

    const { rerender } = render(
      <OffseasonClient
        transactions={offseasonTransactions}
        teams={offseasonTeams}
        draftProspects={offseasonDraft}
      />
    );

    const notice = screen.getByTestId('offseason-static-snapshot-notice');
    expect(notice).toHaveTextContent(/Static Off-Season Snapshot/i);
    expect(notice).toHaveTextContent(expectedMaxDate);
    expect(notice).toHaveTextContent(/stops on/i);
    expect(notice).toHaveTextContent(/live in-season moves/i);
    expect(notice).toHaveTextContent(/not automatically refreshed/i);

    const newerDate = '2026-11-18';
    const updatedTransactions = [
      ...offseasonTransactions,
      {
        ...offseasonTransactions[0],
        id: 'tx-test-newer-date',
        date: newerDate,
      },
    ];

    rerender(
      <OffseasonClient
        transactions={updatedTransactions}
        teams={offseasonTeams}
        draftProspects={offseasonDraft}
      />
    );

    const updatedNotice = screen.getByTestId('offseason-static-snapshot-notice');
    expect(updatedNotice).toHaveTextContent(newerDate);
    expect(updatedNotice).not.toHaveTextContent(expectedMaxDate);
  });

  it('renders the Static Off-Season Snapshot notice safely when transactions is empty', () => {
    render(
      <OffseasonClient
        transactions={[]}
        teams={offseasonTeams}
        draftProspects={offseasonDraft}
      />
    );

    const notice = screen.getByTestId('offseason-static-snapshot-notice');
    expect(notice).toHaveTextContent(/Static Off-Season Snapshot/i);
    expect(notice).toHaveTextContent(/live in-season moves/i);
    expect(notice).toHaveTextContent(/not automatically refreshed/i);
    expect(notice.textContent).not.toMatch(/\b(null|undefined)\b/i);
  });
});
