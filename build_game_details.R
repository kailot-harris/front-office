# ==============================================================================
# build_game_details.R
# Purely empirical post-game box score, Four Factors, efficiency metrics,
# context splits, and Hollinger Game Score payload builder (Matchup Game Detail
# v3 -- Phase 1).
#
# Designed to be sourced without side effects by build_matchups_dataset.R and
# standalone unit/contract tests. Reads only caller-supplied data frames (no
# hidden network calls, no setwd(), no top-level execution).
# ==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

GAME_DETAIL_SCHEMA_VERSION <- "1.0"

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
  schema_ver = GAME_DETAIL_SCHEMA_VERSION
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
        explainability     = NULL,
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
      explainability = NULL,
      game_flow      = NULL
    )
  )
}

# ------------------------------------------------------------------------------
# Churn control & atomic JSON output (v3 sections 2.2 & 2.3)
# ------------------------------------------------------------------------------

.read_json_schema_version <- function(path) {
  if (!file.exists(path)) return(NULL)
  header <- tryCatch(readLines(path, n = 10L, warn = FALSE, encoding = "UTF-8"),
                     error = function(e) character(0))
  hit <- grep('"schema_version"\\s*:', header, value = TRUE)
  if (length(hit) >= 1L) {
    m <- regexec('"schema_version"\\s*:\\s*"([^"]+)"', hit[1], perl = TRUE)
    caps <- regmatches(hit[1], m)[[1]]
    if (length(caps) >= 2L) return(caps[2])
  }
  # Fallback for compact/non-standard formatting when header lines didn't match.
  parsed <- tryCatch(jsonlite::fromJSON(path), error = function(e) NULL)
  if (is.list(parsed) && !is.null(parsed$schema_version)) {
    return(as.character(parsed$schema_version))
  }
  NULL
}

#' Decide whether a game detail file should be rebuilt on this run.
#'
#' Returns TRUE when no file exists, force is TRUE, game_date is within the
#' 7-day stat-correction window (>= today_date - 7), or the existing file's
#' schema_version differs from schema_ver.
should_rebuild_game_detail <- function(
  game_date,
  path,
  schema_ver = GAME_DETAIL_SCHEMA_VERSION,
  today_date = Sys.Date(),
  force = identical(Sys.getenv("NBA_FORCE_REBUILD_GAMES"), "true")
) {
  if (isTRUE(force)) return(TRUE)
  if (!file.exists(path)) return(TRUE)

  gd <- tryCatch(as.Date(as.character(game_date)), error = function(e) as.Date(NA))
  td <- as.Date(today_date)
  if (is.na(gd) || is.na(td)) return(TRUE)
  if (gd >= (td - 7L)) return(TRUE)

  existing_ver <- .read_json_schema_version(path)
  !identical(existing_ver, as.character(schema_ver))
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
#' and has valid away/home team_box rows plus player_box rows). Applies the
#' 7-day rebuild window and generated_at-ignoring byte comparison.
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
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
) {
  if (is.null(games)) {
    games <- .derive_games_from_team_box(team_box)
  }

  n_games <- nrow(games)
  if (n_games == 0L) {
    return(list(
      total_games          = 0L,
      games_with_box_score = 0L,
      rebuilt_candidates   = 0L,
      written              = 0L,
      unchanged            = 0L,
      skipped_window       = 0L,
      skipped_no_box_score = 0L,
      written_ids          = character(0),
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
  n_unchanged      <- 0L
  n_skipped_window <- 0L
  n_skipped_no_box <- 0L

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

    n_has_box <- n_has_box + 1L
    if (!should_rebuild_game_detail(
      game_date  = gdates[i],
      path       = out_path,
      schema_ver = schema_ver,
      today_date = today_date,
      force      = force
    )) {
      n_skipped_window <- n_skipped_window + 1L
      has_detail_vec[i] <- file.exists(out_path)
      action_vec[i] <- "skipped_window"
      next
    }

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
      schema_ver      = schema_ver
    )

    changed <- write_game_json_if_changed(payload, out_path)
    has_detail_vec[i] <- file.exists(out_path)
    if (changed) {
      n_written <- n_written + 1L
      written_ids <- c(written_ids, gid)
      action_vec[i] <- "written"
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
    unchanged            = n_unchanged,
    skipped_window       = n_skipped_window,
    skipped_no_box_score = n_skipped_no_box,
    written_ids          = written_ids,
    game_status          = data.frame(
      game_id         = gids,
      has_box_score   = has_box_vec,
      has_game_detail = has_detail_vec,
      action          = action_vec,
      stringsAsFactors = FALSE
    )
  )
}
