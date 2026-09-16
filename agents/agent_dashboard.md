---
name: agent_dashboard
role: The Front Window
soul: Distrustful of any number the UI shows without a visible provenance label.
focus: app.R only.
wave: 2 (parallel with agent_engine, agent_pipeline, agent_props, agent_cleanup)
---

# Agent Brief: The Front Window

You own exactly one file: `app.R`. Confirm `tools/test_phase4_foundation.R` (from
`agent_foundation`, Wave 1) passes before you start.

Read `docs/SECURITY_TECHNICAL_REVIEW.md` findings C-1 (app.R refs), C-3, H-3, M-3, M-6, M-8, L-6 in
full before editing. Also read `docs/task_assignments_phase4.md`'s "Interface contracts" section —
you depend on an `is_synthetic` column that `agent_props` adds to `prediction_accuracy_log.rds` in
this same wave, and on `agent_pipeline` switching `Win_Pct` to a numeric proportion. Build against
the contracted names/types; do not wait for their code, and do not assume the old formats survive
this wave.

## Files you may touch
`app.R` only.

## Tasks

1. **C-1.** Replace the hardcoded HCA literals at `app.R:270,1123` with `WNBA_HCA` (source
   `config.R` if not already at the top of `app.R`).

2. **C-3.** In the Tab 8 reactive `r_diagnostics_df()` (`app.R:1175-1206`), filter
   `prediction_accuracy_log.rds` on `status == "RESOLVED" & !is_synthetic` (per the interface
   contract — `is_synthetic` will exist on the schema by the time you test this, written by
   `agent_props`). Add a visible "N real resolved predictions" count to the tab so an empty real
   sample renders as an honest small/zero number rather than silently falling back to synthetic
   rows.

3. **H-3.** Fix `app.R:1184`'s `box_path <- "cache/box_scores_cache.rds"` to use the `CACHE_TEAM_BOX`
   constant (already sourced from `config.R` at `app.R:57-58`) instead of a bare literal pointed at
   the wrong (pre-tidy-up) directory. Fix the `select()` at `app.R:1197` to use the real column names
   `team_score`/`opponent_team_score` instead of `score`/`opponent_score`. Change the value boxes
   (`app.R:1210-1213`) to render `"—"` rather than `0.0` when the diagnostics data frame is `NULL` —
   a missing-data state must never look identical to a perfect-model reading.

4. **M-3.** Replace `app.R:1300-1301`'s `grepl(input$props_search_player, player, ignore.case =
   TRUE)` with `stringr::str_detect(player, stringr::fixed(input$props_search_player, ignore_case =
   TRUE))`. Do not use `fixed = TRUE` on `grepl()` directly — it silently drops `ignore.case`
   (verified in the review; re-verify yourself before you ship it).

5. **M-6.** Delete the local `%||%` definition at `app.R:50` now that `logging_utils.R` defines the
   canonical hardened one. Confirm `app.R` sources `logging_utils.R` (it should already, directly or
   transitively) before this use appears.

6. **M-8.** `roster_bottom_up_engine.R` (owned by `agent_pipeline` this wave) will switch
   `Win_Pct` to a numeric proportion. Update every `app.R` read of `Win_Pct` to format it at display
   time with `scales::percent()` rather than expecting a pre-formatted string.

7. **L-6.** Change `app.R:444-447`'s dual-path read of `latest_player_props.rds` (`data/` then
   fallback `cache/`) to read the single canonical `CACHE_PLAYER_PROPS` constant from `config.R`,
   matching what `agent_props` will make the sole write target this wave.

## Test suite — write `tools/test_phase4_dashboard.R`
Reuse the existing headless probe pattern from `tools/headless_dashboard_probe.R`
(`Sys.setenv(NOT_CRAN = "true")` before creating an `AppDriver`, per `CLAUDE.md`):
- Click through all tabs; assert zero browser console errors (same bar the existing probe uses).
- On Tab 8: temporarily rename `data/box_scores_cache.rds` (restore it after), reload the tab,
  assert the MAE/RMSE value boxes show `"—"` not `"0"`.
- On the Props tab: type `"("` into the search box one character at a time (simulating natural
  typing); assert the tab does not enter Shiny's error state.
- Assert `grep -c "%||%" app.R` for a definition returns 0.
- Assert a `Win_Pct` value renders as e.g. `"79.3%"` in the standings tab even though the
  underlying cache column is now numeric `0.793`.

## Definition of done
`tools/test_phase4_dashboard.R` passes with real captured output (screenshots or console-error
counts, not just "looked fine") pasted into your Handoff Notes entry under P4-B in
`docs/task_assignments_phase4.md`. `git diff --stat` shows only `app.R` plus your new test script
changed.
