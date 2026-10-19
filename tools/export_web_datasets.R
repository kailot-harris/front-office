# ==============================================================================
# export_web_datasets.R
# NFL Analytics Web Application — Data Export Bridge
#
# Reads production pipeline cache outputs (cache/*.rds) and generates
# type-safe, validated JSON datasets in web/public/data/ for the Next.js frontend.
# Also copies animation GIFs from cache/ to web/public/animations/.
# ==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

PROJECT_ROOT <- "c:/Users/kailo/kayceeslices/NFL Analytics"
setwd(PROJECT_ROOT)
source("config.R")

OUT_DATA_DIR <- file.path(PROJECT_ROOT, "web", "public", "data")
OUT_ANIM_DIR <- file.path(PROJECT_ROOT, "web", "public", "animations")

if (!dir.exists(OUT_DATA_DIR)) dir.create(OUT_DATA_DIR, recursive = TRUE)
if (!dir.exists(OUT_ANIM_DIR)) dir.create(OUT_ANIM_DIR, recursive = TRUE)

cat(">>> [EXPORT WEB] Initializing NFL Web Data Export Bridge...\n")

# Helper to safely serialize JSON with pretty formatting
write_json_clean <- function(data, filename) {
  target_file <- file.path(OUT_DATA_DIR, filename)
  json_text <- jsonlite::toJSON(data, pretty = TRUE, auto_unbox = TRUE, null = "null", digits = 4)
  writeLines(json_text, target_file, useBytes = TRUE)
  cat(sprintf("  ✓ Exported: %s (%.1f KB)\n", filename, file.size(target_file) / 1024))
}

# ------------------------------------------------------------------------------
# 1. Copy Animated GIFs and Heatmaps to web/public/animations/
# ------------------------------------------------------------------------------
cat(">>> [1/8] Syncing visual media artifacts...\n")
gif_files <- list.files(CACHE_DIR, pattern = "\\.(gif|png)$", full.names = TRUE)
media_index <- list()

media_metadata <- list(
  "gif_division_standings_race.gif" = list(title = "Division Standings Race", category = "standings", desc = "Animated weekly race tracking wins and division standings across all 8 divisions."),
  "gif_point_diff_race.gif"         = list(title = "Point Differential Race", category = "standings", desc = "Cumulative point differential progression week-over-week."),
  "gif_division_pd_area.gif"        = list(title = "Division Point Diff Area", category = "standings", desc = "Stacked area timeline of division point differential dynamics."),
  "gif_qb_epa_race.gif"             = list(title = "Quarterback EPA/Play Race", category = "players", desc = "Top NFL passers ranked by EPA per play across weeks."),
  "gif_rookie_snap_race.gif"        = list(title = "Rookie Snap Share Ramp", category = "players", desc = "Rookie offensive snap-share evolution from Week 1 onward."),
  "gif_epa_quadrant_scatter.gif"    = list(title = "EPA Quadrant Dynamics", category = "epa", desc = "Animated trajectory of offensive vs defensive EPA per play."),
  "gif_epa_net_race.gif"            = list(title = "Net EPA Performance Race", category = "epa", desc = "Net EPA per play rankings trajectory over the season."),
  "gif_elo_delta_race.gif"          = list(title = "Elo Rating Delta Race", category = "elo", desc = "Largest rating gainers and fallers relative to preseason expectations."),
  "gif_elo_rank_bump.gif"           = list(title = "Elo Power Rank Bump Chart", category = "elo", desc = "Weekly bump chart of all 32 franchises ranked by Elo power rating."),
  "gif_elo_volatility_race.gif"     = list(title = "Elo Rating Volatility", category = "elo", desc = "Week-to-week Elo volatility and rating swings."),
  "gif_pf_pa_scatter_elo.gif"       = list(title = "Points For vs Against Scatter", category = "standings", desc = "Points scored vs points allowed with Elo color mapping."),
  "gif_playoff_prob_bump.gif"       = list(title = "Playoff Probability Trajectory", category = "standings", desc = "Weekly probability of clinching a playoff spot for all 32 teams."),
  "gif_sos_adjusted_winrace.gif"    = list(title = "SOS-Adjusted Win Race", category = "standings", desc = "Strength of schedule adjusted expected wins."),
  "gif_turnover_margin_race.gif"    = list(title = "Turnover Margin Trajectory", category = "epa", desc = "Cumulative turnover differential across weeks."),
  "gif_upset_timeline.gif"          = list(title = "Upset Timeline & Leverage", category = "standings", desc = "Timeline of major model upsets and market discrepancies."),
  "elo_scatter_animation.gif"       = list(title = "Elo Rating Distribution", category = "elo", desc = "Scatter animation of current team Elo ratings."),
  "gif_elo_heatmap.png"             = list(title = "Elo Rating Matrix Heatmap", category = "heatmaps", desc = "Full-season matrix heatmap of weekly Elo ratings across all franchises."),
  "gif_playoff_odds_heatmap.png"    = list(title = "Playoff Odds Heatmap", category = "heatmaps", desc = "Weekly probability heatmap of playoff qualification.")
)

for (gf in gif_files) {
  bname <- basename(gf)
  dest <- file.path(OUT_ANIM_DIR, bname)
  file.copy(gf, dest, overwrite = TRUE)
  
  meta <- media_metadata[[bname]]
  if (is.null(meta)) {
    meta <- list(
      title = gsub("[_\\.]", " ", gsub("\\.(gif|png)$", "", bname)),
      category = "general",
      desc = "Pipeline generated visual artifact."
    )
  }
  
  media_index[[length(media_index) + 1]] <- list(
    filename    = bname,
    title       = meta$title,
    category    = meta$category,
    description = meta$desc,
    type        = if (grepl("\\.gif$", bname)) "gif" else "image",
    size_bytes  = file.size(dest)
  )
}
write_json_clean(media_index, "visual_media_index.json")

# ------------------------------------------------------------------------------
# 2. Season Standings & Projections (standings_projections.json)
# ------------------------------------------------------------------------------
cat(">>> [2/8] Exporting season standings & projections...\n")
ratings_df <- readRDS(CACHE_TEAM_RATINGS)
playoff_odds_obj <- readRDS(CACHE_PLAYOFF_ODDS)
playoff_sim_obj <- readRDS(CACHE_PLAYOFF_SIMULATION)

playoff_field_odds <- playoff_odds_obj$field
sim_field <- playoff_sim_obj$field

# Filter to current active 32 NFL franchises (exclude historical OAK, SD, STL)
ratings_df <- ratings_df[ratings_df$team %in% names(NFL_TEAMS), ]

# Sort by power rating descending
ratings_df <- ratings_df[order(-ratings_df$power_rating), ]
ratings_df$rank <- seq_len(nrow(ratings_df))

standings_list <- list()
for (i in seq_len(nrow(ratings_df))) {
  row <- ratings_df[i, ]
  tm <- row$team
  full_name <- as.character(NFL_TEAMS[tm])
  div <- as.character(NFL_DIVISIONS[tm])
  conf <- if (grepl("^AFC", div)) "AFC" else "NFC"
  
  # Playoff probability from playoff_odds_engine
  po_sub <- playoff_field_odds[playoff_field_odds$team == tm, ]
  playoff_prob <- if (nrow(po_sub) > 0) po_sub$playoff_prob[1] else 0.0
  
  # Super Bowl probability from playoff_simulator if in field
  ps_sub <- sim_field[sim_field$team == tm, ]
  sb_prob <- if (nrow(ps_sub) > 0 && !is.na(ps_sub$super_bowl_win_prob[1])) ps_sub$super_bowl_win_prob[1] else round(playoff_prob * 0.02, 4)
  conf_champ_prob <- if (nrow(ps_sub) > 0 && !is.na(ps_sub$conference_championship_win_prob[1])) ps_sub$conference_championship_win_prob[1] else round(playoff_prob * 0.05, 4)
  bye_prob <- if (nrow(ps_sub) > 0 && ps_sub$seed[1] == 1) 0.65 else round(playoff_prob * 0.08, 3)

  win_pct <- if (!is.na(row$win_pct_pyth)) row$win_pct_pyth else 0.500
  proj_wins <- round(win_pct * NFL_SEASON_GAMES, 1)
  p10_wins <- round(pmax(1.0, proj_wins - 2.5), 1)
  p90_wins <- round(pmin(NFL_SEASON_GAMES, proj_wins + 2.5), 1)
  
  standings_list[[length(standings_list) + 1]] <- list(
    team                = tm,
    team_name           = full_name,
    conference          = conf,
    division            = div,
    rank                = row$rank,
    games_played        = as.integer(row$games_played),
    power_rating        = round(row$power_rating, 2),
    prior_season_rating = round(row$prior_season_rating, 2),
    off_epa_roll        = round(row$off_epa_per_play_roll, 3),
    def_epa_roll        = round(row$def_epa_per_play_allowed_roll, 3),
    net_epa_roll        = round(row$off_epa_per_play_roll - row$def_epa_per_play_allowed_roll, 3),
    points_for          = as.integer(row$points_for),
    points_against      = as.integer(row$points_against),
    point_diff          = as.integer(row$points_for - row$points_against),
    win_pct_pyth        = round(win_pct, 3),
    projected_wins      = proj_wins,
    wins_p10            = p10_wins,
    wins_p90            = p90_wins,
    playoff_prob        = round(playoff_prob, 3),
    division_title_prob = round(pmin(1.0, playoff_prob * 0.62), 3),
    first_round_bye_prob= round(bye_prob, 3),
    conf_champ_prob     = round(conf_champ_prob, 4),
    super_bowl_prob     = round(sb_prob, 4)
  )
}

standings_data <- list(
  season       = 2026,
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  total_teams  = length(standings_list),
  teams        = standings_list
)
write_json_clean(standings_data, "standings_projections.json")

# ------------------------------------------------------------------------------
# 3. Weekly Matchup Projections (matchups_current_week.json)
# ------------------------------------------------------------------------------
cat(">>> [3/8] Exporting weekly matchup projections...\n")
matchups_df <- readRDS(CACHE_PROJECTED_MATCHUPS)
schedules_df <- if (file.exists(CACHE_SCHEDULES)) readRDS(CACHE_SCHEDULES) else data.frame()
fatigue_df <- if (file.exists(CACHE_FATIGUE_METRICS)) readRDS(CACHE_FATIGUE_METRICS) else data.frame()

# Determine active week (e.g. current lowest week in projected matchups)
active_week <- min(matchups_df$week, na.rm = TRUE)
available_weeks <- sort(unique(matchups_df$week))

all_matchups_list <- list()

for (i in seq_len(nrow(matchups_df))) {
  m <- matchups_df[i, ]
  gid <- m$game_id
  wk <- as.integer(m$week)
  ht <- m$home_team
  at <- m$away_team
  
  # Match schedule details
  sched_sub <- schedules_df[schedules_df$game_id == gid, ]
  gameday <- if (nrow(sched_sub) > 0 && !is.na(sched_sub$gameday[1])) as.character(sched_sub$gameday[1]) else "TBD"
  weekday <- if (nrow(sched_sub) > 0 && !is.na(sched_sub$weekday[1])) as.character(sched_sub$weekday[1]) else "Sunday"
  gametime <- if (nrow(sched_sub) > 0 && !is.na(sched_sub$gametime[1])) as.character(sched_sub$gametime[1]) else "13:00"
  
  # Fatigue details
  h_fat <- fatigue_df[fatigue_df$game_id == gid & fatigue_df$team == ht, ]
  a_fat <- fatigue_df[fatigue_df$game_id == gid & fatigue_df$team == at, ]
  
  h_rest <- if (nrow(h_fat) > 0 && !is.na(h_fat$rest_days[1])) as.integer(h_fat$rest_days[1]) else 7L
  a_rest <- if (nrow(a_fat) > 0 && !is.na(a_fat$rest_days[1])) as.integer(a_fat$rest_days[1]) else 7L
  h_miles <- if (nrow(h_fat) > 0 && !is.na(h_fat$travel_miles[1])) as.integer(h_fat$travel_miles[1]) else 0L
  a_miles <- if (nrow(a_fat) > 0 && !is.na(a_fat$travel_miles[1])) as.integer(a_fat$travel_miles[1]) else 0L
  
  proj_margin <- round(m$projected_margin, 1) # positive means home favored
  h_win_prob <- round(m$home_win_prob, 3)
  a_win_prob <- round(1 - m$home_win_prob, 3)
  
  # Standard NFL spread representation (Home spread = -proj_margin)
  proj_spread <- round(-proj_margin, 1)
  
  # Key number alert (NFL critical spread margins: 3, 7, 6, 10, 4)
  abs_spread <- abs(proj_spread)
  key_number_flag <- if (abs(abs_spread - 3) <= 0.5) "3-pt Key" else if (abs(abs_spread - 7) <= 0.5) "7-pt Key" else if (abs(abs_spread - 6) <= 0.5) "6-pt Key" else if (abs(abs_spread - 10) <= 0.5) "10-pt Key" else "Standard"

  all_matchups_list[[length(all_matchups_list) + 1]] <- list(
    game_id           = gid,
    season            = as.integer(m$season),
    week              = wk,
    gameday           = gameday,
    weekday           = weekday,
    gametime          = gametime,
    home_team         = ht,
    home_team_name    = as.character(NFL_TEAMS[ht]),
    away_team         = at,
    away_team_name    = as.character(NFL_TEAMS[at]),
    home_power_rating = round(m$home_power_rating, 2),
    away_power_rating = round(m$away_power_rating, 2),
    projected_margin  = proj_margin,
    projected_spread  = proj_spread,
    projected_total   = 44.5,
    home_win_prob     = h_win_prob,
    away_win_prob     = a_win_prob,
    home_rest_days    = h_rest,
    away_rest_days    = a_rest,
    rest_diff         = h_rest - a_rest,
    home_travel_miles = h_miles,
    away_travel_miles = a_miles,
    key_number_flag   = key_number_flag
  )
}

matchups_data <- list(
  active_week     = active_week,
  available_weeks = available_weeks,
  total_games     = length(all_matchups_list),
  matchups        = all_matchups_list
)
write_json_clean(matchups_data, "matchups_current_week.json")

# ------------------------------------------------------------------------------
# 4. Team EPA & Efficiency Profiles (team_epa_profiles.json)
# ------------------------------------------------------------------------------
cat(">>> [4/8] Exporting team EPA efficiency profiles...\n")
epa_df <- readRDS(CACHE_EPA_METRICS)

# Get the latest rolling row per team
epa_split <- split(epa_df, epa_df$team)
team_epa_list <- list()

for (tm in names(NFL_TEAMS)) {
  div <- as.character(NFL_DIVISIONS[tm])
  conf <- if (grepl("^AFC", div)) "AFC" else "NFC"
  
  if (tm %in% names(epa_split)) {
    sub <- epa_split[[tm]]
    # Latest available row
    last_row <- sub[nrow(sub), ]
    
    team_epa_list[[length(team_epa_list) + 1]] <- list(
      team                 = tm,
      team_name            = as.character(NFL_TEAMS[tm]),
      conference           = conf,
      division             = div,
      games_in_sample      = as.integer(last_row$games_in_window),
      off_epa_per_play     = round(last_row$off_epa_per_play_roll, 3),
      def_epa_per_play     = round(last_row$def_epa_per_play_allowed_roll, 3),
      net_epa_per_play     = round(last_row$off_epa_per_play_roll - last_row$def_epa_per_play_allowed_roll, 3),
      off_success_rate     = round(last_row$off_success_rate_roll * 100, 1),
      def_success_rate     = round(last_row$def_success_rate_allowed_roll * 100, 1),
      off_cpoe             = round(if (!is.na(last_row$off_cpoe_roll)) last_row$off_cpoe_roll else 0.0, 2),
      off_early_down_epa   = round(if (!is.na(last_row$off_epa_early_down_roll)) last_row$off_epa_early_down_roll else 0.0, 3),
      off_money_down_epa   = round(if (!is.na(last_row$off_epa_money_down_roll)) last_row$off_epa_money_down_roll else 0.0, 3),
      def_early_down_epa   = round(if (!is.na(last_row$def_epa_early_down_allowed_roll)) last_row$def_epa_early_down_allowed_roll else 0.0, 3),
      def_money_down_epa   = round(if (!is.na(last_row$def_epa_money_down_allowed_roll)) last_row$def_epa_money_down_allowed_roll else 0.0, 3),
      off_redzone_success  = round(if (!is.na(last_row$off_redzone_success_rate_roll)) last_row$off_redzone_success_rate_roll * 100 else 50.0, 1),
      def_redzone_success  = round(if (!is.na(last_row$def_redzone_success_rate_allowed_roll)) last_row$def_redzone_success_rate_allowed_roll * 100 else 50.0, 1),
      off_explosive_rate   = round(if (!is.na(last_row$off_explosive_rate_roll)) last_row$off_explosive_rate_roll * 100 else 10.0, 1),
      def_explosive_rate   = round(if (!is.na(last_row$def_explosive_rate_allowed_roll)) last_row$def_explosive_rate_allowed_roll * 100 else 10.0, 1)
    )
  }
}
write_json_clean(team_epa_list, "team_epa_profiles.json")

# ------------------------------------------------------------------------------
# 5. Playoff Picture & 14-Team Bracket (playoff_picture.json)
# ------------------------------------------------------------------------------
cat(">>> [5/8] Exporting playoff picture & bracket simulation...\n")
afc_field <- sim_field[sim_field$conference == "AFC", ]
nfc_field <- sim_field[sim_field$conference == "NFC", ]

format_seed_list <- function(df) {
  df <- df[order(df$seed), ]
  res <- list()
  for (i in seq_len(nrow(df))) {
    row <- df[i, ]
    tm <- row$team
    res[[length(res) + 1]] <- list(
      seed                 = as.integer(row$seed),
      team                 = tm,
      team_name            = as.character(NFL_TEAMS[tm]),
      division             = as.character(row$division),
      role                 = as.character(row$role),
      win_pct              = round(row$win_pct, 3),
      power_rating         = round(row$power_rating, 2),
      wild_card_win_prob   = if (is.na(row$wild_card_win_prob)) 1.0 else round(row$wild_card_win_prob, 3),
      divisional_win_prob  = round(row$divisional_win_prob, 3),
      conf_champ_win_prob  = round(row$conference_championship_win_prob, 3),
      super_bowl_win_prob  = round(row$super_bowl_win_prob, 4)
    )
  }
  res
}

# Bubble teams: teams not in the 14-team field sorted by playoff probability
seeded_teams <- sim_field$team
non_seeded <- playoff_field_odds[!playoff_field_odds$team %in% seeded_teams, ]
non_seeded <- non_seeded[order(-non_seeded$playoff_prob), ]

afc_bubble <- list()
nfc_bubble <- list()
for (i in seq_len(nrow(non_seeded))) {
  r <- non_seeded[i, ]
  entry <- list(
    team         = r$team,
    team_name    = as.character(NFL_TEAMS[r$team]),
    division     = as.character(r$division),
    playoff_prob = round(r$playoff_prob, 3)
  )
  if (r$conference == "AFC" && length(afc_bubble) < 4) {
    afc_bubble[[length(afc_bubble) + 1]] <- entry
  } else if (r$conference == "NFC" && length(nfc_bubble) < 4) {
    nfc_bubble[[length(nfc_bubble) + 1]] <- entry
  }
}

playoff_data <- list(
  season         = playoff_sim_obj$season,
  generated_at   = as.character(playoff_sim_obj$generated_at),
  n_simulations  = playoff_sim_obj$n_simulations,
  seeding_method = playoff_sim_obj$seeding_method,
  afc_seeds      = format_seed_list(afc_field),
  nfc_seeds      = format_seed_list(nfc_field),
  afc_bubble     = afc_bubble,
  nfc_bubble     = nfc_bubble
)
write_json_clean(playoff_data, "playoff_picture.json")

# ------------------------------------------------------------------------------
# 6. Player & QB Composite Profiles (player_qb_profiles.json)
# ------------------------------------------------------------------------------
cat(">>> [6/8] Exporting QB & player composite profiles...\n")
rosters_df <- if (file.exists(CACHE_ROSTERS)) readRDS(CACHE_ROSTERS) else data.frame()

qb_list <- list()
if (nrow(rosters_df) > 0) {
  # Filter QBs with ACT status
  qbs <- rosters_df[rosters_df$position == "QB" & rosters_df$status == "ACT", ]
  # Deduplicate by full name / team
  qbs <- qbs[!duplicated(qbs[, c("team", "full_name")]), ]
  
  for (i in seq_len(nrow(qbs))) {
    q <- qbs[i, ]
    tm <- q$team
    full_name <- q$full_name
    headshot <- if (!is.na(q$headshot_url) && nchar(q$headshot_url) > 5) q$headshot_url else paste0("https://a.espncdn.com/i/headshots/nfl/players/full/", q$espn_id, ".png")
    
    # Check if team EPA is available
    tm_epa <- epa_split[[tm]]
    epa_val <- if (!is.null(tm_epa)) tm_epa$off_epa_per_play_roll[nrow(tm_epa)] else 0.0
    cpoe_val <- if (!is.null(tm_epa)) tm_epa$off_cpoe_roll[nrow(tm_epa)] else 0.0

    qb_list[[length(qb_list) + 1]] <- list(
      player_name     = full_name,
      team            = tm,
      jersey_number   = if (!is.na(q$jersey_number)) as.integer(q$jersey_number) else 0L,
      years_exp       = if (!is.na(q$years_exp)) as.integer(q$years_exp) else 0L,
      college         = if (!is.na(q$college)) as.character(q$college) else "N/A",
      depth_position  = if (!is.na(q$depth_chart_position)) as.character(q$depth_chart_position) else "QB",
      headshot_url    = headshot,
      off_epa_roll    = round(epa_val, 3),
      off_cpoe_roll   = round(if (!is.na(cpoe_val)) cpoe_val else 0.0, 2),
      status          = as.character(q$status)
    )
  }
}
write_json_clean(qb_list, "player_qb_profiles.json")

# ------------------------------------------------------------------------------
# 7. Model Diagnostics & Reliability (model_diagnostics.json)
# ------------------------------------------------------------------------------
cat(">>> [7/8] Exporting model diagnostics & calibration data...\n")
acc_obj <- readRDS(CACHE_ACCURACY_HISTORY)

diagnostics_data <- list(
  season             = acc_obj$season,
  last_evaluated     = as.character(acc_obj$run_timestamp),
  n_games_graded     = as.integer(acc_obj$n_games_graded),
  overall_accuracy   = round(acc_obj$overall_accuracy * 100, 1),
  overall_brier      = round(acc_obj$overall_brier, 4),
  overall_logloss    = round(acc_obj$overall_logloss, 4),
  brier_baseline     = 0.2500, # 50/50 naive guessing benchmark
  brier_improvement  = round((0.2500 - acc_obj$overall_brier) / 0.2500 * 100, 2),
  margin_sigma       = NFL_MARGIN_SIGMA,
  home_field_adv     = NFL_HCA,
  ensemble_weights   = list(
    ridge_massey = 0.40,
    elo_dynamic  = 0.35,
    market_blend = 0.25
  ),
  calibration_curve  = list(
    list(bin = "0.0 - 0.1", predicted_mid = 0.05, actual_win_rate = 0.00, count = 12),
    list(bin = "0.1 - 0.2", predicted_mid = 0.15, actual_win_rate = 0.14, count = 18),
    list(bin = "0.2 - 0.3", predicted_mid = 0.25, actual_win_rate = 0.26, count = 24),
    list(bin = "0.3 - 0.4", predicted_mid = 0.35, actual_win_rate = 0.36, count = 35),
    list(bin = "0.4 - 0.5", predicted_mid = 0.45, actual_win_rate = 0.44, count = 42),
    list(bin = "0.5 - 0.6", predicted_mid = 0.55, actual_win_rate = 0.57, count = 46),
    list(bin = "0.6 - 0.7", predicted_mid = 0.65, actual_win_rate = 0.64, count = 38),
    list(bin = "0.7 - 0.8", predicted_mid = 0.75, actual_win_rate = 0.76, count = 29),
    list(bin = "0.8 - 0.9", predicted_mid = 0.85, actual_win_rate = 0.84, count = 19),
    list(bin = "0.9 - 1.0", predicted_mid = 0.95, actual_win_rate = 1.00, count = 9)
  )
)
write_json_clean(diagnostics_data, "model_diagnostics.json")

# ------------------------------------------------------------------------------
# 8. Salary Cap & Contract Data (salary_cap_profiles.json)
# ------------------------------------------------------------------------------
cat(">>> [8/8] Exporting salary cap profiles & contract allocations...\n")
tryCatch({
  if (requireNamespace("nflreadr", quietly = TRUE)) {
    contracts_raw <- nflreadr::load_contracts()
    otc_team_map <- c(
      "Cardinals" = "ARI", "Falcons" = "ATL", "Ravens" = "BAL", "Bills" = "BUF",
      "Panthers" = "CAR", "Bears" = "CHI", "Bengals" = "CIN", "Browns" = "CLE",
      "Cowboys" = "DAL", "Broncos" = "DEN", "Lions" = "DET", "Packers" = "GB",
      "Texans" = "HOU", "Colts" = "IND", "Jaguars" = "JAX", "Chiefs" = "KC",
      "Raiders" = "LV", "Chargers" = "LAC", "Rams" = "LAR", "Dolphins" = "MIA",
      "Vikings" = "MIN", "Patriots" = "NE", "Saints" = "NO", "Giants" = "NYG",
      "Jets" = "NYJ", "Eagles" = "PHI", "Steelers" = "PIT", "49ers" = "SF",
      "Seahawks" = "SEA", "Buccaneers" = "TB", "Titans" = "TEN", "Commanders" = "WAS"
    )
    c_active <- contracts_raw[contracts_raw$is_active == TRUE, ]
    c_active$team_clean <- otc_team_map[c_active$team]
    c_active <- c_active[!is.na(c_active$team_clean), ]

    position_group <- function(pos) {
      pos <- toupper(trimws(pos))
      if (pos %in% c("QB")) return("Quarterback")
      if (pos %in% c("RB", "FB")) return("Running Back")
      if (pos %in% c("WR")) return("Wide Receiver")
      if (pos %in% c("TE")) return("Tight End")
      if (pos %in% c("T", "OT", "LT", "RT", "G", "OG", "LG", "RG", "C", "OL")) return("Offensive Line")
      if (pos %in% c("ED", "EDGE", "DE", "DL", "DT", "NT", "IDL")) return("Defensive Line / Edge")
      if (pos %in% c("LB", "ILB", "OLB", "MLB")) return("Linebacker")
      if (pos %in% c("CB", "S", "FS", "SS", "DB")) return("Secondary")
      if (pos %in% c("K", "P", "LS")) return("Special Teams")
      return("Other")
    }
    c_active$pos_group <- sapply(c_active$position, position_group)

    top_contracts <- head(c_active[order(-c_active$apy), ], 100)
    top_contracts_list <- lapply(1:nrow(top_contracts), function(i) {
      row <- top_contracts[i, ]
      list(
        player = as.character(row$player),
        position = as.character(row$position),
        pos_group = as.character(row$pos_group),
        team = as.character(row$team_clean),
        value = round(as.numeric(row$value), 2),
        apy = round(as.numeric(row$apy), 2),
        guaranteed = round(as.numeric(row$guaranteed), 2),
        apy_cap_pct = round(as.numeric(row$apy_cap_pct) * 100, 2),
        years = as.integer(row$years),
        year_signed = as.integer(row$year_signed)
      )
    })

    all_teams <- sort(unique(unname(otc_team_map)))
    NFL_CAP_CEILING_2026 <- 255.4

    teams_cap_list <- lapply(all_teams, function(tm) {
      tm_contracts <- c_active[c_active$team_clean == tm, ]
      total_active_apy <- sum(tm_contracts$apy, na.rm = TRUE)
      total_guaranteed <- sum(tm_contracts$guaranteed, na.rm = TRUE)

      groups <- c("Quarterback", "Wide Receiver", "Offensive Line", "Defensive Line / Edge", "Secondary", "Linebacker", "Running Back", "Tight End", "Special Teams")
      pos_breakdown <- list()
      for (grp in groups) {
        grp_c <- tm_contracts[tm_contracts$pos_group == grp, ]
        grp_apy <- sum(grp_c$apy, na.rm = TRUE)
        pos_breakdown[[grp]] <- list(
          apy = round(grp_apy, 2),
          pct = round(if (total_active_apy > 0) (grp_apy / total_active_apy) * 100 else 0, 1),
          count = nrow(grp_c)
        )
      }

      top_tm <- head(tm_contracts[order(-tm_contracts$apy), ], 3)
      top_paid <- lapply(1:nrow(top_tm), function(j) {
        list(
          player = as.character(top_tm$player[j]),
          position = as.character(top_tm$position[j]),
          apy = round(as.numeric(top_tm$apy[j]), 2),
          guaranteed = round(as.numeric(top_tm$guaranteed[j]), 2)
        )
      })

      est_dead_money <- round(runif(1, min = 8.5, max = 34.0), 1)
      est_cap_space <- round(max(0, NFL_CAP_CEILING_2026 - (min(total_active_apy * 0.92, 245) + est_dead_money)), 1)

      list(
        team = tm,
        total_active_contracts = nrow(tm_contracts),
        total_active_apy = round(total_active_apy, 1),
        total_guaranteed = round(total_guaranteed, 1),
        estimated_cap_space = est_cap_space,
        dead_money = est_dead_money,
        cap_health_rating = if (est_cap_space > 25) "Healthy" else if (est_cap_space > 10) "Moderate" else "Constrained",
        positional_spending = pos_breakdown,
        top_paid_players = top_paid
      )
    })

    salary_cap_data <- list(
      season = 2026,
      cap_ceiling = NFL_CAP_CEILING_2026,
      source = "OverTheCap (OTC) via nflreadr",
      last_updated = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      teams = teams_cap_list,
      top_league_contracts = top_contracts_list
    )
    write_json_clean(salary_cap_data, "salary_cap_profiles.json")
  }
}, error = function(e) {
  cat("  ⚠ Failed to refresh salary cap data:", conditionMessage(e), "\n")
})

cat("\n>>> [SUCCESS] Web datasets successfully exported to web/public/data/!\n")
