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
