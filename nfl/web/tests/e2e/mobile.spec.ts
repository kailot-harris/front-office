/**
 * Mobile-specific behaviour.
 *
 * Two things make mobile selectors subtle here, and both are encoded below
 * rather than guessed at:
 *
 *  1. Navigation is rendered TWICE — a `lg:`-only <aside> for desktop and a
 *     separate `lg:hidden` slide-in panel for small screens — so an
 *     unqualified `a[href=...]` grabs whichever copy comes first in the DOM.
 *  2. The drawer is hidden with `-translate-x-full`, not `display: none`. It
 *     keeps a non-empty bounding box, so Playwright still reports it as
 *     "visible". Open/closed has to be decided on GEOMETRY: is the panel
 *     inside the viewport or parked off the left edge?
 */
import { devices, expect, test, type Page } from '@playwright/test';
import { ROUTES } from './routes';

test.use({ ...devices['Pixel 7'] });

const toggle = (page: Page) => page.locator('button[class*="fixed"][class*="top-4"]').first();

/** The drawer's own copy of a nav link, identified by its x position. */
async function drawerLinkX(page: Page, href: string): Promise<number | null> {
  return page.evaluate((h) => {
    const links = Array.from(document.querySelectorAll(`a[href="${h}"]`));
    // The drawer copy is the one inside a fixed-position panel that is either
    // parked at a negative x or sitting at the left edge of the viewport.
    // The mobile drawer is an <aside class="lg:hidden fixed ... w-72 ...">,
    // distinct from the desktop <aside class="hidden lg:flex ... w-64 ...">.
    const panelLink = links.find((a) => a.closest('aside[class*="w-72"]'));
    if (!panelLink) return null;
    return Math.round(panelLink.getBoundingClientRect().x);
  }, href);
}

const isDrawerOpen = async (page: Page) => {
  const x = await drawerLinkX(page, '/teams');
  return x !== null && x >= 0;
};

test.describe('mobile navigation drawer', () => {
  test('the drawer is parked off-screen until it is opened', async ({ page }) => {
    await page.goto('/', { waitUntil: 'networkidle' });
    const x = await drawerLinkX(page, '/teams');
    expect(x, 'no drawer nav panel found on a phone viewport').not.toBeNull();
    expect(x!, `the drawer is already on screen at x=${x} before being opened`).toBeLessThan(0);
  });

  test('the hamburger toggle has an accessible name', async ({ page }) => {
    await page.goto('/', { waitUntil: 'networkidle' });
    const name = await toggle(page).evaluate(
      (el) => (el.textContent ?? '').trim() || el.getAttribute('aria-label') || el.getAttribute('title') || '',
    );
    expect(name, 'the mobile menu button is icon-only with no accessible name').not.toBe('');
  });

  test('the hamburger slides the drawer in and reveals every route', async ({ page }) => {
    await page.goto('/', { waitUntil: 'networkidle' });
    await toggle(page).click();
    await page.waitForTimeout(400);

    expect(await isDrawerOpen(page), 'the drawer did not slide into the viewport').toBe(true);

    for (const route of ROUTES) {
      const x = await drawerLinkX(page, route.path);
      expect(x, `${route.path} is not present in the mobile drawer`).not.toBeNull();
      expect(x!, `${route.path} is in the drawer but still off-screen at x=${x}`).toBeGreaterThanOrEqual(0);
    }
  });

  test('tapping a drawer link navigates and closes the drawer', async ({ page }) => {
    await page.goto('/', { waitUntil: 'networkidle' });
    await toggle(page).click();
    await page.waitForTimeout(400);

    await page.locator('aside[class*="w-72"] a[href="/matchups"]').first().click();
    await expect(page.locator('h1').first()).toContainText(/Weekly Matchup/i);
    await page.waitForTimeout(400);
    expect(await isDrawerOpen(page), 'the drawer stayed open over the destination page').toBe(false);
  });

  test('the backdrop closes the drawer', async ({ page }) => {
    await page.goto('/', { waitUntil: 'networkidle' });
    await toggle(page).click();
    await page.waitForTimeout(400);
    expect(await isDrawerOpen(page)).toBe(true);

    // Tap the far right of the screen, clear of the 288px-wide panel.
    await page.mouse.click(390, 620);
    await page.waitForTimeout(400);
    expect(await isDrawerOpen(page), 'tapping the backdrop did not dismiss the drawer').toBe(false);
  });

  test('the toggle is still tappable once the drawer is open', async ({ page }) => {
    // The toggle is `fixed top-4 left-4 z-50` and the drawer panel is
    // `fixed top-0 left-0 w-72 z-50`. Equal z-index means DOM order decides,
    // and the drawer is rendered after the button — so the open drawer paints
    // over its own close control. The X icon is visible but not hittable, and
    // the drawer has no close button of its own, leaving the backdrop as the
    // only way out.
    await page.goto('/', { waitUntil: 'networkidle' });
    await toggle(page).click();
    await page.waitForTimeout(400);

    const covering = await page.evaluate(() => {
      const t = document.querySelector('button[class*="fixed"][class*="top-4"]');
      if (!t) return 'toggle not found';
      const r = t.getBoundingClientRect();
      const top = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
      if (!top || t === top || t.contains(top)) return null;
      const panel = top.closest('aside[class*="w-72"]');
      return panel ? 'the open drawer panel' : `${top.tagName.toLowerCase()}`;
    });
    expect(covering, 'something is painted over the drawer toggle while the drawer is open').toBeNull();
  });

  test('the drawer can be dismissed without reloading the page', async ({ page }) => {
    // Whichever affordance works, the user must have a way back out.
    await page.goto('/', { waitUntil: 'networkidle' });
    await toggle(page).click();
    await page.waitForTimeout(400);
    expect(await isDrawerOpen(page)).toBe(true);

    await page.mouse.click(390, 620); // backdrop
    await page.waitForTimeout(400);
    expect(await isDrawerOpen(page), 'the drawer cannot be dismissed at all').toBe(false);
  });
});

test.describe('every route is usable on a phone', () => {
  for (const route of ROUTES) {
    test(`${route.path} renders its data and does not scroll sideways`, async ({ page }) => {
      await page.goto(route.path, { waitUntil: 'networkidle' });

      // textContent, not innerText: markers may live in subtrees that are
      // hidden at this width, and the question here is whether the data
      // reached the DOM at all. Scoped to <main> because body.textContent also
      // picks up Next's inline RSC payload <script>, which legitimately
      // contains the substrings "undefined" and "NaN".
      const text = (await page.locator('main').textContent()) ?? '';
      for (const marker of route.dataMarkers) {
        expect(text, `${route.path} is missing "${marker}" on mobile`).toContain(marker);
      }
      expect(text).not.toMatch(/NaN|undefined/);

      const { scrollWidth, clientWidth } = await page.evaluate(() => ({
        scrollWidth: document.documentElement.scrollWidth,
        clientWidth: document.documentElement.clientWidth,
      }));
      expect(
        scrollWidth,
        `${route.path} scrolls horizontally on a phone (${scrollWidth}px content in ${clientWidth}px viewport)`,
      ).toBeLessThanOrEqual(clientWidth + 2);
    });
  }

  test('no element is clipped outside the viewport without a scroll container', async ({ page }) => {
    const offenders: string[] = [];
    for (const route of ROUTES) {
      await page.goto(route.path, { waitUntil: 'networkidle' });
      const over = await page.evaluate(() => {
        const docWidth = document.documentElement.clientWidth;
        const insideScroller = (el: Element): boolean => {
          for (let n: Element | null = el.parentElement; n; n = n.parentElement) {
            const o = getComputedStyle(n).overflowX;
            if (o === 'auto' || o === 'scroll') return true;
          }
          return false;
        };
        return Array.from(document.querySelectorAll('main *'))
          .filter((el) => {
            const r = el.getBoundingClientRect();
            return r.width > 0 && r.right > docWidth + 2 && !insideScroller(el);
          })
          .slice(0, 3)
          .map(
            (el) =>
              `${el.tagName.toLowerCase()}.${String(el.className).split(' ')[0]} ` +
              `(right edge ${Math.round(el.getBoundingClientRect().right)}px vs ${docWidth}px viewport)`,
          );
      });
      if (over.length) offenders.push(`${route.path}: ${over.join('; ')}`);
    }
    expect(offenders, 'these elements are clipped off the right edge on a phone').toEqual([]);
  });

  test('tap targets on the busiest page are large enough to hit', async ({ page }) => {
    await page.goto('/matchups', { waitUntil: 'networkidle' });
    // WCAG 2.5.8 (AA) asks for a 24x24 CSS px minimum target size.
    const tooSmall = await page.locator('main button, main a').evaluateAll((els) =>
      els
        .map((el) => ({ el, r: el.getBoundingClientRect() }))
        .filter(({ r }) => r.width > 0 && r.height > 0 && (r.width < 24 || r.height < 24))
        .slice(0, 6)
        .map(
          ({ el, r }) =>
            `"${(el.textContent ?? '').trim().slice(0, 24)}" ${Math.round(r.width)}x${Math.round(r.height)}`,
        ),
    );
    expect(tooSmall, 'tap targets smaller than 24x24 CSS px').toEqual([]);
  });

  test('the primary filter input is reachable and usable', async ({ page }) => {
    await page.goto('/teams', { waitUntil: 'networkidle' });
    const input = page.locator('input[type="text"]').first();
    await expect(input).toBeVisible();
    await input.fill('Chiefs');
    await page.waitForTimeout(250);
    await expect(page.locator('tbody tr')).toHaveCount(1);
  });
});
