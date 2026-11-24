# ==============================================================================
# tools/momentum_measures_study.R - do momentum measures on team stats predict
# the next 5-10 games beyond team strength? And are the Momentum Board's blend
# weights right? (research only; NOT part of the pipeline)
#
# Part A. 11 momentum measures x 14 team stat series = 154 features. Each is
#   scored on what it adds, out of season, to a baseline of pregame Elo plus
#   season-to-date net rating:
#     1. single-feature screening (block-bootstrap 95% CI, Benjamini-Hochberg FDR),
#     2. redundancy families (correlation clusters across measures and series),
#     3. a nested small-combination search (top 6 series x top 6 measures ranked on
#        training seasons only -> C(6,3)^2 = 400 combinations of 3 series x 3
#        measures, ridge regression, chosen by inner leave-one-season-out),
#        compared with an elastic net over all 154, greedy forward selection and
#        the board's current momentum score,
#     4. a permutation baseline (targets shuffled among teams within each date),
#     5. selection stability.
# Part B. The board's blend 0.7 z(form) + 0.1 z(trend) + 0.1 z(residual) +
#   0.1 z(Elo change) (build_momentum_dataset.R, COMBINED_WEIGHTS) at windows 5,
#   10 and 18: a 0.05-step simplex grid over form / trend / Elo change, non-negative
#   regression weights per fold, flatness, each component alone, the 2026-27
#   residual check (small sample, never imputed) and a "trend swap" row that
#   replaces or joins the trend component with the best part-A feature.
#
# Protocol: leave-one-season-out (LOSO) over the regular seasons 2018-19 to
# 2025-26, pooled out-of-fold predictions, paired bootstrap with 2,000 resamples of
# whole team-seasons (next-10 targets overlap from game to game, so rows are not
# independent). 2019-20 (hiatus + Orlando bubble) and 2020-21 (72 games, no crowds)
# stay in; a sensitivity run drops them. 2026-27 to date is a final holdout,
# scored once, after every choice is fixed (section 9).
#
# NO LOOK-AHEAD: every feature for a team after its game k uses only games 1..k;
# cross-team z-scores on date d use each team's latest state on or before d; the
# targets use only games k+1 .. k+h. Fitted parameters (Kalman variances, ridge
# and regression coefficients, series/measure rankings, selections) come from
# training seasons only. NO IMPUTATION: missing values stay missing and are
# counted per feature.
#
# Data: hoopR team boxes and schedules cached as cache/momentum_study_*_<season>.rds
# (2017-18 is loaded only to seed 2018-19 Elo); 2026-27 uses the board's own inputs
# (cache/matchups_team_box_2027.rds, cache/matchups_schedule_2027.rds,
# cache/prediction_accuracy_log.rds).
#
# Output: cache/momentum_measures_study_results.rds,
#         docs/research/momentum_measures_study_results.json,
#         cache/momentum_measures_study_tables.md (tables for the report).
# Run: Rscript tools/momentum_measures_study.R
#      (MOMENTUM_STUDY_N_PERM / MOMENTUM_STUDY_N_BOOT override the run sizes for a
#       quick smoke test only; the published run uses the defaults 200 / 2000.)
# ==============================================================================

STUDY_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  start <- if (length(f)) dirname(normalizePath(f[1], winslash = "/", mustWork = FALSE)) else getwd()
  root <- start
  while (!file.exists(file.path(root, "config.R"))) {
    parent <- dirname(root)
    if (identical(parent, root)) stop("momentum_measures_study.R: cannot find config.R at or above ", start)
    root <- parent
  }
  normalizePath(root, winslash = "/")
})
setwd(STUDY_ROOT)  # fatigue_travel_engine.R sources config.R from the working directory

source(file.path(STUDY_ROOT, "config.R"))
source(file.path(STUDY_ROOT, "R", "elo.R"))
Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")   # definitions only; the stage does not run
source(file.path(STUDY_ROOT, "build_momentum_dataset.R"))
if (!exists("calculate_travel_fatigue", mode = "function")) source(file.path(STUDY_ROOT, "fatigue_travel_engine.R"))
suppressPackageStartupMessages({ library(jsonlite); library(glmnet) })

t_start <- Sys.time()
elapsed <- function() as.numeric(difftime(Sys.time(), t_start, units = "mins"))
say <- function(...) cat(sprintf("[%5.1f min] ", elapsed()), sprintf(...), "\n", sep = "")

# ------------------------------------------------------------------------------
# 0. Settings
# ------------------------------------------------------------------------------
STUDY_SEED <- 20261124L
N_BOOT <- as.integer(Sys.getenv("MOMENTUM_STUDY_N_BOOT", "2000"))
N_PERM <- as.integer(Sys.getenv("MOMENTUM_STUDY_N_PERM", "200"))
HIST_SEASONS <- 2019:2026         # hoopR end-year numbering: 2019 = 2018-19
FLAGGED_SEASONS <- 2020:2021      # 2019-20 bubble, 2020-21 shortened
SENS_SEASONS <- setdiff(HIST_SEASONS, FLAGGED_SEASONS)
HOLDOUT_SEASON <- 2027L
MIN_GAMES <- 10L                  # no feature value before a team's 10th game
MIN_Z_TEAMS <- 10L                # a date's cross-team z needs this many teams with the value
BOARD_MIN_Z_TEAMS <- 3L           # the board's own rule (score_states)
IMPULSE_DECAY <- 0.85
RIDGE_ALPHAS <- c(0.01, 0.1, 1)   # ridge penalty = alpha x training rows (features are unit-scale z)
TOP_K <- 6L
GRID_STEP <- 0.05
FDR_Q <- 0.05
STABLE_SHARE <- 0.5
season_name <- function(s) sprintf("%d-%02d", s - 1L, s %% 100L)

SERIES <- c(elo = "Elo rating", margin = "Point margin", ortg = "Offensive rating", drtg = "Defensive rating",
            net = "Net rating", pace = "Pace (possessions)", efg = "Effective FG%", tov = "Turnover %",
            orb = "Offensive rebound %", ftr = "Free-throw rate", efg_def = "Effective FG% allowed",
            tov_def = "Turnover % forced", orb_def = "Offensive rebound % allowed", ftr_def = "Free-throw rate allowed")
MEASURES <- c(roc10 = "ROC-10", macd = "MACD", velocity = "Velocity", acceleration = "Acceleration",
              ewma_change = "EWMA of changes", zscore = "Z-score", rsi = "RSI", growth = "Growth difference",
              kalman = "Kalman slope", streak = "Streak", impulse = "Impulse")
FEATURES <- as.vector(t(outer(names(SERIES), names(MEASURES), paste, sep = "__")))
FEAT_SERIES <- rep(names(SERIES), each = length(MEASURES))
FEAT_MEASURE <- rep(names(MEASURES), times = length(SERIES))
KCOL <- which(FEAT_MEASURE == "kalman")
NF <- length(FEATURES)
stopifnot(NF == 154L)

TARGETS <- data.frame(
  id = c("net10_beyond_elo", "net5_beyond_elo", "ortg10_adj", "drtg10_adj", "win10_beyond_elo", "next_game_win"),
  definition = c(
    "Mean over the team's next 10 games of (point margin minus the margin Elo expected), the expectation using the team's Elo after game k, the opponent's pregame Elo and home court: (Elo - opp Elo + 100 x home sign) / 28 points.",
    "Same as net10_beyond_elo over the next 5 games.",
    "Mean opponent-adjusted offensive rating over the next 10 games (points per 100 possessions minus the opponent's season-to-date average allowed).",
    "Mean opponent-adjusted defensive rating over the next 10 games (points allowed per 100 possessions minus the opponent's season-to-date average scored); lower is better.",
    "Win share over the next 10 games minus the mean Elo win probability for those games (team Elo after game k).",
    "Next game won by the home side (one row per game), logistic model on the pregame Elo difference with home court plus the season-to-date net-rating difference; scored by log loss and ROC-AUC."),
  primary = c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE),
  kind = c(rep("continuous", 5), "binary"), stringsAsFactors = FALSE)
CONT_TARGETS <- TARGETS$id[TARGETS$kind == "continuous"]
PRIMARY <- "net10_beyond_elo"

# ------------------------------------------------------------------------------
# 1. Data: one regular-season team-game panel per season, with the shared Elo
# ------------------------------------------------------------------------------
read_cache <- function(kind, s) {
  path <- file.path(CACHE_DIR, sprintf("momentum_study_%s_%d.rds", kind, s))
  if (!file.exists(path)) stop("missing ", path, ": load it with hoopR::load_nba_", kind, "(seasons = ", s, ") and saveRDS() it there")
  as.data.frame(readRDS(path), stringsAsFactors = FALSE)
}
NBA_FRANCHISES <- ARENA_DB$team   # drops All-Star and exhibition sides
nba_only <- function(tb) tb[canon_team(tb$team_abbreviation) %in% NBA_FRANCHISES &
                              canon_team(tb$opponent_team_abbreviation) %in% NBA_FRANCHISES, , drop = FALSE]
BUBBLE_START <- as.Date("2020-07-30")   # hoopR does not flag the bubble games as neutral
# One row per game for Elo. build_momentum_dataset.R::elo_games_from_panel() keeps
# the home row OR (neutral and alphabetically first); at a neutral site hoopR still
# marks one side "home", so both rows can pass and the game would be counted twice.
# The study keeps the first row per game_id.
elo_games_once <- function(p) { g <- elo_games_from_panel(p); g[!duplicated(g$game_id), , drop = FALSE] }

build_season <- function(s) {
  if (s == HOLDOUT_SEASON) {
    tb <- read_required(file.path(CACHE_DIR, "matchups_team_box_2027.rds"), "team box 2026-27")
    sc <- read_required(file.path(CACHE_DIR, "matchups_schedule_2027.rds"), "schedule 2026-27")
  } else { tb <- read_cache("team_box", s); sc <- read_cache("schedule", s) }
  prev <- read_cache("team_box", s - 1L)
  reg <- nba_only(tb[tb$season_type %in% 2L, , drop = FALSE])
  prior <- elo_games_once(build_team_game_panel(normalise_team_box(
    nba_only(prev[prev$season_type %in% c(2L, 3L, 5L), , drop = FALSE]))))
  neutral_ids <- as.character(sc$game_id[sc$neutral_site %in% TRUE])
  if (s == 2020L) neutral_ids <- union(neutral_ids, as.character(reg$game_id[as.Date(reg$game_date) >= BUBBLE_START]))
  p <- build_team_game_panel(normalise_team_box(reg), neutral_ids)
  seed <- elo_carry_over(attr(elo_run_games(prior), "final"))
  played <- elo_run_games(elo_games_once(p), seed = seed)
  p <- attach_schedule_context(p)
  p <- attach_elo(p, played)
  if (s == HOLDOUT_SEASON) {
    log27 <- read_required(file.path(CACHE_DIR, "prediction_accuracy_log.rds"), "prediction log")
    p <- attach_prediction_log(p, log27, min(as.Date(sc$game_date)), max(as.Date(sc$game_date)))
  }
  p <- p[order(p$team, p$game_date, p$game_id), , drop = FALSE]
  p$game_index <- ave(seq_len(nrow(p)), p$team, FUN = seq_along)
  p$season <- s
  rownames(p) <- NULL
  p
}

say("Loading seasons")
PANELS <- list()
for (s in c(HIST_SEASONS, HOLDOUT_SEASON)) PANELS[[as.character(s)]] <- build_season(s)
log_cov27 <- attr(PANELS[[as.character(HOLDOUT_SEASON)]], "log_coverage")

# ------------------------------------------------------------------------------
# 2. Stat series (opponent-adjusted with the opponent's EARLIER games only) and targets
# ------------------------------------------------------------------------------
prior_mean_by_team <- function(x, team) ave(x, team, FUN = function(v) {
  n <- length(v); ok <- !is.na(v); s <- cumsum(ifelse(ok, v, 0)); m <- cumsum(ok)
  out <- c(NA_real_, (s / m)[-n]); out[c(TRUE, m[-n] == 0)] <- NA_real_; out[seq_len(n)]
})
lead_in_team <- function(x, team, i) ave(x, team, FUN = function(v) {
  n <- length(v); if (i >= n) rep(NA_real_, n) else c(v[(i + 1L):n], rep(NA_real_, i))
})
# (for column, against column, side): side "for" = for - opponent's earlier average
# allowed; side "against" = against - opponent's earlier average produced.
SERIES_DEF <- list(margin = c("margin", "neg_margin", "for"), ortg = c("ortg", "drtg", "for"),
                   drtg = c("ortg", "drtg", "against"), net = c("net", "neg_net", "for"),
                   pace = c("poss", "poss", "for"), efg = c("efg", "opp_efg", "for"),
                   tov = c("tov_pct", "opp_tov_pct", "for"), orb = c("oreb_pct", "opp_oreb_pct", "for"),
                   ftr = c("ft_rate", "opp_ft_rate", "for"), efg_def = c("efg", "opp_efg", "against"),
                   tov_def = c("tov_pct", "opp_tov_pct", "against"), orb_def = c("oreb_pct", "opp_oreb_pct", "against"),
                   ftr_def = c("ft_rate", "opp_ft_rate", "against"))

season_rows <- function(p) {
  p$neg_margin <- -p$margin; p$neg_net <- -p$net; p$opp_oreb_pct <- 1 - p$dreb_pct
  p$home_sign <- ifelse(p$neutral, 0, ifelse(p$home, 1, -1))
  oi <- match(paste(p$game_id, p$opp), paste(p$game_id, p$team))
  out <- data.frame(season = p$season, team = p$team, game_id = p$game_id, game_date = p$game_date,
                    k = p$game_index, win = p$win, home = p$home, neutral = p$neutral, opp = p$opp,
                    elo_pre = p$elo_pre, elo_post = p$elo_post, opp_elo_pre = p$opp_elo_pre,
                    margin = p$margin, home_sign = p$home_sign, stringsAsFactors = FALSE)
  out$s_elo <- p$elo_post
  for (nm in names(SERIES_DEF)) {
    d <- SERIES_DEF[[nm]]
    if (d[3] == "for") out[[paste0("s_", nm)]] <- p[[d[1]]] - prior_mean_by_team(p[[d[2]]], p$team)[oi]
    else out[[paste0("s_", nm)]] <- p[[d[2]]] - prior_mean_by_team(p[[d[1]]], p$team)[oi]
  }
  # Baseline covariates known after game k: Elo after game k (= pregame Elo for k+1)
  # and season-to-date net rating through game k.
  out$elo_c <- p$elo_post - ELO_MEAN
  cs <- function(x) ave(x, p$team, FUN = cumsum)
  out$snet <- 100 * (cs(p$pts) - cs(p$opp_pts)) / cs(p$poss)
  # Targets: games k+1 .. k+h only.
  for (h in c(5L, 10L)) {
    acc_m <- 0; acc_w <- 0
    for (i in seq_len(h)) {
      m <- lead_in_team(p$margin, p$team, i); oe <- lead_in_team(p$opp_elo_pre, p$team, i)
      hs <- lead_in_team(p$home_sign, p$team, i); w <- lead_in_team(as.numeric(p$win), p$team, i)
      d <- p$elo_post - oe + hs * ELO_HOME_ADV
      acc_m <- acc_m + m - d / ELO_POINTS_PER_MARGIN_POINT
      acc_w <- acc_w + w - 1 / (1 + 10^(-d / 400))
    }
    out[[sprintf("net%d_beyond_elo", h)]] <- acc_m / h
    if (h == 10L) out$win10_beyond_elo <- acc_w / h
  }
  acc_o <- 0; acc_d <- 0
  for (i in 1:10) { acc_o <- acc_o + lead_in_team(out$s_ortg, p$team, i); acc_d <- acc_d + lead_in_team(out$s_drtg, p$team, i) }
  out$ortg10_adj <- acc_o / 10; out$drtg10_adj <- acc_d / 10
  out
}
TG <- do.call(rbind, lapply(PANELS, season_rows)); rownames(TG) <- NULL
stopifnot(!anyDuplicated(paste(TG$season, TG$game_id, TG$team)))   # one row per team per game
TG$block <- paste(TG$season, TG$team)
NTG <- nrow(TG)

# Next-game rows: one per game (home side, or the alphabetically first side at a
# neutral site); features come from the cross-section of the previous league date.
NG <- do.call(rbind, lapply(PANELS, function(p) {
  g <- p[p$home | (p$neutral & p$team < p$opp), , drop = FALSE]
  g <- g[!duplicated(g$game_id), , drop = FALSE]   # one row per game (see elo_games_once)
  dates <- sort(unique(p$game_date)); pos <- match(g$game_date, dates)
  data.frame(season = g$season, game_id = g$game_id, game_date = g$game_date,
             prev_date = as.Date(ifelse(pos > 1L, as.character(dates[pmax(pos - 1L, 1L)]), NA_character_)),
             home = g$team, away = g$opp, home_win = as.numeric(g$win),
             elo_diff = g$elo_pre - g$opp_elo_pre + ifelse(g$neutral, 0, ELO_HOME_ADV), stringsAsFactors = FALSE)
}))
rownames(NG) <- NULL
NG$block <- paste(NG$season, NG$home)
stopifnot(all(is.na(NG$prev_date) | NG$prev_date < NG$game_date))   # look-ahead guard

season_table <- do.call(rbind, lapply(PANELS, function(p) data.frame(
  season = season_name(p$season[1]), hoopr_season = p$season[1],
  role = if (p$season[1] == HOLDOUT_SEASON) "final holdout (in progress)" else if (p$season[1] %in% FLAGGED_SEASONS) "LOSO (flagged; dropped in sensitivity run)" else "LOSO",
  games = length(unique(p$game_id)), team_games = nrow(p), teams = length(unique(p$team)),
  first = format(min(p$game_date)), last = format(max(p$game_date)),
  neutral_games = length(unique(p$game_id[p$neutral])), stringsAsFactors = FALSE)))
rownames(season_table) <- NULL
cat("\n>>> Seasons\n"); print(season_table, row.names = FALSE)
cat(sprintf("    2026-27 games with a resolved logged pregame margin (residual input): %d of %d\n",
            log_cov27$panel_games_with_margin, log_cov27$panel_games))

# ------------------------------------------------------------------------------
# 3. The 11 measures, forward-only (each value after game k uses games 1..k)
# ------------------------------------------------------------------------------
ewma_vec <- function(x, span) {
  a <- 2 / (span + 1); out <- x; n <- length(x)
  if (n > 1) for (i in 2:n) out[i] <- a * x[i] + (1 - a) * out[i - 1L]
  out
}
trail <- function(x, f) as.numeric(stats::filter(x, f, sides = 1))   # trailing window only
lagn <- function(x, L) { n <- length(x); if (L >= n) rep(NA_real_, n) else c(rep(NA_real_, L), x[seq_len(n - L)]) }
VEL_W <- (1:10) - 5.5

# v: the team's season series in game order (missing games removed); for Elo the
# level is the post-game rating and the "change" the per-game Elo change; for a
# box series the "change" is the surprise: game value minus the team's own mean
# of its EARLIER games.
compute_measures <- function(v, is_elo, elo_pre1 = NA_real_, win = NULL) {
  n <- length(v)
  out <- matrix(NA_real_, n, length(MEASURES), dimnames = list(NULL, names(MEASURES)))
  if (n < MIN_GAMES) return(out)
  k <- seq_len(n)
  if (is_elo) { chg <- v - c(elo_pre1, v[-n]) }
  else { chg <- v - c(NA_real_, cumsum(v)[-n] / seq_len(n - 1L)) }
  # ROC-10: Elo = change over the last 10 games / 10; box = mean of the last 10
  # games minus the mean of the team's games before them (>= 5 earlier games).
  if (is_elo) { L <- c(elo_pre1, v); roc <- (L[k + 1L] - L[pmax(k - 10L, 0L) + 1L]) / 10 }
  else {
    cs <- cumsum(v); nb <- k - 10L
    roc <- trail(v, rep(0.1, 10)) - ifelse(nb >= BASELINE_MIN_GAMES, cs[pmax(nb, 1L)] / pmax(nb, 1L), NA_real_)
  }
  out[, "roc10"] <- roc
  out[, "macd"] <- ewma_vec(v, 5) - ewma_vec(v, 15)                       # recursive, one-sided
  # Velocity: slope of a least-squares line through the trailing 10 games (not a
  # whole-season smoother); acceleration: velocity now minus 5 games earlier.
  vel <- trail(v, rev(VEL_W) / sum(VEL_W^2))
  out[, "velocity"] <- vel
  out[, "acceleration"] <- vel - lagn(vel, 5L)
  s0 <- if (is_elo) 1L else 2L
  ew <- rep(NA_real_, n); ew[s0:n] <- ewma_vec(chg[s0:n], 5); out[, "ewma_change"] <- ew
  # Z-score: ROC-10 / sd of the team's changes in games 1..k only (an expanding
  # window; never the full-season sd).
  ok <- !is.na(chg); m <- cumsum(ok); s1 <- cumsum(ifelse(ok, chg, 0)); s2 <- cumsum(ifelse(ok, chg^2, 0))
  sdc <- sqrt(pmax((s2 - s1^2 / m) / (m - 1), 0)); sdc[m < 2] <- NA_real_
  out[, "zscore"] <- ifelse(sdc > 0, roc / sdc, NA_real_)
  G <- trail(pmax(chg, 0), rep(0.1, 10)); Lo <- trail(pmax(-chg, 0), rep(0.1, 10))
  out[, "rsi"] <- ifelse(G + Lo > 0, 100 * G / (G + Lo), NA_real_)
  s10 <- trail(chg, rep(1, 10))
  out[, "growth"] <- s10 - lagn(s10, 10L)                                # difference, not the unstable ratio
  sg <- if (is_elo) ifelse(win, 1, -1) else ifelse(is.na(chg), 0, sign(chg))
  st <- numeric(n); st[1] <- sg[1]
  for (i in 2:n) st[i] <- if (sg[i] == 0) 0 else if (sign(st[i - 1L]) == sg[i]) st[i - 1L] + sg[i] else sg[i]
  out[, "streak"] <- st
  mm <- numeric(n); acc <- 0
  for (i in k) { acc <- IMPULSE_DECAY * acc + ifelse(is.na(chg[i]), 0, chg[i]); mm[i] <- acc }
  out[, "impulse"] <- mm
  out[k < MIN_GAMES, ] <- NA_real_
  out
}

say("Computing 154 features (Kalman slopes are fitted per fold below)")
FR <- matrix(NA_real_, NTG, NF, dimnames = list(NULL, FEATURES))
UNITS <- list()   # per series: compressed team-season series for the Kalman filter
for (sn in names(SERIES)) {
  col <- paste0("s_", sn); units <- list()
  for (b in unique(TG$block)) {
    r <- which(TG$block == b); r <- r[order(TG$k[r])]
    v <- TG[[col]][r]; keep <- !is.na(v); rr <- r[keep]
    if (!length(rr)) next
    M <- compute_measures(v[keep], sn == "elo", elo_pre1 = TG$elo_pre[r[1]], win = TG$win[rr])
    FR[rr, paste(sn, colnames(M), sep = "__")] <- M
    units[[b]] <- list(season = TG$season[rr[1]], rows = rr, vals = v[keep])
  }
  UNITS[[sn]] <- units
}

# Kalman local linear trend (level + slope), FILTERED (forward) slope: the
# estimate after game k uses games 1..k only (no smoothing pass). The three noise
# variances are fitted by maximum likelihood on the training seasons' series only.
kalman_run <- function(Y, lpar, slope = FALSE) {
  h <- exp(lpar[1]); qe <- exp(lpar[2]); qz <- exp(lpar[3])
  n <- nrow(Y); Tm <- ncol(Y)
  l <- Y[, 1]; b <- rep(0, n); P11 <- rep(h, n); P12 <- rep(0, n); P22 <- rep(1, n)
  ll <- 0; S <- if (slope) matrix(NA_real_, n, Tm) else NULL
  if (slope) S[, 1] <- b
  for (t in 2:Tm) {
    y <- Y[, t]; ok <- !is.na(y)
    al <- l + b; p11 <- P11 + 2 * P12 + P22 + qe; p12 <- P12 + P22; p22 <- P22 + qz
    Fv <- p11 + h; e <- y - al; K1 <- p11 / Fv; K2 <- p12 / Fv
    l <- ifelse(ok, al + K1 * e, al); b <- ifelse(ok, b + K2 * e, b)
    P11 <- ifelse(ok, p11 - p11 * K1, p11); P12 <- ifelse(ok, p12 - p11 * K2, p12); P22 <- ifelse(ok, p22 - p12 * K2, p22)
    if (t >= 3) ll <- ll - 0.5 * sum((log(Fv) + e^2 / Fv)[ok])
    if (slope) S[, t] <- ifelse(ok, b, NA_real_)
  }
  if (slope) S else -ll
}
unit_matrix <- function(units) {
  Tm <- max(vapply(units, function(u) length(u$vals), integer(1)))
  Y <- matrix(NA_real_, length(units), Tm)
  for (i in seq_along(units)) Y[i, seq_along(units[[i]]$vals)] <- units[[i]]$vals
  Y
}
kalman_version <- function(train_seasons) {
  K <- matrix(NA_real_, NTG, length(SERIES), dimnames = list(NULL, FEATURES[KCOL])); pars <- list()
  for (si in seq_along(SERIES)) {
    units <- UNITS[[names(SERIES)[si]]]
    units <- units[vapply(units, function(u) length(u$vals) >= 2L, logical(1))]
    tr <- units[vapply(units, function(u) u$season %in% train_seasons, logical(1))]
    allv <- unlist(lapply(tr, `[[`, "vals")); mu <- mean(allv); sdv <- stats::sd(allv)
    Ytr <- (unit_matrix(tr) - mu) / sdv
    fit <- stats::optim(c(log(0.5), log(0.05), log(0.001)), function(lp) kalman_run(Ytr, lp),
                        method = "Nelder-Mead", control = list(maxit = 400))
    S <- kalman_run((unit_matrix(units) - mu) / sdv, fit$par, slope = TRUE) * sdv
    for (i in seq_along(units)) {
      rr <- units[[i]]$rows; sl <- S[i, seq_along(rr)]; sl[seq_along(rr) < MIN_GAMES] <- NA_real_
      K[rr, si] <- sl
    }
    pars[[names(SERIES)[si]]] <- c(obs_var = exp(fit$par[1]), level_var = exp(fit$par[2]), slope_var = exp(fit$par[3]),
                                   scale_sd = sdv, converged = fit$convergence == 0)
  }
  list(K = K, pars = pars)
}
say("Fitting Kalman variances per fold (training seasons only)")
KV <- list()
for (s in HIST_SEASONS) KV[[as.character(s)]] <- kalman_version(setdiff(HIST_SEASONS, s))
KV[["full"]] <- kalman_version(HIST_SEASONS)

# ------------------------------------------------------------------------------
# 4. Cross-team z-scores by date (each team's latest state on or before the date)
# ------------------------------------------------------------------------------
ZIDX <- list()
NG$h_row <- NA_integer_; NG$a_row <- NA_integer_
for (s in unique(TG$season)) {
  r <- which(TG$season == s); dates <- sort(unique(TG$game_date[r])); teams <- sort(unique(TG$team[r]))
  LR <- matrix(NA_integer_, length(dates), length(teams), dimnames = list(NULL, teams))
  for (tm in teams) {
    rr <- r[TG$team[r] == tm]; rr <- rr[order(TG$game_date[rr])]
    pos <- findInterval(as.numeric(dates), as.numeric(TG$game_date[rr]))
    LR[pos > 0, tm] <- rr[pos[pos > 0]]
  }
  on_date <- split(r, factor(match(TG$game_date[r], dates), levels = seq_along(dates)))
  gi <- which(NG$season == s); pp <- match(NG$prev_date[gi], dates)
  NG$h_row[gi] <- ifelse(is.na(pp), NA_integer_, LR[cbind(pmax(pp, 1L), match(NG$home[gi], teams))])
  NG$a_row[gi] <- ifelse(is.na(pp), NA_integer_, LR[cbind(pmax(pp, 1L), match(NG$away[gi], teams))])
  ng_on <- split(gi, factor(pp, levels = seq_along(dates)))
  ZIDX[[as.character(s)]] <- list(dates = dates, LR = LR, on_date = on_date, ng_on = ng_on)
}
stopifnot(all(is.na(NG$h_row) | TG$game_date[NG$h_row] < NG$game_date))   # look-ahead guard
NG$snet_diff <- TG$snet[NG$h_row] - TG$snet[NG$a_row]

zdate <- function(M, min_teams) {
  Z <- matrix(NA_real_, nrow(M), ncol(M), dimnames = list(NULL, colnames(M)))
  ZN <- matrix(NA_real_, nrow(NG), ncol(M), dimnames = list(NULL, colnames(M)))
  for (zi in ZIDX) for (di in seq_along(zi$dates)) {
    lr <- zi$LR[di, ]; lr <- lr[!is.na(lr)]
    X <- M[lr, , drop = FALSE]; ok <- !is.na(X); cnt <- colSums(ok); X[!ok] <- 0
    mu <- colSums(X) / cnt; sdv <- sqrt(pmax((colSums(X^2) - cnt * mu^2) / (cnt - 1), 0))
    bad <- cnt < min_teams; den <- ifelse(is.na(sdv) | sdv < 1e-9, Inf, sdv)
    zf <- function(rows) { Y <- sweep(sweep(M[rows, , drop = FALSE], 2, mu), 2, den, "/"); Y[, bad] <- NA_real_; Y }
    rows <- zi$on_date[[di]]; if (length(rows)) Z[rows, ] <- zf(rows)
    g <- zi$ng_on[[di]]
    if (length(g)) { g <- g[!is.na(NG$h_row[g]) & !is.na(NG$a_row[g])]
      if (length(g)) ZN[g, ] <- zf(NG$h_row[g]) - zf(NG$a_row[g]) }
  }
  list(Z = Z, ZN = ZN)
}
say("Cross-team z-scores")
zb <- zdate(FR, MIN_Z_TEAMS); ZB <- zb$Z; ZBN <- zb$ZN
ZK <- lapply(KV, function(v) zdate(v$K, MIN_Z_TEAMS))
getZ <- function(key) { Z <- ZB; Z[, KCOL] <- ZK[[key]]$Z; Z }
getZN <- function(key) { Z <- ZBN; Z[, KCOL] <- ZK[[key]]$ZN; Z }

# Feature count and missing counts (historical team-game rows).
hist_rows <- TG$season %in% HIST_SEASONS
Zfull <- getZ("full")
feat_missing <- data.frame(feature = FEATURES, series = FEAT_SERIES, measure = FEAT_MEASURE,
                           present = colSums(!is.na(Zfull[hist_rows, ])), missing = colSums(is.na(Zfull[hist_rows, ])),
                           missing_with_primary_target = colSums(is.na(Zfull[hist_rows & !is.na(TG[[PRIMARY]]), ])),
                           stringsAsFactors = FALSE)
cat(sprintf("\n>>> Features computed: %d (%d series x %d measures) on %d historical team-game rows\n",
            NF, length(SERIES), length(MEASURES), sum(hist_rows)))
cat("    Missing count per measure (summed over the 14 series; missing = before game 10, warm-up of the measure, or no z that date):\n")
print(tapply(feat_missing$missing, factor(feat_missing$measure, levels = names(MEASURES)), sum))
cat(sprintf("    Missing per feature: min %d, median %d, max %d of %d rows\n",
            min(feat_missing$missing), as.integer(stats::median(feat_missing$missing)), max(feat_missing$missing), sum(hist_rows)))

# Board components per window (the board's own window_states), z among ranked teams.
say("Board components (form, trend, residual, Elo change) per window")
BOARD <- list()
for (w in MOMENTUM_WINDOWS) {
  raw <- matrix(NA_real_, NTG, 4, dimnames = list(NULL, c("form", "trend", "residual", "elo")))
  for (s in names(PANELS)) {
    st <- window_states(PANELS[[s]], w)
    r <- which(TG$season == as.integer(s)); ix <- match(paste(TG$team[r], TG$k[r]), paste(st$team, st$game_index))
    st <- st[ix, ]
    raw[r, "form"] <- ifelse(st$ranked, st$adj_form, NA); raw[r, "trend"] <- ifelse(st$ranked, st$net_change, NA)
    raw[r, "elo"] <- ifelse(st$ranked, st$elo_change_window, NA)
    raw[r, "residual"] <- ifelse(st$residual_ranked, st$residual, NA)
  }
  BOARD[[as.character(w)]] <- zdate(raw, BOARD_MIN_Z_TEAMS)$Z
}
CURRENT_W3 <- COMBINED_WEIGHTS[c("form", "trend", "elo")] / sum(COMBINED_WEIGHTS[c("form", "trend", "elo")])
board_score <- function(w) as.numeric(BOARD[[as.character(w)]][, c("form", "trend", "elo")] %*% CURRENT_W3)

# ------------------------------------------------------------------------------
# 5. Evaluation machinery
# ------------------------------------------------------------------------------
block_levels <- function(seasons) sort(unique(TG$block[TG$season %in% seasons]))
make_counts <- function(nb, seed) {
  set.seed(seed)
  idx <- matrix(sample.int(nb, nb * N_BOOT, replace = TRUE), nrow = N_BOOT)
  t(apply(idx, 1, tabulate, nbins = nb))
}
COUNTS <- list()
get_counts <- function(seasons) {
  key <- paste(seasons, collapse = ",")
  if (is.null(COUNTS[[key]])) COUNTS[[key]] <<- list(levels = block_levels(seasons), C = make_counts(length(block_levels(seasons)), STUDY_SEED + length(seasons)))
  COUNTS[[key]]
}
block_sums <- function(S, blk, nb) {
  out <- matrix(0, nb, ncol(S)); rs <- rowsum(S, blk); out[as.integer(rownames(rs)), ] <- rs; out
}
q95 <- function(x) unname(stats::quantile(x, c(0.025, 0.975), na.rm = TRUE))
solve_safe <- function(A, b) tryCatch(solve(A, b), error = function(e) qr.solve(A, b))
logit_fit <- function(X, y) stats::glm.fit(cbind(1, X), y, family = stats::binomial())$coefficients
logit_pred <- function(b, X) as.numeric(stats::plogis(cbind(1, X) %*% b))
log_loss <- function(p, y) { p <- pmin(pmax(p, 1e-12), 1 - 1e-12); -(y * log(p) + (1 - y) * log(1 - p)) }
auc_fast <- function(p, y) { r <- rank(p); n1 <- sum(y == 1); n0 <- length(y) - n1; (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0) }

# Continuous: pooled out-of-fold R^2 gain over the baseline (same rows), and the
# incremental IC = Spearman correlation of the candidate's out-of-fold increment
# with the baseline's out-of-fold residual. Bootstrap over team-season blocks
# (ranks fixed at their full-sample values inside the bootstrap).
cont_stats <- function(y, pb, pc, blk, cnt) {
  eb <- y - pb; ec <- y - pc; r1 <- rank(pc - pb); r2 <- rank(eb)
  S <- block_sums(cbind(1, y, y^2, eb^2, ec^2, r1, r2, r1^2, r2^2, r1 * r2), blk, length(cnt$levels))
  f <- function(B) {
    n <- B[, 1]; sst <- B[, 3] - B[, 2]^2 / n
    cv <- B[, 10] / n - B[, 6] * B[, 7] / n^2
    cbind(gain = (B[, 4] - B[, 5]) / sst, ic = cv / sqrt((B[, 8] / n - (B[, 6] / n)^2) * (B[, 9] / n - (B[, 7] / n)^2)))
  }
  pt <- f(matrix(colSums(S), 1)); bt <- f(cnt$C %*% S)
  list(r2_gain = unname(pt[1, 1]), ic = unname(pt[1, 2]), ci = q95(bt[, 1]), ic_ci = q95(bt[, 2]),
       p = (1 + sum(bt[, 1] <= 0, na.rm = TRUE)) / (N_BOOT + 1), n = length(y), boot = bt[, 1])
}
# Binary: McFadden-style gain = (baseline log loss - candidate log loss) / null log loss.
bin_stats <- function(y, pb, pc, blk, cnt) {
  llb <- log_loss(pb, y); llc <- log_loss(pc, y); ll0 <- log_loss(rep(mean(y), length(y)), y)
  S <- block_sums(cbind(llb, llc, ll0), blk, length(cnt$levels))
  pt <- colSums(S); bt <- cnt$C %*% S
  g <- (bt[, 1] - bt[, 2]) / bt[, 3]
  list(r2_gain = unname((pt[1] - pt[2]) / pt[3]), ic = auc_fast(pc, y) - auc_fast(pb, y), ci = q95(g), ic_ci = c(NA, NA),
       p = (1 + sum(g <= 0)) / (N_BOOT + 1), n = length(y), boot = g)
}

verdict_of <- function(gain, lo, q) {
  if (is.na(gain)) return(c("inconclusive", "not enough rows to score"))
  if (gain <= 0) return(c("discarded", "adds nothing to Elo plus season net rating on unseen seasons (out-of-fold gain is zero or negative)"))
  if (lo > 0 && q < FDR_Q) return(c("kept", sprintf("adds to Elo plus season net rating on unseen seasons; the 95%% interval is above zero and it survives the false-discovery correction (q < %.2f)", FDR_Q)))
  if (lo > 0) return(c("inconclusive", "positive with an interval above zero, but it does not survive the false-discovery correction across 154 features"))
  c("inconclusive", "small positive gain, but the 95% interval includes zero")
}

screen_target <- function(tid, seasons) {
  cnt <- get_counts(seasons); binary <- tid == "next_game_win"
  if (!binary) {
    y <- TG[[tid]]; Xb <- cbind(1, TG$elo_c, TG$snet); sea <- TG$season; blkv <- match(TG$block, cnt$levels)
    base_ok <- sea %in% seasons & !is.na(y) & stats::complete.cases(Xb)
  } else {
    y <- NG$home_win; Xb <- cbind(NG$elo_diff, NG$snet_diff); sea <- NG$season; blkv <- match(NG$block, cnt$levels)
    base_ok <- sea %in% seasons & !is.na(y) & stats::complete.cases(Xb)
  }
  PB <- matrix(NA_real_, length(y), NF); PC <- PB
  for (s in seasons) {
    Z <- if (binary) getZN(as.character(s)) else getZ(as.character(s))
    tr0 <- base_ok & sea != s; te0 <- base_ok & sea == s
    for (j in seq_len(NF)) {
      okj <- !is.na(Z[, j]); tr <- tr0 & okj; te <- te0 & okj
      if (sum(te) == 0 || sum(tr) < 50) next
      if (!binary) {
        bb <- solve_safe(crossprod(Xb[tr, ]), crossprod(Xb[tr, ], y[tr])); PB[te, j] <- Xb[te, ] %*% bb
        Xc <- cbind(Xb, Z[, j]); bc <- solve_safe(crossprod(Xc[tr, ]), crossprod(Xc[tr, ], y[tr])); PC[te, j] <- Xc[te, ] %*% bc
      } else {
        PB[te, j] <- logit_pred(logit_fit(Xb[tr, , drop = FALSE], y[tr]), Xb[te, , drop = FALSE])
        Xc <- cbind(Xb, Z[, j]); PC[te, j] <- logit_pred(logit_fit(Xc[tr, ], y[tr]), Xc[te, ])
      }
    }
  }
  Zm <- if (binary) getZN("full") else getZ("full")
  rows <- lapply(seq_len(NF), function(j) {
    ok <- base_ok & !is.na(PC[, j])
    st <- if (!binary) cont_stats(y[ok], PB[ok, j], PC[ok, j], blkv[ok], cnt) else bin_stats(y[ok], PB[ok, j], PC[ok, j], blkv[ok], cnt)
    st$missing <- sum(base_ok & is.na(Zm[, j]))
    st
  })
  df <- data.frame(feature = FEATURES, series = FEAT_SERIES, measure = FEAT_MEASURE, target = tid,
                   incremental_ic = vapply(rows, `[[`, 0, "ic"), r2_gain = vapply(rows, `[[`, 0, "r2_gain"),
                   ci_lo = vapply(rows, function(r) r$ci[1], 0), ci_hi = vapply(rows, function(r) r$ci[2], 0),
                   p_value = vapply(rows, `[[`, 0, "p"), n = vapply(rows, `[[`, 0, "n"),
                   missing = vapply(rows, `[[`, 0, "missing"), stringsAsFactors = FALSE)
  df$q_value <- stats::p.adjust(df$p_value, "BH")
  v <- t(mapply(verdict_of, df$r2_gain, df$ci_lo, df$q_value)); df$verdict <- v[, 1]; df$reason <- v[, 2]
  df$ic_metric <- if (binary) "ROC-AUC change vs baseline" else "incremental rank IC (Spearman, out-of-fold)"
  df$gain_metric <- if (binary) "log-loss gain / null log loss (McFadden-style R^2 gain)" else "pooled out-of-fold R^2 gain"
  df
}

# ------------------------------------------------------------------------------
# 6. Part A step 1-2: single features and redundancy families
# ------------------------------------------------------------------------------
say("Part A step 1: single-feature screening, %d targets x %d features, LOSO over %d seasons", nrow(TARGETS), NF, length(HIST_SEASONS))
SINGLE <- do.call(rbind, lapply(TARGETS$id, function(tid) { r <- screen_target(tid, HIST_SEASONS); say("  %s done", tid); r }))
rownames(SINGLE) <- NULL
prim <- SINGLE[SINGLE$target == PRIMARY, ]; prim <- prim[order(-prim$r2_gain), ]
cat("\n>>> Top 10 single features on the primary target (pooled OOF R^2 gain, 95% CI, q):\n")
print(head(prim[, c("feature", "r2_gain", "ci_lo", "ci_hi", "incremental_ic", "q_value", "n", "verdict")], 10), row.names = FALSE)
cat("    Verdicts by target:\n"); print(table(SINGLE$target, SINGLE$verdict))

say("Part A step 2: redundancy families")
R <- suppressWarnings(stats::cor(Zfull[hist_rows, ], use = "pairwise.complete.obs"))
R[is.na(R)] <- 0
feat_cl <- stats::cutree(stats::hclust(stats::as.dist(1 - abs(R)), "complete"), h = 0.3)
feat_families <- lapply(split(FEATURES, feat_cl), identity)
feat_families <- feat_families[order(-lengths(feat_families))]
pair_mean <- function(by, ids) {
  M <- matrix(NA_real_, length(ids), length(ids), dimnames = list(ids, ids))
  for (a in ids) for (b in ids) {
    if (by == "measure") M[a, b] <- mean(abs(diag(R[FEAT_MEASURE == a, FEAT_MEASURE == b])))
    else M[a, b] <- mean(abs(diag(R[FEAT_SERIES == a, FEAT_SERIES == b])))
  }
  M
}
RM <- pair_mean("measure", names(MEASURES)); RS <- pair_mean("series", names(SERIES))
measure_cl <- stats::cutree(stats::hclust(stats::as.dist(1 - RM), "average"), h = 0.5)
series_cl <- stats::cutree(stats::hclust(stats::as.dist(1 - RS), "average"), h = 0.5)
cat("    Measure families (mean |r| across series >= 0.5):\n"); print(split(names(MEASURES), measure_cl))
cat("    Series families (mean |r| across measures >= 0.5):\n"); print(split(names(SERIES), series_cl))
cat(sprintf("    Feature clusters with every pair |r| >= 0.7: %d clusters, %d with more than one feature\n",
            length(feat_families), sum(lengths(feat_families) > 1)))

# ------------------------------------------------------------------------------
# 7. Part A step 3-5: nested combination search, comparisons, permutations, stability
# ------------------------------------------------------------------------------
SER_TRIPLES <- utils::combn(TOP_K, 3); MEA_TRIPLES <- utils::combn(TOP_K, 3)
COMB_ROWS <- hist_rows & !is.na(TG[[PRIMARY]]) & !is.na(TG$elo_c) & !is.na(TG$snet) &
  stats::complete.cases(Zfull) & !is.na(board_score(10L))
fcol <- function(si, mi) 3L + (si - 1L) * length(MEASURES) + mi   # column in [1, elo, snet, Z]

# Sufficient statistics per fold version and season (X'X does not change under permutation).
prep_comb <- function(seasons) {
  ri <- which(COMB_ROWS & TG$season %in% seasons)
  Xb <- cbind(1, TG$elo_c[ri], TG$snet[ri])
  keys <- c(as.character(seasons), "full")
  A <- list(); Xs <- list()
  for (key in keys) {
    X <- cbind(Xb, getZ(key)[ri, ]); Xs[[key]] <- X
    A[[key]] <- lapply(setNames(seasons, seasons), function(t) crossprod(X[TG$season[ri] == t, ]))
  }
  list(ri = ri, sea = TG$season[ri], date = TG$game_date[ri], X = Xs, A = A, seasons = seasons)
}

# Inner search on a set of training seasons: rank series and measures on those
# seasons only, then choose (combination, ridge alpha) by inner LOSO pooled SSE.
inner_search <- function(P, key, y, train, want_blocks = FALSE) {
  X <- P$X[[key]]; sea <- P$sea; trr <- sea %in% train
  Xt <- X[trr, ]; yt <- y[trr]
  bb <- solve_safe(crossprod(Xt[, 1:3]), crossprod(Xt[, 1:3], yt)); res <- yt - Xt[, 1:3] %*% bb
  cors <- abs(suppressWarnings(stats::cor(Xt[, -(1:3)], res)))[, 1]; cors[is.na(cors)] <- 0
  CM <- matrix(cors, nrow = length(SERIES), byrow = TRUE)
  top_s <- order(-rowMeans(CM))[1:TOP_K]; top_m <- order(-colMeans(CM))[1:TOP_K]
  cl <- list(); yy <- list(); n <- list(); sy <- list()
  for (t in train) { w <- sea == t; cl[[as.character(t)]] <- crossprod(X[w, ], y[w]); yy[[as.character(t)]] <- sum(y[w]^2); n[[as.character(t)]] <- sum(w); sy[[as.character(t)]] <- sum(y[w]) }
  Aall <- Reduce(`+`, P$A[[key]][as.character(train)]); call <- Reduce(`+`, cl); N <- sum(unlist(n))
  sst <- sum(unlist(yy)) - sum(unlist(sy))^2 / N
  sse_cols <- function(cols, alpha) {
    pen <- diag(c(rep(0, 3), rep(1, length(cols) - 3)), length(cols)) * alpha
    tot <- 0
    for (t in as.character(train)) {
      Ai <- P$A[[key]][[t]][cols, cols]; ci <- cl[[t]][cols]
      b <- solve_safe(Aall[cols, cols] - Ai + pen * (N - n[[t]]), call[cols] - ci)
      tot <- tot + yy[[t]] - 2 * sum(b * ci) + as.numeric(t(b) %*% Ai %*% b)
    }
    tot
  }
  base_sse <- sse_cols(1:3, 0)
  best <- list(sse = Inf); cand <- NULL
  for (a in seq_along(RIDGE_ALPHAS)) for (i in seq_len(ncol(SER_TRIPLES))) for (j in seq_len(ncol(MEA_TRIPLES))) {
    ss <- top_s[SER_TRIPLES[, i]]; ms <- top_m[MEA_TRIPLES[, j]]
    cols <- c(1:3, as.vector(outer(ss, ms, fcol)))
    e <- sse_cols(cols, RIDGE_ALPHAS[a])
    if (want_blocks) cand <- rbind(cand, c(a, i, j, e))
    if (e < best$sse) best <- list(sse = e, series = ss, measures = ms, alpha = RIDGE_ALPHAS[a], cols = cols)
  }
  best$inner_gain <- (base_sse - best$sse) / sst
  best$top_series <- names(SERIES)[top_s]; best$top_measures <- names(MEASURES)[top_m]
  best$Aall <- Aall; best$call <- call; best$N <- N; best$cand <- cand; best$ss_top <- top_s; best$ms_top <- top_m
  best
}
fit_cols <- function(best) {
  cols <- best$cols; pen <- diag(c(rep(0, 3), rep(1, length(cols) - 3)), length(cols)) * best$alpha
  solve_safe(best$Aall[cols, cols] + pen * best$N, best$call[cols])
}

combo_search <- function(P, y, detail = TRUE) {
  sea <- P$sea; pc <- pb <- rep(NA_real_, length(y)); folds <- list()
  for (s in P$seasons) {
    key <- as.character(s); train <- setdiff(P$seasons, s); te <- sea == s
    best <- inner_search(P, key, y, train)
    X <- P$X[[key]]
    pc[te] <- X[te, best$cols] %*% fit_cols(best)
    pb[te] <- X[te, 1:3] %*% solve_safe(best$Aall[1:3, 1:3], best$call[1:3])
    if (detail) {
      sst_s <- sum((y[te] - mean(y[te]))^2)
      folds[[season_name(s)]] <- list(held_out = season_name(s), series = names(SERIES)[best$series],
                                      measures = names(MEASURES)[best$measures], ridge_alpha = best$alpha,
                                      top6_series = best$top_series, top6_measures = best$top_measures,
                                      inner_r2_gain = best$inner_gain,
                                      held_out_r2_gain = (sum((y[te] - pb[te])^2) - sum((y[te] - pc[te])^2)) / sst_s,
                                      held_out_rows = sum(te))
    }
  }
  gain <- (sum((y - pb)^2) - sum((y - pc)^2)) / sum((y - mean(y))^2)
  list(gain = gain, folds = folds, pc = pc, pb = pb)
}

permute_within_date <- function(y, sea, date) {
  g <- paste(sea, date); out <- y
  for (ix in split(seq_along(y), g)) if (length(ix) > 1) out[ix] <- y[ix[sample.int(length(ix))]]
  out
}

# Comparisons on the same rows and folds: elastic net (all 154), greedy forward
# selection, and the board's current score (window 10, residual dropped, weights rescaled).
compare_models <- function(P, y) {
  sea <- P$sea; out <- list(); pe <- pg <- pbd <- pb <- rep(NA_real_, length(y)); greedy_sel <- list(); enet_n <- list()
  bscore <- board_score(10L)[P$ri]
  for (s in P$seasons) {
    key <- as.character(s); X <- P$X[[key]]; tr <- sea != s; te <- sea == s; train <- setdiff(P$seasons, s)
    pb[te] <- X[te, 1:3] %*% solve_safe(crossprod(X[tr, 1:3]), crossprod(X[tr, 1:3], y[tr]))
    # elastic net, lambda by inner LOSO
    set.seed(STUDY_SEED + s)
    fid <- match(sea[tr], train)
    cvf <- glmnet::cv.glmnet(X[tr, -1], y[tr], foldid = fid, alpha = 0.5, penalty.factor = c(0, 0, rep(1, NF)))
    pe[te] <- as.numeric(stats::predict(cvf, X[te, -1], s = "lambda.min"))
    co <- as.matrix(stats::coef(cvf, s = "lambda.min"))[-(1:3), 1]; enet_n[[season_name(s)]] <- sum(co != 0)
    # greedy forward selection (OLS), inner LOSO pooled SSE, up to 9 features
    cl <- list(); yy <- list(); nn <- list()
    for (t in as.character(train)) { w <- sea == as.integer(t); cl[[t]] <- crossprod(X[w, ], y[w]); yy[[t]] <- sum(y[w]^2); nn[[t]] <- sum(w) }
    Aall <- Reduce(`+`, P$A[[key]][as.character(train)]); call <- Reduce(`+`, cl)
    sse <- function(cols) { tot <- 0; for (t in as.character(train)) { Ai <- P$A[[key]][[t]][cols, cols]; ci <- cl[[t]][cols]
      b <- solve_safe(Aall[cols, cols] - Ai, call[cols] - ci); tot <- tot + yy[[t]] - 2 * sum(b * ci) + as.numeric(t(b) %*% Ai %*% b) }; tot }
    cur <- 1:3; cur_sse <- sse(cur)
    repeat {
      if (length(cur) >= 12) break
      cand <- setdiff(4:(3 + NF), cur); e <- vapply(cand, function(j) sse(c(cur, j)), 0)
      if (min(e) >= cur_sse) break
      cur <- c(cur, cand[which.min(e)]); cur_sse <- min(e)
    }
    greedy_sel[[season_name(s)]] <- FEATURES[cur[-(1:3)] - 3]
    pg[te] <- X[te, cur] %*% solve_safe(Aall[cur, cur], call[cur])
    Xd <- cbind(X[, 1:3], bscore)
    pbd[te] <- Xd[te, ] %*% solve_safe(crossprod(Xd[tr, ]), crossprod(Xd[tr, ], y[tr]))
  }
  list(pb = pb, enet = pe, greedy = pg, board = pbd, greedy_selected = greedy_sel, enet_nonzero = enet_n)
}

summ_gain <- function(y, pb, pc, blk, cnt) { st <- cont_stats(y, pb, pc, blk, cnt); list(r2_gain = st$r2_gain, ci = st$ci, ic = st$ic, boot = st$boot) }

run_part_a_search <- function(seasons, label, with_perm) {
  say("Part A step 3 (%s): nested combination search over %s", label, paste(season_name(seasons), collapse = ", "))
  P <- prep_comb(seasons); y <- TG[[PRIMARY]][P$ri]
  cnt <- get_counts(seasons); blk <- match(TG$block[P$ri], cnt$levels)
  real <- combo_search(P, y)
  real_stats <- summ_gain(y, real$pb, real$pc, blk, cnt)
  say("  combination search done: pooled OOF R^2 gain %.5f [%.5f, %.5f]", real_stats$r2_gain, real_stats$ci[1], real_stats$ci[2])
  cmp <- compare_models(P, y)
  comps <- list(elastic_net = summ_gain(y, cmp$pb, cmp$enet, blk, cnt), greedy_forward = summ_gain(y, cmp$pb, cmp$greedy, blk, cnt),
                board_current_score_w10 = summ_gain(y, cmp$pb, cmp$board, blk, cnt))
  for (nm in names(comps)) comps[[nm]]$boot <- NULL
  # paired: combination search vs board score
  st_vs_board <- cont_stats(y, cmp$board, real$pc, blk, cnt)
  say("  comparisons done")
  # Stability
  fsel <- real$folds
  ser_counts <- sort(table(unlist(lapply(fsel, `[[`, "series"))), decreasing = TRUE)
  mea_counts <- sort(table(unlist(lapply(fsel, `[[`, "measures"))), decreasing = TRUE)
  combo_ids <- vapply(fsel, function(f) paste(paste(sort(f$series), collapse = "+"), "x", paste(sort(f$measures), collapse = "+")), "")
  mfam <- function(m) paste0("M", measure_cl[m]); sfam <- function(s) paste0("S", series_cl[s])
  ser_fam_counts <- sort(table(unlist(lapply(fsel, function(f) unique(sfam(f$series))))), decreasing = TRUE)
  mea_fam_counts <- sort(table(unlist(lapply(fsel, function(f) unique(mfam(f$measures))))), decreasing = TRUE)
  nfold <- length(fsel); need <- ceiling(STABLE_SHARE * nfold)
  stable_exact <- length(ser_counts) >= 3 && length(mea_counts) >= 3 && all(head(ser_counts, 3) >= need) && all(head(mea_counts, 3) >= need)
  stable_family <- all(head(ser_fam_counts, min(3, length(ser_fam_counts))) >= need) && all(head(mea_fam_counts, min(3, length(mea_fam_counts))) >= need)
  season_gain <- vapply(fsel, `[[`, 0, "held_out_r2_gain")
  out <- list(label = label, seasons = season_name(seasons), rows = length(y), folds = unname(fsel),
              pooled_r2_gain = real_stats$r2_gain, pooled_ci = real_stats$ci, pooled_ic = real_stats$ic,
              comparisons = comps, combination_vs_board_r2_gain = st_vs_board$r2_gain, combination_vs_board_ci = st_vs_board$ci,
              greedy_selected = cmp$greedy_selected, elastic_net_nonzero = cmp$enet_nonzero,
              stability = list(series_counts = as.list(ser_counts), measure_counts = as.list(mea_counts),
                               series_family_counts = as.list(ser_fam_counts), measure_family_counts = as.list(mea_fam_counts),
                               distinct_combinations = length(unique(combo_ids)), combination_counts = as.list(table(combo_ids)),
                               folds_needed = need, stable_exact = stable_exact, stable_family = stable_family,
                               seasons_with_positive_gain = sum(season_gain > 0), of_seasons = nfold))
  out$P <- P; out$y <- y; out$blk <- blk
  out
}

# Final selection on all historical seasons (fixed BEFORE the holdout is looked at),
# with the number of combinations tied with the best (block bootstrap of inner SSE).
final_selection <- function(A_res) {
  P <- A_res$P; y <- A_res$y; cnt <- get_counts(P$seasons); blk <- A_res$blk
  best <- inner_search(P, "full", y, P$seasons, want_blocks = TRUE)
  X <- P$X[["full"]]; sea <- P$sea; a_ix <- match(best$alpha, RIDGE_ALPHAS)
  cand <- best$cand[best$cand[, 1] == a_ix, , drop = FALSE]
  nb <- length(cnt$levels); SSEB <- matrix(0, nb, nrow(cand))
  for (ci in seq_len(nrow(cand))) {
    ss <- best$ss_top[SER_TRIPLES[, cand[ci, 2]]]; ms <- best$ms_top[MEA_TRIPLES[, cand[ci, 3]]]
    cols <- c(1:3, as.vector(outer(ss, ms, fcol))); pen <- diag(c(rep(0, 3), rep(1, 9))) * best$alpha
    e2 <- numeric(length(y))
    for (t in P$seasons) {
      w <- sea == t; Ai <- P$A[["full"]][[as.character(t)]]
      b <- solve_safe(best$Aall[cols, cols] - Ai[cols, cols] + pen * (best$N - sum(w)), best$call[cols] - crossprod(X[w, cols], y[w]))
      e2[w] <- (y[w] - X[w, cols] %*% b)^2
    }
    SSEB[, ci] <- block_sums(matrix(e2), blk, nb)[, 1]
  }
  bj <- which.min(colSums(SSEB))
  D <- cnt$C %*% (SSEB - SSEB[, bj])
  ties <- sum(apply(D, 2, function(d) stats::quantile(d, 0.025) <= 0)) - 1L
  list(series = names(SERIES)[best$series], measures = names(MEASURES)[best$measures], alpha = best$alpha,
       features = FEATURES[best$cols[-(1:3)] - 3], inner_r2_gain = best$inner_gain,
       top6_series = best$top_series, top6_measures = best$top_measures,
       tied_with_best = ties, of_combinations = nrow(cand), coef = fit_cols(best), cols = best$cols, best = best)
}

A_MAIN <- run_part_a_search(HIST_SEASONS, "main (8 seasons)", TRUE)

# Permutation baseline (the long step): the whole nested search with targets shuffled
# among teams within each date.
say("Part A step 4: permutation baseline, %d runs (each = full nested search)", N_PERM)
t_perm <- Sys.time()
set.seed(STUDY_SEED + 999L)
PERM <- numeric(N_PERM)
for (b in seq_len(N_PERM)) {
  yp <- permute_within_date(A_MAIN$y, A_MAIN$P$sea, A_MAIN$P$date)
  PERM[b] <- combo_search(A_MAIN$P, yp, detail = FALSE)$gain
  if (b %% 20 == 0) say("  permutation %d of %d", b, N_PERM)
}
perm_minutes <- as.numeric(difftime(Sys.time(), t_perm, units = "mins"))
perm_p95 <- unname(stats::quantile(PERM, 0.95))
say("  permutations done in %.1f min; 95th percentile %.5f; real %.5f", perm_minutes, perm_p95, A_MAIN$pooled_r2_gain)

FINAL_A <- final_selection(A_MAIN)
crit <- c(ci_above_zero = unname(A_MAIN$pooled_ci[1] > 0), beats_permutation_p95 = unname(A_MAIN$pooled_r2_gain > perm_p95),
          stable_selection = A_MAIN$stability$stable_exact || A_MAIN$stability$stable_family,
          sign_holds_most_seasons = A_MAIN$stability$seasons_with_positive_gain > A_MAIN$stability$of_seasons / 2)
COMBO_RELIABLE <- all(crit)
combo_verdict <- if (COMBO_RELIABLE) sprintf("reliable: %s x %s", paste(FINAL_A$series, collapse = ", "), paste(FINAL_A$measures, collapse = ", ")) else
  sprintf("none found: fails %s", paste(names(crit)[!crit], collapse = ", "))
say("Combination verdict: %s", combo_verdict)

say("Sensitivity: part A without 2019-20 and 2020-21")
SENS_SINGLE <- screen_target(PRIMARY, SENS_SEASONS)
A_SENS <- run_part_a_search(SENS_SEASONS, "sensitivity (6 seasons, no 2019-20 / 2020-21)", FALSE)

# ------------------------------------------------------------------------------
# 8. Part B: the board's blend weights
# ------------------------------------------------------------------------------
simplex_grid <- function(comps, step = GRID_STEP) {
  m <- round(1 / step); k <- length(comps)
  g <- as.matrix(expand.grid(rep(list(0:m), k - 1L))); g <- g[rowSums(g) <= m, , drop = FALSE]
  g <- cbind(g, m - rowSums(g)) / m; colnames(g) <- comps; rownames(g) <- NULL; g
}
wlabel <- function(w) paste(sprintf("%s %.2f", names(w), w), collapse = " / ")

# comp_fun(key) -> NTG x m component z matrix; rows: logical over TG.
blend_eval <- function(tid, rows, seasons, comp_fun, grid, current) {
  cnt <- get_counts(seasons); nb <- length(cnt$levels)
  ri <- which(rows & TG$season %in% seasons); sea <- TG$season[ri]; y <- TG[[tid]][ri]; blk <- match(TG$block[ri], cnt$levels)
  Wall <- rbind(grid, current = current[colnames(grid)]); G <- nrow(Wall); cur_j <- G; ngrid <- G - 1L
  SSEB <- matrix(0, nb, G); eb2 <- numeric(length(y)); pbo <- numeric(length(y)); nn_e2 <- numeric(length(y)); nnw <- list()
  for (s in seasons) {
    Cm <- comp_fun(as.character(s))[ri, , drop = FALSE]; X <- cbind(1, TG$elo_c[ri], TG$snet[ri], Cm)
    tr <- sea != s; te <- sea == s
    A <- crossprod(X[tr, ]); cv <- crossprod(X[tr, ], y[tr])[, 1]
    bb <- solve_safe(A[1:3, 1:3], cv[1:3]); pbo[te] <- X[te, 1:3] %*% bb; eb2[te] <- (y[te] - pbo[te])^2
    A3c <- A[1:3, -(1:3), drop = FALSE]; Acc <- A[-(1:3), -(1:3), drop = FALSE]; cc <- cv[-(1:3)]
    B <- vapply(seq_len(G), function(g) { w <- Wall[g, ]; a34 <- A3c %*% w
      Aw <- rbind(cbind(A[1:3, 1:3], a34), c(a34, as.numeric(t(w) %*% Acc %*% w)))
      solve_safe(Aw, c(cv[1:3], sum(w * cc))) }, numeric(4))
    S <- Cm[te, , drop = FALSE] %*% t(Wall)
    E <- y[te] - X[te, 1:3] %*% B[1:3, , drop = FALSE] - sweep(S, 2, B[4, ], "*")
    SSEB <- SSEB + block_sums(E^2, blk[te], nb)
    # non-negative component weights (baseline coefficients free), training rows
    f <- function(b) as.numeric(t(b) %*% A %*% b - 2 * sum(b * cv)); gr <- function(b) as.numeric(2 * (A %*% b - cv))
    m <- ncol(Cm); b0 <- c(bb, rep(0.01, m))
    bn <- stats::optim(b0, f, gr, method = "L-BFGS-B", lower = c(rep(-Inf, 3), rep(0, m)))$par
    cw <- bn[-(1:3)]; nnw[[season_name(s)]] <- if (sum(cw) > 0) setNames(cw / sum(cw), colnames(Cm)) else setNames(rep(NA_real_, m), colnames(Cm))
    nn_e2[te] <- (y[te] - X[te, ] %*% bn)^2
  }
  SB <- block_sums(cbind(1, y, y^2, eb2, nn_e2), blk, nb)
  sst_pt <- sum(SB[, 3]) - sum(SB[, 2])^2 / sum(SB[, 1])
  gain <- (sum(SB[, 4]) - colSums(SSEB)) / sst_pt
  BS <- cnt$C %*% SB; sst_b <- BS[, 3] - BS[, 2]^2 / BS[, 1]
  GB <- (BS[, 4] - cnt$C %*% SSEB) / sst_b                      # N_BOOT x G gains
  best_j <- which.max(gain[seq_len(ngrid)])
  dbest <- GB[, best_j] - GB[, seq_len(ngrid)]
  flat <- sum(apply(dbest, 2, function(x) stats::quantile(x, 0.025) <= 0))
  d_bc <- GB[, best_j] - GB[, cur_j]
  # LOSO-selected weights: chosen on the other seasons' out-of-fold blocks, scored on the held-out season.
  bseason <- as.integer(sub(" .*", "", cnt$levels)); sel_blk <- numeric(nb); chosen <- list()
  for (s in seasons) {
    o <- bseason != s; j <- which.min(colSums(SSEB[o, seq_len(ngrid), drop = FALSE]))
    sel_blk[!o] <- SSEB[!o, j]; chosen[[season_name(s)]] <- Wall[j, ]
  }
  g_sel <- (sum(SB[, 4]) - sum(sel_blk)) / sst_pt; GSEL <- (BS[, 4] - cnt$C %*% sel_blk) / sst_b
  g_nn <- (sum(SB[, 4]) - sum(SB[, 5])) / sst_pt; GNN <- (BS[, 4] - BS[, 5]) / sst_b
  ic_of <- function(w) { sc <- as.numeric(comp_fun("full")[ri, , drop = FALSE] %*% w)
    suppressWarnings(stats::cor(sc, y - pbo, method = "spearman")) }
  singles <- vapply(colnames(grid), function(cn) gain[which(grid[, cn] == 1)], 0)
  list(target = tid, seasons = season_name(seasons), rows = length(y), components = colnames(grid),
       current_weights = current[colnames(grid)], current_r2_gain = gain[cur_j], current_ic = ic_of(current[colnames(grid)]),
       best_weights = Wall[best_j, ], best_r2_gain = gain[best_j], best_ic = ic_of(Wall[best_j, ]),
       best_vs_current = c(delta = gain[best_j] - gain[cur_j], ci_lo = q95(d_bc)[1], ci_hi = q95(d_bc)[2]),
       flatness = c(within_ci_of_best = flat, of = ngrid),
       loso_selected = list(chosen = chosen, r2_gain = g_sel,
                            vs_current = c(delta = g_sel - gain[cur_j], ci_lo = q95(GSEL - GB[, cur_j])[1], ci_hi = q95(GSEL - GB[, cur_j])[2])),
       nonnegative_regression = list(weights_by_fold = nnw, r2_gain = g_nn,
                                     vs_current = c(delta = g_nn - gain[cur_j], ci_lo = q95(GNN - GB[, cur_j])[1], ci_hi = q95(GNN - GB[, cur_j])[2])),
       component_alone_r2_gain = singles,
       .GB_best = GB[, best_j], .SSE_best = SSEB[, best_j], .SB = SB)
}
strip <- function(x) x[!grepl("^\\.", names(x))]

say("Part B: blend weights per window")
G3 <- simplex_grid(c("form", "trend", "elo"))
best_single <- prim$feature[1]                         # best part-A single feature on the primary target
best_single_is_kalman <- FEAT_MEASURE[match(best_single, FEATURES)] == "kalman"
PART_B <- list(); PART_B_SENS <- list()
for (w in MOMENTUM_WINDOWS) {
  key <- paste0("w", w); Bz <- BOARD[[as.character(w)]]
  cf3 <- function(k) Bz[, c("form", "trend", "elo")]
  rows_w <- !is.na(TG$elo_c) & !is.na(TG$snet) & stats::complete.cases(Bz[, c("form", "trend", "elo")])
  res <- list()
  for (tid in c(PRIMARY, "net5_beyond_elo")) res[[tid]] <- blend_eval(tid, rows_w & !is.na(TG[[tid]]), HIST_SEASONS, cf3, G3, CURRENT_W3)
  # trend swap / join with the best part-A single feature (same rows for the paired comparison)
  xcol <- function(k) getZ(k)[, best_single]
  rows_x <- rows_w & !is.na(TG[[PRIMARY]]) & !is.na(Zfull[, best_single])
  base3 <- blend_eval(PRIMARY, rows_x, HIST_SEASONS, cf3, G3, CURRENT_W3)
  cfs <- function(k) { m <- cbind(Bz[, c("form")], xcol(k), Bz[, "elo"]); colnames(m) <- c("form", "x", "elo"); m }
  swap <- blend_eval(PRIMARY, rows_x, HIST_SEASONS, cfs, simplex_grid(c("form", "x", "elo")), c(form = CURRENT_W3[["form"]], x = CURRENT_W3[["trend"]], elo = CURRENT_W3[["elo"]]))
  cfj <- function(k) { m <- cbind(Bz[, c("form", "trend")], xcol(k), Bz[, "elo"]); colnames(m) <- c("form", "trend", "x", "elo"); m }
  join <- blend_eval(PRIMARY, rows_x, HIST_SEASONS, cfj, simplex_grid(c("form", "trend", "x", "elo")), c(form = 0.7, trend = 0.1, x = 0.1, elo = 0.1))
  cnt <- get_counts(HIST_SEASONS)
  pd <- function(a, b) { d <- a$.GB_best - b$.GB_best; c(delta = a$best_r2_gain - b$best_r2_gain, ci_lo = q95(d)[1], ci_hi = q95(d)[2]) }
  res$trend_swap <- list(feature = best_single, rows = base3$rows, best_3_component_on_same_rows = list(weights = base3$best_weights, r2_gain = base3$best_r2_gain),
                         swap = list(weights = swap$best_weights, r2_gain = swap$best_r2_gain, vs_best_3_component = pd(swap, base3),
                                     loso_selected_vs_current_swap = swap$loso_selected$vs_current),
                         join = list(weights = join$best_weights, r2_gain = join$best_r2_gain, vs_best_3_component = pd(join, base3),
                                     flatness = join$flatness))
  res[[PRIMARY]] <- res[[PRIMARY]]; PART_B[[key]] <- res
  PART_B_SENS[[key]] <- blend_eval(PRIMARY, rows_w & !is.na(TG[[PRIMARY]]), SENS_SEASONS, cf3, G3, CURRENT_W3)
  say("  window %d done", w)
}

# Residual check: 2026-27 only (the only season with logged pregame predictions),
# in-sample, small sample, next-5 target (next-10 needs 10 later games). Rows lacking
# a residual are left out, never filled.
RESID <- list()
for (w in MOMENTUM_WINDOWS) {
  Bz <- BOARD[[as.character(w)]]
  r <- which(TG$season == HOLDOUT_SEASON & !is.na(TG$net5_beyond_elo) & stats::complete.cases(Bz))
  out <- list(label = "SMALL SAMPLE: 2026-27 only, in-sample, next-5 target; rows without a residual left out", rows = length(r),
              teams = length(unique(TG$team[r])))
  if (length(r) >= 10) {
    y <- TG$net5_beyond_elo[r]; Z4 <- Bz[r, c("form", "trend", "residual", "elo")]
    s4 <- as.numeric(Z4 %*% COMBINED_WEIGHTS[c("form", "trend", "residual", "elo")]); s3 <- as.numeric(Z4[, c("form", "trend", "elo")] %*% CURRENT_W3)
    ic <- function(s, ix = seq_along(y)) suppressWarnings(stats::cor(s[ix], y[ix], method = "spearman"))
    lv <- unique(TG$block[r]); bi <- match(TG$block[r], lv); set.seed(STUDY_SEED + w)
    boots <- replicate(N_BOOT, { pick <- sample.int(length(lv), replace = TRUE); ix <- unlist(lapply(pick, function(p) which(bi == p))); ic(s4, ix) - ic(s3, ix) })
    out$ic_current_4 <- ic(s4); out$ic_current_3_no_residual <- ic(s3); out$ic_residual_alone <- ic(Z4[, "residual"])
    out$ic_4_minus_3 <- c(delta = out$ic_current_4 - out$ic_current_3_no_residual, ci_lo = q95(boots)[1], ci_hi = q95(boots)[2])
  }
  RESID[[paste0("w", w)]] <- out
}

# Recommendations for part B: change a window's weights only if the LOSO-selected
# weights beat the current ones with a 95% interval above zero.
REC_B <- lapply(MOMENTUM_WINDOWS, function(w) {
  r <- PART_B[[paste0("w", w)]][[PRIMARY]]
  if (r$loso_selected$vs_current["ci_lo"] > 0) list(change = TRUE, weights = r$best_weights,
                                                      text = sprintf("window %d: change the form / trend / Elo change weights to %s (the residual weight is a separate decision; it cannot be tested before 2026-27)", w, wlabel(r$best_weights)))
  else list(change = FALSE, weights = COMBINED_WEIGHTS, text = sprintf("window %d: keep 0.7/0.1/0.1/0.1", w))
})
names(REC_B) <- paste0("w", MOMENTUM_WINDOWS)

# ------------------------------------------------------------------------------
# 9. HOLDOUT 2026-27 - scored ONCE, here, after every choice above is fixed
# ------------------------------------------------------------------------------
say("HOLDOUT 2026-27: scoring the fixed choices once")
HOLD <- list(note = "Scored once, after the part A combination and the part B weights were fixed on 2018-19 to 2025-26. Rows need a team's 10th game for features and 5 or 10 later games for the target.")
Zh <- getZ("full"); hold_rows <- TG$season == HOLDOUT_SEASON
holdout_score <- function(tid, cols_feat, alpha, Ztr_fun) {
  trr <- hist_rows & !is.na(TG[[tid]]) & !is.na(TG$elo_c) & !is.na(TG$snet) & stats::complete.cases(Zh[, cols_feat, drop = FALSE])
  ter <- hold_rows & !is.na(TG[[tid]]) & !is.na(TG$elo_c) & !is.na(TG$snet) & stats::complete.cases(Zh[, cols_feat, drop = FALSE])
  X <- cbind(1, TG$elo_c, TG$snet, Zh[, cols_feat, drop = FALSE]); y <- TG[[tid]]
  out <- list(target = tid, rows = sum(ter), teams = length(unique(TG$team[ter])))
  if (sum(ter) < 20) { out$result <- "too few 2026-27 rows to score yet (needs at least 20)"; return(out) }
  pen <- diag(c(0, 0, 0, rep(1, length(cols_feat)))) * alpha * sum(trr)
  b <- solve_safe(crossprod(X[trr, ]) + pen, crossprod(X[trr, ], y[trr])); bb <- solve_safe(crossprod(X[trr, 1:3]), crossprod(X[trr, 1:3], y[trr]))
  pc <- X[ter, ] %*% b; pb <- X[ter, 1:3] %*% bb; yt <- y[ter]
  out$r2_gain <- (sum((yt - pb)^2) - sum((yt - pc)^2)) / sum((yt - mean(yt))^2); out$result <- "scored"
  out
}
HOLD$part_a <- list(choice = list(series = FINAL_A$series, measures = FINAL_A$measures, ridge_alpha = FINAL_A$alpha, reliable = COMBO_RELIABLE),
                    primary = holdout_score(PRIMARY, FINAL_A$features, FINAL_A$alpha),
                    next5 = holdout_score("net5_beyond_elo", FINAL_A$features, FINAL_A$alpha))
HOLD$part_b <- lapply(MOMENTUM_WINDOWS, function(w) {
  Bz <- BOARD[[as.character(w)]]; best <- PART_B[[paste0("w", w)]][[PRIMARY]]$best_weights
  lapply(setNames(c(PRIMARY, "net5_beyond_elo"), c(PRIMARY, "net5_beyond_elo")), function(tid) {
    ok <- !is.na(TG[[tid]]) & !is.na(TG$elo_c) & !is.na(TG$snet) & stats::complete.cases(Bz[, c("form", "trend", "elo")])
    trr <- hist_rows & ok; ter <- hold_rows & ok
    o <- list(target = tid, rows = sum(ter), best_weights = best)
    if (sum(ter) < 20) { o$result <- "too few 2026-27 rows to score yet (needs at least 20)"; return(o) }
    y <- TG[[tid]]; X3 <- cbind(1, TG$elo_c, TG$snet)
    sc <- function(wv) { X <- cbind(X3, Bz[, c("form", "trend", "elo")] %*% wv); b <- solve_safe(crossprod(X[trr, ]), crossprod(X[trr, ], y[trr])); X[ter, ] %*% b }
    pb <- X3[ter, ] %*% solve_safe(crossprod(X3[trr, ]), crossprod(X3[trr, ], y[trr])); yt <- y[ter]; sst <- sum((yt - mean(yt))^2)
    o$current_r2_gain <- (sum((yt - pb)^2) - sum((yt - sc(CURRENT_W3))^2)) / sst
    o$best_r2_gain <- (sum((yt - pb)^2) - sum((yt - sc(best))^2)) / sst; o$result <- "scored"
    o
  })
})
names(HOLD$part_b) <- paste0("w", MOMENTUM_WINDOWS)
str(HOLD, max.level = 4)

# ------------------------------------------------------------------------------
# 10. Save results (RDS, JSON for a future methodology page, report tables)
# ------------------------------------------------------------------------------
total_min <- elapsed()
RESULTS <- list(meta = list(run_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"), seed = STUDY_SEED, n_boot = N_BOOT, n_perm = N_PERM,
                            seasons = season_table, residual_log_coverage_2027 = log_cov27, runtime_min = total_min,
                            permutation_minutes = perm_minutes),
                feature_missing = feat_missing, single = SINGLE, single_sensitivity = SENS_SINGLE,
                families = list(features = feat_families, measure = split(names(MEASURES), measure_cl), series = split(names(SERIES), series_cl),
                                measure_mean_abs_r = RM, series_mean_abs_r = RS),
                kalman_parameters = lapply(KV, `[[`, "pars"),
                part_a = A_MAIN[setdiff(names(A_MAIN), c("P", "y", "blk"))], part_a_sensitivity = A_SENS[setdiff(names(A_SENS), c("P", "y", "blk"))],
                permutation = list(gains = PERM, p95 = perm_p95, minutes = perm_minutes),
                final_choice = FINAL_A[setdiff(names(FINAL_A), "best")], reliability = crit, combination_verdict = combo_verdict,
                part_b = lapply(PART_B, function(r) lapply(r, function(x) if (is.list(x) && !is.null(x$target)) strip(x) else x)),
                part_b_sensitivity = lapply(PART_B_SENS, strip), residual_check = RESID, recommendation_b = REC_B, holdout = HOLD)
saveRDS(RESULTS, file.path(CACHE_DIR, "momentum_measures_study_results.rds"))

measure_text <- c(
  roc10 = "Elo: (Elo after game k - Elo 10 games earlier) / 10. Box series: mean of the last 10 games minus the mean of the team's games before them (at least 5 earlier games).",
  macd = "Exponentially weighted mean of the series with span 5 minus the same with span 15, updated game by game from the season's first game.",
  velocity = "Slope of a least-squares line through the trailing 10 games of the series.",
  acceleration = "Velocity after game k minus velocity after game k-5.",
  ewma_change = "Exponentially weighted mean (span 5) of the per-game change (Elo) or surprise (box series: game value minus the team's own mean of its earlier games).",
  zscore = "ROC-10 divided by the standard deviation of the team's changes or surprises in games 1..k (expanding window).",
  rsi = "Over the last 10 changes or surprises: 100 x average gain / (average gain + average loss); recent gains vs losses on a 0-100 scale.",
  growth = "Sum of the last 10 changes or surprises minus the sum of the 10 before them (a difference, because the ratio is unstable near zero).",
  kalman = "Filtered slope of a local linear trend model (level + slope + noise) run forward through games 1..k; its three noise variances are fitted by maximum likelihood on the training seasons only.",
  streak = "Signed length of the current run: wins/losses for Elo, positive/negative surprises for box series.",
  impulse = "m[k] = 0.85 x m[k-1] + change or surprise in game k, from the season's first game.")
measure_field <- c(roc10 = "finance (rate of change)", macd = "finance (moving-average convergence/divergence)", velocity = "physics (kinematics)",
                   acceleration = "physics (kinematics)", ewma_change = "signal processing", zscore = "sports analytics (hot-hand style)",
                   rsi = "finance (relative strength index)", growth = "epidemiology (growth of an outbreak)", kalman = "econometrics (state-space models)",
                   streak = "basketball hot-hand literature", impulse = "control theory (damped impulse response)")
series_text <- c(elo = "Shared Elo rating after each game (R/elo.R: K 20, home court 100, margin-of-victory multiplier, 0.75 season carry-over).",
                 margin = "Point margin minus the opponent's season-to-date average margin allowed (earlier games only).",
                 ortg = "Points per 100 possessions minus the opponent's season-to-date average allowed.",
                 drtg = "Points allowed per 100 possessions minus the opponent's season-to-date average scored.",
                 net = "Net rating (ORtg - DRtg) minus the opponent's season-to-date average allowed.",
                 pace = "Possessions (FGA - ORB + TOV + 0.44 x FTA, both teams averaged) minus the opponent's season-to-date average.",
                 efg = "Effective FG% minus the opponent's season-to-date average allowed.", tov = "Turnover % minus the opponent's season-to-date average forced.",
                 orb = "Offensive rebound % minus the opponent's season-to-date average allowed.", ftr = "FTA/FGA minus the opponent's season-to-date average allowed.",
                 efg_def = "Effective FG% allowed minus the opponent's season-to-date average.", tov_def = "Turnover % forced minus the opponent's season-to-date average committed.",
                 orb_def = "Offensive rebound % allowed minus the opponent's season-to-date average.", ftr_def = "FTA/FGA allowed minus the opponent's season-to-date average.")
cvec <- function(x) as.list(x)
part_b_json <- lapply(MOMENTUM_WINDOWS, function(w) {
  r <- PART_B[[paste0("w", w)]]; m <- r[[PRIMARY]]
  list(window = w, target = PRIMARY, rows = m$rows, current_weights = cvec(m$current_weights), current_r2_gain = m$current_r2_gain,
       current_incremental_ic = m$current_ic, best_weights = cvec(m$best_weights), best_r2_gain = m$best_r2_gain, best_incremental_ic = m$best_ic,
       best_vs_current = cvec(m$best_vs_current), flatness = cvec(m$flatness),
       loso_selected = list(weights_by_fold = lapply(m$loso_selected$chosen, cvec), r2_gain = m$loso_selected$r2_gain, vs_current = cvec(m$loso_selected$vs_current)),
       nonnegative_regression = list(weights_by_fold = lapply(m$nonnegative_regression$weights_by_fold, cvec), r2_gain = m$nonnegative_regression$r2_gain,
                                     vs_current = cvec(m$nonnegative_regression$vs_current)),
       component_alone_r2_gain = cvec(m$component_alone_r2_gain),
       next5 = list(current_r2_gain = r$net5_beyond_elo$current_r2_gain, best_weights = cvec(r$net5_beyond_elo$best_weights),
                    best_r2_gain = r$net5_beyond_elo$best_r2_gain, best_vs_current = cvec(r$net5_beyond_elo$best_vs_current)),
       residual_small_sample_check = RESID[[paste0("w", w)]],
       trend_swap = r$trend_swap,
       sensitivity_without_2019_20_2020_21 = list(best_weights = cvec(PART_B_SENS[[paste0("w", w)]]$best_weights),
                                                  current_r2_gain = PART_B_SENS[[paste0("w", w)]]$current_r2_gain,
                                                  best_vs_current = cvec(PART_B_SENS[[paste0("w", w)]]$best_vs_current),
                                                  loso_selected_vs_current = cvec(PART_B_SENS[[paste0("w", w)]]$loso_selected$vs_current)),
       recommendation = REC_B[[paste0("w", w)]]$text)
})
fold_json <- function(A) lapply(A$folds, function(f) f)
json <- list(
  study = list(title = "NBA momentum measures study: do momentum measures on team stats predict the next 5-10 games beyond team strength?",
               run_date = format(Sys.Date()), seasons = lapply(seq_len(nrow(season_table)), function(i) as.list(season_table[i, ])),
               holdout = "2026-27 regular season to date; scored once after every choice was fixed",
               protocol = c("Leave-one-season-out over 2018-19 to 2025-26 with pooled out-of-fold predictions",
                            sprintf("Paired bootstrap, %d resamples of whole team-seasons (next-10 targets overlap from game to game)", N_BOOT),
                            "Baseline: Elo after the game plus season-to-date net rating; candidates scored on what they add",
                            "Every feature uses only the team's earlier games; cross-team z-scores per date use each team's latest state on or before that date",
                            "No imputation; missing values are counted per feature",
                            sprintf("Benjamini-Hochberg false discovery rate across the 154 features per target (q < %.2f)", FDR_Q),
                            "Nested combination search: top 6 series x top 6 measures ranked on training seasons only, 400 combinations x 3 ridge penalties chosen by inner leave-one-season-out",
                            sprintf("Permutation baseline: %d reruns of the whole nested search with the target shuffled among teams within each date", N_PERM),
                            "Sensitivity run without 2019-20 and 2020-21"),
               seeds = list(study = STUDY_SEED, permutation = STUDY_SEED + 999L, bootstrap = "STUDY_SEED + number of seasons in the run"),
               runtime_minutes = total_min, permutation_minutes = perm_minutes),
  targets = lapply(seq_len(nrow(TARGETS)), function(i) list(id = TARGETS$id[i], definition = TARGETS$definition[i], primary = TARGETS$primary[i])),
  measures = lapply(names(MEASURES), function(m) list(id = m, name = MEASURES[[m]], field_of_origin = measure_field[[m]],
                                                      forward_only_definition = paste(measure_text[[m]], "Uses only the team's games up to and including the latest one; no value before the 10th game."))),
  series = lapply(names(SERIES), function(s) list(id = s, name = SERIES[[s]], definition = series_text[[s]])),
  single_feature_results = lapply(seq_len(nrow(SINGLE)), function(i) {
    r <- SINGLE[i, ]
    list(feature = r$feature, series = r$series, measure = r$measure, target = r$target, incremental_ic = r$incremental_ic, ic_metric = r$ic_metric,
         r2_gain = r$r2_gain, gain_metric = r$gain_metric, ci_95 = c(r$ci_lo, r$ci_hi), fdr_q_value = r$q_value, p_value = r$p_value,
         n = r$n, missing_count = r$missing, verdict = r$verdict, reason = r$reason)
  }),
  single_feature_sensitivity_primary = lapply(seq_len(nrow(SENS_SINGLE)), function(i) { r <- SENS_SINGLE[i, ]
    list(feature = r$feature, r2_gain = r$r2_gain, ci_95 = c(r$ci_lo, r$ci_hi), fdr_q_value = r$q_value, n = r$n, verdict = r$verdict) }),
  families = list(feature_clusters_abs_r_0_7 = unname(lapply(feat_families, identity)),
                  measure_families = unname(split(names(MEASURES), measure_cl)), series_families = unname(split(names(SERIES), series_cl)),
                  measure_mean_abs_r = lapply(as.data.frame(round(RM, 4)), identity), series_mean_abs_r = lapply(as.data.frame(round(RS, 4)), identity)),
  combination_search = list(target = PRIMARY, rows = A_MAIN$rows, folds = fold_json(A_MAIN),
                            pooled_r2_gain = A_MAIN$pooled_r2_gain, pooled_ci_95 = A_MAIN$pooled_ci, pooled_incremental_ic = A_MAIN$pooled_ic,
                            comparisons = A_MAIN$comparisons, combination_vs_board_score = list(r2_gain = A_MAIN$combination_vs_board_r2_gain, ci_95 = A_MAIN$combination_vs_board_ci),
                            greedy_selected_by_fold = A_MAIN$greedy_selected, elastic_net_nonzero_by_fold = A_MAIN$elastic_net_nonzero,
                            selection_stability = A_MAIN$stability,
                            permutation = list(runs = N_PERM, p95 = perm_p95, mean = mean(PERM), max = max(PERM), share_at_or_above_real = mean(PERM >= A_MAIN$pooled_r2_gain), minutes = perm_minutes),
                            final_choice = list(series = FINAL_A$series, measures = FINAL_A$measures, ridge_alpha = FINAL_A$alpha, inner_r2_gain = FINAL_A$inner_r2_gain,
                                                tied_with_best_within_ci = FINAL_A$tied_with_best, of_combinations = FINAL_A$of_combinations),
                            reliability_checks = as.list(crit), final_verdict = combo_verdict,
                            sensitivity_without_2019_20_2020_21 = list(rows = A_SENS$rows, folds = fold_json(A_SENS), pooled_r2_gain = A_SENS$pooled_r2_gain,
                                                                       pooled_ci_95 = A_SENS$pooled_ci, comparisons = A_SENS$comparisons, selection_stability = A_SENS$stability)),
  blend_weights = part_b_json,
  holdout = HOLD,
  limits = c("Effects are small: regression to the mean dominates NBA results over 5-10 games.",
             "The combination search uses rows where all 154 features exist (from about a team's 21st game) so every candidate is scored on the same rows; single features use all rows where they exist.",
             "Kalman variances are fitted on the outer training seasons and reused in the inner loop.",
             "Bootstrap intervals for the incremental IC hold the ranks at their full-sample values.",
             "The next-game target is scored by log loss; its ROC-AUC change is a point estimate without an interval.",
             sprintf("The board residual exists only for 2026-27 (%d of %d games with a resolved logged pregame margin); its check is in-sample and small.", log_cov27$panel_games_with_margin, log_cov27$panel_games),
             "2026-27 is early: teams have played too few games for most holdout rows (features need 10 games, targets 5 or 10 later games).",
             "Possession estimates and four-factor rates are noisy over 5-10 games.",
             "The Elo-expectation residual proxy for part B was not run.")
)
dir.create(file.path(STUDY_ROOT, "docs", "research"), recursive = TRUE, showWarnings = FALSE)
# Keep names on named vectors and matrices (jsonlite would otherwise drop them).
namify <- function(x) {
  if (is.data.frame(x)) return(lapply(seq_len(nrow(x)), function(i) namify(as.list(x[i, , drop = FALSE]))))
  if (is.matrix(x) && !is.null(rownames(x))) return(lapply(setNames(seq_len(nrow(x)), rownames(x)), function(i) namify(x[i, ])))
  if (is.list(x)) return(lapply(x, namify))
  if (is.atomic(x) && !is.null(names(x)) && length(x) > 0) return(as.list(x))
  x
}
json <- namify(json)
jsonlite::write_json(json, file.path(STUDY_ROOT, "docs", "research", "momentum_measures_study_results.json"),
                     auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null", null = "null")

# Report tables (markdown) - every number pasted into the report comes from here.
f4 <- function(x) ifelse(is.na(x), "NA", sprintf("%.4f", x)); f5 <- function(x) ifelse(is.na(x), "NA", sprintf("%+.5f", x))
md <- c("## Seasons", "", "| Season | Role | Games | Team-games | First | Last |", "|---|---|---|---|---|---|",
        sprintf("| %s | %s | %d | %d | %s | %s |", season_table$season, season_table$role, season_table$games, season_table$team_games, season_table$first, season_table$last), "",
        "## Verdicts by target", "", "| Target | kept | inconclusive | discarded |", "|---|---|---|---|",
        vapply(TARGETS$id, function(t) { x <- SINGLE[SINGLE$target == t, ]; sprintf("| %s | %d | %d | %d |", t, sum(x$verdict == "kept"), sum(x$verdict == "inconclusive"), sum(x$verdict == "discarded")) }, ""), "")
for (t in TARGETS$id) {
  x <- SINGLE[SINGLE$target == t, ]; x <- head(x[order(-x$r2_gain), ], 10)
  md <- c(md, sprintf("## Top 10 single features: %s", t), "", "| Feature | Gain | 95% CI | IC / AUC change | q | n | Missing | Verdict |", "|---|---|---|---|---|---|---|---|",
          sprintf("| %s | %s | [%s, %s] | %s | %s | %d | %d | %s |", x$feature, f5(x$r2_gain), f5(x$ci_lo), f5(x$ci_hi), f5(x$incremental_ic), f4(x$q_value), x$n, x$missing, x$verdict), "")
}
xs <- head(SENS_SINGLE[order(-SENS_SINGLE$r2_gain), ], 10)
md <- c(md, "## Sensitivity (no 2019-20 / 2020-21): top 10 single features, primary target", "", "| Feature | Gain | 95% CI | q | Verdict |", "|---|---|---|---|---|",
        sprintf("| %s | %s | [%s, %s] | %s | %s |", xs$feature, f5(xs$r2_gain), f5(xs$ci_lo), f5(xs$ci_hi), f4(xs$q_value), xs$verdict), "",
        "## Measure families (mean |r| across series >= 0.5)", "", vapply(split(names(MEASURES), measure_cl), function(v) paste("-", paste(v, collapse = ", ")), ""), "",
        "## Series families (mean |r| across measures >= 0.5)", "", vapply(split(names(SERIES), series_cl), function(v) paste("-", paste(v, collapse = ", ")), ""), "",
        "## Combination search by outer fold (primary target)", "", "| Held-out season | Series | Measures | Ridge alpha | Inner gain | Held-out gain | Rows |", "|---|---|---|---|---|---|---|",
        vapply(A_MAIN$folds, function(f) sprintf("| %s | %s | %s | %g | %s | %s | %d |", f$held_out, paste(f$series, collapse = ", "), paste(f$measures, collapse = ", "), f$ridge_alpha, f5(f$inner_r2_gain), f5(f$held_out_r2_gain), f$held_out_rows), ""), "",
        "## Combination search summary", "", "| Model | Pooled OOF R^2 gain | 95% CI |", "|---|---|---|",
        sprintf("| Nested 3x3 combination | %s | [%s, %s] |", f5(A_MAIN$pooled_r2_gain), f5(A_MAIN$pooled_ci[1]), f5(A_MAIN$pooled_ci[2])),
        vapply(names(A_MAIN$comparisons), function(n) { c0 <- A_MAIN$comparisons[[n]]; sprintf("| %s | %s | [%s, %s] |", n, f5(c0$r2_gain), f5(c0$ci[1]), f5(c0$ci[2])) }, ""),
        sprintf("| Sensitivity: nested 3x3 combination (6 seasons) | %s | [%s, %s] |", f5(A_SENS$pooled_r2_gain), f5(A_SENS$pooled_ci[1]), f5(A_SENS$pooled_ci[2])),
        vapply(names(A_SENS$comparisons), function(n) { c0 <- A_SENS$comparisons[[n]]; sprintf("| Sensitivity: %s | %s | [%s, %s] |", n, f5(c0$r2_gain), f5(c0$ci[1]), f5(c0$ci[2])) }, ""), "",
        sprintf("Permutation baseline: %d runs, 95th percentile %s, mean %s, max %s; share of runs at or above the real gain %s; runtime %.1f min.",
                N_PERM, f5(perm_p95), f5(mean(PERM)), f5(max(PERM)), f4(mean(PERM >= A_MAIN$pooled_r2_gain)), perm_minutes),
        sprintf("Stability: %d distinct combinations in %d folds; series counts %s; measure counts %s; seasons with positive held-out gain %d of %d.",
                A_MAIN$stability$distinct_combinations, A_MAIN$stability$of_seasons,
                paste(sprintf("%s %d", names(A_MAIN$stability$series_counts), unlist(A_MAIN$stability$series_counts)), collapse = ", "),
                paste(sprintf("%s %d", names(A_MAIN$stability$measure_counts), unlist(A_MAIN$stability$measure_counts)), collapse = ", "),
                A_MAIN$stability$seasons_with_positive_gain, A_MAIN$stability$of_seasons),
        sprintf("Final choice on all 8 seasons: %s x %s (ridge alpha %g); %d of %d other combinations tie with it within the bootstrap interval.",
                paste(FINAL_A$series, collapse = ", "), paste(FINAL_A$measures, collapse = ", "), FINAL_A$alpha, FINAL_A$tied_with_best, FINAL_A$of_combinations - 1L),
        sprintf("Reliability checks: %s. Verdict: %s.", paste(sprintf("%s = %s", names(crit), crit), collapse = "; "), combo_verdict), "",
        "## Part B: blend weights (primary target, LOSO over 8 seasons)", "",
        "| Window | Rows | Current (0.78/0.11/0.11) gain | Best weights | Best gain | Best - current [95% CI] | Grid points within CI of best | LOSO-selected - current [95% CI] | Non-negative regression - current [95% CI] |",
        "|---|---|---|---|---|---|---|---|---|")
for (w in MOMENTUM_WINDOWS) { m <- PART_B[[paste0("w", w)]][[PRIMARY]]
  md <- c(md, sprintf("| %d | %d | %s | %s | %s | %s [%s, %s] | %d of %d | %s [%s, %s] | %s [%s, %s] |", w, m$rows, f5(m$current_r2_gain), wlabel(m$best_weights), f5(m$best_r2_gain),
                      f5(m$best_vs_current[1]), f5(m$best_vs_current[2]), f5(m$best_vs_current[3]), m$flatness[1], m$flatness[2],
                      f5(m$loso_selected$vs_current[1]), f5(m$loso_selected$vs_current[2]), f5(m$loso_selected$vs_current[3]),
                      f5(m$nonnegative_regression$vs_current[1]), f5(m$nonnegative_regression$vs_current[2]), f5(m$nonnegative_regression$vs_current[3]))) }
md <- c(md, "", "| Window | Form alone | Trend alone | Elo change alone | Next-5: current gain | Next-5: best weights | Next-5: best - current [95% CI] |", "|---|---|---|---|---|---|---|")
for (w in MOMENTUM_WINDOWS) { m <- PART_B[[paste0("w", w)]][[PRIMARY]]; n5 <- PART_B[[paste0("w", w)]]$net5_beyond_elo
  md <- c(md, sprintf("| %d | %s | %s | %s | %s | %s | %s [%s, %s] |", w, f5(m$component_alone_r2_gain["form"]), f5(m$component_alone_r2_gain["trend"]), f5(m$component_alone_r2_gain["elo"]),
                      f5(n5$current_r2_gain), wlabel(n5$best_weights), f5(n5$best_vs_current[1]), f5(n5$best_vs_current[2]), f5(n5$best_vs_current[3]))) }
md <- c(md, "", sprintf("Trend swap / join feature (best single part-A feature on the primary target): %s", best_single), "",
        "| Window | Rows | Best 3-component gain (same rows) | Swap: best weights | Swap - best 3 [95% CI] | Join: best weights | Join - best 3 [95% CI] |", "|---|---|---|---|---|---|---|")
for (w in MOMENTUM_WINDOWS) { ts <- PART_B[[paste0("w", w)]]$trend_swap
  md <- c(md, sprintf("| %d | %d | %s | %s | %s [%s, %s] | %s | %s [%s, %s] |", w, ts$rows, f5(ts$best_3_component_on_same_rows$r2_gain), wlabel(ts$swap$weights),
                      f5(ts$swap$vs_best_3_component[1]), f5(ts$swap$vs_best_3_component[2]), f5(ts$swap$vs_best_3_component[3]), wlabel(ts$join$weights),
                      f5(ts$join$vs_best_3_component[1]), f5(ts$join$vs_best_3_component[2]), f5(ts$join$vs_best_3_component[3]))) }
md <- c(md, "", "| Window | Sensitivity (6 seasons): current gain | best weights | best - current [95% CI] | LOSO-selected - current [95% CI] |", "|---|---|---|---|---|")
for (w in MOMENTUM_WINDOWS) { m <- PART_B_SENS[[paste0("w", w)]]
  md <- c(md, sprintf("| %d | %s | %s | %s [%s, %s] | %s [%s, %s] |", w, f5(m$current_r2_gain), wlabel(m$best_weights), f5(m$best_vs_current[1]), f5(m$best_vs_current[2]), f5(m$best_vs_current[3]),
                      f5(m$loso_selected$vs_current[1]), f5(m$loso_selected$vs_current[2]), f5(m$loso_selected$vs_current[3]))) }
md <- c(md, "", "| Window | Residual check rows (2026-27) | Teams | IC current 4-part | IC 3-part (no residual) | IC residual alone | 4 - 3 [95% CI] |", "|---|---|---|---|---|---|---|")
for (w in MOMENTUM_WINDOWS) { r <- RESID[[paste0("w", w)]]
  md <- c(md, if (is.null(r$ic_current_4)) sprintf("| %d | %d | %d | too few rows | | | |", w, r$rows, r$teams) else
    sprintf("| %d | %d | %d | %s | %s | %s | %s [%s, %s] |", w, r$rows, r$teams, f4(r$ic_current_4), f4(r$ic_current_3_no_residual), f4(r$ic_residual_alone),
            f5(r$ic_4_minus_3[1]), f5(r$ic_4_minus_3[2]), f5(r$ic_4_minus_3[3]))) }
md <- c(md, "", "## Holdout 2026-27 (scored once)", "",
        sprintf("- Part A choice %s x %s: primary target rows %d (%s%s); next-5 rows %d (%s%s).", paste(FINAL_A$series, collapse = ", "), paste(FINAL_A$measures, collapse = ", "),
                HOLD$part_a$primary$rows, HOLD$part_a$primary$result, if (!is.null(HOLD$part_a$primary$r2_gain)) paste(", R^2 gain", f5(HOLD$part_a$primary$r2_gain)) else "",
                HOLD$part_a$next5$rows, HOLD$part_a$next5$result, if (!is.null(HOLD$part_a$next5$r2_gain)) paste(", R^2 gain", f5(HOLD$part_a$next5$r2_gain)) else ""))
for (w in MOMENTUM_WINDOWS) for (tid in c(PRIMARY, "net5_beyond_elo")) { h <- HOLD$part_b[[paste0("w", w)]][[tid]]
  md <- c(md, sprintf("- Part B window %d, %s: rows %d, %s%s", w, tid, h$rows, h$result,
                      if (!is.null(h$current_r2_gain)) sprintf(" (current gain %s, best-weights gain %s)", f5(h$current_r2_gain), f5(h$best_r2_gain)) else "")) }
md <- c(md, "", "## Recommendations (rule-based)", "", paste("- A:", combo_verdict), vapply(REC_B, function(r) paste("- B:", r$text), ""), "",
        sprintf("Runtime: %.1f minutes in total (permutations %.1f minutes).", total_min, perm_minutes))
writeLines(md, file.path(CACHE_DIR, "momentum_measures_study_tables.md"))

cat("\n================ SUMMARY ================\n")
cat(sprintf("Features: %d; single-feature rows: %d (%d targets)\n", NF, nrow(SINGLE), nrow(TARGETS)))
cat(sprintf("Combination search: pooled OOF R^2 gain %.5f [%.5f, %.5f]; permutation p95 %.5f (%d runs, %.1f min)\n",
            A_MAIN$pooled_r2_gain, A_MAIN$pooled_ci[1], A_MAIN$pooled_ci[2], perm_p95, N_PERM, perm_minutes))
cat(sprintf("Verdict A: %s\n", combo_verdict))
for (r in REC_B) cat("Verdict B:", r$text, "\n")
cat(sprintf("Results: cache/momentum_measures_study_results.rds, docs/research/momentum_measures_study_results.json, cache/momentum_measures_study_tables.md\n"))
cat(sprintf("Total runtime: %.1f minutes\n", total_min))
