import { defineConfig, devices } from '@playwright/test';

/**
 * End-to-end config for the NBA Analytics web app.
 *
 * Runs against the PRODUCTION export in `out/` rather than `next dev`, because
 * every page here is statically prerendered — dev mode would exercise a
 * different rendering path from the one that ships, and would hide a build-time
 * data error behind an on-demand compile.
 *
 * The server is scripts/serve-static-export.mjs, not `next start`: this app
 * builds with `output: 'export'`, which `next start` refuses to serve outright.
 * It used to be launched here anyway, so the managed webServer exited on boot
 * and Playwright reported a passing stage having run zero tests.
 *
 * Set E2E_BASE_URL to point at an already-running server (or a deployment) and
 * the managed webServer is skipped.
 */
const PORT = Number(process.env.E2E_PORT ?? 3100);
const baseURL = process.env.E2E_BASE_URL ?? `http://127.0.0.1:${PORT}`;

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: 1,
  workers: process.env.CI ? 2 : undefined,
  reporter: [
    ['list'],
    ['json', { outputFile: 'test-results/playwright-results.json' }],
    ['html', { outputFolder: 'test-results/playwright-report', open: 'never' }],
  ],
  outputDir: 'test-results/playwright-artifacts',
  timeout: 45_000,
  expect: { timeout: 10_000 },
  use: {
    baseURL,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'off',
  },
  projects: [
    {
      name: 'desktop-chromium',
      testIgnore: /mobile\.spec\.ts/,
      use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 } },
    },
    {
      name: 'mobile-chromium',
      testMatch: /mobile\.spec\.ts/,
      use: { ...devices['Pixel 7'] },
    },
  ],
  webServer: process.env.E2E_BASE_URL
    ? undefined
    : {
        command: `node scripts/serve-static-export.mjs`,
        env: { E2E_PORT: String(PORT) },
        url: baseURL,
        reuseExistingServer: !process.env.CI,
        timeout: 120_000,
        // Piped, not ignored: if the export is missing the server says so on
        // stdout and exits 1, and that message is the whole diagnosis.
        stdout: 'pipe',
        stderr: 'pipe',
      },
});
