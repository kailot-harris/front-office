# Inconsistency Remediation Plan

Written 2026-10-17. Source material: `REPO_MAP.md` §9 (known issues), `HANDOFF.md` §2/§4 (verified
live bugs), and a comparative investigation of the `WNBA Analytics` and `NFL Analytics` sibling
repos, which independently hit and fixed several of the same problems — those fixes are cited below
as proven reference implementations, not just proposals.

Each item below becomes one GitHub issue (linked once created). This doc is the shared plan; the
issues are the actionable, assignable units of work. Priority order reflects live-data impact first,
then cosmetic/consistency cleanup.

---

## P0 — Silent data-freshness bug

### 1. `sync_rosters.R` never actually runs inside the automated pipeline

**Problem:** `sync_rosters.R`'s auto-run footer is
`if (sys.nframe() == 0 || interactive()) { sync_active_rosters() }`. `run_full_pipeline.R`'s
`run_stage()` sources this file from inside its own function body (`source(script_name, local =
FALSE)` at `run_full_pipeline.R:19`), so `sys.nframe()` is never 0 in that call path and
`interactive()` is `FALSE` under `Rscript`. The guard evaluates `FALSE`, the fetch/save logic never
executes, but sourcing without error means `run_stage()`'s `tryCatch` logs "COMPLETED" anyway.
Verified: `cache/active_rosters_cache.rds` has carried a Sep 6 mtime through 40+ days of "successful"
daily runs.

**Reference fix (already shipped in both sibling repos, confirmed via code read):**
- WNBA: changed the footer guard from `sys.nframe()==0` to `!interactive()` *and* restructured
  `run_stage()` to take `call_fn`/`entry_fn`/`output` parameters — `call_fn` explicitly invokes the
  entry function after sourcing (not relying on an auto-run footer at all), `entry_fn` asserts the
  function exists post-source, and `output` asserts the declared cache file's mtime actually advanced
  during the stage, WARNing if not.
- NFL: identical fix, described as a `call_fn` contract — every stage script exposes a callable
  `run_*()` function and `run_stage()` calls it directly. Its staleness check (filed as "Finding C-2")
  is live in production and caught a real 711-hour-stale `betting_ledger.rds` on 2026-10-17.

**Plan:**
1. Change `sync_rosters.R`'s footer to call `sync_active_rosters()` unconditionally — drop the frame
   guard entirely (matches every other DAG-stage script's existing pattern; none of them use a frame
   guard today).
2. Audit `daily_ingest.R` for the same guard; it's not in the DAG today, but fix it for consistency
   and because `WNBA_REPLICATION_PLAN.md`/future contributors may wire it in later.
3. Add an output-staleness check to `run_full_pipeline.R`'s `run_stage()`: after sourcing/calling a
   stage, if the stage declares an expected output path, `stat()` it and WARN (not fail) if its mtime
   is older than the stage's own start time.
4. Validate: run `Rscript sync_rosters.R` standalone, confirm fresh mtime; then run
   `Rscript run_full_pipeline.R` end-to-end and confirm the mtime advances *from inside the automated
   path* — that's the actual regression being fixed, not just the standalone script working.

**Priority:** P0. This is a live, currently-silent correctness bug feeding the core rating engine.

---

## P1 — Filename mismatches causing silent synthetic fallback

### 2. `player_props_engine.R` reads a roster path nothing writes

`generate_active_props_table()` reads `cache/active_rosters.rds`; `sync_rosters.R` writes
`cache/active_rosters_cache.rds`. These never connect, so the props engine always falls back to its
fabricated 8-player-per-team synthetic roster regardless of real roster data being available.

**Plan:** Point `player_props_engine.R` at `cache/active_rosters_cache.rds` (the real file). While
touching this, consider a small shared join helper (modeled on WNBA's `rapm_join_utils.R`, which
centralizes the player-ID/name join + collision handling between the ratings file and the roster
file) rather than inlining the fix ad hoc — the same join pattern is needed in item 3 below.

### 3. `risk_management_engine.R` reads a ledger path nothing writes

`compute_risk_state()` loads `cache/bet_log.rds`; the real ledger (written by `bet_tracker.r`) is
`cache/betting_ledger.rds`, a different schema. The risk engine always falls back to a synthetic
120-bet ledger.

**Plan:** Repoint to `cache/betting_ledger.rds` and adapt `compute_risk_state()` to that schema
(drawdown/high-water-mark logic should be schema-agnostic once the column names are reconciled).

---

## P1 — Silent synthetic fallbacks should be loud

### 4. Synthetic-data fallbacks across the pipeline are invisible

Per `REPO_MAP.md` §6, nearly every engine falls back to fabricated data on missing input, and this is
a deliberate fail-safe design — but it currently produces zero visible signal that it happened.
**Reference pattern (NFL):** `risk_management_engine.R` there logs
`WARN ... Using SYNTHETIC_FALLBACK ... THIS IS SIMULATED P&L, NOT REAL BETTING RESULTS` whenever it
falls back, so the log/dashboard can distinguish real from fabricated output.

**Plan:** Add a one-line `WARN`-level log (console `cat()` is fine for now, pending item 6) at every
existing fallback branch (`rapm_engine.R`, `shot_quality_engine.R`, `fatigue_travel_engine.R`,
`playoff_simulator.R`, `risk_management_engine.R`, `copula_props_engine.R`,
`player_props_engine.R`'s roster fallback) stating plainly that synthetic data is being used and why
(missing file path). No behavior change — pure visibility.

---

## P2 — Cross-file numeric inconsistency

### 5. Two different sigma constants for margin → win-probability conversion

`market_odds_engine.R` uses `pnorm(margin/11.2)`; `roster_bottom_up_engine.R` and
`playoff_simulator.R` use `pnorm(margin/11.8)`. Never unified or explained.

**Plan:** Decide on one empirically-derived value (fit from real historical margin variance, not
picked arbitrarily), hoist it into `config.R` as `MARGIN_SIGMA`, and update all three call sites to
reference the shared constant.

---

## P2 — Dashboard gaps (cosmetic placeholders presented as real)

### 6. `app.R` Tab 6 ("Model Calibration & Reliability") is a hardcoded fake curve

`live_calibration.R` has a fully working `calibration_analysis()` (Brier/BSS/log-loss + reliability
plot) that is never wired into the dashboard; Tab 6 renders a static simulated curve instead.

**Reference pattern (both siblings):** an append-only PENDING→RESOLVED prediction log reconciled
against real game outcomes, rendered as accuracy/Brier/log-loss value boxes
(`prediction_accuracy_logger.R` in WNBA, `accuracy_tracker.R` in NFL).

**Plan:** Build an equivalent `prediction_accuracy_logger.R` (log each day's pre-game model win
probabilities, reconcile against `box_scores_cache.rds` once games complete), then replace Tab 6's
hardcoded curve with `live_calibration.R::calibration_analysis()` run against that real log.

### 7. `app.R` Tab 5 ("Team Embeddings") doesn't plot the actual embeddings

It currently scatters points-created vs. shooting-luck from `team_shot_quality.rds`, mislabeled as
"embeddings." It never reads `team_embeddings.csv`'s real 16-D vectors.

**Plan:** Add a real embeddings view — e.g. a 2D PCA/t-SNE projection of the 16-D vectors, or a
pairwise cosine-similarity heatmap from `team_similarity_matrix.csv` — and rename/relabel the
existing shot-quality-luck scatter as its own tab or sub-panel so the label matches the content.

---

## P2 — Risk/Kelly reconciliation

### 8. Risk engine's drawdown-tiered Kelly multiplier isn't fed back into staking

`risk_management_engine.R` computes a tiered multiplier (0.25 → 0.175 → 0.10 → 0.00) but
`market_odds_engine.R::calculate_kelly()` never reads it back — the two Kelly-scaling mechanisms run
independently.

**Plan:** Have `market_odds_engine.R` read `cache/risk_state.rds`'s current tier at the top of
`evaluate_betting_slate()` and pass the resulting multiplier into `calculate_kelly()`'s `fraction`
argument instead of its own hardcoded 0.25.

---

## P3 — Naming/consistency cleanup (low risk, low effort, bundle together)

### 9. `live_game_listener.R` env-var naming inconsistency + dead `ODDS_API_KEY` read

Reads `THE_ODDS_API_KEY`, while `market_odds_engine.R` reads `ODDS_API_KEY` — different names for the
same credential. The variable is read but never actually used to call a live endpoint; the listener
still polls one hardcoded fake game.

**Plan (naming only, scoped small — the live in-play integration itself is a separate, larger future
feature, not bundled into this cleanup):** Rename to `ODDS_API_KEY` for consistency with the rest of
the repo. Leave the "not yet wired to a live endpoint" limitation documented in a code comment rather
than attempting the live in-play integration in this pass.

### 10. `bet_tracker.r` lowercase extension vs. everything else `.R`

Purely cosmetic but shows up in directory listings as an outlier.

**Plan:** Rename to `bet_tracker.R`, update the two call sites (`run_full_pipeline.R`,
`schedule_daily.bat`) that reference it by exact filename.

### 11. `schedule_daily.bat` and `run_full_pipeline.R` overlap

The `.bat` file's 3-step sequence (`run_full_pipeline.R` → `bet_tracker.r` → `market_odds_engine.R`)
duplicates stages `run_full_pipeline.R` already runs internally (steps 7 and 13 of its own 13-stage
DAG).

**Plan:** Simplify `schedule_daily.bat` to a single `Rscript run_full_pipeline.R` call now that the
DAG already covers both stages; verify no stage was relying on the `.bat` file's extra invocation for
some side effect (e.g. a second odds snapshot later in the morning) before removing it — if so,
document that intentional double-run explicitly instead of leaving it looking accidental.

---

## P3 — Documentation hygiene

### 12. `WNBA_REPLICATION_PLAN.md` is stale and describes a state that no longer exists

The plan assumes "no code or folder has been created yet" for a sibling project that has since grown
far beyond a straight port (its own `CLAUDE.md`, `renv.lock`, auth layer, real play-by-play ingester,
etc. — confirmed by direct inspection).

**Plan:** Archive this file (e.g. move to a `docs/archive/` subfolder, or delete it and note the
removal in a commit message) rather than leave it as a misleading live planning doc. This is a
judgment call for the repo owner, not something to silently resolve — flagged here for an explicit
decision, not auto-applied.

---

## Not included in this remediation pass (separate, larger efforts)

- Real stint-level RAPM (replacing `rapm_engine.R`'s synthetic stints) — neither sibling repo has
  solved this either; it's genuinely new work, not a consistency fix.
- Structured dual-sink logging with secret redaction, `renv` dependency pinning, an auth layer / admin
  control-panel app — all real, worthwhile, but additive capabilities rather than "fixing an
  inconsistency," scoped out of this particular plan and tracked separately if wanted.
