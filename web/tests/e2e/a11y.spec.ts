import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

/**
 * WNBA#230: axe-core on every top-level route of the built static export, in
 * both color schemes. Serious and critical violations fail the run; WCAG 2.2
 * AA is the target (axe's wcag2a/2aa/21a/21aa/22aa rule tags).
 */
const ROUTES = [
  '/',
  '/bracket-2026/',
  '/cap-sheet/',
  '/clutch/',
  '/coaches/',
  '/defense/',
  '/diagnostics/',
  '/gallery/',
  '/matchups/',
  '/offseason/',
  '/offseason-monitor/',
  '/player-dna/',
  '/players/',
  '/retrospective/',
  '/series/',
  '/shots/',
  '/teams/',
  '/variants/',
];

const BASE = `${process.env.PAGES_BASE_PATH ?? ''}/wnba`;

for (const colorScheme of ['light', 'dark'] as const) {
  test.describe(`axe (${colorScheme})`, () => {
    test.use({ colorScheme });
    for (const route of ROUTES) {
      test(`${route} has no serious or critical violations`, async ({ page }) => {
        test.setTimeout(180_000);
        await page.goto(`${BASE}${route}`, { waitUntil: 'load' });
        const results = await new AxeBuilder({ page })
          .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
          .analyze();
        const blocking = results.violations.filter(
          (v) => v.impact === 'serious' || v.impact === 'critical',
        );
        const report = blocking.map(
          (v) => `${v.id} (${v.impact}): ${v.nodes.length} node(s) e.g. ${v.nodes[0]?.target.join(' ')}`,
        );
        expect(report, report.join('\n')).toEqual([]);
      });
    }
  });
}
