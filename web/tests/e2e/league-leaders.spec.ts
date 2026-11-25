/**
 * League leaders panel on /players (NFL_analytics#230), on the static export.
 * Panel at the top of the page, cards grouped, top 3 expanding to top 10, a
 * through date and noise notes per card, "Not enough games yet" for empty
 * cards, and no link to a methodology page.
 */
import fs from 'fs';
import path from 'path';
import { expect, test } from '@playwright/test';

interface Card { key: string; status: string; noise_note: boolean; leaders: { player: string }[] }
const DATA = JSON.parse(
  fs.readFileSync(path.join(__dirname, '..', '..', 'public', 'data', 'player_leaders.json'), 'utf8'),
) as { groups: { key: string }[]; cards: Card[] };
const big = DATA.cards.find((c) => c.leaders.length === 10) as Card;

test.describe('league leaders panel', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/players', { waitUntil: 'networkidle' });
  });

  test('sits at the top of /players with every group and card', async ({ page }) => {
    const panel = page.getByTestId('league-leaders');
    await expect(panel).toBeVisible();
    await expect(panel.getByRole('heading', { name: /League Leaders/ })).toBeVisible();
    const panelTop = (await panel.boundingBox())!.y;
    const h1Top = (await page.locator('h1').first().boundingBox())!.y;
    expect(panelTop).toBeLessThan(h1Top);
    for (const g of DATA.groups) await expect(page.getByTestId(`leader-group-${g.key}`)).toBeVisible();
    await expect(page.locator('[data-testid^="leader-card-"]')).toHaveCount(DATA.cards.length);
  });

  test('top 3 expands to top 10', async ({ page }) => {
    const el = page.getByTestId(`leader-card-${big.key}`);
    await expect(el.getByTestId('leader-row')).toHaveCount(3);
    await el.getByRole('button', { name: 'Show top 10' }).click();
    await expect(el.getByTestId('leader-row')).toHaveCount(10);
    await expect(el.getByTestId('leader-row').first()).toContainText(big.leaders[0].player);
  });

  test('through dates, noise notes and empty cards', async ({ page }) => {
    for (const c of DATA.cards) {
      const el = page.getByTestId(`leader-card-${c.key}`);
      await expect(el.getByTestId('leader-through')).toBeVisible();
      await expect(el.getByTestId('leader-noise-note')).toHaveCount(c.noise_note ? 1 : 0);
      if (c.status === 'not_enough_games') await expect(el.getByTestId('leader-empty')).toContainText('Not enough games yet');
    }
  });

  test('no link to a methodology page', async ({ page }) => {
    await expect(page.getByTestId('league-leaders').locator('a')).toHaveCount(0);
    await expect(page.locator('a[href*="methodology"]')).toHaveCount(0);
  });
});
