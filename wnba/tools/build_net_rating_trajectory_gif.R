# ==============================================================================
# build_net_rating_trajectory_gif.R
# Path: tools/build_net_rating_trajectory_gif.R
#
# Animated net-rating trajectory for the two Finalists of CURRENT_SEASON across
# the whole postseason: one frame per playoff game date, each showing both teams'
# adjusted net rating as it stood with only the games played up to that point.
#
# This is the visual companion to tools/finals_series_backtest.R. That script
# answers "what would the model have said at each point"; this one shows the
# input that moved underneath it -- the ratings themselves. The two MUST agree,
# so the trajectory is not recomputed here: it is read from
# CACHE_FINALS_SERIES_BACKTEST for the Finals dates, and extended backwards
# through the earlier rounds with the same ratings_as_of() helper that artifact
# was built with. Recomputing it independently would let the chart and the table
# drift apart silently, which is the one failure mode that would matter.
#
# FINALS-SPECIFIC BY DESIGN, BUT NOT HARDCODED TO ONE MATCHUP (issue #96). The
# pair of teams is READ from CACHE_FINALS_SERIES_BACKTEST (team_high/team_low and
# their abbreviations), so a different Finals matchup -- or a different season --
# animates correctly with no edit here. The GS/ATL values survive only as a
# last-resort fallback for when that artifact is unavailable, and taking that
# path emits a labeled warning. What IS Finals-specific is the framing: exactly
# two teams, the "Finals" shading anchored on the first Finals date, and a
# caption that speaks about a series forecast. An arbitrary pair of teams who
# never met in the Finals would render, but that shading and caption would be
# wrong, so pass high_*/low_* explicitly only for a real Finals pair.
#
# RENDERING BACKEND. gifski only -- frames are drawn with ggplot2 and encoded
# with gifski::gifski(). gganimate is deliberately NOT a dependency here: a
# reveal-over-time animation needs nothing more than a per-frame filter, so
# adding it would buy nothing. gifski IS recorded in renv.lock (issue #96).
#
# REDUCED MOTION. Two artifacts are written, never one:
#   MEDIA_NET_RATING_TRAJECTORY_GIF  the animation
#   MEDIA_NET_RATING_TRAJECTORY_PNG  its FINAL FRAME as a still
# A looping GIF has no pause control, so the bracket page serves the PNG to any
# reader whose browser reports `prefers-reduced-motion: reduce`. The still is a
# copy of the last frame of the same render -- not a separately styled chart --
# so the two can never disagree. See config.R's note on this pair.
#
# PIPELINE PLACEMENT (issue #96): deliberately a tools/ one-off, NOT a
# run_full_pipeline.R stage. Its upstream, tools/finals_series_backtest.R, is a
# tools/ one-off for the same reason -- both are once-a-postseason artifacts
# about a single concluded series, not per-run derived data, and in the DAG this
# one would re-encode a ~30-frame raster animation on every daily run to produce
# a byte-identical file. Promote it to a stage only if the trajectory ever needs
# to refresh mid-series, and then follow the new-pipeline-stage-checklist
# conventions (declare output = MEDIA_NET_RATING_TRAJECTORY_GIF, and place it
# AFTER the backtest stage it reads).
#
# REUSES, NEVER RESTATES:
#   - config.R                        CACHE_TEAM_BOX, CACHE_FINALS_SERIES_BACKTEST,
#                                     MEDIA_NET_RATING_TRAJECTORY_GIF/PNG,
#                                     CURRENT_SEASON
#   - playoff_simulator.R             get_playoff_adjusted_rating()
#   - tools/finals_series_backtest.R  ratings_as_of()
#   - daily_ingest.R                  filter_real_franchises()
#
# FAIL-SAFE (repo convention): a missing box-score cache, a missing backtest
# artifact, or an absent gifski install each produce a labeled warning and an
# early return, never a half-written GIF and never a crash.
# ==============================================================================

if (!requireNamespace("here", quietly = TRUE)) {
  stop("Package 'here' is required to derive PROJECT_DIR portably. Install it with install.packages('here').")
}
PROJECT_DIR <- here::here()
setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

Sys.setenv(WNBA_SERIES_LENGTH_NO_AUTORUN = "1")
Sys.setenv(WNBA_FINALS_BACKTEST_NO_AUTORUN = "1")
if (!exists("CACHE_TEAM_BOX")) source("config.R")
if (!exists("ratings_as_of")) source("tools/finals_series_backtest.R")
if (!exists("filter_real_franchises")) source("daily_ingest.R")

.LOG_SCRIPT <- "build_net_rating_trajectory_gif.R"

# Frame geometry and pacing. Held frames at the end stop the GIF from snapping
# back to the start the instant the last point lands, which makes the final
# state unreadable on a short loop.
FRAME_W   <- 1000
FRAME_H   <- 600
FRAME_RES <- 120
FPS       <- 2
HOLD_FRAMES <- 6

# Dark palette, matching the site's bracket page (slate-900 panel on a near-black
# page, violet for the high seed and amber for the low seed -- the same two hues
# the FinalsSeriesBacktest component uses for its probability bar, so a reader
# moving between the chart and the table does not have to re-learn the colors).
BG_COLOR    <- "#0b1120"
PANEL_COLOR <- "#0f172a"
GRID_COLOR  <- "#1e293b"
TEXT_COLOR  <- "#cbd5e1"
MUTED_COLOR <- "#64748b"
HIGH_COLOR  <- "#a78bfa"  # violet-400
LOW_COLOR   <- "#f59e0b"  # amber-500

dark_theme <- theme_minimal(base_size = 11) +
  theme(
    plot.background   = element_rect(fill = BG_COLOR, color = NA),
    panel.background  = element_rect(fill = PANEL_COLOR, color = NA),
    panel.grid.major  = element_line(color = GRID_COLOR, linewidth = 0.3),
    panel.grid.minor  = element_blank(),
    text              = element_text(color = TEXT_COLOR),
    axis.text         = element_text(color = MUTED_COLOR),
    plot.title        = element_text(color = "#f1f5f9", face = "bold", size = 14),
    plot.subtitle     = element_text(color = MUTED_COLOR, size = 9),
    plot.caption      = element_text(color = MUTED_COLOR, size = 7, hjust = 0),
    legend.position   = "none"
  )

# ------------------------------------------------------------------------------
# Who played, and when the Finals started -- both read from the backtest
# artifact rather than restated here, so this chart cannot caption a different
# matchup than the table it sits next to. Returns NULL if the artifact is
# unreadable, and the caller falls back with a warning.
# ------------------------------------------------------------------------------
finals_matchup_from_backtest <- function() {
  if (!file.exists(CACHE_FINALS_SERIES_BACKTEST)) return(NULL)
  bt <- tryCatch(readRDS(CACHE_FINALS_SERIES_BACKTEST), error = function(e) NULL)
  if (is.null(bt) || !is.data.frame(bt) || nrow(bt) == 0) return(NULL)

  needed <- c("team_high", "team_high_abb", "team_low", "team_low_abb")
  if (!all(needed %in% names(bt))) return(NULL)

  finals_start <- as.Date(NA)
  fg <- attr(bt, "finals_games")
  if (!is.null(fg) && is.data.frame(fg) && nrow(fg) > 0) {
    finals_start <- min(as.Date(fg$game_day))
  }

  list(
    high_abb     = as.character(bt$team_high_abb[1]),
    high_name    = as.character(bt$team_high[1]),
    low_abb      = as.character(bt$team_low_abb[1]),
    low_name     = as.character(bt$team_low[1]),
    finals_start = finals_start
  )
}

# ------------------------------------------------------------------------------
# Trajectory: one row per (team, playoff game date), carrying that team's
# adjusted net rating computed from every CURRENT_SEASON game played strictly
# before the NEXT date -- i.e. the rating as it stood once that date's games were
# in the book. Identical construction to the backtest's information sets, which
# is why ratings_as_of() is reused rather than reimplemented.
# ------------------------------------------------------------------------------
build_trajectory <- function(high_abb, high_name, low_abb, low_name,
                             finals_start = as.Date(NA), season_yr = CURRENT_SEASON) {
  if (!file.exists(CACHE_TEAM_BOX)) {
    warning(sprintf(">>> [NET RATING GIF] %s not found -- cannot build trajectory.", CACHE_TEAM_BOX))
    return(NULL)
  }
  box <- filter_real_franchises(readRDS(CACHE_TEAM_BOX)) %>%
    filter(season == season_yr) %>%
    mutate(game_day = as.Date(game_date))

  post_days <- box %>%
    filter(season_type == 3L) %>%
    distinct(game_day) %>%
    arrange(game_day) %>%
    pull(game_day)

  if (length(post_days) == 0) {
    warning(">>> [NET RATING GIF] No postseason dates found -- nothing to animate.")
    return(NULL)
  }

  # A point for the state BEFORE the postseason began, so the chart opens on the
  # regular-season baseline rather than mid-flight.
  anchor <- min(post_days) - 1L
  marks <- c(anchor, post_days)

  rows <- lapply(marks, function(d) {
    r <- ratings_as_of(box, d + 1L, c(2L, 3L), high_abb, low_abb)
    tibble::tibble(
      game_day = d,
      team     = c(high_name, low_name),
      abbr     = c(high_abb, low_abb),
      net_adj  = c(get_playoff_adjusted_rating(high_name, r$raw_high),
                   get_playoff_adjusted_rating(low_name,  r$raw_low)),
      n_games  = c(r$n_high, r$n_low)
    )
  })
  traj <- bind_rows(rows) %>% filter(!is.na(net_adj))

  if (is.na(finals_start)) {
    warning(">>> [NET RATING GIF] No Finals start date available -- Finals shading omitted.")
  }
  attr(traj, "finals_start") <- finals_start
  attr(traj, "anchor") <- anchor
  traj
}

# ------------------------------------------------------------------------------
# One frame: the trajectory revealed up to `upto`, with the latest value labeled.
# ------------------------------------------------------------------------------
draw_frame <- function(traj, upto, y_range, x_range, finals_start, high_abb, low_abb) {
  shown <- traj %>% filter(game_day <= upto)
  tips  <- shown %>% group_by(abbr) %>% slice_max(game_day, n = 1) %>% ungroup()

  p <- ggplot(shown, aes(x = game_day, y = net_adj, color = abbr, group = abbr))

  if (!is.na(finals_start)) {
    p <- p + annotate("rect", xmin = finals_start, xmax = x_range[2],
                      ymin = -Inf, ymax = Inf, fill = "#1e293b", alpha = 0.55) +
      annotate("text", x = finals_start, y = y_range[2],
               label = "  Finals", hjust = 0, vjust = 1.4,
               color = MUTED_COLOR, size = 2.6)
  }

  p +
    geom_line(linewidth = 1.1) +
    geom_point(size = 1.6) +
    geom_point(data = tips, size = 3.2) +
    geom_text(data = tips,
              aes(label = sprintf("%s %+.2f", abbr, net_adj)),
              hjust = -0.15, vjust = -0.6, size = 3.1, fontface = "bold",
              show.legend = FALSE) +
    scale_color_manual(values = setNames(c(HIGH_COLOR, LOW_COLOR), c(high_abb, low_abb))) +
    scale_x_date(limits = x_range, date_labels = "%b %d") +
    scale_y_continuous(limits = y_range) +
    labs(
      title = sprintf("Adjusted net rating through the %d playoffs", CURRENT_SEASON),
      subtitle = sprintf("Each point uses only games played up to that date  |  through %s",
                         format(upto, "%b %d")),
      x = NULL, y = "Adjusted net rating",
      # Reader-facing caption: plain words, no filenames or artifact names.
      caption = paste("Reconstruction from box scores, not an archived forecast.",
                      "Same ratings behind the series forecasts.")
    ) +
    dark_theme
}

# ------------------------------------------------------------------------------
# Main entry point. Writes the GIF and its final-frame still, or neither.
#
# high_*/low_* default to NULL, meaning "read the matchup from the backtest
# artifact". Pass them only to override that.
# ------------------------------------------------------------------------------
build_net_rating_trajectory_gif <- function(high_abb = NULL, high_name = NULL,
                                            low_abb = NULL, low_name = NULL,
                                            out_gif = MEDIA_NET_RATING_TRAJECTORY_GIF,
                                            out_png = MEDIA_NET_RATING_TRAJECTORY_PNG) {
  if (!requireNamespace("gifski", quietly = TRUE)) {
    warning(">>> [NET RATING GIF] Package 'gifski' is not installed -- no GIF written.")
    return(invisible(NULL))
  }

  m <- finals_matchup_from_backtest()
  if (is.null(m)) {
    warning(sprintf(paste(">>> [NET RATING GIF] %s unreadable -- falling back to the 2026",
                          "Finals pair. Verify the matchup before publishing."),
                    basename(CACHE_FINALS_SERIES_BACKTEST)))
    m <- list(high_abb = "GS", high_name = "Golden State Valkyries",
              low_abb = "ATL", low_name = "Atlanta Dream",
              finals_start = as.Date(NA))
  }
  if (is.null(high_abb))  high_abb  <- m$high_abb
  if (is.null(high_name)) high_name <- m$high_name
  if (is.null(low_abb))   low_abb   <- m$low_abb
  if (is.null(low_name))  low_name  <- m$low_name

  traj <- build_trajectory(high_abb, high_name, low_abb, low_name, m$finals_start)
  if (is.null(traj) || nrow(traj) == 0) return(invisible(NULL))

  finals_start <- attr(traj, "finals_start")
  marks <- sort(unique(traj$game_day))
  # Fixed axes across every frame. Without this the lines appear to jump as the
  # range grows, which reads as rating movement that did not happen.
  pad_y <- diff(range(traj$net_adj)) * 0.18
  y_range <- c(min(traj$net_adj) - pad_y, max(traj$net_adj) + pad_y)
  x_range <- c(min(marks), max(marks) + 2L)

  tmp_dir <- file.path(tempdir(), "net_rating_frames")
  dir.create(tmp_dir, showWarnings = FALSE, recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  frame_marks <- c(marks, rep(max(marks), HOLD_FRAMES))
  png_files <- character(length(frame_marks))
  for (i in seq_along(frame_marks)) {
    png_files[i] <- file.path(tmp_dir, sprintf("frame_%03d.png", i))
    ggsave(png_files[i],
           draw_frame(traj, frame_marks[i], y_range, x_range, finals_start, high_abb, low_abb),
           width = FRAME_W / FRAME_RES, height = FRAME_H / FRAME_RES,
           dpi = FRAME_RES, units = "in", bg = BG_COLOR)
  }

  for (d in unique(c(dirname(out_gif), dirname(out_png)))) {
    if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  }

  gifski::gifski(png_files, gif_file = out_gif,
                 width = FRAME_W, height = FRAME_H, delay = 1 / FPS, progress = FALSE)

  # Reduced-motion still: a COPY of the last rendered frame, not a re-render, so
  # the animation and the still cannot disagree about the final state.
  if (!file.copy(png_files[length(png_files)], out_png, overwrite = TRUE)) {
    warning(sprintf(">>> [NET RATING GIF] Could not write the reduced-motion still to %s.", out_png))
  }

  message(sprintf(">>> [NET RATING GIF] Saved %s (%d frames, %d dates, %d held) and still %s.",
                  out_gif, length(frame_marks), length(marks), HOLD_FRAMES, basename(out_png)))
  invisible(c(gif = out_gif, png = out_png))
}

if (!interactive() && !identical(Sys.getenv("WNBA_NET_RATING_GIF_NO_AUTORUN"), "1")) {
  invisible(build_net_rating_trajectory_gif())
}
