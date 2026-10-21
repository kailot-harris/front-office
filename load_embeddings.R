# ==============================================================================
# Embedding Loader & Tidy Joining Helper
# Path: c:/Users/kailo/kayceeslices/front-office/NBA Analytics/load_embeddings.R
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
})

if (file.exists("config.R")) source("config.R")

# ------------------------------------------------------------------------------
# Standard NBA Team Mapping Fallback (30 Teams)
# ------------------------------------------------------------------------------
get_nba_team_metadata <- function() {
  # First try CACHE_TEAM_BOX (box_scores_cache.rds)
  if (exists("CACHE_TEAM_BOX") && file.exists(CACHE_TEAM_BOX)) {
    tryCatch({
      b <- readRDS(CACHE_TEAM_BOX)
      sub <- unique(data.frame(
        team_id = as.integer(b[["team_id"]]),
        team_name = as.character(b[["team_name"]]),
        team_abbreviation = as.character(b[["team_abbreviation"]]),
        stringsAsFactors = FALSE
      ))
      if (nrow(sub) > 0) return(sub)
    }, error = function(e) NULL)
  }
  
  # Next try CACHE_ACTIVE_ROSTERS (active_rosters_cache.rds)
  if (exists("CACHE_ACTIVE_ROSTERS") && file.exists(CACHE_ACTIVE_ROSTERS)) {
    tryCatch({
      ar <- readRDS(CACHE_ACTIVE_ROSTERS)
      sub <- unique(data.frame(
        team_id = as.integer(ar[["team_id"]]),
        team_name = as.character(ar[["team_name"]]),
        stringsAsFactors = FALSE
      ))
      if (nrow(sub) > 0) {
        # Fallback abbreviations if not present
        return(sub)
      }
    }, error = function(e) NULL)
  }
  
  # Standard 30 NBA Teams fallback
  tibble::tribble(
    ~team_id, ~team_name, ~team_abbreviation,
    1L,  "Hawks",         "ATL",
    2L,  "Celtics",       "BOS",
    3L,  "Pelicans",      "NO",
    4L,  "Bulls",         "CHI",
    5L,  "Cavaliers",     "CLE",
    6L,  "Mavericks",     "DAL",
    7L,  "Nuggets",       "DEN",
    8L,  "Pistons",       "DET",
    9L,  "Warriors",      "GS",
    10L, "Rockets",       "HOU",
    11L, "Pacers",        "IND",
    12L, "Clippers",      "LAC",
    13L, "Lakers",        "LAL",
    14L, "Heat",          "MIA",
    15L, "Bucks",         "MIL",
    16L, "Timberwolves",  "MIN",
    17L, "Nets",          "BKN",
    18L, "Knicks",        "NY",
    19L, "Magic",         "ORL",
    20L, "76ers",         "PHI",
    21L, "Suns",          "PHX",
    22L, "Trail Blazers", "POR",
    23L, "Kings",         "SAC",
    24L, "Spurs",         "SA",
    25L, "Thunder",       "OKC",
    26L, "Jazz",          "UTAH",
    27L, "Wizards",       "WSH",
    28L, "Raptors",       "TOR",
    29L, "Grizzlies",     "MEM",
    30L, "Hornets",       "CHA"
  )
}

# ------------------------------------------------------------------------------
# Get Team Embeddings (joined with metadata)
# ------------------------------------------------------------------------------
get_team_embeddings <- function(nba_only = TRUE) {
  emb_path <- if (exists("CACHE_EMBEDDINGS")) CACHE_EMBEDDINGS else "team_embeddings.csv"
  if (!file.exists(emb_path)) {
    warning("Embeddings CSV does not exist yet. Run team_embeddings.py first.")
    return(NULL)
  }
  
  emb <- read_csv(emb_path, show_col_types = FALSE) |>
    mutate(team_id = as.integer(team_id))
  
  meta <- get_nba_team_metadata()
  if (!is.null(meta) && nrow(meta) > 0) {
    emb <- emb |>
      left_join(meta, by = "team_id") |>
      mutate(
        team_name = coalesce(team_name, paste("Team", team_id)),
        team_abbreviation = coalesce(team_abbreviation, as.character(team_id))
      ) |>
      relocate(team_id, team_name, team_abbreviation)
  } else {
    emb <- emb |>
      mutate(
        team_name = paste("Team", team_id),
        team_abbreviation = as.character(team_id)
      ) |>
      relocate(team_id, team_name, team_abbreviation)
  }
  
  if (nba_only) {
    emb <- emb |> filter(team_id <= 30)
  }
  
  return(emb)
}

# ------------------------------------------------------------------------------
# Compute 2D PCA Projection of 16-D Team Latent Vectors
# ------------------------------------------------------------------------------
get_embeddings_pca <- function(nba_only = TRUE) {
  emb <- get_team_embeddings(nba_only = nba_only)
  if (is.null(emb) || nrow(emb) < 3) return(NULL)
  
  emb_cols <- grep("^emb_", names(emb), value = TRUE)
  if (length(emb_cols) < 2) return(NULL)
  
  mat <- as.matrix(emb[, emb_cols])
  
  # Center and scale for PCA
  pca <- prcomp(mat, scale. = TRUE, center = TRUE)
  var_explained <- (pca$sdev^2) / sum(pca$sdev^2)
  
  pca_df <- emb |>
    select(team_id, team_name, team_abbreviation) |>
    mutate(
      PC1 = pca$x[, 1],
      PC2 = pca$x[, 2]
    )
  
  list(
    data = pca_df,
    pca_object = pca,
    var_explained = var_explained,
    pc1_pct = round(var_explained[1] * 100, 1),
    pc2_pct = round(var_explained[2] * 100, 1)
  )
}

# ------------------------------------------------------------------------------
# Get Team Similarity Matrix labeled with Team Abbreviations
# ------------------------------------------------------------------------------
get_team_similarity_matrix <- function(nba_only = TRUE) {
  sim_path <- if (exists("CACHE_SIMILARITY")) CACHE_SIMILARITY else "team_similarity_matrix.csv"
  if (!file.exists(sim_path)) {
    warning("Similarity matrix CSV does not exist yet. Run team_embeddings.py first.")
    return(NULL)
  }
  
  sim <- read.csv(sim_path, row.names = 1, check.names = FALSE)
  
  meta <- get_nba_team_metadata()
  if (!is.null(meta) && nrow(meta) > 0) {
    id_char <- as.character(meta$team_id)
    abbr_char <- as.character(meta$team_abbreviation)
    map <- setNames(abbr_char, id_char)
    
    r_names <- ifelse(rownames(sim) %in% names(map), map[rownames(sim)], rownames(sim))
    c_names <- ifelse(colnames(sim) %in% names(map), map[colnames(sim)], colnames(sim))
    rownames(sim) <- r_names
    colnames(sim) <- c_names
  }
  
  if (nba_only) {
    # Keep 30 official NBA teams if present
    meta30 <- get_nba_team_metadata() |> filter(team_id <= 30)
    valid_abbrs <- unique(meta30$team_abbreviation)
    keep_r <- intersect(rownames(sim), valid_abbrs)
    keep_c <- intersect(colnames(sim), valid_abbrs)
    if (length(keep_r) > 0 && length(keep_c) > 0) {
      sim <- sim[keep_r, keep_c]
    }
  }
  
  return(sim)
}