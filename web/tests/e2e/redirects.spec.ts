import { test, expect } from '@playwright/test';

const BASE = `${process.env.PAGES_BASE_PATH ?? ''}/wnba`;

/** #211: every renamed page keeps its old address as a forwarding stub. */
const MOVED: Array<[string, string]> = [
  ['/series', '/playoffs'],
  ['/offseason-monitor', '/offseason'],
];

for (const [from, to] of MOVED) {
  test(`${from} forwards to ${to}`, async ({ page }) => {
    await page.goto(`${BASE}${from}/?q=1`);
    await page.waitForURL((url) => url.pathname.endsWith(`${to}/`));
    expect(new URL(page.url()).search).toBe('?q=1');
  });
}
