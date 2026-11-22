import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

/** Every top-level route in app/. Keep in step with the app directory. */
export const ROUTES = [
  '/',
  '/cap-sheet/',
  '/clutch/',
  '/diagnostics/',
  '/gallery/',
  '/matchups/',
  '/offseason/',
  '/player-dna/',
  '/players/',
  '/postseason/',
  '/retrospective/',
  '/playoffs/',
  '/spatial/',
  '/teams/',
  '/variants/',
];

for (const route of ROUTES) {
  test(`axe: ${route} has no serious or critical violations`, async ({ page }) => {
    const res = await page.goto(route, { waitUntil: 'networkidle' });
    expect(res?.status()).toBe(200);
    const results = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    const blocking = results.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
    const summary = blocking.map((v) => ({
      id: v.id,
      impact: v.impact,
      nodes: v.nodes.slice(0, 5).map((n) => `${n.target.join(' ')} :: ${n.failureSummary?.split('\n').slice(0, 2).join(' ')}`),
      count: v.nodes.length,
    }));
    expect(summary, JSON.stringify(summary, null, 2)).toEqual([]);
  });
}
