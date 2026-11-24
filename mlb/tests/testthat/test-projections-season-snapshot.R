if (!file.exists("config.R")) {
  proj_dir <- if (file.exists("../../config.R")) {
    normalizePath("../..", winslash = "/")
  } else {
    stop("Cannot locate the project root: no config.R at ./ or ../../.", call. = FALSE)
  }
  setwd(proj_dir)
}

suppressPackageStartupMessages({
  library(testthat)
  library(jsonlite)
})

source("config.R")

make_players_df <- function() {
  data.frame(
    player_id = c("B_19755", "P_543037"),
    mlbam_id = c("660271", "543037"),
    player_name = c("Shohei Ohtani", "Gerrit Cole"),
    team = c("LAD", "NYY"),
    player_type = c("Batter", "Pitcher"),
    position = c("B", "SP"),
    age = c(31L, 35L),
    observed_workload = c(650, 180),
    proj_workload = c(620, 175),
    park_factor = c(1.0, 1.0),
    stat1_label = c("wOBA", "xFIP"),
    stat1_raw = c(0.410, 3.10),
    stat1_pooled = c(0.390, 3.25),
    stat2_label = c("ISO", "K%"),
    stat2_raw = c(0.280, 29.0),
    stat2_pooled = c(0.265, 28.0),
    stat3_label = c("OBP", "BB%"),
    stat3_val = c(0.395, 6.5),
    k_pct_pooled = c(22.0, 28.0),
    bb_pct_pooled = c(13.0, 6.5),
    count1_label = c("HR", "SO"),
    count1_val = c(44, 210),
    composite_zscore = c(2.5, 1.9),
    stringsAsFactors = FALSE
  )
}

test_that("read_projections_season_players validates season and timestamp metadata", {
  tmp_dir <- tempfile("proj_snap_")
  dir.create(tmp_dir, recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  # 1. Valid top-level metadata object
  f_valid <- file.path(tmp_dir, "valid.json")
  jsonlite::write_json(
    list(generated_at = "2027-04-02T15:30:00Z", season = 2027L, players = make_players_df()),
    f_valid,
    auto_unbox = TRUE
  )
  res_ok <- read_projections_season_players(f_valid, expected_season = 2027L, caller = "TEST")
  expect_true(res_ok$ok)
  expect_equal(res_ok$season, 2027L)
  expect_equal(res_ok$generated_at, "2027-04-02T15:30:00Z")
  expect_equal(res_ok$as_of_date, "2027-04-02")
  expect_equal(nrow(res_ok$players), 2L)

  # 2. Valid nested metadata object
  f_meta <- file.path(tmp_dir, "valid_meta.json")
  jsonlite::write_json(
    list(metadata = list(generated_at = "2027-04-03T10:00:00Z", season = 2027L), players = make_players_df()),
    f_meta,
    auto_unbox = TRUE
  )
  res_meta <- read_projections_season_players(f_meta, expected_season = 2027L, caller = "TEST")
  expect_true(res_meta$ok)
  expect_equal(res_meta$season, 2027L)
  expect_equal(res_meta$as_of_date, "2027-04-03")

  # 3. Wrong season logs >>> [FAIL] and returns ok = FALSE
  msgs_mismatch <- character(0)
  res_mismatch <- withCallingHandlers(
    read_projections_season_players(f_valid, expected_season = 2028L, caller = "TEST"),
    message = function(m) {
      msgs_mismatch <<- c(msgs_mismatch, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  expect_false(res_mismatch$ok)
  expect_null(res_mismatch$players)
  expect_true(any(grepl(">>> \\[FAIL\\]", msgs_mismatch)))
  expect_true(any(grepl("season mismatch", msgs_mismatch)))

  # 4. Legacy bare array without season metadata logs >>> [FAIL] and returns ok = FALSE
  f_bare <- file.path(tmp_dir, "bare.json")
  jsonlite::write_json(make_players_df(), f_bare, auto_unbox = TRUE)
  msgs_bare <- character(0)
  res_bare <- withCallingHandlers(
    read_projections_season_players(f_bare, expected_season = 2027L, caller = "TEST"),
    message = function(m) {
      msgs_bare <<- c(msgs_bare, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  expect_false(res_bare$ok)
  expect_true(any(grepl(">>> \\[FAIL\\]", msgs_bare)))

  # 5. Missing generated_at logs >>> [FAIL] and returns ok = FALSE
  f_nots <- file.path(tmp_dir, "no_ts.json")
  jsonlite::write_json(list(season = 2027L, players = make_players_df()), f_nots, auto_unbox = TRUE)
  msgs_nots <- character(0)
  res_nots <- withCallingHandlers(
    read_projections_season_players(f_nots, expected_season = 2027L, caller = "TEST"),
    message = function(m) {
      msgs_nots <<- c(msgs_nots, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  expect_false(res_nots$ok)
  expect_true(any(grepl(">>> \\[FAIL\\]", msgs_nots)))
})

test_that("tools/export_web_data.R emits season and generated_at on projections_season_players.json", {
  src <- paste(readLines("tools/export_web_data.R", warn = FALSE), collapse = "\n")
  expect_true(grepl("players_payload\\s*<-\\s*list\\(", src))
  expect_true(grepl("generated_at\\s*=\\s*format\\(Sys\\.time\\(", src))
  expect_true(grepl("season\\s*=\\s*as\\.integer\\(season\\)", src))
  expect_true(grepl("players\\s*=\\s*player_projections", src))
})

test_that("all 5 readers refuse wrong-season projections with >>> [FAIL] and clean return without writing", {
  tmp_root <- tempfile("readers_136_")
  data_dir <- file.path(tmp_root, "web", "public", "data")
  cache_dir <- file.path(tmp_root, "cache")
  dir.create(data_dir, recursive = TRUE)
  dir.create(cache_dir, recursive = TRUE)
  on.exit(unlink(tmp_root, recursive = TRUE), add = TRUE)

  players_2026_file <- file.path(data_dir, "projections_season_players.json")
  jsonlite::write_json(
    list(generated_at = "2026-10-31T04:00:00Z", season = 2026L, players = make_players_df()),
    players_2026_file,
    auto_unbox = TRUE
  )
  teams_df <- data.frame(
    team = c("LAD", "NYY"),
    team_name = c("Dodgers", "Yankees"),
    full_name = c("Los Angeles Dodgers", "New York Yankees"),
    league = c("NL", "AL"),
    division = c("NL West", "AL East"),
    stringsAsFactors = FALSE
  )
  jsonlite::write_json(teams_df, file.path(data_dir, "projections_season_teams.json"), auto_unbox = TRUE)
  jsonlite::write_json(list(teams = list()), file.path(data_dir, "cbt_payroll_sheet.json"), auto_unbox = TRUE)

  # 1. mlb_clutch_leverage_engine.R
  source("mlb_clutch_leverage_engine.R")
  clutch_out <- file.path(data_dir, "clutch_leverage_metrics.json")
  msgs <- character(0)
  res <- withCallingHandlers(
    run_mlb_clutch_engine(
      players_file = players_2026_file,
      post_file = NULL,
      fg_batters_file = file.path(tmp_root, "missing_fg_b.rds"),
      fg_pitchers_file = file.path(tmp_root, "missing_fg_p.rds"),
      boxscores_file = file.path(tmp_root, "missing_box.rds"),
      output_json = clutch_out,
      expected_season = 2027L
    ),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  expect_null(res)
  expect_false(file.exists(clutch_out))
  expect_true(any(grepl(">>> \\[FAIL\\]", msgs)))

  # 2. mlb_series_simulator.R
  source("mlb_series_simulator.R")
  series_out <- file.path(data_dir, "playoff_series_matchups.json")
  msgs <- character(0)
  res <- withCallingHandlers(
    run_mlb_series_simulator(root_dir = tmp_root, expected_season = 2027L),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  expect_null(res)
  expect_false(file.exists(series_out))
  expect_true(any(grepl(">>> \\[FAIL\\]", msgs)))

  # 3. mlb_cbt_payroll_engine.R
  source("mlb_cbt_payroll_engine.R")
  unlink(file.path(data_dir, "cbt_payroll_sheet.json"))
  cbt_out <- file.path(data_dir, "cbt_payroll_sheet.json")
  msgs <- character(0)
  res <- withCallingHandlers(
    run_mlb_cbt_payroll_engine(
      root_dir = tmp_root,
      payroll_source_path = file.path(tmp_root, "missing_src.json"),
      expected_season = 2027L
    ),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  expect_null(res)
  expect_false(file.exists(cbt_out))
  expect_true(any(grepl(">>> \\[FAIL\\]", msgs)))

  # 4. tools/export_player_spatial_maps.R
  source("tools/export_player_spatial_maps.R")
  spatial_idx <- file.path(data_dir, "spatial_index.json")
  msgs <- character(0)
  res <- withCallingHandlers(
    export_player_spatial_maps(out_dir = data_dir, season = 2027L, root_dir = tmp_root),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  expect_null(res)
  expect_false(file.exists(spatial_idx))
  expect_true(any(grepl(">>> \\[FAIL\\]", msgs)))

  # 5. tools/offseason/capture_baseline_s0.R
  jsonlite::write_json(list(teams = list()), file.path(data_dir, "cbt_payroll_sheet.json"), auto_unbox = TRUE)
  s0_env <- new.env(parent = globalenv())
  sys.source("tools/offseason/capture_baseline_s0.R", envir = s0_env)
  s0_out <- file.path(cache_dir, "league_state_baseline.json")
  msgs <- character(0)
  res <- withCallingHandlers(
    s0_env$main(root_dir = tmp_root, expected_season = 2027L),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  expect_null(res)
  expect_false(file.exists(s0_out))
  expect_true(any(grepl(">>> \\[FAIL\\]", msgs)))
})

test_that("readers record projectionsSnapshot season and as_of_date in published payloads", {
  tmp_root <- tempfile("snap_prov_")
  data_dir <- file.path(tmp_root, "web", "public", "data")
  dir.create(data_dir, recursive = TRUE)
  on.exit(unlink(tmp_root, recursive = TRUE), add = TRUE)

  players_file <- file.path(data_dir, "projections_season_players.json")
  jsonlite::write_json(
    list(generated_at = "2026-10-31T04:00:00Z", season = 2026L, players = make_players_df()),
    players_file,
    auto_unbox = TRUE
  )
  teams_df <- data.frame(
    team = c("LAD", "NYY"),
    team_name = c("Dodgers", "Yankees"),
    full_name = c("Los Angeles Dodgers", "New York Yankees"),
    league = c("NL", "AL"),
    division = c("NL West", "AL East"),
    stringsAsFactors = FALSE
  )
  jsonlite::write_json(teams_df, file.path(data_dir, "projections_season_teams.json"), auto_unbox = TRUE)

  # CBT engine records projectionsSnapshot
  source("mlb_cbt_payroll_engine.R")
  suppressMessages(run_mlb_cbt_payroll_engine(
    root_dir = tmp_root,
    payroll_source_path = file.path(tmp_root, "missing_src.json"),
    expected_season = 2026L
  ))
  cbt_out <- jsonlite::fromJSON(file.path(data_dir, "cbt_payroll_sheet.json"), simplifyVector = FALSE)
  expect_equal(cbt_out$projectionsSnapshot$season, 2026L)
  expect_equal(cbt_out$projectionsSnapshot$as_of_date, "2026-10-31")

  # Clutch engine records projectionsSnapshot
  source("mlb_clutch_leverage_engine.R")
  clutch_out_path <- file.path(data_dir, "clutch_leverage_metrics.json")
  suppressMessages(run_mlb_clutch_engine(
    players_file = players_file,
    post_file = NULL,
    fg_batters_file = file.path(tmp_root, "missing_fg_b.rds"),
    fg_pitchers_file = file.path(tmp_root, "missing_fg_p.rds"),
    boxscores_file = file.path(tmp_root, "missing_box.rds"),
    output_json = clutch_out_path,
    expected_season = 2026L
  ))
  clutch_out <- jsonlite::fromJSON(clutch_out_path, simplifyVector = FALSE)
  expect_equal(clutch_out$projectionsSnapshot$season, 2026L)
  expect_equal(clutch_out$projectionsSnapshot$as_of_date, "2026-10-31")

  # Spatial maps exporter records projectionsSnapshot on both spatial/<id>.json and spatial_index.json
  source("tools/export_player_spatial_maps.R")
  suppressMessages(export_player_spatial_maps(out_dir = data_dir, season = 2026L, root_dir = tmp_root))
  sp_idx <- jsonlite::fromJSON(file.path(data_dir, "spatial_index.json"), simplifyVector = FALSE)
  expect_equal(sp_idx[[1]]$projectionsSnapshot$season, 2026L)
  expect_equal(sp_idx[[1]]$projectionsSnapshot$as_of_date, "2026-10-31")
  sp_p1 <- jsonlite::fromJSON(file.path(data_dir, "spatial", "B_19755.json"), simplifyVector = FALSE)
  expect_equal(sp_p1$projectionsSnapshot$season, 2026L)
  expect_equal(sp_p1$projectionsSnapshot$as_of_date, "2026-10-31")
})
