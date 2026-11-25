import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { afterEach, describe, expect, it, vi } from 'vitest';

let mockPathname = '/';
vi.mock('next/navigation', () => ({ usePathname: () => mockPathname }));

let forceOpen = false;
vi.mock('react', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react')>();
  const useState = ((init: unknown) =>
    forceOpen && init === false ? [true, () => {}] : actual.useState(init)) as typeof actual.useState;
  return { ...actual, default: { ...actual, useState }, useState };
});

const {
  NAV_ITEMS,
  Sidebar,
  readStoredOpenGroups,
  writeStoredOpenGroups,
} = await import('@/components/Sidebar');

const renderSidebar = (pathname: string, seasonState?: string, openMobile = false) => {
  mockPathname = pathname;
  forceOpen = openMobile;
  try {
    return renderToStaticMarkup(createElement(Sidebar, { seasonState }));
  } finally {
    forceOpen = false;
  }
};

const extractGroupButtons = (sectionHtml: string) => {
  const matches = [
    ...sectionHtml.matchAll(
      /<button[^>]*aria-expanded="(true|false)"[^>]*aria-controls="[^"]*-nav-group-([^"]+)"[^>]*><span>([^<]+)<\/span>/g,
    ),
  ];
  return matches.map((m) => ({
    expanded: m[1] === 'true',
    id: m[2],
    label: m[3],
  }));
};

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('Sidebar collapsible groups (front-office #230)', () => {
  it('keeps flat NAV_ITEMS array intact for nav sync checks', () => {
    expect(Array.isArray(NAV_ITEMS)).toBe(true);
    expect(NAV_ITEMS.length).toBe(14);
    expect(NAV_ITEMS.every((i) => typeof i.href === 'string' && typeof i.label === 'string')).toBe(true);
  });

  it('renders all 5 collapsible group buttons identically in desktop and mobile', () => {
    const html = renderSidebar('/', 'regular', true);
    const dialog = html.slice(html.indexOf('role="dialog"'), html.indexOf('<aside'));
    const aside = html.slice(html.indexOf('<aside'));

    const mobileGroups = extractGroupButtons(dialog);
    const desktopGroups = extractGroupButtons(aside);

    expect(desktopGroups).toEqual([
      { id: 'season-games', label: 'Season &amp; Games', expanded: true },
      { id: 'player', label: 'Player', expanded: false },
      { id: 'front-office', label: 'Front Office', expanded: false },
      { id: 'visualizations', label: 'Visualizations', expanded: false },
      { id: 'models', label: 'Models', expanded: false },
    ]);
    expect(mobileGroups).toEqual(desktopGroups);
  });

  it('always opens the group containing the active pathname and sets aria-current="page"', () => {
    const html = renderSidebar('/variants/', 'regular');
    const aside = html.slice(html.indexOf('<aside'));
    const groups = extractGroupButtons(aside);

    expect(groups.find((g) => g.id === 'models')?.expanded).toBe(true);
    expect(groups.find((g) => g.id === 'season-games')?.expanded).toBe(false);

    const activeLink = aside.slice(aside.indexOf('<nav aria-label="Primary"')).match(/<a[^>]*aria-current="page"[^>]*>/);
    expect(activeLink).not.toBeNull();
    expect(activeLink?.[0]).toContain('href="/variants"');
  });

  it('treats /teams as active in Season & Games', () => {
    const html = renderSidebar('/teams', 'regular');
    const aside = html.slice(html.indexOf('<aside'));
    const groups = extractGroupButtons(aside);
    expect(groups.find((g) => g.id === 'season-games')?.expanded).toBe(true);
    const activeLink = aside.slice(aside.indexOf('<nav aria-label="Primary"')).match(/<a[^>]*aria-current="page"[^>]*>/);
    expect(activeLink?.[0]).toContain('href="/"');
  });

  it('promotes Front Office to top with defaultOpen=true in offseason while keeping active group open', () => {
    const html = renderSidebar('/players', 'offseason');
    const aside = html.slice(html.indexOf('<aside'));
    const groups = extractGroupButtons(aside);

    expect(groups.map((g) => g.id)).toEqual([
      'front-office',
      'season-games',
      'player',
      'visualizations',
      'models',
    ]);
    expect(groups[0].expanded).toBe(true);
    expect(groups[1].expanded).toBe(false);
    expect(groups[2].expanded).toBe(true);
    expect(groups[3].expanded).toBe(false);
    expect(groups[4].expanded).toBe(false);
  });

  it('safely handles SSR and unavailable or corrupted localStorage', () => {
    // Node environment has no window by default (SSR).
    expect(readStoredOpenGroups()).toEqual({});
    expect(() => writeStoredOpenGroups({ models: true })).not.toThrow();

    const store = new Map<string, string>();
    vi.stubGlobal('window', {
      localStorage: {
        getItem: (k: string) => store.get(k) ?? null,
        setItem: (k: string, v: string) => {
          store.set(k, v);
        },
      },
    });

    writeStoredOpenGroups({ player: true, models: false });
    expect(readStoredOpenGroups()).toEqual({ player: true, models: false });

    store.set('fo-mlb-sidebar-groups', '{bad json');
    expect(readStoredOpenGroups()).toEqual({});

    vi.stubGlobal('window', {
      get localStorage() {
        throw new Error('SecurityError');
      },
    });
    expect(readStoredOpenGroups()).toEqual({});
    expect(() => writeStoredOpenGroups({ player: true })).not.toThrow();
  });
});
