/**
 * Route smoke tests — every page loads, renders its own data, and logs nothing.
 *
 * These run against `next start` on a production build, so a failure here is a
 * failure a visitor would see.
 */
import { expect, test } from '@playwright/test';
import {
  BASE_PATH,
  ROUTES,
  ROUTE_HREFS,
  isRealConsoleError,
  isRealRequestFailure,
  linkHref,
} from './routes';

for (const route of ROUTES) {
  test.describe(`${route.path}`, () => {
    test('responds 200 and renders its heading, title and data', async ({ page }) => {
      const response = await page.goto(route.path, { waitUntil: 'domcontentloaded' });
      expect(response?.status(), `${route.path} did not return 200`).toBe(200);

      await expect(page).toHaveTitle(new RegExp(route.title, 'i'));

      const h1 = page.locator('h1').first();
      await expect(h1, `${route.path} has no <h1>`).toBeVisible();
      await expect(h1).toContainText(new RegExp(route.heading.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i'));

      // Assert PRESENCE IN THE DOM, not visibility. Several markers are table
      // headers that are deliberately hidden at narrow widths, so a
      // `toBeVisible()` check would resolve to the hidden copy and fail even
      // though the dataset rendered fine. `textContent` (unlike `innerText`)
      // includes text in hidden subtrees, which is the question being asked
      // here: did the data reach the page at all?
      await page.waitForLoadState('networkidle');
      const text = (await page.locator('body').textContent()) ?? '';
      for (const marker of route.dataMarkers) {
        expect(text, `${route.path} is missing "${marker}" — its dataset did not render`).toContain(marker);
      }
    });

    test('logs no console errors and makes no failed requests', async ({ page }) => {
      const consoleErrors: string[] = [];
      const failedRequests: string[] = [];

      page.on('console', (msg) => {
        if (msg.type() === 'error' && isRealConsoleError(msg.text())) consoleErrors.push(msg.text());
      });
      page.on('pageerror', (err) => consoleErrors.push(`pageerror: ${err.message}`));
      page.on('requestfailed', (req) => {
        const failure = req.failure()?.errorText ?? '';
        if (!isRealRequestFailure(req.url(), failure)) return;
        failedRequests.push(`${req.method()} ${req.url()} — ${failure}`);
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
      // A bare "null" is a real leak; "nullify"/"annull" are not, so require
      // word boundaries.
      expect(body, `${route.path} renders a bare "null"`).not.toMatch(/\bnull\b/);
    });

    test('has no horizontally overflowing content', async ({ page }) => {
      await page.goto(route.path, { waitUntil: 'networkidle' });
      const overflow = await page.evaluate(() => {
        const docWidth = document.documentElement.clientWidth;
        /**
         * Content wider than the viewport is only a bug if the user cannot
         * reach it. Deliberately scrollable rails (the 18-week selector on
         * /matchups, wide data tables) sit inside an `overflow-x: auto`
         * ancestor, so walk up and exclude those.
         */
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
        `${route.path} has content overflowing the viewport that the user cannot scroll to`,
      ).toEqual([]);
    });
  });
}

test.describe('navigation', () => {
  test('the sidebar reaches every route', async ({ page }) => {
    await page.goto('/', { waitUntil: 'networkidle' });
    const hrefs = await page.locator('nav a, aside a').evaluateAll((els) =>
      els.map((el) => el.getAttribute('href')).filter((h): h is string => Boolean(h && h.startsWith('/'))),
    );
    // Compared against the basePath-prefixed, trailing-slashed form, because
    // that is what Next renders into the markup — see linkHref in routes.ts.
    for (const href of ROUTE_HREFS) {
      expect([...new Set(hrefs)], `no navigation link to ${href}`).toContain(href);
    }
  });

  test('every navigation link leads to a working page', async ({ page }) => {
    await page.goto('/', { waitUntil: 'domcontentloaded' });
    // Scoped to links inside this app's basePath. The sidebar also links to the
    // sibling sports (/nba/, /mlb/, /wnba/), which only exist once every sport's
    // export is assembled into the combined Pages site — they are correctly
    // unreachable against this app's own `out/` and are not this suite's to assert.
    const hrefs = [
      ...new Set(
        await page.locator('a').evaluateAll(
          (els, base) =>
            els
              .map((el) => el.getAttribute('href'))
              .filter((h): h is string => Boolean(h && h.startsWith(`${base}/`))),
          BASE_PATH,
        ),
      ),
    ];
    for (const href of hrefs) {
      const res = await page.goto(href, { waitUntil: 'domcontentloaded' });
      expect(res?.status(), `navigation link ${href} is broken`).toBeLessThan(400);
      await expect(page.locator('h1').first(), `${href} rendered no heading`).toBeVisible();
    }
  });

  test('an unknown route renders the not-found page rather than crashing', async ({ page }) => {
    const res = await page.goto('/this-route-does-not-exist', { waitUntil: 'domcontentloaded' });
    expect(res?.status()).toBe(404);
    await expect(page.locator('body')).toBeVisible();
  });

  test('client-side navigation between pages preserves the shell', async ({ page }) => {
    // The nav links live in two places: the desktop <aside> and the mobile
    // drawer. Target whichever copy is actually on screen.
    await page.goto('/', { waitUntil: 'networkidle' });
    const link = (href: string) => page.locator(`a[href="${href}"]:visible`).first();

    if (!(await link(linkHref('/teams')).count())) {
      // Mobile: open the drawer first.
      await page.locator('button:visible').first().click();
      await page.waitForTimeout(300);
    }
    await link(linkHref('/teams')).click();
    await expect(page.locator('h1').first()).toContainText(/Team Ratings/i);
  });
});
