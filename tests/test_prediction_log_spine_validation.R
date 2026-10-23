# ==============================================================================
# tests/test_prediction_log_spine_validation.R
#
# Covers GitHub issue 24: a parsed bookmaker matchup whose teams are not a real
# scheduled game must be impossible to write, and a bad row already in the log
# must be correctable on a later run.
#
# Runs with NO `cache/` directory: `cache/` is gitignored, so a git worktree has
# neither the schedule spine nor the prediction log. Every artifact here is an
# in-memory fixture injected through the seams in prediction_accuracy_logger.R
# (`spine`, `slate`, `existing_log`, `persist = FALSE`).
#
# The logger auto-executes `run_prediction_accuracy_logger()` on source and
# needs ODDS_API_KEY-dependent artifacts, so it is NOT sourced. Instead its
# top-level definitions are parsed and evaluated selectively (see
# `load_logger_definitions` below) - no pipeline stage runs, no API is called.
#
# Usage: Rscript tests/test_prediction_log_spine_validation.R
# ==============================================================================

suppressPackageStartupMessages({
  library(tibble)
  library(dplyr)
  library(stringr)
})

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
})

failures <- 0L
checks   <- 0L

ok <- function(label, cond) {
  checks <<- checks + 1L
  if (isTRUE(cond)) {
    cat(sprintf("  PASS  %s\n", label))
  } else {
    failures <<- failures + 1L
    cat(sprintf("  FAIL  %s\n", label))
  }
}

section <- function(title) cat(sprintf("\n== %s ==\n", title))

# ------------------------------------------------------------------------------
# Load the units under test without executing the pipeline.
# ------------------------------------------------------------------------------
load_logger_definitions <- function(path, env) {
  exprs <- parse(path)
  for (e in exprs) {
    # Keep only top-level `name <- value` assignments (constants and function
    # definitions). Skips setwd(), source(), library(), the `if (dir.exists())`
    # guard and the trailing run_prediction_accuracy_logger() call.
    if (is.call(e) && length(e) == 3L &&
        as.character(e[[1]]) %in% c("<-", "=") && is.name(e[[2]])) {
      tryCatch(eval(e, envir = env), error = function(err) invisible(NULL))
    }
  }
  invisible(env)
}

env <- new.env(parent = globalenv())
source(file.path(REPO_ROOT, "team_name_resolver.R"), local = env)
# Constants normally supplied by config.R.
env$CURRENT_SEASON <- 2027L
env$CACHE_DIR      <- tempdir()
load_logger_definitions(file.path(REPO_ROOT, "prediction_accuracy_logger.R"), env)

for (nm in c("resolve_team_name", ".empty_prediction_log", ".build_slate_rows",
             ".normalize_schedule_spine", ".validate_slate_against_spine",
             ".report_spine_rejections", ".upsert_predictions",
             ".check_predicted_winner_consistency", "log_todays_predictions",
             "PRED_LOG_WINNER_PROB_CUTOFF")) {
  if (!exists(nm, envir = env, inherits = FALSE)) {
    stop(sprintf("Fixture load failed: %s not defined after selective eval.", nm))
  }
}
attach_env <- function(nm) get(nm, envir = env)

resolve_team_name                   <- attach_env("resolve_team_name")
.build_slate_rows                   <- attach_env(".build_slate_rows")
.normalize_schedule_spine           <- attach_env(".normalize_schedule_spine")
.validate_slate_against_spine       <- attach_env(".validate_slate_against_spine")
.report_spine_rejections            <- attach_env(".report_spine_rejections")
.upsert_predictions                 <- attach_env(".upsert_predictions")
.check_predicted_winner_consistency <- attach_env(".check_predicted_winner_consistency")
log_todays_predictions              <- attach_env("log_todays_predictions")

# ------------------------------------------------------------------------------
# CRITERION 2: resolver deduplication is behaviour-preserving.
# ------------------------------------------------------------------------------
section("Criterion 2: shared resolver reproduces every nickname and abbreviation")

CANONICAL <- c(
  "Celtics", "Thunder", "Cavaliers", "Spurs", "Warriors", "Rockets", "Knicks",
  "Pistons", "Nuggets", "Heat", "76ers", "Pacers", "Trail Blazers",
  "Timberwolves", "Magic", "Grizzlies", "Lakers", "Raptors", "Hawks",
  "Mavericks", "Clippers", "Bucks", "Suns", "Jazz", "Hornets", "Nets", "Bulls",
  "Pelicans", "Wizards", "Kings"
)
ok("resolver exposes all 30 canonical nicknames",
   setequal(get("NBA_CANONICAL_NICKNAMES", envir = env), CANONICAL))

for (nick in CANONICAL) {
  got <- resolve_team_name(nick)
  ok(sprintf("nickname %-14s -> %s", nick, got), identical(got, nick))
}

# The four ESPN abbreviations build_matchups_dataset.R has to fix up.
ABBR <- c(UTAH = "Jazz", GS = "Warriors", WSH = "Wizards", NO = "Pelicans")
for (a in names(ABBR)) {
  got <- resolve_team_name(a)
  ok(sprintf("abbreviation %-5s -> %s (expected %s)", a, got, ABBR[[a]]),
     identical(got, unname(ABBR[[a]])))
}

# Vectorized call must match element-wise calls (old call sites used vapply).
vec <- resolve_team_name(c(CANONICAL, names(ABBR)))
elt <- vapply(c(CANONICAL, names(ABBR)), resolve_team_name, character(1),
              USE.NAMES = FALSE)
ok("vectorized resolver == element-wise resolver", identical(vec, elt))

ok("unrecognized input passes through unchanged",
   identical(resolve_team_name("Sonics"), "Sonics"))

# ------------------------------------------------------------------------------
# Spine fixture: the real 2026-10-21 / 2026-10-23 games from issue 24.
# ------------------------------------------------------------------------------
spine_fixture <- tibble(
  game_id = c("SP1", "SP2", "SP3", "SP4"),
  game_date = as.Date(c("2026-10-21", "2026-10-21", "2026-10-23", "2026-10-23")),
  home_short_display_name = c("Grizzlies", "Pelicans", "Jazz", "Warriors"),
  away_short_display_name = c("Jazz", "Pacers", "Pelicans", "Grizzlies")
)

slate_row <- function(game_id, game_date, away, home, team, prob) {
  tibble(game_id = game_id, game_date = as.Date(game_date),
         Matchup = paste0(away, " vs. ", home),
         Team = team, Model_Win_Prob = prob)
}

# ------------------------------------------------------------------------------
# CRITERION 3: a fabricated pairing is rejected, not written.
# ------------------------------------------------------------------------------
section("Criterion 3: fabricated pairing (2026-10-21 home 76ers away Jazz) is rejected")

bad_slate <- slate_row("BAD1", "2026-10-21", "Utah Jazz",
                       "Philadelphia 76ers", "Philadelphia 76ers", 0.55)
bad_rows  <- .build_slate_rows(bad_slate)
cat(sprintf("  parsed: date %s  home %s  away %s\n",
            bad_rows$game_date, bad_rows$home_team, bad_rows$away_team))
ok("parsed to home 76ers / away Jazz",
   identical(bad_rows$home_team, "76ers") && identical(bad_rows$away_team, "Jazz"))

chk <- .validate_slate_against_spine(bad_rows, spine_fixture)
ok("spine was available", isTRUE(chk$spine_available))
ok("0 rows accepted", nrow(chk$accepted) == 0L)
ok("1 row rejected", nrow(chk$rejected) == 1L)
cat("  rejection report:\n")
invisible(.report_spine_rejections(chk$rejected, strict = FALSE))

# End to end through the real insertion path, with nothing persisted.
empty_log <- get(".empty_prediction_log", envir = env)()
res_bad <- log_todays_predictions(slate = bad_slate, spine = spine_fixture,
                                  existing_log = empty_log, persist = FALSE)
ok("insertion path wrote nothing for the fabricated pairing",
   is.null(res_bad) || nrow(res_bad) == 0L)

# Strict mode must hard-stop rather than drop.
hard <- tryCatch({
  .report_spine_rejections(chk$rejected, strict = TRUE); "no error"
}, error = function(e) conditionMessage(e))
ok("strict mode raises a loud stop()", grepl("schedule spine contract", hard))

# All four of issue 24's bad pairings must be rejected.
issue_24_bad <- bind_rows(
  slate_row("B1", "2026-10-21", "Utah Jazz", "Philadelphia 76ers", "Utah Jazz", 0.5),
  slate_row("B2", "2026-10-21", "Indiana Pacers", "Orlando Magic", "Orlando Magic", 0.5),
  slate_row("B3", "2026-10-23", "Orlando Magic", "Utah Jazz", "Utah Jazz", 0.5),
  slate_row("B4", "2026-10-23", "Philadelphia 76ers", "Golden State Warriors",
            "Golden State Warriors", 0.5)
)
chk4 <- .validate_slate_against_spine(.build_slate_rows(issue_24_bad), spine_fixture)
ok("all 4 issue-24 pairings rejected", nrow(chk4$rejected) == 4L && nrow(chk4$accepted) == 0L)

# A reversed-orientation row must ALSO be rejected (no bidirectional join).
rev_slate <- slate_row("REV", "2026-10-21", "Memphis Grizzlies", "Utah Jazz",
                       "Utah Jazz", 0.6)
chk_rev <- .validate_slate_against_spine(.build_slate_rows(rev_slate), spine_fixture)
ok("home/away-inverted row is rejected, not silently matched",
   nrow(chk_rev$rejected) == 1L)

# ------------------------------------------------------------------------------
# CRITERION 4: a real scheduled game still passes.
# ------------------------------------------------------------------------------
section("Criterion 4: real game (2026-10-21 home Grizzlies away Jazz) is accepted")

good_slate <- slate_row("SP1", "2026-10-21", "Utah Jazz", "Memphis Grizzlies",
                        "Memphis Grizzlies", 0.62)
good_rows  <- .build_slate_rows(good_slate)
cat(sprintf("  parsed: date %s  home %s  away %s  prob %.3f  winner %s\n",
            good_rows$game_date, good_rows$home_team, good_rows$away_team,
            good_rows$predicted_home_win_prob, good_rows$predicted_winner))

chk_good <- .validate_slate_against_spine(good_rows, spine_fixture)
ok("1 row accepted", nrow(chk_good$accepted) == 1L)
ok("0 rows rejected", nrow(chk_good$rejected) == 0L)

res_good <- log_todays_predictions(slate = good_slate, spine = spine_fixture,
                                   existing_log = empty_log, persist = FALSE)
ok("insertion path wrote the good row", !is.null(res_good) && nrow(res_good) == 1L)
ok("teams unchanged by validation",
   identical(res_good$home_team, "Grizzlies") && identical(res_good$away_team, "Jazz"))

# Mixed slate: the good row must publish even though a bad row is present.
mixed <- bind_rows(good_slate, bad_slate)
res_mixed <- log_todays_predictions(slate = mixed, spine = spine_fixture,
                                    existing_log = empty_log, persist = FALSE)
ok("mixed slate keeps the good row and drops the bad one",
   nrow(res_mixed) == 1L && identical(res_mixed$game_id, "SP1"))

# ------------------------------------------------------------------------------
# CRITERION 5: a corrected row for an already-logged game_id updates it.
# ------------------------------------------------------------------------------
section("Criterion 5: a stored PENDING row with wrong teams is corrected, not dropped")

stored <- empty_log
stored <- bind_rows(stored, tibble(
  game_id = "SP3", game_date = as.Date("2026-10-23"), season = 2027L,
  home_team = "Jazz", away_team = "Magic",            # fabricated pairing
  prediction_timestamp = as.POSIXct("2026-10-23 09:00:00"),
  predicted_home_win_prob = 0.339, .pred_Win = 0.339,
  predicted_winner = "Magic", predicted_margin = NA_real_,
  target_home_win = NA_character_, actual_winner = NA_character_,
  correct = NA, brier_component = NA_real_, log_loss_component = NA_real_,
  status = "PENDING", resolved_timestamp = as.POSIXct(NA)
))
cat(sprintf("  BEFORE: game_id %s  home %s  away %s  prob %.3f  winner %s  status %s\n",
            stored$game_id, stored$home_team, stored$away_team,
            stored$predicted_home_win_prob, stored$predicted_winner, stored$status))

# Old behaviour, for contrast: anti_join on game_id alone drops the correction.
correction <- slate_row("SP3", "2026-10-23", "New Orleans Pelicans", "Utah Jazz",
                        "Utah Jazz", 0.339)
correction_rows <- .build_slate_rows(correction)
ok("old anti_join(by = 'game_id') would have dropped the correction",
   nrow(anti_join(correction_rows, stored, by = "game_id")) == 0L)

res_fix <- log_todays_predictions(slate = correction, spine = spine_fixture,
                                  existing_log = stored, persist = FALSE)
after <- res_fix[res_fix$game_id == "SP3", ]
cat(sprintf("  AFTER : game_id %s  home %s  away %s  prob %.3f  winner %s  status %s\n",
            after$game_id, after$home_team, after$away_team,
            after$predicted_home_win_prob, after$predicted_winner, after$status))
ok("still exactly one row for that game_id", nrow(after) == 1L)
ok("home_team corrected Jazz -> Jazz (unchanged, correct side)",
   identical(after$home_team, "Jazz"))
ok("away_team corrected Magic -> Pelicans", identical(after$away_team, "Pelicans"))
ok("predicted_winner recomputed Magic -> Pelicans",
   identical(after$predicted_winner, "Pelicans"))

# Re-running with the same correct row must be a no-op (still idempotent).
res_again <- log_todays_predictions(slate = correction, spine = spine_fixture,
                                    existing_log = res_fix, persist = FALSE)
ok("re-running the same validated row changes nothing (idempotent)",
   nrow(res_again) == 1L && identical(res_again$away_team, "Pelicans"))

# A graded (RESOLVED) row must never be silently overwritten.
graded <- stored
graded$status <- "RESOLVED"
upsert <- get(".upsert_predictions", envir = env)
res_graded <- upsert(graded, correction_rows)
ok("a RESOLVED row is reported, not overwritten",
   res_graded$n_locked == 1L && res_graded$n_corrected == 0L &&
     identical(res_graded$log$away_team[1], "Magic"))

# ------------------------------------------------------------------------------
# CRITERION 6: predicted_winner self-consistency guard.
# ------------------------------------------------------------------------------
section("Criterion 6: winner guard flags the live corrupt row")

corrupt <- tibble(
  game_id = "7469a7f48dbb77001b3148829f80c97b",
  game_date = as.Date("2026-10-23"),
  home_team = "Jazz", away_team = "Pelicans",
  predicted_home_win_prob = 0.339, predicted_winner = "Magic",
  status = "PENDING"
)
flagged <- .check_predicted_winner_consistency(corrupt, label = "live log fixture")
ok("guard flags the live corrupt row", nrow(flagged) == 1L)
ok("flagged row is the expected game_id",
   identical(flagged$game_id, "7469a7f48dbb77001b3148829f80c97b"))

wrong_side <- tibble(
  game_id = "WS1", game_date = as.Date("2026-10-21"),
  home_team = "Grizzlies", away_team = "Jazz",
  predicted_home_win_prob = 0.62, predicted_winner = "Jazz",
  status = "PENDING"
)
ok("guard flags a winner on the wrong side of 0.50",
   nrow(.check_predicted_winner_consistency(wrong_side, label = "wrong-side fixture")) == 1L)

clean <- tibble(
  game_id = c("C1", "C2"), game_date = as.Date(c("2026-10-21", "2026-10-21")),
  home_team = c("Grizzlies", "Pelicans"), away_team = c("Jazz", "Pacers"),
  predicted_home_win_prob = c(0.62, 0.41),
  predicted_winner = c("Grizzlies", "Pacers"),
  status = c("PENDING", "PENDING")
)
ok("guard passes consistent rows",
   nrow(.check_predicted_winner_consistency(clean, label = "clean fixture")) == 0L)

# Rows about to be written are hard-stopped, not merely reported.
strict_msg <- tryCatch({
  .check_predicted_winner_consistency(corrupt, label = "parsed active slate",
                                      strict = TRUE); "no error"
}, error = function(e) conditionMessage(e))
ok("strict mode raises a loud stop() for rows about to be written",
   grepl("inconsistent with their", strict_msg))

# ------------------------------------------------------------------------------
section("Spine normalization edge cases")
ok("TBD placeholder fixtures are dropped from the spine",
   nrow(.normalize_schedule_spine(tibble(
     game_id = "X", game_date = as.Date("2026-10-21"),
     home_short_display_name = "TBD", away_short_display_name = "TBD"))) == 0L)
ok("missing spine columns raise an error",
   inherits(tryCatch(.normalize_schedule_spine(tibble(game_id = "X")),
                     error = function(e) e), "error"))
ok("NULL spine yields an empty spine (no check possible)",
   nrow(.normalize_schedule_spine(NULL)) == 0L)
chk_nospine <- .validate_slate_against_spine(good_rows, NULL)
ok("absent spine accepts rows but reports spine_available = FALSE",
   !isTRUE(chk_nospine$spine_available) && nrow(chk_nospine$accepted) == 1L)

# ------------------------------------------------------------------------------
cat(sprintf("\n%d checks, %d failure(s).\n", checks, failures))
if (failures > 0L) quit(status = 1L)
cat("ALL CHECKS PASSED\n")
