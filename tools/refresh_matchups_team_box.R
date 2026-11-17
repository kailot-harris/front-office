# ==============================================================================
# tools/refresh_matchups_team_box.R  (issue #171)
# Refreshes cache/matchups_team_box_<season>.rds from hoopR BEFORE the XGBoost
# TreeSHAP stage (8.6). xgboost_shap_engine.R derives each game's prior-games
# counts and rolling features from this cache, but until now only
# build_matchups_dataset.R (stage 9) refreshed it, so SHAP always ran on the
# previous run's box scores -- one day stale on the first run of each day.
#
# Semantics match build_matchups_dataset.R's fetch_or_cache(): a successful, non-
# empty pull overwrites the cache; a failed or empty pull leaves the existing
# cache untouched (warn, never throw). Stage 9 still pulls again and so stays
# self-sufficient when run alone.
# ==============================================================================

refresh_matchups_team_box <- function(season = NULL, path = NULL, pull = NULL) {
  if (is.null(season)) season <- MATCHUPS_HOOPR_SEASON
  if (is.null(path))   path   <- CACHE_MATCHUPS_TEAM_BOX(season)
  if (is.null(pull))   pull   <- function() hoopR::load_nba_team_box(seasons = season)
  got <- tryCatch(as.data.frame(pull()), error = function(e) {
    cat(sprintf(">>> [WARN] refresh_matchups_team_box: live pull failed: %s\n", conditionMessage(e)))
    NULL
  })
  if (!is.null(got) && nrow(got) > 0) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    saveRDS(got, path)
    cat(sprintf(">>> refresh_matchups_team_box: cached %d rows to %s\n", nrow(got), basename(path)))
    return(invisible("refreshed"))
  }
  if (!is.null(got)) {
    cat(">>> [WARN] refresh_matchups_team_box: live pull returned 0 rows; keeping existing cache.\n")
  }
  invisible(if (file.exists(path)) "kept" else "missing")
}

run_refresh_matchups_team_box <- function() refresh_matchups_team_box()
