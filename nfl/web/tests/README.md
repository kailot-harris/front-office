# Web app test suite

Test infrastructure for the Next.js app in `web/`. Built 2026-10-19.

```bash
npm test               # the whole pipeline (typecheck -> lint -> unit -> build -> e2e)
npm run test:fast      # everything except the build and the browser tests (~15s)
npm run test:contracts # dataset contracts, invariants and drift only
npm run test:components# React component tests only
npm run test:e2e       # Playwright only (builds are NOT run for you here)
npm run test:strict    # ignore the known-issues baseline; any failure fails the run
```

First-time setup on a new machine:

```bash
npm ci                           # or plain `npm install`; no flags needed
npm run test:e2e:install         # downloads the Playwright chromium build
```

## Why it is shaped this way

The app is ~7,000 lines of React that renders ten statically-prerendered pages
from ten JSON files produced by `tools/export_web_datasets.R`. `lib/data.ts`
reads each file with a bare `JSON.parse(...) as T` cast, so **TypeScript proves
nothing about the data at runtime**. The expensive failure mode for this app is
not a crash — it is a page that renders a confident, plausible, wrong number.

So the suite is weighted towards *data coherence* rather than UI mechanics, in
five layers, cheapest first:

| Layer | Location | What it protects |
| --- | --- | --- |
| 1. Schema | `tests/contracts/schema.test.ts`, `schemas.ts` | Every dataset parses and every field is in range. zod schemas are `.strict()`, so a field added upstream in R fails a test instead of silently going unrendered. |
| 1b. Type truth | `tests/contracts/types-vs-data.test.ts` | Reads the string-literal unions out of the `lib/types.ts` *source* and compares them to the values actually present, so a declared type and the data cannot drift apart. |
| 2. Invariants | `tests/contracts/invariants.test.ts` | Mutually exclusive probabilities summing to 1, complementary win probabilities, percentiles ordered, declared totals reconciling with their parts, schedule structure. This is the layer that catches a plausible-but-wrong export. |
| 3. Referential | `tests/contracts/referential.test.ts` | Every team code in all ten datasets resolves against `lib/teams.ts`. CLAUDE.md flags NFL ID reconciliation as this project's biggest join hazard, so every join point is asserted rather than trusted. |
| 4. Assets | `tests/contracts/assets.test.ts` | Gallery index vs. files on disk (both directions), sizes, and remote image hosts against `next.config.mjs` `remotePatterns`. |
| 5. Drift | `tests/drift/content-drift.test.ts` | Numeric literals written into page copy vs. the datasets they describe. The web-layer analogue of the repo's `config-constant-drift-audit` skill. |
| Components | `tests/components/*.test.tsx` | Filter, sort, paginate, tab and modal behaviour, rendered against the **real** datasets, plus empty/single-row resilience. |
| E2E | `tests/e2e/*.spec.ts` | A production build in real Chromium: route smoke, hydration, layout geometry, accessibility baseline, broken images, mobile drawer. |

### The drift layer is the point

`CLAUDE.md` records WNBA Finding C-1: a modelling constant was typed a second
time at a live call site, drifted out of sync with `config.R`, and implied a
materially wrong win-probability curve until someone noticed. That is exactly
what this app does with margin sigma — three hardcoded copies, two different
values, with the sidebar and the home-page banner contradicting each other on
screen. `tests/drift/content-drift.test.ts` reads component **source** and
compares its literals to the live data so that class of bug fails a test.

## The known-issues baseline

`npm test` does not just report pass/fail. It reconciles every failure against
`tests/known-issues.json`:

- a failure **listed** there → reported as `KNOWN`, does not fail the run
- a failure **not listed** → reported as `NEW FAILURES`, fails the run
- a listed test that now **passes** → reported as `FIXED`, prompting you to
  delete the entry

This keeps the suite usable as a merge gate while real defects are still open,
without ever hiding them. Every entry names the defect and the file the fix
belongs in. There is deliberately no automatic `--update-baseline`: adding an
entry requires a human-written title and fix, so the baseline cannot silently
absorb a regression.

When you fix something, run the suite, see it reported as `FIXED`, and delete
the entry. Use `npm run test:strict` to see the unfiltered picture.

## Conventions worth knowing before you add tests

Things that cost time to discover the first time:

- **Tests run against the real datasets, not fixtures.** A failure therefore
  means the page is broken for the data that actually ships. The trade-off is
  that some tests are sensitive to a new export; that is intentional.
- **Scope row queries to the table.** Team names and percentages appear in both
  the highlight cards and the table, so an unscoped `getByText` throws
  "found multiple elements" instead of testing what it looks like it tests.
- **`/teams` has two All/AFC/NFC chip groups** — the scatter owns one and the
  table owns the other, with separate state. Target the table's explicitly.
- **Week rail labels are `"Week 1Final"`, not `"1"`.** There is no word
  boundary between `1` and `F`, so match `^Week 1(?!\d)`, not `^Week 1\b`.
- **Playwright's `getByText('FINAL')` is a case-insensitive substring match**,
  so it also hits the `Week 1Final` rail labels. Scope to `main` and pass
  `{ exact: true }`.
- **The mobile drawer is hidden with `-translate-x-full`, not `display: none`.**
  It keeps a bounding box, so Playwright still calls it "visible". Decide
  open/closed on geometry (is the panel's x >= 0?).
- **Navigation is rendered twice** — a `lg:`-only `<aside class="w-64">` and a
  `lg:hidden` `<aside class="w-72">` drawer. An unqualified `a[href=...]`
  grabs whichever comes first in the DOM.
- **`body.textContent` includes Next's inline RSC `<script>` payload**, which
  legitimately contains the substrings `undefined` and `NaN`. Scope
  placeholder checks to `main`.
- **Overflow is only a bug if it is unreachable.** The 18-week rail and the
  wide tables sit inside `overflow-x: auto` on purpose, so the overflow checks
  walk up the tree and exclude scrollable ancestors.
- **E2E runs against `next build && next start`, not `next dev`**, because
  every page is statically prerendered — dev mode would exercise a different
  rendering path and hide a build-time data error behind an on-demand compile.
- **Interaction specs pin a 1920px viewport.** Below 1792px the fixed sidebar
  covers the left edge of the content (issue `UI-1`), so a
  "click the first chip" step would fail on the layout defect rather than the
  behaviour it is named for. Remove the `test.use` once `UI-1` is fixed.
- **Playwright projects do not overlap.** `desktop-chromium` runs everything
  except `mobile.spec.ts`; `mobile-chromium` runs only `mobile.spec.ts`, which
  carries its own full route sweep. Running both over everything only
  duplicates work and reports the same defects twice.

## Environment notes

- **`vitest` is pinned to `4.x` by an `overrides` entry** in `web/package.json`,
  not only by its devDependency range. Without that override a *fresh* resolve
  (lockfile absent) crashes on npm 10.9.8 — the npm bundled with Node 22, which
  is what CI uses — with `Cannot read properties of null (reading 'edgesOut')`
  in arborist's `#loadPeerSet`. Cause: `@testing-library/jest-dom`
  peer-depends on `vitest: ">= 0.32"`, which is open-ended, so a fresh resolve
  reaches vitest 5 and npm 10.9.8 dies loading vitest 5's
  `@vitest/browser-playwright` peer set. With the override in place,
  `npm install`, `npm install --package-lock-only` and `npm ci` all succeed on
  the default npm 10.9.8 with no flags, and **no particular npm version is
  required to regenerate the lockfile** (verified 2026-10-24, issue #45).
  Two things to know if you ever edit it: the override spec must stay
  **character-identical** to the `vitest` devDependency range or npm aborts
  with `EOVERRIDE`, and the `"vitest": "$vitest"` reference form does *not*
  resolve on npm 10.9.8 (`Unable to resolve reference $vitest`) — write the
  range out literally. Vitest stays on 4 rather than 5 independently of all
  this, because vitest 5 requires `@types/node@^22 || >=24` and this project
  pins `^20`.
- **No coverage report.** v8 coverage emits nothing under vitest 4's
  `projects` layout here, and a vitest-only percentage would be misleading
  anyway: the contract/invariant/drift layers assert on JSON and execute almost
  no app code, while the layer that does exercise the components end to end
  (Playwright) is not instrumented by vitest. Per-layer test counts above are
  the honest signal.
- **`tsconfig.json` gained `"target": "ES2017"`** so `tsc --noEmit` permits
  iterating `Set`/`Map`. It has no runtime effect (`noEmit` is true and Next
  downlevels via SWC), but without it every `for...of` over a Set in a test is
  a type error.
- **JSX in tests** is compiled by oxc via `oxc: { jsx: { runtime: 'automatic' } }`
  in `vitest.config.mts`, because `tsconfig.json` sets `"jsx": "preserve"` for
  the Next compiler.
- If `tsc` reports errors that do not match the source, delete
  `tsconfig.tsbuildinfo` — `incremental: true` caches across config changes.

## Layout

```
tests/
  known-issues.json          baseline of documented, still-open defects
  helpers/datasets.ts        dataset loaders + league structural constants
  contracts/
    schemas.ts               zod schema per dataset (the real runtime contract)
    schema.test.ts           every dataset parses and conforms
    types-vs-data.test.ts    lib/types.ts unions vs. the values in the data
    invariants.test.ts       statistical + structural coherence
    referential.test.ts      cross-dataset and lib/teams.ts integrity
    assets.test.ts           gallery files, sizes, remote host allow-list
  unit/data.test.ts          lib/data.ts I/O boundary and error paths
  drift/content-drift.test.ts hardcoded UI copy vs. the data
  components/*.test.tsx      per-client-component behaviour (jsdom)
  e2e/
    routes.ts                the route table every spec iterates
    smoke.spec.ts            load, title, h1, data present, no console errors
    interactions.spec.ts     filters/sorts/tabs/pagination in a real browser
    a11y-and-assets.spec.ts  a11y baseline + broken-image detection
    layout.spec.ts           sidebar overlap geometry, footer, active nav
    mobile.spec.ts           drawer behaviour + phone route sweep
scripts/run-test-suite.mjs   the orchestrator
test-results/                reports (gitignored)
```
