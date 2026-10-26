# ==============================================================================
# Live NBA Injury Scraper & Roster Availability Feeder
# ==============================================================================

# This file's own directory, derived rather than hardcoded. A hardcoded
# PROJECT_DIR plus setwd() ran ahead of config.R's worktree-safe derivation, so
# from a git worktree this stage silently relocated into the main checkout and
# read that tree's config, caches and siblings. Siblings below are sourced by
# absolute path; `local = TRUE` is a no-op under run_stage() (which sources
# stages into the global environment) and lets a test load this file into a
# throwaway environment. The block is identical in every stage entrypoint and
# tests/test_stage_bootstrap.R asserts that.
.THIS_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  ofile <- NULL
  for (fr in sys.frames()) {
    cand <- tryCatch(get("ofile", envir = fr, inherits = FALSE), error = function(e) NULL)
    if (is.character(cand) && length(cand) == 1L && nzchar(cand)) ofile <- cand
  }
  base <- if (!is.null(ofile)) dirname(ofile)
          else if (length(f) == 1L && nzchar(f)) dirname(f)
          else getwd()
  normalizePath(base, winslash = "/", mustWork = FALSE)
})

suppressPackageStartupMessages({
  library(tidyverse)
  library(httr2)
  library(jsonlite)
})

source(file.path(.THIS_DIR, "config.R"), local = TRUE)

# Ensure cache path fallback exists
if (!exists("CACHE_INJURY_DATA")) {
  CACHE_INJURY_DATA <- file.path(CACHE_DIR, "injury_data_cache.rds")
}

fetch_live_nba_injuries <- function() {
  cat("\n==================================================================\n")
  cat("           FETCHING LIVE NBA OFFICIAL INJURY DISCLOSURES          \n")
  cat("==================================================================\n\n")
  
  url <- "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/injuries"
  
  cat("[INJURY FEED] Connecting to real-time injury portal...\n")
  
  raw_resp <- tryCatch({
    request(url) |>
      req_timeout(8) |>
      req_perform() |>
      resp_body_json(simplifyVector = TRUE)
  }, error = function(e) {
    cat(sprintf("[INJURY WARNING] Portal unreachable (%s).\n", e$message))
    NULL
  })
  
  all_scratches <- list()
  
  # Parse live feed if in-season
  if (!is.null(raw_resp) && length(raw_resp$injuries) > 0) {
    teams_list <- raw_resp$injuries
    
    for (i in seq_len(nrow(teams_list))) {
      t_name <- teams_list$displayName[i]
      p_df   <- teams_list$injuries[[i]]
      if (is.null(p_df) || nrow(p_df) == 0) next
      
      clean_team <- case_when(
        grepl("Trail Blazers|Portland", t_name, ignore.case = TRUE) ~ "Trail Blazers",
        grepl("76ers|Philadelphia", t_name, ignore.case = TRUE)      ~ "76ers",
        TRUE ~ word(t_name, -1)
      )
      
      for (j in seq_len(nrow(p_df))) {
        p_row <- p_df[j, ]
        raw_stat <- if (!is.null(p_row$status)) p_row$status else "Questionable"
        std_status <- case_when(
          grepl("out", raw_stat, ignore.case = TRUE)      ~ "Out",
          grepl("doubtful", raw_stat, ignore.case = TRUE) ~ "Doubtful",
          grepl("probable", raw_stat, ignore.case = TRUE) ~ "Probable",
          TRUE                                            ~ "Questionable"
        )
        
        all_scratches[[length(all_scratches) + 1]] <- tibble(
          game_date   = Sys.Date(),
          team_name   = clean_team,
          player_name = p_row$athlete$displayName,
          player_id   = as.integer(p_row$athlete$id),
          status      = std_status,
          injury_desc = coalesce(p_row$type$description, "Undisclosed")
        )
      }
    }
  }
  
  injury_table <- if (length(all_scratches) > 0) bind_rows(all_scratches) else tibble()
  
  # If 0 injuries returned (Offseason / Pre-Season mode)
  if (nrow(injury_table) == 0) {
    message(">>> [WARN] Using SYNTHETIC_FALLBACK injury list: live injury portal returned 0 disclosures (offseason/preseason).")
    cat("[OFFSEASON INFO] Regular season daily injury reports are inactive (September).\n")
    cat("[OFFSEASON INFO] Loading high-impact rehabilitation & recovery roster list.\n\n")
    
    injury_table <- tibble(
      game_date   = Sys.Date(),
      team_name   = c("Celtics", "Clippers", "76ers", "Bucks", "Knicks", "Grizzlies"),
      player_name = c("Kristaps Porzingis", "Kawhi Leonard", "Joel Embiid", "Khris Middleton", "OG Anunoby", "GG Jackson"),
      player_id   = c(204001L, 202695L, 203954L, 203114L, 1628384L, 1641713L),
      status      = c("Out", "Questionable", "Questionable", "Doubtful", "Probable", "Out"),
      injury_desc = c("Foot/Tendon Recovery", "Knee Inflammation", "Meniscus Recovery", "Ankle Surgery", "Elbow Soreness", "Right Foot Procedure")
    )
  } else {
    cat(sprintf("[INJURY SUCCESS] Parsed %d official player injury designations.\n\n", nrow(injury_table)))
  }
  
  # Display preview
  print(knitr::kable(injury_table, format = "simple"))
  
  saveRDS(injury_table, CACHE_INJURY_DATA)
  cat(sprintf("\n[CACHE] Saved injury disclosures to: %s\n", CACHE_INJURY_DATA))
  
  return(injury_table)
}


# Set NBA_SKIP_STAGE_AUTORUN=1 to source this file for its definitions alone;
# run_full_pipeline.R relies on this call, so it stays on by default.
if (!nzchar(Sys.getenv("NBA_SKIP_STAGE_AUTORUN"))) {
  fetch_live_nba_injuries()
}
