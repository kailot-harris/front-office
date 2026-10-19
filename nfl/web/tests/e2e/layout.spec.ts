/**
 * Layout regression tests for the app shell.
 *
 * `app/layout.tsx` lays the body out as `flex md:flex-row` with <Sidebar />
 * as the first child, which reads as though the sidebar occupies a column.
 * It does not: at `lg:` and up the sidebar is `position: fixed; left: 0;
 * width: 16rem; z-index: 30`, so it is taken out of flow and the content
 * column is never offset by its width.
 *
 * These tests assert the invariant that actually matters to a visitor: no
 * interactive control may sit underneath the fixed sidebar, because clicking
 * it activates the sidebar link on top instead of the control the user aimed
 * at.
 */
import { expect, test } from '@playwright/test';
import { ROUTES } from './routes';

/** Viewport widths at or above the sidebar's `lg:` breakpoint. */
const DESKTOP_WIDTHS = [1024, 1280, 1366, 1440, 1600, 1920];

test.describe('the fixed sidebar must not overlap page content', () => {
  for (const width of DESKTOP_WIDTHS) {
    test(`content clears the sidebar at ${width}px`, async ({ page }) => {
      await page.setViewportSize({ width, height: 900 });
      const overlaps: string[] = [];

      for (const route of ROUTES) {
        await page.goto(route.path, { waitUntil: 'networkidle' });
        const result = await page.evaluate(() => {
          const aside = document.querySelector('aside');
          if (!aside) return null;
          const asideBox = aside.getBoundingClientRect();
          if (asideBox.width === 0) return null; // collapsed below lg:
          const content = document.querySelector('main > div');
          if (!content) return null;
          return {
            sidebarRight: Math.round(asideBox.right),
            contentLeft: Math.round(content.getBoundingClientRect().left),
          };
        });
        if (!result) continue;
        if (result.contentLeft < result.sidebarRight) {
          overlaps.push(
            `${route.path}: content starts at ${result.contentLeft}px but the sidebar occupies ` +
              `0-${result.sidebarRight}px (${result.sidebarRight - result.contentLeft}px hidden)`,
          );
        }
      }

      expect(
        overlaps.slice(0, 4),
        `At ${width}px the sidebar covers the left edge of the page content on ${overlaps.length} route(s). ` +
          `app/layout.tsx needs a left offset on the content column (e.g. lg:pl-64) to match the ` +
          `fixed w-64 sidebar, or the sidebar needs to participate in the flex flow.`,
      ).toEqual([]);
    });
  }

  for (const route of ROUTES) {
    test(`${route.path} has no control hidden under the sidebar at 1440px`, async ({ page }) => {
      await page.setViewportSize({ width: 1440, height: 900 });
      await page.goto(route.path, { waitUntil: 'networkidle' });

      const obscured = await page.evaluate(() => {
        const aside = document.querySelector('aside');
        if (!aside || aside.getBoundingClientRect().width === 0) return [];
        const hidden: string[] = [];
        const controls = document.querySelectorAll('main button, main a, main input, main select, main th');
        for (const el of Array.from(controls)) {
          const box = el.getBoundingClientRect();
          if (box.width === 0 || box.height === 0) continue;
          if (box.top < 0 || box.top > window.innerHeight) continue;
          const topMost = document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2);
          if (topMost && aside.contains(topMost)) {
            hidden.push(`${el.tagName.toLowerCase()} "${(el.textContent ?? '').trim().slice(0, 40)}"`);
          }
        }
        return hidden;
      });

      expect(
        obscured,
        `${route.path}: these controls are underneath the fixed sidebar at 1440x900, so clicking them ` +
          `activates a sidebar nav link instead`,
      ).toEqual([]);
    });
  }
});

test.describe('the sidebar itself stays usable', () => {
  test('is hidden below the lg breakpoint', async ({ page }) => {
    await page.setViewportSize({ width: 820, height: 1180 });
    await page.goto('/', { waitUntil: 'networkidle' });
    const width = await page.evaluate(() => {
      const aside = document.querySelector('aside');
      return aside ? aside.getBoundingClientRect().width : 0;
    });
    expect(width, 'the desktop sidebar should not occupy space on a tablet viewport').toBe(0);
  });

  test('stays pinned while the page scrolls', async ({ page }) => {
    await page.setViewportSize({ width: 1920, height: 900 });
    await page.goto('/?view=table', { waitUntil: 'networkidle' });
    const before = await page.evaluate(() => document.querySelector('aside')?.getBoundingClientRect().top ?? null);
    await page.evaluate(() => window.scrollTo(0, 800));
    await page.waitForTimeout(200);
    const after = await page.evaluate(() => document.querySelector('aside')?.getBoundingClientRect().top ?? null);
    expect(after).toBe(before);
  });

  test('marks the current route as active', async ({ page }) => {
    await page.setViewportSize({ width: 1920, height: 900 });
    await page.goto('/teams', { waitUntil: 'networkidle' });
    const activeHrefs = await page.locator('aside a').evaluateAll((els) =>
      els
        .filter((el) => /bg-emerald|text-emerald|border-emerald/.test(el.className))
        .map((el) => el.getAttribute('href')),
    );
    expect(activeHrefs, '/teams is not highlighted in the sidebar').toContain('/teams');
  });
});

test.describe('footer', () => {
  test('is present and below the content on every route', async ({ page }) => {
    await page.setViewportSize({ width: 1920, height: 900 });
    for (const route of ROUTES) {
      await page.goto(route.path, { waitUntil: 'domcontentloaded' });
      const footer = page.locator('footer');
      await expect(footer, `${route.path} has no footer`).toHaveCount(1);
      const ok = await page.evaluate(() => {
        const f = document.querySelector('footer')!.getBoundingClientRect();
        const m = document.querySelector('main')!.getBoundingClientRect();
        return f.top >= m.top;
      });
      expect(ok, `${route.path}: the footer is not below the main content`).toBe(true);
    }
  });
});
