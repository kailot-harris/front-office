# HANDOFF — `front-office` consolidation & GitHub Pages workstream

**Written:** 2026-10-19, after commit `5ade015` ("Document live URL, trailing-slash
routing, and the relock workflow"). Working tree clean, `main` pushed, site live.
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
between those repos and this one.** The `src-<sport>` remotes used for the subtree
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
  trailingSlash: true,     // emits <route>/index.html - see §5
  basePath,
  images: { unoptimized: true, remotePatterns: [ /* per-sport CDN hosts */ ] },
};
```

`PAGES_BASE_PATH` is set to `/front-office` in `deploy.yml:12`. **If this repo is
renamed, that value must change to match**, or every asset URL breaks.

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

**Workflow-level caveat discovered here:** the very first push that *creates* the
default branch does **not** fire the `push` trigger, so no deploy ran until it was
kicked manually (`gh workflow run deploy.yml --ref main`). Both workflows define
`workflow_dispatch` for exactly this reason.

---

## 7. Concrete next step

**Bump CI to Node 22** — the clearest outstanding item, and low-risk.

- **File:** `.github/workflows/deploy.yml:57` — change `node-version: 20` to
  `node-version: 22`. Consider the same in `relock.yml:22` (already 22).
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
redundant private upstream repos (§2); and whether to wire up real build-time data
regeneration (§4).
