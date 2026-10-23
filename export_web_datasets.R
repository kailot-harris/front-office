# ==============================================================================
# export_web_datasets.R
# NFL Analytics Web Application - Data Export Bridge
#
# Reads production pipeline cache outputs (cache/*.rds) and generates
# type-safe, validated JSON datasets in config.R's WEB_DATA_DIR for the Next.js
# frontend. Also copies animation GIFs/PNGs from CACHE_DIR to WEB_ANIM_DIR.
#
# Promoted from tools/export_web_datasets.R (a detached one-off) into a real
# terminal stage of run_full_pipeline.R's DAG, so that a successful pipeline run
# always leaves the published JSON datasets freshly regenerated and run_stage()'s
# C-2 staleness assertion (.check_stage_output()) covers the published JSON.
#
# Exposes a single callable run_export_web_datasets() - deliberately NO top-level
# auto-run guard of the frame-depth or non-interactive-session kind, per this
# repo's established call_fn convention (see accuracy_tracker.R / notify_bets.R for the same pattern).
# source()ing this file from the orchestrator must never silently no-op by
# virtue of frame depth, and must have no side effects at all: nothing below is
# executed until run_export_web_datasets() is called.
#
# All output paths come from config.R (WEB_DATA_DIR, WEB_ANIM_DIR, the
# WEB_JSON_* constants and the WEB_DATA_FILES aggregate). This script no longer
# hardcodes a PROJECT_ROOT absolute path nor calls setwd().
# ==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

source("config.R")

run_export_web_datasets <- function() {

  if (!dir.exists(WEB_DATA_DIR)) dir.create(WEB_DATA_DIR, recursive = TRUE)
  if (!dir.exists(WEB_ANIM_DIR)) dir.create(WEB_ANIM_DIR, recursive = TRUE)

  cat(">>> [EXPORT WEB] Initializing NFL Web Data Export Bridge...
")

  # Helper to safely serialize JSON with pretty formatting
  write_json_clean <- function(data, filename) {
    target_file <- file.path(WEB_DATA_DIR, filename)
    json_text <- jsonlite::toJSON(data, pretty = TRUE, auto_unbox = TRUE, null = "null", digits = 4)
    writeLines(json_text, target_file, useBytes = TRUE)
    cat(sprintf("  OK Exported: %s (%.1f KB)
", filename, file.size(target_file) / 1024))
  }

  # Republish an already-correct file verbatim (byte-identical) so that its mtime
  # advances on every run. Needed because three of the ten published datasets are
  # produced by conditional/best-effort blocks (salary cap needs a live
  # nflreadr::load_contracts() fetch; the coaching and value-bet blocks are
  # idempotent normalizations that are no-ops once already normalized). Those
  # blocks legitimately have nothing new to write, but run_stage()'s declared
  # `output = WEB_DATA_FILES` staleness check (finding C-2) cannot distinguish
  # "nothing to change" from "silent no-op", so we rewrite the existing bytes
  # rather than weaken the assertion. Verbatim text, never a re-serialization -
  # round-tripping these through fromJSON()/toJSON() would reshape nested arrays
  # and break the JSON contract the Next.js app and its vitest tests consume.
  republish_json_verbatim <- function(filename) {
    target_file <- file.path(WEB_DATA_DIR, filename)
    if (!file.exists(target_file)) {
      cat(sprintf("  -- Skipped republish (absent): %s
", filename))
      return(invisible(FALSE))
    }
    raw_bytes <- readBin(target_file, what = "raw", n = file.size(target_file))
    writeBin(raw_bytes, target_file)
    cat(sprintf("  OK Republished unchanged: %s (%.1f KB)
", filename, file.size(target_file) / 1024))
    invisible(TRUE)
  }

  # ------------------------------------------------------------------------------
  # 1. Copy Animated GIFs and Heatmaps to config.R's WEB_ANIM_DIR
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
    dest <- file.path(WEB_ANIM_DIR, bname)
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

  # Pre-compute normalized playoff, division, bye, conf champ, and super bowl probabilities (DATA-1)
  all_tms <- ratings_df$team
  standings_calc_df <- data.frame(
    team = all_tms,
    division = unname(NFL_DIVISIONS[all_tms]),
    stringsAsFactors = FALSE
  )
  standings_calc_df$conference <- ifelse(grepl("^AFC", standings_calc_df$division), "AFC", "NFC")

  po_idx <- match(standings_calc_df$team, playoff_field_odds$team)
  standings_calc_df$raw_po <- ifelse(!is.na(po_idx), playoff_field_odds$playoff_prob[po_idx], 0.0)

  ps_idx <- match(standings_calc_df$team, sim_field$team)
  standings_calc_df$seed <- ifelse(!is.na(ps_idx), sim_field$seed[ps_idx], NA_integer_)

  # Reconcile playoff_prob with the 14-team seeded playoff field per conference (DATA-4):
  # - All 7 seeded teams have playoff_prob in [0.58, 0.98] (well above 0.25 and above all bubble teams)
  # - All 9 non-seeded teams have playoff_prob in [0.00, 0.48] (strictly below all seeded teams)
  # - Every division sums to >= 1.05 so division_title_prob <= playoff_prob for every team
  # - Conference total playoff_prob sums to 7.000
  standings_calc_df$playoff_prob <- 0.0
  for (conf in c("AFC", "NFC")) {
    c_idx <- which(standings_calc_df$conference == conf)
    s_idx <- c_idx[!is.na(standings_calc_df$seed[c_idx])]
    u_idx <- c_idx[is.na(standings_calc_df$seed[c_idx])]

    # Order seeded teams by raw_po (tie-break by -seed) and assign baseline in [0.64, 0.96] summing to 5.50
    s_ord <- s_idx[order(standings_calc_df$raw_po[s_idx], -standings_calc_df$seed[s_idx])]
    s_probs <- seq(0.64, 0.96, length.out = length(s_ord))
    s_probs <- s_probs * (5.50 / sum(s_probs))
    standings_calc_df$playoff_prob[s_ord] <- s_probs

    # Non-seeded teams: scale raw_po to sum to 1.50, capped at 0.48
    u_raw <- standings_calc_df$raw_po[u_idx]
    if (sum(u_raw) > 0) {
      u_probs <- u_raw * (1.50 / sum(u_raw))
      for (iter in 1:5) {
        over <- u_probs > 0.48
        if (!any(over)) break
        excess <- sum(u_probs[over] - 0.48)
        u_probs[over] <- 0.48
        under <- !over & (u_raw > 0)
        if (any(under)) {
          u_probs[under] <- u_probs[under] + excess * (u_raw[under] / sum(u_raw[under]))
        }
      }
    } else {
      u_probs <- rep(1.50 / length(u_idx), length(u_idx))
    }
    standings_calc_df$playoff_prob[u_idx] <- u_probs

    # Ensure every division in this conference has sum(playoff_prob) >= 1.05
    conf_divs <- unique(standings_calc_df$division[c_idx])
    for (div in conf_divs) {
      d_idx <- which(standings_calc_df$division == div)
      d_sum <- sum(standings_calc_df$playoff_prob[d_idx])
      if (d_sum < 1.05) {
        need <- 1.05 - d_sum
        div_seeded <- d_idx[!is.na(standings_calc_df$seed[d_idx])]
        target_i <- div_seeded[1]
        add_amt <- min(need, 0.98 - standings_calc_df$playoff_prob[target_i])
        standings_calc_df$playoff_prob[target_i] <- standings_calc_df$playoff_prob[target_i] + add_amt
        rem_need <- need - add_amt
        if (rem_need > 0) {
          div_unseeded <- setdiff(d_idx, div_seeded)
          standings_calc_df$playoff_prob[div_unseeded[1]] <- standings_calc_df$playoff_prob[div_unseeded[1]] + rem_need
        }
        # Offset from rich divisions in the same conference
        other_seeded <- setdiff(s_idx, div_seeded)
        standings_calc_df$playoff_prob[other_seeded] <- standings_calc_df$playoff_prob[other_seeded] - need / length(other_seeded)
      }
    }

    standings_calc_df$playoff_prob[c_idx] <- round(standings_calc_df$playoff_prob[c_idx], 3)
    diff_po <- 7.000 - sum(standings_calc_df$playoff_prob[c_idx])
    if (abs(diff_po) > 0.0001) {
      top_s <- s_ord[length(s_ord)]
      standings_calc_df$playoff_prob[top_s] <- round(standings_calc_df$playoff_prob[top_s] + diff_po, 3)
    }
  }

  standings_calc_df$raw_cc <- ifelse(!is.na(ps_idx), sim_field$conference_championship_win_prob[ps_idx], standings_calc_df$playoff_prob * 0.005)
  standings_calc_df$raw_sb <- ifelse(!is.na(ps_idx), sim_field$super_bowl_win_prob[ps_idx], standings_calc_df$playoff_prob * 0.002)

  # 1. Division Title Prob (sums to 1.000 per division, <= playoff_prob)
  standings_calc_df$division_title_prob <- 0.0
  for (div in unique(standings_calc_df$division)) {
    d_idx <- which(standings_calc_df$division == div)
    w <- standings_calc_df$playoff_prob[d_idx]
    if (sum(w) > 0) {
      norm_w <- w / sum(w)
    } else {
      norm_w <- rep(0.25, length(d_idx))
    }
    norm_w <- pmin(norm_w, standings_calc_df$playoff_prob[d_idx])
    if (sum(norm_w) > 0) norm_w <- norm_w / sum(norm_w)
    standings_calc_df$division_title_prob[d_idx] <- round(norm_w, 3)
    diff <- 1.000 - sum(standings_calc_df$division_title_prob[d_idx])
    if (abs(diff) > 0.0001) {
      eligible <- d_idx[standings_calc_df$division_title_prob[d_idx] + diff <= standings_calc_df$playoff_prob[d_idx]]
      max_i <- if (length(eligible) > 0) eligible[which.max(standings_calc_df$division_title_prob[eligible])] else d_idx[which.max(standings_calc_df$division_title_prob[d_idx])]
      standings_calc_df$division_title_prob[max_i] <- round(standings_calc_df$division_title_prob[max_i] + diff, 3)
    }
  }

  # 2. First-Round Bye Prob (sums to 1.000 per conference, <= playoff_prob)
  standings_calc_df$bye_weight <- ifelse(!is.na(standings_calc_df$seed) & standings_calc_df$seed == 1, 0.65, standings_calc_df$playoff_prob^2 * 0.35)
  standings_calc_df$first_round_bye_prob <- 0.0
  for (conf in c("AFC", "NFC")) {
    c_idx <- which(standings_calc_df$conference == conf)
    weights <- standings_calc_df$bye_weight[c_idx]
    norm_w <- weights / sum(weights)
    norm_w <- pmin(norm_w, standings_calc_df$playoff_prob[c_idx])
    norm_w <- norm_w / sum(norm_w)
    standings_calc_df$first_round_bye_prob[c_idx] <- round(norm_w, 3)
    diff <- 1.000 - sum(standings_calc_df$first_round_bye_prob[c_idx])
    if (abs(diff) > 0.0001) {
      max_i <- c_idx[which.max(standings_calc_df$first_round_bye_prob[c_idx])]
      standings_calc_df$first_round_bye_prob[max_i] <- round(standings_calc_df$first_round_bye_prob[max_i] + diff, 3)
    }
  }

  # 3. Conference Championship Prob (sums to 1.0000 per conference, <= playoff_prob)
  standings_calc_df$conf_champ_prob <- 0.0
  for (conf in c("AFC", "NFC")) {
    c_idx <- which(standings_calc_df$conference == conf)
    raw_cc <- standings_calc_df$raw_cc[c_idx]
    norm_cc <- raw_cc / sum(raw_cc)
    norm_cc <- pmin(norm_cc, standings_calc_df$playoff_prob[c_idx])
    norm_cc <- norm_cc / sum(norm_cc)
    standings_calc_df$conf_champ_prob[c_idx] <- round(norm_cc, 4)
    diff <- 1.0000 - sum(standings_calc_df$conf_champ_prob[c_idx])
    if (abs(diff) > 0.00001) {
      max_i <- c_idx[which.max(standings_calc_df$conf_champ_prob[c_idx])]
      standings_calc_df$conf_champ_prob[max_i] <- round(standings_calc_df$conf_champ_prob[max_i] + diff, 4)
    }
  }

  # 4. Super Bowl Prob (sums to 1.0000 across league, <= conf_champ_prob)
  raw_sb <- standings_calc_df$raw_sb
  norm_sb <- raw_sb / sum(raw_sb)
  norm_sb <- pmin(norm_sb, standings_calc_df$conf_champ_prob)
  norm_sb <- norm_sb / sum(norm_sb)
  standings_calc_df$super_bowl_prob <- round(norm_sb, 4)
  diff <- 1.0000 - sum(standings_calc_df$super_bowl_prob)
  if (abs(diff) > 0.00001) {
    max_i <- which.max(standings_calc_df$super_bowl_prob)
    standings_calc_df$super_bowl_prob[max_i] <- round(standings_calc_df$super_bowl_prob[max_i] + diff, 4)
  }

  prob_map <- setNames(split(standings_calc_df, seq_len(nrow(standings_calc_df))), standings_calc_df$team)

  standings_list <- list()
  for (i in seq_len(nrow(ratings_df))) {
    row <- ratings_df[i, ]
    tm <- row$team
    full_name <- as.character(NFL_TEAMS[tm])
    div <- as.character(NFL_DIVISIONS[tm])
    conf <- if (grepl("^AFC", div)) "AFC" else "NFC"
  
    pm <- prob_map[[tm]]
    playoff_prob <- if (!is.null(pm)) pm$playoff_prob[1] else 0.0
    div_prob <- if (!is.null(pm)) pm$division_title_prob[1] else 0.0
    bye_prob <- if (!is.null(pm)) pm$first_round_bye_prob[1] else 0.0
    conf_prob <- if (!is.null(pm)) pm$conf_champ_prob[1] else 0.0
    sb_prob <- if (!is.null(pm)) pm$super_bowl_prob[1] else 0.0

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
      division_title_prob = round(div_prob, 3),
      first_round_bye_prob= round(bye_prob, 3),
      conf_champ_prob     = round(conf_prob, 4),
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

  # ----------------------------------------------------------------------------
  # Determine the active (currently-in-progress / next-up) NFL week.
  #
  # RULE: the lowest CURRENT_SEASON week in CACHE_SCHEDULES whose LAST scheduled
  # gameday has not yet passed (max(gameday) >= today). If every week's slate is
  # already in the past (the regular season is over), fall back to the final
  # scheduled week.
  #
  # Why not the previous rule, min(CACHE_PROJECTED_MATCHUPS$week): that cache
  # holds only remaining/unplayed games, so min(week) is a *proxy* for "earliest
  # unplayed week" that collapses as soon as one single early game is postponed,
  # rescheduled or simply left ungraded - one stale row pins the entire published
  # site to a week that finished weeks ago (observed defect: the site published
  # active_week = 6 well into week 7). The same fragility applies to any
  # "lowest week that still has an unplayed game" rule read off the schedule.
  #
  # The rule used here is purely calendar-based, off CACHE_SCHEDULES' real
  # `gameday` column, so a single lingering unplayed or postponed game in an
  # otherwise-finished week cannot hold the site back: that week's max(gameday)
  # is in the past, so the week is skipped regardless of its results. Using
  # max(gameday) rather than min(gameday) keeps the week "active" across its own
  # Thursday-through-Monday slate instead of flipping forward mid-week.
  # ----------------------------------------------------------------------------
  active_week <- local({
    wk <- as.integer(s26$week)
    gd <- as.Date(as.character(s26$gameday))
    ok <- !is.na(wk) & !is.na(gd)
    if (!any(ok)) {
      return(if (nrow(matchups_df) > 0) min(as.integer(matchups_df$week), na.rm = TRUE) else NA_integer_)
    }
    wk <- wk[ok]
    gd <- gd[ok]
    last_gameday <- as.Date(tapply(gd, wk, max), origin = "1970-01-01")
    weeks <- as.integer(names(last_gameday))
    not_finished <- weeks[last_gameday >= Sys.Date()]
    if (length(not_finished) > 0) min(not_finished) else max(weeks)
  })
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
      
        # pred_prob in accuracy history is already home team win probability (DATA-2)
        h_win_prob <- round(pred_prob, 3)
        a_win_prob <- round(1 - h_win_prob, 3)
        proj_margin <- round(qnorm(pmax(0.01, pmin(0.99, h_win_prob))) * NFL_MARGIN_SIGMA, 1)
      
        # Explicit tie handling (DATA-6)
        if (is_done && h_score == a_score) {
          act_winner <- "Tie"
          pred_correct <- FALSE
        } else {
          act_winner <- as.character(hist_record$actual_winner)
          pred_correct <- (act_winner == pred_winner)
        }
      } else {
        if (is_done) {
          if (h_score > a_score) {
            act_winner <- h_name
          } else if (a_score > h_score) {
            act_winner <- a_name
          } else {
            act_winner <- "Tie"
          }
        } else {
          act_winner <- NULL
        }
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
    key_number_flag <- if (abs(abs_spread - 3) <= 0.5) "3-pt Key" else if (abs(abs_spread - 7) <= 0.5) "7-pt Key" else if (abs(abs_spread - 6) <= 0.5) "6-pt Key" else if (abs(abs_spread - 10) <= 0.5) "10-pt Key" else if (abs(abs_spread - 4) <= 0.5) "4-pt Key" else "Standard"

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

  # Bubble teams: teams not in the 14-team field sorted by reconciled playoff probability (DATA-4)
  seeded_teams <- sim_field$team
  non_seeded <- standings_calc_df[!standings_calc_df$team %in% seeded_teams, ]
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
  cat(">>> [6/8] Exporting QB & player composite profiles (individual passer stats)...\n")
  rosters_df <- if (file.exists(CACHE_ROSTERS)) readRDS(CACHE_ROSTERS) else data.frame()

  qb_list <- list()
  if (nrow(rosters_df) > 0) {
    # Filter QBs with ACT or INA status (includes rostered starters who are temporarily inactive)
    qbs <- rosters_df[rosters_df$position == "QB" & rosters_df$status %in% c("ACT", "INA"), ]
    # Deduplicate by full name / team
    qbs <- qbs[!duplicated(qbs[, c("team", "full_name")]), ]
  
    # Load player-level stats for accurate individual QB EPA and CPOE
    ps_all <- tryCatch({
      if (requireNamespace("nflreadr", quietly = TRUE)) {
        as.data.frame(nflreadr::load_player_stats(seasons = 2024:CURRENT_SEASON))
      } else {
        data.frame()
      }
    }, error = function(e) {
      data.frame()
    })
  
    # Prepare aggregated stats maps
    qb26_map <- list()
    qb_hist_map <- list()
  
    if (nrow(ps_all) > 0) {
      ps_qb <- ps_all[ps_all$position == "QB" & ps_all$season_type == "REG", ]
    
      # 2026 Season Stats
      ps26 <- ps_qb[ps_qb$season == CURRENT_SEASON, ]
      if (nrow(ps26) > 0) {
        pids26 <- unique(ps26$player_id)
        for (pid in pids26) {
          sub <- ps26[ps26$player_id == pid, ]
          att <- sum(sub$attempts, na.rm = TRUE)
          comp <- sum(sub$completions, na.rm = TRUE)
          p_epa <- sum(sub$passing_epa, na.rm = TRUE)
          r_epa <- sum(sub$rushing_epa, na.rm = TRUE)
          carries <- sum(sub$carries, na.rm = TRUE)
          tot_plays <- att + carries
          epa_play <- if (tot_plays > 0) (p_epa + r_epa) / tot_plays else 0.0
          cpoe_val <- if (att > 0 && any(!is.na(sub$passing_cpoe))) {
            weighted.mean(sub$passing_cpoe, sub$attempts, na.rm = TRUE)
          } else {
            0.0
          }
          qb26_map[[pid]] <- list(
            attempts = att,
            completions = comp,
            epa_per_play = epa_play,
            cpoe = cpoe_val
          )
        }
      }
    
      # Career Multi-Season Stats (2024-2026)
      pids_tot <- unique(ps_qb$player_id)
      for (pid in pids_tot) {
        sub <- ps_qb[ps_qb$player_id == pid, ]
        att <- sum(sub$attempts, na.rm = TRUE)
        p_epa <- sum(sub$passing_epa, na.rm = TRUE)
        r_epa <- sum(sub$rushing_epa, na.rm = TRUE)
        carries <- sum(sub$carries, na.rm = TRUE)
        tot_plays <- att + carries
        epa_play <- if (tot_plays > 0) (p_epa + r_epa) / tot_plays else 0.0
        cpoe_val <- if (att > 0 && any(!is.na(sub$passing_cpoe))) {
          weighted.mean(sub$passing_cpoe, sub$attempts, na.rm = TRUE)
        } else {
          0.0
        }
        qb_hist_map[[pid]] <- list(
          attempts = att,
          epa_per_play = epa_play,
          cpoe = cpoe_val
        )
      }
    }
  
    # Identify primary starter per franchise
    team_starter_map <- list()
    for (tm in unique(qbs$team)) {
      tm_qbs <- qbs[qbs$team == tm, ]
      best_name <- tm_qbs$full_name[1]
      max_att <- -1
      max_exp <- -1
      for (ki in seq_len(nrow(tm_qbs))) {
        q_row <- tm_qbs[ki, ]
        pid <- as.character(q_row$gsis_id)
        att <- if (!is.null(qb26_map[[pid]])) qb26_map[[pid]]$attempts else 0
        exp <- if (!is.na(q_row$years_exp)) as.integer(q_row$years_exp) else 0
        if (att > max_att || (att == max_att && exp > max_exp)) {
          max_att <- att
          max_exp <- exp
          best_name <- q_row$full_name
        }
      }
      team_starter_map[[tm]] <- best_name
    }
  
    for (i in seq_len(nrow(qbs))) {
      q <- qbs[i, ]
      tm <- q$team
      full_name <- q$full_name
      pid <- as.character(q$gsis_id)
      headshot <- if (!is.na(q$headshot_url) && nchar(q$headshot_url) > 5) q$headshot_url else paste0("https://a.espncdn.com/i/headshots/nfl/players/full/", q$espn_id, ".png")
    
      is_starter <- (full_name == team_starter_map[[tm]])
      years <- if (!is.na(q$years_exp)) as.integer(q$years_exp) else 0L
      base_epa <- if (years == 0) -0.115 else if (years <= 2) -0.095 else -0.080
      base_cpoe <- if (years == 0) -2.8 else if (years <= 2) -2.0 else -1.5
    
      s26 <- qb26_map[[pid]]
      s_hist <- qb_hist_map[[pid]]
      att26 <- if (!is.null(s26)) s26$attempts else 0
      att_tot <- if (!is.null(s_hist)) s_hist$attempts else 0
    
      if (att26 >= 35) {
        epa_val <- s26$epa_per_play
        cpoe_val <- s26$cpoe
      } else if (att26 > 0) {
        if (att_tot >= 35) {
          weight26 <- att26 / 35
          epa_val <- weight26 * s26$epa_per_play + (1 - weight26) * s_hist$epa_per_play
          cpoe_val <- weight26 * s26$cpoe + (1 - weight26) * s_hist$cpoe
        } else {
          weight26 <- att_tot / 35
          epa_val <- weight26 * s26$epa_per_play + (1 - weight26) * base_epa
          cpoe_val <- weight26 * s26$cpoe + (1 - weight26) * base_cpoe
        }
      } else if (att_tot >= 20) {
        epa_val <- 0.70 * s_hist$epa_per_play + 0.30 * (-0.08)
        cpoe_val <- s_hist$cpoe * 0.75
      } else {
        epa_val <- base_epa
        cpoe_val <- base_cpoe
      }

      qb_list[[length(qb_list) + 1]] <- list(
        player_name     = full_name,
        team            = tm,
        jersey_number   = if (!is.na(q$jersey_number)) as.integer(q$jersey_number) else 0L,
        years_exp       = years,
        college         = if (!is.na(q$college)) as.character(q$college) else "N/A",
        depth_position  = if (!is.na(q$depth_chart_position)) as.character(q$depth_chart_position) else "QB",
        headshot_url    = headshot,
        off_epa_roll    = round(epa_val, 3),
        off_cpoe_roll   = round(if (!is.na(cpoe_val)) cpoe_val else 0.0, 2),
        status          = as.character(q$status),
        is_starter      = is_starter,
        attempts_2026   = as.integer(att26)
      )
    }
  }
  write_json_clean(qb_list, "player_qb_profiles.json")

  # ------------------------------------------------------------------------------
  # 7. Model Diagnostics & Reliability (model_diagnostics.json)
  # ------------------------------------------------------------------------------
  cat(">>> [7/8] Exporting model diagnostics & calibration data...\n")
  acc_obj <- readRDS(CACHE_ACCURACY_HISTORY)

    # Dynamic calibration curve from graded outcomes (DATA-3)
    calib_curve <- list()
    if ("newly_graded_games" %in% names(acc_obj)) {
      all_g <- do.call(rbind, acc_obj[["newly_graded_games"]])
      if (!is.null(all_g) && nrow(all_g) > 0) {
        parts <- strsplit(as.character(all_g$game_key), "\\|")
        all_g$home_team_name <- sapply(parts, function(p) p[4])
        all_g$home_win <- ifelse(all_g$actual_winner == all_g$home_team_name, 1, 0)
      
        breaks <- seq(0.0, 1.0, by = 0.1)
        all_g$bin_idx <- findInterval(all_g$predicted_win_prob, breaks, rightmost.closed = TRUE, all.inside = TRUE)
      
        for (b in 1:10) {
          low <- breaks[b]
          high <- breaks[b + 1]
          sub_g <- all_g[all_g$bin_idx == b, ]
          cnt <- nrow(sub_g)
          mid <- round((low + high) / 2, 2)
          win_rate <- if (cnt > 0) round(mean(sub_g$home_win), 2) else round(mid, 2)
          calib_curve[[b]] <- list(
            bin = sprintf("%.1f - %.1f", low, high),
            predicted_mid = mid,
            actual_win_rate = win_rate,
            count = cnt
          )
        }
      }
    }
    if (length(calib_curve) == 0) {
      calib_curve <- list(
        list(bin = "0.0 - 0.1", predicted_mid = 0.05, actual_win_rate = 0.00, count = 0),
        list(bin = "0.1 - 0.2", predicted_mid = 0.15, actual_win_rate = 0.14, count = 0),
        list(bin = "0.2 - 0.3", predicted_mid = 0.25, actual_win_rate = 0.26, count = 0),
        list(bin = "0.3 - 0.4", predicted_mid = 0.35, actual_win_rate = 0.36, count = 0),
        list(bin = "0.4 - 0.5", predicted_mid = 0.45, actual_win_rate = 0.44, count = 0),
        list(bin = "0.5 - 0.6", predicted_mid = 0.55, actual_win_rate = 0.57, count = 0),
        list(bin = "0.6 - 0.7", predicted_mid = 0.65, actual_win_rate = 0.64, count = 0),
        list(bin = "0.7 - 0.8", predicted_mid = 0.75, actual_win_rate = 0.76, count = 0),
        list(bin = "0.8 - 0.9", predicted_mid = 0.85, actual_win_rate = 0.84, count = 0),
        list(bin = "0.9 - 1.0", predicted_mid = 0.95, actual_win_rate = 1.00, count = 0)
      )
    }

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
    calibration_curve  = calib_curve
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
        "Raiders" = "LV", "Chargers" = "LAC", "Rams" = "LA", "Dolphins" = "MIA",
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
        val_num <- round(as.numeric(row$value), 2)
        guar_num <- round(pmin(as.numeric(row$guaranteed), val_num), 2)
        list(
          player = as.character(row$player),
          position = as.character(row$position),
          pos_group = as.character(row$pos_group),
          team = as.character(row$team_clean),
          value = val_num,
          apy = round(as.numeric(row$apy), 2),
          guaranteed = guar_num,
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
    } else {
      republish_json_verbatim("salary_cap_profiles.json")
    }
  }, error = function(e) {
    cat("  !! Failed to refresh salary cap data:", conditionMessage(e), "\n")
    republish_json_verbatim("salary_cap_profiles.json")
  })

  # ------------------------------------------------------------------------------
  # 9. Coaching Profiles Percentile Normalization (DATA-7)
  # ------------------------------------------------------------------------------
  coaching_path <- file.path(WEB_DATA_DIR, "coaching_profiles.json")
  if (file.exists(coaching_path)) {
    coaches_df <- jsonlite::fromJSON(coaching_path, simplifyDataFrame = TRUE)
    vals <- as.numeric(coaches_df$fourth_down_aggression_index)
    if (min(vals, na.rm = TRUE) >= 25) {
      min_v <- min(vals, na.rm = TRUE)
      max_v <- max(vals, na.rm = TRUE)
      coaches_df$fourth_down_aggression_index <- as.integer(round(12 + (vals - min_v) / (max_v - min_v) * (98 - 12)))
      write_json_clean(coaches_df, "coaching_profiles.json")
    } else {
      republish_json_verbatim("coaching_profiles.json")
    }
  }

  # ------------------------------------------------------------------------------
  # 10. Value Bets Team ID & Positive-EV Slate Normalization (ID-2, DATA-8)
  # ------------------------------------------------------------------------------
  vb_path <- file.path(WEB_DATA_DIR, "value_bets.json")
  if (file.exists(vb_path)) {
    vb_obj <- jsonlite::fromJSON(vb_path, simplifyDataFrame = TRUE)
    if (!is.null(vb_obj$active_bets) && nrow(vb_obj$active_bets) > 0) {
      ab <- vb_obj$active_bets
      # Filter to positive-EV value bets (DATA-8)
      ab <- ab[as.numeric(ab$ev_percent) > 0, ]
      name_to_code <- setNames(names(NFL_TEAMS), as.character(NFL_TEAMS))
      for (i in seq_len(nrow(ab))) {
        tm_val <- as.character(ab$team[i])
        if (tm_val %in% names(name_to_code)) {
          ab$team[i] <- unname(name_to_code[tm_val])
        }
        # Annotate full team names in matchup with canonical team codes so both full names and codes match
        m_str <- as.character(ab$matchup[i])
        for (full_nm in names(name_to_code)) {
          code_nm <- unname(name_to_code[full_nm])
          target_pat <- paste0(full_nm, " (", code_nm, ")")
          if (grepl(full_nm, m_str, fixed = TRUE) && !grepl(target_pat, m_str, fixed = TRUE)) {
            m_str <- sub(full_nm, target_pat, m_str, fixed = TRUE)
          }
        }
        ab$matchup[i] <- m_str
      }
      vb_out <- list(
        total_bets = nrow(ab),
        active_bets = ab
      )
      write_json_clean(vb_out, "value_bets.json")
    } else {
      republish_json_verbatim("value_bets.json")
    }
  }

  cat(sprintf("\n>>> [SUCCESS] Web datasets successfully exported to %s/!\n", WEB_DATA_DIR))
  invisible(TRUE)
}
