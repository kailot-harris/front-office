# HANDOFF — NBA Analytics

Written 2026-10-17, after inspecting the live state of the repo (no prior HANDOFF.md existed).
For whoever picks this up next — human or agent, zero assumed context.

---

## 1. What this project is

A personal, local-only (**no git — `git init` has never been run here**), Windows-only NBA
analytics + quantitative sports-betting pipeline. Mostly R (tidyverse/tidymodels), one Python file
for team embeddings. Runs via `Rscript`, orchestrated by `schedule_daily.bat` + Windows Task
Scheduler (daily ~05:00).

**Read `REPO_MAP.md` first, in full, before touching any code.** It is an exhaustive, verified,
file-by-file inventory (data sources, the 13-stage pipeline DAG, every script's real vs. synthetic
data status, known filename mismatches, the two Phase-4/5 planning docs' relationship to actual
code). This HANDOFF.md does not repeat that content — it only adds what changed/was verified since
REPO_MAP.md was written, plus the concrete next step. Reading order: `REPO_MAP.md` → `ADR.md` (Phase
1 rationale) → `engineering_log_phase2.md` / `engineering_log_phase3.md` (narrative history) → this
file.

**Hard boundary rule (ADR.md Principle I):** never edit `NBA_Analysis_Project.Rmd` or
`NBA_Analysis_Project - Original -no Llm.Rmd` — both are frozen baseline reference reports.

**A sibling project exists and has far outgrown its planning doc.** `WNBA_REPLICATION_PLAN.md` in
this repo describes a *proposed* port of this codebase to `C:\Users\kailo\kayceeslices\WNBA
Analytics\`, written as "no code or folder has been created yet." That is now false and badly
stale: `WNBA Analytics\` already exists, is far more mature than a straight port (it has its own
`CLAUDE.md`/`AGENTS.md`, `renv.lock`-managed dependencies, an `auth_login_module.R`/`auth_utils.R`
login layer, a `control_panel_app.R`, a real `pbp_engine.R` play-by-play ingester, a
`prediction_accuracy_logger.R`, `rapm_join_utils.R`, and its own daily pipeline log current as of
2026-10-17). **Do not treat `WNBA_REPLICATION_PLAN.md` as a live plan** — it describes a Phase-0
state that was superseded by independent work. If someone asks you to "execute the WNBA
replication plan," stop and point them at the actual `WNBA Analytics\` repo and its own
`CLAUDE.md` instead; this is a tracker-hygiene discrepancy for the owner to resolve (e.g. archive
or delete the stale plan doc), not something to silently fix here.

---

## 2. Current automation state (verified live, not from docs)

The daily pipeline **is running and producing real output**. `pipeline_execution.log`'s most recent
entry: `PIPELINE RUN COMPLETED SUCCESSFULLY: Sat 10/17/2026 5:00:26.61`, and that run pulled **46
live NBA games from The Odds API** (not the fixture fallback — `ODDS_API_KEY` is live and working
today). Most `cache/*.rds` files carry an Oct 17 05:00 mtime, confirming the day's run actually
wrote fresh output for: `latest_value_bets.rds`, `latest_player_props.rds`, `odds_history.rds`,
`betting_ledger.rds`, `rolling_bet_metrics.rds`, `risk_state.rds`, `rapm_ratings.rds`,
`team_shot_quality.rds`, `travel_fatigue_metrics.rds`, `playoff_series_bos_nyk.rds`,
`copula_jokic_pra.rds`, `projected_30_team_standings.rds`, `injury_data_cache.rds`.

### Newly discovered bug: roster sync has been silently dead since Sep 6

`cache/active_rosters_cache.rds` still has a **Sep 6** mtime despite the pipeline log showing
`sync_rosters.R` "COMPLETED" every single day since. Root cause, verified by reading the code:

- `sync_rosters.R`'s last line is `if (sys.nframe() == 0 || interactive()) { sync_active_rosters() }`.
- `run_full_pipeline.R`'s `run_stage()` helper calls `source(script_name, local = FALSE)` **from
  inside its own function body** (`run_full_pipeline.R:19`). That means when `sync_rosters.R` is
  sourced during the automated batch run, `sys.nframe()` is *not* 0 (there's an enclosing call
  frame from `run_stage()`), and `interactive()` is `FALSE` under `Rscript`. The guard evaluates
  `FALSE`, so **`sync_active_rosters()` never actually executes** — the file is sourced (defining
  the function) but the fetch/save never runs. Because sourcing without calling the function
  doesn't throw, `run_stage()`'s `tryCatch` sees no error and logs "COMPLETED" anyway.
- `daily_ingest.R` has the identical guard and the identical problem, but it's harmless there since
  `daily_ingest.R` was never wired into `run_full_pipeline.R`'s DAG in the first place (confirmed —
  `REPO_MAP.md` §3.1 already notes this file isn't called by the pipeline).
- Every other auto-running engine in the DAG (`roster_bottom_up_engine.R`,
  `fatigue_travel_engine.R`, `shot_quality_engine.R`, `rapm_engine.R`, `market_odds_engine.R`,
  `player_props_engine.R`, `copula_props_engine.R`, `playoff_simulator.R`,
  `risk_management_engine.R`, `bet_tracker.r`) calls its top-level function unconditionally at the
  bottom of the file with no frame guard — those genuinely do execute every run. `sync_rosters.R`
  is the one outlier.
- **Practical impact**: `roster_bottom_up_engine.R` (the core team-rating engine) has been joining
  against a roster snapshot that is six weeks stale relative to the pipeline's other inputs —
  mid-season trades/signings since Sep 6 are invisible to it. This has presumably been quietly
  degrading rating accuracy for over a month without any error surfacing anywhere (not in the log,
  not in the dashboard).
- **Not fixed as part of this handoff** — flagging per write-handoff convention (surface, don't
  silently patch an automated system you weren't asked to touch). The fix is small: either drop the
  `sys.nframe() == 0 || interactive()` guard entirely and call `sync_active_rosters()`
  unconditionally like every sibling engine does, or change `run_stage()` to call the script's
  entry function by name after sourcing rather than relying on an auto-run footer. Verify
  `daily_ingest.R` isn't relying on the same guard for some other (manual) invocation path before
  touching it too.

---

## 3. What's real vs. synthetic (quick pointer, full detail in REPO_MAP.md §1/§6/§9)

Still synthetic/fabricated end-to-end as of this inspection (no change from REPO_MAP.md's findings):
`rapm_engine.R` (fake stints), `shot_quality_engine.R` (fake shot profiles), `fatigue_travel_engine.R`
slate function (hardcoded 4-game sample), `playoff_simulator.R` (feeds off the synthetic RAPM),
`risk_management_engine.R` (reads a `cache/bet_log.rds` path nothing else writes, so always falls
back to its synthetic ledger — the *real* ledger is `cache/betting_ledger.rds`, different schema),
`player_props_engine.R`'s roster (reads `cache/active_rosters.rds`, which nothing writes — the real
file is `cache/active_rosters_cache.rds`, a one-character filename mismatch that's been there since
Phase 3/4 and is separate from the §2 bug above), `copula_props_engine.R` (one hardcoded Jokic demo,
not run across the roster), `xpoints_engine.R` (effectively always synthetic — stats.nba.com blocks
it in practice).

Genuinely live today: `sync_rosters.R`'s ESPN fetch logic works when run manually/interactively
(confirmed by code reading — just not when driven by the automated DAG, see §2),
`injury_scraper.R` (ESPN injuries JSON), `market_odds_engine.R` (The Odds API — confirmed live
today, 46 games), `roster_bottom_up_engine.R` (real BPM from real `player_box_scores_cache.rds`,
joined against whatever roster snapshot happens to be on disk), `bet_tracker.r` (real ledger
grading against real box scores).

---

## 4. Known pre-existing issues not yet fixed (carried from REPO_MAP.md, still open)

- `cache/active_rosters.rds` vs `cache/active_rosters_cache.rds` filename mismatch
  (`player_props_engine.R` reads the former, nothing writes it).
- `cache/bet_log.rds` vs `cache/betting_ledger.rds` — `risk_management_engine.R` reads a path
  nothing writes.
- Two different margin→win-probability sigma constants in play (11.2 in `market_odds_engine.R` vs
  11.8 in `roster_bottom_up_engine.R`/`playoff_simulator.R`) — never unified.
- `app.R` Tab 6 (Model Calibration) is a hardcoded fake curve; `live_calibration.R`'s real
  `calibration_analysis()` is never wired into it.
- `app.R` Tab 5 ("Team Embeddings") doesn't actually plot `team_embeddings.csv`'s 16-D vectors.
- Risk engine's drawdown-tiered Kelly multiplier is not read back into
  `market_odds_engine.R`'s `calculate_kelly()`.
- `live_game_listener.R` reads `ODDS_API_KEY`/`THE_ODDS_API_KEY` (inconsistent env var name vs.
  `market_odds_engine.R`) but never actually calls The Odds API's live in-play endpoint — it still
  polls one hardcoded fake game (`BOS_NYK_LIVE`).
- `config.R` line 37 hardcodes a live Discord webhook URL in plaintext — treat as a compromised
  credential if this repo is ever shared/published; rotate it first.
- `schedule_daily.bat` and `run_full_pipeline.R` overlap (both touch bet grading/odds evaluation),
  not deduplicated.

---

## 5. Concrete next step

**Fix the `sync_rosters.R` auto-run guard (§2) and verify the fix with a real run**, since it's a
live, silently-broken automated system (not a cosmetic doc gap) and it's upstream of the pipeline's
core rating engine:

1. In `sync_rosters.R`, change the last line from
   `if (sys.nframe() == 0 || interactive()) { sync_active_rosters() }` to an unconditional
   `sync_active_rosters()` (matching the pattern every other DAG-stage script already uses — see
   §2's list), or restructure `run_full_pipeline.R`'s `run_stage()` to call known entry-point
   functions explicitly after sourcing instead of relying on auto-run footers.
2. Run `Rscript sync_rosters.R` standalone first and confirm `cache/active_rosters_cache.rds`'s
   mtime updates and row count is sane (~556 players across 30 teams per the historical
   `next_researcher_handoff_prompt.md` checklist figure — verify that figure is still accurate for
   the current season rather than trusting it blindly).
3. Then run `Rscript run_full_pipeline.R` end-to-end and confirm the mtime updates *from inside the
   automated path*, not just standalone — that's the actual regression being fixed.
4. Check whether `player_props_engine.R`'s filename mismatch (§4, `active_rosters.rds` vs
   `active_rosters_cache.rds`) should be fixed in the same pass — it's a one-line path fix and
   would mean the props engine starts consuming a real roster instead of its synthetic fallback for
   the first time. Not required for the sync_rosters.R fix itself, but it's the natural next domino
   once rosters are confirmed fresh.

After that, the two filename mismatches in §4 (`bet_log.rds`, sigma-constant unification) and the
Tab 6/Tab 5 dashboard gaps are the next-highest-value items, in roughly that order — none are
urgent, all are pre-existing and documented in `REPO_MAP.md` §9's wishlist.

Separately, flag to the project owner (don't act on it yourself): `WNBA_REPLICATION_PLAN.md` is
stale and should probably be archived or deleted now that `WNBA Analytics\` has its own independent,
more advanced implementation with its own docs.
