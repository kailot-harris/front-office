# ==============================================================================
# test_schedule_completed_reconcile.R (#253)
# A schedule re-ingest must never flip a played game back to not completed, and
# must never mark a game completed that no source reported as final.
# Offline: synthetic fixtures only, no network, no cache reads.
# ==============================================================================
args_all <- commandArgs(trailingOnly = FALSE)
f <- sub("^--file=", "", args_all[grepl("^--file=", args_all)])
if (length(f) == 1 && nzchar(f) && file.exists(f)) {
  cand <- normalizePath(dirname(dirname(dirname(f))), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(cand, "config.R"))) setwd(cand)
}
suppressPackageStartupMessages(library(dplyr))
source("daily_ingest.R")

fails <- 0L
check <- function(label, ok) {
  cat(sprintf("[%s] %s\n", if (isTRUE(ok)) "PASS" else "FAIL", label))
  if (!isTRUE(ok)) fails <<- fails + 1L
}

mk <- function(ids, completed) {
  tibble::tibble(game_id = rep(ids, each = 2), is_completed = rep(completed, length.out = length(ids)) |> rep(each = 2))
}
box <- tibble::tibble(
  game_id = c(1L, 1L, 2L, 3L, 3L),
  team_score = c(68L, 63L, 70L, NA_integer_, NA_integer_))

# Feed says FALSE for game 1 (final box exists) -> flipped to completed.
out <- reconcile_schedule_completed(mk(c(1L, 2L, 3L, 4L), FALSE), box = box)
done <- function(o, id) all(o$is_completed[o$game_id == id])
check("final box score keeps game 1 completed", done(out, 1L))
check("box with one side only (game 2) is not treated as final", !done(out, 2L))
check("box rows with NA scores (game 3) are not treated as final", !done(out, 3L))
check("game with no source (game 4) stays not completed", !done(out, 4L))

# Previous schedule cache had game 4 completed; feed regressed to FALSE.
prior <- mk(c(4L), TRUE)
out2 <- reconcile_schedule_completed(mk(c(1L, 4L), FALSE), box = NULL, prior_sched = prior)
check("previously completed game is not reverted", done(out2, 4L))
check("no box and no prior: game 1 stays not completed", !done(out2, 1L))

# Completed rows are untouched and other columns / row count are preserved.
inp <- mk(c(1L, 2L), c(TRUE, FALSE))
out3 <- reconcile_schedule_completed(inp, box = box)
check("already completed row stays completed", done(out3, 1L))
check("row count and columns unchanged", nrow(out3) == nrow(inp) && identical(names(out3), names(inp)))

# Degenerate inputs pass through.
check("NULL schedule passes through", is.null(reconcile_schedule_completed(NULL, box = box)))
check("box lacking team_score is ignored", !done(reconcile_schedule_completed(mk(1L, FALSE), box = box["game_id"]), 1L))

# Postponed / cancelled games (#259): 2026-07-16 DAL vs NY (401857072) was postponed
# and made up on 2026-07-20 under 401892393. schedule_to_long() preserves status_type_name,
# reconcile_schedule_completed() leaves it uncompleted, and derive_rest_features() skips it
# so it does not fabricate rest/travel for subsequent games.
raw_pp <- tibble::tibble(
  game_id = c("100", "401857072", "102"),
  game_date = as.Date(c("2026-07-12", "2026-07-16", "2026-07-18")),
  season = c(2026L, 2026L, 2026L),
  season_type = c(2L, 2L, 2L),
  home_abbreviation = c("TOR", "DAL", "IND"),
  away_abbreviation = c("NY", "NY", "NY"),
  status_type_completed = c(TRUE, FALSE, TRUE),
  status_type_name = c("STATUS_FINAL", "STATUS_POSTPONED", "STATUS_FINAL"),
  notes_headline = c(NA_character_, "Travel Issues - Makeup date July 20", NA_character_)
)
long_pp <- schedule_to_long(raw_pp)
check("schedule_to_long preserves status_type_name",
      "status_type_name" %in% names(long_pp) &&
        all(long_pp$status_type_name[long_pp$game_id == "401857072"] == "STATUS_POSTPONED"))

rest_pp <- derive_rest_features(long_pp)
ny_18 <- rest_pp[rest_pp$team_abbreviation == "NY" & rest_pp$game_id == "102", ]
ny_pp <- rest_pp[rest_pp$team_abbreviation == "NY" & rest_pp$game_id == "401857072", ]
check("derive_rest_features skips postponed game for NY days_rest (5, not 1)",
      nrow(ny_18) == 1L && identical(ny_18$days_rest, 5L))
check("derive_rest_features skips postponed game for NY last_played_at (TOR, not DAL)",
      nrow(ny_18) == 1L && identical(ny_18$last_played_at, "TOR"))
check("derive_rest_features leaves postponed row days_rest = NA and is_back_to_back = FALSE",
      nrow(ny_pp) == 1L && is.na(ny_pp$days_rest) && identical(ny_pp$is_back_to_back, FALSE))

rec_pp <- reconcile_schedule_completed(rest_pp, box = box)
check("reconcile_schedule_completed keeps postponed game with 0 box rows uncompleted",
      !done(rec_pp, "401857072"))

if (fails > 0L) quit(status = 1L)
cat("All schedule reconcile assertions passed.\n")
