import { test, expect } from '@playwright/test';

/** #211: every renamed page keeps its old address as a forwarding stub. */
const MOVED: Array<[string, string]> = [['/series', '/playoffs']];

for (const [from, to] of MOVED) {
  test(`${from} forwards to ${to}`, async ({ page }) => {
    await page.goto(`${from}/?q=1`);
    await page.waitForURL((url) => url.pathname.includes(`${to}/`));
    expect(new URL(page.url()).search).toBe('?q=1');
  });
}
