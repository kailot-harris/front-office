# ==============================================================================
# build_tactical_events_dataset.R
# Extracts after-timeout (ATO) possessions and coach's challenge outcomes from
# ESPN play-by-play for build_coaching_dataset.R.
#
# Output: cache/pbp_timeout_cache.rds, matching the schema documented in
# build_coaching_dataset.R (PBP_REQUIRED_COLS):
#   team, event_type ("ato_offense" | "ato_defense" | "challenge"),
#   points, possessions, challenge_won
# plus game_id, season and period for traceability.
#
# Note: this builder is deliberately standalone, like every other build_*.R here.
# It repeats the small hoopR loaders in build_stint_dataset.R rather than adding a
# shared module that would change that script's already-validated behaviour.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(hoopR)
})

if (file.exists("config.R")) source("config.R")
.cache_dir <- if (exists("CACHE_DIR")) CACHE_DIR else "cache"
if (!dir.exists(.cache_dir)) dir.create(.cache_dir, recursive = TRUE)

message(">>> [TACTICAL] Building ATO and coach's challenge dataset from play-by-play...")

.current_season <- if (exists("CURRENT_SEASON")) CURRENT_SEASON else 2027
TACTICAL_SEASONS <- as.integer(
  Sys.getenv("TACTICAL_SEASONS", paste(c(.current_season, .current_season - 1), collapse = ",")) |>
    strsplit(",") |> unlist()
)

ESPN_ABBR_FIXUPS <- c(GS = "GSW", SA = "SAS", NY = "NYK", UTAH = "UTA",
                      NO = "NOP", WSH = "WAS")
NON_TEAM_ABBRS <- c("EAST", "WEST", "USA", "WORLD", "STARS", "STRIPES")

fix_abbr <- function(x) {
  x <- as.character(x)
  ifelse(x %in% names(ESPN_ABBR_FIXUPS), ESPN_ABBR_FIXUPS[x], x)
}

load_cached_season <- function(sn, prefix, fetch_fn, label) {
  path <- file.path(.cache_dir, sprintf("%s_%d.rds", prefix, sn))
  if (file.exists(path)) {
    got <- tryCatch(readRDS(path), error = function(e) NULL)
    if (!is.null(got) && nrow(got) > 0) {
      message(sprintf(">>> [TACTICAL] Loaded season %d %s from cache (%s rows).",
                      sn, label, format(nrow(got), big.mark = ",")))
      return(as.data.frame(got))
    }
  }
  message(sprintf(">>> [TACTICAL] Fetching season %d %s via hoopR...", sn, label))
  got <- tryCatch({
    d <- fetch_fn(seasons = sn)
    if (!is.null(d) && nrow(d) > 0) saveRDS(d, path)
    d
  }, error = function(e) {
    message(sprintf(">>> [WARN] hoopR %s fetch failed for season %d: %s", label, sn, conditionMessage(e)))
    NULL
  })
  if (is.null(got) || nrow(got) == 0) return(NULL)
  as.data.frame(got)
}

# Authoritative player -> team map; event team_id is not reliable on every event type.
load_player_teams <- function(seasons) {
  frames <- lapply(seasons, function(sn)
    load_cached_season(sn, "nba_player_box", hoopR::load_nba_player_box, "player box"))
  frames <- Filter(Negate(is.null), frames)
  if (length(frames) == 0) return(NULL)
  bind_rows(frames) %>%
    filter(!is.na(athlete_id), !is.na(team_abbreviation)) %>%
    transmute(game_id = as.character(game_id),
              player_id = as.character(athlete_id),
              team = fix_abbr(team_abbreviation)) %>%
    distinct(game_id, player_id, .keep_all = TRUE)
}

# ------------------------------------------------------------------------------
# Event classification
# ------------------------------------------------------------------------------
# A possession ends on a made field goal, a defensive rebound, a turnover, the
# final free throw of a trip, or the end of a period.
is_possession_end <- function(type_text, scoring_play, shooting_play) {
  ft <- grepl("Free Throw", type_text)
  made_fg <- scoring_play & shooting_play & !ft
  last_ft <- grepl("Free Throw - (1 of 1|2 of 2|3 of 3)", type_text)
  made_fg | last_ft |
    type_text == "Defensive Rebound" |
    grepl("Turnover", type_text) |
    type_text %in% c("End Period", "End Game")
}

# Events that identify who actually has the ball (a substitution or a second
# timeout after the first tells us nothing about possession).
is_offensive_marker <- function(type_text, shooting_play) {
  shooting_play | grepl("Turnover", type_text) | grepl("Free Throw", type_text) |
    type_text == "Offensive Rebound"
}

# ------------------------------------------------------------------------------
# ATO extraction for one game
# ------------------------------------------------------------------------------
extract_game_atos <- function(g, roster) {
  g <- g[order(g$game_play_number), ]
  n <- nrow(g)
  if (n < 10 || is.null(roster) || nrow(roster) == 0) return(NULL)

  home_ab <- fix_abbr(g$home_team_abbrev[1])
  away_ab <- fix_abbr(g$away_team_abbrev[1])
  if (home_ab %in% NON_TEAM_ABBRS || away_ab %in% NON_TEAM_ABBRS) return(NULL)

  team_of <- setNames(roster$team, roster$player_id)
  a1 <- as.character(g$athlete_id_1)
  tt <- g$type_text
  sp <- g$scoring_play
  shp <- g$shooting_play

  poss_end <- is_possession_end(tt, sp, shp)
  off_marker <- is_offensive_marker(tt, shp)

  timeouts <- which(tt == "Full Timeout")
  if (length(timeouts) == 0) return(NULL)

  out <- list()
  for (ti in timeouts) {
    if (ti >= n) next

    # Find the first event after the timeout that reveals who has the ball
    j <- ti + 1
    off_team <- NA_character_
    while (j <= n && tt[j] != "End Period" && tt[j] != "End Game") {
      if (off_marker[j] && !is.na(a1[j]) && !is.na(team_of[a1[j]])) {
        off_team <- unname(team_of[a1[j]])
        break
      }
      j <- j + 1
    }
    if (is.na(off_team) || !(off_team %in% c(home_ab, away_ab))) next

    # Walk the possession to its first ending event
    k <- j
    while (k <= n && !poss_end[k]) k <- k + 1
    k <- min(k, n)

    span <- j:k
    scored <- sp[span] & !is.na(g$score_value[span])
    if (!any(scored)) {
      pts <- 0
    } else {
      # Credit only points put up by the team in possession
      scorer_team <- vapply(span, function(r) {
        if (is.na(a1[r])) return(NA_character_)
        tm <- team_of[a1[r]]
        if (is.na(tm)) NA_character_ else unname(tm)
      }, character(1))
      pts <- sum(g$score_value[span][scored & scorer_team[seq_along(span)] == off_team],
                 na.rm = TRUE)
    }

    def_team <- if (off_team == home_ab) away_ab else home_ab

    out[[length(out) + 1]] <- data.frame(
      game_id = as.character(g$game_id[1]),
      season = g$season[1],
      period = g$period_number[ti],
      team = c(off_team, def_team),
      event_type = c("ato_offense", "ato_defense"),
      points = c(pts, pts),
      possessions = c(1, 1),
      challenge_won = c(NA, NA),
      stringsAsFactors = FALSE
    )
  }

  if (length(out) == 0) return(NULL)
  do.call(rbind, out)
}

# ------------------------------------------------------------------------------
# Challenge extraction (vectorised across all games)
# ------------------------------------------------------------------------------
# "Overturned" means the challenging coach won. "Stands" and "Supported" both mean
# the original call survived, i.e. the challenge failed. "replaycenter" rows state
# no outcome and are excluded rather than guessed.
extract_challenges <- function(pbp) {
  ch <- pbp %>%
    filter(grepl("Coach's Challenge", type_text)) %>%
    filter(!grepl("replaycenter", type_text, ignore.case = TRUE))
  if (nrow(ch) == 0) return(NULL)

  # The event text brackets the challenging team's mascot: "[Spurs] COACH'S CHALLENGE..."
  mascot <- sub("^.*?\\[([^]]+)\\].*$", "\\1", ch$text)
  team <- ifelse(mascot == ch$home_team_mascot, fix_abbr(ch$home_team_abbrev),
                 ifelse(mascot == ch$away_team_mascot, fix_abbr(ch$away_team_abbrev),
                        NA_character_))
  # Fall back to team_id where the bracket is absent or unmatched
  team <- ifelse(!is.na(team), team,
                 ifelse(!is.na(ch$team_id) & ch$team_id == ch$home_team_id,
                        fix_abbr(ch$home_team_abbrev),
                        ifelse(!is.na(ch$team_id) & ch$team_id == ch$away_team_id,
                               fix_abbr(ch$away_team_abbrev), NA_character_)))

  won <- grepl("Overturned", ch$type_text, ignore.case = TRUE)

  res <- data.frame(
    game_id = as.character(ch$game_id),
    season = ch$season,
    period = ch$period_number,
    team = team,
    event_type = "challenge",
    points = NA_real_,
    possessions = NA_real_,
    challenge_won = won,
    stringsAsFactors = FALSE
  )
  res[!is.na(res$team) & !(res$team %in% NON_TEAM_ABBRS), ]
}

# ------------------------------------------------------------------------------
# Driver
# ------------------------------------------------------------------------------
build_tactical_dataset <- function() {
  frames <- lapply(TACTICAL_SEASONS, function(sn)
    load_cached_season(sn, "nba_pbp", hoopR::load_nba_pbp, "play-by-play"))
  frames <- Filter(Negate(is.null), frames)
  if (length(frames) == 0) stop("No play-by-play available; cannot build pbp_timeout_cache.rds.")
  pbp <- bind_rows(frames)
  pbp$game_id <- as.character(pbp$game_id)
  pbp <- pbp[!is.na(pbp$game_play_number) & !is.na(pbp$period_number), ]

  rosters <- load_player_teams(TACTICAL_SEASONS)
  if (is.null(rosters)) stop("No player box data available; cannot attribute possessions.")
  roster_by_game <- split(rosters, rosters$game_id)

  split_games <- split(pbp, pbp$game_id)
  message(sprintf(">>> [TACTICAL] Scanning %s games for after-timeout possessions...",
                  format(length(split_games), big.mark = ",")))

  ato_list <- vector("list", length(split_games))
  for (k in seq_along(split_games)) {
    gid <- names(split_games)[k]
    ato_list[[k]] <- tryCatch(extract_game_atos(split_games[[k]], roster_by_game[[gid]]),
                              error = function(e) NULL)
    if (k %% 250 == 0) message(sprintf("    ... %d / %d games", k, length(split_games)))
  }
  atos <- bind_rows(ato_list)
  challenges <- extract_challenges(pbp)

  events <- bind_rows(atos, challenges)
  if (nrow(events) == 0) stop("Play-by-play parsed but produced no tactical events.")

  out_path <- file.path(.cache_dir, "pbp_timeout_cache.rds")
  saveRDS(events, out_path)

  n_off <- sum(events$event_type == "ato_offense")
  n_ch <- sum(events$event_type == "challenge")
  message(sprintf(">>> [TACTICAL] Extracted %s ATO possessions and %s challenge outcomes across %d teams.",
                  format(n_off, big.mark = ","), format(n_ch, big.mark = ","),
                  length(unique(events$team))))
  if (n_off > 0) {
    lg_ppp <- sum(events$points[events$event_type == "ato_offense"]) / n_off
    message(sprintf(">>> [TACTICAL] League ATO efficiency: %.3f points per possession.", lg_ppp))
  }
  if (n_ch > 0) {
    message(sprintf(">>> [TACTICAL] League challenge success rate: %.1f%%.",
                    mean(events$challenge_won[events$event_type == "challenge"]) * 100))
  }
  message(sprintf(">>> [TACTICAL] Saved to %s.", out_path))
  invisible(events)
}

if (!interactive()) {
  invisible(build_tactical_dataset())
}
