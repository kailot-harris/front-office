import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';

vi.mock('next/navigation', () => ({ usePathname: () => '/' }));

// Force the phone drawer open: the Sidebar's boolean useState hooks start true.
let forceOpen = false;
vi.mock('react', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react')>();
  const useState = ((init: unknown) =>
    forceOpen && init === false ? [true, () => {}] : actual.useState(init)) as typeof actual.useState;
  return { ...actual, default: { ...actual, useState }, useState };
});

const { Sidebar } = await import('@/components/Sidebar');

const render = (open: boolean, seasonState?: string) => {
  forceOpen = open;
  try {
    return renderToStaticMarkup(createElement(Sidebar, { seasonState }));
  } finally {
    forceOpen = false;
  }
};

const anchors = (html: string) => [...html.matchAll(/<a\b[^>]*>/g)].map((m) => m[0]);

describe('Sidebar home link (front-office #220)', () => {
  it('is the first link, points at /front-office/ and is never aria-current', () => {
    const html = render(false, 'offseason');
    const first = anchors(html)[0];
    expect(first).toContain('href="/front-office/"');
    expect(first).not.toContain('aria-current');
    expect(html).toContain('Front Office home');
    const aside = html.slice(html.indexOf('<aside'));
    expect(anchors(aside)[0]).toContain('href="/front-office/"');
    expect(aside.indexOf('Front Office home')).toBeLessThan(aside.indexOf('ANALYTICS'));
  });

  it('also appears first in the phone drawer', () => {
    const html = render(true, 'offseason');
    const dialog = html.slice(html.indexOf('role="dialog"'));
    expect(anchors(dialog)[0]).toContain('href="/front-office/"');
    expect(html.match(/href="\/front-office\/"/g)).toHaveLength(2);
  });

  it('renders Front Office before Season & Games and Models in the offseason', () => {
    const html = render(false, 'offseason');
    const frontOffice = html.indexOf('Offseason Moves');
    const seasonGames = html.indexOf('Season Standings');
    const models = html.indexOf('Models');
    expect(frontOffice).toBeGreaterThan(-1);
    expect(frontOffice).toBeLessThan(seasonGames);
    expect(seasonGames).toBeLessThan(models);
  });
});
