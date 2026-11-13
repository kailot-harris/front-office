# ==============================================================================
# tools/postseason_feed.R — real per-plate-appearance postseason data
# Path: tools/postseason_feed.R
#
# Shared loader for the postseason charts. Everything here comes from MLB's
# public Stats API and is cached under cache/postseason/. There is no fallback:
# if a game's feed cannot be fetched the caller stops and renders nothing.
#
#   ps_fetch_wp(game_pk)   one row per plate appearance: inning, half, score,
#                          MLB's home win probability, leverage index, the
#                          pitcher, and MLB's own description of the play
#   ps_team_abbr()         team id -> abbreviation lookup
#   ps_world_series()      the published World Series summary (real results)
# ==============================================================================

PS_API <- "https://statsapi.mlb.com/api/v1"

ps_fetch_wp <- function(game_pk) {
  path <- cache_path("postseason", sprintf("wp_%s.rds", game_pk))
  if (file.exists(path)) return(readRDS(path))

  x <- tryCatch(
    jsonlite::fromJSON(sprintf("%s/game/%s/winProbability", PS_API, game_pk), flatten = TRUE),
    error = function(e) NULL
  )
  need <- c("atBatIndex", "about.inning", "about.isTopInning", "homeTeamWinProbability",
            "leverageIndex", "result.homeScore", "result.awayScore", "result.description",
            "matchup.pitcher.id", "matchup.pitcher.fullName")
  if (!is.data.frame(x) || nrow(x) == 0 || !all(need %in% names(x))) {
    stop(sprintf("[SKIP-NO-DATA] no win probability feed for game %s; nothing rendered.", game_pk), call. = FALSE)
  }

  out <- data.frame(
    game_pk    = as.integer(game_pk),
    ab         = as.integer(x$atBatIndex),
    inning     = as.integer(x$about.inning),
    top        = as.logical(x$about.isTopInning),
    home_wp    = as.numeric(x$homeTeamWinProbability) / 100,
    li         = as.numeric(x$leverageIndex),
    home_score = as.integer(x$result.homeScore),
    away_score = as.integer(x$result.awayScore),
    desc       = as.character(x$result.description),
    pitcher_id = as.integer(x$matchup.pitcher.id),
    pitcher    = as.character(x$matchup.pitcher.fullName),
    stringsAsFactors = FALSE
  )
  out <- out[order(out$ab), , drop = FALSE]
  saveRDS(out, path)
  out
}

ps_team_abbr <- function() {
  path <- cache_path("postseason", "team_abbr.rds")
  if (file.exists(path)) return(readRDS(path))
  x <- tryCatch(jsonlite::fromJSON(sprintf("%s/teams?sportId=1", PS_API), flatten = TRUE)$teams,
                error = function(e) NULL)
  if (!is.data.frame(x) || !all(c("id", "abbreviation") %in% names(x))) {
    stop("[SKIP-NO-DATA] could not load the MLB team list; nothing rendered.", call. = FALSE)
  }
  map <- setNames(as.character(x$abbreviation), as.character(x$id))
  saveRDS(map, path)
  map
}

ps_world_series <- function() {
  if (!file.exists(WEB_JSON_WORLD_SERIES)) {
    stop("[SKIP-NO-DATA] world_series.json was not found; nothing rendered.", call. = FALSE)
  }
  ws <- jsonlite::fromJSON(WEB_JSON_WORLD_SERIES, simplifyVector = FALSE)
  ws$completed <- Filter(function(g) isTRUE(g$is_completed), ws$games)
  if (length(ws$completed) == 0) {
    stop("[SKIP-NO-DATA] no completed World Series games on record; nothing rendered.", call. = FALSE)
  }
  ws
}

# ------------------------------------------------------------------------------
# Postseason results: games, series and regular-season records.
#
# Everything below is read from cache/ingest/mlb_schedule_<season>.rds (MLB's
# schedule feed) and world_series.json. Nothing about who played, who won or by
# how much is written in a chart script.
# ------------------------------------------------------------------------------

ps_schedule <- function(season = 2026,
                        schedule_file = cache_path("ingest", sprintf("mlb_schedule_%d.rds", season))) {
  if (!file.exists(schedule_file)) {
    stop(sprintf("[SKIP-NO-DATA] %s was not found; nothing rendered.", schedule_file), call. = FALSE)
  }
  sch <- as.data.frame(readRDS(schedule_file))
  need <- c("game_pk", "game_type", "official_date", "status_detailed_state", "series_description",
            "description", "series_game_number", "teams_home_team_id", "teams_away_team_id",
            "teams_home_team_name", "teams_away_team_name", "teams_home_score", "teams_away_score")
  if (!all(need %in% names(sch))) {
    stop("[SKIP-NO-DATA] the schedule cache is missing expected columns; nothing rendered.", call. = FALSE)
  }
  sch[sch$status_detailed_state == "Final", need, drop = FALSE]
}

#' Regular-season wins and losses per team abbreviation.
ps_records <- function(season = 2026, schedule = ps_schedule(season)) {
  abbr <- ps_team_abbr()
  reg <- schedule[schedule$game_type == "R" & !is.na(schedule$teams_home_score) &
                    !is.na(schedule$teams_away_score), , drop = FALSE]
  reg <- reg[!duplicated(reg$game_pk), , drop = FALSE]
  if (nrow(reg) == 0) {
    stop("[SKIP-NO-DATA] no final regular-season games on record; nothing rendered.", call. = FALSE)
  }
  home_won <- reg$teams_home_score > reg$teams_away_score
  winner <- ifelse(home_won, reg$teams_home_team_id, reg$teams_away_team_id)
  loser  <- ifelse(home_won, reg$teams_away_team_id, reg$teams_home_team_id)
  w <- table(unname(abbr[as.character(winner)]))
  l <- table(unname(abbr[as.character(loser)]))
  teams <- union(names(w), names(l))
  data.frame(
    team = teams,
    wins = as.integer(ifelse(is.na(w[teams]), 0L, w[teams])),
    losses = as.integer(ifelse(is.na(l[teams]), 0L, l[teams])),
    stringsAsFactors = FALSE
  )
}

#' One row per completed postseason game, all four rounds.
#' round: 1 Wild Card, 2 Division Series, 3 Championship Series, 4 World Series.
ps_games <- function(season = 2026, schedule = ps_schedule(season)) {
  abbr <- ps_team_abbr()
  round_of <- c(F = 1L, D = 2L, L = 3L)
  po <- schedule[schedule$game_type %in% names(round_of), , drop = FALSE]
  po <- po[!duplicated(po$game_pk), , drop = FALSE]
  if (nrow(po) == 0) {
    stop("[SKIP-NO-DATA] no final postseason games on record; nothing rendered.", call. = FALSE)
  }
  early <- data.frame(
    game_pk    = as.integer(po$game_pk),
    round      = unname(round_of[po$game_type]),
    league     = substr(po$series_description, 1, 2),
    # "NLDS 'A' Game 3" -> "NLDS 'A'"; the letter keeps the two series in a round apart
    series     = trimws(sub(" Game [0-9]+.*$", "", po$description)),
    game_num   = as.integer(po$series_game_number),
    date       = as.character(po$official_date),
    home       = unname(abbr[as.character(po$teams_home_team_id)]),
    away       = unname(abbr[as.character(po$teams_away_team_id)]),
    home_name  = as.character(po$teams_home_team_name),
    away_name  = as.character(po$teams_away_team_name),
    home_score = as.integer(po$teams_home_score),
    away_score = as.integer(po$teams_away_score),
    stringsAsFactors = FALSE
  )

  # The World Series comes from the published summary, which the results
  # refresh keeps current even when the schedule cache is behind.
  ws <- ps_world_series()
  late <- do.call(rbind, lapply(ws$completed, function(g) {
    data.frame(
      game_pk = as.integer(g$game_pk), round = 4L, league = "WS", series = "World Series",
      game_num = as.integer(g$game_number), date = as.character(g$game_date),
      home = g$home_team, away = g$away_team,
      home_name = g$home_team_name, away_name = g$away_team_name,
      home_score = as.integer(g$home_score), away_score = as.integer(g$away_score),
      stringsAsFactors = FALSE
    )
  }))

  out <- rbind(early, late)
  out$winner <- ifelse(out$home_score > out$away_score, out$home, out$away)
  out$loser  <- ifelse(out$home_score > out$away_score, out$away, out$home)
  out[order(out$round, out$series, out$game_num), , drop = FALSE]
}

#' One row per postseason series: who won, who lost, and by how many games.
#' Only decided series are returned (a team reached the wins the round needs).
ps_series <- function(games) {
  need_wins <- c(2L, 3L, 4L, 4L)
  rows <- lapply(split(games, games$series), function(g) {
    tally <- sort(table(g$winner), decreasing = TRUE)
    teams <- union(g$home, g$away)
    top <- names(tally)[1]
    other <- setdiff(teams, top)
    data.frame(
      series = g$series[1], round = g$round[1], league = g$league[1],
      winner = top, loser = other,
      winner_wins = as.integer(tally[1]),
      loser_wins = as.integer(nrow(g) - tally[1]),
      first_home = g$home[which.min(g$game_num)],
      decided = as.integer(tally[1]) >= need_wins[g$round[1]],
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  out <- out[out$decided, , drop = FALSE]
  out[order(out$round, out$series), , drop = FALSE]
}

#' Team abbreviation -> full name, taken from the games themselves.
ps_team_names <- function(games) {
  nm <- c(setNames(games$home_name, games$home), setNames(games$away_name, games$away))
  nm[!duplicated(names(nm))]
}
