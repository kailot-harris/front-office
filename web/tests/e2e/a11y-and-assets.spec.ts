/**
 * Accessibility baseline and asset integrity, checked in a real browser.
 *
 * Deliberately a hand-rolled baseline rather than a full axe-core audit: these
 * are the rules this specific app can actually violate given how it is built
 * (every page is a data table plus logo images plus unlabelled icon buttons).
 */
import { expect, test } from '@playwright/test';
import { ROUTES } from './routes';

test.describe('accessibility baseline', () => {
  for (const route of ROUTES) {
    test.describe(route.path, () => {
      test('declares a language and a unique page title', async ({ page }) => {
        await page.goto(route.path, { waitUntil: 'domcontentloaded' });
        expect(await page.locator('html').getAttribute('lang')).toBe('en');
        expect((await page.title()).length, 'page title is too short to be useful').toBeGreaterThan(10);
      });

      test('has exactly one <h1>', async ({ page }) => {
        await page.goto(route.path, { waitUntil: 'domcontentloaded' });
        expect(await page.locator('h1').count(), `${route.path} should have exactly one <h1>`).toBe(1);
      });

      test('does not skip a heading level', async ({ page }) => {
        await page.goto(route.path, { waitUntil: 'networkidle' });
        const levels = await page.locator('h1,h2,h3,h4,h5,h6').evaluateAll((els) =>
          els.map((el) => Number(el.tagName.slice(1))),
        );
        const skips: string[] = [];
        for (let i = 1; i < levels.length; i++) {
          if (levels[i] - levels[i - 1] > 1) skips.push(`h${levels[i - 1]} -> h${levels[i]} at index ${i}`);
        }
        expect(skips, `${route.path} skips heading levels`).toEqual([]);
      });

      test('exposes a main landmark', async ({ page }) => {
        await page.goto(route.path, { waitUntil: 'domcontentloaded' });
        expect(await page.locator('main').count()).toBeGreaterThan(0);
      });

      test('every image has alt text', async ({ page }) => {
        await page.goto(route.path, { waitUntil: 'networkidle' });
        const missing = await page.locator('img').evaluateAll((imgs) =>
          imgs
            .filter((img) => !(img as HTMLImageElement).alt?.trim())
            .map((img) => (img as HTMLImageElement).currentSrc || (img as HTMLImageElement).src)
            .slice(0, 5),
        );
        expect(missing, `${route.path} has images with no alt text`).toEqual([]);
      });

      test('every form control has an accessible name', async ({ page }) => {
        await page.goto(route.path, { waitUntil: 'networkidle' });
        const unlabelled = await page.locator('input, select, textarea').evaluateAll((els) =>
          els
            .filter((el) => {
              const e = el as HTMLInputElement;
              if (e.type === 'hidden') return false;
              const hasLabel =
                e.getAttribute('aria-label') ||
                e.getAttribute('aria-labelledby') ||
                e.getAttribute('placeholder') ||
                e.getAttribute('title') ||
                (e.id && document.querySelector(`label[for="${e.id}"]`)) ||
                e.closest('label');
              return !hasLabel;
            })
            .map((el) => `${el.tagName.toLowerCase()}[type=${(el as HTMLInputElement).type ?? '?'}]`)
            .slice(0, 5),
        );
        expect(unlabelled, `${route.path} has form controls with no accessible name`).toEqual([]);
      });

      test('every button has an accessible name', async ({ page }) => {
        await page.goto(route.path, { waitUntil: 'networkidle' });
        const unnamed = await page.locator('button').evaluateAll((els) =>
          els
            .filter((el) => {
              const text = (el.textContent ?? '').trim();
              return (
                !text &&
                !el.getAttribute('aria-label') &&
                !el.getAttribute('aria-labelledby') &&
                !el.getAttribute('title')
              );
            })
            .map((el) => (el.outerHTML.slice(0, 90)))
            .slice(0, 5),
        );
        expect(
          unnamed,
          `${route.path} has icon-only buttons with no aria-label — a screen reader announces them as "button"`,
        ).toEqual([]);
      });

      test('is keyboard reachable: tabbing moves focus into the page', async ({ page }) => {
        await page.goto(route.path, { waitUntil: 'networkidle' });
        await page.keyboard.press('Tab');
        const tag = await page.evaluate(() => document.activeElement?.tagName.toLowerCase() ?? 'body');
        expect(tag, `${route.path}: the first Tab did not reach a focusable element`).not.toBe('body');
      });

      test('data tables have header cells', async ({ page }) => {
        await page.goto(route.path, { waitUntil: 'networkidle' });
        const tablesWithoutHeaders = await page.locator('table').evaluateAll((tables) =>
          tables.filter((t) => t.querySelectorAll('th').length === 0).length,
        );
        expect(tablesWithoutHeaders, `${route.path} has a <table> with no <th>`).toBe(0);
      });
    });
  }
});

test.describe('asset integrity in the browser', () => {
  for (const route of ROUTES) {
    test(`${route.path} loads every image it renders`, async ({ page }) => {
      await page.goto(route.path, { waitUntil: 'networkidle' });
      // Give lazy-loaded logos a chance to resolve.
      await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
      await page.waitForTimeout(1200);
      await page.evaluate(() => window.scrollTo(0, 0));
      await page.waitForTimeout(300);

      const broken = await page.locator('img').evaluateAll((imgs) =>
        imgs
          .filter((el) => {
            const img = el as HTMLImageElement;
            // naturalWidth === 0 after completion means the fetch failed.
            return img.complete && img.naturalWidth === 0;
          })
          .map((el) => (el as HTMLImageElement).src)
          .slice(0, 8),
      );
      expect(broken, `${route.path} renders broken images`).toEqual([]);
    });
  }

  test('gallery media files all resolve over HTTP', async ({ page, request }) => {
    await page.goto('/gallery', { waitUntil: 'networkidle' });
    const srcs = [
      ...new Set(
        await page.locator('img').evaluateAll((imgs) =>
          imgs.map((i) => (i as HTMLImageElement).getAttribute('src') ?? '').filter(Boolean),
        ),
      ),
    ];
    expect(srcs.length, 'gallery rendered no images').toBeGreaterThan(0);

    const failures: string[] = [];
    for (const src of srcs) {
      const url = src.startsWith('http') ? src : new URL(src, page.url()).toString();
      // Skip next/image optimiser URLs pointed at remote hosts.
      if (url.includes('/_next/image') && url.includes('http')) continue;
      const res = await request.get(url);
      if (!res.ok()) failures.push(`${res.status()} ${url}`);
    }
    expect(failures, 'gallery assets failed to load').toEqual([]);
  });
});

test.describe('responsive layout', () => {
  // The mobile drawer has its own spec (tests/e2e/mobile.spec.ts) so it runs
  // under the mobile project with a real mobile user agent and touch support.
  for (const size of [
    { name: 'mobile', width: 390, height: 844 },
    { name: 'tablet', width: 820, height: 1180 },
    { name: 'desktop', width: 1680, height: 1050 },
  ]) {
    test(`every route renders at ${size.name} without clipping the body`, async ({ page }) => {
      await page.setViewportSize({ width: size.width, height: size.height });
      for (const route of ROUTES) {
        await page.goto(route.path, { waitUntil: 'domcontentloaded' });
        const scrollWidth = await page.evaluate(() => document.documentElement.scrollWidth);
        expect(
          scrollWidth,
          `${route.path} at ${size.name} scrolls horizontally (${scrollWidth}px > ${size.width}px)`,
        ).toBeLessThanOrEqual(size.width + 2);
      }
    });
  }
});

test.describe('document metadata', () => {
  test('every route has a unique title and a meta description', async ({ page }) => {
    const titles = new Map<string, string>();
    for (const route of ROUTES) {
      await page.goto(route.path, { waitUntil: 'domcontentloaded' });
      const title = await page.title();
      const description = await page.locator('meta[name="description"]').getAttribute('content');
      expect(description?.length ?? 0, `${route.path} has no meta description`).toBeGreaterThan(20);
      for (const [otherPath, otherTitle] of titles) {
        expect(title, `${route.path} and ${otherPath} share the title "${title}"`).not.toBe(otherTitle);
      }
      titles.set(route.path, title);
    }
  });
});
