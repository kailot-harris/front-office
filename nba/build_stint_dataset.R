# ==============================================================================
# build_stint_dataset.R
# Extracts stint-level lineup data from ESPN play-by-play for rapm_engine.R.
#
# A "stint" is a span of play during which both five-man lineups are unchanged.
# Stints are cut at every substitution and at every period boundary.
#
# Output: cache/stint_lineups.rds, one row per (stint x player on floor), matching
# the schema rapm_engine.R documents in STINT_REQUIRED_COLS:
#   stint_id, player_id, team, is_home, possessions, net_points
# plus player_name, game_id, game_date, period and season for traceability.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(hoopR)
})

if (file.exists("config.R")) source("config.R")
.cache_dir <- if (exists("CACHE_DIR")) CACHE_DIR else "cache"
if (!dir.exists(.cache_dir)) dir.create(.cache_dir, recursive = TRUE)

message(">>> [STINTS] Building stint-level lineup dataset from play-by-play...")

# Seasons to pool. RAPM needs volume, so the current season is backfilled with the
# prior one exactly as shot_quality_engine.R does for its rolling window.
.current_season <- if (exists("CURRENT_SEASON")) CURRENT_SEASON else 2027
STINT_SEASONS <- as.integer(Sys.getenv("STINT_SEASONS", paste(c(.current_season, .current_season - 1), collapse = ",")) |>
                              strsplit(",") |> unlist())

ESPN_ABBR_FIXUPS <- c(GS = "GSW", SA = "SAS", NY = "NYK", UTAH = "UTA",
                      NO = "NOP", WSH = "WAS")
NON_TEAM_ABBRS <- c("EAST", "WEST", "USA", "WORLD", "STARS", "STRIPES")

fix_abbr <- function(x) {
  x <- as.character(x)
  ifelse(x %in% names(ESPN_ABBR_FIXUPS), ESPN_ABBR_FIXUPS[x], x)
}

# ------------------------------------------------------------------------------
# Play-by-play ingestion (cached per season)
# ------------------------------------------------------------------------------
load_pbp <- function(seasons) {
  frames <- list()
  for (sn in seasons) {
    pbp_cache <- file.path(.cache_dir, sprintf("nba_pbp_%d.rds", sn))
    got <- NULL
    if (file.exists(pbp_cache)) {
      got <- tryCatch(readRDS(pbp_cache), error = function(e) NULL)
      if (!is.null(got) && nrow(got) > 0) {
        message(sprintf(">>> [STINTS] Loaded season %d play-by-play from cache (%s rows).",
                        sn, format(nrow(got), big.mark = ",")))
      } else got <- NULL
    }
    if (is.null(got)) {
      message(sprintf(">>> [STINTS] Fetching season %d play-by-play via hoopR...", sn))
      got <- tryCatch({
        p <- hoopR::load_nba_pbp(seasons = sn)
        if (!is.null(p) && nrow(p) > 0) saveRDS(p, pbp_cache)
        p
      }, error = function(e) {
        message(sprintf(">>> [WARN] hoopR pbp fetch failed for season %d: %s", sn, conditionMessage(e)))
        NULL
      })
    }
    if (!is.null(got) && nrow(got) > 0) frames[[length(frames) + 1]] <- as.data.frame(got)
  }
  if (length(frames) == 0) return(NULL)
  bind_rows(frames)
}

# ------------------------------------------------------------------------------
# Authoritative player -> team mapping
# ------------------------------------------------------------------------------
# Event `team_id` is NOT reliably the acting player's team: on fouls, goaltending
# and kicked-ball violations it can name the opponent, which silently assigns
# players to the wrong side of the ridge design. The player box score states each
# athlete's team per game directly, so side assignment comes from there instead.
load_player_teams <- function(seasons) {
  frames <- list()
  for (sn in seasons) {
    box_cache <- file.path(.cache_dir, sprintf("nba_player_box_%d.rds", sn))
    got <- NULL
    if (file.exists(box_cache)) {
      got <- tryCatch(readRDS(box_cache), error = function(e) NULL)
      if (!is.null(got) && nrow(got) > 0) {
        message(sprintf(">>> [STINTS] Loaded season %d player box from cache (%s rows).",
                        sn, format(nrow(got), big.mark = ",")))
      } else got <- NULL
    }
    if (is.null(got)) {
      message(sprintf(">>> [STINTS] Fetching season %d player box via hoopR...", sn))
      got <- tryCatch({
        b <- hoopR::load_nba_player_box(seasons = sn)
        if (!is.null(b) && nrow(b) > 0) saveRDS(b, box_cache)
        b
      }, error = function(e) {
        message(sprintf(">>> [WARN] hoopR player box fetch failed for season %d: %s", sn, conditionMessage(e)))
        NULL
      })
    }
    if (!is.null(got) && nrow(got) > 0) frames[[length(frames) + 1]] <- as.data.frame(got)
  }
  if (length(frames) == 0) return(NULL)

  bind_rows(frames) %>%
    filter(!is.na(athlete_id), !is.na(team_abbreviation)) %>%
    transmute(
      game_id = as.character(game_id),
      player_id = as.character(athlete_id),
      team = fix_abbr(team_abbreviation),
      is_home = tolower(as.character(home_away)) == "home",
      starter = as.logical(starter)
    ) %>%
    distinct(game_id, player_id, .keep_all = TRUE)
}

# ------------------------------------------------------------------------------
# Possession estimation
# ------------------------------------------------------------------------------
# Standard estimator over a span of play, summed across both teams and halved:
#   poss = FGA + 0.44*FTA + TOV - OREB
# Free throws are weighted 0.44 because only some FT trips end a possession.
IS_FT <- function(tt) grepl("Free Throw", tt, fixed = FALSE)

span_possessions <- function(type_text, shooting_play) {
  ft <- IS_FT(type_text)
  fga <- sum(shooting_play & !ft, na.rm = TRUE)
  fta <- sum(ft, na.rm = TRUE)
  tov <- sum(grepl("Turnover", type_text), na.rm = TRUE)
  oreb <- sum(type_text == "Offensive Rebound", na.rm = TRUE)
  max(0, (fga + 0.44 * fta + tov - oreb) / 2)
}

# ------------------------------------------------------------------------------
# Per-game stint extraction
# ------------------------------------------------------------------------------
extract_game_stints <- function(g, roster) {
  g <- g[order(g$game_play_number), ]
  n <- nrow(g)
  if (n < 10) return(NULL)

  home_ab <- fix_abbr(g$home_team_abbrev[1])
  away_ab <- fix_abbr(g$away_team_abbrev[1])
  if (home_ab %in% NON_TEAM_ABBRS || away_ab %in% NON_TEAM_ABBRS) return(NULL)
  if (is.null(roster) || nrow(roster) == 0) return(NULL)

  # player_id -> TRUE if on the home side, straight from the box score
  side_of <- setNames(roster$is_home, roster$player_id)

  is_sub <- g$type_text == "Substitution"
  a1 <- as.character(g$athlete_id_1)
  a2 <- as.character(g$athlete_id_2)

  # Running score is post-event, so the score entering row i is the score at i-1.
  pre_home <- c(0, g$home_score[-n])
  pre_away <- c(0, g$away_score[-n])

  name_map <- c(
    setNames(as.character(g$athlete_name_1), a1),
    setNames(as.character(g$athlete_name_2), a2)
  )
  name_map <- name_map[!is.na(names(name_map))]

  stints <- list()

  for (p in unique(g$period_number)) {
    idx <- which(g$period_number == p)
    if (length(idx) < 3) next

    # --- Infer who was on the floor when the period began ---------------------
    # A player who records an event, or is substituted OUT, before having been
    # substituted IN during this period must have started the period on court.
    entered <- character(0)
    start_home <- character(0)
    start_away <- character(0)

    for (i in idx) {
      if (is_sub[i]) {
        out_p <- a2[i]
        if (!is.na(out_p) && !(out_p %in% entered) && !is.na(side_of[out_p])) {
          if (side_of[[out_p]]) start_home <- union(start_home, out_p)
          else start_away <- union(start_away, out_p)
        }
        if (!is.na(a1[i])) entered <- union(entered, a1[i])
      } else {
        act <- a1[i]
        if (!is.na(act) && !(act %in% entered) && !is.na(side_of[act])) {
          if (side_of[[act]]) start_home <- union(start_home, act)
          else start_away <- union(start_away, act)
        }
      }
    }

    # Lineups we cannot pin to exactly five are dropped rather than guessed.
    if (length(start_home) != 5 || length(start_away) != 5) next

    home5 <- start_home
    away5 <- start_away

    emit <- function(from, to) {
      if (to < from) return(NULL)
      rows <- from:to
      poss <- span_possessions(g$type_text[rows], g$shooting_play[rows])
      if (poss <= 0) return(NULL)
      net <- (g$home_score[to] - pre_home[from]) - (g$away_score[to] - pre_away[from])
      list(poss = poss, net = net, home5 = home5, away5 = away5, period = p)
    }

    i <- idx[1]
    last <- idx[length(idx)]
    stint_start <- i
    while (i <= last) {
      if (is_sub[i]) {
        st <- emit(stint_start, i - 1)
        if (!is.null(st)) stints[[length(stints) + 1]] <- st
        # Apply every substitution in this dead-ball run before reopening
        j <- i
        while (j <= last && is_sub[j]) {
          p_in <- a1[j]; p_out <- a2[j]
          # Guard against a feed glitch substituting in a player already on the
          # floor, which would place the same column twice in one stint's design row.
          if (!is.na(p_in) && !is.na(p_out) && !is.na(side_of[p_in])) {
            if (side_of[[p_in]]) {
              if (p_out %in% home5 && !(p_in %in% home5)) home5 <- c(setdiff(home5, p_out), p_in)
            } else {
              if (p_out %in% away5 && !(p_in %in% away5)) away5 <- c(setdiff(away5, p_out), p_in)
            }
          }
          j <- j + 1
        }
        stint_start <- j
        i <- j
      } else {
        i <- i + 1
      }
    }
    st <- emit(stint_start, last)
    if (!is.null(st)) stints[[length(stints) + 1]] <- st
  }

  if (length(stints) == 0) return(NULL)

  # Only stints with two complete, non-overlapping five-man lineups are usable by
  # the ridge design: a repeated player would mean one column counted twice.
  stints <- Filter(function(s) {
    length(s$home5) == 5 && length(s$away5) == 5 &&
      !anyDuplicated(c(s$home5, s$away5))
  }, stints)
  if (length(stints) == 0) return(NULL)

  do.call(rbind, lapply(seq_along(stints), function(k) {
    s <- stints[[k]]
    players <- c(s$home5, s$away5)
    data.frame(
      game_id = g$game_id[1],
      game_date = g$game_date[1],
      season = g$season[1],
      period = s$period,
      local_stint = k,
      player_id = players,
      player_name = unname(name_map[players]),
      team = c(rep(home_ab, 5), rep(away_ab, 5)),
      is_home = c(rep(TRUE, 5), rep(FALSE, 5)),
      possessions = s$poss,
      net_points = s$net,
      stringsAsFactors = FALSE
    )
  }))
}

# ------------------------------------------------------------------------------
# Driver
# ------------------------------------------------------------------------------
build_stint_dataset <- function() {
  pbp <- load_pbp(STINT_SEASONS)
  if (is.null(pbp)) stop("No play-by-play available; cannot build stint_lineups.rds.")

  rosters <- load_player_teams(STINT_SEASONS)
  if (is.null(rosters)) stop("No player box data available; cannot assign players to teams.")
  roster_by_game <- split(rosters, rosters$game_id)

  pbp <- pbp[!is.na(pbp$game_play_number) & !is.na(pbp$period_number), ]
  pbp$game_id <- as.character(pbp$game_id)
  game_ids <- unique(pbp$game_id)
  message(sprintf(">>> [STINTS] Parsing %s games across seasons %s...",
                  format(length(game_ids), big.mark = ","),
                  paste(STINT_SEASONS, collapse = ", ")))

  split_games <- split(pbp, pbp$game_id)
  results <- vector("list", length(split_games))
  done <- 0L
  for (k in seq_along(split_games)) {
    gid <- names(split_games)[k]
    results[[k]] <- tryCatch(extract_game_stints(split_games[[k]], roster_by_game[[gid]]),
                             error = function(e) NULL)
    done <- done + 1L
    if (done %% 250 == 0) message(sprintf("    ... %d / %d games", done, length(split_games)))
  }

  parsed <- bind_rows(results)
  if (nrow(parsed) == 0) stop("Play-by-play parsed but produced no usable stints.")

  # Globally unique stint ids across games
  parsed <- parsed %>%
    mutate(stint_key = paste(game_id, period, local_stint, sep = "-")) %>%
    mutate(stint_id = as.integer(factor(stint_key))) %>%
    select(stint_id, player_id, player_name, team, is_home, possessions, net_points,
           game_id, game_date, season, period)

  n_stints <- length(unique(parsed$stint_id))
  n_games <- length(unique(parsed$game_id))
  coverage <- n_games / length(game_ids)

  # Independent check: the first stint of period 1 is the opening lineup, which the
  # box score reports directly. Agreement here is evidence the substitution replay
  # is tracking the floor correctly rather than drifting.
  opening <- parsed %>%
    filter(period == 1) %>%
    group_by(game_id) %>%
    filter(stint_id == min(stint_id)) %>%
    ungroup() %>%
    select(game_id, player_id)
  box_starters <- rosters %>% filter(starter) %>% select(game_id, player_id)
  agree <- opening %>%
    inner_join(box_starters %>% mutate(is_box_starter = TRUE),
               by = c("game_id", "player_id"))
  starter_rate <- if (nrow(opening) > 0) nrow(agree) / nrow(opening) else NA_real_
  message(sprintf(">>> [STINTS] Opening-lineup check: %.1f%% of inferred period-1 starters match the box score starter flag.",
                  starter_rate * 100))

  out_path <- file.path(.cache_dir, "stint_lineups.rds")
  saveRDS(parsed, out_path)

  message(sprintf(">>> [STINTS] Extracted %s stints over %d games (%.1f%% of games yielded usable lineups).",
                  format(n_stints, big.mark = ","), n_games, coverage * 100))
  message(sprintf(">>> [STINTS] %s player-stint rows, %d distinct players, median %.1f possessions/stint.",
                  format(nrow(parsed), big.mark = ","),
                  length(unique(parsed$player_id)),
                  median(parsed$possessions)))
  message(sprintf(">>> [STINTS] Saved to %s.", out_path))
  invisible(parsed)
}

if (!interactive()) {
  invisible(build_stint_dataset())
}
