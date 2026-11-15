# ==============================================================================
# Secondary XGBoost Feature Fusion & TreeSHAP Engine (Issue #124)
#
# Trains a deterministic binary logistic XGBoost model on prior-season fused
# team differential features (18-game rolling box metrics, schedule/fatigue
# features, and 16-D style embedding similarity) and computes exact per-game
# TreeSHAP explanations (predict(..., predcontrib = TRUE)) for the target
# season's non-TBD schedule using strictly causal prior-date box scores.
# ==============================================================================

# This file's own directory, derived rather than hardcoded, matching sibling
# stage entrypoints so git worktrees stay isolated and tests can source from
# any scratch working directory under NBA_SKIP_STAGE_AUTORUN=1.
.THIS_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  ofile <- NULL
  for (fr in sys.frames()) {
    cand <- tryCatch(get("ofile", envir = fr, inherits = FALSE), error = function(e) NULL)
    if (is.character(cand) && length(cand) == 1L && nzchar(cand)) ofile <- cand
  }
  base <- if (!is.null(ofile)) dirname(ofile)
          else if (length(f) == 1L && nzchar(f)) dirname(f)
          else getwd()
  normalizePath(base, winslash = "/", mustWork = FALSE)
})

suppressPackageStartupMessages({
  library(tidyverse)
  library(slider)
  library(xgboost)
})

source(file.path(.THIS_DIR, "config.R"), local = TRUE)
source(file.path(.THIS_DIR, "load_embeddings.R"), local = TRUE)
source(file.path(.THIS_DIR, "team_name_resolver.R"), local = TRUE)

XGB_SHAP_MODEL_ID     <- "xgboost_feature_fusion_v1"
XGB_SHAP_MODEL_LABEL  <- "XGBoost Feature Fusion (TreeSHAP)"
XGB_SHAP_WINDOW_GAMES <- if (exists("ROLLING_WINDOW_SIZE")) as.integer(ROLLING_WINDOW_SIZE) else 18L

XGB_SHAP_FEATURE_NAMES <- c(
  "diff_roll_pts",
  "diff_roll_efg",
  "diff_roll_ts",
  "diff_roll_tovp",
  "diff_roll_oreb",
  "diff_roll_dreb",
  "diff_roll_ast",
  "diff_roll_stl",
  "diff_roll_blk",
  "diff_days_rest",
  "diff_fatigue_index",
  "diff_is_b2b",
  "style_similarity"
)

XGB_SHAP_FEATURE_LABELS <- c(
  diff_roll_pts      = "18-Game Scoring Diff (PPG)",
  diff_roll_efg      = "18-Game eFG% Diff",
  diff_roll_ts       = "18-Game True Shooting Diff",
  diff_roll_tovp     = "18-Game Turnover Rate Diff",
  diff_roll_oreb     = "18-Game Offensive Rebound Diff",
  diff_roll_dreb     = "18-Game Defensive Rebound Diff",
  diff_roll_ast      = "18-Game Assists Diff",
  diff_roll_stl      = "18-Game Steals Diff",
  diff_roll_blk      = "18-Game Blocks Diff",
  diff_days_rest     = "Days Rest Diff",
  diff_fatigue_index = "Schedule Fatigue Index Diff",
  diff_is_b2b        = "Back-to-Back Diff",
  style_similarity   = "16-D Style Embedding Cosine Sim"
)

XGB_SHAP_BOX_REQUIRED_COLS <- c(
  "game_id", "game_date", "team_id", "team_score",
  "field_goals_made", "field_goals_attempted",
  "three_point_field_goals_made", "free_throws_attempted",
  "total_turnovers", "offensive_rebounds", "defensive_rebounds",
  "assists", "steals", "blocks"
)

XGB_SHAP_SCHED_REQUIRED_COLS <- c(
  "game_id", "game_date", "home_id", "away_id",
  "home_short_display_name", "away_short_display_name"
)

.assert_required_cols <- function(df, required, label) {
  if (is.null(df) || !is.data.frame(df)) {
    stop(sprintf("%s must be a data.frame.", label), call. = FALSE)
  }
  missing_cols <- setdiff(required, names(df))
  if (length(missing_cols) > 0L) {
    stop(sprintf("%s is missing required column(s): %s",
                 label, paste(missing_cols, collapse = ", ")), call. = FALSE)
  }
  invisible(TRUE)
}

.format_hoopr_season <- function(s) {
  s_int <- as.integer(s)
  sprintf("%d-%02d", s_int - 1L, s_int %% 100L)
}

.derive_train_seasons_label <- function(seasons) {
  s_vals <- sort(unique(as.integer(seasons)))
  s_vals <- s_vals[!is.na(s_vals)]
  if (length(s_vals) == 0L) return("unknown")
  if (length(s_vals) == 1L) return(.format_hoopr_season(s_vals[1L]))
  sprintf("%s..%s", .format_hoopr_season(s_vals[1L]), .format_hoopr_season(s_vals[length(s_vals)]))
}

# Compute schedule rest, B2B, density, and fatigue index deterministically from
# ordered (team_id, game_date, game_id) rows without sourcing injury_load_tracker.R
# (which performs a cwd-relative source("config.R")).
.compute_schedule_features_df <- function(sched_rows, group_by_season = TRUE) {
  rest_cap <- if (exists("REST_DAYS_CAP")) as.numeric(REST_DAYS_CAP) else 7.0
  has_season <- isTRUE(group_by_season) && ("season" %in% names(sched_rows))

  df <- sched_rows |>
    mutate(
      game_id = as.character(.data$game_id),
      game_date = as.Date(as.character(.data$game_date)),
      team_id = as.integer(.data$team_id),
      team_home_away = as.character(.data$team_home_away)
    ) |>
    distinct(.data$game_id, .data$team_id, .keep_all = TRUE)

  if (has_season) {
    df <- df |>
      mutate(season = as.integer(.data$season)) |>
      arrange(.data$team_id, .data$season, .data$game_date, .data$game_id) |>
      group_by(.data$season, .data$team_id)
  } else {
    df <- df |>
      arrange(.data$team_id, .data$game_date, .data$game_id) |>
      group_by(.data$team_id)
  }

  df |>
    mutate(
      days_since_prior = as.numeric(.data$game_date - dplyr::lag(.data$game_date, 1L)),
      days_rest = pmin(rest_cap, dplyr::coalesce(.data$days_since_prior, 3.0)),
      is_back_to_back = dplyr::if_else(dplyr::coalesce(.data$days_since_prior, 3.0) == 1.0, 1L, 0L),
      is_3_in_4 = dplyr::if_else(as.numeric(.data$game_date - dplyr::lag(.data$game_date, 2L)) <= 3.0, 1L, 0L),
      is_4_in_5 = dplyr::if_else(as.numeric(.data$game_date - dplyr::lag(.data$game_date, 3L)) <= 4.0, 1L, 0L),
      prev_home_away = dplyr::lag(.data$team_home_away, 1L),
      travel_flag = dplyr::if_else(
        !is.na(.data$prev_home_away) & (.data$team_home_away != .data$prev_home_away),
        1L, 0L
      )
    ) |>
    ungroup() |>
    mutate(
      is_back_to_back = dplyr::coalesce(.data$is_back_to_back, 0L),
      is_3_in_4       = dplyr::coalesce(.data$is_3_in_4, 0L),
      is_4_in_5       = dplyr::coalesce(.data$is_4_in_5, 0L),
      travel_flag     = dplyr::coalesce(.data$travel_flag, 0L),
      schedule_fatigue_index = .data$is_back_to_back * 1.5 +
        .data$is_3_in_4 * 1.0 +
        .data$is_4_in_5 * 1.0 +
        .data$travel_flag * 0.5
    ) |>
    select("game_id", "team_id", "days_rest", "is_back_to_back", "schedule_fatigue_index")
}

.compute_box_metrics <- function(df, label = "team_box") {
  .assert_required_cols(df, XGB_SHAP_BOX_REQUIRED_COLS, label)
  if (nrow(df) == 0L) {
    return(tibble(
      game_id = character(),
      game_date = as.Date(character()),
      team_id = integer(),
      team_norm = character(),
      pts_scored = numeric(),
      oreb = numeric(),
      dreb = numeric(),
      ast = numeric(),
      stl = numeric(),
      blk = numeric(),
      efg = numeric(),
      tov = numeric(),
      ts = numeric()
    ))
  }

  fgm  <- as.numeric(df$field_goals_made)
  fga  <- as.numeric(df$field_goals_attempted)
  fg3m <- as.numeric(df$three_point_field_goals_made)
  fta  <- as.numeric(df$free_throws_attempted)
  tov_tot <- as.numeric(df$total_turnovers)
  pts  <- as.numeric(df$team_score)

  team_raw <- if ("team_short_display_name" %in% names(df)) {
    as.character(df$team_short_display_name)
  } else if ("team_name" %in% names(df)) {
    as.character(df$team_name)
  } else {
    as.character(df$team_id)
  }

  out <- tibble(
    game_id    = as.character(df$game_id),
    game_date  = as.Date(as.character(df$game_date)),
    team_id    = as.integer(df$team_id),
    team_norm  = resolve_team_name(team_raw),
    pts_scored = pts,
    oreb       = as.numeric(df$offensive_rebounds),
    dreb       = as.numeric(df$defensive_rebounds),
    ast        = as.numeric(df$assists),
    stl        = as.numeric(df$steals),
    blk        = as.numeric(df$blocks),
    efg        = (fgm + 0.5 * fg3m) / pmax(1.0, fga),
    tov        = tov_tot / pmax(1.0, fga + 0.44 * fta + tov_tot),
    ts         = pts / pmax(1.0, 2.0 * (fga + 0.44 * fta))
  )

  if ("season" %in% names(df)) out$season <- as.integer(df$season)
  if ("team_home_away" %in% names(df)) out$team_home_away <- as.character(df$team_home_away)
  if ("team_winner" %in% names(df)) out$team_winner <- df$team_winner
  out
}

.build_embedding_lookup <- function(team_emb = NULL) {
  if (is.null(team_emb)) {
    team_emb <- suppressWarnings(get_team_embeddings(nba_only = TRUE))
  }
  if (is.null(team_emb) || !is.data.frame(team_emb) || nrow(team_emb) == 0L) {
    return(list(by_id = list(), by_name = list()))
  }

  emb_cols <- grep("^emb_", names(team_emb), value = TRUE)
  if (length(emb_cols) == 0L) {
    return(list(by_id = list(), by_name = list()))
  }

  mat <- as.matrix(team_emb[, emb_cols, drop = FALSE])
  storage.mode(mat) <- "numeric"

  by_id <- list()
  by_name <- list()

  for (i in seq_len(nrow(team_emb))) {
    vec <- as.numeric(mat[i, ])
    if (!all(is.finite(vec))) next

    if ("team_id" %in% names(team_emb) && !is.na(team_emb$team_id[i])) {
      id_key <- as.character(as.integer(team_emb$team_id[i]))
      by_id[[id_key]] <- vec
    }
    if ("team_name" %in% names(team_emb) && !is.na(team_emb$team_name[i])) {
      nm_key <- resolve_team_name(team_emb$team_name[i])
      if (nzchar(nm_key)) by_name[[nm_key]] <- vec
    }
    if ("team_abbreviation" %in% names(team_emb) && !is.na(team_emb$team_abbreviation[i])) {
      ab_key <- resolve_team_name(team_emb$team_abbreviation[i])
      if (nzchar(ab_key) && is.null(by_name[[ab_key]])) by_name[[ab_key]] <- vec
    }
  }

  list(by_id = by_id, by_name = by_name)
}

.resolve_team_emb_vec <- function(emb_lookup, team_id = NA_integer_, team_name = NA_character_) {
  if (!is.na(team_id)) {
    v <- emb_lookup$by_id[[as.character(as.integer(team_id))]]
    if (!is.null(v)) return(v)
  }
  if (!is.na(team_name) && nzchar(trimws(as.character(team_name)))) {
    nm <- resolve_team_name(team_name)
    v <- emb_lookup$by_name[[nm]]
    if (!is.null(v)) return(v)
  }
  NULL
}

.calc_style_similarity <- function(emb_lookup, home_id, home_name, away_id, away_name) {
  v1 <- .resolve_team_emb_vec(emb_lookup, home_id, home_name)
  v2 <- .resolve_team_emb_vec(emb_lookup, away_id, away_name)
  if (is.null(v1) || is.null(v2)) return(0.0)
  denom <- sqrt(sum(v1^2)) * sqrt(sum(v2^2)) + 1e-6
  val <- sum(v1 * v2) / denom
  if (is.finite(val)) val else 0.0
}

.extract_training_dataset <- function(team_box_df,
                                      window_games = XGB_SHAP_WINDOW_GAMES,
                                      target_season = MATCHUPS_HOOPR_SEASON,
                                      emb_lookup = NULL) {
  .assert_required_cols(
    team_box_df,
    c(XGB_SHAP_BOX_REQUIRED_COLS, "season", "team_home_away", "team_winner"),
    "CACHE_TEAM_BOX"
  )
  if (is.null(emb_lookup)) emb_lookup <- .build_embedding_lookup()

  train_box_raw <- team_box_df[as.integer(team_box_df$season) < as.integer(target_season), , drop = FALSE]
  if (nrow(train_box_raw) == 0L) {
    stop(sprintf("No training box score records found with season < %d.", as.integer(target_season)),
         call. = FALSE)
  }

  metrics_df <- .compute_box_metrics(train_box_raw, label = "CACHE_TEAM_BOX")

  rolled <- metrics_df |>
    arrange(.data$team_id, .data$season, .data$game_date, .data$game_id) |>
    group_by(.data$season, .data$team_id) |>
    mutate(
      roll_pts_scored = slider::slide_dbl(.data$pts_scored, mean, .before = window_games, .after = -1L),
      roll_efg        = slider::slide_dbl(.data$efg, mean, .before = window_games, .after = -1L),
      roll_ts         = slider::slide_dbl(.data$ts, mean, .before = window_games, .after = -1L),
      roll_tovp       = slider::slide_dbl(.data$tov, mean, .before = window_games, .after = -1L),
      roll_oreb       = slider::slide_dbl(.data$oreb, mean, .before = window_games, .after = -1L),
      roll_dreb       = slider::slide_dbl(.data$dreb, mean, .before = window_games, .after = -1L),
      roll_ast        = slider::slide_dbl(.data$ast, mean, .before = window_games, .after = -1L),
      roll_stl        = slider::slide_dbl(.data$stl, mean, .before = window_games, .after = -1L),
      roll_blk        = slider::slide_dbl(.data$blk, mean, .before = window_games, .after = -1L)
    ) |>
    ungroup()

  sched_feats <- .compute_schedule_features_df(metrics_df, group_by_season = TRUE)
  fused <- rolled |>
    left_join(sched_feats, by = c("game_id", "team_id"))

  home_df <- fused |>
    filter(.data$team_home_away == "home") |>
    select(
      "game_id", "season", "game_date",
      home_id = "team_id", home_name = "team_norm", home_win = "team_winner",
      home_roll_pts = "roll_pts_scored", home_roll_efg = "roll_efg",
      home_roll_ts = "roll_ts", home_roll_tovp = "roll_tovp",
      home_roll_oreb = "roll_oreb", home_roll_dreb = "roll_dreb",
      home_roll_ast = "roll_ast", home_roll_stl = "roll_stl", home_roll_blk = "roll_blk",
      home_days_rest = "days_rest",
      home_fatigue = "schedule_fatigue_index",
      home_b2b = "is_back_to_back"
    )

  away_df <- fused |>
    filter(.data$team_home_away == "away") |>
    select(
      "game_id",
      away_id = "team_id", away_name = "team_norm",
      away_roll_pts = "roll_pts_scored", away_roll_efg = "roll_efg",
      away_roll_ts = "roll_ts", away_roll_tovp = "roll_tovp",
      away_roll_oreb = "roll_oreb", away_roll_dreb = "roll_dreb",
      away_roll_ast = "roll_ast", away_roll_stl = "roll_stl", away_roll_blk = "roll_blk",
      away_days_rest = "days_rest",
      away_fatigue = "schedule_fatigue_index",
      away_b2b = "is_back_to_back"
    )

  matchup_df <- inner_join(home_df, away_df, by = "game_id") |>
    mutate(
      diff_roll_pts      = .data$home_roll_pts - .data$away_roll_pts,
      diff_roll_efg      = .data$home_roll_efg - .data$away_roll_efg,
      diff_roll_ts       = .data$home_roll_ts - .data$away_roll_ts,
      diff_roll_tovp     = .data$home_roll_tovp - .data$away_roll_tovp,
      diff_roll_oreb     = .data$home_roll_oreb - .data$away_roll_oreb,
      diff_roll_dreb     = .data$home_roll_dreb - .data$away_roll_dreb,
      diff_roll_ast      = .data$home_roll_ast - .data$away_roll_ast,
      diff_roll_stl      = .data$home_roll_stl - .data$away_roll_stl,
      diff_roll_blk      = .data$home_roll_blk - .data$away_roll_blk,
      diff_days_rest     = .data$home_days_rest - .data$away_days_rest,
      diff_fatigue_index = .data$home_fatigue - .data$away_fatigue,
      diff_is_b2b        = as.numeric(.data$home_b2b - .data$away_b2b)
    )

  matchup_df$style_similarity <- vapply(seq_len(nrow(matchup_df)), function(i) {
    .calc_style_similarity(
      emb_lookup,
      matchup_df$home_id[i], matchup_df$home_name[i],
      matchup_df$away_id[i], matchup_df$away_name[i]
    )
  }, numeric(1))

  feat_mat <- as.matrix(matchup_df[, XGB_SHAP_FEATURE_NAMES, drop = FALSE])
  finite_rows <- apply(feat_mat, 1L, function(r) all(is.finite(r))) & !is.na(matchup_df$home_win)
  train_df <- matchup_df[finite_rows, , drop = FALSE]

  if (nrow(train_df) == 0L) {
    stop("Training feature extraction produced 0 complete rows.", call. = FALSE)
  }

  train_df <- train_df |> arrange(.data$season, .data$game_date, .data$game_id)
  list(
    df = train_df,
    train_seasons_label = .derive_train_seasons_label(train_df$season)
  )
}

.train_xgb_shap_model <- function(train_df,
                                  train_seasons_label,
                                  window_games = XGB_SHAP_WINDOW_GAMES,
                                  target_season = MATCHUPS_HOOPR_SEASON) {
  X_raw <- as.matrix(train_df[, XGB_SHAP_FEATURE_NAMES, drop = FALSE])
  storage.mode(X_raw) <- "numeric"

  feature_means <- colMeans(X_raw)
  feature_sds   <- apply(X_raw, 2L, stats::sd)
  feature_sds[!is.finite(feature_sds) | feature_sds == 0] <- 1.0
  names(feature_means) <- XGB_SHAP_FEATURE_NAMES
  names(feature_sds)   <- XGB_SHAP_FEATURE_NAMES

  X_scaled <- sweep(sweep(X_raw, 2L, feature_means, "-"), 2L, feature_sds, "/")
  colnames(X_scaled) <- XGB_SHAP_FEATURE_NAMES
  y_num <- ifelse(as.logical(train_df$home_win), 1, 0)

  set.seed(42)
  dm <- xgboost::xgb.DMatrix(data = X_scaled, label = y_num)
  bst <- xgboost::xgb.train(
    params = list(
      objective   = "binary:logistic",
      eval_metric = "logloss",
      max_depth   = 4,
      eta         = 0.03,
      nthread     = 1
    ),
    data    = dm,
    nrounds = 200,
    verbose = 0
  )

  list(
    booster_raw         = xgboost::xgb.save.raw(bst),
    feature_names       = XGB_SHAP_FEATURE_NAMES,
    feature_labels      = XGB_SHAP_FEATURE_LABELS,
    feature_means       = feature_means,
    feature_sds         = feature_sds,
    train_seasons_label = train_seasons_label,
    window_games        = as.integer(window_games),
    target_season       = as.integer(target_season),
    n_train_games       = as.integer(nrow(train_df)),
    trained_at          = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
}

.is_valid_cached_model <- function(obj, target_season, window_games) {
  if (is.null(obj) || !is.list(obj)) return(FALSE)
  req <- c("booster_raw", "feature_names", "feature_labels",
           "feature_means", "feature_sds", "train_seasons_label", "window_games")
  if (!all(req %in% names(obj))) return(FALSE)
  if (!is.raw(obj$booster_raw) || length(obj$booster_raw) == 0L) return(FALSE)
  if (!identical(as.character(obj$feature_names), XGB_SHAP_FEATURE_NAMES)) return(FALSE)
  if (!identical(as.integer(obj$window_games), as.integer(window_games))) return(FALSE)
  if (!is.null(obj$target_season) &&
      !identical(as.integer(obj$target_season), as.integer(target_season))) return(FALSE)
  if (length(obj$feature_means) != length(XGB_SHAP_FEATURE_NAMES) ||
      length(obj$feature_sds) != length(XGB_SHAP_FEATURE_NAMES)) return(FALSE)
  if (any(!is.finite(obj$feature_means)) || any(!is.finite(obj$feature_sds)) ||
      any(obj$feature_sds <= 0)) return(FALSE)
  TRUE
}

.load_or_train_model <- function(team_box_path,
                                 model_cache_path,
                                 target_season = MATCHUPS_HOOPR_SEASON,
                                 window_games = XGB_SHAP_WINDOW_GAMES,
                                 force_retrain = FALSE,
                                 emb_lookup = NULL) {
  use_cache <- !isTRUE(force_retrain) && file.exists(model_cache_path)
  if (use_cache && file.exists(team_box_path)) {
    model_mtime <- file.info(model_cache_path)$mtime
    box_mtime   <- file.info(team_box_path)$mtime
    if (is.na(model_mtime) || is.na(box_mtime) || model_mtime < box_mtime) {
      use_cache <- FALSE
    }
  }

  if (use_cache) {
    cached <- tryCatch(readRDS(model_cache_path), error = function(e) NULL)
    if (.is_valid_cached_model(cached, target_season, window_games)) {
      cat(sprintf("[XGB-SHAP] Reusing cached model from %s (%s, n=%s)\n",
                  basename(model_cache_path), cached$train_seasons_label,
                  if (!is.null(cached$n_train_games)) cached$n_train_games else "?"))
      return(cached)
    }
  }

  if (!file.exists(team_box_path)) {
    stop(sprintf("Training box score cache missing at %s.", team_box_path), call. = FALSE)
  }

  team_box_df <- readRDS(team_box_path)
  extracted <- .extract_training_dataset(
    team_box_df   = team_box_df,
    window_games  = window_games,
    target_season = target_season,
    emb_lookup    = emb_lookup
  )
  model_obj <- .train_xgb_shap_model(
    train_df            = extracted$df,
    train_seasons_label = extracted$train_seasons_label,
    window_games        = window_games,
    target_season       = target_season
  )

  model_dir <- dirname(model_cache_path)
  if (!dir.exists(model_dir)) dir.create(model_dir, recursive = TRUE)
  saveRDS(model_obj, model_cache_path)
  cat(sprintf("[XGB-SHAP] Trained & cached model (%s, %d games) -> %s\n",
              model_obj$train_seasons_label, model_obj$n_train_games, model_cache_path))
  model_obj
}

.prepare_clean_schedule <- function(sched_df, target_season) {
  .assert_required_cols(sched_df, XGB_SHAP_SCHED_REQUIRED_COLS, "CACHE_MATCHUPS_SCHEDULE")

  df <- sched_df
  if ("season" %in% names(df)) {
    df <- df[as.integer(df$season) == as.integer(target_season), , drop = FALSE]
  }

  home_nm <- trimws(as.character(df$home_short_display_name))
  away_nm <- trimws(as.character(df$away_short_display_name))
  is_tbd <- is.na(home_nm) | is.na(away_nm) | !nzchar(home_nm) | !nzchar(away_nm) |
    home_nm == "TBD" | away_nm == "TBD"
  df <- df[!is_tbd, , drop = FALSE]

  if (nrow(df) == 0L) {
    return(tibble(
      game_id = character(),
      game_date = as.Date(character()),
      home_id = integer(),
      away_id = integer(),
      home_name = character(),
      away_name = character()
    ))
  }

  tibble(
    game_id   = as.character(df$game_id),
    game_date = as.Date(as.character(df$game_date)),
    home_id   = as.integer(df$home_id),
    away_id   = as.integer(df$away_id),
    home_name = resolve_team_name(df$home_short_display_name),
    away_name = resolve_team_name(df$away_short_display_name)
  ) |>
    filter(!is.na(.data$game_date)) |>
    distinct(.data$game_id, .keep_all = TRUE) |>
    arrange(.data$game_date, .data$game_id)
}

.rolling_snapshot <- function(team_box_rows, this_game_date, window_games) {
  if (is.null(team_box_rows) || nrow(team_box_rows) == 0L) {
    return(list(prior_games_n = 0L, stats = NULL))
  }
  prior <- team_box_rows[team_box_rows$game_date < this_game_date, , drop = FALSE]
  prior_n <- as.integer(nrow(prior))
  if (prior_n == 0L) {
    return(list(prior_games_n = 0L, stats = NULL))
  }
  win <- utils::tail(prior, window_games)
  list(
    prior_games_n = prior_n,
    stats = c(
      roll_pts  = mean(win$pts_scored),
      roll_efg  = mean(win$efg),
      roll_ts   = mean(win$ts),
      roll_tovp = mean(win$tov),
      roll_oreb = mean(win$oreb),
      roll_dreb = mean(win$dreb),
      roll_ast  = mean(win$ast),
      roll_stl  = mean(win$stl),
      roll_blk  = mean(win$blk)
    )
  )
}

.score_season_games <- function(model_obj,
                                sched_df,
                                season_box_df,
                                target_season = MATCHUPS_HOOPR_SEASON,
                                emb_lookup = NULL) {
  if (is.null(emb_lookup)) emb_lookup <- .build_embedding_lookup()
  clean_sched <- .prepare_clean_schedule(sched_df, target_season)
  out <- stats::setNames(vector("list", nrow(clean_sched)), clean_sched$game_id)
  if (nrow(clean_sched) == 0L) return(out)

  box_metrics <- .compute_box_metrics(season_box_df, label = "CACHE_MATCHUPS_TEAM_BOX")
  if (nrow(box_metrics) > 0L) {
    box_metrics <- box_metrics |> arrange(.data$game_date, .data$game_id)
  }

  # Pre-split prior box score rows by team_id (and normalized name fallback)
  box_by_id <- if (nrow(box_metrics) > 0L) split(box_metrics, as.character(box_metrics$team_id)) else list()
  box_by_name <- if (nrow(box_metrics) > 0L) split(box_metrics, box_metrics$team_norm) else list()

  # Deterministic schedule fatigue / rest / B2B features strictly up to each game_date
  sched_long <- bind_rows(
    tibble(
      game_id = clean_sched$game_id,
      season = as.integer(target_season),
      game_date = clean_sched$game_date,
      team_id = clean_sched$home_id,
      team_home_away = "home"
    ),
    tibble(
      game_id = clean_sched$game_id,
      season = as.integer(target_season),
      game_date = clean_sched$game_date,
      team_id = clean_sched$away_id,
      team_home_away = "away"
    )
  )
  sched_feats <- .compute_schedule_features_df(sched_long, group_by_season = TRUE)
  sched_key <- paste(sched_feats$game_id, sched_feats$team_id, sep = "::")
  sched_idx_map <- stats::setNames(seq_len(nrow(sched_feats)), sched_key)

  feat_names  <- model_obj$feature_names
  feat_labels <- model_obj$feature_labels
  feat_means  <- as.numeric(model_obj$feature_means[feat_names])
  feat_sds    <- as.numeric(model_obj$feature_sds[feat_names])
  win_games   <- as.integer(model_obj$window_games)

  valid_records <- list()

  for (i in seq_len(nrow(clean_sched))) {
    gid       <- clean_sched$game_id[i]
    gdate     <- clean_sched$game_date[i]
    h_id      <- clean_sched$home_id[i]
    a_id      <- clean_sched$away_id[i]
    h_name    <- clean_sched$home_name[i]
    a_name    <- clean_sched$away_name[i]

    h_rows <- if (!is.na(h_id)) box_by_id[[as.character(h_id)]] else NULL
    if (is.null(h_rows) && !is.na(h_name) && nzchar(h_name)) h_rows <- box_by_name[[h_name]]
    a_rows <- if (!is.na(a_id)) box_by_id[[as.character(a_id)]] else NULL
    if (is.null(a_rows) && !is.na(a_name) && nzchar(a_name)) a_rows <- box_by_name[[a_name]]

    h_snap <- .rolling_snapshot(h_rows, gdate, win_games)
    a_snap <- .rolling_snapshot(a_rows, gdate, win_games)

    if (a_snap$prior_games_n == 0L || h_snap$prior_games_n == 0L) {
      next
    }

    h_sf_idx <- sched_idx_map[[paste(gid, h_id, sep = "::")]]
    a_sf_idx <- sched_idx_map[[paste(gid, a_id, sep = "::")]]
    if (is.null(h_sf_idx) || is.na(h_sf_idx) || is.null(a_sf_idx) || is.na(a_sf_idx)) {
      next
    }

    hs <- h_snap$stats
    as_ <- a_snap$stats

    raw_vals <- c(
      diff_roll_pts      = unname(hs[["roll_pts"]] - as_[["roll_pts"]]),
      diff_roll_efg      = unname(hs[["roll_efg"]] - as_[["roll_efg"]]),
      diff_roll_ts       = unname(hs[["roll_ts"]] - as_[["roll_ts"]]),
      diff_roll_tovp     = unname(hs[["roll_tovp"]] - as_[["roll_tovp"]]),
      diff_roll_oreb     = unname(hs[["roll_oreb"]] - as_[["roll_oreb"]]),
      diff_roll_dreb     = unname(hs[["roll_dreb"]] - as_[["roll_dreb"]]),
      diff_roll_ast      = unname(hs[["roll_ast"]] - as_[["roll_ast"]]),
      diff_roll_stl      = unname(hs[["roll_stl"]] - as_[["roll_stl"]]),
      diff_roll_blk      = unname(hs[["roll_blk"]] - as_[["roll_blk"]]),
      diff_days_rest     = sched_feats$days_rest[h_sf_idx] - sched_feats$days_rest[a_sf_idx],
      diff_fatigue_index = sched_feats$schedule_fatigue_index[h_sf_idx] - sched_feats$schedule_fatigue_index[a_sf_idx],
      diff_is_b2b        = as.numeric(sched_feats$is_back_to_back[h_sf_idx] - sched_feats$is_back_to_back[a_sf_idx]),
      style_similarity   = .calc_style_similarity(emb_lookup, h_id, h_name, a_id, a_name)
    )[feat_names]

    if (any(!is.finite(raw_vals))) {
      next
    }

    z_vals <- (raw_vals - feat_means) / feat_sds
    names(z_vals) <- feat_names
    if (any(!is.finite(z_vals))) {
      next
    }

    valid_records[[length(valid_records) + 1L]] <- list(
      game_id = gid,
      raw_vals = raw_vals,
      z_vals = z_vals,
      away_prior_games_n = a_snap$prior_games_n,
      home_prior_games_n = h_snap$prior_games_n
    )
  }

  if (length(valid_records) == 0L) {
    return(out)
  }

  X_pred <- do.call(rbind, lapply(valid_records, function(r) r$z_vals))
  colnames(X_pred) <- feat_names

  bst <- xgboost::xgb.load.raw(model_obj$booster_raw)
  dm_pred <- xgboost::xgb.DMatrix(data = X_pred)
  pred_probs <- as.numeric(predict(bst, dm_pred))
  shap_mat   <- predict(bst, dm_pred, predcontrib = TRUE)

  if (!("(Intercept)" %in% colnames(shap_mat)) || !all(feat_names %in% colnames(shap_mat))) {
    stop("xgboost predcontrib output missing expected feature or (Intercept) columns.", call. = FALSE)
  }

  for (k in seq_along(valid_records)) {
    rec <- valid_records[[k]]
    gid <- rec$game_id
    pred_prob <- pred_probs[k]
    sh_row    <- shap_mat[k, ]
    base_val  <- unname(as.numeric(sh_row[["(Intercept)"]]))
    shap_vals <- unname(as.numeric(sh_row[feat_names]))
    tot       <- sum(shap_vals) + base_val

    if (!is.finite(pred_prob) || !is.finite(base_val) || any(!is.finite(shap_vals)) ||
        abs(stats::plogis(tot) - pred_prob) >= 1e-4) {
      stop(sprintf("TreeSHAP additivity/probability assertion failed for game_id %s (diff=%.6g).",
                   gid, abs(stats::plogis(tot) - pred_prob)), call. = FALSE)
    }

    ord <- order(-abs(round(shap_vals, 5L)), -abs(shap_vals), feat_names)
    factors <- lapply(ord, function(j) {
      sv <- shap_vals[j]
      fname <- feat_names[j]
      list(
        feature          = fname,
        label            = unname(as.character(feat_labels[[fname]])),
        feature_value    = round(unname(rec$raw_vals[[j]]), 4L),
        z_score          = round(unname(rec$z_vals[[j]]), 4L),
        shap_log_odds    = round(sv, 5L),
        shap_prob_approx = round(stats::plogis(base_val + sv) - stats::plogis(base_val), 4L)
      )
    })
    names(factors) <- NULL

    out[[gid]] <- list(
      model_id                = XGB_SHAP_MODEL_ID,
      model_label             = XGB_SHAP_MODEL_LABEL,
      train_seasons_label     = model_obj$train_seasons_label,
      window_games            = win_games,
      away_prior_games_n      = as.integer(rec$away_prior_games_n),
      home_prior_games_n      = as.integer(rec$home_prior_games_n),
      base_value_log_odds     = round(base_val, 5L),
      total_log_odds          = round(tot, 5L),
      predicted_home_win_prob = round(pred_prob, 4L),
      factors                 = factors
    )
  }

  out
}

run_xgboost_shap_engine <- function(season = MATCHUPS_HOOPR_SEASON,
                                    force_retrain = FALSE,
                                    team_box_path = CACHE_TEAM_BOX,
                                    schedule_path = CACHE_MATCHUPS_SCHEDULE(season),
                                    season_box_path = CACHE_MATCHUPS_TEAM_BOX(season),
                                    model_cache_path = CACHE_XGBOOST_SHAP_MODEL,
                                    output_path = CACHE_XGBOOST_GAME_SHAP(season),
                                    team_emb = NULL) {
  season <- as.integer(season)
  cat("\n==================================================================\n")
  cat(sprintf("   NBA SECONDARY XGBOOST FEATURE FUSION & TREESHAP (SEASON %d)   \n", season))
  cat("==================================================================\n\n")

  if (!file.exists(schedule_path)) {
    stop(sprintf("Schedule cache missing at %s.", schedule_path), call. = FALSE)
  }
  if (!file.exists(season_box_path)) {
    stop(sprintf("Season team box cache missing at %s.", season_box_path), call. = FALSE)
  }

  emb_lookup <- .build_embedding_lookup(team_emb)
  model_obj <- .load_or_train_model(
    team_box_path    = team_box_path,
    model_cache_path = model_cache_path,
    target_season    = season,
    window_games     = XGB_SHAP_WINDOW_GAMES,
    force_retrain    = force_retrain,
    emb_lookup       = emb_lookup
  )

  sched_df      <- readRDS(schedule_path)
  season_box_df <- readRDS(season_box_path)

  results <- .score_season_games(
    model_obj     = model_obj,
    sched_df      = sched_df,
    season_box_df = season_box_df,
    target_season = season,
    emb_lookup    = emb_lookup
  )

  out_dir <- dirname(output_path)
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  saveRDS(results, output_path)

  n_total <- length(results)
  n_non_null <- sum(!vapply(results, is.null, logical(1)))
  cat(sprintf("[XGB-SHAP] Saved %d game entries (%d scored, %d null/insufficient history) -> %s\n",
              n_total, n_non_null, n_total - n_non_null, output_path))

  invisible(results)
}

if (!nzchar(Sys.getenv("NBA_SKIP_STAGE_AUTORUN"))) {
  run_xgboost_shap_engine()
}
