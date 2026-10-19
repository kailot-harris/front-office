# SPEC_COMPLIANCE_REPORT.md
### P6 — Final Spec-Compliance Verification (`wnba_spec_compliance_agent`) — 2026-09-12

## ADDENDUM (2026-09-12, post-P6) — Odds API & Discord Webhook Now Confirmed Live

After this report was originally written, the user provisioned `ODDS_API_KEY` and `DISCORD_WEBHOOK` as
real environment variables and registered `schedule_daily.bat` in Windows Task Scheduler. This was
independently re-verified against real evidence (not re-stated from the user's own checklist in
`docs/USER_TASKS.md`):

- **`Get-ScheduledTask -TaskName "WNBA Analytics Schedule Daily"`**: `Enabled = True`, daily trigger at
  `05:30`, action correctly points at `schedule_daily.bat`, `LastTaskResult = 0` (success), a manual test
  run completed at `2026-09-12 08:37`.
- **`pipeline_execution.log` / `logs/wnba_pipeline.log`** from that 08:37 run: `market_odds_engine.R`
  logged `[FEED] Querying live multi-region WNBA odds from The Odds API...` →
  `[FEED SUCCESS] Parsing 8 live WNBA games from API.` — the `SYNTHETIC_FALLBACK` fixture path did **not**
  trigger. `notify_bets.R` logged `[ALERT SUCCESS] Broadcasted calibrated live WNBA bets to Discord
  webhook.` All 13/13 pipeline stages completed; `shot_quality_engine.R` reported `15 WNBA teams on REAL
  shot data, 0 on SYNTHETIC_FALLBACK`.

This is the first time the Odds API live branch has ever actually fired in this project's history (every
prior run, in every earlier phase, hit the fixture). Sections 1, 2, and 5 below are updated in place to
reflect this; the original text is struck through/annotated rather than deleted, so the history of what
changed and why is preserved.

## 0. Method

Confirmed `task_assignments_phase2.md` showed P1-P5 all `done` before starting. Read
`GAP_REMEDIATION_PLAN.md`, `TESTING_PLAN.md` (including its Execution Log), `task_assignments.md`
(original T0-T5), and every P1-P5 Handoff Note in full. Then independently re-verified the load-bearing
claims against real files/output rather than restating the Handoff Notes as fact:

- Confirmed `ODDS_API_KEY` is empty in this shell (`echo $ODDS_API_KEY` → empty), independently of P1's
  own three-way check.
- Confirmed via `ls` that every cache file the Handoff Notes claim was written actually exists:
  `cache/games_for_embeddings.csv`, `cache/rapm_ratings.rds`, `cache/wnba_pbp_cache.rds`,
  `cache/wnba_shots_cache.rds`, `cache/team_shot_quality.rds`, `cache/betting_ledger.rds`,
  `cache/model_calibration_input.rds`, `cache/risk_state.rds`, `team_embeddings.csv`,
  `team_similarity_matrix.csv`, `logs/wnba_pipeline.log`.
- Grepped the real source of `shot_quality_engine.R`, `risk_management_engine.R`, `app.R`,
  `rapm_engine.R`, `load_embeddings.R` directly (not the Handoff Notes' quoted excerpts) and confirmed
  the labeling/fallback/fix claims exist verbatim in the code.
- **Independently re-ran** `Rscript.exe test_logging_fault_injection.R` myself in this session (not
  trusting P5's self-report alone): real output reproduced, exit code 0, 4/4 scenarios PASSED, with the
  same real error strings (DNS failure, `readRDS()` "unknown input format", stack trace, fail-safe
  continuation) P5 reported. This is independent re-verification, not a restated claim.

---

## 1. "All data is originated from live feeds."

| Source | Status |
|---|---|
| wehoop box scores (`daily_ingest.R`, `player_metrics.R`) | Live, confirmed pre-existing since T0/T1, re-confirmed by `TESTING_PLAN.md`'s Execution Log (3,906 real rows, exhibition/CONN checks all pass). |
| ESPN rosters/injuries | Live (`LIVE_ESPN` label, n=42, 0% NA IDs, per `TESTING_PLAN.md` §2.2/2.3, unchanged by this round). |
| RAPM/pbp (`rapm_engine.R`) | Live. Confirmed by code read: `wehoop::load_wnba_stats_possessions()` pulled for all 8 seasons, 253,968 real possessions retained, `cache/rapm_ratings.rds` exists with `data_source = "wehoop::load_wnba_stats_possessions (real, WNBA Stats API-backed)"` (line 196) tagging every row. This is a genuinely new live path (did not exist before this round). |
| Shot quality (`shot_quality_engine.R`) | Live as primary. Confirmed by code read: `data_source = "real_wnba_stats_shots"` (line 284) on the primary path, fed from `load_wnba_stats_shots()` (265,912 real shots pulled across 8 seasons per P2's notes); `cache/team_shot_quality.rds` exists. |
| Embeddings training data (`team_embeddings.py`/`build_games_for_embeddings.R`) | Live. `cache/games_for_embeddings.csv` exists (1,953 real games per P1); `team_embeddings.csv`/`team_similarity_matrix.csv` regenerated with real abbreviation-string `team_id`s, confirmed via `load_embeddings.R`'s real fix (`as.character(team_id)`, line 38, verified by direct grep). |
| Odds API (`market_odds_engine.R`) | ~~Not live in this environment...~~ **UPDATE (2026-09-12 addendum): now confirmed live.** `ODDS_API_KEY` provisioned by the user; a real Scheduled Task run at 08:37 logged `[FEED SUCCESS] Parsing 8 live WNBA games from API.` The fixture path did not trigger. This is independently verified against `pipeline_execution.log`, not just re-stated from the user's report. |

**Verdict: PASS.** (Upgraded from PASS WITH CAVEATS per the 2026-09-12 addendum.) Every data source in
the pipeline — wehoop box scores, ESPN rosters/injuries, RAPM/pbp, shot quality, embeddings training
data, and now the Odds API — is confirmed live with real run evidence from an actual pipeline execution,
not code inspection alone. No data source in this pipeline remains un-provisioned or unexercised.

---

## 2. "All synthetic data origin points are fallbacks only, with functional live feeds in place."

| Synthetic path | Live path exists & has priority? | Fallback-only trigger verified? | Labeled in its own data? |
|---|---|---|---|
| `market_odds_engine.R` fixture slate | Yes (code-verified) | Yes — currently *always* fires (no key), but only because of the key gap, not a design flaw; code-read confirms live branch is checked first | Console `[FEED NOTICE]`/log `WARN`, but **no `data_source` column** in `cache/latest_value_bets.rds` itself (a pre-existing, disclosed gap from `TESTING_PLAN.md`, not fixed this round) |
| `shot_quality_engine.R::generate_team_shot_profiles_synthetic()` | Yes — real path is primary for all 15 teams this run (0 fallback triggers) | Verified by code read (`<3 real games` guard); not exercised in the current cached run | Yes — `data_source = "SYNTHETIC_FALLBACK"` confirmed by grep, distinct from `"real_wnba_stats_shots"` |
| `rapm_engine.R::estimate_rapm_box_plusminus_fallback()` | Yes — real possession-level path succeeded for all 8 seasons this run | Verified by code read; not exercised in the current cached run | Yes — `data_source = "real_box_score_plusminus_fallback"` (distinct tag, confirmed by grep) vs. the primary `"wehoop::load_wnba_stats_possessions (real, WNBA Stats API-backed)"` — note this fallback's *inputs* are real box scores, not fabricated numbers, so it is a lower-fidelity real-data fallback, not a synthetic one |
| `risk_management_engine.R` synthetic 120-bet seed ledger | Yes — `load_real_ledger()` reads real `cache/betting_ledger.rds` first | **Independently re-verified via my own re-run of the fault-injection suite**: missing-ledger scenario (2b) shows the real code path logging `WARN` at each decision point and only falling to the seed ledger when genuinely triggered | Yes — `log_warn(..., data_source = "SYNTHETIC_FALLBACK")` confirmed by grep and by the live fault-injection log line I reproduced |
| `app.R` Tab 6 old hardcoded `seq()`/`rnorm()` curve | Yes — real `cache/model_calibration_input.rds` / `calibration_analysis()` path is now primary | Code-verified: only falls to the static curve if `box_scores_cache.rds` itself is missing (extreme case) | Plot title says `"SYNTHETIC FALLBACK"` per P3's notes (not independently re-rendered, since no browser is available in this environment — code read only) |
| Odds API fixture (see item 1) | ~~Live path exists but never exercised~~ **UPDATE: live branch confirmed firing** (08:37 run, 8 real games parsed) | **Now demonstrated, not just constructed**: the 08:37 run took the live branch, proving the fixture is a genuine fallback rather than the only path ever taken | Labeled via console/log, not a data column (still a minor gap, see below) |

**Verdict: PASS**, individually (updated 2026-09-12 addendum):
- Shot quality, RAPM fallback, risk ledger fallback, and the calibration-tab fallback: **PASS** — each
  has a real live/primary path confirmed to take priority, a genuine fallback-only trigger condition,
  and a clear `data_source`-style label.
- Odds API fixture: **upgraded to PASS.** Previously the caveat was that the fixture had never once
  yielded to its live counterpart, making "fallback-only" true only by construction, not by demonstrated
  behavior. The 08:37 run resolves this: the live branch fired for real, and the fixture remains
  available (and will correctly re-trigger) for genuine outage/off-season conditions. Residual, separate
  from this verdict: `latest_value_bets.rds` still has no `data_source` column distinguishing live vs.
  fixture rows within the data itself (console/log labeling exists, in-data labeling doesn't) — tracked
  as a minor follow-up in the residual risk list, not a blocker to this PASS.
- Overall: **PASS.** (Upgraded from PASS WITH CAVEATS.)

---

## 3. "<1% difference from industry/academic standards" for the ML model.

`ML_BENCHMARK_REPORT.md`'s own verbatim verdict (Section 8): **"Gap verdict: <1% is NOT met."** Real gap
of ~3.6 percentage points vs. Alves & Barbosa (2025), *Computation* 13(10):230, DOI
10.3390/computation13100230 (67.48% WNBA-specific accuracy) against this model's pooled LOSO accuracy
0.639 [0.618, 0.661].

**Independent check performed:**
- **Benchmark citability:** the DOI (`10.3390/computation13100230`) is a well-formed MDPI *Computation*
  DOI; the paper title/journal/venue is plausible and internally consistent with an ML basketball-outcome
  study. P4 disclosed it could not independently fetch the source (403 on both MDPI and ResearchGate) and
  relied on search-summary corroboration across three queries — this is a real, disclosed limitation, not
  a fabricated citation, but it does mean the 67.48% figure itself is one level removed from primary-source
  confirmation in this report chain. I did not have a means to re-fetch the source in this pass either, so
  this caveat is inherited, not independently resolved.
- **CV methodology:** leave-one-season-out (8 real seasons, 2019-2026), each season refit from scratch and
  held out in turn, pooled out-of-fold bootstrap CI (2,000 resamples) — this is a sound design for a
  short-season sport, explicitly not a single cherry-picked split. The fold-to-fold spread (0.569-0.695)
  is reported honestly as evidence a single split would be untrustworthy, which is consistent with, not
  contradicted by, the pooled estimate.
- P4 honestly reported the gap is real-but-modest (benchmark point estimate sits 1.4 points outside this
  model's own CI upper bound, itself smaller than half the CI width) rather than overclaiming either a
  clean pass or a dramatic failure. No metric beyond accuracy could be externally compared (neither paper's
  precision/recall/F1/ROC-AUC was source-verifiable) — this limitation is stated, not hidden.

**Verdict: FAIL.** The spec's own <1% bar is not met on the one metric (accuracy) that could be checked
at all, and the other four required metrics (precision/recall/F1/ROC-AUC) have no verifiable external
comparator, so no PASS claim is possible for them either. This is not upgraded to PASS WITH CAVEATS —
the gap (~3.6 points) is real per P4's own honest analysis, not a hair's-breadth miss.

---

## 4. "Deep logging of errors is confirmed with testing."

`LOGGING_README.md` documents structured `log_info()`/`log_warn()`/`log_error()` calls (console + file,
`logs/wnba_pipeline.log`, append + 5MB rotation) wired into 8 scripts including `run_full_pipeline.R`'s
`run_stage()` (with a real multi-frame stack trace via the `withCallingHandlers`-inside-`tryCatch`
technique).

**Independent re-verification performed (not trusting P5's self-report alone):** re-ran
`"C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "test_logging_fault_injection.R"` myself in this session.
Real result: **exit code 0, 4/4 scenarios PASSED**, reproducing:
1. A real DNS failure on a broken host (`httr2_failure/httr2_error/...`, real `curl` error message).
2. A real `readRDS()` "unknown input format" error on a genuinely corrupted temp file, via the actual
   `load_real_ledger()` function.
3. A missing-ledger fallback that both fires (120-bet synthetic report returned) and logs `WARN` at each
   decision branch.
4. A real dummy-stage failure in `run_stage()` producing a genuine ~10-frame stack trace, `run_stage()`
   returning `FALSE`, and a subsequent stage still running and returning `TRUE` (fail-safe continuation
   intact after the logging changes).

I inspected the actual console output of my own re-run (shown above in my tool output, not asserted) and
confirmed the real log lines match what `LOGGING_README.md`/P5's Handoff Notes describe, including exact
error text (e.g. "Could not resolve host," "unknown input format").

**Verdict: PASS.** Deep, structured, leveled logging exists, is wired into the highest-value real code
paths (including the two newly-live P2 branches and the newly-fixed P3 branch), and its correctness under
genuine fault injection (not just happy-path) was independently reproduced in this session with a fresh
run, not merely re-read from a prior report.

---

## 5. Overall verdict and residual risk list

**Overall (updated 2026-09-12 addendum): PASS on spec items 1, 2, and 4; FAIL on spec item 3.** ~~PASS
WITH CAVEATS on spec items 1 and 2~~ — both upgraded to clean PASS now that the Odds API's live branch
has actually fired in a real run (see addendum above). The system is materially better than
pre-remediation (RAPM and shot-quality are now genuinely live, the risk ledger and calibration tab bugs
are fixed, deep logging exists and is fault-tested, and the odds/Discord live paths are now proven, not
just wired). It does not meet the letter of the full 4-item spec on one count: item 3's ML benchmark gap
is an honest, documented, real shortfall that provisioning credentials cannot fix — it needs either new
modeling work or a decision to accept the gap (see `docs/USER_TASKS.md` Stage 3).

**Residual risk list, prioritized (updated):**
1. ~~Odds API never exercised live (spec #1/#2).~~ **RESOLVED 2026-09-12** — confirmed live via real
   pipeline run evidence, see addendum above.
2. **ML benchmark gap not closed (spec #3).** ~3.6-point real accuracy gap vs. a WNBA-specific published
   benchmark; the one feature-addition attempt (embeddings similarity) made things slightly worse. Closing
   this would likely require new features/data this repo doesn't currently have (P4's own conclusion),
   not further tuning of the existing model. This is now the sole open item blocking a full 4/4 PASS.
3. **Benchmark paper not independently source-verified.** The 67.48% WNBA figure used for spec #3 rests on
   search-summary corroboration, not a directly fetched primary source (403 errors on both MDPI and
   ResearchGate in every session that tried). A human with normal (non-automated) browser access should
   confirm the number and check whether the paper reports precision/recall/F1/ROC-AUC, which would let a
   future pass grade those four metrics too.
4. **`latest_value_bets.rds` still has no `data_source` column** distinguishing live vs. fixture odds
   (unlike the injury cache's `LIVE_ESPN`/`SYNTHETIC_FALLBACK` pattern) — now that the Odds API is
   confirmed live, this is a good time to add it: still a minor labeling gap, not a correctness bug, but
   cheaper to fix now while the live path is actively exercised and testable.
5. **RAPM lambda=900 was grid-searched, not cross-validated** — a defensible but not fully rigorous choice
   per P2's own header comment; a future pass could k-fold/LOSO-tune it the same way P4 tuned the win model.
6. **Shot-quality curve runs "hot" vs. real WNBA shooting** (13/15 teams show negative `shooting_luck_pts`)
   — `calc_expected_shot_prob()` was intentionally ported unchanged per this round's brief, but a future
   recalibration against real WNBA FG%-by-distance data (now cached at `cache/wnba_shots_cache.rds`) is a
   natural, low-effort follow-up.
7. ~~No interactive browser verification of `app.R` Tab 6's calibration plot/labels~~ **RESOLVED
   2026-09-12.** A working headless-browser test setup (`shinytest2`/`chromote` driving a real installed
   Chrome) was set up and used to click through all 8 dashboard tabs and capture real console
   errors/screenshots — not code inspection alone. Result: all 8/8 tabs render with zero
   `.shiny-output-error` elements; Tab 6 shows the real Brier 0.2210 / BSS 0.116 / Log-Loss 0.6432 value
   boxes and a real reliability curve, matching P3's reported numbers exactly. This same probe also
   caught and fixed a real, previously-undetected bug in Tab 3 (Injury & Load Monitor): a vector-unsafe
   use of `app.R`'s own scalar `%||%` operator inside a `mutate()` on the injury cache's `data_source`
   column, which R 4.3+ hard-errors on and Shiny surfaced as an unreadable `Error [object Object]`. See
   `tools/headless_dashboard_probe.R` (now a reusable script) and `CLAUDE.md`'s Environment section for
   how to re-run this. A human eyeballing the dashboard once for visual/UX polish is still worthwhile but
   no longer a correctness-verification blocker.

## Deliverable confirmation

`SPEC_COMPLIANCE_REPORT.md` (this file) written. `task_assignments_phase2.md` updated below with P6
marked `done` and this Handoff Note appended.
