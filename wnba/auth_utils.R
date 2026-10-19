# ==============================================================================
# WNBA Analytics - Auth Utilities (Slice 1 of issue #44, GitHub issue #51)
# Path: <project root>/auth_utils.R
#
# Standalone, SQLite-backed, bcrypt-hashed user store. Usable directly from an R
# console with no UI (that comes in a later slice: #52/#53). Fully decoupled from
# the pipeline's own DuckDB file (logs/analytics.duckdb) -- this module never
# touches that file.
#
# Hashing package: `bcrypt` (not `sodium`). Chosen because its API
# (bcrypt::hashpw() / bcrypt::checkpw()) is a direct, minimal wrapper around
# bcrypt hashing/verification with no additional key-management surface, which
# keeps this slice's scope tight. `sodium` is a general crypto library (secret
# boxes, signing, etc.) and would pull in capability this slice doesn't need.
#
# Per CLAUDE.md: constants (CACHE_DIR) are read from config.R, never hardcoded;
# no secrets are hardcoded anywhere in this file.
# ==============================================================================

if (!requireNamespace("RSQLite", quietly = TRUE)) {
  stop("Package 'RSQLite' is required by auth_utils.R. Install it with renv::install('RSQLite').")
}
if (!requireNamespace("bcrypt", quietly = TRUE)) {
  stop("Package 'bcrypt' is required by auth_utils.R. Install it with renv::install('bcrypt').")
}
if (!requireNamespace("DBI", quietly = TRUE)) {
  stop("Package 'DBI' is required by auth_utils.R. Install it with renv::install('DBI').")
}

# config.R defines CACHE_DIR (and creates it if absent) via here::here(), so the
# auth DB path is portable across machines/checkouts just like every other cache
# path in this repo. Guard the source() so re-sourcing auth_utils.R repeatedly
# (e.g. from a test script) doesn't re-run config.R's side effects redundantly,
# but still works standalone if CACHE_DIR isn't already in scope.
if (!exists("CACHE_DIR", inherits = TRUE)) {
  source("config.R")
}

# Deliberately a dedicated SQLite file, NOT logs/analytics.duckdb -- this user
# store must stay fully decoupled from the pipeline's own analytics DB.
AUTH_DB_PATH <- file.path(CACHE_DIR, "auth_users.sqlite")

# ------------------------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------------------------

# Opens a connection to the auth SQLite DB, creating the `users` table if it
# does not already exist. Busy timeout is set so near-simultaneous writers
# (e.g. two Rscript processes calling create_user() back-to-back) block and
# retry briefly against SQLite's file lock instead of immediately erroring out
# with "database is locked".
.auth_db_connect <- function() {
  con <- DBI::dbConnect(RSQLite::SQLite(), dbname = AUTH_DB_PATH)
  # 5 second busy timeout: SQLite will retry internally on a locked database
  # instead of failing instantly, which is what makes near-simultaneous
  # create_user() calls from separate processes safe against this single file.
  DBI::dbExecute(con, "PRAGMA busy_timeout = 5000;")
  if (!DBI::dbExistsTable(con, "users")) {
    DBI::dbExecute(con, "
      CREATE TABLE users (
        username   TEXT PRIMARY KEY,
        password_hash TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    ")
  }
  con
}

# A fixed, valid bcrypt hash with an unknown/unknowable password. Used as the
# comparison target when a username does not exist, so verify_user() always
# performs a bcrypt comparison of comparable cost on both the "no such user"
# and "wrong password" paths. This closes the two most common side channels
# for a user-enumeration bug in a login check:
#   - timing: without this, a nonexistent username would return instantly
#     (no bcrypt comparison), while an existing username with a wrong password
#     would take the full bcrypt comparison time -- an attacker could time
#     responses to enumerate valid usernames. Always doing a bcrypt::checkpw()
#     call keeps the two paths' cost comparable.
#   - error message / return value: both paths return the same FALSE, with no
#     distinct error or message that reveals which case occurred.
# This is a constant literal hash (not a secret -- it hashes no real password
# and gates nothing), generated once with bcrypt::hashpw() at cost 12 to match
# this module's real hashes.
.AUTH_DUMMY_HASH <- "$2a$12$Ow6zfKOOKzsjAWiGlREqNuZI2UdLcUcqGIssNGTJEdVr2rlyYcjX2"

# ------------------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------------------

#' Create a new user with a bcrypt-hashed password.
#'
#' @param username character scalar, must be non-empty and not already taken.
#' @param password character scalar, the raw password (never stored as-is).
#' @return invisible TRUE on success. Errors (does not silently fail) if the
#'   username already exists or inputs are invalid, since callers at an R
#'   console need to know a create attempt didn't happen.
create_user <- function(username, password) {
  if (!is.character(username) || length(username) != 1 || is.na(username) || !nzchar(username)) {
    stop("create_user(): 'username' must be a single non-empty string.")
  }
  if (!is.character(password) || length(password) != 1 || is.na(password) || !nzchar(password)) {
    stop("create_user(): 'password' must be a single non-empty string.")
  }

  con <- .auth_db_connect()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  existing <- DBI::dbGetQuery(
    con,
    "SELECT 1 FROM users WHERE username = ?;",
    params = list(username)
  )
  if (nrow(existing) > 0) {
    stop(sprintf("create_user(): username '%s' already exists.", username))
  }

  password_hash <- bcrypt::hashpw(password)

  DBI::dbExecute(
    con,
    "INSERT INTO users (username, password_hash, created_at) VALUES (?, ?, ?);",
    params = list(username, password_hash, format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  )

  invisible(TRUE)
}

#' Verify a username/password pair against the bcrypt-hashed user store.
#'
#' Always returns a boolean -- never errors for a nonexistent username, and
#' takes a comparable amount of time / produces an identical return value
#' whether the username doesn't exist or the password is simply wrong, so
#' this function cannot be used to enumerate valid usernames (see
#' .AUTH_DUMMY_HASH above for the mechanism).
#'
#' @param username character scalar.
#' @param password character scalar, the raw password to check.
#' @return TRUE if the username exists and the password matches; FALSE
#'   otherwise (including a nonexistent username, or malformed input).
verify_user <- function(username, password) {
  if (!is.character(username) || length(username) != 1 || is.na(username) || !nzchar(username)) {
    return(FALSE)
  }
  if (!is.character(password) || length(password) != 1 || is.na(password)) {
    return(FALSE)
  }

  con <- .auth_db_connect()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  row <- DBI::dbGetQuery(
    con,
    "SELECT password_hash FROM users WHERE username = ?;",
    params = list(username)
  )

  # Always resolve a hash to compare against -- the real one if the user
  # exists, otherwise the fixed dummy hash -- so bcrypt::checkpw() always runs
  # and the "no such user" / "wrong password" paths are indistinguishable.
  stored_hash <- if (nrow(row) == 1) row$password_hash[[1]] else .AUTH_DUMMY_HASH
  user_exists <- nrow(row) == 1

  password_matches <- tryCatch(
    bcrypt::checkpw(password, stored_hash),
    error = function(e) FALSE
  )

  isTRUE(user_exists && password_matches)
}

#' Create a new user, gated on a key-phrase (Slice 2 of issue #44, GitHub
#' issue #52).
#'
#' Wraps create_user() with an authorization check: the caller-supplied
#' `key_phrase` must exactly match `Sys.getenv("CONTROL_PANEL_SIGNUP_KEY", "")`.
#' This is a signup-wide gate (one shared phrase controls whether anyone can
#' sign up at all), not a per-account secret -- but per CLAUDE.md's
#' secrets-handling convention it is still treated as secret-adjacent: it is
#' read only via Sys.getenv(..., "") (never hardcoded), and it is never
#' echoed back in any error/warning/message produced by this function.
#'
#' Fail-safe behavior: if the env var is unset/empty, every signup attempt is
#' rejected unconditionally -- including a caller who happens to pass
#' `key_phrase = ""`. An unset gate must never be read as "no gate, allow
#' everyone" (see CLAUDE.md's fail-safe-design convention).
#'
#' @param username character scalar, passed through to create_user().
#' @param password character scalar, passed through to create_user().
#' @param key_phrase character scalar, checked against
#'   Sys.getenv("CONTROL_PANEL_SIGNUP_KEY", "").
#' @return invisible TRUE on success (account created). invisible FALSE if
#'   authorization fails (wrong/missing key_phrase, or the gate is unset) --
#'   this path never calls create_user() and never touches the users table.
#'   Propagates create_user()'s own error (e.g. duplicate username, invalid
#'   input) if authorization succeeds but account creation itself fails.
create_account_if_authorized <- function(username, password, key_phrase) {
  required_key <- Sys.getenv("CONTROL_PANEL_SIGNUP_KEY", "")

  # Fail-safe: an unset/empty gate rejects everyone, full stop -- never
  # treated as "no gate". This also naturally rejects a key_phrase of ""
  # even though "" == "" would otherwise match.
  if (!nzchar(required_key)) {
    return(invisible(FALSE))
  }

  if (!is.character(key_phrase) || length(key_phrase) != 1 || is.na(key_phrase)) {
    return(invisible(FALSE))
  }

  # Deliberately no cat()/message()/warning() on the mismatch path below (or
  # anywhere in this function) that would include `key_phrase` or
  # `required_key` -- doing so would leak the secret-adjacent gate value into
  # logs/console output even though this function's job is only to say
  # yes/no.
  if (!identical(key_phrase, required_key)) {
    return(invisible(FALSE))
  }

  create_user(username, password)
  invisible(TRUE)
}
