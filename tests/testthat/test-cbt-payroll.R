# Ensure working directory is project root
if (!file.exists("config.R")) {
  proj_dir <- if (file.exists("../../config.R")) {
    normalizePath("../..", winslash = "/")
  } else {
    stop("Cannot locate the project root: no config.R at ./ or ../../. Run tests from the repo root or from tests/testthat/.", call. = FALSE)
  }
  setwd(proj_dir)
}

suppressPackageStartupMessages({
  library(testthat)
})

source("logging_utils.R")
source("config.R")
source("mlb_cbt_payroll_engine.R")

test_that("compute_cbt_tax() handles NULL/NA/NaN/Inf payroll without erroring (issue #125)", {
  expect_true(is.na(compute_cbt_tax(NA_real_, FALSE)))
  expect_true(is.na(compute_cbt_tax(NaN, FALSE)))
  expect_true(is.na(compute_cbt_tax(Inf, FALSE)))
  expect_true(is.na(compute_cbt_tax(-Inf, FALSE)))
  expect_true(is.na(compute_cbt_tax(NULL, FALSE)))
})

test_that("compute_cbt_tax() treats an NA repeater flag as FALSE with a warning (issue #125)", {
  expect_warning(
    result <- compute_cbt_tax(300, NA),
    "repeater"
  )
  expect_equal(result, compute_cbt_tax(300, FALSE))
})

test_that("compute_cbt_tax() is vectorised over payroll and is_repeater (issue #125)", {
  payrolls <- c(200, 250, 270, NA, Inf, 310)
  reps     <- c(FALSE, FALSE, TRUE, FALSE, TRUE, FALSE)

  result <- compute_cbt_tax(payrolls, reps)
  expect_length(result, length(payrolls))
  expect_equal(result[1], 0.0)          # under threshold
  expect_true(is.na(result[4]))         # NA payroll
  expect_true(is.na(result[5]))         # Inf payroll
  expect_false(is.na(result[6]))        # Tier 4 payroll still computes

  # Scalar input still works (not just vectors)
  expect_equal(compute_cbt_tax(200, FALSE), 0.0)
})

test_that("get_cbt_tier() returns 'Unknown' for NA/NaN/Inf payroll instead of erroring (issue #125)", {
  expect_equal(get_cbt_tier(NA_real_), "Unknown")
  expect_equal(get_cbt_tier(NaN), "Unknown")
  expect_equal(get_cbt_tier(Inf), "Unknown")
  expect_equal(get_cbt_tier(-Inf), "Unknown")
})

test_that("get_cbt_tier() is vectorised and matches expected tier bands (issue #125)", {
  payrolls <- c(200, 250, 270, 290, 310, NA)
  tiers <- get_cbt_tier(payrolls)

  expect_length(tiers, length(payrolls))
  expect_equal(tiers[1], "Under CBT Threshold")
  expect_equal(tiers[2], "Tier 1 Surcharge ($244M-$264M)")
  expect_equal(tiers[3], "Tier 2 Draft Penalty ($264M-$284M)")
  expect_equal(tiers[4], "Tier 3 Cohen Tax ($284M-$304M)")
  expect_equal(tiers[5], "Tier 4 Mega Tax (> $304M)")
  expect_equal(tiers[6], "Unknown")

  # Scalar input still works
  expect_equal(get_cbt_tier(200), "Under CBT Threshold")
})

test_that("team_alias() returns NA for missing/empty team codes and never maps them to 'LAD' (issue #135)", {
  expect_true(is.na(team_alias(NA)))
  expect_true(is.na(team_alias(NA_character_)))
  expect_true(is.na(team_alias("")))
  expect_true(is.na(team_alias("   ")))
  expect_true(is.na(team_alias(NULL)))
  expect_true(is.na(team_alias(character(0))))

  expect_equal(team_alias("OAK"), "ATH")
  expect_equal(team_alias("WAS"), "WSH")
  expect_equal(team_alias("CWS"), "CHW")
  expect_equal(team_alias("SFG"), "SF")
  expect_equal(team_alias("KCR"), "KC")
  expect_equal(team_alias("SDP"), "SD")
  expect_equal(team_alias("TBR"), "TB")
  expect_equal(team_alias("LAD"), "LAD")
})

test_that("mlb_cbt_payroll_engine.R does not contain hardcoded team_payroll_anchors or repeater_teams (issue #135)", {
  engine_lines <- readLines("mlb_cbt_payroll_engine.R", warn = FALSE)
  expect_false(any(grepl("team_payroll_anchors", engine_lines, fixed = TRUE)),
               info = "Unsourced hardcoded team_payroll_anchors must not exist in mlb_cbt_payroll_engine.R")
  expect_false(any(grepl("repeater_teams", engine_lines, fixed = TRUE)),
               info = "Hardcoded repeater_teams must not exist in mlb_cbt_payroll_engine.R")
})

test_that("run_mlb_cbt_payroll_engine() publishes null payroll/CBT fields when no sourced dataset exists (issue #135)", {
  tmp_root <- tempfile("cbt_no_src_")
  dir.create(file.path(tmp_root, "web", "public", "data"), recursive = TRUE)
  on.exit(unlink(tmp_root, recursive = TRUE), add = TRUE)

  teams_df <- data.frame(
    team = c("LAD", "NYY"),
    team_name = c("Dodgers", "Yankees"),
    full_name = c("Los Angeles Dodgers", "New York Yankees"),
    league = c("NL", "AL"),
    division = c("NL West", "AL East"),
    stringsAsFactors = FALSE
  )
  players_df <- data.frame(
    player_id = c("B_19755", "B_15640"),
    player_name = c("Shohei Ohtani", "Aaron Judge"),
    team = c("LAD", "NYY"),
    player_type = c("Batter", "Batter"),
    position = c("DH", "OF"),
    composite_zscore = c(2.5, 2.6),
    stringsAsFactors = FALSE
  )
  jsonlite::write_json(teams_df, file.path(tmp_root, "web", "public", "data", "projections_season_teams.json"), auto_unbox = TRUE)
  jsonlite::write_json(
    list(generated_at = "2026-04-01T12:00:00Z", season = 2026L, players = players_df),
    file.path(tmp_root, "web", "public", "data", "projections_season_players.json"),
    auto_unbox = TRUE
  )

  catalog <- suppressMessages(run_mlb_cbt_payroll_engine(
    root_dir = tmp_root,
    payroll_source_path = file.path(tmp_root, "data", "missing_payroll_source.json")
  ))

  out_raw <- jsonlite::fromJSON(file.path(tmp_root, "web", "public", "data", "cbt_payroll_sheet.json"), simplifyVector = FALSE)
  expect_null(out_raw$payrollSource)
  expect_null(out_raw$payrollAsOfDate)
  expect_null(out_raw$totalLeaguePayroll)
  expect_null(out_raw$totalLuxuryTaxCollected)
  expect_length(out_raw$teams, 2)

  for (tm in out_raw$teams) {
    expect_null(tm$payroll2026)
    expect_null(tm$payroll2027)
    expect_null(tm$payroll2028)
    expect_null(tm$cbtSpace2026)
    expect_null(tm$cbtTaxBill)
    expect_null(tm$totalCommitment)
    expect_null(tm$isRepeater)
    expect_equal(tm$cbtTier, "Unknown")
    expect_null(tm$penalties$draftPickDrop10)
    expect_null(tm$penalties$internationalPoolReduction)
    expect_null(tm$penalties$taxRateDescription)
    expect_null(tm$penalties$revenueShareEligible)
    contract_ids <- vapply(tm$contracts, function(c) c$playerId, character(1))
    expect_false(any(grepl("^DEPTH_", contract_ids)))
  }
})

test_that("run_mlb_cbt_payroll_engine() uses sourced cached payroll dataset with source & date recorded (issue #135)", {
  tmp_root <- tempfile("cbt_with_src_")
  dir.create(file.path(tmp_root, "web", "public", "data"), recursive = TRUE)
  dir.create(file.path(tmp_root, "data"), recursive = TRUE)
  on.exit(unlink(tmp_root, recursive = TRUE), add = TRUE)

  teams_df <- data.frame(
    team = c("LAD", "PIT"),
    team_name = c("Dodgers", "Pirates"),
    full_name = c("Los Angeles Dodgers", "Pittsburgh Pirates"),
    league = c("NL", "NL"),
    division = c("NL West", "NL Central"),
    stringsAsFactors = FALSE
  )
  players_df <- data.frame(
    player_id = c("B_19755"),
    player_name = c("Shohei Ohtani"),
    team = c("LAD"),
    player_type = c("Batter"),
    position = c("DH"),
    composite_zscore = c(2.5),
    stringsAsFactors = FALSE
  )
  jsonlite::write_json(teams_df, file.path(tmp_root, "web", "public", "data", "projections_season_teams.json"), auto_unbox = TRUE)
  jsonlite::write_json(
    list(generated_at = "2026-04-01T12:00:00Z", season = 2026L, players = players_df),
    file.path(tmp_root, "web", "public", "data", "projections_season_players.json"),
    auto_unbox = TRUE
  )

  src_path <- file.path(tmp_root, "data", "cbt_payroll_source.json")
  jsonlite::write_json(
    list(
      source = "Cot's Baseball Contracts",
      as_of_date = "2026-04-01",
      teams = list(
        LAD = list(payroll2026 = 310.0, isRepeater = TRUE)
      )
    ),
    src_path,
    auto_unbox = TRUE
  )

  suppressMessages(run_mlb_cbt_payroll_engine(root_dir = tmp_root, payroll_source_path = src_path))
  out_raw <- jsonlite::fromJSON(file.path(tmp_root, "web", "public", "data", "cbt_payroll_sheet.json"), simplifyVector = FALSE)

  expect_equal(out_raw$payrollSource, "Cot's Baseball Contracts")
  expect_equal(out_raw$payrollAsOfDate, "2026-04-01")
  expect_equal(out_raw$totalLeaguePayroll, 310.0)

  lad <- out_raw$teams[[1]]
  pit <- out_raw$teams[[2]]
  expect_equal(lad$teamAbbr, "LAD")
  expect_equal(lad$payroll2026, 310.0)
  expect_null(lad$payroll2027)
  expect_null(lad$payroll2028)
  expect_true(lad$isRepeater)
  expect_equal(pit$teamAbbr, "PIT")
  expect_null(pit$payroll2026)

  # Missing source metadata must error
  bad_src_path <- file.path(tmp_root, "data", "bad_source.json")
  jsonlite::write_json(list(teams = list(LAD = list(payroll2026 = 310.0))), bad_src_path, auto_unbox = TRUE)
  expect_error(load_sourced_payroll(bad_src_path), "source")
})
