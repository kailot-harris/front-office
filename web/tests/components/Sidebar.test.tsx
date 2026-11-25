import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent, within } from '@testing-library/react';
import { Sidebar } from '@/components/Sidebar';

let mockPathname = '/';

vi.mock('next/navigation', () => ({
  usePathname: () => mockPathname,
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), prefetch: vi.fn(), back: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
}));

describe('Sidebar grouped navigation (#230)', () => {
  beforeEach(() => {
    mockPathname = '/';
    window.localStorage.clear();
  });

  it('renders the 5 collapsible group buttons in order and opens only the active group in regular season', () => {
    const { container } = render(<Sidebar seasonState="regular" />);
    const aside = container.querySelector('aside')!;
    const groupButtons = within(aside).getAllByRole('button').filter((b) => b.hasAttribute('aria-expanded'));
    const labels = groupButtons.map((b) => b.textContent?.trim());

    expect(labels).toEqual([
      'Season & Games',
      'Player',
      'Front Office',
      'Visualizations',
      'Models',
    ]);

    expect(within(aside).getByRole('button', { name: /Season & Games/i })).toHaveAttribute('aria-expanded', 'true');
    expect(within(aside).getByRole('button', { name: /Player/i })).toHaveAttribute('aria-expanded', 'false');
    expect(within(aside).getByRole('button', { name: /Front Office/i })).toHaveAttribute('aria-expanded', 'false');
    expect(within(aside).getByRole('button', { name: /Visualizations/i })).toHaveAttribute('aria-expanded', 'false');
    expect(within(aside).getByRole('button', { name: /Models/i })).toHaveAttribute('aria-expanded', 'false');

    const activeLink = within(aside).getByRole('link', { name: /Season Standings/i });
    expect(activeLink).toHaveAttribute('aria-current', 'page');
  });

  it('keeps the active group open on non-home routes and cannot collapse it', () => {
    mockPathname = '/players/';
    const { container } = render(<Sidebar seasonState="regular" />);
    const aside = container.querySelector('aside')!;

    const playerBtn = within(aside).getByRole('button', { name: /Player/i });
    expect(playerBtn).toHaveAttribute('aria-expanded', 'true');
    expect(within(aside).getByRole('link', { name: /Player Ratings & Projections/i })).toHaveAttribute('aria-current', 'page');
    expect(within(aside).getByRole('button', { name: /Season & Games/i })).toHaveAttribute('aria-expanded', 'false');

    // Clicking the active group heading keeps it open
    fireEvent.click(playerBtn);
    expect(playerBtn).toHaveAttribute('aria-expanded', 'true');
  });

  it('toggles non-active groups and persists open state in localStorage across mounts', () => {
    const { container, unmount } = render(<Sidebar seasonState="regular" />);
    const aside = container.querySelector('aside')!;

    const modelsBtn = within(aside).getByRole('button', { name: /Models/i });
    expect(modelsBtn).toHaveAttribute('aria-expanded', 'false');
    expect(within(aside).queryByRole('link', { name: /Diagnostics/i })).not.toBeInTheDocument();

    fireEvent.click(modelsBtn);
    expect(modelsBtn).toHaveAttribute('aria-expanded', 'true');
    expect(within(aside).getByRole('link', { name: /Diagnostics/i })).toBeInTheDocument();

    unmount();

    // Remount on a different route; Models should remain open from localStorage
    mockPathname = '/players';
    const { container: container2 } = render(<Sidebar seasonState="regular" />);
    const aside2 = container2.querySelector('aside')!;
    expect(within(aside2).getByRole('button', { name: /Models/i })).toHaveAttribute('aria-expanded', 'true');
    expect(within(aside2).getByRole('link', { name: /Diagnostics/i })).toBeInTheDocument();
    expect(within(aside2).getByRole('button', { name: /Player/i })).toHaveAttribute('aria-expanded', 'true');
  });

  it('promotes Front Office to the top and opens it by default in offseason', () => {
    const { container } = render(<Sidebar seasonState="offseason" />);
    const aside = container.querySelector('aside')!;
    const groupButtons = within(aside).getAllByRole('button').filter((b) => b.hasAttribute('aria-expanded'));
    expect(groupButtons.map((b) => b.textContent?.trim())).toEqual([
      'Front Office',
      'Season & Games',
      'Player',
      'Visualizations',
      'Models',
    ]);

    expect(within(aside).getByRole('button', { name: /Front Office/i })).toHaveAttribute('aria-expanded', 'true');
    expect(within(aside).getByRole('link', { name: /Offseason Moves/i })).toBeInTheDocument();
    expect(within(aside).getByRole('button', { name: /Season & Games/i })).toHaveAttribute('aria-expanded', 'true');
  });

  it('renders identical collapsible groups in the mobile drawer', () => {
    render(<Sidebar seasonState="regular" />);
    fireEvent.click(screen.getByLabelText(/toggle navigation menu/i));
    const drawer = screen.getByRole('dialog');

    const groupButtons = within(drawer).getAllByRole('button').filter((b) => b.hasAttribute('aria-expanded'));
    expect(groupButtons.map((b) => b.textContent?.trim())).toEqual([
      'Season & Games',
      'Player',
      'Front Office',
      'Visualizations',
      'Models',
    ]);
    expect(within(drawer).getByRole('link', { name: /Season Standings/i })).toHaveAttribute('aria-current', 'page');

    fireEvent.click(within(drawer).getByRole('button', { name: /Visualizations/i }));
    expect(within(drawer).getByRole('button', { name: /Visualizations/i })).toHaveAttribute('aria-expanded', 'true');
    expect(within(drawer).getByRole('link', { name: /Shot Charts/i })).toBeInTheDocument();
  });
});
