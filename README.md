# Front Office

**Live:** https://kailot-harris.github.io/front-office/

A single multi-page site combining four independent sport analytics projects,
each served as a static Next.js export under its own path:

- `/nba` — NBA Analytics
- `/wnba` — WNBA Analytics
- `/mlb` — MLB Analytics
- `/nfl` — NFL Analytics

## Repo layout

```
.
├── index.html              # landing page, links to each sport
├── .github/workflows/deploy.yml
├── nba/                     # full history preserved from NBA_analytics repo
│   └── web/                 # Next.js app
├── wnba/                    # full history preserved from WNBA_analytics repo
│   └── web/
├── mlb/                     # full history preserved from MLB-Analytics repo
│   └── web/
└── nfl/                     # full history preserved from NFL_analytics repo
    └── web/
```

Each `<sport>/` folder is everything from that sport's original standalone repo
(R ingest/modeling pipeline, docs, tests, and the `web/` Next.js app), merged
in with `git subtree` so the original commit history is still reachable —
`git log <sport>/<some-file>` walks all the way back to that project's first
commit.

## How deploys work

`.github/workflows/deploy.yml` builds all four apps in parallel
(`output: 'export'` static builds), stitches their `out/` directories plus the
root `index.html` into one `site/` folder, and publishes it with
`actions/deploy-pages`.

Each app's `next.config.mjs` sets `basePath` from the `PAGES_BASE_PATH` env var
plus its own slug (e.g. `/front-office/nba`). `PAGES_BASE_PATH` is set to
`/front-office` in `deploy.yml` — **if this repo is ever renamed, update that
value to match**, since project Pages are served at
`https://<user>.github.io/<repo-name>/`.

The apps also set `trailingSlash: true`, so each route exports as
`<route>/index.html` and both `/nba/teams` and `/nba/teams/` resolve.

### Utility: regenerating a lockfile

`.github/workflows/relock.yml` (manual dispatch, pick a sport) regenerates that
app's `package-lock.json` on a Linux runner with npm 11 and verifies `npm ci`
accepts it. This exists because **npm 10 crashes** with
`Cannot read properties of null (reading 'edgesOut')` while resolving the
`@vitest/coverage-v8` peer graph — on both Windows (10.9.8) and Linux runners
(10.9.9). If a lockfile ever drifts out of sync with its `package.json`, run
this workflow and commit the resulting artifact rather than fighting local npm.

## Data regeneration

Each app's `web/public/data/*.json` is produced by that sport's R pipeline
(e.g. `nba/daily_ingest.R`, `mlb/run_full_pipeline.R`). The workflow currently
builds from whatever JSON is already committed — it does **not** re-run the R
ingest in CI yet, because that requires:

1. An R environment (`r-lib/actions/setup-r` + `setup-renv`, since `wnba/` and
   `mlb/` ship `renv.lock`; `nba/` and `nfl/` don't pin one yet).
2. Live API keys (odds providers, stats providers, etc.) added as GitHub
   Actions secrets — these aren't present in this repo and need to be added
   per-sport under **Settings → Secrets and variables → Actions**.

The commented-out steps in `deploy.yml` show where to wire this in once
secrets are configured. Until then, refresh `web/public/data` locally (running
each sport's existing ingest scripts the same way you do today) and commit
the updated JSON — the next deploy will pick it up.

## Local development

Each sport's web app is developed independently, same as before:

```sh
cd nba/web && npm install && npm run dev
```

Note: since `basePath` is always `/${PAGES_BASE_PATH}/<sport>`, and
`PAGES_BASE_PATH` is unset locally, the dev server serves the app under
`/nba`, `/wnba`, etc. (e.g. http://localhost:3000/nba) rather than at `/`.

### Gotcha: `basePath` does not rewrite hand-written asset paths

Next's `basePath`/`assetPrefix` config only prefixes URLs it generates itself
(`next/link`, `next/image`, its own JS/CSS chunks). It does **not** touch a
literal string you write yourself, e.g. `<img src="/logos/ATL_logo.png">` or
`fetch('/data/shots/123.json')`. Those resolve against the domain root in the
browser, so in production (served at `/front-office/<sport>/...`) they 404
while looking completely fine in local dev — this is exactly what broke WNBA
team logos (see `wnba/web/lib/basePath.ts`).

All four sports are fixed as of 2026-10-20. Fixing this takes **two** steps,
and step 1 alone is a no-op in production — that mistake shipped once already.

**Step 1 — route the path through `BASE_PATH`.** Any `<img src="/...">` or
`fetch('/...')` against a file under `public/` must import that sport's
`BASE_PATH` constant from `<sport>/web/lib/basePath.ts` (all four exist) and
prefix it:

```ts
import { BASE_PATH } from '@/lib/basePath';
fetch(`${BASE_PATH}/data/shots/${id}.json`);
```

**Step 2 — make sure `PAGES_BASE_PATH` reaches the browser.** `lib/basePath.ts`
reads `process.env.PAGES_BASE_PATH`, but it's imported by `'use client'`
components, so it compiles into the **client** bundle. Next.js only substitutes
`process.env.NODE_ENV` and `NEXT_PUBLIC_*` vars there — any other custom var is
left as a runtime lookup against an empty `process` shim, comes back
`undefined`, and the `?? ''` fallback silently degrades `BASE_PATH` to
`/<sport>` instead of `/front-office/<sport>`. Every "fixed" path still 404s.

That's why each `next.config.mjs` carries this line, which is **not** redundant
with `basePath` and must not be removed:

```js
env: { PAGES_BASE_PATH: repoBase },
```

**Verifying it.** A green build and a `200` from `curl` on the asset URL are
*not* sufficient — they prove the file is served at that path, not that the app
requests it there. That's exactly how the first broken fix passed review. Check
the built bundle instead:

```sh
# want no output: no unresolved runtime lookups left
grep -rl PAGES_BASE_PATH nba/web/out/_next/static/chunks/
# want a hit: the value inlined at build time
grep -ro '"".concat("/front-office","/nba")' nba/web/out/_next/static/chunks/
```

Best of all, load the page and watch the browser network tab for 404s.
`HANDOFF.md` §5 has the full write-up.
