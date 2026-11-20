# Landing digest (front-office#200; MLB-Analytics#124, #126, #127)
if (!file.exists("config.R")) {
  setwd(if (file.exists("../../config.R")) normalizePath("../..", winslash = "/") else getwd())
}
suppressPackageStartupMessages(library(jsonlite))
source("tools/export_landing_digest.R")

log_row <- function(pk, date, hp, hs, as_, status = "Final", src = "walk_forward") {
  data.frame(game_pk = pk, game_date = date, status_detail = status,
             is_completed = status %in% LD_FINAL_STATUSES, home_team_id = 1L, home_team = "AAA",
             away_team_id = 2L, away_team = "BBB", home_win_prob = hp, away_win_prob = 1 - hp,
             projection_source = src, home_score = hs, away_score = as_, stringsAsFactors = FALSE)
}

test_that("hit rule: a win by the >50% side is a hit; 50%, ties and postponed are excluded", {
  expect_true(ld_hit(0.62, 5, 3))          # home favoured, home won
  expect_false(ld_hit(0.62, 2, 3))         # home favoured, away won
  expect_true(ld_hit(0.40, 1, 4))          # away favoured, away won
  expect_true(is.na(ld_hit(0.5, 5, 3)))    # exact 50%
  expect_true(is.na(ld_hit(0.6, 4, 4)))    # tie
  expect_true(is.na(ld_hit(0.6, NA, NA, "Postponed")))
  expect_true(is.na(ld_hit(0.6, 3, 1, "Cancelled")))
  expect_true(is.na(ld_hit(NA, 3, 1)))     # no prediction
  expect_identical(ld_predicted_winner("AAA", "BBB", 0.5), NA_character_)
  expect_identical(ld_predicted_winner("AAA", "BBB", 0.3), "BBB")
})

test_that("record counts hits, games and exclusions; last_7 is the 7 days before the slate", {
  log <- rbind(
    log_row(1, "2026-09-01", 0.65, 5, 2),                       # hit (outside last 7)
    log_row(2, "2026-09-20", 0.55, 1, 3),                       # miss
    log_row(3, "2026-09-21", 0.50, 3, 1),                       # excluded: 50%
    log_row(4, "2026-09-22", 0.70, NA, NA, "Postponed"),        # excluded: postponed
    log_row(5, "2026-09-23", 0.40, 2, 6),                       # hit
    log_row(6, "2026-09-23", 0.80, 9, 1, src = "current_elo"),  # hindsight: never graded
    log_row(7, "2026-09-25", 0.60, 4, 2)                        # on the slate date: not yet
  )
  r <- ld_record(log, "2026-09-25")
  expect_equal(r$season, list(hits = 2L, games = 3L, excluded = 2L))
  expect_equal(r$last_7, list(hits = 1L, games = 2L, excluded = 2L))
})

test_that("calibration buckets 50-100 by 10 on the favoured side", {
  log <- rbind(log_row(1, "2026-09-01", 0.65, 5, 2), log_row(2, "2026-09-02", 0.35, 5, 2),
               log_row(3, "2026-09-03", 0.92, 5, 2), log_row(4, "2026-09-04", 0.50, 5, 2))
  cal <- ld_calibration(log, "2026-09-10")
  expect_equal(vapply(cal, function(b) b$lo, integer(1)), c(50L, 60L, 70L, 80L, 90L))
  expect_equal(vapply(cal, function(b) b$hi, integer(1)), c(60L, 70L, 80L, 90L, 100L))
  b60 <- cal[[2]]
  expect_equal(b60$games, 2L)
  expect_equal(b60$predicted_mean, 0.65)
  expect_equal(b60$actual_rate, 0.5)
  expect_equal(cal[[5]]$games, 1L)
  expect_null(cal[[1]]$predicted_mean)    # the exact-50% pick never lands in a bucket
  expect_equal(sum(vapply(cal, function(b) b$games, integer(1))), 3L)
})

test_that("movers fall back to the nearest earlier date and keep the top 5 by |delta|", {
  teams <- c("A", "B", "C", "D", "E", "F")
  h <- ld_update_history(ld_read_history(tempfile()), "2026-09-01", teams, rep(1500, 6))
  h <- ld_update_history(h, "2026-09-10", teams, c(1510, 1490, 1500, 1503, 1520, 1499))
  h <- ld_update_history(h, "2026-09-11", teams, c(1512, 1480, 1500, 1503, 1520, 1499))
  m <- ld_movers(h, "2026-09-11")
  expect_identical(m$metric, "elo_rating")
  expect_setequal(names(m$windows), c("1", "7", "21"))
  expect_identical(m$windows[["1"]]$compared_to, "2026-09-10")
  expect_identical(m$windows[["7"]]$compared_to, "2026-09-01")   # no 09-04 row: nearest earlier
  expect_null(m$windows[["21"]]$compared_to)                       # not enough history
  expect_length(m$windows[["21"]]$items, 0)
  w7 <- m$windows[["7"]]$items
  expect_length(w7, 5)                                             # C is unchanged: not a mover
  expect_identical(vapply(w7, function(i) i$team, ""), c("B", "E", "A", "D", "F"))
  expect_equal(w7[[1]]$delta, -20)
  expect_equal(w7[[1]]$previous, 1500)
  expect_equal(w7[[1]]$current, 1480)
})

test_that("ratings history replaces same-day rows and is pruned to about 400 days", {
  h <- ld_update_history(ld_read_history(tempfile()), "2024-12-01", "A", 1500)
  h <- ld_update_history(h, "2026-02-01", "A", 1510)
  h <- ld_update_history(h, "2026-02-01", "A", 1511)
  expect_equal(nrow(h), 1L)
  expect_equal(h$value, 1511)
})

test_that("data/history/ratings_history.csv is outside cache/ and web/public/ and not gitignored", {
  skip_if(Sys.which("git") == "", "git not available")
  path <- LD_HISTORY_PATH
  expect_false(startsWith(path, "cache") || startsWith(path, file.path("web", "public")))
  status <- suppressWarnings(system2("git", c("check-ignore", "-q", path),
                                     stdout = FALSE, stderr = FALSE))
  expect_equal(status, 1L)   # git check-ignore exits 1 when the path is NOT ignored
})

test_that("season_state and next_milestone come from the schedule", {
  s <- data.frame(official_date = c("2026-02-20", "2026-03-25", "2026-09-27", "2026-09-29", "2026-10-31"),
                  game_type = c("S", "R", "R", "F", "W"), stringsAsFactors = FALSE)
  expect_identical(ld_season_state(s, "2026-03-01"), "preseason")
  expect_identical(ld_season_state(s, "2026-06-01"), "regular")
  expect_identical(ld_season_state(s, "2026-10-05"), "postseason")
  expect_identical(ld_season_state(s, "2026-11-20"), "offseason")
  expect_equal(ld_next_milestone("preseason", s, "2026-03-01"),
               list(label = "Opening Day", date = "2026-03-25"))
  expect_equal(ld_next_milestone("regular", s, "2026-06-01"),
               list(label = "Postseason begins", date = "2026-09-29"))
  expect_null(ld_next_milestone("offseason", s, "2026-11-20", monitor = NULL))
})

test_that("committed landing_digest.json passes the gate contract and has no betting terms", {
  f <- file.path("web", "public", "data", LD_FILE)
  skip_if_not(file.exists(f))
  source("config.R")
  source("logging_utils.R")
  source("tools/publish_web.R")
  res <- .assert_landing_digest_contract(f)
  expect_true(res$pass, info = paste(res$detail, collapse = "\n"))
  expect_false(any(grepl("odds|spread|moneyline|over/under", readLines(f), ignore.case = TRUE)))
})
