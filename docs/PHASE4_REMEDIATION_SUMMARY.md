# Phase 4 Remediation — Summary

**Date:** 2026-09-16
**Status:** Waves 0–3 complete. Wave 4 (verification sign-off) not yet run — see "What's left"
at the bottom.

This is the entry-point summary. For the full agent-by-agent evidence (every real command
output, every check, every deviation explained), read `docs/task_assignments_phase4.md` in
full — it is long (1600+ lines) on purpose, because every fix there is backed by a real
reproduction, not a description. This document exists so a human or another agent can get
oriented in five minutes instead of reading all of that.

---

## What this was

`docs/SECURITY_TECHNICAL_REVIEW.md` (2026-09-16, a separate adversarial review pass) found 21
issues in the pipeline: 3 Critical, 4 High, 8 Medium, 6 Low. The headline problems were a
mis-set home-court-advantage constant silently driving max-stake home-team betting
recommendations (C-1), four pipeline stages that logged `[COMPLETED]` without executing a
single line of work (C-2), and a dashboard accuracy scoreboard built entirely from synthetic
fixture data reporting a fabricated 83% accuracy (C-3).

Phase 4 remediates all 21 findings.

## How it was orchestrated

Several findings shared hub files (`app.R`, `market_odds_engine.R`, `run_full_pipeline.R`,
`roster_bottom_up_engine.R`), and this repo had no version control at the start of Phase 4, so
two agents could never safely edit the same file concurrently. The findings were regrouped by
**disjoint file ownership** into a wave DAG (full detail and rationale in
`docs/task_assignments_phase4.md`) and executed as:

- **Phase 0** (orchestrator): `git init` + baseline commit — the repo's first version control.
- **Wave 1** (`agent_foundation`, serial): shared constants/helpers every later agent depends on.
- **Wave 2** (5 agents in parallel, disjoint files): `agent_engine`, `agent_dashboard`,
  `agent_pipeline`, `agent_props`, `agent_cleanup`.
- **Wave 2.5** (orchestrator): integration checkpoint — full pipeline run + headless dashboard
  probe, run once all five Wave 2 agents landed.
- **Wave 3** (orchestrator, complete): investigate and invalidate/regenerate caches poisoned by
  the pre-fix HCA value — gated on user confirmation, given by "Then proceed."
- **Wave 4** (not yet run): re-run the original review's reproductions against the fixed code,
  write a verification/sign-off doc.

Every agent brief lives in `agents/agent_foundation.md`, `agent_engine.md`, `agent_dashboard.md`,
`agent_pipeline.md`, `agent_props.md`, `agent_cleanup.md`.

## Findings closed, by ID

| ID | What it was | Fixed by | Verified how |
|---|---|---|---|
| C-1 | HCA `11.6` in live code vs `2.40` in comment/everywhere else | `agent_foundation` (constant) + `agent_engine`/`agent_dashboard`/`agent_pipeline` (call sites) | Real standalone run: `contrib_hca` now `2.4` on all rows; implied home-win prob for identical teams 0.568 (was 0.796); Kelly stakes no longer all pinned at the 3% cap |
| C-2 | 4 stages silently no-op under `source()` (`sys.nframe()==0` guard never true) | `agent_pipeline` | Real `sys.nframe()` harness flipped FALSE→TRUE for all 4; real full pipeline run: all 4 stages' mtimes advance (were frozen); found and fixed a **5th** silent no-op the review missed (`tools/data_health_probe.R`) |
| C-3 | Dashboard accuracy tab was 100% synthetic `DIAG_*` fixture rows reporting fabricated 83% accuracy | `agent_props` (schema: `is_synthetic` column + migration) + `agent_dashboard` (filter + honest count) | Real cache migration (100/114 rows backfilled); Tab 8 now reads "0 real resolved predictions \| 100 excluded as synthetic" instead of 83%/0.131 Brier |
| H-1 | Odds API key reachable by the logger in cleartext on any network error | `agent_foundation` (log redaction) + `agent_engine` (key never enters a URL string at all, via `httr2::req_url_query()`) | Real 401 triggered with a fake key; confirmed absent from console, text log, and DuckDB log table. **This was not latent** — `ODDS_API_KEY` is live on this machine (see below) |
| H-2 | RAPM↔roster join fixed in one file, left broken/naive in two more (one hard-failing nightly) | `agent_foundation` (shared `join_rapm_to_roster()` helper) + `agent_pipeline`/`agent_props` (call sites) | `player_props_engine.R` standalone run now exits 0 and regenerates its cache (was frozen since 2026-09-14 from a live `integer` vs `character` join-type error) |
| H-3 | Dashboard Model Diagnostics tab read a dead path + wrong column names, silently rendered a false "0 pts MAE" | `agent_dashboard` | Path/columns fixed; missing-data state now renders `"—"`, never `0.0` |
| H-4 | `resolve_team_name()` mapped `""`/short strings to a real franchise (`""` → Atlanta Dream) | `agent_engine` | Fuzzed with `""`, `"a"`, `"s"`, `"  "`, `"xy"` — all now return `NA_character_`; exact/abbreviation matches unaffected |
| M-1 | Python stage exit status never checked | `agent_pipeline` | `system2()` + explicit non-zero check wired into the existing fail-safe `tryCatch` |
| M-2 | Orchestrator never sourced `config.R` directly, relied on stage-0 leaking globals | `agent_pipeline` | Explicit `source("config.R")` added |
| M-3 | Props search box passed raw input to `grepl()` as regex — crashed on `(` | `agent_dashboard` | `stringr::str_detect(..., fixed(..., ignore_case=TRUE))`; re-verified the `fixed=TRUE` + `ignore.case` gotcha independently |
| M-4 | Opponent-adjustment formula's own comment said it was backwards | `agent_props` | **Investigated the review's own premise and found it wrong** — regression on 16,657 real rows shows the sign was accidentally right; the real bug was centering a team quantity on a player-level mean plus an unstable denominator. Fixed on the data, not the assumption |
| M-5 | Predictions logged against synthetic fixture games could never reconcile, logged as "yet" forever | `agent_engine` (source marker) + `agent_props` (propagation + `UNRESOLVABLE` sweep) | `market_data_source` column now on `latest_value_bets.rds` and the prediction log; stale `PENDING` rows now age out after 7 days |
| M-6 | Unsafe scalar `%||%` duplicated in 3 files (1 already hardened) | `agent_foundation` (canonical) + `agent_engine`/`agent_dashboard` (delete local copies) | Grep-verified zero local redefinitions remain anywhere |
| M-7 | No `future.seed`; DuckDB logger reconnected per line, dropped rows under concurrent writers | `agent_foundation` (persistent connection + spill file) + `agent_pipeline` (`future.seed=TRUE` + spill-merge) | Real concurrent-process test confirmed no crash + no data loss; real parallel pipeline run recovered 18 spilled rows from 3 workers |
| M-8 | `Win_Pct` stored as a formatted string (`"79.3%"`), silent `NA` on any numeric use | `agent_pipeline` (numeric write) + `agent_dashboard` (display-time formatting) | Real cache confirmed numeric, `[0,1]` range |
| L-1 | Nickname match passed a 15-element vector to `grepl()`'s `pattern` (only tested element 1) | `agent_engine` | Vectorized with `vapply`; confirmed the R length>1 pattern warning no longer fires |
| L-2 | Stale comment citations of `ROLLING_WINDOW_SIZE=13` (live value is 12) | `agent_foundation` + `agent_cleanup` | Comments now cite the constant's name, not a restated number |
| L-3 | `turnovers` vs `total_turnovers` mixed for the same concept across two feature roles | `agent_cleanup` | Standardized on `total_turnovers`; measured isolated impact (+0.92 mean shift, r=0.976) |
| L-4 | `daily_ingest.R` not in the pipeline DAG, ran only as an implicit side effect | `agent_props` (decoupled) + `agent_pipeline` (explicit `call_fn` stage) | Real pipeline run shows the stage's own log lines (602 rows fetched) under its own `[STAGE]` banner |
| L-5 | Scratch `temp_*.R` files at repo root, no `.gitignore` | `agent_cleanup` | Files deleted or consolidated into `tools/derive_props_distribution_params.R` (verified it reproduces every shipped constant exactly); new `.gitignore` added |
| L-6 | Two copies of `latest_player_props.rds` written, dashboard read the wrong one on fallback | `agent_props` (single write) + `agent_dashboard` (single read) | Both now use `CACHE_PLAYER_PROPS` exclusively |

## Integration checkpoint (Wave 2.5)

- Full `run_full_pipeline.R`, real run: **exit 0, 36.49s, 18/18 stages**, all declared cache
  outputs fresh, log-spill merge recovered 18 rows from 3 concurrent workers, zero
  `UNRELIABLE VALUE` RNG warnings.
- `tools/headless_dashboard_probe.R`: **8/8 tabs clean**, zero browser console errors.
- This run genuinely dispatched a live Discord webhook notification (real bet picks from the
  now-fixed model) — confirmed with the user as acceptable, used as their own manual
  verification channel.

## Things found during remediation that weren't in the original review

- **The RAPM↔roster join key isn't fully collision-free**, contrary to what `CLAUDE.md` claimed.
  15 `(team, last_name)` groups collide on the RAPM side (e.g. both Ogwumike sisters). Harmless
  for the one site the review checked (`calculate_matchup_delta()`'s per-team max) but would have
  silently double-counted in the two possession-weighted aggregates this phase touched. `CLAUDE.md`
  corrected; `join_rapm_to_roster()` resolves collisions deterministically by total possessions.
- **`ODDS_API_KEY` and `DISCORD_WEBHOOK` are both live on this machine.** The review's H-1 analysis
  assumed the key was empty ("does not fire today"); it wasn't — a real transient network error
  would already have written the live key to disk before this fix. Checked: no unredacted key
  exists in the currently committed log files.
- **`app.R` never had `plotly` attached** — the dashboard failed to boot on every tab, not just
  the one `agent_dashboard` was assigned. Found and fixed because it blocked that agent's own
  testing.
- **`compute_elo_ratings()` had never run successfully** — written against a schema
  `box_scores_cache.rds` has never had. Unmasked by fixing C-2 (the function's caller was itself
  a no-op) and rewritten against the real schema; rates 1,943 real games now.
- **`tools/data_health_probe.R` (stage 0) had the same C-2-class no-op bug**, missed by the
  original review because it never got past stage 0 in a normal run to notice. Now wired via
  `call_fn`.
- **`tools/ml_cv_benchmark.R` had a hard dependency on `fastshap`, which is archived on CRAN** and
  won't install on R 4.5.2 — the script was fully unrunnable before this wave for a reason
  unrelated to any of the 21 findings. Made optional; worth filing as its own finding.
- **An external git client (pattern matches GitHub Desktop) committed and pushed mid-wave** to a
  private GitHub remote (`github.com/kailot-harris/WNBA_analytics`), outside this session's
  control. No credential leaked (verified). It left a genuine unresolved merge-conflict inside
  `.gitignore` (silently ignoring `cache/`/`docs/` wholesale via a template default) — found and
  fixed before the Wave 2 commit landed.

## Wave 3 results (cache invalidation)

Investigated before mutating anything, since this task was explicitly gated on user
confirmation. Turned out the two live betting caches (`cache/latest_value_bets.rds`,
`cache/odds_history.rds`) had already been regenerated clean by the Wave 2.5 integration run
(both post-date it, `contrib_hca` uniformly `2.4`) and `cache/prediction_accuracy_log.rds`
contains zero rows with the contaminated `11.6` value — the 14 real rows never had a margin
logged at all, and the 100 synthetic rows were already regenerated post-fix by `agent_props`'s
own testing. **The actual gap found was different from what was flagged**:
`tools/optimize_hca.R` filtered resolved predictions without excluding synthetic fixture rows,
so — even with zero `11.6` contamination left — running it today would have silently derived an
"optimal HCA" from 100 fabricated games. Fixed by adding `!is_synthetic` to its filter; re-run
now correctly refuses with "No RESOLVED predictions found to optimize against" instead of
reporting a fabricated number. Also re-verified (without ever printing the key) that both
`logs/wnba_pipeline.log` and `logs/logs.duckdb` remain fully redacted after the extra log volume
from Wave 2.5 — no log-scrub was needed. Full detail in `docs/task_assignments_phase4.md`'s P4-G
Handoff Notes entry.

## What's left

- **Wave 4 — verification doc.** Re-run the original review's own reproductions against the fixed
  code and write `docs/SECURITY_REMEDIATION_VERIFICATION.md` as the formal sign-off, mirroring
  `docs/SECURITY_TECHNICAL_REVIEW.md`'s finding-by-finding structure.
- `agent_pipeline` flagged the remaining half of M-1 as a follow-up: `config.R` should get a
  `PYTHON_BIN` constant so the interpreter isn't resolved bare from `PATH`. Not yet done.
- `agent_pipeline` also flagged that `config.R`'s `CACHE_EMBEDDINGS`/`CACHE_SIMILARITY` constants
  are orphaned (the Python embeddings script never actually writes those paths). Not yet scoped
  into a wave.
- `agent_cleanup`'s finding that `tools/ml_cv_benchmark.R` depends on the CRAN-archived
  `fastshap` package is worth filing as its own finding outside this phase. Not yet filed.
