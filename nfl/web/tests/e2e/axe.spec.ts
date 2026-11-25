/**
 * WCAG 2.2 AA audit with axe-core, against the production static export.
 *
 * Every top-level route is checked in both color schemes, because light and dark
 * follow prefers-color-scheme and each has its own contrast pairs. The run fails
 * on any serious or critical violation (front-office a11y standard, NFL issue 7).
 */
import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

/** Every app/<route>/page.tsx, plus home. Kept explicit so a new route is a visible diff. */
export const AXE_ROUTES = [
  '/',
  '/matchups',
  '/momentum',
  '/momentum/methodology',
  '/teams',
  '/coaches',
  '/cap-sheet',
  '/playoffs',
  '/players',
  '/variants',
  '/diagnostics',
  '/gallery',
  '/clutch',
  '/player-dna',
  '/passing',
];

const WCAG_TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'];

for (const colorScheme of ['light', 'dark'] as const) {
  test.describe(`axe (${colorScheme})`, () => {
    test.use({ colorScheme });

    for (const route of AXE_ROUTES) {
      test(`${route} has no serious or critical violations`, async ({ page }) => {
        // The methodology page renders every study table (hundreds of rows); axe needs longer there.
        if (route === '/momentum/methodology') test.slow();
        await page.goto(route, { waitUntil: 'networkidle' });
        const results = await new AxeBuilder({ page }).withTags(WCAG_TAGS).analyze();
        const blocking = results.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
        const summary = blocking.map(
          (v) => `${v.impact} ${v.id} (${v.nodes.length}): ${v.nodes.slice(0, 3).map((n) => n.target.join(' ')).join(' | ')}`,
        );
        expect(summary, `${route} in ${colorScheme} mode`).toEqual([]);
      });
    }
  });
}
