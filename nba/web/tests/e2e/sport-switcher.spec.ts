import { test, expect, type Page } from '@playwright/test';
import table from './switcher-table.fixture.json';
import { resolveSwitch, switchHref, SPORTS, type SportSlug, type SwitcherTable } from '../../components/SportSwitcher';

// front-office#212. Identical in all four sport repos. The table is served by
// the aggregator, not this app, so it is mocked (fixture = a copy of the
// aggregator's nav/switcher.json). Sport links are checked by href, since the
// other sports are not served here.
const T = table as SwitcherTable;
const ROUTE = '**/nav/switcher.json';
const nav = (page: Page) => page.locator('aside').getByRole('navigation', { name: 'Switch sport' });
const link = (page: Page, label: string) => nav(page).getByRole('link', { name: label, exact: true });
const slash = (p: string) => (p === '/' ? '/' : `${p}/`);

// Some sport apps are served locally at the site root, others under
// <PAGES_BASE_PATH>/<sport>/. Find which once and prefix every visit.
let prefix: string | undefined;
async function open(page: Page, path: string) {
  if (prefix === undefined) {
    const base = process.env.PAGES_BASE_PATH ?? '';
    for (const c of ['', ...SPORTS.map((s) => `${base}/${s.slug}`)]) {
      const r = await page.request.get(`${c}/`, { maxRedirects: 0 });
      if (r.ok()) { prefix = c; break; }
    }
    prefix ??= '';
  }
  await page.goto(`${prefix}${path}`, { waitUntil: 'domcontentloaded' });
}

async function currentSport(page: Page): Promise<SportSlug> {
  return (await nav(page).locator('a[aria-current="page"]').getAttribute('data-sport')) as SportSlug;
}

// Every (page, other sport) pair of a given kind for the sport under test.
function cases(sport: SportSlug, kind: 'exact' | 'related' | 'standings') {
  const out: { path: string; to: SportSlug }[] = [];
  for (const path of Object.keys(T.sports[sport].pages)) {
    for (const { slug } of SPORTS) {
      if (slug === sport) continue;
      const r = resolveSwitch(T, sport, slug, path);
      const k = !r.note ? 'exact' : r.note[1] === 'Season Standings' && r.path === '/' ? 'standings' : 'related';
      if (k === kind) out.push({ path, to: slug });
    }
  }
  return out;
}

test.describe('Sport switcher (#212)', () => {
  for (const kind of ['exact', 'related', 'standings'] as const) {
    test(`${kind} targets match the table`, async ({ page }) => {
      await page.route(ROUTE, (r) => r.fulfill({ json: T }));
      await open(page, '/');
      const sport = await currentSport(page);
      const list = cases(sport, kind);
      test.skip(list.length === 0, `no ${kind} case for ${sport}`);
      const { path, to } = list[0];
      await open(page, slash(path));
      const label = SPORTS.find((s) => s.slug === to)!.label;
      const href = switchHref(to, resolveSwitch(T, sport, to, path));
      await expect(link(page, label)).toHaveAttribute('href', href);
    });
  }

  test('table failure falls back', async ({ page }) => {
    await page.route(ROUTE, (r) => r.fulfill({ status: 500, body: '' }));
    await open(page, '/players/');
    const sport = await currentSport(page);
    for (const { slug, label } of SPORTS) {
      if (slug === sport) continue;
      await expect(link(page, label)).toHaveAttribute('href', switchHref(slug, { path: '/players' }));
    }
  });

  test('current sport is marked and the arrival note works', async ({ page }) => {
    await page.route(ROUTE, (r) => r.fulfill({ json: T }));
    await open(page, '/?from=Some+Page&to=Season+Standings');
    const sport = await currentSport(page);
    const label = SPORTS.find((s) => s.slug === sport)!.label;
    await expect(link(page, label)).toHaveAttribute('aria-current', 'page');
    const note = page.getByRole('status').filter({ hasText: `No Some Page in ${label}` });
    await expect(note).toContainText('showing Season Standings.');
    await expect(page).toHaveURL(/\/$/);
    await note.getByRole('button', { name: 'Dismiss' }).click();
    await expect(note).toHaveCount(0);
  });
});

test.describe('Sport switcher in the phone drawer (#212)', () => {
  test.use({ viewport: { width: 393, height: 851 } });
  test('drawer shows the switcher', async ({ page }) => {
    await page.route(ROUTE, (r) => r.fulfill({ status: 404, body: '' }));
    await open(page, '/');
    await page.getByRole('button', { name: /toggle navigation menu|open menu|menu/i }).first().click();
    const drawerNav = page.getByRole('navigation', { name: 'Switch sport' }).locator('visible=true');
    await expect(drawerNav.locator('a[aria-current="page"]')).toHaveCount(1);
    await expect(drawerNav.getByRole('link')).toHaveCount(4);
  });
});
