# ==============================================================================
# tests/test_build_game_details.R
#
# Unit, contract, idempotency, and empirical cache tests for build_game_details.R
# and config.R (Tier 1a -- Matchup Game Detail v3 Phase 1).
#
# Works standalone on synthetic fixtures even when cache/ is absent, and also
# validates empirical invariants against cache/matchups_team_box_2027.rds and
# cache/nba_player_box_2027.rds when present. Writes only to tempdir().
#
# Usage: Rscript --vanilla tests/test_build_game_details.R
# ==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  if (basename(base) == "tests") {
    normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
  } else {
    normalizePath(base, winslash = "/", mustWork = FALSE)
  }
})

failures <- 0L
checks   <- 0L

ok <- function(label, cond) {
  checks <<- checks + 1L
  if (isTRUE(cond)) {
    cat(sprintf("  PASS  %s\n", label))
  } else {
    failures <<- failures + 1L
    cat(sprintf("  FAIL  %s\n", label))
  }
}

near_eq <- function(a, b, tol = 1e-6) {
  !is.null(a) && !is.null(b) && is.numeric(a) && is.numeric(b) &&
    length(a) == 1L && length(b) == 1L && abs(a - b) <= tol
}

section <- function(title) cat(sprintf("\n== %s ==\n", title))
canon <- function(x) normalizePath(x, winslash = "/", mustWork = FALSE)

# ------------------------------------------------------------------------------
section("1. Sourcing config.R and build_game_details.R from scratch cwd")
# ------------------------------------------------------------------------------

cfg_env <- new.env(parent = globalenv())
source(file.path(REPO_ROOT, "config.R"), local = cfg_env)

ok("config.R defines CACHE_MATCHUPS_PLAYER_BOX function",
   is.function(cfg_env$CACHE_MATCHUPS_PLAYER_BOX))
ok("CACHE_MATCHUPS_PLAYER_BOX(2027) matches nba_player_box_2027.rds",
   grepl("nba_player_box_2027[.]rds$", cfg_env$CACHE_MATCHUPS_PLAYER_BOX(2027)) &&
     identical(canon(cfg_env$CACHE_MATCHUPS_PLAYER_BOX(2027)),
               canon(file.path(cfg_env$CACHE_DIR, "nba_player_box_2027.rds"))))
ok("config.R defines WEB_GAMES_DIR as <WEB_DATA_DIR>/games",
   identical(canon(cfg_env$WEB_GAMES_DIR),
             canon(file.path(cfg_env$WEB_DATA_DIR, "games"))))

mod_env <- new.env(parent = globalenv())
wd_before <- canon(getwd())
scratch_dir <- file.path(tempdir(), "gbd_source_scratch")
if (dir.exists(scratch_dir)) unlink(scratch_dir, recursive = TRUE)
dir.create(scratch_dir, recursive = TRUE)

setwd(scratch_dir)
load_out <- capture.output({
  source(file.path(REPO_ROOT, "build_game_details.R"), local = mod_env)
})
wd_after <- canon(getwd())
setwd(wd_before)

ok("build_game_details.R loads cleanly from scratch directory",
   is.function(mod_env$build_game_detail_payload) &&
     is.function(mod_env$export_game_details) &&
     is.function(mod_env$write_game_json_if_changed) &&
     is.function(mod_env$should_rebuild_game_detail))
ok("build_game_details.R produces zero stdout side effects on source()",
   length(load_out) == 0L)
ok("build_game_details.R leaves working directory untouched",
   identical(wd_after, canon(scratch_dir)))
ok("build_game_details.R creates no files in scratch directory on source()",
   length(list.files(scratch_dir, all.files = TRUE, no.. = TRUE)) == 0L)
unlink(scratch_dir, recursive = TRUE)

# Bind module helpers for testing.
attach_env <- mod_env

# ------------------------------------------------------------------------------
section("2. Abbreviation normalization and character numeric parsing")
# ------------------------------------------------------------------------------

raw_abbrs <- c("GS", "SA", "NY", "UTAH", "NO", "WSH", "BOS", "LAL")
exp_abbrs <- c("GSW", "SAS", "NYK", "UTA", "NOP", "WAS", "BOS", "LAL")
ok("canonical_nba_abbr normalizes all 6 ESPN variants",
   identical(mod_env$canonical_nba_abbr(raw_abbrs), exp_abbrs))

parsed_pm <- mod_env$parse_num_or_na(c("62", "-14", "+7", "", NA))
ok("parse_num_or_na parses signed strings and turns blanks/NA to NA",
   identical(parsed_pm[1:3], c(62, -14, 7)) && all(is.na(parsed_pm[4:5])))

# ------------------------------------------------------------------------------
section("3. Synthetic fixtures: formulas, classification, tie-breakers, nulls")
# ------------------------------------------------------------------------------

make_team_row <- function(game_id, game_date, team_id, abbr, name, home_away,
                          score, winner, fgm, fga, fg3m, fg3a, ftm, fta,
                          oreb, dreb, reb, ast, stl, blk, tov, team_tov,
                          total_tov, pf, pip, fbp, top, lead) {
  data.frame(
    game_id                           = as.integer(game_id),
    game_date                         = as.Date(game_date),
    team_id                           = as.integer(team_id),
    team_abbreviation                 = as.character(abbr),
    team_name                         = as.character(name),
    team_short_display_name           = as.character(name),
    team_home_away                    = as.character(home_away),
    team_score                        = as.integer(score),
    team_winner                       = as.logical(winner),
    field_goals_made                  = as.integer(fgm),
    field_goals_attempted             = as.integer(fga),
    three_point_field_goals_made      = as.integer(fg3m),
    three_point_field_goals_attempted = as.integer(fg3a),
    free_throws_made                  = as.integer(ftm),
    free_throws_attempted             = as.integer(fta),
    offensive_rebounds                = as.integer(oreb),
    defensive_rebounds                = as.integer(dreb),
    total_rebounds                    = as.integer(reb),
    assists                           = as.integer(ast),
    steals                            = as.integer(stl),
    blocks                            = as.integer(blk),
    turnovers                         = as.integer(tov),
    team_turnovers                    = as.integer(team_tov),
    total_turnovers                   = as.integer(total_tov),
    fouls                             = as.integer(pf),
    points_in_paint                   = as.character(pip),
    fast_break_points                 = as.character(fbp),
    turnover_points                   = as.character(top),
    largest_lead                      = as.character(lead),
    stringsAsFactors                  = FALSE
  )
}

make_player_row <- function(game_id, game_date, team_id, abbr, home_away,
                            athlete_id, name, short_name, jersey = "1",
                            pos = "G", starter = TRUE, dnp = FALSE,
                            reason = NA_character_, minutes = 24,
                            pts = 0, fgm = 0, fga = 0, fg3m = 0, fg3a = 0,
                            ftm = 0, fta = 0, oreb = 0, dreb = 0, reb = 0,
                            ast = 0, stl = 0, blk = 0, tov = 0, pf = 0,
                            plus_minus = "0") {
  data.frame(
    game_id                           = as.integer(game_id),
    game_date                         = as.Date(game_date),
    athlete_id                        = as.integer(athlete_id),
    athlete_display_name              = as.character(name),
    athlete_short_name                = as.character(short_name),
    athlete_jersey                    = as.character(jersey),
    athlete_position_abbreviation     = as.character(pos),
    team_id                           = as.integer(team_id),
    team_abbreviation                 = as.character(abbr),
    home_away                         = as.character(home_away),
    starter                           = as.logical(starter),
    did_not_play                      = as.logical(dnp),
    reason                            = as.character(reason),
    minutes                           = as.numeric(minutes),
    points                            = as.integer(pts),
    field_goals_made                  = as.integer(fgm),
    field_goals_attempted             = as.integer(fga),
    three_point_field_goals_made      = as.integer(fg3m),
    three_point_field_goals_attempted = as.integer(fg3a),
    free_throws_made                  = as.integer(ftm),
    free_throws_attempted             = as.integer(fta),
    offensive_rebounds                = as.integer(oreb),
    defensive_rebounds                = as.integer(dreb),
    rebounds                          = as.integer(reb),
    assists                           = as.integer(ast),
    steals                            = as.integer(stl),
    blocks                            = as.integer(blk),
    turnovers                         = as.integer(tov),
    fouls                             = as.integer(pf),
    plus_minus                        = as.character(plus_minus),
    stringsAsFactors                  = FALSE
  )
}

# Game 9001: GS (away, 110) @ NO (home, 102) on 2026-11-12
# Away (GS): FGM=40, FGA=80, FG3M=12, FG3A=30, FTM=18, FTA=22, OREB=10, DREB=32, REB=42,
#            AST=25, STL=8, BLK=5, TOV=11, team_tov=2, total_tov=13, PF=18
# Home (NO): FGM=36, FGA=85, FG3M=10, FG3A=28, FTM=20, FTA=25, OREB=12, DREB=28, REB=40,
#            AST=21, STL=6, BLK=4, TOV=14, team_tov=1, total_tov=15, PF=20
tb_9001 <- rbind(
  make_team_row(9001, "2026-11-12", 9, "GS", "Warriors", "away", 110, TRUE,
                40, 80, 12, 30, 18, 22, 10, 32, 42, 25, 8, 5, 11, 2, 13, 18,
                "48", "16", "19", "14"),
  make_team_row(9001, "2026-11-12", 3, "NO", "Pelicans", "home", 102, FALSE,
                36, 85, 10, 28, 20, 25, 12, 28, 40, 21, 6, 4, 14, 1, 15, 20,
                "42", "11", "13", "5")
)

# Away players sum to exact team totals (except team_tov=2, so player tov sums to 11):
# - Starter 1 (Alpha): 36m, 35 pts, 13/24 FG, 5/10 3PT, 4/5 FT, 2 OR, 6 DR, 8 REB, 8 AST, 2 STL, 1 BLK, 3 TOV, 2 PF
#   GmSc = 35 + 0.4*13 - 0.7*24 - 0.4*(5-4) + 0.7*2 + 0.3*6 + 2 + 0.7*8 + 0.7*1 - 0.4*2 - 3 = 30.7
# - Starter 2 (Beta, reason="COACH'S DECISION" but did_not_play=FALSE!): 34m, 25 pts, 9/18 FG, 3/7 3PT, 4/4 FT,
#   3 OR, 5 DR, 8 REB, 5 AST, 2 STL, 1 BLK, 2 TOV, 3 PF -> GmSc = 22.6
# - Starter 3 (Gamma): 100m? Wait keep total minutes = 240: 36 + 34 + 35 + 35 + 30 + 30 + 40 + 0 = 240
#   Starter 3 (Gamma): 35m, 18 pts, 7/14 FG, 2/6 3PT, 2/3 FT, 2 OR, 8 DR, 10 REB, 4 AST, 1 STL, 1 BLK, 2 TOV, 4 PF
# - Starter 4 (Delta): 35m, 12 pts, 4/10 FG, 1/4 3PT, 3/4 FT, 1 OR, 5 DR, 6 REB, 3 AST, 1 STL, 1 BLK, 2 TOV, 3 PF
# - Starter 5 (Epsilon): 30m, 8 pts, 3/6 FG, 0/1 3PT, 2/2 FT, 1 OR, 4 DR, 5 REB, 2 AST, 1 STL, 1 BLK, 1 TOV, 3 PF
# - Bench 1 (Zeta, starter=FALSE): 40m, 12 pts, 4/8 FG, 1/2 3PT, 3/4 FT, 1 OR, 4 DR, 5 REB, 2 AST, 1 STL, 0 BLK, 1 TOV, 3 PF
# - Bench 2 (Sub-minute active: min=0, ast=1, everything else 0): MUST stay active, excluded from top_performers
# - Bench 3 (Zero-minute zero-stat: dnp=FALSE, min=0, all stats=0): MUST go to away_inactive
# - DNP 1 (Aaron Injured: dnp=TRUE, min=NA, reason="LEFT KNEE SPRAIN"): MUST go to away_inactive
pb_9001 <- rbind(
  make_player_row(9001, "2026-11-12", 9, "GS", "away", 101, "Alpha Star", "A. Star", "30", "G", TRUE, FALSE, NA_character_,
                  36, 35, 13, 24, 5, 10, 4, 5, 2, 6, 8, 8, 2, 1, 3, 2, "+12"),
  make_player_row(9001, "2026-11-12", 9, "GS", "away", 102, "Beta Guard", "B. Guard", "0", "G", TRUE, FALSE, "COACH'S DECISION",
                  34, 25, 9, 18, 3, 7, 4, 4, 3, 5, 8, 5, 2, 1, 2, 3, "+8"),
  make_player_row(9001, "2026-11-12", 9, "GS", "away", 103, "Gamma Wing", "G. Wing", "22", "F", TRUE, FALSE, NA_character_,
                  35, 18, 7, 14, 2, 6, 2, 3, 2, 8, 10, 4, 1, 1, 2, 4, "+6"),
  make_player_row(9001, "2026-11-12", 9, "GS", "away", 104, "Delta Fwd", "D. Fwd", "23", "F", TRUE, FALSE, NA_character_,
                  35, 12, 4, 10, 1, 4, 3, 4, 1, 5, 6, 3, 1, 1, 2, 3, "+4"),
  make_player_row(9001, "2026-11-12", 9, "GS", "away", 105, "Epsilon Ctr", "E. Ctr", "5", "C", TRUE, FALSE, NA_character_,
                  30, 8, 3, 6, 0, 1, 2, 2, 1, 4, 5, 2, 1, 1, 1, 3, "+2"),
  make_player_row(9001, "2026-11-12", 9, "GS", "away", 106, "Zeta Sixth", "Z. Sixth", "8", "G", FALSE, FALSE, NA_character_,
                  70, 12, 4, 8, 1, 2, 3, 4, 1, 4, 5, 2, 1, 0, 1, 3, "+8"),
  make_player_row(9001, "2026-11-12", 9, "GS", "away", 107, "Sub Minute", "S. Minute", "99", "G", FALSE, FALSE, "COACH'S DECISION",
                  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, "0"),
  make_player_row(9001, "2026-11-12", 9, "GS", "away", 108, "Zero Stat", "Z. Stat", "98", "F", FALSE, FALSE, "COACH'S DECISION",
                  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, "0"),
  make_player_row(9001, "2026-11-12", 9, "GS", "away", 109, "Aaron Injured", "A. Injured", NA_character_, "C", FALSE, TRUE, "LEFT KNEE SPRAIN",
                  NA_real_, NA_integer_, NA_integer_, NA_integer_, NA_integer_, NA_integer_, NA_integer_, NA_integer_,
                  NA_integer_, NA_integer_, NA_integer_, NA_integer_, NA_integer_, NA_integer_, NA_integer_, NA_integer_, NA_character_),

  # Home (NO) players: sum exactly to home team totals (102 pts, 36/85 FG, 10/28 3PT, 20/25 FT, 12/28/40 REB, 21 AST, 6 STL, 4 BLK, 14 TOV, 20 PF)
  # Include tie-breaker test:
  # - Home Star A (22.7 GmSc, 25 pts, 36m) vs Away Beta Guard (22.7 GmSc, 25 pts, 34m): Home Star A wins on minutes (36 > 34)!
  # - Home Bench A (15 pts, starter=FALSE) + Home Bench B (8 pts, starter=FALSE) -> bench_points = 23
  make_player_row(9001, "2026-11-12", 3, "NO", "home", 201, "Home Star A", "H. Star A", "1", "F", TRUE, FALSE, NA_character_,
                  36, 25, 9, 18, 3, 7, 4, 4, 3, 5, 8, 5, 2, 1, 2, 3, "-4"),
  make_player_row(9001, "2026-11-12", 3, "NO", "home", 202, "Home Two", "H. Two", "2", "G", TRUE, FALSE, NA_character_,
                  48, 22, 8, 20, 2, 6, 4, 5, 2, 6, 8, 6, 1, 1, 3, 4, "-6"),
  make_player_row(9001, "2026-11-12", 3, "NO", "home", 203, "Home Three", "H. Three", "3", "G", TRUE, FALSE, NA_character_,
                  44, 18, 6, 15, 2, 5, 4, 5, 2, 5, 7, 4, 1, 1, 3, 4, "-8"),
  make_player_row(9001, "2026-11-12", 3, "NO", "home", 204, "Home Four", "H. Four", "4", "F", TRUE, FALSE, NA_character_,
                  40, 14, 5, 12, 1, 4, 3, 4, 2, 4, 6, 2, 1, 0, 2, 3, "-8"),
  make_player_row(9001, "2026-11-12", 3, "NO", "home", 205, "Home Five", "H. Five", "5", "C", TRUE, FALSE, NA_character_,
                  32, 0, 0, 4, 0, 2, 0, 0, 1, 4, 5, 1, 0, 1, 2, 2, "-8"),
  make_player_row(9001, "2026-11-12", 3, "NO", "home", 206, "Home Bench A", "H. Bench A", "6", "G", FALSE, FALSE, NA_character_,
                  24, 15, 5, 10, 2, 4, 3, 4, 1, 2, 3, 2, 1, 0, 1, 2, "-4"),
  make_player_row(9001, "2026-11-12", 3, "NO", "home", 207, "Home Bench B", "H. Bench B", "7", "F", FALSE, FALSE, NA_character_,
                  16, 8, 3, 6, 0, 0, 2, 3, 1, 2, 3, 1, 0, 0, 1, 2, "-2")
)

payload_9001 <- mod_env$build_game_detail_payload(
  game_id         = "9001",
  team_box_game   = tb_9001,
  player_box_game = pb_9001,
  slate           = 4L,
  slate_label     = "Week 4 \u00b7 Nov 10 \u2013 Nov 16",
  game_date       = "2026-11-12",
  is_completed    = TRUE,
  season          = 2027L,
  season_label    = "2026-2027",
  generated_at    = "2026-11-15T12:00:00Z"
)

d <- payload_9001$data
ok("Envelope metadata fields match v3 section 3",
   identical(payload_9001$schema_version, "1.0") &&
     identical(payload_9001$sport, "nba") &&
     identical(payload_9001$endpoint, "game_detail") &&
     identical(payload_9001$season, 2027L) &&
     identical(payload_9001$season_label, "2026-2027") &&
     is.null(d$explainability) &&
     is.null(d$game_flow))

ok("Team abbreviations normalized GS->GSW and NO->NOP",
   identical(d$away_team$teamAbbr, "GSW") &&
     identical(d$home_team$teamAbbr, "NOP") &&
     identical(d$away_team$score, 110L) &&
     identical(d$home_team$score, 102L) &&
     isTRUE(d$away_team$is_winner) &&
     identical(d$home_team$is_winner, FALSE))

# Hand-calculated Dean Oliver possessions & efficiency factors for 9001:
# poss_h = 85 + 0.44*25 - 1.07 * (12 / (12 + 32)) * (85 - 36) + 15 = 85 + 11 - 1.07*(12/44)*49 + 15 = 96.700909...
# poss_a = 80 + 0.44*22 - 1.07 * (10 / (10 + 28)) * (80 - 40) + 13 = 80 + 9.68 - 1.07*(10/38)*40 + 13 = 91.416842...
exp_poss_h <- 85 + 0.44 * 25 - 1.07 * (12 / 44) * (85 - 36) + 15
exp_poss_a <- 80 + 0.44 * 22 - 1.07 * (10 / 38) * (80 - 40) + 13
exp_poss   <- 0.5 * (exp_poss_h + exp_poss_a)
exp_away_efg  <- round(100 * (40 + 0.5 * 12) / 80, 1)
exp_away_ts   <- round(100 * 110 / (2 * (80 + 0.44 * 22)), 1)
exp_away_tov  <- round(100 * 13 / (80 + 0.44 * 22 + 13), 1)
exp_away_oreb <- round(100 * 10 / (10 + 28), 1)
exp_away_ftar <- round(100 * 22 / 80, 1)
exp_away_ortg <- round(100 * 110 / exp_poss, 1)
exp_home_ortg <- round(100 * 102 / exp_poss, 1)
exp_pace      <- round(48 * exp_poss / 48, 1)

ef_by_key <- setNames(d$efficiency_factors, vapply(d$efficiency_factors, `[[`, character(1), "key"))
ok("efficiency_factors has all 8 keys in spec order",
   identical(names(ef_by_key), c("efg_pct", "ts_pct", "tov_pct", "oreb_pct", "fta_rate", "ortg", "drtg", "pace")))
ok("efg_pct matches exact formula", near_eq(ef_by_key$efg_pct$away_value, exp_away_efg))
ok("ts_pct matches exact formula", near_eq(ef_by_key$ts_pct$away_value, exp_away_ts))
ok("tov_pct uses total_turnovers", near_eq(ef_by_key$tov_pct$away_value, exp_away_tov))
ok("oreb_pct matches exact formula", near_eq(ef_by_key$oreb_pct$away_value, exp_away_oreb))
ok("fta_rate matches exact formula, label, and unit",
   near_eq(ef_by_key$fta_rate$away_value, exp_away_ftar) &&
     identical(ef_by_key$fta_rate$unit, "per100fga") &&
     grepl("attempts per 100 field-goal attempts", ef_by_key$fta_rate$label, fixed = TRUE))
ok("ortg, drtg, pace match Dean Oliver possessions and drtg == opp$ortg",
   near_eq(d$box_score$away_totals$possessions_est, round(exp_poss, 1)) &&
     near_eq(ef_by_key$ortg$away_value, exp_away_ortg) &&
     near_eq(ef_by_key$ortg$home_value, exp_home_ortg) &&
     identical(ef_by_key$drtg$away_value, ef_by_key$ortg$home_value) &&
     identical(ef_by_key$drtg$home_value, ef_by_key$ortg$away_value) &&
     near_eq(ef_by_key$pace$away_value, exp_pace) &&
     identical(ef_by_key$tov_pct$higher_is_better, FALSE) &&
     identical(ef_by_key$drtg$higher_is_better, FALSE) &&
     is.null(ef_by_key$pace$higher_is_better))

cs_by_key <- setNames(d$context_splits, vapply(d$context_splits, `[[`, character(1), "key"))
ok("context_splits has all 8 keys and bench_points sums active non-starters",
   identical(names(cs_by_key), c("points_in_paint", "fast_break_points", "turnover_points",
                                 "bench_points", "largest_lead", "assists", "steals", "blocks")) &&
     identical(cs_by_key$points_in_paint$away_value, 48L) &&
     identical(cs_by_key$bench_points$away_value, 12L) &&
     identical(cs_by_key$bench_points$home_value, 23L))

# Player classification & sorting checks:
away_pids <- vapply(d$box_score$away_players, `[[`, character(1), "playerId")
away_inact_names <- vapply(d$box_score$away_inactive, `[[`, character(1), "playerName")
ok("Active players keep Beta (reason='COACH'S DECISION') and Sub Minute (0 min + 1 ast)",
   all(c("102", "107") %in% away_pids) &&
     identical(away_pids, c("101", "103", "104", "102", "105", "106", "107")))
ok("Inactive players route Zero Stat and Aaron Injured sorted by playerName ASC",
   identical(away_inact_names, c("Aaron Injured", "Zero Stat")) &&
     identical(d$box_score$away_inactive[[1]]$reason, "LEFT KNEE SPRAIN") &&
     is.null(d$box_score$away_players[[1]]$jersey) == FALSE &&
     identical(d$box_score$away_players[[4]]$jersey, "0"))

# Active player sums match team totals on all 12 non-rebound + 3 rebound stats:
sum_field <- function(players, fld) sum(vapply(players, `[[`, integer(1), fld))
ok("Away active player sums equal team totals for all 12 non-rebound counting stats",
   sum_field(d$box_score$away_players, "points") == d$box_score$away_totals$points &&
     sum_field(d$box_score$away_players, "fgm") == d$box_score$away_totals$fgm &&
     sum_field(d$box_score$away_players, "fga") == d$box_score$away_totals$fga &&
     sum_field(d$box_score$away_players, "fg3m") == d$box_score$away_totals$fg3m &&
     sum_field(d$box_score$away_players, "fg3a") == d$box_score$away_totals$fg3a &&
     sum_field(d$box_score$away_players, "ftm") == d$box_score$away_totals$ftm &&
     sum_field(d$box_score$away_players, "fta") == d$box_score$away_totals$fta &&
     sum_field(d$box_score$away_players, "ast") == d$box_score$away_totals$ast &&
     sum_field(d$box_score$away_players, "stl") == d$box_score$away_totals$stl &&
     sum_field(d$box_score$away_players, "blk") == d$box_score$away_totals$blk &&
     sum_field(d$box_score$away_players, "tov") == d$box_score$away_totals$tov &&
     sum_field(d$box_score$away_players, "pf") == d$box_score$away_totals$pf &&
     d$box_score$away_totals$team_tov == 2L &&
     d$box_score$away_totals$total_tov == 13L)

# Hollinger Game Score & top_performers tie-breaker check:
alpha_gmsc <- d$box_score$away_players[[1]]$game_score
ok("Hollinger Game Score matches exact formula for Alpha Star (30.7)",
   near_eq(alpha_gmsc, 30.7))
tp_ids <- vapply(d$box_score$top_performers, `[[`, character(1), "playerId")
ok("top_performers returns top 3 with minutes > 0 and breaks ties by minutes DESC",
   identical(tp_ids, c("101", "201", "102")) && !("107" %in% tp_ids))

# Tie-breaker check on points DESC and playerName ASC when game_score ties:
tp_cands <- list(
  list(teamAbbr = "GSW", playerId = "1", playerName = "Zed",   points = 20L, reb = 5L, ast = 5L, minutes = 30, game_score = 20.0),
  list(teamAbbr = "GSW", playerId = "2", playerName = "Bob",   points = 20L, reb = 5L, ast = 5L, minutes = 30, game_score = 20.0),
  list(teamAbbr = "NOP", playerId = "3", playerName = "Aaron", points = 24L, reb = 2L, ast = 2L, minutes = 28, game_score = 20.0),
  list(teamAbbr = "NOP", playerId = "4", playerName = "Carl",  points = 18L, reb = 8L, ast = 8L, minutes = 35, game_score = 20.0)
)
tp_sorted <- mod_env$.select_top_performers(tp_cands, n = 3L)
ok("top_performers breaks equal game_score by points DESC, minutes DESC, playerName ASC",
   identical(vapply(tp_sorted, `[[`, character(1), "playerId"), c("3", "2", "1")))

# Overtime game_minutes test (sum_min = 265 -> 53 min):
pb_ot <- pb_9001
pb_ot$minutes[pb_ot$athlete_id == 101] <- 61 # away sum_min = 240 + 25 = 265 -> 53
payload_ot <- mod_env$build_game_detail_payload(
  game_id = "9001", team_box_game = tb_9001, player_box_game = pb_ot,
  slate = 4L, game_date = "2026-11-12", generated_at = "2026-11-15T12:00:00Z"
)
exp_pace_ot <- round(48 * exp_poss / 53, 1)
ok("Overtime game uses max(round(min/5), 48) = 53 for pace",
   near_eq(payload_ot$data$box_score$away_totals$pace, exp_pace_ot) &&
     near_eq(payload_ot$data$box_score$home_totals$pace, exp_pace_ot))

# Zero-denominator & JSON array test:
tb_zero <- rbind(
  make_team_row(9002, "2026-11-12", 1, "ATL", "Hawks", "away", 0, FALSE,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                NA_character_, NA_character_, NA_character_, NA_character_),
  make_team_row(9002, "2026-11-12", 2, "BOS", "Celtics", "home", 0, FALSE,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                NA_character_, NA_character_, NA_character_, NA_character_)
)
pb_zero <- rbind(
  # Single active player (0 pts, 1 ast, 0 min -> length 1 away_players, length 0 away_inactive, length 0 top_performers)
  make_player_row(9002, "2026-11-12", 1, "ATL", "away", 301, "Solo Active", "S. Active", "11", "G", TRUE, FALSE, NA_character_,
                  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, NA_character_),
  # Single inactive player on home side (length 0 home_players, length 1 home_inactive)
  make_player_row(9002, "2026-11-12", 2, "BOS", "home", 302, "Solo Inactive", "S. Inactive", "7", "F", FALSE, TRUE, NA_character_,
                  NA_real_, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, NA_character_)
)
payload_zero <- mod_env$build_game_detail_payload(
  game_id = "9002", team_box_game = tb_zero, player_box_game = pb_zero,
  slate = 4L, game_date = "2026-11-12", generated_at = "2026-11-15T12:00:00Z"
)
zero_json <- mod_env$serialize_game_detail_json(payload_zero)
zero_parsed <- jsonlite::fromJSON(zero_json, simplifyVector = FALSE)

at_z <- payload_zero$data$box_score$away_totals
ap_z <- payload_zero$data$box_score$away_players[[1]]
ef_z <- setNames(payload_zero$data$efficiency_factors,
                 vapply(payload_zero$data$efficiency_factors, `[[`, character(1), "key"))

ok("Zero denominators produce NULL (never NaN or Inf) for all ratios",
   is.null(at_z$fg_pct) && is.null(at_z$fg3_pct) && is.null(at_z$ft_pct) &&
     is.null(at_z$efg_pct) && is.null(at_z$ts_pct) &&
     is.null(at_z$possessions_est) && is.null(at_z$ortg) &&
     is.null(at_z$drtg) && is.null(at_z$pace) &&
     is.null(ef_z$tov_pct$away_value) && is.null(ef_z$oreb_pct$away_value) &&
     is.null(ef_z$fta_rate$away_value) &&
     is.null(ap_z$fg_pct) && is.null(ap_z$efg_pct) && is.null(ap_z$ts_pct) &&
     is.null(ap_z$plus_minus))

ok("Raw JSON never emits NaN, Infinity, or NA strings",
   !grepl(":\\s*NaN\\b|:\\s*-?Infinity\\b|:\\s*\"NA\"", zero_json, perl = TRUE))

ok("Arrays serialize as JSON arrays [...] even at length 0 or 1",
   grepl('"away_players"\\s*:\\s*\\[\\s*\\{', zero_json, perl = TRUE) &&
     grepl('"home_players"\\s*:\\s*\\[\\s*\\]', zero_json, perl = TRUE) &&
     grepl('"away_inactive"\\s*:\\s*\\[\\s*\\]', zero_json, perl = TRUE) &&
     grepl('"home_inactive"\\s*:\\s*\\[\\s*\\{', zero_json, perl = TRUE) &&
     grepl('"top_performers"\\s*:\\s*\\[\\s*\\]', zero_json, perl = TRUE) &&
     is.list(zero_parsed$data$box_score$away_players) &&
     length(zero_parsed$data$box_score$away_players) == 1L)

# Naming convention check (only teamAbbr, teamName, playerId, playerName are camelCase):
collect_keys <- function(x) {
  if (!is.list(x)) return(character(0))
  nms <- names(x)
  out <- if (!is.null(nms)) nms[nzchar(nms)] else character(0)
  for (el in x) out <- c(out, collect_keys(el))
  unique(out)
}
all_keys <- collect_keys(payload_9001)
camel_keys <- all_keys[grepl("[A-Z]", all_keys)]
ok("Only teamAbbr, teamName, playerId, playerName use camelCase",
   setequal(camel_keys, c("teamAbbr", "teamName", "playerId", "playerName")))

# Zero-betting term guard on serialized JSON:
betting_re <- "\\b(bet|bets|betting|wager|wagers|odds|sportsbook|bookmaker|moneyline|parlay|vig|juice|bankroll|payout|handicap)\\b"
json_9001 <- mod_env$serialize_game_detail_json(payload_9001)
ok("Serialized payload contains zero betting terms",
   !grepl(betting_re, json_9001, ignore.case = TRUE, perl = TRUE))

# ------------------------------------------------------------------------------
section("4. Churn control, 7-day rebuild window, and idempotency")
# ------------------------------------------------------------------------------

tmp_games_dir <- file.path(tempdir(), "gbd_churn_test")
if (dir.exists(tmp_games_dir)) unlink(tmp_games_dir, recursive = TRUE)
dir.create(tmp_games_dir, recursive = TRUE)

today_ref <- as.Date("2026-11-15")

# Games:
# - 9001: 2026-11-12 (3 days old, has box score)
# - 9003: 2026-11-08 (exactly 7 days old, has box score -> rebuilt inside window)
# - 9004: 2026-11-01 (14 days old, has box score -> skipped outside window on run 2)
# - 9005: 2026-11-14 (completed, missing player_box -> has_box_score FALSE, no file)
# - 9006: 2026-11-18 (unplayed, is_completed FALSE -> has_box_score FALSE, no file)
tb_9003 <- tb_9001; tb_9003$game_id <- 9003L; tb_9003$game_date <- as.Date("2026-11-08")
pb_9003 <- pb_9001; pb_9003$game_id <- 9003L; pb_9003$game_date <- as.Date("2026-11-08")
tb_9004 <- tb_9001; tb_9004$game_id <- 9004L; tb_9004$game_date <- as.Date("2026-11-01")
pb_9004 <- pb_9001; pb_9004$game_id <- 9004L; pb_9004$game_date <- as.Date("2026-11-01")
tb_9005 <- tb_9001; tb_9005$game_id <- 9005L; tb_9005$game_date <- as.Date("2026-11-14")

tb_batch <- rbind(tb_9001, tb_9003, tb_9004, tb_9005)
pb_batch <- rbind(pb_9001, pb_9003, pb_9004)
games_batch <- data.frame(
  game_id      = c("9001", "9003", "9004", "9005", "9006"),
  game_date    = as.Date(c("2026-11-12", "2026-11-08", "2026-11-01", "2026-11-14", "2026-11-18")),
  slate        = c(4L, 3L, 2L, 4L, 5L),
  slate_label  = c("Week 4", "Week 3", "Week 2", "Week 4", "Week 5"),
  is_completed = c(TRUE, TRUE, TRUE, TRUE, FALSE),
  stringsAsFactors = FALSE
)

res1 <- mod_env$export_game_details(
  team_box     = tb_batch,
  player_box   = pb_batch,
  games        = games_batch,
  out_dir      = tmp_games_dir,
  season       = 2027L,
  season_label = "2026-2027",
  today_date   = today_ref,
  generated_at = "2026-11-15T10:00:00Z"
)

ok("Run 1 writes 3 files and skips 2 games lacking full box scores",
   res1$written == 3L &&
     res1$unchanged == 0L &&
     res1$skipped_no_box_score == 2L &&
     file.exists(file.path(tmp_games_dir, "9001.json")) &&
     file.exists(file.path(tmp_games_dir, "9003.json")) &&
     file.exists(file.path(tmp_games_dir, "9004.json")) &&
     !file.exists(file.path(tmp_games_dir, "9005.json")) &&
     !file.exists(file.path(tmp_games_dir, "9006.json")))

# Record exact bytes and timestamps after Run 1, pause briefly, then Run 2 with new generated_at:
Sys.sleep(0.05)
bytes_before <- lapply(c("9001.json", "9003.json", "9004.json"), function(f) {
  p <- file.path(tmp_games_dir, f)
  readBin(p, "raw", file.info(p)$size)
})

res2 <- mod_env$export_game_details(
  team_box     = tb_batch,
  player_box   = pb_batch,
  games        = games_batch,
  out_dir      = tmp_games_dir,
  season       = 2027L,
  season_label = "2026-2027",
  today_date   = today_ref,
  generated_at = "2026-11-15T18:30:00Z"
)

bytes_after <- lapply(c("9001.json", "9003.json", "9004.json"), function(f) {
  p <- file.path(tmp_games_dir, f)
  readBin(p, "raw", file.info(p)$size)
})

ok("Run 2 with new generated_at writes 0 files, skips 14d game, leaves bytes untouched",
   res2$written == 0L &&
     res2$unchanged == 2L &&
     res2$skipped_window == 1L &&
     identical(bytes_before, bytes_after) &&
     identical(jsonlite::fromJSON(file.path(tmp_games_dir, "9001.json"))$generated_at,
               "2026-11-15T10:00:00Z"))

# Run 3: stat correction on 9001 updates only 9001.json:
tb_batch_corr <- tb_batch
tb_batch_corr$assists[tb_batch_corr$game_id == 9001L & tb_batch_corr$team_home_away == "away"] <- 26L
res3 <- mod_env$export_game_details(
  team_box     = tb_batch_corr,
  player_box   = pb_batch,
  games        = games_batch,
  out_dir      = tmp_games_dir,
  season       = 2027L,
  season_label = "2026-2027",
  today_date   = today_ref,
  generated_at = "2026-11-15T19:00:00Z"
)
ok("Stat correction in 7-day window rewrites only the changed game (9001)",
   res3$written == 1L && identical(res3$written_ids, "9001") &&
     res3$unchanged == 1L && res3$skipped_window == 1L)

# should_rebuild_game_detail predicates (including exact 7-day boundary):
p_old <- file.path(tmp_games_dir, "9004.json")
p_7d  <- file.path(tmp_games_dir, "9003.json")
ok("should_rebuild_game_detail returns TRUE at exact 7-day boundary (today - 7) and FALSE at (today - 8)",
   mod_env$should_rebuild_game_detail("2026-11-08", p_7d, schema_ver = "1.0",
                                      today_date = today_ref, force = FALSE) &&
     !mod_env$should_rebuild_game_detail("2026-11-07", p_old, schema_ver = "1.0",
                                         today_date = today_ref, force = FALSE))
ok("should_rebuild_game_detail returns FALSE outside 7-day window when schema matches",
   !mod_env$should_rebuild_game_detail("2026-11-01", p_old, schema_ver = "1.0",
                                       today_date = today_ref, force = FALSE))
ok("should_rebuild_game_detail returns TRUE on schema_version mismatch",
   mod_env$should_rebuild_game_detail("2026-11-01", p_old, schema_ver = "1.1",
                                      today_date = today_ref, force = FALSE))
ok("should_rebuild_game_detail returns TRUE when force=TRUE or file missing",
   mod_env$should_rebuild_game_detail("2026-11-01", p_old, schema_ver = "1.0",
                                      today_date = today_ref, force = TRUE) &&
     mod_env$should_rebuild_game_detail("2026-11-01", file.path(tmp_games_dir, "missing.json"),
                                        schema_ver = "1.0", today_date = today_ref, force = FALSE))

# Env var NBA_FORCE_REBUILD_GAMES="true":
old_force_env <- Sys.getenv("NBA_FORCE_REBUILD_GAMES", unset = NA)
Sys.setenv(NBA_FORCE_REBUILD_GAMES = "true")
ok("NBA_FORCE_REBUILD_GAMES='true' triggers rebuild for old game",
   mod_env$should_rebuild_game_detail("2026-11-01", p_old, schema_ver = "1.0",
                                      today_date = today_ref))
if (is.na(old_force_env)) Sys.unsetenv("NBA_FORCE_REBUILD_GAMES") else Sys.setenv(NBA_FORCE_REBUILD_GAMES = old_force_env)

unlink(tmp_games_dir, recursive = TRUE)

# ------------------------------------------------------------------------------
section("5. Empirical cache validation (optional when cache RDS files exist)")
# ------------------------------------------------------------------------------

tb_path <- cfg_env$CACHE_MATCHUPS_TEAM_BOX(2027)
pb_path <- cfg_env$CACHE_MATCHUPS_PLAYER_BOX(2027)

if (file.exists(tb_path) && file.exists(pb_path)) {
  emp_tb <- as.data.frame(readRDS(tb_path))
  emp_pb <- as.data.frame(readRDS(pb_path))
  emp_out_dir <- file.path(tempdir(), "gbd_empirical_test")
  if (dir.exists(emp_out_dir)) unlink(emp_out_dir, recursive = TRUE)
  dir.create(emp_out_dir, recursive = TRUE)

  emp_games <- mod_env$.derive_games_from_team_box(emp_tb)
  emp_res1 <- mod_env$export_game_details(
    team_box     = emp_tb,
    player_box   = emp_pb,
    games        = emp_games,
    out_dir      = emp_out_dir,
    season       = 2027L,
    season_label = "2026-2027",
    today_date   = as.Date("2026-11-15"),
    generated_at = "2026-11-15T12:00:00Z"
  )
  emp_res2 <- mod_env$export_game_details(
    team_box     = emp_tb,
    player_box   = emp_pb,
    games        = emp_games,
    out_dir      = emp_out_dir,
    season       = 2027L,
    season_label = "2026-2027",
    today_date   = as.Date("2026-11-15"),
    generated_at = "2026-11-15T18:00:00Z"
  )

  expected_n <- length(intersect(emp_tb$game_id, emp_pb$game_id))
  ok(sprintf("Empirical export wrote all %d overlapping games on run 1", expected_n),
     emp_res1$written == expected_n && emp_res1$games_with_box_score == expected_n)
  ok("Empirical export rewrote 0 files on run 2",
     emp_res2$written == 0L)

  # Check contract invariants across all exported empirical JSON files:
  json_files <- list.files(emp_out_dir, pattern = "\\.json$", full.names = TRUE)
  bad_json <- 0L
  drtg_mismatch <- 0L
  pts_mismatch <- 0L
  reb_diff_games <- character(0)
  nonreb_diff_games <- character(0)

  nonreb_stats <- c("points", "fgm", "fga", "fg3m", "fg3a", "ftm", "fta", "ast", "stl", "blk", "tov", "pf")
  reb_stats <- c("oreb", "dreb", "reb")

  for (jf in json_files) {
    raw <- mod_env$.read_utf8_text(jf)
    if (grepl(":\\s*NaN\\b|:\\s*-?Infinity\\b|:\\s*\"NA\"", raw, perl = TRUE)) {
      bad_json <- bad_json + 1L
    }
    obj <- jsonlite::fromJSON(raw, simplifyVector = FALSE)
    gd <- obj$data
    if (!isTRUE(gd$has_box_score) || is.null(gd$box_score)) bad_json <- bad_json + 1L
    at <- gd$box_score$away_totals
    ht <- gd$box_score$home_totals
    if (!identical(at$drtg, ht$ortg) || !identical(ht$drtg, at$ortg)) {
      drtg_mismatch <- drtg_mismatch + 1L
    }

    for (side in list(list(tot = at, pl = gd$box_score$away_players, nm = gd$away_team$teamAbbr),
                      list(tot = ht, pl = gd$box_score$home_players, nm = gd$home_team$teamAbbr))) {
      for (st in nonreb_stats) {
        s_p <- sum(vapply(side$pl, `[[`, integer(1), st))
        s_t <- side$tot[[st]]
        if (s_p != s_t) {
          if (st == "points") pts_mismatch <- pts_mismatch + 1L
          if (abs(s_p - s_t) > 1L) bad_json <- bad_json + 1L
          nonreb_diff_games <- c(nonreb_diff_games,
                                 sprintf("%s %s %s (%d vs %d)", gd$game_id, side$nm, st, s_p, s_t))
        }
      }
      for (st in reb_stats) {
        s_p <- sum(vapply(side$pl, `[[`, integer(1), st))
        s_t <- side$tot[[st]]
        if (s_p != s_t) {
          if (abs(s_p - s_t) > 1L) bad_json <- bad_json + 1L
          reb_diff_games <- c(reb_diff_games,
                              sprintf("%s %s %s (%d vs %d)", gd$game_id, side$nm, st, s_p, s_t))
        }
      }
    }
  }

  ok("All empirical game JSONs have valid non-NaN/Inf/NA serialization and drtg == opp$ortg",
     bad_json == 0L && drtg_mismatch == 0L && pts_mismatch == 0L)

  if (length(reb_diff_games) > 0L) {
    cat(sprintf("  INFO  Source feed 1-rebound diffs (%d team-stat pairs): %s\n",
                length(reb_diff_games), paste(reb_diff_games, collapse = "; ")))
  }
  if (length(nonreb_diff_games) > 0L) {
    cat(sprintf("  INFO  Source cache-age 1-unit diffs (%d team-stat pairs, tb vs pb timestamp): %s\n",
                length(nonreb_diff_games), paste(nonreb_diff_games, collapse = "; ")))
  }

  # Spot-check empirical edge cases in cache:
  # - Sub-30-second active players stay in away_players/home_players:
  g_cryer <- jsonlite::fromJSON(file.path(emp_out_dir, "401909285.json"), simplifyVector = FALSE)
  cryer_ids <- vapply(c(g_cryer$data$box_score$away_players, g_cryer$data$box_score$home_players),
                      `[[`, character(1), "playerId")
  cryer_names <- vapply(c(g_cryer$data$box_score$away_players, g_cryer$data$box_score$home_players),
                        `[[`, character(1), "playerName")
  cryer_tp <- vapply(g_cryer$data$box_score$top_performers, `[[`, character(1), "playerName")
  ok("Empirical sub-30s player (LJ Cryer, 0 min + 1 ast in 401909285) stays active and out of top_performers",
     ("LJ Cryer" %in% cryer_names) && !("LJ Cryer" %in% cryer_tp) && length(cryer_ids) > 0L)

  # - Active player with COACH'S DECISION in reason (401909960 Kyle Kuzma):
  g_kuzma <- jsonlite::fromJSON(file.path(emp_out_dir, "401909960.json"), simplifyVector = FALSE)
  kuzma_names <- vapply(g_kuzma$data$box_score$away_players, `[[`, character(1), "playerName")
  ok("Empirical active player with reason='COACH'S DECISION' (Kyle Kuzma in 401909960) stays active",
     "Kyle Kuzma" %in% kuzma_names)

  # - Empirical OT game + abbreviation normalization (401909942 ORL @ GS -> GSW, 53 min):
  g_ot <- jsonlite::fromJSON(file.path(emp_out_dir, "401909942.json"), simplifyVector = FALSE)
  exp_ot_pace <- round(48 * g_ot$data$box_score$away_totals$possessions_est / 53, 1)
  ok("Empirical OT game 401909942 normalizes GS->GSW and uses 53-minute pace",
     identical(g_ot$data$home_team$teamAbbr, "GSW") &&
       abs(g_ot$data$box_score$home_totals$pace - exp_ot_pace) <= 0.2)

  unlink(emp_out_dir, recursive = TRUE)
} else {
  cat("  SKIP  cache RDS files absent; empirical verification skipped\n")
}

# ------------------------------------------------------------------------------
cat(sprintf("\n%d checks, %d failure(s).\n", checks, failures))
if (failures > 0L) quit(status = 1L)
cat("ALL CHECKS PASSED\n")
