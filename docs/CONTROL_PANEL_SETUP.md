# Control Panel Network Access & Auth Setup — WNBA Analytics

## What this covers

`control_panel_app.R` (GitHub issue #43's tree) is network-accessible, not localhost-only, and
gated behind **real multi-user login** (issue #44, slices #51/#52/#53, wired in by #54):
`auth_utils.R`'s SQLite-backed, bcrypt-hashed user store, mounted via `auth_login_module.R`'s
`mod_login_ui()`/`mod_login_server()`. The login/signup form is always visible; the real
control-panel content (stage picker, staleness preview, run control, captured output) is
rendered entirely server-side only after a successful login — it does not exist in the page at
all pre-auth, not merely hidden with CSS.

**#50's old placeholder single shared-password gate (`CONTROL_PANEL_PASSWORD`) is fully dead.**
There is no reference to it anywhere in `control_panel_app.R` — do not set it, it does nothing.

## Steps a human needs to take

1. Choose a signup key-phrase — a shared secret that gates who is *allowed to create an
   account* (not a per-account password). Set it as a **persistent Windows user environment
   variable** (survives reboots and new terminal sessions, no code changes needed anywhere in
   this repo):

   ```
   setx CONTROL_PANEL_SIGNUP_KEY "PASTE_YOUR_CHOSEN_KEY_PHRASE_HERE"
   ```

   Note: `setx` only affects **new** terminal/process sessions started after the command runs —
   close and reopen any open terminal (and restart R/the Shiny process) before expecting the
   variable to be visible.

2. Verify it worked, in a **freshly opened** terminal:

   ```
   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" -e "cat(nchar(Sys.getenv('CONTROL_PANEL_SIGNUP_KEY')))"
   ```

   This should print a number greater than 0 (not `0`).

3. Launch the app on a network-accessible host (adjust the port as needed):

   ```r
   shiny::runApp("control_panel_app.R", host = "0.0.0.0", port = 7700)
   ```

4. From another device on the network, visit `http://<this-machine's-LAN-IP>:7700`. Use the
   "Need an account? Sign up" link, enter a username/password plus the signup key-phrase from
   step 1, then log in with that new account. The pipeline-stage controls only appear after a
   successful login.

5. For a second person to get their own account, they need the same `CONTROL_PANEL_SIGNUP_KEY`
   value — share it the way you'd share any admin-only secret (not committed to the repo, not
   posted anywhere public). Once an account exists, that person logs in with their own
   username/password going forward; they do not need the signup key-phrase again.

## Session behavior

Logins are **not persisted** across browser restarts (no "remember me" cookie) — a fresh login
is required each new browser session, and a same-tab page refresh is treated identically to a
brand-new session (see `auth_login_module.R`'s header comment for why). This is intentional,
not a bug to work around.

## What stays unaffected

- Launching `control_panel_app.R` the normal way (`shiny::runApp("control_panel_app.R")` with
  no `host` argument, which defaults to `127.0.0.1`) still requires logging in — the login wall
  applies regardless of host, it just matters more once the app is network-reachable.
- `run_full_pipeline.R`'s own scheduled run (`schedule_daily.bat`) does not go through this
  app at all and is completely unaffected by any of this.
- `cache/auth_users.sqlite` (the user store) is fully decoupled from the pipeline's own
  `logs/analytics.duckdb` — nothing here touches pipeline data, and nothing in the pipeline
  touches this file.
