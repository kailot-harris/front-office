# ==============================================================================
# tools/export_player_spatial_maps.R — Player Dropdown Spatial Maps Exporter
# Path: c:/Users/kailo/kayceeslices/front-office/MLB Analytics/tools/export_player_spatial_maps.R
#
# Generates empirical per-player spatial maps from Statcast tracking data:
#   - Batters: Field Spray Charts from tracked balls in play (type == "X",
#              hc_x, hc_y, launch_speed, launch_angle, hit_distance_sc, 30-park HR checks)
#   - Pitchers: Strike Zone Matrix & Arsenal Maps from tracked pitch events
#              (plate_x, plate_z, release_speed, pfx_x, pfx_z, pitch_type)
#
# Strictly empirical: zero synthetic fallbacks or RNG draws (Issue #71).
# Players without Statcast events in the ingested sample emit empty tracking arrays
# and has_statcast_tracking = FALSE.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
  library(jsonlite)
})

if (!exists("PROJECT_DIR", inherits = FALSE)) {
  PROJECT_DIR <- if (exists("MLB_ROOT_DIR", inherits = FALSE)) MLB_ROOT_DIR else getwd()
}
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

source("logging_utils.R")
source("config.R")
if (!exists("get_mlb_park_dimensions", mode = "function")) {
  source("tools/export_spatial_analytics.R")
}
.LOG_SCRIPT <- "export_player_spatial_maps.R"

pt_labels <- c(
  "FF" = "4-Seam Fastball", "SI" = "Sinker", "FC" = "Cutter", "SL" = "Slider",
  "ST" = "Sweeper", "CH" = "Changeup", "FS" = "Splitter", "CU" = "Curveball",
  "KC" = "Knuckle Curve", "SV" = "Slurve", "FA" = "Fastball", "KN" = "Knuckleball",
  "PO" = "Pitchout"
)

export_player_spatial_maps <- function(out_dir = file.path(MLB_ROOT_DIR, "web", "public", "data")) {
  start_time <- Sys.time()
  cat("==================================================================\n")
  cat(">>> EXPORTING EMPIRICAL PLAYER SPATIAL MAPS (HITS & PITCHES)\n")
  cat("==================================================================\n")

  if (!dir.exists(out_dir)) {
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  }

  players_file <- file.path(out_dir, "projections_season_players.json")
  if (!file.exists(players_file)) {
    alt_p <- file.path(MLB_ROOT_DIR, "web", "public", "data", "projections_season_players.json")
    if (file.exists(alt_p)) players_file <- alt_p
  }
  if (!file.exists(players_file)) {
    stop(sprintf("Players file not found at %s. Run export_web_data.R first.", players_file))
  }
  players <- jsonlite::fromJSON(players_file)

  sc_file <- file.path(MLB_ROOT_DIR, "cache", "ingest", "statcast_pitches_2024-04-01_2024-04-02.rds")
  if (!file.exists(sc_file)) {
    alt_paths <- c(
      file.path(MLB_ROOT_DIR, "..", "..", "MLB Analytics", "cache", "ingest", "statcast_pitches_2024-04-01_2024-04-02.rds"),
      file.path(MLB_ROOT_DIR, "..", "MLB Analytics", "cache", "ingest", "statcast_pitches_2024-04-01_2024-04-02.rds")
    )
    for (ap in alt_paths) {
      if (file.exists(ap)) {
        sc_file <- ap
        break
      }
    }
  }
  sc_df <- if (file.exists(sc_file)) readRDS(sc_file) else data.frame()

  cw_file <- file.path(MLB_ROOT_DIR, "cache", "id_crosswalk", "mlb_id_crosswalk.rds")
  if (!file.exists(cw_file)) {
    alt_paths_cw <- c(
      file.path(MLB_ROOT_DIR, "..", "..", "MLB Analytics", "cache", "id_crosswalk", "mlb_id_crosswalk.rds"),
      file.path(MLB_ROOT_DIR, "..", "MLB Analytics", "cache", "id_crosswalk", "mlb_id_crosswalk.rds")
    )
    for (ap in alt_paths_cw) {
      if (file.exists(ap)) {
        cw_file <- ap
        break
      }
    }
  }
  cw_df <- if (file.exists(cw_file)) readRDS(cw_file) else data.frame()

  park_dims <- get_mlb_park_dimensions()

  eval_hr_in_park <- function(dist, angle, park) {
    if (is.na(dist) || dist < 290) return(FALSE)
    t_angle <- max(-45, min(45, angle))
    fence_dist <- if (t_angle <= -22.5) {
      park$lf + (park$lcf - park$lf) * ((t_angle + 45) / 22.5)
    } else if (t_angle <= 0) {
      park$lcf + (park$cf - park$lcf) * ((t_angle + 22.5) / 22.5)
    } else if (t_angle <= 22.5) {
      park$cf + (park$rcf - park$cf) * (t_angle / 22.5)
    } else {
      park$rcf + (park$rf - park$rcf) * ((t_angle - 22.5) / 22.5)
    }
    dist >= fence_dist
  }

  has_sc <- nrow(sc_df) > 0

  # Handedness lookup maps
  stand_lookup <- if (has_sc && "stand" %in% names(sc_df)) {
    clean_s <- sc_df %>% dplyr::filter(!is.na(stand) & !is.na(batter))
    setNames(as.character(clean_s$stand), as.character(clean_s$batter))
  } else list()

  throws_lookup <- if (has_sc && "p_throws" %in% names(sc_df)) {
    clean_t <- sc_df %>% dplyr::filter(!is.na(p_throws) & !is.na(pitcher))
    setNames(as.character(clean_t$p_throws), as.character(clean_t$pitcher))
  } else list()

  # Process tracked Statcast batted balls (empirical balls in play: type == "X")
  sc_batted <- if (has_sc) {
    sc_df %>%
      dplyr::filter(type == "X" & !is.na(hc_x) & !is.na(hc_y)) %>%
      dplyr::mutate(
        d_x = round(2.5 * (as.numeric(hc_x) - 125.42), 1),
        d_y = round(2.5 * (198.27 - as.numeric(hc_y)), 1),
        dist_calc = round(sqrt(d_x^2 + d_y^2), 1),
        hit_dist = round(coalesce(as.numeric(hit_distance_sc), dist_calc), 1),
        bearing_deg = round(atan2(d_x, d_y) * 180 / pi, 1),
        launch_ev = round(coalesce(as.numeric(launch_speed), 0), 1),
        launch_la = round(coalesce(as.numeric(launch_angle), 0), 1),
        batter_chr = as.character(batter),
        hit_type = case_when(
          events == "home_run" ~ "Home Run",
          events == "triple" ~ "Triple",
          events == "double" ~ "Double",
          events == "single" ~ "Single",
          TRUE ~ "Out"
        )
      )
  } else data.frame()

  # Process tracked Statcast pitches (empirical pitch events)
  sc_pitches <- if (has_sc) {
    sc_df %>%
      dplyr::filter(!is.na(plate_x) & !is.na(plate_z) & !is.na(release_speed) & !is.na(pitch_type)) %>%
      dplyr::mutate(
        px = round(as.numeric(plate_x), 2),
        pz = round(as.numeric(plate_z), 2),
        pitcher_chr = as.character(pitcher),
        velo = round(as.numeric(release_speed), 1),
        pfx_x = round(as.numeric(pfx_x) * 12, 1),
        pfx_z = round(as.numeric(pfx_z) * 12, 1),
        pitch_type = as.character(pitch_type),
        in_zone = px >= -0.85 & px <= 0.85 & pz >= 1.5 & pz <= 3.5,
        is_strike = description %in% c("called_strike", "swinging_strike", "foul", "foul_tip", "hit_into_play"),
        result = case_when(
          description == "called_strike" ~ "called_strike",
          description %in% c("swinging_strike", "swinging_strike_blocked") ~ "swinging_strike",
          description %in% c("foul", "foul_tip") ~ "foul",
          description == "hit_into_play" ~ "in_play",
          TRUE ~ "ball"
        )
      )
  } else data.frame()

  cat(sprintf("Processing %d players (%d batters, %d pitchers)...\n",
              nrow(players),
              sum(players$player_type == "Batter"),
              sum(players$player_type == "Pitcher")))

  batted_by_batter <- if (nrow(sc_batted) > 0) split(sc_batted, sc_batted$batter_chr) else list()
  pitches_by_pitcher <- if (nrow(sc_pitches) > 0) split(sc_pitches, sc_pitches$pitcher_chr) else list()

  spatial_maps <- list()

  for (i in seq_len(nrow(players))) {
    p <- players[i, ]
    p_id <- p$player_id
    mlbam <- as.character(p$mlbam_id)
    is_batter <- p$player_type == "Batter"

    if (is_batter) {
      # ------------------------------------------------------------------------
      # BATTER SPATIAL MAP (Empirical Statcast Batted Balls)
      # ------------------------------------------------------------------------
      sc_sub <- if (mlbam %in% names(batted_by_batter)) batted_by_batter[[mlbam]] else NULL
      is_statcast <- !is.null(sc_sub) && nrow(sc_sub) > 0

      # Determine handedness: L or R
      stand <- if (mlbam %in% names(stand_lookup)) stand_lookup[[mlbam]] else "R"
      is_lhb <- stand == "L"

      balls_list <- list()
      if (is_statcast) {
        for (j in seq_len(nrow(sc_sub))) {
          b <- sc_sub[j, ]
          parks_hr <- sum(vapply(park_dims, function(park) eval_hr_in_park(b$hit_dist, b$bearing_deg, park), logical(1)))
          balls_list[[length(balls_list) + 1]] <- list(
            x = b$d_x,
            y = b$d_y,
            dist = b$hit_dist,
            bearing = b$bearing_deg,
            ev = b$launch_ev,
            la = b$launch_la,
            hit_type = b$hit_type,
            event = as.character(b$events),
            parks_hr_count = parks_hr
          )
        }
      }

      n_total <- length(balls_list)

      if (n_total > 0) {
        ev_vec <- vapply(balls_list, function(b) b$ev, numeric(1))
        dist_vec <- vapply(balls_list, function(b) b$dist, numeric(1))
        la_vec <- vapply(balls_list, function(b) b$la, numeric(1))
        bear_vec <- vapply(balls_list, function(b) b$bearing, numeric(1))
        type_vec <- vapply(balls_list, function(b) b$hit_type, character(1))

        n_hits <- sum(type_vec %in% c("Single", "Double", "Triple", "Home Run"))
        n_hrs <- sum(type_vec == "Home Run")

        # Pull vs Center vs Oppo based on batter handedness
        pull_count <- if (is_lhb) sum(bear_vec > 15.0) else sum(bear_vec < -15.0)
        oppo_count <- if (is_lhb) sum(bear_vec < -15.0) else sum(bear_vec > 15.0)
        center_count <- sum(abs(bear_vec) <= 15.0)

        batter_summary <- list(
          total_balls = n_total,
          hits = n_hits,
          home_runs = n_hrs,
          avg_ev = round(mean(ev_vec, na.rm = TRUE), 1),
          max_ev = round(max(ev_vec, na.rm = TRUE), 1),
          avg_dist = round(mean(dist_vec, na.rm = TRUE), 1),
          max_dist = round(max(dist_vec, na.rm = TRUE), 1),
          avg_la = round(mean(la_vec, na.rm = TRUE), 1),
          hard_hit_pct = round(sum(ev_vec >= 95.0, na.rm = TRUE) / n_total * 100, 1),
          pull_pct = round(pull_count / n_total * 100, 1),
          center_pct = round(center_count / n_total * 100, 1),
          oppo_pct = round(oppo_count / n_total * 100, 1)
        )
      } else {
        batter_summary <- list(
          total_balls = 0,
          hits = 0,
          home_runs = 0,
          avg_ev = 0,
          max_ev = 0,
          avg_dist = 0,
          max_dist = 0,
          avg_la = 0,
          hard_hit_pct = 0,
          pull_pct = 0,
          center_pct = 0,
          oppo_pct = 0
        )
      }

      spatial_maps[[p_id]] <- list(
        player_id = p_id,
        player_name = p$player_name,
        player_type = "Batter",
        team = p$team,
        position = p$position,
        is_statcast_tracked = is_statcast,
        has_statcast_tracking = is_statcast,
        sample_size = n_total,
        batted_balls = balls_list,
        batter_summary = batter_summary
      )

    } else {
      # ------------------------------------------------------------------------
      # PITCHER SPATIAL MAP (Empirical Statcast Pitches in Arsenal)
      # ------------------------------------------------------------------------
      sc_sub <- if (mlbam %in% names(pitches_by_pitcher)) pitches_by_pitcher[[mlbam]] else NULL
      is_statcast <- !is.null(sc_sub) && nrow(sc_sub) > 0

      pitches_list <- list()
      if (is_statcast) {
        for (j in seq_len(nrow(sc_sub))) {
          pt <- sc_sub[j, ]
          pt_code <- as.character(pt$pitch_type)
          pt_name <- ifelse(pt_code %in% names(pt_labels), pt_labels[pt_code], pt_code)
          pitches_list[[length(pitches_list) + 1]] <- list(
            px = pt$px,
            pz = pt$pz,
            pitch_type = pt_code,
            pitch_name = pt_name,
            velo = pt$velo,
            pfx_x = pt$pfx_x,
            pfx_z = pt$pfx_z,
            result = pt$result,
            is_strike = pt$is_strike,
            in_zone = pt$in_zone
          )
        }
      }

      n_pitches <- length(pitches_list)

      if (n_pitches > 0) {
        v_vec <- vapply(pitches_list, function(pt) pt$velo, numeric(1))
        str_vec <- vapply(pitches_list, function(pt) pt$is_strike, logical(1))
        zone_vec <- vapply(pitches_list, function(pt) pt$in_zone, logical(1))
        res_vec <- vapply(pitches_list, function(pt) pt$result, character(1))
        type_vec <- vapply(pitches_list, function(pt) pt$pitch_type, character(1))
        name_vec <- vapply(pitches_list, function(pt) pt$pitch_name, character(1))

        unique_types <- unique(type_vec)
        arsenal_list <- list()
        for (ut in unique_types) {
          idx <- which(type_vec == ut)
          sub_v <- v_vec[idx]
          sub_res <- res_vec[idx]
          whiffs <- sum(sub_res == "swinging_strike")
          swings <- sum(sub_res %in% c("swinging_strike", "foul", "in_play"))
          hb_sub <- vapply(pitches_list[idx], function(x) x$pfx_x, numeric(1))
          ivb_sub <- vapply(pitches_list[idx], function(x) x$pfx_z, numeric(1))

          arsenal_list[[length(arsenal_list) + 1]] <- list(
            pitch_type = ut,
            pitch_name = name_vec[idx[1]],
            count = length(idx),
            pct = round(length(idx) / n_pitches * 100, 1),
            avg_velo = round(mean(sub_v, na.rm = TRUE), 1),
            avg_hb = round(mean(hb_sub, na.rm = TRUE), 1),
            avg_ivb = round(mean(ivb_sub, na.rm = TRUE), 1),
            whiff_pct = round(whiffs / max(1, swings) * 100, 1)
          )
        }
        arsenal_list <- arsenal_list[order(vapply(arsenal_list, function(a) a$count, integer(1)), decreasing = TRUE)]

        pitcher_summary <- list(
          total_pitches = n_pitches,
          avg_velo = round(mean(v_vec, na.rm = TRUE), 1),
          max_velo = round(max(v_vec, na.rm = TRUE), 1),
          strike_pct = round(sum(str_vec) / n_pitches * 100, 1),
          zone_pct = round(sum(zone_vec) / n_pitches * 100, 1),
          whiff_pct = round(sum(res_vec == "swinging_strike") / n_pitches * 100, 1),
          called_strike_pct = round(sum(res_vec == "called_strike") / n_pitches * 100, 1),
          arsenal = arsenal_list
        )
      } else {
        pitcher_summary <- list(
          total_pitches = 0,
          avg_velo = 0,
          max_velo = 0,
          strike_pct = 0,
          zone_pct = 0,
          whiff_pct = 0,
          called_strike_pct = 0,
          arsenal = list()
        )
      }

      spatial_maps[[p_id]] <- list(
        player_id = p_id,
        player_name = p$player_name,
        player_type = "Pitcher",
        team = p$team,
        position = p$position,
        is_statcast_tracked = is_statcast,
        has_statcast_tracking = is_statcast,
        sample_size = n_pitches,
        pitches = pitches_list,
        pitcher_summary = pitcher_summary
      )
    }
  }

  out_file <- file.path(out_dir, "player_spatial_maps.json")
  cat(sprintf("Serializing %d player spatial maps to JSON...\n", length(spatial_maps)))
  jsonlite::write_json(spatial_maps, out_file, pretty = FALSE, auto_unbox = TRUE)

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  file_size_mb <- file.info(out_file)$size / (1024 * 1024)
  cat(sprintf("      Saved: %s (%.2f MB)\n", out_file, file_size_mb))
  cat(sprintf(">>> EMPIRICAL SPATIAL MAPS EXPORT COMPLETED IN %.2f SECONDS\n", elapsed))
  cat("==================================================================\n")

  log_info(sprintf("Exported empirical player spatial maps in %.2fs (%.2f MB, %s).",
                   elapsed, file_size_mb, out_file),
           script = .LOG_SCRIPT)

  invisible(out_file)
}

if (sys.nframe() == 0) {
  export_player_spatial_maps()
}
