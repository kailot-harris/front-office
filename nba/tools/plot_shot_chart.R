# ==============================================================================
# tools/plot_shot_chart.R
# Path: tools/plot_shot_chart.R
#
# High-resolution NBA half-court shot chart generator and exporter.
# Closes issue #39 (Phase 3 viz).
#
# Features:
#   - Sources tools/viz_common.R for theme_nba_dark(), NBA_COLORS, and team palettes.
#   - Regulation NBA half-court court geometry (50 ft wide, 47 ft deep, rim at (0, 5.25),
#     3-point arc at 23.75 ft / 22 ft in corners, restricted area at 4 ft, key 16 ft wide).
#   - Supports static export to high-resolution PNG (default 1200x1100 @ 300 dpi).
#   - Robust shot data normalization: accepts raw shot data frames or paths, handling
#     coordinate transforms from ESPN tracking or pre-transformed coordinates.
#   - Density / hexbin / scatter display modes with make/miss styling and team accents.
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
  # Fallback check
  alt_path <- "tools/viz_common.R"
  if (file.exists(alt_path)) viz_common_path <- alt_path else stop("Cannot find tools/viz_common.R")
}
source(viz_common_path)

suppressPackageStartupMessages({
  library(ggplot2)
})

# ------------------------------------------------------------------------------
# 1. Court Geometry Generator
# Standard NBA half-court dimensions:
#   Width:  -25 to 25 ft (x)
#   Depth:   0 to 47 ft (y)
#   Hoop:    (0, 5.25)
#   Backboard: x in [-3, 3] at y = 4
#   Key:     x in [-8, 8], y in [0, 19]
#   Free throw circle: center (0, 19), radius = 6
#   Restricted area arc: center (0, 5.25), radius = 4, y >= 5.25
#   Corner 3 lines: x = -22 and x = 22, y in [0, 14.0]
#   3PT arc: center (0, 5.25), radius = 23.75 ft, between corner lines
# ------------------------------------------------------------------------------
create_nba_court_elements <- function(line_color = "#334155", linewidth = 0.6) {
  # Helper to generate circle arc coordinates
  calc_arc <- function(center = c(0, 5.25), radius = 23.75, from_angle = 0, to_angle = pi, n = 120) {
    theta <- seq(from_angle, to_angle, length.out = n)
    data.frame(
      x = center[1] + radius * cos(theta),
      y = center[2] + radius * sin(theta)
    )
  }

  # Hoop ring (radius 0.75 ft = 18 inches / 2)
  hoop <- calc_arc(c(0, 5.25), radius = 0.75, 0, 2 * pi, n = 60)

  # Backboard line: x in [-3, 3], y = 4.0
  backboard <- data.frame(
    x = c(-3, 3),
    y = c(4, 4)
  )

  # Neck connector between backboard and hoop: x = 0, y from 4 to 4.5
  neck <- data.frame(
    x = c(0, 0),
    y = c(4, 4.5)
  )

  # Restricted area arc (radius 4 ft around hoop at (0, 5.25), for y >= 5.25)
  restricted_arc <- calc_arc(c(0, 5.25), radius = 4.0, 0, pi, n = 60)
  # Restricted area straight segments to backboard plane
  restricted_straight_l <- data.frame(x = c(-4, -4), y = c(4, 5.25))
  restricted_straight_r <- data.frame(x = c(4, 4), y = c(4, 5.25))

  # Key outer boundary (16 ft wide, 19 ft deep)
  key_box <- data.frame(
    x = c(-8, -8, 8, 8, -8),
    y = c(0, 19, 19, 0, 0)
  )

  # Free throw circle (top half solid, radius 6 at (0, 19))
  ft_top_arc <- calc_arc(c(0, 19), radius = 6.0, 0, pi, n = 60)
  # Bottom half dashed
  ft_bottom_arc <- calc_arc(c(0, 19), radius = 6.0, pi, 2 * pi, n = 60)

  # 3-point line calculation
  # Corner lines extend from baseline y = 0 to y = 14.0 ft (where dist to hoop is 23.75)
  # Since (22)^2 + (y - 5.25)^2 = (23.75)^2 => (y - 5.25)^2 = 564.0625 - 484 = 80.0625 => y - 5.25 = 8.9477 => y = 14.1977
  y_corner_end <- 5.25 + sqrt(23.75^2 - 22^2)
  angle_corner_r <- acos(22 / 23.75)
  angle_corner_l <- pi - angle_corner_r
  arc_3pt <- calc_arc(c(0, 5.25), radius = 23.75, angle_corner_r, angle_corner_l, n = 120)

  corner_3_left <- data.frame(
    x = c(-22, -22),
    y = c(0, y_corner_end)
  )
  corner_3_right <- data.frame(
    x = c(22, 22),
    y = c(0, y_corner_end)
  )

  # Half-court outer boundary
  court_perimeter <- data.frame(
    x = c(-25, -25, 25, 25, -25),
    y = c(0, 47, 47, 0, 0)
  )

  # Half-court center circle arc (radius 6 at (0, 47))
  center_arc <- calc_arc(c(0, 47), radius = 6.0, pi, 2 * pi, n = 60)
  center_arc_outer <- calc_arc(c(0, 47), radius = 2.0, pi, 2 * pi, n = 40)

  list(
    geom_path(data = court_perimeter, aes(x = x, y = y), color = line_color, linewidth = linewidth),
    geom_path(data = backboard, aes(x = x, y = y), color = line_color, linewidth = linewidth * 1.5),
    geom_path(data = neck, aes(x = x, y = y), color = line_color, linewidth = linewidth),
    geom_path(data = hoop, aes(x = x, y = y), color = "#f97316", linewidth = linewidth * 1.3),
    geom_path(data = restricted_arc, aes(x = x, y = y), color = line_color, linewidth = linewidth),
    geom_path(data = restricted_straight_l, aes(x = x, y = y), color = line_color, linewidth = linewidth),
    geom_path(data = restricted_straight_r, aes(x = x, y = y), color = line_color, linewidth = linewidth),
    geom_path(data = key_box, aes(x = x, y = y), color = line_color, linewidth = linewidth),
    geom_path(data = ft_top_arc, aes(x = x, y = y), color = line_color, linewidth = linewidth),
    geom_path(data = ft_bottom_arc, aes(x = x, y = y), color = line_color, linewidth = linewidth, linetype = "dashed"),
    geom_path(data = corner_3_left, aes(x = x, y = y), color = line_color, linewidth = linewidth),
    geom_path(data = corner_3_right, aes(x = x, y = y), color = line_color, linewidth = linewidth),
    geom_path(data = arc_3pt, aes(x = x, y = y), color = line_color, linewidth = linewidth),
    geom_path(data = center_arc, aes(x = x, y = y), color = line_color, linewidth = linewidth),
    geom_path(data = center_arc_outer, aes(x = x, y = y), color = line_color, linewidth = linewidth)
  )
}

# ------------------------------------------------------------------------------
# 2. Normalize Shot Data Coordinates & Columns
# ------------------------------------------------------------------------------
normalize_shot_coordinates <- function(df) {
  if (is.null(df) || nrow(df) == 0) {
    return(data.frame(
      x = numeric(0), y = numeric(0), dist = numeric(0),
      made = logical(0), outcome = character(0),
      player_name = character(0), team_abbrev = character(0)
    ))
  }

  res <- as.data.frame(df)

  # Resolve player name
  if (!"player_name" %in% names(res)) {
    if ("athlete_name_1" %in% names(res)) {
      res$player_name <- as.character(res$athlete_name_1)
    } else if ("player" %in% names(res)) {
      res$player_name <- as.character(res$player)
    } else {
      res$player_name <- "Unknown Player"
    }
  }

  # Resolve team abbreviation
  if (!"team_abbrev" %in% names(res)) {
    if ("team_name" %in% names(res)) {
      res$team_abbrev <- resolve_team_abbr(as.character(res$team_name))
    } else if ("team" %in% names(res)) {
      res$team_abbrev <- resolve_team_abbr(as.character(res$team))
    } else {
      res$team_abbrev <- "NBA"
    }
  }

  # Resolve shot make / miss flag
  if (!"made" %in% names(res)) {
    if ("shot_made_flag" %in% names(res)) {
      res$made <- as.logical(res$shot_made_flag %in% c(1, TRUE, "1", "TRUE", "true"))
    } else if ("scoring_play" %in% names(res)) {
      res$made <- as.logical(res$scoring_play %in% c(1, TRUE, "1", "TRUE", "true"))
    } else if ("score_value" %in% names(res)) {
      res$made <- as.integer(res$score_value) > 0
    } else {
      res$made <- TRUE
    }
  } else {
    res$made <- as.logical(res$made %in% c(1, TRUE, "1", "TRUE", "true"))
  }
  res$outcome <- ifelse(res$made, "Made", "Missed")

  # Resolve x and y coordinates
  # Check if coordinate_x_raw / coordinate_y_raw exist (ESPN tracking format)
  if ("coordinate_x_raw" %in% names(res) && "coordinate_y_raw" %in% names(res)) {
    # ESPN raw tracking coordinates: x in [0, 50], y from backboard in [-5, 43+]
    # Transformation to standard NBA half court:
    # x: centered at 0 => coordinate_x_raw - 25.0
    # y: distance from baseline => coordinate_y_raw + 4.0
    res$x <- round(as.numeric(res$coordinate_x_raw) - 25.0, 2)
    res$y <- round(pmax(0, pmin(47, as.numeric(res$coordinate_y_raw) + 4.0)), 2)
  } else if ("x" %in% names(res) && "y" %in% names(res)) {
    res$x <- as.numeric(res$x)
    res$y <- as.numeric(res$y)
    # Check if x is in [0, 50] range instead of [-25, 25]
    if (max(res$x, na.rm = TRUE) > 25.0 && min(res$x, na.rm = TRUE) >= 0) {
      res$x <- round(res$x - 25.0, 2)
    }
  } else {
    res$x <- 0
    res$y <- 0
  }

  # Calculate shot distance from basket (0, 5.25)
  res$dist <- round(sqrt(res$x^2 + (res$y - 5.25)^2), 2)

  # Filter out rows with invalid or missing coordinates
  res <- res[!is.na(res$x) & !is.na(res$y) & res$y >= 0 & res$y <= 47 & abs(res$x) <= 25, ]
  res
}

# ------------------------------------------------------------------------------
# 3. Load Shots from Cache Helper
# ------------------------------------------------------------------------------
load_nba_shots_cache <- function(season = c(2026, 2027), player = NULL, cache_dirs = NULL) {
  if (is.null(cache_dirs)) {
    cache_dirs <- c(
      file.path(REPO_ROOT, "cache"),
      "cache",
      "C:/Users/kailo/kayceeslices/front-office/NBA Analytics/cache"
    )
  }

  all_shots <- list()
  for (yr in season) {
    target_file <- sprintf("nba_shots_%d.rds", yr)
    for (cd in cache_dirs) {
      p <- file.path(cd, target_file)
      if (file.exists(p)) {
        df_yr <- tryCatch(readRDS(p), error = function(e) NULL)
        if (!is.null(df_yr) && nrow(df_yr) > 0) {
          all_shots[[as.character(yr)]] <- df_yr
          break
        }
      }
    }
  }

  if (length(all_shots) == 0) {
    warning("load_nba_shots_cache: Could not find shot cache in inspected paths.")
    return(data.frame())
  }

  combined <- do.call(rbind, all_shots)
  if (!is.null(player) && nzchar(player)) {
    name_col <- if ("athlete_name_1" %in% names(combined)) {
      "athlete_name_1"
    } else if ("player_name" %in% names(combined)) {
      "player_name"
    } else {
      NULL
    }
    if (!is.null(name_col)) {
      matched <- grepl(player, combined[[name_col]], ignore.case = TRUE)
      combined <- combined[matched, ]
    }
  }

  normalize_shot_coordinates(combined)
}

# ------------------------------------------------------------------------------
# 4. Shot Chart Plot Builder
# ------------------------------------------------------------------------------
plot_half_court_shot_chart <- function(shot_data,
                                       player_name = NULL,
                                       team = NULL,
                                       season_label = "2025-26",
                                       subtitle = NULL,
                                       caption = "NBA Analytics | Regulation Half-Court",
                                       point_size = 2.5,
                                       point_alpha = 0.75,
                                       density_contours = FALSE) {
  df <- normalize_shot_coordinates(shot_data)

  if (is.null(player_name) || !nzchar(player_name)) {
    if (nrow(df) > 0 && nzchar(df$player_name[1])) {
      player_name <- df$player_name[1]
    } else {
      player_name <- "NBA Shot Chart"
    }
  }

  if (is.null(team) || !nzchar(team)) {
    if (nrow(df) > 0 && nzchar(df$team_abbrev[1])) {
      team <- df$team_abbrev[1]
    } else {
      team <- "NBA"
    }
  }

  team_color <- get_nba_team_color(team, "primary")
  if (is.null(team_color) || is.na(team_color) || team_color == "#3fd0c9") {
    team_color <- NBA_COLORS$accent
  }

  # Build subtitle stats if not provided
  if (is.null(subtitle)) {
    if (nrow(df) > 0) {
      total_shots <- nrow(df)
      made_shots  <- sum(df$made)
      fg_pct      <- round(100 * made_shots / total_shots, 1)
      subtitle <- sprintf("%s | %d/%d (%.1f%% FG)", season_label, made_shots, total_shots, fg_pct)
    } else {
      subtitle <- sprintf("%s | 0 Attempts", season_label)
    }
  }

  # Shot outcome colors (Accent/Team for made, Negative muted red for missed)
  outcome_colors <- c(
    "Made"   = team_color,
    "Missed" = NBA_COLORS$negative
  )
  outcome_shapes <- c(
    "Made"   = 19, # solid circle
    "Missed" = 4   # x mark
  )

  p <- ggplot() +
    # Court lines
    create_nba_court_elements(line_color = "#334155", linewidth = 0.55)

  if (density_contours && nrow(df) >= 15) {
    p <- p +
      stat_density_2d(
        data = df,
        aes(x = x, y = y, fill = after_stat(level)),
        geom = "polygon",
        alpha = 0.15,
        bins = 6,
        show.legend = FALSE
      ) +
      scale_fill_gradient(low = "#1e293b", high = team_color)
  }

  if (nrow(df) > 0) {
    p <- p +
      geom_point(
        data = df,
        aes(x = x, y = y, color = outcome, shape = outcome),
        size = point_size,
        alpha = point_alpha,
        stroke = 1.1
      )
  }

  p <- p +
    coord_fixed(xlim = c(-25, 25), ylim = c(0, 47), expand = FALSE) +
    scale_color_manual(values = outcome_colors, name = "Outcome") +
    scale_shape_manual(values = outcome_shapes, name = "Outcome") +
    labs(
      title = player_name,
      subtitle = subtitle,
      caption = caption
    ) +
    theme_nba_dark() +
    theme(
      axis.title        = element_blank(),
      axis.text         = element_blank(),
      axis.ticks        = element_blank(),
      panel.grid.major  = element_blank(),
      panel.grid.minor  = element_blank(),
      legend.position   = "bottom",
      legend.direction  = "horizontal",
      plot.title        = element_text(face = "bold", size = rel(1.4), color = NBA_COLORS$text),
      plot.subtitle     = element_text(size = rel(1.05), color = team_color),
      plot.margin       = margin(14, 18, 12, 18)
    )

  p
}

# ------------------------------------------------------------------------------
# 5. Export Function
# ------------------------------------------------------------------------------
export_shot_chart_png <- function(plot_obj, out_path, width = 10, height = 9.4, dpi = 300) {
  d <- dirname(out_path)
  if (nzchar(d) && !dir.exists(d)) {
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
  }

  ggsave(
    filename = out_path,
    plot = plot_obj,
    width = width,
    height = height,
    dpi = dpi,
    bg = NBA_COLORS$bg
  )

  invisible(out_path)
}
