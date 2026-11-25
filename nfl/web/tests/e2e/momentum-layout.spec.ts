/**
 * Momentum Board (#226): the expanded team row stays inside the viewport at a
 * small desktop and a phone width, the page never scrolls sideways (the table
 * scrolls inside its own container), and the sidebar entry opens the board.
 * Ported from the NBA board's layout spec, where the expanded panel was once
 * clipped at ~800 px because it chose its columns from the browser width.
 */
import { expect, test, type Page } from '@playwright/test';
import { linkHref } from './routes';

const SIZES = [
  { name: '800x600', width: 800, height: 600 },
  { name: '375 mobile', width: 375, height: 812 },
];

async function expandFirstRow(page: Page) {
  await page.goto('/momentum', { waitUntil: 'networkidle' });
  const toggle = page.locator('tbody tr[data-team] button[aria-expanded]').first();
  await expect(toggle).toBeVisible();
  await toggle.click();
  const detail = page.getByTestId('momentum-detail');
  await expect(detail).toBeVisible();
  // let the ResizeObserver-driven layout settle
  await page.waitForTimeout(300);
  return detail;
}

for (const size of SIZES) {
  test.describe(`expanded row at ${size.name}`, () => {
    test.use({ viewport: { width: size.width, height: size.height } });

    test('nothing in the expanded row overflows the viewport or the scroll container', async ({ page }) => {
      const detail = await expandFirstRow(page);
      await expect(detail.getByRole('heading', { name: 'Key numbers' })).toBeVisible();

      const result = await page.evaluate(() => {
        const scroll = document.querySelector('[data-testid="momentum-scroll"]') as HTMLElement;
        const detailEl = document.querySelector('[data-testid="momentum-detail"]') as HTMLElement;
        scroll.scrollLeft = 0;
        const box = scroll.getBoundingClientRect();
        const limitRight = Math.min(box.right, document.documentElement.clientWidth);
        const offenders: string[] = [];
        for (const el of [detailEl, ...Array.from(detailEl.querySelectorAll<HTMLElement>('*'))]) {
          const r = el.getBoundingClientRect();
          if (r.width === 0 && r.height === 0) continue;
          if (r.right > limitRight + 1 || r.left < box.left - 1) {
            offenders.push(
              `${el.tagName.toLowerCase()} "${(el.textContent ?? '').trim().slice(0, 30)}" ${Math.round(r.left)}..${Math.round(r.right)} (limit ${Math.round(box.left)}..${Math.round(limitRight)})`,
            );
          }
        }
        const sections = Array.from(detailEl.querySelectorAll('section')).map((s) => {
          const r = s.getBoundingClientRect();
          return { left: r.left, top: r.top, bottom: r.bottom };
        });
        return {
          offenders,
          pageOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
          containerWidth: box.width,
          sections,
        };
      });

      expect(result.offenders, result.offenders.join('\n')).toEqual([]);
      expect(result.pageOverflow).toBeLessThanOrEqual(2);

      // Below the stacking width every section starts at the same left edge.
      if (result.containerWidth < 768) {
        const lefts = new Set(result.sections.map((s) => Math.round(s.left)));
        expect(lefts.size, 'sections should stack into one column').toBe(1);
      }
    });

    test('the table stays horizontally scrollable', async ({ page }) => {
      await expandFirstRow(page);
      const scrolls = await page.evaluate(() => {
        const s = document.querySelector('[data-testid="momentum-scroll"]') as HTMLElement;
        return s.scrollWidth > s.clientWidth;
      });
      // the 52rem table minimum is wider than both of these containers
      expect(scrolls).toBe(true);
    });
  });
}

test('the sidebar entry opens the Momentum Board', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto('/', { waitUntil: 'networkidle' });
  // Sidebar groups are collapsible and a collapsed group renders no links: open them first.
  const collapsed = page.locator('aside nav button[aria-expanded="false"]');
  while ((await collapsed.count()) > 0) await collapsed.first().click();
  const entry = page.locator(`aside a[href="${linkHref('/momentum')}"]`).first();
  await expect(entry).toContainText('Momentum Board');
  await entry.click();
  await expect(page).toHaveURL(/\/momentum\/?$/);
  await expect(page.locator('h1').first()).toHaveText('Momentum Board');
  await expect(page.getByTestId('momentum-not-forecast')).toBeVisible();
});
