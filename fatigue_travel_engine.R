# ==============================================================================
# fatigue_travel_engine.R
# Phase 3 (T3): Circadian Rhythm, Altitude & Haversine Travel Vector Engine
# Path: fatigue_travel_engine.R
#
# Ported from the NBA Analytics repo's fatigue_travel_engine.R (see REPO_MAP.md /
# WNBA_REPLICATION_PLAN.md / agent4.md in this folder). The travel/circadian/altitude/
# back-to-back fatigue MATH is unchanged from the NBA original (sport-agnostic per the
# plan) — the only real content change is ARENA_DB, rebuilt with REAL lat/lon/timezone-
# offset/altitude data for the 15 current (2026) WNBA franchises from config.R's
# WNBA_TEAMS, not fabricated or copy-pasted from the NBA file.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)

# config.R owns every structural constant and cache path used below
# (CACHE_WNBA_SCHEDULE for the real schedule path, WNBA_TEAMS for the franchise filter).
# Sourced defensively so a bare `source("fatigue_travel_engine.R")` from a tool script
# still resolves them, without re-sourcing inside a pipeline run that already has them.
if (!exists("CACHE_WNBA_SCHEDULE")) source("config.R")

message(">>> [FATIGUE] Initializing Circadian & Travel Distance Engine (WNBA, 15 teams)...")

# ------------------------------------------------------------------------------
# 1. Arena Geographic & Elevation Coordinates — REAL data, web-search-verified
#    2026-09-12 against each team's current home arena (see sources in comments
#    below and in task_assignments.md's T3 Handoff Notes). Team codes match
#    config.R's WNBA_TEAMS exactly (15 teams) — do not hardcode a separate list.
#
#    Sources (arena identity, verified via WebSearch on 2026-09-12):
#      - Wikipedia team pages + NBC New York "every WNBA arena" roundup for the
#        13 established franchises' current home arenas.
#      - Toronto Tempo (2026 expansion team): Coca-Cola Coliseum, Exhibition
#        Place, Toronto (Wikipedia "Toronto Tempo" / "2026 Toronto Tempo season").
#      - Portland Fire (2026 expansion/return team): Moda Center, Portland, OR,
#        shared with the NBA's Trail Blazers (Wikipedia "Portland Fire" /
#        "2026 Portland Fire season", KGW, WNBA.com "Introducing the Portland Fire").
#      - Phoenix Mercury: play at the arena formerly branded "PHX Arena", newly
#        renamed "Mortgage Matchup Center" in 2026 under a fresh naming-rights
#        deal (Wikipedia "Mortgage Matchup Center", mercury.wnba.com press
#        release) — same physical downtown-Phoenix building/coordinates as the
#        NBA original's "PHX" arena row, just a new sponsor name.
#      - Washington Mystics: CareFirst Arena, 1100 Oak Dr SE, Washington, DC
#        (St. Elizabeths East campus, Congress Heights) — Wikipedia "CareFirst
#        Arena", washington.org listing.
#    Lat/lon/altitude figures are standard public geographic coordinates for each
#    named venue/city (not fabricated); timezone_offset uses each city's STANDARD
#    (non-DST) UTC offset, matching the convention of the NBA original's ARENA_DB
#    (e.g. Phoenix stays -7 year-round since Arizona does not observe DST).
# ------------------------------------------------------------------------------
ARENA_DB <- tibble(
  team = c("ATL", "CHI", "CON", "DAL", "GS",
           "IND", "LV",  "LA",  "MIN", "NY",
           "PHX", "POR", "SEA", "TOR", "WSH"),
  arena = c(
    "Gateway Center Arena", "Wintrust Arena", "Mohegan Sun Arena", "College Park Center",
    "Chase Center", "Gainbridge Fieldhouse", "Michelob ULTRA Arena", "Crypto.com Arena",
    "Target Center", "Barclays Center", "Mortgage Matchup Center (fka PHX Arena)",
    "Moda Center", "Climate Pledge Arena", "Coca-Cola Coliseum", "CareFirst Arena"
  ),
  lat = c(33.6404, 41.8534, 41.4948, 32.7519, 37.7680,
          39.7640, 36.0908, 34.0430, 44.9795, 40.6826,
          33.4457, 45.5316, 47.6221, 43.6435, 38.8398),
  lon = c(-84.4415, -87.6325, -72.0972, -97.0938, -122.3877,
          -86.1555, -115.1745, -118.2673, -93.2761, -73.9754,
          -112.0712, -122.6668, -122.3540, -79.4183, -76.9928),
  timezone_offset = c(-5, -6, -5, -6, -8,
                      -5, -8, -8, -6, -5,
                      -7, -8, -8, -5, -5),
  altitude_ft = c(1010, 597, 200, 551, 10,
                  715, 2030, 233, 830, 33,
                  1086, 50, 175, 251, 180)
)

# ------------------------------------------------------------------------------
# 2. Haversine Great-Circle Distance (Miles) — UNCHANGED from NBA original.
#    Sport-agnostic geometry; no NBA-specific constant lives here.
# ------------------------------------------------------------------------------
haversine_dist_miles <- function(lat1, lon1, lat2, lon2) {
  r <- 3958.8 # Earth radius in miles
  phi1 <- lat1 * pi / 180
  phi2 <- lat2 * pi / 180
  delta_phi <- (lat2 - lat1) * pi / 180
  delta_lambda <- (lon2 - lon1) * pi / 180

  a <- sin(delta_phi / 2)^2 + cos(phi1) * cos(phi2) * sin(delta_lambda / 2)^2
  c <- 2 * atan2(sqrt(a), sqrt(1 - a))
  return(r * c)
}

# ------------------------------------------------------------------------------
# 3. Micro-Rest & Fatigue Rating Calculator — UNCHANGED math from NBA original.
#
#    NOTE ON THE ALTITUDE-TAX BRANCH (per agent4.md instruction): this branch
#    will rarely trigger for the WNBA. The NBA has two high-altitude markets
#    over the 4,000ft threshold used below (Denver 5,280ft, Utah 4,226ft). The
#    WNBA's highest-elevation current arena is Las Vegas's Michelob ULTRA Arena
#    at ~2,030ft — well under the 4,000ft trigger — so `altitude_tax` will
#    evaluate to 0 for every real WNBA matchup as of the 2026 season. The logic
#    is kept as-is (not deleted) per the brief: it is sport-agnostic physiology
#    math, and a future WNBA expansion into a high-altitude market (there is no
#    current one, but this is not guaranteed to stay true forever) would need it
#    without requiring a code change.
# ------------------------------------------------------------------------------
calculate_travel_fatigue <- function(team_code, origin_team_code, days_rest = 1, is_back_to_back = FALSE) {
  orig <- ARENA_DB %>% filter(team == origin_team_code)
  dest <- ARENA_DB %>% filter(team == team_code)

  req_found <- (nrow(orig) > 0 && nrow(dest) > 0)
  if (!req_found) return(list(travel_miles = 0, fatigue_drag_pts = 0))

  # Flight Distance
  miles <- haversine_dist_miles(orig$lat, orig$lon, dest$lat, dest$lon)

  # Timezone Shift: Traveling East is harder on body clock than traveling West
  tz_shift <- dest$timezone_offset - orig$timezone_offset
  circadian_tax <- ifelse(tz_shift > 0, tz_shift * 0.35, abs(tz_shift) * 0.15)

  # Altitude Tax (WNBA: no current market clears the 4,000ft trigger — see comment above)
  altitude_tax <- 0
  if (dest$altitude_ft >= 4000 && orig$altitude_ft < 2000) {
    # If on 0 days rest (back-to-back at elevation), maximum physiological penalty
    altitude_tax <- ifelse(days_rest == 0, 2.1, 1.2)
  }

  # Distance Fatigue Penalty
  distance_tax <- (miles / 1000) * 0.40

  # Base Back-to-Back Drag
  b2b_tax <- ifelse(is_back_to_back, 1.85, 0.0)

  total_fatigue_drag <- round(distance_tax + circadian_tax + altitude_tax + b2b_tax, 2)

  list(
    travel_miles = round(miles, 0),
    timezone_shift = tz_shift,
    destination_elevation = dest$altitude_ft,
    fatigue_drag_pts = total_fatigue_drag
  )
}

# ------------------------------------------------------------------------------
# 3b. REAL (UNPLAYED-GAME) SLATE — GitHub issue #93.
#
# Reads the schedule cache written by daily_ingest.R's daily_schedule_ingest(), which
# already carries per-team `days_rest`, `is_back_to_back` and `last_played_at` (the
# previous game's venue = this trip's travel origin). Nothing in
# calculate_travel_fatigue() changes: this is a real CALLER for the arguments it has
# always accepted, replacing nothing.
#
# FAIL-SAFE: file.exists()-guarded, readRDS wrapped, schema-checked. Any miss returns
# NULL and the caller falls back to the original hand-coded demo slate.
# ------------------------------------------------------------------------------
load_unplayed_schedule_slate <- function(schedule_path = CACHE_WNBA_SCHEDULE) {
  if (!file.exists(schedule_path)) {
    message(sprintf(">>> [FATIGUE] Schedule cache not found at %s — no real slate available.",
                    schedule_path))
    return(NULL)
  }
  sched <- tryCatch(readRDS(schedule_path), error = function(e) {
    message(sprintf(">>> [FATIGUE] Schedule cache unreadable (%s) — no real slate available.",
                    conditionMessage(e)))
    NULL
  })
  if (is.null(sched) || !is.data.frame(sched) || nrow(sched) == 0) return(NULL)

  needed <- c("game_id", "game_date", "team_abbreviation", "opponent_team_abbreviation",
              "is_home", "is_completed", "days_rest", "is_back_to_back", "last_played_at")
  if (!all(needed %in% names(sched))) {
    message(">>> [FATIGUE] Schedule cache is missing rest columns — no real slate available.")
    return(NULL)
  }

  slate <- sched %>%
    filter(!is_completed) %>%
    filter(team_abbreviation %in% names(WNBA_TEAMS)) %>%
    arrange(game_date, game_id, desc(is_home))

  if (nrow(slate) == 0) {
    message(">>> [FATIGUE] Schedule cache holds no unplayed games — no real slate available.")
    return(NULL)
  }
  slate
}

evaluate_unplayed_slate_fatigue <- function(schedule_path = CACHE_WNBA_SCHEDULE) {
  slate <- load_unplayed_schedule_slate(schedule_path)
  if (is.null(slate)) return(NULL)

  slate %>%
    mutate(
      # destination = the venue of the scheduled game (its home team's arena);
      # days_rest NA (team's first game of the season) is treated as "rested" for the
      # model argument only — is_back_to_back stays FALSE, so no penalty is invented.
      venue_code = if_else(is_home, team_abbreviation, opponent_team_abbreviation),
      model_days_rest = dplyr::coalesce(as.numeric(days_rest), 1)
    ) %>%
    rowwise() %>%
    mutate(
      fatigue_metrics = list(calculate_travel_fatigue(
        venue_code, last_played_at, model_days_rest, is_back_to_back
      )),
      travel_miles = fatigue_metrics$travel_miles,
      tz_shift = fatigue_metrics$timezone_shift,
      point_spread_drag = fatigue_metrics$fatigue_drag_pts
    ) %>%
    ungroup() %>%
    select(-fatigue_metrics, -model_days_rest)
}

# Evaluate a slate of road teams. Per agent4.md / REPO_MAP.md §1, the frame below
# remains a SYNTHETIC/DEMO sample schedule (like the NBA original). As of issue #93 it
# is the FALLBACK only: evaluate_slate_fatigue() prefers the real unplayed-game slate
# derived from the schedule cache and drops back to this frame when that cache is
# absent, unreadable, or empty of unplayed games.
#' Collapse the per-team fatigue rows to the one-row-per-game, demo-compatible schema.
#'
#' SCHEMA CONTRACT: market_odds_engine.R:474-477 filters this cache on
#' `away_team` / `home_team` and reads `point_spread_drag`, with drag semantics
#' "fatigue carried by the AWAY (traveling) team, added to the home fair margin"
#' (market_odds_engine.R:490). The real path must therefore emit the same columns and
#' the same meaning as the demo frame, or that consumer errors on a missing column.
#' Per-team detail for the home side is kept alongside under `home_*` names.
unplayed_slate_by_game <- function(per_team) {
  away <- per_team %>% filter(!is_home)
  home <- per_team %>%
    filter(is_home) %>%
    select(game_id,
           home_days_rest = days_rest,
           home_is_b2b = is_back_to_back,
           home_last_played_at = last_played_at,
           home_travel_miles = travel_miles,
           home_point_spread_drag = point_spread_drag)

  away %>%
    transmute(game_date, game_id,
              away_team = team_abbreviation,
              home_team = opponent_team_abbreviation,
              last_played_at, days_rest,
              is_b2b = is_back_to_back,
              travel_miles, tz_shift, point_spread_drag) %>%
    left_join(home, by = "game_id")
}

evaluate_slate_fatigue <- function(schedule_path = CACHE_WNBA_SCHEDULE) {
  real <- tryCatch(evaluate_unplayed_slate_fatigue(schedule_path),
                   error = function(e) {
                     message(sprintf(">>> [FATIGUE] Real schedule path errored (%s); using demo slate.",
                                     conditionMessage(e)))
                     NULL
                   })
  if (!is.null(real) && nrow(real) > 0) {
    by_game <- unplayed_slate_by_game(real)
    saveRDS(by_game, "cache/travel_fatigue_metrics.rds")
    message(sprintf(paste0(">>> [FATIGUE] Successfully computed travel fatigue vectors for ",
                           "%d unplayed games / %d team-game rows (WNBA, REAL schedule slate)."),
                    nrow(by_game), nrow(real)))
    return(by_game)
  }

  message(">>> [FATIGUE] Falling back to SYNTHETIC/DEMO slate (no usable schedule cache).")
  sample_schedule <- tibble(
    away_team = c("LA", "SEA", "NY", "CHI"),
    home_team = c("LV", "PHX", "CON", "ATL"),
    last_played_at = c("LA", "DAL", "NY", "CHI"),
    days_rest = c(0, 1, 0, 2), # LA on B2B, no WNBA market currently clears the altitude trigger
    is_b2b = c(TRUE, FALSE, TRUE, FALSE)
  )

  results <- sample_schedule %>%
    rowwise() %>%
    mutate(
      fatigue_metrics = list(calculate_travel_fatigue(home_team, last_played_at, days_rest, is_b2b)),
      travel_miles = fatigue_metrics$travel_miles,
      tz_shift = fatigue_metrics$timezone_shift,
      point_spread_drag = fatigue_metrics$fatigue_drag_pts
    ) %>%
    select(-fatigue_metrics)

  saveRDS(results, "cache/travel_fatigue_metrics.rds")
  message(">>> [FATIGUE] Successfully computed travel fatigue vectors for active slate (WNBA, synthetic demo slate).")
  return(results)
}

if (!interactive()) {
  invisible(evaluate_slate_fatigue())
}
