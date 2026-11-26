# ==============================================================================
# tests/test_player_leaders.R - league leaders panel (WNBA_analytics#268)
#
# Offline (no cache, no network):
#   1. config.R minimums match the owner's #268 decisions exactly (44G base)
#   2. scaling: required = minimum x team games played / 44
#   3. ranking: highest leads, lowest leads for turnovers / turnover rate, ties
#   4. qualifying uses the scaled bar of the player's CURRENT team (traded player)
#   5. rate formulas (Basketball Reference, as in the study) on a hand fixture
#   6. RAPM: a past-season fit is never shown; a current-season fit needs both sides
#   7. ESPN game summary parsing (saved WNBA fixture) gives the box-score rows
#   8. evening refresh: success adds the game; a failed fetch leaves the leaders
#      file byte-identical while final-score patching still happens; re-run no-op
#
# Usage: Rscript tests/test_player_leaders.R
# ==============================================================================

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  if (basename(base) == "tests") normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
  else normalizePath(base, winslash = "/", mustWork = FALSE)
})
setwd(REPO_ROOT)

failures <- 0L; passes <- 0L
ok <- function(label, cond) {
  if (isTRUE(cond)) { passes <<- passes + 1L; cat(sprintf("  PASS  %s\n", label)) }
  else { failures <<- failures + 1L; cat(sprintf("  FAIL  %s\n", label)) }
}
near <- function(a, b, tol = 1e-6) isTRUE(all(abs(a - b) < tol))

Sys.setenv(WNBA_SKIP_STAGE_AUTORUN = "1")
ple <- new.env(parent = globalenv())
suppressMessages(sys.source(file.path(REPO_ROOT, "build_player_leaders.R"), envir = ple))
Sys.unsetenv("WNBA_SKIP_STAGE_AUTORUN")

# ---------------------------------------------------------------------------
cat("1. config.R minimums (owner decisions, #268)\n")
expect <- c(LEADERS_MIN_GAMES_PTS = 6, LEADERS_MIN_GAMES_REB = 6, LEADERS_MIN_GAMES_AST = 6,
            LEADERS_MIN_GAMES_TOV = 10, LEADERS_MIN_GAMES_FG3M = 10, LEADERS_MIN_GAMES_OREB = 10,
            LEADERS_MIN_GAMES_BLK = 10, LEADERS_MIN_GAMES_STL = 15,
            LEADERS_MIN_FTA_FT_PCT = 100, LEADERS_MIN_FGA_FG_PCT = 150, LEADERS_MIN_FG3A_FG3_PCT = 80,
            LEADERS_MIN_MINUTES_USG_PCT = 150, LEADERS_MIN_MINUTES_AST_PCT = 150,
            LEADERS_MIN_MINUTES_ORB_PCT = 200, LEADERS_MIN_MINUTES_DRB_PCT = 200,
            LEADERS_MIN_MINUTES_TOV_PCT = 450, LEADERS_MIN_MINUTES_EFG_PCT = 450,
            LEADERS_MIN_MINUTES_TS_PCT = 450, LEADERS_MIN_POSS_PER_SIDE_RAPM = 1000,
            LEADERS_FULL_SEASON_GAMES = 44)
for (k in names(expect)) ok(sprintf("%s = %s", k, expect[[k]]), identical(as.numeric(get(k, envir = ple)), expect[[k]]))
ok("study source commit", identical(ple$LEADERS_STUDY_SOURCE_COMMIT, "70a56bb4863b62e26d7e68aef54997fce02b059e"))
ok("21 cards, every stat names an existing config constant",
   length(ple$PL_STATS) == 21L && all(vapply(ple$PL_STATS, function(s) exists(s$min, envir = ple), logical(1))))
ok("noise notes on 3P%, eFG%, TS% and the three RAPM cards only",
   setequal(names(Filter(function(s) s$noise, ple$PL_STATS)),
            c("fg3_pct", "efg_pct", "ts_pct", "orapm", "drapm", "total_rapm")))
ok("lowest leads only for turnovers and turnover rate",
   setequal(names(Filter(function(s) s$lower_is_better, ple$PL_STATS)), c("tov", "tov_pct")))

# ---------------------------------------------------------------------------
cat("2. scaling\n")
ok("FT% bar after 22 team games is 50 attempts", near(ple$pl_required(100, 22), 50))
ok("11 team games: 6-game bar is 6*11/44", near(ple$pl_required(6, 11), 6 * 11 / 44))
ok("44 team games: full bar", near(ple$pl_required(450, 44), 450))

# ---------------------------------------------------------------------------
cat("3-4. ranking and qualifying\n")
st_pts <- ple$PL_STATS$pts
cand <- data.frame(player_id = c("a", "b", "c", "d", "e"), player = c("A", "B", "C", "D", "E"),
                   team = "NY", position = c("G", "F", "C", "PG", "G-F"),
                   value = c(20, 25, 25, 30, 18), sample = c(3, 3, 3, 1, 3),
                   team_games_played = 22, stringsAsFactors = FALSE)
# bar = 6 * 22 / 44 = 3 games: d (1 game) does not qualify.
cd <- ple$pl_card(st_pts, cand, "2026-07-15")
ranks <- vapply(cd$leaders$all, `[[`, 0L, "rank"); who <- vapply(cd$leaders$all, `[[`, "", "player")
ok("non-qualifier excluded at scaled bar", !("D" %in% who) && cd$qualified_count$all == 4L)
ok("highest leads, ties share rank and list by name", identical(who, c("B", "C", "A", "E")) && identical(ranks, c(1L, 1L, 3L, 4L)))
ok("position filter lists: G gets A and E (G-F -> G), F gets B, C gets C",
   identical(vapply(cd$leaders$G, `[[`, "", "player"), c("A", "E")) &&
     identical(vapply(cd$leaders$F, `[[`, "", "player"), "B") && cd$leaders$C[[1]]$rank == 1L)
ok("card carries through date, required and status ok",
   cd$through_date == "2026-07-15" && cd$status == "ok" && near(cd$leaders$all[[1]]$required, 3))
st_tov <- ple$PL_STATS$tov
cd2 <- ple$pl_card(st_tov, transform(cand, value = c(3, 1, 2, 0.5, 4), sample = c(10, 10, 10, 2, 10), minutes = 450), "2026-07-15")
ok("turnovers: lowest leads", identical(vapply(cd2$leaders$all, `[[`, "", "player"), c("B", "C", "A", "E")))
cd3 <- ple$pl_card(st_pts, transform(cand, sample = 1), "2026-07-15")
ok("no qualifiers -> not_enough_games with the panel text and a reason",
   cd3$status == "not_enough_games" && cd3$status_text == "Not enough games yet" &&
     nzchar(cd3$null_reason) && length(cd3$leaders$all) == 0L)
ok("top 10 cap", length(ple$pl_card(st_pts, data.frame(player_id = as.character(1:15), player = sprintf("P%02d", 1:15),
   team = "NY", position = "G", value = 1:15, sample = 30, team_games_played = 22), "x")$leaders$all) == 10L)

# Traded player: games for two teams; identity and bar follow the latest team.
g <- data.frame(game_id = c("1", "2", "3"), game_date = c("2026-06-01", "2026-06-02", "2026-06-05"),
                player_id = "t", player = "Traded", team_id = c("10", "10", "20"), team = c("ATL", "ATL", "NY"),
                position = "G", min = 30, fgm = 5, fga = 10, fg3m = 1, fg3a = 3, ftm = 2, fta = 2,
                oreb = 1, dreb = 4, reb = 5, ast = 3, stl = 1, blk = 0, tov = 2, pts = 13,
                tm_min = 200, tm_fgm = 32, tm_fga = 70, tm_fta = 18, tm_tov = 14, tm_oreb = 8, tm_dreb = 26,
                opp_oreb = 9, opp_dreb = 25, stringsAsFactors = FALSE)
tot <- ple$pl_add_games(ple$pl_empty_totals(), g)
ok("traded player: 3 games summed, team follows the latest game", tot$games == 3 && tot$team == "NY" && tot$team_id == "20")

# ---------------------------------------------------------------------------
cat("5. rate formulas (study definitions)\n")
share <- 30 / (200 / 5)
cards <- ple$pl_box_cards(tot, data.frame(team_id = c("10", "20"), team = c("ATL", "NY"), games = c(44, 44)), "2026-06-05")
val <- function(k) { x <- Filter(function(c) c$key == k, cards)[[1]]; x$leaders$all }
v <- function(k) { st <- ple$PL_STATS[[k]]; st$num(tot) / st$den(tot) }
ok("eFG% = (FG + 0.5*3P)/FGA", near(v("efg_pct"), (15 + 1.5) / 30))
ok("TS% = PTS/(2*(FGA+0.44*FTA))", near(v("ts_pct"), 39 / (2 * (30 + 0.44 * 6))))
ok("TOV% = 100*TOV/(FGA+0.44*FTA+TOV)", near(v("tov_pct"), 100 * 6 / (30 + 0.44 * 6 + 6)))
ok("ORB% = 100*ORB*(TmMP/5)/(MP*(TmORB+OppDRB))", near(v("orb_pct"), 100 * 3 / (3 * share * (8 + 25))))
ok("DRB% = 100*DRB*(TmMP/5)/(MP*(TmDRB+OppORB))", near(v("drb_pct"), 100 * 12 / (3 * share * (26 + 9))))
ok("AST% = 100*AST/((MP/(TmMP/5))*TmFG - FG)", near(v("ast_pct"), 100 * 9 / (3 * share * 32 - 15)))
ok("USG% = 100*(FGA+0.44FTA+TOV)*(TmMP/5)/(MP*(TmFGA+0.44TmFTA+TmTOV))",
   near(v("usg_pct"), 100 * (30 + 0.44 * 6 + 6) / (3 * share * (70 + 0.44 * 18 + 14))))
ok("90 minutes is below the scaled 450-minute bar at 44 team games", length(val("ts_pct")) == 0L)
g_na <- g; g_na$tm_oreb[1] <- NA
tot_na <- ple$pl_add_games(ple$pl_empty_totals(), g_na)
cards_na <- ple$pl_box_cards(tot_na, data.frame(team_id = c("10", "20"), team = c("ATL", "NY"), games = c(5, 5)), "x")
orb_na <- Filter(function(c) c$key == "orb_pct", cards_na)[[1]]
ok("missing team context -> no rate (not imputed), not ranked", tot_na$ctx_missing_games == 1 && length(orb_na$leaders$all) == 0L)

# ---------------------------------------------------------------------------
cat("6. RAPM\n")
tg <- data.frame(team_id = c("10", "20"), team = c("ATL", "NY"), games = c(22, 22), stringsAsFactors = FALSE)
rapm <- data.frame(player_id = c("p1", "p2", "p3"), player_name = c("Traded", "Two", "Three"), team = c("NY", "ATL", "ATL"),
                   n_off_poss = c(600, 400, 550), n_def_poss = c(550, 600, 490),
                   orapm = c(1, 2, 3), drapm = c(0.5, 1, 2), total_rapm = c(1.5, 3, 5),
                   season = 2025L, season_label = "2025", stringsAsFactors = FALSE)
rc <- ple$pl_rapm_cards(rapm, tg, tot, season = 2026L, crosswalk_path = NULL)
ok("past-season fit: every RAPM card empty with a no-fallback reason",
   all(vapply(rc, function(c) c$status == "not_enough_games" && grepl("does not fall back", c$null_reason), logical(1))))
rapm$season <- 2026L
rc2 <- ple$pl_rapm_cards(rapm, tg, tot, season = 2026L, crosswalk_path = NULL)
# bar = 1000 * 22 / 44 = 500 per side: p1 qualifies, p2 (400 off) and p3 (490 def) do not.
ok("current-season fit: 500 per side at 22 games, both sides required",
   identical(vapply(rc2$total_rapm$leaders$all, `[[`, "", "player"), "Traded"))

# ---------------------------------------------------------------------------
cat("6b. turnovers per game: 450-minute floor\n")
ok("config: LEADERS_MIN_MINUTES_TOV_PER_GAME is 450", identical(as.integer(ple$LEADERS_MIN_MINUTES_TOV_PER_GAME), 450L))
st_tov <- ple$PL_STATS[["tov"]]
cand_tov <- data.frame(player_id = c("a", "b", "c"), player = c("Low minutes", "Enough minutes", "Few games"),
                       team = "NY", position = "G", value = c(0, 1.2, 0.5), sample = c(10, 10, 4),
                       minutes = c(50, 300, 400), team_games_played = 22, stringsAsFactors = FALSE)
# At 22 team games: 5 games and 225 minutes. "Low minutes" fails minutes, "Few games" fails games.
card_tov <- ple$pl_card(st_tov, cand_tov, "2026-07-15")
ok("tov: only the player past both scaled bars qualifies",
   identical(vapply(card_tov$leaders$all, `[[`, "", "player"), "Enough minutes"))
ok("tov card carries the minutes bar", identical(card_tov$minimum_minutes_full_season, 450) &&
   identical(card_tov$minimum_minutes_constant, "LEADERS_MIN_MINUTES_TOV_PER_GAME"))
card_pts <- ple$pl_card(ple$PL_STATS[["pts"]], cand_tov, "2026-07-15")
ok("other cards have no minutes bar", is.null(card_pts$minimum_minutes_full_season) && length(card_pts$leaders$all) == 3L)
card_none <- ple$pl_card(st_tov, cand_tov[1, ], "2026-07-15")
ok("empty tov card names both bars", grepl("450 minutes", card_none$null_reason))

cat("6c. leader RAPM fit is separate from the ensemble fit\n")
ok("RAPM cards name the leader cache file", grepl("rapm_ratings_leaders.rds", rc2$total_rapm$through_date_null_reason, fixed = TRUE))
tmpd <- tempfile("leaders_rapm_"); dir.create(tmpd)
fake <- file.path(tmpd, "engine.R")
writeLines(c("load_or_build_wnba_pbp_cache <- function(seasons, force_refresh = FALSE) NULL",
             "fit_rapm_ratings <- function(...) stop('must not be called')"), fake)
out_rds <- file.path(tmpd, "rapm_ratings_leaders.rds")
res <- suppressMessages(ple$pl_fit_leader_rapm(2026L, out_path = out_rds, engine = fake))
ok("no current-season possessions: no fit, no file, no error", is.null(res) && !file.exists(out_rds))
ok("autorun flag restored after the fit", !nzchar(Sys.getenv("WNBA_SKIP_STAGE_AUTORUN")))
eng_src <- readLines(file.path(REPO_ROOT, "rapm_engine.R"))
ok("rapm_engine.R honours WNBA_SKIP_STAGE_AUTORUN", any(grepl("WNBA_SKIP_STAGE_AUTORUN", eng_src, fixed = TRUE)))

# ---------------------------------------------------------------------------
cat("7. ESPN summary parsing\n")
fx <- jsonlite::fromJSON(file.path(REPO_ROOT, "tests", "fixtures", "espn_summary_401856890.json"), simplifyVector = FALSE)
er <- ple$pl_game_rows_from_espn(fx, "401856890", "2026-05-15")
con <- er$players[er$players$team == "CON", ]
ok("two teams, players who played only", nrow(er$teams) == 2L && all(!is.na(er$players$min)))
ok("CON player sums match the team box (32-83 FG, 15 FTA)", sum(con$fgm) == 32 && sum(con$fga) == 83 && sum(con$fta) == 15)
ok("team context attached (opponent rebounds, team minutes)", all(!is.na(er$players$opp_dreb)) && all(er$players$tm_min > 0))
ok("bad summary stops", inherits(tryCatch(ple$pl_game_rows_from_espn(list(), "x", "d"), error = function(e) e), "error"))

# ---------------------------------------------------------------------------
cat("8. evening refresh (tools/refresh_live_results.R)\n")
source(file.path(REPO_ROOT, "tools", "refresh_live_results.R"))
d <- tempfile("plr_"); dir.create(d)
m <- data.frame(game_id = c("401856890", "777"), game_date = c("2026-05-15", "2026-05-15"),
                home_team = c("NY", "ATL"), away_team = c("CON", "LV"), is_completed = c(TRUE, FALSE),
                home_score = c(85L, NA), away_score = c(75L, NA), actual_margin = c(10L, NA),
                actual_winner = c("NY", NA), predicted_winner = c("NY", "ATL"), prediction_correct = c(TRUE, NA),
                has_logged_prediction = c(TRUE, TRUE),
                week = c(1L, 1L), season_type = c("regular", "regular"), stringsAsFactors = FALSE)
w <- data.frame(week = 1L, label = "Week 1", start_date = "2026-05-15", end_date = "2026-05-21",
                total_games = 2L, completed_games = 1L, pending_games = 1L, graded_games = 1L,
                correct_games = 1L, accuracy_pct = 100.0, stringsAsFactors = FALSE)
w$season_types <- list("regular")
p <- list(
  available_weeks = 1L, active_week = 1L,
  summary = list(total_games = 2L, completed_games = 1L, pending_games = 1L, graded_games = 1L,
                 correct_games = 1L, accuracy_pct = 100.0, graded_games_available = TRUE,
                 grading_state = "ok", played_without_logged_prediction = 0L),
  weeks = w, matchups = m
)
mp <- file.path(d, "matchups_slates.json")
writeLines(jsonlite::toJSON(p, auto_unbox = TRUE, na = "null", pretty = TRUE), mp)
dp <- file.path(d, "landing_digest.json")
writeLines("{}", dp)
lp <- file.path(d, "player_leaders.json")
empty_payload <- ple$pl_build_payload(ple$pl_empty_totals(),
  data.frame(team_id = character(0), team = character(0), games = numeric(0), stringsAsFactors = FALSE),
  character(0), list(), list(player_box = "fixture"))
ple$pl_write_payload(empty_payload, lp)
bytes_before <- readBin(lp, "raw", file.info(lp)$size)
scores <- function(dates) data.frame(game_id = "777", is_final = TRUE, home_score = 81L, away_score = 79L)

# Failure path: summary fetch fails -> scores patched, leaders file untouched.
r_fail <- suppressWarnings(refresh_live_results(dates = "2026-05-15", payload_path = mp, fetcher = scores,
                                                digest_path = dp, summary_fetcher = function(id) NULL,
                                                today = as.Date("2026-05-16")))
ok("fetch failure: final score still patched", r_fail$n_changed == 1L && !is.null(r_fail$file))
ok("fetch failure: leaders status reports it and file is byte-identical",
   grepl("^fetch_failed", r_fail$leaders$status) && is.null(r_fail$leaders$file) &&
     identical(readBin(lp, "raw", file.info(lp)$size), bytes_before))
r_err <- refresh_live_results(dates = "2026-05-15", payload_path = mp, fetcher = scores,
                              digest_path = dp, summary_fetcher = function(id) stop("boom"),
                              today = as.Date("2026-05-16"))
ok("fetcher error is caught; leaders untouched", grepl("^error", r_err$leaders$status) &&
     identical(readBin(lp, "raw", file.info(lp)$size), bytes_before))

# Success path: both games now final; 401856890 parses from the fixture, 777 has none -> all or nothing.
r_partial <- suppressWarnings(refresh_live_results(dates = "2026-05-15", payload_path = mp, fetcher = scores,
  digest_path = dp, summary_fetcher = function(id) if (id == "401856890") fx else NULL, today = as.Date("2026-05-16")))
ok("one of two summaries missing: all or nothing, file untouched",
   grepl("^fetch_failed: 777", r_partial$leaders$status) && identical(readBin(lp, "raw", file.info(lp)$size), bytes_before))
pm <- jsonlite::fromJSON(mp, simplifyVector = TRUE); pm$matchups$is_completed[pm$matchups$game_id == "777"] <- FALSE
pm$matchups$game_id[pm$matchups$game_id == "777"] <- "778"
writeLines(jsonlite::toJSON(pm, auto_unbox = TRUE, na = "null", pretty = TRUE), mp)
r_ok <- refresh_live_results(dates = character(0), payload_path = mp, fetcher = scores,
                             digest_path = dp, summary_fetcher = function(id) fx, today = as.Date("2026-05-16"))
out <- jsonlite::fromJSON(lp, simplifyVector = FALSE)
pts <- Filter(function(c) c$key == "pts", out$cards)[[1]]
ok("success: game added, through date set, cards rebuilt",
   r_ok$leaders$status == "updated" && r_ok$leaders$n_games == 1L && out$through_date == "2026-05-15" &&
     identical(unlist(out$season_totals$game_ids), "401856890") && pts$status == "ok")
ok("success: team games played counted once per team", all(unlist(out$season_totals$team_games$games) == 1))
r_again <- refresh_live_results(dates = character(0), payload_path = mp, fetcher = scores,
                                digest_path = dp, summary_fetcher = function(id) stop("must not be called"),
                                today = as.Date("2026-05-16"))
ok("re-run: up to date, nothing fetched", r_again$leaders$status == "up_to_date")
ok("no leaders file -> nothing to patch", refresh_live_results(dates = character(0), payload_path = mp,
   digest_path = dp, leaders_path = file.path(d, "absent.json"), today = as.Date("2026-05-16"))$leaders$status == "no_file")

# Payload text carries no betting vocabulary.
txt <- ple$pl_json_text(out)
ok("no betting terms in the payload",
   !grepl("\\b(odds|lines?|spreads?|picks?|props?|wagers?|edges?|bets?|betting|sportsbook|moneyline|parlay)\\b", txt, ignore.case = TRUE))

cat(sprintf("\n%d passed, %d failed\n", passes, failures))
if (failures > 0L) quit(status = 1L)
