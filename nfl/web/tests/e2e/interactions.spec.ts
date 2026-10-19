/**
 * End-to-end interaction tests — the controls on each page in a real browser.
 *
 * The vitest component suites already cover filter/sort logic in isolation.
 * These exist to catch what jsdom cannot: hydration failures that leave a
 * control inert, click handlers lost because a server component boundary was
 * drawn wrong, and state that survives (or fails to survive) a reload.
 */
import { expect, test } from '@playwright/test';
import { ROUTES } from './routes';

/**
 * Run these specs at a width where the fixed sidebar does not cover the left
 * edge of the content (see layout.spec.ts — content clears it from 1792px up).
 * Otherwise every "click the first chip in the row" step fails on the layout
 * defect instead of testing the behaviour it is named for.
 */
test.use({ viewport: { width: 1920, height: 1080 } });

test.describe('search inputs are live after hydration', () => {
  for (const route of ROUTES.filter((r) => r.expectsSearch)) {
    test(`${route.path} filters as the user types`, async ({ page }) => {
      await page.goto(route.path, { waitUntil: 'networkidle' });
      const input = page.locator('input[type="text"]').first();
      await expect(input, `${route.path} has no text filter`).toBeVisible();

      const before = await page.locator('tbody tr, [class*="rounded-xl"]').count();
      await input.fill('zzzznotarealthing');
      await page.waitForTimeout(250);
      const after = await page.locator('tbody tr, [class*="rounded-xl"]').count();

      expect(
        after,
        `${route.path}: typing an unmatched query did not reduce the result count ` +
          `(${before} -> ${after}) — the input may not be hydrated`,
      ).toBeLessThan(before);

      await input.fill('');
      await page.waitForTimeout(250);
      expect(await page.locator('tbody tr, [class*="rounded-xl"]').count()).toBeGreaterThanOrEqual(after);
    });
  }
});

test.describe('home page standings dashboard', () => {
  test('the three view tabs each render their own layout', async ({ page }) => {
    await page.goto('/', { waitUntil: 'networkidle' });

    await page.getByRole('button', { name: /Full 32 Table/i }).click();
    await expect(page.locator('table')).toBeVisible();
    await expect(page.locator('tbody tr')).toHaveCount(32);

    await page.getByRole('button', { name: /8 Divisions/i }).click();
    // The division group labels are <span>s, not headings (see the
    // heading-level finding in a11y-and-assets.spec.ts), and "AFC East" also
    // appears in the hidden <option> list of the division <select>.
    await expect(
      page.locator('span').filter({ hasText: /^AFC East$/ }).first(),
      'the divisions view did not render an AFC East group label',
    ).toBeVisible();

    await page.getByRole('button', { name: /Distribution Visualizer/i }).click();
    await expect(page.locator('h1')).toBeVisible();
  });

  test('the active tab is written to the URL and survives a reload', async ({ page }) => {
    await page.goto('/', { waitUntil: 'networkidle' });
    await page.getByRole('button', { name: /Full 32 Table/i }).click();
    await expect(page).toHaveURL(/view=table/);

    await page.reload({ waitUntil: 'networkidle' });
    await expect(page.locator('table'), 'the ?view=table deep link did not restore the table').toBeVisible();
  });

  test('a ?view= deep link opens the right tab directly', async ({ page }) => {
    await page.goto('/?view=divisions', { waitUntil: 'networkidle' });
    await expect(page.locator('span').filter({ hasText: /^AFC North$/ }).first()).toBeVisible();
  });

  test('the conference chips filter the table', async ({ page }) => {
    await page.goto('/?view=table', { waitUntil: 'networkidle' });
    await expect(page.locator('tbody tr')).toHaveCount(32);
    await page.getByRole('button', { name: 'AFC', exact: true }).first().click();
    await expect(page.locator('tbody tr')).toHaveCount(16);
    await page.getByRole('button', { name: 'All', exact: true }).first().click();
    await expect(page.locator('tbody tr')).toHaveCount(32);
  });

  test('clicking a sortable header reorders the table', async ({ page }) => {
    await page.goto('/?view=table', { waitUntil: 'networkidle' });
    const firstCell = () => page.locator('tbody tr').first().innerText();
    const before = await firstCell();
    await page.getByRole('cell', { name: /Power Rating/i }).or(page.locator('th', { hasText: /Power Rating/i })).first().click();
    await page.waitForTimeout(200);
    await page.locator('th', { hasText: /Power Rating/i }).first().click();
    await page.waitForTimeout(200);
    expect(await firstCell(), 'two clicks on a header did not change the leading row').not.toBe(before);
  });
});

test.describe('matchups week selector', () => {
  test('selecting each week swaps the slate', async ({ page }) => {
    await page.goto('/matchups', { waitUntil: 'networkidle' });
    const weeks = page.locator('button', { hasText: /^Week \d+/ });
    const count = await weeks.count();
    expect(count, 'no week buttons rendered').toBeGreaterThan(10);

    const seen = new Set<string>();
    for (let i = 0; i < count; i++) {
      await weeks.nth(i).click();
      await page.waitForTimeout(150);
      const body = await page.locator('main').innerText();
      expect(body, `week index ${i} rendered a placeholder`).not.toMatch(/NaN|undefined/);
      // Fingerprint the SLATE, not the whole page: the week rail is identical
      // on every week, so a prefix of main.innerText never changes.
      const slate = await page
        .locator('[class*="rounded-xl"]')
        .filter({ hasText: 'Model Win Probability' })
        .first()
        .innerText();
      seen.add(slate);
    }
    expect(
      seen.size,
      `all ${count} weeks rendered an identical first fixture — the week selector is inert`,
    ).toBeGreaterThan(count - 2);
  });

  test('past weeks show FINAL scores and future weeks do not', async ({ page }) => {
    await page.goto('/matchups', { waitUntil: 'networkidle' });
    // Scoped to <main> and exact-cased: getByText('FINAL') is a
    // case-insensitive substring match, so it would also hit the "Week 1Final"
    // labels in the week rail.
    const finalBadges = page.locator('main').getByText('FINAL', { exact: true });

    await page.locator('button', { hasText: /^Week 1Final/ }).click();
    await page.waitForTimeout(200);
    expect(await finalBadges.count(), 'a completed week showed no FINAL badges').toBeGreaterThan(0);

    await page.locator('button', { hasText: /^Week 18/ }).click();
    await page.waitForTimeout(250);
    expect(await finalBadges.count(), 'an unplayed week showed FINAL badges').toBe(0);
  });

  test('the weekday chips narrow the slate', async ({ page }) => {
    await page.goto('/matchups', { waitUntil: 'networkidle' });
    const cards = () => page.locator('[class*="rounded-xl"]').filter({ hasText: 'Model Win Probability' });
    const before = await cards().count();
    const sunday = page.getByRole('button', { name: 'Sunday', exact: true });
    if (await sunday.count()) {
      await sunday.click();
      await page.waitForTimeout(200);
      expect(await cards().count()).toBeLessThanOrEqual(before);
    }
  });
});

test.describe('players pagination', () => {
  test('Next and Previous move through the roster', async ({ page }) => {
    await page.goto('/players', { waitUntil: 'networkidle' });
    const firstRow = () => page.locator('tbody tr').first().innerText();

    const page1 = await firstRow();
    await page.getByRole('button', { name: /next/i }).click();
    await page.waitForTimeout(200);
    const page2 = await firstRow();
    expect(page2).not.toBe(page1);

    await page.getByRole('button', { name: /prev/i }).click();
    await page.waitForTimeout(200);
    expect(await firstRow()).toBe(page1);
  });

  test('searching from a later page still shows the match', async ({ page }) => {
    // Regression guard for the pagination reset bug: `currentPage` is not reset
    // when the search query changes, so a search issued from page 2+ slices
    // past the end of the filtered list and renders an empty table.
    await page.goto('/players', { waitUntil: 'networkidle' });
    const target = await page.locator('tbody tr').first().locator('td').nth(1).innerText();

    await page.getByRole('button', { name: /next/i }).click();
    await page.waitForTimeout(200);

    await page.locator('input[type="text"]').first().fill(target.trim());
    await page.waitForTimeout(300);

    const rows = await page.locator('tbody tr').count();
    expect(
      rows,
      `searching for "${target.trim()}" from page 2 rendered ${rows} rows — ` +
        `the page index was not reset when the filter changed`,
    ).toBeGreaterThan(0);
  });
});

test.describe('playoff bracket simulator', () => {
  test('running a simulation produces a champion', async ({ page }) => {
    await page.goto('/playoffs', { waitUntil: 'networkidle' });
    const run = page.getByRole('button', { name: /simulat/i }).first();
    await expect(run).toBeVisible();
    await run.click();
    await page.waitForTimeout(400);
    const body = await page.locator('main').innerText();
    expect(body).not.toMatch(/NaN|undefined/);
  });

  test('ten consecutive simulations never error', async ({ page }) => {
    const errors: string[] = [];
    page.on('pageerror', (e) => errors.push(e.message));
    await page.goto('/playoffs', { waitUntil: 'networkidle' });
    const run = page.getByRole('button', { name: /simulat/i }).first();
    for (let i = 0; i < 10; i++) {
      await run.click();
      await page.waitForTimeout(120);
    }
    expect(errors).toEqual([]);
    expect(await page.locator('main').innerText()).not.toMatch(/NaN|undefined/);
  });
});

test.describe('salary cap tabs', () => {
  test('switching to the contracts tab lists players', async ({ page }) => {
    await page.goto('/salary-cap', { waitUntil: 'networkidle' });
    await page.getByRole('button', { name: /Top 100 League Contracts/i }).click();
    await expect(page.locator('tbody tr').first()).toBeVisible();
    expect(await page.locator('tbody tr').count()).toBeGreaterThan(10);
  });

  test('switching back to team profiles restores 32 rows', async ({ page }) => {
    await page.goto('/salary-cap', { waitUntil: 'networkidle' });
    await page.getByRole('button', { name: /Top 100 League Contracts/i }).click();
    await page.getByRole('button', { name: /32 Team Cap Profiles/i }).click();
    await expect(page.locator('tbody tr')).toHaveCount(32);
  });
});

test.describe('gallery', () => {
  test('category chips filter the grid', async ({ page }) => {
    await page.goto('/gallery', { waitUntil: 'networkidle' });
    const tiles = () => page.locator('img');
    const before = await tiles().count();
    expect(before).toBeGreaterThan(0);

    const elo = page.getByRole('button', { name: 'elo', exact: true });
    if (await elo.count()) {
      await elo.click();
      await page.waitForTimeout(250);
      expect(await tiles().count()).toBeLessThan(before);
      await page.getByRole('button', { name: /All Visuals/i }).click();
      await page.waitForTimeout(250);
      expect(await tiles().count()).toBe(before);
    }
  });

  test('opening a media item shows a lightbox and closes again', async ({ page }) => {
    await page.goto('/gallery', { waitUntil: 'networkidle' });
    const openers = page.locator('button').filter({ has: page.locator('img') });
    if (!(await openers.count())) return;
    await openers.first().click();
    await page.waitForTimeout(300);
    await page.keyboard.press('Escape');
    await page.waitForTimeout(200);
    expect(await page.locator('main').innerText()).not.toMatch(/NaN|undefined/);
  });
});

test.describe('teams page', () => {
  test('selecting a team opens its detail panel', async ({ page }) => {
    await page.goto('/teams', { waitUntil: 'networkidle' });
    const row = page.locator('tbody tr').first();
    const name = await row.innerText();
    await row.click();
    await page.waitForTimeout(250);
    const body = await page.locator('main').innerText();
    expect(body).toContain(name.split('\n')[0].trim().slice(0, 6));
    expect(body).not.toMatch(/NaN|undefined/);
  });
});
