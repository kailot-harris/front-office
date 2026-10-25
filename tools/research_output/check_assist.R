# GitHub issue #90: PROJECT_DIR was a hardcoded absolute path to this repo's pre-move
# location, which stopped existing when the repo moved under front-office/. Derived from
# THIS SCRIPT'S own location now, walking up to the directory that holds config.R, so this
# tools/ script setwd()s to the real project root regardless of where it is invoked from
# (CLAUDE.md's tools/ convention) and fails loudly instead of silently no-op'ing (the
# dir.exists() guard) or aborting on a missing directory (the unguarded setwd). The walk-up
# is depth-agnostic, so it works from tools/<subdir>/ and inside a git worktree too.
PROJECT_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
  start <- if (length(file_arg)) {
    dirname(normalizePath(file_arg[1], winslash = "/", mustWork = FALSE))
  } else {
    getwd()   # sourced interactively: start from the caller's cwd
  }
  root <- start
  while (!file.exists(file.path(root, "config.R"))) {
    parent <- dirname(root)
    if (identical(parent, root)) {
      stop(sprintf("check_assist.R: cannot locate the repo root (no config.R at or above '%s')", start))
    }
    root <- parent
  }
  root
})
setwd(PROJECT_DIR)
suppressPackageStartupMessages(library(dplyr))
pbp <- wehoop::load_wnba_pbp(seasons = 2025)
made_shots <- pbp %>% filter(scoring_play == TRUE, shooting_play == TRUE)
cat("made shots:", nrow(made_shots), " athlete_id_2 non-NA among them:", sum(!is.na(made_shots$athlete_id_2)), "\n")
print(head(made_shots %>% filter(!is.na(athlete_id_2)) %>% select(text, athlete_name_1, athlete_name_2), 10))
cat("\nsample text with 'assist':\n")
print(head(pbp$text[grepl("assist", pbp$text, ignore.case = TRUE)], 10))
