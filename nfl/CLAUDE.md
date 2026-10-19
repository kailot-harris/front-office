# NFL Analytics — Working Notes

## Environment
- Repo root: `C:\Users\kailo\kayceeslices\NFL Analytics` (Bash path
  `/c/Users/kailo/kayceeslices/NFL Analytics`). This is a git repo (initialized during Phase 0),
  unlike the WNBA sibling repo's own early history.
- R invocation path and the "write R to a temp `.R` file, don't inline `Rscript -e`" caution from
  the WNBA sibling repo have not yet been independently re-verified against this machine/repo — a
  future agent running R here for the first time should confirm the Rscript.exe path and inline-`-e`
  behavior itself rather than assuming the WNBA repo's exact findings carry over unchanged, and
- Confirmed live (2026-09-30): `C:\Program Files\R\R-4.5.2\bin\Rscript.exe` **segfaults (exit
  139) instead of erroring cleanly** when pointed at a relative path that doesn't resolve to an
  existing file — e.g. running `.claude/skills/<name>/scripts/foo.R` from this repo's root
  crashes, because repo-local `.claude/` has no `skills/` subfolder; user-level skills actually
  live under `C:\Users\<user>\.claude\skills\`. Always use the absolute path when invoking a
  user-level skill's `.R` scripts from this repo, and treat a bare "Segmentation fault" from
  Rscript here as a signal to check the path first, not a script-logic bug.
  should update this section with what it actually finds.
- `config.R` and `tools/derive_nfl_constants.R` were built and run against **real**
  `nflreadr::load_schedules()` / `nflreadr::load_teams(current = TRUE)` data on 2026-09-16 — see
  `config.R`'s header comment and `tools/derive_nfl_constants.R` for full derivation methodology.
  Re-run the derivation script and re-verify structural facts (roster limits, team list, playoff
  format) at the start of each new season before trusting downstream modeling — nflverse data,
  franchise names/locations, and league rules (season length, playoff field) have all changed
  before and are exactly the class of fact this repo re-verifies rather than assumes.

## Data quirks that will silently corrupt results if missed
- **ESPN's NFL injuries JSON feed has no top-level `athlete.id` field** — confirmed live against
  `site.web.api.espn.com/apis/site/v2/sports/football/nfl/injuries` on 2026-09-16 (see
  `docs/NFL_REPLICATION_PLAN.md` §2 for the verbatim example payload). The real ESPN athlete ID
  must be parsed out of the athlete's `links[].href` "Player Card" URL (e.g.
  `.../nfl/player/_/id/4430821/...` → `4430821`), not read from `athlete.id` (that field, when
  present at all, is the injury-report-entry ID, not a player ID). This is the **exact same
  quirk** the WNBA Analytics sibling repo's ESPN injuries feed has — `injury_scraper.R` in this
  repo must reuse that proven href-parsing approach rather than assuming `athlete$id` exists.
- **Use `nflreadr::load_*()` functions, not nflfastR's `fast_scraper_*()` functions.** Live
  verification of nflfastR's own changelog (2026-09-16) shows `fast_scraper_roster()` /
  `fast_scraper_schedules()` are deprecated in favor of nflreadr's `load_rosters()` /
  `load_schedules()`, and nflfastR now re-exports nflreadr's `load_pbp()` /
  `load_player_stats()` / `load_team_stats()` rather than maintaining independent versions.
  nflfastR's older dependency, the `nflfastR-raw` GitHub repo, is frozen and will not receive
  2026+ seasons — any code path that pins to it directly is broken for current data. Call
  `nflreadr::load_*()` directly (see `docs/NFL_REPLICATION_PLAN.md` §2 for the full verified
  function/coverage-window table: `load_pbp()` 1999+, `load_snap_counts()` 2012+,
  `load_participation()`/`load_nextgen_stats()` 2016+, with 2023+ `load_participation()` data
  FTN-sourced and released only after the postseason completes — do not assume in-season
  participation features are live-usable for the current season).
- **Four competing NFL player-ID schemes exist** (ESPN athlete IDs, GSIS IDs — nflverse's own
  primary key, PFR IDs, NFL.com/NGS-style IDs) — a materially larger join-mismatch risk than the
  WNBA repo ever had, since that repo mostly dealt with one ID space (ESPN) plus name-based
  fallbacks. Use `nflreadr::load_ff_playerids()` as the canonical cross-source crosswalk at every
  join point that mixes ID schemes, and add a post-join match-rate assertion (fail loudly below a
  threshold) rather than trusting a join to "just work" silently at zero/near-zero matches.

## Constants convention — single source of truth, never duplicate a constant at a call site
Every sport-specific structural or modeling constant lives in `config.R` and only in `config.R`
(`NFL_TEAMS`, `NFL_TEAM_COUNT`, `NFL_ROSTER_MAX`, `NFL_GAMEDAY_ACTIVE_MAX`,
`NFL_PRACTICE_SQUAD_SIZE`, `NFL_SEASON_GAMES`, `NFL_MARGIN_SIGMA`, `NFL_HCA`,
`NFL_PLAYOFF_FIELD` and its related seed/bye constants, `ROLLING_WINDOW_SIZE`, the `CACHE_*`
filepaths, etc. — see `config.R` itself for the current authoritative list, not a copy of it
restated here, since these get re-benchmarked over time and a second list would itself drift).
Every other script in this repo must `source("config.R")` and reference these symbols directly —
treat a script that re-types a numeric literal or re-derives a constant locally instead of
sourcing `config.R` as a bug, not a style nit.

This is a **ported-bug lesson**, not a hypothetical concern: the WNBA Analytics sibling repo's own
remediation history (Finding C-1) is a documented case where a modeling constant (home-court
advantage) was hardcoded a second time at a live call site instead of being read from `config.R`,
silently drifted out of sync with the config value, and implied a materially wrong
win-probability curve until caught. NFL's config surface is larger than WNBA's (more structural
constants, more data-source options, more ID schemes to reconcile — see the quirks above), which
makes this exact failure mode *more* likely to recur here, not less, absent explicit discipline
from Phase 0 onward. The `.claude/skills/config-constant-drift-audit` skill in this repo exists
specifically to mechanically check for this class of drift — run it before merging any change
that touches a modeling/structural constant.

## Process / conventions
- No secrets are ever hardcoded in this repo. `config.R`'s `DISCORD_WEBHOOK` is read via
  `Sys.getenv("DISCORD_WEBHOOK", "")`; any future API key (e.g. an Odds API key) must follow the
  same pattern — empty-string default, never a literal credential committed to a file.
- Every empirically-derived constant in `config.R` documents its derivation inline (script used,
  date run, data window, comparison figures considered and rejected) — see `NFL_MARGIN_SIGMA` and
  `NFL_HCA`'s comments for the pattern. Follow the same documentation density for any new derived
  constant rather than just dropping in a bare number.
- Multi-agent build work is tracked in dated `docs/task_assignments_phaseN.md` files (Task
  Tracker table + wave dependency graph + interface contracts + append-only Handoff Notes),
  scaffolded via the `.claude/skills/remediation-phase-scaffold` skill. Read the current phase
  file's Handoff Notes before touching any script another agent already built — real filenames
  and schemas sometimes diverge from what an earlier plan document proposed.
- `docs/NFL_REPLICATION_PLAN.md` documents Phase 0's live-verified research (data-source
  decisions, coverage windows, playoff-bracket structure, ID-crosswalk strategy) — treat it as a
  historical design reference and factual foundation for later phases, not as a substitute for
  re-verifying a fact that may have changed (nflverse coverage windows, vendor market-key names,
  and league rules all shift over time).
- Stage scripts in `run_full_pipeline.R`'s eventual DAG must expose a callable function that the
  orchestrator invokes explicitly, never rely on a `sys.nframe() == 0`-style top-level-only guard
  to decide whether to execute — `source()`ing a stage from an orchestrator changes frame depth,
  so a frame-depth guard silently no-ops under `source()` while still reporting success. This is a
  documented WNBA-repo failure mode (see `docs/NFL_REPLICATION_PLAN.md` §1) to avoid from the
  start here, not fix after the fact.

## Folder layout
Repo root holds the pipeline `.R` scripts, deliberately flat: every script `source()`s its
siblings by bare filename (e.g. `source("config.R")`), and `run_full_pipeline.R`'s `run_stage()`
will source each stage script the same way once it exists. Do not move these into a subfolder:
- `agents/` — per-subagent task briefs. Pure documentation, not sourced by any code.
- `docs/` — planning/report/tracking markdown (`NFL_REPLICATION_PLAN.md`,
  `task_assignments_phaseN.md`, etc.).
- `data/` — loose data artifacts, separate from `cache/` (runtime-generated caches).
- `cache/` — runtime-generated cache files (`config.R`'s `CACHE_PBP`, `CACHE_SCHEDULES`,
  `CACHE_ROSTERS`, `CACHE_INJURY_DATA`, `CACHE_PARTICIPATION`, `CACHE_NEXTGEN_STATS`,
  `CACHE_PLAYER_PROPS`, etc. all point here).
- `tools/` — one-off utility/derivation scripts not part of `run_full_pipeline.R`'s DAG (e.g.
  `tools/derive_nfl_constants.R`). Each should `setwd()` to the absolute project root before
  `source()`-ing dependencies by bare filename, so it runs correctly regardless of invocation
  location.
- `.claude/skills/` — repo-specific agent tooling conventions (deep-review-to-manuscript,
  render-and-inspect-quarto, remediation-phase-scaffold, config-constant-drift-audit,
  pipeline-freshness-audit), adapted from the WNBA Analytics sibling repo.
