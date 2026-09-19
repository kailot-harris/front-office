---
name: headless-ui-regression-sweep
description: Runs the headless dashboard probe after any app.R change and requires visually inspecting a real screenshot, not just trusting an absence of .shiny-output-error or a JS row-count hint, before calling a UI task done. Use after any app.R edit, before reporting a dashboard/UI task complete.
---

# Headless UI Regression Sweep

## Why this exists

This repo has shipped real, silent `app.R` bugs before (an injury-tab `%||%`-on-a-vector crash
that motivated `tools/headless_dashboard_probe.R`'s own creation), and the probe itself once had a
bug — an unscoped `table.dataTable` selector that silently matched whichever tab's table happened
to render first in the DOM instead of the actually-active tab — that only surfaced because a
screenshot was manually inspected rather than trusting the JS row-count check alone
(`docs/HANDOFF.md`, 2026-09-17). This skill makes "verify visually" a forced step, not something
remembered ad hoc.

## When to use

Any `app.R` change, before reporting a dashboard/UI task complete.

## Procedure

1. Run a full, fast, error-only sweep first:
   `Rscript.exe tools/headless_dashboard_probe.R` (full path per CLAUDE.md:
   `C:\Program Files\R\R-4.5.2\bin\Rscript.exe`). This clicks through every tab and reports
   browser console errors.
2. If the edit added/changed a specific tab's content (new table, new reactive, new column), also
   run it scoped with a screenshot:
   `Rscript.exe tools/headless_dashboard_probe.R <tab_value> --screenshot`.
3. Read the saved screenshot at `tools/probe_screenshots/<tab_value>.png` with the Read tool and
   visually confirm real data renders correctly. **Do not treat the JS-reported row-count hint as
   authoritative by itself** — it has a documented reliability gap on at least one DT rendering
   pattern in this app (see `tools/headless_dashboard_probe.R`'s own comment on the visibility-based
   table lookup fix). The header-line check (confirms the right tab's table was found) and the
   screenshot are the trustworthy signals.
4. If a tab was added, removed, or renamed, update the `TAB_VALUES` constant in
   `tools/headless_dashboard_probe.R` itself so the no-argument full sweep keeps covering it.
5. Treat any `.shiny-output-error` element or a browser console `SEVERE`/`error` log line as a hard
   blocker — do not report the UI task done with either present.

## Known pitfalls

- A JS selector scoped only by CSS class (e.g. bare `.active`) is not reliable in this app — Shiny
  and bslib keep every tab's DOM mounted, just hidden, and this app's tab panes don't reliably
  carry an `.active` class either. Use a visibility check
  (`.filter(t => t.offsetParent !== null)`) if you touch the probe's table-lookup logic again.
- A clean console-error sweep is necessary but not sufficient — always follow with a real
  screenshot read for any tab whose content actually changed.
