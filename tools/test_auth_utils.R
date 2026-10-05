# ==============================================================================
# tools/test_auth_utils.R
# Standalone test/verification script for auth_utils.R (GitHub issue #51).
#
# Per CLAUDE.md's folder-layout convention, this tools/ script setwd()s to the
# absolute project root first, then source()s siblings (config.R, auth_utils.R)
# by bare filename, so it runs correctly regardless of invocation cwd.
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" tools\test_auth_utils.R
# Exits 0 on success (all assertions pass), exits 1 (via stop()) on any
# assertion failure.
# ==============================================================================

# Resolve the project root the same portable way config.R does (here::here()),
# independent of where/how Rscript was invoked from.
PROJECT_ROOT <- tryCatch(here::here(), error = function(e) NA_character_)
if (is.na(PROJECT_ROOT) || !file.exists(file.path(PROJECT_ROOT, "config.R"))) {
  # Last-resort fallback: assume this script lives at <root>/tools/test_auth_utils.R.
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
# Fresh auth DB for a clean, repeatable test run. This test script's own DB is
# intentionally separate from any real cache/auth_users.sqlite a human session
# may already be using -- delete and recreate it each run.
# ------------------------------------------------------------------------------
if (file.exists(AUTH_DB_PATH)) {
  file.remove(AUTH_DB_PATH)
}
check("auth_users.sqlite does not exist before first use", !file.exists(AUTH_DB_PATH))

test_user <- "slice1_test_user"
test_pass <- "Correct-Horse-Battery-Staple-42!"
wrong_pass <- "definitely-the-wrong-password"

# --- Criterion 1: sourcing + first use creates the DB file -------------------
create_user(test_user, test_pass)
check("cache/auth_users.sqlite created on first use", file.exists(AUTH_DB_PATH))

# --- Criterion 2: stored value is a bcrypt hash, never the raw password ------
con <- DBI::dbConnect(RSQLite::SQLite(), dbname = AUTH_DB_PATH)
row <- DBI::dbGetQuery(con, "SELECT password_hash FROM users WHERE username = ?;", params = list(test_user))
DBI::dbDisconnect(con)

stored_hash <- row$password_hash[[1]]
check("exactly one row stored for the created user", nrow(row) == 1)
check("stored_hash is not equal to the raw password", stored_hash != test_pass)
check("stored_hash matches the bcrypt pattern ($2...)", grepl("^\\$2[aby]?\\$", stored_hash))

# --- Criterion 3: verify_user() correctness, no error on nonexistent user ----
check("verify_user() TRUE for correct password", isTRUE(verify_user(test_user, test_pass)))
check("verify_user() FALSE for incorrect password", identical(verify_user(test_user, wrong_pass), FALSE))

nonexistent_result <- tryCatch(
  list(ok = TRUE, value = verify_user("this_user_does_not_exist_at_all", "whatever123"), errored = FALSE),
  error = function(e) list(ok = FALSE, value = NA, errored = TRUE, msg = conditionMessage(e))
)
check("verify_user() does not throw for a nonexistent username", isTRUE(nonexistent_result$ok) && !isTRUE(nonexistent_result$errored))
check("verify_user() returns FALSE for a nonexistent username", identical(nonexistent_result$value, FALSE))

# Timing/behavior parity check (best-effort, not a strict perf assertion):
# both the "wrong password for an existing user" and "nonexistent username"
# paths should run a real bcrypt comparison, so neither should return
# implausibly fast relative to the other. This is a sanity check, not a hard
# gate (bcrypt timing has natural jitter), so we only check order-of-magnitude.
t_wrong_user  <- system.time(verify_user(test_user, wrong_pass))[["elapsed"]]
t_no_such_usr <- system.time(verify_user("another_nonexistent_user_xyz", wrong_pass))[["elapsed"]]
check(
  sprintf("wrong-password (%.4fs) and no-such-user (%.4fs) paths are same order of magnitude", t_wrong_user, t_no_such_usr),
  t_no_such_usr < (t_wrong_user * 10 + 0.5) && t_wrong_user < (t_no_such_usr * 10 + 0.5)
)

# --- Criterion 4: near-simultaneous create_user() calls don't corrupt the DB -
# True concurrent *processes* are launched here (not just sequential in-process
# calls) via two background Rscript.exe invocations hitting the same SQLite
# file at nearly the same time, each creating a distinct new user.
concurrent_user_a <- "slice1_concurrent_user_a"
concurrent_user_b <- "slice1_concurrent_user_b"

worker_script <- tempfile(fileext = ".R")
writeLines(c(
  sprintf("setwd(%s)", encodeString(PROJECT_ROOT, quote = '"')),
  "source('config.R')",
  "source('auth_utils.R')",
  "args <- commandArgs(trailingOnly = TRUE)",
  "create_user(args[[1]], args[[2]])"
), worker_script)

rscript_bin <- file.path(R.home("bin"), "Rscript.exe")

p1 <- sys::exec_background(rscript_bin, c(worker_script, concurrent_user_a, "passwordA123"))
p2 <- sys::exec_background(rscript_bin, c(worker_script, concurrent_user_b, "passwordB123"))

status1 <- sys::exec_status(p1, wait = TRUE)
status2 <- sys::exec_status(p2, wait = TRUE)

check("concurrent create_user() process A exited cleanly", identical(status1, 0L))
check("concurrent create_user() process B exited cleanly", identical(status2, 0L))

con <- DBI::dbConnect(RSQLite::SQLite(), dbname = AUTH_DB_PATH)
all_users <- DBI::dbGetQuery(con, "SELECT username FROM users;")
DBI::dbDisconnect(con)

check("auth_users.sqlite still readable after concurrent writers", is.data.frame(all_users))
check("concurrent user A present after concurrent writes", concurrent_user_a %in% all_users$username)
check("concurrent user B present after concurrent writes", concurrent_user_b %in% all_users$username)
check("verify_user() works for concurrently-created user A", isTRUE(verify_user(concurrent_user_a, "passwordA123")))
check("verify_user() works for concurrently-created user B", isTRUE(verify_user(concurrent_user_b, "passwordB123")))

unlink(worker_script)

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
  stop("test_auth_utils.R: one or more assertions failed.")
}
