/**
 * /players/leaders/methodology (NBA_analytics#258), on the static export:
 * all 4 group curves render SVGs, all 21 minimums rows render, and the page
 * fits a 375 px phone without horizontal page scroll.
 */
import fs from 'node:fs';
import path from 'node:path';
import { expect, test } from '@playwright/test';

const DATA = JSON.parse(
  fs.readFileSync(path.join(process.cwd(), 'public', 'data', 'leader_methodology.json'), 'utf8'),
) as { minimums: { key: string }[] };

test('renders all four reliability charts and every minimum row', async ({ page }) => {
  await page.goto('/players/leaders/methodology', { waitUntil: 'networkidle' });
  await expect(page.locator('h1')).toContainText('League Leaders Methodology');
  for (const group of ['counting', 'shooting', 'rates', 'rapm']) {
    const chart = page.getByTestId(`leader-chart-${group}`);
    await expect(chart).toBeVisible();
    await expect(chart.locator('svg path').first()).toBeVisible();
  }
  await expect(page.locator('[data-testid^="minimum-row-"]')).toHaveCount(DATA.minimums.length);
});

test.describe('at 375 px', () => {
  test.use({ viewport: { width: 375, height: 812 } });

  test('the page does not scroll sideways', async ({ page }) => {
    await page.goto('/players/leaders/methodology', { waitUntil: 'networkidle' });
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    expect(overflow).toBeLessThanOrEqual(2);
  });
});
