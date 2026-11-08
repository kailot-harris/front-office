# ==============================================================================
# offseason_fixtures.R
# Shared fixture-path resolution for the off-season monitor's test suite.
#
# WHY THIS EXISTS
# Four test sites each hardcoded the same *runtime* path for the frozen real
# ESPN league-wire capture they assert against:
#
#   cache/raw_ingest_archive/20261106/league_wire_espn_114245.json
#
#   - tests/unit/test_offseason_dag_end_to_end.R (Property 1, Property 5)
#   - tests/unit/test_offseason_ingestion.R      (Criterion 2)
#   - tools/offseason/test_regex_extraction.R    (Criterion 1)
#
# Everything under cache/ is gitignored runtime output, and that directory name
# carries the ingest date, so the file exists only on a machine that happened to
# run the 2026-11-06 ingest. In a fresh clone, a fresh git worktree, or CI, all
# four tests failed at their opening `expect_true(file.exists(...))` — not
# because anything was broken, but because a test fixture was being sourced from
# untracked runtime state. Found while adding the Media Sentiment Pulse (#156),
# whose worktree could not run the DAG end-to-end test for exactly this reason.
#
# The capture is now promoted to a tracked fixture, byte-identical to the
# archived original (sha256 c75a8c33c6497dc992bb2ff6ba7ac932d5c1fef97e0cfe4cb58a668b02c23dab),
# which is the same treatment #159 gave data/fixtures/wire_items_sample.json.
# Byte-stability matters: these tests assert exact values off this payload —
# 25 transaction rows, pageCount 5, first row IND / "Kelly Krauskopf" /
# 2026-10-23T07:00Z, and >= 35 extracted deltas. Re-capturing the endpoint today
# would return different bytes and break them, so this file must never be
# "refreshed" in place; a new capture belongs in a new fixture under its own name.
#
# Not sourced by any pipeline code — test-support only.
# ==============================================================================

# Canonical tracked location of the frozen 2026-11-06 ESPN transactions payload.
OFFSEASON_LEAGUE_WIRE_RAW_FIXTURE <- file.path(
  "data", "fixtures", "league_wire_espn_20261106_raw.json"
)

#' Resolve the frozen 2026-11-06 ESPN league-wire capture
#'
#' Prefers the tracked fixture, so the result is identical in a fresh clone, a
#' worktree, and CI. Falls back to the gitignored runtime archive the fixture was
#' promoted from, purely so a machine that still carries the original (and may
#' have it checked out at an older revision) keeps working.
#'
#' When neither exists, returns the canonical tracked path rather than NULL, so
#' the caller's own `expect_true(file.exists(...))` reports the path a reader
#' should go looking for instead of failing on a NULL.
#'
#' @return character(1) path, relative to the project root.
offseason_league_wire_raw_fixture <- function() {
  if (file.exists(OFFSEASON_LEAGUE_WIRE_RAW_FIXTURE)) {
    return(OFFSEASON_LEAGUE_WIRE_RAW_FIXTURE)
  }

  legacy_archive <- file.path(
    "cache", "raw_ingest_archive", "20261106", "league_wire_espn_114245.json"
  )
  if (file.exists(legacy_archive)) {
    return(legacy_archive)
  }

  OFFSEASON_LEAGUE_WIRE_RAW_FIXTURE
}
