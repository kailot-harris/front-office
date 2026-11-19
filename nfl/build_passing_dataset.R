# ==============================================================================
# build_passing_dataset.R
# Extracts NFL NextGenStats-style QB passing charts and throw maps, calculates
# 12 discrete depth/horizontal zone baselines, and outputs chunked JSON files
# for the Next.js web application.
#
# Data window (front-office#109)
#   Seasons: one season, NFL_PASSING_SEASON (default CURRENT_SEASON = 2026),
#     read from exact single-season cache (CACHE_DNA_PBP / cache/nfl_pbp_<season>.rds)
#     and refreshed via nflreadr::load_pbp() when missing, stale (>12h), or forced.
#     No season-type filter: playoff games count if present.
#   Filters: pass plays with a passer id, recorded air yards, a left, middle or
#     right pass location, and a recorded completion result. Missing EPA counts
#     as 0.
#   Minimum sample: MIN_PASS_ATTEMPTS (15 such passes) for a QB to get a file.
#   Pipeline wiring: Stage 14.1 of run_full_pipeline.R via run_build_passing_dataset().
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
})

# ------------------------------------------------------------------------------
# 1. 12 Discrete Throw Zone Classification (top-level pure constants & helpers)
# ------------------------------------------------------------------------------
# Depths:
# - Behind LOS (< 0 air yards)
# - Short (0 <= air yards < 10)
# - Intermediate (10 <= air yards < 20)
# - Deep (air yards >= 20)
# Sectors: Left, Middle, Right
CANONICAL_ZONES <- c(
  "Deep Left",
  "Deep Middle",
  "Deep Right",
  "Intermediate Left",
  "Intermediate Middle",
  "Intermediate Right",
  "Short Left",
  "Short Middle",
  "Short Right",
  "Behind LOS Left",
  "Behind LOS Middle",
  "Behind LOS Right"
)

classify_12_zones <- function(air_yards, pass_loc) {
  if (is.na(air_yards) || is.na(pass_loc)) return(NA_character_)
  loc <- tolower(trimws(as.character(pass_loc)))
  if (!loc %in% c("left", "middle", "right")) return(NA_character_)

  depth <- if (air_yards < 0) {
    "Behind LOS"
  } else if (air_yards < 10) {
    "Short"
  } else if (air_yards < 20) {
    "Intermediate"
  } else {
    "Deep"
  }

  sector <- paste0(toupper(substr(loc, 1, 1)), substr(loc, 2, nchar(loc)))
  paste(depth, sector)
}

run_build_passing_dataset <- function(force_refresh = FALSE) {
  if (!exists("WEB_DATA_DIR") || !exists("CACHE_DIR")) {
    if (file.exists("config.R")) {
      source("config.R")
    }
  }

  default_season <- if (exists("CURRENT_SEASON")) as.character(CURRENT_SEASON) else "2026"
  PASSING_SEASON <- as.integer(Sys.getenv("NFL_PASSING_SEASON", default_season))
  cat(sprintf(">>> [PASSING CHARTS] Building passing dataset for season %d...\n", PASSING_SEASON))

  # 1. Load PBP data from exact single-season cache (refresh if missing or >12h old)
  cache_dir <- if (exists("CACHE_DIR")) CACHE_DIR else "cache"
  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)
  pbp_cache_path <- if (exists("CACHE_DNA_PBP") && exists("CURRENT_SEASON") &&
                        PASSING_SEASON == as.integer(CURRENT_SEASON)) {
    CACHE_DNA_PBP
  } else {
    file.path(cache_dir, sprintf("nfl_pbp_%d.rds", PASSING_SEASON))
  }

  needs_refresh <- isTRUE(force_refresh) || !file.exists(pbp_cache_path) ||
    as.numeric(difftime(Sys.time(), file.info(pbp_cache_path)$mtime, units = "hours")) > 12

  raw_pbp <- NULL
  if (needs_refresh) {
    if (!requireNamespace("nflreadr", quietly = TRUE)) {
      if (file.exists(pbp_cache_path)) {
        warning("Package 'nflreadr' unavailable; falling back to existing cache.")
        raw_pbp <- readRDS(pbp_cache_path)
      } else {
        stop("Package 'nflreadr' required to fetch PBP data when cache is missing.")
      }
    } else {
      cat(sprintf(">>> Fetching season %d PBP via nflreadr -> %s...\n", PASSING_SEASON, pbp_cache_path))
      raw_pbp <- tryCatch({
        p <- nflreadr::load_pbp(seasons = PASSING_SEASON)
        saveRDS(p, pbp_cache_path)
        cat(sprintf(">>> Cached raw PBP to %s (%d rows).\n", pbp_cache_path, nrow(p)))
        p
      }, error = function(e) {
        if (file.exists(pbp_cache_path)) {
          warning(sprintf("nflreadr::load_pbp failed (%s); falling back to existing cache %s", e$message, pbp_cache_path))
          readRDS(pbp_cache_path)
        } else {
          stop(sprintf("Failed to load PBP: %s", e$message))
        }
      })
    }
  } else {
    cat(sprintf(">>> Loading PBP data from local cache (%s)...\n", pbp_cache_path))
    raw_pbp <- readRDS(pbp_cache_path)
  }

  if (is.null(raw_pbp) || nrow(raw_pbp) == 0 || !"season" %in% names(raw_pbp)) {
    stop("Could not obtain valid play-by-play data.")
  }
  raw_pbp <- raw_pbp %>% filter(season == PASSING_SEASON)
  if (nrow(raw_pbp) == 0) {
    stop(sprintf("Could not obtain play-by-play rows for season %d.", PASSING_SEASON))
  }
  cat(sprintf(">>> Loaded %d raw PBP records for season %d.\n", nrow(raw_pbp), PASSING_SEASON))

  # 2. Load QB metadata from rosters_cache or player_qb_profiles
  qb_metadata_map <- list()
  rosters_path <- if (exists("CACHE_ROSTERS")) CACHE_ROSTERS else file.path(cache_dir, "rosters_cache.rds")

  if (file.exists(rosters_path)) {
    rosters <- readRDS(rosters_path)
    qb_rosters <- rosters %>%
      filter(position == "QB") %>%
      distinct(gsis_id, .keep_all = TRUE)
    for (i in seq_len(nrow(qb_rosters))) {
      gid <- qb_rosters$gsis_id[i]
      if (!is.na(gid) && nzchar(gid)) {
        qb_metadata_map[[gid]] <- list(
          player_name = qb_rosters$full_name[i],
          team = qb_rosters$team[i],
          jersey_number = if (!is.na(qb_rosters$jersey_number[i])) as.integer(qb_rosters$jersey_number[i]) else NULL,
          headshot_url = if (!is.na(qb_rosters$headshot_url[i]) && nzchar(qb_rosters$headshot_url[i])) qb_rosters$headshot_url[i] else NULL
        )
      }
    }
  }

  qb_profiles_path <- if (exists("WEB_JSON_PLAYER_QB_PROFILES")) {
    WEB_JSON_PLAYER_QB_PROFILES
  } else {
    "web/public/data/player_qb_profiles.json"
  }
  if (file.exists(qb_profiles_path)) {
    qb_profs <- fromJSON(qb_profiles_path)
  }

# 4. Filter to valid targeted pass attempts
clean_passes <- raw_pbp %>%
  filter(
    pass == 1,
    !is.na(passer_player_id),
    nzchar(as.character(passer_player_id)),
    !is.na(air_yards),
    !is.na(pass_location),
    tolower(trimws(as.character(pass_location))) %in% c("left", "middle", "right"),
    !is.na(complete_pass)
  ) %>%
  mutate(
    player_id = as.character(passer_player_id),
    passer_name = as.character(passer_player_name),
    air_yards = as.numeric(air_yards),
    pass_location = tolower(trimws(as.character(pass_location))),
    complete_pass = as.integer(complete_pass),
    epa = ifelse(is.na(epa), 0, round(as.numeric(epa), 3)),
    cpoe = ifelse(is.na(cpoe), NA_real_, round(as.numeric(cpoe), 2)),
    zone = mapply(classify_12_zones, air_yards, pass_location)
  ) %>%
  filter(!is.na(zone), zone %in% CANONICAL_ZONES)

cat(sprintf(">>> Total clean targeted pass records: %d\n", nrow(clean_passes)))

# 5. League Baselines across 12 Discrete Zones
total_lg_passes <- nrow(clean_passes)

league_averages <- clean_passes %>%
  group_by(zone) %>%
  summarise(
    attempts = n(),
    completions = sum(complete_pass == 1),
    comp_pct = round(completions / attempts, 3),
    avg_cpoe = round(mean(cpoe, na.rm = TRUE), 2),
    avg_epa = round(mean(epa, na.rm = TRUE), 3),
    pct_of_passes = round(attempts / total_lg_passes, 3),
    .groups = "drop"
  )

# Ensure all 12 zones exist in league_averages
for (z in CANONICAL_ZONES) {
  if (!z %in% league_averages$zone) {
    league_averages <- bind_rows(league_averages, tibble(
      zone = z, attempts = 0, completions = 0, comp_pct = 0,
      avg_cpoe = 0, avg_epa = 0, pct_of_passes = 0
    ))
  }
}
league_averages <- league_averages %>%
  arrange(match(zone, CANONICAL_ZONES))

cat(">>> League Baselines across 12 Throw Zones:\n")
print(league_averages)

# 6. Group by QB and export chunked JSON
index_path <- if (exists("WEB_JSON_PASSING_INDEX")) WEB_JSON_PASSING_INDEX else "web/public/data/passing_index.json"
out_dir <- file.path(dirname(index_path), "passing")
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

qb_groups <- split(clean_passes, clean_passes$player_id)

# Filter QBs with at least 15 pass attempts
MIN_PASS_ATTEMPTS <- 15
eligible_qbs <- names(Filter(function(df) nrow(df) >= MIN_PASS_ATTEMPTS, qb_groups))
cat(sprintf(">>> Found %d eligible QBs with >= %d pass attempts.\n", length(eligible_qbs), MIN_PASS_ATTEMPTS))

# Prune stale files in out_dir
current_files <- list.files(out_dir, pattern = "\\.json$")
stale_files <- setdiff(sub("\\.json$", "", current_files), eligible_qbs)
if (length(stale_files) > 0) {
  unlink(file.path(out_dir, paste0(stale_files, ".json")))
  cat(sprintf(">>> Pruned %d stale per-QB passing files.\n", length(stale_files)))
}

passing_index <- list()

for (pid in eligible_qbs) {
  p_passes <- qb_groups[[pid]]
  total_att <- nrow(p_passes)
  total_cmp <- sum(p_passes$complete_pass == 1)
  overall_comp_pct <- round(total_cmp / total_att, 3)
  overall_cpoe <- round(mean(p_passes$cpoe, na.rm = TRUE), 2)
  if (is.nan(overall_cpoe) || is.na(overall_cpoe)) overall_cpoe <- 0
  overall_epa <- round(mean(p_passes$epa, na.rm = TRUE), 3)

  # Resolve metadata
  meta <- qb_metadata_map[[pid]]
  p_name <- if (!is.null(meta$player_name)) meta$player_name else p_passes$passer_name[1]
  p_team <- if (!is.null(meta$team)) meta$team else p_passes$posteam[1]
  jersey <- if (!is.null(meta$jersey_number)) meta$jersey_number else NULL
  headshot <- if (!is.null(meta$headshot_url)) meta$headshot_url else NULL

  # Zone metrics for this QB
  qb_zone_metrics <- list()
  for (z in CANONICAL_ZONES) {
    z_passes <- p_passes %>% filter(zone == z)
    z_att <- nrow(z_passes)
    z_cmp <- sum(z_passes$complete_pass == 1)
    z_pct <- if (z_att > 0) round(z_cmp / z_att, 3) else 0
    z_cpoe <- if (z_att > 0 && any(!is.na(z_passes$cpoe))) round(mean(z_passes$cpoe, na.rm = TRUE), 2) else 0
    if (is.nan(z_cpoe)) z_cpoe <- 0
    z_epa <- if (z_att > 0) round(mean(z_passes$epa, na.rm = TRUE), 3) else 0
    z_share <- round(z_att / total_att, 3)

    qb_zone_metrics[[length(qb_zone_metrics) + 1]] <- list(
      zone = z,
      attempts = z_att,
      completions = z_cmp,
      comp_pct = z_pct,
      avg_cpoe = z_cpoe,
      avg_epa = z_epa,
      pct_of_passes = z_share
    )
  }

  # Clean pass attempt array
  clean_records <- p_passes %>%
    transmute(
      air_yards = round(air_yards, 1),
      pass_location = pass_location,
      complete_pass = complete_pass,
      epa = round(epa, 3),
      cpoe = ifelse(is.na(cpoe), NA, round(cpoe, 2)),
      zone = zone,
      week = as.integer(week),
      down = if ("down" %in% names(p_passes)) as.integer(down) else NA_integer_,
      ydstogo = if ("ydstogo" %in% names(p_passes)) as.integer(ydstogo) else NA_integer_,
      defteam = as.character(defteam),
      game_id = as.character(game_id)
    )

  qb_payload <- list(
    player_id = pid,
    player_name = p_name,
    team = p_team,
    jersey_number = jersey,
    headshot_url = headshot,
    total_passes = total_att,
    completions = total_cmp,
    comp_pct = overall_comp_pct,
    avg_cpoe = overall_cpoe,
    avg_epa = overall_epa,
    zones = qb_zone_metrics,
    passes = clean_records
  )

  qb_file <- file.path(out_dir, paste0(pid, ".json"))
  write_json(qb_payload, qb_file, auto_unbox = TRUE, null = "null")

  passing_index[[length(passing_index) + 1]] <- list(
    player_id = pid,
    player_name = p_name,
    team = p_team,
    jersey_number = jersey,
    headshot_url = headshot,
    total_passes = total_att,
    completions = total_cmp,
    comp_pct = overall_comp_pct,
    avg_cpoe = overall_cpoe,
    avg_epa = overall_epa
  )
}

# 7. Sort catalog by Team, then by Pass Volume
index_df <- bind_rows(passing_index) %>%
  arrange(team, desc(total_passes), player_name)

write_json(index_df, index_path, auto_unbox = TRUE, pretty = TRUE, null = "null")
cat(sprintf(">>> Wrote passing catalog with %d QBs to %s\n", nrow(index_df), index_path))

# 8. Save passing metadata
meta_path <- if (exists("WEB_JSON_PASSING_METADATA")) WEB_JSON_PASSING_METADATA else "web/public/data/passing_metadata.json"
write_json(list(
  updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  season = PASSING_SEASON,
  total_passes_sampled = total_lg_passes,
  zones = CANONICAL_ZONES,
  league_averages = league_averages
), meta_path, auto_unbox = TRUE, pretty = TRUE, null = "null")
cat(sprintf(">>> Wrote passing metadata to %s\n", meta_path))

cat(">>> [SUCCESS] QB Passing dataset generation complete!\n")
}

if (sys.nframe() == 0) {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  root_dir <- if (length(file_arg) > 0) {
    normalizePath(dirname(sub("^--file=", "", file_arg[1])), winslash = "/", mustWork = FALSE)
  } else {
    normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  }
  setwd(root_dir)
  if (file.exists("config.R")) {
    source("config.R")
  }
  run_build_passing_dataset()
}
