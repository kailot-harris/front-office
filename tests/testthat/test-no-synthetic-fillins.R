repo_root_for_fillin_tests <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = TRUE)

test_that("mlb_series_simulator emits NA/null instead of constant coalesce fill-ins and sorts NAs last", {
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)

  sim_env <- new.env(parent = globalenv())
  sim_env$PROJECT_DIR <- repo_root_for_fillin_tests
  suppressMessages(sys.source(file.path(repo_root_for_fillin_tests, "mlb_series_simulator.R"), envir = sim_env))

  teams_df <- tibble::tibble(
    team = c("AAA", "BBB"),
    team_name = c("Alpha", "Beta"),
    full_name = c("Alpha Club", "Beta Club"),
    league = c("AL", "NL"),
    division = c("East", "West"),
    ensemble_mean_wins = c(90, 85),
    variant_bottom_up_mean_wins = c(NA_real_, 85)
  )

  players_df <- tibble::tibble(
    player_id = c(
      "P_A1", "P_A2", "P_A3", "P_A4", "P_A5", "P_A6",
      "B_A1", "B_A2",
      "P_B1", "P_B2", "P_B3", "P_B4", "P_B5",
      "B_B1"
    ),
    mlbam_id = as.character(1001:1014),
    player_name = c(
      "SP Missing", "SP Known45", "SP Known40", "SP Known35", "SP Known30", "RP Known450",
      "Bat Missing", "Bat Known280",
      "B_P1", "B_P2", "B_P3", "B_P4", "B_P5",
      "B_B1"
    ),
    team = c(rep("AAA", 8), rep("BBB", 6)),
    player_type = c(
      rep("Pitcher", 6), rep("Batter", 2),
      rep("Pitcher", 5), "Batter"
    ),
    stat1_raw = c(
      rep(NA_real_, 6), NA_real_, 0.280,
      rep(NA_real_, 5), 0.300
    ),
    stat2_raw = c(
      rep(NA_real_, 6), NA_real_, 0.145,
      rep(NA_real_, 5), 0.150
    ),
    stat3_val = c(
      NA_real_, 45, 40, 35, 30, 25, NA_real_, 0.310,
      55, 50, 45, 40, 35, 0.320
    ),
    stat1_pooled = c(
      NA_real_, 3.50, 3.60, 3.70, 3.80, 4.50, NA_real_, NA_real_,
      3.40, 3.50, 3.60, 3.70, 3.80, NA_real_
    ),
    stat2_pooled = c(
      NA_real_, 3.40, 3.50, 3.60, 3.70, 4.40, NA_real_, NA_real_,
      3.30, 3.40, 3.50, 3.60, 3.70, NA_real_
    ),
    k_pct_pooled = c(
      NA_real_, 24.0, 23.0, 22.0, 21.5, 21.0, NA_real_, 19.0,
      25.0, 24.0, 23.0, 22.0, 21.0, 20.0
    ),
    bb_pct_pooled = c(
      NA_real_, 7.0, 7.2, 7.4, 7.6, 8.0, NA_real_, 9.0,
      6.5, 6.8, 7.0, 7.2, 7.5, 8.5
    ),
    count1_val = c(
      rep(NA_real_, 6), NA_real_, 15,
      rep(NA_real_, 5), 20
    ),
    proj_workload = c(
      200, 180, 170, 160, 150, 55, 500, 480,
      190, 180, 170, 160, 65, 520
    )
  )

  profiles <- sim_env$build_mlb_playoff_profiles(teams_df, players_df, list())
  aaa <- profiles$AAA

  # Sorting: SP Missing (stat3_val = NA) must sort AFTER known starters, not as 50
  expect_equal(aaa$starters[[1]]$playerName, "SP Known45")
  expect_equal(aaa$starters[[4]]$playerName, "SP Known30")

  # Relievers: RP Known450 (stat1_pooled = 4.50) must sort BEFORE SP Missing (NA)
  expect_equal(aaa$relievers[[1]]$playerName, "RP Known450")
  expect_equal(aaa$relievers[[2]]$playerName, "SP Missing")
  expect_true(is.na(aaa$relievers[[2]]$projEra))
  expect_true(is.na(aaa$relievers[[2]]$xFip))
  expect_true(is.na(aaa$relievers[[2]]$kPct))

  # Batters: Bat Known280 (wOBA = 0.280) must sort BEFORE Bat Missing (NA)
  expect_equal(aaa$lineupCore[[1]]$playerName, "Bat Known280")
  expect_equal(aaa$lineupCore[[2]]$playerName, "Bat Missing")
  expect_true(is.na(aaa$lineupCore[[2]]$wOBA))
  expect_true(is.na(aaa$lineupCore[[2]]$iso))
  expect_true(is.na(aaa$lineupCore[[2]]$obp))
  expect_true(is.na(aaa$lineupCore[[2]]$hr))
  expect_true(is.na(aaa$lineupCore[[2]]$kPct))
  expect_true(is.na(aaa$lineupCore[[2]]$bbPct))

  # Base Elo is NA when variant_bottom_up_mean_wins is NA and bullpen_lookup is absent
  expect_true(is.na(aaa$baseElo))

  # JSON round-trip with na = "null" emits null (not 52.0 / 3.50 / 0.315)
  parsed <- jsonlite::fromJSON(
    jsonlite::toJSON(aaa, auto_unbox = TRUE, na = "null"),
    simplifyVector = FALSE
  )
  expect_null(parsed$baseElo)
  expect_null(parsed$relievers[[2]]$xFip)
  expect_null(parsed$lineupCore[[2]]$wOBA)

  # Simulation handles NA baseElo / rGS without crashing
  sim_res <- sim_env$simulate_mlb_series("AAA", "BBB", "BBB", profiles, series_length = 3, n_sims = 50)
  expect_true(is.numeric(sim_res$winProbA))
  expect_false(is.na(sim_res$winProbA))
})

test_that("mlb_clutch_leverage_engine handles missing files cleanly and emits NA/null for missing stats", {
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)

  clutch_env <- new.env(parent = globalenv())
  clutch_env$PROJECT_DIR <- repo_root_for_fillin_tests
  suppressMessages(sys.source(file.path(repo_root_for_fillin_tests, "mlb_clutch_leverage_engine.R"), envir = clutch_env))

  # Missing input file should warn and return NULL cleanly without stop()
  expect_warning(
    res_missing <- clutch_env$run_mlb_clutch_engine(
      players_file = tempfile(fileext = ".json"),
      output_json = tempfile(fileext = ".json")
    ),
    "Missing"
  )
  expect_null(res_missing)

  # Missing stat fields should produce NA/null, never constant fallback numbers
  tmp_players <- tempfile(fileext = ".json")
  tmp_out <- tempfile(fileext = ".json")
  on.exit(unlink(c(tmp_players, tmp_out)), add = TRUE)

  players_input <- tibble::tibble(
    player_id = c("B1", "B2", "P1", "P2"),
    mlbam_id = c("101", "102", "201", "202"),
    player_name = c("Batter Missing", "Batter Known", "Pitcher Missing", "Pitcher Known"),
    team = c("NYY", "NYY", "LAD", "LAD"),
    player_type = c("Batter", "Batter", "Pitcher", "Pitcher"),
    position = c(NA_character_, "SS", NA_character_, "RP"),
    stat1_raw = c(NA_real_, 0.340, NA_real_, NA_real_),
    stat2_raw = c(NA_real_, 0.190, NA_real_, NA_real_),
    stat3_val = c(NA_real_, 0.360, NA_real_, 58.0),
    stat1_pooled = c(NA_real_, NA_real_, NA_real_, 3.20),
    stat2_pooled = c(NA_real_, NA_real_, NA_real_, 3.30),
    composite_zscore = c(NA_real_, 1.5, NA_real_, 1.2),
    proj_workload = c(NA_real_, 600, NA_real_, 65)
  )
  writeLines(jsonlite::toJSON(players_input, auto_unbox = TRUE, na = "null"), tmp_players)

  catalog <- suppressMessages(clutch_env$run_mlb_clutch_engine(
    players_file = tmp_players,
    post_file = tempfile(fileext = ".json"),
    fg_batters_file = tempfile(fileext = ".rds"),
    fg_pitchers_file = tempfile(fileext = ".rds"),
    boxscores_file = tempfile(fileext = ".rds"),
    output_json = tmp_out
  ))

  expect_true(file.exists(tmp_out))
  parsed <- jsonlite::fromJSON(tmp_out, simplifyVector = FALSE)
  expect_equal(parsed$totalProfiles, 4)

  by_id <- setNames(parsed$profiles, vapply(parsed$profiles, `[[`, character(1), "playerId"))

  # Missing batter fields must be JSON null (not 0.315 / 0.160 / 0.320 / 500 / "OF")
  expect_null(by_id$B1$position)
  expect_null(by_id$B1$baseMetricVal)
  expect_null(by_id$B1$rispSplit$pa)
  expect_null(by_id$B1$rispSplit$avg)

  # Missing pitcher fields must be JSON null (not 3.85 / 3.80 / 52.0 / 120)
  expect_null(by_id$P1$position)
  expect_null(by_id$P1$baseMetricVal)
  expect_null(by_id$P1$avgLeverageIndex)
  expect_null(by_id$P1$firemanStats$shutdowns)
})
