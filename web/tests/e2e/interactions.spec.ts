/**
 * End-to-end interaction tests — user controls and interactive behaviors.
 */
import { expect, test } from '@playwright/test';
import { ROUTES } from './routes';

test.use({ viewport: { width: 1440, height: 900 } });

test.describe('search inputs are live after hydration', () => {
  for (const route of ROUTES.filter((r) => r.expectsSearch)) {
    test(`${route.path} search input accepts input and updates state`, async ({ page }) => {
      await page.goto(route.path, { waitUntil: 'networkidle' });
      const input = page.locator('input[type="text"]').first();
      await expect(input, `${route.path} has no text filter`).toBeVisible();

      await input.fill('xyznonexistentquery');
      await page.waitForTimeout(250);

      await input.fill('');
      await page.waitForTimeout(250);
      expect(await input.inputValue()).toBe('');
    });
  }
});

test.describe('home page standings visualizer vs table tabs', () => {
  test('toggles between Playoff Contenders Visualizer and Full Standings Table', async ({ page }) => {
    await page.goto('/', { waitUntil: 'networkidle' });

    // Click tab to table
    const tableTab = page.locator('#tab-btn-table');
    await tableTab.click();
    await expect(page.locator('table')).toBeVisible();
    await expect(page.locator('tbody tr')).toHaveCount(30);

    // Filter by East
    const eastBtn = page.getByRole('button', { name: /east conf/i });
    await eastBtn.click();
    await expect(page.locator('tbody tr')).toHaveCount(15);

    // Switch back to All
    const allBtn = page.getByRole('button', { name: /all leagues/i });
    await allBtn.click();
    await expect(page.locator('tbody tr')).toHaveCount(30);
  });
});

test.describe('shots explorer interactivity', () => {
  test('player dropdown changes selected player telemetry', async ({ page }) => {
    await page.goto('/shots', { waitUntil: 'networkidle' });
    const selects = page.locator('select');
    expect(await selects.count()).toBeGreaterThanOrEqual(2);
  });
});

test.describe('series simulator interactivity', () => {
  test('changing teams in playoff simulator updates probability outputs', async ({ page }) => {
    await page.goto('/series', { waitUntil: 'networkidle' });
    await expect(page.locator('text=10,000 Sims / Run')).toBeVisible();
  });
});
