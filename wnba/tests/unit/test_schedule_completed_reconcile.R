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

if (fails > 0L) quit(status = 1L)
cat("All schedule reconcile assertions passed.\n")
