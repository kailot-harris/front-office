# ==============================================================================
# build_player_leaders.R - NFL league leaders panel data layer (NFL_analytics#230)
#
# Writes web/public/data/player_leaders.json, read by the leaders panel at the
# top of /players. One card per stat, grouped by position group (Passing,
# Rushing, Receiving, Defense, Impact); each card carries its top 10, its own
# through date and a noise-note flag. There is no position filter (#230).
#
# INPUTS (current season, regular season only; nothing from a past season):
#   play-by-play       CACHE_DNA_PBP (nflreadr::load_pbp, refreshed by Stage 14.1)
#   player stats       CACHE_DNA_PLAYER_STATS (nflreadr::load_player_stats, week level)
#   snap counts        CACHE_SNAP_COUNTS (nflreadr::load_snap_counts; games played)
#   players table      CACHE_LEADERS_PLAYERS (nflreadr::load_players; pfr -> gsis link)
#   PFR advanced stats nflreadr::load_pfr_advstats(stat_type = "rush" / "def"), fetched
#                      every run. If the current season cannot be fetched, the yards
#                      after contact and pressures cards are null with the reason;
#                      they are never filled from another source.
#
# STAT DEFINITIONS: taken from the leader reliability study
# (tools/leader_reliability_study.R on research/leader-reliability, study commit
# LEADERS_STUDY_SOURCE_COMMIT). Dropbacks, designed carries, targets and games
# played are counted exactly as there (see ldr_play_tables / ldr_games_played).
#
# QUALIFYING (config.R, LEADERS_*): the owner's full-season (17-game) bars from
# the #230 comment, scaled by the games played by the player's CURRENT team:
#   required = minimum * team_games_played / LEADERS_FULL_SEASON_GAMES
# A traded player's sample counts every game he played this season, for any team,
# and is held to the bar of the team he played for most recently. Season totals
# have no minimum.
#
# RANKING: highest leads, except sack rate and interception rate (lowest leads).
# Ties (on the value rounded to 4 decimals) share a rank and are listed by name.
#
# EVENING REFRESH: tools/refresh_live_results.R calls ldr_refresh_leaders(), which
# fetches the same nflverse files by URL with base R and rebuilds every card except
# the impact card (total EPA, model-based: 09:00 pipeline only). This file loads
# jsonlite and base R only; nflreadr is used only by ldr_load_inputs_pipeline().
#
# Usage:
#   Rscript build_player_leaders.R              # build and write
#   source("build_player_leaders.R")            # definitions only, no writes
#   run_stage("build_player_leaders.R", ..., call_fn = "run_build_player_leaders")
# ==============================================================================

suppressPackageStartupMessages(library(jsonlite))
if (!exists("WEB_JSON_PLAYER_LEADERS") || !exists("LEADERS_STUDY_SOURCE_COMMIT")) source("config.R")

`%||%` <- function(a, b) if (is.null(a)) b else a

# ------------------------------------------------------------------------------
# Definitions
# ------------------------------------------------------------------------------
LDR_SCHEMA_VERSION <- 1L
LDR_TOP_N <- 10L
LDR_GROUPS <- list(
  list(key = "passing",   label = "Passing"),
  list(key = "rushing",   label = "Rushing"),
  list(key = "receiving", label = "Receiving"),
  list(key = "defense",   label = "Defense"),
  list(key = "impact",    label = "Impact"))
LDR_NOT_ENOUGH <- "Not enough games yet"
LDR_UNAVAILABLE <- "Data not available"
LDR_NOISE_TEXT <- "Mostly noise at season sample sizes: treat the order as rough."
LDR_UNIT_LABELS <- c(season_total = "season total", games = "games played", dropbacks = "dropbacks",
                     designed_carries = "designed carries", targets = "targets")
# Study link-rate rule: snap-count rows (snaps > 0) linked to a gsis id must reach this
# share, or the games-played cards are not built (null with the reason).
LDR_MIN_LINK_RATE <- 0.9

.ldr_stat <- function(key, label, group, kind, unit, format, min = NULL, lower = FALSE,
                      noise = FALSE, source, refresh = "pipeline_and_evening", formula) {
  list(key = key, label = label, group = group, kind = kind, unit = unit, format = format,
       min = min, lower_is_better = lower, noise = noise, source = source, refresh = refresh,
       formula = formula)
}
LDR_SRC_PBP <- "nflreadr::load_pbp()"
LDR_SRC_PS  <- "nflreadr::load_player_stats(summary_level = \"week\")"
LDR_SRC_PG  <- "nflreadr::load_player_stats(summary_level = \"week\") + load_snap_counts()"
LDR_STATS <- list(
  # ---- passing
  .ldr_stat("pass_ypg", "Passing yards per game", "passing", "per_game", "games", "per_game",
            min = "LEADERS_MIN_GAMES_YARDS_PER_GAME", source = LDR_SRC_PG,
            formula = "sum(passing yards) / games played"),
  .ldr_stat("pass_td", "Passing touchdowns", "passing", "total", "season_total", "count",
            source = LDR_SRC_PS, formula = "sum(passing TDs)"),
  .ldr_stat("pass_epa", "EPA per dropback", "passing", "rate", "dropbacks", "epa_play",
            min = "LEADERS_MIN_DROPBACKS_PASSING_RATES", source = LDR_SRC_PBP,
            formula = "sum(qb_epa) / dropbacks"),
  .ldr_stat("pass_cpoe", "Completion % over expected", "passing", "rate", "dropbacks", "cpoe",
            min = "LEADERS_MIN_DROPBACKS_PASSING_RATES", noise = TRUE, source = LDR_SRC_PBP,
            formula = "mean(cpoe) over dropbacks that are pass attempts with a cpoe value (percentage points)"),
  .ldr_stat("pass_succ", "Dropback success rate", "passing", "rate", "dropbacks", "pct",
            min = "LEADERS_MIN_DROPBACKS_PASSING_RATES", source = LDR_SRC_PBP,
            formula = "sum(success) / dropbacks (success = EPA > 0)"),
  .ldr_stat("sack_rate", "Sack rate", "passing", "rate", "dropbacks", "pct",
            min = "LEADERS_MIN_DROPBACKS_PASSING_RATES", lower = TRUE, source = LDR_SRC_PBP,
            formula = "sacks / dropbacks"),
  .ldr_stat("int_rate", "Interception rate", "passing", "rate", "dropbacks", "pct",
            min = "LEADERS_MIN_DROPBACKS_PASSING_RATES", lower = TRUE, noise = TRUE, source = LDR_SRC_PBP,
            formula = "interceptions / pass attempts (sacks and scrambles excluded)"),
  # ---- rushing
  .ldr_stat("rush_ypg", "Rushing yards per game", "rushing", "per_game", "games", "per_game",
            min = "LEADERS_MIN_GAMES_YARDS_PER_GAME", source = LDR_SRC_PG,
            formula = "sum(rushing yards) / games played"),
  .ldr_stat("rush_epa", "EPA per carry", "rushing", "rate", "designed_carries", "epa_play",
            min = "LEADERS_MIN_DESIGNED_CARRIES_RUSHING_RATES", noise = TRUE, source = LDR_SRC_PBP,
            formula = "sum(epa) / designed carries"),
  .ldr_stat("rush_succ", "Rushing success rate", "rushing", "rate", "designed_carries", "pct",
            min = "LEADERS_MIN_DESIGNED_CARRIES_RUSHING_RATES", noise = TRUE, source = LDR_SRC_PBP,
            formula = "sum(success) / designed carries"),
  .ldr_stat("rush_yac", "Yards after contact per carry", "rushing", "rate", "designed_carries", "yards_play",
            min = "LEADERS_MIN_DESIGNED_CARRIES_RUSHING_RATES",
            source = "nflreadr::load_pfr_advstats(stat_type = \"rush\") + load_pbp()",
            formula = "sum(PFR rushing_yards_after_contact) / sum(PFR carries); qualifying sample = designed carries (play-by-play) in the games PFR covers"),
  # ---- receiving
  .ldr_stat("rec_ypg", "Receiving yards per game", "receiving", "per_game", "games", "per_game",
            min = "LEADERS_MIN_GAMES_YARDS_PER_GAME", source = LDR_SRC_PG,
            formula = "sum(receiving yards) / games played"),
  .ldr_stat("receptions", "Receptions", "receiving", "total", "season_total", "count",
            source = LDR_SRC_PS, formula = "sum(receptions)"),
  .ldr_stat("rec_epa", "EPA per target", "receiving", "rate", "targets", "epa_play",
            min = "LEADERS_MIN_TARGETS_RECEIVING_RATES", noise = TRUE, source = LDR_SRC_PBP,
            formula = "sum(epa) / targets"),
  .ldr_stat("catch_rate", "Catch rate", "receiving", "rate", "targets", "pct",
            min = "LEADERS_MIN_TARGETS_RECEIVING_RATES", source = LDR_SRC_PBP,
            formula = "receptions / targets"),
  # ---- defense
  .ldr_stat("sacks", "Sacks", "defense", "total", "season_total", "count",
            source = LDR_SRC_PS, formula = "sum(def_sacks)"),
  .ldr_stat("def_int", "Interceptions", "defense", "total", "season_total", "count",
            source = LDR_SRC_PS, formula = "sum(def_interceptions)"),
  .ldr_stat("tfl", "Tackles for loss", "defense", "total", "season_total", "count",
            source = LDR_SRC_PS, formula = "sum(def_tackles_for_loss)"),
  .ldr_stat("pressures", "Pressures", "defense", "total", "season_total", "count",
            source = "nflreadr::load_pfr_advstats(stat_type = \"def\")", formula = "sum(PFR def_pressures)"),
  # ---- impact (no new model; total EPA, clearly labelled)
  .ldr_stat("total_epa", "Total EPA (passing + rushing + receiving)", "impact", "total", "season_total",
            "epa_total", source = LDR_SRC_PBP, refresh = "pipeline_only",
            formula = "sum(qb_epa on his dropbacks as passer) + sum(epa on his designed carries) + sum(epa on his targets)"))
names(LDR_STATS) <- vapply(LDR_STATS, `[[`, "", "key")

# Full-season minimum for a stat, read from config.R by name (never retyped here).
ldr_minimum <- function(st) if (is.null(st$min)) NA_real_ else as.numeric(get(st$min))

# required = minimum * team_games_played / 17
ldr_required <- function(minimum, team_games_played, base = LEADERS_FULL_SEASON_GAMES) {
  minimum * team_games_played / base
}

nz <- function(x) !is.na(x) & x == 1

# ------------------------------------------------------------------------------
# Inputs -> tables (study definitions)
# ------------------------------------------------------------------------------
# Regular-season rows of the current season only.
.ldr_reg <- function(d, season, type_col) {
  d <- as.data.frame(d, stringsAsFactors = FALSE)
  if (!nrow(d)) return(d)
  keep <- rep(TRUE, nrow(d))
  if ("season" %in% names(d)) keep <- keep & as.integer(d$season) == as.integer(season)
  if (type_col %in% names(d)) keep <- keep & d[[type_col]] == "REG"
  d[keep, , drop = FALSE]
}

# One row per game in the play-by-play: the universe of played games.
ldr_game_table <- function(pbp) {
  g <- pbp[!duplicated(pbp$game_id), c("game_id", "game_date", "home_team", "away_team")]
  g$game_date <- as.character(as.Date(g$game_date))
  g[order(g$game_date, g$game_id), , drop = FALSE]
}

# Team games played over a set of game ids: named numeric, team -> games.
ldr_team_games <- function(games, game_ids) {
  g <- games[games$game_id %in% game_ids, , drop = FALSE]
  tab <- table(c(g$home_team, g$away_team))
  stats::setNames(as.numeric(tab), names(tab))
}

ldr_through <- function(games, game_ids) {
  d <- games$game_date[games$game_id %in% game_ids]
  if (!length(d)) NULL else max(d)
}

# Plays: dropbacks, designed carries and targets, exactly as the study counts them.
ldr_play_tables <- function(pbp) {
  pbp$game_date <- as.character(as.Date(pbp$game_date))
  db <- pbp[nz(pbp$qb_dropback) & pbp$play_type %in% c("pass", "run") & !nz(pbp$two_point_attempt) &
              !is.na(pbp$passer_id), , drop = FALSE]
  db$player_id <- db$passer_id
  db$att <- as.numeric(nz(db$pass_attempt) & !nz(db$sack))
  ru <- pbp[pbp$play_type %in% "run" & nz(pbp$rush_attempt) & !nz(pbp$qb_scramble) & !nz(pbp$qb_kneel) &
              !nz(pbp$two_point_attempt) & !is.na(pbp$rusher_player_id), , drop = FALSE]
  ru$player_id <- ru$rusher_player_id
  re <- pbp[pbp$play_type %in% "pass" & nz(pbp$pass_attempt) & !nz(pbp$sack) & !nz(pbp$two_point_attempt) &
              !is.na(pbp$receiver_player_id), , drop = FALSE]
  re$player_id <- re$receiver_player_id
  list(db = db, ru = ru, re = re)
}

# Per-player sums of `cols` (NA stays NA: a sample with a missing value has no value,
# as in the study) plus the team of the player's most recent row.
ldr_agg <- function(d, cols, order_cols = c("game_date", "play_id"), team_col = "posteam") {
  if (!nrow(d)) return(NULL)
  d <- d[do.call(order, lapply(order_cols, function(cn) d[[cn]])), , drop = FALSE]
  out <- data.frame(player_id = unique(d$player_id), stringsAsFactors = FALSE)
  idx <- match(d$player_id, out$player_id)
  for (cn in cols) out[[cn]] <- as.numeric(tapply(as.numeric(d[[cn]]), idx, sum))
  out$n <- as.numeric(tabulate(idx, nrow(out)))
  last <- !duplicated(d$player_id, fromLast = TRUE)
  out$team <- as.character(d[[team_col]][last])[match(out$player_id, d$player_id[last])]
  out
}

# pfr_id -> gsis_id from the nflverse players table (the study's crosswalk).
ldr_pfr_xwalk <- function(players) {
  x <- players[!is.na(players$pfr_id) & !is.na(players$gsis_id) & nzchar(players$pfr_id), c("pfr_id", "gsis_id")]
  x[!duplicated(x$pfr_id), , drop = FALSE]
}

# Names and positions: player stats (display name) first, then the players table.
ldr_identity <- function(pstats, players) {
  a <- pstats[order(pstats$week), c("player_id", "player_display_name", "position")]
  a <- a[!duplicated(a$player_id, fromLast = TRUE), ]
  b <- if (!is.null(players)) data.frame(player_id = players$gsis_id, player_display_name = players$display_name,
                                          position = players$position, stringsAsFactors = FALSE) else a[0, ]
  b <- b[!is.na(b$player_id) & !(b$player_id %in% a$player_id), ]
  b <- b[!duplicated(b$player_id), ]
  rbind(a, b)
}

# ------------------------------------------------------------------------------
# Cards
# ------------------------------------------------------------------------------
.ldr_round <- function(x, d = 4L) ifelse(is.finite(x), round(x, d), NA_real_)

# Order qualified rows in the card direction; ties share a rank and sort by name.
ldr_rank_rows <- function(df, lower_is_better) {
  if (!nrow(df)) return(df)
  key <- round(df$value, 4)
  if (!lower_is_better) key <- -key
  df <- df[order(key, df$player), , drop = FALSE]
  key <- sort(key)
  df$rank <- as.integer(rank(key, ties.method = "min"))
  df
}

.ldr_leader_list <- function(df) {
  df <- utils::head(df, LDR_TOP_N)
  lapply(seq_len(nrow(df)), function(i) list(
    rank = df$rank[i], player_id = df$player_id[i], player = df$player[i],
    team = df$team[i], position = if (is.na(df$position[i])) NULL else df$position[i],
    value = .ldr_round(df$value[i]),
    sample = if (is.na(df$sample[i])) NULL else .ldr_round(df$sample[i], 1L),
    required = if (is.na(df$required[i])) NULL else .ldr_round(df$required[i], 1L),
    team_games_played = if (is.na(df$team_games_played[i])) NULL else as.integer(df$team_games_played[i])))
}

# Assemble a card. cand: player_id, value, sample, team (+ optional player/position);
# tg: named team games over the card's games; ident: names/positions.
ldr_card <- function(st, cand, tg, through, ident, unavailable_reason = NULL, notes = NULL) {
  minimum <- ldr_minimum(st)
  total <- st$kind == "total"
  if (is.null(cand) || !nrow(cand)) cand <- data.frame(player_id = character(0), value = numeric(0),
    sample = numeric(0), team = character(0), stringsAsFactors = FALSE)
  m <- match(cand$player_id, ident$player_id)
  if (!("player" %in% names(cand))) cand$player <- rep(NA_character_, nrow(cand))
  if (!("position" %in% names(cand))) cand$position <- rep(NA_character_, nrow(cand))
  cand$player <- ifelse(is.na(cand$player), ident$player_display_name[m], cand$player)
  cand$position <- ifelse(is.na(cand$position), ident$position[m], cand$position)
  cand$player[is.na(cand$player)] <- cand$player_id[is.na(cand$player)]
  cand$team_games_played <- as.integer(unname(tg[cand$team]))
  cand$required <- if (total) rep(NA_real_, nrow(cand)) else ldr_required(minimum, cand$team_games_played)
  if (total) cand$sample <- rep(NA_real_, nrow(cand))
  missing_value <- !is.finite(cand$value)
  keep <- !missing_value
  if (total) {
    # A counting total of zero leads nothing; total EPA keeps every finite value.
    if (st$format == "count") keep <- keep & cand$value > 0
  } else {
    keep <- keep & is.finite(cand$required) & is.finite(cand$sample) & cand$sample >= cand$required
  }
  q <- ldr_rank_rows(cand[keep, , drop = FALSE], st$lower_is_better)
  unavailable <- !is.null(unavailable_reason)
  empty <- nrow(q) == 0L
  status <- if (unavailable) "unavailable" else if (empty) "not_enough_games" else "ok"
  list(
    key = st$key, label = st$label, group = st$group, kind = st$kind, format = st$format,
    lower_is_better = st$lower_is_better, unit = st$unit, unit_label = LDR_UNIT_LABELS[[st$unit]],
    minimum_full_season = if (total) NULL else minimum, minimum_constant = st$min,
    through_date = if (unavailable) NULL else through,
    through_date_null_reason = if (unavailable) unavailable_reason else if (is.null(through)) "No game of this season is in the source yet." else NULL,
    noise_note = st$noise, noise_note_text = if (st$noise) LDR_NOISE_TEXT else NULL,
    status = status,
    status_text = switch(status, ok = NULL, not_enough_games = LDR_NOT_ENOUGH, unavailable = LDR_UNAVAILABLE),
    null_reason = switch(status, ok = NULL, unavailable = unavailable_reason,
      not_enough_games = if (total) "No player has recorded this stat yet this season." else
        sprintf("No player has reached the scaled minimum yet (%s %s over a full season, scaled by team games played).",
                format(minimum, big.mark = ","), LDR_UNIT_LABELS[[st$unit]])),
    source = st$source, refresh = st$refresh, formula = st$formula,
    candidates = nrow(cand), qualified_count = nrow(q), excluded_no_value = sum(missing_value),
    notes = notes,
    leaders = .ldr_leader_list(q))
}

# Build every card from the inputs. `skip` = keys not to build (refresh: impact).
# inp: pbp, pstats, snaps, players (data frames, any may be NULL), pfr_rush, pfr_def
# (NULL with pfr_errors[[type]] holding the fetch error when unavailable).
ldr_build_cards <- function(inp, season = CURRENT_SEASON, skip = character(0)) {
  pbp <- .ldr_reg(inp$pbp, season, "season_type")
  if (!nrow(pbp)) stop("build_player_leaders: no regular-season play-by-play for the current season", call. = FALSE)
  pstats <- .ldr_reg(inp$pstats, season, "season_type")
  snaps <- .ldr_reg(inp$snaps, season, "game_type")
  players <- if (is.null(inp$players)) NULL else as.data.frame(inp$players, stringsAsFactors = FALSE)
  games <- ldr_game_table(pbp)
  ident <- ldr_identity(pstats, players)
  pt <- ldr_play_tables(pbp)
  cards <- list(); diag <- list()
  st_of <- function(k) LDR_STATS[[k]]
  pbp_ids <- games$game_id
  tg_pbp <- ldr_team_games(games, pbp_ids); thr_pbp <- ldr_through(games, pbp_ids)

  # ---- play-by-play rate cards
  pt$db$cpoe_num <- ifelse(is.na(pt$db$cpoe), 0, pt$db$cpoe)
  pt$db$cpoe_den <- as.numeric(!is.na(pt$db$cpoe))
  adb <- ldr_agg(pt$db, c("qb_epa", "cpoe_num", "cpoe_den", "success", "sack", "interception", "att"))
  aru <- ldr_agg(pt$ru, c("epa", "success"))
  are <- ldr_agg(pt$re, c("epa", "complete_pass"))
  rate <- function(num, den) ifelse(!is.na(den) & den > 0, num / den, NA_real_)
  rc <- function(a, val) data.frame(player_id = a$player_id, value = val, sample = a$n, team = a$team,
                                    stringsAsFactors = FALSE)
  add <- function(k, cand, tg, thr, reason = NULL, notes = NULL) {
    if (!(k %in% skip)) cards[[k]] <<- ldr_card(st_of(k), cand, tg, thr, ident, reason, notes)
  }
  add("pass_epa",  rc(adb, rate(adb$qb_epa, adb$n)), tg_pbp, thr_pbp)
  add("pass_cpoe", rc(adb, rate(adb$cpoe_num, adb$cpoe_den)), tg_pbp, thr_pbp)
  add("pass_succ", rc(adb, rate(adb$success, adb$n)), tg_pbp, thr_pbp)
  add("sack_rate", rc(adb, rate(adb$sack, adb$n)), tg_pbp, thr_pbp)
  add("int_rate",  rc(adb, rate(adb$interception, adb$att)), tg_pbp, thr_pbp)
  add("rush_epa",  rc(aru, rate(aru$epa, aru$n)), tg_pbp, thr_pbp)
  add("rush_succ", rc(aru, rate(aru$success, aru$n)), tg_pbp, thr_pbp)
  add("rec_epa",   rc(are, rate(are$epa, are$n)), tg_pbp, thr_pbp)
  add("catch_rate", rc(are, rate(are$complete_pass, are$n)), tg_pbp, thr_pbp)

  # ---- total EPA (impact): passer + rusher + receiver credit, the study's fields
  if (!("total_epa" %in% skip)) {
    parts <- rbind(
      data.frame(player_id = pt$db$player_id, epa = pt$db$qb_epa, game_date = pt$db$game_date,
                 play_id = pt$db$play_id, posteam = pt$db$posteam, stringsAsFactors = FALSE),
      data.frame(player_id = pt$ru$player_id, epa = pt$ru$epa, game_date = pt$ru$game_date,
                 play_id = pt$ru$play_id, posteam = pt$ru$posteam, stringsAsFactors = FALSE),
      data.frame(player_id = pt$re$player_id, epa = pt$re$epa, game_date = pt$re$game_date,
                 play_id = pt$re$play_id, posteam = pt$re$posteam, stringsAsFactors = FALSE))
    ate <- ldr_agg(parts, "epa")
    add("total_epa", rc(ate, ate$epa), tg_pbp, thr_pbp)
  }

  # ---- season totals from player stats
  ps_ids <- intersect(unique(pstats$game_id), pbp_ids)
  psx <- pstats[pstats$game_id %in% ps_ids, , drop = FALSE]
  psx$game_date <- games$game_date[match(psx$game_id, games$game_id)]
  psx$play_id <- 0
  tg_ps <- ldr_team_games(games, ps_ids); thr_ps <- ldr_through(games, ps_ids)
  aps <- ldr_agg(psx, c("passing_tds", "receptions", "def_sacks", "def_interceptions", "def_tackles_for_loss"),
                 order_cols = c("game_date", "play_id"), team_col = "team")
  tc <- function(val) data.frame(player_id = aps$player_id, value = val, sample = NA_real_, team = aps$team,
                                 stringsAsFactors = FALSE)
  if (!is.null(aps)) {
    add("pass_td", tc(aps$passing_tds), tg_ps, thr_ps)
    add("receptions", tc(aps$receptions), tg_ps, thr_ps)
    add("sacks", tc(aps$def_sacks), tg_ps, thr_ps)
    add("def_int", tc(aps$def_interceptions), tg_ps, thr_ps)
    add("tfl", tc(aps$def_tackles_for_loss), tg_ps, thr_ps)
  } else {
    for (k in c("pass_td", "receptions", "sacks", "def_int", "tfl"))
      add(k, NULL, tg_ps, NULL, "No current-season player stats are available yet.")
  }

  # ---- yards per game: games played from snap counts (study game_table)
  xw <- if (is.null(players)) NULL else ldr_pfr_xwalk(players)
  pg_reason <- NULL; link_rate <- NA_real_
  if (is.null(xw) || !nrow(snaps)) {
    pg_reason <- "Snap counts or the nflverse players table (games played) are unavailable for the current season."
  } else {
    snaps$gsis_id <- xw$gsis_id[match(snaps$pfr_player_id, xw$pfr_id)]
    on_field <- !is.na(snaps$offense_snaps) & snaps$offense_snaps > 0
    played <- on_field | (!is.na(snaps$defense_snaps) & snaps$defense_snaps > 0)
    link_rate <- mean(!is.na(snaps$gsis_id[played]))
    if (!is.finite(link_rate) || link_rate < LDR_MIN_LINK_RATE)
      pg_reason <- sprintf("Only %.1f%% of snap-count rows link to a gsis id (the study requires %.0f%%).",
                           100 * link_rate, 100 * LDR_MIN_LINK_RATE)
  }
  diag$snap_link_rate <- if (is.finite(link_rate)) round(link_rate, 4) else NULL
  pg_ids <- if (is.null(pg_reason)) Reduce(intersect, list(unique(snaps$game_id), ps_ids)) else character(0)
  tg_pg <- ldr_team_games(games, pg_ids); thr_pg <- ldr_through(games, pg_ids)
  pg_card <- function(k, pool, col) {
    if (!is.null(pg_reason)) return(add(k, NULL, tg_pg, NULL, pg_reason))
    s <- snaps[!is.na(snaps$offense_snaps) & snaps$offense_snaps > 0 & snaps$game_id %in% pg_ids, , drop = FALSE]
    s <- s[!duplicated(s[, c("pfr_player_id", "game_id")]), , drop = FALSE]
    s <- s[!is.na(s$gsis_id) & s$gsis_id %in% pool, , drop = FALSE]
    ps1 <- psx[!duplicated(psx[, c("player_id", "game_id")]), c("player_id", "game_id", col)]
    v <- as.numeric(ps1[[col]][match(paste(s$gsis_id, s$game_id), paste(ps1$player_id, ps1$game_id))])
    # Played with no stats row = none of the counted events (0), as in the study.
    has_row <- paste(s$gsis_id, s$game_id) %in% paste(ps1$player_id, ps1$game_id)
    v[!has_row] <- 0
    s$yds <- v; s$player_id <- s$gsis_id
    s$game_date <- games$game_date[match(s$game_id, games$game_id)]; s$play_id <- 0
    a <- ldr_agg(s, "yds", team_col = "team")
    notes <- sprintf("%d of %d pool players have no linked snap-count rows and cannot be ranked.",
                     sum(!(pool %in% s$gsis_id)), length(pool))
    add(k, if (is.null(a)) NULL else data.frame(player_id = a$player_id, value = a$yds / a$n, sample = a$n,
                                                 team = a$team, stringsAsFactors = FALSE),
        tg_pg, thr_pg, notes = notes)
  }
  pg_card("pass_ypg", unique(pt$db$player_id), "passing_yards")
  pg_card("rush_ypg", unique(pt$ru$player_id), "rushing_yards")
  pg_card("rec_ypg",  unique(pt$re$player_id), "receiving_yards")

  # ---- Pro Football Reference cards (never filled from another source)
  pfr_reason <- function(type) sprintf(
    "Pro Football Reference %s stats for %d could not be fetched (nflreadr::load_pfr_advstats): %s",
    type, season, inp$pfr_errors[[type]] %||% "no rows returned")
  pr <- .ldr_reg(inp$pfr_rush %||% data.frame(), season, "game_type")
  if (!nrow(pr) || is.null(xw)) {
    add("rush_yac", NULL, NULL, NULL, if (!nrow(pr)) pfr_reason("rush") else "The nflverse players table is unavailable (pfr -> gsis link).")
  } else {
    pr <- pr[!is.na(pr$carries) & pr$carries > 0 & pr$game_id %in% pbp_ids, , drop = FALSE]
    pr <- pr[!duplicated(pr[, c("pfr_player_id", "game_id")]), , drop = FALSE]
    pr_ids <- unique(pr$game_id)
    pr$player_id <- xw$gsis_id[match(pr$pfr_player_id, xw$pfr_id)]
    unlinked <- unique(pr$pfr_player_id[is.na(pr$player_id)])
    pr <- pr[!is.na(pr$player_id), , drop = FALSE]
    pr$game_date <- games$game_date[match(pr$game_id, games$game_id)]; pr$play_id <- 0
    ay <- ldr_agg(pr, c("rushing_yards_after_contact", "carries"), team_col = "team")
    rcar <- ldr_agg(pt$ru[pt$ru$game_id %in% pr_ids, , drop = FALSE], character(0))
    add("rush_yac", if (is.null(ay)) NULL else data.frame(
          player_id = ay$player_id, value = rate(ay$rushing_yards_after_contact, ay$carries),
          sample = rcar$n[match(ay$player_id, rcar$player_id)],
          team = ifelse(is.na(rcar$team[match(ay$player_id, rcar$player_id)]), ay$team,
                       rcar$team[match(ay$player_id, rcar$player_id)]), stringsAsFactors = FALSE),
        ldr_team_games(games, pr_ids), ldr_through(games, pr_ids),
        notes = sprintf("%d PFR rushers could not be linked to a gsis id and cannot be ranked.", length(unlinked)))
  }
  pd <- .ldr_reg(inp$pfr_def %||% data.frame(), season, "game_type")
  if (!nrow(pd)) {
    add("pressures", NULL, NULL, NULL, pfr_reason("def"))
  } else {
    pd <- pd[pd$game_id %in% pbp_ids, , drop = FALSE]
    pd <- pd[!duplicated(pd[, c("pfr_player_id", "game_id")]), , drop = FALSE]
    pd_ids <- unique(pd$game_id)
    gs <- if (is.null(xw)) rep(NA_character_, nrow(pd)) else xw$gsis_id[match(pd$pfr_player_id, xw$pfr_id)]
    pd$player_id <- ifelse(is.na(gs), paste0("pfr:", pd$pfr_player_id), gs)
    pd$game_date <- games$game_date[match(pd$game_id, games$game_id)]; pd$play_id <- 0
    ap <- ldr_agg(pd, "def_pressures", team_col = "team")
    nm <- pd$pfr_player_name[match(ap$player_id, pd$player_id)]
    add("pressures", data.frame(player_id = ap$player_id, value = ap$def_pressures, sample = NA_real_,
                                team = ap$team, player = nm, stringsAsFactors = FALSE),
        ldr_team_games(games, pd_ids), ldr_through(games, pd_ids))
  }
  list(cards = cards[intersect(names(LDR_STATS), names(cards))], diag = diag,
       games = games, n_games = nrow(games))
}

# ------------------------------------------------------------------------------
# Payload
# ------------------------------------------------------------------------------
ldr_methods <- function(diag = list()) {
  mins <- lapply(LDR_STATS, function(st) list(
    key = st$key, label = st$label, group = st$group, unit = st$unit, unit_label = LDR_UNIT_LABELS[[st$unit]],
    minimum_full_season = if (st$kind == "total") NULL else ldr_minimum(st), constant = st$min,
    lower_is_better = st$lower_is_better, formula = st$formula))
  ex <- round(ldr_required(LEADERS_MIN_DROPBACKS_PASSING_RATES, 12), 0)
  list(
    scaling_rule = sprintf("required = minimum x team games played / %d", LEADERS_FULL_SEASON_GAMES),
    scaling_text = sprintf(paste0(
      "Each minimum is a full-season (%d-game) bar set by the owner after reviewing the leader reliability study's curves; ",
      "the study did not choose them. The bar scales with the games played by the player's current team: ",
      "required = minimum x team games played / %d. For example, after 12 team games the passing-rate bar is about %d dropbacks. ",
      "Season totals have no minimum."), LEADERS_FULL_SEASON_GAMES, LEADERS_FULL_SEASON_GAMES, ex),
    traded_players = paste0(
      "A traded player's sample counts every game he played this season, for any team, and is held to the bar ",
      "of the team he played for most recently (his team in his latest game in that card's source)."),
    ranking = paste0("Highest figure leads, except sack rate and interception rate, where the lowest figure leads. ",
                     "Totals are ranked as season totals. Ties share a rank."),
    impact_note = paste0(
      "Total EPA is the impact measure; football has no RAPM and no new model is fitted. Each player is credited with ",
      "the EPA of his own plays, using the study's fields: nflfastR qb_epa on his dropbacks as passer (pass attempts, ",
      "sacks and scrambles), epa on his designed carries, and epa on his targets as receiver, summed. A completed pass ",
      "credits both the passer and the receiver in full, so totals across players do not sum to team EPA. ",
      "Two-point tries and kneels are excluded."),
    noise_note = paste0(
      "Interception rate, completion % over expected, EPA per carry, rushing success rate and EPA per target are mostly ",
      "noise at season sample sizes (study: interception rate, EPA per carry and rushing success rate never reach 0.5 ",
      "reliability; completion % over expected is about 0.34 at 150 dropbacks; EPA per target about 0.13 at 30 targets)."),
    definitions = paste0(
      "Dropbacks: plays with qb_dropback = 1 (pass attempts, sacks, scrambles), credited to the passer. ",
      "Designed carries: run plays with rush_attempt = 1, excluding QB scrambles and kneels, credited to the rusher. ",
      "Targets: pass attempts (not sacks) with a listed receiver. Two-point tries are excluded throughout. ",
      "Games played: games with at least one offensive snap in the snap counts. ",
      "Success = EPA above zero; completion % over expected is nflfastR's cpoe in percentage points."),
    refresh = paste0(
      "Cards update in the 09:00 pipeline run and in the evening score refreshes. The total EPA card is model-based ",
      "and updates in the 09:00 run only. Each card shows its own through date."),
    sample = "Regular-season games of the current season only. There is no fallback to last season.",
    not_available = paste0(
      "Yards per route run is not shown: nflverse does not record routes run for every receiver."),
    study_source_commit = LEADERS_STUDY_SOURCE_COMMIT,
    base_games = LEADERS_FULL_SEASON_GAMES,
    minimums = unname(mins),
    diagnostics = diag,
    nulls = "Values that cannot be supported are null with a reason; nothing is imputed or synthesised.")
}

ldr_build_payload <- function(cards, diag, sources, now = Sys.time(), season = CURRENT_SEASON) {
  thr <- unlist(lapply(cards, `[[`, "through_date"))
  list(
    schema_version = LDR_SCHEMA_VERSION,
    generated_at = format(now, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    season = as.character(season),
    season_type = "REG",
    through_date = if (length(thr)) max(thr) else NULL,
    groups = LDR_GROUPS,
    cards = unname(cards),
    methods = ldr_methods(diag),
    sources = sources)
}

ldr_json_text <- function(payload) {
  as.character(jsonlite::toJSON(payload, auto_unbox = TRUE, pretty = TRUE,
                                null = "null", na = "null", digits = NA))
}

ldr_write_payload <- function(payload, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(ldr_json_text(payload), path, useBytes = TRUE)
  invisible(path)
}

# ------------------------------------------------------------------------------
# Inputs: pipeline (nflreadr + caches)
# ------------------------------------------------------------------------------
.ldr_hours_old <- function(p) as.numeric(difftime(Sys.time(), file.info(p)$mtime, units = "hours"))

# Same-season cache, refreshed through nflreadr when missing or older than max_hours.
.ldr_cached <- function(path, fetch, max_hours) {
  if (!file.exists(path) || .ldr_hours_old(path) > max_hours) {
    d <- tryCatch(fetch(), error = function(e) {
      message(sprintf(">>> [LEADERS] refresh of %s failed: %s", basename(path), conditionMessage(e))); NULL })
    if (!is.null(d) && nrow(d)) saveRDS(d, path)
  }
  if (file.exists(path)) as.data.frame(readRDS(path), stringsAsFactors = FALSE) else NULL
}

ldr_load_inputs_pipeline <- function(season = CURRENT_SEASON) {
  if (!requireNamespace("nflreadr", quietly = TRUE)) stop("build_player_leaders: nflreadr is not installed", call. = FALSE)
  inp <- list(pfr_errors = list())
  inp$pbp <- .ldr_cached(CACHE_DNA_PBP, function() nflreadr::load_pbp(seasons = season), 12)
  inp$pstats <- .ldr_cached(CACHE_DNA_PLAYER_STATS,
                            function() nflreadr::load_player_stats(seasons = season, summary_level = "week"), 12)
  inp$snaps <- .ldr_cached(CACHE_SNAP_COUNTS, function() nflreadr::load_snap_counts(seasons = season), 24)
  inp$players <- .ldr_cached(CACHE_LEADERS_PLAYERS, function() nflreadr::load_players(), 24)
  for (type in c("rush", "def")) {
    d <- tryCatch(as.data.frame(nflreadr::load_pfr_advstats(seasons = season, stat_type = type, summary_level = "week")),
                  error = function(e) { inp$pfr_errors[[type]] <<- conditionMessage(e); NULL })
    if (!is.null(d) && !nrow(d)) inp$pfr_errors[[type]] <- "no rows returned for the current season"
    inp[[paste0("pfr_", type)]] <- d
  }
  for (k in c("pbp", "pstats")) if (is.null(inp[[k]])) stop(sprintf("build_player_leaders: missing current-season input %s", k), call. = FALSE)
  inp
}

ldr_sources <- function(inp, how) {
  list(
    play_by_play = sprintf("%s (regular season, %s)", LDR_SRC_PBP, how),
    player_stats = sprintf("%s (%s)", LDR_SRC_PS, how),
    snap_counts = sprintf("nflreadr::load_snap_counts() (%s)", how),
    players = sprintf("nflreadr::load_players() for the pfr -> gsis link (%s)", how),
    pfr_rush = if (is.null(inp$pfr_errors$rush)) sprintf("nflreadr::load_pfr_advstats(stat_type = \"rush\") (%s)", how) else
      sprintf("unavailable: %s", inp$pfr_errors$rush),
    pfr_def = if (is.null(inp$pfr_errors$def)) sprintf("nflreadr::load_pfr_advstats(stat_type = \"def\") (%s)", how) else
      sprintf("unavailable: %s", inp$pfr_errors$def),
    study = sprintf("tools/leader_reliability_study.R at %s", LEADERS_STUDY_SOURCE_COMMIT))
}

# ------------------------------------------------------------------------------
# Stage entry point (09:00 pipeline)
# ------------------------------------------------------------------------------
run_build_player_leaders <- function(season = CURRENT_SEASON, output_json = WEB_JSON_PLAYER_LEADERS,
                                     inputs = NULL, now = Sys.time()) {
  inp <- inputs %||% ldr_load_inputs_pipeline(season)
  built <- ldr_build_cards(inp, season)
  payload <- ldr_build_payload(built$cards, built$diag, ldr_sources(inp, "09:00 pipeline"), now, season)
  ldr_write_payload(payload, output_json)
  st <- vapply(payload$cards, `[[`, "", "status")
  cat(sprintf(">>> [LEADERS] Wrote %s (through %s): %d of %d cards have qualifiers; not enough games: %s; unavailable: %s\n",
              output_json, payload$through_date %||% "n/a", sum(st == "ok"), length(st),
              paste(vapply(payload$cards[st == "not_enough_games"], `[[`, "", "key"), collapse = ", "),
              paste(vapply(payload$cards[st == "unavailable"], `[[`, "", "key"), collapse = ", ")))
  invisible(payload)
}

# ------------------------------------------------------------------------------
# Evening refresh (tools/refresh_live_results.R): base R + jsonlite only
# ------------------------------------------------------------------------------
LDR_NFLVERSE_RELEASES <- "https://github.com/nflverse/nflverse-data/releases/download/"
# The same release files nflreadr::load_*() read.
ldr_release_paths <- function(season) list(
  pbp = sprintf("pbp/play_by_play_%d.rds", season),
  pstats = sprintf("stats_player/stats_player_week_%d.rds", season),
  snaps = sprintf("snap_counts/snap_counts_%d.rds", season),
  players = "players/players.rds",
  pfr_rush = sprintf("pfr_advstats/advstats_week_rush_%d.rds", season),
  pfr_def = sprintf("pfr_advstats/advstats_week_def_%d.rds", season))

ldr_fetch_release_rds <- function(rel_path) {
  f <- tempfile(fileext = ".rds")
  on.exit(unlink(f), add = TRUE)
  utils::download.file(paste0(LDR_NFLVERSE_RELEASES, rel_path), f, mode = "wb", quiet = TRUE)
  as.data.frame(readRDS(f), stringsAsFactors = FALSE)
}

# Fetch every input; core inputs (play-by-play, player stats, snap counts, players)
# failing stops the refresh, PFR failing only blanks those two cards' inputs.
ldr_load_inputs_release <- function(season = CURRENT_SEASON, fetch = ldr_fetch_release_rds) {
  p <- ldr_release_paths(season)
  inp <- list(pfr_errors = list())
  for (k in c("pbp", "pstats", "snaps", "players")) inp[[k]] <- fetch(p[[k]])
  for (type in c("rush", "def")) {
    k <- paste0("pfr_", type)
    inp[[k]] <- tryCatch(fetch(p[[k]]), error = function(e) { inp$pfr_errors[[type]] <<- conditionMessage(e); NULL })
  }
  inp
}

.ldr_cards_by_key <- function(cards) stats::setNames(cards, vapply(cards, `[[`, "", "key"))

#' Rebuild the non-model leader cards from freshly fetched nflverse data.
#'
#' Never raises: any failure returns a status and leaves the file exactly as it was.
#' The total EPA card (model-based) is copied through; so is a PFR card whose
#' current-season fetch failed (it keeps its own through date). Writes only when a
#' card changed.
#' @return list(status, file)
ldr_refresh_leaders <- function(path = WEB_JSON_PLAYER_LEADERS, season = CURRENT_SEASON,
                                fetch = ldr_fetch_release_rds, now = Sys.time()) {
  tryCatch({
    if (!file.exists(path)) return(list(status = "no_file", file = NULL))
    old <- jsonlite::fromJSON(path, simplifyVector = FALSE)
    old_cards <- .ldr_cards_by_key(old$cards)
    inp <- tryCatch(ldr_load_inputs_release(season, fetch), error = function(e) e)
    if (inherits(inp, "error")) return(list(status = sprintf("fetch_failed: %s", conditionMessage(inp)), file = NULL))
    model_keys <- names(Filter(function(s) s$refresh == "pipeline_only", LDR_STATS))
    built <- ldr_build_cards(inp, season, skip = model_keys)
    # Round-trip new cards through JSON so they compare like the file's cards.
    new_cards <- .ldr_cards_by_key(jsonlite::fromJSON(ldr_json_text(unname(built$cards)), simplifyVector = FALSE))
    keep_old <- model_keys
    if (!is.null(inp$pfr_errors$rush)) keep_old <- c(keep_old, "rush_yac")
    if (!is.null(inp$pfr_errors$def)) keep_old <- c(keep_old, "pressures")
    for (k in keep_old) if (!is.null(old_cards[[k]])) new_cards[[k]] <- old_cards[[k]]
    new_cards <- new_cards[intersect(names(LDR_STATS), names(new_cards))]
    if (identical(unname(new_cards), unname(old_cards[names(new_cards)])) &&
        length(new_cards) == length(old_cards)) {
      return(list(status = "up_to_date", file = NULL))
    }
    sources <- old$sources %||% list()
    sources$evening_refresh <- sprintf(paste0(
      "Non-model cards rebuilt by tools/refresh_live_results.R from the nflverse release files at %s",
      "; total EPA%s copied from the 09:00 run"), format(now, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      if (length(keep_old) > 1) sprintf(" and %s", paste(setdiff(keep_old, model_keys), collapse = ", ")) else "")
    payload <- ldr_build_payload(unname(new_cards), built$diag, sources, now, season)
    ldr_write_payload(payload, path)
    list(status = "updated", file = path)
  }, error = function(e) list(status = sprintf("error: %s", conditionMessage(e)), file = NULL))
}

# Entry point: Rscript build_player_leaders.R
local({
  argv <- commandArgs(trailingOnly = FALSE)
  files <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (any(grepl("build_player_leaders[.]R$", files))) run_build_player_leaders()
})
