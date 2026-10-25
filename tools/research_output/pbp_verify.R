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
      stop(sprintf("pbp_verify.R: cannot locate the repo root (no config.R at or above '%s')", start))
    }
    root <- parent
  }
  root
})
setwd(PROJECT_DIR)
suppressPackageStartupMessages(library(dplyr))

feats <- readRDS("cache/player_pbp_features.rds")
roster <- readRDS("cache/active_rosters_cache.rds")

cat("=== nrow check ===\n")
cat("features nrow:", nrow(feats), " roster nrow (distinct player_id):", n_distinct(roster$player_id), "\n\n")

cat("=== NA leakage check (player_id/team_abbreviation/data_source) ===\n")
cat("NA player_id:", sum(is.na(feats$player_id)), "\n")
cat("NA team_abbreviation:", sum(is.na(feats$team_abbreviation)), "\n")
cat("NA data_source:", sum(is.na(feats$data_source)), "\n\n")

cat("=== column list ===\n")
print(names(feats))

cat("\n=== data_source distribution ===\n")
print(table(feats$data_source, useNA = "ifany"))

cat("\n=== Top 10 by clutch_points ===\n")
feats %>% arrange(desc(clutch_points)) %>%
  select(player_name, team_abbreviation, data_source, clutch_points, clutch_fga, clutch_fg_pct, clutch_scoring_plays) %>%
  head(10) %>% print(n = 10)

cat("\n=== Top 10 by pct_three (min fga_total >= 20) ===\n")
feats %>% filter(fga_total >= 20) %>% arrange(desc(pct_three)) %>%
  select(player_name, team_abbreviation, data_source, fga_total, pct_three, pct_rim, pct_off_dribble_jumper, pct_catch_shoot_jumper) %>%
  head(10) %>% print(n = 10)

cat("\n=== Top 10 by assists ===\n")
feats %>% arrange(desc(assists)) %>%
  select(player_name, team_abbreviation, data_source, assists) %>%
  head(10) %>% print(n = 10)
