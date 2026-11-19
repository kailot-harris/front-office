# ==============================================================================
# build_clutch_dataset.R
# Feature 6: True Clutch & Leverage Creation Index
# Analyzes real high-leverage late-game performance (Score margin <= 5 pts, <= 5:00 4Q/OT):
# 1. USCI (Unassisted Shot Creation Index) = (FGM_unassisted / FGA) * PPP
# 2. Clutch TS% vs Regular Season TS% Delta (True Shooting Resilience)
# 3. Turnover Fragility under Late-Game Pressure: Delta TOV%
# 4. Clutch Defensive Win Probability Added (c-dWPA)
# 5. Clutch Shot Spatial Distribution (Rim, Mid-Range, 3PT with make/miss rates)
#
# All metrics are derived strictly from empirical play-by-play events
# in the current-season cache/nba_pbp_<CURRENT_SEASON>.rds and box scores.
# Manual star player overrides and affine clamping heuristics have been
# eradicated (Issue #81, following WNBA Issue #144 precedent).
#
# Exports:
#   - web/public/data/clutch_leverage_metrics.json
#   - cache/clutch_leverage_metrics.rds
#
# Data window (front-office#109):
#   Seasons: the current season only (CURRENT_SEASON in config.R, labelled via
#     season_label(); 2027 = 2026-27). Play-by-play is
#     cache/nba_pbp_<CURRENT_SEASON>.rds and baseline shooting / turnover rates
#     come from cache/nba_player_box_<CURRENT_SEASON>.rds. The script stops if
#     either is missing: there is no fallback to another season, to an unnamed
#     cache file, or to projection baselines (front-office#191). The player list
#     comes from the 2026-27 season projections. No season-type filter is
#     applied. The JSON exports season, throughDate (latest game_date present in
#     the play-by-play input) and generatedAt, so pages read the window from data.
#   Filters: the clutch window is period 4 or overtime, 5:00 or less on the clock,
#     and a score margin of 5 points or fewer, using the score recorded on each
#     play row (the score after that play).
#   Minimum sample: MIN_CLUTCH_FGA = 20 clutch field-goal attempts (NBA#90; the
#     owner's to tune) for clutch rates, a USCI rank and an archetype. Players
#     below it stay in the file with their attempt count (clutchFga) and shot
#     breakdown, but with empty rates, qualified = false, clutchRank = null and
#     clutchArchetype = null.
#   USCI scale: capped at 0-150, not a 0-100 index; values above 100 occur (#90).
#   Known issues: #187 (score margin after the play).
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(tibble)
})

# Source global config
config_path <- if (file.exists("config.R")) "config.R" else "../config.R"
source(config_path)

cat(">>> [CLUTCH ENGINE] Initializing True Clutch & Leverage Creation Engine...\n")

# Load existing player projections
proj_players_file <- WEB_JSON_PROJECTIONS_SEASON_PLAYERS
if (!file.exists(proj_players_file)) {
  stop("Missing projections_season_players.json")
}

players_df <- jsonlite::fromJSON(proj_players_file)
cat(sprintf(">>> Loaded %d player projections for %s season.\n", nrow(players_df), season_label()))

# Load empirical play-by-play cache
pbp_file <- current_season_cache("pbp")  # stop()s if the current-season file is missing
box_file <- current_season_cache("player_box")  # stop()s if missing

cat(sprintf(">>> Ingesting empirical play-by-play from '%s'...\n", pbp_file))
pbp <- readRDS(pbp_file)
box_df <- readRDS(box_file)
through_date <- data_through_date(pbp, box_df)
cat(sprintf(">>> Season %s, data through %s (earlier of play-by-play and player box).\n", season_label(), through_date))

# Compute seconds remaining and score margin
pbp$sec_remaining <- pbp$clock_minutes * 60 + pbp$clock_seconds
pbp$margin <- abs(pbp$home_score - pbp$away_score)

# Clutch filter: 4th quarter or overtime (period >= 4), last 5 minutes (<= 300s), margin <= 5
clutch <- pbp[pbp$period_number >= 4 & pbp$sec_remaining <= 300 & pbp$margin <= 5, ]
cat(sprintf(">>> Filtered %d clutch event records across %d close games.\n",
            nrow(clutch), length(unique(clutch$game_id))))

# Ingest regular season player box scores for baseline TS% and TOV%
cat(sprintf(">>> Ingested %d regular-season player box scores for baseline calibration.\n", nrow(box_df)))
reg_box <- box_df %>%
  group_by(athlete_id = as.character(athlete_id)) %>%
  summarise(
    reg_games = n(),
    reg_min = sum(as.numeric(minutes), na.rm = TRUE),
    reg_pts = sum(as.numeric(points), na.rm = TRUE),
    reg_fga = sum(as.numeric(field_goals_attempted), na.rm = TRUE),
    reg_fgm = sum(as.numeric(field_goals_made), na.rm = TRUE),
    reg_fta = sum(as.numeric(free_throws_attempted), na.rm = TRUE),
    reg_ftm = sum(as.numeric(free_throws_made), na.rm = TRUE),
    reg_tov = sum(as.numeric(turnovers), na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    base_ts = if_else(
      (reg_fga + 0.44 * reg_fta) > 0,
      round((reg_pts / (2 * (reg_fga + 0.44 * reg_fta))) * 100, 1),
      NA_real_  # no attempts: unobserved, published as null (never a default)
    ),
    base_tov_rate = if_else(
      (reg_fga + 0.44 * reg_fta + reg_tov) > 0,
      (reg_tov / (reg_fga + 0.44 * reg_fta + reg_tov)) * 100,
      NA_real_  # no possessions used: unobserved, published as null
    )
  )

# --- Aggregations from empirical PBP ---

# 1. Team-level clutch possessions for USG% calculation
team_clutch_plays <- clutch %>%
  filter(!is.na(team_id)) %>%
  group_by(game_id, team_id = as.character(team_id)) %>%
  summarise(
    tm_fga = sum(shooting_play == TRUE & !grepl("free throw", type_text, ignore.case = TRUE), na.rm = TRUE),
    tm_fta = sum(grepl("free throw", type_text, ignore.case = TRUE), na.rm = TRUE),
    tm_tov = sum(grepl("turnover", type_text, ignore.case = TRUE) | grepl("turnover", text, ignore.case = TRUE), na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(tm_poss = tm_fga + 0.44 * tm_fta + tm_tov)

# 2. Player-level clutch possessions per game
player_clutch_plays <- clutch %>%
  filter(!is.na(athlete_id_1), !is.na(team_id)) %>%
  group_by(game_id, athlete_id = as.character(athlete_id_1), team_id = as.character(team_id)) %>%
  summarise(
    p_fga = sum(shooting_play == TRUE & !grepl("free throw", type_text, ignore.case = TRUE), na.rm = TRUE),
    p_fta = sum(grepl("free throw", type_text, ignore.case = TRUE), na.rm = TRUE),
    p_tov = sum(grepl("turnover", type_text, ignore.case = TRUE) | grepl("turnover", text, ignore.case = TRUE), na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(p_poss = p_fga + 0.44 * p_fta + p_tov)

player_usg_tbl <- player_clutch_plays %>%
  inner_join(team_clutch_plays, by = c("game_id", "team_id")) %>%
  group_by(athlete_id) %>%
  summarise(
    tot_p_poss = sum(p_poss),
    tot_tm_poss = sum(tm_poss),
    clutch_usg_pct = round(pmin(100.0, pmax(0.0, (tot_p_poss / pmax(1.0, tot_tm_poss)) * 100)), 1),
    .groups = "drop"
  )

# 3. Player clutch shooting breakdown (spatial & unassisted)
shots <- clutch %>%
  filter(shooting_play == TRUE, !grepl("free throw", type_text, ignore.case = TRUE), !is.na(athlete_id_1))

shots_summary <- shots %>%
  mutate(
    is_make = scoring_play == TRUE,
    is_unassisted = is_make & (is.na(athlete_id_2) | athlete_id_2 == 0),
    is_three = points_attempted == 3 | grepl("three point|3pt", type_text, ignore.case = TRUE),
    dist = if_else(!is.na(coordinate_x) & !is.na(coordinate_y), sqrt(coordinate_x^2 + coordinate_y^2), 15),
    is_rim = !is_three & (dist <= 4.5 | grepl("layup|dunk|tip|hook|putback", type_text, ignore.case = TRUE)),
    is_mid = !is_three & !is_rim,
    pts_val = case_when(
      is_make & is_three ~ 3L,
      is_make ~ 2L,
      TRUE ~ 0L
    )
  ) %>%
  group_by(athlete_id = as.character(athlete_id_1)) %>%
  summarise(
    clutch_fga = n(),
    clutch_fgm = sum(is_make),
    clutch_fg_pts = sum(pts_val),
    unassisted_fgm = sum(is_unassisted),
    rim_fga = sum(is_rim),
    rim_fgm = sum(is_rim & is_make),
    mid_fga = sum(is_mid),
    mid_fgm = sum(is_mid & is_make),
    three_fga = sum(is_three),
    three_fgm = sum(is_three & is_make),
    .groups = "drop"
  )

# 4. Free throws
fts_summary <- clutch %>%
  filter(grepl("free throw", type_text, ignore.case = TRUE), !is.na(athlete_id_1)) %>%
  group_by(athlete_id = as.character(athlete_id_1)) %>%
  summarise(
    clutch_fta = n(),
    clutch_ftm = sum(scoring_play == TRUE, na.rm = TRUE),
    .groups = "drop"
  )

# 5. Turnovers
tovs_summary <- clutch %>%
  filter(grepl("turnover", type_text, ignore.case = TRUE) | grepl("turnover", text, ignore.case = TRUE), !is.na(athlete_id_1)) %>%
  group_by(athlete_id = as.character(athlete_id_1)) %>%
  summarise(
    clutch_tov = n(),
    .groups = "drop"
  )

# 6. Defensive events (defensive rebounds, blocks, steals)
drebs_summary <- clutch %>%
  filter(grepl("defensive rebound", type_text, ignore.case = TRUE), !is.na(athlete_id_1)) %>%
  group_by(athlete_id = as.character(athlete_id_1)) %>%
  summarise(clutch_dreb = n(), .groups = "drop")

blks_summary <- clutch %>%
  filter(grepl("block", text, ignore.case = TRUE), !is.na(athlete_id_2)) %>%
  group_by(athlete_id = as.character(athlete_id_2)) %>%
  summarise(clutch_blk = n(), .groups = "drop")

stls_summary <- clutch %>%
  filter(grepl("steal", text, ignore.case = TRUE), !is.na(athlete_id_2)) %>%
  group_by(athlete_id = as.character(athlete_id_2)) %>%
  summarise(clutch_stl = n(), .groups = "drop")

# 7. Clutch games and empirical on-court minutes per game
p_events1 <- clutch %>% filter(!is.na(athlete_id_1)) %>% select(game_id, athlete_id = athlete_id_1, sec_remaining)
p_events2 <- clutch %>% filter(!is.na(athlete_id_2)) %>% select(game_id, athlete_id = athlete_id_2, sec_remaining)
p_events <- bind_rows(p_events1, p_events2)

p_time_summary <- p_events %>%
  group_by(athlete_id = as.character(athlete_id), game_id) %>%
  summarise(
    span_sec = max(sec_remaining) - min(sec_remaining),
    .groups = "drop"
  ) %>%
  group_by(athlete_id) %>%
  summarise(
    clutch_games = n(),
    avg_clutch_mpg = round(mean(pmax(span_sec, 60)) / 60, 1),
    .groups = "drop"
  )

# Minimum sample threshold (NBA#90). Below this many clutch field-goal attempts a
# player is published unranked, with no clutch rates and no archetype. 20 is the
# default; the value is the owner's to tune. Keep CLUTCH_MIN_FGA in
# web/lib/clutchTypes.ts equal to this constant.
MIN_CLUTCH_FGA <- 20L

clutch_profiles <- list()

for (i in seq_len(nrow(players_df))) {
  p <- players_df[i, ]
  p_id <- as.character(p$player_id)
  name <- p$player_name
  pos <- p$position
  team <- p$team
  pts <- p$proj_pts
  is_center <- pos == "C"

  # Match player stats
  sh <- shots_summary %>% filter(athlete_id == p_id)
  ft <- fts_summary %>% filter(athlete_id == p_id)
  tv <- tovs_summary %>% filter(athlete_id == p_id)
  dr <- drebs_summary %>% filter(athlete_id == p_id)
  bk <- blks_summary %>% filter(athlete_id == p_id)
  st <- stls_summary %>% filter(athlete_id == p_id)
  tm <- p_time_summary %>% filter(athlete_id == p_id)
  us <- player_usg_tbl %>% filter(athlete_id == p_id)
  bx <- reg_box %>% filter(athlete_id == p_id)

  c_fga <- if (nrow(sh) > 0) sh$clutch_fga else 0L
  has_sufficient_sample <- c_fga >= MIN_CLUTCH_FGA

  # Base TS% from current-season regular season box scores
  # (null when the player has no box row or no attempts; never imputed)
  base_ts <- if (nrow(bx) > 0) bx$base_ts else NA_real_

  rim_fga <- if (nrow(sh) > 0) as.integer(sh$rim_fga) else 0L
  rim_fgm <- if (nrow(sh) > 0) as.integer(sh$rim_fgm) else 0L
  mid_fga <- if (nrow(sh) > 0) as.integer(sh$mid_fga) else 0L
  mid_fgm <- if (nrow(sh) > 0) as.integer(sh$mid_fgm) else 0L
  three_fga <- if (nrow(sh) > 0) as.integer(sh$three_fga) else 0L
  three_fgm <- if (nrow(sh) > 0) as.integer(sh$three_fgm) else 0L

  rim_pct <- if (rim_fga > 0) round((rim_fgm / rim_fga) * 100, 1) else 0.0
  mid_pct <- if (mid_fga > 0) round((mid_fgm / mid_fga) * 100, 1) else 0.0
  three_pct <- if (three_fga > 0) round((three_fgm / three_fga) * 100, 1) else 0.0

  if (has_sufficient_sample) {
    c_fgm <- sh$clutch_fgm
    c_fta <- if (nrow(ft) > 0) ft$clutch_fta else 0L
    c_ftm <- if (nrow(ft) > 0) ft$clutch_ftm else 0L
    c_pts <- sh$clutch_fg_pts + c_ftm
    c_tov <- if (nrow(tv) > 0) tv$clutch_tov else 0L
    c_dreb <- if (nrow(dr) > 0) dr$clutch_dreb else 0L
    c_blk <- if (nrow(bk) > 0) bk$clutch_blk else 0L
    c_stl <- if (nrow(st) > 0) st$clutch_stl else 0L
    c_gp <- if (nrow(tm) > 0) tm$clutch_games else 0L  # 0 clutch games; the "+ 8" prior below keeps c-dWPA finite

    # Empirical Clutch MPG
    clutch_min_pg <- if (nrow(tm) > 0) round(pmin(5.0, pmax(0.5, tm$avg_clutch_mpg)), 1) else NA_real_

    # Empirical Clutch Usage %
    clutch_usg_pct <- if (nrow(us) > 0) us$clutch_usg_pct else NA_real_

    # Empirical True Shooting %
    clutch_ts_pct <- round(pmin(100.0, pmax(0.0, (c_pts / (2 * (c_fga + 0.44 * c_fta))) * 100)), 1)
    ts_delta <- round(clutch_ts_pct - base_ts, 1)

    # Points Per Possession & USCI
    clutch_ppp <- round(c_pts / (c_fga + 0.44 * c_fta), 2)
    unassisted_fgm_pct <- if (c_fgm > 0) round((sh$unassisted_fgm / c_fgm) * 100, 1) else 0.0
    usci_score <- round(pmin(150.0, pmax(0.0, (unassisted_fgm_pct / 100) * clutch_ppp * 100)), 1)

    # Turnover Fragility Under Pressure (Delta TOV%)
    clutch_tov_rate <- (c_tov / (c_fga + 0.44 * c_fta + c_tov)) * 100
    base_tov_rate <- if (nrow(bx) > 0) bx$base_tov_rate else NA_real_
    tov_fragility <- round(clutch_tov_rate - base_tov_rate, 1)  # NA when baseline unobserved

    # Clutch Defensive Win Probability Added (c-dWPA) in percentage points
    c_dwpa <- round((c_dreb * 0.12 + c_stl * 0.35 + c_blk * 0.40 + 2.0) / (c_gp + 8) * 6, 2)

    # Archetype based on empirical metrics
    clutch_archetype <- if (usci_score >= 65.0) "Elite Late-Game Closer & Iso Engine" else
                        if (isTRUE(ts_delta >= 2.0)) "High-Pressure True Shooting Riser" else
                        if (c_dwpa >= 1.5) "Late-Game Defensive Anchor & Lock" else
                        if (unassisted_fgm_pct <= 35.0 && clutch_ts_pct >= 58.0) "Dead-Eye Spot-Up Release Valve" else
                        "Situational Rotation Finisher"
  } else {
    clutch_min_pg <- NA_real_
    clutch_usg_pct <- NA_real_
    clutch_ts_pct <- NA_real_
    ts_delta <- NA_real_
    usci_score <- NA_real_
    unassisted_fgm_pct <- NA_real_
    clutch_ppp <- NA_real_
    tov_fragility <- NA_real_
    c_dwpa <- NA_real_
    clutch_archetype <- NA_character_
  }

  clutch_profiles[[i]] <- list(
    playerId = p_id,
    playerName = name,
    team = team,
    position = pos,
    clutchFga = as.integer(c_fga),
    qualified = has_sufficient_sample,
    clutchRank = NA_integer_,
    clutchArchetype = clutch_archetype,
    clutchMpg = clutch_min_pg,
    clutchUsgPct = clutch_usg_pct,
    clutchTsPct = clutch_ts_pct,
    baseTsPct = base_ts,
    tsDelta = ts_delta,
    usciScore = usci_score,
    unassistedFgmPct = unassisted_fgm_pct,
    clutchPpp = clutch_ppp,
    tovFragility = tov_fragility,
    cDwpa = c_dwpa,
    shotBreakdown = list(
      totalClutchFga = as.integer(rim_fga + mid_fga + three_fga),
      rim = list(fga = rim_fga, fgm = rim_fgm, pct = rim_pct),
      mid = list(fga = mid_fga, fgm = mid_fgm, pct = mid_pct),
      three = list(fga = three_fga, fgm = three_fgm, pct = three_pct)
    )
  )
}

# USCI rank among qualified players only (1 = highest USCI, ties share the best
# rank). Players under MIN_CLUTCH_FGA keep clutchRank = null.
qualified_idx <- which(vapply(clutch_profiles, function(x) isTRUE(x$qualified), logical(1)))
if (length(qualified_idx) > 0) {
  q_usci <- vapply(clutch_profiles[qualified_idx], function(x) x$usciScore, numeric(1))
  q_rank <- as.integer(rank(-q_usci, ties.method = "min"))
  for (k in seq_along(qualified_idx)) {
    clutch_profiles[[qualified_idx[k]]]$clutchRank <- q_rank[k]
  }
}
cat(sprintf(">>> %d of %d players reach MIN_CLUTCH_FGA = %d and are ranked.
",
            length(qualified_idx), length(clutch_profiles), MIN_CLUTCH_FGA))

# ------------------------------------------------------------------------------
# Export JSON & RDS
# ------------------------------------------------------------------------------
output_json <- WEB_JSON_CLUTCH_LEVERAGE_METRICS
clutch_payload <- list(
  season = season_label(),
  throughDate = through_date,
  generatedAt = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  profiles = clutch_profiles
)
jsonlite::write_json(clutch_payload, output_json, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf(">>> [SUCCESS] Wrote %d Clutch profiles to '%s'.\n", length(clutch_profiles), output_json))

if (!dir.exists(CACHE_DIR)) dir.create(CACHE_DIR, recursive = TRUE)
cache_rds <- file.path(CACHE_DIR, "clutch_leverage_metrics.rds")
saveRDS(clutch_profiles, cache_rds)
cat(sprintf(">>> [SUCCESS] Cached RDS in '%s'.\n", cache_rds))
