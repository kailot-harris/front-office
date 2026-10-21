# ==============================================================================
# Live NBA Roster Synchronizer (Automated Offseason Trade Tracker)
# Path: c:/Users/kailo/kayceeslices/front-office/NBA Analytics/sync_rosters.R
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/front-office/NBA Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(tidyverse)
  library(httr2)
  library(jsonlite)
})

source("config.R")

sync_active_rosters <- function() {
  cat("\n==================================================================\n")
  cat("        FETCHING LIVE ACTIVE ROSTERS & OFFSEASON TRADES           \n")
  cat("==================================================================\n\n")
  
  # 1. Fetch All 30 NBA Teams and IDs
  teams_url <- "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/teams"
  
  cat("[ROSTER SYNC] Fetching team registry from live CDN...\n")
  teams_resp <- tryCatch({
    request(teams_url) |>
      req_timeout(6) |>
      req_perform() |>
      resp_body_json(simplifyVector = TRUE)
  }, error = function(e) {
    stop("Failed to reach ESPN team endpoint: ", e$message)
  })
  
  teams_data <- teams_resp$sports$leagues[[1]]$teams[[1]]$team
  
  roster_list <- list()
  
  cat(sprintf("[ROSTER SYNC] Querying active rosters for all %d NBA franchises...\n", nrow(teams_data)))
  
  for (i in seq_len(nrow(teams_data))) {
    team_id   <- teams_data$id[i]
    team_name <- teams_data$name[i]
    
    # Standardize Franchise Name
    clean_team <- case_when(
      grepl("Trail Blazers|Portland", team_name, ignore.case = TRUE) ~ "Trail Blazers",
      grepl("76ers|Philadelphia", team_name, ignore.case = TRUE)      ~ "76ers",
      TRUE ~ word(team_name, -1)
    )
    
    # Roster endpoint for this specific team
    roster_url <- sprintf("https://site.api.espn.com/apis/site/v2/sports/basketball/nba/teams/%s/roster", team_id)
    
    roster_resp <- tryCatch({
      request(roster_url) |>
        req_timeout(4) |>
        req_perform() |>
        resp_body_json(simplifyVector = TRUE)
    }, error = function(e) NULL)
    
    if (is.null(roster_resp) || is.null(roster_resp$athletes)) next
    
    athletes <- roster_resp$athletes
    
    roster_list[[i]] <- tibble(
      team_name   = clean_team,
      team_id     = as.integer(team_id),
      player_id   = as.integer(athletes$id),
      player_name = athletes$displayName,
      position    = athletes$position$abbreviation,
      jersey      = athletes$jersey
    )
    
    Sys.sleep(0.05) # Polite micro-delay
  }
  
  active_rosters <- bind_rows(roster_list)
  
  cat(sprintf("\n[SUCCESS] Synchronized %d active NBA players across all 30 rosters.\n\n", nrow(active_rosters)))
  
  # Preview latest roster movements
  cat("Preview of live rosters (sample teams):\n")
  print(head(active_rosters |> select(team_name, player_name, position, jersey), 12))
  
  out_path <- file.path(CACHE_DIR, "active_rosters_cache.rds")
  saveRDS(active_rosters, out_path)
  cat(sprintf("\n[CACHE] Saved active rosters to: %s\n", out_path))
  
  return(active_rosters)
}

sync_active_rosters()