import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen, fireEvent, within } from '@testing-library/react';
import React from 'react';
import { Sidebar } from '../../components/Sidebar';

let mockPathname = '/';

vi.mock('next/navigation', () => ({
  usePathname: () => mockPathname,
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), prefetch: vi.fn(), back: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
}));

beforeEach(() => {
  window.localStorage.clear();
  mockPathname = '/';
});

describe('Sidebar active tab highlighting', () => {
  it('highlights the home tab with aria-current="page" when on root /', () => {
    mockPathname = '/';
    render(<Sidebar />);
    const link = screen.getByRole('link', { name: /Season Standings/i });
    expect(link.getAttribute('aria-current')).toBe('page');
    expect(link.className).toContain('bg-accent-600');
    expect(link.className).toContain('text-white');
  });

  it('highlights /matchups nav link when usePathname returns /matchups/ with trailing slash', () => {
    mockPathname = '/matchups/';
    render(<Sidebar />);
    const matchupsLink = screen.getByRole('link', { name: /Matchups/i });
    expect(matchupsLink.getAttribute('aria-current')).toBe('page');
    expect(matchupsLink.className).toContain('bg-accent-600');
    expect(matchupsLink.className).toContain('text-white');

    const homeLink = screen.getByRole('link', { name: /Season Standings/i });
    expect(homeLink.hasAttribute('aria-current')).toBe(false);
    expect(homeLink.className).not.toContain('bg-accent-600');
  });

  it('auto-opens Player group and highlights /players when usePathname returns /players/', () => {
    mockPathname = '/players/';
    const { container } = render(<Sidebar />);
    const aside = container.querySelector('aside')!;
    const playerBtn = within(aside).getByRole('button', { name: 'Player' });
    expect(playerBtn.getAttribute('aria-expanded')).toBe('true');

    const playersLink = within(aside).getByRole('link', { name: /Player Ratings & Projections/i });
    expect(playersLink.getAttribute('aria-current')).toBe('page');
    expect(playersLink.className).toContain('bg-accent-600');
  });

  it('highlights home tab when pathname is /teams or /teams/', () => {
    mockPathname = '/teams/';
    render(<Sidebar />);
    const homeLink = screen.getByRole('link', { name: /Season Standings/i });
    expect(homeLink.getAttribute('aria-current')).toBe('page');
    expect(homeLink.className).toContain('bg-accent-600');
  });

  it('auto-opens Front Office group and highlights /offseason tab', () => {
    mockPathname = '/offseason/';
    const { container } = render(<Sidebar />);
    const aside = container.querySelector('aside')!;
    const foBtn = within(aside).getByRole('button', { name: 'Front Office' });
    expect(foBtn.getAttribute('aria-expanded')).toBe('true');

    const monitorLink = within(aside).getByRole('link', { name: /Offseason Moves/i });
    expect(monitorLink.getAttribute('aria-current')).toBe('page');
    expect(monitorLink.className).toContain('bg-accent-600');
    expect(within(aside).getByText('Weekly Pulse')).toBeDefined();
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

describe('Sidebar grouped collapsible sections (#230)', () => {
  const groupButtonLabels = (root: HTMLElement) =>
    Array.from(root.querySelectorAll('nav[aria-label="Primary navigation"] > div > button')).map(
      (btn) => btn.textContent?.trim(),
    );

  it('renders the 5 collapsible groups in NAV_GROUPS order during season', () => {
    mockPathname = '/';
    const { container } = render(<Sidebar seasonState="regular" />);
    const aside = container.querySelector('aside')!;
    expect(groupButtonLabels(aside)).toEqual([
      'Season & Games',
      'Player',
      'Front Office',
      'Visualizations',
      'Models',
    ]);
    expect(within(aside).getByRole('button', { name: 'Season & Games' }).getAttribute('aria-expanded')).toBe('true');
    expect(within(aside).getByRole('button', { name: 'Player' }).getAttribute('aria-expanded')).toBe('false');
    expect(within(aside).getByRole('button', { name: 'Front Office' }).getAttribute('aria-expanded')).toBe('false');
  });

  it('promotes Front Office to first and open by default in offseason', () => {
    mockPathname = '/offseason/';
    const { container } = render(<Sidebar seasonState="offseason" />);
    const aside = container.querySelector('aside')!;
    expect(groupButtonLabels(aside)).toEqual([
      'Front Office',
      'Season & Games',
      'Player',
      'Visualizations',
      'Models',
    ]);
    expect(within(aside).getByRole('button', { name: 'Front Office' }).getAttribute('aria-expanded')).toBe('true');
    expect(within(aside).getByRole('button', { name: 'Season & Games' }).getAttribute('aria-expanded')).toBe('false');
  });

  it('renders the same 5 collapsible groups in the mobile drawer', () => {
    mockPathname = '/diagnostics/';
    render(<Sidebar />);
    fireEvent.click(screen.getByLabelText('Toggle navigation menu'));
    const drawer = screen.getByRole('dialog');
    expect(groupButtonLabels(drawer)).toEqual([
      'Season & Games',
      'Player',
      'Front Office',
      'Visualizations',
      'Models',
    ]);
    expect(within(drawer).getByRole('button', { name: 'Models' }).getAttribute('aria-expanded')).toBe('true');
  });

  it('keeps the active group open even if clicked', () => {
    mockPathname = '/shots/';
    const { container } = render(<Sidebar />);
    const aside = container.querySelector('aside')!;
    const vizBtn = within(aside).getByRole('button', { name: 'Visualizations' });
    expect(vizBtn.getAttribute('aria-expanded')).toBe('true');
    fireEvent.click(vizBtn);
    expect(vizBtn.getAttribute('aria-expanded')).toBe('true');
    expect(within(aside).getByRole('link', { name: /Shot Charts/i })).toBeDefined();
  });

  it('toggles non-active groups and persists open state in localStorage across mounts', () => {
    mockPathname = '/';
    const { container, unmount } = render(<Sidebar />);
    const aside = container.querySelector('aside')!;
    const modelsBtn = within(aside).getByRole('button', { name: 'Models' });
    expect(modelsBtn.getAttribute('aria-expanded')).toBe('false');

    fireEvent.click(modelsBtn);
    expect(modelsBtn.getAttribute('aria-expanded')).toBe('true');
    expect(within(aside).getByRole('link', { name: /Diagnostics/i })).toBeDefined();

    unmount();

    mockPathname = '/matchups/';
    const second = render(<Sidebar />);
    const secondAside = second.container.querySelector('aside')!;
    expect(
      within(secondAside).getByRole('button', { name: 'Models' }).getAttribute('aria-expanded'),
    ).toBe('true');
  });

  it('handles unavailable localStorage without throwing', () => {
    const getSpy = vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('SecurityError');
    });
    const setSpy = vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('SecurityError');
    });
    try {
      mockPathname = '/';
      const { container } = render(<Sidebar />);
      const aside = container.querySelector('aside')!;
      const playerBtn = within(aside).getByRole('button', { name: 'Player' });
      fireEvent.click(playerBtn);
      expect(playerBtn.getAttribute('aria-expanded')).toBe('true');
    } finally {
      getSpy.mockRestore();
      setSpy.mockRestore();
    }
  });
});
