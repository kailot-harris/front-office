# ==============================================================================
# test_landing_digest.R
# Offline tests for tools/build_landing_digest.R and its slot B/C patch in
# tools/refresh_live_results.R (Refs kailot-harris/WNBA_analytics#224-#227,
# kailot-harris/front-office#200). Temp dirs and inline fixtures only; never
# reads cache/.
# ==============================================================================

args_all <- commandArgs(trailingOnly = FALSE)
f <- sub("^--file=", "", args_all[grepl("^--file=", args_all)])
if (length(f) == 1 && nzchar(f) && file.exists(f)) {
  cand <- normalizePath(dirname(dirname(dirname(f))), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(cand, "config.R"))) setwd(cand)
}
cur <- getwd()
while (!file.exists(file.path(cur, "config.R")) && dirname(cur) != cur) cur <- dirname(cur)
if (file.exists(file.path(cur, "config.R"))) setwd(cur)
dir.create("logs", showWarnings = FALSE)

user_lib <- Sys.getenv("R_LIBS_USER")
if (nzchar(user_lib) && dir.exists(user_lib) && !(user_lib %in% .libPaths())) {
  .libPaths(c(.libPaths(), user_lib))
} else {
  default_user_lib <- file.path(Sys.getenv("LOCALAPPDATA", file.path(Sys.getenv("USERPROFILE"), "AppData", "Local")), "R", "win-library", "4.5")
  if (dir.exists(default_user_lib) && !(default_user_lib %in% .libPaths())) .libPaths(c(.libPaths(), default_user_lib))
}

suppressPackageStartupMessages({
  library(testthat)
  library(jsonlite)
})

ROOT <- getwd()
Sys.setenv(WNBA_SKIP_DIGEST_AUTORUN = "1", WNBA_SKIP_MANIFEST_AUTORUN = "1")
source(file.path("tools", "build_landing_digest.R"))

# One matchup row in matchups_slates.json shape.
mrow <- function(id, date, home, away, p = NA, hs = NA, as_ = NA, done = FALSE,
                 basis = if (is.na(p)) "team_rating_differential" else "logged_model", week = 1L) {
  data.frame(game_id = id, game_date = date, week = week, season_type = "regular",
             home_team = home, away_team = away, home_team_name = paste(home, "Name"),
             away_team_name = paste(away, "Name"), is_completed = done,
             home_score = hs, away_score = as_, actual_margin = if (done) hs - as_ else NA,
             actual_winner = if (done && !is.na(hs) && hs != as_) (if (hs > as_) home else away) else NA,
             has_prediction = TRUE, has_logged_prediction = !is.na(p), projection_basis = basis,
             projected_margin = NA, home_win_prob = if (is.na(p)) 0.6 else p,
             predicted_winner = NA, is_graded = FALSE, prediction_correct = NA,
             stringsAsFactors = FALSE)
}

test_that("hit rule: >50% side wins = hit; exact 50%, tie and postponed are excluded", {
  expect_true(ld_grade(0.7, "A", "B", 90, 80, "final")$hit)
  expect_false(ld_grade(0.7, "A", "B", 70, 80, "final")$hit)
  expect_true(ld_grade(0.3, "A", "B", 70, 80, "final")$hit)
  r50 <- ld_grade(0.5, "A", "B", 90, 80, "final")
  expect_true(is.na(r50$hit)); expect_equal(r50$outcome, "excluded")
  tie <- ld_grade(0.7, "A", "B", 80, 80, "final")
  expect_true(is.na(tie$hit)); expect_equal(tie$outcome, "excluded")
  pp <- ld_grade(0.7, "A", "B", NA, NA, "postponed")
  expect_true(is.na(pp$hit)); expect_equal(pp$outcome, "excluded")
  expect_equal(ld_grade(0.7, "A", "B", NA, NA, "cancelled")$outcome, "excluded")
  expect_equal(ld_grade(NA, "A", "B", 90, 80, "final")$outcome, "no_prediction")
  expect_equal(ld_grade(0.7, "A", "B", NA, NA, "scheduled")$outcome, "pending")
})

test_that("record and calibration apply the rule; rating fallback is never a prediction", {
  rows <- rbind(
    mrow("1", "2026-07-01", "A", "B", 0.65, 90, 80, TRUE),       # hit, 60-70
    mrow("2", "2026-07-02", "C", "D", 0.55, 70, 80, TRUE),       # miss, 50-60
    mrow("3", "2026-07-09", "A", "C", 0.50, 90, 80, TRUE),       # exact 50% -> excluded
    mrow("4", "2026-07-09", "B", "D", 0.95, 80, 80, TRUE),       # tie -> excluded
    mrow("5", "2026-07-08", "B", "C", 0.20, 70, 85, TRUE),       # hit (away 80%), 80-90
    mrow("6", "2026-07-09", "D", "A", NA, 99, 60, TRUE),         # rating fallback only
    mrow("7", "2026-07-05", "C", "A", 0.7),                      # never played -> excluded
    mrow("8", "2026-07-10", "A", "D", 0.6))                      # today, pending
  rb <- ld_results_blocks(rows, as.Date("2026-07-10"))
  expect_equal(rb$record$season, list(hits = 2L, games = 3L, excluded = 3L))
  # last 7 = 2026-07-03 .. 2026-07-09
  expect_equal(rb$record$last_7, list(hits = 1L, games = 1L, excluded = 3L))
  cal <- rb$calibration
  expect_length(cal, 5)
  expect_equal(vapply(cal, `[[`, 0, "lo"), c(0.5, 0.6, 0.7, 0.8, 0.9))
  expect_equal(vapply(cal, `[[`, 0L, "games"), c(1L, 1L, 0L, 1L, 0L))
  expect_equal(cal[[2]]$predicted_mean, 0.65); expect_equal(cal[[2]]$actual_rate, 1)
  expect_equal(cal[[4]]$predicted_mean, 0.8)
  expect_null(cal[[3]]$actual_rate)
  y <- rb$yesterday
  expect_length(y, 3)
  fb <- Filter(function(g) g$game_id == "6", y)[[1]]
  expect_null(fb$home_win_prob); expect_equal(fb$prediction_status, "not_yet_run"); expect_null(fb$hit)
  g50 <- Filter(function(g) g$game_id == "3", y)[[1]]
  expect_null(g50$hit); expect_null(g50$predicted_winner); expect_true(g50$final)
})

test_that("movers use the nearest earlier date and are empty without history", {
  d <- tempfile("hist_"); dir.create(d); p <- file.path(d, "ratings_history.csv")
  base <- as.Date("2026-07-30")
  for (dt in as.list(base - c(30, 9, 1))) {
    off <- as.numeric(base - dt)
    ld_update_history(data.frame(team = c("A", "B", "C"), value = c(1, 2, 3) + off / 10), dt, p)
  }
  h <- ld_update_history(data.frame(team = c("A", "B", "C"), value = c(1, 2, 3)), base, p)
  m <- ld_movers(h, base)
  expect_equal(m$metric, "net_rating")
  expect_equal(m$windows[["1"]]$compared_to, "2026-07-29")
  expect_equal(m$windows[["7"]]$compared_to, "2026-07-21")   # no row on 07-23 -> nearest earlier
  expect_equal(m$windows[["21"]]$compared_to, "2026-06-30")
  it <- m$windows[["7"]]$items[[1]]
  expect_equal(it$delta, round(it$current - it$previous, 2))
  expect_length(m$windows[["7"]]$items, 3)
  only <- ld_movers(h[h$date == base, ], base)
  expect_null(only$windows[["1"]]$compared_to); expect_length(only$windows[["21"]]$items, 0)
  # pruning to ~400 days and same-day replacement
  h2 <- ld_update_history(data.frame(team = "A", value = 9), base + 420, p)
  expect_true(all(h2$date > base + 420 - LD_HISTORY_KEEP))
  h3 <- ld_update_history(data.frame(team = "A", value = 7), base + 420, p)
  expect_equal(sum(h3$date == base + 420), 1L); expect_equal(h3$value[h3$date == base + 420], 7)
})

test_that("ratings history CSV is tracked-eligible (git check-ignore says not ignored)", {
  git <- Sys.which("git")
  skip_if(!nzchar(git), "git not on PATH")
  out <- suppressWarnings(system2(git, c("-C", shQuote(ROOT), "check-ignore", "-q", "data/history/ratings_history.csv"),
                                  stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status"); st <- if (is.null(st)) 0L else st
  expect_equal(st, 1L)  # 1 = not ignored; 0 would mean ignored
})

test_that("season_state and next_milestone come from real dates, never guessed", {
  g <- ld_normalize_games(rbind(mrow("1", "2026-05-10", "A", "B"), mrow("3", "2026-08-30", "A", "B"), mrow("2", "2026-09-10", "A", "B")))
  g$season_type[3] <- "postseason"
  expect_equal(ld_season_state(g, as.Date("2026-04-01")), "preseason")
  expect_equal(ld_season_state(g, as.Date("2026-06-01")), "regular")
  expect_equal(ld_season_state(g, as.Date("2026-09-10")), "postseason")
  expect_equal(ld_season_state(g, as.Date("2026-11-20")), "offseason")
  mon <- list(editions = list(list(upcomingMilestones = list(
    list(date = "2026-11-15", event = "Past"), list(date = NULL, event = "TBD"),
    list(date = "2027-04-12", event = "Draft")))))
  expect_equal(ld_next_milestone("offseason", g, as.Date("2026-11-20"), mon), list(label = "Draft", date = "2027-04-12"))
  expect_null(ld_next_milestone("offseason", g, as.Date("2026-11-20"), NULL))
})

test_that("slot B/C refresh patches yesterday, record and calibration on a fixture", {
  source(file.path("tools", "refresh_live_results.R"))
  setwd(ROOT)
  d <- tempfile("rlr_"); dir.create(d)
  mp <- file.path(d, "matchups_slates.json"); dp <- file.path(d, "landing_digest.json")
  rows <- rbind(mrow("101", "2026-07-09", "A", "B", 0.7, week = 1L),
                mrow("102", "2026-07-09", "C", "D", 0.6, week = 1L))
  payload <- list(season = 2026L, generated_at = "2026-07-09T00:00:00Z", active_week = 1L,
                  available_weeks = 1L, summary = list(completed_games = 0L),
                  weeks = data.frame(week = 1L, completed_games = 0L, pending_games = 2L,
                                     graded_games = 0L, correct_games = NA, accuracy_pct = NA),
                  matchups = rows)
  writeLines(toJSON(payload, auto_unbox = TRUE, na = "null", pretty = TRUE), mp)
  digest <- list(schema_version = 1L, sport = "wnba", generated_at = "2026-07-10T09:00:00Z",
                 slate_date = "2026-07-10", season_state = "regular", next_milestone = NULL,
                 today = I(list()), yesterday = I(list()),
                 record = list(season = list(hits = 0L, games = 0L, excluded = 0L),
                               last_7 = list(hits = 0L, games = 0L, excluded = 0L)),
                 calibration = I(ld_calibration(ld_grade_games(ld_normalize_games(rows[0, ]), as.Date("2026-07-10")))),
                 movers = list(metric = "net_rating", windows = list(
                   "1" = list(compared_to = NULL, items = I(list())),
                   "7" = list(compared_to = NULL, items = I(list())),
                   "21" = list(compared_to = NULL, items = I(list())))))
  writeLines(ld_json_text(digest), dp)
  fake <- function(dates) data.frame(game_id = c("101", "102"), is_final = TRUE,
                                     home_score = c(90L, 70L), away_score = c(80L, 75L))
  res <- refresh_live_results(dates = "2026-07-09", payload_path = mp, fetcher = fake,
                              today = as.Date("2026-07-10"), digest_path = dp)
  expect_equal(res$n_changed, 2L)
  expect_equal(res$digest_file, dp)
  out <- fromJSON(dp, simplifyVector = FALSE)
  expect_equal(out$slate_date, "2026-07-10")
  expect_length(out$yesterday, 2)
  expect_equal(vapply(out$yesterday, function(g) isTRUE(g$hit), logical(1)), c(TRUE, FALSE))
  expect_equal(out$record$season$hits, 1L); expect_equal(out$record$season$games, 2L)
  expect_equal(out$record$last_7$games, 2L)
  expect_equal(vapply(out$calibration, function(b) b$games, 0L), c(0L, 1L, 1L, 0L, 0L))
  expect_equal(names(out$movers$windows), c("1", "7", "21"))
  expect_length(out$today, 0)
  # second run with nothing new: digest unchanged (no stamp churn)
  res2 <- refresh_live_results(dates = "2026-07-09", payload_path = mp, fetcher = fake,
                               today = as.Date("2026-07-10"), digest_path = dp)
  expect_null(res2$digest_file)
})

test_that("manifest through_date comes from yesterday finals; gate validates the digest", {
  source(file.path("tools", "write_data_manifest.R"))
  source(file.path("tools", "publish_web.R"))
  setwd(ROOT)
  d <- tempfile("ldm_"); dir.create(d)
  dg <- list(schema_version = 1L, sport = "wnba", generated_at = "2026-07-10T09:00:00Z",
             slate_date = "2026-07-10", season_state = "regular", next_milestone = NULL,
             today = I(list()),
             yesterday = list(list(game_id = "1", game_date = "2026-07-09", status = "final", final = TRUE,
                                   prediction_status = "available"),
                              list(game_id = "2", game_date = "2026-07-09", status = "not_played", final = FALSE,
                                   prediction_status = "not_yet_run")),
             record = list(season = list(hits = 0L, games = 0L, excluded = 0L),
                           last_7 = list(hits = 0L, games = 0L, excluded = 0L)),
             calibration = I(ld_calibration(ld_grade_games(ld_normalize_games(data.frame()), Sys.Date()))),
             movers = list(metric = "net_rating", windows = list("1" = list(), "7" = list(), "21" = list())))
  writeLines(ld_json_text(dg), file.path(d, "landing_digest.json"))
  m <- build_data_manifest(data_dir = d, schedule_path = file.path(d, "none.rds"), previous = NULL)
  e <- m$datasets[[1]]
  expect_equal(e$through_date, "2026-07-09")
  expect_equal(e$through_date_source, "payload:yesterday[].game_date (final)")
  expect_equal(e$stamp_source, "payload:generated_at")
  write_data_manifest(data_dir = d, schedule_path = file.path(d, "none.rds"), previous = NULL)
  r <- .assert_manifest_and_coverage(d, dry_run = FALSE)
  expect_true(r$pass, info = paste(r$problems, collapse = "; "))
  # off-season: no finals -> not_game_dated with a coverage note
  dg$yesterday <- I(list()); writeLines(ld_json_text(dg), file.path(d, "landing_digest.json"))
  m2 <- build_data_manifest(data_dir = d, schedule_path = file.path(d, "none.rds"), previous = NULL)
  expect_equal(m2$datasets[[1]]$through_date_source, "not_game_dated")
  expect_true(nzchar(m2$datasets[[1]]$coverage_note))
  # broken digest fails the gate
  dg$movers <- list(metric = "net_rating", windows = list("1" = list()))
  writeLines(ld_json_text(dg), file.path(d, "landing_digest.json"))
  write_data_manifest(data_dir = d, schedule_path = file.path(d, "none.rds"), previous = NULL)
  expect_false(.assert_manifest_and_coverage(d, dry_run = FALSE)$pass)
})

test_that("committed digest has the full contract and no betting terms", {
  p <- file.path("web", "public", "data", "landing_digest.json")
  skip_if_not(file.exists(p))
  expect_length(.pw_landing_digest_problems(p), 0)
  txt <- tolower(paste(readLines(p, warn = FALSE), collapse = " "))
  expect_false(grepl("odds|spread|moneyline|over/under", txt))
})
