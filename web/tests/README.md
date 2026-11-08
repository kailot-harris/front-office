# `web/` test layers

`vitest.config.mts` deliberately pins **no coverage number** — v8 coverage does not emit a report
under vitest 4's `projects` layout here, and a percentage would be misleading for this suite (the
contract layers assert on JSON and execute almost no app code). That config's comment names the
**per-layer test counts below** as the honest coverage signal instead, so keep this file current
whenever you add or remove a test file.

Run everything with `npx vitest run` from `web/`.

## Counts as of 2026-11-08 (`#169`) — 12 files / 170 tests, all passing

### `node` project (`environment: 'node'`) — 10 files / 153 tests

Pure fs + JSON + math. These read `public/data/*.json` and assert schema, referential integrity and
modelling invariants. They do **not** render components.

| File | Tests | Layer |
| --- | --- | --- |
| `contracts/schema.test.ts` | 39 | contract |
| `contracts/invariants.test.ts` | 38 | contract |
| `contracts/types-vs-data.test.ts` | 32 | contract |
| `contracts/referential.test.ts` | 16 | contract |
| `contracts/bracket-order.test.ts` | 6 | contract |
| `contracts/assets.test.ts` | 4 | contract |
| `contracts/offseason_monitor_contract.test.ts` | 4 | contract |
| `drift/content-drift.test.ts` | 6 | drift |
| `unit/data.test.ts` | 5 | unit |
| `unit/shotChartUtils.test.ts` | 3 | unit |

### `components` project (`environment: 'jsdom'`) — 2 files / 17 tests

`@testing-library/react`, with `setup/vitest.setup.ts` as the setup file. This is the only layer
that executes React component code.

| File | Tests | Covers |
| --- | --- | --- |
| `components/MediaSentimentPulseCard.test.tsx` | 10 | the memo-tab sentiment card's three render states, the sign-dependent `Least positive` / `Most negative` label boundary mirrored from `tools/offseason/render_memo.R:333`, and the off-topic exclusion count that is the visible evidence of #156's relevance filter |
| `components/Sidebar.test.tsx` | 7 | nav active-tab highlighting, including trailing-slash pathnames |

## There is no live end-to-end layer

`playwright.config.ts` sets `testDir: './tests/e2e'` and `vitest.config.mts` excludes that path on
the grounds that Playwright drives it — but **`tests/e2e/` does not exist**, so Playwright currently
runs zero specs. Do not read the vitest config's coverage rationale as describing a live e2e layer.
Headless UI coverage on the R side is also retired (`app.R`, `tools/headless_dashboard_probe.R` and
the `headless-ui-regression-sweep` skill were all removed under #142), which makes the `components`
project above the only automated UI verification in this repo.

## Shared fixtures

`helpers/datasets.ts` is the only shared fixture helper and serves the `node` project (it loads the
real published JSON). Component tests build their own inline fixtures, trimmed to the fields the
component under test reads, with a comment naming the published edition they were copied from.
