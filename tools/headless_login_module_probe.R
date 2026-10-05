# Headless browser QA for auth_login_module.R / tools/demo_login_app.R (GitHub issue #53),
# using shinytest2 (chromote-backed, drives real Chrome) -- same pattern as
# tools/headless_dashboard_probe.R and tools/headless_control_panel_probe.R (NOT_CRAN env var,
# CHROMOTE_CHROME, AppDriver against the real Chrome install). Throwaway QA script for this
# ticket -- not part of run_full_pipeline.R's DAG, does not need to be production-grade.
#
# Verifies, in order, the five success criteria from the issue #53 brief:
#   1. Pre-login, the protected content's DOM element is absent AND its server-side render body
#      never executed (protected_render_count side-effect counter stays unreachable/absent).
#   2. A valid username/password (pre-seeded directly via create_user(), same mechanism
#      verify_user() reads) logs in and reveals the protected content.
#   3. A bad username and a bad password both produce the exact same generic error text.
#   4. A second, independent AppDriver session against the same running app starts logged out
#      (no persisted "remember me" state).
#   5. The login<->signup toggle works, and a successful signup (correct key-phrase) can then
#      log in via the same path as criterion 2.
#
# USAGE: Rscript.exe tools/headless_login_module_probe.R

Sys.setenv(CHROMOTE_CHROME = Sys.getenv(
  "CHROMOTE_CHROME",
  "C:/Program Files/Google/Chrome/Application/chrome.exe"
))
if (Sys.getenv("NOT_CRAN") == "") Sys.setenv(NOT_CRAN = "true")

script_dir <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) NA)
project_dir <- if (!is.na(script_dir)) normalizePath(file.path(script_dir, "..")) else getwd()
setwd(project_dir)

suppressMessages(library(shinytest2))

source("config.R")
source("auth_utils.R")

pass <- function(msg) cat(sprintf("[PASS] %s\n", msg))
fail <- function(msg) { cat(sprintf("[FAIL] %s\n", msg)); failures <<- c(failures, msg) }
failures <- character(0)

# ------------------------------------------------------------------------------------------
# Fresh auth DB for a clean, repeatable probe run, isolated from any other human/test
# session's cache/auth_users.sqlite (same convention as tools/test_*.R scripts).
# ------------------------------------------------------------------------------------------
if (file.exists(AUTH_DB_PATH)) file.remove(AUTH_DB_PATH)

PROBE_SIGNUP_KEY <- "probe-login-module-key-7f3a1c"

# Pre-seed a known-good user directly via create_user() (bypassing the UI) for criterion 2/3 --
# the signup-flow-created user is a SEPARATE account used only for criterion 5.
SEED_USER <- "probe_seed_user"
SEED_PASS <- "Correct-Probe-Password-1!"
create_user(SEED_USER, SEED_PASS)

# shinytest2's AppDriver always looks for a literal ./app.R inside app_dir -- point it at a
# throwaway wrapper dir that sources tools/demo_login_app.R, matching the wrapper_dir pattern
# used in tools/headless_control_panel_probe.R. The wrapper also sets
# CONTROL_PANEL_SIGNUP_KEY *inside the spawned app process* (not just this probe's own
# process) so criterion 5's signup-via-UI path has a real gate to pass against. This is a
# throwaway test fixture key, not a real secret -- it never leaves this probe script.
wrapper_dir <- file.path(tempdir(), "login_module_probe_app")
dir.create(wrapper_dir, showWarnings = FALSE)
writeLines(
  sprintf(
    'Sys.setenv(CONTROL_PANEL_SIGNUP_KEY = %s)\nsetwd(%s)\nsource("tools/demo_login_app.R")$value',
    shQuote(PROBE_SIGNUP_KEY, type = "cmd"),
    shQuote(project_dir, type = "cmd")
  ),
  file.path(wrapper_dir, "app.R")
)

new_app <- function() {
  AppDriver$new(
    app_dir = wrapper_dir, name = "wnba-login-module-probe",
    height = 900, width = 1200, load_timeout = 60000, timeout = 60000,
    shiny_args = list(port = 7659)
  )
}

app <- new_app()
app$wait_for_idle(duration = 500, timeout = 60000)

# ------------------------------------------------------------------------------------------
# Criterion 1: pre-login, protected content is absent from the DOM AND its render body never
# ran (protected_counter_probe element -- nested inside the gated renderUI -- does not exist).
# ------------------------------------------------------------------------------------------
protected_region_html_pre <- app$get_js('document.getElementById("protected_region").innerHTML;')
counter_probe_exists_pre <- app$get_js('document.getElementById("protected_counter_probe") !== null;')
cat(sprintf("Pre-login protected_region innerHTML: %s\n", trimws(protected_region_html_pre)))
cat(sprintf("Pre-login protected_counter_probe element exists: %s\n", counter_probe_exists_pre))

# Shiny's uiOutput("protected_ui") container div itself always exists in the DOM once
# rendered (e.g. `<div id="protected_ui" ...></div>`) -- renderUI() returning NULL empties
# its CHILDREN, not the wrapper element itself. Demanding fully-empty innerHTML on the
# parent #protected_region was too strict; the actual proof the gated body never ran is that
# neither the counter element nor the "Secret dashboard" text it would render exists.
no_secret_content_pre <- !grepl("Secret dashboard", protected_region_html_pre, fixed = TRUE)
if (no_secret_content_pre && isFALSE(counter_probe_exists_pre)) {
  pass("Criterion 1: protected content absent from DOM pre-login and its render body's output element never materialized (never ran).")
} else {
  fail(sprintf(
    "Criterion 1: expected no protected content and no counter-probe element pre-login, got html='%s' counter_exists=%s.",
    protected_region_html_pre, counter_probe_exists_pre
  ))
}

# ------------------------------------------------------------------------------------------
# Criterion 3: bad username and bad password both give the identical generic error text.
# Run BEFORE the successful login below so the login form is still showing.
# ------------------------------------------------------------------------------------------
login_ns <- "auth-"          # module id "auth" -> NS() prefix "auth-"
module_root_sel <- sprintf("#%slogin_module_root", login_ns)

# Helper: set a namespaced module input by exact id without relying on tidy-eval splicing in
# set_inputs()'s dots (not guaranteed supported for dynamic names) -- build the named list and
# dispatch via do.call() instead.
set_module_input <- function(driver, field, value) {
  args <- setNames(list(value), paste0(login_ns, field))
  # shinytest2's AppDriver$set_inputs() takes the priority override as the trailing-underscore
  # parameter `priority_` (matching its wait_/timeout_ convention) -- `.priority` is not a
  # recognized parameter and gets treated as a literal (nonexistent) Shiny input id to set,
  # producing a spurious "Unable to find input binding for element with id .priority" error
  # on every call (harmless to the real field value, but noisy and worth fixing).
  args$priority_ <- "event"
  # Setting a plain text/password field doesn't itself trigger any output change (only the
  # subsequent login_submit/signup_submit click() does) -- set_inputs()'s default wait_ = TRUE
  # otherwise burns a full 60s timeout waiting for a reactive flush that was never coming,
  # repeated per field, which is what actually exhausted this probe's wall-clock budget and
  # let concurrent chrome instances pile up into a real memory-pressure kill.
  args$wait_ <- FALSE
  do.call(driver$set_inputs, args)
}

set_module_input(app, "login_username", "no_such_user_at_all")
set_module_input(app, "login_password", "whatever-password-1")
app$click(paste0(login_ns, "login_submit"))
app$wait_for_idle(duration = 500, timeout = 30000)
err_text_1 <- app$get_html(module_root_sel)

set_module_input(app, "login_username", SEED_USER)
set_module_input(app, "login_password", "definitely-the-wrong-password")
app$click(paste0(login_ns, "login_submit"))
app$wait_for_idle(duration = 500, timeout = 30000)
err_text_2 <- app$get_html(module_root_sel)

GENERIC_MSG <- "Incorrect username or password."
bad_user_has_msg <- grepl(GENERIC_MSG, err_text_1, fixed = TRUE)
bad_pass_has_msg <- grepl(GENERIC_MSG, err_text_2, fixed = TRUE)
cat(sprintf("Bad-username attempt shows generic message: %s\n", bad_user_has_msg))
cat(sprintf("Bad-password attempt shows generic message: %s\n", bad_pass_has_msg))

if (bad_user_has_msg && bad_pass_has_msg) {
  pass("Criterion 3: bad username and bad password both surfaced the identical generic error message.")
} else {
  fail(sprintf(
    "Criterion 3: expected generic message '%s' on both paths; bad_user=%s bad_pass=%s.",
    GENERIC_MSG, bad_user_has_msg, bad_pass_has_msg
  ))
}

# ------------------------------------------------------------------------------------------
# Criterion 2: valid credentials log in and reveal the protected content.
# ------------------------------------------------------------------------------------------
set_module_input(app, "login_username", SEED_USER)
set_module_input(app, "login_password", SEED_PASS)
# A successful login re-renders TWO outputs at once (this module's own form_ui collapsing to
# empty, plus the host app's protected_ui populating) rather than the single in-place text
# swap the two failed-login clicks above produced -- give this one a longer ceiling in case
# that larger flush is what's pushing it past the default wait under current machine load.
app$click(paste0(login_ns, "login_submit"), timeout_ = 90000)
app$wait_for_idle(duration = 500, timeout = 30000)

protected_region_html_post <- app$get_js('document.getElementById("protected_region").innerHTML;')
counter_text_post <- tryCatch(app$get_text("#protected_counter_probe"), error = function(e) NA)
cat(sprintf("Post-login protected_region non-empty: %s\n", nchar(trimws(protected_region_html_post)) > 0))
cat(sprintf("Post-login protected_counter_probe text: %s\n", counter_text_post))

if (nchar(trimws(protected_region_html_post)) > 0 && identical(trimws(counter_text_post), "1")) {
  pass("Criterion 2: valid login revealed the protected content, and its render body executed exactly once (counter == 1).")
} else {
  fail(sprintf(
    "Criterion 2: expected non-empty protected content with counter '1' after valid login, got html_nonempty=%s counter='%s'.",
    nchar(trimws(protected_region_html_post)) > 0, counter_text_post
  ))
}

app$stop()

# ------------------------------------------------------------------------------------------
# Criterion 4: a second, independent AppDriver session starts logged out.
# ------------------------------------------------------------------------------------------
app2 <- new_app()
app2$wait_for_idle(duration = 500, timeout = 60000)

protected_region_html_fresh <- app2$get_js('document.getElementById("protected_region").innerHTML;')
cat(sprintf("Fresh second-session protected_region innerHTML: %s\n", trimws(protected_region_html_fresh)))

if (identical(trimws(protected_region_html_fresh), "")) {
  pass("Criterion 4: a brand-new session/AppDriver instance starts logged out (no persisted state carried over).")
} else {
  fail("Criterion 4: a brand-new session/AppDriver instance appears to already be logged in -- persisted state leaked across sessions.")
}

# ------------------------------------------------------------------------------------------
# Criterion 5: login<->signup toggle works; a successful signup (correct key-phrase) can then
# log in via criterion 2's same path.
# ------------------------------------------------------------------------------------------
app2$click(paste0(login_ns, "go_to_signup"))
app2$wait_for_idle(duration = 500, timeout = 30000)
signup_form_visible <- app2$get_js(sprintf('document.getElementById("%s") !== null;', paste0(login_ns, "signup_submit")))
cat(sprintf("Signup form visible after toggle click: %s\n", signup_form_visible))
if (!isTRUE(signup_form_visible)) {
  fail("Criterion 5: clicking the signup toggle did not reveal the signup form -- aborting rest of criterion 5.")
} else {
  pass("Criterion 5a: the login<->signup toggle link reveals the signup form.")

  NEW_USER <- "probe_signup_created_user"
  NEW_PASS <- "Brand-New-Probe-Password-2!"
  set_module_input(app2, "signup_username", NEW_USER)
  set_module_input(app2, "signup_password", NEW_PASS)
  set_module_input(app2, "signup_key_phrase", PROBE_SIGNUP_KEY)
  app2$click(paste0(login_ns, "signup_submit"))
  app2$wait_for_idle(duration = 500, timeout = 30000)

  # Confirm the account now exists on the shared auth DB (ground truth, not just UI text).
  account_exists <- isTRUE(verify_user(NEW_USER, NEW_PASS))
  cat(sprintf("New account verify_user() check after signup: %s\n", account_exists))

  login_form_showing_again <- app2$get_js(sprintf('document.getElementById("%s") !== null;', paste0(login_ns, "login_submit")))
  cat(sprintf("Login form showing again after successful signup: %s\n", login_form_showing_again))

  if (account_exists) {
    pass("Criterion 5b: signup through the UI with a correct key-phrase created a real account (verify_user() confirms).")
  } else {
    fail("Criterion 5b: signup through the UI did not result in a verifiable account.")
  }

  if (isTRUE(login_form_showing_again)) {
    set_module_input(app2, "login_username", NEW_USER)
    set_module_input(app2, "login_password", NEW_PASS)
    app2$click(paste0(login_ns, "login_submit"))
    app2$wait_for_idle(duration = 500, timeout = 30000)

    protected_region_after_signup_login <- app2$get_js('document.getElementById("protected_region").innerHTML;')
    cat(sprintf("protected_region after logging in with the newly-signed-up account: %s\n",
                nchar(trimws(protected_region_after_signup_login)) > 0))
    if (nchar(trimws(protected_region_after_signup_login)) > 0) {
      pass("Criterion 5c: the newly-signed-up account successfully logged in and revealed protected content.")
    } else {
      fail("Criterion 5c: the newly-signed-up account could not log in / protected content did not appear.")
    }
  } else {
    fail("Criterion 5c: login form did not reappear after signup, could not test logging in with the new account.")
  }
}

app2$stop()

cat(sprintf("\n%d failure(s) out of this probe run.\n", length(failures)))
if (length(failures) > 0) {
  cat("Failures:\n")
  for (f in failures) cat(sprintf(" - %s\n", f))
  quit(status = 1)
} else {
  cat("ALL CRITERIA PASSED.\n")
  quit(status = 0)
}
