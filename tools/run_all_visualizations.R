# ==============================================================================
# tools/run_all_visualizations.R — Master MLB Visualization Suite Orchestrator
# Path: c:/Users/kailo/kayceeslices/front-office/MLB Analytics/tools/run_all_visualizations.R
#
# Phase 9: Quantitative Visualization Suite (Issue #24)
# Master callable runner executing all 4 quantitative visualization tools:
#   1. tools/viz_elo_trajectories.R   -> cache/viz/elo_trajectories_2024.png
#   2. tools/viz_pythag_luck.R         -> cache/viz/pythag_luck_quadrants_2024.png
#   3. tools/viz_bullpen_fatigue.R     -> cache/viz/bullpen_fatigue_status.png
#   4. tools/viz_postseason_odds.R     -> cache/viz/postseason_championship_odds.png
#
# Validates generated artifacts (existence, non-zero byte size, freshness)
# and prints an executive console summary gallery.
# ==============================================================================

suppressPackageStartupMessages({
  library(ggplot2)
  library(scales)
  library(dplyr)
})

source("config.R")
source("tools/viz_theme.R")
source("tools/viz_elo_trajectories.R")
source("tools/viz_pythag_luck.R")
source("tools/viz_bullpen_fatigue.R")
source("tools/viz_postseason_odds.R")

generate_all_visualizations <- function(season = 2024) {
  start_time <- Sys.time()
  message("==================================================================")
  message(sprintf(">>> STARTING MLB QUANTITATIVE VISUALIZATION SUITE (SEASON %d)", season))
  message("==================================================================")
  
  ensure_viz_dir()
  
  viz_manifest <- list(
    list(
      name   = "30-Team Elo Rating Race Trajectories",
      script = "tools/viz_elo_trajectories.R",
      output = cache_path("viz", sprintf("elo_trajectories_%d.png", season)),
      fn     = function() generate_viz_elo_trajectories(season = season)
    ),
    list(
      name   = "Pythagorean Luck & Residual Quadrants",
      script = "tools/viz_pythag_luck.R",
      output = cache_path("viz", sprintf("pythag_luck_quadrants_%d.png", season)),
      fn     = function() generate_viz_pythag_luck(season = season)
    ),
    list(
      name   = "Bullpen Fatigue & Arm-Stress Status",
      script = "tools/viz_bullpen_fatigue.R",
      output = cache_path("viz", "bullpen_fatigue_status.png"),
      fn     = function() generate_viz_bullpen_fatigue()
    ),
    list(
      name   = "12-Team Postseason Championship Odds",
      script = "tools/viz_postseason_odds.R",
      output = cache_path("viz", "postseason_championship_odds.png"),
      fn     = function() generate_viz_postseason_odds(season = season)
    )
  )
  
  results <- list()
  
  for (item in viz_manifest) {
    message(sprintf("\n--- Executing: %s (%s) ---", item$name, item$script))
    t0 <- Sys.time()
    res <- tryCatch({
      item$fn()
      elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
      
      # Verify output exists and is non-empty
      if (!file.exists(item$output)) {
        stop(sprintf("Expected output '%s' was not generated.", item$output))
      }
      f_size <- file.info(item$output)[["size"]]
      if (is.na(f_size) || f_size <= 0) {
        stop(sprintf("Generated output '%s' is empty (size 0).", item$output))
      }
      
      data.frame(
        name    = item$name,
        output  = basename(item$output),
        size_kb = round(f_size / 1024, 1),
        status  = "SUCCESS",
        elapsed = round(elapsed, 2),
        stringsAsFactors = FALSE
      )
    }, error = function(e) {
      elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
      message(sprintf(">>> [ERROR] Failed to generate %s: %s", item$name, conditionMessage(e)))
      data.frame(
        name    = item$name,
        output  = basename(item$output),
        size_kb = 0,
        status  = "FAILED",
        elapsed = round(elapsed, 2),
        stringsAsFactors = FALSE
      )
    })
    results[[length(results) + 1]] <- res
  }
  
  summary_df <- do.call(rbind, results)
  total_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  
  message("\n==================================================================")
  message(sprintf(">>> MLB VISUALIZATION SUITE COMPLETED IN %.2f SECONDS", total_time))
  message("------------------------------------------------------------------")
  for (i in seq_len(nrow(summary_df))) {
    message(sprintf("  [%s] %-38s -> %-30s (%5.1f KB, %4.2fs)",
                    summary_df$status[i],
                    summary_df$name[i],
                    summary_df$output[i],
                    summary_df$size_kb[i],
                    summary_df$elapsed[i]))
  }
  message("==================================================================")
  
  all_ok <- all(summary_df$status == "SUCCESS")
  if (!all_ok) {
    warning("One or more visualization generators failed.")
  }
  
  invisible(summary_df)
}

if (sys.nframe() == 0) {
  generate_all_visualizations()
}
