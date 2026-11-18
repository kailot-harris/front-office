# Pipeline visualization: stylized graphic of one date's NBA game predictions
# (Sys.Date() by default, or --date=YYYY-MM-DD), built from prediction_accuracy_log.rds.
# Generates both date-stamped and canonical "_today" PNG and GIF artifacts in cache/ and
# copies them to web/public/media/.
#
# Behaviour (issue #130):
#   * The prediction log is the only source. If it is missing, unreadable, or lacks the
#     columns this graphic needs, the script stops with an error (non-zero exit under
#     Rscript; a [FAILED] stage warning under run_full_pipeline.R's run_stage()).
#   * If the target date has no games in the log, the script draws a "No Games Scheduled"
#     card FOR THAT DATE (never another date's slate), names the next logged slate when
#     one exists, writes it to the same four output paths, and finishes normally (exit 0).
#
# Set NBA_SKIP_STAGE_AUTORUN=1 to source this file for its definitions alone (tests).
PROJECT_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  if (file.exists(file.path(base, "config.R"))) {
    normalizePath(base, winslash = "/", mustWork = FALSE)
  } else if (file.exists(file.path(base, "..", "config.R"))) {
    normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
  } else if (file.exists(file.path(getwd(), "config.R"))) {
    normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  } else {
    stop("Cannot locate the NBA Analytics repo root (no config.R next to this script, ",
         "in its parent, or in the working directory).")
  }
})
setwd(PROJECT_ROOT)
source("config.R")
suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(magick)
})

# Shared palette (unchanged from the original game-day graphic).
PRED_PLOT_PALETTE <- list(
  bg          = "#0b1120",
  panel_bg    = "#111a2e",
  grid_col    = "#22304a",
  away_col    = "#ff6b57",
  home_col    = "#3fd0c9",
  text_col    = "#e7ecf5",
  subtext_col = "#9fb0c9"
)

PRED_LOG_REQUIRED_COLS <- c("game_date", "home_team", "away_team",
                            "predicted_home_win_prob", "predicted_winner", "status")

# Target date: --date=YYYY-MM-DD, or Sys.Date().
parse_prediction_target_date <- function(args = commandArgs(trailingOnly = TRUE)) {
  target <- Sys.Date()
  for (arg in args) {
    if (grepl("^--date=", arg)) {
      target <- as.Date(sub("^--date=", "", arg))
    }
  }
  if (is.na(target)) stop("Invalid --date value; expected --date=YYYY-MM-DD.", call. = FALSE)
  target
}

# Read and validate the prediction log. Every failure here is a real error: an empty
# slate is handled downstream, but missing/unreadable data must never look like a holiday.
load_prediction_log <- function(path) {
  if (!file.exists(path)) {
    stop(sprintf("Prediction log not found: %s. Cannot draw the daily predictions image.", path),
         call. = FALSE)
  }
  pred_log <- tryCatch(readRDS(path), error = function(e) {
    stop(sprintf("Prediction log is unreadable: %s (%s)", path, conditionMessage(e)), call. = FALSE)
  })
  if (!is.data.frame(pred_log)) {
    stop(sprintf("Prediction log is not a data frame: %s", path), call. = FALSE)
  }
  missing_cols <- setdiff(PRED_LOG_REQUIRED_COLS, names(pred_log))
  if (length(missing_cols) > 0) {
    stop(sprintf("Prediction log %s is missing required column(s): %s",
                 path, paste(missing_cols, collapse = ", ")), call. = FALSE)
  }
  pred_log
}

# Next logged date with games after target_date, with its game count (or NULL).
find_next_slate <- function(pred_log, target_date) {
  dates <- as.Date(pred_log$game_date)
  later <- sort(unique(dates[!is.na(dates) & dates > target_date]))
  if (length(later) == 0) return(NULL)
  rows <- pred_log[!is.na(dates) & dates == later[1], , drop = FALSE]
  n_games <- if ("game_id" %in% names(rows)) length(unique(rows$game_id)) else nrow(rows)
  list(date = later[1], n_games = n_games)
}

# TRUE only when target_date sits in the gap between the last logged game of one season
# and the first logged game of the next. A date after the last logged game is NOT called
# offseason, because the log only reaches as far ahead as projections have been made.
is_between_seasons <- function(pred_log, target_date) {
  if (!"season" %in% names(pred_log)) return(FALSE)
  dates <- as.Date(pred_log$game_date)
  keep <- !is.na(dates) & !is.na(pred_log$season)
  dates <- dates[keep]; seasons <- pred_log$season[keep]
  before <- dates < target_date; after <- dates > target_date
  if (!any(before) || !any(after)) return(FALSE)
  prev_season <- seasons[before][which.max(dates[before])]
  next_season <- seasons[after][which.min(dates[after])]
  !identical(prev_season, next_season)
}

build_game_day_plot <- function(today_games, target_date) {
  pal <- PRED_PLOT_PALETTE
  bg <- pal$bg; panel_bg <- pal$panel_bg; grid_col <- pal$grid_col
  away_col <- pal$away_col; home_col <- pal$home_col
  text_col <- pal$text_col; subtext_col <- pal$subtext_col

  df <- today_games |>
    mutate(
      home_win_prob = predicted_home_win_prob,
      home_prob_pct = home_win_prob * 100,
      matchup = paste0(away_team, " @ ", home_team),
      picked_winner_prob = ifelse(predicted_winner == home_team, home_win_prob, 1 - home_win_prob),
      pick_label = sprintf("Model pick: %s (%.1f%% win prob) \u00b7 %s", predicted_winner, picked_winner_prob * 100, status)
    ) |>
    arrange(home_win_prob) |>
    mutate(matchup = factor(matchup, levels = matchup))

  p <- ggplot(df, aes(y = matchup)) +
    geom_vline(xintercept = 50, linetype = "dashed", color = grid_col, linewidth = 0.6) +
    geom_segment(aes(x = 50, xend = home_prob_pct, yend = matchup),
                 color = ifelse(df$home_prob_pct >= 50, home_col, away_col),
                 linewidth = 3.2, lineend = "round") +
    geom_point(aes(x = home_prob_pct),
               color = ifelse(df$home_prob_pct >= 50, home_col, away_col),
               size = 5.5) +
    geom_text(aes(x = home_prob_pct,
                  label = sprintf("%.0f%%", home_prob_pct),
                  hjust = ifelse(df$home_prob_pct >= 50, -0.55, 1.55)),
              color = text_col, size = 3.4, fontface = "bold") +
    geom_text(aes(x = 4, y = matchup, label = pick_label),
              hjust = 0, vjust = 3.2, color = subtext_col, size = 2.9, fontface = "italic") +
    scale_x_continuous(limits = c(0, 100), breaks = c(0, 25, 50, 75, 100),
                       labels = c("0%", "25%", "50%", "75%", "100%"),
                       expand = c(0, 0)) +
    scale_y_discrete(expand = expansion(add = 0.9)) +
    labs(
      title    = paste0("NBA \u2014 Model Projections for ", format(target_date, "%b %d, %Y")),
      subtitle = paste0("Home win probability (dot) \u00b7 Season ", CURRENT_SEASON,
                         " \u00b7 Generated ", format(Sys.Date(), "%b %d, %Y")),
      x = "Home team win probability",
      y = NULL,
      caption = "Dot right of the dashed 50% line = home favored \u00b7 left = away favored \u00b7 NBA Analytics"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.background   = element_rect(fill = bg, color = NA),
      panel.background  = element_rect(fill = panel_bg, color = NA),
      panel.grid.major.x = element_line(color = grid_col, linewidth = 0.3),
      panel.grid.major.y = element_blank(),
      panel.grid.minor   = element_blank(),
      axis.text          = element_text(color = text_col),
      axis.title.x       = element_text(color = subtext_col, margin = margin(t = 10)),
      axis.text.y        = element_text(color = text_col, face = "bold", size = 11),
      plot.title         = element_text(color = text_col, face = "bold", size = 20, margin = margin(b = 4)),
      plot.subtitle      = element_text(color = subtext_col, size = 11, margin = margin(b = 14)),
      plot.caption       = element_text(color = subtext_col, size = 8, margin = margin(t = 12)),
      plot.margin        = margin(20, 30, 16, 16)
    )

  list(plot = p, height = max(6, 1.2 + 0.7 * nrow(df)))
}

# Fallback card for a date with no games: same palette, width and title/subtitle styling.
build_no_games_plot <- function(target_date, next_slate = NULL, offseason = FALSE) {
  pal <- PRED_PLOT_PALETTE
  headline <- if (isTRUE(offseason)) "Offseason" else "No Games Scheduled"
  body <- if (isTRUE(offseason)) "NBA offseason \u2014 no games on this date" else "No NBA games on this date"
  next_line <- if (!is.null(next_slate)) {
    sprintf("Next slate: %s (%d game%s)", format(next_slate$date, "%a, %b %d"),
            next_slate$n_games, if (next_slate$n_games == 1) "" else "s")
  } else {
    "Next slate: not yet in the prediction log"
  }

  p <- ggplot() +
    annotate("text", x = 50, y = 62, label = body,
             color = pal$text_col, size = 8, fontface = "bold") +
    annotate("segment", x = 30, xend = 70, y = 47, yend = 47,
             color = pal$home_col, linewidth = 1.2, lineend = "round") +
    annotate("text", x = 50, y = 32, label = next_line,
             color = pal$home_col, size = 5.5, fontface = "bold") +
    scale_x_continuous(limits = c(0, 100), expand = c(0, 0)) +
    scale_y_continuous(limits = c(0, 100), expand = c(0, 0)) +
    labs(
      title    = paste0("NBA \u2014 ", headline, " for ", format(target_date, "%b %d, %Y")),
      subtitle = paste0("Season ", CURRENT_SEASON, " \u00b7 Generated ", format(Sys.Date(), "%b %d, %Y")),
      x = NULL, y = NULL,
      caption = "Model projections appear here on game days \u00b7 NBA Analytics"
    ) +
    theme_void(base_size = 12) +
    theme(
      plot.background  = element_rect(fill = pal$bg, color = NA),
      panel.background = element_rect(fill = pal$panel_bg, color = NA),
      plot.title       = element_text(color = pal$text_col, face = "bold", size = 20, margin = margin(b = 4)),
      plot.subtitle    = element_text(color = pal$subtext_col, size = 11, margin = margin(b = 14)),
      plot.caption     = element_text(color = pal$subtext_col, size = 8, margin = margin(t = 12)),
      plot.margin      = margin(20, 30, 16, 16)
    )

  list(plot = p, height = 6)
}

# Write dated + "_today" PNG/GIF into cache_dir and copy all four into web_media_dir.
write_prediction_graphics <- function(p, height, target_date, cache_dir, web_media_dir) {
  date_str <- format(target_date, "%Y-%m-%d")
  filename_png <- sprintf("nba_predictions_%s.png", date_str)
  filename_gif <- sprintf("nba_predictions_%s.gif", date_str)
  out_path_png <- file.path(cache_dir, filename_png)
  out_path_gif <- file.path(cache_dir, filename_gif)

  ggsave(out_path_png, p, width = 10, height = height, dpi = 200, bg = PRED_PLOT_PALETTE$bg)
  cat("Saved PNG:", out_path_png, "\n")

  img <- magick::image_read(out_path_png)
  magick::image_write(img, out_path_gif, format = "gif")
  cat("Saved GIF:", out_path_gif, "\n")

  today_png <- file.path(cache_dir, "nba_predictions_today.png")
  today_gif <- file.path(cache_dir, "nba_predictions_today.gif")
  file.copy(out_path_png, today_png, overwrite = TRUE)
  file.copy(out_path_gif, today_gif, overwrite = TRUE)

  if (!dir.exists(web_media_dir)) dir.create(web_media_dir, recursive = TRUE)
  file.copy(out_path_png, file.path(web_media_dir, filename_png), overwrite = TRUE)
  file.copy(out_path_gif, file.path(web_media_dir, filename_gif), overwrite = TRUE)
  file.copy(today_png, file.path(web_media_dir, "nba_predictions_today.png"), overwrite = TRUE)
  file.copy(today_gif, file.path(web_media_dir, "nba_predictions_today.gif"), overwrite = TRUE)
  cat("Synced all prediction graphics to:", web_media_dir, "\n")

  c(dated_png = out_path_png, dated_gif = out_path_gif,
    today_png = today_png, today_gif = today_gif)
}

plot_today_predictions <- function(target_date = Sys.Date(),
                                   pred_log_file = file.path(CACHE_DIR, "prediction_accuracy_log.rds"),
                                   cache_dir = CACHE_DIR,
                                   web_media_dir = file.path(PROJECT_ROOT, "web", "public", "media")) {
  target_date <- as.Date(target_date)
  pred_log <- load_prediction_log(pred_log_file)
  today_games <- pred_log |> filter(as.Date(game_date) == target_date)

  if (nrow(today_games) > 0) {
    built <- build_game_day_plot(today_games, target_date)
    paths <- write_prediction_graphics(built$plot, built$height, target_date, cache_dir, web_media_dir)
    message(sprintf("Wrote NBA predictions image for %s (%d games).", target_date, nrow(today_games)))
    return(invisible(list(kind = "game_day", target_date = target_date,
                          n_games = nrow(today_games), paths = paths)))
  }

  next_slate <- find_next_slate(pred_log, target_date)
  offseason <- is_between_seasons(pred_log, target_date)
  built <- build_no_games_plot(target_date, next_slate, offseason)
  paths <- write_prediction_graphics(built$plot, built$height, target_date, cache_dir, web_media_dir)
  message(sprintf("No NBA games on %s; wrote %s fallback image (%s)",
                  target_date, if (offseason) "offseason" else "no-games",
                  if (is.null(next_slate)) "no later slate in the prediction log"
                  else sprintf("next slate %s", next_slate$date)))
  invisible(list(kind = if (offseason) "offseason" else "no_games", target_date = target_date,
                 n_games = 0L, next_slate = next_slate, paths = paths))
}

if (!nzchar(Sys.getenv("NBA_SKIP_STAGE_AUTORUN"))) {
  plot_today_predictions(parse_prediction_target_date())
}
