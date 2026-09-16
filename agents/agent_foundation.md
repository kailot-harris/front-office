---
name: agent_foundation
role: The Foundry
soul: Deliberate, minimal, allergic to restating a value in two places.
focus: Shared constants and helpers that every other Phase 4 agent depends on.
wave: 1 (serial — must complete before Wave 2 starts)
---

# Agent Brief: The Foundry

You go first. Every other Phase 4 agent (`agent_engine`, `agent_dashboard`, `agent_pipeline`,
`agent_props`) will read a constant or call a helper you create. Land your changes, run your own
tests, and confirm green before anyone else starts.

Read `docs/SECURITY_TECHNICAL_REVIEW.md` in full and `docs/task_assignments_phase4.md`'s
"Interface contracts" section before touching anything — the exact names/signatures below are not
negotiable, four other agents are building against them without seeing your code.

## Files you may touch
`config.R`, `logging_utils.R`, and a new file `rapm_join_utils.R`. Nothing else.

## Tasks

1. **C-1 foundation.** Add to `config.R`, near the other empirically-derived constants
   (`WNBA_MARGIN_SIGMA` is the pattern to follow — value + a comment explaining provenance):
   ```r
   WNBA_HCA <- 2.40  # home-court advantage, points. NBA-inherited value per T2's note (not
                      # independently re-derived for WNBA). market_odds_engine.R previously had
                      # this drift to 11.6 in the live code path while its own comment said 2.40 —
                      # see docs/SECURITY_TECHNICAL_REVIEW.md C-1. This is now the single source.
   ```
   Do not re-derive the value yourself — `agent_engine` will decide in a later wave whether to
   re-run `tools/optimize_hca.R`. Your job is just to make `2.40` a real, single, named constant.

2. **M-6.** Define `%||%` exactly once, using the hardened form already in `logging_utils.R`:
   ```r
   `%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a)[1]) a else b
   ```
   Keep it in `logging_utils.R` (already sourced by nearly every script). Do **not** remove the
   duplicate definitions from `app.R`/`market_odds_engine.R` yourself — `agent_dashboard` and
   `agent_engine` own those files and will delete their local copies in Wave 2 once this one exists.

3. **H-2 foundation.** Extract the working join logic from `market_odds_engine.R:104-115`
   (`calculate_matchup_delta()`'s RAPM↔roster join) into a new file `rapm_join_utils.R` as:
   ```r
   join_rapm_to_roster <- function(rost, rapm) { ... }
   ```
   Signature: takes the roster cache and RAPM cache data frames, returns a data frame keyed by
   `(team_abbreviation, player identity)` with at least a `total_rapm` column, using the
   `(team full name, normalized last name)` match already proven correct in
   `market_odds_engine.R`. Preserve the collision-safety property (0 duplicate team+lastname
   groups) — re-verify it against the real caches as part of your test, don't just move the code.
   Do not edit `market_odds_engine.R` itself to call this new helper — that's `agent_engine`'s job
   in Wave 2; you're only building the helper.

4. **H-1 foundation.** In `logging_utils.R`'s `.log_format_extra()` (and the DuckDB `extra_json`
   builder), add a redaction pass that scrubs `apiKey`/`api_key`/`token`/`webhook`/`secret` query
   parameters and Discord webhook paths from any string value before it's written to the console,
   text log, or DuckDB log table.

5. **M-7 (logging half only).** Change `.log_write()` to hold one DuckDB connection for the
   process lifetime instead of opening/closing a fresh connection per log line. (The
   `future_lapply`/`future.seed` half of M-7 belongs to `agent_pipeline`, not you.)

6. **L-2 (config.R half only).** Fix `config.R:111`'s stale citation of
   `cache/window_sweep_3_25_results.rds` (real file is `data/window_sweep_3_25_results.csv`, with a
   same-named `.rds` also existing in `cache/` — clarify which is authoritative in the comment) and
   the `config.R:127-134` note that the offseason-method re-benchmark ran at `window_size=13`
   — either re-verify the `"reset"` conclusion still holds at the current `ROLLING_WINDOW_SIZE=12`,
   or explicitly flag in the comment that this has not been rechecked since the value changed.
   (`tools/ml_cv_benchmark.R:62`'s stale comment is `agent_cleanup`'s job, not yours.)

## Test suite — write `tools/test_phase4_foundation.R`, run it, paste real output in your handoff
- Source `config.R`, assert `WNBA_HCA == 2.40`.
- Source `logging_utils.R` and `rapm_join_utils.R`; load the real `active_rosters_cache.rds` and
  `rapm_ratings.rds`; run `join_rapm_to_roster()`; assert every one of the 15 `WNBA_TEAMS` gets
  at least one matched player (mirror the "0 duplicate team+lastname" collision check this session
  already ran once — re-run it, don't trust the old number).
- Call `.log_format_extra()` (or whatever the redaction entry point ends up being) with a fake
  `url = "...apiKey=SUPERSECRET123..."` argument; assert `"SUPERSECRET123"` does **not** appear
  anywhere in the returned/rendered string.
- Assert the new `%||%` handles both a genuinely scalar call and a full NA vector without erroring
  (the exact crash class documented in `CLAUDE.md`).

## Definition of done
`Rscript.exe tools/test_phase4_foundation.R` exits 0 and prints a line for each of the four checks
above with PASS. Append a Handoff Notes entry to `docs/task_assignments_phase4.md` under P4-C with
the real command output (not a paraphrase), then stop — do not start any Wave 2 file.
