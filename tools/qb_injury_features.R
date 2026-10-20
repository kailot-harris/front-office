# ==============================================================================
# QB-Injury / Backup-Starter Feature Builder (Phase 1, model-quality remediation)
# Path: c:/Users/kailo/kayceeslices/front-office/nfl analytics/tools/qb_injury_features.R
#
# First player-level data join in this repo (CLAUDE.md flags this as the highest
# join-mismatch risk area - four competing NFL player-ID schemes exist). VERIFIED
# LIVE 2026-09-17: nflreadr::load_depth_charts() is gsis_id-keyed (same primary key
# CACHE_ROSTERS/CACHE_INJURY_DATA already use), and is available back to season 2003
# (checked: load_depth_charts(seasons=2003) returns real rows), unlike
# nflreadr::load_injuries() (2009+ only, checked live: seasons < 2009 error
# "seasons >= 2009 are not all TRUE"). Since this feature is built ENTIRELY from
# load_depth_charts() (no injuries-cache join needed - see methodology below), no
# nflreadr::load_ff_playerids() crosswalk step is required here: there is no
# ID-scheme mixing to reconcile, which is itself a verified conclusion (not a
# skipped check) per CLAUDE.md's instruction to add a match-rate assertion at any
# join point that DOES mix schemes.
#
# METHODOLOGY: rather than relying on injury-report text (report_status is often a
# practice-participation label, not a clean game-status - see injury_scraper.R's
# coalesce(report_status, practice_status) - and only covers 2009+), this defines
# "backup QB started" directly and only from real depth-chart data: for team T in
# week W of season S, take the depth_team=="1" QB as that week's ACTUAL starter, and
# compare it to T's "primary QB as of week W" - the mode starter among T's OWN
# depth-chart rows strictly BEFORE week W this season (falling back to ALL of
# season S-1 if week W is T's first game of the season, e.g. week 1). Both windows
# are strictly in the past relative to week W - no lookahead. A mismatch means a
# real backup (for any reason - injury, benching, bye-adjacent rest) started that
# week; this is the decision-relevant signal for a rating adjustment regardless of
# the specific cause, and it is available pre-game in real time (depth charts are
# published before kickoff) so it is usable for live inference, not just backtesting.
#
# No top-level side effects beyond function definitions - safe to source() from any
# script (derive_qb_injury_penalty.R, model_backtest_harness.R, and eventually
# team_ratings_engine.R's live QB-adjustment step all reuse these two functions
# rather than each re-deriving their own version).
# ==============================================================================

# ------------------------------------------------------------------------------------------
# get_qb_starter_table(): one row per (season, week, team) = that week's ACTUAL depth_team=="1"
# QB, regular season only (game_type == "REG" - matches this repo's other season-games
# filtering convention). club_code is nflreadr's depth-chart team-code column; verified live
# 2026-09-17 to use the same abbreviations as config.R's NFL_TEAMS.
# ------------------------------------------------------------------------------------------
get_qb_starter_table <- function(seasons) {
  # as.data.frame() forces materialization out of whatever backend object nflreadr/duckdb
  # returns (observed live: a lazy/data.table-flavored object that made dplyr::filter()'s NSE
  # resolve `position` as a missing standalone variable instead of a column reference when
  # called from inside a source()'d function - reproducible from team_ratings_engine.R's live
  # call path, not from a bare top-level script). Fully-qualified dplyr:: calls are defensive
  # against any filter()/arrange() masking from other packages this repo's stage scripts load
  # (e.g. market_odds_engine.R's library(tidyr)/library(stringr)).
  dc <- as.data.frame(nflreadr::load_depth_charts(seasons = seasons))
  dc |>
    dplyr::filter(position == "QB", depth_team == "1", game_type == "REG") |>
    dplyr::distinct(season, week, club_code, .keep_all = TRUE) |>
    dplyr::transmute(season, week, team = club_code, gsis_id) |>
    dplyr::arrange(team, season, week)
}

# ------------------------------------------------------------------------------------------
# compute_qb_backup_flags(): adds primary_qb_asof (mode of the team's own starts strictly
# before this week, falling back to the entirety of the prior season) and qb_backup_started
# (this week's actual starter != primary_qb_asof) to a get_qb_starter_table() output.
# Deliberately a plain per-team loop, not a vectorized window function - the data is small
# (~32 teams x ~18 weeks x ~23 seasons, a few thousand rows) and the loop keeps the "strictly
# before this row" windowing unambiguous and easy to audit for lookahead bugs, which matters
# more here than micro-performance (see this repo's no-lookahead-audit convention).
# ------------------------------------------------------------------------------------------
compute_qb_backup_flags <- function(starter_tbl) {
  teams <- unique(starter_tbl$team)
  out <- vector("list", length(teams))

  for (ti in seq_along(teams)) {
    t <- teams[ti]
    sub <- starter_tbl |> dplyr::filter(team == t) |> dplyr::arrange(season, week)
    n <- nrow(sub)
    primary <- character(n)
    backup_started <- rep(NA, n)

    for (i in seq_len(n)) {
      s <- sub$season[i]; w <- sub$week[i]
      window <- sub[sub$season == s & sub$week < w, ]
      if (nrow(window) == 0) window <- sub[sub$season == s - 1L, ]

      if (nrow(window) == 0 || is.na(sub$gsis_id[i])) {
        primary[i] <- NA_character_
        backup_started[i] <- NA
      } else {
        tab <- sort(table(window$gsis_id), decreasing = TRUE)
        primary[i] <- names(tab)[1]
        backup_started[i] <- sub$gsis_id[i] != primary[i]
      }
    }

    sub$primary_qb_asof <- primary
    sub$qb_backup_started <- backup_started
    out[[ti]] <- sub
  }

  bind_rows(out)
}
