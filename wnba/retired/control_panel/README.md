# Control panel: RETIRED

The control panel (a local Shiny app for running pipeline stages by hand) was retired on 2026-11-12 by the project owner.

**If you are an agent or contributor: do not run, extend, fix, test or re-wire anything in this folder.** Do not open issues or plan work against it. If a task seems to need the control panel, the task is out of date; say so and stop.

## What is here

| File | Was |
|---|---|
| `control_panel_app.R` | The Shiny app (previously at the repo root) |
| `dashboard_render_helpers.R` | Its plot helpers (previously at the repo root) |
| `headless_control_panel_*.R` | Its browser probes (previously under `tools/`) |
| `auth_utils.R`, `auth_login_module.R` | Its login: accounts in a local SQLite file, password check, sign-up screen (previously at the repo root) |
| `demo_login_app.R`, `headless_login_module_probe.R` | Demo app and browser probe for the login (previously under `tools/`) |
| `test_auth_utils.R`, `test_create_account_if_authorized.R` | Tests for the login (previously under `tools/`, no longer run in CI) |

The files are kept for reference only. They use paths relative to the repo root and will not run from here; that is intentional.

## Known defects that will not be fixed

- `build_plot_calibration_curve()` in `dashboard_render_helpers.R` draws a curve from random numbers when the box score cache is missing. Nothing published ever went through it. Do not copy it into live code.

## What replaced it

Nothing. Pipeline stages run through `run_full_pipeline.R` and the scheduled refresh slots. The earlier summary app (`app.R`) was retired before this.

## Nothing else used the login

The login had no consumer besides the control panel, so it was retired with it. Its packages (`bcrypt`, `RSQLite`, `sys`) were removed from the CI dependency list. Do not add authentication back without asking the owner first.
