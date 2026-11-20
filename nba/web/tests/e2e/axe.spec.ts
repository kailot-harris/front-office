import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { ROUTE_PATHS } from './routes';

/**
 * WCAG 2.2 AA gate (NBA_analytics#216): every top-level route of the built
 * static export, in both prefers-color-scheme modes, must have no serious or
 * critical axe violations.
 */
const TOP_LEVEL_ROUTES = [...ROUTE_PATHS, '/teams', '/gallery'];
const BLOCKING = new Set(['serious', 'critical']);

for (const colorScheme of ['light', 'dark'] as const) {
  test.describe(`axe (${colorScheme})`, () => {
    test.use({ colorScheme });

    for (const route of TOP_LEVEL_ROUTES) {
      test(`${route} has no serious or critical violations in ${colorScheme} mode`, async ({ page }) => {
        // Large prerendered pages (teams, players) plus a full axe pass need more than the default 45 s.
        test.setTimeout(180_000);
        await page.emulateMedia({ colorScheme, reducedMotion: 'reduce' });
        await page.goto(route, { waitUntil: 'load' });
        await expect(page.locator('main')).toBeVisible();

        const results = await new AxeBuilder({ page })
          .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
          .analyze();
        const blocking = results.violations
          .filter((v) => BLOCKING.has(v.impact ?? ''))
          .map((v) => ({
            id: v.id,
            impact: v.impact,
            nodes: v.nodes.map((n) => `${n.target.join(' ')} :: ${n.failureSummary?.split('\n')[1] ?? ''}`),
            count: v.nodes.length,
          }));
        // Full list kept as an artifact (test-results/axe/) for triage in CI.
        mkdirSync('test-results/axe', { recursive: true });
        const slug = `${colorScheme}${route === '/' ? '-home' : route.replace(/\//g, '-')}`;
        writeFileSync(`test-results/axe/${slug}.json`, JSON.stringify(blocking, null, 2));
        expect(blocking, JSON.stringify(blocking, null, 2)).toEqual([]);
      });
    }
  });
}
