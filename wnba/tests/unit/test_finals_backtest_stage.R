# ==============================================================================
# test_finals_backtest_stage.R
# Offline unit & regression tests for tools/finals_series_backtest.R and its
# run_full_pipeline.R stage wiring (WNBA_analytics#211).
#
# Runs completely offline with zero writes to real cache/ or data/ paths.
# ==============================================================================

# ------------------------------------------------------------------------------
# Root-resolution prelude (Issue #90 Working Directory Trap)
# ------------------------------------------------------------------------------
args_all <- commandArgs(trailingOnly = FALSE)
f <- sub("^--file=", "", args_all[grepl("^--file=", args_all)])
if (length(f) == 1 && nzchar(f) && file.exists(f)) {
  cand <- normalizePath(dirname(dirname(dirname(f))), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(cand, "config.R"))) setwd(cand)
}
cur <- getwd()
while (!file.exists(file.path(cur, "config.R")) && dirname(cur) != cur) {
  cur <- dirname(cur)
}
if (file.exists(file.path(cur, "config.R"))) setwd(cur)

# Ensure user library is accessible even when running inside an isolated renv sandbox
user_lib <- Sys.getenv("R_LIBS_USER")
if (nzchar(user_lib) && dir.exists(user_lib) && !(user_lib %in% .libPaths())) {
  .libPaths(c(.libPaths(), user_lib))
} else {
  default_user_lib <- file.path(
    Sys.getenv("LOCALAPPDATA", file.path(Sys.getenv("USERPROFILE"), "AppData", "Local")),
    "R", "win-library", "4.5"
  )
  if (dir.exists(default_user_lib) && !(default_user_lib %in% .libPaths())) {
    .libPaths(c(.libPaths(), default_user_lib))
  }
}

suppressPackageStartupMessages({
  library(testthat)
  library(dplyr)
  library(tibble)
})

# Source backtest stage with autorun suppressed so sourcing itself has no side effects.
prev_skip <- Sys.getenv("WNBA_SKIP_STAGE_AUTORUN", unset = NA_character_)
Sys.setenv(WNBA_SKIP_STAGE_AUTORUN = "1")
source("tools/finals_series_backtest.R")
if (is.na(prev_skip)) {
  Sys.unsetenv("WNBA_SKIP_STAGE_AUTORUN")
} else {
  Sys.setenv(WNBA_SKIP_STAGE_AUTORUN = prev_skip)
}

# ------------------------------------------------------------------------------
# Helpers for synthetic offline fixtures
# ------------------------------------------------------------------------------
make_box_fixture <- function(reg_games = 10L, finals_games = NULL,
                             high_abb = "GS", low_abb = "ATL",
                             season_yr = CURRENT_SEASON) {
  reg_dates <- as.Date("2026-07-01") + seq_len(reg_games) - 1L
  reg_high <- tibble(
    season = season_yr,
    season_type = 2L,
    game_date = as.character(reg_dates),
    team_abbreviation = high_abb,
    opponent_team_abbreviation = "NY",
    team_score = 84L,
    opponent_team_score = 78L
  )
  reg_low <- tibble(
    season = season_yr,
    season_type = 2L,
    game_date = as.character(reg_dates),
    team_abbreviation = low_abb,
    opponent_team_abbreviation = "MIN",
    team_score = 82L,
    opponent_team_score = 77L
  )
  # Include an exhibition row and legacy CONN code to verify filter_real_franchises() runs cleanly.
  reg_other <- tibble(
    season = season_yr,
    season_type = 2L,
    game_date = as.character(reg_dates[1]),
    team_abbreviation = c("CONN", "ALL"),
    opponent_team_abbreviation = c("NY", "USA"),
    team_score = c(80L, 100L),
    opponent_team_score = c(75L, 95L)
  )
  out <- bind_rows(reg_high, reg_low, reg_other)
  if (!is.null(finals_games) && nrow(finals_games) > 0) {
    fin_high <- finals_games %>%
      transmute(
        season = season_yr,
        season_type = 3L,
        game_date = as.character(game_day),
        team_abbreviation = high_abb,
        opponent_team_abbreviation = low_abb,
        team_score = as.integer(score_high),
        opponent_team_score = as.integer(score_low)
      )
    fin_low <- finals_games %>%
      transmute(
        season = season_yr,
        season_type = 3L,
        game_date = as.character(game_day),
        team_abbreviation = low_abb,
        opponent_team_abbreviation = high_abb,
        team_score = as.integer(score_low),
        opponent_team_score = as.integer(score_high)
      )
    out <- bind_rows(out, fin_high, fin_low)
  }
  out
}

find_run_stage_calls <- function(pipeline_path, script_target) {
  exprs <- parse(pipeline_path, keep.source = FALSE)
  proto <- function(script_name, description, call_fn = NULL, entry_fn = NULL, output = NULL) NULL
  hits <- list()
  walk <- function(node, idx_ref) {
    if (is.call(node)) {
      head <- node[[1]]
      if (is.symbol(head) && identical(as.character(head), "run_stage")) {
        matched <- tryCatch(match.call(proto, node), error = function(e) NULL)
        if (!is.null(matched) && identical(matched$script_name, script_target)) {
          hits[[length(hits) + 1L]] <<- list(
            index = idx_ref,
            call_fn = matched$call_fn,
            output = matched$output
          )
        }
      }
      for (i in seq_along(node)) walk(node[[i]], idx_ref)
    } else if (is.pairlist(node) || is.expression(node)) {
      for (i in seq_along(node)) walk(node[[i]], if (is.expression(node)) i else idx_ref)
    }
  }
  walk(exprs, NA_integer_)
  hits
}

find_top_level_call_index <- function(pipeline_path, fn_name, first_arg) {
  exprs <- parse(pipeline_path, keep.source = FALSE)
  for (i in seq_along(exprs)) {
    node <- exprs[[i]]
    if (is.call(node) && is.symbol(node[[1]]) &&
        identical(as.character(node[[1]]), fn_name) &&
        length(node) >= 2 && identical(node[[2]], first_arg)) {
      return(i)
    }
  }
  NA_integer_
}

# ------------------------------------------------------------------------------
# Tests
# ------------------------------------------------------------------------------

test_that("tools/finals_series_backtest.R exposes run_finals_series_backtest and obeys WNBA_SKIP_STAGE_AUTORUN", {
  expect_true(exists("run_finals_series_backtest", mode = "function"))
  expect_true(exists("run_finals_backtest", mode = "function"))

  src_lines <- readLines("tools/finals_series_backtest.R", warn = FALSE)
  src_code <- paste(src_lines[!grepl("^\\s*#", src_lines)], collapse = "\n")
  expect_true(grepl("sys\\.nframe\\(\\)\\s*==\\s*0", src_code))
  expect_true(grepl("WNBA_SKIP_STAGE_AUTORUN", src_code, fixed = TRUE))

  # Probe in an isolated Rscript child process evaluating at frame 0 with WNBA_SKIP_STAGE_AUTORUN=1.
  probe_script <- tempfile(fileext = ".R")
  on.exit(unlink(probe_script), add = TRUE)
  lib_init <- paste(deparse(.libPaths()), collapse = "")
  writeLines(c(
    sprintf('.libPaths(%s)', lib_init),
    'Sys.setenv(WNBA_SKIP_STAGE_AUTORUN = "1")',
    'eval(parse("tools/finals_series_backtest.R"), envir = .GlobalEnv)',
    'cat("HAS_FN=", exists("run_finals_series_backtest", mode = "function"), "\\n", sep = "")'
  ), probe_script)

  prev_renv <- Sys.getenv("RENV_ACTIVATE_PROJECT", unset = NA_character_)
  prev_skip_child <- Sys.getenv("WNBA_SKIP_STAGE_AUTORUN", unset = NA_character_)
  Sys.setenv(RENV_ACTIVATE_PROJECT = "FALSE", WNBA_SKIP_STAGE_AUTORUN = "1")
  on.exit({
    if (is.na(prev_renv)) Sys.unsetenv("RENV_ACTIVATE_PROJECT") else Sys.setenv(RENV_ACTIVATE_PROJECT = prev_renv)
    if (is.na(prev_skip_child)) Sys.unsetenv("WNBA_SKIP_STAGE_AUTORUN") else Sys.setenv(WNBA_SKIP_STAGE_AUTORUN = prev_skip_child)
  }, add = TRUE)

  rscript <- file.path(R.home("bin"), "Rscript")
  out <- suppressWarnings(system2(
    rscript,
    c("--vanilla", shQuote(probe_script)),
    stdout = TRUE,
    stderr = TRUE
  ))
  expect_null(attr(out, "status"), info = paste(out, collapse = "\n"))
  expect_true(any(grepl("HAS_FN=TRUE", out, fixed = TRUE)), info = paste(out, collapse = "\n"))
  expect_false(any(grepl("\\[FINALS BACKTEST\\] Saved", out)))
})

test_that("run_full_pipeline.R registers tools/finals_series_backtest.R before export_web_json", {
  expect_no_error(parse("run_full_pipeline.R"))

  hits <- find_run_stage_calls("run_full_pipeline.R", "tools/finals_series_backtest.R")
  expect_equal(length(hits), 1L)
  expect_identical(hits[[1]]$call_fn, "run_finals_series_backtest")
  expect_identical(as.character(hits[[1]]$output), "CACHE_FINALS_SERIES_BACKTEST")

  export_idx <- find_top_level_call_index("run_full_pipeline.R", "run_registered_stage", "export_web_json")
  expect_false(is.na(export_idx))
  expect_lt(hits[[1]]$index, export_idx)
})

test_that("run_finals_series_backtest fails safe when box scores or Finals games are unavailable", {
  tmp_dir <- tempfile("finals_bt_missing_")
  dir.create(tmp_dir, recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  out_missing <- file.path(tmp_dir, "out_missing.rds")
  expect_warning(
    res_missing <- run_finals_series_backtest(
      team_box_path = file.path(tmp_dir, "does_not_exist.rds"),
      out_path = out_missing,
      bracket_path = NULL
    ),
    "not found"
  )
  expect_null(res_missing)
  expect_false(file.exists(out_missing))

  # Regular season exists, no Finals games yet.
  reg_only_path <- file.path(tmp_dir, "reg_only.rds")
  saveRDS(make_box_fixture(reg_games = 6L, finals_games = NULL), reg_only_path)
  out_reg_only <- file.path(tmp_dir, "out_reg_only.rds")
  expect_warning(
    res_reg_only <- run_finals_series_backtest(
      team_box_path = reg_only_path,
      out_path = out_reg_only,
      bracket_path = NULL
    ),
    "No postseason games"
  )
  expect_null(res_reg_only)
  expect_false(file.exists(out_reg_only))

  # Bracket exists without a Finals row yet.
  bracket_no_finals <- file.path(tmp_dir, "bracket_no_finals.rds")
  saveRDS(tibble(round = c("Round 1", "Semifinals"), team_a = c("A", "C"), team_b = c("B", "D"),
                 team_a_abb = c("GS", "NY"), team_b_abb = c("DAL", "MIN")), bracket_no_finals)
  out_no_fin <- file.path(tmp_dir, "out_no_fin.rds")
  expect_warning(
    res_no_fin <- run_finals_series_backtest(
      team_box_path = reg_only_path,
      out_path = out_no_fin,
      bracket_path = bracket_no_finals
    ),
    "No Finals series"
  )
  expect_null(res_no_fin)
  expect_false(file.exists(out_no_fin))
})

test_that("run_finals_series_backtest builds walk-forward reconstructions offline across full 7-game Finals", {
  tmp_dir <- tempfile("finals_bt_full_")
  dir.create(tmp_dir, recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  finals_7 <- tibble(
    game_day = as.Date(c("2026-10-17", "2026-10-19", "2026-10-21", "2026-10-24",
                         "2026-10-26", "2026-10-29", "2026-10-31")),
    score_high = c(68L, 65L, 71L, 67L, 64L, 69L, 68L),
    score_low  = c(64L, 79L, 97L, 62L, 55L, 80L, 63L)
  )
  box_path <- file.path(tmp_dir, "box_7.rds")
  out_path <- file.path(tmp_dir, "finals_bt_7.rds")
  saveRDS(make_box_fixture(reg_games = 12L, finals_games = finals_7), box_path)

  res <- suppressMessages(run_finals_series_backtest(
    team_box_path = box_path,
    out_path = out_path,
    bracket_path = NULL
  ))

  expect_true(file.exists(out_path))
  disk <- readRDS(out_path)
  expect_identical(nrow(res), nrow(disk))
  expect_true(startsWith(attr(disk, "provenance"), "RECONSTRUCTION, not an archived forecast."))

  fg <- attr(disk, "finals_games")
  expect_equal(nrow(fg), 7L)
  expect_equal(sum(fg$high_won), 4L)
  expect_equal(as.character(range(fg$game_day)), c("2026-10-17", "2026-10-31"))

  # Walk-forward leak check: pre-series sees only the 12 regular-season games; after G6 sees 12+6=18.
  pre <- disk %>%
    filter(info_set == "pre-series", information == "all games to date", conditioning == "actual_state")
  expect_equal(pre$n_games_high, 12)
  expect_equal(pre$state_high, 0L)
  expect_equal(pre$state_low, 0L)

  after6 <- disk %>%
    filter(info_set == "after G6", information == "all games to date", conditioning == "actual_state")
  expect_equal(after6$n_games_high, 18)
  expect_equal(after6$state_high, 3L)
  expect_equal(after6$state_low, 3L)

  # Dynamic matchup resolution from bracket_path for a different Finals pair.
  finals_ny_min <- tibble(
    game_day = as.Date(c("2026-10-10", "2026-10-12", "2026-10-15", "2026-10-18")),
    score_high = c(85L, 76L, 88L, 81L),
    score_low  = c(79L, 82L, 74L, 75L)
  )
  box_ny_min <- file.path(tmp_dir, "box_ny_min.rds")
  bracket_ny_min <- file.path(tmp_dir, "bracket_ny_min.rds")
  out_ny_min <- file.path(tmp_dir, "bt_ny_min.rds")
  saveRDS(make_box_fixture(reg_games = 10L, finals_games = finals_ny_min,
                           high_abb = "NY", low_abb = "MIN"), box_ny_min)
  saveRDS(tibble(
    round = "Finals",
    team_a = "New York Liberty",
    team_a_abb = "NY",
    team_b = "Minnesota Lynx",
    team_b_abb = "MIN"
  ), bracket_ny_min)

  res_dyn <- suppressMessages(run_finals_series_backtest(
    team_box_path = box_ny_min,
    out_path = out_ny_min,
    bracket_path = bracket_ny_min
  ))
  expect_true(file.exists(out_ny_min))
  expect_identical(unique(res_dyn$team_high_abb), "NY")
  expect_identical(unique(res_dyn$team_low_abb), "MIN")
})
