# ==============================================================================
# build_game_details.R
# Purely empirical post-game box score, Four Factors, efficiency metrics,
# context splits, Hollinger Game Score, and Phase 2 explainability payload
# builder (Matchup Game Detail v3 -- Phases 1 & 2).
#
# Designed to be sourced without side effects by build_matchups_dataset.R and
# standalone unit/contract tests. Reads only caller-supplied data frames (no
# hidden network calls, no setwd(), no top-level execution).
# ==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

GAME_DETAIL_SCHEMA_VERSION <- "1.0"
GAME_DETAIL_HCA_POINTS <- 2.40
GAME_DETAIL_ENSEMBLE_WEIGHTS <- c(
  bottom_up    = 0.35,
  rapm         = 0.25,
  shot_fatigue = 0.20,
  embeddings   = 0.20
)
GAME_DETAIL_LOG_SOURCES <- c("LOGGED_PREGAME", "BACKTEST_PREWEEK", "BACKTEST_SEEDED")
GAME_DETAIL_WATERFALL_SPECS <- list(
  list(key = "bottom_up",    label = "Bottom-up BPM"),
  list(key = "rapm",         label = "Regularized APM"),
  list(key = "shot_fatigue", label = "Shot quality & fatigue"),
  list(key = "embeddings",   label = "Player embeddings"),
  list(key = "home_court",   label = "Home court advantage"),
  list(key = "schedule",     label = "Schedule & travel")
)
GAME_DETAIL_ENTERING_FACTOR_KEYS <- c("efg_pct", "tov_pct", "oreb_pct", "fta_rate", "ortg")

# ESPN uses non-canonical abbreviations in hoopR team_box/player_box for 6 teams.
ESPN_ABBR_FIXUPS <- c(
  GS   = "GSW",
  SA   = "SAS",
  NY   = "NYK",
  UTAH = "UTA",
  NO   = "NOP",
  WSH  = "WAS"
)

PLAYER_COUNTING_STAT_COLS <- c(
  "points",
  "rebounds",
  "offensive_rebounds",
  "defensive_rebounds",
  "assists",
  "steals",
  "blocks",
  "turnovers",
  "fouls",
  "field_goals_made",
  "field_goals_attempted",
  "three_point_field_goals_made",
  "three_point_field_goals_attempted",
  "free_throws_made",
  "free_throws_attempted"
)

`%||%` <- function(x, y) if (is.null(x)) y else x

# Normalize raw ESPN/hoopR team abbreviations to the canonical 3-letter codes.
canonical_nba_abbr <- function(x) {
  s <- toupper(trimws(as.character(x)))
  hit <- s %in% names(ESPN_ABBR_FIXUPS)
  s[hit] <- unname(ESPN_ABBR_FIXUPS[s[hit]])
  s
}

# Parse character-encoded numeric fields (e.g. "62", "-14", "+5") safely to numeric.
parse_num_or_na <- function(x) {
  if (is.null(x) || length(x) == 0L) return(numeric(0))
  if (is.numeric(x)) return(as.numeric(x))
  s <- trimws(as.character(x))
  s <- sub("^\\+", "", s)
  s[!nzchar(s)] <- NA_character_
  suppressWarnings(as.numeric(s))
}

num_or_null <- function(x, digits = NULL) {
  if (is.null(x) || length(x) != 1L || is.na(x) || !is.finite(x)) return(NULL)
  v <- as.numeric(x)
  if (!is.null(digits)) v <- round(v, digits)
  if (!is.finite(v)) return(NULL)
  v
}

int_or_null <- function(x) {
  if (is.null(x) || length(x) != 1L || is.na(x) || !is.finite(x)) return(NULL)
  as.integer(round(as.numeric(x)))
}

chr_or_null <- function(x) {
  if (is.null(x) || length(x) != 1L || is.na(x)) return(NULL)
  s <- trimws(as.character(x))
  if (!nzchar(s)) return(NULL)
  s
}

zero_if_na_int <- function(x) {
  v <- parse_num_or_na(x)
  v[is.na(v) | !is.finite(v)] <- 0
  as.integer(round(v))
}

# Safe scaled ratio: returns NULL when numerator/denominator is missing, non-finite, or <= 0.
safe_ratio <- function(num, den, scale = 100, digits = 1L) {
  if (is.null(num) || is.null(den) || length(num) != 1L || length(den) != 1L) {
    return(NULL)
  }
  num <- as.numeric(num)
  den <- as.numeric(den)
  if (is.na(num) || is.na(den) || !is.finite(num) || !is.finite(den) || den <= 0) {
    return(NULL)
  }
  val <- scale * (num / den)
  if (!is.finite(val)) return(NULL)
  round(val, digits)
}

# Locale-independent English weekday & slate label formatting.
format_weekday_en <- function(d) {
  d <- as.Date(d)
  if (is.na(d)) return(NA_character_)
  c("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")[as.POSIXlt(d)$wday + 1L]
}

format_month_day_en <- function(d) {
  d <- as.Date(d)
  lt <- as.POSIXlt(d)
  mon <- c("Jan", "Feb", "Mar", "Apr", "May", "Jun",
           "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")[lt$mon + 1L]
  sprintf("%s %d", mon, as.integer(lt$mday))
}

format_slate_label_en <- function(slate, start_date, end_date) {
  sprintf("Week %d \u00b7 %s \u2013 %s",
          as.integer(slate),
          format_month_day_en(start_date),
          format_month_day_en(end_date))
}

#' Compute John Hollinger's Game Score (GmSc) for player box rows.
#'
#' Formula: PTS + 0.4*FGM - 0.7*FGA - 0.4*(FTA - FTM) + 0.7*OREB + 0.3*DREB
#'          + STL + 0.7*AST + 0.7*BLK - 0.4*PF - TOV.
compute_hollinger_game_score <- function(pts, fgm, fga, ftm, fta,
                                         oreb, dreb, stl, ast, blk, pf, tov) {
  raw <- as.numeric(pts) +
    0.4 * as.numeric(fgm) -
    0.7 * as.numeric(fga) -
    0.4 * (as.numeric(fta) - as.numeric(ftm)) +
    0.7 * as.numeric(oreb) +
    0.3 * as.numeric(dreb) +
    as.numeric(stl) +
    0.7 * as.numeric(ast) +
    0.7 * as.numeric(blk) -
    0.4 * as.numeric(pf) -
    as.numeric(tov)
  round(raw, 1L)
}

.col_or_default <- function(df, col, default) {
  if (col %in% names(df)) df[[col]] else rep(default, nrow(df))
}

#' Classify one team's player box rows into active and inactive lists.
#'
#' Inactive rule (v3 section 4.1.2): did_not_play is TRUE, or minutes is NA, or
#' minutes == 0 AND every counting stat is 0. Never classifies via `reason`
#' (ESPN places "COACH'S DECISION" on active players).
classify_game_players <- function(pb_team, team_abbr = NULL) {
  if (is.null(pb_team) || nrow(pb_team) == 0L) {
    return(list(
      players = list(),
      inactive = list(),
      active_minutes = 0,
      bench_points = 0L,
      top_performer_candidates = list()
    ))
  }

  n <- nrow(pb_team)
  dnp_raw <- .col_or_default(pb_team, "did_not_play", FALSE)
  dnp_flag <- !is.na(dnp_raw) & as.logical(dnp_raw)
  mins_raw <- parse_num_or_na(.col_or_default(pb_team, "minutes", NA_real_))

  all_zero <- rep(TRUE, n)
  for (cc in PLAYER_COUNTING_STAT_COLS) {
    if (cc %in% names(pb_team)) {
      vals <- parse_num_or_na(pb_team[[cc]])
      all_zero <- all_zero & (is.na(vals) | vals == 0)
    }
  }

  is_inactive <- dnp_flag | is.na(mins_raw) | (mins_raw == 0 & all_zero)
  act_df <- pb_team[!is_inactive, , drop = FALSE]
  inact_df <- pb_team[is_inactive, , drop = FALSE]

  # Build active player rows, sorted: starter DESC, minutes DESC, points DESC, playerName ASC.
  players_list <- list()
  candidates <- list()
  active_minutes <- 0
  bench_points <- 0L

  if (nrow(act_df) > 0L) {
    starter_raw <- .col_or_default(act_df, "starter", FALSE)
    act_starter <- !is.na(starter_raw) & as.logical(starter_raw)
    act_min <- parse_num_or_na(.col_or_default(act_df, "minutes", 0))
    act_min[is.na(act_min)] <- 0
    act_pts <- zero_if_na_int(.col_or_default(act_df, "points", 0L))
    act_name <- as.character(.col_or_default(act_df, "athlete_display_name", ""))

    ord <- order(-as.integer(act_starter), -act_min, -act_pts, act_name)
    act_df <- act_df[ord, , drop = FALSE]
    act_starter <- act_starter[ord]
    act_min <- act_min[ord]
    act_pts <- act_pts[ord]
    act_name <- act_name[ord]

    active_minutes <- sum(act_min, na.rm = TRUE)
    bench_points <- as.integer(sum(act_pts[!act_starter], na.rm = TRUE))

    act_id <- as.character(.col_or_default(act_df, "athlete_id", ""))
    act_short <- as.character(.col_or_default(act_df, "athlete_short_name", NA_character_))
    act_jersey <- .col_or_default(act_df, "athlete_jersey", NA_character_)
    act_pos <- if ("athlete_position_abbreviation" %in% names(act_df)) {
      act_df$athlete_position_abbreviation
    } else {
      .col_or_default(act_df, "athlete_position_name", NA_character_)
    }
    act_pm <- parse_num_or_na(.col_or_default(act_df, "plus_minus", NA_real_))

    oreb <- zero_if_na_int(.col_or_default(act_df, "offensive_rebounds", 0L))
    dreb <- zero_if_na_int(.col_or_default(act_df, "defensive_rebounds", 0L))
    reb  <- zero_if_na_int(.col_or_default(act_df, "rebounds", 0L))
    ast  <- zero_if_na_int(.col_or_default(act_df, "assists", 0L))
    stl  <- zero_if_na_int(.col_or_default(act_df, "steals", 0L))
    blk  <- zero_if_na_int(.col_or_default(act_df, "blocks", 0L))
    tov  <- zero_if_na_int(.col_or_default(act_df, "turnovers", 0L))
    pf   <- zero_if_na_int(.col_or_default(act_df, "fouls", 0L))
    fgm  <- zero_if_na_int(.col_or_default(act_df, "field_goals_made", 0L))
    fga  <- zero_if_na_int(.col_or_default(act_df, "field_goals_attempted", 0L))
    fg3m <- zero_if_na_int(.col_or_default(act_df, "three_point_field_goals_made", 0L))
    fg3a <- zero_if_na_int(.col_or_default(act_df, "three_point_field_goals_attempted", 0L))
    ftm  <- zero_if_na_int(.col_or_default(act_df, "free_throws_made", 0L))
    fta  <- zero_if_na_int(.col_or_default(act_df, "free_throws_attempted", 0L))

    gmsc <- compute_hollinger_game_score(
      pts = act_pts, fgm = fgm, fga = fga, ftm = ftm, fta = fta,
      oreb = oreb, dreb = dreb, stl = stl, ast = ast, blk = blk,
      pf = pf, tov = tov
    )

    resolved_abbr <- if (!is.null(team_abbr)) {
      as.character(team_abbr)
    } else if ("team_abbreviation" %in% names(act_df)) {
      canonical_nba_abbr(act_df$team_abbreviation[1])
    } else {
      ""
    }

    players_list <- vector("list", nrow(act_df))
    for (k in seq_len(nrow(act_df))) {
      sname <- chr_or_null(act_short[k]) %||% act_name[k]
      row_obj <- list(
        playerId   = act_id[k],
        playerName = act_name[k],
        short_name = sname,
        jersey     = chr_or_null(act_jersey[k]),
        position   = chr_or_null(act_pos[k]),
        starter    = isTRUE(act_starter[k]),
        minutes    = as.numeric(act_min[k]),
        points     = as.integer(act_pts[k]),
        oreb       = as.integer(oreb[k]),
        dreb       = as.integer(dreb[k]),
        reb        = as.integer(reb[k]),
        ast        = as.integer(ast[k]),
        stl        = as.integer(stl[k]),
        blk        = as.integer(blk[k]),
        tov        = as.integer(tov[k]),
        pf         = as.integer(pf[k]),
        plus_minus = num_or_null(act_pm[k]),
        fgm        = as.integer(fgm[k]),
        fga        = as.integer(fga[k]),
        fg_pct     = safe_ratio(fgm[k], fga[k], 100, 1L),
        fg3m       = as.integer(fg3m[k]),
        fg3a       = as.integer(fg3a[k]),
        fg3_pct    = safe_ratio(fg3m[k], fg3a[k], 100, 1L),
        ftm        = as.integer(ftm[k]),
        fta        = as.integer(fta[k]),
        ft_pct     = safe_ratio(ftm[k], fta[k], 100, 1L),
        efg_pct    = safe_ratio(fgm[k] + 0.5 * fg3m[k], fga[k], 100, 1L),
        ts_pct     = safe_ratio(act_pts[k], 2 * (fga[k] + 0.44 * fta[k]), 100, 1L),
        game_score = as.numeric(gmsc[k])
      )
      players_list[[k]] <- row_obj

      if (act_min[k] > 0) {
        candidates[[length(candidates) + 1L]] <- list(
          teamAbbr   = resolved_abbr,
          playerId   = act_id[k],
          playerName = act_name[k],
          points     = as.integer(act_pts[k]),
          reb        = as.integer(reb[k]),
          ast        = as.integer(ast[k]),
          minutes    = as.numeric(act_min[k]),
          game_score = as.numeric(gmsc[k])
        )
      }
    }
  }

  # Build inactive player rows, sorted by playerName ASC.
  inactive_list <- list()
  if (nrow(inact_df) > 0L) {
    inact_name <- as.character(.col_or_default(inact_df, "athlete_display_name", ""))
    inact_ord <- order(inact_name)
    inact_df <- inact_df[inact_ord, , drop = FALSE]
    inact_name <- inact_name[inact_ord]
    inact_id <- as.character(.col_or_default(inact_df, "athlete_id", ""))
    inact_pos <- if ("athlete_position_abbreviation" %in% names(inact_df)) {
      inact_df$athlete_position_abbreviation
    } else {
      .col_or_default(inact_df, "athlete_position_name", NA_character_)
    }
    inact_reason <- .col_or_default(inact_df, "reason", NA_character_)

    inactive_list <- vector("list", nrow(inact_df))
    for (k in seq_len(nrow(inact_df))) {
      inactive_list[[k]] <- list(
        playerId   = inact_id[k],
        playerName = inact_name[k],
        position   = chr_or_null(inact_pos[k]),
        reason     = chr_or_null(inact_reason[k])
      )
    }
  }

  list(
    players = unname(players_list),
    inactive = unname(inactive_list),
    active_minutes = active_minutes,
    bench_points = bench_points,
    top_performer_candidates = unname(candidates)
  )
}

.extract_team_counting_stats <- function(tb_row) {
  get_num <- function(col) {
    if (col %in% names(tb_row)) parse_num_or_na(tb_row[[col]][1]) else NA_real_
  }
  get_int <- function(col) int_or_null(get_num(col))

  list(
    points            = get_int("team_score"),
    fgm               = get_int("field_goals_made"),
    fga               = get_int("field_goals_attempted"),
    fg3m              = get_int("three_point_field_goals_made"),
    fg3a              = get_int("three_point_field_goals_attempted"),
    ftm               = get_int("free_throws_made"),
    fta               = get_int("free_throws_attempted"),
    oreb              = get_int("offensive_rebounds"),
    dreb              = get_int("defensive_rebounds"),
    reb               = get_int("total_rebounds"),
    ast               = get_int("assists"),
    stl               = get_int("steals"),
    blk               = get_int("blocks"),
    tov               = get_int("turnovers"),
    team_tov          = get_int("team_turnovers"),
    total_tov         = get_int("total_turnovers"),
    pf                = get_int("fouls"),
    points_in_paint   = get_int("points_in_paint"),
    fast_break_points = get_int("fast_break_points"),
    turnover_points   = get_int("turnover_points"),
    largest_lead      = get_int("largest_lead")
  )
}

# Dean Oliver possession estimate averaged across both teams using total_turnovers.
.compute_dean_oliver_possessions <- function(away_stats, home_stats) {
  req <- c("fga", "fgm", "fta", "oreb", "dreb", "total_tov")
  for (k in req) {
    if (is.null(away_stats[[k]]) || is.null(home_stats[[k]])) return(NA_real_)
  }
  denom_h <- home_stats$oreb + away_stats$dreb
  denom_a <- away_stats$oreb + home_stats$dreb
  if (!is.finite(denom_h) || denom_h <= 0 || !is.finite(denom_a) || denom_a <= 0) {
    return(NA_real_)
  }
  poss_h <- home_stats$fga + 0.44 * home_stats$fta -
    1.07 * (home_stats$oreb / denom_h) * (home_stats$fga - home_stats$fgm) +
    home_stats$total_tov
  poss_a <- away_stats$fga + 0.44 * away_stats$fta -
    1.07 * (away_stats$oreb / denom_a) * (away_stats$fga - away_stats$fgm) +
    away_stats$total_tov
  poss <- 0.5 * (poss_h + poss_a)
  if (!is.finite(poss) || poss <= 0) return(NA_real_)
  poss
}

.build_team_box_totals <- function(team_stats, opp_stats, player_minutes,
                                   poss_raw, game_minutes) {
  fgm  <- team_stats$fgm
  fga  <- team_stats$fga
  fg3m <- team_stats$fg3m
  fg3a <- team_stats$fg3a
  ftm  <- team_stats$ftm
  fta  <- team_stats$fta
  pts  <- team_stats$points

  efg_num <- if (!is.null(fgm) && !is.null(fg3m)) fgm + 0.5 * fg3m else NULL
  ts_den  <- if (!is.null(fga) && !is.null(fta)) 2 * (fga + 0.44 * fta) else NULL

  list(
    minutes         = round(as.numeric(player_minutes), 1L),
    points          = as.integer(pts %||% 0L),
    fgm             = as.integer(fgm %||% 0L),
    fga             = as.integer(fga %||% 0L),
    fg_pct          = safe_ratio(fgm, fga, 100, 1L),
    fg3m            = as.integer(fg3m %||% 0L),
    fg3a            = as.integer(fg3a %||% 0L),
    fg3_pct         = safe_ratio(fg3m, fg3a, 100, 1L),
    ftm             = as.integer(ftm %||% 0L),
    fta             = as.integer(fta %||% 0L),
    ft_pct          = safe_ratio(ftm, fta, 100, 1L),
    oreb            = as.integer(team_stats$oreb %||% 0L),
    dreb            = as.integer(team_stats$dreb %||% 0L),
    reb             = as.integer(team_stats$reb %||% 0L),
    ast             = as.integer(team_stats$ast %||% 0L),
    stl             = as.integer(team_stats$stl %||% 0L),
    blk             = as.integer(team_stats$blk %||% 0L),
    tov             = as.integer(team_stats$tov %||% 0L),
    team_tov        = as.integer(team_stats$team_tov %||% 0L),
    total_tov       = as.integer(team_stats$total_tov %||% 0L),
    pf              = as.integer(team_stats$pf %||% 0L),
    efg_pct         = safe_ratio(efg_num, fga, 100, 1L),
    ts_pct          = safe_ratio(pts, ts_den, 100, 1L),
    possessions_est = num_or_null(poss_raw, 1L),
    ortg            = safe_ratio(pts, poss_raw, 100, 1L),
    drtg            = safe_ratio(opp_stats$points, poss_raw, 100, 1L),
    pace            = safe_ratio(48 * poss_raw, game_minutes, 1, 1L)
  )
}

.build_efficiency_factors <- function(away_totals, home_totals, away_stats, home_stats) {
  calc_tov_pct <- function(s) {
    if (is.null(s$total_tov) || is.null(s$fga) || is.null(s$fta)) return(NULL)
    safe_ratio(s$total_tov, s$fga + 0.44 * s$fta + s$total_tov, 100, 1L)
  }
  calc_oreb_pct <- function(s, opp_s) {
    if (is.null(s$oreb) || is.null(opp_s$dreb)) return(NULL)
    safe_ratio(s$oreb, s$oreb + opp_s$dreb, 100, 1L)
  }
  calc_fta_rate <- function(s) {
    if (is.null(s$fta) || is.null(s$fga)) return(NULL)
    safe_ratio(s$fta, s$fga, 100, 1L)
  }

  specs <- list(
    list(
      key = "efg_pct",
      label = "Effective FG%",
      away_value = away_totals$efg_pct,
      home_value = home_totals$efg_pct,
      unit = "pct",
      higher_is_better = TRUE,
      description = "Field-goal percentage adjusted for 3-point makes: 100 * (FGM + 0.5 * FG3M) / FGA."
    ),
    list(
      key = "ts_pct",
      label = "True Shooting %",
      away_value = away_totals$ts_pct,
      home_value = home_totals$ts_pct,
      unit = "pct",
      higher_is_better = TRUE,
      description = "Scoring efficiency across field goals and free throws: 100 * PTS / (2 * (FGA + 0.44 * FTA))."
    ),
    list(
      key = "tov_pct",
      label = "Turnover %",
      away_value = calc_tov_pct(away_stats),
      home_value = calc_tov_pct(home_stats),
      unit = "pct",
      higher_is_better = FALSE,
      description = "Share of possessions ending in a turnover using total turnovers: 100 * TotalTOV / (FGA + 0.44 * FTA + TotalTOV)."
    ),
    list(
      key = "oreb_pct",
      label = "Offensive Rebound %",
      away_value = calc_oreb_pct(away_stats, home_stats),
      home_value = calc_oreb_pct(home_stats, away_stats),
      unit = "pct",
      higher_is_better = TRUE,
      description = "Share of available offensive rebounds grabbed against opponent defensive rebounds: 100 * OREB / (OREB + OppDREB)."
    ),
    list(
      key = "fta_rate",
      label = "Free-throw attempt rate (attempts per 100 field-goal attempts)",
      away_value = calc_fta_rate(away_stats),
      home_value = calc_fta_rate(home_stats),
      unit = "per100fga",
      higher_is_better = TRUE,
      description = "Free-throw attempt rate (attempts per 100 field-goal attempts): 100 * FTA / FGA."
    ),
    list(
      key = "ortg",
      label = "Offensive Rating",
      away_value = away_totals$ortg,
      home_value = home_totals$ortg,
      unit = "per100poss",
      higher_is_better = TRUE,
      description = "Points scored per 100 estimated Dean Oliver possessions: 100 * PTS / Poss."
    ),
    list(
      key = "drtg",
      label = "Defensive Rating",
      away_value = away_totals$drtg,
      home_value = home_totals$drtg,
      unit = "per100poss",
      higher_is_better = FALSE,
      description = "Points allowed per 100 estimated Dean Oliver possessions (equals opponent Offensive Rating)."
    ),
    list(
      key = "pace",
      label = "Pace",
      away_value = away_totals$pace,
      home_value = home_totals$pace,
      unit = "poss48",
      higher_is_better = NULL,
      description = "Estimated Dean Oliver possessions per 48 minutes: 48 * Poss / game_minutes."
    )
  )

  unname(specs)
}

.build_context_splits <- function(away_stats, home_stats, away_bench_pts, home_bench_pts) {
  specs <- list(
    list(key = "points_in_paint",   label = "Points in Paint",      away = away_stats$points_in_paint,   home = home_stats$points_in_paint),
    list(key = "fast_break_points", label = "Fast-Break Points",    away = away_stats$fast_break_points, home = home_stats$fast_break_points),
    list(key = "turnover_points",   label = "Points Off Turnovers", away = away_stats$turnover_points,   home = home_stats$turnover_points),
    list(key = "bench_points",      label = "Bench Points",         away = away_bench_pts,               home = home_bench_pts),
    list(key = "largest_lead",      label = "Largest Lead",         away = away_stats$largest_lead,      home = home_stats$largest_lead),
    list(key = "assists",           label = "Assists",              away = away_stats$ast,               home = home_stats$ast),
    list(key = "steals",            label = "Steals",               away = away_stats$stl,               home = home_stats$stl),
    list(key = "blocks",            label = "Blocks",               away = away_stats$blk,               home = home_stats$blk)
  )

  unname(lapply(specs, function(sp) {
    list(
      key        = sp$key,
      label      = sp$label,
      away_value = sp$away,
      home_value = sp$home
    )
  }))
}

.select_top_performers <- function(candidates, n = 3L) {
  if (length(candidates) == 0L) return(list())
  gmsc <- vapply(candidates, function(c) c$game_score, numeric(1))
  pts  <- vapply(candidates, function(c) c$points, integer(1))
  mins <- vapply(candidates, function(c) c$minutes, numeric(1))
  nm   <- vapply(candidates, function(c) c$playerName, character(1))

  ord <- order(-gmsc, -pts, -mins, nm)
  keep <- head(ord, n)

  unname(lapply(candidates[keep], function(c) {
    list(
      teamAbbr   = c$teamAbbr,
      playerId   = c$playerId,
      playerName = c$playerName,
      points     = c$points,
      reb        = c$reb,
      ast        = c$ast,
      game_score = c$game_score
    )
  }))
}

.split_player_box_sides <- function(pb_game, away_tb, home_tb, away_abbr, home_abbr) {
  if (is.null(pb_game) || nrow(pb_game) == 0L) {
    empty <- pb_game
    return(list(away = empty, home = empty))
  }

  if ("team_id" %in% names(pb_game) && "team_id" %in% names(away_tb) &&
      !is.na(away_tb$team_id[1]) && !is.na(home_tb$team_id[1])) {
    away_id <- as.integer(away_tb$team_id[1])
    home_id <- as.integer(home_tb$team_id[1])
    pb_tid <- suppressWarnings(as.integer(pb_game$team_id))
    return(list(
      away = pb_game[!is.na(pb_tid) & pb_tid == away_id, , drop = FALSE],
      home = pb_game[!is.na(pb_tid) & pb_tid == home_id, , drop = FALSE]
    ))
  }

  if ("home_away" %in% names(pb_game)) {
    ha <- tolower(trimws(as.character(pb_game$home_away)))
    return(list(
      away = pb_game[!is.na(ha) & ha == "away", , drop = FALSE],
      home = pb_game[!is.na(ha) & ha == "home", , drop = FALSE]
    ))
  }

  if ("team_abbreviation" %in% names(pb_game)) {
    pb_abbr <- canonical_nba_abbr(pb_game$team_abbreviation)
    return(list(
      away = pb_game[!is.na(pb_abbr) & pb_abbr == away_abbr, , drop = FALSE],
      home = pb_game[!is.na(pb_abbr) & pb_abbr == home_abbr, , drop = FALSE]
    ))
  }

  empty <- pb_game[0L, , drop = FALSE]
  list(away = empty, home = empty)
}

# ------------------------------------------------------------------------------
# Phase 2: Explainability builders (waterfall, entering baselines, TreeSHAP)
# ------------------------------------------------------------------------------

.get_margin_sigma <- function() {
  if (exists("MARGIN_SIGMA", inherits = TRUE)) {
    v <- suppressWarnings(as.numeric(get("MARGIN_SIGMA", inherits = TRUE)))
    if (length(v) == 1L && is.finite(v) && v > 0) return(v)
  }
  11.8
}

.field_or_null <- function(obj, field) {
  if (is.null(obj) || !(field %in% names(obj))) return(NULL)
  v <- obj[[field]]
  if (is.list(v) && length(v) == 1L) v <- v[[1L]]
  if (length(v) == 0L) return(NULL)
  v[1L]
}

.num_field <- function(obj, field) {
  v <- .field_or_null(obj, field)
  if (is.null(v)) return(NA_real_)
  suppressWarnings(as.numeric(v))
}

.lookup_ensemble_team <- function(ensemble_ratings, team_abbr = NULL, team_name = NULL) {
  if (is.null(ensemble_ratings) || !is.data.frame(ensemble_ratings) || nrow(ensemble_ratings) == 0L) {
    return(NULL)
  }
  abbr <- chr_or_null(team_abbr)
  if (!is.null(abbr) && "team" %in% names(ensemble_ratings)) {
    canon_tbl <- canonical_nba_abbr(ensemble_ratings$team)
    idx <- which(!is.na(canon_tbl) & canon_tbl == canonical_nba_abbr(abbr))
    if (length(idx) >= 1L) return(ensemble_ratings[idx[1L], , drop = FALSE])
  }
  nm <- chr_or_null(team_name)
  if (!is.null(nm) && "team_name" %in% names(ensemble_ratings)) {
    tbl_nm <- trimws(as.character(ensemble_ratings$team_name))
    idx <- which(!is.na(tbl_nm) & tbl_nm == nm)
    if (length(idx) >= 1L) return(ensemble_ratings[idx[1L], , drop = FALSE])
  }
  NULL
}

.assemble_waterfall_steps <- function(step_points, step_details, target_margin,
                                      context_label = "waterfall") {
  rounded_pts <- round(as.numeric(step_points), 2L)
  rounded_pts[abs(rounded_pts) < 1e-12] <- 0
  steps <- vector("list", 6L)
  for (idx in seq_len(6L)) {
    steps[[idx]] <- list(
      key    = GAME_DETAIL_WATERFALL_SPECS[[idx]]$key,
      label  = GAME_DETAIL_WATERFALL_SPECS[[idx]]$label,
      points = unname(rounded_pts[idx]),
      detail = step_details[[idx]]
    )
  }

  target_rounded <- round(as.numeric(target_margin), 2L)
  if (abs(target_rounded) < 1e-12) target_rounded <- 0
  step_sum <- round(sum(rounded_pts), 2L)
  residual <- round(target_rounded - step_sum, 2L)
  if (abs(residual) < 1e-12) residual <- 0

  if (abs(residual) > 0.02 + 1e-9) {
    stop(sprintf(
      "%s attribution drift: |predicted_margin (%.2f) - sum(6 steps) (%.2f)| = %.2f > 0.02",
      context_label, target_rounded, step_sum, abs(residual)
    ))
  }
  if (abs(residual) >= 0.005) {
    steps[[7L]] <- list(
      key    = "rounding",
      label  = "Component rounding",
      points = residual,
      detail = "2-decimal component rounding residual"
    )
  }
  unname(steps)
}

.split_team_box_sides <- function(tb_g) {
  away_tb <- if (!is.null(tb_g) && nrow(tb_g) > 0L && "team_home_away" %in% names(tb_g)) {
    tb_g[tolower(as.character(tb_g$team_home_away)) == "away", , drop = FALSE]
  } else {
    data.frame()
  }
  home_tb <- if (!is.null(tb_g) && nrow(tb_g) > 0L && "team_home_away" %in% names(tb_g)) {
    tb_g[tolower(as.character(tb_g$team_home_away)) == "home", , drop = FALSE]
  } else {
    data.frame()
  }
  if (nrow(away_tb) > 1L) away_tb <- away_tb[1L, , drop = FALSE]
  if (nrow(home_tb) > 1L) home_tb <- home_tb[1L, , drop = FALSE]
  list(away = away_tb, home = home_tb)
}

#' Compute empirical Four Factors + ORtg efficiency factors from a single game's
#' two-row team_box data frame. Shared by build_game_detail_payload() and
#' build_matchups_dataset.R so realized factors in entering_baselines match
#' game details identically.
compute_game_realized_factors <- function(team_box_game) {
  sides <- .split_team_box_sides(team_box_game)
  if (nrow(sides$away) != 1L || nrow(sides$home) != 1L) return(NULL)
  away_score <- parse_num_or_na(.col_or_default(sides$away, "team_score", NA_real_)[1L])
  home_score <- parse_num_or_na(.col_or_default(sides$home, "team_score", NA_real_)[1L])
  if (is.na(away_score) || is.na(home_score)) return(NULL)

  away_stats <- .extract_team_counting_stats(sides$away)
  home_stats <- .extract_team_counting_stats(sides$home)
  poss_raw <- .compute_dean_oliver_possessions(away_stats, home_stats)
  away_totals <- .build_team_box_totals(away_stats, home_stats, 240, poss_raw, 48)
  home_totals <- .build_team_box_totals(home_stats, away_stats, 240, poss_raw, 48)
  .build_efficiency_factors(away_totals, home_totals, away_stats, home_stats)
}

#' Build a strictly attributed 6-step (plus optional rounding residual) margin
#' waterfall. Never substitutes current ensemble ratings onto a logged forecast.
build_margin_waterfall <- function(game_row, ensemble_ratings = NULL, log_row = NULL) {
  basis <- chr_or_null(.field_or_null(game_row, "projection_basis"))
  if (is.null(basis) || identical(basis, "team_rating_differential")) return(NULL)

  gid_label <- chr_or_null(.field_or_null(game_row, "game_id")) %||%
    chr_or_null(.field_or_null(game_row, "espn_game_id")) %||% "?"

  if (identical(basis, "primary_ensemble")) {
    if (is.null(ensemble_ratings) || !is.data.frame(ensemble_ratings) || nrow(ensemble_ratings) == 0L) {
      return(NULL)
    }
    home_abbr <- chr_or_null(.field_or_null(game_row, "home_team"))
    away_abbr <- chr_or_null(.field_or_null(game_row, "away_team"))
    home_name <- chr_or_null(.field_or_null(game_row, "home_name")) %||%
      chr_or_null(.field_or_null(game_row, "home_team_name"))
    away_name <- chr_or_null(.field_or_null(game_row, "away_name")) %||%
      chr_or_null(.field_or_null(game_row, "away_team_name"))

    h_row <- .lookup_ensemble_team(ensemble_ratings, home_abbr, home_name)
    a_row <- .lookup_ensemble_team(ensemble_ratings, away_abbr, away_name)
    if (is.null(h_row) || is.null(a_row)) return(NULL)

    comp_cols <- c("rating_bottom_up", "rating_rapm", "rating_shot_fatigue", "rating_embeddings")
    if (!all(comp_cols %in% names(ensemble_ratings))) return(NULL)

    h_vals <- vapply(comp_cols, function(c) .num_field(h_row, c), numeric(1))
    a_vals <- vapply(comp_cols, function(c) .num_field(a_row, c), numeric(1))
    if (!all(is.finite(h_vals)) || !all(is.finite(a_vals))) return(NULL)

    hca_pts <- if ("hca_pts" %in% names(game_row) && is.finite(.num_field(game_row, "hca_pts"))) {
      .num_field(game_row, "hca_pts")
    } else {
      GAME_DETAIL_HCA_POINTS
    }

    away_drag <- .num_field(game_row, "away_fatigue_drag")
    home_drag <- .num_field(game_row, "home_fatigue_drag")
    sched_adj <- if ("schedule_adjustment" %in% names(game_row)) {
      val <- .num_field(game_row, "schedule_adjustment")
      if (!is.finite(val)) return(NULL)
      val
    } else if (is.finite(away_drag) && is.finite(home_drag)) {
      away_drag - home_drag
    } else {
      0
    }

    raw_steps <- c(
      GAME_DETAIL_ENSEMBLE_WEIGHTS[["bottom_up"]]    * (h_vals[["rating_bottom_up"]]    - a_vals[["rating_bottom_up"]]),
      GAME_DETAIL_ENSEMBLE_WEIGHTS[["rapm"]]         * (h_vals[["rating_rapm"]]         - a_vals[["rating_rapm"]]),
      GAME_DETAIL_ENSEMBLE_WEIGHTS[["shot_fatigue"]] * (h_vals[["rating_shot_fatigue"]] - a_vals[["rating_shot_fatigue"]]),
      GAME_DETAIL_ENSEMBLE_WEIGHTS[["embeddings"]]   * (h_vals[["rating_embeddings"]]   - a_vals[["rating_embeddings"]]),
      hca_pts,
      sched_adj
    )

    target_margin <- .num_field(game_row, "predicted_margin")
    if (!is.finite(target_margin)) {
      h_net <- .num_field(h_row, "ensemble_net_rating")
      a_net <- .num_field(a_row, "ensemble_net_rating")
      target_margin <- if (is.finite(h_net) && is.finite(a_net)) {
        (h_net - a_net) + hca_pts + sched_adj
      } else {
        sum(raw_steps)
      }
    }

    h_lbl <- canonical_nba_abbr(home_abbr %||% .field_or_null(h_row, "team"))
    a_lbl <- canonical_nba_abbr(away_abbr %||% .field_or_null(a_row, "team"))
    details <- list(
      sprintf("35%% BPM blend (%s %+.2f vs %s %+.2f)", h_lbl, h_vals[["rating_bottom_up"]], a_lbl, a_vals[["rating_bottom_up"]]),
      sprintf("25%% RAPM blend (%s %+.2f vs %s %+.2f)", h_lbl, h_vals[["rating_rapm"]], a_lbl, a_vals[["rating_rapm"]]),
      sprintf("20%% Shot/Fatigue blend (%s %+.2f vs %s %+.2f)", h_lbl, h_vals[["rating_shot_fatigue"]], a_lbl, a_vals[["rating_shot_fatigue"]]),
      sprintf("20%% Embeddings blend (%s %+.2f vs %s %+.2f)", h_lbl, h_vals[["rating_embeddings"]], a_lbl, a_vals[["rating_embeddings"]]),
      sprintf("%s home-court constant (+%.2f pts)", h_lbl, round(hca_pts, 2L)),
      if (is.finite(away_drag) && is.finite(home_drag)) {
        sprintf("%s fatigue %.2f minus %s fatigue %.2f", a_lbl, away_drag, h_lbl, home_drag)
      } else {
        "Rest, back-to-back & travel drag differential"
      }
    )

    return(.assemble_waterfall_steps(
      raw_steps, details, target_margin,
      context_label = sprintf("primary_ensemble game %s", gid_label)
    ))
  }

  if (basis %in% c("logged_model_margin", "margin_from_logged_win_prob")) {
    if (is.null(log_row)) return(NULL)
    req_cols <- c(
      "comp_bottom_up", "comp_rapm", "comp_shot_fatigue", "comp_embeddings",
      "comp_home_court", "comp_schedule", "sigma_game"
    )
    vals <- vapply(req_cols, function(c) .num_field(log_row, c), numeric(1))
    if (!all(is.finite(vals)) || vals[["sigma_game"]] <= 0) return(NULL)

    target_margin <- .num_field(game_row, "predicted_margin")
    if (!is.finite(target_margin)) target_margin <- .num_field(log_row, "predicted_margin")
    if (!is.finite(target_margin)) return(NULL)

    details <- list(
      "Logged pregame 35% BPM blend differential",
      "Logged pregame 25% RAPM blend differential",
      "Logged pregame 20% Shot/Fatigue blend differential",
      "Logged pregame 20% Embeddings blend differential",
      "Logged pregame home-court constant",
      "Logged pregame schedule & travel drag differential"
    )
    return(.assemble_waterfall_steps(
      vals[seq_len(6L)], details, target_margin,
      context_label = sprintf("logged game %s", gid_label)
    ))
  }

  NULL
}

#' Build strictly causal pooled entering Four Factors + ORtg baselines for a
#' completed game. Returns NULL if realized_factors is NULL or either team has
#' zero prior games strictly before game_date.
build_entering_baselines <- function(game_id, game_date, away_team, home_team,
                                     team_box_df, realized_factors) {
  if (is.null(realized_factors) || is.null(team_box_df) ||
      !is.data.frame(team_box_df) || nrow(team_box_df) == 0L) {
    return(NULL)
  }
  cutoff_date <- tryCatch(as.Date(as.character(game_date)), error = function(e) as.Date(NA))
  if (is.na(cutoff_date)) return(NULL)

  away_abbr <- canonical_nba_abbr(away_team)
  home_abbr <- canonical_nba_abbr(home_team)
  if (!nzchar(away_abbr) || !nzchar(home_abbr)) return(NULL)

  req_cols <- c("game_id", "game_date", "team_abbreviation")
  if (!all(req_cols %in% names(team_box_df))) return(NULL)

  tb_dates <- tryCatch(
    as.Date(as.character(team_box_df$game_date)),
    error = function(e) as.Date(rep(NA_character_, nrow(team_box_df)))
  )
  tb_gids <- as.character(team_box_df$game_id)
  tb_scores <- parse_num_or_na(.col_or_default(team_box_df, "team_score", NA_real_))
  gid_chr <- as.character(game_id)

  keep <- !is.na(tb_dates) & (tb_dates < cutoff_date) & (tb_gids != gid_chr) & !is.na(tb_scores)
  if (!any(keep)) return(NULL)

  prior_tb <- team_box_df[keep, , drop = FALSE]
  prior_gids <- as.character(prior_tb$game_id)
  prior_canon <- canonical_nba_abbr(prior_tb$team_abbreviation)

  realized_keys <- vapply(realized_factors, function(f) as.character(f$key), character(1))

  sum_stat <- function(df, col) {
    if (!(col %in% names(df))) return(NULL)
    v <- parse_num_or_na(df[[col]])
    if (length(v) == 0L || all(is.na(v))) return(NULL)
    s <- sum(v, na.rm = TRUE)
    if (!is.finite(s)) return(NULL)
    s
  }

  sum_side <- function(df) {
    list(
      points    = sum_stat(df, "team_score"),
      fgm       = sum_stat(df, "field_goals_made"),
      fga       = sum_stat(df, "field_goals_attempted"),
      fg3m      = sum_stat(df, "three_point_field_goals_made"),
      ftm       = sum_stat(df, "free_throws_made"),
      fta       = sum_stat(df, "free_throws_attempted"),
      oreb      = sum_stat(df, "offensive_rebounds"),
      dreb      = sum_stat(df, "defensive_rebounds"),
      total_tov = sum_stat(df, "total_turnovers")
    )
  }

  compute_team_baseline <- function(target_abbr, side_field) {
    t_idx <- which(!is.na(prior_canon) & prior_canon == target_abbr)
    if (length(t_idx) == 0L) return(NULL)
    t_idx <- t_idx[!duplicated(prior_gids[t_idx])]

    opp_mask <- is.na(prior_canon) | (prior_canon != target_abbr)
    opp_pool <- prior_tb[opp_mask, , drop = FALSE]
    opp_pool_gids <- prior_gids[opp_mask]
    opp_match <- match(prior_gids[t_idx], opp_pool_gids)
    valid <- !is.na(opp_match)
    if (!any(valid)) return(NULL)

    t_df <- prior_tb[t_idx[valid], , drop = FALSE]
    o_df <- opp_pool[opp_match[valid], , drop = FALSE]
    prior_n <- as.integer(nrow(t_df))
    if (prior_n == 0L) return(NULL)

    ts <- sum_side(t_df)
    os <- sum_side(o_df)

    efg_num <- if (!is.null(ts$fgm) && !is.null(ts$fg3m)) ts$fgm + 0.5 * ts$fg3m else NULL
    tov_den <- if (!is.null(ts$fga) && !is.null(ts$fta) && !is.null(ts$total_tov)) {
      ts$fga + 0.44 * ts$fta + ts$total_tov
    } else NULL
    oreb_den <- if (!is.null(ts$oreb) && !is.null(os$dreb)) ts$oreb + os$dreb else NULL
    poss_pooled <- .compute_dean_oliver_possessions(ts, os)

    entering_vals <- list(
      efg_pct  = safe_ratio(efg_num, ts$fga, 100, 1L),
      tov_pct  = safe_ratio(ts$total_tov, tov_den, 100, 1L),
      oreb_pct = safe_ratio(ts$oreb, oreb_den, 100, 1L),
      fta_rate = safe_ratio(ts$fta, ts$fga, 100, 1L),
      ortg     = if (is.finite(poss_pooled) && poss_pooled > 0) safe_ratio(ts$points, poss_pooled, 100, 1L) else NULL
    )

    realized_vals <- setNames(
      lapply(realized_factors, function(f) num_or_null(f[[side_field]], 1L)),
      realized_keys
    )

    factor_list <- lapply(GAME_DETAIL_ENTERING_FACTOR_KEYS, function(k) {
      ent <- entering_vals[[k]]
      real <- realized_vals[[k]]
      diff_val <- if (!is.null(ent) && !is.null(real) && is.finite(ent) && is.finite(real)) {
        d <- round(real - ent, 1L)
        if (abs(d) < 1e-12) 0 else d
      } else {
        NULL
      }
      list(
        key        = k,
        entering   = ent,
        realized   = real,
        difference = diff_val
      )
    })

    list(
      teamAbbr      = target_abbr,
      prior_games_n = prior_n,
      factors       = unname(factor_list)
    )
  }

  away_bl <- compute_team_baseline(away_abbr, "away_value")
  if (is.null(away_bl)) return(NULL)
  home_bl <- compute_team_baseline(home_abbr, "home_value")
  if (is.null(home_bl)) return(NULL)

  unname(list(away_bl, home_bl))
}

#' Assemble GameExplainabilityPayload for both MatchupGame (slates JSON) and
#' GameDetailPayload (per-game JSON).
build_game_explainability <- function(game_row, ensemble_ratings = NULL, log_row = NULL,
                                      shap_entry = NULL, team_box_df = NULL,
                                      realized_factors = NULL) {
  raw_basis <- chr_or_null(.field_or_null(game_row, "projection_basis"))
  proj_basis <- if (identical(raw_basis, "team_rating_differential")) NULL else raw_basis
  if (!is.null(proj_basis) &&
      !(proj_basis %in% c("primary_ensemble", "logged_model_margin", "margin_from_logged_win_prob"))) {
    stop(sprintf("Unsupported projection_basis in build_game_explainability(): %s", proj_basis))
  }

  home_abbr <- chr_or_null(.field_or_null(game_row, "home_team"))
  away_abbr <- chr_or_null(.field_or_null(game_row, "away_team"))
  home_name <- chr_or_null(.field_or_null(game_row, "home_name")) %||%
    chr_or_null(.field_or_null(game_row, "home_team_name"))
  away_name <- chr_or_null(.field_or_null(game_row, "away_name")) %||%
    chr_or_null(.field_or_null(game_row, "away_team_name"))

  raw_margin <- .num_field(game_row, "predicted_margin")
  raw_prob <- .num_field(game_row, "predicted_home_win_prob")
  sigma_out <- NULL

  if (identical(proj_basis, "primary_ensemble")) {
    sg <- .num_field(game_row, "sigma_game")
    if (is.finite(sg) && sg > 0) {
      sigma_out <- num_or_null(sg, 4L)
    } else if (!is.null(ensemble_ratings) && is.data.frame(ensemble_ratings)) {
      h_row <- .lookup_ensemble_team(ensemble_ratings, home_abbr, home_name)
      a_row <- .lookup_ensemble_team(ensemble_ratings, away_abbr, away_name)
      if (!is.null(h_row) && !is.null(a_row)) {
        sd_h <- .num_field(h_row, "rating_disagreement_sd")
        sd_a <- .num_field(a_row, "rating_disagreement_sd")
        sd_h <- if (is.finite(sd_h) && sd_h > 0) sd_h else 0
        sd_a <- if (is.finite(sd_a) && sd_a > 0) sd_a else 0
        sg_calc <- sqrt(.get_margin_sigma()^2 + sd_h^2 + sd_a^2)
        sigma_out <- num_or_null(sg_calc, 4L)

        if (!is.finite(raw_margin)) {
          h_net <- .num_field(h_row, "ensemble_net_rating")
          a_net <- .num_field(a_row, "ensemble_net_rating")
          hca_pts <- if ("hca_pts" %in% names(game_row) && is.finite(.num_field(game_row, "hca_pts"))) {
            .num_field(game_row, "hca_pts")
          } else {
            GAME_DETAIL_HCA_POINTS
          }
          sched_adj <- if ("schedule_adjustment" %in% names(game_row) && is.finite(.num_field(game_row, "schedule_adjustment"))) {
            .num_field(game_row, "schedule_adjustment")
          } else {
            0
          }
          if (is.finite(h_net) && is.finite(a_net)) {
            raw_margin <- (h_net - a_net) + hca_pts + sched_adj
          }
        }
        if (!is.finite(raw_prob) && is.finite(raw_margin)) {
          raw_prob <- pnorm(raw_margin / sg_calc)
        }
      }
    }
  } else if (!is.null(proj_basis) &&
             proj_basis %in% c("logged_model_margin", "margin_from_logged_win_prob") &&
             !is.null(log_row)) {
    sg_log <- .num_field(log_row, "sigma_game")
    if (is.finite(sg_log) && sg_log > 0) {
      sigma_out <- num_or_null(sg_log, 4L)
    }
  }

  pred_margin <- num_or_null(raw_margin, 2L)
  pred_prob <- num_or_null(raw_prob, 4L)

  waterfall <- build_margin_waterfall(
    game_row         = game_row,
    ensemble_ratings = ensemble_ratings,
    log_row          = log_row
  )

  is_comp <- isTRUE(as.logical(.field_or_null(game_row, "is_completed")))

  logged_forecast <- NULL
  if (!is.null(proj_basis) &&
      proj_basis %in% c("logged_model_margin", "margin_from_logged_win_prob") &&
      !is.null(log_row)) {
    ls_val <- chr_or_null(.field_or_null(log_row, "log_source"))
    if (is.null(ls_val) || !(ls_val %in% GAME_DETAIL_LOG_SOURCES)) {
      stop(sprintf("Invalid or missing log_source for logged game %s: %s",
                   chr_or_null(.field_or_null(game_row, "game_id")) %||% "?",
                   ls_val %||% "NULL"))
    }
    ts_raw <- .field_or_null(log_row, "prediction_timestamp")
    ts_str <- if (inherits(ts_raw, "POSIXt")) {
      if (is.na(ts_raw)) NULL else format(ts_raw, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    } else {
      chr_or_null(ts_raw)
    }
    if (is.null(ts_str)) {
      stop(sprintf("Missing prediction_timestamp for logged game %s",
                   chr_or_null(.field_or_null(game_row, "game_id")) %||% "?"))
    }

    brier_comp <- NULL
    ll_comp <- NULL
    if (is_comp && !is.null(pred_prob) && is.finite(pred_prob)) {
      hs <- .num_field(game_row, "home_score")
      if (!is.finite(hs)) hs <- .num_field(game_row, "box_home_score")
      as_val <- .num_field(game_row, "away_score")
      if (!is.finite(as_val)) as_val <- .num_field(game_row, "box_away_score")
      if (is.finite(hs) && is.finite(as_val)) {
        y <- as.numeric(hs > as_val)
        p <- min(max(as.numeric(pred_prob), 1e-6), 1 - 1e-6)
        brier_comp <- round((p - y)^2, 6L)
        ll_comp <- round(-(y * log(p) + (1 - y) * log(1 - p)), 6L)
      }
    }

    logged_forecast <- list(
      prediction_timestamp = ts_str,
      log_source           = ls_val,
      brier_component      = brier_comp,
      log_loss_component   = ll_comp
    )
  }

  entering_baselines <- NULL
  if (is_comp && !is.null(realized_factors)) {
    gid_val <- chr_or_null(.field_or_null(game_row, "game_id")) %||%
      chr_or_null(.field_or_null(game_row, "espn_game_id"))
    gdate_val <- .field_or_null(game_row, "game_date")
    entering_baselines <- build_entering_baselines(
      game_id          = gid_val,
      game_date        = gdate_val,
      away_team        = away_abbr,
      home_team        = home_abbr,
      team_box_df      = team_box_df,
      realized_factors = realized_factors
    )
  }

  shap_out <- NULL
  if (!is.null(shap_entry) && is.list(shap_entry)) {
    shap_out <- shap_entry
    if (!is.null(shap_out$factors)) {
      shap_out$factors <- unname(shap_out$factors)
    }
  }

  list(
    projection_basis        = proj_basis,
    predicted_margin        = pred_margin,
    predicted_home_win_prob = pred_prob,
    sigma_game              = sigma_out,
    margin_waterfall        = waterfall,
    logged_forecast         = logged_forecast,
    entering_baselines      = entering_baselines,
    xgboost_shap            = shap_out
  )
}

#' Build a GameDetailEnvelope payload for one game.
#'
#' Maintains the Phase 1 contract invariant: `box_score`, `efficiency_factors`,
#' and `context_splits` are non-null if and only if `has_box_score` is TRUE.
build_game_detail_payload <- function(
  game_id,
  team_box_game,
  player_box_game,
  slate = 1L,
  slate_label = NULL,
  game_date = NULL,
  is_completed = TRUE,
  season = 2027L,
  season_label = sprintf("%d-%d", as.integer(season) - 1L, as.integer(season)),
  away_team_meta = NULL,
  home_team_meta = NULL,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  schema_ver = GAME_DETAIL_SCHEMA_VERSION,
  explainability = NULL
) {
  gid <- as.character(game_id)

  tb_g <- if (!is.null(team_box_game) && nrow(team_box_game) > 0L) {
    team_box_game[as.character(team_box_game$game_id) == gid, , drop = FALSE]
  } else {
    team_box_game
  }
  pb_g <- if (!is.null(player_box_game) && nrow(player_box_game) > 0L) {
    player_box_game[as.character(player_box_game$game_id) == gid, , drop = FALSE]
  } else {
    player_box_game
  }

  tb_sides <- .split_team_box_sides(tb_g)
  away_tb <- tb_sides$away
  home_tb <- tb_sides$home

  g_date <- if (!is.null(game_date) && !is.na(game_date)) {
    as.Date(as.character(game_date))
  } else if (nrow(away_tb) == 1L && "game_date" %in% names(away_tb)) {
    as.Date(as.character(away_tb$game_date[1]))
  } else {
    as.Date(NA)
  }

  slate_int <- as.integer(slate)
  slate_lbl <- chr_or_null(slate_label) %||% sprintf("Week %d", slate_int)

  resolve_team_info <- function(tb_row, meta) {
    abbr <- if (nrow(tb_row) == 1L && "team_abbreviation" %in% names(tb_row)) {
      canonical_nba_abbr(tb_row$team_abbreviation[1])
    } else if (!is.null(meta$teamAbbr)) {
      canonical_nba_abbr(meta$teamAbbr)
    } else {
      ""
    }
    tname <- if (nrow(tb_row) == 1L) {
      chr_or_null(.col_or_default(tb_row, "team_short_display_name", NA_character_)[1]) %||%
        chr_or_null(.col_or_default(tb_row, "team_name", NA_character_)[1]) %||%
        chr_or_null(meta$teamName) %||%
        abbr
    } else {
      chr_or_null(meta$teamName) %||% abbr
    }
    list(abbr = abbr, name = tname)
  }

  away_info <- resolve_team_info(away_tb, away_team_meta)
  home_info <- resolve_team_info(home_tb, home_team_meta)

  away_score_num <- if (nrow(away_tb) == 1L) parse_num_or_na(away_tb$team_score[1]) else NA_real_
  home_score_num <- if (nrow(home_tb) == 1L) parse_num_or_na(home_tb$team_score[1]) else NA_real_

  completed_flag <- isTRUE(as.logical(is_completed))
  has_box_score <- completed_flag &&
    nrow(away_tb) == 1L &&
    nrow(home_tb) == 1L &&
    !is.na(away_score_num) &&
    !is.na(home_score_num) &&
    !is.null(pb_g) &&
    nrow(pb_g) > 0L

  if (!has_box_score) {
    return(list(
      schema_version = as.character(schema_ver),
      generated_at   = as.character(generated_at),
      sport          = "nba",
      endpoint       = "game_detail",
      season         = as.integer(season),
      season_label   = as.character(season_label),
      data = list(
        game_id            = gid,
        slate              = slate_int,
        slate_label        = slate_lbl,
        game_date          = if (!is.na(g_date)) format(g_date, "%Y-%m-%d") else NULL,
        weekday            = format_weekday_en(g_date),
        is_completed       = completed_flag,
        has_box_score      = FALSE,
        away_team          = list(teamAbbr = away_info$abbr, teamName = away_info$name, score = NULL, is_winner = NULL),
        home_team          = list(teamAbbr = home_info$abbr, teamName = home_info$name, score = NULL, is_winner = NULL),
        efficiency_factors = NULL,
        context_splits     = NULL,
        box_score          = NULL,
        explainability     = explainability,
        game_flow          = NULL
      )
    ))
  }

  away_score <- as.integer(round(away_score_num))
  home_score <- as.integer(round(home_score_num))
  away_winner <- if ("team_winner" %in% names(away_tb) && !is.na(away_tb$team_winner[1])) {
    as.logical(away_tb$team_winner[1])
  } else {
    away_score > home_score
  }
  home_winner <- if ("team_winner" %in% names(home_tb) && !is.na(home_tb$team_winner[1])) {
    as.logical(home_tb$team_winner[1])
  } else {
    home_score > away_score
  }

  sides <- .split_player_box_sides(pb_g, away_tb, home_tb, away_info$abbr, home_info$abbr)
  away_players_res <- classify_game_players(sides$away, team_abbr = away_info$abbr)
  home_players_res <- classify_game_players(sides$home, team_abbr = home_info$abbr)

  away_stats <- .extract_team_counting_stats(away_tb)
  home_stats <- .extract_team_counting_stats(home_tb)

  game_minutes <- max(
    round(away_players_res$active_minutes / 5),
    round(home_players_res$active_minutes / 5),
    48
  )
  poss_raw <- .compute_dean_oliver_possessions(away_stats, home_stats)

  away_totals <- .build_team_box_totals(
    away_stats, home_stats, away_players_res$active_minutes, poss_raw, game_minutes
  )
  home_totals <- .build_team_box_totals(
    home_stats, away_stats, home_players_res$active_minutes, poss_raw, game_minutes
  )

  efficiency_factors <- .build_efficiency_factors(away_totals, home_totals, away_stats, home_stats)
  context_splits <- .build_context_splits(
    away_stats, home_stats,
    away_players_res$bench_points, home_players_res$bench_points
  )
  top_performers <- .select_top_performers(
    c(away_players_res$top_performer_candidates, home_players_res$top_performer_candidates),
    n = 3L
  )

  list(
    schema_version = as.character(schema_ver),
    generated_at   = as.character(generated_at),
    sport          = "nba",
    endpoint       = "game_detail",
    season         = as.integer(season),
    season_label   = as.character(season_label),
    data = list(
      game_id       = gid,
      slate         = slate_int,
      slate_label   = slate_lbl,
      game_date     = format(g_date, "%Y-%m-%d"),
      weekday       = format_weekday_en(g_date),
      is_completed  = TRUE,
      has_box_score = TRUE,
      away_team = list(
        teamAbbr  = away_info$abbr,
        teamName  = away_info$name,
        score     = away_score,
        is_winner = away_winner
      ),
      home_team = list(
        teamAbbr  = home_info$abbr,
        teamName  = home_info$name,
        score     = home_score,
        is_winner = home_winner
      ),
      efficiency_factors = efficiency_factors,
      context_splits     = context_splits,
      box_score = list(
        away_totals    = away_totals,
        home_totals    = home_totals,
        away_players   = away_players_res$players,
        home_players   = home_players_res$players,
        away_inactive  = away_players_res$inactive,
        home_inactive  = home_players_res$inactive,
        top_performers = top_performers
      ),
      explainability = explainability,
      game_flow      = NULL
    )
  )
}

# ------------------------------------------------------------------------------
# Churn control & atomic JSON output (v3 sections 2.2 & 2.3)
# ------------------------------------------------------------------------------

# No rebuild window (frozen-game-file drift, 2026-11-16). Every completed game's payload is
# rebuilt in memory on every run, and write_game_json_if_changed() writes it only when its
# content differs. An earlier version skipped games older than 7 days whose file existed.
# That froze old files while matchups_slates.json kept recomputing the same figures, so a
# late feed correction made the two disagree, failed contract test P2-c and blocked the
# publish. Of the five files that drifted on 2026-11-16:
#   - three had a box-score correction to that game, and
#   - two had no change to their own box score at all: a correction to an EARLIER game
#     moved a team's season-to-date "entering" baseline.
# A fingerprint of a game's own box rows would have missed those two, which is why the
# whole payload is rebuilt and compared instead. The cost is about 12 s for 197 games.
# Daily churn stays limited to files whose content actually changed.

# Leaf paths (e.g. "data.box_score.away_totals.dreb") whose values differ between two
# serialized game detail payloads, ignoring generated_at. Used only for the log line written
# when an existing file is rewritten.
.game_detail_changed_paths <- function(old_txt, new_txt) {
  parse <- function(t) tryCatch(jsonlite::fromJSON(t, simplifyVector = FALSE),
                                error = function(e) NULL)
  old <- parse(old_txt)
  new <- parse(new_txt)
  if (is.null(old) || is.null(new)) return("<unparseable previous file>")
  flatten <- function(x, prefix) {
    if (is.list(x) && length(x) > 0L) {
      nms <- names(x)
      keys <- if (is.null(nms)) sprintf("%s[%d]", prefix, seq_along(x) - 1L)
              else if (nzchar(prefix)) paste0(prefix, ".", nms)
              else nms
      unlist(Map(flatten, x, keys), recursive = FALSE, use.names = FALSE)
    } else {
      list(list(path = prefix, value = if (is.null(x) || length(x) == 0L) NA else x))
    }
  }
  to_map <- function(x) {
    leaves <- flatten(x, "")
    vals <- lapply(leaves, `[[`, "value")
    names(vals) <- vapply(leaves, `[[`, character(1), "path")
    vals
  }
  om <- to_map(old)
  nm <- to_map(new)
  keys <- union(names(om), names(nm))
  keys <- keys[!grepl("(^|\\.)generated_at$", keys)]
  differs <- vapply(keys, function(k) !identical(om[[k]], nm[[k]]), logical(1))
  keys[differs]
}

# Box-score fields (the feed's own numbers) are listed first, then derived figures, so the
# log line leads with what the feed corrected rather than its knock-on effects.
.format_changed_paths <- function(paths, max_show = 6L) {
  if (length(paths) == 0L) return("no field-level difference (formatting only)")
  paths <- paths[order(!grepl("^data\\.box_score\\.", paths), seq_along(paths))]
  shown <- head(paths, max_show)
  more <- length(paths) - length(shown)
  paste0(paste(shown, collapse = ", "), if (more > 0L) sprintf(" (+%d more)", more) else "")
}

.strip_generated_at_text <- function(txt) {
  txt <- gsub("\r\n", "\n", txt, fixed = TRUE)
  txt <- gsub('(?m)^[ \\t]*"generated_at"\\s*:\\s*(?:"[^"]*"|null)\\s*,?[ \\t]*\\n?', "", txt, perl = TRUE)
  txt <- gsub('"generated_at"\\s*:\\s*(?:"[^"]*"|null)\\s*,?', "", txt, perl = TRUE)
  txt
}

serialize_game_detail_json <- function(payload) {
  txt <- as.character(jsonlite::toJSON(
    payload,
    pretty     = TRUE,
    auto_unbox = TRUE,
    null       = "null",
    na         = "null",
    digits     = NA
  ))
  enc2utf8(paste0(txt, "\n"))
}

.read_utf8_text <- function(path) {
  sz <- file.info(path)$size
  if (is.na(sz) || sz <= 0) return("")
  raw_bytes <- readBin(path, what = "raw", n = sz)
  txt <- rawToChar(raw_bytes)
  Encoding(txt) <- "UTF-8"
  txt
}

#' Atomically write payload JSON to path only if content changed ignoring generated_at.
#'
#' Returns TRUE if the file was written/updated, FALSE if unchanged.
write_game_json_if_changed <- function(payload, path) {
  cand_txt <- serialize_game_detail_json(payload)
  if (file.exists(path)) {
    disk_txt <- tryCatch(.read_utf8_text(path), error = function(e) NULL)
    if (!is.null(disk_txt) &&
        identical(.strip_generated_at_text(cand_txt), .strip_generated_at_text(disk_txt))) {
      return(FALSE)
    }
  }

  parent <- dirname(path)
  if (!dir.exists(parent)) dir.create(parent, recursive = TRUE, showWarnings = FALSE)

  tmp_path <- tempfile(pattern = paste0(".", basename(path), "."),
                       tmpdir = parent, fileext = ".tmp")
  on.exit({
    if (file.exists(tmp_path)) unlink(tmp_path)
  }, add = TRUE)

  writeBin(charToRaw(cand_txt), tmp_path)
  if (!isTRUE(file.rename(tmp_path, path))) {
    stop(sprintf("Failed to atomically rename %s -> %s", tmp_path, path))
  }
  TRUE
}

.derive_games_from_team_box <- function(team_box) {
  if (is.null(team_box) || nrow(team_box) == 0L) {
    return(data.frame(
      game_id = character(0), game_date = as.Date(character(0)),
      slate = integer(0), slate_label = character(0),
      is_completed = logical(0), stringsAsFactors = FALSE
    ))
  }

  tb <- team_box
  tb$gid_chr <- as.character(tb$game_id)
  tb$gdate <- as.Date(as.character(tb$game_date))

  away <- tb[tolower(as.character(tb$team_home_away)) == "away", c("gid_chr", "gdate", "team_score"), drop = FALSE]
  home <- tb[tolower(as.character(tb$team_home_away)) == "home", c("gid_chr", "team_score"), drop = FALSE]
  away <- away[!duplicated(away$gid_chr), , drop = FALSE]
  home <- home[!duplicated(home$gid_chr), , drop = FALSE]
  names(away)[3] <- "away_score"
  names(home)[2] <- "home_score"

  g <- merge(away, home, by = "gid_chr", all = FALSE, sort = FALSE)
  if (nrow(g) == 0L) {
    return(data.frame(
      game_id = character(0), game_date = as.Date(character(0)),
      slate = integer(0), slate_label = character(0),
      is_completed = logical(0), stringsAsFactors = FALSE
    ))
  }
  g <- g[order(g$gdate, g$gid_chr), , drop = FALSE]
  season_start <- min(g$gdate, na.rm = TRUE)
  slates <- as.integer(floor(as.numeric(g$gdate - season_start) / 7) + 1L)

  # Compute week bounds over the observed dates.
  uniq_slates <- sort(unique(slates))
  bounds_map <- setNames(character(length(uniq_slates)), as.character(uniq_slates))
  for (s in uniq_slates) {
    ds <- g$gdate[slates == s]
    bounds_map[as.character(s)] <- format_slate_label_en(s, min(ds), max(ds))
  }

  data.frame(
    game_id      = g$gid_chr,
    game_date    = g$gdate,
    slate        = slates,
    slate_label  = unname(bounds_map[as.character(slates)]),
    is_completed = !is.na(parse_num_or_na(g$away_score)) & !is.na(parse_num_or_na(g$home_score)),
    stringsAsFactors = FALSE
  )
}

#' Batch export per-game detail JSON files under out_dir.
#'
#' Emits games/<game_id>.json ONLY when has_box_score is TRUE (game is completed
#' and has valid away/home team_box rows plus player_box rows). Every such game is
#' rebuilt in memory on every run and written only when its content changed
#' (generated_at ignored). Each rewrite of an existing file is logged through
#' log_fn with the game, its age and the changed fields, and returned in
#' `$updates`. `force` is accepted for backward compatibility; it has no effect,
#' because every game is already rebuilt.
export_game_details <- function(
  team_box,
  player_box,
  games = NULL,
  out_dir = if (exists("WEB_GAMES_DIR", inherits = TRUE)) get("WEB_GAMES_DIR", inherits = TRUE) else file.path("web", "public", "data", "games"),
  season = if (exists("MATCHUPS_HOOPR_SEASON", inherits = TRUE)) as.integer(get("MATCHUPS_HOOPR_SEASON", inherits = TRUE)) else 2027L,
  season_label = if (exists("MATCHUPS_SEASON_LABEL", inherits = TRUE)) as.character(get("MATCHUPS_SEASON_LABEL", inherits = TRUE)) else sprintf("%d-%d", as.integer(season) - 1L, as.integer(season)),
  today_date = Sys.Date(),
  force = identical(Sys.getenv("NBA_FORCE_REBUILD_GAMES"), "true"),
  schema_ver = GAME_DETAIL_SCHEMA_VERSION,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  explainability_by_game = NULL,
  log_fn = function(msg) cat(msg, "\n", sep = "")
) {
  if (is.null(games)) {
    games <- .derive_games_from_team_box(team_box)
  }

  empty_updates <- data.frame(
    game_id = character(0), game_date = as.Date(character(0)), days_old = integer(0),
    n_changed = integer(0), changed_fields = character(0), stringsAsFactors = FALSE
  )

  n_games <- nrow(games)
  if (n_games == 0L) {
    return(list(
      total_games          = 0L,
      games_with_box_score = 0L,
      rebuilt_candidates   = 0L,
      written              = 0L,
      created              = 0L,
      updated              = 0L,
      unchanged            = 0L,
      skipped_no_box_score = 0L,
      written_ids          = character(0),
      updates              = empty_updates,
      game_status          = data.frame(
        game_id = character(0), has_box_score = logical(0),
        has_game_detail = logical(0), action = character(0),
        stringsAsFactors = FALSE
      )
    ))
  }

  gid_col <- if ("game_id" %in% names(games)) "game_id" else "espn_game_id"
  gids <- as.character(games[[gid_col]])
  gdates <- as.Date(as.character(games$game_date))
  gslates <- if ("slate" %in% names(games)) as.integer(games$slate) else rep(1L, n_games)
  gslabels <- if ("slate_label" %in% names(games)) {
    as.character(games$slate_label)
  } else {
    sprintf("Week %d", gslates)
  }
  gcompleted <- if ("is_completed" %in% names(games)) {
    !is.na(games$is_completed) & as.logical(games$is_completed)
  } else {
    rep(TRUE, n_games)
  }

  # Pre-index team_box and player_box by game_id for O(N) batch performance.
  tb_gids <- if (!is.null(team_box) && nrow(team_box) > 0L) as.character(team_box$game_id) else character(0)
  pb_gids <- if (!is.null(player_box) && nrow(player_box) > 0L) as.character(player_box$game_id) else character(0)
  tb_idx <- if (length(tb_gids) > 0L) split(seq_along(tb_gids), tb_gids) else list()
  pb_idx <- if (length(pb_gids) > 0L) split(seq_along(pb_gids), pb_gids) else list()

  has_box_vec    <- logical(n_games)
  has_detail_vec <- logical(n_games)
  action_vec     <- character(n_games)
  written_ids    <- character(0)

  n_has_box        <- 0L
  n_rebuilt        <- 0L
  n_written        <- 0L
  n_created        <- 0L
  n_unchanged      <- 0L
  n_skipped_no_box <- 0L
  updates          <- list()
  td               <- as.Date(today_date)

  for (i in seq_len(n_games)) {
    gid <- gids[i]
    tb_rows_i <- tb_idx[[gid]]
    pb_rows_i <- pb_idx[[gid]]

    tb_g <- if (!is.null(tb_rows_i)) team_box[tb_rows_i, , drop = FALSE] else team_box[0L, , drop = FALSE]
    pb_g <- if (!is.null(pb_rows_i)) player_box[pb_rows_i, , drop = FALSE] else player_box[0L, , drop = FALSE]

    has_away <- nrow(tb_g) > 0L && any(tolower(as.character(tb_g$team_home_away)) == "away" &
                                          !is.na(parse_num_or_na(tb_g$team_score)))
    has_home <- nrow(tb_g) > 0L && any(tolower(as.character(tb_g$team_home_away)) == "home" &
                                          !is.na(parse_num_or_na(tb_g$team_score)))
    has_box <- gcompleted[i] && has_away && has_home && nrow(pb_g) > 0L
    has_box_vec[i] <- has_box

    out_path <- file.path(out_dir, sprintf("%s.json", gid))
    if (!has_box) {
      n_skipped_no_box <- n_skipped_no_box + 1L
      has_detail_vec[i] <- FALSE
      action_vec[i] <- "skipped_no_box_score"
      next
    }

    exp_i <- if (!is.null(explainability_by_game) && gid %in% names(explainability_by_game)) {
      explainability_by_game[[gid]]
    } else NULL

    n_has_box <- n_has_box + 1L
    n_rebuilt <- n_rebuilt + 1L
    away_meta <- if ("away_team" %in% names(games) && any(c("away_team_name", "away_name") %in% names(games))) {
      nm_col <- if ("away_team_name" %in% names(games)) "away_team_name" else "away_name"
      list(teamAbbr = games$away_team[i], teamName = games[[nm_col]][i])
    } else NULL
    home_meta <- if ("home_team" %in% names(games) && any(c("home_team_name", "home_name") %in% names(games))) {
      nm_col <- if ("home_team_name" %in% names(games)) "home_team_name" else "home_name"
      list(teamAbbr = games$home_team[i], teamName = games[[nm_col]][i])
    } else NULL

    payload <- build_game_detail_payload(
      game_id         = gid,
      team_box_game   = tb_g,
      player_box_game = pb_g,
      slate           = gslates[i],
      slate_label     = gslabels[i],
      game_date       = gdates[i],
      is_completed    = TRUE,
      season          = season,
      season_label    = season_label,
      away_team_meta  = away_meta,
      home_team_meta  = home_meta,
      generated_at    = generated_at,
      schema_ver      = schema_ver,
      explainability  = exp_i
    )

    existed <- file.exists(out_path)
    old_txt <- if (existed) tryCatch(.read_utf8_text(out_path), error = function(e) NULL) else NULL
    changed <- write_game_json_if_changed(payload, out_path)
    has_detail_vec[i] <- file.exists(out_path)
    if (changed) {
      n_written <- n_written + 1L
      written_ids <- c(written_ids, gid)
      if (existed) {
        action_vec[i] <- "updated"
        paths <- if (is.null(old_txt)) "<unreadable previous file>"
                 else .game_detail_changed_paths(old_txt, serialize_game_detail_json(payload))
        days_old <- if (is.na(gdates[i]) || is.na(td)) NA_integer_ else as.integer(td - gdates[i])
        updates[[length(updates) + 1L]] <- data.frame(
          game_id = gid, game_date = gdates[i], days_old = days_old,
          n_changed = length(paths), changed_fields = paste(paths, collapse = ", "),
          stringsAsFactors = FALSE
        )
        log_fn(sprintf(">>> Game detail %s (%s, %s days old) updated: %d field(s) changed: %s",
                       gid, format(gdates[i]), days_old, length(paths),
                       .format_changed_paths(paths)))
      } else {
        n_created <- n_created + 1L
        action_vec[i] <- "written"
      }
    } else {
      n_unchanged <- n_unchanged + 1L
      action_vec[i] <- "unchanged"
    }
  }

  list(
    total_games          = as.integer(n_games),
    games_with_box_score = n_has_box,
    rebuilt_candidates   = n_rebuilt,
    written              = n_written,
    created              = n_created,
    updated              = n_written - n_created,
    unchanged            = n_unchanged,
    skipped_no_box_score = n_skipped_no_box,
    written_ids          = written_ids,
    updates              = if (length(updates) > 0L) do.call(rbind, updates) else empty_updates,
    game_status          = data.frame(
      game_id         = gids,
      has_box_score   = has_box_vec,
      has_game_detail = has_detail_vec,
      action          = action_vec,
      stringsAsFactors = FALSE
    )
  )
}
