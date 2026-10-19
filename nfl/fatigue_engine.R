# ==============================================================================
# fatigue_engine.R
# Phase 3, Task P3-A (docs/task_assignments_phase2.md, "Phase 3" doc despite the filename -
# see that doc's naming note). DAG stage: fatigue/embeddings (docs/NFL_REPLICATION_PLAN.md
# §1 order: ingest -> metrics -> ratings -> fatigue/embeddings -> market/props -> risk/notify
# -> live/dashboard).
#
# Computes REAL, schedule-driven fatigue metrics for every game in CACHE_SCHEDULES (played and
# upcoming) - unlike the WNBA Analytics sibling repo's fatigue_travel_engine.R, which is an
# explicitly-labeled SYNTHETIC/DEMO script (its own header/footer says so): it hardcodes a
# 4-row sample slate and never reads a real schedule feed. This repo has real CACHE_SCHEDULES
# data from Phase 1 (nflreadr::load_schedules(), 6,771 games, 2002-2026 seasons as of
# 2026-09-16), so there is no excuse to ship a toy example here. Every row of CACHE_SCHEDULES
# produces two real output rows (one per team) in CACHE_FATIGUE_METRICS.
#
# Two fatigue axes are computed:
#   1. Travel/circadian/altitude ("TRAVEL AXIS") - haversine great-circle distance + timezone-
#      shift circadian tax + high-altitude tax. Math PORTED LARGELY UNCHANGED from the WNBA
#      repo's fatigue_travel_engine.R (haversine_dist_miles(), the asymmetric eastward/westward
#      circadian_tax formula, and the altitude_tax shape) - this is sport-agnostic geometry and
#      human physiology, not WNBA-specific. The only real content changes are (a) a rebuilt,
#      live-verified 32-team NFL_STADIUM_DB (see its header below) in place of WNBA's ARENA_DB,
#      and (b) the altitude_tax branch actually FIRES for real NFL games now (Denver clears the
#      4,000ft threshold at 5,280ft - no WNBA market did), and (c) the "is_back_to_back" input
#      from the WNBA original (no NFL analog - teams play one game/week) is replaced by this
#      stage's own short_week flag (see axis 2) as the "elevated in-window fatigue" trigger.
#   2. Short-rest / bye-week ("REST AXIS") - NFL-specific, no WNBA analog, per
#      docs/NFL_REPLICATION_PLAN.md §4.2: real days-of-rest per team since its immediately
#      prior scheduled game, computed from actual gameday date arithmetic (not an assumed
#      "Thursday = short week" special case), a short_week flag, and an explicit off_bye /
#      season_opener flag for games with no valid prior-game gap. REST_DAYS_CAP (config.R,
#      previously unused) is this stage's first real consumer.
#
# Exposed function: run_fatigue_engine() - no required args, returns TRUE/FALSE.
# Output shape: LONG format, one row per (team, game) - i.e. two rows per CACHE_SCHEDULES game
# (home-team perspective + away-team perspective), because rest-days/short-week/travel-origin
# are properties of a TEAM's schedule sequence, not symmetric between the two teams in a game
# (e.g. the home team may be coming off a bye while the away team is on a short week in the very
# same game). Row count should be ~2x nrow(CACHE_SCHEDULES).
#
# `source("config.R")` / `source("logging_utils.R")` at top; `.LOG_SCRIPT <- "fatigue_engine.R"`.
# Per this repo's CLAUDE.md ("Process / conventions"), NO sys.nframe()/!interactive() auto-run
# footer - all five existing stages use call_fn-style explicit invocation by the orchestrator,
# and P3-B (run_full_pipeline.R) wires this stage in after this script lands.
# ==============================================================================

source("config.R")
source("logging_utils.R")

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

.LOG_SCRIPT <- "fatigue_engine.R"

# ------------------------------------------------------------------------------------------
# 1. NFL Stadium Geographic & Elevation Database - REAL data, web-search-verified 2026-09-16.
#    Team codes match config.R's NFL_TEAMS exactly (32 teams) - do not hardcode a separate list.
#    timezone_offset is each stadium's STANDARD (non-DST) UTC offset, matching the WNBA repo's
#    ARENA_DB convention (e.g. Arizona/Nevada stay on their standard offset year-round since
#    neither observes DST, so -7/-8 respectively is correct in both summer and winter for those
#    two states specifically; every other listed offset is the winter/standard value, which is
#    what the WNBA original used too - a documented, consistent simplification, not a bug).
#
#    SOURCES (all verified via live WebSearch on 2026-09-16, not recalled from training data -
#    stadium naming-rights deals and even franchise venues change year to year):
#      - SHARED STADIUMS, explicitly double-checked per this task's instructions:
#          * LA (Rams) and LAC (Chargers) both play at SoFi Stadium, Inglewood, CA - confirmed
#            current for the 2026 season (sofistadium.com's own 2026 Chargers-vs-Rams preseason
#            listing; joint Rams/Chargers tenancy still in effect as of 2026-09-16).
#          * NYG (Giants) and NYJ (Jets) both play at MetLife Stadium, East Rutherford, NJ -
#            confirmed current for 2026 (still one of only two two-team stadiums in the league).
#      - RECENTLY CHANGED VENUES/NAMES, found via live search and reflected below:
#          * BUF (Bills): brand-new "Highmark Stadium" opened June 2026 in Orchard Park, NY,
#            replacing the team's 50+ year-old former stadium on the same property (built just
#            across the street from the old site, per spectrumlocalnews.com's 2026-06-23
#            coverage) - coordinates below are for the new building's Orchard Park site, not the
#            demolished former stadium's exact former footprint.
#          * KC (Chiefs): stadium reverted to "Arrowhead Stadium" for the 2026 season, dropping
#            the "GEHA Field at" naming-rights prefix used since 2021 (Bleacher Report /
#            totalprosports.com, both 2026 coverage) - same physical building/coordinates.
#          * WAS (Commanders): current name is "Northwest Stadium" (Landover, MD) - the
#            franchise briefly used "Commanders Field" in early 2024 before the Northwest
#            Federal Credit Union naming deal was announced later that year; the team's planned
#            new RFK-site stadium does not open until ~2030, so 2026 is still Northwest Stadium
#            (nbcwashington.com, Wikipedia "Northwest Stadium", both checked 2026-09-16).
#          * TEN (Titans): the new enclosed "New Nissan Stadium" is still under construction
#            (on track for a February/summer 2027 opening per nfl.com and wsmv.com 2026
#            coverage) - the team plays the ENTIRE 2026 season at the old (still-standing)
#            Nissan Stadium in Nashville, which is what is listed below.
#          * CLE (Browns): current name is "Huntington Bank Field" (20-year naming-rights deal
#            announced Sept. 2024) - NOT "FirstEnergy Stadium", which the team's OWN new-stadium
#            project page/domain reuses for a different, not-yet-open Brook Park, OH facility
#            (dome.clevelandbrowns.com, targeted 2029) that must not be confused with the current
#            2026 Cleveland lakefront venue used below.
#          * PIT (Steelers): current name is "Acrisure Stadium" (renamed 2022, formerly Heinz
#            Field) - confirmed still current for 2026 via post-gazette.com's Feb. 2026 field-
#            resurfacing coverage of "Acrisure Stadium".
#          * NO (Saints): current name is "Caesars Superdome" (rebranded 2021, formerly
#            Mercedes-Benz Superdome / originally Louisiana Superdome) - confirmed current via
#            neworleanssaints.com's own 2026 stadium page.
#      - All other stadium identities (name, city) cross-checked against each team's current
#        stadium being unchanged from well-established, still-current venues (State Farm
#        Stadium/ARI, Mercedes-Benz Stadium/ATL, M&T Bank Stadium/BAL, Bank of America
#        Stadium/CAR, Soldier Field/CHI, Paycor Stadium/CIN, AT&T Stadium/DAL, Empower Field at
#        Mile High/DEN, Ford Field/DET, Lambeau Field/GB, NRG Stadium/HOU, Lucas Oil Stadium/IND,
#        EverBank Stadium/JAX, Allegiant Stadium/LV, Hard Rock Stadium/MIA, U.S. Bank
#        Stadium/MIN, Gillette Stadium/NE, Lincoln Financial Field/PHI, Lumen Field/SEA, Levi's
#        Stadium/SF, Raymond James Stadium/TB) - none of these had a 2026 naming-rights or venue
#        change surface in live search.
#      - Denver altitude double-checked per this task's instructions: Empower Field at Mile
#        High's own site (empowerfieldatmilehigh.com/stadium-information/about-us/elevation-
#        5280') confirms 5,280ft - clears the 4,000ft altitude_tax threshold used below (see
#        calculate_travel_fatigue()'s comment), unlike the WNBA repo where no market did.
#    Lat/lon/altitude figures are standard public geographic coordinates for each named venue
#    (not fabricated); altitude figures are approximate ground-level elevations in feet.
# ------------------------------------------------------------------------------------------
NFL_STADIUM_DB <- tibble(
  team = c("ARI","ATL","BAL","BUF","CAR","CHI","CIN","CLE","DAL","DEN",
           "DET","GB","HOU","IND","JAX","KC","LA","LAC","LV","MIA",
           "MIN","NE","NO","NYG","NYJ","PHI","PIT","SEA","SF","TB",
           "TEN","WAS"),
  stadium = c(
    "State Farm Stadium", "Mercedes-Benz Stadium", "M&T Bank Stadium", "Highmark Stadium (new, 2026)",
    "Bank of America Stadium", "Soldier Field", "Paycor Stadium", "Huntington Bank Field",
    "AT&T Stadium", "Empower Field at Mile High", "Ford Field", "Lambeau Field",
    "NRG Stadium", "Lucas Oil Stadium", "EverBank Stadium", "Arrowhead Stadium",
    "SoFi Stadium", "SoFi Stadium", "Allegiant Stadium", "Hard Rock Stadium",
    "U.S. Bank Stadium", "Gillette Stadium", "Caesars Superdome", "MetLife Stadium",
    "MetLife Stadium", "Lincoln Financial Field", "Acrisure Stadium", "Lumen Field",
    "Levi's Stadium", "Raymond James Stadium", "Nissan Stadium (old, through 2026)",
    "Northwest Stadium"
  ),
  lat = c(33.5276, 33.7554, 39.2780, 42.7738, 35.2258, 41.8623, 39.0955, 41.5061,
          32.7473, 39.7439, 42.3400, 44.5013, 29.6847, 39.7601, 30.3239, 39.0489,
          33.9535, 33.9535, 36.0909, 25.9580, 44.9735, 42.0909, 29.9511, 40.8135,
          40.8135, 39.9008, 40.4468, 47.5952, 37.4030, 27.9759, 36.1665, 38.9077),
  lon = c(-112.2626, -84.4008, -76.6227, -78.7867, -80.8528, -87.6167, -84.5160, -81.6995,
          -97.0945, -105.0201, -83.0456, -88.0622, -95.4107, -86.1639, -81.6373, -94.4839,
          -118.3392, -118.3392, -115.1833, -80.2389, -93.2575, -71.2643, -90.0812, -74.0745,
          -74.0745, -75.1675, -80.0158, -122.3316, -121.9700, -82.5033, -86.7713, -76.8645),
  timezone_offset = c(-7, -5, -5, -5, -5, -6, -5, -5,
                      -6, -7, -5, -6, -6, -5, -5, -6,
                      -8, -8, -8, -5, -6, -5, -6, -5,
                      -5, -5, -5, -8, -8, -5, -6, -5),
  altitude_ft = c(1132, 1050, 20, 630, 750, 595, 490, 605,
                  550, 5280, 600, 640, 40, 715, 16, 750,
                  125, 125, 2001, 7, 830, 200, 3, 7,
                  7, 40, 730, 15, 30, 13, 440, 110)
)
stopifnot(setequal(NFL_STADIUM_DB$team, names(NFL_TEAMS)))

# ------------------------------------------------------------------------------------------
# 1b. Historical-relocation stadium addendum. CACHE_SCHEDULES spans 2002-2026 and includes
#     franchise codes that predate a relocation and no longer appear in config.R's NFL_TEAMS
#     (verified live: OAK = Oakland Raiders pre-Las Vegas move, SD = San Diego Chargers pre-LA
#     move, STL = St. Louis Rams pre-LA move). These are NOT part of the current 32-team
#     NFL_STADIUM_DB above (which intentionally matches NFL_TEAMS exactly, per this task's
#     contract) - they exist only so historical games' travel/circadian math has a real origin/
#     destination site instead of silently going NA. Coordinates are the well-documented,
#     now-demolished/vacated former venues (not live-verified with the same web-search rigor as
#     the current 32 above, since these are closed venues rather than live 2026 naming-rights
#     facts that could have silently drifted) - approximate but geographically correct.
# ------------------------------------------------------------------------------------------
.HISTORICAL_STADIUM_DB <- tibble(
  team = c("OAK", "SD", "STL"),
  stadium = c("Oakland Coliseum", "Qualcomm Stadium", "Edward Jones Dome"),
  lat = c(37.7516, 32.7831, 38.6329),
  lon = c(-122.2005, -117.1195, -90.1886),
  timezone_offset = c(-8, -8, -6),
  altitude_ft = c(10, 20, 465)
)

.STADIUM_LOOKUP <- bind_rows(NFL_STADIUM_DB, .HISTORICAL_STADIUM_DB)

# ------------------------------------------------------------------------------------------
# 2. Haversine Great-Circle Distance (Miles) - UNCHANGED from the WNBA/NBA original.
#    Sport-agnostic geometry; no NFL-specific constant lives here.
# ------------------------------------------------------------------------------------------
haversine_dist_miles <- function(lat1, lon1, lat2, lon2) {
  r <- 3958.8 # Earth radius in miles
  phi1 <- lat1 * pi / 180
  phi2 <- lat2 * pi / 180
  delta_phi <- (lat2 - lat1) * pi / 180
  delta_lambda <- (lon2 - lon1) * pi / 180

  a <- sin(delta_phi / 2)^2 + cos(phi1) * cos(phi2) * sin(delta_lambda / 2)^2
  c <- 2 * atan2(sqrt(a), sqrt(1 - a))
  r * c
}

# Internal short-rest threshold: a standard NFL week is games 7 days apart (Sunday-to-Sunday).
# A team playing on <= 5 days' rest (e.g. Thursday after the prior Sunday = 4 days) is on a
# genuine short week. This is NOT a config.R constant because it is this script's own derived
# classification threshold for the short_week flag, not a shared modeling constant referenced
# elsewhere in the pipeline (unlike REST_DAYS_CAP, which config.R already owns and this script
# reuses rather than re-deriving).
.SHORT_WEEK_MAX_REST_DAYS <- 5
# A team coming off its bye typically jumps from ~7 days' rest to ~13-14 (one extra full week).
# 12 is used as the off-bye detection floor so real byes are always caught while still being
# comfortably below REST_DAYS_CAP.
.OFF_BYE_MIN_REST_DAYS <- 12

# ------------------------------------------------------------------------------------------
# 3. Travel/Circadian/Altitude fatigue calculator - math UNCHANGED in shape from the WNBA
#    original's calculate_travel_fatigue(); `is_back_to_back` is replaced by this stage's own
#    `short_week` flag as the "elevated fatigue trigger" input (see header note above).
# ------------------------------------------------------------------------------------------
calculate_travel_fatigue_vec <- function(dest_lat, dest_lon, dest_tz, dest_alt,
                                          orig_lat, orig_lon, orig_tz, orig_alt,
                                          short_week) {
  miles <- haversine_dist_miles(orig_lat, orig_lon, dest_lat, dest_lon)

  # Timezone shift: traveling EAST (positive shift) is harder on the body clock than West.
  tz_shift <- dest_tz - orig_tz
  circadian_tax <- ifelse(tz_shift > 0, tz_shift * 0.35, abs(tz_shift) * 0.15)

  # Altitude tax: fires for any dest stadium >= 4,000ft when the team is coming from < 2,000ft.
  # Denver's Empower Field at Mile High (5,280ft, live-verified above) clears this threshold, so
  # this branch DOES actually engage for real Denver home games, unlike the WNBA repo (no WNBA
  # market cleared 4,000ft as of that repo's verification). Elevated penalty on a short week,
  # mirroring the WNBA original's back-to-back elevated-penalty case.
  altitude_tax <- ifelse(
    !is.na(dest_alt) & !is.na(orig_alt) & dest_alt >= 4000 & orig_alt < 2000,
    ifelse(short_week, 2.1, 1.2),
    0
  )

  distance_tax <- (miles / 1000) * 0.40
  short_week_tax <- ifelse(short_week, 1.85, 0.0)

  total_fatigue_drag <- round(distance_tax + circadian_tax + altitude_tax + short_week_tax, 2)

  list(
    travel_miles = round(miles, 0),
    timezone_shift = tz_shift,
    destination_elevation = dest_alt,
    fatigue_drag_pts = total_fatigue_drag
  )
}

# ------------------------------------------------------------------------------------------
# 4. Main entry point.
# ------------------------------------------------------------------------------------------
run_fatigue_engine <- function() {
  tryCatch({
    if (!file.exists(CACHE_SCHEDULES)) {
      log_error("CACHE_SCHEDULES not found - run the ingest stage first.", schedules_path = CACHE_SCHEDULES)
      return(FALSE)
    }

    sched <- readRDS(CACHE_SCHEDULES)
    log_info("Loaded CACHE_SCHEDULES for fatigue engine.", rows = nrow(sched))

    if (nrow(sched) == 0) {
      log_error("CACHE_SCHEDULES is empty - nothing to compute.")
      return(FALSE)
    }

    sched <- sched %>%
      mutate(gameday = as.Date(gameday))

    if (any(is.na(sched$gameday))) {
      n_bad <- sum(is.na(sched$gameday))
      log_warn("Some games have NA gameday - these rows cannot get a real rest-days computation.",
               n_na_gameday = n_bad)
    }

    # ---- Long format: one row per (team, game) ----
    home_side <- sched %>%
      transmute(
        game_id, season, game_type, week, gameday, weekday,
        team = home_team, opponent = away_team, is_home = TRUE,
        site_team = home_team
      )
    away_side <- sched %>%
      transmute(
        game_id, season, game_type, week, gameday, weekday,
        team = away_team, opponent = home_team, is_home = FALSE,
        site_team = home_team
      )
    long <- bind_rows(home_side, away_side)

    # ---- Rest-days axis: real date arithmetic per team, sequential across a team's own games ----
    long <- long %>%
      arrange(team, gameday, week) %>%
      group_by(team) %>%
      mutate(
        prior_gameday   = lag(gameday),
        prior_season    = lag(season),
        prior_site_team = lag(site_team),
        # A team's first game of a season (real season boundary, not assumed week==1 - playoff
        # seeding/bye structure can shift Week 1 dates) OR its very first game in the data has no
        # valid prior-game gap.
        season_opener = is.na(prior_gameday) | season != prior_season,
        rest_days_raw = ifelse(season_opener, NA_real_, as.numeric(gameday - prior_gameday)),
        off_bye = !season_opener & !is.na(rest_days_raw) & rest_days_raw >= .OFF_BYE_MIN_REST_DAYS,
        short_week = !season_opener & !off_bye & !is.na(rest_days_raw) &
          rest_days_raw <= .SHORT_WEEK_MAX_REST_DAYS,
        extreme_rest_flag = !is.na(rest_days_raw) & rest_days_raw > REST_DAYS_CAP,
        rest_days = ifelse(is.na(rest_days_raw), NA_real_, pmin(rest_days_raw, REST_DAYS_CAP))
      ) %>%
      ungroup()

    # ---- Travel/circadian/altitude axis ----
    dest_idx <- match(long$site_team, .STADIUM_LOOKUP$team)
    orig_idx <- match(long$prior_site_team, .STADIUM_LOOKUP$team)

    n_missing_dest <- sum(is.na(dest_idx))
    n_missing_orig <- sum(is.na(orig_idx) & !long$season_opener)
    if (n_missing_dest > 0) {
      log_warn("Some game sites have no stadium DB match - travel metrics NA for those rows.",
               n_missing_dest = n_missing_dest)
    }
    if (n_missing_orig > 0) {
      log_warn("Some prior-game sites have no stadium DB match - travel metrics NA for those rows.",
               n_missing_orig = n_missing_orig)
    }

    fatigue <- calculate_travel_fatigue_vec(
      dest_lat = .STADIUM_LOOKUP$lat[dest_idx], dest_lon = .STADIUM_LOOKUP$lon[dest_idx],
      dest_tz  = .STADIUM_LOOKUP$timezone_offset[dest_idx], dest_alt = .STADIUM_LOOKUP$altitude_ft[dest_idx],
      orig_lat = .STADIUM_LOOKUP$lat[orig_idx], orig_lon = .STADIUM_LOOKUP$lon[orig_idx],
      orig_tz  = .STADIUM_LOOKUP$timezone_offset[orig_idx], orig_alt = .STADIUM_LOOKUP$altitude_ft[orig_idx],
      short_week = long$short_week
    )

    long$travel_miles          <- fatigue$travel_miles
    long$timezone_shift        <- fatigue$timezone_shift
    long$destination_elevation_ft <- fatigue$destination_elevation
    long$fatigue_drag_pts      <- fatigue$fatigue_drag_pts

    # Season openers have no real prior site, so travel is genuinely undefined - NA is correct,
    # not a computed (wrong) zero.
    long$travel_miles[long$season_opener]   <- NA_real_
    long$timezone_shift[long$season_opener] <- NA_real_
    long$fatigue_drag_pts[long$season_opener] <- NA_real_

    out <- long %>%
      select(
        game_id, season, game_type, week, gameday, weekday,
        team, opponent, is_home, site_team, prior_site_team,
        prior_gameday, rest_days_raw, rest_days, extreme_rest_flag,
        season_opener, off_bye, short_week,
        travel_miles, timezone_shift, destination_elevation_ft, fatigue_drag_pts
      ) %>%
      arrange(season, week, game_id, desc(is_home))

    saveRDS(out, CACHE_FATIGUE_METRICS)
    log_info("Fatigue engine completed and cache written.",
             rows = nrow(out), games = nrow(sched), path = CACHE_FATIGUE_METRICS)

    TRUE
  }, error = function(e) {
    log_error("run_fatigue_engine failed.", condition = e)
    FALSE
  })
}
