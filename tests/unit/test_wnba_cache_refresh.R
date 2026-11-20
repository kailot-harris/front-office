# ==============================================================================
# test_wnba_cache_refresh.R
# Offline unit tests for wnba_cache_utils.R and all 4 WNBA build-once caches
# (Issue #210):
#   - cache/wnba_espn_pbp_cache.rds    (pbp_engine.R::load_or_build_wnba_espn_pbp_cache)
#   - cache/wnba_pbp_cache.rds         (rapm_engine.R::load_or_build_wnba_pbp_cache)
#   - cache/wnba_shots_cache.rds       (shot_quality_engine.R::load_or_build_wnba_shots_cache)
#   - cache/player_box_scores_cache.rds (player_metrics.R::get_player_box_scores_chunked)
#
# 100% offline: uses temp sandboxes and injected mock fetch_fn callbacks; never
# makes live wehoop HTTP calls and never writes to production cache/ or data/.
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

# Ensure user library is accessible when running with RENV_ACTIVATE_PROJECT=FALSE
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
  library(tidyr)
})

source("config.R")
source("logging_utils.R")
source("wnba_cache_utils.R")

# Safely load an engine script into an isolated child environment, stripping any
# trailing auto-execution block (`if (!interactive()) ...` or `invisible(generate_team_shot_profiles())`)
# so sourcing in tests never runs the pipeline or touches production caches.
load_engine_isolated <- function(script_path, expected_tail_regex = NULL) {
  lines <- readLines(script_path, warn = FALSE)
  if (!is.null(expected_tail_regex)) {
    hit <- grep(expected_tail_regex, lines)
    if (length(hit) == 0L) {
      stop(sprintf("Expected auto-run footer matching '%s' not found in %s", expected_tail_regex, script_path))
    }
    cut_line <- tail(hit, 1L)
    lines <- lines[seq_len(cut_line - 1L)]
  }
  tmp_script <- tempfile(fileext = ".R")
  on.exit(unlink(tmp_script), add = TRUE)
  writeLines(lines, tmp_script)
  env <- new.env(parent = .GlobalEnv)
  suppressMessages(source(tmp_script, local = env))
  env
}

pbp_env <- load_engine_isolated("pbp_engine.R", expected_tail_regex = "^if \\(!interactive\\(\\)\\)")
rapm_env <- load_engine_isolated("rapm_engine.R", expected_tail_regex = "^if \\(!interactive\\(\\)\\)")
sq_env <- load_engine_isolated("shot_quality_engine.R", expected_tail_regex = "^invisible\\(generate_team_shot_profiles\\(\\)\\)")
pm_env <- load_engine_isolated("player_metrics.R", expected_tail_regex = NULL)

make_sandbox <- function(prefix = "wnba_cache_test_") {
  d <- tempfile(prefix)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

FIXED_NOW <- as.POSIXct("2026-09-01 12:00:00", tz = "UTC")

# ==============================================================================
# 1. Pure helpers in wnba_cache_utils.R
# ==============================================================================

test_that("wnba_cache_utils.R exports required helpers", {
  expect_true(exists("wnba_schedule_completed_max_date", mode = "function"))
  expect_true(exists("wnba_cache_max_date", mode = "function"))
  expect_true(exists("wnba_cache_decision", mode = "function"))
  expect_true(exists("wnba_replace_season_rows", mode = "function"))
})

test_that("wnba_schedule_completed_max_date prefers completed schedule and falls back to team box", {
  sb <- make_sandbox()
  on.exit(unlink(sb, recursive = TRUE), add = TRUE)

  sched_path <- file.path(sb, "wnba_schedule_cache.rds")
  box_path <- file.path(sb, "box_scores_cache.rds")

  # Neither exists -> NA
  expect_true(is.na(wnba_schedule_completed_max_date(2026, sched_path, box_path)))

  # Schedule exists with completed and uncompleted 2026 games + completed 2025 game
  sched_df <- tibble::tibble(
    season = c(2025L, 2026L, 2026L, 2026L),
    game_date = as.Date(c("2025-10-10", "2026-08-25", "2026-08-30", "2026-09-15")),
    is_completed = c(TRUE, TRUE, TRUE, FALSE)
  )
  saveRDS(sched_df, sched_path)

  box_df <- tibble::tibble(
    season = c(2025L, 2026L),
    game_date = as.Date(c("2025-10-10", "2026-08-28"))
  )
  saveRDS(box_df, box_path)

  expect_equal(
    wnba_schedule_completed_max_date(2026, sched_path, box_path),
    as.Date("2026-08-30")
  )

  # Schedule has only uncompleted 2026 games -> falls back to box cache
  sched_future <- tibble::tibble(
    season = c(2026L, 2026L),
    game_date = as.Date(c("2026-09-10", "2026-09-15")),
    is_completed = c(FALSE, FALSE)
  )
  saveRDS(sched_future, sched_path)
  expect_equal(
    wnba_schedule_completed_max_date(2026, sched_path, box_path),
    as.Date("2026-08-28")
  )

  # Missing schedule file -> falls back to box cache
  unlink(sched_path)
  expect_equal(
    wnba_schedule_completed_max_date(2026, sched_path, box_path),
    as.Date("2026-08-28")
  )

  # Corrupt schedule file + status_type_completed support check
  writeLines("not_an_rds", sched_path)
  expect_warning(
    res_corrupt <- wnba_schedule_completed_max_date(2026, sched_path, box_path),
    "Failed to read RDS"
  )
  expect_equal(res_corrupt, as.Date("2026-08-28"))

  sched_alt <- tibble::tibble(
    season = c(2026L, 2026L),
    game_date = c("2026-08-29T23:00:00Z", "2026-09-05T23:00:00Z"),
    status_type_completed = c(TRUE, FALSE)
  )
  saveRDS(sched_alt, sched_path)
  expect_equal(
    wnba_schedule_completed_max_date(2026, sched_path, box_path),
    as.Date("2026-08-29")
  )
})

test_that("wnba_cache_max_date extracts current_season max date across data.frame and rapm list shapes", {
  # Standard data.frame with game_date
  df_dated <- tibble::tibble(
    season = c(2025L, 2026L, 2026L),
    game_date = as.Date(c("2025-10-10", "2026-08-20", "2026-08-25"))
  )
  expect_equal(wnba_cache_max_date(df_dated, 2026), as.Date("2026-08-25"))
  expect_true(is.na(wnba_cache_max_date(df_dated, 2027)))

  # RAPM list shape with game_date in $possessions
  rapm_dated <- list(
    possessions = df_dated,
    pulled_at = as.POSIXct("2026-09-01 08:00:00", tz = "UTC")
  )
  expect_equal(wnba_cache_max_date(rapm_dated, 2026), as.Date("2026-08-25"))

  # RAPM list shape without game_date (real wehoop::load_wnba_stats_possessions schema)
  rapm_no_date <- list(
    possessions = tibble::tibble(game_id = c("1022500001", "1022600001"), season = c(2025L, 2026L)),
    pulled_at = as.POSIXct("2026-08-24 07:30:00", tz = "UTC")
  )
  expect_equal(wnba_cache_max_date(rapm_no_date, 2026), as.Date("2026-08-24"))
  expect_true(is.na(wnba_cache_max_date(rapm_no_date, 2027)))

  # Shots data.frame without game_date, with and without pulled_at attribute
  shots_no_date <- tibble::tibble(game_id = c("1022500001", "1022600001"), season = c(2025L, 2026L))
  expect_true(is.na(wnba_cache_max_date(shots_no_date, 2026)))
  attr(shots_no_date, "pulled_at") <- as.POSIXct("2026-08-26 15:00:00", tz = "UTC")
  expect_equal(wnba_cache_max_date(shots_no_date, 2026), as.Date("2026-08-26"))

  # NULL / empty shapes
  expect_true(is.na(wnba_cache_max_date(NULL, 2026)))
  expect_true(is.na(wnba_cache_max_date(tibble::tibble(), 2026)))
  expect_true(is.na(wnba_cache_max_date(list(), 2026)))
})

test_that("wnba_cache_decision covers fetch, refetch, and cache branches", {
  # Missing or empty -> fetch
  expect_identical(
    wnba_cache_decision(cache_exists = FALSE, schedule_max_date = as.Date("2026-08-30"), now = FIXED_NOW),
    "fetch"
  )
  expect_identical(
    wnba_cache_decision(cache_exists = TRUE, cache_non_empty = FALSE, schedule_max_date = as.Date("2026-08-30"), now = FIXED_NOW),
    "fetch"
  )

  # force_refresh -> fetch
  expect_identical(
    wnba_cache_decision(
      cache_exists = TRUE, cache_non_empty = TRUE,
      cache_max_date = as.Date("2026-08-30"),
      schedule_max_date = as.Date("2026-08-30"),
      cache_mtime = FIXED_NOW - 3600,
      now = FIXED_NOW, force_refresh = TRUE
    ),
    "fetch"
  )

  # Lagging + mtime >= 6h -> refetch
  expect_identical(
    wnba_cache_decision(
      cache_exists = TRUE, cache_non_empty = TRUE,
      cache_max_date = as.Date("2026-08-25"),
      schedule_max_date = as.Date("2026-08-30"),
      cache_mtime = FIXED_NOW - 7 * 3600,
      now = FIXED_NOW, min_refresh_age_hours = 6
    ),
    "refetch"
  )

  # Current season missing (cache_max_date = NA) + mtime >= 6h -> refetch
  expect_identical(
    wnba_cache_decision(
      cache_exists = TRUE, cache_non_empty = TRUE,
      cache_max_date = as.Date(NA),
      schedule_max_date = as.Date("2026-08-30"),
      cache_mtime = FIXED_NOW - 6 * 3600,
      now = FIXED_NOW, min_refresh_age_hours = 6
    ),
    "refetch"
  )

  # Lagging + mtime < 6h -> cache (cooldown)
  expect_identical(
    wnba_cache_decision(
      cache_exists = TRUE, cache_non_empty = TRUE,
      cache_max_date = as.Date("2026-08-25"),
      schedule_max_date = as.Date("2026-08-30"),
      cache_mtime = FIXED_NOW - 2 * 3600,
      now = FIXED_NOW, min_refresh_age_hours = 6
    ),
    "cache"
  )

  # Up to date + mtime >= 6h -> cache
  expect_identical(
    wnba_cache_decision(
      cache_exists = TRUE, cache_non_empty = TRUE,
      cache_max_date = as.Date("2026-08-30"),
      schedule_max_date = as.Date("2026-08-30"),
      cache_mtime = FIXED_NOW - 48 * 3600,
      now = FIXED_NOW, min_refresh_age_hours = 6
    ),
    "cache"
  )

  # No completed schedule games -> cache
  expect_identical(
    wnba_cache_decision(
      cache_exists = TRUE, cache_non_empty = TRUE,
      cache_max_date = as.Date("2026-08-25"),
      schedule_max_date = as.Date(NA),
      cache_mtime = FIXED_NOW - 48 * 3600,
      now = FIXED_NOW
    ),
    "cache"
  )

  # Historical-only request -> cache
  expect_identical(
    wnba_cache_decision(
      cache_exists = TRUE, cache_non_empty = TRUE,
      cache_max_date = as.Date("2026-08-25"),
      schedule_max_date = as.Date("2026-08-30"),
      cache_mtime = FIXED_NOW - 48 * 3600,
      now = FIXED_NOW,
      current_season_requested = FALSE
    ),
    "cache"
  )
})

test_that("wnba_replace_season_rows preserves historical seasons and coerces column types safely", {
  existing <- tibble::tibble(
    season = c(2024L, 2025L, 2026L),
    game_id = c(401600001L, 401700001L, 401800001L),
    game_date = as.Date(c("2024-09-01", "2025-09-01", "2026-08-20")),
    note = c("hist_2024", "hist_2025", "old_2026"),
    pts = c(10L, 12L, 8L),
    tag = factor(c("a", "b", "c"))
  )

  # New 2026 rows with incompatible types: character game_id, character date, all-NA logical note, double pts, extra col
  new_2026 <- tibble::tibble(
    season = c(2026, 2026),
    game_id = c("401800001", "401800002"),
    game_date = c("2026-08-20", "2026-08-30"),
    note = c(NA, NA),
    pts = c(8.0, 15.5),
    tag = c("c", "d"),
    extra_flag = c(TRUE, FALSE)
  )

  merged <- wnba_replace_season_rows(existing, new_2026, target_season = 2026)
  expect_equal(nrow(merged), 4L)
  expect_equal(sum(merged$season == 2024L), 1L)
  expect_equal(sum(merged$season == 2025L), 1L)
  expect_equal(sum(merged$season == 2026L), 2L)
  expect_equal(merged$note[merged$season == 2024L], "hist_2024")
  expect_equal(merged$note[merged$season == 2025L], "hist_2025")
  expect_true(all(is.na(merged$note[merged$season == 2026L])))
  expect_s3_class(merged$game_date, "Date")
  expect_equal(max(merged$game_date[merged$season == 2026L]), as.Date("2026-08-30"))

  # Empty / NULL new_df returns existing intact
  expect_identical(wnba_replace_season_rows(existing, NULL, 2026), existing)
  expect_identical(wnba_replace_season_rows(existing, existing[0, ], 2026), existing)
})

# ==============================================================================
# 2. End-to-end offline tests for all 4 cache writers
# ==============================================================================

test_that("pbp_engine::load_or_build_wnba_espn_pbp_cache handles fetch, refetch, cooldown, cache, and failure", {
  sb <- make_sandbox()
  on.exit(unlink(sb, recursive = TRUE), add = TRUE)

  cache_path <- file.path(sb, "wnba_espn_pbp_cache.rds")
  sched_path <- file.path(sb, "wnba_schedule_cache.rds")
  box_path <- file.path(sb, "box_scores_cache.rds")

  saveRDS(tibble::tibble(
    season = c(2026L, 2026L),
    game_date = as.Date(c("2026-08-30", "2026-09-10")),
    is_completed = c(TRUE, FALSE)
  ), sched_path)

  # Backward-compatible signature check
  expect_equal(names(formals(pbp_env$load_or_build_wnba_espn_pbp_cache))[1:2], c("seasons", "force_refresh"))

  # 1) Missing cache -> fetch all requested seasons
  called <- integer(0)
  mock_fetch <- function(s) {
    called <<- c(called, s)
    if (s == 2025L) {
      tibble::tibble(season = 2025L, game_id = 1L, game_date = as.Date("2025-10-01"), text = "hist")
    } else {
      tibble::tibble(season = 2026L, game_id = 2L, game_date = as.Date("2026-08-20"), text = "old26")
    }
  }
  res1 <- pbp_env$load_or_build_wnba_espn_pbp_cache(
    seasons = 2025:2026, force_refresh = FALSE,
    cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
    current_season = 2026L, now = FIXED_NOW, fetch_fn = mock_fetch, max_retries = 1L, sleep_sec = 0
  )
  expect_equal(called, c(2025L, 2026L))
  expect_equal(nrow(res1), 2L)
  expect_true(file.exists(cache_path))

  # 2) Lagging cache within < 6h cooldown -> stays "cache"
  Sys.setFileTime(cache_path, FIXED_NOW - 2 * 3600)
  called <- integer(0)
  res2 <- pbp_env$load_or_build_wnba_espn_pbp_cache(
    seasons = 2025:2026, force_refresh = FALSE,
    cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
    current_season = 2026L, now = FIXED_NOW, fetch_fn = mock_fetch, max_retries = 1L, sleep_sec = 0
  )
  expect_equal(called, integer(0))
  expect_equal(nrow(res2), 2L)

  # 3) Lagging cache >= 6h old -> refetches ONLY 2026, preserves 2025
  Sys.setFileTime(cache_path, FIXED_NOW - 10 * 3600)
  called <- integer(0)
  mock_fetch_new <- function(s) {
    called <<- c(called, s)
    tibble::tibble(
      season = 2026L,
      game_id = c("2", "3"),
      game_date = as.Date(c("2026-08-20", "2026-08-30")),
      text = c(NA, NA)
    )
  }
  res3 <- pbp_env$load_or_build_wnba_espn_pbp_cache(
    seasons = 2025:2026, force_refresh = FALSE,
    cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
    current_season = 2026L, now = FIXED_NOW, fetch_fn = mock_fetch_new, max_retries = 1L, sleep_sec = 0
  )
  expect_equal(called, 2026L)
  expect_equal(sum(res3$season == 2025L), 1L)
  expect_equal(res3$text[res3$season == 2025L], "hist")
  expect_equal(sum(res3$season == 2026L), 2L)
  expect_equal(max(res3$game_date[res3$season == 2026L]), as.Date("2026-08-30"))

  # 4) Up-to-date cache even when mtime >= 6h -> stays "cache"
  Sys.setFileTime(cache_path, FIXED_NOW - 48 * 3600)
  called <- integer(0)
  res4 <- pbp_env$load_or_build_wnba_espn_pbp_cache(
    seasons = 2025:2026, force_refresh = FALSE,
    cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
    current_season = 2026L, now = FIXED_NOW, fetch_fn = mock_fetch_new, max_retries = 1L, sleep_sec = 0
  )
  expect_equal(called, integer(0))
  expect_equal(nrow(res4), 3L)

  # 5) Failed / empty refetch keeps existing cache intact and warns
  saveRDS(tibble::tibble(season = 2026L, game_date = as.Date("2026-09-05"), is_completed = TRUE), sched_path)
  Sys.setFileTime(cache_path, FIXED_NOW - 10 * 3600)
  before_disk <- readRDS(cache_path)
  expect_warning(
    res5 <- pbp_env$load_or_build_wnba_espn_pbp_cache(
      seasons = 2025:2026, force_refresh = FALSE,
      cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
      current_season = 2026L, now = FIXED_NOW,
      fetch_fn = function(s) stop("simulated network failure"),
      max_retries = 1L, sleep_sec = 0
    ),
    "keeping existing cache intact"
  )
  expect_equal(res5, before_disk)
  expect_equal(readRDS(cache_path), before_disk)
})

test_that("rapm_engine::load_or_build_wnba_pbp_cache handles list shape, refetch, cooldown, cache, and failure", {
  sb <- make_sandbox()
  on.exit(unlink(sb, recursive = TRUE), add = TRUE)

  cache_path <- file.path(sb, "wnba_pbp_cache.rds")
  sched_path <- file.path(sb, "wnba_schedule_cache.rds")
  box_path <- file.path(sb, "box_scores_cache.rds")

  saveRDS(tibble::tibble(
    season = 2026L,
    game_date = as.Date("2026-08-30"),
    is_completed = TRUE
  ), sched_path)

  expect_equal(names(formals(rapm_env$load_or_build_wnba_pbp_cache))[1:2], c("seasons", "force_refresh"))

  # 1) Missing cache -> fetch all requested seasons (real no-game_date possessions schema)
  called_poss <- integer(0)
  called_shots <- integer(0)
  mock_poss <- function(yr) {
    called_poss <<- c(called_poss, yr)
    if (yr == 2025L) {
      tibble::tibble(game_id = "1022500001", season = 2025L, points = 2)
    } else {
      tibble::tibble(game_id = "1022600001", season = 2026L, points = 3)
    }
  }
  mock_shots <- function(yr) {
    called_shots <<- c(called_shots, yr)
    tibble::tibble(person_id = yr, player_name = paste0("Player_", yr))
  }

  t_old <- as.POSIXct("2026-08-20 10:00:00", tz = "UTC")
  res1 <- rapm_env$load_or_build_wnba_pbp_cache(
    seasons = 2025:2026, force_refresh = FALSE,
    cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
    current_season = 2026L, now = t_old,
    poss_fetch_fn = mock_poss, shots_fetch_fn = mock_shots
  )
  expect_equal(called_poss, c(2025L, 2026L))
  expect_equal(called_shots, c(2025L, 2026L))
  expect_true(is.list(res1) && !is.data.frame(res1))
  expect_equal(nrow(res1$possessions), 2L)
  expect_equal(res1$pulled_at, t_old)

  # 2) Lagging (pulled_at 2026-08-20 < 2026-08-30) but within < 6h cooldown -> stays "cache"
  Sys.setFileTime(cache_path, FIXED_NOW - 3 * 3600)
  called_poss <- integer(0)
  res2 <- rapm_env$load_or_build_wnba_pbp_cache(
    seasons = 2025:2026, force_refresh = FALSE,
    cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
    current_season = 2026L, now = FIXED_NOW,
    poss_fetch_fn = mock_poss, shots_fetch_fn = mock_shots
  )
  expect_equal(called_poss, integer(0))
  expect_equal(nrow(res2$possessions), 2L)

  # 3) Lagging >= 6h -> refetches ONLY 2026, preserves 2025 possessions and historical player_names
  Sys.setFileTime(cache_path, FIXED_NOW - 12 * 3600)
  called_poss <- integer(0)
  called_shots <- integer(0)
  mock_poss_new <- function(yr) {
    called_poss <<- c(called_poss, yr)
    tibble::tibble(game_id = c("1022600001", "1022600002"), season = 2026L, points = c(3, 2))
  }
  mock_shots_new <- function(yr) {
    called_shots <<- c(called_shots, yr)
    tibble::tibble(person_id = c("2026", "9999"), player_name = c("Player_2026_v2", "Rookie_2026"))
  }
  res3 <- rapm_env$load_or_build_wnba_pbp_cache(
    seasons = 2025:2026, force_refresh = FALSE,
    cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
    current_season = 2026L, now = FIXED_NOW,
    poss_fetch_fn = mock_poss_new, shots_fetch_fn = mock_shots_new
  )
  expect_equal(called_poss, 2026L)
  expect_equal(called_shots, 2026L)
  expect_equal(sum(res3$possessions$season == 2025L), 1L)
  expect_equal(sum(res3$possessions$season == 2026L), 2L)
  expect_true("2025" %in% as.character(res3$player_names$person_id))
  expect_true("9999" %in% as.character(res3$player_names$person_id))
  expect_equal(res3$pulled_at, FIXED_NOW)

  # 4) Up-to-date (pulled_at 2026-09-01 >= 2026-08-30) even 48h later -> stays "cache"
  later_now <- FIXED_NOW + 48 * 3600
  Sys.setFileTime(cache_path, FIXED_NOW)
  called_poss <- integer(0)
  res4 <- rapm_env$load_or_build_wnba_pbp_cache(
    seasons = 2025:2026, force_refresh = FALSE,
    cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
    current_season = 2026L, now = later_now,
    poss_fetch_fn = mock_poss_new, shots_fetch_fn = mock_shots_new
  )
  expect_equal(called_poss, integer(0))
  expect_equal(nrow(res4$possessions), 3L)

  # 5) Historical-only caller (seasons = 2025) does not trigger 2026 refetch even when schedule advances
  saveRDS(tibble::tibble(season = 2026L, game_date = as.Date("2026-09-05"), is_completed = TRUE), sched_path)
  Sys.setFileTime(cache_path, FIXED_NOW - 12 * 3600)
  called_poss <- integer(0)
  res_hist <- rapm_env$load_or_build_wnba_pbp_cache(
    seasons = 2025L, force_refresh = FALSE,
    cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
    current_season = 2026L, now = FIXED_NOW,
    poss_fetch_fn = mock_poss_new, shots_fetch_fn = mock_shots_new
  )
  expect_equal(called_poss, integer(0))

  # 6) Empty refetch warns and keeps existing list intact
  before_disk <- readRDS(cache_path)
  expect_warning(
    res5 <- rapm_env$load_or_build_wnba_pbp_cache(
      seasons = 2025:2026, force_refresh = FALSE,
      cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
      current_season = 2026L, now = FIXED_NOW,
      poss_fetch_fn = function(yr) tibble::tibble(),
      shots_fetch_fn = function(yr) NULL
    ),
    "keeping existing cache intact"
  )
  expect_equal(res5$possessions, before_disk$possessions)
  expect_equal(readRDS(cache_path)$possessions, before_disk$possessions)

  # 7) Single fetch_fn list-returning mock also works cleanly
  res6 <- rapm_env$load_or_build_wnba_pbp_cache(
    seasons = 2025:2026, force_refresh = FALSE,
    cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
    current_season = 2026L, now = FIXED_NOW,
    fetch_fn = function(yr) {
      list(
        possessions = tibble::tibble(game_id = "1022600099", season = 2026L, points = 2),
        player_names = tibble::tibble(person_id = "7777", player_name = "Test_Via_FetchFn")
      )
    }
  )
  expect_true("1022600099" %in% res6$possessions$game_id)
  expect_true("7777" %in% as.character(res6$player_names$person_id))
  expect_equal(sum(res6$possessions$season == 2025L), 1L)
})

test_that("shot_quality_engine::load_or_build_wnba_shots_cache handles fetch, refetch, box fallback, cooldown, cache, and failure", {
  sb <- make_sandbox()
  on.exit(unlink(sb, recursive = TRUE), add = TRUE)

  cache_path <- file.path(sb, "wnba_shots_cache.rds")
  sched_path <- file.path(sb, "missing_schedule.rds")
  box_path <- file.path(sb, "box_scores_cache.rds")

  # Test CACHE_TEAM_BOX fallback when schedule is missing
  saveRDS(tibble::tibble(season = 2026L, game_date = as.Date("2026-08-30")), box_path)

  expect_equal(names(formals(sq_env$load_or_build_wnba_shots_cache))[1:2], c("seasons", "force_refresh"))

  # 1) Missing cache -> fetch all seasons
  called <- integer(0)
  t_old <- as.POSIXct("2026-08-20 10:00:00", tz = "UTC")
  mock_shots <- function(yr) {
    called <<- c(called, yr)
    if (yr == 2025L) {
      tibble::tibble(game_id = "1022500001", season = 2025L, shot_distance = 12)
    } else {
      tibble::tibble(game_id = "1022600001", season = 2026L, shot_distance = 24)
    }
  }
  res1 <- sq_env$load_or_build_wnba_shots_cache(
    seasons = 2025:2026, force_refresh = FALSE,
    cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
    current_season = 2026L, now = t_old, fetch_fn = mock_shots
  )
  expect_equal(called, c(2025L, 2026L))
  expect_equal(nrow(res1), 2L)
  expect_equal(attr(res1, "pulled_at", exact = TRUE), t_old)

  # 2) Lagging within 6h cooldown -> stays "cache"
  Sys.setFileTime(cache_path, FIXED_NOW - 1 * 3600)
  called <- integer(0)
  res2 <- sq_env$load_or_build_wnba_shots_cache(
    seasons = 2025:2026, force_refresh = FALSE,
    cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
    current_season = 2026L, now = FIXED_NOW, fetch_fn = mock_shots
  )
  expect_equal(called, integer(0))

  # 3) Lagging >= 6h -> refetches ONLY 2026, preserves 2025
  Sys.setFileTime(cache_path, FIXED_NOW - 8 * 3600)
  called <- integer(0)
  mock_shots_new <- function(yr) {
    called <<- c(called, yr)
    tibble::tibble(
      game_id = c("1022600001", "1022600002"),
      season = 2026L,
      shot_distance = c(24, 3)
    )
  }
  res3 <- sq_env$load_or_build_wnba_shots_cache(
    seasons = 2025:2026, force_refresh = FALSE,
    cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
    current_season = 2026L, now = FIXED_NOW, fetch_fn = mock_shots_new
  )
  expect_equal(called, 2026L)
  expect_equal(sum(res3$season == 2025L), 1L)
  expect_equal(sum(res3$season == 2026L), 2L)
  expect_equal(attr(res3, "pulled_at", exact = TRUE), FIXED_NOW)

  # 4) Up-to-date >= 6h later -> stays "cache"
  later_now <- FIXED_NOW + 48 * 3600
  Sys.setFileTime(cache_path, FIXED_NOW)
  called <- integer(0)
  res4 <- sq_env$load_or_build_wnba_shots_cache(
    seasons = 2025:2026, force_refresh = FALSE,
    cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
    current_season = 2026L, now = later_now, fetch_fn = mock_shots_new
  )
  expect_equal(called, integer(0))
  expect_equal(nrow(res4), 3L)

  # 5) Failed refetch keeps existing cache intact and warns
  saveRDS(tibble::tibble(season = 2026L, game_date = as.Date("2026-09-05")), box_path)
  Sys.setFileTime(cache_path, FIXED_NOW - 10 * 3600)
  before_disk <- readRDS(cache_path)
  expect_warning(
    res5 <- sq_env$load_or_build_wnba_shots_cache(
      seasons = 2025:2026, force_refresh = FALSE,
      cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
      current_season = 2026L, now = FIXED_NOW,
      fetch_fn = function(yr) stop("simulated shots error")
    ),
    "keeping existing cache intact"
  )
  expect_equal(nrow(res5), nrow(before_disk))
  expect_equal(nrow(readRDS(cache_path)), nrow(before_disk))
})

test_that("player_metrics::get_player_box_scores_chunked handles fetch, refetch, cooldown, cache, failure, and backward-compat callers", {
  sb <- make_sandbox()
  on.exit(unlink(sb, recursive = TRUE), add = TRUE)

  cache_path <- file.path(sb, "player_box_scores_cache.rds")
  sched_path <- file.path(sb, "wnba_schedule_cache.rds")
  box_path <- file.path(sb, "box_scores_cache.rds")

  saveRDS(tibble::tibble(
    season = 2026L,
    game_date = as.Date("2026-08-30"),
    is_completed = TRUE
  ), sched_path)

  expect_equal(names(formals(pm_env$get_player_box_scores_chunked))[1:2], c("seasons", "force_refresh"))

  # 1) Missing cache -> fetch all seasons, normalize CONN->CON, filter exhibitions
  called <- integer(0)
  mock_pbox <- function(s) {
    called <<- c(called, s)
    if (s == 2025L) {
      tibble::tibble(
        season = c(2025L, 2025L),
        game_id = c(100L, 101L),
        game_date = as.Date(c("2025-09-10", "2025-09-10")),
        team_abbreviation = c("CONN", "SPO"),
        points = c(18, 99)
      )
    } else {
      tibble::tibble(
        season = 2026L,
        game_id = 200L,
        game_date = as.Date("2026-08-20"),
        team_abbreviation = "MIN",
        points = 22
      )
    }
  }
  res1 <- pm_env$get_player_box_scores_chunked(
    seasons = 2025:2026, force_refresh = FALSE,
    cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
    current_season = 2026L, now = FIXED_NOW, fetch_fn = mock_pbox, max_retries = 1L, sleep_sec = 0
  )
  expect_equal(called, c(2025L, 2026L))
  expect_equal(nrow(res1), 2L)
  expect_equal(res1$team_abbreviation[res1$season == 2025L], "CON")

  # 2) Lagging within < 6h cooldown -> stays "cache"
  Sys.setFileTime(cache_path, FIXED_NOW - 4 * 3600)
  called <- integer(0)
  res2 <- pm_env$get_player_box_scores_chunked(
    seasons = 2025:2026, force_refresh = FALSE,
    cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
    current_season = 2026L, now = FIXED_NOW, fetch_fn = mock_pbox, max_retries = 1L, sleep_sec = 0
  )
  expect_equal(called, integer(0))

  # 3) Lagging >= 6h -> refetches ONLY 2026, preserves 2025, applies filter_real_franchises
  Sys.setFileTime(cache_path, FIXED_NOW - 10 * 3600)
  called <- integer(0)
  mock_pbox_new <- function(s) {
    called <<- c(called, s)
    tibble::tibble(
      season = c(2026L, 2026L, 2026L),
      game_id = c("200", "201", "202"),
      game_date = as.Date(c("2026-08-20", "2026-08-30", "2026-08-30")),
      team_abbreviation = c("MIN", "NY", "COOP"),
      points = c(22, 25, 10)
    )
  }
  res3 <- pm_env$get_player_box_scores_chunked(
    seasons = 2025:2026, force_refresh = FALSE,
    cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
    current_season = 2026L, now = FIXED_NOW, fetch_fn = mock_pbox_new, max_retries = 1L, sleep_sec = 0
  )
  expect_equal(called, 2026L)
  expect_equal(sum(res3$season == 2025L), 1L)
  expect_equal(res3$team_abbreviation[res3$season == 2025L], "CON")
  expect_equal(sum(res3$season == 2026L), 2L)
  expect_false("COOP" %in% res3$team_abbreviation)
  expect_equal(max(res3$game_date[res3$season == 2026L]), as.Date("2026-08-30"))

  # 4) Up-to-date >= 6h later -> stays "cache" (also test 1-arg positional compatibility via schedule match)
  Sys.setFileTime(cache_path, FIXED_NOW - 48 * 3600)
  called <- integer(0)
  res4 <- pm_env$get_player_box_scores_chunked(
    2025:2026,
    cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
    current_season = 2026L, now = FIXED_NOW, fetch_fn = mock_pbox_new, max_retries = 1L, sleep_sec = 0
  )
  expect_equal(called, integer(0))
  expect_equal(nrow(res4), 3L)

  # 5) 2-arg positional force_refresh = TRUE triggers full fetch
  called <- integer(0)
  res_force <- pm_env$get_player_box_scores_chunked(
    2026L, TRUE,
    cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
    current_season = 2026L, now = FIXED_NOW, fetch_fn = mock_pbox_new, max_retries = 1L, sleep_sec = 0
  )
  expect_equal(called, 2026L)
  expect_equal(nrow(res_force), 2L)

  # 6) Failed / empty (and exhibition-only) refetch warns and does NOT stop() or wipe existing cache
  saveRDS(tibble::tibble(season = 2026L, game_date = as.Date("2026-09-05"), is_completed = TRUE), sched_path)
  Sys.setFileTime(cache_path, FIXED_NOW - 10 * 3600)
  before_disk <- readRDS(cache_path)
  expect_warning(
    res5 <- pm_env$get_player_box_scores_chunked(
      seasons = 2025:2026, force_refresh = FALSE,
      cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
      current_season = 2026L, now = FIXED_NOW,
      fetch_fn = function(s) stop("simulated player box error"),
      max_retries = 1L, sleep_sec = 0
    ),
    "keeping existing cache intact"
  )
  expect_equal(res5, before_disk)
  expect_equal(readRDS(cache_path), before_disk)

  expect_warning(
    res6 <- pm_env$get_player_box_scores_chunked(
      seasons = 2025:2026, force_refresh = FALSE,
      cache_path = cache_path, schedule_path = sched_path, team_box_path = box_path,
      current_season = 2026L, now = FIXED_NOW,
      fetch_fn = function(s) tibble::tibble(
        season = 2026L, game_id = "999", game_date = as.Date("2026-09-05"),
        team_abbreviation = "SPO", points = 10
      ),
      max_retries = 1L, sleep_sec = 0
    ),
    "keeping existing cache intact"
  )
  expect_equal(res6, before_disk)
  expect_equal(readRDS(cache_path), before_disk)
})

test_that("Zero-arg and (seasons, force_refresh) backward-compatible calls resolve defaults cleanly", {
  sb <- make_sandbox()
  on.exit(unlink(sb, recursive = TRUE), add = TRUE)

  sched_path <- file.path(sb, "wnba_schedule_cache.rds")
  box_path <- file.path(sb, "box_scores_cache.rds")
  saveRDS(tibble::tibble(
    season = as.integer(CURRENT_SEASON),
    game_date = as.Date("2026-08-30"),
    is_completed = TRUE
  ), sched_path)

  # Helper to bind sandbox cache paths inside an isolated engine child env
  bind_sandbox_paths <- function(env, pbp_path, shots_path, pbox_path) {
    env$CACHE_DIR <- sb
    env$CACHE_WNBA_SCHEDULE <- sched_path
    env$CACHE_TEAM_BOX <- box_path
    env$CACHE_PBP_EVENTS <- pbp_path
    env$CACHE_PBP_RAW <- pbp_path
    env$CACHE_PLAYER_BOX <- pbox_path
    invisible(TRUE)
  }

  espn_path <- file.path(sb, "wnba_espn_pbp_cache.rds")
  rapm_path <- file.path(sb, "wnba_pbp_cache.rds")
  shots_path <- file.path(sb, "wnba_shots_cache.rds")
  pbox_path <- file.path(sb, "player_box_scores_cache.rds")

  saveRDS(tibble::tibble(season = as.integer(CURRENT_SEASON), game_date = as.Date("2026-08-30"), id = 1L), espn_path)
  saveRDS(list(
    possessions = tibble::tibble(season = as.integer(CURRENT_SEASON), game_id = "1022600001"),
    player_names = tibble::tibble(person_id = 1L, player_name = "Test"),
    pulled_at = as.POSIXct("2026-08-30 12:00:00", tz = "UTC"),
    seasons = as.integer(CURRENT_SEASON)
  ), rapm_path)
  shots_df <- tibble::tibble(season = as.integer(CURRENT_SEASON), game_id = "1022600001")
  attr(shots_df, "pulled_at") <- as.POSIXct("2026-08-30 12:00:00", tz = "UTC")
  saveRDS(shots_df, shots_path)
  saveRDS(tibble::tibble(season = as.integer(CURRENT_SEASON), game_date = as.Date("2026-08-30"), athlete_id = 1L), pbox_path)

  # Restore sandbox bindings on exit so parent env isn't affected
  for (env in list(pbp_env, rapm_env, sq_env, pm_env)) {
    bind_sandbox_paths(env, espn_path, shots_path, pbox_path)
  }

  expect_equal(nrow(pbp_env$load_or_build_wnba_espn_pbp_cache()), 1L)
  expect_equal(nrow(pbp_env$load_or_build_wnba_espn_pbp_cache(ALL_SEASONS, FALSE)), 1L)

  expect_equal(nrow(rapm_env$load_or_build_wnba_pbp_cache()$possessions), 1L)
  expect_equal(nrow(rapm_env$load_or_build_wnba_pbp_cache(ALL_SEASONS, FALSE)$possessions), 1L)

  expect_equal(nrow(sq_env$load_or_build_wnba_shots_cache()), 1L)
  expect_equal(nrow(sq_env$load_or_build_wnba_shots_cache(ALL_SEASONS, FALSE)), 1L)

  expect_equal(nrow(pm_env$get_player_box_scores_chunked()), 1L)
  expect_equal(nrow(pm_env$get_player_box_scores_chunked(ALL_SEASONS)), 1L)
  expect_equal(nrow(pm_env$get_player_box_scores_chunked(ALL_SEASONS, FALSE)), 1L)
})
