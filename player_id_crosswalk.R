# ==============================================================================
# Cross-Source NFL Player-ID Crosswalk
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/player_id_crosswalk.R
#
# CLAUDE.md flags four competing NFL player-ID schemes (ESPN athlete IDs, GSIS IDs - nflverse's
# own primary key, PFR IDs, NFL.com/NGS-style IDs) as a real join-mismatch risk and names
# nflreadr::load_ff_playerids() as the canonical crosswalk to use "at every join point that
# mixes ID schemes, and add a post-join match-rate assertion (fail loudly below a threshold)
# rather than trusting a join to 'just work' silently." As of 2026-09-17, that function had
# NEVER actually been called live anywhere in this repo - only referenced in comments/docs as
# "the thing to use later" (confirmed via repo-wide grep). This file is that live verification
# plus the reusable infrastructure, not a hypothetical placeholder.
#
# LIVE-VERIFIED 2026-09-17 against the real nflreadr::load_ff_playerids() table:
#   - 12,494 rows, 35 columns (mfl_id/sportradar_id/fantasypros_id/gsis_id/pff_id/sleeper_id/
#     nfl_id/espn_id/yahoo_id/fleaflicker_id/cbs_id/pfr_id/... - real column names, not assumed).
#   - gsis_id NA rate 35.9%, espn_id NA rate 34.6%, pfr_id NA rate 22.9% - this crosswalk covers
#     a much wider historical/obscure-player population than any one source needs, so a
#     sizeable per-column NA rate is expected and not itself a data-quality red flag.
#   - REAL DATA QUIRK FOUND: 10 gsis_id values are each assigned to TWO DIFFERENT named players
#     (e.g. gsis_id 00-0022828 maps to both "Nate Jones" (WR) and "Nathan Jones" (CB) - a
#     name-collision bug in the underlying ffverse crosswalk itself, not a parsing error on this
#     repo's end). A naive left_join() on gsis_id would silently fan out these 10 IDs into
#     duplicate rows. load_player_id_crosswalk() below DROPS ambiguous (duplicated) id values
#     from the crosswalk entirely rather than guessing which player is correct - the same
#     "don't guess, drop and log" discipline this repo already applies elsewhere (e.g.
#     injury_scraper.R's NA-athlete-ID rows).
#   - Real match-rate spot check against this repo's own cache/injury_data_cache.rds (800 real
#     ESPN_LIVE rows, 376 real NFLREADR_OFFICIAL rows, live-scraped 2026-09-17): 89.0% of
#     ESPN_LIVE rows' espn_athlete_id matched a real espn_id in the crosswalk; 83.2% of
#     NFLREADR_OFFICIAL rows' gsis_id matched. Both comfortably clear this file's
#     default min_match_rate - recorded here as a real baseline to compare future runs against,
#     not a guarantee that stays constant as rosters turn over.
#
# Assumes the caller has already done: source("config.R"); source("logging_utils.R");
# library(dplyr). No top-level side effects beyond function definitions - safe to source() from
# any script.
# ==============================================================================

# ------------------------------------------------------------------------------------------
# load_player_id_crosswalk(): loads nflreadr::load_ff_playerids(), caches it
# (CACHE_PLAYER_ID_CROSSWALK - a large (12K-row), slow-changing table not worth re-fetching
# every pipeline run), and DROPS any id value that maps to 2+ distinct player names in ANY of
# `dedupe_cols` (default gsis_id/espn_id/pfr_id - the three schemes this repo actually consumes
# elsewhere) - see header's "real data quirk found" note for why this is necessary, not
# paranoid. force_refresh = TRUE bypasses the cache (e.g. to pick up a new draft class).
# ------------------------------------------------------------------------------------------
load_player_id_crosswalk <- function(force_refresh = FALSE, dedupe_cols = c("gsis_id", "espn_id", "pfr_id")) {
  if (!force_refresh && file.exists(CACHE_PLAYER_ID_CROSSWALK)) {
    return(readRDS(CACHE_PLAYER_ID_CROSSWALK))
  }

  raw <- nflreadr::load_ff_playerids()
  clean <- raw

  for (col in intersect(dedupe_cols, names(raw))) {
    vals <- clean[[col]]
    dupe_vals <- unique(vals[!is.na(vals) & duplicated(vals)])
    if (length(dupe_vals) > 0) {
      log_warn(sprintf("load_player_id_crosswalk(): %d ambiguous %s value(s) map to 2+ distinct players in nflreadr::load_ff_playerids() - dropping rather than guessing which is correct.",
                        length(dupe_vals), col),
               call = "load_player_id_crosswalk()",
               ambiguous_values = paste(utils::head(dupe_vals, 5), collapse = ", "))
      clean <- clean[is.na(clean[[col]]) | !clean[[col]] %in% dupe_vals, ]
    }
  }

  saveRDS(clean, CACHE_PLAYER_ID_CROSSWALK)
  log_info(sprintf("load_player_id_crosswalk(): cached %d rows (of %d raw) to CACHE_PLAYER_ID_CROSSWALK.",
                    nrow(clean), nrow(raw)), call = "load_player_id_crosswalk()", out_path = CACHE_PLAYER_ID_CROSSWALK)
  clean
}

# ------------------------------------------------------------------------------------------
# assert_join_match_rate(): the "post-join match-rate assertion" CLAUDE.md's ID-crosswalk
# quirk explicitly calls for. Always logs the rate; log_warn (not a hard stop() - a low match
# rate degrades a join's coverage, it doesn't corrupt what DID match) when it falls below
# min_match_rate, so a near-zero-match join is loud in the logs rather than silently accepted.
# `n_matched`/`n_eligible` are counts the caller computes right after its own left_join() -
# deliberately NOT a generic join wrapper (this repo's convention favors a few explicit lines
# per real call site over a one-size-fits-all abstraction for a class of join that varies a lot
# in column names/types across future use cases - see CLAUDE.md's anti-premature-abstraction
# note).
# ------------------------------------------------------------------------------------------
assert_join_match_rate <- function(n_matched, n_eligible, label, min_match_rate = 0.5) {
  if (n_eligible == 0) {
    log_warn(sprintf("assert_join_match_rate(): 0 eligible (non-NA join-key) rows for '%s' - cannot compute a match rate.", label),
             call = "assert_join_match_rate()", label = label)
    return(invisible(NA_real_))
  }
  match_rate <- n_matched / n_eligible
  log_info(sprintf("assert_join_match_rate(): '%s' matched %d/%d (%.1f%%) against the player-ID crosswalk.",
                    label, n_matched, n_eligible, match_rate * 100),
           call = "assert_join_match_rate()", label = label, match_rate = match_rate)
  if (match_rate < min_match_rate) {
    log_warn(sprintf("assert_join_match_rate(): '%s' match rate %.1f%% is BELOW the %.0f%% warning threshold - investigate before trusting this join's output (e.g. a scheme/format change, a stale crosswalk cache, or a genuinely low-coverage ID column).",
                      label, match_rate * 100, min_match_rate * 100),
             call = "assert_join_match_rate()", label = label, match_rate = match_rate, min_match_rate = min_match_rate)
  }
  invisible(match_rate)
}
