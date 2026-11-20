import { defineConfig, devices } from '@playwright/test';

/**
 * Accessibility suite (kailot-harris/MLB-Analytics#130).
 *
 * Runs axe against the built static export in `out/` (run `npm run build`
 * first), served by scripts/serve-static-export.mjs because `next start` does
 * not serve `output: 'export'`. Every top-level route is checked in both the
 * light and the dark colour scheme. Set E2E_BASE_URL to test a running server.
 */
// 3140, not 3100: the other sport repos use 3100, and reuseExistingServer would
// otherwise test whichever site is already listening there.
const PORT = Number(process.env.E2E_PORT ?? 3140);
const baseURL = process.env.E2E_BASE_URL ?? `http://127.0.0.1:${PORT}`;

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: process.env.CI ? 2 : 4,
  reporter: [['list'], ['html', { outputFolder: 'test-results/playwright-report', open: 'never' }]],
  outputDir: 'test-results/playwright-artifacts',
  timeout: 180_000,
  use: { baseURL, trace: 'retain-on-failure' },
  projects: [
    { name: 'light', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 }, colorScheme: 'light' } },
    { name: 'dark', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 }, colorScheme: 'dark' } },
  ],
  webServer: process.env.E2E_BASE_URL
    ? undefined
    : {
        command: 'node scripts/serve-static-export.mjs',
        env: { E2E_PORT: String(PORT) },
        url: baseURL,
        reuseExistingServer: !process.env.CI,
        timeout: 120_000,
        stdout: 'pipe',
        stderr: 'pipe',
      },
});
