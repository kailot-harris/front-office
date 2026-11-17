# ==============================================================================
# tests/helpers/test_fixtures.R
# Shared fixture-path and data resolution for offline NFL Analytics test suites.
#
# Provides fallback to committed test fixtures under tests/fixtures/ when
# untracked runtime caches under cache/ are absent (e.g. in CI or fresh clones).
#
# Tracked fixtures contain 100% genuine real NFL data extracts (zero synthetic
# rows):
#   - prediction_accuracy_log_fixture.rds (145 backfilled + 123 pregame 2026 rows)
#   - schedules_fixture.rds (842 real rows from 2024, 2025, 2026)
#   - game_details_fixture.rds (16 completed games from 2026 Week 1 with real box scores)
# ==============================================================================

get_prediction_log_path <- function(root_dir = ".") {
  cache_path <- file.path(root_dir, "cache", "prediction_accuracy_log.rds")
  if (file.exists(cache_path)) return(cache_path)
  fixture_path <- file.path(root_dir, "tests", "fixtures", "prediction_accuracy_log_fixture.rds")
  if (file.exists(fixture_path)) return(fixture_path)
  NULL
}

get_schedules_path <- function(root_dir = ".") {
  cache_path <- file.path(root_dir, "cache", "schedules_cache.rds")
  if (file.exists(cache_path)) return(cache_path)
  fixture_path <- file.path(root_dir, "tests", "fixtures", "schedules_fixture.rds")
  if (file.exists(fixture_path)) return(fixture_path)
  NULL
}

get_game_details_fixture <- function(root_dir = ".") {
  fixture_path <- file.path(root_dir, "tests", "fixtures", "game_details_fixture.rds")
  if (file.exists(fixture_path)) {
    return(readRDS(fixture_path))
  }
  NULL
}
