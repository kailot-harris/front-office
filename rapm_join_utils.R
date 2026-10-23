# ==============================================================================
# rapm_join_utils.R (WNBA)
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/rapm_join_utils.R
#
# Single source of truth for joining `cache/rapm_ratings.rds` to
# `cache/active_rosters_cache.rds`.
#
# GitHub issue #91:
# Upgraded to use cross-source player ID crosswalk (espn_athlete_id <-> wnba_player_id)
# as the PRIMARY join key, recovering all 21 players previously dropped due to
# ambiguous surnames or trades (e.g. Alanna Smith, NaLyssa Smith, Natasha Howard,
# Gabby Williams, Alysha Clark, Haley Jones, Nyara Sabally, Isabelle Harrison).
#
# Fail-safe: if the crosswalk is unavailable or a player is not in it, falls back
# to the proven (team_name, normalized last_name) join with deterministic collision
# resolution by possession plurality.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
})

if (file.exists("config.R")) source("config.R")
if (file.exists("player_id_crosswalk.R")) source("player_id_crosswalk.R")

# Normalize a roster-style full name ("Nneka Ogwumike") down to the join key that
# matches rapm_ratings.rds's last-name-only `player_name` ("Ogwumike").
# Handles hyphenated names and compound names like "Van Lith" / "Diggins-Smith".
normalize_rapm_last_name <- function(x, from_full_name = TRUE) {
  if (from_full_name) {
    # Check for compound prefix like "Van Lith"
    x <- ifelse(grepl("\\bvan\\s+", x, ignore.case = TRUE),
                sub(".*\\b(van\\s+\\S+).*", "\\1", x, ignore.case = TRUE),
                word(x, -1))
  }
  tolower(trimws(gsub("[^a-zA-Z ]", "", x)))
}

#' Join RAPM ratings onto an active-roster table.
#'
#' @param rost Roster data frame (schema of `cache/active_rosters_cache.rds`):
#'   requires `team_abbreviation`, `team_name`, `player_id`, `player_name`.
#' @param rapm RAPM data frame (schema of `cache/rapm_ratings.rds`):
#'   requires `team`, `player_name`, `total_rapm` (and optionally `orapm`,
#'   `drapm`, `n_off_poss`, `n_def_poss`, `low_sample_flag`).
#' @param matched_only If TRUE (default) return only roster players that matched a
#'   RAPM row — inner-join semantics. If FALSE, return every roster row with
#'   RAPM columns NA-filled (left-join semantics) plus `rapm_matched`.
#' @param use_crosswalk If TRUE (default), use player ID crosswalk (Issue #91)
#'   as primary join key before surname fallback. If FALSE, use purely the
#'   legacy (team_name, normalized last_name) join.
#' @param crosswalk Optional pre-loaded player ID crosswalk data frame. If NULL,
#'   attempts to load via load_player_id_crosswalk().
#'
#' @return A data frame with ONE ROW PER ROSTER PLAYER, keyed by
#'   (`team_abbreviation`, `player_id`) — `player_id` here is always the roster/ESPN
#'   ID — carrying at least `total_rapm`. Also returned: `team_name`, `player_name`
#'   (roster full name), `last_name` (the join key), `rapm_player_id`,
#'   `rapm_matched`, `rapm_ambiguous`, `rapm_match_method`, and whichever of
#'   `orapm`/`drapm`/`n_off_poss`/`n_def_poss`/`low_sample_flag` exist on `rapm`.
#'
#' Fail-safe per repo convention: a missing/NULL/empty input or a missing required
#' column produces a warning and a zero-row frame of the right shape, never an error.
join_rapm_to_roster <- function(rost, rapm, matched_only = TRUE, use_crosswalk = TRUE, crosswalk = NULL) {

  empty_result <- function() {
    tibble(
      team_abbreviation = character(0), team_name = character(0),
      player_id = integer(0), player_name = character(0), last_name = character(0),
      rapm_player_id = character(0), total_rapm = numeric(0),
      rapm_matched = logical(0), rapm_ambiguous = logical(0),
      rapm_match_method = character(0)
    )
  }

  if (is.null(rost) || is.null(rapm) || !is.data.frame(rost) || !is.data.frame(rapm) ||
      nrow(rost) == 0 || nrow(rapm) == 0) {
    warning("join_rapm_to_roster(): empty or non-data.frame input; returning 0 rows.")
    return(empty_result())
  }

  need_rost <- c("team_abbreviation", "team_name", "player_id", "player_name")
  need_rapm <- c("team", "player_name", "total_rapm")
  missing_r <- setdiff(need_rost, names(rost))
  missing_p <- setdiff(need_rapm, names(rapm))
  if (length(missing_r) || length(missing_p)) {
    warning(sprintf(
      "join_rapm_to_roster(): missing columns (roster: %s | rapm: %s); returning 0 rows.",
      paste(missing_r, collapse = ","), paste(missing_p, collapse = ",")))
    return(empty_result())
  }

  # --- roster side: full name -> normalized last name -------------------------
  r <- rost |>
    mutate(
      last_name = normalize_rapm_last_name(.data$player_name, from_full_name = TRUE),
      .espn_id  = as.character(.data$player_id)
    )

  # --- rapm side: ensure player_id is character and last_name exists ----------
  keep_cols <- intersect(c("orapm", "drapm", "n_off_poss", "n_def_poss", "low_sample_flag"),
                         names(rapm))
  p <- rapm |>
    mutate(
      .rapm_id  = as.character(.data$player_id),
      last_name = normalize_rapm_last_name(.data$player_name, from_full_name = FALSE)
    )

  # --- PRIMARY PATH: Cross-source Player ID Crosswalk (#91) -------------------
  matched_by_id <- FALSE
  if (isTRUE(use_crosswalk)) {
    cw_df <- crosswalk
    if (is.null(cw_df)) {
      cw_df <- tryCatch({
        if (exists("load_player_id_crosswalk", mode = "function")) {
          load_player_id_crosswalk()
        } else if (exists("CACHE_PLAYER_ID_CROSSWALK") && file.exists(CACHE_PLAYER_ID_CROSSWALK)) {
          readRDS(CACHE_PLAYER_ID_CROSSWALK)
        } else {
          NULL
        }
      }, error = function(e) NULL)
    }

    if (!is.null(cw_df) && is.data.frame(cw_df) &&
        all(c("espn_athlete_id", "wnba_player_id") %in% names(cw_df)) && nrow(cw_df) > 0) {

      cw_map <- cw_df |>
        filter(!is.na(.data$espn_athlete_id), !is.na(.data$wnba_player_id),
               .data$espn_athlete_id != "", .data$wnba_player_id != "") |>
        mutate(
          espn_athlete_id = as.character(.data$espn_athlete_id),
          wnba_player_id  = as.character(.data$wnba_player_id)
        ) |>
        distinct(.data$espn_athlete_id, .keep_all = TRUE) |>
        select("espn_athlete_id", "wnba_player_id")

      p_select <- p |>
        select(all_of(c(".rapm_id", "total_rapm", keep_cols))) |>
        distinct(.data$.rapm_id, .keep_all = TRUE)

      r_id_join <- r |>
        left_join(cw_map, by = c(".espn_id" = "espn_athlete_id")) |>
        left_join(p_select, by = c("wnba_player_id" = ".rapm_id"))

      # If ID join succeeded in matching rows, use it as base
      if (any(!is.na(r_id_join$total_rapm))) {
        matched_by_id <- TRUE
        r_joined <- r_id_join |>
          mutate(
            rapm_player_id    = coalesce(.data$wnba_player_id, NA_character_),
            rapm_matched      = !is.na(.data$total_rapm),
            rapm_ambiguous    = FALSE, # ID join is unambiguous
            rapm_match_method = if_else(.data$rapm_matched, "id_crosswalk", NA_character_)
          ) |>
          select(-"wnba_player_id")
      }
    }
  }

  if (!matched_by_id) {
    # Initialize un-joined frame
    r_joined <- r |>
      mutate(
        rapm_player_id    = NA_character_,
        total_rapm        = NA_real_,
        rapm_matched      = FALSE,
        rapm_ambiguous    = FALSE,
        rapm_match_method = NA_character_
      )
    for (col in keep_cols) {
      r_joined[[col]] <- if (is.logical(rapm[[col]])) NA else NA_real_
    }
  }

  # --- FALLBACK PATH: (team_name, normalized last_name) for unmatched rows ---
  unmatched_mask <- !r_joined$rapm_matched
  if (any(unmatched_mask)) {
    poss <- function(df) {
      o <- if ("n_off_poss" %in% names(df)) coalesce(as.numeric(df$n_off_poss), 0) else 0
      d <- if ("n_def_poss" %in% names(df)) coalesce(as.numeric(df$n_def_poss), 0) else 0
      o + d
    }

    p_fallback <- p |>
      mutate(.poss = poss(p)) |>
      group_by(.data$team, .data$last_name) |>
      mutate(.collision_ambig = n() > 1) |>
      arrange(desc(.data$.poss), desc(.data$total_rapm), .data$.rapm_id, .by_group = TRUE) |>
      slice(1) |>
      ungroup() |>
      select(all_of(c("team", "last_name", ".rapm_id", "total_rapm", ".collision_ambig", keep_cols)))

    r_unmatched <- r_joined[unmatched_mask, ]
    # Drop previous NA join columns before merging
    cols_to_drop <- intersect(c(".rapm_id", "rapm_player_id", "total_rapm", keep_cols), names(r_unmatched))
    r_unmatched_clean <- r_unmatched[, setdiff(names(r_unmatched), cols_to_drop)]

    r_fb_join <- r_unmatched_clean |>
      left_join(p_fallback, by = c("team_name" = "team", "last_name"))

    fb_matched <- !is.na(r_fb_join$total_rapm)
    r_fb_join <- r_fb_join |>
      mutate(
        rapm_player_id    = if_else(fb_matched, .data$.rapm_id, NA_character_),
        rapm_matched      = fb_matched,
        rapm_ambiguous    = if_else(fb_matched, coalesce(.data$.collision_ambig, FALSE), FALSE),
        rapm_match_method = if_else(fb_matched, "surname_team_fallback", NA_character_)
      )

    # Label remaining unmatched rows with diagnostic reason
    rapm_last_names <- unique(p$last_name)
    still_unmatched <- !r_fb_join$rapm_matched
    if (any(still_unmatched)) {
      r_fb_join$rapm_match_method[still_unmatched] <- if_else(
        r_fb_join$last_name[still_unmatched] %in% rapm_last_names,
        "unmatched_surname_in_rapm",
        "unmatched_no_data"
      )
    }

    # Clean temporary columns
    r_fb_join <- r_fb_join |> select(-any_of(c(".rapm_id", ".collision_ambig")))

    # Align columns and splice back
    all_cols <- union(names(r_joined), names(r_fb_join))
    for (c in setdiff(all_cols, names(r_joined))) r_joined[[c]] <- NA
    for (c in setdiff(all_cols, names(r_fb_join))) r_fb_join[[c]] <- NA

    r_joined[unmatched_mask, names(r_joined)] <- r_fb_join[, names(r_joined)]
  }

  # Clean internal helper columns
  out <- r_joined |>
    select(-any_of(c(".espn_id", ".rapm_id")))

  if (isTRUE(matched_only)) {
    out <- out |> filter(.data$rapm_matched)
  }

  standard_cols <- c("team_abbreviation", "team_name", "player_id", "player_name", "last_name",
                     "rapm_player_id", "total_rapm", "rapm_matched", "rapm_ambiguous", "rapm_match_method")
  other_cols <- setdiff(names(out), standard_cols)

  out |>
    relocate(all_of(standard_cols), all_of(other_cols))
}

invisible(NULL)
