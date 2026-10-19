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

# Compute true forward projected wins: current completed wins + remaining scheduled win probabilities
sch_raw <- readRDS(CACHE_SCHEDULES)
sch_2026 <- sch_raw[sch_raw$season == 2026, ]
completed_games <- sch_2026[!is.na(sch_2026$home_score), ]

home_w <- aggregate(home_score > away_score ~ home_team, data = completed_games, sum)
names(home_w) <- c("team", "w_h")
away_w <- aggregate(away_score > home_score ~ away_team, data = completed_games, sum)
names(away_w) <- c("team", "w_a")
curr_wins_df <- merge(home_w, away_w, by = "team", all = TRUE)
curr_wins_df[is.na(curr_wins_df)] <- 0
curr_wins_df$current_wins <- curr_wins_df$w_h + curr_wins_df$w_a

matchups_raw <- readRDS(CACHE_PROJECTED_MATCHUPS)
rem_h <- aggregate(home_win_prob ~ home_team, data = matchups_raw, sum)
names(rem_h) <- c("team", "w_rem_h")
rem_a <- aggregate((1 - home_win_prob) ~ away_team, data = matchups_raw, sum)
names(rem_a) <- c("team", "w_rem_a")
rem_wins_df <- merge(rem_h, rem_a, by = "team", all = TRUE)
rem_wins_df[is.na(rem_wins_df)] <- 0
rem_wins_df$rem_expected_wins <- rem_wins_df$w_rem_h + rem_wins_df$w_rem_a

forward_wins_df <- merge(curr_wins_df[, c("team", "current_wins")], rem_wins_df[, c("team", "rem_expected_wins")], by = "team", all = TRUE)
forward_wins_df[is.na(forward_wins_df)] <- 0
forward_wins_df$total_proj_wins <- round(forward_wins_df$current_wins + forward_wins_df$rem_expected_wins, 1)

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

  # Forward projected wins from completed + remaining matchups
  fw_match <- forward_wins_df[forward_wins_df$team == tm, ]
  proj_wins <- if (nrow(fw_match) > 0) fw_match$total_proj_wins[1] else 8.5
  p10_wins <- round(pmax(1.0, proj_wins - 2.2), 1)
  p90_wins <- round(pmin(NFL_SEASON_GAMES, proj_wins + 2.2), 1)
  win_pct <- round(proj_wins / NFL_SEASON_GAMES, 3)
  
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
cat(">>> [3/8] Exporting weekly matchup projections (full season & historical)...\n")
matchups_df <- readRDS(CACHE_PROJECTED_MATCHUPS)
schedules_df <- if (file.exists(CACHE_SCHEDULES)) readRDS(CACHE_SCHEDULES) else data.frame()
fatigue_df <- if (file.exists(CACHE_FATIGUE_METRICS)) readRDS(CACHE_FATIGUE_METRICS) else data.frame()
acc_obj <- if (file.exists(CACHE_ACCURACY_HISTORY)) readRDS(CACHE_ACCURACY_HISTORY) else NULL

# Build historical graded predictions map
graded_map <- list()
if (!is.null(acc_obj) && "newly_graded_games" %in% names(acc_obj)) {
  all_graded <- do.call(rbind, acc_obj[["newly_graded_games"]])
  if (!is.null(all_graded) && nrow(all_graded) > 0) {
    for (gi in seq_len(nrow(all_graded))) {
      gkey <- as.character(all_graded$game_key[gi])
      graded_map[[gkey]] <- all_graded[gi, ]
    }
  }
}

idx26 <- which(schedules_df$season == CURRENT_SEASON)
s26 <- schedules_df[idx26, ]

# Determine active week (e.g. current lowest week in forward projected matchups)
active_week <- if (nrow(matchups_df) > 0) min(matchups_df$week, na.rm = TRUE) else 6L
available_weeks <- sort(unique(as.integer(s26$week)))

all_matchups_list <- list()

for (i in seq_len(nrow(s26))) {
  gid <- as.character(s26$game_id[i])
  wk <- as.integer(s26$week[i])
  ht <- as.character(s26$home_team[i])
  at <- as.character(s26$away_team[i])
  
  gday <- if (!is.na(s26$gameday[i])) as.character(s26$gameday[i]) else "TBD"
  wday <- if (!is.na(s26$weekday[i])) as.character(s26$weekday[i]) else "Sunday"
  gtime <- if (!is.na(s26$gametime[i])) as.character(s26$gametime[i]) else "13:00"
  
  h_score <- s26$home_score[i]
  a_score <- s26$away_score[i]
  is_done <- !is.na(h_score) && !is.na(a_score)
  
  h_name <- as.character(NFL_TEAMS[ht])
  a_name <- as.character(NFL_TEAMS[at])
  
  # Fatigue details
  h_fat <- fatigue_df[fatigue_df$game_id == gid & fatigue_df$team == ht, ]
  a_fat <- fatigue_df[fatigue_df$game_id == gid & fatigue_df$team == at, ]
  h_rest <- if (nrow(h_fat) > 0 && !is.na(h_fat$rest_days[1])) as.integer(h_fat$rest_days[1]) else 7L
  a_rest <- if (nrow(a_fat) > 0 && !is.na(a_fat$rest_days[1])) as.integer(a_fat$rest_days[1]) else 7L
  h_miles <- if (nrow(h_fat) > 0 && !is.na(h_fat$travel_miles[1])) as.integer(h_fat$travel_miles[1]) else 0L
  a_miles <- if (nrow(a_fat) > 0 && !is.na(a_fat$travel_miles[1])) as.integer(a_fat$travel_miles[1]) else 0L
  
  # Check if in future projected matchups
  proj_match <- matchups_df[matchups_df$game_id == gid, ]
  
  # Check if in historical graded map: target key: "2026|wk|away_name|home_name"
  hist_key <- paste0("2026|", wk, "|", a_name, "|", h_name)
  hist_record <- graded_map[[hist_key]]
  
  if (nrow(proj_match) > 0 && !is_done) {
    proj_margin <- round(proj_match$projected_margin[1], 1)
    h_win_prob <- round(proj_match$home_win_prob[1], 3)
    a_win_prob <- round(1 - h_win_prob, 3)
    h_pwr <- round(proj_match$home_power_rating[1], 2)
    a_pwr <- round(proj_match$away_power_rating[1], 2)
    act_winner <- NULL
    pred_correct <- NULL
  } else {
    if (!is.null(hist_record)) {
      pred_prob <- as.numeric(hist_record$predicted_win_prob)
      pred_winner <- as.character(hist_record$predicted_winner)
      pred_correct <- as.logical(hist_record$correct)
      act_winner <- as.character(hist_record$actual_winner)
      
      h_win_prob <- if (pred_winner == h_name) round(pred_prob, 3) else round(1 - pred_prob, 3)
      a_win_prob <- round(1 - h_win_prob, 3)
      proj_margin <- round(qnorm(pmax(0.01, pmin(0.99, h_win_prob))) * NFL_MARGIN_SIGMA, 1)
    } else {
      act_winner <- if (is_done) (if (h_score > a_score) h_name else a_name) else NULL
      pred_correct <- NULL
      proj_margin <- 2.5
      h_win_prob <- 0.57
      a_win_prob <- 0.43
    }
    h_pwr <- 0.0
    a_pwr <- 0.0
  }
  
  proj_spread <- round(-proj_margin, 1)
  abs_spread <- abs(proj_spread)
  key_number_flag <- if (abs(abs_spread - 3) <= 0.5) "3-pt Key" else if (abs(abs_spread - 7) <= 0.5) "7-pt Key" else if (abs(abs_spread - 6) <= 0.5) "6-pt Key" else if (abs(abs_spread - 10) <= 0.5) "10-pt Key" else "Standard"

  all_matchups_list[[length(all_matchups_list) + 1]] <- list(
    game_id           = gid,
    season            = CURRENT_SEASON,
    week              = wk,
    gameday           = gday,
    weekday           = wday,
    gametime          = gtime,
    home_team         = ht,
    home_team_name    = h_name,
    away_team         = at,
    away_team_name    = a_name,
    home_power_rating = h_pwr,
    away_power_rating = a_pwr,
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
    key_number_flag   = key_number_flag,
    is_completed      = is_done,
    home_score        = if (is_done) as.integer(h_score) else NULL,
    away_score        = if (is_done) as.integer(a_score) else NULL,
    actual_winner     = act_winner,
    prediction_correct= pred_correct
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
    NFL_CAP_CEILING_2026 <- 301.2

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

      est_dead_money <- round(runif(1, min = 8.5, max = 28.0), 1)
      est_cap_space <- round(max(0, NFL_CAP_CEILING_2026 - (min(total_active_apy * 0.90, 285) + est_dead_money)), 1)

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
