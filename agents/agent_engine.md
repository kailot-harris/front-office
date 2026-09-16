---
name: agent_engine
role: The Pricer
soul: Skeptical of its own model, insists every number trace to a real derivation.
focus: market_odds_engine.R and its downstream tools/ backtests.
wave: 2 (parallel with agent_dashboard, agent_pipeline, agent_props, agent_cleanup)
---

# Agent Brief: The Pricer

`agent_foundation` has already landed `WNBA_HCA` in `config.R`, a hardened `%||%` in
`logging_utils.R`, and `join_rapm_to_roster()` in `rapm_join_utils.R`. Confirm
`tools/test_phase4_foundation.R` passes before you start; if it doesn't, stop and report rather
than building on an unverified foundation.

Read `docs/SECURITY_TECHNICAL_REVIEW.md` findings C-1, H-1, H-4, L-1, M-5, M-6 in full before
editing — each has a real reproduction in that doc; your fix is only done when that exact
reproduction no longer shows the defect.

## Files you may touch
`market_odds_engine.R`, `tools/optimize_hca.R`, `tools/backtest_margin_hyperparams.R`,
`tools/build_calibration_cache.R`. Nothing else — `app.R`'s HCA references belong to
`agent_dashboard`, `roster_bottom_up_engine.R`'s/`playoff_simulator.R`'s belong to `agent_pipeline`.

## Tasks

1. **C-1.** Replace the hardcoded `11.6` at `market_odds_engine.R:420` (`fair_margin <- ... + 11.6 +
   ...`) and `:426` (`hcas[i] <- 11.6`) with `WNBA_HCA`. Update the comment at lines 416-420 so it
   no longer says "(2.40) left unchanged" while adding a different number — it should just say the
   value is read from `config.R::WNBA_HCA`. Update `tools/build_calibration_cache.R:64` and
   `tools/optimize_hca.R:59` to read `WNBA_HCA` instead of restating `2.40`. Update
   `tools/backtest_margin_hyperparams.R:64`'s `HCA_CONST <- 11.6` line to read from `WNBA_HCA`
   instead of enshrining the wrong value.

2. **H-1.** At `market_odds_engine.R:195-213`: stop building `url` with the raw API key
   interpolated in. Either (a) build the URL from a keyless base path and pass the key via
   `httr2::req_url_query()`, logging only the keyless base, or (b) redact before logging:
   `sub("apiKey=[^&]*", "apiKey=***REDACTED***", url)` at the `log_error()` call site. Prefer (a) —
   it also benefits from `agent_foundation`'s logger-level redaction as defense in depth, not as
   the only layer.

3. **H-4.** In `resolve_team_name()` (`market_odds_engine.R:157-178`): require
   `nchar(trimws(s)) >= 3` before attempting any substring match, returning `NA_character_`
   otherwise. Drop the reverse-containment clause `grepl(s, fn, fixed = TRUE)` entirely — keep only
   the forward direction (franchise name found inside input). Return `NA_character_` on no match
   instead of passing the raw input through, and log a `WARN` with the unresolved value. Check the
   one caller at `market_odds_engine.R:383-389` handles an `NA` team name without crashing (it
   already has an `nrow(h_row) > 0` fallback path for unrecognized names — an `NA` should route into
   that same path).

4. **L-1.** In the nickname-matching clause (`market_odds_engine.R:173-174`), vectorize properly:
   `vapply(nick, function(n) grepl(paste0("\\b", n, "\\b"), s), logical(1))` combined with `any()`,
   instead of passing the length-15 `nick` vector directly to `grepl()`'s `pattern` argument.

5. **M-5 (engine half).** `fetch_market_odds()` currently returns the `SYNTHETIC_FALLBACK` fixture
   slate with no provenance marker reaching the caller. Add a `market_data_source` field to its
   return value (`"LIVE_ODDS_API"` or `"SYNTHETIC_FALLBACK"`) per the interface contract in
   `docs/task_assignments_phase4.md` — `agent_props` will consume this in
   `log_todays_predictions()`, you don't need to touch that file.

6. **M-6.** Delete the local `%||%` definition in `market_odds_engine.R:60` now that
   `logging_utils.R` defines the canonical one. Confirm `market_odds_engine.R` sources
   `logging_utils.R` before any `%||%` use (it already does).

## Test suite — write `tools/test_phase4_engine.R`
- Compute implied home-win-probability for two identical teams at the (now-fixed) HCA and
  `WNBA_MARGIN_SIGMA`; assert it falls in `[0.53, 0.60]` (was 0.796 under the bug). This is the
  exact C-1 reproduction from the review, re-run.
- Fuzz `resolve_team_name()` with `""`, `"a"`, `"s"` — assert all three now return
  `NA_character_`, not a team name. Also assert `"Las Vegas Aces"` and other exact matches still
  resolve correctly (no regression).
- Render the redacted log path with a fake `apiKey=SUPERSECRET123` URL; assert the secret does not
  appear in the logged string (same check as Wave 1's test, re-run against your actual call site
  this time, not the helper in isolation).
- `grep -c "%||%" market_odds_engine.R` for a *definition* (not a use) — assert zero local
  redefinitions remain.
- Run `Rscript.exe market_odds_engine.R` standalone against real caches; assert it completes and
  the resulting `hcas` column in its output is `2.40` for every row, not `11.6`.

## Definition of done
`tools/test_phase4_engine.R` passes end to end with real output pasted into your Handoff Notes
entry under P4-A in `docs/task_assignments_phase4.md`. `git diff --stat` (after Phase 0's `git
init`) shows only your four owned files plus your new test script changed.
