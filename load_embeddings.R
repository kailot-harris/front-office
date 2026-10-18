# ==============================================================================
# Embedding Loader & Tidy Joining Helper
# Path: c:/Users/kailo/kayceeslices/NBA Analytics/load_embeddings.R
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
})

source("config.R")

get_team_embeddings <- function() {
  if (!file.exists(CACHE_EMBEDDINGS)) {
    warning("Embeddings CSV does not exist yet. Run team_embeddings.py first.")
    return(NULL)
  }
  
  emb <- read_csv(CACHE_EMBEDDINGS, show_col_types = FALSE) |>
    mutate(team_id = as.integer(team_id))
  return(emb)
}