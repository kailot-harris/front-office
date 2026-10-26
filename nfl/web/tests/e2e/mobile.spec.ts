/**
 * Mobile-specific behaviour.
 *
 * Two things make mobile selectors subtle here, and both are encoded below
 * rather than guessed at:
 *
 *  1. Navigation is rendered TWICE — a `md:`-only <aside> for desktop and a
 *     separate `md:hidden` drawer overlay for small screens — so an
 *     unqualified `a[href=...]` grabs whichever copy comes first in the DOM.
 *     The drawer copy is the one with no <aside> ancestor.
 *  2. The drawer is CONDITIONALLY RENDERED (`{isOpen && ...}` in Sidebar.tsx),
 *     not parked off-screen with a transform. Closed means absent from the
 *     DOM, so "is it open?" is `does a non-<aside> nav link exist, on screen?`
 *     and not a question about its x offset alone.
 */
import { devices, expect, test, type Page } from '@playwright/test';
import { ROUTES, linkHref } from './routes';

test.use({ ...devices['Pixel 7'] });

const toggle = (page: Page) => page.locator('div[class*="md:hidden"] button').first();

/**
 * The drawer panel. Sidebar.tsx renders the same <NavContent /> in the desktop
 * <aside> and in the drawer, and the home page ALSO links to several routes from
 * its own content cards, so a nav link has to be matched by its panel ancestor
 * and not by "the first one" or "the one outside the <aside>". `max-w-[85vw]` is
 * what makes the panel's class list unique: the desktop aside is `lg:w-72` and a
 * tooltip elsewhere in the sidebar is `w-72 sm:w-80`.
 */
const PANEL = 'div[class*="max-w-[85vw]"]';

/**
 * The x position of the drawer's own copy of a nav link, or null when the drawer
 * is not rendered at all.
 */
async function drawerLinkX(page: Page, path: string): Promise<number | null> {
  return page.evaluate(
    ([h, panel]) => {
      const panelLink = document.querySelector(`${panel} a[href="${h}"]`);
      if (!panelLink) return null;
      return Math.round(panelLink.getBoundingClientRect().x);
    },
    [linkHref(path), PANEL],
  );
}

const isDrawerOpen = async (page: Page) => {
  const x = await drawerLinkX(page, '/teams');
  return x !== null && x >= 0;
};

test.describe('mobile navigation drawer', () => {
  test('is not rendered until the hamburger is tapped', async ({ page }) => {
    await page.goto('/', { waitUntil: 'networkidle' });
    expect(
      await drawerLinkX(page, '/teams'),
      'a drawer nav panel is in the DOM before the hamburger was tapped',
    ).toBeNull();
  });

  test('the hamburger toggle has an accessible name', async ({ page }) => {
    await page.goto('/', { waitUntil: 'networkidle' });
    const name = await toggle(page).evaluate(
      (el) => (el.textContent ?? '').trim() || el.getAttribute('aria-label') || el.getAttribute('title') || '',
    );
    expect(name, 'the mobile menu button is icon-only with no accessible name').not.toBe('');
  });

  test('the hamburger opens the drawer and reveals every route', async ({ page }) => {
    await page.goto('/', { waitUntil: 'networkidle' });
    await toggle(page).click();
    await page.waitForTimeout(400);

    expect(await isDrawerOpen(page), 'the drawer did not open').toBe(true);

    for (const route of ROUTES) {
      const x = await drawerLinkX(page, route.path);
      expect(x, `${route.path} is not present in the mobile drawer`).not.toBeNull();
      expect(x!, `${route.path} is in the drawer but off-screen at x=${x}`).toBeGreaterThanOrEqual(0);
    }
  });

  test('tapping a drawer link navigates and closes the drawer', async ({ page }) => {
    await page.goto('/', { waitUntil: 'networkidle' });
    await toggle(page).click();
    await page.waitForTimeout(400);

    await page.locator(`${PANEL} a[href="${linkHref('/matchups')}"]`).first().click();
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

  test('the drawer has a close control that is actually hittable', async ({ page }) => {
    // The panel renders its own X at `absolute top-3 right-3`, inside the
    // panel and above the backdrop. The hamburger in the page header is NOT
    // the way back out — the overlay is `fixed inset-0 z-50` and covers it —
    // so this X is the only affordance other than the backdrop, and it has to
    // be the element that actually receives the tap at its own centre.
    await page.goto('/', { waitUntil: 'networkidle' });
    await toggle(page).click();
    await page.waitForTimeout(400);
    expect(await isDrawerOpen(page)).toBe(true);

    const close = page.locator(`${PANEL} button`).first();
    await expect(close, 'the open drawer has no close button').toBeVisible();
    await close.click();
    await page.waitForTimeout(400);
    expect(await isDrawerOpen(page), 'the drawer close button did not dismiss the drawer').toBe(false);
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
