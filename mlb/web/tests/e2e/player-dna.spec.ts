import { test, expect } from '@playwright/test';

/**
 * /player-dna embeds only the first screen of profiles and fetches the full
 * player_dna_profiles.json after hydration. Checks that the fetch (under the
 * basePath) completes, the default player's peer comps render, each player type
 * shows its published dimension count, and no team is shown as "MLB".
 */
test('player-dna: full dataset loads, peer comps render, 16 batter / 15 pitcher skill rows, no "MLB" team', async ({ page }) => {
  const fullFetch = page.waitForResponse(
    (res) => /\/mlb\/data\/player_dna_profiles\.json$/.test(new URL(res.url()).pathname) && res.status() === 200,
  );
  const res = await page.goto('/player-dna/');
  expect(res?.status()).toBe(200);
  const full = await fullFetch;
  const body = (await full.json()) as { profiles: unknown[] };

  const status = page.getByTestId('dna-load-status');
  await expect(status).toHaveAttribute('data-state', 'complete');
  // After the fetch every batter is in the roster, not just the embedded first screen.
  const batterCount = (body.profiles as { playerType: string }[]).filter((p) => p.playerType === 'Batter').length;
  await expect(page.getByTestId('dna-roster-item')).toHaveCount(batterCount);

  // Default player (first batter) shows its peer comps.
  await expect(page.getByTestId('dna-selected-name')).not.toBeEmpty();
  await expect(page.getByTestId('dna-peer-comp')).toHaveCount(5);
  await expect(page.getByTestId('dna-skill-row')).toHaveCount(16);

  // Pitchers: 15 skill rows.
  await page.getByTestId('dna-type-pitcher').click();
  await expect(page.getByTestId('dna-skill-row')).toHaveCount(15);
  await expect(page.getByTestId('dna-peer-comp')).toHaveCount(5);

  // Back to batters: 16 again.
  await page.getByTestId('dna-type-batter').click();
  await expect(page.getByTestId('dna-skill-row')).toHaveCount(16);

  // No team is ever shown as "MLB": team labels, logo fallbacks and logo alt text.
  for (const type of ['dna-type-batter', 'dna-type-pitcher']) {
    await page.getByTestId(type).click();
    const teams = await page.getByTestId('dna-team').allInnerTexts();
    expect(teams.length).toBeGreaterThan(0);
    expect(teams.map((t) => t.trim())).not.toContain('MLB');
    const main = page.locator('main');
    await expect(main.getByText('MLB', { exact: true })).toHaveCount(0);
    await expect(main.locator('img[alt^="MLB "]')).toHaveCount(0);
  }

  // A multi-club player is labelled "2+ teams" with no logo.
  await page.getByTestId('dna-type-batter').click();
  await page.getByPlaceholder(/Search Batter/).fill('2+ teams');
  const multi = page.getByTestId('dna-roster-item').first();
  await expect(multi.getByRole('img', { name: '2+ teams' })).toBeVisible();
  await multi.click();
  await expect(page.locator('h2 + div [data-testid="dna-team"]')).toHaveText('2+ teams');
});
