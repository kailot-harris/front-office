import { defineConfig, devices } from '@playwright/test';

/**
 * End-to-end config.
 *
 * Runs against a PRODUCTION build (`next build && next start`) rather than
 * `next dev`, because every page here is statically prerendered — dev mode
 * would exercise a different rendering path from the one that ships, and would
 * hide a build-time data error behind an on-demand compile.
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
  // One retry everywhere, not just in CI: browser tests occasionally hit a
  // transient driver-protocol error ("Unterminated string in JSON at position
  // 524288") when many workers share the managed dev server. A single retry
  // keeps that from failing the gate while a genuine failure still fails twice.
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
  /**
   * Specs are split by project rather than run twice. `mobile.spec.ts` carries
   * its own full route sweep with a real mobile device profile, so running the
   * desktop specs again under a phone viewport would only duplicate work and
   * report the same defects twice.
   */
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
        command: `npx next start -p ${PORT}`,
        url: baseURL,
        reuseExistingServer: !process.env.CI,
        timeout: 120_000,
        // Not piped: buffering next start's output through the driver is what
        // provokes the protocol error noted above.
        stdout: 'ignore',
        stderr: 'pipe',
      },
});
