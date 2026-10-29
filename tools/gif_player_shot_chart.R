# ==============================================================================
# tools/gif_player_shot_chart.R
# Path: tools/gif_player_shot_chart.R
#
# Animated rolling-window player shot evolution GIF generator with static PNG
# fallback for prefers-reduced-motion.
# Closes issue #40 (Phase 3 viz).
#
# Features:
#   - Sources tools/viz_common.R and tools/plot_shot_chart.R.
#   - Slices player shots into chronologically ordered frames using a rolling window
#     or cumulative progressive timeline (e.g., rolling window of N games or shots).
#   - Renders each intermediate state on regulation NBA half court.
#   - Calls render_animated_artifact() to encode high-performance GIF via gifski
#     and copies final frame to static PNG.
# ==============================================================================

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  if (file.exists(file.path(base, "tools", "viz_common.R"))) {
    normalizePath(base, winslash = "/", mustWork = FALSE)
  } else if (file.exists(file.path(base, "..", "tools", "viz_common.R"))) {
    normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
  } else {
    getwd()
  }
})

viz_common_path <- file.path(REPO_ROOT, "tools", "viz_common.R")
if (!file.exists(viz_common_path)) {
  alt_path <- "tools/viz_common.R"
  if (file.exists(alt_path)) viz_common_path <- alt_path else stop("Cannot find tools/viz_common.R")
}
source(viz_common_path)

plot_shot_chart_path <- file.path(REPO_ROOT, "tools", "plot_shot_chart.R")
if (!file.exists(plot_shot_chart_path)) {
  alt_path <- "tools/plot_shot_chart.R"
  if (file.exists(alt_path)) plot_shot_chart_path <- alt_path else stop("Cannot find tools/plot_shot_chart.R")
}
source(plot_shot_chart_path)

suppressPackageStartupMessages({
  library(ggplot2)
})

# ------------------------------------------------------------------------------
# Generate Rolling-Window Frames & Dual-Output Animation (GIF + PNG)
# ------------------------------------------------------------------------------
generate_player_shot_chart_gif <- function(shot_data,
                                           player_name = NULL,
                                           team = NULL,
                                           gif_path = "output/player_shot_evolution.gif",
                                           png_path = "output/player_shot_evolution.png",
                                           n_frames = 10,
                                           window_mode = c("cumulative", "rolling"),
                                           window_size = 30,
                                           fps = 2,
                                           hold_last_frames = 5,
                                           width_px = 800,
                                           height_px = 750,
                                           temp_dir = NULL) {
  window_mode <- match.arg(window_mode)
  df <- normalize_shot_coordinates(shot_data)

  if (nrow(df) == 0) {
    stop("generate_player_shot_chart_gif: 'shot_data' contains 0 valid shots.")
  }

  if (is.null(player_name) || !nzchar(player_name)) {
    player_name <- if (nzchar(df$player_name[1])) df$player_name[1] else "Player Shot Evolution"
  }

  if (is.null(team) || !nzchar(team)) {
    team <- if (nzchar(df$team_abbrev[1])) df$team_abbrev[1] else "NBA"
  }

  # Ensure temp directory for frames
  cleanup_temp <- FALSE
  if (is.null(temp_dir)) {
    temp_dir <- file.path(tempdir(), sprintf("shot_gif_%d_%d", Sys.getpid(), as.integer(Sys.time())))
    cleanup_temp <- TRUE
  }
  if (!dir.exists(temp_dir)) {
    dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
  }

  total_shots <- nrow(df)
  n_frames <- min(as.integer(n_frames), total_shots)
  if (n_frames < 2) n_frames <- min(2, total_shots)

  # Calculate shot indices for each frame
  step_indices <- unique(round(seq(from = min(5, total_shots), to = total_shots, length.out = n_frames)))
  n_actual_frames <- length(step_indices)

  frame_paths <- character(n_actual_frames)

  for (i in seq_along(step_indices)) {
    idx_end <- step_indices[i]
    if (window_mode == "cumulative") {
      df_sub <- df[1:idx_end, , drop = FALSE]
      sub_title <- sprintf("Cumulative: Shots 1 - %d of %d", idx_end, total_shots)
    } else {
      idx_start <- max(1, idx_end - window_size + 1)
      df_sub <- df[idx_start:idx_end, , drop = FALSE]
      sub_title <- sprintf("Rolling Window: Shots %d - %d (Size: %d)", idx_start, idx_end, nrow(df_sub))
    }

    # Generate frame plot
    p_frame <- plot_half_court_shot_chart(
      shot_data = df_sub,
      player_name = player_name,
      team = team,
      subtitle = sub_title,
      caption = sprintf("Frame %d of %d | NBA Analytics", i, n_actual_frames),
      point_size = 2.8,
      point_alpha = 0.82
    )

    frame_file <- file.path(temp_dir, sprintf("frame_%03d.png", i))
    ggsave(
      filename = frame_file,
      plot = p_frame,
      width = width_px / 100,
      height = height_px / 100,
      dpi = 100,
      bg = NBA_COLORS$bg
    )
    frame_paths[i] <- normalizePath(frame_file, winslash = "/")
  }

  # Render animated GIF and static PNG fallback via render_animated_artifact()
  result <- render_animated_artifact(
    frame_paths = frame_paths,
    gif_path = gif_path,
    png_path = png_path,
    fps = fps,
    hold_last_frames = hold_last_frames,
    width = width_px,
    height = height_px
  )

  # Clean up temp frames if auto-created
  if (cleanup_temp && dir.exists(temp_dir)) {
    unlink(temp_dir, recursive = TRUE)
  }

  invisible(result)
}
