# ==============================================================================
# build_player_leaders.R - NBA league leaders panel data layer (NBA_analytics#254)
#
# Writes web/public/data/player_leaders.json, read by the leaders panel at the
# top of /players. One card per stat, grouped as scoring, shooting, playmaking,
# rebounding, defense and impact; each card carries the top 10 for All, Guards,
# Forwards and Centers, its own through date and a noise-note flag.
#
# INPUTS (real caches only; a missing box-score input stops the stage):
#   cache/nba_player_box_<season>.rds     player box scores (current season)
#   cache/matchups_team_box_<season>.rds  team box scores (rate denominators and
#                                         team games played)
#   cache/rapm_ratings_leaders.rds        offensive, defensive and total RAPM and
#                                         possessions per side (impact cards), fit
#                                         here each 09:00 run on the CURRENT season's
#                                         possessions (pl_fit_leader_rapm). The
#                                         ensemble's cache/rapm_ratings.rds is not
#                                         read or written. Used only when its
#                                         `season` is the current season; otherwise
#                                         the impact cards are empty with a reason.
#                                         No fallback to a past season, and no
#                                         synthetic RAPM path.
#
# QUALIFYING (config.R, LEADERS_*): every minimum is the owner's full-season
# (82-game) bar from #253 and scales with the player's CURRENT team's games
# played: required = minimum * team_games_played / LEADERS_FULL_SEASON_GAMES.
# A traded player's sample counts every game he played this season, for any
# team, and is held to the bar of the team he played for most recently.
#
# RANKING: per-game average, percentage or rate; highest leads, except turnovers
# and turnover rate, where the lowest leads. Ties share a rank.
#
# RATE FORMULAS: Basketball Reference definitions, taken from the leader
# reliability study (tools/leader_reliability_study.R on research/leader-reliability),
# summed over the player's games: value = sum(numerator) / sum(denominator), with
# share_g = MP_g / (TmMP_g / 5) and TmMP_g the sum of the team's player minutes.
#
# EVENING REFRESH: the payload carries `season_totals` (per-player sums of every
# numerator and denominator, the team games played and the game ids included),
# so tools/refresh_live_results.R can add a night's box scores from ESPN's public
# game summary without any cache and rebuild the box-score cards with the same
# functions. This file therefore loads jsonlite and base R only.
#
# Set NBA_SKIP_STAGE_AUTORUN=1 to source this file for its definitions only.
# ==============================================================================

.LEADERS_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  ofile <- NULL
  for (fr in sys.frames()) {
    cand <- tryCatch(get("ofile", envir = fr, inherits = FALSE), error = function(e) NULL)
    if (is.character(cand) && length(cand) == 1L && nzchar(cand)) ofile <- cand
  }
  base <- if (!is.null(ofile)) dirname(ofile)
          else if (length(f) == 1L && nzchar(f) && grepl("build_player_leaders\\.R$", f)) dirname(f)
          else getwd()
  normalizePath(base, winslash = "/", mustWork = FALSE)
})

suppressPackageStartupMessages(library(jsonlite))

if (!exists("CACHE_DIR") || !exists("WEB_JSON_PLAYER_LEADERS") ||
    !exists("LEADERS_STUDY_SOURCE_COMMIT")) {
  source(file.path(.LEADERS_DIR, "config.R"), local = TRUE)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# ------------------------------------------------------------------------------
# Definitions
# ------------------------------------------------------------------------------
PL_SCHEMA_VERSION <- 1L
PL_TOP_N <- 10L
PL_POSITIONS <- c("all", "G", "F", "C")
PL_POSITION_LABELS <- c(all = "All", G = "Guards", F = "Forwards", C = "Centers")
PL_GROUPS <- list(
  list(key = "scoring",    label = "Scoring"),
  list(key = "shooting",   label = "Shooting"),
  list(key = "playmaking", label = "Playmaking"),
  list(key = "rebounding", label = "Rebounding"),
  list(key = "defense",    label = "Defense"),
  list(key = "impact",     label = "Impact"))
PL_NOT_ENOUGH <- "Not enough games yet"
PL_NOISE_TEXT <- "Mostly noise at season sample sizes: treat the order as rough."

# ESPN / hoopR abbreviation dialect -> the codes the rest of the site uses.
PL_ABBR_FIXUPS <- c(GS = "GSW", SA = "SAS", NY = "NYK", UTAH = "UTA", NO = "NOP",
                    NOLA = "NOP", WSH = "WAS", PHO = "PHX")
pl_norm_abbr <- function(x) {
  x <- toupper(trimws(as.character(x)))
  hit <- !is.na(x) & x %in% names(PL_ABBR_FIXUPS)
  x[hit] <- PL_ABBR_FIXUPS[x[hit]]
  x
}

# Box-score position -> filter group. ESPN lists many players broadly ("F", "G");
# a combined listing ("G-F") takes its first letter. Anything else has no group
# and appears under All only.
pl_position_group <- function(pos) {
  p <- toupper(trimws(as.character(pos)))
  first <- substr(p, 1L, 1L)
  out <- ifelse(p %in% c("PG", "SG"), "G",
         ifelse(p %in% c("SF", "PF"), "F", first))
  out[!(out %in% c("G", "F", "C"))] <- NA_character_
  out
}

# Per-player additive sums. The share-weighted team sums are the rate
# denominators' building blocks (study formulas, see header).
PL_SUM_FIELDS <- c("games", "min", "fgm", "fga", "fg3m", "fg3a", "ftm", "fta",
                   "oreb", "dreb", "reb", "ast", "stl", "blk", "tov", "pts",
                   "s_tm_fgm", "s_orb_chances", "s_drb_chances", "s_tm_poss_used",
                   "ctx_missing_games")
PL_ID_FIELDS <- c("player_id", "player", "team_id", "team", "position",
                  "last_game_date", "last_game_id")

# Stat catalogue. unit = what the sample counts; min = config.R constant name.
.pl_stat <- function(key, label, group, kind, unit, min, lower = FALSE, noise = FALSE,
                     num = NULL, den = NULL, rapm_col = NULL, floor_min = NULL) {
  list(key = key, label = label, group = group, kind = kind, unit = unit, min = min,
       lower_is_better = lower, noise = noise, num = num, den = den, rapm_col = rapm_col,
       floor_min = floor_min)
}
.ones <- function(t) t$games
PL_STATS <- list(
  .pl_stat("pts",  "Points per game",             "scoring",    "per_game", "games",   "LEADERS_MIN_GAMES_PTS",  num = function(t) t$pts,  den = .ones),
  .pl_stat("fg3m", "3-pointers made per game",    "scoring",    "per_game", "games",   "LEADERS_MIN_GAMES_FG3M", num = function(t) t$fg3m, den = .ones),
  # USG% = 100 * ((FGA + 0.44 * FTA + TOV) * (TmMP / 5)) / (MP * (TmFGA + 0.44 * TmFTA + TmTOV))
  .pl_stat("usg_pct", "Usage rate",               "scoring",    "rate",     "minutes", "LEADERS_MIN_MINUTES_USG_PCT",
           num = function(t) 100 * (t$fga + 0.44 * t$fta + t$tov), den = function(t) t$s_tm_poss_used),
  .pl_stat("fg_pct",  "Field goal %",             "shooting",   "shooting", "fga",     "LEADERS_MIN_FGA_FG_PCT",   num = function(t) t$fgm,  den = function(t) t$fga),
  .pl_stat("fg3_pct", "3-point %",                "shooting",   "shooting", "fg3a",    "LEADERS_MIN_FG3A_FG3_PCT", noise = TRUE,
           num = function(t) t$fg3m, den = function(t) t$fg3a),
  .pl_stat("ft_pct",  "Free throw %",             "shooting",   "shooting", "fta",     "LEADERS_MIN_FTA_FT_PCT",   num = function(t) t$ftm,  den = function(t) t$fta),
  # eFG% = (FG + 0.5 * 3P) / FGA
  .pl_stat("efg_pct", "Effective field goal %",   "shooting",   "rate",     "minutes", "LEADERS_MIN_MINUTES_EFG_PCT", noise = TRUE,
           num = function(t) t$fgm + 0.5 * t$fg3m, den = function(t) t$fga),
  # TS% = PTS / (2 * (FGA + 0.44 * FTA))
  .pl_stat("ts_pct",  "True shooting %",          "shooting",   "rate",     "minutes", "LEADERS_MIN_MINUTES_TS_PCT", noise = TRUE,
           num = function(t) t$pts, den = function(t) 2 * (t$fga + 0.44 * t$fta)),
  .pl_stat("ast",  "Assists per game",            "playmaking", "per_game", "games",   "LEADERS_MIN_GAMES_AST",  num = function(t) t$ast,  den = .ones),
  # AST% = 100 * AST / (((MP / (TmMP / 5)) * TmFG) - FG)
  .pl_stat("ast_pct", "Assist rate",              "playmaking", "rate",     "minutes", "LEADERS_MIN_MINUTES_AST_PCT",
           num = function(t) 100 * t$ast, den = function(t) t$s_tm_fgm - t$fgm),
  .pl_stat("tov",  "Turnovers per game",          "playmaking", "per_game", "games",   "LEADERS_MIN_GAMES_TOV",  lower = TRUE,
           floor_min = "LEADERS_MIN_MINUTES_TOV_PER_GAME",
           num = function(t) t$tov,  den = .ones),
  # TOV% = 100 * TOV / (FGA + 0.44 * FTA + TOV)
  .pl_stat("tov_pct", "Turnover rate",            "playmaking", "rate",     "minutes", "LEADERS_MIN_MINUTES_TOV_PCT", lower = TRUE,
           num = function(t) 100 * t$tov, den = function(t) t$fga + 0.44 * t$fta + t$tov),
  .pl_stat("reb",  "Rebounds per game",           "rebounding", "per_game", "games",   "LEADERS_MIN_GAMES_REB",  num = function(t) t$reb,  den = .ones),
  .pl_stat("oreb", "Offensive rebounds per game", "rebounding", "per_game", "games",   "LEADERS_MIN_GAMES_OREB", num = function(t) t$oreb, den = .ones),
  # ORB% = 100 * ORB * (TmMP / 5) / (MP * (TmORB + OppDRB))
  .pl_stat("orb_pct", "Offensive rebound rate",   "rebounding", "rate",     "minutes", "LEADERS_MIN_MINUTES_ORB_PCT",
           num = function(t) 100 * t$oreb, den = function(t) t$s_orb_chances),
  # DRB% = 100 * DRB * (TmMP / 5) / (MP * (TmDRB + OppORB))
  .pl_stat("drb_pct", "Defensive rebound rate",   "rebounding", "rate",     "minutes", "LEADERS_MIN_MINUTES_DRB_PCT",
           num = function(t) 100 * t$dreb, den = function(t) t$s_drb_chances),
  .pl_stat("stl",  "Steals per game",             "defense",    "per_game", "games",   "LEADERS_MIN_GAMES_STL",  num = function(t) t$stl,  den = .ones),
  .pl_stat("blk",  "Blocks per game",             "defense",    "per_game", "games",   "LEADERS_MIN_GAMES_BLK",  num = function(t) t$blk,  den = .ones),
  .pl_stat("orapm",      "Offensive RAPM", "impact", "rapm", "possessions_per_side", "LEADERS_MIN_POSS_PER_SIDE_RAPM", noise = TRUE, rapm_col = "orapm"),
  .pl_stat("drapm",      "Defensive RAPM", "impact", "rapm", "possessions_per_side", "LEADERS_MIN_POSS_PER_SIDE_RAPM", noise = TRUE, rapm_col = "drapm"),
  .pl_stat("total_rapm", "Total RAPM",     "impact", "rapm", "possessions_per_side", "LEADERS_MIN_POSS_PER_SIDE_RAPM", noise = TRUE, rapm_col = "total_rapm"))
names(PL_STATS) <- vapply(PL_STATS, `[[`, "", "key")

PL_UNIT_LABELS <- c(games = "games played", fga = "field goal attempts",
                    fg3a = "3-point attempts", fta = "free throw attempts",
                    minutes = "minutes", possessions_per_side = "possessions on each side")
PL_FORMAT <- c(per_game = "per_game", shooting = "pct", rate = "pct", rapm = "rapm")
# eFG% and TS% are fractions like the shooting %; the other rates are already 0-100.
.pl_format <- function(st) {
  if (st$kind == "rate" && !(st$key %in% c("efg_pct", "ts_pct"))) "rate" else PL_FORMAT[[st$kind]]
}

# Full-season minimum for a stat, read from config.R by name (never retyped here).
pl_minimum <- function(st) as.numeric(get(st$min))
# Optional second bar in minutes (turnovers per game only); NA when the card has none.
pl_minutes_floor <- function(st) if (is.null(st$floor_min)) NA_real_ else as.numeric(get(st$floor_min))

# required = minimum * team_games_played / 82
pl_required <- function(minimum, team_games_played, base = LEADERS_FULL_SEASON_GAMES) {
  minimum * team_games_played / base
}

# ------------------------------------------------------------------------------
# Per-player-game rows (one shape for both sources: hoopR caches and ESPN summary)
# ------------------------------------------------------------------------------
PL_GAME_COLS <- c("game_id", "game_date", "player_id", "player", "team_id", "team",
                  "position", "min", "fgm", "fga", "fg3m", "fg3a", "ftm", "fta",
                  "oreb", "dreb", "reb", "ast", "stl", "blk", "tov", "pts")
PL_TEAM_COLS <- c("game_id", "team_id", "tm_fgm", "tm_fga", "tm_fta", "tm_tov",
                  "tm_oreb", "tm_dreb")

# Join team context (team totals, opponent rebounds, team minutes) onto player rows.
pl_attach_team_context <- function(g, team) {
  team <- team[!duplicated(team[, c("game_id", "team_id")]), , drop = FALSE]
  opp <- team[, c("game_id", "team_id", "tm_oreb", "tm_dreb")]
  # The opponent is the other team in the same game.
  opp_rows <- lapply(seq_len(nrow(team)), function(i) {
    o <- team[team$game_id == team$game_id[i] & team$team_id != team$team_id[i], , drop = FALSE]
    if (nrow(o) == 1L) c(o$tm_oreb, o$tm_dreb) else c(NA_real_, NA_real_)
  })
  team$opp_oreb <- vapply(opp_rows, `[`, 0, 1L)
  team$opp_dreb <- vapply(opp_rows, `[`, 0, 2L)
  tm_min <- stats::aggregate(min ~ game_id + team_id, data = g, FUN = sum)
  names(tm_min)[3] <- "tm_min"
  g <- merge(g, tm_min, by = c("game_id", "team_id"), all.x = TRUE)
  g <- merge(g, team, by = c("game_id", "team_id"), all.x = TRUE)
  g
}

# Played rows only: not did-not-play and minutes recorded (the study's rule).
pl_game_rows_from_box <- function(pb, tb) {
  pb <- as.data.frame(pb); tb <- as.data.frame(tb)
  if ("season_type" %in% names(pb)) pb <- pb[pb$season_type %in% 2L, , drop = FALSE]
  if ("season_type" %in% names(tb)) tb <- tb[tb$season_type %in% 2L, , drop = FALSE]
  dnp <- !is.na(pb$did_not_play) & pb$did_not_play
  played <- pb[!dnp & !is.na(pb$minutes), , drop = FALSE]
  g <- data.frame(
    game_id   = as.character(played$game_id),
    game_date = as.character(as.Date(played$game_date)),
    player_id = as.character(played$athlete_id),
    player    = as.character(played$athlete_display_name),
    team_id   = as.character(played$team_id),
    team      = pl_norm_abbr(played$team_abbreviation),
    position  = as.character(played$athlete_position_abbreviation),
    min  = as.numeric(played$minutes),
    fgm  = as.numeric(played$field_goals_made),  fga  = as.numeric(played$field_goals_attempted),
    fg3m = as.numeric(played$three_point_field_goals_made),
    fg3a = as.numeric(played$three_point_field_goals_attempted),
    ftm  = as.numeric(played$free_throws_made),  fta  = as.numeric(played$free_throws_attempted),
    oreb = as.numeric(played$offensive_rebounds), dreb = as.numeric(played$defensive_rebounds),
    reb  = as.numeric(played$rebounds), ast = as.numeric(played$assists),
    stl  = as.numeric(played$steals),   blk = as.numeric(played$blocks),
    tov  = as.numeric(played$turnovers), pts = as.numeric(played$points),
    stringsAsFactors = FALSE)
  team <- data.frame(
    game_id = as.character(tb$game_id), team_id = as.character(tb$team_id),
    tm_fgm = as.numeric(tb$field_goals_made), tm_fga = as.numeric(tb$field_goals_attempted),
    tm_fta = as.numeric(tb$free_throws_attempted), tm_tov = as.numeric(tb$turnovers),
    tm_oreb = as.numeric(tb$offensive_rebounds), tm_dreb = as.numeric(tb$defensive_rebounds),
    stringsAsFactors = FALSE)
  pl_attach_team_context(g, team)
}

# Team games played, from team rows (game_id, team_id, team).
pl_team_games_from_rows <- function(rows) {
  rows <- rows[!duplicated(rows[, c("game_id", "team_id")]), , drop = FALSE]
  if (!nrow(rows)) return(data.frame(team_id = character(0), team = character(0),
                                     games = numeric(0), stringsAsFactors = FALSE))
  n <- table(rows$team_id)
  abbr <- tapply(rows$team, rows$team_id, function(x) x[length(x)])
  data.frame(team_id = names(n), team = unname(as.character(abbr[names(n)])),
             games = as.numeric(n), stringsAsFactors = FALSE)
}

# ------------------------------------------------------------------------------
# Season totals (additive, so a refresh can add games without the caches)
# ------------------------------------------------------------------------------
pl_empty_totals <- function() {
  df <- as.data.frame(setNames(replicate(length(PL_ID_FIELDS), character(0), simplify = FALSE), PL_ID_FIELDS),
                      stringsAsFactors = FALSE)
  for (f in PL_SUM_FIELDS) df[[f]] <- numeric(0)
  df
}

# Per-row contributions -> per-player sums for one batch of games.
pl_contributions <- function(g) {
  share <- g$min / (g$tm_min / 5)
  ctx <- cbind(share, g$tm_fgm, g$tm_fga, g$tm_fta, g$tm_tov, g$tm_oreb, g$tm_dreb,
               g$opp_oreb, g$opp_dreb)
  missing <- !stats::complete.cases(ctx) | is.na(g$tm_min) | g$tm_min <= 0
  share[missing] <- 0
  z <- function(x) ifelse(missing, 0, x)
  g$games <- 1
  g$s_tm_fgm       <- z(share * g$tm_fgm)
  g$s_orb_chances  <- z(share * (g$tm_oreb + g$opp_dreb))
  g$s_drb_chances  <- z(share * (g$tm_dreb + g$opp_oreb))
  g$s_tm_poss_used <- z(share * (g$tm_fga + 0.44 * g$tm_fta + g$tm_tov))
  g$ctx_missing_games <- as.numeric(missing)
  g
}

# Add a batch of player-game rows (already carrying team context) to totals.
pl_add_games <- function(totals, g) {
  if (!nrow(g)) return(totals)
  g <- pl_contributions(g)
  g <- g[order(g$game_date, g$game_id), , drop = FALSE]
  sums <- stats::aggregate(g[, PL_SUM_FIELDS], by = list(player_id = g$player_id), FUN = sum)
  latest <- g[!duplicated(g$player_id, fromLast = TRUE),
              c("player_id", "player", "team_id", "team", "position", "game_date", "game_id")]
  names(latest)[6:7] <- c("last_game_date", "last_game_id")
  add <- merge(latest, sums, by = "player_id")
  out <- totals
  for (i in seq_len(nrow(add))) {
    k <- match(add$player_id[i], out$player_id)
    if (is.na(k)) {
      out[nrow(out) + 1L, ] <- add[i, names(out)]
    } else {
      for (f in PL_SUM_FIELDS) out[[f]][k] <- out[[f]][k] + add[[f]][i]
      # Identity follows the most recent game (traded players move to the new team).
      if (is.na(out$last_game_date[k]) || add$last_game_date[i] >= out$last_game_date[k]) {
        for (f in setdiff(PL_ID_FIELDS, "player_id")) out[[f]][k] <- add[[f]][i]
      }
    }
  }
  out
}

pl_add_team_games <- function(team_games, rows) {
  new <- pl_team_games_from_rows(rows)
  for (i in seq_len(nrow(new))) {
    k <- match(new$team_id[i], team_games$team_id)
    if (is.na(k)) team_games[nrow(team_games) + 1L, ] <- new[i, names(team_games)]
    else { team_games$games[k] <- team_games$games[k] + new$games[i]; team_games$team[k] <- new$team[i] }
  }
  team_games
}

# ------------------------------------------------------------------------------
# Cards
# ------------------------------------------------------------------------------
.pl_round <- function(x, d = 4L) ifelse(is.finite(x), round(x, d), NA_real_)

# Rank qualified rows. Highest first unless lower_is_better; ties share a rank
# (on the value as published, 4 decimals) and are listed by name.
pl_rank_rows <- function(df, lower_is_better) {
  if (!nrow(df)) return(df)
  v <- round(df$value, 6)
  ord <- if (lower_is_better) order(v, df$player) else order(-v, df$player)
  df <- df[ord, , drop = FALSE]
  key <- if (lower_is_better) round(df$value, 4) else -round(df$value, 4)
  df$rank <- as.integer(rank(key, ties.method = "min"))
  df
}

.pl_leader_list <- function(df, n = PL_TOP_N) {
  df <- utils::head(df, n)
  lapply(seq_len(nrow(df)), function(i) list(
    rank = df$rank[i], player_id = df$player_id[i], player = df$player[i],
    team = df$team[i], position = if (is.na(df$position[i])) NULL else df$position[i],
    position_group = if (is.na(df$position_group[i])) NULL else df$position_group[i],
    value = .pl_round(df$value[i]), sample = .pl_round(df$sample[i], 1L),
    required = .pl_round(df$required[i], 1L), team_games_played = df$team_games_played[i]))
}

# Assemble a card from a candidate frame (player_id, player, team, position,
# value, sample, team_games_played) for stat `st`.
pl_card <- function(st, cand, through_date, through_date_null_reason = NULL,
                    unavailable_reason = NULL) {
  minimum <- pl_minimum(st)
  if (is.null(cand) || !nrow(cand)) cand <- data.frame(player_id = character(0), player = character(0),
    team = character(0), position = character(0), value = numeric(0), sample = numeric(0),
    team_games_played = numeric(0), stringsAsFactors = FALSE)
  cand$required <- pl_required(minimum, cand$team_games_played)
  cand$position_group <- pl_position_group(cand$position)
  floor_min <- pl_minutes_floor(st)
  keep <- is.finite(cand$value) & is.finite(cand$required) & cand$sample >= cand$required
  if (!is.na(floor_min)) {
    mins <- if ("minutes" %in% names(cand)) as.numeric(cand$minutes) else rep(NA_real_, nrow(cand))
    keep <- keep & !is.na(mins) & mins >= pl_required(floor_min, cand$team_games_played)
  }
  q <- cand[keep, , drop = FALSE]
  q <- pl_rank_rows(q, st$lower_is_better)
  leaders <- list(); counts <- list()
  for (p in PL_POSITIONS) {
    sub <- if (p == "all") q else q[!is.na(q$position_group) & q$position_group == p, , drop = FALSE]
    if (p != "all" && nrow(sub)) sub$rank <- as.integer(rank(
      if (st$lower_is_better) round(sub$value, 4) else -round(sub$value, 4), ties.method = "min"))
    leaders[[p]] <- .pl_leader_list(sub)
    counts[[p]] <- nrow(sub)
  }
  empty <- nrow(q) == 0L
  list(
    key = st$key, label = st$label, group = st$group, kind = st$kind, format = .pl_format(st),
    lower_is_better = st$lower_is_better, unit = st$unit, unit_label = PL_UNIT_LABELS[[st$unit]],
    minimum_full_season = minimum, minimum_constant = st$min,
    minimum_minutes_full_season = if (is.na(floor_min)) NULL else floor_min,
    minimum_minutes_constant = st$floor_min,
    through_date = through_date, through_date_null_reason = through_date_null_reason,
    noise_note = st$noise, noise_note_text = if (st$noise) PL_NOISE_TEXT else NULL,
    status = if (empty) "not_enough_games" else "ok",
    status_text = if (empty) PL_NOT_ENOUGH else NULL,
    null_reason = if (!empty) NULL else (unavailable_reason %||%
      sprintf("No player has reached the scaled minimum yet (%s %s%s over a full season, scaled by team games played).",
              format(minimum, big.mark = ","), PL_UNIT_LABELS[[st$unit]],
              if (is.na(floor_min)) "" else sprintf(" and %s minutes", format(floor_min, big.mark = ",")))),
    candidates = nrow(cand), qualified_count = counts, leaders = leaders)
}

# Box-score cards (everything except impact) from season totals.
pl_box_cards <- function(totals, team_games, through_date) {
  tg <- team_games$games[match(totals$team_id, team_games$team_id)]
  cards <- list()
  for (st in PL_STATS) {
    if (st$kind == "rapm") next
    num <- st$num(totals); den <- st$den(totals)
    value <- ifelse(den > 0, num / den, NA_real_)
    # Rates need team context for every game; a player with a game lacking it gets
    # no rate (null, never imputed) and is not ranked.
    if (st$kind == "rate" && !(st$key %in% c("efg_pct", "ts_pct"))) value[totals$ctx_missing_games > 0] <- NA_real_
    sample <- switch(st$unit, games = totals$games, fga = totals$fga, fg3a = totals$fg3a,
                     fta = totals$fta, minutes = totals$min)
    cand <- data.frame(player_id = totals$player_id, player = totals$player, team = totals$team,
                       position = totals$position, value = value, sample = sample,
                       minutes = totals$min, team_games_played = tg, stringsAsFactors = FALSE)
    cards[[st$key]] <- pl_card(st, cand, through_date)
  }
  cards
}

# Impact cards from the leader RAPM fit. Current season only.
pl_rapm_cards <- function(rapm, team_games, totals, season = CURRENT_SEASON,
                          rapm_file = sprintf("cache/%s", LEADERS_RAPM_CACHE_FILE)) {
  stats_rapm <- Filter(function(s) s$kind == "rapm", PL_STATS)
  reason <- NULL; cand_base <- NULL
  if (is.null(rapm) || !nrow(rapm)) {
    reason <- sprintf("%s is missing or empty, so no RAPM can be shown.", rapm_file)
  } else {
    rs <- unique(as.integer(rapm$season))
    if (!identical(rs, as.integer(season))) {
      lab <- unique(as.character(rapm$season_label %||% rs))
      reason <- sprintf(paste0("%s holds the %s fit, not %s. RAPM for %s has not been fit yet, ",
                               "and the panel does not fall back to a past season."),
                        rapm_file, paste(lab, collapse = ", "), season_label(season), season_label(season))
    } else {
      team <- pl_norm_abbr(rapm$team)
      tg <- team_games$games[match(team, pl_norm_abbr(team_games$team))]
      pos <- totals$position[match(rapm$player_name, totals$player)]
      sample <- pmin(as.numeric(rapm$off_possessions), as.numeric(rapm$def_possessions))
      cand_base <- data.frame(player_id = as.character(rapm$player_id), player = as.character(rapm$player_name),
                              team = team, position = pos, sample = sample, team_games_played = tg,
                              stringsAsFactors = FALSE)
    }
  }
  cards <- list()
  for (st in stats_rapm) {
    cand <- NULL
    if (!is.null(cand_base)) { cand <- cand_base; cand$value <- as.numeric(rapm[[st$rapm_col]]) }
    cards[[st$key]] <- pl_card(st, cand, through_date = NULL,
      through_date_null_reason = sprintf("%s carries no game-date coverage; RAPM updates in the 09:00 run only.", rapm_file),
      unavailable_reason = reason)
  }
  cards
}

# ------------------------------------------------------------------------------
# Payload
# ------------------------------------------------------------------------------
pl_methods <- function() {
  mins <- lapply(PL_STATS, function(st) list(
    key = st$key, label = st$label, unit = st$unit, unit_label = PL_UNIT_LABELS[[st$unit]],
    minimum_full_season = pl_minimum(st), constant = st$min,
    minimum_minutes_full_season = if (is.na(pl_minutes_floor(st))) NULL else pl_minutes_floor(st),
    minimum_minutes_constant = st$floor_min))
  list(
    scaling_rule = sprintf("required = minimum x team games played / %d", LEADERS_FULL_SEASON_GAMES),
    scaling_text = sprintf(paste0(
      "Each minimum is a full-season (%d-game) bar set by the owner after reviewing the reliability study's curves; ",
      "the study did not choose them. The bar scales with the team games played by the player's current team: ",
      "required = minimum x team games played / %d. For example, after 41 team games the free throw %% bar is 125 attempts."),
      LEADERS_FULL_SEASON_GAMES, LEADERS_FULL_SEASON_GAMES),
    traded_players = paste0(
      "A traded player's sample counts every game he played this season, for any team, and is held to the bar ",
      "of the team he played for most recently."),
    position_note = paste0(
      "Positions are the box-score listing, and some players are listed broadly (for example \"F\"). ",
      "A combined listing such as \"G-F\" counts under its first letter."),
    ranking = "Ranked by per-game average, percentage or rate. For turnovers and turnover rate the lowest figure leads. Ties share a rank.",
    noise_note = paste0(
      "The 3-point %, effective field goal %, true shooting % and RAPM cards are mostly noise at season sample sizes ",
      "(split-half reliability at the chosen minimums: 3P% about 0.26; eFG% and TS% about 0.63; total RAPM about 0.59)."),
    rate_formulas = list(
      efg_pct = "(FG + 0.5 x 3P) / FGA",
      ts_pct  = "PTS / (2 x (FGA + 0.44 x FTA))",
      tov_pct = "100 x TOV / (FGA + 0.44 x FTA + TOV)",
      orb_pct = "100 x ORB x (TmMP / 5) / (MP x (TmORB + OppDRB))",
      drb_pct = "100 x DRB x (TmMP / 5) / (MP x (TmDRB + OppORB))",
      ast_pct = "100 x AST / (((MP / (TmMP / 5)) x TmFG) - FG)",
      usg_pct = "100 x ((FGA + 0.44 x FTA + TOV) x (TmMP / 5)) / (MP x (TmFGA + 0.44 x TmFTA + TmTOV))",
      summing = "Summed over the player's games: value = sum of numerators / sum of denominators. TmMP is the sum of the team's player minutes in that game."),
    refresh = paste0(
      "Box-score and rate cards update in the 09:00 pipeline run and in the evening score refreshes. ",
      "RAPM cards update in the 09:00 run only. Each card shows its own through date."),
    sample = "Regular-season games only. A game counts when the player is not listed as did-not-play and has minutes recorded.",
    study_source_commit = LEADERS_STUDY_SOURCE_COMMIT,
    base_games = LEADERS_FULL_SEASON_GAMES,
    minimums = unname(mins),
    nulls = "Values that cannot be supported are null with a reason; nothing is imputed or synthesised.")
}

.pl_cols <- function(df) lapply(as.list(df), function(x) I(if (is.numeric(x)) round(x, 4) else x))

pl_build_payload <- function(totals, team_games, game_ids, impact_cards, sources,
                             now = Sys.time(), season = CURRENT_SEASON) {
  through <- if (nrow(totals)) max(totals$last_game_date, na.rm = TRUE) else NULL
  box <- pl_box_cards(totals, team_games, through)
  all_cards <- c(box, impact_cards)
  order_keys <- names(PL_STATS)
  cards <- unname(all_cards[order_keys[order_keys %in% names(all_cards)]])
  tg <- team_games[order(team_games$team), , drop = FALSE]
  list(
    schema_version = PL_SCHEMA_VERSION,
    generated_at = format(now, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    season = season_label(season),
    through_date = through,
    position_filters = lapply(PL_POSITIONS, function(p) list(key = p, label = PL_POSITION_LABELS[[p]])),
    groups = PL_GROUPS,
    cards = cards,
    methods = pl_methods(),
    sources = sources,
    season_totals = list(
      description = paste0("Per-player season sums behind the box-score cards (numerators, denominators and samples), ",
                           "team games played and the game ids included, so the evening refresh can add new games."),
      game_ids = I(sort(unique(as.character(game_ids)))),
      team_games = .pl_cols(tg),
      players = .pl_cols(totals[order(totals$player_id), , drop = FALSE])))
}

pl_json_text <- function(payload) {
  as.character(jsonlite::toJSON(payload, auto_unbox = TRUE, pretty = FALSE,
                                null = "null", na = "null", digits = NA))
}

pl_write_payload <- function(payload, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(pl_json_text(payload), path, useBytes = TRUE)
  invisible(path)
}

# Read season totals back out of a published payload.
pl_read_totals <- function(payload) {
  st <- payload$season_totals
  players <- as.data.frame(lapply(st$players, unlist), stringsAsFactors = FALSE)
  if (!nrow(players) || !ncol(players)) players <- pl_empty_totals()
  for (f in PL_ID_FIELDS) players[[f]] <- as.character(players[[f]])
  for (f in PL_SUM_FIELDS) players[[f]] <- as.numeric(players[[f]])
  tg <- as.data.frame(lapply(st$team_games, unlist), stringsAsFactors = FALSE)
  if (!nrow(tg) || !ncol(tg)) tg <- data.frame(team_id = character(0), team = character(0),
                                               games = numeric(0), stringsAsFactors = FALSE)
  tg$team_id <- as.character(tg$team_id); tg$team <- as.character(tg$team); tg$games <- as.numeric(tg$games)
  list(players = players[, c(PL_ID_FIELDS, PL_SUM_FIELDS)], team_games = tg[, c("team_id", "team", "games")],
       game_ids = as.character(unlist(st$game_ids)))
}

# ------------------------------------------------------------------------------
# Evening refresh: ESPN game summary -> the same player-game rows
# ------------------------------------------------------------------------------
PL_ESPN_SUMMARY <- "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/summary?event=%s"

# Returns the parsed summary, or NULL (with a warning) on any failure.
pl_espn_fetch_summary <- function(game_id) {
  tryCatch({
    con <- url(sprintf(PL_ESPN_SUMMARY, game_id), open = "rb", headers = c("User-Agent" = "Mozilla/5.0"))
    on.exit(close(con), add = TRUE)
    jsonlite::fromJSON(paste(readLines(con, warn = FALSE), collapse = ""), simplifyVector = FALSE)
  }, error = function(e) {
    warning(sprintf("ESPN summary fetch failed for %s: %s", game_id, conditionMessage(e)), call. = FALSE)
    NULL
  })
}

.pl_split_made_att <- function(x) {
  p <- strsplit(as.character(x), "-", fixed = TRUE)[[1]]
  if (length(p) != 2L) return(c(NA_real_, NA_real_))
  suppressWarnings(as.numeric(p))
}

# Player-game rows (with team context) from one ESPN game summary. Stops when the
# summary lacks the box score, so the caller can leave the leaders file unchanged.
pl_game_rows_from_espn <- function(j, game_id, game_date) {
  box <- j$boxscore
  if (is.null(box$teams) || length(box$teams) != 2L || is.null(box$players) || length(box$players) != 2L) {
    stop(sprintf("summary for %s has no two-team box score", game_id), call. = FALSE)
  }
  team_rows <- lapply(box$teams, function(t) {
    s <- setNames(lapply(t$statistics, `[[`, "displayValue"), vapply(t$statistics, `[[`, "", "name"))
    fg <- .pl_split_made_att(s[["fieldGoalsMade-fieldGoalsAttempted"]] %||% NA)
    ft <- .pl_split_made_att(s[["freeThrowsMade-freeThrowsAttempted"]] %||% NA)
    num <- function(k) suppressWarnings(as.numeric(s[[k]] %||% NA))
    data.frame(game_id = as.character(game_id), team_id = as.character(t$team$id),
               team = pl_norm_abbr(t$team$abbreviation),
               tm_fgm = fg[1], tm_fga = fg[2], tm_fta = ft[2], tm_tov = num("turnovers"),
               tm_oreb = num("offensiveRebounds"), tm_dreb = num("defensiveRebounds"),
               stringsAsFactors = FALSE)
  })
  team <- do.call(rbind, team_rows)
  rows <- list()
  for (side in box$players) {
    tid <- as.character(side$team$id)
    st <- side$statistics[[1]]
    keys <- unlist(st$keys)
    for (a in st$athletes) {
      if (isTRUE(a$didNotPlay)) next
      v <- setNames(as.list(unlist(lapply(a$stats, function(x) x %||% NA))), keys)
      if (!length(a$stats) || is.null(v$minutes) || is.na(suppressWarnings(as.numeric(v$minutes)))) next
      fg <- .pl_split_made_att(v[["fieldGoalsMade-fieldGoalsAttempted"]])
      f3 <- .pl_split_made_att(v[["threePointFieldGoalsMade-threePointFieldGoalsAttempted"]])
      ft <- .pl_split_made_att(v[["freeThrowsMade-freeThrowsAttempted"]])
      n <- function(k) suppressWarnings(as.numeric(v[[k]] %||% NA))
      rows[[length(rows) + 1L]] <- data.frame(
        game_id = as.character(game_id), game_date = as.character(game_date),
        player_id = as.character(a$athlete$id), player = as.character(a$athlete$displayName),
        team_id = tid, team = team$team[match(tid, team$team_id)],
        position = as.character(a$athlete$position$abbreviation %||% NA),
        min = n("minutes"), fgm = fg[1], fga = fg[2], fg3m = f3[1], fg3a = f3[2],
        ftm = ft[1], fta = ft[2], oreb = n("offensiveRebounds"), dreb = n("defensiveRebounds"),
        reb = n("rebounds"), ast = n("assists"), stl = n("steals"), blk = n("blocks"),
        tov = n("turnovers"), pts = n("points"), stringsAsFactors = FALSE)
    }
  }
  if (!length(rows)) stop(sprintf("summary for %s lists no players who played", game_id), call. = FALSE)
  g <- do.call(rbind, rows)
  if (anyNA(g[, c("fgm", "fga", "fg3m", "fg3a", "ftm", "fta", "pts")])) {
    stop(sprintf("summary for %s has unparsable player box-score fields", game_id), call. = FALSE)
  }
  list(players = pl_attach_team_context(g, team[, PL_TEAM_COLS]),
       teams = team[, c("game_id", "team_id", "team")])
}

PL_REFRESH_MAX_GAMES <- 30L

#' Add newly finished games' box scores to player_leaders.json.
#'
#' All or nothing: if any game's summary cannot be fetched or parsed, the file is
#' left exactly as it was (and the caller's score patching is unaffected).
#' @param matchups Matchup rows (game_id, game_date, is_completed).
#' @param fetch_summary function(game_id) -> parsed ESPN summary or NULL.
#' @return list(status, n_games, file)
pl_refresh_leaders <- function(path, matchups, fetch_summary = pl_espn_fetch_summary,
                               max_games = PL_REFRESH_MAX_GAMES, now = Sys.time()) {
  if (!file.exists(path)) return(list(status = "no_file", n_games = 0L, file = NULL))
  payload <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  tot <- pl_read_totals(payload)
  done <- !is.na(matchups$is_completed) & matchups$is_completed
  ids <- as.character(matchups$game_id[done])
  dates <- substr(as.character(matchups$game_date[done]), 1, 10)
  new <- !(ids %in% tot$game_ids)
  if (!any(new)) return(list(status = "up_to_date", n_games = 0L, file = NULL))
  if (sum(new) > max_games) {
    return(list(status = sprintf("skipped: %d games missing, more than %d; left for the 09:00 run", sum(new), max_games),
                n_games = 0L, file = NULL))
  }
  batches <- list(); teams <- list()
  for (k in which(new)) {
    j <- fetch_summary(ids[k])
    if (is.null(j)) return(list(status = sprintf("fetch_failed: %s", ids[k]), n_games = 0L, file = NULL))
    r <- tryCatch(pl_game_rows_from_espn(j, ids[k], dates[k]), error = function(e) e)
    if (inherits(r, "error")) return(list(status = sprintf("parse_failed: %s", conditionMessage(r)), n_games = 0L, file = NULL))
    batches[[length(batches) + 1L]] <- r$players
    teams[[length(teams) + 1L]] <- r$teams
  }
  g <- do.call(rbind, batches)
  players <- pl_add_games(tot$players, g)
  team_games <- pl_add_team_games(tot$team_games, do.call(rbind, teams))
  impact <- Filter(function(cd) identical(cd$group, "impact"), payload$cards)
  names(impact) <- vapply(impact, `[[`, "", "key")
  sources <- payload$sources
  sources$evening_refresh <- sprintf("%d game(s) added from ESPN's public game summary by tools/refresh_live_results.R", length(batches))
  out <- pl_build_payload(players, team_games, c(tot$game_ids, ids[new]), impact, sources, now = now)
  pl_write_payload(out, path)
  list(status = "updated", n_games = length(batches), file = path)
}

# ------------------------------------------------------------------------------
# Current-season RAPM for the impact cards
# ------------------------------------------------------------------------------
# Fits RAPM on the CURRENT season's possessions with rapm_engine.R's own model and
# writes it to cache/<LEADERS_RAPM_CACHE_FILE>. The ensemble's cache/rapm_ratings.rds
# is never touched. The possession table is re-downloaded every run, because the
# in-progress season grows daily; if that download fails, the last downloaded copy
# of THIS season's possessions is used (real data, one day older). Returns NULL,
# with a message, when there is no current-season data at all.
pl_fit_leader_rapm <- function(season = CURRENT_SEASON,
                               out_path = file.path(CACHE_DIR, LEADERS_RAPM_CACHE_FILE),
                               engine = "rapm_engine.R") {
  old <- Sys.getenv("NBA_SKIP_STAGE_AUTORUN", unset = NA)
  Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")
  on.exit(if (is.na(old)) Sys.unsetenv("NBA_SKIP_STAGE_AUTORUN") else
    Sys.setenv(NBA_SKIP_STAGE_AUTORUN = old), add = TRUE)
  tryCatch({
    eng <- new.env(parent = globalenv())
    source(engine, local = eng)
    cache <- eng$load_or_build_possession_cache(season, force_refresh = TRUE)
    if (is.null(cache)) cache <- eng$load_or_build_possession_cache(season, force_refresh = FALSE)
    if (is.null(cache) || is.null(cache$possessions) || !nrow(cache$possessions)) {
      message(sprintf(">>> [LEADERS] No %s possessions published yet; RAPM cards stay empty.", season_label(season)))
      return(NULL)
    }
    eng$estimate_rapm_from_possessions(cache, out_path = out_path)
  }, error = function(e) {
    message(">>> [LEADERS] Current-season RAPM fit failed: ", conditionMessage(e))
    NULL
  })
}

# ------------------------------------------------------------------------------
# Stage entry point (09:00 pipeline)
# ------------------------------------------------------------------------------
build_player_leaders <- function(season = CURRENT_SEASON,
                                 player_box_path = file.path(CACHE_DIR, sprintf("nba_player_box_%d.rds", season)),
                                 team_box_path = CACHE_MATCHUPS_TEAM_BOX(season),
                                 rapm_path = file.path(CACHE_DIR, LEADERS_RAPM_CACHE_FILE),
                                 output_json = WEB_JSON_PLAYER_LEADERS,
                                 fit_rapm = TRUE,
                                 now = Sys.time()) {
  for (p in c(player_box_path, team_box_path)) {
    if (!file.exists(p)) stop(sprintf("build_player_leaders: missing current-season input %s", p), call. = FALSE)
  }
  pb <- readRDS(player_box_path); tb <- readRDS(team_box_path)
  g <- pl_game_rows_from_box(pb, tb)
  totals <- pl_add_games(pl_empty_totals(), g)
  tb2 <- as.data.frame(tb)
  if ("season_type" %in% names(tb2)) tb2 <- tb2[tb2$season_type %in% 2L, , drop = FALSE]
  team_games <- pl_team_games_from_rows(data.frame(
    game_id = as.character(tb2$game_id), team_id = as.character(tb2$team_id),
    team = pl_norm_abbr(tb2$team_abbreviation), stringsAsFactors = FALSE))
  if (fit_rapm) pl_fit_leader_rapm(season, out_path = rapm_path)
  rapm <- if (file.exists(rapm_path)) as.data.frame(readRDS(rapm_path)) else NULL
  impact <- pl_rapm_cards(rapm, team_games, totals, season,
                          rapm_file = sprintf("cache/%s", basename(rapm_path)))
  sources <- list(
    player_box = sprintf("cache/nba_player_box_%d.rds (hoopR, regular season)", season),
    team_box = sprintf("cache/matchups_team_box_%d.rds (hoopR, regular season)", season),
    rapm = sprintf("cache/%s (%s)", basename(rapm_path), if (is.null(rapm)) "missing" else
      paste(unique(as.character(rapm$data_source)), collapse = "; ")))
  payload <- pl_build_payload(totals, team_games, unique(g$game_id), impact, sources, now = now, season = season)
  pl_write_payload(payload, output_json)
  ok <- vapply(payload$cards, function(cd) cd$status == "ok", logical(1))
  cat(sprintf(">>> [LEADERS] Wrote %s (through %s): %d of %d cards have qualifiers; empty: %s\n",
              output_json, payload$through_date %||% "n/a", sum(ok), length(ok),
              paste(vapply(payload$cards[!ok], `[[`, "", "key"), collapse = ", ")))
  invisible(payload)
}

if (!nzchar(Sys.getenv("NBA_SKIP_STAGE_AUTORUN"))) {
  build_player_leaders()
}
