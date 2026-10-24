# ==============================================================================
# build_playoff_bracket_2026.R
#
# GitHub issue #92. Builds CACHE_PLAYOFF_BRACKET_CURRENT
# (cache/playoff_bracket_<CURRENT_SEASON>.rds): the current season's playoff
# bracket with, for every series, the resolved result AND the model prediction
# for that series side by side. Consumed by export_web_json.R, which ships it to
# web/public/data/playoff_bracket_2026.json for the Next.js /bracket-2026 route.
#
# WHY THIS IS A SEPARATE SCRIPT rather than more code inside export_web_json.R:
# export_web_json.R is an exporter. Every other payload it builds is a
# readRDS -> reshape -> write_json pass over caches other scripts produced, and
# it sources no modeling engine. Deriving this artifact instead needs the DP
# series-length model (tools/series_length_predictor.R, which in turn pulls in
# playoff_simulator.R) plus the round-inference helper from
# tools/generate_historical_season_snapshots.R. Putting that behind the exporter
# would make a JSON writer depend on two modeling engines, and would recompute
# the bracket on every export. Keeping it here matches the repo's existing
# build_*_dataset.R convention (one script produces one cache, the exporter only
# reshapes it) and gives the artifact a single owner.
#
# ---- SCHEMA ----
# A tibble, one row per series, carrying the SAME fields export_web_json.R's
# `historicalBrackets` payload uses -- team_a/team_b/games_played/series_length/
# winner/games/round -- so the new page and the existing archive section speak
# one shape, plus a `prediction` list-column.
#
# ---- THE TWO HALVES HAVE DIFFERENT PROVENANCE, DELIBERATELY ----
# Resolved half: derived from CACHE_TEAM_BOX (season_type == 3), never
# hardcoded, with round labels from assign_bracket_rounds().
#
# Prediction half, per round:
#   * Round 1 -- RECONSTRUCTED NOW. There is no archived Round 1 forecast; the
#     repo has never stored one. It is retrodicted through
#     series_length_distribution() from net ratings computed over
#     `season_type == 2` games only, so the playoff games being predicted do not
#     feed their own prediction. It is a reconstruction, not a forecast, and is
#     labeled as one.
#   * Semifinals -- ARCHIVED FORECAST, copied VERBATIM out of
#     cache/series_length_predictions.rds (generated 2026-10-04, before either
#     series was played). These are NEVER recomputed. They were produced by an
#     older code path whose net ratings pooled regular-season and Round 1
#     playoff games together, so they are not methodologically identical to the
#     Round 1 reconstruction above -- and that is the point. They are the only
#     record in this repo of what the model actually said about a series ahead of
#     time, and recomputing them for internal consistency would destroy that
#     record rather than clean it up. Each round's label states its own basis.
#   * Finals -- no prediction block content. Tracked separately (issue #94); the
#     series row is present with its resolved games so far, and its prediction
#     block is marked unavailable rather than filled with a fabricated number.
#
# Because the two rounds' ratings bases differ, NOTHING here describes either
# round as a clean held-out test. The `ratingBasis` string on each prediction
# says exactly which games fed it.
#
# ---- FAIL-SAFE ----
# Every cache read is file.exists()-guarded. A missing or empty box-score cache
# yields a zero-row artifact (written, so downstream readers find a real file),
# which the web route renders as an empty state. A missing prediction archive
# downgrades the affected rounds to prediction unavailable. Nothing here
# hard-crashes the pipeline.
# ==============================================================================

if (!exists("CACHE_TEAM_BOX") || !exists("CACHE_PLAYOFF_BRACKET_CURRENT")) source("config.R")
if (!exists("filter_real_franchises")) source("daily_ingest.R")

# Source tools/series_length_predictor.R as a LIBRARY. Without this env var it
# auto-runs run_series_length_demo() on source, which re-simulates every series
# and targets the archived forecast file this script reads.
Sys.setenv(WNBA_SERIES_LENGTH_NO_AUTORUN = "1")
if (!exists("series_length_distribution")) source("tools/series_length_predictor.R")

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
})

.LOG_SCRIPT <- "build_playoff_bracket_2026.R"
message(">>> [BRACKET 2026] Building current-season playoff bracket (results + predictions)...")

# Archived pre-game forecasts. Read-only; this script never writes this file.
ARCHIVED_PREDICTIONS_PATH <- file.path(CACHE_DIR, "series_length_predictions.rds")

# Round label -> series format. This is the WNBA's postseason structure (first
# round best-of-3, semifinals best-of-5, finals best-of-7), not a modeling
# constant: the format's actual parameters (home_flags, win_threshold, label) are
# read from playoff_simulator.R's PLAYOFF_FORMATS and never restated here.
# Validated against the data below, rather than trusted.
ROUND_FORMATS <- c("Round 1" = "bo3", "Semifinals" = "bo5", "Finals" = "bo7")

# ------------------------------------------------------------------------------
# assign_bracket_rounds(), reused rather than reimplemented.
#
# tools/generate_historical_season_snapshots.R cannot simply be source()d: it
# auto-runs generate_historical_season_snapshots() at its last line, which
# regenerates every 2019-2025 standings / bracket / RAPM cache (slow, and writes
# files that are nothing to do with this artifact). So only that one function
# definition is parsed out and evaluated. Verified against 2026: the function
# returns 4 "Round 1" + 2 "Semifinals" + 1 "Finals" without aborting (it does
# abort on 2019-2021's bye-based brackets -- issue #89 -- which is why this is
# checked rather than assumed).
# ------------------------------------------------------------------------------
load_assign_bracket_rounds <- function(
  path = file.path("tools", "generate_historical_season_snapshots.R")
) {
  if (exists("assign_bracket_rounds")) return(get("assign_bracket_rounds"))
  if (!file.exists(path)) {
    warning(sprintf(">>> [BRACKET 2026] %s not found — cannot infer round labels.", path))
    return(NULL)
  }
  fn <- NULL
  for (e in parse(path)) {
    if (is.call(e) && identical(as.character(e[[1]]), "<-") &&
        identical(as.character(e[[2]]), "assign_bracket_rounds")) {
      fn <- eval(e, envir = new.env(parent = globalenv()))
    }
  }
  if (is.null(fn)) {
    warning(sprintf(">>> [BRACKET 2026] assign_bracket_rounds() not found in %s.", path))
  }
  fn
}

# ------------------------------------------------------------------------------
# Resolved half: one row per series, from season_type == 3 box scores.
# Pairing logic mirrors tools/generate_historical_season_snapshots.R's: a series
# is every postseason game between an unordered pair of teams in that season.
# ------------------------------------------------------------------------------
build_resolved_series <- function(box, season_yr = CURRENT_SEASON) {
  post <- box %>% filter(season == season_yr, season_type == 3L)
  if (nrow(post) == 0) {
    message(sprintf(">>> [BRACKET 2026] No %d postseason (season_type == 3) rows — empty bracket.", season_yr))
    return(tibble())
  }

  game_level <- post %>%
    group_by(game_id) %>%
    summarise(
      game_date  = dplyr::first(game_date),
      team_a     = dplyr::first(team_display_name),
      team_a_abb = dplyr::first(team_abbreviation),
      score_a    = dplyr::first(team_score),
      team_b     = dplyr::first(opponent_team_display_name),
      team_b_abb = dplyr::first(opponent_team_abbreviation),
      score_b    = dplyr::first(opponent_team_score),
      .groups = "drop"
    ) %>%
    mutate(pair_key = paste(pmin(team_a_abb, team_b_abb), pmax(team_a_abb, team_b_abb)))

  bracket <- game_level %>%
    group_by(pair_key) %>%
    group_modify(function(games, key) {
      games <- games %>% arrange(game_date)
      team_x <- games$team_a[1]; team_x_abb <- games$team_a_abb[1]
      team_y <- games$team_b[1]; team_y_abb <- games$team_b_abb[1]

      wins_x <- sum(
        (games$team_a_abb == team_x_abb & games$score_a > games$score_b) |
        (games$team_b_abb == team_x_abb & games$score_b > games$score_a)
      )
      wins_y <- nrow(games) - wins_x

      game_log <- lapply(seq_len(nrow(games)), function(i) {
        list(game_date = games$game_date[i],
             team_a = games$team_a[i], score_a = games$score_a[i],
             team_b = games$team_b[i], score_b = games$score_b[i])
      })

      tibble(
        team_a = team_x, team_a_abb = team_x_abb,
        team_b = team_y, team_b_abb = team_y_abb,
        wins_a = wins_x, wins_b = wins_y,
        games_played = nrow(games), series_length = nrow(games),
        winner = if (wins_x > wins_y) team_x else team_y,
        winner_abb = if (wins_x > wins_y) team_x_abb else team_y_abb,
        games = list(game_log)
      )
    }) %>%
    ungroup() %>%
    select(-pair_key)

  assign_rounds <- load_assign_bracket_rounds()
  if (is.null(assign_rounds)) {
    bracket$round <- NA_character_
    return(bracket)
  }

  # assign_bracket_rounds() stop()s rather than guessing when its
  # chronological-reconstruction assumption breaks (issue #89). Caught here so an
  # unreconstructable bracket shape degrades to unlabeled rounds instead of
  # aborting the pipeline stage.
  labeled <- tryCatch(assign_rounds(bracket), error = function(e) {
    warning(sprintf(">>> [BRACKET 2026] assign_bracket_rounds() failed (%s) — rounds left unlabeled.",
                    conditionMessage(e)))
    NULL
  })
  if (is.null(labeled)) {
    bracket$round <- NA_character_
    return(bracket)
  }
  labeled
}

# ------------------------------------------------------------------------------
# Is this series actually over?
#
# The box-score cache only ever contains games that have been played, so a series
# in progress looks exactly like a short series: the 2026 Finals currently has a
# single game in it, and the naive "whoever has more wins" winner column would
# otherwise present Golden State as the champion off a 1-0 lead. A series is
# complete only when the leader has reached its format's win_threshold, read from
# playoff_simulator.R's PLAYOFF_FORMATS rather than restated here.
#
# `winner`/`winner_abb` are kept populated for schema parity with
# export_web_json.R's historicalBrackets payload, but for an incomplete series
# they mean "currently leading", which is what `series_complete = FALSE` tells
# every consumer. The web page renders "leads" rather than "won" on that flag.
# ------------------------------------------------------------------------------
mark_series_complete <- function(bracket) {
  bracket$series_complete <- vapply(seq_len(nrow(bracket)), function(i) {
    rnd <- bracket$round[i]
    if (is.na(rnd) || !rnd %in% names(ROUND_FORMATS)) return(NA)
    thr <- PLAYOFF_FORMATS[[ROUND_FORMATS[[rnd]]]]$win_threshold
    max(bracket$wins_a[i], bracket$wins_b[i]) >= thr
  }, logical(1))
  bracket
}

# ------------------------------------------------------------------------------
# Expected series length under a length distribution.
# ------------------------------------------------------------------------------
expected_games <- function(dist) {
  if (is.null(dist) || nrow(dist) == 0) return(NA_real_)
  round(sum(dist$length * dist$probability), 3)
}

dist_to_list <- function(dist) {
  if (is.null(dist) || nrow(dist) == 0) return(list())
  lapply(seq_len(nrow(dist)), function(i) {
    list(length = as.integer(dist$length[i]),
         label = as.character(dist$label[i]),
         probability = round(as.numeric(dist$probability[i]), 6))
  })
}

# ------------------------------------------------------------------------------
# Round 1 reconstruction.
#
# Leak-free by construction: `seeds` is derived with season_type_filter = 2, so
# the net ratings fed to the DP come from regular-season games only and the
# Round 1 games being predicted are not part of their own prediction.
#
# Round 1 is a best-of-3, so the exact series win probability comes from
# bo3_game_by_game_breakdown()'s closed form rather than from a Monte Carlo
# estimate -- the DP already computes the per-game probabilities exactly.
# ------------------------------------------------------------------------------
predict_round1 <- function(row, seeds) {
  s_a <- seeds %>% filter(abbr == row$team_a_abb)
  s_b <- seeds %>% filter(abbr == row$team_b_abb)
  if (nrow(s_a) == 0 || nrow(s_b) == 0) {
    return(unavailable_prediction(sprintf(
      "No derived regular-season seed for %s or %s.", row$team_a_abb, row$team_b_abb)))
  }

  high <- if (s_a$seed[1] <= s_b$seed[1]) s_a else s_b
  low  <- if (s_a$seed[1] <= s_b$seed[1]) s_b else s_a

  fmt_key <- ROUND_FORMATS[["Round 1"]]
  dist <- series_length_distribution(high$team[1], low$team[1],
                                     high$net_adj[1], low$net_adj[1], format = fmt_key)
  bd <- bo3_game_by_game_breakdown(high$net_adj[1], low$net_adj[1])
  p_high <- bd$p1 * bd$p2 + (bd$p1 * (1 - bd$p2) + (1 - bd$p1) * bd$p2) * bd$p3

  build_prediction(
    provenance = "round1_reconstruction",
    provenance_label = sprintf(
      "Reconstruction, computed %s. No Round 1 forecast was archived before these series were played.",
      format(Sys.Date(), "%Y-%m-%d")),
    rating_basis = sprintf(
      "%d regular-season games only (season_type == 2); the Round 1 games being predicted are excluded.",
      CURRENT_SEASON),
    as_of = "",
    fmt_key = fmt_key, dist = dist, p_high = p_high,
    high = high$team[1], high_abb = high$abbr[1], low = low$team[1], low_abb = low$abbr[1],
    seed_high = as.integer(high$seed[1]), seed_low = as.integer(low$seed[1]),
    net_high = round(high$net_adj[1], 4), net_low = round(low$net_adj[1], 4),
    actual_winner = row$winner, actual_winner_abb = row$winner_abb,
    series_complete = isTRUE(row$series_complete)
  )
}

# ------------------------------------------------------------------------------
# Semifinal: archived forecast, copied verbatim.
#
# Matched to a series by unordered team-name pair, NOT by the archive's list key
# ($semifinal_atl_ny / $semifinal_gs_lv), so a renamed key or a different
# semifinal pairing in a future season does not silently attach a forecast to
# the wrong series.
#
# Every number below is read straight off the archive. Nothing is recomputed:
# no call to series_length_distribution(), no re-derived net ratings.
# ------------------------------------------------------------------------------
predict_semifinal_from_archive <- function(row, archive) {
  if (is.null(archive)) {
    return(unavailable_prediction("Archived forecast file not found."))
  }
  entries <- archive[grepl("^semifinal", names(archive))]
  want <- sort(c(row$team_a, row$team_b))

  match_idx <- which(vapply(entries, function(e) {
    !is.null(e$team_high) && !is.null(e$team_low) &&
      identical(sort(c(e$team_high, e$team_low)), want)
  }, logical(1)))

  if (length(match_idx) != 1) {
    return(unavailable_prediction(sprintf(
      "No single archived forecast matches %s vs %s (%d candidates).",
      row$team_a, row$team_b, length(match_idx))))
  }
  e <- entries[[match_idx]]
  as_of <- if (!is.null(archive$generated_at)) format(as.Date(archive$generated_at), "%Y-%m-%d") else ""

  # The archive stores full team names only, no abbreviations. Resolve them off the
  # RESOLVED side of this same series row (not by recomputing anything on the
  # prediction side) so the page can render logos for the archived rounds too.
  abb_of <- function(nm) {
    if (identical(nm, row$team_a)) row$team_a_abb
    else if (identical(nm, row$team_b)) row$team_b_abb
    else NA_character_
  }

  pred <- build_prediction(
    provenance = "archived_forecast",
    provenance_label = sprintf(
      "Archived forecast, as of %s — what the model said before this series was played.", as_of),
    rating_basis = sprintf(
      paste0("%d regular-season games pooled with Round 1 postseason games, as the ratings ",
             "stood on %s. Carried forward verbatim, not recomputed."),
      CURRENT_SEASON, as_of),
    as_of = as_of,
    fmt_key = e$format,
    dist = e$distribution,
    p_high = e$series$p_high_seed_win,
    high = e$team_high, high_abb = abb_of(e$team_high),
    low = e$team_low, low_abb = abb_of(e$team_low),
    seed_high = NA_integer_, seed_low = NA_integer_,
    net_high = round(e$net_high_adj, 4), net_low = round(e$net_low_adj, 4),
    actual_winner = row$winner, actual_winner_abb = row$winner_abb,
    series_complete = isTRUE(row$series_complete)
  )
  # Archived extras that only exist for the archived rounds, kept verbatim.
  pred$forecast$fairMlHigh <- as.integer(e$series$fair_ml_high)
  pred$forecast$fairMlLow  <- as.integer(e$series$fair_ml_low)
  pred$forecast$avgSeriesGames <- round(as.numeric(e$series$avg_series_games), 3)
  pred
}

unavailable_prediction <- function(reason) {
  list(available = FALSE, provenance = "unavailable", provenanceLabel = reason, forecast = NULL)
}

build_prediction <- function(provenance, provenance_label, rating_basis, as_of, fmt_key, dist,
                             p_high, high, high_abb, low, low_abb, seed_high, seed_low,
                             net_high, net_low, actual_winner, actual_winner_abb,
                             series_complete) {
  fmt <- PLAYOFF_FORMATS[[fmt_key]]
  predicted <- if (p_high >= 0.5) high else low
  predicted_abb <- if (p_high >= 0.5) high_abb else low_abb
  predicted_abb <- predicted_abb %||% ""
  list(
    available = TRUE,
    provenance = provenance,
    provenanceLabel = provenance_label,
    forecast = list(
      ratingBasis = rating_basis,
      asOf = as_of,
      format = fmt_key,
      formatLabel = fmt$label,
      teamHigh = high, teamHighAbbr = high_abb %||% "",
      teamLow = low, teamLowAbbr = low_abb %||% "",
      seedHigh = seed_high, seedLow = seed_low,
      netHighAdj = net_high, netLowAdj = net_low,
      pHighSeedWin = round(p_high, 6),
      pLowSeedWin = round(1 - p_high, 6),
      predictedWinnerName = predicted,
      predictedWinner = predicted_abb,
      expectedGames = expected_games(dist),
      lengthDistribution = dist_to_list(dist),
      # Prediction vs. result, the whole point of the page. A three-state string
      # rather than a boolean because a series still being played has no verdict
      # yet, and a FALSE there would read as "the model got it wrong" when the
      # series simply has not finished (the 2026 Finals is 1 game in).
      resultStatus = if (!isTRUE(series_complete)) "pending"
                     else if (identical(predicted, actual_winner)) "correct"
                     else "incorrect"
    )
  )
}

# `%||%` here is jsonlite/rlang's null-coalescing operator, NOT app.R's scalar
# NA-coalescing redefinition (CLAUDE.md flags that one as vector-unsafe). Defined
# locally so this script does not depend on which of the two is in scope.
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

# ------------------------------------------------------------------------------
# Main entry point.
# ------------------------------------------------------------------------------
build_playoff_bracket_current <- function(season = CURRENT_SEASON,
                                          out_path = CACHE_PLAYOFF_BRACKET_CURRENT) {
  if (!file.exists(CACHE_TEAM_BOX)) {
    warning(sprintf(
      ">>> [BRACKET 2026] FALLBACK: %s not found — writing an EMPTY bracket artifact. The web page will render its empty state.",
      CACHE_TEAM_BOX))
    empty <- tibble()
    attr(empty, "season") <- season
    attr(empty, "generated_at") <- Sys.time()
    attr(empty, "source_note") <- sprintf("FALLBACK (empty): %s not found.", CACHE_TEAM_BOX)
    saveRDS(empty, out_path)
    return(invisible(empty))
  }

  box <- readRDS(CACHE_TEAM_BOX) %>% filter_real_franchises()
  bracket <- build_resolved_series(box, season_yr = season)

  if (nrow(bracket) == 0) {
    attr(bracket, "season") <- season
    attr(bracket, "generated_at") <- Sys.time()
    attr(bracket, "source_note") <- sprintf(
      "No season_type == 3 rows for %d in %s.", season, basename(CACHE_TEAM_BOX))
    saveRDS(bracket, out_path)
    message(sprintf(">>> [BRACKET 2026] Saved %s (0 series — empty state).", out_path))
    return(invisible(bracket))
  }

  # Leak-free seeds for the Round 1 reconstruction: season_type == 2 only.
  seeds <- derive_playoff_seeds(season_yr = season, season_type_filter = 2L)
  if (is.null(seeds)) {
    warning(">>> [BRACKET 2026] FALLBACK: seeds could not be derived — Round 1 predictions will be marked unavailable.")
    seeds <- tibble(seed = integer(0), abbr = character(0), team = character(0),
                    net_rating = numeric(0), net_adj = numeric(0))
  }

  archive <- NULL
  if (file.exists(ARCHIVED_PREDICTIONS_PATH)) {
    archive <- tryCatch(readRDS(ARCHIVED_PREDICTIONS_PATH), error = function(e) NULL)
    if (is.null(archive)) {
      warning(sprintf(">>> [BRACKET 2026] FALLBACK: %s exists but could not be read — archived semifinal forecasts marked unavailable.",
                      ARCHIVED_PREDICTIONS_PATH))
    }
  } else {
    warning(sprintf(">>> [BRACKET 2026] FALLBACK: %s not found — archived semifinal forecasts marked unavailable.",
                    ARCHIVED_PREDICTIONS_PATH))
  }

  bracket <- mark_series_complete(bracket)

  predictions <- vector("list", nrow(bracket))
  for (i in seq_len(nrow(bracket))) {
    row <- bracket[i, ]
    rnd <- row$round
    fmt_key <- if (!is.na(rnd) && rnd %in% names(ROUND_FORMATS)) ROUND_FORMATS[[rnd]] else NA_character_

    # Sanity check the round -> format mapping against the data instead of
    # trusting it: a series cannot have run longer than its format allows.
    if (!is.na(fmt_key) && row$games_played > length(PLAYOFF_FORMATS[[fmt_key]]$home_flags)) {
      warning(sprintf(
        ">>> [BRACKET 2026] %s vs %s is labeled '%s' (format %s, max %d games) but played %d — round/format mapping may be wrong.",
        row$team_a, row$team_b, rnd, fmt_key,
        length(PLAYOFF_FORMATS[[fmt_key]]$home_flags), row$games_played))
    }

    predictions[[i]] <- if (is.na(rnd)) {
      unavailable_prediction("Round label could not be inferred for this series.")
    } else if (identical(rnd, "Round 1")) {
      predict_round1(row, seeds)
    } else if (identical(rnd, "Semifinals")) {
      predict_semifinal_from_archive(row, archive)
    } else {
      # Finals (and any earlier round in a larger bracket): no archived forecast
      # exists and none is fabricated here. The Finals' per-game decomposition is
      # tracked as its own ticket (issue #94).
      unavailable_prediction(sprintf(
        "No model prediction is recorded for the %s. The series result is shown on its own.", rnd))
    }
  }

  bracket$prediction <- predictions

  # Order so the earliest round comes first; see sort below. (series_complete is
  # derived before predictions are built -- see mark_series_complete().)

  # Stable display order: Round 1 first, then Semifinals, then Finals; within a
  # round, by the series' first game date.
  round_rank <- match(bracket$round, names(ROUND_FORMATS))
  round_rank[is.na(round_rank)] <- length(ROUND_FORMATS) + 1L
  first_date <- vapply(bracket$games, function(gl) min(vapply(gl, function(g) as.numeric(g$game_date), numeric(1))), numeric(1))
  bracket <- bracket[order(round_rank, first_date), ]

  attr(bracket, "season") <- season
  attr(bracket, "generated_at") <- Sys.time()
  attr(bracket, "source_note") <- sprintf(
    "Resolved series derived from %s (season_type == 3). Round 1 predictions reconstructed from season_type == 2 ratings; Semifinal predictions copied verbatim from %s.",
    basename(CACHE_TEAM_BOX), basename(ARCHIVED_PREDICTIONS_PATH))

  saveRDS(bracket, out_path)
  message(sprintf(">>> [BRACKET 2026] Saved %s (%d series: %s).", out_path, nrow(bracket),
                  paste(sprintf("%d %s", as.integer(table(bracket$round)), names(table(bracket$round))),
                        collapse = ", ")))
  invisible(bracket)
}

if (!interactive()) {
  invisible(build_playoff_bracket_current())
}
