# HANDOFF — `front-office` consolidation & GitHub Pages workstream

**Written:** 2026-10-20, after commit `132c7fa` ("docs: document the basePath
hand-written-asset gotcha behind the WNBA logo bug"). Working tree clean, `main`
pushed, deploy green, site live.

**Updated:** 2026-10-20, after commit `dc3e353` (last of four subtree merges
bringing in the client-bundle `PAGES_BASE_PATH` fix). 390 commits on
`origin/main`, tree clean, deploy run `39357674081` green (5/5 jobs), site live
and verified. This update closed out the previous §7 ("fix the hand-written
`basePath` bug in NBA and MLB") **and corrected a wrong claim it rested on** —
the WNBA fix that §5 previously reported as "Fixed, commit `742023e`" was still
broken in production. See §5's two-layer gotcha.

**For:** whoever picks this up next, with no context from the session that created it.

---

## 1. What this project is

`front-office` is a **single public repo that publishes four previously separate
sport-analytics projects as one multi-page static site** on GitHub Pages:

- **Live site:** https://kailot-harris.github.io/front-office/
- **Repo:** https://github.com/kailot-harris/front-office (PUBLIC, default branch `main`)

```
/            landing page (index.html) -> links to the four sports
/nba/        NBA Analytics
/wnba/       WNBA Analytics
/mlb/        MLB Analytics
/nfl/        NFL Analytics
```

Each `<sport>/` directory is the **entire** original standalone project — the R
ingest/modelling pipeline, its docs, its tests, and a Next.js app under
`<sport>/web/`. They were combined with `git subtree` so each project's original
commit history is preserved in this repo.

### Scope boundary — read this before editing

This workstream owns **only** the consolidation and publishing layer:

- `index.html`, `README.md`, `.gitignore` (root)
- `.github/workflows/deploy.yml`, `.github/workflows/relock.yml`
- the `output`/`basePath`/`trailingSlash` block at the top of each
  `<sport>/web/next.config.mjs`

**Everything else inside `<sport>/` belongs to that sport's own workstream.** Each
sport has its own pre-existing handoff doc, which is authoritative for that
sport's modelling/feature work and was *not* written or updated by this
workstream:

| Sport | Its own handoff doc |
|---|---|
| NBA | `nba/HANDOFF.md`, `nba/REPO_MAP.md` |
| WNBA | `wnba/docs/HANDOFF.md`, `wnba/docs/REPO_MAP.md` |
| MLB | `mlb/docs/HANDOFF.md`, `mlb/docs/HANDOFF_PHASE_1_TO_4.md` |
| NFL | `nfl/docs/HANDOFF.md` |

Those docs predate consolidation, so **any path they cite is now relative to that
sport's subdirectory** (a reference to `config.R` means `nba/config.R`). They also
contain line-number citations that drift — re-verify before trusting them.

---

## 2. Git history: how the subtree merge is laid out

All four projects' histories are real commits in this repo (366 total on
`origin/main`), not squashes. Each sport was added with
`git subtree add --prefix=<sport> <remote> main` (no `--squash`), producing a merge
commit whose **second parent** is that project's original history tip.

| Sport | Subtree merge commit | Original history tip | Commits preserved |
|---|---|---|---|
| nba | `cb077b506` | `5be94d8e3` | 41 |
| wnba | `746b4f50b` | `6e3abe101` | 158 |
| mlb | `bfaaecd1a` | `5beab9c24` | 51 |
| nfl | `b3a82ba8a` | `335aa817b` | 104 |

All four were verified as ancestors of `origin/main` with
`git merge-base --is-ancestor <tip> origin/main`.

**Gotcha — history looks missing but isn't.** `git log -- nba/somefile` shows only
a couple of commits, because git does not trace paths across the subtree merge
boundary (the files lived at the repo *root* in their original history, not under
`nba/`). The history is fully present. To actually read it:

```sh
git log 5be94d8e3            # NBA's original history, directly
git log --follow nba/config.R
```

**The upstream repos still exist, are still private, and are unchanged.** Local
working copies remain at `C:\Users\kailo\kayceeslices\<SPORT> Analytics`, each on
`main` with a clean tree and its own remote:

| Local path | Upstream |
|---|---|
| `kayceeslices\NBA Analytics` | `kailot-harris/NBA_analytics` |
| `kayceeslices\WNBA Analytics` | `kailot-harris/WNBA_analytics` |
| `kayceeslices\MLB Analytics` | `kailot-harris/MLB-Analytics` |
| `kayceeslices\NFL Analytics` | `kailot-harris/NFL_analytics` |

No decision has been made about retiring them. **Nothing syncs automatically
between those repos and this one.**

**Anomaly worth knowing about the local layout:** the folder holding those four
checkouts is `C:\Users\kailo\kayceeslices\front-office\`, i.e. it shares this
repo's name while being **neither a git repository nor a checkout of it** (`git
rev-parse` there fails with "not a git repository"). Its contents are the four
standalone clones plus an unrelated `wnba_summary_app_deploy\` directory. An
agent started in that directory sees something that looks like this monorepo,
has no `.git`, and has no indication the aggregator exists — which is exactly the
wrong-repo trap §6 step 0 warns about. Left as-is; renaming or `git init`-ing it
is the owner's call.

As of 2026-10-20 each standalone repo is **3 commits ahead** of what it was
before the `basePath` work, all four already propagated here:

| Upstream repo | New commits |
|---|---|
| `WNBA_analytics` | `e1189f5`, `30bb5d6`, `e9c7656` |
| `NBA_analytics` | `e5c570a`, `3419155`, `874742f` |
| `NFL_analytics` | `8a39a86`, `833e384`, `63f93f1` |
| `MLB-Analytics` | `b8aa990`, `c65504c`, `bbb3e56` |

Three commits each for one logical fix is a **course-correction artifact**, not
three separate changes: the first commit used the wrong `basePath` pattern, the
second realigned it to this repo's pattern, the third added the missing client-
bundle `env` key (§5). They were already pushed before the problems were found,
so they were left as forward-only commits rather than rewritten. Squashing them
would need a force-push to four repos and has **not** been done — owner's call.

The `src-<sport>` remotes used for the subtree
merge were deleted after use, so pulling later upstream work requires re-adding
one:

```sh
git remote add src-nba https://github.com/kailot-harris/NBA_analytics
git subtree pull --prefix=nba src-nba main
```

---

## 3. What's actually implemented

| File | State |
|---|---|
| `index.html` (51 lines) | Real. Self-contained dark-themed landing page, inline `<style>`, four relative links (`href="nba/"` …). No build step, no framework, copied verbatim into the published site. |
| `.github/workflows/deploy.yml` (105 lines) | Real and passing. `push` to `main` + `workflow_dispatch`. 4-way build matrix → `assemble-and-deploy`. |
| `.github/workflows/relock.yml` (41 lines) | Real and passing. Manual dispatch only; see §5. |
| `README.md` (89 lines) | Real. User-facing counterpart to this doc. |
| R data regeneration in CI | **NOT IMPLEMENTED — commented-out stub** at `deploy.yml:45-53`. See §4. |
| `mlb/.github/workflows/ci.yml` | **Inert.** Inherited from the MLB repo. GitHub only registers workflows at the *repo root* `.github/workflows/`, so this never runs here. Confirmed via the API: only `deploy.yml` and `relock.yml` are registered. |

### The four Next.js apps

All four `next.config.mjs` files are **structurally identical** (verified by diff;
they differ only in the sport slug and `images.remotePatterns` hostnames):

```js
const sportSlug = 'nba';                                  // per-sport
const repoBase  = process.env.PAGES_BASE_PATH ?? '';
const basePath  = `${repoBase}/${sportSlug}`;

const nextConfig = {
  output: 'export',        // static export; GitHub Pages cannot run a Next server
  env: { PAGES_BASE_PATH: repoBase },  // REQUIRED - see §5, this is load-bearing
  trailingSlash: true,     // emits <route>/index.html - see §5
  basePath,
  images: { unoptimized: true, remotePatterns: [ /* per-sport CDN hosts */ ] },
};
```

`PAGES_BASE_PATH` is set to `/front-office` in `deploy.yml:18`. **If this repo is
renamed, that value must change to match**, or every asset URL breaks.

The `env: { PAGES_BASE_PATH: repoBase }` line is **not redundant** with the
`basePath` above it, and deleting it reintroduces a silent production-only
breakage. It exists so `lib/basePath.ts` (next row) can read the same value from
*client-side* code. §5 explains why.

Each app also has a **`<sport>/web/lib/basePath.ts`** (6–7 lines, all four
present and identical apart from the slug):

```ts
const repoBase = process.env.PAGES_BASE_PATH ?? '';
export const BASE_PATH = `${repoBase}/nba`;
```

`BASE_PATH` must be imported and prefixed onto **every hand-written asset path**
in app code (`fetch('/data/...')`, `<img src="/logos/...">`). Current importers:

| Sport | Files importing `BASE_PATH` |
|---|---|
| nba | `components/InlinePlayerShotCard.tsx`, `components/ShotChartModal.tsx`, `components/ShotsExplorerClient.tsx` |
| wnba | `lib/teams.ts` (`getTeamLogoUrl`), `components/ShotsExplorerClient.tsx` |
| mlb | `lib/teams.ts` (`getTeamLogoUrl`), `components/PlayersClient.tsx` |
| nfl | `components/GalleryClient.tsx` (3 paths: `next/image` src, modal `<img>`, download `href`) |

NBA's and NFL's `getTeamLogoUrl()` are **not** in that list on purpose — they
return `https://a.espncdn.com/...` CDN URLs, so they're immune to this bug class.
MLB's returns a local `/logos/<teamId>.png` for known teams and falls back to the
ESPN CDN otherwise, so only its local branch needed the prefix.

| Sport | Routes (dirs with `page.tsx`) | Tracked data files | `public/data` size | Ingest entrypoints | `renv.lock` |
|---|---|---|---|---|---|
| nba | 12 | 274 | 24M | `daily_ingest.R`, `run_full_pipeline.R` | no |
| wnba | 12 | 225 | 27M | `daily_ingest.R`, `run_full_pipeline.R` | yes |
| mlb | 10 | 11 | 21M | `mlb_ingest.R`, `run_full_pipeline.R` | yes |
| nfl | 9 | 10 | 456K | `daily_ingest.R`, `run_full_pipeline.R` | no |

None of the apps use `app/api/` routes, dynamic `[param]` segments, or server
components requiring a runtime — which is *why* static export works. **Preserving
that is a hard constraint:** adding an API route or a dynamic segment without
`generateStaticParams` will break the Pages build.

### Verification actually performed

Re-run and confirmed at the time of writing (not remembered from earlier):

- Deploy run `39340902187`: all 5 jobs green (`build` ×4 + `assemble-and-deploy`).
- **All 43 routes** across the four sports return HTTP 200, enumerated from
  `<sport>/web/app/*/page.tsx` and fetched live.
- Landing page, all four sport roots, and sample deep routes return 200 in **both**
  `/nba/teams` and `/nba/teams/` forms.
- Data JSON serves correctly, e.g. `mlb/data/clutch_leverage_metrics.json` → 200
  (~276KB), `nba/data/coaching_metrics.json` → 200 (~32KB).

Added by the 2026-10-20 update (the `PAGES_BASE_PATH` client-bundle fix):

- All four apps built locally with `MSYS_NO_PATHCONV=1 PAGES_BASE_PATH=/front-office
  npm run build` — green, in both the standalone upstream checkouts and this repo's
  layout.
- Deploy run `39357674081` green, 5/5 jobs.
- **The built bundle was inspected, not just the build exit code.** The deployed
  chunk `/front-office/nba/_next/static/chunks/app/shots/page-92475596c06ac52b.js`
  contains `"".concat("/front-office","/nba")` and **zero** occurrences of the
  string `PAGES_BASE_PATH`, proving the value is inlined at build time rather than
  looked up at runtime in the browser. This is the check that would have caught the
  original broken WNBA fix; see §5 and §6 step 6.
- Live `curl` 200s on the specific assets that were 404ing:
  `/front-office/mlb/logos/147.png`, `/front-office/wnba/logos/NY_logo.png`,
  `/front-office/mlb/data/player_spatial_maps.json`,
  `/front-office/nba/data/shots_metadata.json`; and
  `/front-office/nfl/gallery/` HTML now emits `front-office/nfl/animations/...` srcs.
- **Statically checked** (not executed) that no test asserts a bare-prefix URL that
  the change would break: NBA's `tests/setup/vitest.setup.ts:31-32` matches with
  `url.includes('/data/shots/')` + `split(...)`, which still works on a prefixed
  URL; WNBA's `tests/contracts/assets.test.ts:16` and `tests/unit/data.test.ts:56-57`
  expect `/wnba/logos/...`, which is what `BASE_PATH` evaluates to when
  `PAGES_BASE_PATH` is unset (as in vitest). No other test references a bare
  `/data/`, `/logos/`, or `/animations/` URL.

**Still not performed — do not assume coverage:** no sport's test suite, `lint`, or
`typecheck` was actually *run* in either session.

**Not performed — do not assume coverage:** no sport's own test suite, `lint`, or
`typecheck` was run in this workstream, and **`deploy.yml` does not gate on them**
(it runs only `npm ci` then `npm run build`). NBA/WNBA/NFL each ship a large suite
(`test:all`, `test:unit`, `test:contracts`, `test:components`, `test:e2e`,
`typecheck`, `lint`); MLB's web app has only `lint`. Whether those suites currently
pass is **unknown**.

---

## 4. Data regeneration — deliberately not wired up

Each app reads static JSON from `<sport>/web/public/data/*.json`, produced by that
sport's R pipeline. **CI does not regenerate it.** Builds consume whatever JSON is
committed, so the published site is only as fresh as the last commit.

The intended design *is* build-time regeneration, and the steps are written out but
commented at `deploy.yml:45-53` (`r-lib/actions/setup-r`, `setup-renv`,
`Rscript run_full_pipeline.R`). They were left disabled because enabling them needs
things not available in this repo:

1. **API credentials as GitHub Actions secrets.** The pipelines read
   `ODDS_API_KEY` and per-sport Discord webhooks via `Sys.getenv()`. No secrets are
   configured on this repo.
2. **An R toolchain decision.** `wnba/` and `mlb/` ship `renv.lock`; `nba/` and
   `nfl/` do **not** pin dependencies, so `setup-renv` can't restore them
   reproducibly as-is.
3. **Runtime/safety review.** The pipelines hit live external APIs and some stages
   dispatch Discord notifications — running them on every push may be undesirable
   and may burn rate-limited quota.

**Current practice:** regenerate locally with the existing scripts and commit the
updated JSON; the next push publishes it.

### Secrets posture (audited before the repo was made public)

The repo was scanned before publishing, because `nba/REPO_MAP.md:66` documents a
**live Discord webhook once hardcoded in a `config.R`**, flagged "treat it as
compromised/rotate it."

What was checked and found:

- No `.Renviron`, `.env`, credential, `.pem`, or `.key` file is tracked, and none
  was ever added in any of the 366 commits.
- Every Discord-webhook-shaped string in **full history file contents** was
  classified: all are placeholders, dummy IDs (`1234567890`), or literal
  `***REDACTED***`. **Zero real-shaped credentials.**
- No `ghp_`/`gho_`/`sk-`/`xox`/`AKIA`/private-key material in tracked files.
- All `Sys.getenv()` calls use empty-string fallbacks, never a hardcoded key.
- Only `nba/.Renviron.example` is present; real `.Renviron` files exist solely in
  the upstream local working copies and were never committed, so the subtree merge
  did not carry them over.

Conclusion: the documented incident belongs to an **ancestor codebase** (likely
`kayceeslices\Research_v2` / `Research_v3`), not to any of these four repos'
history.

**Two open items for the owner, deliberately not acted on:**

1. If that webhook was never rotated, rotate it. This workstream could not verify
   its current status.
2. `nba/REPO_MAP.md` and `wnba/docs/REPO_MAP.md` now **publicly** describe the
   incident. The credential isn't in the repo, so this is disclosure of a past
   issue rather than a live leak — but it's public text, and nobody has decided
   whether to redact it.

---

## 5. Environment & tooling gotchas

**`basePath` does not rewrite hand-written asset paths — and fixing it takes
TWO steps, not one.** All four sports are fixed as of `dc3e353`; this section is
the reference for the next person who adds a sport or a hand-written asset path.

Next's `basePath`/`assetPrefix` (see §3's `next.config.mjs` snippet) only prefixes URLs
*Next itself* generates (`next/link`, `next/image`, its own JS/CSS chunks). A
literal string you write yourself — `<img src="/logos/ATL_logo.png">`,
`fetch('/data/shots/123.json')` — is not touched. It resolves against the domain
root in the browser, so it works fine in local dev (`basePath` is `''` there,
per §3) and silently 404s in production (`basePath` is `/front-office/<sport>`).

This is exactly what broke WNBA's team logos (reported by the user as "icons not
appearing", traced from the live `/wnba/players/` page down to
`wnba/web/lib/teams.ts`'s `getTeamLogoUrl()`).

### Step 1 — route hand-written paths through `BASE_PATH`

Add/import the per-sport `BASE_PATH` constant from `<sport>/web/lib/basePath.ts`
(§3) and prefix every literal `/...` asset path with it. Done for all four sports;
§3's table lists the current importers.

### Step 2 — expose `PAGES_BASE_PATH` to the client bundle (the part that was missed)

**Step 1 alone does nothing in production.** `lib/basePath.ts` reads
`process.env.PAGES_BASE_PATH`, but it is imported by `'use client'` components, so
it is compiled into the **browser** bundle. Next.js only substitutes two things
into client bundles: `process.env.NODE_ENV`, and vars prefixed
`NEXT_PUBLIC_`. A plain custom var is left as a literal runtime property
lookup against webpack's empty `process` shim — which is `undefined` in the
browser, so `?? ''` swallowed it and `BASE_PATH` silently became `/wnba`
instead of `/front-office/wnba`. Every "fixed" path still 404'd.

The fix is the `env: { PAGES_BASE_PATH: repoBase }` key in each
`next.config.mjs` (§3), which makes Next inline the real value at build time.
Evidence of the bug, from the shipped pre-fix MLB bundle:

```js
let t = null !== (i = l(257).env.PAGES_BASE_PATH) && void 0 !== i ? i : ''   // ← runtime lookup, undefined in browser
```

and after adding the `env` key:

```js
let i = "".concat("/front-office", "/mlb")                                    // ← inlined at build time
```

**This defeated the obvious verification.** The original fix was checked by
`curl`-ing the asset URLs and seeing 200s — but that only proves the files are
*served* at the right path, not that the app *requests* them there. A green
build plus 200s on hand-constructed URLs is **not** sufficient evidence. See §6
step 6 for the check that actually catches it.

| Sport | Status as of `dc3e353` |
|---|---|
| wnba | Step 1 in `742023e`; Step 2 in `e9c7656` → merged `dc3e353`. Logos + shot fetch verified live. |
| nba | Both steps, `874742f` (+ earlier path commits) → merged. Shot-chart fetches verified live. |
| mlb | Both steps, `bbb3e56` (+ earlier) → merged. Logos + spatial-map fetch verified live. |
| nfl | Both steps, `63f93f1` (+ earlier) → merged. Gallery `/animations/` paths verified live. |

**If you add a fifth sport, or any new hand-written asset path, do both steps**
and verify per §6 step 6.

### Other environment gotchas

**npm 10 cannot resolve the NFL dependency graph at all.** It crashes with:

```
npm error Cannot read properties of null (reading 'edgesOut')
```

This is an upstream bug in npm 10's arborist `#loadPeerSet`, triggered while
resolving the `@vitest/coverage-v8` → `@vitest/browser-playwright` peer chain. It
is **not** environment-specific: it reproduces on Windows (npm 10.9.8), on Linux
runners (npm 10.9.9), and in the untouched upstream NFL repo. `npm cache clean
--force` and deleting the lockfile do not help. **npm 11 resolves it fine.**

Consequence: `.github/workflows/relock.yml` exists as the supported way to
regenerate any sport's lockfile — manual dispatch, pick a sport, it installs
`npm@latest` on a Linux runner, regenerates from scratch, **verifies `npm ci`
accepts the result**, and uploads the lockfile as an artifact to download and
commit. Use it instead of fighting local npm.

That workflow was created because the NFL build initially failed: the committed
lockfile pinned `@vitest/coverage-v8@4.1.12` alongside `vitest@4.1.11`, but
coverage-v8 peer-requires the *exact* matching vitest version, so `npm ci`
correctly rejected it. Fixed in `78cbc9f` (whole vitest family now uniformly
`4.1.12`). **This was a pre-existing defect in the upstream NFL repo**, not
something consolidation introduced — the same drift is presumably still in
`kailot-harris/NFL_analytics`.

**`node-version: 20` in `deploy.yml` is behind what the dependencies ask for.**
The last successful deploy emitted **150 `EBADENGINE` warnings**; dependencies
request `node: '^22.22.2 || ^24.15.0 || >=26.0.0'`, `'>=22'`, and
`'^22.14.0 || >=24.0.0'`. Builds pass today (warnings only), and no app declares
its own `engines` field, but this is latent — a future dependency bump could turn
it into a hard failure. Local development uses node v22.22.3. GitHub separately
annotates that Node-20-targeted actions are deprecated and being forced onto
Node 24. See §7.

**Git Bash mangles env vars that look like paths.** Running
`PAGES_BASE_PATH=/front-office node -e ...` under Git Bash produced
`C:/Program Files/Git/front-office/nba` instead of `/front-office/nba` — MSYS path
conversion, not a config bug. When checking `basePath` locally, set the variable
*inside* Node (`process.env.PAGES_BASE_PATH = '/front-office'`) or use
`MSYS_NO_PATHCONV=1`. CI is unaffected (Linux, and the value comes from YAML `env:`).

**`trailingSlash: true` is load-bearing for Pages.** Without it, static export
emits `teams.html`, so `/nba/teams` worked but `/nba/teams/` returned **404** — a
real trap for hand-typed and shared URLs. With it, routes export as
`teams/index.html` and both forms resolve. Don't remove it.

**Node can't `require()` MSYS paths.** `/tmp/x.json` must be a Windows path
(`C:/Users/...`) when passed to `node -e`; `cygpath -w` output needs its
backslashes handled. Simplest workaround: copy the file into the repo first, then
read it with a relative path.

**The branch was renamed.** `git init` here defaulted to `master`; it was renamed
to `main` before the first push to match `deploy.yml`'s trigger and all four
upstream repos.

---

## 6. The proven workflow for changing this site

0. **Decide which repo you're editing — this is the step people get wrong.**
   There are *two* plausible places to edit a sport's app, and they are not the
   same repo:

   - `C:\Users\kailo\kayceeslices\front-office\<SPORT> Analytics\` — the local
     working copy of that sport's **standalone upstream repo** (§2). Note the
     local parent folder is *also* named `front-office` but is **not a git repo
     at all** and is **not** a checkout of this one; it just holds the four
     standalone clones side by side.
   - this repo (`kailot-harris/front-office`) — the only thing GitHub Pages
     actually builds and serves.

   **Editing a standalone repo alone deploys nothing.** Nothing syncs
   automatically (§2). Pick one of:

   - **Aggregator-only** (fastest; fine for publishing-layer changes): edit here,
     commit, push. The upstream repo then lacks the fix and will conflict on the
     next subtree pull.
   - **Upstream-then-propagate** (what was done on 2026-10-20, preferred for app
     code so the standalone repo stays the source of truth):

     ```sh
     # 1. in the standalone checkout: edit, commit, push to its own origin/main
     # 2. in a clone of THIS repo:
     git remote add nba-origin https://github.com/kailot-harris/NBA_analytics
     git fetch nba-origin main
     git subtree pull --prefix=nba nba-origin main -m "Merge <what> (git subtree)"
     git push origin main        # ← this is what triggers the deploy
     ```

     The remotes are not persisted in this repo's config (the original
     `src-<sport>` ones were deleted after the initial merge, §2), so re-add one
     each time; name it whatever you like.

   **Keep the two sides' patterns identical or every pull conflicts.** On
   2026-10-20 a fix was written in the standalone repos using a
   `NODE_ENV === 'production'` check with a hardcoded `/front-office/<sport>`,
   while this repo already computed `basePath` from `PAGES_BASE_PATH` (§3). The
   subtree pull hit a content conflict in `next.config.mjs` immediately. The
   resolution was to rewrite the standalone side to match this repo's pattern
   (commits `30bb5d6`/`3419155`/`833e384`/`c65504c`), after which all four pulls
   merged clean. **This repo's pattern is authoritative** — it's the one the
   deploy workflow feeds `PAGES_BASE_PATH` into, and it doesn't hardcode the repo
   name.

1. **Edit** the relevant file — a sport's app under `<sport>/web/`, or this
   workstream's files per §1.
2. **If you touched dependencies**, do *not* trust local npm for NFL (§5). Use
   `relock.yml` and commit the artifact.
3. **Commit and push to `main`.** That alone triggers a deploy; there is no
   separate release step.
   - Docs are committed separately from feature work in this project's inherited
     convention (61 `docs:`-prefixed commits across history).
4. **Watch the run**, don't assume:
   ```sh
   RUN=$(gh run list --workflow=deploy.yml --limit 1 --json databaseId --jq '.[0].databaseId')
   gh run watch "$RUN" --exit-status
   gh run view "$RUN" --json jobs --jq '.jobs[] | "\(.name): \(.conclusion)"'
   ```
   - A `cancelled` run is usually benign: `concurrency: group: pages,
     cancel-in-progress: true` means a newer run supersedes an in-flight one.
   - On failure, `gh run view <id> --log-failed` is the fast path to the error.
5. **Verify live, including the data layer** — a green build does not prove the
   site works, since the JSON is served as static assets:
   ```sh
   BASE=https://kailot-harris.github.io/front-office
   curl -sL -o /dev/null -w '%{http_code}\n' "$BASE/nba/teams/"
   curl -s -o /dev/null -w '%{http_code}\n' "$BASE/nba/data/coaching_metrics.json"
   ```
   Allow ~20s after deploy for the CDN to serve new content.
6. **If you touched anything asset-path- or env-var-related, verify the built
   bundle, not just the HTTP status.** 200s on URLs you typed yourself prove
   only that the file is *served* there — not that the app *asks* for it there.
   That gap is what let a broken `basePath` fix ship and get signed off (§5).

   ```sh
   # no unresolved runtime lookups should remain:
   grep -rc PAGES_BASE_PATH <sport>/web/out/_next/static/chunks/ | grep -v ':0$'
   # and the value should appear inlined (note: Next splits it across a concat):
   grep -ro '"".concat("/front-office","/nba")' <sport>/web/out/_next/static/chunks/
   ```

   The same check against the **deployed** bundle, which is the real proof:

   ```sh
   BASE=https://kailot-harris.github.io/front-office
   CHUNK=$(curl -s "$BASE/nba/shots/" | grep -o '/front-office/nba/_next/static/chunks/app/shots/page-[a-z0-9]*\.js' | head -1)
   curl -s "$BASE${CHUNK#/front-office}" | grep -c PAGES_BASE_PATH   # want 0
   ```

   Better still, load the page in a browser and watch the network tab for 404s —
   no static check substitutes for seeing the app actually fetch its data.

**Workflow-level caveat discovered here:** the very first push that *creates* the
default branch does **not** fire the `push` trigger, so no deploy ran until it was
kicked manually (`gh workflow run deploy.yml --ref main`). Both workflows define
`workflow_dispatch` for exactly this reason.

---

## 7. Concrete next step

**The previous top item — the hand-written-`basePath` bug — is done** for all
four sports (§5), including the client-bundle inlining step that the first
attempt missed. Nothing in this repo is known-broken in production right now.

**Bump CI to Node 22**, low-risk, now the top item.

- **File:** `.github/workflows/deploy.yml:63` (`node-version: 20`; re-verify the
  line number, this doc has shifted it twice) — change to `node-version: 22`.
  `relock.yml:22` is already 22.
- **Why:** the current successful build emits 150 `EBADENGINE` warnings because
  dependencies require node ≥22 (§5). Local dev is already on v22.22.3, so this
  also removes a local/CI divergence.
- **Validate:** push, confirm all 5 jobs stay green, confirm the EBADENGINE count
  drops (`gh run view <id> --log | grep -c EBADENGINE`), then re-run the live route
  check in §6 step 5. If the warning count doesn't drop to ~0, the remaining
  offenders need naming before going further.

**Step after that — decide the CI quality gate.** `deploy.yml` currently runs only
`npm ci && npm run build`, so a broken test or type error publishes silently.
NBA/WNBA/NFL each have full suites and `typecheck`; MLB's web app has only `lint`
(§3). Whether those suites currently pass is **unknown and untested here** — run
them locally per sport *before* adding them as a required CI step, or the first
gated push will fail for reasons unrelated to the change being made. MLB's
inherited `mlb/.github/workflows/ci.yml` is inert and may be worth either
promoting into the root workflow or deleting, so it stops looking like active CI.

**Also open, owner decisions (not blockers):** rotating the webhook and the
`REPO_MAP.md` public-disclosure question (§4); whether to archive the four now-
redundant private upstream repos (§2); whether to wire up real build-time data
regeneration (§4); whether to squash the three-commit-per-repo course-correction
history from 2026-10-20 (§2, needs a force-push to four repos); and whether to
rename or `git init` the confusingly-named local `front-office` parent folder
(§2).

**Resolved 2026-10-20** (commit titled "docs: document both steps of the
basePath fix in README and deploy.yml"): `README.md`'s "Gotcha" section and `deploy.yml`'s
`PAGES_BASE_PATH` comment previously described only Step 1 of the §5 fix, so
anyone following them would have reproduced the original broken version. Both
now document both steps, state that a green build plus a `curl` 200 is not
sufficient evidence, and point here. `README.md` also no longer claims NBA/MLB
are unfixed. If you change the §5 fix pattern, update those two files too —
they are the first thing a newcomer reads.
