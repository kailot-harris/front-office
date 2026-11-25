# ==============================================================================
# tests/test_player_leaders.R - league leaders panel (NBA_analytics#254)
#
# Offline (no cache, no network):
#   1. config.R minimums match the owner's #253 decisions exactly
#   2. scaling: required = minimum x team games played / 82
#   3. ranking: highest leads, lowest leads for turnovers / turnover rate, ties
#   4. qualifying uses the scaled bar of the player's CURRENT team (traded player)
#   5. rate formulas (Basketball Reference, as in the study) on a hand fixture
#   6. RAPM: a past-season fit is never shown; a current-season fit needs both sides
#   7. ESPN game summary parsing (saved fixture) gives the box-score rows
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

Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")
ple <- new.env(parent = globalenv())
suppressMessages(sys.source(file.path(REPO_ROOT, "build_player_leaders.R"), envir = ple))
Sys.unsetenv("NBA_SKIP_STAGE_AUTORUN")

# ---------------------------------------------------------------------------
cat("1. config.R minimums (owner decisions, #253)\n")
expect <- c(LEADERS_MIN_GAMES_PTS = 10, LEADERS_MIN_GAMES_REB = 10, LEADERS_MIN_GAMES_AST = 10,
            LEADERS_MIN_GAMES_TOV = 20, LEADERS_MIN_GAMES_FG3M = 20, LEADERS_MIN_GAMES_OREB = 20,
            LEADERS_MIN_GAMES_BLK = 20, LEADERS_MIN_GAMES_STL = 30,
            LEADERS_MIN_FTA_FT_PCT = 250, LEADERS_MIN_FGA_FG_PCT = 250, LEADERS_MIN_FG3A_FG3_PCT = 150,
            LEADERS_MIN_MINUTES_USG_PCT = 250, LEADERS_MIN_MINUTES_AST_PCT = 250,
            LEADERS_MIN_MINUTES_ORB_PCT = 400, LEADERS_MIN_MINUTES_DRB_PCT = 400,
            LEADERS_MIN_MINUTES_TOV_PCT = 1000, LEADERS_MIN_MINUTES_EFG_PCT = 1000,
            LEADERS_MIN_MINUTES_TS_PCT = 1000, LEADERS_MIN_POSS_PER_SIDE_RAPM = 2000,
            LEADERS_FULL_SEASON_GAMES = 82)
for (k in names(expect)) ok(sprintf("%s = %s", k, expect[[k]]), identical(as.numeric(get(k, envir = ple)), expect[[k]]))
ok("study source commit", identical(ple$LEADERS_STUDY_SOURCE_COMMIT, "d340cfdf247cb4876228d7a5f917cac0cba60de9"))
ok("21 cards, every stat names an existing config constant",
   length(ple$PL_STATS) == 21L && all(vapply(ple$PL_STATS, function(s) exists(s$min, envir = ple), logical(1))))
ok("noise notes on 3P%, eFG%, TS% and the three RAPM cards only",
   setequal(names(Filter(function(s) s$noise, ple$PL_STATS)),
            c("fg3_pct", "efg_pct", "ts_pct", "orapm", "drapm", "total_rapm")))
ok("lowest leads only for turnovers and turnover rate",
   setequal(names(Filter(function(s) s$lower_is_better, ple$PL_STATS)), c("tov", "tov_pct")))

# ---------------------------------------------------------------------------
cat("2. scaling\n")
ok("FT% bar after 41 team games is 125 attempts", near(ple$pl_required(250, 41), 125))
ok("17 team games: 10-game bar is 10*17/82", near(ple$pl_required(10, 17), 10 * 17 / 82))
ok("82 team games: full bar", near(ple$pl_required(1000, 82), 1000))

# ---------------------------------------------------------------------------
cat("3-4. ranking and qualifying\n")
st_pts <- ple$PL_STATS$pts
cand <- data.frame(player_id = c("a", "b", "c", "d", "e"), player = c("A", "B", "C", "D", "E"),
                   team = "BOS", position = c("G", "F", "C", "PG", "G-F"),
                   value = c(20, 25, 25, 30, 18), sample = c(5, 5, 5, 2, 5),
                   team_games_played = 41, stringsAsFactors = FALSE)
# bar = 10 * 41 / 82 = 5 games: d (2 games) does not qualify.
cd <- ple$pl_card(st_pts, cand, "2026-11-23")
ranks <- vapply(cd$leaders$all, `[[`, 0L, "rank"); who <- vapply(cd$leaders$all, `[[`, "", "player")
ok("non-qualifier excluded at scaled bar", !("D" %in% who) && cd$qualified_count$all == 4L)
ok("highest leads, ties share rank and list by name", identical(who, c("B", "C", "A", "E")) && identical(ranks, c(1L, 1L, 3L, 4L)))
ok("position filter lists: G gets A and E (G-F -> G), F gets B, C gets C",
   identical(vapply(cd$leaders$G, `[[`, "", "player"), c("A", "E")) &&
     identical(vapply(cd$leaders$F, `[[`, "", "player"), "B") && cd$leaders$C[[1]]$rank == 1L)
ok("card carries through date, required and status ok",
   cd$through_date == "2026-11-23" && cd$status == "ok" && near(cd$leaders$all[[1]]$required, 5))
st_tov <- ple$PL_STATS$tov
cd2 <- ple$pl_card(st_tov, transform(cand, value = c(3, 1, 2, 0.5, 4), sample = c(12, 12, 12, 2, 12), minutes = 1000), "2026-11-23")
ok("turnovers: lowest leads", identical(vapply(cd2$leaders$all, `[[`, "", "player"), c("B", "C", "A", "E")))
cd3 <- ple$pl_card(st_pts, transform(cand, sample = 1), "2026-11-23")
ok("no qualifiers -> not_enough_games with the panel text and a reason",
   cd3$status == "not_enough_games" && cd3$status_text == "Not enough games yet" &&
     nzchar(cd3$null_reason) && length(cd3$leaders$all) == 0L)
ok("top 10 cap", length(ple$pl_card(st_pts, data.frame(player_id = as.character(1:15), player = sprintf("P%02d", 1:15),
   team = "BOS", position = "G", value = 1:15, sample = 50, team_games_played = 41), "x")$leaders$all) == 10L)

# Traded player: games for two teams; identity and bar follow the latest team.
g <- data.frame(game_id = c("1", "2", "3"), game_date = c("2026-11-01", "2026-11-02", "2026-11-05"),
                player_id = "t", player = "Traded", team_id = c("10", "10", "20"), team = c("BOS", "BOS", "NYK"),
                position = "G", min = 30, fgm = 5, fga = 10, fg3m = 1, fg3a = 3, ftm = 2, fta = 2,
                oreb = 1, dreb = 4, reb = 5, ast = 3, stl = 1, blk = 0, tov = 2, pts = 13,
                tm_min = 240, tm_fgm = 40, tm_fga = 85, tm_fta = 20, tm_tov = 14, tm_oreb = 10, tm_dreb = 33,
                opp_oreb = 11, opp_dreb = 32, stringsAsFactors = FALSE)
tot <- ple$pl_add_games(ple$pl_empty_totals(), g)
ok("traded player: 3 games summed, team follows the latest game", tot$games == 3 && tot$team == "NYK" && tot$team_id == "20")

# ---------------------------------------------------------------------------
cat("5. rate formulas (study definitions)\n")
share <- 30 / (240 / 5)
cards <- ple$pl_box_cards(tot, data.frame(team_id = c("10", "20"), team = c("BOS", "NYK"), games = c(82, 82)), "2026-11-05")
val <- function(k) { x <- Filter(function(c) c$key == k, cards)[[1]]; x$leaders$all }
# Minute bars at 82 games (90 minutes played) exclude rate cards; recompute directly.
v <- function(k) { st <- ple$PL_STATS[[k]]; st$num(tot) / st$den(tot) }
ok("eFG% = (FG + 0.5*3P)/FGA", near(v("efg_pct"), (15 + 1.5) / 30))
ok("TS% = PTS/(2*(FGA+0.44*FTA))", near(v("ts_pct"), 39 / (2 * (30 + 0.44 * 6))))
ok("TOV% = 100*TOV/(FGA+0.44*FTA+TOV)", near(v("tov_pct"), 100 * 6 / (30 + 0.44 * 6 + 6)))
ok("ORB% = 100*ORB*(TmMP/5)/(MP*(TmORB+OppDRB))", near(v("orb_pct"), 100 * 3 / (3 * share * (10 + 32))))
ok("DRB% = 100*DRB*(TmMP/5)/(MP*(TmDRB+OppORB))", near(v("drb_pct"), 100 * 12 / (3 * share * (33 + 11))))
ok("AST% = 100*AST/((MP/(TmMP/5))*TmFG - FG)", near(v("ast_pct"), 100 * 9 / (3 * share * 40 - 15)))
ok("USG% = 100*(FGA+0.44FTA+TOV)*(TmMP/5)/(MP*(TmFGA+0.44TmFTA+TmTOV))",
   near(v("usg_pct"), 100 * (30 + 0.44 * 6 + 6) / (3 * share * (85 + 0.44 * 20 + 14))))
ok("90 minutes is below the scaled 1,000-minute bar at 82 team games", length(val("ts_pct")) == 0L)
g_na <- g; g_na$tm_oreb[1] <- NA
tot_na <- ple$pl_add_games(ple$pl_empty_totals(), g_na)
cards_na <- ple$pl_box_cards(tot_na, data.frame(team_id = c("10", "20"), team = c("BOS", "NYK"), games = c(5, 5)), "x")
orb_na <- Filter(function(c) c$key == "orb_pct", cards_na)[[1]]
ok("missing team context -> no rate (not imputed), not ranked", tot_na$ctx_missing_games == 1 && length(orb_na$leaders$all) == 0L)

# ---------------------------------------------------------------------------
cat("6. RAPM\n")
tg <- data.frame(team_id = c("10", "20"), team = c("BOS", "NYK"), games = c(41, 41), stringsAsFactors = FALSE)
rapm <- data.frame(player_id = c("p1", "p2", "p3"), player_name = c("Traded", "Two", "Three"), team = c("NYK", "BOS", "BOS"),
                   off_possessions = c(1500, 900, 1200), def_possessions = c(1400, 1300, 990),
                   orapm = c(1, 2, 3), drapm = c(0.5, 1, 2), total_rapm = c(1.5, 3, 5),
                   season = 2026L, season_label = "2025-26", stringsAsFactors = FALSE)
rc <- ple$pl_rapm_cards(rapm, tg, tot, season = 2027L)
ok("past-season fit: every RAPM card empty with a no-fallback reason",
   all(vapply(rc, function(c) c$status == "not_enough_games" && grepl("does not fall back", c$null_reason), logical(1))))
rapm$season <- 2027L
rc2 <- ple$pl_rapm_cards(rapm, tg, tot, season = 2027L)
# bar = 2000 * 41 / 82 = 1000 per side: p1 qualifies, p2 (900 off) and p3 (990 def) do not.
ok("current-season fit: 1,000 per side at 41 games, both sides required",
   identical(vapply(rc2$total_rapm$leaders$all, `[[`, "", "player"), "Traded"))

# ---------------------------------------------------------------------------
cat("6b. turnovers per game: 1,000-minute floor (owner decision, 2026-11-25)\n")
ok("config: LEADERS_MIN_MINUTES_TOV_PER_GAME is 1000", identical(as.integer(ple$LEADERS_MIN_MINUTES_TOV_PER_GAME), 1000L))
st_tov <- ple$PL_STATS[["tov"]]
cand_tov <- data.frame(player_id = c("a", "b", "c"), player = c("Low minutes", "Enough minutes", "Few games"),
                       team = "BOS", position = "G", value = c(0, 1.2, 0.5), sample = c(20, 20, 9),
                       minutes = c(100, 600, 900), team_games_played = 41, stringsAsFactors = FALSE)
# At 41 team games: 10 games and 500 minutes. "Low minutes" fails minutes, "Few games" fails games.
card_tov <- ple$pl_card(st_tov, cand_tov, "2026-11-23")
ok("tov: only the player past both scaled bars qualifies",
   identical(vapply(card_tov$leaders$all, `[[`, "", "player"), "Enough minutes"))
ok("tov card carries the minutes bar", identical(card_tov$minimum_minutes_full_season, 1000) &&
   identical(card_tov$minimum_minutes_constant, "LEADERS_MIN_MINUTES_TOV_PER_GAME"))
card_pts <- ple$pl_card(ple$PL_STATS[["pts"]], cand_tov, "2026-11-23")
ok("other cards have no minutes bar", is.null(card_pts$minimum_minutes_full_season) && length(card_pts$leaders$all) == 3L)
card_none <- ple$pl_card(st_tov, cand_tov[1, ], "2026-11-23")
ok("empty tov card names both bars", grepl("1,000 minutes", card_none$null_reason))

cat("6c. leader RAPM fit is separate from the ensemble fit\n")
ok("RAPM cards name the leader cache file", grepl("rapm_ratings_leaders.rds", rc2$total_rapm$through_date_null_reason, fixed = TRUE))
tmpd <- tempfile("leaders_rapm_"); dir.create(tmpd)
fake <- file.path(tmpd, "engine.R")
writeLines(c("load_or_build_possession_cache <- function(season, force_refresh = FALSE) NULL",
             "estimate_rapm_from_possessions <- function(...) stop('must not be called')"), fake)
out_rds <- file.path(tmpd, "rapm_ratings_leaders.rds")
res <- suppressMessages(ple$pl_fit_leader_rapm(2027L, out_path = out_rds, engine = fake))
ok("no current-season possessions: no fit, no file, no error", is.null(res) && !file.exists(out_rds))
ok("autorun flag restored after the fit", !nzchar(Sys.getenv("NBA_SKIP_STAGE_AUTORUN")))
eng_src <- readLines(file.path(REPO_ROOT, "rapm_engine.R"))
ok("rapm_engine.R honours NBA_SKIP_STAGE_AUTORUN", any(grepl("NBA_SKIP_STAGE_AUTORUN", eng_src, fixed = TRUE)))

# ---------------------------------------------------------------------------
cat("7. ESPN summary parsing\n")
fx <- jsonlite::fromJSON(file.path(REPO_ROOT, "tests", "fixtures", "espn_summary_401910036.json"), simplifyVector = FALSE)
er <- ple$pl_game_rows_from_espn(fx, "401910036", "2026-11-23")
mem <- er$players[er$players$team == "MEM", ]
ok("two teams, players who played only", nrow(er$teams) == 2L && all(!is.na(er$players$min)))
ok("MEM player sums match the team box (39-81 FG, 24 FTA)", sum(mem$fgm) == 39 && sum(mem$fga) == 81 && sum(mem$fta) == 24)
ok("team context attached (opponent rebounds, team minutes)", all(!is.na(er$players$opp_dreb)) && all(er$players$tm_min > 0))
ok("bad summary stops", inherits(tryCatch(ple$pl_game_rows_from_espn(list(), "x", "d"), error = function(e) e), "error"))

# ---------------------------------------------------------------------------
cat("8. evening refresh (tools/refresh_live_results.R)\n")
source(file.path(REPO_ROOT, "tools", "refresh_live_results.R"))
d <- tempfile("plr_"); dir.create(d)
m <- data.frame(game_id = c("401910036", "777"), game_date = c("2026-11-23", "2026-11-23"),
                home_team = c("CHA", "BOS"), away_team = c("MEM", "NYK"), is_completed = c(TRUE, FALSE),
                home_score = c(100L, NA), away_score = c(110L, NA), actual_margin = c(-10L, NA),
                actual_winner = c("MEM", NA), predicted_winner = c("MEM", "BOS"), prediction_correct = c(TRUE, NA),
                slate = 1L, stringsAsFactors = FALSE)
p <- list(completed_games = 1L, pending_games = 1L, matchups = m,
          slates = data.frame(slate = 1L, graded_total = 1L, correct_total = 1L, accuracy_pct = 100))
mp <- file.path(d, "matchups_slates.json")
writeLines(jsonlite::toJSON(p, auto_unbox = TRUE, na = "null", pretty = TRUE), mp)
lp <- file.path(d, "player_leaders.json")
empty_payload <- ple$pl_build_payload(ple$pl_empty_totals(),
  data.frame(team_id = character(0), team = character(0), games = numeric(0), stringsAsFactors = FALSE),
  character(0), list(), list(player_box = "fixture"))
ple$pl_write_payload(empty_payload, lp)
bytes_before <- readBin(lp, "raw", file.info(lp)$size)
scores <- function(dates) data.frame(game_id = "777", is_final = TRUE, home_score = 101L, away_score = 99L)

# Failure path: summary fetch fails -> scores patched, leaders file untouched.
r_fail <- suppressWarnings(refresh_live_results(dates = "2026-11-23", payload_path = mp, fetcher = scores,
                                                summary_fetcher = function(id) NULL, today = as.Date("2026-11-24")))
ok("fetch failure: final score still patched", r_fail$n_changed == 1L && !is.null(r_fail$file))
ok("fetch failure: leaders status reports it and file is byte-identical",
   grepl("^fetch_failed", r_fail$leaders$status) && is.null(r_fail$leaders$file) &&
     identical(readBin(lp, "raw", file.info(lp)$size), bytes_before))
r_err <- refresh_live_results(dates = "2026-11-23", payload_path = mp, fetcher = scores,
                              summary_fetcher = function(id) stop("boom"), today = as.Date("2026-11-24"))
ok("fetcher error is caught; leaders untouched", grepl("^error", r_err$leaders$status) &&
     identical(readBin(lp, "raw", file.info(lp)$size), bytes_before))

# Success path: both games now final; 401910036 parses from the fixture, 777 has none -> all or nothing.
r_partial <- suppressWarnings(refresh_live_results(dates = "2026-11-23", payload_path = mp, fetcher = scores,
  summary_fetcher = function(id) if (id == "401910036") fx else NULL, today = as.Date("2026-11-24")))
ok("one of two summaries missing: all or nothing, file untouched",
   grepl("^fetch_failed: 777", r_partial$leaders$status) && identical(readBin(lp, "raw", file.info(lp)$size), bytes_before))
pm <- jsonlite::fromJSON(mp); pm$matchups$is_completed[pm$matchups$game_id == "777"] <- FALSE
pm$matchups$game_id[pm$matchups$game_id == "777"] <- "778"
writeLines(jsonlite::toJSON(pm, auto_unbox = TRUE, na = "null", pretty = TRUE), mp)
r_ok <- refresh_live_results(dates = character(0), payload_path = mp, fetcher = scores,
                             summary_fetcher = function(id) fx, today = as.Date("2026-11-24"))
out <- jsonlite::fromJSON(lp, simplifyVector = FALSE)
pts <- Filter(function(c) c$key == "pts", out$cards)[[1]]
ok("success: game added, through date set, cards rebuilt",
   r_ok$leaders$status == "updated" && r_ok$leaders$n_games == 1L && out$through_date == "2026-11-23" &&
     identical(unlist(out$season_totals$game_ids), "401910036") && pts$status == "ok")
ok("success: team games played counted once per team", all(unlist(out$season_totals$team_games$games) == 1))
r_again <- refresh_live_results(dates = character(0), payload_path = mp, fetcher = scores,
                                summary_fetcher = function(id) stop("must not be called"), today = as.Date("2026-11-24"))
ok("re-run: up to date, nothing fetched", r_again$leaders$status == "up_to_date")
ok("no leaders file -> nothing to patch", refresh_live_results(dates = character(0), payload_path = mp,
   leaders_path = file.path(d, "absent.json"), today = as.Date("2026-11-24"))$leaders$status == "no_file")

# Payload text carries no betting vocabulary.
txt <- ple$pl_json_text(out)
ok("no betting terms in the payload",
   !grepl("\\b(odds|lines?|spreads?|picks?|props?|wagers?|edges?|bets?|betting|sportsbook|moneyline|parlay)\\b", txt, ignore.case = TRUE))

cat(sprintf("\n%d passed, %d failed\n", passes, failures))
if (failures > 0L) quit(status = 1L)
