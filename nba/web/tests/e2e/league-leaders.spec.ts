/**
 * League leaders panel on /players (NBA_analytics#254), on the static export.
 * Cards grouped, top 3 expanding to top 10, the position filter, a through date
 * and noise notes per card, "Not enough games yet" for empty cards, and no link
 * to the methodology page (that page is built later, in #258).
 */
import fs from 'fs';
import path from 'path';
import { expect, test } from '@playwright/test';

const DATA = JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'public', 'data', 'player_leaders.json'), 'utf8'));

test.describe('league leaders panel', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/players', { waitUntil: 'networkidle' });
  });

  test('sits at the top of /players with every group and card', async ({ page }) => {
    const panel = page.getByTestId('league-leaders');
    await expect(panel).toBeVisible();
    await expect(panel.getByRole('heading', { name: /League Leaders/ })).toBeVisible();
    for (const g of DATA.groups) await expect(page.getByTestId(`leader-group-${g.key}`)).toBeVisible();
    await expect(page.locator('[data-testid^="leader-card-"]')).toHaveCount(DATA.cards.length);
  });

  test('top 3 expands to top 10, and the position filter applies to every card', async ({ page }) => {
    const pts = page.getByTestId('leader-card-pts');
    await expect(pts.getByTestId('leader-row')).toHaveCount(3);
    await pts.getByRole('button', { name: /Show top 10/ }).click();
    await expect(pts.getByTestId('leader-row')).toHaveCount(10);
    await page.getByTestId('leader-filter-C').click();
    const reb = DATA.cards.find((c: { key: string }) => c.key === 'reb');
    await expect(page.getByTestId('leader-card-reb').getByTestId('leader-row').first()).toContainText(reb.leaders.C[0].player);
  });

  test('through dates, noise notes and empty cards', async ({ page }) => {
    for (const c of DATA.cards) {
      const el = page.getByTestId(`leader-card-${c.key}`);
      await expect(el.getByTestId('leader-through')).toBeVisible();
      await expect(el.getByTestId('leader-noise-note')).toHaveCount(c.noise_note ? 1 : 0);
      if (c.status === 'not_enough_games') await expect(el.getByTestId('leader-empty')).toContainText('Not enough games yet');
    }
  });

  test('links from the methods note to the methodology page', async ({ page }) => {
    const methods = page.getByTestId('leader-methods');
    await methods.locator('summary').click();
    const link = methods.getByRole('link', { name: /Full methodology/ });
    await expect(link).toBeVisible();
    await link.click();
    await expect(page).toHaveURL(/\/players\/leaders\/methodology\/?$/);
    await expect(page.locator('h1')).toContainText('League Leaders Methodology');
  });
});
