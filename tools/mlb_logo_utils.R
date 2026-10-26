# ==============================================================================
# tools/mlb_logo_utils.R — MLB Team Logo Fetcher, Caching, and Grid Annotations
# Path: c:/Users/kailo/kayceeslices/front-office/MLB Analytics/tools/mlb_logo_utils.R
#
# Provides utilities to:
#   1. Fetch and locally cache official MLB team logos (120px PNGs from midfield.mlbstatic.com).
#   2. Convert logos to grid rasterGrobs for clean embedding into ggplot2 charts.
#   3. Add logo watermarks / icons to bar charts, scatterplots, and bracket views.
# ==============================================================================

suppressPackageStartupMessages({
  library(png)
  library(grid)
  library(httr2)
  library(dplyr)
})

if (file.exists("config.R")) {
  source("config.R")
  source("logging_utils.R")
} else if (file.exists("../../config.R")) {
  source("../../config.R")
  source("../../logging_utils.R")
} else {
  source(file.path(if (exists("MLB_ROOT_DIR", inherits = FALSE)) MLB_ROOT_DIR else getwd(), "config.R"))
  source(file.path(if (exists("MLB_ROOT_DIR", inherits = FALSE)) MLB_ROOT_DIR else getwd(), "logging_utils.R"))
}
.LOG_SCRIPT <- "mlb_logo_utils.R"

MLB_LOGO_DIR <- file.path(PROJECT_DIR, "cache", "logos")

#' Ensure Logo Directory Exists
ensure_logo_dir <- function() {
  if (!dir.exists(MLB_LOGO_DIR)) {
    dir.create(MLB_LOGO_DIR, recursive = TRUE, showWarnings = FALSE)
  }
  MLB_LOGO_DIR
}

#' Get or Download Team Logo Local File Path
#'
#' @param team_id Numeric/character MLB team ID (e.g. 147 for NYY, 158 for MIL)
#' @return File path to local PNG file, or NULL if download fails
get_team_logo_path <- function(team_id) {
  if (is.na(team_id) || length(team_id) == 0) return(NULL)
  ensure_logo_dir()
  
  local_path <- file.path(MLB_LOGO_DIR, sprintf("%s.png", as.character(team_id)))
  if (file.exists(local_path) && file.info(local_path)$size > 500) {
    return(local_path)
  }

  # Fetch 120px transparent PNG spot logo from MLB Static CDN
  url <- sprintf("https://midfield.mlbstatic.com/v1/team/%s/spots/120", as.character(team_id))
  
  success <- tryCatch({
    resp <- httr2::request(url) |>
      httr2::req_timeout(10) |>
      httr2::req_retry(max_tries = 2) |>
      httr2::req_perform()
    
    if (httr2::resp_status(resp) == 200) {
      writeBin(httr2::resp_body_raw(resp), local_path)
      TRUE
    } else {
      FALSE
    }
  }, error = function(e) {
    FALSE
  })

  if (success && file.exists(local_path)) local_path else NULL
}

#' Cache All Active 30 MLB Team Logos
#'
#' @return Named vector of local file paths
cache_all_mlb_logos <- function() {
  ensure_logo_dir()
  act_teams <- subset(MLB_TEAMS, sport_id == 1 & active == TRUE)
  paths <- character()
  
  for (tid in act_teams$team_id) {
    p <- get_team_logo_path(tid)
    if (!is.null(p)) {
      paths[as.character(tid)] <- p
    }
  }
  log_info(sprintf("Cached %d MLB team logos to %s", length(paths), MLB_LOGO_DIR), script = .LOG_SCRIPT)
  invisible(paths)
}

#' Read Logo as a Grid Raster Object
#'
#' @param team_id Team ID numeric/character
#' @return rasterGrob or NULL
get_team_logo_grob <- function(team_id, x = 0.5, y = 0.5, width = 0.05, height = NULL) {
  path <- get_team_logo_path(team_id)
  if (is.null(path) || !file.exists(path)) return(NULL)
  
  img <- tryCatch(png::readPNG(path), error = function(e) NULL)
  if (is.null(img)) return(NULL)
  
  grid::rasterGrob(img, x = x, y = y, width = width, height = height, default.units = "npc")
}
