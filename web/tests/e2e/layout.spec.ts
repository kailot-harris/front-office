import { test, expect } from '@playwright/test';
import { ROUTES } from './routes';

test.describe('Layout & Viewport Verification', () => {
  const VIEWPORTS = [
    { name: 'desktop-hd', width: 1280, height: 800 },
    { name: 'desktop-fhd', width: 1440, height: 900 },
    { name: 'desktop-4k', width: 1920, height: 1080 },
  ];

  for (const vp of VIEWPORTS) {
    test.describe(`${vp.name} (${vp.width}x${vp.height})`, () => {
      test.use({ viewport: { width: vp.width, height: vp.height } });

      test('sidebar is visible and does not overlap main content on homepage', async ({ page }) => {
        await page.goto('/', { waitUntil: 'domcontentloaded' });

        const sidebar = page.locator('aside');
        await expect(sidebar).toBeVisible();

        const main = page.locator('main');
        await expect(main).toBeVisible();

        const sidebarBox = await sidebar.boundingBox();
        const mainBox = await main.boundingBox();

        expect(sidebarBox).not.toBeNull();
        expect(mainBox).not.toBeNull();

        if (sidebarBox && mainBox) {
          // Verify sidebar is to the left or does not collide horizontally with main content
          // In flex md:flex-row, main.x >= sidebar.x + sidebar.width - 2 (allowing 2px subpixel)
          expect(mainBox.x).toBeGreaterThanOrEqual(sidebarBox.x + sidebarBox.width - 2);
        }
      });

      test('no horizontal scrollbar on core analytical routes', async ({ page }) => {
        const testRoutes = ['/', '/standings', '/players', '/shots', '/cap-sheet'];

        for (const path of testRoutes) {
          await page.goto(path, { waitUntil: 'domcontentloaded' });
          await page.waitForTimeout(300);

          const scrollWidth = await page.evaluate(() => document.documentElement.scrollWidth);
          const clientWidth = await page.evaluate(() => document.documentElement.clientWidth);

          // Allow up to 2px tolerance for subpixel layout rounding
          expect(
            scrollWidth,
            `Expected ${path} scrollWidth (${scrollWidth}) <= clientWidth (${clientWidth})`
          ).toBeLessThanOrEqual(clientWidth + 2);
        }
      });
    });
  }
});
