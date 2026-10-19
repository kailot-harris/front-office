# ==============================================================================
# build_shot_chart_dataset.R
# Extracts WNBA shot locations for rotation players, calculates 14 discrete zone baselines,
# and outputs optimized JSON files for the Next.js web application.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
})

cat(">>> [SHOT CHARTS] Loading rotation player catalog from Next.js web app...\n")
players_json_path <- "web/public/data/projections_season_players.json"
if (!file.exists(players_json_path)) {
  stop("Missing projections_season_players.json in web/public/data")
}

players_df <- fromJSON(players_json_path)
cat(sprintf(">>> Loaded %d rotation players.\n", nrow(players_df)))

# 1. Load shot data from cache
shots_cache_path <- "cache/wnba_espn_pbp_cache.rds"
if (!file.exists(shots_cache_path)) {
  stop(sprintf("Missing shot cache at %s", shots_cache_path))
}

cat(">>> Loading WNBA shot records from wnba_espn_pbp_cache.rds...\n")
raw_pbp <- readRDS(shots_cache_path)

# Filter to field goal attempts with coordinate tracking
fga_shots <- raw_pbp %>%
  filter(shooting_play == TRUE, !is.na(athlete_id_1), !is.na(coordinate_x_raw), !is.na(coordinate_y_raw)) %>%
  filter(!grepl("Free Throw", type_text, ignore.case = TRUE))

cat(sprintf(">>> Total raw tracked FGA records: %d\n", nrow(fga_shots)))

# 2. 14 Discrete Zone Classification for WNBA Half-Court
# Court dimensions: 50 ft wide (-25 to +25), 47 ft from baseline
# Basket rim is at (0, 5.25)
# WNBA 3-point line is 22.15 ft (FIBA distance; 21.9 ft in corners)
classify_14_zones <- function(x, y, dist, val = 2) {
  # 1. Deep / Logo 3 (dist > 27.5 ft or y > 33.0 ft from baseline)
  if (dist > 27.5 || y > 33.0) {
    return("Deep / Logo 3")
  }

  # 2. Corner 3s (y <= 14.0 ft, |x| >= 21.0 ft)
  if (abs(x) >= 21.0 && y <= 14.0) {
    if (x < 0) return("Left Corner 3") else return("Right Corner 3")
  }

  # 3. Above Break 3s (dist >= 22.15 ft or official 3-pointer)
  if (dist >= 22.15 || val == 3) {
    if (x < -7.0) return("Left Wing 3")
    if (x > 7.0)  return("Right Wing 3")
    return("Center 3")
  }

  # 4. Restricted Area (< 4.0 ft)
  if (dist <= 4.0) {
    return("Restricted Area")
  }

  # 5. In The Paint (|x| <= 8 ft, y <= 19 ft)
  if (abs(x) <= 8.0 && y <= 19.0) {
    if (y <= 11.5) return("Paint (Low / Floater)")
    return("Paint (High / FT)")
  }

  # 6. Baseline Mid-Range (y <= 14.0 ft)
  if (y <= 14.0) {
    if (x < 0) return("Left Baseline Mid") else return("Right Baseline Mid")
  }

  # 7. Wing & Center Mid-Range
  if (x < -7.0) return("Left Wing Mid")
  if (x > 7.0)  return("Right Wing Mid")
  return("Center Mid")
}

# Coordinate transformation and zone assignment
clean_fga <- fga_shots %>%
  mutate(
    athlete_id = as.character(athlete_id_1),
    x = round(coordinate_x_raw - 25.0, 1),
    y = round(pmax(0, pmin(47, coordinate_y_raw + 4.0)), 1),
    dist = round(sqrt(x^2 + (y - 5.25)^2), 1),
    made = as.logical(scoring_play),
    val = ifelse(score_value == 3 | (dist >= 22.15 & !grepl("Free Throw", type_text, ignore.case = TRUE)), 3, 2),
    zone = mapply(classify_14_zones, x, y, dist, val)
  )

cat(sprintf(">>> Processed %d clean shots with 14-zone classifications.\n", nrow(clean_fga)))

# 3. Calculate League Averages per Zone
league_averages <- clean_fga %>%
  group_by(zone) %>%
  summarise(
    total_fga = n(),
    total_fgm = sum(made),
    lg_fg_pct = round(total_fgm / total_fga, 3),
    .groups = "drop"
  )

cat(">>> League Baselines across 14 Discrete Zones:\n")
print(league_averages)

# 4. Filter shots for our rotation players
rotation_player_ids <- as.character(unique(players_df$player_id))
player_shots_matched <- clean_fga %>%
  filter(athlete_id %in% rotation_player_ids) %>%
  left_join(
    players_df %>%
      mutate(player_id = as.character(player_id)) %>%
      select(player_id, player_team = team),
    by = c("athlete_id" = "player_id")
  ) %>%
  select(
    athlete_id,
    player_name = athlete_name_1,
    team_abbrev = player_team,
    period = period_number,
    clock = clock_display_value,
    type = type_text,
    x,
    y,
    dist,
    val,
    made,
    zone
  )

cat(sprintf(">>> Matched %d shots across rotation players.\n", nrow(player_shots_matched)))

# Create output directories in web app
out_dir <- "web/public/data/shots"
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

# Save league metadata
meta_path <- "web/public/data/shots_metadata.json"
meta_obj <- list(
  season = 2026,
  updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
  total_shots_sampled = nrow(clean_fga),
  league_averages = league_averages,
  zones = c(
    "Restricted Area",
    "Paint (Low / Floater)",
    "Paint (High / FT)",
    "Left Baseline Mid",
    "Right Baseline Mid",
    "Left Wing Mid",
    "Center Mid",
    "Right Wing Mid",
    "Left Corner 3",
    "Right Corner 3",
    "Left Wing 3",
    "Center 3",
    "Right Wing 3",
    "Deep / Logo 3"
  )
)
write_json(meta_obj, meta_path, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf(">>> Wrote 14-zone metadata to %s\n", meta_path))

# Group shots by player and export per-player JSON
player_groups <- split(player_shots_matched, player_shots_matched$athlete_id)

cat(sprintf(">>> Writing per-player shot files for %d players...\n", length(player_groups)))

player_catalog <- list()

for (pid in names(player_groups)) {
  p_shots <- player_groups[[pid]]

  p_meta <- players_df %>% filter(as.character(player_id) == pid)
  if (nrow(p_meta) > 0) {
    p_name <- p_meta$player_name[1]
    p_team <- p_meta$team[1]
  } else {
    p_name <- p_shots$player_name[1]
    p_team <- p_shots$team_abbrev[1]
  }

  clean_shots <- p_shots %>%
    select(x, y, dist, val, made, zone, type, period, clock)

  player_catalog[[pid]] <- list(
    player_id = pid,
    player_name = p_name,
    team = p_team,
    total_shots = nrow(clean_shots)
  )

  player_file <- file.path(out_dir, paste0(pid, ".json"))
  write_json(list(
    player_id = pid,
    player_name = p_name,
    team = p_team,
    total_shots = nrow(clean_shots),
    shots = clean_shots
  ), player_file, auto_unbox = TRUE)
}

# Sort catalog by Team, then by Shot Volume
catalog_df <- bind_rows(player_catalog) %>%
  arrange(team, desc(total_shots), player_name)

index_path <- "web/public/data/shots_index.json"
write_json(catalog_df, index_path, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf(">>> Wrote shot chart catalog with %d players to %s\n", nrow(catalog_df), index_path))

# Sync metadata and index to cache/
if (dir.exists("cache")) {
  write_json(meta_obj, "cache/shots_metadata.json", auto_unbox = TRUE, pretty = TRUE)
  write_json(catalog_df, "cache/shots_index.json", auto_unbox = TRUE, pretty = TRUE)
  cat(">>> Synced shots metadata and index to cache/\n")
}

cat(">>> [SUCCESS] WNBA 14-Zone dataset generation complete!\n")
