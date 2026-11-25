# ==============================================================================
# tools/leader_reliability_study.R
#
# Issue #253: how large a sample does a player need before each leader stat
# reflects his real level rather than noise? RESEARCH ONLY. This script is not
# wired into the pipeline, changes no production setting and chooses no
# qualifying minimum. It measures reliability curves; the owner reads them and
# sets the minimums (issue #254 consumes them).
#
# WHAT IT DOES
#   1. Per-game counting stats (sample unit: games played), shooting
#      percentages (unit: attempts of that shot type) and rate stats (unit:
#      minutes), from ESPN player and team box scores via hoopR, regular season
#      only, rows where the player did not play excluded.
#        - Split-half reliability: each player-season's games are numbered by
#          date; odd-numbered games form half A, even-numbered games half B. At
#          sample size n the stat is computed on each half from the first n
#          units of that half and correlated across player-seasons (Pearson).
#          Spearman-Brown: r_sb = 2r / (1 + r), the reliability of a sample of
#          2n units.
#        - Rest-of-season check: the stat over a player's first n units of the
#          season against the same stat over ALL his remaining games that
#          season, for player-seasons whose remainder holds at least n units.
#   2. RAPM (offensive, defensive, total): rapm_engine.R is sourced unchanged
#      and its load_or_build_possession_cache() / estimate_rapm_from_possessions()
#      are called on the odd-numbered and the even-numbered regular-season games
#      of each season separately; ratings are correlated across halves by
#      possessions-per-side bins. No synthetic path exists or is called here.
#   3. Intervals: player-season block bootstrap, percentile 95% intervals.
#
# Units and samples: games are discrete, so for attempts and minutes the sample
# "first n units" is the shortest run of whole games (in date order) whose
# cumulative units reach n. The realised sample is therefore n plus at most one
# game's worth of units; the mean realised size is reported at every point.
#
# No imputation: a value that is missing in a played game stays missing; any
# sample that contains it is dropped at that point and counted (n_missing).
#
# Run from the project root (fresh session):
#   Rscript tools/leader_reliability_study.R
# Smoke test with fewer resamples:
#   LRS_N_BOOT=50 Rscript tools/leader_reliability_study.R
# Re-run each offseason by changing SEASONS / RAPM_SEASONS below.
# ==============================================================================

# ---- Settings (change these to re-run the study) ------------------------------
# hoopR END-year numbering: 2026 === the 2025-26 season. 2020 is left out because
# that regular season was halted and never completed. 2027 is in progress.
SEASONS        <- c(2017L, 2018L, 2019L, 2021L, 2022L, 2023L, 2024L, 2025L, 2026L)
RAPM_SEASONS   <- SEASONS
SEED           <- 253L
N_BOOT         <- as.integer(Sys.getenv("LRS_N_BOOT", "1000"))
GRID_GAMES     <- 1:40
GRID_ATTEMPTS  <- c(seq(10, 100, 10), seq(125, 500, 25), seq(550, 800, 50))
GRID_MINUTES   <- c(seq(25, 200, 25), seq(250, 1500, 50))
# RAPM: possessions per side within EACH half (min over the two halves and the two
# sides). Bins are half-open [lo, hi). Thresholds give "at least k" curves.
RAPM_BIN_EDGES <- c(0, 250, 500, 750, 1000, 1500, 2000, 2500, Inf)
RAPM_THRESHOLDS <- c(seq(100, 1000, 100), seq(1250, 2500, 250))
RAPM_RULE_POSS_PER_SIDE <- 2000L   # RAPM_LEADERBOARD_MIN_POSS_PER_SIDE in rapm_engine.R
REF_BARS       <- c(0.5, 0.6, 0.7, 0.8)
MIN_PLAYERS    <- 30L              # a curve point is reported only with >= this many player-seasons
# --------------------------------------------------------------------------------

t_start <- Sys.time()

PROJECT_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  if (length(f) == 1L) {
    normalizePath(file.path(dirname(normalizePath(f)), ".."), winslash = "/", mustWork = FALSE)
  } else {
    normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  }
})
setwd(PROJECT_ROOT)
if (!file.exists("rapm_engine.R")) stop("Run from the NBA Analytics project root.")

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(jsonlite)
})

CACHE   <- "cache"
OUT_DIR <- file.path("docs", "research")
FIG_DIR <- file.path(OUT_DIR, "leader_reliability_study")
dir.create(CACHE, showWarnings = FALSE, recursive = TRUE)
dir.create(FIG_DIR, showWarnings = FALSE, recursive = TRUE)

say <- function(...) message(sprintf("[%s] ", format(Sys.time(), "%H:%M:%S")), sprintf(...))
say("Leader reliability study: seasons %s, %d bootstrap resamples, seed %d",
    paste(SEASONS, collapse = ","), N_BOOT, SEED)

# ==============================================================================
# 1. Data
# ==============================================================================
# Player boxes for 2024-2026 come from the project's player_box_scores_cache.rds
# (copied into this checkout's cache/); other seasons are pulled with hoopR into
# cache/lrs_player_box_<season>.rds. Team boxes always come from hoopR.
load_player_box <- function(season) {
  shared <- file.path(CACHE, "player_box_scores_cache.rds")
  if (file.exists(shared)) {
    x <- as.data.frame(readRDS(shared))
    if (season %in% unique(x$season)) {
      return(list(df = x[x$season == season, , drop = FALSE], source = "player_box_scores_cache.rds"))
    }
  }
  path <- file.path(CACHE, sprintf("lrs_player_box_%d.rds", season))
  if (!file.exists(path)) {
    say("Downloading hoopR player box %d", season)
    saveRDS(as.data.frame(hoopR::load_nba_player_box(seasons = season)), path)
  }
  list(df = as.data.frame(readRDS(path)), source = sprintf("hoopR::load_nba_player_box(%d)", season))
}
load_team_box <- function(season) {
  path <- file.path(CACHE, sprintf("lrs_team_box_%d.rds", season))
  if (!file.exists(path)) {
    say("Downloading hoopR team box %d", season)
    saveRDS(as.data.frame(hoopR::load_nba_team_box(seasons = season)), path)
  }
  as.data.frame(readRDS(path))
}

PB_COLS <- c(fgm = "field_goals_made", fga = "field_goals_attempted",
             fg3m = "three_point_field_goals_made", fg3a = "three_point_field_goals_attempted",
             ftm = "free_throws_made", fta = "free_throws_attempted",
             oreb = "offensive_rebounds", dreb = "defensive_rebounds", reb = "rebounds",
             ast = "assists", stl = "steals", blk = "blocks", tov = "turnovers", pts = "points")

data_audit <- list()
games_list <- list()
for (s in SEASONS) {
  pbl <- load_player_box(s)
  pb  <- pbl$df
  tb  <- load_team_box(s)
  pb  <- pb[pb$season_type == 2L, , drop = FALSE]
  tb  <- tb[tb$season_type == 2L, , drop = FALSE]
  n_rows   <- nrow(pb)
  dnp      <- !is.na(pb$did_not_play) & pb$did_not_play
  min_na   <- !dnp & is.na(pb$minutes)
  played   <- pb[!dnp & !min_na, , drop = FALSE]

  g <- data.frame(
    season     = s,
    game_id    = as.character(played$game_id),
    game_date  = as.Date(played$game_date),
    player_id  = as.character(played$athlete_id),
    player     = as.character(played$athlete_display_name),
    team_id    = as.character(played$team_id),
    min        = as.numeric(played$minutes),
    stringsAsFactors = FALSE
  )
  for (k in names(PB_COLS)) g[[k]] <- as.numeric(played[[PB_COLS[[k]]]])

  # Team minutes: sum of the team's player minutes in that game (ESPN whole minutes).
  tm_min <- aggregate(min ~ game_id + team_id, data = g, FUN = sum)
  names(tm_min)[3] <- "tm_min"
  team <- data.frame(
    game_id  = as.character(tb$game_id), team_id = as.character(tb$team_id),
    opp_id   = as.character(tb$opponent_team_id),
    tm_fgm   = as.numeric(tb$field_goals_made), tm_fga = as.numeric(tb$field_goals_attempted),
    tm_fta   = as.numeric(tb$free_throws_attempted), tm_tov = as.numeric(tb$turnovers),
    tm_oreb  = as.numeric(tb$offensive_rebounds), tm_dreb = as.numeric(tb$defensive_rebounds),
    stringsAsFactors = FALSE)
  team <- team[!duplicated(team[, c("game_id", "team_id")]), ]
  opp  <- team[, c("game_id", "team_id", "tm_oreb", "tm_dreb")]
  names(opp) <- c("game_id", "opp_id", "opp_oreb", "opp_dreb")
  team <- merge(team, opp, by = c("game_id", "opp_id"), all.x = TRUE)
  g <- merge(g, tm_min, by = c("game_id", "team_id"), all.x = TRUE)
  g <- merge(g, team[, setdiff(names(team), "opp_id")], by = c("game_id", "team_id"), all.x = TRUE)

  data_audit[[as.character(s)]] <- list(
    season = s, player_box_source = pbl$source,
    regular_season_rows = n_rows, did_not_play_rows = sum(dnp),
    played_but_minutes_missing_rows = sum(min_na), player_games_used = nrow(g),
    games = length(unique(g$game_id)), players = length(unique(g$player_id)),
    player_games_missing_any_box_stat = sum(!complete.cases(g[, names(PB_COLS)])),
    player_games_missing_team_context = sum(!complete.cases(g[, c("tm_min", "tm_fgm", "tm_fga", "tm_fta",
                                                                   "tm_tov", "tm_oreb", "tm_dreb",
                                                                   "opp_oreb", "opp_dreb")])))
  games_list[[as.character(s)]] <- g
  say("Season %d: %d player-games, %d games, %d players (%s)", s, nrow(g),
      length(unique(g$game_id)), length(unique(g$player_id)), pbl$source)
}
games <- do.call(rbind, games_list)
rm(games_list)

# Order each player-season by date and assign odd/even halves.
games$ps_id <- paste(games$season, games$player_id, sep = "_")
games <- games[order(games$ps_id, games$game_date, games$game_id), ]
games$k    <- ave(seq_len(nrow(games)), games$ps_id, FUN = seq_along)
games$half <- ifelse(games$k %% 2L == 1L, "A", "B")
ps_levels  <- sort(unique(games$ps_id))
games$ps   <- match(games$ps_id, ps_levels)
N_PS <- length(ps_levels)
say("%d player-seasons, %d player-games in total", N_PS, nrow(games))

# ==============================================================================
# 2. Stat definitions. value over a sample = sum(num) / sum(den); unit is what n counts.
# ==============================================================================
# Basketball Reference definitions, per game g, summed over the sample's games.
# share_g = MP_g / (TmMP_g / 5) is the player's share of his team's floor time.
with_share <- function(d) d$min / (d$tm_min / 5)
STATS <- list(
  # ---- counting, per game, unit = games
  pts  = list(group = "counting", label = "Points per game",           unit = "games", num = function(d) d$pts,  den = function(d) rep(1, nrow(d))),
  reb  = list(group = "counting", label = "Rebounds per game",         unit = "games", num = function(d) d$reb,  den = function(d) rep(1, nrow(d))),
  oreb = list(group = "counting", label = "Offensive rebounds per game", unit = "games", num = function(d) d$oreb, den = function(d) rep(1, nrow(d))),
  ast  = list(group = "counting", label = "Assists per game",          unit = "games", num = function(d) d$ast,  den = function(d) rep(1, nrow(d))),
  stl  = list(group = "counting", label = "Steals per game",           unit = "games", num = function(d) d$stl,  den = function(d) rep(1, nrow(d))),
  blk  = list(group = "counting", label = "Blocks per game",           unit = "games", num = function(d) d$blk,  den = function(d) rep(1, nrow(d))),
  tov  = list(group = "counting", label = "Turnovers per game",        unit = "games", num = function(d) d$tov,  den = function(d) rep(1, nrow(d))),
  fg3m = list(group = "counting", label = "3-pointers made per game",  unit = "games", num = function(d) d$fg3m, den = function(d) rep(1, nrow(d))),
  # ---- shooting, unit = attempts of that type
  fg_pct  = list(group = "shooting", label = "Field goal %",  unit = "fga",  num = function(d) d$fgm,  den = function(d) d$fga),
  fg3_pct = list(group = "shooting", label = "3-point %",     unit = "fg3a", num = function(d) d$fg3m, den = function(d) d$fg3a),
  ft_pct  = list(group = "shooting", label = "Free throw %",  unit = "fta",  num = function(d) d$ftm,  den = function(d) d$fta),
  # ---- rates, unit = minutes
  # eFG% = (FG + 0.5 * 3P) / FGA
  efg_pct = list(group = "rates", label = "Effective field goal %", unit = "minutes",
                 num = function(d) d$fgm + 0.5 * d$fg3m, den = function(d) d$fga),
  # TS% = PTS / (2 * (FGA + 0.44 * FTA))
  ts_pct  = list(group = "rates", label = "True shooting %", unit = "minutes",
                 num = function(d) d$pts, den = function(d) 2 * (d$fga + 0.44 * d$fta)),
  # TOV% = 100 * TOV / (FGA + 0.44 * FTA + TOV)
  tov_pct = list(group = "rates", label = "Turnover rate", unit = "minutes",
                 num = function(d) 100 * d$tov, den = function(d) d$fga + 0.44 * d$fta + d$tov),
  # ORB% = 100 * ORB * (TmMP / 5) / (MP * (TmORB + OppDRB))
  orb_pct = list(group = "rates", label = "Offensive rebound rate", unit = "minutes",
                 num = function(d) 100 * d$oreb, den = function(d) with_share(d) * (d$tm_oreb + d$opp_dreb)),
  # DRB% = 100 * DRB * (TmMP / 5) / (MP * (TmDRB + OppORB))
  drb_pct = list(group = "rates", label = "Defensive rebound rate", unit = "minutes",
                 num = function(d) 100 * d$dreb, den = function(d) with_share(d) * (d$tm_dreb + d$opp_oreb)),
  # AST% = 100 * AST / (((MP / (TmMP / 5)) * TmFG) - FG)
  ast_pct = list(group = "rates", label = "Assist rate", unit = "minutes",
                 num = function(d) 100 * d$ast, den = function(d) with_share(d) * d$tm_fgm - d$fgm),
  # USG% = 100 * ((FGA + 0.44 * FTA + TOV) * (TmMP / 5)) / (MP * (TmFGA + 0.44 * TmFTA + TmTOV))
  usg_pct = list(group = "rates", label = "Usage rate", unit = "minutes",
                 num = function(d) 100 * (d$fga + 0.44 * d$fta + d$tov),
                 den = function(d) with_share(d) * (d$tm_fga + 0.44 * d$tm_fta + d$tm_tov))
)
UNIT_COL  <- c(games = NA, fga = "fga", fg3a = "fg3a", fta = "fta", minutes = "min")
UNIT_GRID <- list(games = GRID_GAMES, fga = GRID_ATTEMPTS, fg3a = GRID_ATTEMPTS,
                  fta = GRID_ATTEMPTS, minutes = GRID_MINUTES)
UNIT_LABEL <- c(games = "games", fga = "field goal attempts", fg3a = "3-point attempts",
                fta = "free throw attempts", minutes = "minutes")

# ==============================================================================
# 3. Bootstrap weights (player-season blocks), shared by every stat and point.
# ==============================================================================
set.seed(SEED)
W <- matrix(0, nrow = N_PS, ncol = N_BOOT)
for (b in seq_len(N_BOOT)) W[, b] <- tabulate(sample.int(N_PS, N_PS, replace = TRUE), N_PS)

# Weighted Pearson correlation for every resample at once; idx = player-season rows.
boot_cor <- function(Wm, idx, x, y) {
  x <- x - mean(x); y <- y - mean(y)
  Wq  <- Wm[idx, , drop = FALSE]
  sw  <- colSums(Wq)
  sx  <- drop(crossprod(Wq, x));     sy  <- drop(crossprod(Wq, y))
  sxx <- drop(crossprod(Wq, x * x)); syy <- drop(crossprod(Wq, y * y))
  sxy <- drop(crossprod(Wq, x * y))
  num <- sw * sxy - sx * sy
  den <- sqrt(pmax(sw * sxx - sx^2, 0) * pmax(sw * syy - sy^2, 0))
  ifelse(den > 0, num / den, NA_real_)
}
sb  <- function(r) 2 * r / (1 + r)
q95 <- function(v) {
  v <- v[is.finite(v)]
  if (length(v) < 10) return(c(NA_real_, NA_real_))
  unname(quantile(v, c(0.025, 0.975)))
}

# ==============================================================================
# 4. Curves
# ==============================================================================
# Cumulative sums along each ordered sequence; for size n, the first row (per
# group) whose cumulative units reach n marks the end of the sample.
cum_frame <- function(d, num, den, unit, grp) {
  o <- order(grp, d$k)
  d <- d[o, ]; num <- num[o]; den <- den[o]; unit <- unit[o]; grp <- grp[o]
  data.frame(grp = grp, ps = d$ps,
             cnum = ave(num, grp, FUN = cumsum), cden = ave(den, grp, FUN = cumsum),
             cu = ave(unit, grp, FUN = cumsum))
}
first_reach <- function(cf, n) {
  r <- cf[!is.na(cf$cu) & cf$cu >= n, ]
  r[!duplicated(r$grp), ]
}

curve_rows <- list()
boot_store <- list()   # per stat: list(sh = matrix grid x B, sbv, ros)
for (st in names(STATS)) {
  spec <- STATS[[st]]
  num  <- spec$num(games); den <- spec$den(games)
  unit <- if (spec$unit == "games") rep(1, nrow(games)) else games[[UNIT_COL[[spec$unit]]]]
  grid <- UNIT_GRID[[spec$unit]]

  cf_half <- cum_frame(games, num, den, unit, paste(games$ps, games$half))
  cf_half$half <- sub("^.* ", "", cf_half$grp)
  cf_full <- cum_frame(games, num, den, unit, games$ps)
  tot <- cf_full[!duplicated(cf_full$grp, fromLast = TRUE), c("ps", "cnum", "cden", "cu")]
  names(tot) <- c("ps", "tnum", "tden", "tu")

  sh_b <- matrix(NA_real_, length(grid), N_BOOT); ros_b <- sh_b
  for (gi in seq_along(grid)) {
    n <- grid[gi]
    # ---- split-half
    a <- first_reach(cf_half[cf_half$half == "A", ], n)
    b <- first_reach(cf_half[cf_half$half == "B", ], n)
    m <- merge(a[, c("ps", "cnum", "cden", "cu")], b[, c("ps", "cnum", "cden", "cu")],
               by = "ps", suffixes = c("_a", "_b"))
    m$va <- ifelse(m$cden_a > 0, m$cnum_a / m$cden_a, NA_real_)
    m$vb <- ifelse(m$cden_b > 0, m$cnum_b / m$cden_b, NA_real_)
    ok <- is.finite(m$va) & is.finite(m$vb)
    n_ok <- sum(ok); n_miss <- sum(!ok)
    r <- if (n_ok >= MIN_PLAYERS) cor(m$va[ok], m$vb[ok]) else NA_real_
    if (n_ok >= MIN_PLAYERS) sh_b[gi, ] <- boot_cor(W, m$ps[ok], m$va[ok], m$vb[ok])
    ci <- q95(sh_b[gi, ]); ci_sb <- q95(sb(sh_b[gi, ]))
    curve_rows[[length(curve_rows) + 1]] <- data.frame(
      stat = st, group = spec$group, unit = spec$unit, method = "split_half", n = n,
      n_players = n_ok, n_missing = n_miss,
      mean_realised_units = if (n_ok > 0) mean(c(m$cu_a[ok], m$cu_b[ok])) else NA_real_,
      r = r, r_lo = ci[1], r_hi = ci[2],
      sb_sample = 2 * n, r_sb = sb(r), r_sb_lo = ci_sb[1], r_sb_hi = ci_sb[2])
    # ---- rest of season: first n units vs all remaining games, remainder >= n units
    f <- merge(first_reach(cf_full, n)[, c("ps", "cnum", "cden", "cu")], tot, by = "ps")
    f <- f[!is.na(f$tu) & (f$tu - f$cu) >= n, ]
    f$ve <- ifelse(f$cden > 0, f$cnum / f$cden, NA_real_)
    f$vr <- ifelse((f$tden - f$cden) > 0, (f$tnum - f$cnum) / (f$tden - f$cden), NA_real_)
    ok2 <- is.finite(f$ve) & is.finite(f$vr)
    n_ok2 <- sum(ok2)
    r2 <- if (n_ok2 >= MIN_PLAYERS) cor(f$ve[ok2], f$vr[ok2]) else NA_real_
    if (n_ok2 >= MIN_PLAYERS) ros_b[gi, ] <- boot_cor(W, f$ps[ok2], f$ve[ok2], f$vr[ok2])
    ci2 <- q95(ros_b[gi, ])
    curve_rows[[length(curve_rows) + 1]] <- data.frame(
      stat = st, group = spec$group, unit = spec$unit, method = "rest_of_season", n = n,
      n_players = n_ok2, n_missing = sum(!ok2),
      mean_realised_units = if (n_ok2 > 0) mean(f$cu[ok2]) else NA_real_,
      r = r2, r_lo = ci2[1], r_hi = ci2[2],
      sb_sample = NA_real_, r_sb = NA_real_, r_sb_lo = NA_real_, r_sb_hi = NA_real_)
  }
  boot_store[[st]] <- list(grid = grid, sh = sh_b, ros = ros_b)
  say("Curves done: %s", st)
}
curves <- do.call(rbind, curve_rows)

# ==============================================================================
# 5. RAPM split-half (rapm_engine.R sourced unchanged)
# ==============================================================================
# rapm_engine.R ends with `if (!interactive()) estimate_rapm_ratings()`. Sourcing it
# into an environment whose interactive() returns TRUE defines its functions without
# running that production fit. Nothing in the file is edited.
rapm_env <- new.env()
rapm_env$interactive <- function() TRUE
source("rapm_engine.R", local = rapm_env)
RAPM_LAMBDA_USED <- rapm_env$RAPM_LAMBDA

rapm_rows <- list(); rapm_audit <- list(); rapm_fail <- list()
for (s in RAPM_SEASONS) {
  res <- tryCatch({
    cache <- rapm_env$load_or_build_possession_cache(s)
    if (is.null(cache) || is.null(cache$possessions) || nrow(cache$possessions) == 0 ||
        length(cache$team_map) == 0) stop("no possession data for this season")
    rs_games <- sort(unique(as.character(cache$possessions$game_id[
      substr(as.character(cache$possessions$game_id), 1, 3) %in% rapm_env$RAPM_GAME_PREFIXES])))
    half_games <- list(A = rs_games[seq(1, length(rs_games), 2)],
                       B = rs_games[seq(2, length(rs_games), 2)])
    fits <- lapply(names(half_games), function(h) {
      ch <- cache
      ch$possessions <- cache$possessions[as.character(cache$possessions$game_id) %in% half_games[[h]], ]
      fr <- rapm_env$estimate_rapm_from_possessions(ch)
      data.frame(player_id = fr$player_id, player_name = fr$player_name,
                 off = fr$off_possessions, def = fr$def_possessions,
                 orapm = fr$orapm, drapm = fr$drapm, total_rapm = fr$total_rapm)
    })
    j <- merge(fits[[1]], fits[[2]], by = "player_id", suffixes = c("_a", "_b"))
    j$season <- s
    j$min_side_half <- pmin(j$off_a, j$def_a, j$off_b, j$def_b)
    rapm_audit[[as.character(s)]] <- list(season = s, regular_season_games = length(rs_games),
                                          games_half_a = length(half_games$A), games_half_b = length(half_games$B),
                                          players_rated_a = nrow(fits[[1]]), players_rated_b = nrow(fits[[2]]),
                                          players_in_both = nrow(j))
    j
  }, error = function(e) { rapm_fail[[as.character(s)]] <<- conditionMessage(e); NULL })
  if (!is.null(res)) rapm_rows[[as.character(s)]] <- res
  say("RAPM season %d: %s", s, if (is.null(res)) paste("FAILED -", rapm_fail[[as.character(s)]]) else
        sprintf("%d players rated in both halves", nrow(res)))
}
rapm_ok <- length(rapm_rows) >= 3
rapm_curves <- NULL; rapm_boot <- list()
if (rapm_ok) {
  rj <- do.call(rbind, rapm_rows)
  rj$rps <- seq_len(nrow(rj))
  set.seed(SEED + 1L)
  WR <- matrix(0, nrow(rj), N_BOOT)
  for (b in seq_len(N_BOOT)) WR[, b] <- tabulate(sample.int(nrow(rj), nrow(rj), replace = TRUE), nrow(rj))
  out <- list()
  for (m in c("orapm", "drapm", "total_rapm")) {
    xa <- rj[[paste0(m, "_a")]]; xb <- rj[[paste0(m, "_b")]]
    # disjoint bins
    for (bi in seq_len(length(RAPM_BIN_EDGES) - 1)) {
      lo <- RAPM_BIN_EDGES[bi]; hi <- RAPM_BIN_EDGES[bi + 1]
      idx <- which(rj$min_side_half >= lo & rj$min_side_half < hi)
      r <- if (length(idx) >= MIN_PLAYERS) cor(xa[idx], xb[idx]) else NA_real_
      bb <- if (length(idx) >= MIN_PLAYERS) boot_cor(WR, idx, xa[idx], xb[idx]) else rep(NA_real_, N_BOOT)
      ci <- q95(bb); ci_sb <- q95(sb(bb))
      out[[length(out) + 1]] <- data.frame(measure = m, kind = "bin", lo = lo, hi = hi,
        n_players = length(idx), r = r, r_lo = ci[1], r_hi = ci[2],
        r_sb = sb(r), r_sb_lo = ci_sb[1], r_sb_hi = ci_sb[2])
    }
    # "at least k per side in each half" curves
    th_b <- matrix(NA_real_, length(RAPM_THRESHOLDS), N_BOOT)
    for (ti in seq_along(RAPM_THRESHOLDS)) {
      k <- RAPM_THRESHOLDS[ti]
      idx <- which(rj$min_side_half >= k)
      r <- if (length(idx) >= MIN_PLAYERS) cor(xa[idx], xb[idx]) else NA_real_
      if (length(idx) >= MIN_PLAYERS) th_b[ti, ] <- boot_cor(WR, idx, xa[idx], xb[idx])
      ci <- q95(th_b[ti, ]); ci_sb <- q95(sb(th_b[ti, ]))
      out[[length(out) + 1]] <- data.frame(measure = m, kind = "threshold", lo = k, hi = Inf,
        n_players = length(idx), r = r, r_lo = ci[1], r_hi = ci[2],
        r_sb = sb(r), r_sb_lo = ci_sb[1], r_sb_hi = ci_sb[2])
    }
    rapm_boot[[m]] <- th_b
  }
  rapm_curves <- do.call(rbind, out)
}

# ==============================================================================
# 6. Crossings of the reference bars (reference points only)
# ==============================================================================
# First grid point at which the curve is at or above the bar. Interval: the same
# first-crossing rule applied to each bootstrap curve, percentile 95%. Resamples in
# which the curve never reaches the bar inside the grid are counted (share_not_reached)
# and enter the percentile as +Inf (reported as "beyond grid").
first_cross <- function(grid, v, bar) { i <- which(!is.na(v) & v >= bar); if (length(i)) grid[i[1]] else Inf }
cross_summary <- function(grid, point_curve, boot_mat, bar, scale = 1) {
  pt <- first_cross(grid, point_curve, bar)
  bc <- apply(boot_mat, 2, function(v) first_cross(grid, v, bar))
  qs <- unname(quantile(bc, c(0.025, 0.975), type = 1))
  list(bar = bar, point = if (is.finite(pt)) pt * scale else NULL,
       lo = if (is.finite(qs[1])) qs[1] * scale else NULL,
       hi = if (is.finite(qs[2])) qs[2] * scale else NULL,
       share_not_reached = mean(!is.finite(bc)))
}
crossings <- list()
for (st in names(STATS)) {
  bs <- boot_store[[st]]
  shc <- curves[curves$stat == st & curves$method == "split_half", ]
  roc <- curves[curves$stat == st & curves$method == "rest_of_season", ]
  crossings[[st]] <- list(
    split_half     = lapply(REF_BARS, function(b) cross_summary(bs$grid, shc$r, bs$sh, b)),
    spearman_brown = lapply(REF_BARS, function(b) cross_summary(bs$grid, shc$r_sb, sb(bs$sh), b, scale = 2)),
    rest_of_season = lapply(REF_BARS, function(b) cross_summary(bs$grid, roc$r, bs$ros, b)))
}
rapm_crossings <- list()
if (rapm_ok) for (m in names(rapm_boot)) {
  th <- rapm_curves[rapm_curves$measure == m & rapm_curves$kind == "threshold", ]
  rapm_crossings[[m]] <- list(
    split_half     = lapply(REF_BARS, function(b) cross_summary(RAPM_THRESHOLDS, th$r, rapm_boot[[m]], b)),
    spearman_brown = lapply(REF_BARS, function(b) cross_summary(RAPM_THRESHOLDS, th$r_sb, sb(rapm_boot[[m]]), b, scale = 2)))
}

# ==============================================================================
# 7. Plots
# ==============================================================================
plot_group <- function(grp, file) {
  d <- curves[curves$group == grp, ]
  d$label <- vapply(d$stat, function(s) STATS[[s]]$label, "")
  sh <- d[d$method == "split_half", ]
  long <- rbind(
    data.frame(label = sh$label, x = sh$n, r = sh$r, lo = sh$r_lo, hi = sh$r_hi,
               curve = "Split-half r (sample n)"),
    data.frame(label = sh$label, x = sh$sb_sample, r = sh$r_sb, lo = sh$r_sb_lo, hi = sh$r_sb_hi,
               curve = "Spearman-Brown (sample 2n)"),
    data.frame(label = d$label[d$method == "rest_of_season"], x = d$n[d$method == "rest_of_season"],
               r = d$r[d$method == "rest_of_season"], lo = d$r_lo[d$method == "rest_of_season"],
               hi = d$r_hi[d$method == "rest_of_season"], curve = "Rest of season r (first n)"))
  unit <- unique(d$unit)
  xlab <- if (length(unit) == 1) paste("Sample size,", UNIT_LABEL[[unit]]) else "Sample size (attempts of that shot type)"
  p <- ggplot(long, aes(x, r, colour = curve, fill = curve)) +
    geom_hline(yintercept = REF_BARS, linetype = "dashed", colour = "grey55", linewidth = 0.3) +
    geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.18, colour = NA, na.rm = TRUE) +
    geom_line(linewidth = 0.7, na.rm = TRUE) +
    facet_wrap(~ label, scales = "free_x") +
    coord_cartesian(ylim = c(0, 1)) +
    labs(x = xlab, y = "Correlation", colour = NULL, fill = NULL,
         title = sprintf("Leader reliability: %s stats", grp),
         subtitle = sprintf("NBA regular seasons %s; bands = player-season bootstrap 95%% (%d resamples); dashed = bars %s",
                            paste(range(SEASONS), collapse = "-"), N_BOOT, paste(REF_BARS, collapse = ", "))) +
    theme_minimal(base_size = 11) + theme(legend.position = "bottom")
  ggsave(file, p, width = 11, height = if (grp == "shooting") 4.5 else 7.5, dpi = 120, bg = "white")
}
plot_files <- c(counting = "counting.png", shooting = "shooting.png", rates = "rates.png", rapm = "rapm.png")
for (g in c("counting", "shooting", "rates")) plot_group(g, file.path(FIG_DIR, plot_files[[g]]))
if (rapm_ok) {
  th <- rapm_curves[rapm_curves$kind == "threshold", ]
  lab <- c(orapm = "Offensive RAPM", drapm = "Defensive RAPM", total_rapm = "Total RAPM")
  long <- rbind(
    data.frame(label = lab[th$measure], x = th$lo, r = th$r, lo = th$r_lo, hi = th$r_hi,
               curve = "Split-half r (>= k per side in each half)"),
    data.frame(label = lab[th$measure], x = 2 * th$lo, r = th$r_sb, lo = th$r_sb_lo, hi = th$r_sb_hi,
               curve = "Spearman-Brown (season equivalent, >= 2k per side)"))
  p <- ggplot(long, aes(x, r, colour = curve, fill = curve)) +
    geom_hline(yintercept = REF_BARS, linetype = "dashed", colour = "grey55", linewidth = 0.3) +
    geom_vline(xintercept = RAPM_RULE_POSS_PER_SIDE, colour = "firebrick", linewidth = 0.4) +
    geom_vline(xintercept = RAPM_RULE_POSS_PER_SIDE / 2, colour = "firebrick", linewidth = 0.4, linetype = "dotted") +
    geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.18, colour = NA, na.rm = TRUE) +
    geom_line(linewidth = 0.7, na.rm = TRUE) + geom_point(size = 1, na.rm = TRUE) +
    facet_wrap(~ label) + coord_cartesian(ylim = c(0, 1)) +
    labs(x = "Possessions per side (split-half curve: minimum in each half; Spearman-Brown curve: season equivalent)",
         y = "Correlation", colour = NULL, fill = NULL,
         title = "Leader reliability: RAPM, odd-game fit vs even-game fit",
         subtitle = sprintf("Seasons %s; solid red = current rule, %d each side (season scale); dotted red = %d each side in each half; bands = bootstrap 95%%",
                            paste(names(rapm_rows), collapse = ","), RAPM_RULE_POSS_PER_SIDE, RAPM_RULE_POSS_PER_SIDE / 2)) +
    theme_minimal(base_size = 11) + theme(legend.position = "bottom")
  ggsave(file.path(FIG_DIR, plot_files[["rapm"]]), p, width = 11, height = 4.8, dpi = 120, bg = "white")
}

runtime_min <- as.numeric(difftime(Sys.time(), t_start, units = "mins"))

# ==============================================================================
# 8. Results JSON
# ==============================================================================
df_rows <- function(d) lapply(seq_len(nrow(d)), function(i) as.list(d[i, , drop = FALSE]))
stats_json <- lapply(names(STATS), function(st) {
  s <- STATS[[st]]
  list(label = s$label, group = s$group, unit = s$unit, unit_label = UNIT_LABEL[[s$unit]],
       split_half = df_rows(curves[curves$stat == st & curves$method == "split_half",
                                   c("n", "n_players", "n_missing", "mean_realised_units", "r", "r_lo", "r_hi",
                                     "sb_sample", "r_sb", "r_sb_lo", "r_sb_hi")]),
       rest_of_season = df_rows(curves[curves$stat == st & curves$method == "rest_of_season",
                                       c("n", "n_players", "n_missing", "mean_realised_units", "r", "r_lo", "r_hi")]),
       crossings = crossings[[st]])
})
names(stats_json) <- names(STATS)

rule_rows <- NULL
if (rapm_ok) {
  rule_rows <- rapm_curves[rapm_curves$kind == "threshold" & rapm_curves$lo == RAPM_RULE_POSS_PER_SIDE / 2, ]
}
results <- list(
  issue = "NBA_analytics#253",
  note = "Reference points only. No qualifying minimum is chosen here; the owner sets them after reviewing the curves.",
  settings = list(seasons = SEASONS, rapm_seasons = RAPM_SEASONS, seed = SEED, n_boot = N_BOOT,
                  grid_games = GRID_GAMES, grid_attempts = GRID_ATTEMPTS, grid_minutes = GRID_MINUTES,
                  rapm_bin_edges_per_side_per_half = RAPM_BIN_EDGES[is.finite(RAPM_BIN_EDGES)],
                  rapm_thresholds_per_side_per_half = RAPM_THRESHOLDS, reference_bars = REF_BARS,
                  min_players_per_point = MIN_PLAYERS, rapm_lambda = RAPM_LAMBDA_USED,
                  rapm_rule_poss_per_side = RAPM_RULE_POSS_PER_SIDE),
  data_audit = unname(data_audit),
  player_seasons = N_PS,
  stats = stats_json,
  rapm = list(
    available = rapm_ok,
    seasons_fit = as.integer(names(rapm_rows)),
    seasons_failed = rapm_fail,
    audit = unname(rapm_audit),
    player_seasons = if (rapm_ok) nrow(rj) else 0L,
    bins = if (rapm_ok) df_rows(rapm_curves[rapm_curves$kind == "bin", ]) else list(),
    thresholds = if (rapm_ok) df_rows(rapm_curves[rapm_curves$kind == "threshold", ]) else list(),
    at_current_rule = if (rapm_ok) df_rows(rule_rows) else list(),
    crossings = rapm_crossings),
  runtime_minutes = round(runtime_min, 2)
)
writeLines(toJSON(results, auto_unbox = TRUE, digits = 4, null = "null", na = "null", pretty = TRUE),
           file.path(OUT_DIR, "leader_reliability_study_results.json"))

# ==============================================================================
# 9. Report
# ==============================================================================
f2 <- function(x) ifelse(is.na(x), "NA", sprintf("%.2f", x))
fmt_cross <- function(cx) {
  if (is.null(cx$point)) return(sprintf("not reached (%.0f%% of resamples)", 100 * cx$share_not_reached))
  hi <- if (is.null(cx$hi)) "beyond grid" else format(cx$hi, big.mark = ",")
  lo <- if (is.null(cx$lo)) "beyond grid" else format(cx$lo, big.mark = ",")
  sprintf("%s [%s, %s]", format(cx$point, big.mark = ","), lo, hi)
}
cross_table <- function(stats, unit_fun, cx_list, kinds) {
  lines <- c(paste0("| Stat | Unit | Curve | ", paste(sprintf("bar %.1f", REF_BARS), collapse = " | "), " |"),
             paste0("|", paste(rep("---", 3 + length(REF_BARS)), collapse = "|"), "|"))
  for (st in stats) for (kd in names(kinds)) {
    cx <- cx_list[[st]][[kd]]
    lines <- c(lines, sprintf("| %s | %s | %s | %s |", unit_fun(st)[1], unit_fun(st)[2], kinds[[kd]],
                              paste(vapply(cx, fmt_cross, ""), collapse = " | ")))
  }
  lines
}
point_at <- function(st, method, n) {
  r <- curves[curves$stat == st & curves$method == method & curves$n == n, ]
  if (!nrow(r)) return("NA")
  sprintf("%s [%s, %s] (N=%d)", f2(r$r), f2(r$r_lo), f2(r$r_hi), r$n_players)
}
snap_n <- c(games = 20, fga = 200, fg3a = 100, fta = 100, minutes = 500)
snap <- c("| Stat | Unit | n | Split-half r at n | Spearman-Brown (2n) | Rest-of-season r at n |",
          "|---|---|---|---|---|---|")
for (st in names(STATS)) {
  u <- STATS[[st]]$unit; n <- snap_n[[u]]
  r <- curves[curves$stat == st & curves$method == "split_half" & curves$n == n, ]
  snap <- c(snap, sprintf("| %s | %s | %s | %s | %s | %s |", STATS[[st]]$label, UNIT_LABEL[[u]], n,
                          point_at(st, "split_half", n),
                          if (nrow(r)) sprintf("%s [%s, %s]", f2(r$r_sb), f2(r$r_sb_lo), f2(r$r_sb_hi)) else "NA",
                          point_at(st, "rest_of_season", n)))
}
audit_tbl <- c("| Season | Player box source | Regular-season rows | Did not play | Played, minutes missing | Player-games used | Games | Rows missing a box stat | Rows missing team context |",
               "|---|---|---|---|---|---|---|---|---|")
for (a in data_audit) audit_tbl <- c(audit_tbl, sprintf("| %d | %s | %s | %s | %d | %s | %d | %d | %d |",
  a$season, a$player_box_source, format(a$regular_season_rows, big.mark = ","), format(a$did_not_play_rows, big.mark = ","),
  a$played_but_minutes_missing_rows, format(a$player_games_used, big.mark = ","), a$games,
  a$player_games_missing_any_box_stat, a$player_games_missing_team_context))

lab_unit <- function(st) c(STATS[[st]]$label, UNIT_LABEL[[STATS[[st]]$unit]])
kinds_box <- c(split_half = "split-half r, sample n", spearman_brown = "Spearman-Brown, sample 2n",
               rest_of_season = "rest-of-season r, first n")

rapm_section <- if (rapm_ok) {
  bins <- rapm_curves[rapm_curves$kind == "bin", ]
  bt <- c("| Measure | Possessions per side in each half | Player-seasons | Split-half r [95%] | Spearman-Brown [95%] |",
          "|---|---|---|---|---|")
  for (i in seq_len(nrow(bins))) bt <- c(bt, sprintf("| %s | %s-%s | %d | %s [%s, %s] | %s [%s, %s] |",
    bins$measure[i], format(bins$lo[i], big.mark = ","), ifelse(is.finite(bins$hi[i]), format(bins$hi[i] - 1, big.mark = ","), "up"),
    bins$n_players[i], f2(bins$r[i]), f2(bins$r_lo[i]), f2(bins$r_hi[i]), f2(bins$r_sb[i]), f2(bins$r_sb_lo[i]), f2(bins$r_sb_hi[i])))
  th <- rapm_curves[rapm_curves$kind == "threshold", ]
  tt <- c("| Measure | At least k per side in each half | Season equivalent (2k) | Player-seasons | Split-half r [95%] | Spearman-Brown [95%] |",
          "|---|---|---|---|---|---|")
  for (i in seq_len(nrow(th))) tt <- c(tt, sprintf("| %s | %s | %s | %d | %s [%s, %s] | %s [%s, %s] |",
    th$measure[i], format(th$lo[i], big.mark = ","), format(2 * th$lo[i], big.mark = ","), th$n_players[i],
    f2(th$r[i]), f2(th$r_lo[i]), f2(th$r_hi[i]), f2(th$r_sb[i]), f2(th$r_sb_lo[i]), f2(th$r_sb_hi[i])))
  rule_lines <- vapply(seq_len(nrow(rule_rows)), function(i) sprintf(
    "- %s: split-half r %s [%s, %s] among the %d player-seasons with at least %s per side in each half; Spearman-Brown (season scale, about %s per side) %s [%s, %s].",
    rule_rows$measure[i], f2(rule_rows$r[i]), f2(rule_rows$r_lo[i]), f2(rule_rows$r_hi[i]), rule_rows$n_players[i],
    format(RAPM_RULE_POSS_PER_SIDE / 2, big.mark = ","), format(RAPM_RULE_POSS_PER_SIDE, big.mark = ","),
    f2(rule_rows$r_sb[i]), f2(rule_rows$r_sb_lo[i]), f2(rule_rows$r_sb_hi[i])), "")
  c("## RAPM",
    "",
    sprintf("Seasons fit: %s. For each season the regular-season games (NBA Stats game ids with prefix `002`) are sorted by game id, which follows the schedule, and alternately assigned to an odd half and an even half. `estimate_rapm_from_possessions()` from `rapm_engine.R` (sourced unchanged, lambda = %s) is fit on each half separately and players rated in both halves are paired. A player-season's exposure is the smallest of his offensive and defensive possessions across the two halves (\"possessions per side in each half\").",
            paste(names(rapm_rows), collapse = ", "), format(RAPM_LAMBDA_USED)),
    if (length(rapm_fail)) sprintf("Seasons that could not be fit: %s.", paste(sprintf("%s (%s)", names(rapm_fail), unlist(rapm_fail)), collapse = "; ")) else "All requested seasons were fit.",
    "",
    "Rest-of-season check for RAPM: not run. RAPM is a joint ridge fit over all players, so a player-specific \"first n possessions vs the rest\" split would need a separate refit for every player and cutoff; the split-half fits above are the RAPM reliability measure delivered here.",
    "",
    "No synthetic RAPM path is used: the script calls only `load_or_build_possession_cache()` and `estimate_rapm_from_possessions()`, which fit published possession data, and never calls `estimate_rapm_ratings()` or any fallback.",
    "",
    "![RAPM curves](leader_reliability_study/rapm.png)",
    "",
    sprintf("### Comparison with the current rule (%s possessions each side)", format(RAPM_RULE_POSS_PER_SIDE, big.mark = ",")),
    "",
    sprintf("Each half holds about half a season, so the current season-scale rule corresponds to about %s per side in each half; the Spearman-Brown value projects the half-season correlation to a full-season sample.",
            format(RAPM_RULE_POSS_PER_SIDE / 2, big.mark = ",")),
    "",
    rule_lines,
    "",
    "Caveats specific to RAPM: ridge shrinkage pulls low-exposure players toward 0 in both halves, and half-season fits carry the same penalty as full-season fits on half the data, so these correlations describe the engine as configured, not an unshrunk rating. The bootstrap resamples player-seasons from the fitted pairs; it does not refit the ridge, so its intervals omit fitting uncertainty. Players in the same lineups share possessions, so ratings are not independent across players.",
    "",
    "### By possessions-per-side bins",
    "", bt, "",
    "### At least k possessions per side in each half",
    "", tt, "")
} else {
  c("## RAPM", "",
    sprintf("Not delivered: fewer than 3 seasons could be fit. Failures: %s.",
            paste(sprintf("%s (%s)", names(rapm_fail), unlist(rapm_fail)), collapse = "; ")), "")
}

rapm_cross_lines <- if (rapm_ok) {
  lines <- c(paste0("| RAPM measure | Curve | ", paste(sprintf("bar %.1f", REF_BARS), collapse = " | "), " |"),
             paste0("|", paste(rep("---", 2 + length(REF_BARS)), collapse = "|"), "|"))
  for (m in names(rapm_crossings)) {
    lines <- c(lines,
      sprintf("| %s | split-half r, at least k per side in each half | %s |", m, paste(vapply(rapm_crossings[[m]]$split_half, fmt_cross, ""), collapse = " | ")),
      sprintf("| %s | Spearman-Brown, season scale (2k per side) | %s |", m, paste(vapply(rapm_crossings[[m]]$spearman_brown, fmt_cross, ""), collapse = " | ")))
  }
  c(lines, "",
    "RAPM crossings use the \"at least k per side in each half\" curves, which pool every player-season at or above k. Because that pool always includes the high-exposure players, the curve can sit above a bar at the smallest k; a crossing at the first grid point means exactly that, and the bin table in the RAPM section shows how low the correlation is within low-exposure bins on their own.")
} else "RAPM crossings not available (see the RAPM section)."

report <- c(
  "# Leader reliability study (issue #253)",
  "",
  "Research only. This study measures how quickly each league-leader stat settles as a player's sample grows. It does not choose any qualifying minimum and changes no production code; the owner reviews these curves and sets the minimums (used by the leaders panel, #254).",
  "",
  sprintf("Generated by `tools/leader_reliability_study.R` (seed %d, %d bootstrap resamples). Runtime of this run: %.1f minutes.", SEED, N_BOOT, runtime_min),
  "",
  "## Data",
  "",
  sprintf("- NBA regular seasons %s (hoopR end-year numbering, so 2026 is 2025-26). 2020 is left out because that regular season was halted and never completed; 2026-27 is in progress and is not used. %s player-seasons.",
          paste(SEASONS, collapse = ", "), format(N_PS, big.mark = ",")),
  "- Player box scores: ESPN via hoopR (`load_nba_player_box`; 2024-2026 from the project's player box cache, which holds the same hoopR table). Team box scores: `hoopR::load_nba_team_box`.",
  "- Regular season only (`season_type == 2`). Rows flagged `did_not_play` are excluded. Rows not flagged but with no minutes recorded are excluded and counted below. Nothing is imputed: a missing value makes any sample that contains it missing at that point, and the number of such player-seasons is reported at every point (`n_missing` in the JSON).",
  "- A player-season covers every team the player played for that season. Team context (team minutes, team and opponent totals) is taken game by game for the team he played for in that game.",
  "",
  audit_tbl,
  "",
  "## Methods",
  "",
  "- **Split-half reliability.** Each player-season's games are numbered in date order; odd-numbered games form half A and even-numbered games half B. At each sample size n the stat is computed on each half from the first n units of that half, for every player-season whose two halves each reach n units, and the two halves are correlated across player-seasons (Pearson). The raw correlation is the reliability of an n-unit sample. The Spearman-Brown value 2r / (1 + r) is the projected reliability of a 2n-unit sample and is plotted at 2n.",
  "- **Rest-of-season check.** The stat over a player's first n units of the season against the same stat over all of his remaining games that season. Rule: only player-seasons whose remaining games hold at least n units are used, so the remainder is never smaller than the early sample.",
  "- **Units.** Counting stats: games played. Shooting: attempts of that shot type. Rates: minutes. Games are indivisible, so for attempts and minutes a sample of n is the shortest run of whole games whose cumulative units reach n; the mean realised size is reported in the JSON (`mean_realised_units`).",
  sprintf("- **Intervals.** Player-season block bootstrap: player-seasons are resampled with replacement (%d resamples, seed %d), every curve point is recomputed on each resample with the same draw, and the 2.5th and 97.5th percentiles are reported. Points with fewer than %d player-seasons are not reported.", N_BOOT, SEED, MIN_PLAYERS),
  "- **Reading the curves at large n.** Only high-volume players reach large samples, so the player pool narrows as n grows; a narrower spread of true talent lowers correlations. A curve that flattens or dips at the right-hand end reflects that selection as well as noise, and the player count at each point should be read with it.",
  "- **Who is in the pool.** As issue #253 specifies, every player-season that reaches n is correlated, from deep bench to stars. The spread of true levels across that pool is wide (a starter's points per game differ from a reserve's mostly through role and minutes), and a wide spread makes correlations high at small n. Separating players near the top of a leader list from each other is a harder task than this pool-wide correlation measures, so the crossings below describe the whole league, not the top of a list.",
  "",
  "## Rate formulas",
  "",
  "Basketball Reference definitions, computed from player and team box scores. For a sample of games each rate is the sum of its per-game numerators over the sum of its per-game denominators. MP is the player's minutes; TmMP is the sum of his team's player minutes in that game; Tm and Opp are the team box totals of his team and its opponent in that game. Team turnovers are the team box `turnovers` (player-credited turnovers, matching the sum of player turnovers).",
  "",
  "| Rate | Formula |",
  "|---|---|",
  "| Effective field goal % | (FG + 0.5 x 3P) / FGA |",
  "| True shooting % | PTS / (2 x (FGA + 0.44 x FTA)) |",
  "| Turnover rate | 100 x TOV / (FGA + 0.44 x FTA + TOV) |",
  "| Offensive rebound rate | 100 x ORB x (TmMP / 5) / (MP x (TmORB + OppDRB)) |",
  "| Defensive rebound rate | 100 x DRB x (TmMP / 5) / (MP x (TmDRB + OppORB)) |",
  "| Assist rate | 100 x AST / (((MP / (TmMP / 5)) x TmFG) - FG) |",
  "| Usage rate | 100 x ((FGA + 0.44 x FTA + TOV) x (TmMP / 5)) / (MP x (TmFGA + 0.44 x TmFTA + TmTOV)) |",
  "",
  "## Curves",
  "",
  "### Counting stats (per game, by games played)",
  "", "![Counting stats](leader_reliability_study/counting.png)", "",
  "### Shooting percentages (by attempts)",
  "", "![Shooting](leader_reliability_study/shooting.png)", "",
  "### Rates (by minutes)",
  "", "![Rates](leader_reliability_study/rates.png)", "",
  "### Snapshot at one sample size per unit",
  "",
  "Correlation [bootstrap 95%] and player-season count. The full curves are in the results JSON.",
  "", snap, "",
  rapm_section,
  "## Reference points for the owner's review",
  "",
  "For each stat, the first grid sample size at which each curve reaches the bar, with a bootstrap 95% interval for that crossing. \"Beyond grid\" means some resamples did not reach the bar inside the grid. These are reference points for review, not chosen values. Split-half and rest-of-season values are in the stat's own unit for an n-unit sample; Spearman-Brown values are the projected sample (2n) at which reliability reaches the bar.",
  "",
  "### Counting, shooting and rates",
  "",
  cross_table(names(STATS), lab_unit, crossings, kinds_box),
  "",
  "### RAPM (possessions per side)",
  "",
  rapm_cross_lines,
  ""
)
writeLines(report, file.path(OUT_DIR, "leader_reliability_study.md"))

say("Done in %.1f minutes. Wrote %s, %s and %d plots.", runtime_min,
    file.path(OUT_DIR, "leader_reliability_study.md"), file.path(OUT_DIR, "leader_reliability_study_results.json"),
    length(list.files(FIG_DIR, pattern = "\\.png$")))
