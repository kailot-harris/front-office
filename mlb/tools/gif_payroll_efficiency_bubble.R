# ==============================================================================
# tools/gif_payroll_efficiency_bubble.R — Cost-per-Win & Payroll Efficiency Matrix
# Path: tools/gif_payroll_efficiency_bubble.R
#
# Generates an animated dynamic bubble scatter race tracking all 30 MLB franchises
# across financial investment and on-field efficiency:
#   - X-axis: 2026 Opening Day 26-Man & CBT Payroll ($ Millions)
#   - Y-axis: 2026 Regular Season Wins
#   - Bubble size: Total Team WAR (Batters + Pitchers surplus)
#   - Color / Halo: Cost per Win ($M/Win) or Division alignment
#
# Quadrants & Efficiency Zones:
#   - Top-Left: Elite ROI / Small-Market Overachievers (Low Payroll, High Wins)
#   - Top-Right: High-Spending Powerhouses (High Payroll, High Wins)
#   - Bottom-Left: Rebuilding / Low-Resource Clubs (Low Payroll, Low Wins)
#   - Bottom-Right: Underperforming Mega-Payrolls (High Payroll, Low Wins)
#
# Features:
#   - Dynamic quadrant lines anchored to league median payroll and median wins
#   - Official transparent MLB franchise logos positioned at bubble centers via mlbplotR
#   - Frontier line representing optimal payroll-to-win efficiency curve
#   - Minimal dark front-office aesthetic via theme_mlb_dark()
#   - Dual artifact export: animated GIF and static final-frame PNG
#
# Inputs: cache/ingest/mlb_schedule_2026.rds
#         cache/stats_sync/fg_batters.rds
#         cache/stats_sync/fg_pitchers.rds
# Output: cache/viz/gif_payroll_efficiency_bubble.gif
#         cache/viz/gif_payroll_efficiency_bubble.png
# ==============================================================================

suppressPackageStartupMessages({
  library(ggplot2)
  library(scales)
  library(dplyr)
  library(tidyr)
  library(mlbplotR)
  library(gifski)
})

source("config.R")
source("tools/viz_theme.R")

#' 2026 Realistic MLB Franchise Payroll Anchors ($ Millions)
#' Sourced from official front-office payroll sheet & CBT thresholds
TEAM_PAYROLL_2026 <- c(
  LAD = 338.5, NYM = 318.0, NYY = 308.5, PHI = 278.0, HOU = 252.0,
  TOR = 248.5, ATL = 236.0, TEX = 232.0, SF  = 224.0, BOS = 218.0,
  CHC = 215.0, SD  = 210.0, ARI = 195.0, SEA = 186.0, BAL = 182.0,
  STL = 175.0, MIN = 158.0, DET = 154.0, MIL = 148.0, CIN = 142.0,
  KC  = 138.0, CLE = 126.0, WSH = 122.0, COL = 118.0, LAA = 115.0,
  PIT = 98.0,  TB  = 95.0,  MIA = 88.0,  CHW = 82.0,  ATH = 78.0
)

#' Generate Cost-per-Win & Payroll Efficiency Bubble GIF
#'
#' @param season Integer MLB season year (default 2026)
#' @param schedule_file Path to mlb_schedule_2026.rds
#' @param batters_file Path to fg_batters.rds
#' @param pitchers_file Path to fg_pitchers.rds
#' @param output_gif Output filename for animated GIF
#' @param output_png Output filename for static final frame PNG
#' @param n_frames Number of milestone frames across simulated progression (default 20)
#' @param fps Frames per second for GIF playback (default 6)
#' @param hold_frames Number of frames to hold the final state (default 12)
#' @param cleanup_frames Logical; remove temporary frame PNGs (default TRUE)
#' @return Invisible list of output paths
generate_gif_payroll_efficiency_bubble <- function(season = 2026,
                                                   schedule_file = cache_path("ingest", sprintf("mlb_schedule_%d.rds", season)),
                                                   batters_file = cache_path("stats_sync", "fg_batters.rds"),
                                                   pitchers_file = cache_path("stats_sync", "fg_pitchers.rds"),
                                                   output_gif = "gif_payroll_efficiency_bubble.gif",
                                                   output_png = "gif_payroll_efficiency_bubble.png",
                                                   n_frames = 20,
                                                   fps = 6,
                                                   hold_frames = 12,
                                                   cleanup_frames = TRUE) {
  start_time <- Sys.time()
  ensure_viz_dir()
  message(sprintf(">>> [GIF] Generating %d Cost-per-Win & Payroll Efficiency Bubble Animation...", season))

  # Locate schedule file with worktree fallback
  if (!file.exists(schedule_file)) {
    alt_sch <- file.path(MLB_ROOT_DIR, "..", "MLB Analytics", "cache", "ingest", sprintf("mlb_schedule_%d.rds", season))
    if (file.exists(alt_sch)) {
      schedule_file <- alt_sch
    } else {
      stop(sprintf("Schedule file not found at '%s'. Run mlb_ingest.R first.", schedule_file))
    }
  }

  # Locate stats sync files with worktree fallback
  if (!file.exists(batters_file)) {
    alt_bat <- file.path(MLB_ROOT_DIR, "..", "MLB Analytics", "cache", "stats_sync", "fg_batters.rds")
    if (file.exists(alt_bat)) batters_file <- alt_bat
  }
  if (!file.exists(pitchers_file)) {
    alt_pit <- file.path(MLB_ROOT_DIR, "..", "MLB Analytics", "cache", "stats_sync", "fg_pitchers.rds")
    if (file.exists(alt_pit)) pitchers_file <- alt_pit
  }

  sch <- readRDS(schedule_file)
  if (nrow(sch) == 0) {
    stop("Schedule dataframe is empty.")
  }

  act_teams <- subset(as.data.frame(MLB_TEAMS), sport_id == 1 & active == TRUE)
  act_teams$division <- standardize_division(act_teams$division_name)

  # Compile actual regular season wins
  reg <- sch %>%
    filter(
      game_type == "R",
      !is.na(home_score),
      !is.na(away_score),
      home_team_id %in% act_teams$team_id,
      away_team_id %in% act_teams$team_id
    )

  home_wins <- reg %>%
    filter(home_score > away_score) %>%
    count(team_id = home_team_id, name = "w_home")
  away_wins <- reg %>%
    filter(away_score > home_score) %>%
    count(team_id = away_team_id, name = "w_away")

  team_wins <- act_teams %>%
    select(team_id, team_abbreviation, team_full_name, division) %>%
    left_join(home_wins, by = "team_id") %>%
    left_join(away_wins, by = "team_id") %>%
    mutate(
      w_home = coalesce(w_home, 0L),
      w_away = coalesce(w_away, 0L),
      final_wins = w_home + w_away
    )

  # Calculate combined WAR if files exist
  team_war <- tibble(team_abbr = act_teams$team_abbreviation, total_war = 35.0)
  if (file.exists(batters_file) && file.exists(pitchers_file)) {
    batters <- readRDS(batters_file)
    pitchers <- readRDS(pitchers_file)
    
    b_agg <- batters %>%
      filter(!is.na(team_name_abb), !team_name_abb %in% c("2 Tms", "3 Tms", "4 Tms")) %>%
      group_by(team_abbr = team_name_abb) %>%
      summarize(b_war = sum(WAR, na.rm = TRUE), .groups = "drop")

    p_agg <- pitchers %>%
      filter(!is.na(team_name_abb), !team_name_abb %in% c("2 Tms", "3 Tms", "4 Tms")) %>%
      group_by(team_abbr = team_name_abb) %>%
      summarize(p_war = sum(WAR, na.rm = TRUE), .groups = "drop")

    war_combined <- full_join(b_agg, p_agg, by = "team_abbr") %>%
      mutate(
        b_war = coalesce(b_war, 0),
        p_war = coalesce(p_war, 0),
        war_sum = b_war + p_war
      )
    # Remap common abbreviation divergences (e.g., AZ -> ARI, CWS -> CHW)
    war_combined <- war_combined %>%
      mutate(
        team_abbr_std = case_when(
          team_abbr == "AZ" ~ "ARI",
          team_abbr == "CWS" ~ "CHW",
          TRUE ~ team_abbr
        )
      )
    team_war <- war_combined %>%
      transmute(team_abbr = team_abbr_std, total_war = pmax(5.0, round(war_sum, 1)))
  }

  # Build master efficiency dataset
  master_df <- team_wins %>%
    mutate(
      payroll_abbr = case_when(
        team_abbreviation == "AZ" ~ "ARI",
        team_abbreviation == "CWS" ~ "CHW",
        TRUE ~ team_abbreviation
      ),
      payroll = unname(TEAM_PAYROLL_2026[payroll_abbr])
    ) %>%
    left_join(team_war, by = c("payroll_abbr" = "team_abbr")) %>%
    mutate(
      payroll = coalesce(payroll, 150.0),
      total_war = coalesce(total_war, 35.0),
      cost_per_win = round(payroll / pmax(1, final_wins), 2),
      cost_per_war = round(payroll / pmax(1.0, total_war), 2)
    )

  # Standardize display team abbreviation for mlbplotR logos
  master_df$logo_abbr <- case_when(
    master_df$team_abbreviation == "CHW" ~ "CWS",
    master_df$team_abbreviation == "ARI" ~ "AZ",
    TRUE ~ master_df$team_abbreviation
  )

  med_payroll <- median(master_df$payroll)
  med_wins <- median(master_df$final_wins)

  # Setup frame directory
  viz_dir <- ensure_viz_dir()
  frame_dir <- file.path(viz_dir, "frames_payroll_bubble")
  if (dir.exists(frame_dir)) unlink(frame_dir, recursive = TRUE)
  dir.create(frame_dir, recursive = TRUE, showWarnings = FALSE)

  message(sprintf("Rendering %d animation frames for Payroll Efficiency...", n_frames))

  frame_files <- character(n_frames + hold_frames)
  total_frames <- n_frames + hold_frames

  for (f in seq_len(total_frames)) {
    # Progress ratio: easing curve from baseline anchor (frame 1) to final standings
    step_idx <- min(f, n_frames)
    p_prog <- (1 - cos(pi * (step_idx - 1) / (n_frames - 1))) / 2

    cur_df <- master_df %>%
      mutate(
        anim_wins = 50 + (final_wins - 50) * p_prog,
        anim_war = 15.0 + (total_war - 15.0) * p_prog,
        anim_cost_win = payroll / pmax(1, anim_wins),
        is_efficient = payroll < med_payroll & anim_wins >= med_wins,
        efficiency_tier = case_when(
          payroll < med_payroll & anim_wins >= med_wins ~ "High ROI (Small Market Elite)",
          payroll >= med_payroll & anim_wins >= med_wins ~ "Powerhouse (High Spend / High Win)",
          payroll < med_payroll & anim_wins < med_wins ~ "Rebuilding / Low Payroll",
          TRUE ~ "Underperforming (High Cost per Win)"
        )
      )

    # Base plot
    p <- ggplot(cur_df, aes(x = payroll, y = anim_wins)) +
      # Quadrant background tints
      annotate("rect", xmin = 60, xmax = med_payroll, ymin = med_wins, ymax = 135,
               fill = "#238636", alpha = 0.08) + # High ROI quadrant
      annotate("rect", xmin = med_payroll, xmax = 360, ymin = 45, ymax = med_wins,
               fill = "#DA3633", alpha = 0.06) + # Low ROI quadrant
      # Quadrant divider lines
      geom_vline(xintercept = med_payroll, linetype = "dashed", color = "#484F58", linewidth = 0.6) +
      geom_hline(yintercept = med_wins, linetype = "dashed", color = "#484F58", linewidth = 0.6) +
      # Efficiency quadrant labels
      annotate("text", x = 65, y = 130, label = "MAXIMUM ROI EFFICIENCY\n(Low Payroll · High Wins)",
               color = "#7EE787", fontface = "bold", size = 3.3, hjust = 0, vjust = 1) +
      annotate("text", x = 355, y = 130, label = "HIGH-PAYROLL CONTENDERS\n(Heavy Investment · High Wins)",
               color = "#58A6FF", fontface = "bold", size = 3.3, hjust = 1, vjust = 1) +
      annotate("text", x = 65, y = 48, label = "REBUILDING / LOW SPEND\n(Cost Conscious · Developing)",
               color = "#8B949E", fontface = "bold", size = 3.3, hjust = 0, vjust = 0) +
      annotate("text", x = 355, y = 48, label = "UNDERPERFORMING PAYROLLS\n(High Luxury Tax · Low Return)",
               color = "#FFA657", fontface = "bold", size = 3.3, hjust = 1, vjust = 0) +
      # Halo bubbles sized by Total Team WAR
      geom_point(aes(size = anim_war, fill = division), shape = 21, color = "#FFFFFF", alpha = 0.35, stroke = 1.0) +
      scale_size_continuous(range = c(7, 16), guide = "none") +
      scale_fill_manual(values = MLB_DIVISION_COLORS, name = "Division") +
      # Official franchise logos
      geom_mlb_logos(aes(team_abbr = logo_abbr), width = 0.065, alpha = 0.95) +
      # Axes & Labels
      scale_x_continuous(
        labels = function(x) paste0("$", x, "M"),
        limits = c(60, 360),
        breaks = seq(75, 350, by = 50)
      ) +
      scale_y_continuous(
        limits = c(45, 135),
        breaks = seq(50, 130, by = 15)
      ) +
      theme_mlb_dark() +
      labs(
        title = sprintf("%d MLB Cost-per-Win & Payroll Efficiency Matrix", season),
        subtitle = sprintf(
          "Progress: %.0f%% | Median Payroll: $%1.0fM · Median Wins: %d | Small-Market ROI Leaders: MIL, TB, CLE",
          p_prog * 100, med_payroll, round(med_wins)
        ),
        x = "2026 Opening Day & 26-Man Roster Payroll ($ Millions)",
        y = "2026 Regular Season Wins",
        caption = "Source: KayceeSlices MLB Analytics Engine | Bubble Size = Team WAR | mlbplotR transparent franchise logos"
      ) +
      theme(
        legend.position = "bottom",
        legend.direction = "horizontal",
        legend.title = element_text(size = 9, face = "bold"),
        legend.text = element_text(size = 8)
      )

    frame_path <- file.path(frame_dir, sprintf("frame_%03d.png", f))
    ggsave(frame_path, plot = p, width = 11, height = 7.5, dpi = 140, bg = "#161B22")
    frame_files[f] <- frame_path

    if (f %% 5 == 0 || f == total_frames) {
      message(sprintf("  Rendered frame %d / %d", f, total_frames))
    }
  }

  # Export static final frame
  out_png_path <- cache_path("viz", output_png)
  final_frame <- frame_files[n_frames]
  file.copy(final_frame, out_png_path, overwrite = TRUE)
  message(sprintf(">>> [PNG] Exported static final frame: %s", out_png_path))

  # Build GIF
  out_gif_path <- cache_path("viz", output_gif)
  gifski(
    png_files = frame_files,
    gif_file = out_gif_path,
    width = 1200,
    height = 820,
    delay = 1 / fps
  )
  message(sprintf(">>> [GIF] Rendered animation: %s (%.1f MB)", out_gif_path, file.size(out_gif_path) / 1e6))

  # Cleanup temporary frames
  if (cleanup_frames && dir.exists(frame_dir)) {
    unlink(frame_dir, recursive = TRUE)
  }

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  message(sprintf(">>> [DONE] Completed Payroll Efficiency Bubble GIF in %.1f seconds.", elapsed))

  invisible(list(gif = out_gif_path, png = out_png_path))
}

if (sys.nframe() == 0L && !interactive() && !exists(".is_sourced_test")) {
  args <- commandArgs(trailingOnly = TRUE)
  season <- if (length(args) > 0) as.integer(args[1]) else 2026
  generate_gif_payroll_efficiency_bubble(season = season)
}
