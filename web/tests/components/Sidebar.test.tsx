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
});
