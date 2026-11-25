# ==============================================================================
# tools/leader_reliability_study.R
#
# Issue #267: how large a sample does a player need before each leader stat
# reflects her real level rather than noise? RESEARCH ONLY. This script is not
# wired into the pipeline, changes no production setting and chooses no
# qualifying minimum. It measures reliability curves; the owner reads them and
# sets the minimums (the WNBA leaders panel consumes them).
#
# It repeats the NBA study (NBA_analytics#253, tools/leader_reliability_study.R
# on that repo's research/leader-reliability branch) for the WNBA, reusing its
# code and report structure. Differences from the NBA script:
#   - data come from wehoop (ESPN player/team box scores, WNBA Stats possessions);
#   - WNBA seasons are about 40 games, so many more past seasons are pooled and
#     every crossing is also reported as a share of the season;
#   - regular season means ESPN season_type 2 AND schedule type "STD", which
#     drops the All-Star game and the Commissioner's Cup final (neither counts
#     in the standings or season statistics);
#   - RAPM uses this repo's rapm_engine.R (possession-level ridge).
#
# WHAT IT DOES
#   1. Per-game counting stats (sample unit: games played), shooting
#      percentages (unit: attempts of that shot type) and rate stats (unit:
#      minutes), from ESPN player and team box scores via wehoop, regular season
#      only, rows where the player did not play excluded.
#        - Split-half reliability: each player-season's games are numbered by
#          date; odd-numbered games form half A, even-numbered games half B. At
#          sample size n the stat is computed on each half from the first n
#          units of that half and correlated across player-seasons (Pearson).
#          Spearman-Brown: r_sb = 2r / (1 + r), the reliability of a sample of
#          2n units.
#        - Rest-of-season check: the stat over a player's first n units of the
#          season against the same stat over ALL her remaining games that
#          season, for player-seasons whose remainder holds at least n units.
#   2. RAPM (offensive, defensive, total): rapm_engine.R is sourced unchanged
#      and its build_possession_design_matrix() / solve_ridge_rapm() are called
#      on the odd-numbered and the even-numbered regular-season games of each
#      season separately, with the engine's own lambda and the same scaling,
#      sign convention and centring as its fit_rapm_ratings(). Ratings are
#      correlated across halves by possessions-per-side bins. The engine's
#      box-score fallback and its live entry points are never called.
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
# Run from the project root (fresh session). The worktree's renv library may be
# empty, so --no-init-file uses the user library (wehoop, dplyr, ggplot2, ...):
#   Rscript --no-init-file tools/leader_reliability_study.R
# Smoke test with fewer resamples:
#   LRS_N_BOOT=50 Rscript --no-init-file tools/leader_reliability_study.R
# Re-run each offseason by changing SEASONS / RAPM_SEASONS below.
# ==============================================================================

# ---- Settings (change these to re-run the study) ------------------------------
# WNBA seasons are calendar years. 2003 and 2004 are left out: wehoop's ESPN player
# box covers only 77% and 90% of their scheduled regular-season games (see
# MIN_GAME_COVERAGE). 2002 has no wehoop team box. 2027 has not started.
SEASONS        <- 2005:2026
RAPM_SEASONS   <- SEASONS            # WNBA Stats possessions exist for 2005-2026
SEED           <- 267L
N_BOOT         <- as.integer(Sys.getenv("LRS_N_BOOT", "1000"))
GRID_GAMES     <- 1:22               # half of a 44-game season
GRID_ATTEMPTS  <- c(seq(10, 100, 10), seq(125, 400, 25))
GRID_MINUTES   <- c(seq(25, 200, 25), seq(250, 800, 50))
# RAPM: possessions per side within EACH half (min over the two halves and the two
# sides). Bins are half-open [lo, hi). Thresholds give "at least k" curves.
RAPM_BIN_EDGES  <- c(0, 125, 250, 375, 500, 750, 1000, 1250, Inf)
RAPM_THRESHOLDS <- c(seq(50, 500, 50), seq(600, 1400, 100))
REF_BARS       <- c(0.5, 0.6, 0.7, 0.8)
MIN_PLAYERS    <- 30L                # a curve point is reported only with >= this many player-seasons
MIN_GAME_COVERAGE <- 0.95            # a season is used only if the player box covers this share of its scheduled games
SEASON_GAMES_CONSTANT <- "WNBA_SEASON_GAMES"  # config.R constant giving the season length used for "share of season"
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
if (!file.exists("rapm_engine.R")) stop("Run from the WNBA Analytics project root.")

# Season length is read from config.R, never restated here.
cfg <- new.env()
sys.source("config.R", envir = cfg)
setwd(PROJECT_ROOT)
SEASON_GAMES_REF <- as.integer(get(SEASON_GAMES_CONSTANT, envir = cfg))

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
say("Leader reliability study (WNBA): seasons %s, %d bootstrap resamples, seed %d",
    paste(range(SEASONS), collapse = "-"), N_BOOT, SEED)

# ==============================================================================
# 1. Data
# ==============================================================================
# Every table is pulled once with wehoop into cache/lrs_<table>_<season>.rds and
# read from there on later runs.
cached_pull <- function(name, season, fn) {
  path <- file.path(CACHE, sprintf("lrs_%s_%d.rds", name, season))
  if (!file.exists(path)) {
    say("Downloading wehoop %s %d", name, season)
    saveRDS(as.data.frame(fn(seasons = season)), path)
  }
  as.data.frame(readRDS(path))
}
load_player_box <- function(s) cached_pull("player_box", s, wehoop::load_wnba_player_box)
load_team_box   <- function(s) cached_pull("team_box", s, wehoop::load_wnba_team_box)
load_schedule   <- function(s) cached_pull("schedule", s, wehoop::load_wnba_schedule)
load_poss       <- function(s) cached_pull("possessions", s, wehoop::load_wnba_stats_possessions)

PB_COLS <- c(fgm = "field_goals_made", fga = "field_goals_attempted",
             fg3m = "three_point_field_goals_made", fg3a = "three_point_field_goals_attempted",
             ftm = "free_throws_made", fta = "free_throws_attempted",
             oreb = "offensive_rebounds", dreb = "defensive_rebounds", reb = "rebounds",
             ast = "assists", stl = "steals", blk = "blocks", tov = "turnovers", pts = "points")

data_audit <- list()
games_list <- list()
seasons_dropped <- list()
for (s in SEASONS) {
  pb <- load_player_box(s)
  tb <- load_team_box(s)
  sc <- load_schedule(s)
  std_ids <- as.character(sc$game_id[sc$season_type == 2L & sc$type_abbreviation == "STD"])
  pb  <- pb[pb$season_type == 2L, , drop = FALSE]
  tb  <- tb[tb$season_type == 2L, , drop = FALSE]
  non_std_games <- length(setdiff(unique(as.character(pb$game_id)), std_ids))
  pb  <- pb[as.character(pb$game_id) %in% std_ids, , drop = FALSE]
  tb  <- tb[as.character(tb$game_id) %in% std_ids, , drop = FALSE]
  coverage <- length(unique(pb$game_id)) / length(std_ids)
  if (coverage < MIN_GAME_COVERAGE) {
    seasons_dropped[[as.character(s)]] <- sprintf("player box covers %.0f%% of scheduled games", 100 * coverage)
    say("Season %d dropped: %s", s, seasons_dropped[[as.character(s)]])
    next
  }
  n_rows   <- nrow(pb)
  dnp      <- !is.na(pb$did_not_play) & pb$did_not_play
  min_na   <- !dnp & is.na(pb$minutes)
  min_na_with_stats <- sum(min_na & !is.na(pb$points) & pb$points > 0)
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
  # Team turnovers: sum of the team's player turnovers in that game. The team box
  # `turnovers` column changes meaning across seasons (before 2013 it often differs
  # from the player sum, and `total_turnovers` matches instead), so the player sum
  # is used for every season: the same definition throughout, from real box rows.
  tm_tov_p <- aggregate(tov ~ game_id + team_id, data = g, FUN = sum, na.action = na.pass)
  names(tm_tov_p)[3] <- "tm_tov"
  team <- data.frame(
    game_id  = as.character(tb$game_id), team_id = as.character(tb$team_id),
    opp_id   = as.character(tb$opponent_team_id),
    tm_fgm   = as.numeric(tb$field_goals_made), tm_fga = as.numeric(tb$field_goals_attempted),
    tm_fta   = as.numeric(tb$free_throws_attempted), tb_tov = as.numeric(tb$turnovers),
    tm_oreb  = as.numeric(tb$offensive_rebounds), tm_dreb = as.numeric(tb$defensive_rebounds),
    stringsAsFactors = FALSE)
  team <- team[!duplicated(team[, c("game_id", "team_id")]), ]
  opp  <- team[, c("game_id", "team_id", "tm_oreb", "tm_dreb")]
  names(opp) <- c("game_id", "opp_id", "opp_oreb", "opp_dreb")
  team <- merge(team, opp, by = c("game_id", "opp_id"), all.x = TRUE)
  g <- merge(g, tm_min, by = c("game_id", "team_id"), all.x = TRUE)
  g <- merge(g, tm_tov_p, by = c("game_id", "team_id"), all.x = TRUE)
  g <- merge(g, team[, setdiff(names(team), "opp_id")], by = c("game_id", "team_id"), all.x = TRUE)

  # Recorded for the audit: share of team-games where the team box `turnovers`
  # equals the player sum used above.
  chk <- unique(g[, c("game_id", "team_id", "tm_tov", "tb_tov")])
  tov_match <- mean(chk$tm_tov == chk$tb_tov, na.rm = TRUE)
  g$tb_tov <- NULL

  data_audit[[as.character(s)]] <- list(
    season = s, scheduled_regular_season_games = length(std_ids),
    player_box_games = length(unique(pb$game_id)), game_coverage = round(coverage, 4),
    non_std_games_removed = non_std_games,
    regular_season_rows = n_rows, did_not_play_rows = sum(dnp),
    played_but_minutes_missing_rows = sum(min_na),
    minutes_missing_rows_with_points = min_na_with_stats,
    player_games_used = nrow(g),
    games = length(unique(g$game_id)), players = length(unique(g$player_id)),
    player_games_missing_any_box_stat = sum(!complete.cases(g[, names(PB_COLS)])),
    player_games_missing_team_context = sum(!complete.cases(g[, c("tm_min", "tm_fgm", "tm_fga", "tm_fta",
                                                                   "tm_tov", "tm_oreb", "tm_dreb",
                                                                   "opp_oreb", "opp_dreb")])),
    team_turnovers_match_player_sum = round(tov_match, 4))
  games_list[[as.character(s)]] <- g
  say("Season %d: %d player-games, %d of %d scheduled games, %d players", s, nrow(g),
      length(unique(g$game_id)), length(std_ids), length(unique(g$player_id)))
}
games <- do.call(rbind, games_list)
rm(games_list)
SEASONS_USED <- as.integer(names(data_audit))

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
# share_g = MP_g / (TmMP_g / 5) is the player's share of her team's floor time.
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

# ---- Share of season --------------------------------------------------------
# Games: n / SEASON_GAMES_REF. Attempts and minutes: a full season for a typical
# rotation player = SEASON_GAMES_REF x the median per-game units among
# "rotation" player-seasons, defined as player-seasons that played in at least
# half of the most games any player played that season. Computed from the data.
ps_tab <- aggregate(cbind(n_games = 1, min, fga, fg3a, fta) ~ ps_id + season, data = games, FUN = sum)
ps_tab$max_games <- ave(ps_tab$n_games, ps_tab$season, FUN = max)
rot <- ps_tab[ps_tab$n_games >= 0.5 * ps_tab$max_games, ]
UNIT_PER_GAME <- c(games = 1,
                   fga = median(rot$fga / rot$n_games), fg3a = median(rot$fg3a / rot$n_games),
                   fta = median(rot$fta / rot$n_games), minutes = median(rot$min / rot$n_games))
UNIT_SEASON <- SEASON_GAMES_REF * UNIT_PER_GAME
season_share <- function(n, unit) n / UNIT_SEASON[[unit]]

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
boot_store <- list()   # per stat: list(grid, sh = matrix grid x B, ros)
for (st in names(STATS)) {                                   # curve loop: every stat
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
      season_share = season_share(n, spec$unit),
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
      season_share = season_share(n, spec$unit),
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
# running that production fit. PROJECT_DIR is set so the engine does not look it up.
# Nothing in the file is edited. Only two engine functions are called below:
# build_possession_design_matrix() and solve_ridge_rapm(). The engine's live entry
# points (estimate_rapm_ratings / fit_rapm_ratings) and its box-score fallback are
# never called, so no non-possession path can run.
rapm_env <- new.env()
rapm_env$interactive <- function() TRUE
rapm_env$PROJECT_DIR <- PROJECT_ROOT
source("rapm_engine.R", local = rapm_env)
setwd(PROJECT_ROOT)
# rapm_engine.R loads its settings with a plain source("config.R"), so they are read
# here from config.R directly (the cfg environment above), the same file the engine uses.
RAPM_LAMBDA_USED <- as.numeric(cfg$RAPM_LAMBDA)
if (length(RAPM_LAMBDA_USED) != 1L || !is.finite(RAPM_LAMBDA_USED)) stop("RAPM_LAMBDA not found in config.R")
RAPM_RULE_POSS_PER_SIDE <- as.integer(cfg$RAPM_LEADERBOARD_MIN_POSS_PER_SIDE)
if (length(RAPM_RULE_POSS_PER_SIDE) != 1L) stop("RAPM_LEADERBOARD_MIN_POSS_PER_SIDE not found in config.R")
REG_PREFIX <- "102"   # WNBA Stats regular-season game ids; Cup final and playoffs use other prefixes

# Same transformation as fit_rapm_ratings(): coefficients x 100, defence negated,
# each side centred on its own mean, total = sum.
fit_half <- function(poss) {
  dm <- rapm_env$build_possession_design_matrix(poss)
  beta <- rapm_env$solve_ridge_rapm(dm$X, dm$y, weights = dm$weights, lambda = RAPM_LAMBDA_USED)
  np <- dm$n_players
  orapm <- beta[1:np] * 100
  drapm <- -beta[(np + 1):(2 * np)] * 100
  orapm <- orapm - mean(orapm); drapm <- drapm - mean(drapm)
  ids <- as.character(dm$all_players)
  off <- as.integer(dm$off_counts[ids]); def <- as.integer(dm$def_counts[ids])
  off[is.na(off)] <- 0L; def[is.na(def)] <- 0L
  list(df = data.frame(player_id = ids, off = off, def = def, orapm = orapm, drapm = drapm,
                       total_rapm = orapm + drapm, stringsAsFactors = FALSE),
       n_poss = dm$n_possessions)
}

rapm_rows <- list(); rapm_audit <- list(); rapm_fail <- list(); team_poss_per_game <- list()
for (s in RAPM_SEASONS) {
  res <- tryCatch({
    p <- load_poss(s)
    if (is.null(p) || nrow(p) == 0) stop("no possession data for this season")
    gid <- as.character(p$game_id)
    p <- p[substr(gid, 1, 3) == REG_PREFIX, , drop = FALSE]
    rs_games <- sort(unique(as.character(p$game_id)))
    if (length(rs_games) < 20) stop("fewer than 20 regular-season games with possession data")
    half_games <- list(A = rs_games[seq(1, length(rs_games), 2)],
                       B = rs_games[seq(2, length(rs_games), 2)])
    fits <- lapply(names(half_games), function(h) fit_half(p[as.character(p$game_id) %in% half_games[[h]], ]))
    j <- merge(fits[[1]]$df, fits[[2]]$df, by = "player_id", suffixes = c("_a", "_b"))
    j$season <- s
    j$min_side_half <- pmin(j$off_a, j$def_a, j$off_b, j$def_b)
    team_poss_per_game[[as.character(s)]] <- (fits[[1]]$n_poss + fits[[2]]$n_poss) / (2 * length(rs_games))
    rapm_audit[[as.character(s)]] <- list(season = s, regular_season_games = length(rs_games),
      possession_rows = nrow(p), possessions_fit = fits[[1]]$n_poss + fits[[2]]$n_poss,
      games_half_a = length(half_games$A), games_half_b = length(half_games$B),
      players_rated_a = nrow(fits[[1]]$df), players_rated_b = nrow(fits[[2]]$df),
      players_in_both = nrow(j))
    j
  }, error = function(e) { rapm_fail[[as.character(s)]] <<- conditionMessage(e); NULL })
  if (!is.null(res)) rapm_rows[[as.character(s)]] <- res
  say("RAPM season %d: %s", s, if (is.null(res)) paste("FAILED -", rapm_fail[[as.character(s)]]) else
        sprintf("%d players rated in both halves", nrow(res)))
}
rapm_ok <- length(rapm_rows) >= 3
# Share of season for RAPM: a season-scale exposure of 2k per side against every
# possession one side of a team has in a SEASON_GAMES_REF-game season, at the
# median per-team-game possession count of the most recent season fit.
TEAM_POSS_SEASON <- if (length(team_poss_per_game)) SEASON_GAMES_REF * team_poss_per_game[[length(team_poss_per_game)]] else NA_real_
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
cross_summary <- function(grid, point_curve, boot_mat, bar, scale = 1, season_units = NA_real_) {
  pt <- first_cross(grid, point_curve, bar)
  bc <- apply(boot_mat, 2, function(v) first_cross(grid, v, bar))
  qs <- unname(quantile(bc, c(0.025, 0.975), type = 1))
  list(bar = bar, point = if (is.finite(pt)) pt * scale else NULL,
       lo = if (is.finite(qs[1])) qs[1] * scale else NULL,
       hi = if (is.finite(qs[2])) qs[2] * scale else NULL,
       point_season_share = if (is.finite(pt) && is.finite(season_units)) round(pt * scale / season_units, 4) else NULL,
       share_not_reached = mean(!is.finite(bc)))
}
crossings <- list()
for (st in names(STATS)) {
  bs <- boot_store[[st]]
  su <- UNIT_SEASON[[STATS[[st]]$unit]]
  shc <- curves[curves$stat == st & curves$method == "split_half", ]
  roc <- curves[curves$stat == st & curves$method == "rest_of_season", ]
  crossings[[st]] <- list(
    split_half     = lapply(REF_BARS, function(b) cross_summary(bs$grid, shc$r, bs$sh, b, season_units = su)),
    spearman_brown = lapply(REF_BARS, function(b) cross_summary(bs$grid, shc$r_sb, sb(bs$sh), b, scale = 2, season_units = su)),
    rest_of_season = lapply(REF_BARS, function(b) cross_summary(bs$grid, roc$r, bs$ros, b, season_units = su)))
}
rapm_crossings <- list()
if (rapm_ok) for (m in names(rapm_boot)) {
  th <- rapm_curves[rapm_curves$measure == m & rapm_curves$kind == "threshold", ]
  # share of season: the season-scale exposure (2k) over a full season of one side's possessions
  rapm_crossings[[m]] <- list(
    split_half     = lapply(REF_BARS, function(b) cross_summary(RAPM_THRESHOLDS, th$r, rapm_boot[[m]], b, season_units = TEAM_POSS_SEASON / 2)),
    spearman_brown = lapply(REF_BARS, function(b) cross_summary(RAPM_THRESHOLDS, th$r_sb, sb(rapm_boot[[m]]), b, scale = 2, season_units = TEAM_POSS_SEASON)))
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
         title = sprintf("WNBA leader reliability: %s stats", grp),
         subtitle = sprintf("WNBA regular seasons %s; bands = player-season bootstrap 95%% (%d resamples); dashed = bars %s",
                            paste(range(SEASONS_USED), collapse = "-"), N_BOOT, paste(REF_BARS, collapse = ", "))) +
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
         title = "WNBA leader reliability: RAPM, odd-game fit vs even-game fit",
         subtitle = sprintf("Seasons %s; solid red = current rule, %s each side; dotted red = %s each side in each half; bands = bootstrap 95%%",
                            paste(range(as.integer(names(rapm_rows))), collapse = "-"),
                            format(RAPM_RULE_POSS_PER_SIDE, big.mark = ","), format(RAPM_RULE_POSS_PER_SIDE / 2, big.mark = ","))) +
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
       seasons_used = SEASONS_USED,
       season_units_reference = round(UNIT_SEASON[[s$unit]], 2),
       split_half = df_rows(curves[curves$stat == st & curves$method == "split_half",
                                   c("n", "season_share", "n_players", "n_missing", "mean_realised_units", "r", "r_lo", "r_hi",
                                     "sb_sample", "r_sb", "r_sb_lo", "r_sb_hi")]),
       rest_of_season = df_rows(curves[curves$stat == st & curves$method == "rest_of_season",
                                       c("n", "season_share", "n_players", "n_missing", "mean_realised_units", "r", "r_lo", "r_hi")]),
       crossings = crossings[[st]])
})
names(stats_json) <- names(STATS)

rule_rows <- NULL; rule_rows_half <- NULL
if (rapm_ok) {
  rule_rows      <- rapm_curves[rapm_curves$kind == "threshold" & rapm_curves$lo == RAPM_RULE_POSS_PER_SIDE / 2, ]
  rule_rows_half <- rapm_curves[rapm_curves$kind == "threshold" & rapm_curves$lo == RAPM_RULE_POSS_PER_SIDE, ]
}
results <- list(
  issue = "WNBA_analytics#267",
  note = "Reference points only. No qualifying minimum is chosen here; the owner sets them after reviewing the curves.",
  settings = list(seasons = SEASONS, seasons_used = SEASONS_USED, seasons_dropped = seasons_dropped,
                  rapm_seasons = RAPM_SEASONS, seed = SEED, n_boot = N_BOOT,
                  grid_games = GRID_GAMES, grid_attempts = GRID_ATTEMPTS, grid_minutes = GRID_MINUTES,
                  rapm_bin_edges_per_side_per_half = RAPM_BIN_EDGES[is.finite(RAPM_BIN_EDGES)],
                  rapm_thresholds_per_side_per_half = RAPM_THRESHOLDS, reference_bars = REF_BARS,
                  min_players_per_point = MIN_PLAYERS, min_game_coverage = MIN_GAME_COVERAGE,
                  season_games_reference = SEASON_GAMES_REF,
                  rapm_lambda = RAPM_LAMBDA_USED,
                  rapm_rule_name = "RAPM_LEADERBOARD_MIN_POSS_PER_SIDE (config.R)",
                  rapm_rule_poss_per_side = RAPM_RULE_POSS_PER_SIDE),
  season_share_reference = list(
    rule = "games: n / season_games_reference; attempts and minutes: n / (season_games_reference x median per-game units of rotation player-seasons, those that played in at least half of the most games any player played that season); RAPM: season-scale possessions per side / (season_games_reference x possessions per team-game of the latest season fit)",
    units_per_game = as.list(round(UNIT_PER_GAME, 3)), units_per_season = as.list(round(UNIT_SEASON, 1)),
    rapm_team_possessions_per_side_per_season = round(TEAM_POSS_SEASON, 0)),
  data_audit = unname(data_audit),
  player_seasons = N_PS,
  stats_not_measured = list(),
  stats = stats_json,
  rapm = list(
    available = rapm_ok,
    seasons_fit = as.integer(names(rapm_rows)),
    seasons_failed = rapm_fail,
    audit = unname(rapm_audit),
    player_seasons = if (rapm_ok) nrow(rj) else 0L,
    bins = if (rapm_ok) df_rows(rapm_curves[rapm_curves$kind == "bin", ]) else list(),
    thresholds = if (rapm_ok) df_rows(rapm_curves[rapm_curves$kind == "threshold", ]) else list(),
    at_current_rule_season_scale = if (rapm_ok) df_rows(rule_rows) else list(),
    at_current_rule_per_half = if (rapm_ok) df_rows(rule_rows_half) else list(),
    crossings = rapm_crossings),
  runtime_minutes = round(runtime_min, 2)
)
writeLines(toJSON(results, auto_unbox = TRUE, digits = 4, null = "null", na = "null", pretty = TRUE),
           file.path(OUT_DIR, "leader_reliability_study_results.json"))

# ==============================================================================
# 9. Report
# ==============================================================================
f2 <- function(x) ifelse(is.na(x), "NA", sprintf("%.2f", x))
pct <- function(x) sprintf("%.0f%%", 100 * x)
fmt_cross <- function(cx) {
  if (is.null(cx$point)) return(sprintf("not reached (%.0f%% of resamples)", 100 * cx$share_not_reached))
  hi <- if (is.null(cx$hi)) "beyond grid" else format(cx$hi, big.mark = ",")
  lo <- if (is.null(cx$lo)) "beyond grid" else format(cx$lo, big.mark = ",")
  sh <- if (is.null(cx$point_season_share)) "" else sprintf(" (%s)", pct(cx$point_season_share))
  sprintf("%s [%s, %s]%s", format(cx$point, big.mark = ","), lo, hi, sh)
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
snap_n <- c(games = 10, fga = 100, fg3a = 50, fta = 50, minutes = 250)
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
audit_tbl <- c("| Season | Scheduled games | Player box games | Regular-season rows | Did not play | Not flagged, minutes missing | Player-games used | Players | Rows missing a box stat | Rows missing team context | Team box TOV = player sum |",
               "|---|---|---|---|---|---|---|---|---|---|---|")
for (a in data_audit) audit_tbl <- c(audit_tbl, sprintf("| %d | %d | %d | %s | %s | %s | %s | %d | %d | %d | %s |",
  a$season, a$scheduled_regular_season_games, a$player_box_games,
  format(a$regular_season_rows, big.mark = ","), format(a$did_not_play_rows, big.mark = ","),
  format(a$played_but_minutes_missing_rows, big.mark = ","), format(a$player_games_used, big.mark = ","), a$players,
  a$player_games_missing_any_box_stat, a$player_games_missing_team_context, pct(a$team_turnovers_match_player_sum)))

lab_unit <- function(st) c(STATS[[st]]$label, UNIT_LABEL[[STATS[[st]]$unit]])
kinds_box <- c(split_half = "split-half r, sample n", spearman_brown = "Spearman-Brown, sample 2n",
               rest_of_season = "rest-of-season r, first n")
share_tbl <- c("| Unit | Median per game (rotation player-seasons) | Full-season reference (x season games) |", "|---|---|---|")
for (u in names(UNIT_SEASON)) share_tbl <- c(share_tbl, sprintf("| %s | %.1f | %s |", UNIT_LABEL[[u]], UNIT_PER_GAME[[u]],
                                                              format(round(UNIT_SEASON[[u]]), big.mark = ",")))

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
  rule_line <- function(rr, k_half, k_season) vapply(seq_len(nrow(rr)), function(i) sprintf(
    "- %s: split-half r %s [%s, %s] among the %d player-seasons with at least %s per side in each half; Spearman-Brown (season scale, about %s per side) %s [%s, %s].",
    rr$measure[i], f2(rr$r[i]), f2(rr$r_lo[i]), f2(rr$r_hi[i]), rr$n_players[i],
    format(k_half, big.mark = ","), format(k_season, big.mark = ","),
    f2(rr$r_sb[i]), f2(rr$r_sb_lo[i]), f2(rr$r_sb_hi[i])), "")
  audit_r <- c("| Season | Regular-season games | Possessions fit | Players rated, odd half | Players rated, even half | Players in both |", "|---|---|---|---|---|---|")
  for (a in rapm_audit) audit_r <- c(audit_r, sprintf("| %d | %d | %s | %d | %d | %d |", a$season, a$regular_season_games,
    format(a$possessions_fit, big.mark = ","), a$players_rated_a, a$players_rated_b, a$players_in_both))
  c("## RAPM",
    "",
    sprintf("Seasons fit: %s. Data: `wehoop::load_wnba_stats_possessions()` (the source `rapm_engine.R` uses), one row per possession with both five-player lineups. For each season the regular-season games (WNBA Stats game ids with prefix `102`; this excludes the playoffs and the Commissioner's Cup final) are sorted by game id, which follows the schedule, and alternately assigned to an odd half and an even half. `rapm_engine.R` is sourced unchanged; its `build_possession_design_matrix()` (which drops possessions without a full lineup or with an impossible points value, as in production) and `solve_ridge_rapm()` (lambda = %s, the engine's `RAPM_LAMBDA`) are fit on each half separately, with the same per-100 scaling, defensive sign flip and per-side centring as `fit_rapm_ratings()`. Players rated in both halves are paired. A player-season's exposure is the smallest of her offensive and defensive possessions across the two halves (\"possessions per side in each half\").",
            paste(names(rapm_rows), collapse = ", "), format(RAPM_LAMBDA_USED)),
    if (length(rapm_fail)) sprintf("Seasons that could not be fit: %s.", paste(sprintf("%s (%s)", names(rapm_fail), unlist(rapm_fail)), collapse = "; ")) else "All requested seasons were fit.",
    "",
    audit_r,
    "",
    "Rest-of-season check for RAPM: not run. RAPM is a joint ridge fit over all players, so a player-specific \"first n possessions vs the rest\" split would need a separate refit for every player and cutoff; the split-half fits above are the RAPM reliability measure delivered here.",
    "",
    "No simulated or fallback RAPM path is used: the script calls only `build_possession_design_matrix()` and `solve_ridge_rapm()` on real possession rows, and never calls `estimate_rapm_ratings()`, `fit_rapm_ratings()` or the engine's box-score fallback.",
    "",
    "![RAPM curves](leader_reliability_study/rapm.png)",
    "",
    sprintf("### Comparison with the current rule (`RAPM_LEADERBOARD_MIN_POSS_PER_SIDE` = %s possessions each side, `config.R`)", format(RAPM_RULE_POSS_PER_SIDE, big.mark = ",")),
    "",
    sprintf("The production leaderboard fits one pooled RAPM over seasons %s and marks a player `leaderboard_eligible` when she has at least %s possessions on both offence and defence in that pooled fit. This study fits one season at a time, so the comparison is made at the season scale: a season-scale exposure of %s per side corresponds to about %s per side in each half, and the Spearman-Brown value projects the half-season correlation to the full season. In the pooled production fit a player can reach the rule's count by adding up possessions over several seasons, and her rating there draws on all of them, so the rule is not the same thing as a single-season count; these single-season figures describe what that count of possessions buys within one season.",
            paste(range(cfg$ALL_SEASONS), collapse = "-"), format(RAPM_RULE_POSS_PER_SIDE, big.mark = ","),
            format(RAPM_RULE_POSS_PER_SIDE, big.mark = ","), format(RAPM_RULE_POSS_PER_SIDE / 2, big.mark = ",")),
    "",
    "At the rule's count as a season-scale exposure (half of it in each half):",
    "",
    rule_line(rule_rows, RAPM_RULE_POSS_PER_SIDE / 2, RAPM_RULE_POSS_PER_SIDE),
    "",
    "At the rule's count reached within each half (about twice the rule over a season):",
    "",
    rule_line(rule_rows_half, RAPM_RULE_POSS_PER_SIDE, 2 * RAPM_RULE_POSS_PER_SIDE),
    "",
    "Caveats specific to RAPM: ridge shrinkage pulls low-exposure players toward 0 in both halves, and half-season fits carry the same penalty as the production fit on a small fraction of its data, so these correlations describe the engine as configured, not an unshrunk rating. The bootstrap resamples player-seasons from the fitted pairs; it does not refit the ridge, so its intervals omit fitting uncertainty. Players in the same lineups share possessions, so ratings are not independent across players.",
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
    sprintf("Share of season for RAPM: the split-half value k is a half-season exposure, shown against half a season of one side's possessions (%s); the Spearman-Brown value 2k is shown against a full season (%s possessions per side, %d games x %.1f possessions per team-game in %s).",
            format(round(TEAM_POSS_SEASON / 2), big.mark = ","), format(round(TEAM_POSS_SEASON), big.mark = ","),
            SEASON_GAMES_REF, TEAM_POSS_SEASON / SEASON_GAMES_REF, tail(names(rapm_rows), 1)),
    "",
    "RAPM crossings use the \"at least k per side in each half\" curves, which pool every player-season at or above k. Because that pool always includes the high-exposure players, the curve can sit above a bar at the smallest k; a crossing at the first grid point means exactly that, and the bin table in the RAPM section shows how low the correlation is within low-exposure bins on their own.")
} else "RAPM crossings not available (see the RAPM section)."

seasons_line <- paste(SEASONS_USED, collapse = ", ")
report <- c(
  "# WNBA leader reliability study (issue #267)",
  "",
  "Research only. This study measures how quickly each league-leader stat settles as a player's sample grows. It repeats the NBA study (NBA_analytics#253) for the WNBA. It does not choose any qualifying minimum and changes no production code; the owner reviews these curves and sets the minimums, which the WNBA leaders panel then uses.",
  "",
  sprintf("Generated by `tools/leader_reliability_study.R` (seed %d, %d bootstrap resamples). Runtime of this run: %.1f minutes.", SEED, N_BOOT, runtime_min),
  "",
  "## Data",
  "",
  sprintf("- WNBA regular seasons %s (%d seasons, %s player-seasons). Every stat below, counting, shooting and rates alike, uses all of these seasons: no box-score field is missing in any of them (see the table). 2003 and 2004 are left out because wehoop's ESPN player box covers only 77%% and 90%% of their scheduled games (the rule is at least %s); 2002 has no wehoop team box; 2027 has not started. 2020 is included: it was a complete 22-game regular season played at a single site.",
          seasons_line, length(SEASONS_USED), format(N_PS, big.mark = ","), pct(MIN_GAME_COVERAGE)),
  "- Season lengths differ: 34 games per team in 2005-2019, 22 in 2020, 32 in 2021, 36 in 2022, 40 in 2023-2024 and 44 in 2025-2026. Older seasons therefore contribute fewer games per player-season, and the largest game counts on the grid come mostly from recent seasons.",
  "- Player and team box scores: ESPN via wehoop (`load_wnba_player_box`, `load_wnba_team_box`). Regular season means ESPN `season_type == 2` and schedule type `STD` (`load_wnba_schedule`), which removes the All-Star game and the Commissioner's Cup final; neither counts in the standings or the season statistics.",
  sprintf("- Rows flagged `did_not_play` are excluded. Rows not flagged but with no minutes recorded are excluded and counted below; before 2013 ESPN did not flag players who did not play. Across all seasons %s of these rows have any points scored (`minutes_missing_rows_with_points` in the JSON), so they are players who did not play rather than lost minutes. Nothing is imputed: a missing value makes any sample that contains it missing at that point, and the number of such player-seasons is reported at every point (`n_missing` in the JSON).",
          format(sum(vapply(data_audit, function(a) a$minutes_missing_rows_with_points, 0)))),
  "- A player-season covers every team the player played for that season. Team context (team minutes, team and opponent totals) is taken game by game for the team she played for in that game.",
  "",
  audit_tbl,
  "",
  "## Methods",
  "",
  "- **Split-half reliability.** Each player-season's games are numbered in date order; odd-numbered games form half A and even-numbered games half B. At each sample size n the stat is computed on each half from the first n units of that half, for every player-season whose two halves each reach n units, and the two halves are correlated across player-seasons (Pearson). The raw correlation is the reliability of an n-unit sample. The Spearman-Brown value 2r / (1 + r) is the projected reliability of a 2n-unit sample and is plotted at 2n.",
  "- **Rest-of-season check.** The stat over a player's first n units of the season against the same stat over all of her remaining games that season. Rule: only player-seasons whose remaining games hold at least n units are used, so the remainder is never smaller than the early sample.",
  "- **Units.** Counting stats: games played. Shooting: attempts of that shot type. Rates: minutes. Games are indivisible, so for attempts and minutes a sample of n is the shortest run of whole games whose cumulative units reach n; the mean realised size is reported in the JSON (`mean_realised_units`).",
  sprintf("- **Intervals.** Player-season block bootstrap: player-seasons are resampled with replacement (%d resamples, seed %d), every curve point is recomputed on each resample with the same draw, and the 2.5th and 97.5th percentiles are reported. Points with fewer than %d player-seasons are not reported.", N_BOOT, SEED, MIN_PLAYERS),
  sprintf("- **Share of season.** Every crossing is also shown as a share of a %d-game season (the current WNBA schedule). For games that is n / %d. For attempts and minutes it is n over a full season for a typical rotation player: %d games times the median per-game value among rotation player-seasons (those that played in at least half of the most games any player played that season), pooled over all seasons used:", SEASON_GAMES_REF, SEASON_GAMES_REF, SEASON_GAMES_REF),
  "",
  share_tbl,
  "",
  "- **Reading the curves at large n.** Only high-volume players reach large samples, so the player pool narrows as n grows; a narrower spread of true talent lowers correlations. A curve that flattens or dips at the right-hand end reflects that selection as well as noise, and the player count at each point should be read with it. WNBA seasons are short, so the pool narrows sooner than in the NBA study.",
  "- **Who is in the pool.** As issue #267 specifies, every player-season that reaches n is correlated, from bench players to stars. The spread of true levels across that pool is wide (a starter's points per game differ from a reserve's mostly through role and minutes), and a wide spread makes correlations high at small n. Separating players near the top of a leader list from each other is harder than these curves suggest, so the crossings below describe the whole league, not the top of a list.",
  "",
  "## Formulas",
  "",
  "Counting stats are totals over the sample divided by games played. Shooting percentages are made over attempted for that shot type: field goal % = FG / FGA, 3-point % = 3P / 3PA, free throw % = FT / FTA.",
  "",
  "Rates use Basketball Reference definitions, computed from player and team box scores. For a sample of games each rate is the sum of its per-game numerators over the sum of its per-game denominators. MP is the player's minutes; TmMP is the sum of her team's player minutes in that game; Tm and Opp are the team box totals of her team and its opponent in that game. Team turnovers (TmTOV) are the sum of the team's player turnovers in that game, for every season. The team box `turnovers` column is not used because its meaning changes: from 2013 it always equals the player sum, but before 2013 it does so in only 40-62% of team-games (last column of the data table).",
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
  "RAPM (offensive, defensive, total) is the possession-level ridge regression in `rapm_engine.R`, in points per 100 possessions; see the RAPM section.",
  "",
  "## Stats not measured",
  "",
  "None. Every stat the issue lists is measured.",
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
  "Correlation [bootstrap 95%] and player-season count. The full curves, with the player count at every point, are in the results JSON.",
  "", snap, "",
  rapm_section,
  "## Reference points for the owner's review",
  "",
  sprintf("For each stat, the first grid sample size at which each curve reaches the bar, with a bootstrap 95%% interval for that crossing and, in parentheses, the point value as a share of a %d-game season (see Methods). \"Beyond grid\" means some resamples did not reach the bar inside the grid. These are reference points for review, not chosen values. Split-half and rest-of-season values are in the stat's own unit for an n-unit sample; Spearman-Brown values are the projected sample (2n) at which reliability reaches the bar. The pool is every player-season, from bench players to stars, so separating players near the top of a leader list is harder than these crossings suggest.", SEASON_GAMES_REF),
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
