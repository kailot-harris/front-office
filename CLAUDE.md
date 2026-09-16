# WNBA Analytics — Working Notes

## Environment
- R is **not on PATH** on this machine. Use the full path:
  `C:\Program Files\R\R-4.5.2\bin\Rscript.exe`.
- Inline multi-line `Rscript -e "..."` (or PowerShell `-e` with embedded newlines) **segfaults**
  on this machine. Always write R code to a temp `.R` file and run
  `Rscript.exe path\to\temp.R` instead.
- Headless browser testing works here: `shinytest2` + `chromote`, driving the real Chrome
  install at `C:\Program Files\Google\Chrome\Application\chrome.exe`, via
  `tools/headless_dashboard_probe.R` (clicks through every `app.R` tab, captures real browser
  console errors/screenshots). Requires `Sys.setenv(NOT_CRAN = "true")` before creating an
  `AppDriver` or it aborts with `Reason: On CRAN` even outside a test suite.

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
- `app.R` defines its own `%||%` (near line 50) as a **scalar** null/NA-coalescing operator
  (`if (!is.null(a) && length(a) > 0 && !is.na(a)) a else b`) — it hard-errors on R 4.3+ if
  applied to a full column/vector (`!is.na(a)` returns a vector, `&&` requires length 1). Use
  `dplyr::coalesce()` for any per-row NA-fill on a column; reserve `%||%` for genuinely scalar
  values.
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
  `config.R` constant, just a literal repeated across every consumer (`app.R`,
  `market_odds_engine.R`, `roster_bottom_up_engine.R`, `rapm_engine.R`, etc.) — use this exact
  string in any new script that reads/writes it.

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
