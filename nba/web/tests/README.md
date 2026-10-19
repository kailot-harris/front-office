# Web App Test Suite & Verification Pipeline

Test infrastructure and data contract verification for the NBA Analytics Next.js platform in `web/`. Built 2026-10-19.

```bash
npm test                # Complete 6-stage pipeline (typecheck -> lint -> contracts -> components -> build -> e2e)
npm run test:fast       # Fast inner loop without build or browser tests (~15s)
npm run test:contracts  # Dataset schemas, invariants, referential integrity & content drift (vitest/node)
npm run test:components # React client components in JSDOM (vitest/components)
npm run test:build      # Production Next.js build verification
npm run test:e2e        # Playwright browser suite (desktop + mobile chromium)
npm run test:strict     # Strict run ignoring known-issues baseline (fails on any error)
```

First-time setup:

```bash
npm install --legacy-peer-deps   # Required for peer dependency alignment with Next 15 / React 19
npx playwright install chromium  # Downloads Chromium engine for E2E tests
```

---

## Why It Is Shaped This Way

The NBA Analytics web application is a rich analytical platform rendering 12 routes from 15 top-level JSON datasets and 25 individual player shot-chart files produced by R and Python simulation pipelines (`pipeline/` and `scripts/`). 

In `lib/data.ts` and `app/*/page.tsx`, datasets are ingested via `fs.readFileSync` and cast with TypeScript assertions (e.g., `JSON.parse(content) as T`). **TypeScript proves nothing about dataset coherence at runtime.** The most hazardous failure mode for an analytics platform is not an unhandled exception or 500 error — it is a page rendering a confident, mathematically invalid number (e.g., playoff odds summing to 162% or salary cap aprons mismatched between UI cards and CBA rules).

The test suite is structured into distinct verification layers, evaluated cheapest-to-most-expensive:

| Layer | Runner / Location | What It Protects |
| :--- | :--- | :--- |
| **1. Type Safety** | `tsc --noEmit` | Strict compile-time typing across all TypeScript files, components, and route handlers. |
| **2. Code Quality** | `next lint` | Static analysis, ESLint hooks rules, and Next.js best practices with zero allowed warnings. |
| **3. Dataset Schemas** | `tests/contracts/schema.test.ts`, `schemas.ts` | Every JSON dataset matches strict Zod schemas (`.strict()`). Unannounced fields added upstream fail here rather than going silently unrendered. |
| **3b. Type Parity** | `tests/contracts/types-vs-data.test.ts` | Reads TypeScript interface definitions from `lib/*.ts` and verifies bidirectional key parity and union membership against live JSON data. |
| **4. Domain Invariants** | `tests/contracts/invariants.test.ts` | Strict NBA mathematical invariants: 30 teams, 82 games, 1,230 league wins, win distributions, quantile order ($p_{10} \le p_{50} \le p_{90}$), playoff/title probability sums, CBA salary totals, and shot zone math. |
| **5. Referential Integrity** | `tests/contracts/referential.test.ts` | Cross-dataset referential consistency: all 30 NBA team abbreviations match `lib/teams.ts`, player pools match across projections and shot charts, and draft picks resolve. |
| **6. Asset Verification** | `tests/contracts/assets.test.ts` | Team logo URLs resolve against ESPN CDN, and every player in `shots_index.json` has a corresponding JSON file on disk. |
| **7. Copy & Drift Audit** | `tests/drift/content-drift.test.ts` | Audits hardcoded UI copy and fallback constants against live JSON data (e.g. CBA thresholds, simulation sample sizes). |
| **8. React Components** | `tests/components/*.test.tsx` (JSDOM) | Unit and integration testing of complex client interactive components (Standings visualizer, Players filter, Shot Chart selector, Playoff matchup visualizer, Cap sheet). |
| **9. Production Build** | `next build` | Production Next.js compilation verifying all static route prerendering and bundle integrity. |
| **10. Browser E2E** | `tests/e2e/*.spec.ts` (Playwright) | Real Chromium browser testing for route smoke checks, hydration, layout geometry, a11y landmarks, and mobile drawer navigation. |

---

## The Known-Issues Baseline (`tests/known-issues.json`)

To prevent ongoing development from being blocked by legitimate upstream data issues while ensuring those issues are never hidden, the test runner reconciles failures against `tests/known-issues.json`:

- **Known Defect**: A failure matching an entry in `tests/known-issues.json` is logged as `KNOWN` and does not fail the run.
- **New Regression**: A failure NOT in `tests/known-issues.json` is logged as `NEW` and causes the suite to exit with code 1.
- **Fixed Defect**: If an issue documented in `tests/known-issues.json` starts passing, the runner reports it as `FIXED`, prompting you to delete the resolved entry.

Every entry in `tests/known-issues.json` requires:
- `id`: Unique identifier
- `title`: Short human-readable summary
- `defect`: Detailed description of the root cause
- `fix`: Target location for remediation (e.g., Python pipeline script or UI component)
- `tests`: Array of test name substrings to match

---

## Key Testing Conventions

- **Real Datasets**: Tests execute directly against the production JSON files in `public/data/` rather than artificial mocks, ensuring real-world data fidelity.
- **Subpixel Layout Tolerance**: Viewport geometry checks allow a 2px tolerance for browser subpixel font and box-model rounding.
- **RSC Script Filtering**: Console error and text content assertions filter out internal Next.js React Server Component payload markers (`undefined`, `NaN` in script tags).
- **Mobile Drawer Geometry**: The mobile navigation drawer is toggled conditionally; mobile specs verify actual DOM visibility and route transitions.
- **Strict Mode**: Use `npm run test:strict` to run without the `known-issues.json` filter and inspect all raw test failures.
