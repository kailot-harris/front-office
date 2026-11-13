# WNBA Analytics — Working Notes

## Retired: the control panel
- **The control panel is retired (2026-11-12, owner decision).** Its code lives in
  `retired/control_panel/` for reference only. Do not run, extend, fix, test or re-wire it, and do
  not open issues or plan work against it. If a task or an old note asks for control panel work, the
  task is out of date: say so and stop.
- Its login code (`auth_utils.R`, `auth_login_module.R`, the login demo/probe and the two auth tests)
  is retired with it and sits in the same folder. Do not add authentication back without asking the
  owner.
- There is no Shiny app in this repo any more. `app.R` was retired earlier (issue #142).

## Shared-checkout safety (issue #105)
- **This primary checkout is shared.** `schedule_daily.bat` ("WNBA Analytics Schedule Daily")
  and `schedule_weekly_offseason.bat` ("WNBA Analytics Schedule Weekly Offseason") run here via
  Windows Task Scheduler, in the *same directory* that interactive sessions and agents use for
  feature work. There is only one working tree at this path — it is not a dedicated,
  always-on-main checkout.
- **Feature work (including agent/subagent work) belongs in its own `git worktree`,
  never directly in this primary checkout.** Create one under `.wnba-worktrees/<name>` (or
  wherever the session's own worktree tooling puts it) and do branch work there. The primary
  checkout at the repo root is reserved for the scheduled tasks and should be left on `main`
  and clean (`git status --short` empty) when you are done with it — do not leave it parked on
  a feature branch or with uncommitted changes "for later."
- **Never clear a dirty primary checkout with `git checkout -- .` (or `git clean -fd`,
  `git reset --hard`) without stashing first.** That is exactly how the issue #105 incident
  destroyed real work: on 2026-11-10 a scheduled 04:15 pipeline run landed on a feature branch
  a subagent had left checked out; the 08:00 publish gate correctly refused
  (`assertion E FAILED ... HEAD=<feature-branch> expected=main`); but at 08:03 a *different*
  agent "fixed" the dirty tree with a bare `git checkout -- .` before merging, silently
  discarding 8 regenerated JSON files and a cache file. Published data stayed stale for ~30
  hours until a manual re-run. If a checkout needs to be cleaned up, `git stash -u` (or commit
  to a branch) first — always leave a recovery path.
- **Never run two builds, pipeline runs, or test suites against this one checkout at the same
  time.** The same 2026-11-10 incident window also saw a second session switch branches twice
  mid-merge, and two test/build runs collide in a single `web/.next` directory (a false
  "Production build" failure plus 7-8 Playwright timeouts). One working directory, one writer
  at a time.
- **Both scheduled entrypoints now enforce this mechanically.** `schedule_daily.bat` and
  `schedule_weekly_offseason.bat` each run a checkout-safety guard right after `cd`-ing into
  `%PROJECT_DIR%` and before any pipeline stage: `git stash push -u` (never a bare discard),
  then `git checkout main`, then assert `git rev-parse --abbrev-ref HEAD` is actually `main` and
  `git diff --quiet` / `git diff --cached --quiet` both report clean. Any failure in that
  sequence aborts the whole run with a non-zero exit code and an `[ERROR]` log line *before*
  touching any pipeline stage or the publish gate — it never silently runs from the wrong
  branch and never discards whatever was sitting in the checkout (recoverable afterward via
  `git stash list`). If you are extending or porting these scripts, keep this guard as the very
  first thing that runs after `cd /d "%PROJECT_DIR%"`.

## Environment
- R is **not on PATH** on this machine. Use the full path:
  `C:\Program Files\R\R-4.5.2\bin\Rscript.exe`.
- Inline multi-line `Rscript -e "..."` (or PowerShell `-e` with embedded newlines) **segfaults**
  on this machine. Always write R code to a temp `.R` file and run
  `Rscript.exe path\to\temp.R` instead.
- Headless browser testing is **no longer set up here.** `app.R` was retired (issue #142), and
  `tools/headless_dashboard_probe.R` and the `headless-ui-regression-sweep` skill were removed with
  it, since both existed only to probe it. If a Shiny UI is ever tested here again, the working
  recipe was `shinytest2` + `chromote` driving the real Chrome at
  `C:\Program Files\Google\Chrome\Application\chrome.exe`, and it required
  `Sys.setenv(NOT_CRAN = "true")` before creating an `AppDriver` or it aborted with
  `Reason: On CRAN` even outside a test suite. The control panel is retired too
  (see the top of this file), so no Shiny UI remains to test.

## Data quirks that will silently corrupt results if missed
- Raw `wehoop::load_wnba_*_box()` data includes non-franchise exhibition/All-Star rows (codes
  vary by season: `DEL`, `WIL`, `ALL`, `USA`, `STE`, `CLA`, `COL`, `COOP`, `SPO`, etc.). Always
  filter to `team_abbreviation %in% names(WNBA_TEAMS)` (after normalization, see next point)
  before aggregating.
- `wehoop` uses `CONN` for the Connecticut Sun in seasons 2019–2023; `config.R`'s `WNBA_TEAMS`
  uses `CON`. A naive exhibition-row filter without normalizing `CONN → CON` first silently
  drops 5 seasons of real Connecticut Sun data instead of just dropping exhibitions. Use the
  `normalize_team_abbreviation()` helper already defined in `daily_ingest.R`/`player_metrics.R`
  — don't reimplement it differently elsewhere.
- ESPN's WNBA injuries endpoint has no `athlete.id` field (unlike the NBA endpoint most code
  here was ported from). `injury_scraper.R` extracts the athlete ID from the "Player Card" link
  href instead — don't assume `athlete$id` exists on this feed.
- The `beat_feeds` wire items from `ingest_sources.R`'s `DEFAULT_BEAT_SOURCES` are **not
  WNBA-only**. These are women's-basketball / women's-sports outlets, so a normal week's
  ingest carries WTA tennis, PWHL and ECAC hockey, NCAA game recaps and FIBA coverage: 23–24
  of 70 items on 2026-11-07. Any consumer that treats a beat item as a WNBA item will
  silently mix other sports into its output (the Media Sentiment Pulse published an NCAA
  Florida–UCF recap as the week's most negative *WNBA* story before this was caught). Filter
  with `sentiment_pulse.R`'s `filter_wnba_relevant_items()` / `item_is_wnba_relevant()`, which
  key off `wnba_team_vocabulary()` derived from `config.R`'s `WNBA_TEAMS` — don't hardcode a
  team-name list. Note also that franchise names are ordinary English words to a sentiment
  lexicon (`liberty`, `golden`, `fever`, `storm`, `sun`, `dream`, `fire`, `sparks`, `aces`),
  so any lexical scoring of this text must mask them first via `mask_team_names()`.
- **`%||%` in `logging_utils.R:32` vs base R ≥ 4.4's `base::`%||%`` (resolved in #153).**
  - `logging_utils.R:32` defines the repo's canonical hardened form (`!is.null(a) && length(a) > 0 && !is.na(a)[1]`),
    which treats `NULL`, `character(0)` (e.g. `grep(...)[1]` -> `NA`), and leading-`NA` scalars as missing.
  - **Base R ≥ 4.4 ships its own `base::`%||%``**, which is `is.null`-only and returns `NA` unchanged.
    Crucially, because `base::`%||%`` is always in scope on R ≥ 4.4, **`exists("%||%")` is always `TRUE`**
    in a fresh session — so guarding `if (!exists("%||%")) source("logging_utils.R")` silently
    no-ops and leaves base R's `is.null`-only version active!
  - Every script that uses `%||%` (including `playoff_simulator.R` and
    `tools/offseason/wire_items_schema.R`) now sources `logging_utils.R` directly (or guards on
    `!exists("log_info", mode = "function")` rather than `!exists("%||%")`). Still use
    `dplyr::coalesce()` for any per-row NA-fill on a column.
- `rapm_engine.R`'s `team` column assignment (both the live possession-vote path and the
  `estimate_rapm_box_plusminus_fallback()` path) is pooled across all of `ALL_SEASONS`, so
  without correction it reflects "the team this player has the most historical
  possessions/minutes with," not their current team — wrong for any traded/signed/
  expansion-drafted player, which silently drops them from `join_rapm_to_roster()`'s inner
  join (confirmed 2026-10-07: 62 of 152 unambiguous-last-name players mismatched, e.g. Angel
  Reese attributed to Chicago Sky while on the Atlanta Dream roster). `rapm_engine.R` now
  calls `reattribute_to_current_roster_team()` at the end of both paths, which overrides
  `team` with `active_rosters_cache.rds`'s current `team_name` whenever a player's last name
  is unambiguous league-wide (ambiguous same-surname cases, e.g. multiple "Williams", are
  left as-is since there's no way to disambiguate from a last-name-only RAPM row). Any future
  change to `rapm_engine.R`'s team-assignment logic must keep calling this helper, or the
  same staleness bug returns.
- `rapm_ratings.rds` and `active_rosters_cache.rds` use incompatible player identifiers
  (`rapm_ratings.rds`'s `player_id` is a different numbering scheme than the ESPN IDs in
  `active_rosters_cache.rds`, and `player_name` there is last-name-only vs. full name in
  rosters). A join on `player_id` or full `player_name` between these two silently returns zero
  matches. Join on `(team full name, normalized last name)` instead — but this key is **not**
  collision-free on the RAPM side (15 `(team, last_name)` groups have >1 RAPM row, e.g. both
  Ogwumike sisters), so a naive join still fans out. Use the shared `join_rapm_to_roster()`
  helper in `rapm_join_utils.R`, which resolves each collision to one row (by most total
  possessions, deterministic tiebreak) rather than reimplementing the join inline.

## Constants — always read from `config.R`, never hardcode or re-derive locally
`config.R` centralizes every structural/modeling constant (`WNBA_TEAMS`, `WNBA_SEASON_GAMES`,
`WNBA_ROSTER_MAX`, `WNBA_GAME_MINUTES`, `WNBA_ROTATION_SIZE`, `WNBA_MARGIN_SIGMA`,
`ROLLING_WINDOW_SIZE`, cache filepaths, etc.), each with its own derivation/validation comment
there. Treat a script that redefines one of these locally instead of sourcing `config.R` as a
bug — and read the value from `config.R` itself rather than trusting a specific number restated
elsewhere (including older revisions of this file), since these get re-benchmarked over time.

## Cache filenames without a central `config.R` constant
- The team-standings cache is `cache/projected_wnba_standings.rds` — deliberately not the NBA
  original's filename (`projected_30_team_standings.rds`). Unlike most cache paths this isn't a
  `config.R` constant, just a literal repeated across its consumers (`roster_bottom_up_engine.R`,
  `rapm_engine.R`, etc.) — use this exact string in any new script that reads/writes it. Two
  consumers named here previously, `app.R` and `market_odds_engine.R`, no longer exist (retired
  under #142 and the zero-betting policy respectively).
- **Never read a test fixture out of `cache/`.** Everything under `cache/` is gitignored runtime
  output, and the `raw_ingest_archive/<YYYYMMDD>/` dirs are named for the ingest date, so such a
  path exists only on a machine that happened to run that day's ingest — not in a fresh clone, a
  new git worktree, or CI. Four off-season tests hardcoded
  `cache/raw_ingest_archive/20261106/league_wire_espn_114245.json` and all failed on their
  opening `file.exists()` outside the original checkout. Frozen real captures belong in
  `data/fixtures/` (tracked), resolved through `tests/helpers/offseason_fixtures.R`'s
  `offseason_league_wire_raw_fixture()`. These fixtures are byte-stable on purpose — tests assert
  exact counts and field values against them — so never re-capture one in place; a new capture
  gets a new filename.

## Process / conventions
- No secrets are ever hardcoded in this repo. All keys/webhooks are read via
  `Sys.getenv(..., "")` with an empty default. If a live credential is genuinely needed to
  complete a task, document what a human must set up (see `docs/ODDS_API_SETUP.md` as the
  pattern) — never fabricate a working call or embed a real secret in a file.
- Every script preserves a fail-safe design: check `file.exists()`/response validity, fall back
  to a clearly labeled synthetic value, never hard-crash the pipeline. When fixing a bug or
  adding a live path, keep the existing fallback intact — just stop it being the *only* path.
- Multi-agent build/remediation work is tracked in dated `docs/task_assignments*.md` files
  (Status column + append-only "Handoff Notes" sections per agent/phase) and per-agent brief
  files (`agents/agentN.md`). Read the relevant task-assignments file's Handoff Notes before
  touching any script another agent already built — they contain the real filenames/schemas
  actually produced, which sometimes differ from what a plan document proposed.
- `docs/REPO_MAP.md` and `docs/WNBA_REPLICATION_PLAN.md` document the *original* NBA system and
  the initial port plan — treat them as historical design references, not as ground truth for
  this repo's current state.

## Folder layout
Repo root holds all pipeline `.R`/`.r`/`.py`/`.bat` scripts, deliberately flat: every script
`source()`s its siblings by bare filename (e.g. `source("config.R")`), and
`run_full_pipeline.R`'s `run_stage()` sources each stage script the same way. Do not move these
into a subfolder, and do not re-flatten the rest of the layout below:
- `agents/` — per-subagent task briefs. Pure documentation, not sourced by any code.
- `docs/` — planning/report/tracking markdown.
- `data/` — loose data artifacts (`config.R`'s `CACHE_TEAM_BOX`/`CACHE_EMBEDDINGS`/
  `CACHE_SIMILARITY` point here) — separate from `cache/`, which holds runtime-generated caches.
- `tools/` — one-off utility/analysis scripts not part of `run_full_pipeline.R`'s DAG. Each
  `setwd()`s to the absolute project root before `source()`-ing dependencies by bare filename,
  so they run correctly regardless of invocation location.
