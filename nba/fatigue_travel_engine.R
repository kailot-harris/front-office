# ==============================================================================
# fatigue_travel_engine.R
# Phase 5: Circadian Rhythm, Altitude & Haversine Travel Vector Engine
#
# LIBRARY FILE. This file defines ARENA_DB and calculate_travel_fatigue() and
# does nothing when sourced. It used to be a pipeline stage that also exported a
# slate table to cache/travel_fatigue_metrics.rds; nothing ever read that file
# and nothing wrote the schedule it needed (NBA_analytics#155), so the stage was
# removed. The real consumers - build_matchups_dataset.R and
# tools/project_week_predictions.R - source this file and call
# calculate_travel_fatigue() on the full schedule they already hold.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

if (file.exists("config.R")) source("config.R")

# ------------------------------------------------------------------------------
# 1. Arena Geographic & Elevation Coordinates
# ------------------------------------------------------------------------------
ARENA_DB <- tibble(
  team = c("BOS", "BKN", "NYK", "PHI", "TOR", "CHI", "CLE", "DET", "IND", "MIL",
           "ATL", "CHA", "MIA", "ORL", "WAS", "DEN", "MIN", "OKC", "POR", "UTA",
           "GSW", "LAC", "LAL", "PHX", "SAC", "DAL", "HOU", "MEM", "NOP", "SAS"),
  lat = c(42.3662, 40.6826, 40.7505, 39.9012, 43.6435, 41.8807, 41.4965, 42.3411, 39.7640, 43.0451,
          33.7573, 35.2251, 25.7814, 28.5392, 38.8982, 39.7487, 44.9795, 35.4634, 45.5316, 40.7683,
          37.7680, 34.0430, 34.0430, 33.4457, 38.6491, 32.7905, 29.7508, 35.1382, 29.9490, 29.4270),
  lon = c(-71.0621, -73.9754, -73.9934, -75.1720, -79.3791, -87.6742, -81.6882, -83.0553, -86.1555, -87.9174,
          -84.3963, -80.8392, -80.1870, -81.3839, -77.0209, -105.0077, -93.2761, -97.5151, -122.6668, -111.9011,
          -122.3877, -118.2673, -118.2673, -112.0712, -121.4997, -96.8103, -95.3621, -90.0505, -90.0821, -98.4375),
  timezone_offset = c(-5, -5, -5, -5, -5, -6, -5, -5, -5, -6,
                      -5, -5, -5, -5, -5, -7, -6, -6, -8, -7,
                      -8, -8, -8, -7, -8, -6, -6, -6, -6, -6),
  altitude_ft = c(141, 56, 33, 39, 251, 597, 653, 600, 715, 617,
                  1020, 751, 6, 82, 25, 5280, 830, 1201, 50, 4226,
                  10, 233, 233, 1086, 30, 430, 80, 337, 3, 650)
)

# ESPN's abbreviations for six clubs differ from ARENA_DB's (NBA_analytics#156).
# Same set as ESPN_ABBR_FIXUPS in build_matchups_dataset.R; callers that already
# canonicalise pass codes straight through unchanged.
ESPN_TO_ARENA_CODE <- c(GS = "GSW", SA = "SAS", NY = "NYK", UTAH = "UTA", NO = "NOP", WSH = "WAS")
arena_code <- function(x) {
  x <- as.character(x)
  hit <- !is.na(x) & x %in% names(ESPN_TO_ARENA_CODE)
  x[hit] <- unname(ESPN_TO_ARENA_CODE[x[hit]])
  x
}
.fatigue_warned_codes <- new.env(parent = emptyenv())

# ------------------------------------------------------------------------------
# 2. Haversine Great-Circle Distance (Miles)
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
# 3. Micro-Rest & Fatigue Rating Calculator
# ------------------------------------------------------------------------------
calculate_travel_fatigue <- function(team_code, origin_team_code, days_rest = 1, is_back_to_back = FALSE) {
  orig <- ARENA_DB %>% filter(team == arena_code(origin_team_code))
  dest <- ARENA_DB %>% filter(team == arena_code(team_code))
  
  # An arena we cannot place is a gap in the data, not a zero: return NA in the
  # same shape as a found row and say so once per code, never error (#156).
  if (nrow(orig) == 0L || nrow(dest) == 0L) {
    for (code in unique(c(if (nrow(orig) == 0L) as.character(origin_team_code),
                          if (nrow(dest) == 0L) as.character(team_code)))) {
      if (!isTRUE(.fatigue_warned_codes[[code]])) {
        assign(code, TRUE, envir = .fatigue_warned_codes)
        message(sprintf(">>> [WARN] fatigue: team code '%s' is not in ARENA_DB (even after ESPN aliasing); travel fatigue is NA for games involving it.", code))
      }
    }
    return(list(travel_miles = NA_real_, timezone_shift = NA_real_,
                destination_elevation = NA_real_, fatigue_drag_pts = NA_real_))
  }
  
  # Flight Distance
  miles <- haversine_dist_miles(orig$lat, orig$lon, dest$lat, dest$lon)
  
  # Timezone Shift: Traveling East is harder on body clock than traveling West
  tz_shift <- dest$timezone_offset - orig$timezone_offset
  circadian_tax <- ifelse(tz_shift > 0, tz_shift * 0.35, abs(tz_shift) * 0.15)
  
  # Altitude Tax (e.g. traveling into Denver 5280 ft or Utah 4226 ft)
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
