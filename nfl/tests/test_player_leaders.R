# ==============================================================================
# tests/test_player_leaders.R - league leaders panel (NFL_analytics#230)
#
# Offline (no cache, no network; hand-made fixture frames shaped like nflverse):
#   PL-1  config.R minimums equal the owner's #230 decisions exactly
#   PL-2  scaling: required = minimum x team games played / 17
#   PL-3  study definitions: dropbacks, designed carries, targets
#   PL-4  ranking: highest leads; lowest leads for sack rate and interception rate
#   PL-5  qualifying uses the bar of the player's CURRENT team (traded player)
#   PL-6  totals have no minimum; a zero total leads nothing; total EPA credit
#   PL-7  PFR fetch failure -> those cards null with a reason, never filled
#   PL-8  no qualifier -> "Not enough games yet"; yards per route run absent
#   PL-9  evening refresh: rebuilds non-model cards, copies total EPA through
#   PL-10 evening refresh: a failed fetch leaves the file byte-identical and
#         refresh_live_results() still patches final scores
#
# Usage: Rscript tests/test_player_leaders.R
# ==============================================================================
failures <- 0L
ok <- function(label, cond) {
  if (isTRUE(cond)) cat(sprintf("[PASS] %s\n", label))
  else { cat(sprintf("[FAIL] %s\n", label)); failures <<- failures + 1L }
}
near <- function(a, b, tol = 1e-6) isTRUE(all(abs(a - b) < tol))
suppressPackageStartupMessages(library(jsonlite))
source("config.R")
source("build_player_leaders.R")

# ---------------------------------------------------------------------------
# PL-1 / PL-2
# ---------------------------------------------------------------------------
ok("PL-1a LEADERS_FULL_SEASON_GAMES = 17", identical(LEADERS_FULL_SEASON_GAMES, 17L))
ok("PL-1b yards per game: 8 games", identical(LEADERS_MIN_GAMES_YARDS_PER_GAME, 8L))
ok("PL-1c passing rates: 250 dropbacks", identical(LEADERS_MIN_DROPBACKS_PASSING_RATES, 250L))
ok("PL-1d rushing rates: 100 designed carries", identical(LEADERS_MIN_DESIGNED_CARRIES_RUSHING_RATES, 100L))
ok("PL-1e receiving rates: 80 targets", identical(LEADERS_MIN_TARGETS_RECEIVING_RATES, 80L))
ok("PL-1f study source commit", identical(LEADERS_STUDY_SOURCE_COMMIT, "75998e2d55f705d76f4ee4530829d01f81122894"))
mins <- vapply(LDR_STATS, function(s) if (is.null(s$min)) "none" else s$min, "")
ok("PL-1g season totals have no minimum",
   all(mins[c("pass_td", "receptions", "sacks", "def_int", "tfl", "pressures", "total_epa")] == "none"))
ok("PL-1h each rate/per-game card uses its group's constant",
   all(mins[c("pass_ypg", "rush_ypg", "rec_ypg")] == "LEADERS_MIN_GAMES_YARDS_PER_GAME") &&
   all(mins[c("pass_epa", "pass_cpoe", "pass_succ", "sack_rate", "int_rate")] == "LEADERS_MIN_DROPBACKS_PASSING_RATES") &&
   all(mins[c("rush_epa", "rush_succ", "rush_yac")] == "LEADERS_MIN_DESIGNED_CARRIES_RUSHING_RATES") &&
   all(mins[c("rec_epa", "catch_rate")] == "LEADERS_MIN_TARGETS_RECEIVING_RATES"))
ok("PL-1i lowest leads only for sack rate and interception rate",
   setequal(names(Filter(function(s) s$lower_is_better, LDR_STATS)), c("sack_rate", "int_rate")))
ok("PL-1j noise notes exactly on int rate, CPOE, EPA/carry, rush success, EPA/target",
   setequal(names(Filter(function(s) s$noise, LDR_STATS)),
            c("int_rate", "pass_cpoe", "rush_epa", "rush_succ", "rec_epa")))
ok("PL-1k only total EPA is pipeline-only",
   identical(names(Filter(function(s) s$refresh == "pipeline_only", LDR_STATS)), "total_epa"))
ok("PL-2a passing-rate bar after 12 team games is ~176 dropbacks", near(ldr_required(250, 12), 250 * 12 / 17) &&
     round(ldr_required(250, 12)) == 176)
ok("PL-2b 17 team games: full bar", near(ldr_required(100, 17), 100))

# ---------------------------------------------------------------------------
# Fixture: 2 games, team A vs B (game 1) and A vs C (game 2).
# ---------------------------------------------------------------------------
SEASON <- 2026L
mk_play <- function(game_id, game_date, home, away, posteam, play_id, play_type, ...) {
  base <- list(season = SEASON, season_type = "REG", week = as.integer(substr(game_id, 6, 7)), game_id = game_id,
               game_date = game_date, home_team = home, away_team = away, posteam = posteam, play_id = play_id,
               play_type = play_type, two_point_attempt = 0, qb_dropback = 0, qb_scramble = 0, qb_kneel = 0,
               qb_spike = 0, pass_attempt = 0, sack = 0, interception = 0, complete_pass = 0, pass_touchdown = 0,
               rush_attempt = 0, passer_id = NA_character_, rusher_player_id = NA_character_,
               receiver_player_id = NA_character_, passing_yards = NA_real_, receiving_yards = NA_real_,
               rushing_yards = NA_real_, epa = 0, qb_epa = 0, success = 0, cpoe = NA_real_)
  a <- list(...); base[names(a)] <- a
  as.data.frame(base, stringsAsFactors = FALSE)
}
pass <- function(g, d, h, a, pt, id, qb, rec, epa, comp, cpoe = 2) mk_play(g, d, h, a, pt, id, "pass", qb_dropback = 1,
  pass_attempt = 1, complete_pass = comp, passer_id = qb, receiver_player_id = rec, epa = epa, qb_epa = epa,
  success = as.numeric(epa > 0), cpoe = cpoe)
sackp <- function(g, d, h, a, pt, id, qb) mk_play(g, d, h, a, pt, id, "pass", qb_dropback = 1, pass_attempt = 1,
  sack = 1, passer_id = qb, epa = -1, qb_epa = -1)
run <- function(g, d, h, a, pt, id, rb, epa, ...) mk_play(g, d, h, a, pt, id, "run", rush_attempt = 1,
  rusher_player_id = rb, epa = epa, success = as.numeric(epa > 0), ...)
G1 <- c("2026_01_B_A", "2026-09-10", "A", "B"); G2 <- c("2026_02_C_A", "2026-09-17", "A", "C")
pbp <- rbind(
  # QB1 (team A): 3 dropbacks, 1 sack; QB2 (team B in game 1): 2 dropbacks, no sack.
  pass(G1[1], G1[2], G1[3], G1[4], "A", 1, "QB1", "WR1", 1.0, 1),
  sackp(G1[1], G1[2], G1[3], G1[4], "A", 2, "QB1"),
  pass(G1[1], G1[2], G1[3], G1[4], "B", 3, "QB2", "WR2", 0.5, 1),
  pass(G1[1], G1[2], G1[3], G1[4], "B", 4, "QB2", "WR2", -0.5, 0, cpoe = NA),
  # a scramble is a dropback, not a designed carry; a kneel and a 2-pt try count for nothing
  mk_play(G1[1], G1[2], G1[3], G1[4], "A", 5, "run", qb_dropback = 1, qb_scramble = 1, rush_attempt = 1,
          passer_id = "QB1", rusher_player_id = "QB1", epa = 0.3, qb_epa = 0.3, success = 1),
  run(G1[1], G1[2], G1[3], G1[4], "A", 6, "QB1", -0.2, qb_kneel = 1),
  run(G1[1], G1[2], G1[3], G1[4], "A", 7, "RB1", 0.4, two_point_attempt = 1),
  run(G1[1], G1[2], G1[3], G1[4], "A", 8, "RB1", 0.2),
  # game 2: QB2 traded to team C; RB1 carries again
  pass(G2[1], G2[2], G2[3], G2[4], "C", 9, "QB2", "WR2", 0.7, 1),
  run(G2[1], G2[2], G2[3], G2[4], "A", 10, "RB1", -0.1))
ps_row <- function(pid, name, pos, wk, gid, team, ...) {
  b <- list(player_id = pid, player_display_name = name, position = pos, season = SEASON, week = wk,
            season_type = "REG", game_id = gid, team = team, passing_yards = 0, passing_tds = 0, rushing_yards = 0,
            receptions = 0, receiving_yards = 0, def_sacks = 0, def_interceptions = 0, def_tackles_for_loss = 0)
  a <- list(...); b[names(a)] <- a
  as.data.frame(b, stringsAsFactors = FALSE)
}
pstats <- rbind(
  ps_row("QB1", "Quarterback One", "QB", 1L, G1[1], "A", passing_yards = 250, passing_tds = 2),
  ps_row("QB2", "Quarterback Two", "QB", 1L, G1[1], "B", passing_yards = 150, passing_tds = 1),
  ps_row("QB2", "Quarterback Two", "QB", 2L, G2[1], "C", passing_yards = 90, passing_tds = 0),
  ps_row("RB1", "Running Back", "RB", 1L, G1[1], "A", rushing_yards = 60),
  ps_row("WR2", "Receiver Two", "WR", 1L, G1[1], "B", receptions = 1, receiving_yards = 30),
  ps_row("WR2", "Receiver Two", "WR", 2L, G2[1], "C", receptions = 1, receiving_yards = 40),
  ps_row("DE1", "Rusher One", "DE", 1L, G1[1], "B", def_sacks = 1.5, def_tackles_for_loss = 2),
  ps_row("LB0", "Zero Stats", "LB", 1L, G1[1], "B"))
snap <- function(pfr, gid, wk, team, off, def = 0) data.frame(game_id = gid, season = SEASON, game_type = "REG",
  week = wk, player = pfr, pfr_player_id = pfr, position = "X", team = team, offense_snaps = off, defense_snaps = def,
  stringsAsFactors = FALSE)
snaps <- rbind(snap("pQB1", G1[1], 1L, "A", 60), snap("pQB1", G2[1], 2L, "A", 55),
               snap("pQB2", G1[1], 1L, "B", 50), snap("pQB2", G2[1], 2L, "C", 40),
               snap("pRB1", G1[1], 1L, "A", 30), snap("pRB1", G2[1], 2L, "A", 20),
               snap("pWR2", G1[1], 1L, "B", 40), snap("pWR2", G2[1], 2L, "C", 45),
               snap("pDE1", G1[1], 1L, "B", 0, 50))
players <- data.frame(gsis_id = c("QB1", "QB2", "RB1", "WR1", "WR2", "DE1"),
                      pfr_id = c("pQB1", "pQB2", "pRB1", "pWR1", "pWR2", "pDE1"),
                      display_name = c("Quarterback One", "Quarterback Two", "Running Back", "Receiver One",
                                       "Receiver Two", "Rusher One"),
                      position = c("QB", "QB", "RB", "WR", "WR", "DE"), stringsAsFactors = FALSE)
pfr_rush <- data.frame(game_id = c(G1[1], G2[1]), season = SEASON, week = 1:2, game_type = "REG", team = "A",
                       pfr_player_name = "Running Back", pfr_player_id = "pRB1", carries = c(1, 1),
                       rushing_yards_after_contact = c(3, 1), stringsAsFactors = FALSE)
pfr_def <- data.frame(game_id = G1[1], season = SEASON, week = 1L, game_type = "REG", team = "B",
                      pfr_player_name = "Rusher One", pfr_player_id = "pDE1", def_pressures = 4, stringsAsFactors = FALSE)
INP <- list(pbp = pbp, pstats = pstats, snaps = snaps, players = players, pfr_rush = pfr_rush, pfr_def = pfr_def,
            pfr_errors = list())
fx <- list(pbp = pbp, pstats = pstats, snaps = snaps, players = players, pfr_rush = pfr_rush, pfr_def = pfr_def)

# Bars this small are only reached with a tiny base: shrink the minimums for the fixture.
with_mins <- function(code) {
  old <- list(LEADERS_MIN_DROPBACKS_PASSING_RATES, LEADERS_MIN_DESIGNED_CARRIES_RUSHING_RATES,
              LEADERS_MIN_TARGETS_RECEIVING_RATES, LEADERS_MIN_GAMES_YARDS_PER_GAME)
  LEADERS_MIN_DROPBACKS_PASSING_RATES <<- 17L       # 17 * 2 team games / 17 = 2 dropbacks for team A
  LEADERS_MIN_DESIGNED_CARRIES_RUSHING_RATES <<- 17L
  LEADERS_MIN_TARGETS_RECEIVING_RATES <<- 17L
  LEADERS_MIN_GAMES_YARDS_PER_GAME <<- 8L
  on.exit({
    LEADERS_MIN_DROPBACKS_PASSING_RATES <<- old[[1]]; LEADERS_MIN_DESIGNED_CARRIES_RUSHING_RATES <<- old[[2]]
    LEADERS_MIN_TARGETS_RECEIVING_RATES <<- old[[3]]; LEADERS_MIN_GAMES_YARDS_PER_GAME <<- old[[4]]
  })
  force(code)
}
built <- with_mins(ldr_build_cards(INP, SEASON))
C <- built$cards
lead <- function(k) vapply(C[[k]]$leaders, `[[`, "", "player_id")
row_of <- function(k, id) Filter(function(r) r$player_id == id, C[[k]]$leaders)[[1]]

# ---------------------------------------------------------------------------
# PL-3 study definitions
# ---------------------------------------------------------------------------
pt <- ldr_play_tables(pbp)
ok("PL-3a dropbacks: passes, sacks and the scramble (QB1 has 3)", sum(pt$db$player_id == "QB1") == 3)
ok("PL-3b designed carries exclude scramble, kneel and 2-pt try (RB1 2, QB1 0)",
   sum(pt$ru$player_id == "RB1") == 2 && sum(pt$ru$player_id == "QB1") == 0)
ok("PL-3c targets: pass attempts with a receiver, not sacks (WR2 3, WR1 1)",
   sum(pt$re$player_id == "WR2") == 3 && sum(pt$re$player_id == "WR1") == 1)
ok("PL-3d EPA per dropback = sum(qb_epa) / dropbacks (QB1 (1 - 1 + 0.3) / 3)",
   near(row_of("pass_epa", "QB1")$value, round(0.3 / 3, 4)))
ok("PL-3e CPOE averages only dropbacks with a cpoe value (QB2: 2)", near(row_of("pass_cpoe", "QB2")$value, 2))
ok("PL-3f interception rate uses attempts (sacks and scrambles excluded)", near(row_of("int_rate", "QB1")$value, 0))

# ---------------------------------------------------------------------------
# PL-4 / PL-5 ranking and scaling with the current team
# ---------------------------------------------------------------------------
ok("PL-4a sack rate: lowest leads (QB2 0 before QB1 1/3)", identical(lead("sack_rate"), c("QB2", "QB1")))
ok("PL-4b EPA per dropback: highest leads (QB2 0.233 before QB1 0.1)", identical(lead("pass_epa"), c("QB2", "QB1")))
ok("PL-4c ties share a rank (int rate 0 / 0)", all(vapply(C$int_rate$leaders, `[[`, 0L, "rank") == 1L))
q2 <- row_of("pass_epa", "QB2")
ok("PL-5a traded QB2 is listed with his latest team C", identical(q2$team, "C"))
ok("PL-5b and held to team C's bar (1 team game -> 17 x 1 / 17 = 1)", q2$team_games_played == 1L && near(q2$required, 1))
ok("PL-5c QB1 (team A, 2 team games) needs 2 dropbacks", near(row_of("pass_epa", "QB1")$required, 2))
ok("PL-5d every listed player meets his scaled bar",
   all(unlist(lapply(C[vapply(C, function(cd) cd$kind != "total", TRUE)], function(cd)
     vapply(cd$leaders, function(r) r$sample >= r$required, TRUE)))))
ok("PL-5e passing yards per game: games from snap counts (QB1 250 / 2 games)",
   near(row_of("pass_ypg", "QB1")$value, 125) && row_of("pass_ypg", "QB1")$sample == 2)
ok("PL-5f per-game bar: 8 x 2 / 17 = 0.94 games for team A", near(row_of("pass_ypg", "QB1")$required, round(8 * 2 / 17, 1)))

# ---------------------------------------------------------------------------
# PL-6 totals and total EPA
# ---------------------------------------------------------------------------
ok("PL-6a totals have no minimum fields", is.null(C$sacks$minimum_full_season) && is.null(C$sacks$leaders[[1]]$required))
ok("PL-6b a zero total leads nothing (LB0 absent from sacks)", identical(lead("sacks"), "DE1"))
ok("PL-6c half sacks kept", near(C$sacks$leaders[[1]]$value, 1.5))
ok("PL-6d passing TDs ranked as a season total", identical(lead("pass_td"), c("QB1", "QB2")))
te <- setNames(vapply(C$total_epa$leaders, `[[`, 0, "value"), lead("total_epa"))
ok("PL-6e total EPA = passer qb_epa + designed-carry epa + target epa",
   near(te[["QB2"]], 0.7) && near(te[["QB1"]], 0.3) && near(te[["WR2"]], 0.7) && near(te[["RB1"]], 0.1))
ok("PL-6f total EPA lists every credited player (2 passers, 1 designed rusher, 2 receivers)", C$total_epa$qualified_count == 5L)

# ---------------------------------------------------------------------------
# PL-7 / PL-8 unavailable and empty cards
# ---------------------------------------------------------------------------
ok("PL-7a PFR cards built when fetched", C$rush_yac$status == "ok" && C$pressures$status == "ok" &&
     near(C$rush_yac$leaders[[1]]$value, 2))
INP2 <- INP; INP2$pfr_rush <- NULL; INP2$pfr_def <- NULL
INP2$pfr_errors <- list(rush = "HTTP 404", def = "HTTP 404")
C2 <- with_mins(ldr_build_cards(INP2, SEASON))$cards
ok("PL-7b PFR fetch failure: yards after contact and pressures unavailable, no leaders, reason given",
   all(vapply(C2[c("rush_yac", "pressures")], function(cd) cd$status == "unavailable" && !length(cd$leaders) &&
     is.null(cd$through_date) && grepl("could not be fetched", cd$null_reason), TRUE)))
C3 <- ldr_build_cards(INP, SEASON)$cards     # real minimums: nobody reaches 250 dropbacks here
ok("PL-8a no qualifier -> status not_enough_games and the panel text",
   C3$pass_epa$status == "not_enough_games" && identical(C3$pass_epa$status_text, "Not enough games yet") &&
     nzchar(C3$pass_epa$null_reason))
ok("PL-8b no yards-per-route-run card", !any(grepl("route", names(LDR_STATS))))
ok("PL-8c each card has a through date", all(vapply(C, function(cd) !is.null(cd$through_date), TRUE)))
ok("PL-8d PFR cards carry their own through date (game 2 for rushing, game 1 for pressures)",
   identical(C$rush_yac$through_date, "2026-09-17") && identical(C$pressures$through_date, "2026-09-10"))
txt <- ldr_json_text(ldr_build_payload(C, built$diag, list(), as.POSIXct("2026-11-25 12:00:00", tz = "UTC"), SEASON))
ok("PL-8e payload carries no betting vocabulary",
   !grepl("\\b(odds|lines?|spreads?|picks?|props?|wagers?|edges?|betting|sportsbook|moneyline)\\b", tolower(txt), perl = TRUE))
ok("PL-8f methods state the scaling rule and traded-player rule",
   grepl("team games played / 17", txt, fixed = TRUE) && grepl("traded player", txt, fixed = TRUE))

# ---------------------------------------------------------------------------
# PL-9 / PL-10 evening refresh
# ---------------------------------------------------------------------------
d <- tempfile("pl_"); dir.create(d)
lp <- file.path(d, "player_leaders.json")
old_payload <- ldr_build_payload(C, built$diag, list(play_by_play = "fixture"),
                                 as.POSIXct("2026-11-24 09:00:00", tz = "UTC"), SEASON)
old_payload$cards[[which(names(C) == "total_epa")]]$leaders[[1]]$value <- 99.9   # marker: must survive the refresh
ldr_write_payload(old_payload, lp)
fetch_ok <- function(rel) {
  k <- names(Filter(function(p) identical(p, rel), ldr_release_paths(SEASON)))
  # one more game: QB1 throws another completion in game 2 -> his cards change
  if (k == "pbp") return(rbind(fx$pbp, pass(G2[1], G2[2], G2[3], G2[4], "A", 11, "QB1", "WR1", 2.0, 1)))
  fx[[k]]
}
r1 <- with_mins(ldr_refresh_leaders(lp, SEASON, fetch = fetch_ok, now = as.POSIXct("2026-11-25 23:00:00", tz = "UTC")))
after <- fromJSON(lp, simplifyVector = FALSE)
ac <- setNames(after$cards, vapply(after$cards, `[[`, "", "key"))
ok("PL-9a refresh rebuilt the file", identical(r1$status, "updated"))
ok("PL-9b non-model card updated (QB1 now 4 dropbacks)",
   any(vapply(ac$pass_epa$leaders, function(r) r$player_id == "QB1" && r$sample == 4, TRUE)))
ok("PL-9c total EPA (model-based) copied through unchanged", near(ac$total_epa$leaders[[1]]$value, 99.9))
ok("PL-9d refresh noted in sources", grepl("refresh_live_results", after$sources$evening_refresh))
r1b <- with_mins(ldr_refresh_leaders(lp, SEASON, fetch = fetch_ok))
ok("PL-9e re-run with the same data is a no-op", identical(r1b$status, "up_to_date"))

bytes <- readBin(lp, "raw", file.size(lp))
fetch_fail <- function(rel) stop("cannot open URL (simulated outage)")
r2 <- ldr_refresh_leaders(lp, SEASON, fetch = fetch_fail)
ok("PL-10a failed fetch -> status fetch_failed", grepl("^fetch_failed", r2$status))
ok("PL-10b failed fetch leaves the leaders file byte-identical", identical(readBin(lp, "raw", file.size(lp)), bytes))

# End to end through refresh_live_results(): scores still patched when the leaders fetch fails.
source("tools/refresh_live_results.R")
row <- function(id, p, done, hs = NA, as_ = NA) list(
  game_id = id, season = 2026L, week = 11L, gameday = "2026-11-19", weekday = "x", gametime = "20:15",
  home_team = "HOU", home_team_name = "Houston Texans", away_team = "IND",
  away_team_name = "Indianapolis Colts", has_projection = TRUE, projected_margin = if (p > 0.5) 3 else -3,
  home_win_prob = p, away_win_prob = round(1 - p, 3), is_completed = done,
  home_score = hs, away_score = as_, actual_winner = NA, prediction_correct = NA)
mp <- file.path(d, "matchups_current_week.json")
writeLines(toJSON(list(generated_at = "2026-11-20T05:00:00Z", active_week = 11L, available_weeks = 11L,
                       total_games = 1L, matchups = list(row("2026_11_B", 0.7, FALSE))),
                  auto_unbox = TRUE, na = "null", pretty = TRUE), mp)
csv <- function(u) data.frame(game_id = "2026_11_B", season = 2026L, home_score = 27L, away_score = 13L)
res <- refresh_live_results(2026L, matchups_path = mp, diagnostics_path = file.path(d, "none.json"),
                            csv_reader = csv, digest_path = file.path(d, "none_digest.json"),
                            leaders_path = lp, leaders_fetch = fetch_fail)
m <- fromJSON(mp, simplifyVector = TRUE)$matchups
ok("PL-10c refresh_live_results patched the final score despite the leaders failure",
   res$n_changed == 1L && isTRUE(m$is_completed[1]) && m$home_score[1] == 27)
ok("PL-10d leaders status reported, file unchanged and not listed as written",
   grepl("^fetch_failed", res$leaders$status) && !(lp %in% res$files) &&
     identical(readBin(lp, "raw", file.size(lp)), bytes))
res2 <- refresh_live_results(2026L, matchups_path = mp, diagnostics_path = file.path(d, "none.json"),
                             csv_reader = csv, digest_path = file.path(d, "none_digest.json"),
                             leaders_path = lp, leaders_fetch = function(rel) with_mins(fetch_ok(rel)))
ok("PL-10e refresh_live_results with a working fetch reports the leaders step",
   res2$leaders$status %in% c("updated", "up_to_date"))
unlink(d, recursive = TRUE)

if (failures > 0) { cat(sprintf("\n%d failure(s)\n", failures)); quit(status = 1L) }
cat("\nAll player leaders tests passed.\n")
