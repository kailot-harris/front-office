# ==============================================================================
# build_shot_chart_dataset.R
# Extracts NBA shot locations for rotation players, calculates 14 discrete zone baselines,
# and outputs optimized JSON files for the Next.js web application.
# ==============================================================================

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
  library(dplyr)
  library(jsonlite)
})

source(file.path(.THIS_DIR, "config.R"), local = TRUE)

# SHOT_CHART_SEASON is hoopR's END-year numbering (e.g. 2027 => 2026-2027).
# Defaults to config.R's CURRENT_SEASON; override with NBA_SHOT_CHART_SEASON to
# inspect another season sample.
resolve_shot_chart_season <- function(default_season = CURRENT_SEASON) {
  env <- trimws(Sys.getenv("NBA_SHOT_CHART_SEASON", unset = ""))
  if (nzchar(env)) {
    parsed <- suppressWarnings(as.integer(env))
    if (is.na(parsed)) {
      stop(sprintf("Invalid NBA_SHOT_CHART_SEASON='%s'; expected integer season year.", env), call. = FALSE)
    }
    return(parsed)
  }
  as.integer(default_season)
}

SHOT_CHART_SEASON <- resolve_shot_chart_season(CURRENT_SEASON)

# 14 Discrete Zone Classification
# Basketball half-court dimensions:
# Width: 50 ft (-25 to +25)
# Length: 47 ft (0 to 47 from baseline)
# Basket rim is at (0, 5.25)
classify_14_zones <- function(x, y, dist, val = 2) {
  # 1. Deep / Logo 3 (dist > 27.5 ft or y > 33 ft from baseline)
  if (dist > 27.5 || y > 33.0) {
    return("Deep / Logo 3")
  }

  # 2. Corner 3s (y <= 14.2 ft, |x| >= 21.5 ft)
  if (abs(x) >= 21.5 && y <= 14.2) {
    if (x < 0) return("Left Corner 3") else return("Right Corner 3")
  }

  # 3. Above Break 3s (dist >= 23.5 ft or official 3-point attempt)
  if (dist >= 23.5 || val == 3) {
    if (x < -7.0) return("Left Wing 3")
    if (x > 7.0)  return("Right Wing 3")
    return("Center 3")
  }

  # 4. Restricted Area (< 4.2 ft)
  if (dist <= 4.2) {
    return("Restricted Area")
  }

  # 5. In The Paint (|x| <= 8 ft, y <= 19 ft)
  if (abs(x) <= 8.0 && y <= 19.0) {
    if (y <= 11.5) return("Paint (Low / Floater)")
    return("Paint (High / FT)")
  }

  # 6. Baseline Mid-Range (y <= 14.2 ft)
  if (y <= 14.2) {
    if (x < 0) return("Left Baseline Mid") else return("Right Baseline Mid")
  }

  # 7. Wing & Center Mid-Range
  if (x < -7.0) return("Left Wing Mid")
  if (x > 7.0)  return("Right Wing Mid")
  return("Center Mid")
}

# ESPN occasionally emits a clock as H:MM:SS (e.g. "1:38:43") alongside the usual
# M:SS. The shot record contract expects a game clock, so keep the final two parts.
normalize_clock <- function(x) {
  vapply(strsplit(as.character(x), ":", fixed = TRUE), function(parts) {
    if (length(parts) == 0L) ""
    else if (length(parts) >= 2L) paste(tail(parts, 2L), collapse = ":")
    else as.character(parts)
  }, character(1))
}

# Latest game_date in the loaded shot sample formatted YYYY-MM-DD, or NULL when
# the feed lacks game_date or contains only NA/unparseable dates.
extract_through_date <- function(shots_df) {
  if (is.null(shots_df) || !("game_date" %in% names(shots_df))) {
    return(NULL)
  }
  gd <- shots_df$game_date
  if (length(gd) == 0L) return(NULL)
  if (inherits(gd, "Date")) {
    parsed <- gd
  } else if (inherits(gd, "POSIXt")) {
    parsed <- as.Date(gd)
  } else {
    gd_chr <- trimws(as.character(gd))
    gd_chr[!nzchar(gd_chr)] <- NA_character_
    parsed <- suppressWarnings(as.Date(gd_chr, tryFormats = c("%Y-%m-%d", "%Y/%m/%d"), optional = TRUE))
  }
  valid <- parsed[!is.na(parsed) & is.finite(as.numeric(parsed))]
  if (length(valid) == 0L) return(NULL)
  format(max(valid), "%Y-%m-%d")
}

# ESPN uses non-canonical abbreviations in hoopR play-by-play/shots feeds for 6 teams.
ESPN_ABBR_FIXUPS <- c(
  GS   = "GSW",
  SA   = "SAS",
  NY   = "NYK",
  UTAH = "UTA",
  NO   = "NOP",
  WSH  = "WAS"
)

REQUIRED_SHOT_COLS <- c(
  "athlete_id_1",
  "coordinate_x_raw",
  "coordinate_y_raw",
  "type_text",
  "scoring_play",
  "score_value",
  "period_number",
  "clock_display_value"
)

canonical_nba_abbr <- function(x) {
  s <- toupper(trimws(as.character(x)))
  hit <- !is.na(s) & (s %in% names(ESPN_ABBR_FIXUPS))
  s[hit] <- unname(ESPN_ABBR_FIXUPS[s[hit]])
  s
}

derive_shot_team_abbrev <- function(df) {
  n <- nrow(df)
  if (n == 0L) return(character(0))

  abbrev <- if ("team_abbrev" %in% names(df)) {
    canonical_nba_abbr(df$team_abbrev)
  } else {
    rep(NA_character_, n)
  }
  abbrev[is.na(abbrev) | !nzchar(abbrev)] <- NA_character_

  pbp_team_cols <- c("team_id", "home_team_id", "home_team_abbrev", "away_team_id", "away_team_abbrev")
  if (all(pbp_team_cols %in% names(df))) {
    tid  <- trimws(as.character(df$team_id))
    hid  <- trimws(as.character(df$home_team_id))
    aid  <- trimws(as.character(df$away_team_id))
    habb <- canonical_nba_abbr(df$home_team_abbrev)
    aabb <- canonical_nba_abbr(df$away_team_abbrev)

    derived <- rep(NA_character_, n)
    is_home <- !is.na(tid) & nzchar(tid) & !is.na(hid) & nzchar(hid) & (tid == hid)
    is_away <- !is.na(tid) & nzchar(tid) & !is.na(aid) & nzchar(aid) & (tid == aid)
    derived[is_home] <- habb[is_home]
    derived[is_away & !is_home] <- aabb[is_away & !is_home]

    missing_abbrev <- is.na(abbrev)
    abbrev[missing_abbrev] <- derived[missing_abbrev]
  }

  abbrev
}

has_valid_shot_cols <- function(df) {
  is.data.frame(df) && nrow(df) > 0L && all(REQUIRED_SHOT_COLS %in% names(df))
}

normalize_shot_records <- function(df) {
  if (is.null(df) || !is.data.frame(df)) return(NULL)
  out <- df
  if ("shooting_play" %in% names(out)) {
    out <- out[!is.na(out$shooting_play) & as.logical(out$shooting_play), , drop = FALSE]
  }
  if (!("athlete_name_1" %in% names(out))) {
    out$athlete_name_1 <- NA_character_
  }
  out$team_abbrev <- derive_shot_team_abbrev(out)
  out
}

distinct_non_na_games <- function(df) {
  if (is.null(df) || !is.data.frame(df) || nrow(df) == 0L || !("game_id" %in% names(df))) {
    return(character(0))
  }
  g <- trimws(as.character(df$game_id))
  unique(g[!is.na(g) & nzchar(g)])
}

is_pbp_richer_than_shots <- function(pbp_df, shots_df) {
  if ("game_id" %in% names(pbp_df) && "game_id" %in% names(shots_df)) {
    pbp_g <- distinct_non_na_games(pbp_df)
    sh_g  <- distinct_non_na_games(shots_df)
    if (length(pbp_g) > 0L || length(sh_g) > 0L) {
      return(length(pbp_g) > length(sh_g))
    }
  }
  nrow(pbp_df) > nrow(shots_df)
}

default_shot_fetch_fn <- function(sn) {
  if (!requireNamespace("hoopR", quietly = TRUE)) {
    stop("Package 'hoopR' is required to fetch shot charts when cache is absent.", call. = FALSE)
  }
  hoopR::load_nba_shots(seasons = sn)
}

read_rds_safely <- function(path) {
  if (is.null(path) || length(path) != 1L || !nzchar(path) || !file.exists(path)) {
    return(NULL)
  }
  tryCatch(readRDS(path), error = function(e) {
    cat(sprintf(">>> [WARN] Failed to read RDS cache (%s): %s\n", path, e$message))
    NULL
  })
}

# Prefer a richer/fresher nba_pbp_<season>.rds cache when nba_shots_<season>.rds
# is absent or trails in game/row coverage; preserve fetch_fn + shots_cache_path
# when neither cache is usable.
load_shot_records <- function(
  shots_cache_path,
  pbp_cache_path = NULL,
  season = CURRENT_SEASON,
  fetch_fn = NULL
) {
  season <- as.integer(season)
  if (is.null(pbp_cache_path)) {
    pbp_cache_path <- file.path(dirname(shots_cache_path), sprintf("nba_pbp_%d.rds", season))
  }
  if (is.null(fetch_fn)) {
    fetch_fn <- default_shot_fetch_fn
  }

  shots_raw <- read_rds_safely(shots_cache_path)
  pbp_raw   <- read_rds_safely(pbp_cache_path)

  shots_norm <- if (has_valid_shot_cols(shots_raw)) normalize_shot_records(shots_raw) else NULL
  shots_ok   <- !is.null(shots_norm) && nrow(shots_norm) > 0L

  pbp_norm <- if (has_valid_shot_cols(pbp_raw)) normalize_shot_records(pbp_raw) else NULL
  pbp_ok   <- !is.null(pbp_norm) && nrow(pbp_norm) > 0L

  if (pbp_ok && (!shots_ok || is_pbp_richer_than_shots(pbp_norm, shots_norm))) {
    if (shots_ok) {
      cat(sprintf(
        ">>> Loading shot data from PBP cache (%s; %d games / %d rows vs shots cache %d games / %d rows)...\n",
        pbp_cache_path,
        length(distinct_non_na_games(pbp_norm)), nrow(pbp_norm),
        length(distinct_non_na_games(shots_norm)), nrow(shots_norm)
      ))
    } else {
      cat(sprintf(">>> Loading shot data from PBP cache (%s)...\n", pbp_cache_path))
    }
    return(pbp_norm)
  }

  if (file.exists(shots_cache_path) && !is.null(shots_raw)) {
    cat(sprintf(">>> Loading shot data from local cache (%s)...\n", shots_cache_path))
    if (shots_ok) return(shots_norm)
    return(shots_raw)
  }

  cat(sprintf(">>> Fetching season %d NBA shot records via hoopR...\n", season))
  fetched <- tryCatch({
    s <- fetch_fn(season)
    if (!is.null(s) && nrow(s) > 0) {
      if (!dir.exists(dirname(shots_cache_path))) {
        dir.create(dirname(shots_cache_path), recursive = TRUE, showWarnings = FALSE)
      }
      saveRDS(s, shots_cache_path)
    }
    s
  }, error = function(e) {
    cat(sprintf(">>> [WARN] Failed to load hoopR shots: %s\n", e$message))
    NULL
  })

  if (has_valid_shot_cols(fetched)) normalize_shot_records(fetched) else fetched
}

build_shot_chart_dataset <- function(
  season = NULL,
  cache_dir = CACHE_DIR,
  web_data_dir = WEB_DATA_DIR,
  players_json_path = file.path(web_data_dir, "projections_season_players.json"),
  shots_cache_path = NULL,
  fetch_fn = NULL,
  pbp_cache_path = NULL
) {
  if (is.null(season)) {
    season <- resolve_shot_chart_season(CURRENT_SEASON)
  } else {
    season <- as.integer(season)
  }
  if (is.null(shots_cache_path)) {
    shots_cache_path <- file.path(cache_dir, sprintf("nba_shots_%d.rds", season))
  }
  if (is.null(pbp_cache_path)) {
    pbp_cache_path <- file.path(dirname(shots_cache_path), sprintf("nba_pbp_%d.rds", season))
  }
  if (is.null(fetch_fn)) {
    fetch_fn <- default_shot_fetch_fn
  }

  cat(">>> [SHOT CHARTS] Loading rotation player catalog from Next.js web app...\n")
  if (!file.exists(players_json_path)) {
    stop(sprintf("Missing projections_season_players.json at %s", players_json_path), call. = FALSE)
  }

  players_df <- fromJSON(players_json_path)
  cat(sprintf(">>> Loaded %d rotation players.\n", nrow(players_df)))

  # 1. Load or fetch shot data
  raw_shots <- load_shot_records(
    shots_cache_path = shots_cache_path,
    pbp_cache_path = pbp_cache_path,
    season = season,
    fetch_fn = fetch_fn
  )

  if (is.null(raw_shots) || nrow(raw_shots) == 0) {
    stop("Could not obtain shot data.", call. = FALSE)
  }

  cat(sprintf(">>> Total raw shot records: %d\n", nrow(raw_shots)))

  # 2. Filter to field goal attempts & classify 14 zones
  fga_shots <- raw_shots %>%
    filter(
      !is.na(athlete_id_1),
      nzchar(trimws(as.character(athlete_id_1))),
      !is.na(coordinate_x_raw),
      !is.na(coordinate_y_raw),
      score_value %in% c(0, 2, 3) | scoring_play
    ) %>%
    filter(!grepl("Free Throw", type_text, ignore.case = TRUE))

  if (nrow(fga_shots) == 0L) {
    stop("No valid field goal attempts found in shot data.", call. = FALSE)
  }

  fga_shots <- fga_shots %>%
    mutate(
      athlete_id = as.character(athlete_id_1),
      clock = normalize_clock(clock_display_value),
      # Court coordinate transformation: width 0..50 -> -25..25; length from baseline 0..47
      # Note: ESPN raw tracking coordinates measure y from the backboard plane (rim at y=1.25),
      # whereas regulation NBA half-court measures y from baseline (4.0 ft behind backboard, rim at y=5.25).
      # Adding +4.0 ft aligns all shots perfectly with regulation court geometry.
      x = round(coordinate_x_raw - 25.0, 1),
      y = round(pmax(0, pmin(47, coordinate_y_raw + 4.0)), 1),
      dist = round(sqrt(x^2 + (y - 5.25)^2), 1),
      made = !is.na(scoring_play) & as.logical(scoring_play),
      val = ifelse((!is.na(score_value) & score_value == 3) | (dist >= 23.5 & !grepl("Free Throw", type_text)), 3, 2),
      zone = as.character(mapply(classify_14_zones, x, y, dist, val, USE.NAMES = FALSE))
    )

  cat(sprintf(">>> Valid Field Goal Attempts: %d\n", nrow(fga_shots)))

  # 3. Calculate League Averages per Zone
  league_averages <- fga_shots %>%
    group_by(zone) %>%
    summarise(
      total_fga = n(),
      total_fgm = sum(made),
      lg_fg_pct = round(total_fgm / total_fga, 3),
      .groups = "drop"
    )

  cat(">>> League Baselines across 14 Discrete Zones:\n")
  print(league_averages)

  # 4. Filter shots for our rotation players
  rotation_player_ids <- unique(as.character(players_df$player_id))
  player_shots_matched <- fga_shots %>%
    filter(athlete_id %in% rotation_player_ids) %>%
    select(
      athlete_id,
      player_name = athlete_name_1,
      team_abbrev,
      period = period_number,
      clock = clock,
      type = type_text,
      x,
      y,
      dist,
      val,
      made,
      zone
    )

  cat(sprintf(">>> Matched %d shots across rotation players.\n", nrow(player_shots_matched)))

  # Create output directories in web app
  if (!dir.exists(web_data_dir)) dir.create(web_data_dir, recursive = TRUE)
  out_dir <- file.path(web_data_dir, "shots")
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

  # Which NBA season(s) these shots were actually taken in. Read off the data rather
  # than restated from `season`, so the label cannot drift away from the file
  # that is loaded. hoopR's shot `season` is the END year (e.g. 2027 => 2026-2027).
  shot_season_label <- local({
    yrs <- if ("season" %in% names(raw_shots)) {
      sort(unique(suppressWarnings(as.integer(raw_shots$season))))
    } else {
      integer(0)
    }
    yrs <- yrs[!is.na(yrs)]
    if (length(yrs) == 0) yrs <- season
    paste(sprintf("%d-%d", yrs - 1L, yrs), collapse = " + ")
  })
  cat(sprintf(">>> [SHOT CHARTS] Shot sample is from the %s season.\n", shot_season_label))

  generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  through_date <- extract_through_date(raw_shots)

  # Save league metadata
  meta_path <- file.path(web_data_dir, "shots_metadata.json")
  meta_payload <- list(
    generated_at = generated_at,
    updated_at = generated_at,
    through_date = through_date,
    total_shots_sampled = nrow(fga_shots),
    source_season_label = shot_season_label,
    league_averages = league_averages,
    zones = c(
      "Restricted Area",
      "Paint (Low / Floater)",
      "Paint (High / FT)",
      "Left Baseline Mid",
      "Right Baseline Mid",
      "Left Wing Mid",
      "Center Mid",
      "Right Wing Mid",
      "Left Corner 3",
      "Right Corner 3",
      "Left Wing 3",
      "Center 3",
      "Right Wing 3",
      "Deep / Logo 3"
    )
  )
  write_json(meta_payload, meta_path, auto_unbox = TRUE, pretty = TRUE, na = "null", null = "null")
  cat(sprintf(">>> Wrote 14-zone metadata to %s\n", meta_path))

  # Group shots by player and export per-player JSON
  player_groups <- split(player_shots_matched, player_shots_matched$athlete_id)

  # Prune per-player files left by an earlier build that are no longer in this run's
  # catalog. Without this, a changed rotation (or a player dropping below the shot
  # minimum) leaves stale <id>.json files behind, and shots_index.json stops matching
  # what is actually on disk.
  stale_files <- setdiff(
    sub("\\.json$", "", list.files(out_dir, pattern = "\\.json$")),
    names(player_groups)
  )
  if (length(stale_files) > 0) {
    unlink(file.path(out_dir, paste0(stale_files, ".json")))
    cat(sprintf(">>> Pruned %d stale per-player shot files.\n", length(stale_files)))
  }

  cat(sprintf(">>> Writing per-player shot files for %d players...\n", length(player_groups)))

  player_catalog <- list()

  for (pid in names(player_groups)) {
    p_shots <- player_groups[[pid]]

    # Ground truth: Lookup player in active rotation catalog
    p_meta <- players_df %>% filter(as.character(player_id) == pid)
    if (nrow(p_meta) > 0) {
      p_name <- p_meta$player_name[1]
      p_team <- canonical_nba_abbr(p_meta$team[1])
    } else {
      p_name <- p_shots$player_name[1]
      p_team <- canonical_nba_abbr(p_shots$team_abbrev[1])
    }

    clean_shots <- p_shots %>%
      select(x, y, dist, val, made, zone, type, period, clock)

    player_catalog[[pid]] <- list(
      player_id = pid,
      player_name = p_name,
      team = p_team,
      total_shots = nrow(clean_shots)
    )

    player_file <- file.path(out_dir, paste0(pid, ".json"))
    write_json(list(
      player_id = pid,
      player_name = p_name,
      team = p_team,
      total_shots = nrow(clean_shots),
      shots = clean_shots
    ), player_file, auto_unbox = TRUE, na = "null", null = "null")
  }

  # Sort catalog by Team, then by Shot Volume
  if (length(player_catalog) > 0L) {
    catalog_df <- bind_rows(player_catalog) %>%
      arrange(team, desc(total_shots), player_name)
  } else {
    catalog_df <- tibble::tibble(
      player_id = character(0),
      player_name = character(0),
      team = character(0),
      total_shots = integer(0)
    )
  }

  index_path <- file.path(web_data_dir, "shots_index.json")
  write_json(catalog_df, index_path, auto_unbox = TRUE, pretty = TRUE, na = "null", null = "null")
  cat(sprintf(">>> Wrote shot chart catalog with %d players to %s\n", nrow(catalog_df), index_path))
  cat(">>> [SUCCESS] 14-Zone dataset generation complete!\n")

  invisible(list(
    metadata = meta_payload,
    catalog = catalog_df,
    metadata_path = meta_path,
    index_path = index_path,
    shots_dir = out_dir
  ))
}

# Set NBA_SKIP_STAGE_AUTORUN=1 to source this file for its definitions alone;
# run_full_pipeline.R relies on this call, so it stays on by default.
if (!nzchar(Sys.getenv("NBA_SKIP_STAGE_AUTORUN"))) {
  build_shot_chart_dataset()
}
