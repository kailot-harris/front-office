# ==============================================================================
# NBA Analytics - build leader_methodology.json (NBA_analytics#258)
# Path: <repo root>/tools/build_leader_methodology.R
#
# Combines the leader reliability study results
# (docs/research/leader_reliability_study_results.json, #256) with the owner's
# qualifying minimums in config.R (#254) into web/public/data/leader_methodology.json,
# read by /players/leaders/methodology.
#
# Frozen research + config artifact: NOT a run_full_pipeline.R stage and not
# in WEB_DATA_FILES. Re-run when the study is re-run or owner minimums change.
#
# Usage:
#   Rscript --vanilla tools/build_leader_methodology.R
#
# Exit status: 0 written; 1 any check failed (nothing written).
# ==============================================================================

.LM_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  ofile <- NULL
  for (fr in sys.frames()) {
    cand <- tryCatch(get("ofile", envir = fr, inherits = FALSE), error = function(e) NULL)
    if (is.character(cand) && length(cand) == 1L && nzchar(cand)) ofile <- cand
  }
  base <- if (!is.null(ofile)) dirname(dirname(ofile))
          else if (length(f) == 1L && nzchar(f) && grepl("build_leader_methodology\\.R$", f)) dirname(dirname(f))
          else getwd()
  normalizePath(base, winslash = "/", mustWork = FALSE)
})

suppressPackageStartupMessages(library(jsonlite))

if (!exists("WEB_JSON_LEADER_METHODOLOGY") || !exists("LEADERS_STUDY_SOURCE_COMMIT")) {
  source(file.path(.LM_DIR, "config.R"), local = TRUE)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

LM_STUDY_REPO_PATH <- "docs/research/leader_reliability_study_results.json"

lm_fail <- function(...) stop(sprintf(...), call. = FALSE)

lm_git_date <- function(args) {
  git <- Sys.which("git")
  if (!nzchar(git)) return(NULL)
  out <- suppressWarnings(tryCatch(
    system2(git, args, stdout = TRUE, stderr = FALSE),
    error = function(e) character(0)
  ))
  if (length(out) >= 1L && grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", trimws(out[[1]]))) {
    trimws(out[[1]])
  } else {
    NULL
  }
}

lm_find_by_n <- function(rows, target_n) {
  for (r in rows) {
    if (!is.null(r$n) && isTRUE(all.equal(as.numeric(r$n), as.numeric(target_n)))) return(r)
  }
  NULL
}

lm_find_by_sb <- function(rows, target_sb) {
  for (r in rows) {
    if (!is.null(r$sb_sample) && isTRUE(all.equal(as.numeric(r$sb_sample), as.numeric(target_sb)))) return(r)
  }
  NULL
}

lm_find_rapm_threshold <- function(rows, measure, target_lo) {
  for (r in rows) {
    if (identical(r$measure, measure) && !is.null(r$lo) &&
        isTRUE(all.equal(as.numeric(r$lo), as.numeric(target_lo)))) {
      return(r)
    }
  }
  NULL
}

lm_stat_specs <- function(cfg_env) {
  get_num <- function(name) {
    if (!exists(name, envir = cfg_env, inherits = TRUE)) lm_fail("missing config constant %s", name)
    as.integer(get(name, envir = cfg_env, inherits = TRUE))
  }
  spec <- function(key, label, group, bucket, unit, unit_label, constant,
                   noise_note = FALSE, floor_constant = NULL) {
    min_val <- get_num(constant)
    floor_val <- if (!is.null(floor_constant)) get_num(floor_constant) else NULL
    list(
      key = key, label = label, group = group, bucket = bucket,
      unit = unit, unit_label = unit_label,
      constant = constant, minimum_full_season = min_val,
      minimum_minutes_constant = floor_constant,
      minimum_minutes_full_season = floor_val,
      noise_note = noise_note
    )
  }
  list(
    # Counting stats (by games played)
    spec("pts",  "Points per game",             "counting", "early",  "games", "games", "LEADERS_MIN_GAMES_PTS"),
    spec("reb",  "Rebounds per game",           "counting", "early",  "games", "games", "LEADERS_MIN_GAMES_REB"),
    spec("ast",  "Assists per game",            "counting", "early",  "games", "games", "LEADERS_MIN_GAMES_AST"),
    spec("tov",  "Turnovers per game",          "counting", "middle", "games", "games", "LEADERS_MIN_GAMES_TOV",
         floor_constant = "LEADERS_MIN_MINUTES_TOV_PER_GAME"),
    spec("fg3m", "3-pointers made per game",    "counting", "middle", "games", "games", "LEADERS_MIN_GAMES_FG3M"),
    spec("oreb", "Offensive rebounds per game", "counting", "middle", "games", "games", "LEADERS_MIN_GAMES_OREB"),
    spec("blk",  "Blocks per game",             "counting", "middle", "games", "games", "LEADERS_MIN_GAMES_BLK"),
    spec("stl",  "Steals per game",             "counting", "late",   "games", "games", "LEADERS_MIN_GAMES_STL"),
    # Shooting (by attempts)
    spec("ft_pct",  "Free throw %", "shooting", "attempts", "fta",  "FTA", "LEADERS_MIN_FTA_FT_PCT"),
    spec("fg_pct",  "Field goal %", "shooting", "attempts", "fga",  "FGA", "LEADERS_MIN_FGA_FG_PCT"),
    spec("fg3_pct", "3-point %",    "shooting", "attempts", "fg3a", "3PA", "LEADERS_MIN_FG3A_FG3_PCT", noise_note = TRUE),
    # Rates (by minutes)
    spec("usg_pct", "Usage rate",             "rates", "early",  "minutes", "minutes", "LEADERS_MIN_MINUTES_USG_PCT"),
    spec("ast_pct", "Assist rate",            "rates", "early",  "minutes", "minutes", "LEADERS_MIN_MINUTES_AST_PCT"),
    spec("orb_pct", "Offensive rebound rate", "rates", "middle", "minutes", "minutes", "LEADERS_MIN_MINUTES_ORB_PCT"),
    spec("drb_pct", "Defensive rebound rate", "rates", "middle", "minutes", "minutes", "LEADERS_MIN_MINUTES_DRB_PCT"),
    spec("tov_pct", "Turnover rate",          "rates", "late",   "minutes", "minutes", "LEADERS_MIN_MINUTES_TOV_PCT"),
    spec("efg_pct", "Effective field goal %", "rates", "late",   "minutes", "minutes", "LEADERS_MIN_MINUTES_EFG_PCT", noise_note = TRUE),
    spec("ts_pct",  "True shooting %",        "rates", "late",   "minutes", "minutes", "LEADERS_MIN_MINUTES_TS_PCT",  noise_note = TRUE),
    # RAPM (by possessions per side)
    spec("orapm",      "Offensive RAPM", "rapm", "possessions", "possessions_per_side", "possessions per side",
         "LEADERS_MIN_POSS_PER_SIDE_RAPM", noise_note = TRUE),
    spec("drapm",      "Defensive RAPM", "rapm", "possessions", "possessions_per_side", "possessions per side",
         "LEADERS_MIN_POSS_PER_SIDE_RAPM", noise_note = TRUE),
    spec("total_rapm", "Total RAPM",     "rapm", "possessions", "possessions_per_side", "possessions per side",
         "LEADERS_MIN_POSS_PER_SIDE_RAPM", noise_note = TRUE)
  )
}

lm_build_minimum_row <- function(sp, study) {
  min_val <- sp$minimum_full_season
  if (identical(sp$group, "rapm")) {
    half_target <- min_val / 2
    row <- lm_find_rapm_threshold(study$rapm$thresholds, sp$key, half_target)
    if (is.null(row)) {
      lm_fail("RAPM threshold %g not found in study for %s", half_target, sp$key)
    }
    rel <- list(
      split_half_n = row$lo,
      split_half_r = row$r,
      split_half_lo = row$r_lo,
      split_half_hi = row$r_hi,
      split_half_n_players = row$n_players,
      spearman_brown_n = min_val,
      spearman_brown_r = row$r_sb,
      spearman_brown_lo = row$r_sb_lo,
      spearman_brown_hi = row$r_sb_hi,
      spearman_brown_n_players = row$n_players,
      spearman_brown_null_reason = NULL,
      rest_of_season_r = NULL,
      rest_of_season_lo = NULL,
      rest_of_season_hi = NULL,
      rest_of_season_n_players = NULL,
      rest_of_season_null_reason = "Rest-of-season check not run for RAPM (joint ridge fit over all players)."
    )
  } else {
    st <- study$stats[[sp$key]]
    if (is.null(st)) lm_fail("stat %s not found in study JSON", sp$key)
    sh <- lm_find_by_n(st$split_half, min_val)
    if (is.null(sh)) lm_fail("split_half n=%g not found in study for %s", min_val, sp$key)
    sb <- lm_find_by_sb(st$split_half, min_val)
    ros <- lm_find_by_n(st$rest_of_season, min_val)
    if (is.null(ros)) lm_fail("rest_of_season n=%g not found in study for %s", min_val, sp$key)

    sb_reason <- if (is.null(sb)) {
      sprintf("Study grid does not evaluate n = %g (half of %g); exact split-half r at %g is reported.",
              min_val / 2, min_val, min_val)
    } else NULL

    rel <- list(
      split_half_n = sh$n,
      split_half_r = sh$r,
      split_half_lo = sh$r_lo,
      split_half_hi = sh$r_hi,
      split_half_n_players = sh$n_players,
      spearman_brown_n = if (!is.null(sb)) sb$sb_sample else NULL,
      spearman_brown_r = if (!is.null(sb)) sb$r_sb else NULL,
      spearman_brown_lo = if (!is.null(sb)) sb$r_sb_lo else NULL,
      spearman_brown_hi = if (!is.null(sb)) sb$r_sb_hi else NULL,
      spearman_brown_n_players = if (!is.null(sb)) sb$n_players else NULL,
      spearman_brown_null_reason = sb_reason,
      rest_of_season_r = ros$r,
      rest_of_season_lo = ros$r_lo,
      rest_of_season_hi = ros$r_hi,
      rest_of_season_n_players = ros$n_players,
      rest_of_season_null_reason = NULL
    )
  }
  c(sp, list(reliability = rel))
}

build_leader_methodology <- function(
  study_path = file.path(.LM_DIR, LM_STUDY_REPO_PATH),
  out_path = WEB_JSON_LEADER_METHODOLOGY,
  cfg_env = NULL,
  now = Sys.time()
) {
  if (!file.exists(study_path)) lm_fail("study JSON missing: %s", study_path)
  if (is.null(cfg_env)) {
    cfg_env <- new.env(parent = globalenv())
    source(file.path(.LM_DIR, "config.R"), local = cfg_env)
  }

  study <- jsonlite::fromJSON(study_path, simplifyVector = FALSE)
  req <- c("issue", "note", "settings", "data_audit", "player_seasons", "stats", "rapm", "runtime_minutes")
  miss <- setdiff(req, names(study))
  if (length(miss)) lm_fail("study JSON missing keys: %s", paste(miss, collapse = ", "))

  source_commit <- get("LEADERS_STUDY_SOURCE_COMMIT", envir = cfg_env, inherits = TRUE)
  base_games <- as.integer(get("LEADERS_FULL_SEASON_GAMES", envir = cfg_env, inherits = TRUE))
  source_sha256 <- unname(as.character(tools::sha256sum(study_path)))
  study_run_date <- lm_git_date(c("log", "-n", "1", "--format=%cs", "--", LM_STUDY_REPO_PATH)) %||%
    lm_git_date(c("log", "-n", "1", "--format=%cs", source_commit))
  published_at <- format(as.POSIXct(now), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

  specs <- lm_stat_specs(cfg_env)
  minimums <- lapply(specs, lm_build_minimum_row, study = study)

  example_games <- as.integer(round(base_games / 2))
  example_keys <- c("pts", "stl", "fg3_pct", "efg_pct", "total_rapm")
  example_rows <- lapply(Filter(function(m) m$key %in% example_keys, minimums), function(m) {
    list(
      key = m$key,
      label = m$label,
      unit_label = m$unit_label,
      minimum_full_season = m$minimum_full_season,
      required = round(m$minimum_full_season * example_games / base_games, 2)
    )
  })

  payload <- list(
    schema_version = 1L,
    source_commit = source_commit,
    source_sha256 = source_sha256,
    study_run_date = study_run_date,
    published_at = published_at,
    issue = study$issue,
    note = study$note,
    base_games = base_games,
    settings = study$settings,
    data_audit = study$data_audit,
    player_seasons = study$player_seasons,
    runtime_minutes = study$runtime_minutes,
    scaling_example = list(
      formula = "required = minimum * team_games_played / base_games",
      team_games_played = example_games,
      base_games = base_games,
      examples = example_rows
    ),
    minimums = minimums,
    stats = study$stats,
    rapm = study$rapm
  )

  txt <- jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null", na = "null", digits = 6, pretty = FALSE)
  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(out_path, ".tmp")
  con <- file(tmp, open = "wb")
  writeBin(charToRaw(enc2utf8(txt)), con)
  close(con)
  if (!file.rename(tmp, out_path)) lm_fail("failed to move %s into place", tmp)
  message(sprintf(">>> build_leader_methodology: wrote %s (%d minimums, commit %s)",
                  out_path, length(minimums), substr(source_commit, 1L, 12L)))
  invisible(out_path)
}

local({
  argv <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (!any(grepl("build_leader_methodology\\.R$", f))) return(invisible(NULL))
  if (nzchar(Sys.getenv("NBA_SKIP_STAGE_AUTORUN"))) return(invisible(NULL))
  setwd(.LM_DIR)
  ok <- tryCatch({
    build_leader_methodology()
    TRUE
  }, error = function(e) {
    message(sprintf("[FAIL] build_leader_methodology: %s", conditionMessage(e)))
    FALSE
  })
  quit(status = if (ok) 0L else 1L, save = "no")
})
