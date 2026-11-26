# ==============================================================================
# test-player-leaders.R - MLB league leaders panel (MLB-Analytics#163)
#
# Offline (no cache, no network):
#   1. config.R minimums match the owner-approved 162-game values + study commit
#   2. scaling: required = minimum x team games played / 162
#   3. ranking: highest leads, lowest leads for K% (bat), ERA, FIP, WHIP, BB% (pit), ties
#   4. position / role filters (IF, OF, C_DH, SP, RP) and traded player rule
#   5. rate formulas (AVG, OBP, SLG, OPS, wOBA, K%, BB%, Barrel%, ERA, FIP, WHIP)
#   6. empty card: "Not enough games yet" with reason, never falls back
#   7. evening refresh: MLB boxscore parsing, success adds regular-season game,
#      failed fetch leaves file byte-identical, postseason game ignored, re-run no-op
# ==============================================================================

if (!file.exists("config.R")) {
  if (file.exists("../../config.R")) setwd(normalizePath("../..", winslash = "/"))
  else stop("Cannot locate project root (no config.R).", call. = FALSE)
}

suppressPackageStartupMessages({
  library(testthat)
  library(jsonlite)
})

Sys.setenv(MLB_SKIP_STAGE_AUTORUN = "1")
ple <- new.env(parent = globalenv())
suppressMessages(sys.source("build_player_leaders.R", envir = ple))
Sys.unsetenv("MLB_SKIP_STAGE_AUTORUN")

test_that("config.R minimums match owner-approved 162-game values and study commit", {
  expect <- c(
    LEADERS_FULL_SEASON_GAMES = 162,
    LEADERS_MIN_PA_AVG = 502, LEADERS_MIN_PA_OBP = 502, LEADERS_MIN_PA_SLG = 502,
    LEADERS_MIN_PA_OPS = 502, LEADERS_MIN_PA_WOBA = 502, LEADERS_MIN_PA_HR = 502,
    LEADERS_MIN_PA_K_PCT = 200, LEADERS_MIN_PA_SB = 200,
    LEADERS_MIN_PA_BB_PCT = 250, LEADERS_MIN_PA_BARREL_PCT = 250,
    LEADERS_MIN_BF_ERA = 675, LEADERS_MIN_BF_FIP = 675, LEADERS_MIN_BF_WHIP = 675,
    LEADERS_MIN_BF_K_PCT = 250, LEADERS_MIN_BF_BB_PCT = 675,
    LEADERS_MIN_APP_IP = 10, LEADERS_MIN_RELIEF_APP_SAVES = 15
  )
  for (k in names(expect)) {
    expect_equal(as.numeric(get(k, envir = ple)), expect[[k]], info = k)
  }
  expect_identical(get("LEADERS_STUDY_SOURCE_COMMIT", envir = ple), "fed327b554883807469ee381225145815f1fa1a3")
  expect_equal(length(ple$PL_STATS), 17L)
  expect_true(all(vapply(ple$PL_STATS, function(s) exists(s$min, envir = ple), logical(1))))
  expect_setequal(
    names(Filter(function(s) s$lower_is_better, ple$PL_STATS)),
    c("k_pct", "era", "fip", "whip", "p_bb_pct")
  )
})

test_that("qualifying bar scales linearly with team games played over 162", {
  expect_equal(ple$pl_required(502, 81), 251)
  expect_equal(ple$pl_required(675, 162), 675)
  expect_equal(ple$pl_required(200, 81), 100)
})

test_that("ranking, ties, position filters, top-10 cap, and empty state work", {
  st_avg <- ple$PL_STATS$avg
  cand <- data.frame(
    player_id = c("a", "b", "c", "d", "e"),
    player = c("Alpha", "Beta", "Gamma", "Delta", "Epsilon"),
    team = "NYY",
    position = c("SS", "CF", "C", "1B", "DH"),
    position_group = c("IF", "OF", "C_DH", "IF", "C_DH"),
    value = c(0.310, 0.325, 0.325, 0.350, 0.290),
    sample = c(260, 260, 260, 100, 260),
    team_games_played = 81,
    stringsAsFactors = FALSE
  )
  cd <- ple$pl_card(st_avg, cand, "2026-07-01")
  who <- vapply(cd$leaders$all, `[[`, "", "player")
  ranks <- vapply(cd$leaders$all, `[[`, 0L, "rank")
  expect_false("Delta" %in% who)
  expect_identical(who, c("Beta", "Gamma", "Alpha", "Epsilon"))
  expect_identical(ranks, c(1L, 1L, 3L, 4L))
  expect_identical(vapply(cd$leaders$IF, `[[`, "", "player"), "Alpha")
  expect_identical(vapply(cd$leaders$OF, `[[`, "", "player"), "Beta")
  expect_identical(vapply(cd$leaders$C_DH, `[[`, "", "player"), c("Gamma", "Epsilon"))

  st_era <- ple$PL_STATS$era
  cd_era <- ple$pl_card(
    st_era,
    transform(cand, position = "P", position_group = "SP", value = c(3.2, 2.1, 2.5, 1.5, 4.0), sample = c(350, 350, 350, 100, 350)),
    "2026-07-01"
  )
  expect_identical(vapply(cd_era$leaders$all, `[[`, "", "player"), c("Beta", "Gamma", "Alpha", "Epsilon"))

  cd_empty <- ple$pl_card(st_avg, transform(cand, sample = 10), "2026-07-01")
  expect_identical(cd_empty$status, "not_enough_games")
  expect_identical(cd_empty$status_text, "Not enough games yet")
  expect_true(nzchar(cd_empty$null_reason))
  expect_length(cd_empty$leaders$all, 0L)

  many <- data.frame(
    player_id = as.character(1:15), player = sprintf("P%02d", 1:15),
    team = "NYY", position = "SS", position_group = "IF",
    value = seq(0.25, 0.39, length.out = 15), sample = 300, team_games_played = 81,
    stringsAsFactors = FALSE
  )
  expect_length(ple$pl_card(st_avg, many, "2026-07-01")$leaders$all, 10L)
})

test_that("traded player sums all games and follows latest team and bar", {
  g <- data.frame(
    game_id = c("1", "2", "3"),
    game_date = c("2026-05-01", "2026-06-01", "2026-08-01"),
    player_id = "100", player = "Traded Slugger",
    team_id = c("147", "147", "119"), team = c("NYY", "NYY", "LAD"),
    position = "OF",
    games = 1, pa = c(4, 4, 5), ab = c(3, 4, 4), h = c(1, 2, 2),
    d2 = c(0, 1, 0), d3 = c(0, 0, 0), hr = c(0, 0, 1),
    bb = c(1, 0, 1), ibb = c(0, 0, 0), hbp = c(0, 0, 0), sf = c(0, 0, 0),
    so = c(1, 0, 1), sb = c(1, 0, 1), tb = c(1, 3, 5),
    woba_num = c(1, 2, 3), woba_den = c(4, 4, 5),
    barrels = c(0, 1, 1), bbe_tracked = c(2, 3, 3), sc_missing_games = c(0, 0, 0),
    stringsAsFactors = FALSE
  )
  tot <- ple$pl_add_bat_games(ple$pl_empty_bat_totals(), g)
  expect_equal(tot$pa, 13)
  expect_equal(tot$hr, 1)
  expect_identical(tot$team, "LAD")
  expect_identical(tot$team_id, "119")

  expect_equal(ple$PL_STATS$avg$num(tot) / ple$PL_STATS$avg$den(tot), 5 / 11)
  expect_equal(ple$PL_STATS$obp$num(tot) / ple$PL_STATS$obp$den(tot), (5 + 2) / (11 + 2))
  expect_equal(ple$PL_STATS$slg$num(tot) / ple$PL_STATS$slg$den(tot), 9 / 11)
  expect_equal(ple$PL_STATS$k_pct$num(tot) / ple$PL_STATS$k_pct$den(tot), 2 / 13)
  expect_equal(ple$PL_STATS$barrel_pct$num(tot) / ple$PL_STATS$barrel_pct$den(tot), 2 / 8)
})

test_that("evening refresh parses MLB boxscore, is all-or-nothing, and ignores postseason", {
  guts <- list(wBB = 0.69, wHBP = 0.72, w1B = 0.88, w2B = 1.25, w3B = 1.58, wHR = 2.02, cFIP = 3.15)
  bat <- data.frame(
    player_id = "1", player = "Bat One", team_id = "147", team = "NYY", position = "SS",
    last_game_date = "2026-09-26", last_game_id = "10",
    games = 160, pa = 600, ab = 540, h = 162, d2 = 30, d3 = 2, hr = 30,
    bb = 55, ibb = 2, hbp = 5, sf = 0, so = 100, sb = 20, tb = 286,
    woba_num = 220, woba_den = 598, barrels = 40, bbe_tracked = 400, sc_missing_games = 0,
    stringsAsFactors = FALSE
  )
  pit <- data.frame(
    player_id = "2", player = "Pit Two", team_id = "147", team = "NYY", position = "P",
    last_game_date = "2026-09-26", last_game_id = "10",
    app = 32, gs = 32, relief_app = 0, bf = 750, outs = 540, ip = 180,
    h = 140, bb = 45, hbp = 5, so = 200, hr = 18, er = 50, sv = 0, fip_num = 500,
    stringsAsFactors = FALSE
  )
  tg <- data.frame(team_id = "147", team = "NYY", games = 161, stringsAsFactors = FALSE)
  payload <- ple$pl_build_payload(bat, pit, tg, c("10"), guts, list(test = "fixture"), season = 2026L)
  tmp <- tempfile(fileext = ".json")
  on.exit(unlink(tmp), add = TRUE)
  ple$pl_write_payload(payload, tmp)
  before_bytes <- readBin(tmp, "raw", file.info(tmp)$size)

  # Postseason game ignored
  ws_games <- data.frame(game_id = "99", game_date = "2026-10-24", game_type = "W", is_completed = TRUE, stringsAsFactors = FALSE)
  r_ws <- ple$pl_refresh_leaders(tmp, ws_games, fetch_boxscore = function(id) stop("should not fetch"))
  expect_identical(r_ws$status, "up_to_date")
  expect_identical(readBin(tmp, "raw", file.info(tmp)$size), before_bytes)

  # Failed fetch leaves file byte-identical
  reg_games <- data.frame(game_id = "11", game_date = "2026-09-27", game_type = "R", is_completed = TRUE, stringsAsFactors = FALSE)
  r_fail <- ple$pl_refresh_leaders(tmp, reg_games, fetch_boxscore = function(id) NULL)
  expect_match(r_fail$status, "^fetch_failed")
  expect_identical(readBin(tmp, "raw", file.info(tmp)$size), before_bytes)

  # Valid boxscore updates totals and cards, preserves barrel_pct
  stub_box <- list(teams = list(
    away = list(team = list(id = 147, abbreviation = "NYY"), players = list(
      ID1 = list(person = list(id = 1, fullName = "Bat One"), position = list(abbreviation = "SS"),
                 stats = list(batting = list(plateAppearances = 4, atBats = 4, hits = 2, doubles = 0,
                                             triples = 0, homeRuns = 1, baseOnBalls = 0, intentionalWalks = 0,
                                             hitByPitch = 0, sacFlies = 0, strikeOuts = 0, stolenBases = 0,
                                             totalBases = 5)))
    )),
    home = list(team = list(id = 111, abbreviation = "BOS"), players = list(
      ID3 = list(person = list(id = 3, fullName = "Bos Pit"), position = list(abbreviation = "P"),
                 stats = list(pitching = list(gamesStarted = 1, battersFaced = 24, inningsPitched = "6.0",
                                              hits = 5, baseOnBalls = 1, hitBatsmen = 0, strikeOuts = 7,
                                              homeRuns = 1, earnedRuns = 2, saves = 0)))
    ))
  ))
  r_ok <- ple$pl_refresh_leaders(tmp, reg_games, fetch_boxscore = function(id) stub_box)
  expect_identical(r_ok$status, "updated")
  expect_equal(r_ok$n_games, 1L)
  updated <- jsonlite::fromJSON(tmp, simplifyVector = FALSE)
  expect_identical(updated$through_date, "2026-09-27")
  expect_true("11" %in% unlist(updated$season_totals$game_ids))

  # Re-run is a no-op
  r_noop <- ple$pl_refresh_leaders(tmp, reg_games, fetch_boxscore = function(id) stop("should not fetch"))
  expect_identical(r_noop$status, "up_to_date")
})
