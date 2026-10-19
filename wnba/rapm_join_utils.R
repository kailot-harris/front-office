# ==============================================================================
# rapm_join_utils.R (WNBA)
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/rapm_join_utils.R
#
# Single source of truth for joining `cache/rapm_ratings.rds` to
# `cache/active_rosters_cache.rds`.
#
# FINDING H-2 (docs/SECURITY_TECHNICAL_REVIEW.md): the two caches use INCOMPATIBLE
# player identifiers — `rapm_ratings.rds$player_id` is a stats-provider numeric ID
# stored as <character> (e.g. "201496"), while `active_rosters_cache.rds$player_id`
# is an ESPN athlete ID stored as <integer> (e.g. 869). There is ZERO overlap even
# after coercing to a common type, and as of the current caches dplyr refuses the
# join outright ("Can't join `x$player_id` with `y$player_id` due to incompatible
# types"), which hard-fails the player_props_engine.R stage nightly behind
# run_stage()'s fail-safe tryCatch.
#
# The working join — on (team full name, normalized last name) — was proven in
# market_odds_engine.R:104-115 (`calculate_matchup_delta()`) but existed in only
# that one of three call sites. This file extracts it so the next schema change
# breaks in one place instead of three. Per CLAUDE.md, do not reimplement this
# join anywhere else; call `join_rapm_to_roster()`.
#
# Consumers (wired up in Phase 4 Wave 2): market_odds_engine.R::calculate_matchup_delta(),
# player_props_engine.R::get_team_def_rapm(), roster_bottom_up_engine.R::compute_team_rapm_ratings().
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
})

# Normalize a roster-style full name ("Nneka Ogwumike") down to the join key that
# matches rapm_ratings.rds's last-name-only `player_name` ("Ogwumike").
# Kept byte-identical in behaviour to market_odds_engine.R:104's `norm_last()`.
normalize_rapm_last_name <- function(x, from_full_name = TRUE) {
  if (from_full_name) x <- word(x, -1)
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
#'   RAPM row — inner-join semantics, identical to the proven
#'   `calculate_matchup_delta()` behaviour. If FALSE, return every roster row with
#'   RAPM columns NA-filled (left-join semantics) plus `rapm_matched`.
#'
#' @return A data frame with ONE ROW PER ROSTER PLAYER, keyed by
#'   (`team_abbreviation`, `player_id`) — `player_id` here is always the roster/ESPN
#'   ID — carrying at least `total_rapm`. Also returned: `team_name`, `player_name`
#'   (roster full name), `last_name` (the join key), `rapm_player_id`,
#'   `rapm_matched`, `rapm_ambiguous`, and whichever of
#'   `orapm`/`drapm`/`n_off_poss`/`n_def_poss`/`low_sample_flag` exist on `rapm`.
#'
#' Fail-safe per repo convention: a missing/NULL/empty input or a missing required
#' column produces a warning and a zero-row frame of the right shape, never an error.
join_rapm_to_roster <- function(rost, rapm, matched_only = TRUE) {

  empty_result <- function() {
    tibble(
      team_abbreviation = character(0), team_name = character(0),
      player_id = integer(0), player_name = character(0), last_name = character(0),
      rapm_player_id = character(0), total_rapm = numeric(0),
      rapm_matched = logical(0), rapm_ambiguous = logical(0)
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
    mutate(last_name = normalize_rapm_last_name(.data$player_name, from_full_name = TRUE))

  # --- rapm side: player_name is ALREADY last-name-only ------------------------
  p <- rapm |>
    mutate(last_name = normalize_rapm_last_name(.data$player_name, from_full_name = FALSE))

  # --- COLLISION HANDLING (H-2) ------------------------------------------------
  # CLAUDE.md and market_odds_engine.R's comment describe this key as
  # "verified collision-free". That is true of the ROSTER side only (0 duplicate
  # (team_name, last_name) groups across all 209 rostered players — re-verified by
  # tools/test_phase4_foundation.R). It is NOT true of the RAPM side: rapm_ratings.rds
  # carries every player who logged possessions for a franchise, so it has 15 duplicate
  # (team, last_name) groups (e.g. both Ogwumike sisters on the Sparks, two "Jones" on
  # Connecticut). Left unhandled, the inner join FANS OUT — 121 matched roster players
  # became 128 joined rows — which is harmless for market_odds_engine's
  # "max total_rapm per team" use but silently double-counts in the possession-weighted
  # team aggregates in player_props_engine.R / roster_bottom_up_engine.R.
  #
  # Resolution: keep exactly one RAPM row per (team, last_name), choosing the row with
  # the most total possessions observed — the best available identity signal for "which
  # player of this surname is the one currently rostered" (it correctly resolves Nneka
  # over Chiney Ogwumike, Kelsey Mitchell, Jackie Young, Jonquel Jones). Ties are broken
  # deterministically by total_rapm then player_id so the result is stable run-to-run.
  # Affected rows are flagged `rapm_ambiguous = TRUE` so callers can audit them.
  poss <- function(df) {
    o <- if ("n_off_poss" %in% names(df)) coalesce(as.numeric(df$n_off_poss), 0) else 0
    d <- if ("n_def_poss" %in% names(df)) coalesce(as.numeric(df$n_def_poss), 0) else 0
    o + d
  }
  p <- p |>
    mutate(.poss = poss(p)) |>
    group_by(.data$team, .data$last_name) |>
    mutate(rapm_ambiguous = n() > 1) |>
    arrange(desc(.data$.poss), desc(.data$total_rapm), .data$player_id, .by_group = TRUE) |>
    slice(1) |>
    ungroup() |>
    select(-".poss")

  keep <- intersect(c("orapm", "drapm", "n_off_poss", "n_def_poss", "low_sample_flag"),
                    names(p))
  p <- p |>
    rename(rapm_player_id = "player_id") |>
    select(all_of(c("team", "last_name", "rapm_player_id", "total_rapm", "rapm_ambiguous", keep)))

  out <- r |>
    left_join(p, by = c("team_name" = "team", "last_name")) |>
    mutate(
      rapm_matched   = !is.na(.data$total_rapm),
      rapm_ambiguous = coalesce(.data$rapm_ambiguous, FALSE)
    )

  if (isTRUE(matched_only)) out <- out |> filter(.data$rapm_matched)

  out |>
    relocate("team_abbreviation", "team_name", "player_id", "player_name", "last_name",
             "rapm_player_id", "total_rapm", "rapm_matched", "rapm_ambiguous")
}

invisible(NULL)
