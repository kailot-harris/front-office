# ==============================================================================
# build_shot_chart_dataset.R
# Extracts NBA shot locations for rotation players, calculates 14 discrete zone baselines,
# and outputs optimized JSON files for the Next.js web application.
# ==============================================================================

suppressPackageStartupMessages({
  library(hoopR)
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

# 1. Load or fetch shot data
# SHOT_CHART_SEASON is hoopR's END-year numbering. The site projects 2026-2027, but
# that season does not have a usable shot sample yet, so default to the last completed
# season (2026 => 2025-2026). The span is stamped into shots_metadata.json below and
# shown on the page. Override with NBA_SHOT_CHART_SEASON to inspect another sample.
SHOT_CHART_SEASON <- as.integer(Sys.getenv("NBA_SHOT_CHART_SEASON", "2026"))
shots_cache_path <- sprintf("cache/nba_shots_%d.rds", SHOT_CHART_SEASON)
if (file.exists(shots_cache_path)) {
  cat(sprintf(">>> Loading shot data from local cache (%s)...\n", shots_cache_path))
  raw_shots <- readRDS(shots_cache_path)
} else {
  cat(sprintf(">>> Fetching season %d NBA shot records via hoopR...\n", SHOT_CHART_SEASON))
  raw_shots <- tryCatch({
    s <- hoopR::load_nba_shots(seasons = SHOT_CHART_SEASON)
    saveRDS(s, shots_cache_path)
    s
  }, error = function(e) {
    cat(sprintf(">>> [WARN] Failed to load hoopR shots: %s\n", e$message))
    NULL
  })
}

if (is.null(raw_shots) || nrow(raw_shots) == 0) {
  stop("Could not obtain shot data.")
}

cat(sprintf(">>> Total raw shot records: %d\n", nrow(raw_shots)))

# 2. 14 Discrete Zone Classification
# Basketball half-court dimensions:
# Width: 50 ft (-25 to +25)
# Length: 47 ft (0 to 47 from baseline)
# Basket rim is at (0, 5.25)
classify_14_zones <- function(x, y, dist, val = 2) {
  # 1. Deep / Logo 3 (dist > 27.5 ft or y > 33 ft from baseline)
  if (dist > 27.5 || y > 33.0) {
    return("Deep / Logo 3")
  }
  
  # 2. Corner 3s (y <= 14.2 ft, |x| >= 21.5 ft)
  if (abs(x) >= 21.5 && y <= 14.2) {
    if (x < 0) return("Left Corner 3") else return("Right Corner 3")
  }
  
  # 3. Above Break 3s (dist >= 23.5 ft or official 3-point attempt)
  if (dist >= 23.5 || val == 3) {
    if (x < -7.0) return("Left Wing 3")
    if (x > 7.0)  return("Right Wing 3")
    return("Center 3")
  }
  
  # 4. Restricted Area (< 4.2 ft)
  if (dist <= 4.2) {
    return("Restricted Area")
  }
  
  # 5. In The Paint (|x| <= 8 ft, y <= 19 ft)
  if (abs(x) <= 8.0 && y <= 19.0) {
    if (y <= 11.5) return("Paint (Low / Floater)")
    return("Paint (High / FT)")
  }
  
  # 6. Baseline Mid-Range (y <= 14.2 ft)
  if (y <= 14.2) {
    if (x < 0) return("Left Baseline Mid") else return("Right Baseline Mid")
  }
  
  # 7. Wing & Center Mid-Range
  if (x < -7.0) return("Left Wing Mid")
  if (x > 7.0)  return("Right Wing Mid")
  return("Center Mid")
}

# ESPN occasionally emits a clock as H:MM:SS (e.g. "1:38:43") alongside the usual
# M:SS. The shot record contract expects a game clock, so keep the final two parts.
normalize_clock <- function(x) {
  vapply(strsplit(as.character(x), ":", fixed = TRUE), function(parts) {
    if (length(parts) >= 2) paste(tail(parts, 2), collapse = ":") else as.character(parts)
  }, character(1))
}

# Filter to field goal attempts
fga_shots <- raw_shots %>%
  filter(!is.na(athlete_id_1), score_value %in% c(0, 2, 3) | scoring_play) %>%
  filter(!grepl("Free Throw", type_text, ignore.case = TRUE)) %>%
  mutate(
    athlete_id = as.character(athlete_id_1),
    clock = normalize_clock(clock_display_value),
    # Court coordinate transformation: width 0..50 -> -25..25; length from baseline 0..47
    # Note: ESPN raw tracking coordinates measure y from the backboard plane (rim at y=1.25),
    # whereas regulation NBA half-court measures y from baseline (4.0 ft behind backboard, rim at y=5.25).
    # Adding +4.0 ft aligns all shots perfectly with regulation court geometry.
    x = round(coordinate_x_raw - 25.0, 1),
    y = round(pmax(0, pmin(47, coordinate_y_raw + 4.0)), 1),
    dist = round(sqrt(x^2 + (y - 5.25)^2), 1),
    made = as.logical(scoring_play),
    val = ifelse(score_value == 3 | (dist >= 23.5 & !grepl("Free Throw", type_text)), 3, 2),
    zone = mapply(classify_14_zones, x, y, dist, val)
  )

cat(sprintf(">>> Valid Field Goal Attempts: %d\n", nrow(fga_shots)))

# 3. Calculate League Averages per Zone
league_averages <- fga_shots %>%
  group_by(zone) %>%
  summarise(
    total_fga = n(),
    total_fgm = sum(made),
    lg_fg_pct = round(total_fgm / total_fga, 3),
    .groups = "drop"
  )

cat(">>> League Baselines across 14 Discrete Zones:\n")
print(league_averages)

# 4. Filter shots for our 330 rotation players
rotation_player_ids <- unique(players_df$player_id)
player_shots_matched <- fga_shots %>%
  filter(athlete_id %in% rotation_player_ids) %>%
  select(
    athlete_id,
    player_name = athlete_name_1,
    team_abbrev,
    period = period_number,
    clock = clock,
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

# Which NBA season(s) these shots were actually taken in. Read off the data rather
# than restated from SHOT_CHART_SEASON, so the label cannot drift away from the file
# that is loaded. hoopR's shot `season` is the END year, so 2026 is the completed
# 2025-2026 season -- one season behind the projection, and labeled as such on the page.
shot_season_label <- local({
  yrs <- if ("season" %in% names(raw_shots)) {
    sort(unique(suppressWarnings(as.integer(raw_shots$season))))
  } else {
    integer(0)
  }
  yrs <- yrs[!is.na(yrs)]
  if (length(yrs) == 0) yrs <- SHOT_CHART_SEASON
  paste(sprintf("%d-%d", yrs - 1L, yrs), collapse = " + ")
})
cat(sprintf(">>> [SHOT CHARTS] Shot sample is from the %s season.\n", shot_season_label))

# Save league metadata
meta_path <- "web/public/data/shots_metadata.json"
write_json(list(
  updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
  total_shots_sampled = nrow(fga_shots),
  source_season_label = shot_season_label,
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
), meta_path, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf(">>> Wrote 14-zone metadata to %s\n", meta_path))

# Group shots by player and export per-player JSON
player_groups <- split(player_shots_matched, player_shots_matched$athlete_id)

# Prune per-player files left by an earlier build that are no longer in this run's
# catalog. Without this, a changed rotation (or a player dropping below the shot
# minimum) leaves stale <id>.json files behind, and shots_index.json stops matching
# what is actually on disk.
stale_files <- setdiff(
  sub("\\.json$", "", list.files(out_dir, pattern = "\\.json$")),
  names(player_groups)
)
if (length(stale_files) > 0) {
  unlink(file.path(out_dir, paste0(stale_files, ".json")))
  cat(sprintf(">>> Pruned %d stale per-player shot files.\n", length(stale_files)))
}

cat(sprintf(">>> Writing per-player shot files for %d players...\n", length(player_groups)))

player_catalog <- list()

for (pid in names(player_groups)) {
  p_shots <- player_groups[[pid]]
  
  # Ground truth: Lookup player in 2026-2027 active rotation catalog
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
cat(">>> [SUCCESS] 14-Zone dataset generation complete!\n")
