# Spec: Emulate Dunks & Threes visual language in `summary_app.R`

Date: 2026-10-05
Source: spec-interview session, grounded against a deep-research pass that
screenshotted comparable public sports-analytics dashboards (Dunks & Threes,
BBall Index, Cleaning the Glass, ESPN BPI, GoJS/Flourish tournament-bracket
examples) into `C:\tmp\screenshots\`. Dunks & Threes
(https://dunksandthrees.com/) was selected as the primary design reference.

## Why this needed a design discussion

`summary_app.R` (1108 lines, 5 `nav_panel` tabs, plain `shiny` + `bslib` +
`ggplot2` + `png`/`grid` — no `DT`/`reactable`, by deliberate original
design per its own header comment) already shares some DNA with Dunks &
Threes: the `flatly` bootswatch theme's primary color is the same teal
(`#18BC9C`) D&T uses as its accent, and a dark-mode toggle already exists.
Closing the rest of the visual gap required resolving several independent
forks before any code could be written:
- Scope: one tab vs. the whole app.
- Whether to introduce a new table-rendering dependency (`reactable`) for
  real inline bar-in-cell rendering, vs. faking it with CSS on the existing
  dependency-free `tableOutput`.
- Which table columns actually warrant a bar (not all metrics are
  bar-appropriate — "lower is better" metrics like Brier Score/Log-Loss
  need an inverted scale or they read backwards).
- Whether to build the Dunks & Threes "quadrant scatter" (ORTG vs. DRTG,
  team logos as markers) — which turned out to require model-engine
  work, not just a chart: **this repo's rating engine only ever produces a
  single blended Net Rating; no offensive/defensive split exists anywhere
  in the pipeline** (confirmed: zero matches for `ortg`/`drtg`/
  `offensive_rating`/`defensive_rating` in `summary_app.R`, and zero
  matches for `offensive`/`defensive` in `roster_bottom_up_engine.R`).

## Decisions made

1. **Scope: whole app**, not a single tab. All 5 `nav_panel` tabs
   (Season Standings & Projections, Playoff Bracket, Model Calibration &
   Reliability, Model Comparison, Prediction Accuracy Tracker) get the
   same visual language applied in one coordinated effort.
2. **Add `reactable` as a new dependency** for real, interactive,
   sortable inline bar-in-cell table rendering (closest match to D&T's
   look). Rejected alternative: faking bars with `tableOutput` +
   CSS `linear-gradient` backgrounds (dependency-free but static,
   unsortable, fragile to maintain).
3. **All three existing tables get converted** to `reactable`:
   `standings_table`, `model_benchmark_table`, `accuracy_table` — for
   visual consistency, not just the one table with the most obvious bar
   metric.
4. **Bar-cell columns, per table** (confirmed default):
   - `standings_table` (Season Standings tab): bars on `Net_Rating`
     (diverging around 0) and `Win_Pct` (0-1 scale). `Rank`, `Team`,
     `Proj_Wins`, `Proj_Losses`, `Top_Core_Players`, `Logo` stay plain
     cells.
   - `model_benchmark_table` (Model Comparison tab): bars on `Accuracy`
     and `ROC-AUC` (0-1 scale, higher-is-better); **inverted-scale** bars
     on `Brier Score` and `Log-Loss` (lower-is-better metrics — an
     un-inverted bar would visually reward the worst model).
   - `accuracy_table` (Prediction Accuracy Tracker tab): **no bar
     cells** — this is a per-game log (date/teams/predicted/actual/
     correct), not a numeric-metric table. Gets color-coded
     correct/incorrect row highlighting instead.
5. **Quadrant scatter chart (ORTG vs. DRTG) is in scope**, but requires
   new model-engine work first (deriving an offensive/defensive split
   from the existing BPM-based Net Rating calculation in
   `roster_bottom_up_engine.R`, and validating the split reconciles back
   to the existing single Net Rating) — this is real new scope, not a
   visual tweak, so it's split into its own ticket, blocked behind the
   engine-split ticket.
6. **Split into 6 independently-testable tickets**, 5 of which are
   parallelizable (tickets 1-4 are mutually independent; 5 and 6 are
   sequential — 6 is blocked on 5).

## Tickets

### 1. Reactable: Standings table
- **File/location:** `summary_app.R`, `standings_table` (`tableOutput` at
  line ~279, `renderTable` at line ~405), Season Standings & Projections
  tab.
- **Change:** Convert to `reactableOutput`/`renderReactable`. Preserve
  the existing `Logo` column (team logo `<img>` tag via
  `team_logo_img_tag()`) and all existing columns. Add bar-cell
  rendering on `Net_Rating` (diverging, centered at 0 — teams below
  average should render visually distinct from teams above, not just a
  longer/shorter bar in one direction) and `Win_Pct` (0 to 1 scale).
- **Independently testable:** yes — this tab's data/reactive (
  `standings_data`) is untouched; only the output renderer changes.
- **Depends on:** nothing.

### 2. Reactable: Model benchmark table
- **File/location:** `summary_app.R`, `model_benchmark_table`
  (`tableOutput` at line ~357, `renderTable` at line ~920), Model
  Comparison tab.
- **Change:** Convert to `reactable`. Bar cells on `Accuracy` and
  `ROC-AUC` (0-1, higher-is-better, normal-direction bars). Bar cells on
  `Brier Score` and `Log-Loss` using an **inverted** color/fill scale
  (shortest/greenest bar = best/lowest value) so "lower is better" reads
  correctly — do not reuse the same bar direction as Accuracy/ROC-AUC
  for these two columns.
- **Independently testable:** yes — `model_benchmark_data` reactive is
  untouched.
- **Depends on:** nothing.

### 3. Reactable: Accuracy table
- **File/location:** `summary_app.R`, `accuracy_table` (`tableOutput`
  at line ~383, `renderTable` at line ~1048, note the existing
  `outputOptions(output, "accuracy_table", suspendWhenHidden = FALSE)`
  at line ~1074 — **must be preserved** since this table lives inside a
  closed-by-default accordion panel that doesn't trigger Shiny's normal
  visibility re-render hook; losing this setting reproduces the known
  blank-table bug documented inline at that line), Prediction Accuracy
  Tracker tab.
- **Change:** Convert to `reactable`. No bar cells (no numeric metric
  column exists in this table — it's a per-game log). Add conditional
  row/cell styling: `correct == TRUE` rows get a success/teal tint,
  `correct == FALSE` rows get a distinct (red/muted) tint.
- **Independently testable:** yes — `r_accuracy_filtered()` reactive is
  untouched.
- **Depends on:** nothing. (Shares no code with tickets 1/2 beyond both
  adding `library(reactable)` to the top-level `library()` block — flag
  this as a likely merge-conflict point if run truly in parallel, not a
  spec blocker.)

### 4. Typography & chart-minimalism visual pass
- **File/location:** `summary_app.R`, CSS in the `ui` block (currently
  no custom `tags$style` block exists beyond `bs_theme`) plus every
  `renderPlot`'s `theme()`/`theme_minimal()` call across all 5 tabs:
  `standings_chart` (~line 428), `bracket_plot`, `calibration_curve_plot`,
  `window_sweep_plot` (~line 931), `accuracy_cumulative_plot` (~line
  1076), and any other `renderPlot` in the file.
- **Change:**
  - Card headers (`card_header(...)`) styled toward small-caps/
    letter-spacing, consistent with D&T's section-label treatment.
  - Consistent card padding/spacing across all 5 tabs.
  - Reduce gridlines and line weights in every `ggplot` chart — D&T's
    charts use minimal/no gridlines, thin lines, generous whitespace.
    Concretely: fewer/lighter `panel.grid` lines, thinner `geom_line`/
    `geom_point` defaults where not already serving a specific semantic
    purpose (e.g. don't thin out the existing dashed CI/reference lines
    that carry real meaning, like the bankroll drawdown chart's
    high-water-mark line or the calibration curve's diagonal reference —
    those stay as-is functionally, just restyle weight/color to match
    the new minimal palette).
- **Independently testable:** yes — purely visual, no data/reactive
  changes, can be verified tab-by-tab via the existing
  `tools/headless_dashboard_probe.R` pattern (screenshot each tab,
  confirm no `.shiny-output-error`, visually confirm style).
- **Depends on:** nothing. Should land cleanly alongside 1/2/3 (touches
  `theme()` calls and a new top-level CSS block, not the table outputs),
  but as with 1/2/3, flag as a merge-conflict risk if parallel agents
  touch the same file concurrently.

### 5. Offense/Defense rating split (model engine)
- **File/location:** `roster_bottom_up_engine.R` (confirmed: currently
  zero references to `offensive`/`defensive` anywhere in this file —
  the engine only ever produces a single blended Net Rating per team).
- **Change:** Derive separate offensive and defensive rating components
  per team from the existing BPM-based calculation, rather than only the
  single blended value. Must reconcile: the existing single Net Rating
  must remain derivable from (or equal to) the new offensive/defensive
  split (e.g. `Net_Rating == Off_Rating - Def_Rating` or equivalent, per
  however the engine's existing BPM blend is structured) — this is a
  correctness requirement, not optional, since every other tab/ticket
  still depends on the existing single Net Rating being unchanged.
  Expose both new values through whatever cache
  `roster_bottom_up_engine.R` currently writes standings data to (same
  cache file, new columns — do not introduce a second cache file for
  this).
- **Independently testable:** yes — this is a model/data-layer change
  only; testable by validating the reconciliation property above against
  historical data, without touching `summary_app.R` at all.
- **Depends on:** nothing (but ticket 6 depends on this landing first).

### 6. Quadrant scatter chart (ORTG vs. DRTG)
- **File/location:** `summary_app.R` — new panel/card, placement TBD by
  implementer (natural fits: Season Standings tab alongside the existing
  standings chart, or its own new `nav_panel`) using the new
  offensive/defensive columns from ticket 5.
- **Change:** New `ggplot` scatter plot, one point per team, x-axis =
  offensive rating, y-axis = defensive rating, team logos as the scatter
  markers (reuse the existing `png`/`grid` logo-rendering machinery
  already used elsewhere in this file for the `Logo` table column),
  styled consistent with ticket 4's minimalism pass (thin gridlines,
  generous whitespace) — matches D&T's team-stats quadrant chart.
- **Independently testable:** yes, once ticket 5's cache columns exist —
  testable by confirming the chart renders with real data and quadrant
  placement is directionally sane (teams known to be offense-strong
  render right-of-center, etc.).
- **Depends on: Ticket 5.** Cannot start implementation (beyond UI
  scaffolding) until ticket 5's offensive/defensive columns exist in the
  standings cache.

## Explicitly out of scope for this spec
- Any change to `app.R` (the separate "Alpha Terminal" trading-dashboard
  app) — confirmed in `summary_app.R`'s own header comment that it is a
  deliberately separate app with no shared tabs or code path.
- Any change to the underlying prediction models themselves beyond the
  offensive/defensive split in ticket 5 (ticket 5 is a decomposition of
  an existing rating, not a new predictive signal).
