# ==============================================================================
# tools/test_create_account_if_authorized.R
# Standalone test/verification script for create_account_if_authorized() in
# auth_utils.R (GitHub issue #52, Slice 2 of #44).
#
# Per CLAUDE.md's folder-layout convention, this tools/ script setwd()s to the
# absolute project root first, then source()s siblings (config.R, auth_utils.R)
# by bare filename, so it runs correctly regardless of invocation cwd.
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" tools\test_create_account_if_authorized.R
# Exits 0 on success (all assertions pass), exits 1 (via stop()) on any
# assertion failure.
# ==============================================================================

PROJECT_ROOT <- tryCatch(here::here(), error = function(e) NA_character_)
if (is.na(PROJECT_ROOT) || !file.exists(file.path(PROJECT_ROOT, "config.R"))) {
  this_file <- normalizePath(sub("^--file=", "", commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))]))
  PROJECT_ROOT <- dirname(dirname(this_file))
}
setwd(PROJECT_ROOT)

source("config.R")
source("auth_utils.R")

failures <- character(0)

check <- function(desc, cond) {
  status <- if (isTRUE(cond)) "PASS" else "FAIL"
  cat(sprintf("[%s] %s\n", status, desc))
  if (!isTRUE(cond)) failures[[length(failures) + 1]] <<- desc
}

# ------------------------------------------------------------------------------
# Fresh auth DB for a clean, repeatable test run, isolated from any other
# human/test session's cache/auth_users.sqlite.
# ------------------------------------------------------------------------------
if (file.exists(AUTH_DB_PATH)) {
  file.remove(AUTH_DB_PATH)
}

# Helper: direct raw table read, bypassing create_user()/verify_user() so we
# are checking ground truth in the SQLite file, not trusting return values.
raw_user_rows <- function(username) {
  con <- DBI::dbConnect(RSQLite::SQLite(), dbname = AUTH_DB_PATH)
  on.exit(DBI::dbDisconnect(con))
  if (!DBI::dbExistsTable(con, "users")) {
    return(data.frame())
  }
  DBI::dbGetQuery(con, "SELECT * FROM users WHERE username = ?;", params = list(username))
}

THE_SECRET_KEY <- "s3cret-signup-key-9f2c7a"

# ------------------------------------------------------------------------------
# Criterion 3: gate unset/empty -> rejected unconditionally, even if the
# caller's key_phrase happens to be "" (matching the unset default).
# Run this FIRST, before the env var is ever set in this process.
# ------------------------------------------------------------------------------
Sys.unsetenv("CONTROL_PANEL_SIGNUP_KEY")
check(
  "gate unset: Sys.getenv(...) resolves to empty string as a precondition",
  identical(Sys.getenv("CONTROL_PANEL_SIGNUP_KEY", ""), "")
)

user_unset_empty <- "sig2_user_unset_gate_empty_match"
result_unset_empty <- create_account_if_authorized(user_unset_empty, "SomePassword!1", "")
check(
  "gate unset + key_phrase='' (matches unset default) -> returns FALSE",
  identical(result_unset_empty, FALSE)
)
check(
  "gate unset + key_phrase='' -> no row created in users table",
  nrow(raw_user_rows(user_unset_empty)) == 0
)

user_unset_nonempty <- "sig2_user_unset_gate_nonempty"
result_unset_nonempty <- create_account_if_authorized(user_unset_nonempty, "SomePassword!1", "anything-at-all")
check(
  "gate unset + non-empty key_phrase -> returns FALSE",
  identical(result_unset_nonempty, FALSE)
)
check(
  "gate unset + non-empty key_phrase -> no row created in users table",
  nrow(raw_user_rows(user_unset_nonempty)) == 0
)

# ------------------------------------------------------------------------------
# Now set the real gate for the remaining criteria.
# ------------------------------------------------------------------------------
Sys.setenv(CONTROL_PANEL_SIGNUP_KEY = THE_SECRET_KEY)

# --- Criterion 1: correct key-phrase succeeds, verifiable via verify_user() --
good_user <- "sig2_good_user"
good_pass <- "Correct-Horse-Battery-Staple-99!"
result_good <- create_account_if_authorized(good_user, good_pass, THE_SECRET_KEY)
check("correct key_phrase -> create_account_if_authorized() returns TRUE", identical(result_good, TRUE))
check("correct key_phrase -> row created in users table", nrow(raw_user_rows(good_user)) == 1)
check("correct key_phrase -> verify_user() returns TRUE afterward", isTRUE(verify_user(good_user, good_pass)))

# --- Criterion 2: wrong key-phrase rejected, no row created ------------------
wrong_key_user <- "sig2_wrong_key_user"
result_wrong_key <- create_account_if_authorized(wrong_key_user, "WrongKeyPass!1", "definitely-not-the-key")
check("wrong key_phrase -> returns FALSE", identical(result_wrong_key, FALSE))
check("wrong key_phrase -> no row created in users table", nrow(raw_user_rows(wrong_key_user)) == 0)

missing_key_user <- "sig2_missing_key_user"
result_missing_key <- create_account_if_authorized(missing_key_user, "MissingKeyPass!1", "")
check("empty key_phrase against a real gate -> returns FALSE", identical(result_missing_key, FALSE))
check("empty key_phrase against a real gate -> no row created", nrow(raw_user_rows(missing_key_user)) == 0)

# ------------------------------------------------------------------------------
# Criterion 4: the key-phrase value never appears in any message/warning/
# error produced by create_account_if_authorized(), on a rejected call.
# Capture everything withCallingHandlers() can see, plus tryCatch for a hard
# error, across both a wrong-key call and an unset-gate call.
# ------------------------------------------------------------------------------
capture_all_text <- function(expr) {
  captured <- character(0)
  result <- tryCatch(
    withCallingHandlers(
      expr,
      message = function(m) { captured <<- c(captured, conditionMessage(m)); invokeRestart("muffleMessage") },
      warning = function(w) { captured <<- c(captured, conditionMessage(w)); invokeRestart("muffleWarning") }
    ),
    error = function(e) { captured <<- c(captured, conditionMessage(e)); NULL }
  )
  captured
}

leak_probe_key <- "LEAK-PROBE-super-secret-phrase-XYZ"
Sys.setenv(CONTROL_PANEL_SIGNUP_KEY = leak_probe_key)

msgs_wrong_key <- capture_all_text(
  create_account_if_authorized("sig2_leak_probe_user_a", "LeakProbePass!1", "wrong-guess-not-the-key")
)
check(
  "wrong-key rejected call: no captured message/warning/error text at all (clean reject)",
  length(msgs_wrong_key) == 0
)
check(
  "wrong-key rejected call: key-phrase string does not appear in any captured text",
  !any(grepl(leak_probe_key, msgs_wrong_key, fixed = TRUE))
)

Sys.unsetenv("CONTROL_PANEL_SIGNUP_KEY")
msgs_unset_gate <- capture_all_text(
  create_account_if_authorized("sig2_leak_probe_user_b", "LeakProbePass!1", leak_probe_key)
)
check(
  "unset-gate rejected call: key-phrase string does not appear in any captured text",
  !any(grepl(leak_probe_key, msgs_unset_gate, fixed = TRUE))
)

# Also sanity-check that the DB file on disk (as raw bytes) doesn't contain
# the leak-probe key -- confirms create_user() was never reached on any
# rejected path in this block (would-be indirect leak via a stored row).
# grepRaw() does a byte-pattern search on the raw vector directly, avoiding
# any text-encoding issues from treating a binary SQLite file as character
# data (e.g. via readLines()).
db_bytes <- readBin(AUTH_DB_PATH, what = "raw", n = file.info(AUTH_DB_PATH)$size)
check(
  "auth_users.sqlite file contents do not contain the leak-probe key-phrase",
  length(grepRaw(leak_probe_key, db_bytes, fixed = TRUE, all = TRUE)) == 0
)

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
cat("\n---\n")
if (length(failures) == 0) {
  cat("ALL CHECKS PASSED\n")
  quit(status = 0)
} else {
  cat(sprintf("%d CHECK(S) FAILED:\n", length(failures)))
  for (f in failures) cat(" -", f, "\n")
  stop("test_create_account_if_authorized.R: one or more assertions failed.")
}
