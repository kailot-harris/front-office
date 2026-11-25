/**
 * /momentum/methodology (#226): the everything-tried table renders every study
 * row, the page fits a 375 px phone without sideways page scroll, and the
 * Momentum Board links to it under the site's basePath.
 */
import fs from 'node:fs';
import path from 'node:path';
import { expect, test } from '@playwright/test';

const DATA = JSON.parse(
  fs.readFileSync(path.join(process.cwd(), 'public', 'data', 'momentum_methodology.json'), 'utf8'),
) as { momentum_measures: { single_feature_results: unknown[] } };

test('the everything-tried table shows every study row when all targets are selected', async ({ page }) => {
  await page.goto('/momentum/methodology', { waitUntil: 'networkidle' });
  await page.getByLabel('What it tries to predict').selectOption({ label: 'All targets' });
  await expect(page.getByTestId('tried-row')).toHaveCount(DATA.momentum_measures.single_feature_results.length);
});

test('the Momentum Board links to the methodology page', async ({ page }) => {
  await page.goto('/momentum', { waitUntil: 'networkidle' });
  const link = page.getByRole('link', { name: 'Full methodology and everything we tested' });
  await expect(link).toBeVisible();
  await link.click();
  await expect(page).toHaveURL(/\/momentum\/methodology\/?$/);
  await expect(page.locator('h1')).toContainText('Momentum Board methodology');
});

test.describe('at 375 px', () => {
  test.use({ viewport: { width: 375, height: 812 } });

  test('the page does not scroll sideways; wide tables scroll inside their own region', async ({ page }) => {
    await page.goto('/momentum/methodology', { waitUntil: 'networkidle' });
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    expect(overflow).toBeLessThanOrEqual(2);
    await expect(page.getByRole('region', { name: 'Every momentum method tried' })).toBeVisible();
  });
});
