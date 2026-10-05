# Control Panel Network Access & Password Setup — WNBA Analytics

## What this covers

`control_panel_app.R` (GitHub issue #43's tree) is network-accessible, not localhost-only, but
is gated behind a **placeholder single shared password** (`CONTROL_PANEL_PASSWORD`) until the
real multi-user auth system (issue #44, slices #51/#52/#53, wired in by #54) replaces it. The
app **refuses to start** on a non-localhost host if that password is unset — this is
intentional fail-safe behavior, not a bug, matching this repo's "no secrets hardcoded, never
silently run unprotected" convention (see `CLAUDE.md`).

## Steps a human needs to take

1. Choose a password. This is a single shared secret for anyone who can run a pipeline stage
   through the control panel — treat it like a shared admin password, not a per-user login.
2. Set it as a **persistent Windows user environment variable** (survives reboots and new
   terminal sessions, no code changes needed anywhere in this repo):

   ```
   setx CONTROL_PANEL_PASSWORD "PASTE_YOUR_CHOSEN_PASSWORD_HERE"
   ```

   Note: `setx` only affects **new** terminal/process sessions started after the command runs —
   close and reopen any open terminal before expecting the variable to be visible.

3. Verify it worked, in a **freshly opened** terminal:

   ```
   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" -e "cat(nchar(Sys.getenv('CONTROL_PANEL_PASSWORD')))"
   ```

   This should print a number greater than 0 (not `0`).

4. Launch the app on a network-accessible host (adjust the port as needed):

   ```r
   shiny::runApp("control_panel_app.R", host = "0.0.0.0", port = 7700)
   ```

   If `CONTROL_PANEL_PASSWORD` is unset at this point, the app will refuse to start and print
   an error naming the host it was asked to bind to — this is the fail-safe check working as
   designed, not a crash to work around.

5. From another device on the network, visit `http://<this-machine's-LAN-IP>:7700`. You should
   see a password prompt before any pipeline-stage controls are visible — the real control
   panel UI is rendered entirely server-side, only after a correct password submission (it is
   not merely hidden with CSS; nothing it contains exists in the page before that point).

## What stays unaffected

- Launching `control_panel_app.R` the normal way (`shiny::runApp("control_panel_app.R")` with
  no `host` argument, which defaults to `127.0.0.1`) works exactly as before, password or not
  — this gate only blocks **non-localhost** launches without a password. Localhost-only use
  (the default for issues #46-#49) is never blocked.
- `run_full_pipeline.R`'s own scheduled run (`schedule_daily.bat`) does not go through this
  app at all and is completely unaffected by this setting.

## This gate is temporary

Once issue #54 wires `auth_login_module.R` (issue #53) into `control_panel_app.R`, this
single-password placeholder is removed entirely in favor of real per-account signup/login.
Do not build anything else on top of `CONTROL_PANEL_PASSWORD` — it is not meant to outlive #54.
