import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
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
    const playersLink = screen.getByRole('link', { name: /Player Projections/i });
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

  it('renders and highlights pinned /offseason-monitor tab', () => {
    mockPathname = '/offseason-monitor/';
    render(<Sidebar />);
    const monitorLink = screen.getByRole('link', { name: /2026-2027 Off-Season Monitor/i });
    expect(monitorLink.className).toContain('bg-accent-600');
    expect(monitorLink.className).toContain('text-white');
    expect(screen.getByText('Weekly Pulse')).toBeDefined();
  });

  it('renders 2026 Championship Archive expandable section', () => {
    mockPathname = '/offseason-monitor';
    render(<Sidebar />);
    expect(screen.getByText(/2026 Championship Archive/i)).toBeDefined();
    // Archive items are contained
    expect(screen.getByRole('link', { name: /CBA Cap Sheet/i })).toBeDefined();
  });
});
