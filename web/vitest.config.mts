import { defineConfig } from 'vitest/config';
import path from 'node:path';

const alias = { '@': path.resolve(import.meta.dirname) };

// tsconfig.json sets `"jsx": "preserve"` for the Next compiler, so the test
// transformer has to be told to actually compile JSX itself.
const jsx = { jsx: { runtime: 'automatic' as const, importSource: 'react' } };

/**
 * Node project for MLB Analytics dataset contract, invariant, referential,
 * and asset tests. Invoked by `scripts/run-test-suite.mjs --only=contracts`
 * and by `tools/publish_web.R` Assertion G.
 */
export default defineConfig({
  resolve: { alias },
  oxc: jsx,
  test: {
    testTimeout: 15000,
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
    ],
  },
});
