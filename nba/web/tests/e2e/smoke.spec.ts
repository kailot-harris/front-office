/**
 * Route smoke tests — every page loads, renders its own data, and logs nothing.
 */
import { expect, test } from '@playwright/test';
import { ROUTES, ROUTE_PATHS, isRealConsoleError } from './routes';

for (const route of ROUTES) {
  test.describe(`${route.path}`, () => {
    test('responds 200 and renders its heading, title and data', async ({ page }) => {
      const response = await page.goto(route.path, { waitUntil: 'domcontentloaded' });
      expect(response?.status(), `${route.path} did not return 200`).toBe(200);

      const expectedTitlePattern = new RegExp(`${route.title}|NBA Season(-Long)? Projections`, 'i');
      await expect(page).toHaveTitle(expectedTitlePattern);

      const h1 = page.locator('h1').first();
      await expect(h1, `${route.path} has no <h1>`).toBeVisible();
      await expect(h1).toContainText(new RegExp(route.heading.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i'));

      await page.waitForLoadState('networkidle');
      const text = (await page.locator('body').textContent()) ?? '';
      for (const marker of route.dataMarkers) {
        expect(text, `${route.path} is missing "${marker}" — its dataset did not render`).toContain(marker);
      }
    });

    test('logs no console errors and makes no failed same-origin requests', async ({ page }) => {
      const consoleErrors: string[] = [];
      const failedRequests: string[] = [];

      page.on('console', (msg) => {
        if (msg.type() === 'error' && isRealConsoleError(msg.text())) consoleErrors.push(msg.text());
      });
      page.on('pageerror', (err) => consoleErrors.push(`pageerror: ${err.message}`));
      page.on('requestfailed', (req) => {
        // Exclude external ESPN CDN logo request failures if offline
        if (new URL(req.url()).origin === new URL(page.url() || 'http://x').origin) {
          failedRequests.push(`${req.method()} ${req.url()} — ${req.failure()?.errorText}`);
        }
      });
      page.on('response', (res) => {
        if (res.status() >= 400 && new URL(res.url()).origin === new URL(page.url() || 'http://x').origin) {
          failedRequests.push(`${res.status()} ${res.url()}`);
        }
      });

      await page.goto(route.path, { waitUntil: 'networkidle' });

      expect(consoleErrors, `${route.path} logged console errors`).toEqual([]);
      expect(failedRequests, `${route.path} had failed same-origin requests`).toEqual([]);
    });

    test('renders no placeholder text where a value should be', async ({ page }) => {
      await page.goto(route.path, { waitUntil: 'networkidle' });
      const body = (await page.locator('body').innerText()).replace(/\s+/g, ' ');

      for (const bad of ['NaN', 'undefined', 'Infinity', '[object Object]']) {
        expect(body, `${route.path} renders "${bad}" to the user`).not.toContain(bad);
      }
      expect(body, `${route.path} renders a bare "null"`).not.toMatch(/\bnull\b/);
    });

    test('has no horizontally overflowing content', async ({ page }) => {
      await page.goto(route.path, { waitUntil: 'networkidle' });
      const overflow = await page.evaluate(() => {
        const docWidth = document.documentElement.clientWidth;
        const insideScroller = (el: Element): boolean => {
          for (let node: Element | null = el.parentElement; node; node = node.parentElement) {
            const overflowX = getComputedStyle(node).overflowX;
            if (overflowX === 'auto' || overflowX === 'scroll') return true;
          }
          return false;
        };
        return Array.from(document.querySelectorAll('*'))
          .filter((el) => {
            const r = el.getBoundingClientRect();
            return r.width > 0 && r.right > docWidth + 2 && !insideScroller(el);
          })
          .slice(0, 5)
          .map((el) => `${el.tagName.toLowerCase()}.${String(el.className).split(' ')[0]}`);
      });
      expect(
        overflow,
        `${route.path} has content overflowing the viewport that the user cannot scroll to`
      ).toEqual([]);
    });
  });
}

test.describe('Redirects and navigation', () => {
  test('/teams redirects to /?tab=table', async ({ page }) => {
    await page.goto('/teams');
    await page.waitForURL('**/?tab=table');
    expect(page.url()).toContain('/?tab=table');
  });
});
