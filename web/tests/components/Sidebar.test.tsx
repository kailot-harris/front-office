import { describe, expect, it, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import React from 'react';
import { Sidebar } from '../../components/Sidebar';

let mockPathname = '/';

vi.mock('next/navigation', () => ({
  usePathname: () => mockPathname,
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), prefetch: vi.fn(), back: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
}));

describe('Sidebar active tab highlighting', () => {
  it('highlights the home tab when on root /', () => {
    mockPathname = '/';
    render(<Sidebar />);
    const link = screen.getByRole('link', { name: /Season Standings/i });
    expect(link.className).toContain('bg-accent-600');
    expect(link.className).toContain('text-white');
  });

  it('highlights the home tab when on root / with trailing slash', () => {
    mockPathname = '/';
    render(<Sidebar />);
    const link = screen.getByRole('link', { name: /Season Standings/i });
    expect(link.className).toContain('bg-accent-600');
    expect(link.className).toContain('text-white');
  });

  it('highlights /matchups nav link when usePathname returns /matchups/ with trailing slash', () => {
    mockPathname = '/matchups/';
    render(<Sidebar />);
    const matchupsLink = screen.getByRole('link', { name: /Matchups/i });
    expect(matchupsLink.className).toContain('bg-accent-600');
    expect(matchupsLink.className).toContain('text-white');

    const homeLink = screen.getByRole('link', { name: /Season Standings/i });
    expect(homeLink.className).not.toContain('bg-accent-600');
  });

  it('highlights /players nav link when usePathname returns /players/ with trailing slash', () => {
    mockPathname = '/players/';
    render(<Sidebar />);
    const playersLink = screen.getByRole('link', { name: /Player Ratings & Projections/i });
    expect(playersLink.className).toContain('bg-accent-600');
    expect(playersLink.className).toContain('text-white');
  });

  it('highlights home tab when pathname is /teams or /teams/', () => {
    mockPathname = '/teams/';
    render(<Sidebar />);
    const homeLink = screen.getByRole('link', { name: /Season Standings/i });
    expect(homeLink.className).toContain('bg-accent-600');
    expect(homeLink.className).toContain('text-white');
  });

  it('renders and highlights pinned /offseason tab', () => {
    mockPathname = '/offseason/';
    render(<Sidebar />);
    const monitorLink = screen.getByRole('link', { name: /Offseason Moves/i });
    expect(monitorLink.className).toContain('bg-accent-600');
    expect(monitorLink.className).toContain('text-white');
    expect(screen.getByText('Weekly Pulse')).toBeDefined();
  });

  it('renders one flat list in the offseason, with no archive or group headers', () => {
    mockPathname = '/offseason';
    const { container } = render(<Sidebar seasonState="offseason" />);
    expect(screen.queryByText(/2026 Championship Archive/i)).toBeNull();
    expect(screen.queryByText(/Off-Season Intelligence/i)).toBeNull();
    const links = container.querySelector('aside')!.querySelectorAll('a');
    // home link + all 15 nav items, every one visible without expanding anything
    expect(links.length).toBe(16);
  });
});

describe('Sidebar Front Office home link (#220)', () => {
  it('is the first link, points at /front-office/ and is never current', () => {
    mockPathname = '/';
    const { container } = render(<Sidebar />);
    const aside = container.querySelector('aside')!;
    const first = aside.querySelector('a')!;
    expect(first.textContent).toContain('Front Office home');
    expect(first.getAttribute('href')).toBe('/front-office/');
    expect(first.hasAttribute('aria-current')).toBe(false);
    expect(first.className).not.toContain('bg-accent-600');
  });

  it('is also first in the phone drawer', () => {
    mockPathname = '/';
    render(<Sidebar />);
    fireEvent.click(screen.getByLabelText('Toggle navigation menu'));
    const drawer = screen.getByRole('dialog');
    const first = drawer.querySelector('a')!;
    expect(first.textContent).toContain('Front Office home');
    expect(first.getAttribute('href')).toBe('/front-office/');
  });
});

describe('Sidebar order (#221)', () => {
  const labels = (container: HTMLElement) =>
    Array.from(container.querySelector('aside')!.querySelectorAll('a'))
      .map((a) => a.querySelector('span.font-semibold')?.textContent)
      .filter(Boolean);

  it('puts offseason pages first in the offseason', () => {
    mockPathname = '/offseason/';
    const { container } = render(<Sidebar seasonState="offseason" />);
    expect(labels(container).slice(0, 2)).toEqual(['Offseason Moves', 'Retrospective']);
  });

  it('uses NAV_ORDER when the season state is missing', () => {
    mockPathname = '/';
    const { container } = render(<Sidebar />);
    expect(labels(container).slice(0, 4)).toEqual([
      'Season Standings', 'Matchups', 'Playoff Simulator', '2026 Bracket',
    ]);
  });
});
