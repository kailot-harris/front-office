import { afterEach, describe, expect, it, vi } from 'vitest';
import { act, render, screen, fireEvent } from '@testing-library/react';

vi.mock('next/navigation', () => ({ usePathname: () => '/shots/' }));

import {
  SportSwitcher,
  SwitchArrivalNote,
  resolveSwitch,
  switchHref,
  type SwitcherTable,
} from '@/components/SportSwitcher';

const TABLE: SwitcherTable = {
  sports: {
    nfl: { label: 'NFL', pages: { '/': 'Season Standings', '/passing': 'Passing Charts', '/teams': 'Team Ratings & EPA', '/players': 'Player Ratings & Projections' } },
    nba: { label: 'NBA', pages: { '/': 'Season Standings', '/shots': 'Shot Charts', '/defense': 'Defense', '/players': 'Player Ratings & Projections', '/coaches': 'Coaching Staffs' } },
    wnba: { label: 'WNBA', pages: { '/': 'Season Standings', '/shots': 'Shot Charts' } },
    mlb: { label: 'MLB', pages: { '/': 'Season Standings', '/spatial': 'Spatial Analytics' } },
  },
  related: {
    'Shot Charts': { nfl: 'Passing Charts', mlb: 'Spatial Analytics' },
    Defense: { nfl: 'Team Ratings & EPA' },
  },
};

afterEach(() => vi.unstubAllGlobals());

describe('resolveSwitch (#212)', () => {
  it('keeps the same address when the target has it', () => {
    expect(resolveSwitch(TABLE, 'nba', 'wnba', '/shots/')).toEqual({ path: '/shots' });
    expect(resolveSwitch(TABLE, 'nba', 'nfl', '/players')).toEqual({ path: '/players' });
  });
  it('uses the related page with a note', () => {
    expect(resolveSwitch(TABLE, 'nba', 'nfl', '/shots')).toEqual({ path: '/passing', note: ['Shot Charts', 'Passing Charts'] });
    expect(resolveSwitch(TABLE, 'nba', 'nfl', '/defense')).toEqual({ path: '/teams', note: ['Defense', 'Team Ratings & EPA'] });
  });
  it('falls back to Season Standings with a note', () => {
    expect(resolveSwitch(TABLE, 'nba', 'mlb', '/coaches')).toEqual({ path: '/', note: ['Coaching Staffs', 'Season Standings'] });
  });
  it('without a table, keeps common pages and sends the rest to standings', () => {
    expect(resolveSwitch(null, 'nba', 'nfl', '/players/')).toEqual({ path: '/players' });
    expect(resolveSwitch(null, 'nba', 'nfl', '/shots/')).toEqual({ path: '/' });
  });
  it('builds hrefs with trailing slash and the note query', () => {
    expect(switchHref('nfl', { path: '/players' })).toBe('/nfl/players/');
    expect(switchHref('nfl', { path: '/passing', note: ['Shot Charts', 'Passing Charts'] }))
      .toBe('/nfl/passing/?from=Shot+Charts&to=Passing+Charts');
  });
});

describe('SportSwitcher', () => {
  it('renders NFL, NBA, WNBA, MLB in order with the current sport marked (#131)', () => {
    vi.stubGlobal('fetch', vi.fn(() => new Promise(() => {})));
    render(<SportSwitcher current="nba" />);
    const nav = screen.getByRole('navigation', { name: 'Switch sport' });
    const links = nav.querySelectorAll('a');
    expect([...links].map((l) => l.textContent?.trim())).toEqual(['NFL', 'NBA', 'WNBA', 'MLB']);
    expect(links[1].getAttribute('aria-current')).toBe('page');
    // table not loaded yet: /shots is not common, so other sports get standings
    expect(links[0].getAttribute('href')).toBe('/nfl/');
  });
  it('uses the table once it loads', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => ({ ok: true, json: async () => TABLE })));
    render(<SportSwitcher current="nba" />);
    await act(async () => {});
    const nfl = screen.getByRole('link', { name: 'NFL' });
    expect(nfl.getAttribute('href')).toBe('/nfl/passing/?from=Shot+Charts&to=Passing+Charts');
    expect(screen.getByRole('link', { name: 'WNBA' }).getAttribute('href')).toBe('/wnba/shots/');
  });
  it('falls back when the table fails to load', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => { throw new Error('offline'); }));
    render(<SportSwitcher current="nba" />);
    await act(async () => {});
    expect(screen.getByRole('link', { name: 'NFL' }).getAttribute('href')).toBe('/nfl/');
  });
});

describe('SwitchArrivalNote', () => {
  it('shows the note from the query, strips it, and dismisses', async () => {
    window.history.replaceState(null, '', '/nba/passing/?from=Shot+Charts&to=Passing+Charts');
    render(<SwitchArrivalNote current="nfl" />);
    await act(async () => {});
    expect(screen.getByRole('status').textContent).toContain('No Shot Charts in NFL — showing Passing Charts.');
    expect(window.location.search).toBe('');
    fireEvent.click(screen.getByRole('button', { name: 'Dismiss' }));
    expect(screen.queryByRole('status')).toBeNull();
  });
  it('renders nothing without the query', () => {
    window.history.replaceState(null, '', '/nba/');
    const { container } = render(<SwitchArrivalNote current="nba" />);
    expect(container.innerHTML).toBe('');
  });
});
