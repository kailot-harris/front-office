import { test, expect } from '@playwright/test';
import { MOVED_ROUTES, linkHref } from './routes';

/** #211: every renamed page keeps its old address as a forwarding stub. */
const MOVED = MOVED_ROUTES;

for (const [from, to] of MOVED) {
  test(`${from} forwards to ${to}`, async ({ page }) => {
    await page.goto(linkHref(from) + '?q=1');
    await page.waitForURL((url) => url.pathname.startsWith(linkHref(to)));
    expect(new URL(page.url()).search).toBe('?q=1');
  });
}
