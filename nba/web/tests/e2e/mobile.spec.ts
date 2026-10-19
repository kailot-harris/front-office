import { test, expect } from '@playwright/test';

test.describe('Mobile Viewport & Drawer Navigation', () => {
  test.use({ viewport: { width: 393, height: 851 } }); // Pixel 7 viewport

  test('mobile navigation drawer opens, displays links, and navigates', async ({ page }) => {
    await page.goto('/', { waitUntil: 'domcontentloaded' });

    // Desktop sidebar should be hidden
    const desktopSidebar = page.locator('aside');
    await expect(desktopSidebar).toBeHidden();

    // Mobile header toggle button should be visible
    const menuButton = page.getByRole('button', { name: /toggle navigation menu/i });
    await expect(menuButton).toBeVisible();

    // Open mobile drawer
    await menuButton.click();

    // Drawer links should now be visible
    const standingsLink = page.getByRole('link', { name: /season standings/i }).first();
    await expect(standingsLink).toBeVisible();

    const shotsLink = page.getByRole('link', { name: /shot charts/i }).first();
    await expect(shotsLink).toBeVisible();

    // Navigate to Shot Charts
    await shotsLink.click();
    await expect(page).toHaveURL(/.*\/shots/);

    // Confirm Shots page loaded
    await expect(page.locator('h1')).toContainText(/shot/i);
  });

  test('mobile pages render without horizontal overflow', async ({ page }) => {
    const mobileRoutes = ['/', '/standings', '/players', '/shots', '/cap-sheet'];

    for (const path of mobileRoutes) {
      await page.goto(path, { waitUntil: 'domcontentloaded' });
      await page.waitForTimeout(300);

      const scrollWidth = await page.evaluate(() => document.documentElement.scrollWidth);
      const clientWidth = await page.evaluate(() => document.documentElement.clientWidth);

      expect(
        scrollWidth,
        `Expected mobile ${path} scrollWidth (${scrollWidth}) <= clientWidth (${clientWidth})`
      ).toBeLessThanOrEqual(clientWidth + 2);
    }
  });
});
