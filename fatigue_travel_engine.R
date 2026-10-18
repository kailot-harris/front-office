# ==============================================================================
# fatigue_travel_engine.R
# Phase 5: Circadian Rhythm, Altitude & Haversine Travel Vector Engine
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)

message(">>> [FATIGUE] Initializing Circadian & Travel Distance Engine...")

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
  orig <- ARENA_DB %>% filter(team == origin_team_code)
  dest <- ARENA_DB %>% filter(team == team_code)
  
  req_found <- (nrow(orig) > 0 && nrow(dest) > 0)
  if (!req_found) return(list(travel_miles = 0, fatigue_drag_pts = 0))
  
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

# Evaluate a slate of road teams
evaluate_slate_fatigue <- function() {
  sample_schedule <- tibble(
    away_team = c("LAL", "MIA", "GSW", "BOS"),
    home_team = c("DEN", "UTA", "NYK", "PHI"),
    last_played_at = c("LAL", "DAL", "GSW", "BOS"),
    days_rest = c(0, 1, 0, 2), # LAL on B2B playing at altitude in Denver
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
  message(">>> [FATIGUE] Successfully computed travel fatigue vectors for active slate.")
  return(results)
}

if (!interactive()) {
  invisible(evaluate_slate_fatigue())
}