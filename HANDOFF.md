# HANDOFF — NBA Analytics

Updated 2026-10-18, after the repo's first GitHub issue-tracking pass (commit `bc201e0` on `main`,
pushed). Originally written 2026-10-17 when no git repo or HANDOFF.md existed yet. For whoever picks
this up next — human or agent, zero assumed context.

---

## 1. What this project is

A personal Windows-only NBA analytics + quantitative sports-betting pipeline. Mostly R
(tidyverse/tidymodels), one Python file for team embeddings. Runs via `Rscript`, orchestrated by
`schedule_daily.bat` + Windows Task Scheduler (daily ~05:00).

**This is now a real git repo** (it was not as of the 2026-10-17 version of this doc — `git init`
happened partway through that session). Remote: `origin` →
`https://github.com/kailot-harris/NBA_analytics`, default/only branch `main` (renamed from `master`
after the initial push; the rename was done deliberately — see §2.1). Working tree is clean as of
this writing; nothing from the remediation plan below has been implemented yet, only planned and
filed as issues.

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

## 2. Git/GitHub state and issue tracker

### 2.1 Repo history (verified via `git log --oneline`, 4 commits total on `main` as of this writing)

1. `e514746` — a pre-existing orphan "Initial commit" that only added a generic R-package
   `.gitignore`, created on GitHub (likely via the repo-creation UI) before this project's actual
   history existed locally.
2. `d544b5a` — this project's real "Initial commit": all 219 tracked files (R/Python scripts, the
   Rmd/PDF/HTML baseline reports, all the phase/ADR/wishlist markdown docs). `config.R`'s previously
   hardcoded Discord webhook was already stripped out and replaced with an `.Renviron`-sourced env
   var *before* this commit — the real webhook value was never committed to this repo. `.Renviron`
   itself, `cache/`, `*.rds`, `.Rhistory`, and `pipeline_execution.log` are all git-ignored and were
   verified absent from `git ls-files` after the commit.
3. `d22a4c0` — merge of the orphan `e514746` history into `main` (`--allow-unrelated-histories`,
   combined rather than discarded the two `.gitignore` files) after the local branch was renamed from
   `master` to `main` and a push conflict surfaced an unrelated existing `main` on the remote.
4. `bc201e0` — added `INCONSISTENCY_REMEDIATION_PLAN.md` (see §2.2).

**Nothing has been force-pushed and no remote history was discarded** — the orphan commit's content
(a generic `.gitignore`) was merged in, not overwritten.

### 2.2 `INCONSISTENCY_REMEDIATION_PLAN.md` → GitHub issues #1–#12

All 12 items in that plan file were filed as individual GitHub issues on
`kailot-harris/NBA_analytics` on 2026-10-18. **As of this writing, all 12 are OPEN — zero have been
started or closed.** This table is the live source of truth for priority/sequencing; don't trust a
stale copy of it without re-running `gh issue list --repo kailot-harris/NBA_analytics --state all`.

| # | Title | Priority | Label | Depends on |
|---|---|---|---|---|
| [#1](https://github.com/kailot-harris/NBA_analytics/issues/1) | `sync_rosters.R` auto-run guard never fires inside the pipeline | P0 | bug | — |
| [#2](https://github.com/kailot-harris/NBA_analytics/issues/2) | `player_props_engine.R` reads `active_rosters.rds`, nothing writes it | P1 | bug | #1 (roster cache should be fresh first) |
| [#3](https://github.com/kailot-harris/NBA_analytics/issues/3) | `risk_management_engine.R` reads `bet_log.rds`, nothing writes it | P1 | bug | — |
| [#4](https://github.com/kailot-harris/NBA_analytics/issues/4) | Synthetic-data fallbacks are silent — make them loud | P1 | enhancement | — |
| [#5](https://github.com/kailot-harris/NBA_analytics/issues/5) | Two sigma constants (11.2 vs 11.8) never unified | P2 | bug | — |
| [#6](https://github.com/kailot-harris/NBA_analytics/issues/6) | `app.R` Tab 6 calibration curve is hardcoded/fake | P2 | enhancement | — |
| [#7](https://github.com/kailot-harris/NBA_analytics/issues/7) | `app.R` Tab 5 "Team Embeddings" doesn't plot real embeddings | P2 | bug | — |
| [#8](https://github.com/kailot-harris/NBA_analytics/issues/8) | Risk engine's Kelly multiplier not fed back into bet sizing | P2 | enhancement | #3 (needs the real ledger wired first) |
| [#9](https://github.com/kailot-harris/NBA_analytics/issues/9) | `live_game_listener.R` env-var naming inconsistency | P3 | documentation | — |
| [#10](https://github.com/kailot-harris/NBA_analytics/issues/10) | `bet_tracker.r` lowercase extension | P3 | documentation | — |
| [#11](https://github.com/kailot-harris/NBA_analytics/issues/11) | `schedule_daily.bat`/`run_full_pipeline.R` overlap | P3 | documentation | — |
| [#12](https://github.com/kailot-harris/NBA_analytics/issues/12) | `WNBA_REPLICATION_PLAN.md` is stale | P3 | documentation | — |

Each issue body is self-contained (problem, reference fix from the WNBA/NFL sibling repos where one
exists, concrete plan, priority) — read the issue itself, not just this table, before starting work.
The plan file (`INCONSISTENCY_REMEDIATION_PLAN.md`) is the doc each issue links back to; keep them in
sync if scope changes while working an issue (e.g. update both, or at minimum comment on the issue
with the deviation).

Validation evidence for *why* these issues exist (verified-live mtimes, code excerpts, sibling-repo
comparison) lives in §3 below and in the plan file itself — this table does not re-derive it.

---

## 3. Current automation state (verified live, not from docs)

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
- **Still not fixed** (as of 2026-10-18) — this is filed as issue
  [#1](https://github.com/kailot-harris/NBA_analytics/issues/1), re-verified moments ago: `tail -5
  sync_rosters.R` still shows the `sys.nframe() == 0 || interactive()` guard unchanged, and
  `cache/active_rosters_cache.rds` still has its Sep 6 mtime. See §2.2/§5 for the plan and sequencing.

---

## 4. What's real vs. synthetic (quick pointer, full detail in REPO_MAP.md §1/§6/§9)

Still synthetic/fabricated end-to-end as of this inspection (no change from REPO_MAP.md's findings):
`rapm_engine.R` (fake stints), `shot_quality_engine.R` (fake shot profiles), `fatigue_travel_engine.R`
slate function (hardcoded 4-game sample), `playoff_simulator.R` (feeds off the synthetic RAPM),
`risk_management_engine.R` (reads a `cache/bet_log.rds` path nothing else writes, so always falls
back to its synthetic ledger — the *real* ledger is `cache/betting_ledger.rds`, different schema),
`player_props_engine.R`'s roster (reads `cache/active_rosters.rds`, which nothing writes — the real
file is `cache/active_rosters_cache.rds`, a one-character filename mismatch that's been there since
Phase 3/4 and is separate from the §3 bug above — tracked as issue #2), `copula_props_engine.R` (one hardcoded Jokic demo,
not run across the roster), `xpoints_engine.R` (effectively always synthetic — stats.nba.com blocks
it in practice).

Genuinely live today: `sync_rosters.R`'s ESPN fetch logic works when run manually/interactively
(confirmed by code reading — just not when driven by the automated DAG, see §3's "Newly discovered
bug" subsection / issue #1),
`injury_scraper.R` (ESPN injuries JSON), `market_odds_engine.R` (The Odds API — confirmed live
today, 46 games), `roster_bottom_up_engine.R` (real BPM from real `player_box_scores_cache.rds`,
joined against whatever roster snapshot happens to be on disk), `bet_tracker.r` (real ledger
grading against real box scores).

One item from the original (2026-10-17) version of this section is now resolved and removed from
here: `config.R`'s hardcoded Discord webhook was moved to a git-ignored `.Renviron` before the first
commit (see §2.1) — it never made it into git history. The remaining known issues are now tracked as
GitHub issues, not restated here — see §2.2's table and `INCONSISTENCY_REMEDIATION_PLAN.md` for the
full list and reference-fix detail. Keeping one copy of this list (the issue tracker) avoids it
drifting out of sync with this doc the way the old inline bullet list would have.

---

## 5. Concrete next step

**Work issue [#1](https://github.com/kailot-harris/NBA_analytics/issues/1)** (`sync_rosters.R`'s dead
auto-run guard) — it's P0, live, silently-broken, and upstream of the pipeline's core rating engine.
The issue body has the full plan; in short:

1. In `sync_rosters.R`, change the last line from
   `if (sys.nframe() == 0 || interactive()) { sync_active_rosters() }` to an unconditional
   `sync_active_rosters()` (matching every other DAG-stage script's existing pattern), or restructure
   `run_full_pipeline.R`'s `run_stage()` to call known entry-point functions explicitly after
   sourcing instead of relying on auto-run footers.
2. Audit `daily_ingest.R` for the identical guard (harmless today since it's not in the DAG, but fix
   for consistency per the issue).
3. Add the output-staleness check to `run_stage()` described in the issue (both sibling repos already
   have a working reference implementation of this — see `INCONSISTENCY_REMEDIATION_PLAN.md` item 1
   for exactly what they did).
4. Validate: `Rscript sync_rosters.R` standalone first (confirm `cache/active_rosters_cache.rds`'s
   mtime updates and the row count is sane — don't blindly trust the historical "~556 players across
   30 teams" figure from `next_researcher_handoff_prompt.md` without re-checking it), *then*
   `Rscript run_full_pipeline.R` end-to-end and confirm the mtime updates **from inside the automated
   path** — that's the actual regression, not just the standalone script working.
5. Commit with `Closes #1` in the message so the issue auto-closes on merge/push to `main`.

**Two steps ahead:** once #1 lands, #2 (`player_props_engine.R`'s `active_rosters.rds` filename
mismatch) becomes low-risk to fix, since it depends on the roster cache actually being fresh — it's
explicitly marked as depending on #1 in §2.2's table. After that, #3 and #4 (both P1, independent of
#1/#2) are the next-highest-value items. Full sequencing and priorities are in §2.2 — re-run
`gh issue list --repo kailot-harris/NBA_analytics --state all` before picking up work, since issue
state (not this table) is the live source of truth and may have changed since this doc was written.
