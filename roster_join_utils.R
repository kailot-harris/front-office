# ==============================================================================
# roster_join_utils.R
# Shared utility for joining active rosters, box scores, and ratings
# Path: c:/Users/kailo/kayceeslices/front-office/NBA Analytics/roster_join_utils.R
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
})

source("config.R")

#' Normalize player names for robust cross-table joins
normalize_player_name <- function(x) {
  x <- tolower(trimws(x))
  x <- gsub("[^a-z ]", "", x)
  x <- gsub("\\s+", " ", x)
  x
}

#' Join two datasets by ID with fallback by normalized name
join_by_id_then_name <- function(left_df, right_df, 
                                 id_col_left = "player_id", 
                                 id_col_right = "athlete_id",
                                 name_col_left = "player_name", 
                                 name_col_right = "athlete_display_name",
                                 suffix_cols = NULL) {
  if (is.null(left_df) || nrow(left_df) == 0) return(left_df)
  if (is.null(right_df) || nrow(right_df) == 0) return(left_df)

  # Coerce IDs to integer for reliable joining
  left_work <- left_df
  right_work <- right_df
  left_work[[id_col_left]] <- suppressWarnings(as.integer(left_work[[id_col_left]]))
  right_work[[id_col_right]] <- suppressWarnings(as.integer(right_work[[id_col_right]]))

  # Primary join on integer IDs
  by_id <- c()
  by_id[id_col_left] <- id_col_right
  joined <- left_join(left_work, right_work, by = by_id)

  # Identify rows where right-side data was not matched
  check_col <- if (!is.null(suffix_cols) && length(suffix_cols) > 0) suffix_cols[1] else setdiff(names(right_df), id_col_right)[1]
  unmatched_idx <- which(is.na(joined[[check_col]]))

  # Secondary fallback join by normalized player name
  if (length(unmatched_idx) > 0 && name_col_left %in% names(left_df) && name_col_right %in% names(right_df)) {
    left_unmatched <- left_work[unmatched_idx, ]
    left_unmatched$.norm_name <- normalize_player_name(left_unmatched[[name_col_left]])
    
    right_dedup <- right_work
    right_dedup$.norm_name <- normalize_player_name(right_dedup[[name_col_right]])
    right_dedup <- right_dedup |> 
      filter(!is.na(.norm_name), .norm_name != "") |> 
      distinct(.norm_name, .keep_all = TRUE)

    by_name <- c(".norm_name" = ".norm_name")
    fallback_joined <- left_join(left_unmatched, right_dedup |> select(-all_of(id_col_right)), by = by_name) |>
      select(-".norm_name")

    # Replace unmatched rows with fallback results
    cols_to_update <- intersect(names(joined), names(fallback_joined))
    joined[unmatched_idx, cols_to_update] <- fallback_joined[, cols_to_update]
  }

  return(joined)
}

#' Build calibrated 8-man primary rotation table per team from live roster cache and box scores
build_real_rotation_table <- function(rosters = NULL, player_box = NULL, rotation_size = 8) {
  roster_path <- if (exists("CACHE_ACTIVE_ROSTERS")) CACHE_ACTIVE_ROSTERS else file.path(CACHE_DIR, "active_rosters_cache.rds")
  box_path    <- if (exists("CACHE_PLAYER_BOX")) CACHE_PLAYER_BOX else file.path(CACHE_DIR, "player_box_scores_cache.rds")
  
  if (is.null(rosters)) {
    if (file.exists(roster_path)) {
      rosters <- tryCatch(readRDS(roster_path), error = function(e) NULL)
    }
  }

  # Fail-safe check: fall back to calibrated synthetic roster if cache missing or empty
  if (is.null(rosters) || nrow(rosters) == 0) {
    message(">>> [WARN] Using SYNTHETIC_FALLBACK rotation: active roster cache missing or unreadable.")
    teams <- c("BOS", "MIL", "DEN", "OKC", "MIN", "NYK", "PHI", "CLE", "IND", "ORL",
               "MIA", "LAL", "GSW", "PHX", "DAL", "LAC", "SAC", "NOP", "HOU", "CHI",
               "ATL", "BKN", "TOR", "MEM", "UTA", "SAS", "POR", "CHA", "WAS", "DET")
    synthetic_rosters <- bind_rows(lapply(teams, function(tm) {
      tibble(
        player_name = paste0(tm, " Player ", seq_len(rotation_size)),
        team = tm,
        pts_mu = head(c(26.5, 20.2, 16.4, 13.8, 11.2, 9.5, 7.8, 6.2), rotation_size),
        reb_mu = head(c(7.8, 8.4, 5.2, 4.1, 5.5, 3.2, 2.9, 2.4), rotation_size),
        ast_mu = head(c(6.5, 4.2, 3.8, 2.9, 1.8, 2.1, 1.4, 1.1), rotation_size),
        fg3m_mu = head(c(3.1, 2.4, 1.8, 1.6, 1.2, 1.0, 0.7, 0.5), rotation_size),
        stl_mu = head(c(1.3, 1.1, 0.9, 0.8, 0.7, 0.6, 0.4, 0.4), rotation_size),
        blk_mu = head(c(1.2, 0.8, 0.6, 0.5, 0.4, 0.3, 0.2, 0.2), rotation_size),
        avg_min = head(c(35.0, 33.0, 30.0, 28.0, 25.0, 22.0, 18.0, 15.0), rotation_size),
        data_source = "SYNTHETIC_FALLBACK"
      )
    }))
    return(synthetic_rosters)
  }

  if (is.null(player_box)) {
    if (file.exists(box_path)) {
      player_box <- tryCatch(readRDS(box_path), error = function(e) NULL)
    }
  }

  if (is.null(player_box) || nrow(player_box) == 0) {
    message(">>> [WARN] Using SYNTHETIC_FALLBACK stat priors: player box score cache missing.")
    # Assign position-based priors to real roster names
    rosters <- rosters |>
      mutate(
        team = team_name,
        pts_mu = 12.0, reb_mu = 4.5, ast_mu = 2.5, fg3m_mu = 1.0, stl_mu = 0.8, blk_mu = 0.5,
        avg_min = 20.0, data_source = "SYNTHETIC_PRIORS"
      )
    return(rosters)
  }

  curr_season <- if (exists("CURRENT_SEASON")) CURRENT_SEASON else 2026

  # 1. Current Season Per-Game Production
  cur_stats <- player_box |>
    filter(season == curr_season, !is.na(athlete_id), minutes > 0) |>
    group_by(athlete_id) |>
    summarise(
      games        = n(),
      pts_mu       = mean(points, na.rm = TRUE),
      reb_mu       = mean(rebounds, na.rm = TRUE),
      ast_mu       = mean(assists, na.rm = TRUE),
      fg3m_mu      = mean(three_point_field_goals_made, na.rm = TRUE),
      stl_mu       = mean(steals, na.rm = TRUE),
      blk_mu       = mean(blocks, na.rm = TRUE),
      avg_min      = mean(minutes, na.rm = TRUE),
      athlete_name = last(athlete_display_name),
      .groups      = "drop"
    )

  # 2. Historical Per-Game Fallback
  hist_stats <- player_box |>
    filter(!is.na(athlete_id), minutes > 0) |>
    group_by(athlete_id) |>
    summarise(
      games_hist   = n(),
      pts_mu_h     = mean(points, na.rm = TRUE),
      reb_mu_h     = mean(rebounds, na.rm = TRUE),
      ast_mu_h     = mean(assists, na.rm = TRUE),
      fg3m_mu_h    = mean(three_point_field_goals_made, na.rm = TRUE),
      stl_mu_h     = mean(steals, na.rm = TRUE),
      blk_mu_h     = mean(blocks, na.rm = TRUE),
      avg_min_h    = mean(minutes, na.rm = TRUE),
      athlete_name = last(athlete_display_name),
      .groups      = "drop"
    )

  # 3. Team abbreviation map from box scores
  #
  # Use every season in the cache, not just CURRENT_SEASON. During the offseason
  # (or any point before the new season's first box score lands) the current-season
  # slice is empty, which previously left this map with zero rows and made
  # `coalesce(team_abbreviation, team_name)` fall back to full names ("Lakers").
  # That silently changed the public player-projection team key from "LAL" to
  # "Lakers" and broke every cross-dataset join. Take the most recent abbreviation
  # observed for each franchise instead.
  team_map <- player_box |>
    filter(!is.na(team_abbreviation),
           !team_name %in% c("World", "Team Stars", "Team Stripes", "All-Stars")) |>
    select(team_name, team_abbreviation, season) |>
    arrange(desc(season)) |>
    distinct(team_name, .keep_all = TRUE) |>
    select(team_name, team_abbreviation)

  # 4. Join Roster with current season stats
  joined_cur <- join_by_id_then_name(
    left_df = rosters |> mutate(player_id = as.integer(player_id)),
    right_df = cur_stats,
    id_col_left = "player_id",
    id_col_right = "athlete_id",
    name_col_left = "player_name",
    name_col_right = "athlete_name",
    suffix_cols = "pts_mu"
  )

  # 5. Fallback join with historical stats for players with no current-season box scores
  joined_full <- join_by_id_then_name(
    left_df = joined_cur,
    right_df = hist_stats,
    id_col_left = "player_id",
    id_col_right = "athlete_id",
    name_col_left = "player_name",
    name_col_right = "athlete_name",
    suffix_cols = "pts_mu_h"
  )

  # join_by_id_then_name() returns its left side untouched when the right side is
  # empty, so a season with no box scores yet (e.g. the offseason, before any
  # CURRENT_SEASON games land in the cache) leaves the stat columns absent entirely
  # rather than present-and-NA. Materialize them as NA so the coalesce chain below
  # still resolves -- otherwise `case_when(!is.na(pts_mu) ...)` errors with
  # "object 'pts_mu' not found" instead of falling through to historical stats.
  expected_stat_cols <- c(
    "pts_mu", "reb_mu", "ast_mu", "fg3m_mu", "stl_mu", "blk_mu", "avg_min",
    "pts_mu_h", "reb_mu_h", "ast_mu_h", "fg3m_mu_h", "stl_mu_h", "blk_mu_h", "avg_min_h"
  )
  for (col in setdiff(expected_stat_cols, names(joined_full))) {
    joined_full[[col]] <- NA_real_
  }

  # 6. Reconcile stats & impute bench priors for true rookies
  matched_rosters <- joined_full |>
    left_join(team_map, by = "team_name") |>
    mutate(
      data_source = case_when(
        !is.na(pts_mu)   ~ "REAL_CURRENT_SEASON",
        !is.na(pts_mu_h) ~ "REAL_HISTORICAL_FALLBACK",
        TRUE             ~ "ROOKIE_BENCH_PRIOR"
      ),
      pts_mu  = coalesce(pts_mu, pts_mu_h, 6.0),
      reb_mu  = coalesce(reb_mu, reb_mu_h, 2.5),
      ast_mu  = coalesce(ast_mu, ast_mu_h, 1.5),
      fg3m_mu = coalesce(fg3m_mu, fg3m_mu_h, 0.5),
      stl_mu  = coalesce(stl_mu, stl_mu_h, 0.5),
      blk_mu  = coalesce(blk_mu, blk_mu_h, 0.3),
      avg_min = coalesce(avg_min, avg_min_h, 10.0),
      team    = coalesce(team_abbreviation, team_name)
    )

  # 7. Select top rotation players per team by playing time
  rotation_table <- matched_rosters |>
    group_by(team) |>
    arrange(desc(avg_min), .by_group = TRUE) |>
    slice_head(n = rotation_size) |>
    ungroup() |>
    select(player_name, team, pts_mu, reb_mu, ast_mu, fg3m_mu, stl_mu, blk_mu, avg_min, data_source)

  return(rotation_table)
}
