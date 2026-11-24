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
  library(dplyr)
  library(jsonlite)
})

assign("PROJECT_DIR", getwd(), envir = globalenv())
source("logging_utils.R")
source("config.R")
source("mlb_ingest.R")
source("tools/export_spatial_analytics.R")
source("tools/export_player_spatial_maps.R")

# Run an expression against an isolated temporary MLB_CACHE_ROOT without
# touching the repository's cache/ directory.
with_temp_cache_root <- function(expr) {
  tmp_root <- tempfile("mlb-ingest-test-")
  tmp_cache <- file.path(tmp_root, "cache")
  dir.create(tmp_cache, recursive = TRUE, showWarnings = FALSE)
  old_cache <- get("MLB_CACHE_ROOT", envir = globalenv())
  on.exit({
    assign("MLB_CACHE_ROOT", old_cache, envir = globalenv())
    unlink(tmp_root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  assign("MLB_CACHE_ROOT", tmp_cache, envir = globalenv())
  force(expr)
}

make_mock_boxscore_json <- function(pk) {
  list(
    teams = list(
      away = list(
        team = list(id = 147L, name = "New York Yankees"),
        teamStats = list(
          batting = list(runs = 4L, hits = 8L, rbi = 4L, homeRuns = 1L, strikeOuts = 7L, baseOnBalls = 3L),
          pitching = list(strikeOuts = 9L, baseOnBalls = 2L, runs = 2L),
          fielding = list(errors = 0L)
        ),
        pitchers = list(1L, 2L, 3L)
      ),
      home = list(
        team = list(id = 111L, name = "Boston Red Sox"),
        teamStats = list(
          batting = list(runs = 2L, hits = 6L, rbi = 2L, homeRuns = 0L, strikeOuts = 9L, baseOnBalls = 2L),
          pitching = list(strikeOuts = 7L, baseOnBalls = 3L, runs = 4L),
          fielding = list(errors = 1L)
        ),
        pitchers = list(4L, 5L)
      )
    )
  )
}

test_that("resolve_current_season() and statcast_cache_path() resolve dynamically", {
  expect_equal(resolve_current_season(), as.integer(MLB_CURRENT_SEASON))

  with_temp_cache_root({
    sc_path <- statcast_cache_path(season = 2026L)
    expect_match(sc_path, "/ingest/statcast_pitches_2026\\.rds$")
    expect_false(grepl("2024-04-0", sc_path, fixed = TRUE))

    sc_default <- statcast_cache_path()
    expect_equal(basename(sc_default), sprintf("statcast_pitches_%d.rds", resolve_current_season()))
  })

  # Fallback when MLB_CURRENT_SEASON is temporarily unavailable
  eval_env <- new.env(parent = baseenv())
  eval_env$CURRENT_SEASON <- 2028L
  fn <- resolve_current_season
  environment(fn) <- eval_env
  expect_equal(fn(), 2028L)

  eval_env2 <- new.env(parent = baseenv())
  fn2 <- resolve_current_season
  environment(fn2) <- eval_env2
  expect_equal(fn2(), as.integer(format(Sys.Date(), "%Y")))
})

test_that("derive_statcast_window() derives min/max dates strictly from completed slate games", {
  sched <- tibble::tibble(
    game_pk               = c(1L, 2L, 3L, 4L, 5L, 6L, 7L),
    official_date         = c("2026-02-21", "2026-03-25", "2026-04-12", "2026-10-03", "2026-10-18", "2026-10-20", "2026-10-28"),
    game_type             = c("S",          "R",          "R",          "F",          "L",          "L",          "W"),
    status_detailed_state = c("Final",      "Final",      "Postponed",  "Completed Early", "Final", "In Progress", "Scheduled"),
    home_score            = c(5L,           3L,           NA_integer_,  4L,           6L,           1L,           NA_integer_),
    away_score            = c(2L,           1L,           NA_integer_,  1L,           2L,           0L,           NA_integer_)
  )

  win <- derive_statcast_window(sched, season = 2026L)
  expect_false(is.null(win))
  expect_equal(win$start_date, "2026-03-25")
  expect_equal(win$end_date, "2026-10-18")
  expect_equal(win$n_games, 3L)

  # Direct MLB Stats API fallback schema (ISO game_date + status column)
  sched_api <- tibble::tibble(
    game_pk   = c(10L, 11L, 12L),
    game_date = c("2026-04-02T23:05:00Z", "2026-07-04T18:10:00Z", "2026-09-27T19:10:00Z"),
    game_type = c("R", "R", "R"),
    status    = c("Final", "Final", "Scheduled")
  )
  win_api <- derive_statcast_window(sched_api, season = 2026L)
  expect_equal(win_api$start_date, "2026-04-02")
  expect_equal(win_api$end_date, "2026-07-04")
  expect_equal(win_api$n_games, 2L)

  # Score-only schedule without status column uses non-NA scores
  sched_scores <- tibble::tibble(
    game_pk    = c(20L, 21L, 22L),
    game_date  = c("2026-04-05", "2026-06-15", "2026-09-20"),
    home_score = c(4L, 2L, NA_integer_),
    away_score = c(1L, 7L, NA_integer_)
  )
  win_scores <- derive_statcast_window(sched_scores, season = 2026L)
  expect_equal(win_scores$start_date, "2026-04-05")
  expect_equal(win_scores$end_date, "2026-06-15")
  expect_equal(win_scores$n_games, 2L)

  # Empty or unplayed schedule returns NULL
  expect_null(derive_statcast_window(tibble::tibble()))
  expect_null(derive_statcast_window(sched[sched$status_detailed_state == "Scheduled", ]))
})

test_that("build_date_chunks() partitions ranges into contiguous non-overlapping sub-windows", {
  chunks <- build_date_chunks("2026-04-01", "2026-04-12", chunk_days = 5L)
  expect_length(chunks, 3L)
  expect_equal(chunks[[1]], list(start_date = "2026-04-01", end_date = "2026-04-05"))
  expect_equal(chunks[[2]], list(start_date = "2026-04-06", end_date = "2026-04-10"))
  expect_equal(chunks[[3]], list(start_date = "2026-04-11", end_date = "2026-04-12"))
  expect_length(build_date_chunks("2026-04-10", "2026-04-01"), 0L)
})

test_that("ingest_mlb_boxscores() processes > 100 game_pks without capping", {
  with_temp_cache_root({
    pks <- c(700001:700150, 700001L, NA_integer_)
    called_pks <- integer(0)
    mock_reader <- function(url) {
      m <- regmatches(url, regexec("/game/([0-9]+)/boxscore$", url))[[1]]
      pk <- as.integer(m[2])
      called_pks <<- c(called_pks, pk)
      make_mock_boxscore_json(pk)
    }

    res <- ingest_mlb_boxscores(
      game_pks = pks,
      season = 2025L,
      force_refresh = TRUE,
      url_reader = mock_reader
    )

    expect_length(called_pks, 150L)
    expect_equal(length(unique(res$game_pk)), 150L)
    expect_equal(nrow(res), 300L)
    expect_true(file.exists(cache_path("ingest", "mlb_boxscores_2025.rds", create = FALSE)))
  })
})

test_that("current-season caches refresh while historical seasons cache cleanly", {
  with_temp_cache_root({
    curr <- resolve_current_season()
    hist <- curr - 2L

    # 1. Historical season caches and skips re-fetch unless force_refresh = TRUE
    hist_box_file <- cache_path("ingest", sprintf("mlb_boxscores_%d.rds", hist))
    saveRDS(tibble::tibble(game_pk = 1L, side = "home"), hist_box_file)

    hist_calls <- 0L
    hist_cached <- ingest_mlb_boxscores(
      game_pks = 999L,
      season = hist,
      force_refresh = FALSE,
      refresh_current = TRUE,
      url_reader = function(url) { hist_calls <<- hist_calls + 1L; make_mock_boxscore_json(999L) }
    )
    expect_equal(hist_calls, 0L)
    expect_equal(hist_cached$game_pk, 1L)

    # 2. Current season refreshes even when file exists and force_refresh = FALSE
    curr_box_file <- cache_path("ingest", sprintf("mlb_boxscores_%d.rds", curr))
    saveRDS(tibble::tibble(game_pk = 1L, side = "home"), curr_box_file)

    curr_calls <- 0L
    curr_refreshed <- ingest_mlb_boxscores(
      game_pks = c(101L, 102L),
      season = curr,
      force_refresh = FALSE,
      refresh_current = TRUE,
      url_reader = function(url) { curr_calls <<- curr_calls + 1L; make_mock_boxscore_json(101L) }
    )
    expect_equal(curr_calls, 2L)
    expect_equal(nrow(curr_refreshed), 4L)

    # 3. Suppressing current-season refresh explicitly in tests reads cache
    suppressed_calls <- 0L
    curr_suppressed <- ingest_mlb_boxscores(
      game_pks = c(103L),
      season = curr,
      force_refresh = FALSE,
      refresh_current = FALSE,
      url_reader = function(url) { suppressed_calls <<- suppressed_calls + 1L; make_mock_boxscore_json(103L) }
    )
    expect_equal(suppressed_calls, 0L)
    expect_equal(nrow(curr_suppressed), 4L)

    # 4. Same refresh policy applies to Statcast season cache
    sc_hist_file <- statcast_cache_path(hist)
    saveRDS(tibble::tibble(pitch_id = 1L), sc_hist_file)
    sc_hist_calls <- 0L
    sc_hist <- ingest_statcast_pitches(
      start_date = sprintf("%d-04-01", hist),
      end_date = sprintf("%d-04-02", hist),
      season = hist,
      force_refresh = FALSE,
      search_fn = function(s, e) { sc_hist_calls <<- sc_hist_calls + 1L; tibble::tibble(pitch_id = 99L) }
    )
    expect_equal(sc_hist_calls, 0L)
    expect_equal(sc_hist$pitch_id, 1L)

    sc_curr_file <- statcast_cache_path(curr)
    saveRDS(tibble::tibble(pitch_id = 1L), sc_curr_file)
    sc_curr_calls <- 0L
    sc_curr <- ingest_statcast_pitches(
      start_date = sprintf("%d-04-01", curr),
      end_date = sprintf("%d-04-08", curr),
      season = curr,
      force_refresh = FALSE,
      search_fn = function(s, e) {
        sc_curr_calls <<- sc_curr_calls + 1L
        tibble::tibble(pitch_id = sc_curr_calls, window = paste(s, e, sep = "_"))
      }
    )
    expect_equal(sc_curr_calls, 2L)
    expect_equal(nrow(sc_curr), 2L)
    expect_true(all(sc_curr$sz_reference_point == ifelse(curr >= 2026L, "middle_of_plate_ABS", "front_of_plate")))

    # 5. Schedule cache follows the same historical-cache vs current-refresh policy
    sched_hist_file <- cache_path("ingest", sprintf("mlb_schedule_%d.rds", hist))
    saveRDS(tibble::tibble(game_pk = 11L, game_date = sprintf("%d-05-01", hist), status = "Final"), sched_hist_file)
    sched_hist_calls <- 0L
    sched_hist <- ingest_mlb_schedule(
      season = hist,
      force_refresh = FALSE,
      url_reader = function(u) { sched_hist_calls <<- sched_hist_calls + 1L; list(dates = list()) }
    )
    expect_equal(sched_hist_calls, 0L)
    expect_equal(sched_hist$game_pk, 11L)

    sched_curr_file <- cache_path("ingest", sprintf("mlb_schedule_%d.rds", curr))
    saveRDS(tibble::tibble(game_pk = 22L, game_date = sprintf("%d-05-01", curr), status = "Final"), sched_curr_file)
    sched_curr_calls <- 0L
    sched_curr <- ingest_mlb_schedule(
      season = curr,
      force_refresh = FALSE,
      url_reader = function(u) {
        sched_curr_calls <<- sched_curr_calls + 1L
        list(dates = list(list(
          date = sprintf("%d-05-02", curr),
          games = list(list(
            gamePk = 33L,
            gameType = "R",
            status = list(detailedState = "Final"),
            teams = list(
              away = list(team = list(id = 147L, name = "A"), score = 1L),
              home = list(team = list(id = 111L, name = "B"), score = 2L)
            ),
            venue = list(id = 1L, name = "Park")
          ))
        )))
      }
    )
    expect_equal(sched_curr_calls, 1L)
    expect_equal(sched_curr$game_pk, 33L)

    # 6. ingest_statcast_pitches() derives window from cached schedule when dates are omitted
    derived_windows <- list()
    sc_from_sched <- ingest_statcast_pitches(
      season = curr,
      force_refresh = TRUE,
      search_fn = function(s, e) {
        derived_windows[[length(derived_windows) + 1L]] <<- c(s, e)
        tibble::tibble(pitch_id = 1L)
      }
    )
    expect_equal(derived_windows[[1]], c(sprintf("%d-05-02", curr), sprintf("%d-05-02", curr)))
    expect_equal(nrow(sc_from_sched), 1L)
  })
})

test_that("run_mlb_ingest() orchestrates schedule-derived window and uncapped boxscores offline", {
  with_temp_cache_root({
    curr <- resolve_current_season()
    n_final <- 115L
    final_dates <- format(as.Date(sprintf("%d-03-26", curr)) + seq(0L, n_final - 1L), "%Y-%m-%d")

    dates_payload <- c(
      list(list(
        date = sprintf("%d-02-20", curr),
        games = list(list(
          gamePk = 900001L,
          gameType = "S",
          status = list(detailedState = "Final"),
          teams = list(
            away = list(team = list(id = 147L, name = "A"), score = 2L),
            home = list(team = list(id = 111L, name = "B"), score = 3L)
          ),
          venue = list(id = 1L, name = "Spring")
        ))
      )),
      lapply(seq_len(n_final), function(i) {
        list(
          date = final_dates[i],
          games = list(list(
            gamePk = 800000L + i,
            gameType = "R",
            status = list(detailedState = "Final"),
            teams = list(
              away = list(team = list(id = 147L, name = "New York Yankees"), score = 3L),
              home = list(team = list(id = 111L, name = "Boston Red Sox"), score = 5L)
            ),
            venue = list(id = 3L, name = "Fenway Park")
          ))
        )
      }),
      list(list(
        date = sprintf("%d-09-30", curr),
        games = list(list(
          gamePk = 899999L,
          gameType = "R",
          status = list(detailedState = "Scheduled"),
          teams = list(
            away = list(team = list(id = 147L, name = "New York Yankees"), score = NULL),
            home = list(team = list(id = 111L, name = "Boston Red Sox"), score = NULL)
          ),
          venue = list(id = 3L, name = "Fenway Park")
        ))
      ))
    )

    seen_windows <- list()
    box_count <- 0L
    out <- run_mlb_ingest(
      force_refresh = TRUE,
      schedule_url_reader = function(u) list(dates = dates_payload),
      boxscore_url_reader = function(u) { box_count <<- box_count + 1L; make_mock_boxscore_json(1L) },
      statcast_search_fn = function(s, e) {
        seen_windows[[length(seen_windows) + 1L]] <<- c(s, e)
        tibble::tibble(pitch_id = seq_along(seen_windows), game_date = s)
      }
    )

    expect_equal(box_count, n_final)
    expect_equal(nrow(out$boxscores), n_final * 2L)
    expect_equal(seen_windows[[1]][1], final_dates[1])
    expect_equal(seen_windows[[length(seen_windows)]][2], final_dates[n_final])
    expect_true(file.exists(statcast_cache_path(curr, create = FALSE)))
  })

  # Season = NULL falls back to resolve_current_season(); 0 completed games skips Statcast cleanly
  with_temp_cache_root({
    sc_zero_calls <- 0L
    out_empty <- run_mlb_ingest(
      season = NULL,
      force_refresh = TRUE,
      schedule_url_reader = function(u) {
        list(dates = list(list(
          date = sprintf("%d-04-01", curr),
          games = list(list(
            gamePk = 999001L,
            gameType = "R",
            status = list(detailedState = "Scheduled"),
            teams = list(
              away = list(team = list(id = 147L, name = "A"), score = NULL),
              home = list(team = list(id = 111L, name = "B"), score = NULL)
            ),
            venue = list(id = 1L, name = "Park")
          ))
        )))
      },
      boxscore_url_reader = function(u) stop("should not fetch boxscores when 0 games completed"),
      statcast_search_fn = function(s, e) { sc_zero_calls <<- sc_zero_calls + 1L; tibble::tibble() }
    )
    expect_equal(sc_zero_calls, 0L)
    expect_equal(nrow(out_empty$boxscores), 0L)
    expect_equal(nrow(out_empty$statcast), 0L)
  })
})

test_that("spatial exporters resolve season Statcast cache paths dynamically without literal dates or .. fallbacks", {
  tmp_root <- tempfile("mlb-spatial-root-")
  on.exit(unlink(tmp_root, recursive = TRUE, force = TRUE), add = TRUE)
  ingest_dir <- file.path(tmp_root, "cache", "ingest")
  cw_dir <- file.path(tmp_root, "cache", "id_crosswalk")
  out_dir <- file.path(tmp_root, "web", "public", "data")
  dir.create(ingest_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(cw_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  curr <- as.integer(MLB_CURRENT_SEASON)
  # Only legacy dated file for curr exists initially
  legacy_curr <- file.path(ingest_dir, sprintf("statcast_pitches_%d-03-25_%d-09-28.rds", curr, curr))
  other_year <- file.path(ingest_dir, sprintf("statcast_pitches_%d.rds", curr - 1L))
  saveRDS(data.frame(x = 1), legacy_curr)
  saveRDS(data.frame(x = 2), other_year)

  expect_equal(
    resolve_statcast_cache_file(root_dir = tmp_root),
    normalizePath(legacy_curr, winslash = "/", mustWork = FALSE)
  )
  expect_equal(
    resolve_statcast_cache_file(season = curr - 1L, root_dir = tmp_root),
    normalizePath(other_year, winslash = "/", mustWork = FALSE)
  )

  # Canonical file takes precedence once created
  canon_curr <- file.path(ingest_dir, sprintf("statcast_pitches_%d.rds", curr))
  n_pitches <- 20L
  sc_fixture <- tibble::tibble(
    pitcher = rep(543037L, n_pitches),
    batter = rep(592450L, n_pitches),
    player_name = rep("Judge, Aaron", n_pitches),
    home_team = rep("NYY", n_pitches),
    stand = rep("R", n_pitches),
    p_throws = rep("R", n_pitches),
    type = c(rep("X", 4L), rep("S", 8L), rep("B", 8L)),
    events = c("home_run", "single", "field_out", "double", rep(NA_character_, 16L)),
    description = c(rep("hit_into_play", 4L), rep("called_strike", 4L), rep("swinging_strike", 4L), rep("ball", 8L)),
    hc_x = c(190, 125, 100, 160, rep(NA_real_, 16L)),
    hc_y = c(40, 110, 140, 70, rep(NA_real_, 16L)),
    hit_distance_sc = c(420, 220, 120, 330, rep(NA_real_, 16L)),
    launch_speed = c(112.4, 96.2, 82.0, 104.5, rep(NA_real_, 16L)),
    launch_angle = c(28.0, 14.0, 5.0, 22.0, rep(NA_real_, 16L)),
    plate_x = c(0.1, -0.1, 0.2, -0.2, rep(0.75, 4L), rep(0.0, 4L), rep(-0.95, 8L)),
    plate_z = c(2.5, 2.4, 2.6, 2.2, rep(2.5, 4L), rep(2.5, 4L), rep(2.5, 8L)),
    pfx_x = rep(-0.5, n_pitches),
    pfx_z = rep(1.2, n_pitches),
    release_speed = rep(96.5, n_pitches),
    release_pos_x = rep(-2.1, n_pitches),
    release_pos_z = rep(5.9, n_pitches),
    release_extension = rep(6.4, n_pitches),
    pitch_type = rep("FF", n_pitches)
  )
  saveRDS(sc_fixture, canon_curr)
  saveRDS(
    tibble::tibble(mlb_id = c(592450L, 543037L), full_name = c("Aaron Judge", "Gerrit Cole")),
    file.path(cw_dir, "mlb_id_crosswalk.rds")
  )
  jsonlite::write_json(
    list(
      generated_at = sprintf("%d-04-01T12:00:00Z", MLB_CURRENT_SEASON),
      season = MLB_CURRENT_SEASON,
      players = data.frame(
        player_id = c("mlb_592450", "mlb_543037"),
        mlbam_id = c(592450L, 543037L),
        player_name = c("Aaron Judge", "Gerrit Cole"),
        player_type = c("Batter", "Pitcher"),
        team = c("NYY", "NYY"),
        position = c("RF", "SP"),
        stringsAsFactors = FALSE
      )
    ),
    file.path(out_dir, "projections_season_players.json"),
    auto_unbox = TRUE
  )

  expect_equal(
    resolve_statcast_cache_file(root_dir = tmp_root),
    normalizePath(canon_curr, winslash = "/", mustWork = FALSE)
  )

  spatial_out <- export_spatial_analytics(out_dir = out_dir, root_dir = tmp_root)
  expect_true(file.exists(spatial_out))
  expect_true(file.exists(file.path(out_dir, "spatial_index.json")))
  expect_true(file.exists(file.path(out_dir, "spatial", "mlb_592450.json")))
  expect_true(file.exists(file.path(out_dir, "spatial", "mlb_543037.json")))

  # Verify zero hardcoded 2024-04-0* literals and zero cross-checkout .. fallbacks
  for (f in c("mlb_ingest.R", "tools/export_spatial_analytics.R", "tools/export_player_spatial_maps.R")) {
    src <- readLines(f, warn = FALSE)
    expect_false(any(grepl("2024-04-0", src, fixed = TRUE)), info = f)
  }
  for (f in c("tools/export_spatial_analytics.R", "tools/export_player_spatial_maps.R")) {
    src <- readLines(f, warn = FALSE)
    expect_false(any(grepl("[\"']\\.\\.([\"']|[/\\\\])|MLB Analytics", src)), info = f)
  }
})
