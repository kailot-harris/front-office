import { test, expect } from '@playwright/test';
import { ROUTES } from './routes';

test.describe('A11y Landmarks & Image Assets', () => {
  for (const route of ROUTES) {
    test(`${route.path} has accessible landmarks and valid headers`, async ({ page }) => {
      await page.goto(route.path, { waitUntil: 'domcontentloaded' });

      // Landmark presence
      const main = page.locator('main');
      await expect(main).toBeVisible();

      // Ensure at least one heading level 1 exists on the page
      const h1Count = await page.locator('h1').count();
      expect(
        h1Count,
        `Expected ${route.path} to contain an <h1> heading`
      ).toBeGreaterThanOrEqual(1);

      // Verify all rendered images have alt attributes
      const images = page.locator('img');
      const imgCount = await images.count();
      for (let i = 0; i < Math.min(imgCount, 15); i++) {
        const alt = await images.nth(i).getAttribute('alt');
        expect(
          alt,
          `Image ${i} on ${route.path} is missing an alt attribute`
        ).not.toBeNull();
      }
    });
  }

  test('team logos and external assets resolve without 5xx errors', async ({ page }) => {
    const failedUrls: string[] = [];

    page.on('response', (res) => {
      const url = res.url();
      if ((url.includes('espncdn.com') || url.includes('/shots/')) && res.status() >= 500) {
        failedUrls.push(`${res.status()} ${url}`);
      }
    });

    await page.goto('/standings', { waitUntil: 'networkidle' });
    expect(failedUrls).toEqual([]);
  });
});
