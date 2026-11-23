/**
 * #82: the e2e route table must cover every page under app/.
 *
 * Every Playwright spec (smoke, a11y, layout, mobile) iterates ROUTES, so a
 * page missing from it gets no browser coverage at all while the suite stays
 * green. That happened to /passing, /dna and /clutch. These checks read app/
 * from disk and fail when the table and the pages disagree.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { MOVED_ROUTES, ROUTE_PATHS } from '../e2e/routes';
import { appRoutes, servedRoutes } from '../helpers/app-routes';

describe('e2e route coverage (#82)', () => {
  it('finds the app routes on disk', () => {
    expect(appRoutes()).toContain('/');
    expect(appRoutes().length).toBeGreaterThan(5);
  });

  it('every page under app/ is in the e2e route table or is a forwarding stub', () => {
    const missing = servedRoutes().filter((r) => !ROUTE_PATHS.includes(r));
    expect(missing, 'add these to ROUTES in tests/e2e/routes.ts').toEqual([]);
  });

  it('every e2e route and stub has a page under app/', () => {
    const onDisk = appRoutes();
    const listed = [...ROUTE_PATHS, ...MOVED_ROUTES.flatMap(([from, to]) => [from, to])];
    expect(listed.filter((r) => !onDisk.includes(r)), 'listed but no app/<route>/page.tsx').toEqual([]);
  });

  it('every forwarding stub is a RedirectStub page', () => {
    for (const [from] of MOVED_ROUTES) {
      const src = readFileSync(path.resolve(import.meta.dirname, '..', '..', 'app', from.slice(1), 'page.tsx'), 'utf8');
      expect(src, `${from} is listed as moved but renders a real page`).toContain('RedirectStub');
    }
  });

  it('no real page is a RedirectStub missing from MOVED_ROUTES', () => {
    for (const r of servedRoutes()) {
      const file = path.resolve(import.meta.dirname, '..', '..', 'app', r === '/' ? '' : r.slice(1), 'page.tsx');
      expect(readFileSync(file, 'utf8'), `${r} is a forwarding stub; add it to MOVED_ROUTES`).not.toContain('RedirectStub');
    }
  });
});
