# ==============================================================================
# fatigue_travel_engine.R
# Phase 3 (T3): Circadian Rhythm, Altitude & Haversine Travel Vector Engine
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/fatigue_travel_engine.R
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

# Evaluate a slate of road teams. Per agent4.md / REPO_MAP.md §1, this remains a
# SYNTHETIC/DEMO sample schedule (like the NBA original) — no real WNBA schedule
# feed is wired into this script. Swapped in 4 real 2026 WNBA team codes.
evaluate_slate_fatigue <- function() {
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
