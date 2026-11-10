# ==============================================================================
# build_passing_dataset.R
# Extracts NFL NextGenStats-style QB passing charts and throw maps, calculates
# 12 discrete depth/horizontal zone baselines, and outputs chunked JSON files
# for the Next.js web application.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
})

# Robustly determine root directory from script location or working directory
get_script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    p <- sub("^--file=", "", file_arg[1])
    return(normalizePath(dirname(p), winslash = "/", mustWork = FALSE))
  }
  normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}
ROOT_DIR <- get_script_dir()
setwd(ROOT_DIR)
cat(sprintf(">>> Working directory set to: %s\n", getwd()))

# Source project configuration if present
if (file.exists("config.R")) {
  source("config.R")
}

PASSING_SEASON <- as.integer(Sys.getenv("NFL_PASSING_SEASON", "2026"))
cat(sprintf(">>> [PASSING CHARTS] Building passing dataset for season %d...\n", PASSING_SEASON))

# 1. Load PBP data: check cache/nfl_pbp_*.rds first
pbp_files <- list.files("cache", pattern = "^nfl_pbp_.*\\.rds$", full.names = TRUE)
raw_pbp <- NULL

if (length(pbp_files) > 0) {
  # Prefer the file matching PASSING_SEASON or most recent
  target_file <- sprintf("cache/nfl_pbp_%d.rds", PASSING_SEASON)
  chosen_file <- if (target_file %in% pbp_files) target_file else tail(sort(pbp_files), 1)
  cat(sprintf(">>> Loading PBP data from local cache (%s)...\n", chosen_file))
  raw_pbp <- readRDS(chosen_file)
} else {
  cat(sprintf(">>> No cache/nfl_pbp_*.rds found. Loading season %d PBP via nflreadr...\n", PASSING_SEASON))
  if (!requireNamespace("nflreadr", quietly = TRUE)) {
    stop("Package 'nflreadr' required to fetch PBP data when cache is missing.")
  }
  raw_pbp <- tryCatch({
    p <- nflreadr::load_pbp(seasons = PASSING_SEASON)
    out_cache <- sprintf("cache/nfl_pbp_%d.rds", PASSING_SEASON)
    if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)
    saveRDS(p, out_cache)
    cat(sprintf(">>> Cached raw PBP to %s (%d rows).\n", out_cache, nrow(p)))
    p
  }, error = function(e) {
    stop(sprintf("Failed to load PBP: %s", e$message))
  })
}

if (is.null(raw_pbp) || nrow(raw_pbp) == 0) {
  stop("Could not obtain valid play-by-play data.")
}
cat(sprintf(">>> Loaded %d raw PBP records.\n", nrow(raw_pbp)))

# 2. Load QB metadata from rosters_cache or player_qb_profiles
qb_metadata_map <- list()

if (file.exists("cache/rosters_cache.rds")) {
  rosters <- readRDS("cache/rosters_cache.rds")
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

if (file.exists("web/public/data/player_qb_profiles.json")) {
  qb_profs <- fromJSON("web/public/data/player_qb_profiles.json")
  # Fallback lookup by player name if gsis_id was missing
}

# 3. 12 Discrete Throw Zone Classification
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
out_dir <- "web/public/data/passing"
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

index_path <- "web/public/data/passing_index.json"
write_json(index_df, index_path, auto_unbox = TRUE, pretty = TRUE, null = "null")
cat(sprintf(">>> Wrote passing catalog with %d QBs to %s\n", nrow(index_df), index_path))

# 8. Save passing metadata
meta_path <- "web/public/data/passing_metadata.json"
write_json(list(
  updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
  season = PASSING_SEASON,
  total_passes_sampled = total_lg_passes,
  zones = CANONICAL_ZONES,
  league_averages = league_averages
), meta_path, auto_unbox = TRUE, pretty = TRUE, null = "null")
cat(sprintf(">>> Wrote passing metadata to %s\n", meta_path))

cat(">>> [SUCCESS] QB Passing dataset generation complete!\n")
