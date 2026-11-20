# Shared fixture helpers for tests/test_landing_digest_*.R (not a test file itself).
REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
})
setwd(REPO_ROOT)
Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")
source(file.path(REPO_ROOT, "tools", "build_landing_digest.R"))

n_pass <- 0L; n_fail <- 0L
check <- function(cond, label) {
  if (isTRUE(cond)) { n_pass <<- n_pass + 1L; cat("  PASS:", label, "\n") }
  else { n_fail <<- n_fail + 1L; cat("  FAIL:", label, "\n") }
}
finish <- function() {
  cat(sprintf("\n%d passed, %d failed\n", n_pass, n_fail))
  if (n_fail > 0L) quit(status = 1L)
}

# One matchups row. prob = home win prob; NA scores = not final.
mrow <- function(id, date, home, away, prob, hs = NA, as_ = NA, logged = TRUE) {
  data.frame(game_id = id, game_date = date, home_team = home, away_team = away,
             is_completed = !is.na(hs), has_projection = TRUE,
             log_source = if (logged) "LOGGED_PREGAME" else NA_character_,
             predicted_home_win_prob = prob, home_score = hs, away_score = as_,
             stringsAsFactors = FALSE)
}
