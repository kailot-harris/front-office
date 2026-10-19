import { defineConfig } from 'vitest/config';
import path from 'node:path';

const alias = { '@': path.resolve(import.meta.dirname) };

// tsconfig.json sets `"jsx": "preserve"` for the Next compiler, so the test
// transformer has to be told to actually compile JSX itself.
const jsx = { jsx: { runtime: 'automatic' as const, importSource: 'react' } };

/**
 * Two projects so each suite runs in the cheapest environment that works:
 *   - `node`   : dataset contract / invariant / drift / unit suites (pure fs + JSON + math)
 *   - `jsdom`  : React component suites (@testing-library/react)
 *
 * Playwright end-to-end specs live in `tests/e2e/` and are deliberately
 * excluded here — they are driven by `playwright.config.ts` instead.
 */
export default defineConfig({
  resolve: { alias },
  oxc: jsx,
  test: {
    testTimeout: 15000,
    // Reporters are chosen per-stage by scripts/run-test-suite.mjs (it needs a
    // separate JSON file per project to reconcile against the baseline), so no
    // json reporter is pinned here.
    reporters: ['default'],
    projects: [
      {
        resolve: { alias },
        oxc: jsx,
        test: {
          name: 'node',
          environment: 'node',
          include: [
            'tests/contracts/**/*.test.ts',
            'tests/unit/**/*.test.ts',
            'tests/drift/**/*.test.ts',
          ],
        },
      },
      {
        resolve: { alias },
        oxc: jsx,
        test: {
          name: 'components',
          environment: 'jsdom',
          globals: true,
          setupFiles: ['tests/setup/vitest.setup.ts'],
          include: ['tests/components/**/*.test.tsx'],
        },
      },
    ],
  },
});
