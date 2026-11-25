# ==============================================================================
# tools/rolling_window_study.R - which trailing window of opponent-adjusted EPA
# per play best predicts an NFL team's next game, and how should windows handle
# the break between seasons? Research only (issue #227); NOT part of the
# pipeline and not sourced by it. Also produces the settings the NFL Momentum
# Board (#226) needs: combined-score weights, a flag detection check and an
# availability data check.
#
# Arms (issue #227):
#   A. Replication of the NBA window test (rolling-window-expt chunk of the NBA
#      project's original Rmd): trailing k-game means of team stats plus EPA,
#      home minus away, random forest (ranger, 300 trees) for home win, trained
#      on seasons before 2025 and tested on 2025, k = 1..17; the window with the
#      highest ROC-AUC is that arm's answer (accuracy and kappa also reported).
#   B. Stronger version: leave-one-season-out (LOSO) over 2012-2025, targets
#      next-game point margin and next-game win, each raw and beyond Elo
#      (production Elo, tools/elo_model.R, pregame ratings only), feature =
#      opponent-adjusted EPA per play (offense minus defense allowed) over the
#      last k games, k = 1..17 plus season-to-date; opponent-adjusted point
#      margin as a comparison. Team-season block bootstrap 95% intervals;
#      selection rule = the shortest window whose score lies inside the 95%
#      interval of the best window's score.
#   Every window in both arms is computed under the three OFFSEASON_METHOD values
#   in config.R (reset, mean_regress, decay; definitions in section 0).
#   C. Combined-score weights for the board (form, trend, residual vs Elo, Elo
#      change), fitted on training seasons only and scored on held-out seasons.
#   D. Flag detection check (SIMULATED detection rates - a methods check, not data).
#   E. Availability data check (injury reports and snap counts coverage).
#
# NO LOOK-AHEAD: every feature for a game uses only earlier games (the window
# lags start at the previous game; the opponent adjustment uses the opponent's
# earlier games only); fitted parameters (regression and logistic coefficients,
# forest, weights) come from training seasons only. NO IMPUTATION: missing values
# stay missing and are counted. 2026 is not scored.
#
# Data (all cached in this checkout's cache/, downloaded with nflreadr if missing):
#   cache/rws_pbp_<season>.rds (2010-2025, selected columns), cache/rws_schedules.rds
#   (2002-2025; Elo runs from 2002 like production), cache/rws_injuries_<s>.rds and
#   cache/rws_snaps_<s>.rds (2012-2025), plus copies of the pipeline's
#   cache/injury_data_cache.rds and cache/snap_counts_cache.rds if present.
# Output: cache/rolling_window_study_results.rds,
#         docs/research/rolling_window_study_results.json,
#         cache/rolling_window_study_tables.md (tables for the report).
# Run:  Rscript tools/rolling_window_study.R
#       RWS_N_BOOT / RWS_N_SIM override the run sizes for a smoke test only
#       (the published run uses 2000 / 10000).
# ==============================================================================

STUDY_ROOT <- local({
  env <- Sys.getenv("NFL_PROJECT_DIR", "")
  if (nzchar(env)) return(normalizePath(env, winslash = "/"))
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  start <- if (length(f)) dirname(normalizePath(f[1], winslash = "/", mustWork = FALSE)) else getwd()
  root <- start
  while (!file.exists(file.path(root, "config.R"))) {
    parent <- dirname(root)
    if (identical(parent, root)) stop("rolling_window_study.R: cannot find config.R at or above ", start)
    root <- parent
  }
  normalizePath(root, winslash = "/")
})
setwd(STUDY_ROOT)

suppressPackageStartupMessages({
  library(dplyr); library(jsonlite)
  library(recipes); library(parsnip); library(workflows); library(yardstick)
})
source(file.path(STUDY_ROOT, "config.R"))
source(file.path(STUDY_ROOT, "tools", "elo_model.R"))   # run_elo_walkforward() and its constants

t_start <- Sys.time()
elapsed <- function() as.numeric(difftime(Sys.time(), t_start, units = "mins"))
say <- function(...) cat(sprintf("[%5.1f min] ", elapsed()), sprintf(...), "\n", sep = "")

# ------------------------------------------------------------------------------
# 0. Settings
# ------------------------------------------------------------------------------
STUDY_SEED <- 20261125L
N_BOOT <- as.integer(Sys.getenv("RWS_N_BOOT", "2000"))
N_SIM <- as.integer(Sys.getenv("RWS_N_SIM", "10000"))
HIST_SEASONS <- 2012:2025          # LOSO seasons (stronger arm, weights, flags)
DATA_FIRST <- 2010L                # 2010-2011 only seed windows carried into 2012 (and the replication's training data)
DATA_LAST <- 2025L                 # 2026 is not scored
REP_TEST_SEASON <- 2025L           # replication: last complete season
ELO_FIRST_SEASON <- MODERN_ERA_START_SEASON
KS <- 1:17
KMAX <- max(KS)
WINDOWS <- c(as.character(KS), "std")   # "std" = season-to-date
METHODS <- c("reset", "mean_regress", "decay")
REP_VARIANTS <- c("original", METHODS)  # "original" = the NBA chunk's own rule (team-only windows across seasons)
# Season-boundary methods (OFFSEASON_METHOD in config.R names them; no code in this
# repo defines mean_regress or decay, so the definitions are this study's):
#   reset        - windows start fresh each season; a team with fewer than k games
#                  that season has no value.
#   mean_regress - windows run across the boundary; each carried game's value is
#                  pulled toward the league average of its own season by
#                  REGRESS_KEEP per boundary crossed (50%: value -> avg + 0.5 x (value - avg)).
#   decay        - windows run across the boundary; each carried game keeps its
#                  value but its weight in the window mean is DECAY_BASE^(seasons back)
#                  (0.5 for last season, 0.25 two seasons back); current-season games weigh 1.
# Season-to-date: the mean of the team's earlier games this season. Under
# mean_regress and decay, a team's first game (no games yet) uses its whole previous
# season with the method's treatment (regressed 50% / equal weights); under reset it has no value.
REGRESS_KEEP <- 0.5
DECAY_BASE <- 0.5
MIN_ROWS <- 200L                   # a window is scored only with at least this many rows
MIN_Z_TEAMS <- 10L                 # per-week standardisation needs this many teams
BOARD_WINDOWS <- c("3", "6", "9", "std")
ONE_SCORE <- 8L; BLOWOUT <- 17L; PYTH_EXP <- 2.37
KEY_PLAYERS <- 22L
DETECT_POWER <- 0.8

# ------------------------------------------------------------------------------
# 1. Data
# ------------------------------------------------------------------------------
PBP_COLS <- c("game_id","season","week","season_type","home_team","away_team","posteam","defteam","play_type","pass","rush",
              "qb_dropback","epa","success","interception","fumble","fumble_lost","fumbled_1_team","fumble_recovery_1_team","yards_gained",
              "first_down","first_down_rush","first_down_pass","first_down_penalty","third_down_converted","third_down_failed","sack","penalty",
              "penalty_team","penalty_yards","rushing_yards","passing_yards","field_goal_attempt","field_goal_result","play")
pbp_path <- function(s) file.path(CACHE_DIR, sprintf("rws_pbp_%d.rds", s))
SCHED_PATH <- file.path(CACHE_DIR, "rws_schedules.rds")
for (s in DATA_FIRST:DATA_LAST) if (!file.exists(pbp_path(s))) {
  say("Downloading play-by-play %d with nflreadr", s)
  p <- as.data.frame(nflreadr::load_pbp(s)); saveRDS(p[, intersect(PBP_COLS, names(p))], pbp_path(s))
}
if (!file.exists(SCHED_PATH)) saveRDS(as.data.frame(nflreadr::load_schedules(ELO_FIRST_SEASON:DATA_LAST)), SCHED_PATH)
FRANCHISE <- c(OAK = "LV", SD = "LAC", STL = "LA")
canon <- function(x) ifelse(x %in% names(FRANCHISE), FRANCHISE[x], x)

SCHED <- as.data.frame(readRDS(SCHED_PATH), stringsAsFactors = FALSE)
SCHED$home_team <- canon(SCHED$home_team); SCHED$away_team <- canon(SCHED$away_team)
SCHED$gameday <- as.Date(SCHED$gameday)
COMPLETED <- SCHED[!is.na(SCHED$home_score) & !is.na(SCHED$away_score) &
                     SCHED$season >= ELO_FIRST_SEASON & SCHED$season <= DATA_LAST, , drop = FALSE]

# Production Elo walk-forward (same call and post-game reconstruction as
# tools/momentum_measures_study.R): every completed game from 2002, PRE-game ratings only.
say("Running the production Elo walk-forward on %d completed games", nrow(COMPLETED))
ELO <- run_elo_walkforward(COMPLETED, data.frame(game_id = character(0), team = character(0), fatigue_drag_pts = numeric(0)), ELO_K_FACTOR)
local({
  sc <- COMPLETED[match(ELO$game_id, COMPLETED$game_id), ]
  ed <- (ELO$home_elo_pre + ELO_HCA_POINTS) - ELO$away_elo_pre
  y <- ifelse(sc$home_score == sc$away_score, 0.5, as.numeric(sc$home_score > sc$away_score))
  wd <- ifelse(sc$home_score > sc$away_score, ed, -ed)
  mult <- log(pmax(abs(sc$home_score - sc$away_score), 1) + 1) * (ELO_MOV_C / (0.001 * wd + ELO_MOV_C))
  shift <- ELO_K_FACTOR * mult * (y - ELO$elo_prob_pure)
  ELO$home_elo_post <<- ELO$home_elo_pre + shift; ELO$away_elo_post <<- ELO$away_elo_pre - shift
})

# Per team-game play-by-play aggregates (regular season). EPA/play follows
# epa_metrics_engine.R and the momentum study (every play with posteam, defteam and
# EPA). Box-style stats for the replication arm: yards per play (pass and run
# plays), rushing yards, net passing yards (yards gained on pass plays, sacks
# included), first downs, third-down conversion rate, sacks taken, giveaways
# (interceptions plus fumbles lost, charged to the fumbling team), penalty yards.
team_game_stats <- function(s) {
  p <- as.data.frame(readRDS(pbp_path(s)), stringsAsFactors = FALSE)
  p <- p[p$season_type == "REG", , drop = FALSE]
  for (cc in c("posteam", "defteam", "home_team", "away_team", "fumbled_1_team", "fumble_recovery_1_team", "penalty_team"))
    if (cc %in% names(p)) p[[cc]] <- canon(p[[cc]])
  num <- function(x) ifelse(is.na(x), 0, as.numeric(x))
  key_of <- function(g, t) paste(g, t)
  sumby <- function(v, k) tapply(v, k, sum)
  pos_ok <- !is.na(p$posteam) & !is.na(p$defteam)
  kpos <- key_of(p$game_id, p$posteam)
  e <- pos_ok & !is.na(p$epa)
  off_epa <- tapply(p$epa[e], kpos[e], mean)
  sp <- pos_ok & p$play_type %in% c("pass", "run") & !is.na(p$yards_gained)
  ypp <- tapply(p$yards_gained[sp], kpos[sp], mean)
  rush_yds <- sumby(num(p$yards_gained) * (p$rush %in% 1 & sp), kpos)
  pass_yds <- sumby(num(p$yards_gained) * (p$pass %in% 1 & sp), kpos)
  fd <- if ("first_down" %in% names(p)) num(p$first_down) else num(p$first_down_rush) + num(p$first_down_pass) + num(p$first_down_penalty)
  first_downs <- sumby(fd * pos_ok, kpos)
  t3c <- sumby(num(p$third_down_converted) * pos_ok, kpos); t3f <- sumby(num(p$third_down_failed) * pos_ok, kpos)
  sacks <- sumby(num(p$sack) * pos_ok, kpos)
  ints <- sumby(num(p$interception) * pos_ok, kpos)
  fum_team <- ifelse(is.na(p$fumbled_1_team), p$posteam, p$fumbled_1_team)
  fl <- p$fumble_lost %in% 1 & !is.na(fum_team)
  fum_lost <- tapply(rep(1, sum(fl)), key_of(p$game_id[fl], fum_team[fl]), sum)
  pen <- p$penalty %in% 1 & !is.na(p$penalty_team)
  pen_yds <- tapply(num(p$penalty_yards[pen]), key_of(p$game_id[pen], p$penalty_team[pen]), sum)
  # fumbles (for the recovery-rate flag): fumbles by the team, and recoveries by the team of any fumble in its games
  fu <- p$fumble %in% 1 & !is.na(p$fumbled_1_team)
  fumbles <- tapply(rep(1, sum(fu)), key_of(p$game_id[fu], p$fumbled_1_team[fu]), sum)
  fr <- fu & !is.na(p$fumble_recovery_1_team)
  recov <- tapply(rep(1, sum(fr)), key_of(p$game_id[fr], p$fumble_recovery_1_team[fr]), sum)
  fga <- pos_ok & p$field_goal_attempt %in% 1
  fg_att <- tapply(rep(1, sum(fga)), kpos[fga], sum)
  fg_made <- tapply(as.numeric(p$field_goal_result[fga] %in% "made"), kpos[fga], sum)
  list(off_epa = off_epa, ypp = ypp, rush_yds = rush_yds, pass_yds = pass_yds, first_downs = first_downs,
       t3c = t3c, t3f = t3f, sacks = sacks, ints = ints, fum_lost = fum_lost, pen_yds = pen_yds,
       fumbles = fumbles, recov = recov, fg_att = fg_att, fg_made = fg_made, games_seen = unique(p$game_id))
}

say("Building the team-game history %d-%d", DATA_FIRST, DATA_LAST)
H <- do.call(rbind, lapply(DATA_FIRST:DATA_LAST, function(s) {
  g <- SCHED[SCHED$season == s & SCHED$game_type == "REG" & !is.na(SCHED$home_score) & !is.na(SCHED$away_score), , drop = FALSE]
  st <- team_game_stats(s)
  mk <- function(home) {
    d <- data.frame(season = s, game_id = g$game_id, game_date = g$gameday, week = g$week, home = home,
                    team = if (home) g$home_team else g$away_team, opp = if (home) g$away_team else g$home_team,
                    pts = if (home) g$home_score else g$away_score, opp_pts = if (home) g$away_score else g$home_score,
                    stringsAsFactors = FALSE)
    d
  }
  d <- rbind(mk(TRUE), mk(FALSE))
  k <- paste(d$game_id, d$team); ko <- paste(d$game_id, d$opp)
  getv <- function(tab, key, zero = FALSE) { v <- as.numeric(tab[key]); if (zero) v[is.na(v) & d$game_id %in% st$games_seen] <- 0; v }
  d$pbp_found <- d$game_id %in% st$games_seen
  d$off_epa <- getv(st$off_epa, k); d$def_epa <- getv(st$off_epa, ko)
  d$ypp <- getv(st$ypp, k); d$rush_yds <- getv(st$rush_yds, k, TRUE); d$pass_yds <- getv(st$pass_yds, k, TRUE)
  d$first_downs <- getv(st$first_downs, k, TRUE)
  t3c <- getv(st$t3c, k, TRUE); t3f <- getv(st$t3f, k, TRUE); d$third_pct <- ifelse(t3c + t3f > 0, t3c / (t3c + t3f), NA_real_)
  d$sacks_taken <- getv(st$sacks, k, TRUE)
  d$giveaways <- getv(st$ints, k, TRUE) + getv(st$fum_lost, k, TRUE)
  d$takeaways <- getv(st$ints, ko, TRUE) + getv(st$fum_lost, ko, TRUE)
  d$pen_yds <- getv(st$pen_yds, k, TRUE)
  d$fumbles_game <- getv(st$fumbles, k, TRUE) + getv(st$fumbles, ko, TRUE)
  d$fum_recovered <- getv(st$recov, k, TRUE)
  d$opp_fg_att <- getv(st$fg_att, ko, TRUE); d$opp_fg_made <- getv(st$fg_made, ko, TRUE)
  d
}))
H$margin <- H$pts - H$opp_pts
H$win <- ifelse(H$margin > 0, 1, ifelse(H$margin < 0, 0, 0.5))
e <- ELO[match(H$game_id, ELO$game_id), ]
H$elo_pre <- ifelse(H$home, e$home_elo_pre, e$away_elo_pre); H$opp_elo_pre <- ifelse(H$home, e$away_elo_pre, e$home_elo_pre)
H$elo_post <- ifelse(H$home, e$home_elo_post, e$away_elo_post)
H$home_sign <- ifelse(H$home, 1, -1)   # production Elo gives the listed home team home field at every site
H$elo_exp_margin <- (H$elo_pre - H$opp_elo_pre + H$home_sign * ELO_HCA_POINTS) / ELO_POINTS_PER_MARGIN_PT
H$elo_win_prob <- ifelse(H$home, e$elo_prob_pure, 1 - e$elo_prob_pure)
H$elo_delta <- H$elo_post - H$elo_pre
H$resid <- H$margin - H$elo_exp_margin
H <- H[order(H$team, H$game_date, H$game_id), , drop = FALSE]; rownames(H) <- NULL
stopifnot(!anyDuplicated(paste(H$game_id, H$team)), !any(is.na(H$elo_pre)))
N <- nrow(H)
H$pos <- ave(seq_len(N), H$team, FUN = seq_along)                       # index in the team's whole history
H$ts <- paste(H$season, H$team)
H$pos_season <- ave(seq_len(N), H$ts, FUN = seq_along)                  # index within the season
prev_date <- ave(as.numeric(H$game_date), H$team, FUN = function(v) c(NA, v[-length(v)]))
H$days_rest <- as.numeric(H$game_date) - prev_date                       # across seasons (as the NBA chunk)
H$rest_in_season <- ifelse(H$pos_season > 1, H$days_rest, NA_real_)
H$opp_row <- match(paste(H$game_id, H$opp), paste(H$game_id, H$team))
H$opp_rest <- H$rest_in_season[H$opp_row]
cat(sprintf("    Team-games %d-%d: %d; without play-by-play: %d; ties: %d games\n", DATA_FIRST, DATA_LAST, N,
            sum(!H$pbp_found), sum(H$margin == 0) / 2))

# ------------------------------------------------------------------------------
# 2. Opponent adjustment (opponent's EARLIER games only)
# ------------------------------------------------------------------------------
# A team's baseline before a game = its mean over its earlier games this season;
# for its first game of a season, its mean over the whole previous season (still
# earlier games; this fallback is new relative to the momentum study, which left
# week-1 values missing, so that week 1 has a value under every method).
prior_mean_in_group <- function(x, grp) ave(x, grp, FUN = function(v) {
  n <- length(v); ok <- !is.na(v); s <- cumsum(ifelse(ok, v, 0)); m <- cumsum(ok)
  out <- c(NA_real_, (s / m)[-n]); out[c(TRUE, m[-n] == 0)] <- NA_real_; out[seq_len(n)]
})
ts_mean <- function(x) tapply(x, H$ts, mean, na.rm = TRUE)
prev_season_mean <- function(x) { m <- ts_mean(x); v <- as.numeric(m[paste(H$season - 1L, H$team)]); v[is.nan(v)] <- NA; v }
baseline_before <- function(x) { pm <- prior_mean_in_group(x, H$ts); ifelse(is.na(pm), prev_season_mean(x), pm) }
opp_base <- function(x) baseline_before(x)[H$opp_row]
H$adj_off_epa <- H$off_epa - opp_base(H$def_epa)      # opponent's earlier EPA/play allowed
H$adj_def_epa <- H$def_epa - opp_base(H$off_epa)      # opponent's earlier EPA/play produced
H$form_epa <- H$adj_off_epa - H$adj_def_epa           # opponent-adjusted EPA/play, offense minus defense allowed
H$form_margin <- H$margin + opp_base(H$margin)        # opponent-adjusted point margin
cat(sprintf("    Missing per-game opponent-adjusted EPA: %d of %d team-games (%d in 2012-2025); margin: %d\n",
            sum(is.na(H$form_epa)), N, sum(is.na(H$form_epa) & H$season %in% HIST_SEASONS), sum(is.na(H$form_margin))))

# ------------------------------------------------------------------------------
# 3. Window engine (forward-only: lag l = the team's l-th previous game)
# ------------------------------------------------------------------------------
LAG_IDX <- sapply(seq_len(KMAX), function(l) { i <- seq_len(N) - l; i[H$pos <= l] <- NA_integer_; i })
lagm <- function(v) matrix(v[LAG_IDX], N, KMAX)
LSEA <- lagm(H$season)
DBACK <- H$season - LSEA                                   # seasons back of each lagged game (NA = no such game)
stopifnot(all(LAG_IDX[!is.na(LAG_IDX)] < row(LAG_IDX)[!is.na(LAG_IDX)]))   # look-ahead guard: lags point to earlier rows
stopifnot(all(H$game_date[LAG_IDX[!is.na(LAG_IDX[, 1]), 1]] < H$game_date[!is.na(LAG_IDX[, 1])]))

LAGCACHE <- new.env()
series_lags <- function(name) {
  if (is.null(LAGCACHE[[name]])) {
    v <- H[[name]]
    avg <- tapply(v, H$season, mean, na.rm = TRUE)
    LAGCACHE[[name]] <- list(V = lagm(v), A = matrix(as.numeric(avg[as.character(LSEA)]), N, KMAX))
  }
  LAGCACHE[[name]]
}
# Window mean of series `name` over the last k games under `method`.
window_value <- function(name, k, method) {
  L <- series_lags(name); V <- L$V[, seq_len(k), drop = FALSE]; D <- DBACK[, seq_len(k), drop = FALSE]
  if (method == "reset") {
    ok <- rowSums(!is.na(D) & D == 0 & !is.na(V)) == k
    out <- rowMeans(V); out[!ok] <- NA_real_
  } else if (method == "mean_regress") {
    A <- L$A[, seq_len(k), drop = FALSE]
    out <- rowMeans(A + REGRESS_KEEP^D * (V - A))            # NA if any game missing
  } else if (method == "decay") {
    W <- DECAY_BASE^D
    out <- rowSums(W * V) / rowSums(W)
  } else if (method == "original") {                         # NBA chunk: slide_dbl(mean, .before = k, .after = -1) by team
    E <- !is.na(D); Vz <- V; Vz[!E] <- 0
    out <- rowSums(Vz) / rowSums(E)
    out[rowSums(E) == 0] <- NA_real_                          # empty window (NaN in the original; dropped by drop_na())
  } else stop("unknown method ", method)
  out
}
std_value <- function(name, method) {
  v <- H[[name]]
  pm <- prior_mean_in_group(v, H$ts)
  if (method == "reset") return(pm)
  prev <- prev_season_mean(v)
  if (method == "mean_regress") {
    avg <- tapply(v, H$season, mean, na.rm = TRUE); a <- as.numeric(avg[as.character(H$season - 1L)])
    prev <- a + REGRESS_KEEP * (prev - a)
  }
  ifelse(H$pos_season == 1, prev, pm)
}
win_value <- function(name, w, method) if (w == "std") std_value(name, method) else window_value(name, as.integer(w), method)

# ------------------------------------------------------------------------------
# 4. Evaluation machinery (LOSO; team-season block bootstrap)
# ------------------------------------------------------------------------------
BLOCK_LEVELS <- sort(unique(H$ts[H$season %in% HIST_SEASONS]))
NB <- length(BLOCK_LEVELS)
set.seed(STUDY_SEED)
BOOT_C <- t(apply(matrix(sample.int(NB, NB * N_BOOT, replace = TRUE), nrow = N_BOOT), 1, tabulate, nbins = NB))
q95 <- function(x) unname(stats::quantile(x, c(0.025, 0.975), na.rm = TRUE))
bsum <- function(S, blk) { out <- matrix(0, NB, ncol(S)); rs <- rowsum(S, blk); out[as.integer(rownames(rs)), ] <- rs; out }
solve_safe <- function(A, b) tryCatch(solve(A, b), error = function(e) qr.solve(A, b))
logit_fit <- function(X, y) suppressWarnings(stats::glm.fit(cbind(1, X), y, family = stats::binomial())$coefficients)
logit_pred <- function(b, X) as.numeric(stats::plogis(cbind(1, X) %*% b))
log_loss <- function(p, y) { p <- pmin(pmax(p, 1e-12), 1 - 1e-12); -(y * log(p) + (1 - y) * log(1 - p)) }
auc_point <- function(p, y) { r <- rank(p); n1 <- sum(y == 1); n0 <- length(y) - n1; (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0) }
# Block-pair concordance matrix: M[a, b] = concordant pairs (positive in block a,
# negative in block b), ties counted half; bootstrap AUC = c'Mc / (n1(c) n0(c)).
auc_boot <- function(p, y, blk) {
  pos <- y == 1; G <- outer(p[pos], p[!pos], ">") + 0.5 * outer(p[pos], p[!pos], "==")
  R1 <- bsum(G, blk[pos])                       # NB x n0
  M <- t(bsum(t(R1), blk[!pos]))                # NB x NB
  n1 <- bsum(matrix(as.numeric(pos)), blk)[, 1]; n0 <- bsum(matrix(as.numeric(!pos)), blk)[, 1]
  rowSums((BOOT_C %*% M) * BOOT_C) / (as.numeric(BOOT_C %*% n1) * as.numeric(BOOT_C %*% n0))
}
r2_boot <- function(y, pred, blk) {
  S <- bsum(cbind(1, y, y^2, (y - pred)^2), blk)
  f <- function(B) 1 - B[, 4] / (B[, 3] - B[, 2]^2 / B[, 1])
  list(point = f(matrix(colSums(S), 1)), boot = f(BOOT_C %*% S))
}
mean_boot <- function(v, blk) { S <- bsum(cbind(1, v), blk); list(point = sum(S[, 2]) / sum(S[, 1]), boot = as.numeric((BOOT_C %*% S[, 2]) / (BOOT_C %*% S[, 1]))) }
loso_linear <- function(y, X, sea, ok) {
  pred <- rep(NA_real_, length(y))
  for (s in HIST_SEASONS) {
    tr <- ok & sea != s; te <- ok & sea == s
    if (sum(te) == 0 || sum(tr) < 50) next
    b <- solve_safe(crossprod(X[tr, , drop = FALSE]), crossprod(X[tr, , drop = FALSE], y[tr])); pred[te] <- X[te, , drop = FALSE] %*% b
  }
  pred
}
loso_logit <- function(y, X, sea, ok) {
  pred <- rep(NA_real_, length(y))
  for (s in HIST_SEASONS) {
    tr <- ok & sea != s; te <- ok & sea == s
    if (sum(te) == 0 || sum(tr) < 50) next
    pred[te] <- logit_pred(logit_fit(X[tr, , drop = FALSE], y[tr]), X[te, , drop = FALSE])
  }
  pred
}

# ------------------------------------------------------------------------------
# 5. Arm B: stronger version
# ------------------------------------------------------------------------------
say("Arm B: LOSO %d-%d, 2 features x 3 methods x %d windows x 4 targets, %d bootstrap resamples",
    min(HIST_SEASONS), max(HIST_SEASONS), length(WINDOWS), N_BOOT)
IN_HIST <- H$season %in% HIST_SEASONS
BLK <- match(H$ts, BLOCK_LEVELS)
y_margin <- H$margin; y_beyond <- H$margin - H$elo_exp_margin
HOME_ROW <- H$home & IN_HIST
y_win <- ifelse(H$margin > 0, 1, ifelse(H$margin < 0, 0, NA_real_))
elo_logit <- stats::qlogis(H$elo_win_prob)
FEATURES_B <- c(epa = "form_epa", margin = "form_margin")

# Score one window's team-minus-opponent difference d on the rows in `mask`.
# The Elo-only baseline for the win target is refit on each candidate's rows.
score_diff <- function(d, mask = IN_HIST) {
  okm <- mask & !is.na(d)
  # margin raw: margin ~ 1 + home sign + difference; beyond Elo: (margin - Elo expected) ~ 1 + difference
  Xr <- cbind(1, H$home_sign, d); Xe <- cbind(1, d)
  pr <- loso_linear(y_margin, Xr, H$season, okm); pe <- loso_linear(y_beyond, Xe, H$season, okm)
  okp <- okm & !is.na(pr)
  res <- list()
  if (sum(okp) >= MIN_ROWS) {
    a <- r2_boot(y_margin[okp], pr[okp], BLK[okp]); b <- r2_boot(y_beyond[okp], pe[okp], BLK[okp])
    res$margin_raw <- list(metric = "out-of-fold R^2", point = a$point, boot = a$boot, n = sum(okp))
    res$margin_beyond_elo <- list(metric = "out-of-fold R^2 of (margin - Elo expected margin)", point = b$point, boot = b$boot, n = sum(okp))
  }
  okw <- mask & H$home & !is.na(d) & !is.na(y_win)
  if (sum(okw) >= MIN_ROWS) {
    pw <- loso_logit(y_win, cbind(d), H$season, okw)
    pb <- loso_logit(y_win, cbind(elo_logit), H$season, okw)
    pc <- loso_logit(y_win, cbind(elo_logit, d), H$season, okw)
    ok2 <- okw & !is.na(pw) & !is.na(pc)
    yy <- y_win[ok2]; bb <- BLK[ok2]
    ll_raw <- mean_boot(log_loss(pw[ok2], yy), bb); ll_c <- mean_boot(log_loss(pc[ok2], yy), bb); ll_b <- mean_boot(log_loss(pb[ok2], yy), bb)
    auc_r <- auc_boot(pw[ok2], yy, bb); auc_c <- auc_boot(pc[ok2], yy, bb); auc_b <- auc_boot(pb[ok2], yy, bb)
    res$win_raw_auc <- list(metric = "ROC-AUC", point = auc_point(pw[ok2], yy), boot = auc_r, n = sum(ok2))
    res$win_raw_logloss <- list(metric = "log loss (lower is better)", point = ll_raw$point, boot = ll_raw$boot, n = sum(ok2))
    res$win_beyond_elo_logloss_gain <- list(metric = "log loss of Elo-only minus log loss with the feature (higher is better)",
                                            point = ll_b$point - ll_c$point, boot = ll_b$boot - ll_c$boot, n = sum(ok2),
                                            logloss = ll_c$point, logloss_elo = ll_b$point)
    res$win_beyond_elo_auc_gain <- list(metric = "ROC-AUC with the feature minus Elo-only ROC-AUC", point = auc_point(pc[ok2], yy) - auc_point(pb[ok2], yy),
                                        boot = auc_c - auc_b, n = sum(ok2), auc = auc_point(pc[ok2], yy), auc_elo = auc_point(pb[ok2], yy))
  }
  res
}
# Same-rows check for reset: rows where both teams have at least 8 earlier games this
# season, so windows 1..8 and season-to-date all exist (all three methods coincide there).
COMMON8 <- IN_HIST & H$pos_season >= 9 & H$pos_season[H$opp_row] >= 9
COMMON8_WINDOWS <- c(as.character(1:8), "std")
B_ROWS <- list(); COUNT_ROWS <- list(); FEATVALS <- list(); B_COMMON <- list()
for (fn in names(FEATURES_B)) for (m in METHODS) for (w in WINDOWS) {
  x <- win_value(FEATURES_B[[fn]], w, m)
  FEATVALS[[paste(fn, m, w)]] <- x
  d <- x - x[H$opp_row]
  okm <- IN_HIST & !is.na(d)
  res <- score_diff(d)
  if (m == "reset" && w %in% COMMON8_WINDOWS) B_COMMON[[paste(fn, "reset_same_rows", w)]] <- score_diff(d, COMMON8)
  B_ROWS[[paste(fn, m, w)]] <- res
  # counts: team-games 2012-2025 with a value (own / own and opponent), and in weeks 1-6
  early <- IN_HIST & H$week <= 6
  COUNT_ROWS[[paste(fn, m, w)]] <- data.frame(feature = fn, method = m, window = w,
    team_games_with_value = sum(IN_HIST & !is.na(x)), team_games_scorable = sum(okm),
    weeks1_6_with_value = sum(early & !is.na(x)), weeks1_6_scorable = sum(early & !is.na(d)),
    weeks1_6_total = sum(early), team_games_total = sum(IN_HIST), stringsAsFactors = FALSE)
}
say("Arm B scored")
COUNTS_DF <- do.call(rbind, COUNT_ROWS); rownames(COUNTS_DF) <- NULL
cat("\n>>> Row counts per method (opponent-adjusted EPA; team-games 2012-2025 with own and opponent values; weeks 1-6)\n")
print(COUNTS_DF[COUNTS_DF$feature == "epa", c("method", "window", "team_games_scorable", "team_games_total", "weeks1_6_scorable", "weeks1_6_total")], row.names = FALSE)

B_TARGETS <- c("margin_raw", "margin_beyond_elo", "win_raw_auc", "win_raw_logloss", "win_beyond_elo_logloss_gain", "win_beyond_elo_auc_gain")
LOWER_BETTER <- c(win_raw_logloss = TRUE)
ALL_B <- c(B_ROWS, B_COMMON)
B_TABLE <- do.call(rbind, lapply(names(ALL_B), function(key) {
  parts <- strsplit(key, " ")[[1]]; r <- ALL_B[[key]]
  do.call(rbind, lapply(B_TARGETS, function(tg) {
    z <- r[[tg]]
    if (is.null(z)) return(data.frame(feature = parts[1], method = parts[2], window = parts[3], target = tg, score = NA, lo = NA, hi = NA, n = 0, stringsAsFactors = FALSE))
    ci <- q95(z$boot)
    data.frame(feature = parts[1], method = parts[2], window = parts[3], target = tg, score = z$point, lo = ci[1], hi = ci[2], n = z$n, stringsAsFactors = FALSE)
  }))
}))
rownames(B_TABLE) <- NULL
# Selection rule: best window's 95% interval; answer = shortest window (1..17, then
# season-to-date as the longest) whose point score lies inside that interval.
select_window <- function(tab, lower_better) {
  tab <- tab[!is.na(tab$score), , drop = FALSE]
  if (!nrow(tab)) return(list(best = NA, best_score = NA, best_lo = NA, best_hi = NA, chosen = NA, chosen_score = NA, within = character(0)))
  ord <- match(tab$window, WINDOWS); tab <- tab[order(ord), ]
  bi <- if (lower_better) which.min(tab$score) else which.max(tab$score)
  lo <- tab$lo[bi]; hi <- tab$hi[bi]
  inside <- tab$score >= lo & tab$score <= hi
  if (lower_better) inside <- tab$score <= hi else inside <- tab$score >= lo
  ci <- which(inside)[1]
  list(best = tab$window[bi], best_score = tab$score[bi], best_lo = lo, best_hi = hi,
       chosen = tab$window[ci], chosen_score = tab$score[ci], within = tab$window[inside])
}
SELECT <- list()
for (fn in names(FEATURES_B)) for (m in c(METHODS, "reset_same_rows")) for (tg in B_TARGETS) {
  s <- select_window(B_TABLE[B_TABLE$feature == fn & B_TABLE$method == m & B_TABLE$target == tg, ], isTRUE(LOWER_BETTER[tg]))
  SELECT[[paste(fn, m, tg)]] <- c(list(feature = fn, method = m, target = tg), s)
}
SELECT_DF <- do.call(rbind, lapply(SELECT, function(s) data.frame(feature = s$feature, method = s$method, target = s$target,
  best = s$best, best_score = s$best_score, best_lo = s$best_lo, best_hi = s$best_hi, chosen = s$chosen, chosen_score = s$chosen_score,
  windows_within = paste(s$within, collapse = ","), stringsAsFactors = FALSE)))
rownames(SELECT_DF) <- NULL
cat("\n>>> Arm B selections (shortest window inside the best window's 95% interval)\n"); print(SELECT_DF[, 1:9], row.names = FALSE)

# Method comparison on the rows reset cannot score (carry methods only differ from
# reset where a window reaches into an earlier season): margin beyond Elo, epa form.
METHOD_EARLY <- do.call(rbind, lapply(c("3", "6", "9", "std"), function(w) {
  xr <- FEATVALS[[paste("epa reset", w)]]; dr <- xr - xr[H$opp_row]
  do.call(rbind, lapply(c("mean_regress", "decay"), function(m) {
    x <- FEATVALS[[paste("epa", m, w)]]; d <- x - x[H$opp_row]
    ok <- IN_HIST & !is.na(d)
    pe <- loso_linear(y_beyond, cbind(1, d), H$season, ok)
    sub <- ok & is.na(dr) & !is.na(pe)
    if (sum(sub) < 30) return(NULL)
    a <- r2_boot(y_beyond[sub], pe[sub], BLK[sub])
    data.frame(window = w, method = m, rows_reset_cannot_score = sum(sub), r2_beyond_elo = a$point,
               lo = q95(a$boot)[1], hi = q95(a$boot)[2], stringsAsFactors = FALSE)
  }))
}))
cat("\n>>> Carry methods on the rows reset leaves unscored (margin beyond Elo, out-of-fold R^2)\n"); print(METHOD_EARLY, row.names = FALSE)

# ------------------------------------------------------------------------------
# 6. Arm A: replication of the NBA window test
# ------------------------------------------------------------------------------
say("Arm A: replication, 4 variants x %d windows, random forest (ranger, 300 trees)", length(KS))
REP_STATS <- c(pts = "pts", fd = "first_downs", rush = "rush_yds", pass = "pass_yds", sacks = "sacks_taken", give = "giveaways",
               take = "takeaways", pen = "pen_yds", ypp = "ypp", third = "third_pct", offepa = "off_epa", defepa = "def_epa")
REP_LEVELS_REMOVED <- c("pts", "ypp", "third", "offepa", "defepa")   # as the NBA chunk removes levels of points and rate stats, keeping their differences
REP_ROWS <- H$home & H$season >= DATA_FIRST & H$season <= REP_TEST_SEASON
run_replication <- function(k, variant) {
  rolled <- sapply(REP_STATS, function(nm) window_value(nm, k, variant))
  hi <- which(REP_ROWS); ai <- H$opp_row[hi]
  df <- data.frame(game_id = H$game_id[hi], season = H$season[hi], home_team = H$team[hi], away_team = H$opp[hi],
                   target_home_win = factor(ifelse(H$margin[hi] > 0, "Win", "Loss"), levels = c("Win", "Loss")))
  for (nm in names(REP_STATS)) if (!nm %in% REP_LEVELS_REMOVED) {
    df[[paste0("home_roll_", nm)]] <- rolled[hi, nm]; df[[paste0("away_roll_", nm)]] <- rolled[ai, nm]
  }
  df$home_days_rest <- H$days_rest[hi]; df$away_days_rest <- H$days_rest[ai]
  for (nm in names(REP_STATS)) df[[paste0("diff_roll_", nm)]] <- rolled[hi, nm] - rolled[ai, nm]
  df$diff_roll_totyds <- (rolled[hi, "rush"] + rolled[hi, "pass"]) - (rolled[ai, "rush"] + rolled[ai, "pass"])
  df$diff_days_rest <- df$home_days_rest - df$away_days_rest
  n_all <- nrow(df); df <- df[stats::complete.cases(df), , drop = FALSE]
  train <- df[df$season < REP_TEST_SEASON, , drop = FALSE]; test <- df[df$season >= REP_TEST_SEASON, , drop = FALSE]
  out <- data.frame(variant = variant, window_size = k, accuracy = NA_real_, roc_auc = NA_real_, auc_lo = NA_real_, auc_hi = NA_real_, kappa = NA_real_,
                    train_games = nrow(train), test_games = nrow(test), rows_dropped_na = n_all - nrow(df), stringsAsFactors = FALSE)
  if (nrow(test) < 20 || nrow(train) < 200 || length(unique(test$target_home_win)) < 2) return(out)
  rec <- recipe(target_home_win ~ ., data = train) |>
    step_rm(game_id, home_team, away_team) |>
    step_normalize(all_numeric_predictors())
  rf <- rand_forest(trees = 300, mode = "classification") |> set_engine("ranger", num.threads = 4)
  set.seed(STUDY_SEED + 100L * match(variant, REP_VARIANTS) + k)   # fixed seed per window (the original set none)
  fit_obj <- fit(workflow() |> add_recipe(rec) |> add_model(rf), data = train)
  preds <- predict(fit_obj, test) |> bind_cols(predict(fit_obj, test, type = "prob")) |> bind_cols(test["target_home_win"])
  out$accuracy <- accuracy(preds, truth = target_home_win, estimate = .pred_class)$.estimate
  out$roc_auc <- roc_auc(preds, truth = target_home_win, .pred_Win, event_level = "first")$.estimate
  out$kappa <- kap(preds, truth = target_home_win, estimate = .pred_class)$.estimate
  # game-level bootstrap interval for the test-season ROC-AUC (not in the original; shows how noisy one season is)
  set.seed(STUDY_SEED + 5000L + k)
  yb <- as.numeric(preds$target_home_win == "Win"); pbw <- preds$.pred_Win
  ab <- replicate(N_BOOT, { i <- sample.int(length(yb), replace = TRUE); if (length(unique(yb[i])) < 2) NA_real_ else auc_point(pbw[i], yb[i]) })
  ci <- q95(ab); out$auc_lo <- ci[1]; out$auc_hi <- ci[2]
  out
}
REP <- do.call(rbind, lapply(REP_VARIANTS, function(v) do.call(rbind, lapply(KS, run_replication, variant = v))))
rownames(REP) <- NULL
REP_BEST <- do.call(rbind, lapply(REP_VARIANTS, function(v) {
  r <- REP[REP$variant == v & !is.na(REP$roc_auc), ]
  if (!nrow(r)) return(data.frame(variant = v, best_window = NA, roc_auc = NA, auc_lo = NA, auc_hi = NA, accuracy = NA, kappa = NA, test_games = NA, windows_inside_best_interval = ""))
  b <- r[which.max(r$roc_auc), ]
  data.frame(variant = v, best_window = b$window_size, roc_auc = b$roc_auc, auc_lo = b$auc_lo, auc_hi = b$auc_hi, accuracy = b$accuracy, kappa = b$kappa, test_games = b$test_games,
             windows_inside_best_interval = paste(r$window_size[r$roc_auc >= b$auc_lo], collapse = ","))
}))
cat("\n>>> Arm A (replication) results\n"); print(REP, row.names = FALSE)
cat("\n>>> Arm A best window by ROC-AUC\n"); print(REP_BEST, row.names = FALSE)
say("Arm A done")

# ------------------------------------------------------------------------------
# 7. Combined-score weights (form, trend, residual vs Elo, Elo change)
# ------------------------------------------------------------------------------
say("Weights: 0.05-step grid and non-negative regression, LOSO, board windows %s", paste(BOARD_WINDOWS, collapse = ", "))
GRID <- as.matrix(subset(expand.grid(form = 0:20, trend = 0:20, resid = 0:20, elo = 0:20), form + trend + resid + elo == 20)) / 20
rownames(GRID) <- NULL
NBA_W <- which(abs(GRID[, 1] - 0.7) < 1e-9 & abs(GRID[, 2] - 0.1) < 1e-9 & abs(GRID[, 3] - 0.1) < 1e-9)
EQUAL_W <- which(apply(abs(GRID - 0.25) < 1e-9, 1, all))
stopifnot(length(NBA_W) == 1, length(EQUAL_W) == 1)
zweek <- function(x) {
  key <- paste(H$season, H$week)
  n <- ave(!is.na(x), key, FUN = sum)
  m <- ave(x, key, FUN = function(v) mean(v, na.rm = TRUE)); s <- ave(x, key, FUN = function(v) stats::sd(v, na.rm = TRUE))
  z <- (x - m) / s
  z[!is.na(x) & !is.na(s) & s < 1e-9] <- 0          # every team equal that week (e.g. trend when the window equals season-to-date): no information, z = 0
  z[n < MIN_Z_TEAMS | !is.finite(z)] <- NA_real_; z
}
lead_same_season <- function(v, i) { j <- seq_len(N) + i; j[j > N] <- NA; j[!is.na(j)][H$ts[j[!is.na(j)]] != H$ts[!is.na(j)]] <- NA
  ok <- !is.na(j); out <- rep(NA_real_, N); out[ok] <- v[j[ok]]; out }
y1 <- y_beyond
y3 <- (y_beyond + lead_same_season(y_beyond, 1) + lead_same_season(y_beyond, 2)) / 3   # this game and the next two, same season
# Exact non-negative least squares (free intercept) by enumerating the 2^4 active sets.
nnls_fit <- function(Z, y) {
  best <- c(mean(y), rep(0, ncol(Z))); best_sse <- sum((y - mean(y))^2)
  for (mask in 1:(2^ncol(Z) - 1)) {
    use <- which(bitwAnd(mask, 2^(seq_len(ncol(Z)) - 1)) > 0)
    if (any(apply(Z[, use, drop = FALSE], 2, stats::var) < 1e-12)) next   # constant column (trend at season-to-date)
    X <- cbind(1, Z[, use, drop = FALSE]); b <- solve_safe(crossprod(X), crossprod(X, y))
    if (any(b[-1] < 0)) next
    sse <- sum((y - X %*% b)^2)
    if (sse < best_sse) { best_sse <- sse; best <- c(b[1], rep(0, ncol(Z))); best[1 + use] <- b[-1] }
  }
  best
}
fit_weights <- function(m, w, target) {
  form <- win_value("form_epa", w, m); stdf <- std_value("form_epa", m)
  trend <- if (w == "std") 0 * form else form - stdf
  trend[abs(trend) < 1e-12] <- 0                       # window identical to season-to-date: exact zero, not rounding noise
  comp <- cbind(form = form, trend = trend,
                resid = win_value("resid", w, m),
                elo = win_value("elo_delta", w, m) * (if (w == "std") pmax(H$pos_season - 1, 1) else as.integer(w)))
  Z <- apply(comp, 2, zweek)
  if (w == "std") Z[, "trend"] <- ifelse(is.na(Z[, "form"]), NA, 0)   # season-to-date has no trend: constant zero
  y <- if (target == "next_game") y1 else y3
  ok <- IN_HIST & stats::complete.cases(Z) & !is.na(y)
  idx <- which(ok); Zo <- Z[idx, , drop = FALSE]; yo <- y[idx]; so <- H$season[idx]; bo <- BLK[idx]
  SSE <- matrix(0, NB, nrow(GRID)); pred_nested <- pred_nnls <- rep(NA_real_, length(idx)); nested_choice <- integer(0); nnls_w <- list()
  for (s in HIST_SEASONS) {
    tr <- so != s; te <- so == s
    if (!any(te)) next
    Sz <- stats::cov(Zo[tr, ]); szy <- stats::cov(Zo[tr, ], yo[tr]); zb <- colMeans(Zo[tr, ]); yb <- mean(yo[tr]); vy <- stats::var(yo[tr])
    vc <- rowSums((GRID %*% Sz) * GRID); cc <- as.numeric(GRID %*% szy)
    b <- ifelse(vc > 0, cc / vc, 0); a <- yb - b * as.numeric(GRID %*% zb)
    P <- sweep(sweep(Zo[te, , drop = FALSE] %*% t(GRID), 2, b, "*"), 2, a, "+")
    SSE <- SSE + bsum((yo[te] - P)^2, bo[te])
    r2tr <- ifelse(vc > 0, cc^2 / (vc * vy), 0)
    pk <- which.max(r2tr); nested_choice <- c(nested_choice, pk); pred_nested[te] <- P[, pk]
    nb <- nnls_fit(Zo[tr, , drop = FALSE], yo[tr]); pred_nnls[te] <- nb[1] + Zo[te, , drop = FALSE] %*% nb[-1]
    nnls_w[[as.character(s)]] <- if (sum(nb[-1]) > 0) nb[-1] / sum(nb[-1]) else nb[-1]
  }
  Sy <- bsum(cbind(1, yo, yo^2), bo)
  sst_pt <- sum(Sy[, 3]) - sum(Sy[, 2])^2 / sum(Sy[, 1])
  sst_b <- as.numeric(BOOT_C %*% Sy[, 3] - (BOOT_C %*% Sy[, 2])^2 / (BOOT_C %*% Sy[, 1]))
  r2_pt <- 1 - colSums(SSE) / sst_pt
  r2_b <- 1 - (BOOT_C %*% SSE) / sst_b                       # N_BOOT x grid
  best <- which.max(r2_pt)
  ci_best <- q95(r2_b[, best])
  nested <- r2_boot(yo, pred_nested, bo); nn <- r2_boot(yo, pred_nnls, bo)
  within <- which(r2_pt >= ci_best[1])
  diff_nba <- r2_b[, best] - r2_b[, NBA_W]
  # full-sample non-negative regression weights (for reference)
  nb_all <- nnls_fit(Zo, yo); nnls_full <- if (sum(nb_all[-1]) > 0) nb_all[-1] / sum(nb_all[-1]) else nb_all[-1]
  wr <- function(ii) { g <- GRID[ii, , drop = FALSE]; apply(g, 2, function(v) sprintf("%.2f-%.2f", min(v), max(v))) }
  list(method = m, window = w, target = target, rows = length(idx),
       best_weights = setNames(as.numeric(GRID[best, ]), colnames(GRID)), best_r2 = r2_pt[best], best_ci = ci_best,
       nba_r2 = r2_pt[NBA_W], nba_ci = q95(r2_b[, NBA_W]), best_minus_nba = r2_pt[best] - r2_pt[NBA_W], best_minus_nba_ci = q95(diff_nba),
       equal_r2 = r2_pt[EQUAL_W], equal_ci = q95(r2_b[, EQUAL_W]),
       form_only_r2 = r2_pt[which(GRID[, 1] == 1)], form_only_ci = q95(r2_b[, which(GRID[, 1] == 1)]),
       nested_r2 = nested$point, nested_ci = q95(nested$boot),
       nested_choices = lapply(nested_choice, function(i) as.numeric(GRID[i, ])),
       nnls_r2 = nn$point, nnls_ci = q95(nn$boot), nnls_fold_weights = lapply(nnls_w, as.numeric), nnls_full_weights = setNames(nnls_full, colnames(GRID)),
       flat_n_within_best_ci = length(within), flat_share_within = length(within) / nrow(GRID),
       flat_weight_ranges = as.list(wr(within)),
       flat_n_within_90pct_of_best = sum(r2_pt >= 0.9 * r2_pt[best]),
       top10 = lapply(order(-r2_pt)[1:10], function(i) list(weights = as.numeric(GRID[i, ]), r2 = r2_pt[i])))
}
WEIGHTS <- list()
for (m in METHODS) for (w in BOARD_WINDOWS) for (tg in c("next_game", "next3")) {
  WEIGHTS[[paste(m, w, tg)]] <- fit_weights(m, w, tg)
}
WEIGHTS_DF <- do.call(rbind, lapply(WEIGHTS, function(r) data.frame(method = r$method, window = r$window, target = r$target, rows = r$rows,
  best = paste(sprintf("%.2f", r$best_weights), collapse = "/"), best_r2 = r$best_r2, best_lo = r$best_ci[1], best_hi = r$best_ci[2],
  nba_r2 = r$nba_r2, nba_lo = r$nba_ci[1], nba_hi = r$nba_ci[2], diff_lo = r$best_minus_nba_ci[1], diff_hi = r$best_minus_nba_ci[2],
  nested_r2 = r$nested_r2, nnls_r2 = r$nnls_r2, form_only_r2 = r$form_only_r2, n_within = r$flat_n_within_best_ci, stringsAsFactors = FALSE)))
rownames(WEIGHTS_DF) <- NULL
cat("\n>>> Weights (held-out R^2 of margin beyond Elo)\n"); print(WEIGHTS_DF, row.names = FALSE, digits = 3)
say("Weights done")

# ------------------------------------------------------------------------------
# 8. Availability data check (injury reports, snap counts)
# ------------------------------------------------------------------------------
say("Availability data check")
inj_path <- function(s) file.path(CACHE_DIR, sprintf("rws_injuries_%d.rds", s))
snap_path <- function(s) file.path(CACHE_DIR, sprintf("rws_snaps_%d.rds", s))
for (s in HIST_SEASONS) {
  if (!file.exists(inj_path(s))) { r <- tryCatch(as.data.frame(nflreadr::load_injuries(s)), error = function(e) NULL); if (!is.null(r)) saveRDS(r, inj_path(s)) }
  if (!file.exists(snap_path(s))) { r <- tryCatch(as.data.frame(nflreadr::load_snap_counts(s)), error = function(e) NULL); if (!is.null(r)) saveRDS(r, snap_path(s)) }
}
TEAMWEEKS <- unique(H[IN_HIST, c("season", "week", "team", "game_id")])
coverage_of <- function(df, kind) {
  if (is.null(df) || !nrow(df)) return(NULL)
  df <- as.data.frame(df)
  if ("game_type" %in% names(df)) df <- df[df$game_type %in% "REG", , drop = FALSE]
  tm <- canon(as.character(df$team))
  have <- if (kind == "snaps" && "game_id" %in% names(df)) unique(paste(df$game_id, tm)) else unique(paste(df$season, df$week, tm))
  key <- if (kind == "snaps" && "game_id" %in% names(df)) paste(TEAMWEEKS$game_id, TEAMWEEKS$team) else paste(TEAMWEEKS$season, TEAMWEEKS$week, TEAMWEEKS$team)
  cov <- tapply(key %in% have, TEAMWEEKS$season, mean)
  n <- tapply(key %in% have, TEAMWEEKS$season, sum); tot <- tapply(rep(1, nrow(TEAMWEEKS)), TEAMWEEKS$season, sum)
  data.frame(season = as.integer(names(cov)), team_weeks = as.integer(tot), with_rows = as.integer(n), share = as.numeric(cov))
}
INJ <- do.call(rbind, lapply(HIST_SEASONS, function(s) if (file.exists(inj_path(s))) readRDS(inj_path(s))[, c("season", "game_type", "team", "week")] else NULL))
SNP <- do.call(rbind, lapply(HIST_SEASONS, function(s) if (file.exists(snap_path(s))) readRDS(snap_path(s)) else NULL))
COV_INJ <- coverage_of(INJ, "injuries"); COV_SNP <- coverage_of(SNP, "snaps")
pipe_inj <- if (file.exists(CACHE_INJURY_DATA)) tryCatch(as.data.frame(readRDS(CACHE_INJURY_DATA)), error = function(e) NULL) else NULL
pipe_snp <- if (file.exists(CACHE_SNAP_COUNTS)) tryCatch(as.data.frame(readRDS(CACHE_SNAP_COUNTS)), error = function(e) NULL) else NULL
pipe_summary <- function(df) if (is.null(df)) list(present = FALSE) else list(present = TRUE, rows = nrow(df),
  seasons = if ("season" %in% names(df)) sort(unique(df$season)) else NULL, weeks = if ("week" %in% names(df)) sort(unique(df$week)) else NULL)
PIPE_INJ <- pipe_summary(pipe_inj); PIPE_SNP <- pipe_summary(pipe_snp)
# The pipeline caches hold the current season only: their coverage of its completed regular-season team-weeks.
SCHED_CUR_PATH <- file.path(CACHE_DIR, sprintf("rws_schedules_%d.rds", CURRENT_SEASON))
if (!file.exists(SCHED_CUR_PATH)) tryCatch(saveRDS(as.data.frame(nflreadr::load_schedules(CURRENT_SEASON)), SCHED_CUR_PATH), error = function(e) NULL)
pipe_cov <- function(df, kind) {
  if (is.null(df) || !file.exists(SCHED_CUR_PATH)) return(NULL)
  sc <- as.data.frame(readRDS(SCHED_CUR_PATH)); sc <- sc[sc$game_type == "REG" & !is.na(sc$home_score), ]
  tw <- rbind(data.frame(season = sc$season, week = sc$week, team = canon(sc$home_team), game_id = sc$game_id),
              data.frame(season = sc$season, week = sc$week, team = canon(sc$away_team), game_id = sc$game_id))
  tm <- canon(as.character(df$team))
  have <- if (kind == "snaps") unique(paste(df$game_id, tm)) else unique(paste(df$season, df$week, tm))
  key <- if (kind == "snaps") paste(tw$game_id, tw$team) else paste(tw$season, tw$week, tw$team)
  data.frame(week = sort(unique(tw$week)), team_weeks = as.integer(tapply(rep(1, nrow(tw)), tw$week, sum)),
             share = as.numeric(tapply(key %in% have, tw$week, mean)))
}
PIPE_INJ$coverage_current_season <- pipe_cov(pipe_inj, "injuries"); PIPE_SNP$coverage_current_season <- pipe_cov(pipe_snp, "snaps")
cat("
>>> Pipeline caches: current-season coverage by week (injuries, snaps)
"); print(PIPE_INJ$coverage_current_season); print(PIPE_SNP$coverage_current_season)
COVER_MIN <- 0.99   # a team-week with no injury row can mean nobody was listed, so near-full counts as covered
cov_full <- function(c) if (is.null(c)) integer(0) else c$season[c$share >= COVER_MIN]
COV_TABLE <- merge(setNames(if (is.null(COV_INJ)) data.frame(season = HIST_SEASONS, a = NA, b = NA, c = NA) else COV_INJ, c("season", "team_weeks", "injury_with_rows", "injury_share")),
                   setNames(if (is.null(COV_SNP)) data.frame(season = HIST_SEASONS, a = NA, b = NA, c = NA) else COV_SNP, c("season", "team_weeks_s", "snaps_with_rows", "snaps_share")), by = "season", all = TRUE)
COV_TABLE$both_full <- COV_TABLE$season %in% intersect(cov_full(COV_INJ), cov_full(COV_SNP))
cat("\n>>> Availability coverage (share of regular-season team-weeks with any rows)\n"); print(COV_TABLE, row.names = FALSE)
both_seasons <- COV_TABLE$season[COV_TABLE$both_full]
# first season from which every later tested season is fully covered by both sources
AVAIL_FROM <- NA_integer_
for (s in rev(HIST_SEASONS)) if (s %in% both_seasons) AVAIL_FROM <- s else break

# ------------------------------------------------------------------------------
# 9. Flag detection check (SIMULATED detection rates; a methods check, not data)
# ------------------------------------------------------------------------------
say("Flag detection check: %d simulations per flag and window", N_SIM)
HH <- H[IN_HIST, , drop = FALSE]
tsm <- function(x, f = mean) as.numeric(tapply(x, HH$ts, f))
q90abs <- function(x) unname(stats::quantile(abs(x), 0.9, na.rm = TRUE))
league_by_ts <- function(x) { ls <- tapply(x, HH$season, mean); as.numeric(ls[as.character(tapply(HH$season, HH$ts, `[`, 1))]) }
one <- abs(HH$margin) <= ONE_SCORE
os_share <- as.numeric(tapply(HH$win[one], HH$ts[one], mean))
pf <- tsm(HH$pts, sum); pa <- tsm(HH$opp_pts, sum); pyth <- pf^PYTH_EXP / (pf^PYTH_EXP + pa^PYTH_EXP)
fum_rate <- as.numeric(tapply(HH$fum_recovered, HH$ts, sum) / tapply(HH$fumbles_game, HH$ts, sum))
lg_fg <- sum(HH$opp_fg_made) / sum(HH$opp_fg_att)
opp_fg <- as.numeric(tapply(HH$opp_fg_made, HH$ts, sum) / tapply(HH$opp_fg_att, HH$ts, sum))
lg_fg_ts <- as.numeric((tapply(HH$opp_fg_made, HH$season, sum) / tapply(HH$opp_fg_att, HH$season, sum))[as.character(tapply(HH$season, HH$ts, `[`, 1))])
tom <- HH$takeaways - HH$giveaways
lam_give <- mean(HH$giveaways)
blow <- abs(HH$margin) >= BLOWOUT; lg_blow <- mean(blow)
opp_elo_dev <- HH$opp_elo_pre - ave(HH$opp_elo_pre, HH$season)
sd_within <- function(x) { r <- x - ave(x, HH$ts, FUN = function(v) mean(v, na.rm = TRUE)); stats::sd(r, na.rm = TRUE) * sqrt(length(HH$ts) / (length(HH$ts) - length(unique(HH$ts)))) }
rest_diff <- HH$rest_in_season - HH$opp_rest
FLAGS <- list(
  one_score = list(label = "One-score record vs expected", test = sprintf("binomial z: wins in one-score games (|margin| <= %d, ties half) vs 0.5", ONE_SCORE),
                   unit = "one-score games", per_game = mean(one), p0 = 0.5, delta = q90abs(os_share - 0.5), type = "binom",
                   effect_basis = "90th percentile of |team-season one-score win share - 0.5|"),
  pythagorean = list(label = "Pythagorean vs actual", test = sprintf("binomial z: wins vs the Pythagorean expectation (exponent %.2f; tested at p0 = 0.5)", PYTH_EXP),
                     unit = "games", per_game = 1, p0 = 0.5, delta = q90abs(tsm(HH$win) - pyth), type = "binom",
                     effect_basis = "90th percentile of |team-season win share - Pythagorean share|"),
  fumble_recovery = list(label = "Fumble-recovery rate", test = "binomial z: share of all fumbles in the team's games recovered by the team vs 0.5",
                         unit = "fumbles (both teams)", per_game = mean(HH$fumbles_game), p0 = 0.5, delta = q90abs(fum_rate - 0.5), type = "binom",
                         effect_basis = "90th percentile of |team-season recovery share - 0.5|"),
  opp_fg_pct = list(label = "Opponent field-goal %", test = sprintf("binomial z: opponents' field goals made vs the league rate (%.3f)", lg_fg),
                    unit = "opponent field-goal attempts", per_game = mean(HH$opp_fg_att), p0 = lg_fg, delta = q90abs(opp_fg - lg_fg_ts), type = "binom",
                    effect_basis = "90th percentile of |team-season opponent FG% - league FG% that season|"),
  turnover_margin = list(label = "Turnover margin vs season level", test = "Poisson z: window takeaways minus giveaways vs the team's season level (variance 2 x league giveaways per game)",
                         unit = "games", per_game = 1, lambda = lam_give, delta = q90abs(tsm(tom)), type = "poisson_diff",
                         effect_basis = "90th percentile of |team-season turnover margin per game|"),
  blowout_skew = list(label = "Blowout skew", test = sprintf("binomial z: share of games decided by %d+ points vs the league rate (%.3f)", BLOWOUT, lg_blow),
                      unit = "games", per_game = 1, p0 = lg_blow, delta = q90abs(tsm(as.numeric(blow)) - lg_blow), type = "binom",
                      effect_basis = "90th percentile of |team-season blowout share - league share|"),
  opponent_strength = list(label = "Opponent strength", test = "z: mean opponent pregame Elo vs the league mean that season, game-to-game SD within team-seasons",
                           unit = "games", per_game = 1, sd = sd_within(opp_elo_dev), delta = q90abs(tsm(opp_elo_dev)), type = "normal",
                           effect_basis = "90th percentile of |team-season mean opponent Elo - league mean|"),
  home_share = list(label = "Home share", test = "binomial z: home games vs 0.5",
                    unit = "games", per_game = 1, p0 = 0.5, delta = q90abs(tsm(as.numeric(HH$home)) - 0.5), type = "binom",
                    effect_basis = "90th percentile of |team-season home share - 0.5|"),
  rest_bye = list(label = "Rest / bye share", test = "z: mean rest-day difference (team minus opponent, within season) vs 0, game-to-game SD within team-seasons",
                  unit = "games (after week 1)", per_game = 1, sd = sd_within(rest_diff), delta = q90abs(tsm(rest_diff, function(v) mean(v, na.rm = TRUE))), type = "normal",
                  effect_basis = "90th percentile of |team-season mean rest-day difference|"))
# Key players missing: from snap counts (if available). Key players = the team-season's
# 22 players with the most snaps (offense plus defense); a key player-game is missed
# when the player has no snap row (or zero snaps) in a team game.
KEY_INFO <- NULL
if (!is.null(SNP) && nrow(SNP)) {
  sn <- as.data.frame(SNP); sn$team <- canon(as.character(sn$team))
  if ("game_type" %in% names(sn)) sn <- sn[sn$game_type %in% "REG", , drop = FALSE]
  sn$snaps <- ifelse(is.na(sn$offense_snaps), 0, sn$offense_snaps) + ifelse(is.na(sn$defense_snaps), 0, sn$defense_snaps)
  sn$ts <- paste(sn$season, sn$team)
  tot <- aggregate(snaps ~ ts + pfr_player_id, data = sn, sum)
  tot <- tot[order(tot$ts, -tot$snaps), ]; tot$rk <- ave(tot$snaps, tot$ts, FUN = seq_along)
  key <- tot[tot$rk <= KEY_PLAYERS, ]
  played <- unique(paste(sn$ts, sn$pfr_player_id, sn$game_id)[sn$snaps > 0])
  tg <- unique(sn[, c("ts", "game_id")])
  kk <- merge(key[, c("ts", "pfr_player_id")], tg, by = "ts")
  kk$missed <- !(paste(kk$ts, kk$pfr_player_id, kk$game_id) %in% played)
  rate <- tapply(kk$missed, kk$ts, mean); lg <- mean(kk$missed)
  KEY_INFO <- list(rate_league = lg, team_seasons = length(rate))
  FLAGS$key_players_missing <- list(label = "Key players missing", test = sprintf("binomial z: key player-games missed vs the league rate (%.3f); key = the team-season's %d players with most snaps", lg, KEY_PLAYERS),
                                    unit = "key player-games", per_game = KEY_PLAYERS, p0 = lg, delta = q90abs(rate - lg), type = "binom",
                                    effect_basis = "90th percentile of |team-season key player-games missed share - league share|",
                                    caveat = "player-games are not independent (one injury spans several games), so this test overstates detection")
}
set.seed(STUDY_SEED + 7L)
sim_detect <- function(f, w) {
  n <- max(round(f$per_game * w), 0)
  if (n < 1) return(list(n = n, rate = 0))
  z <- switch(f$type,
    binom = { p1 <- min(max(f$p0 + f$delta, 0), 1); x <- stats::rbinom(N_SIM, n, p1); (x - n * f$p0) / sqrt(n * f$p0 * (1 - f$p0)) },
    poisson_diff = { tk <- stats::rpois(N_SIM, w * (f$lambda + f$delta / 2)); gv <- stats::rpois(N_SIM, w * max(f$lambda - f$delta / 2, 0)); (tk - gv) / sqrt(2 * f$lambda * w) },
    normal = { m <- stats::rnorm(N_SIM, f$delta, f$sd / sqrt(w)); m / (f$sd / sqrt(w)) })
  list(n = n, rate = mean(abs(z) >= stats::qnorm(0.975)))
}
STD_TYPICAL <- round(stats::median(HH$pos_season - 1))   # typical season-to-date count (mid-season)
FLAG_W <- c(KS, STD_TYPICAL)
FLAG_DF <- do.call(rbind, lapply(names(FLAGS), function(nm) {
  f <- FLAGS[[nm]]
  do.call(rbind, lapply(seq_along(FLAG_W), function(i) { r <- sim_detect(f, FLAG_W[i])
    data.frame(flag = nm, window = if (i > length(KS)) "std" else as.character(FLAG_W[i]), games = FLAG_W[i], typical_count = r$n,
               simulated_detection_rate = r$rate, stringsAsFactors = FALSE) }))
}))
cat(sprintf("\n>>> Flag detection check (SIMULATED; %d draws; plausible effect = 90th percentile team-season deviation)\n", N_SIM))
print(FLAG_DF[FLAG_DF$window %in% c("3", "6", "9", "std", "17"), ], row.names = FALSE)

# ------------------------------------------------------------------------------
# 10. Save results
# ------------------------------------------------------------------------------
runtime <- elapsed()
sel_get <- function(fn, m, tg) SELECT[[paste(fn, m, tg)]]
RESULTS <- list(
  meta = list(issue = 227, run_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"), seed = STUDY_SEED, n_boot = N_BOOT, n_sim = N_SIM,
              runtime_minutes = round(runtime, 1), r_version = R.version.string,
              seasons_loso = HIST_SEASONS, data_seasons = c(DATA_FIRST, DATA_LAST), replication_test_season = REP_TEST_SEASON,
              team_games_2012_2025 = sum(IN_HIST), team_games_without_pbp = sum(!H$pbp_found),
              offseason_methods = list(reset = "windows start fresh each season; fewer than k games that season = no value",
                                       mean_regress = sprintf("carried games pulled toward their season's league average: value -> avg + %.2f^(seasons back) x (value - avg)", REGRESS_KEEP),
                                       decay = sprintf("carried games keep their value with weight %.2f^(seasons back) in the window mean; current-season games weigh 1", DECAY_BASE),
                                       season_to_date = "mean of earlier games this season; under mean_regress/decay the first game uses the previous season (regressed / equal weights)"),
              opponent_adjustment = "game value minus the opponent's mean over its earlier games this season (its whole previous season before its first game)",
              elo = "production walk-forward (tools/elo_model.R, ELO_K_FACTOR), every completed game from 2002, pregame ratings; expected margin = (Elo - opp Elo + 48 x home sign) / 25"),
  row_counts = COUNTS_DF,
  stronger_arm = list(table = B_TABLE, selections = SELECT_DF, carry_methods_on_rows_reset_cannot_score = METHOD_EARLY,
                      selection_rule = "shortest window (1..17, season-to-date treated as longest) whose point score lies inside the 95% team-season block bootstrap interval of the best window's score"),
  replication_arm = list(results = REP, best = REP_BEST, test_season = REP_TEST_SEASON, trees = 300,
                         predictors_levels_kept = setdiff(names(REP_STATS), REP_LEVELS_REMOVED), predictors_diff = c(names(REP_STATS), "totyds", "days_rest")),
  weights = list(grid = "0.05 steps, 4 weights summing to 1 (1771 weightings)", components = c("form", "trend", "residual", "elo_change"),
                 standardisation = sprintf("z-score across teams within each season-week (at least %d teams)", MIN_Z_TEAMS),
                 score = "pooled held-out (LOSO) R^2 of margin beyond Elo from a one-variable linear map of the combined score fitted on training seasons",
                 table = WEIGHTS_DF, detail = unname(WEIGHTS)),
  flags = list(note = "SIMULATED detection rates: a methods check, not published data",
               definitions = lapply(FLAGS, function(f) f[setdiff(names(f), "type")]), detection = FLAG_DF,
               std_typical_games = STD_TYPICAL, power_threshold = DETECT_POWER),
  availability = list(coverage = COV_TABLE, fully_covered_from = AVAIL_FROM, pipeline_injury_cache = PIPE_INJ, pipeline_snap_cache = PIPE_SNP,
                      key_players = KEY_INFO, covered_threshold = COVER_MIN))
saveRDS(RESULTS, file.path(CACHE_DIR, "rolling_window_study_results.rds"))
dir.create(file.path(STUDY_ROOT, "docs", "research"), showWarnings = FALSE, recursive = TRUE)
writeLines(jsonlite::toJSON(RESULTS, auto_unbox = TRUE, digits = 6, pretty = TRUE, na = "null", dataframe = "rows"),
           file.path(STUDY_ROOT, "docs", "research", "rolling_window_study_results.json"))

# report tables (markdown)
md <- character(0); add <- function(...) md <<- c(md, ...)
fmt <- function(x, d = 4) ifelse(is.na(x), "-", formatC(x, format = "f", digits = d))
for (fn in names(FEATURES_B)) for (tg in B_TARGETS) {
  add(sprintf("\n### Arm B: %s, %s", fn, tg), "", "| Window | reset | mean_regress | decay |", "|---|---|---|---|")
  for (w in WINDOWS) {
    cell <- function(m) { r <- B_TABLE[B_TABLE$feature == fn & B_TABLE$method == m & B_TABLE$window == w & B_TABLE$target == tg, ]
      if (is.na(r$score)) "-" else sprintf("%s [%s, %s] n=%d", fmt(r$score), fmt(r$lo), fmt(r$hi), r$n) }
    add(sprintf("| %s | %s | %s | %s |", w, cell("reset"), cell("mean_regress"), cell("decay")))
  }
}
writeLines(md, file.path(CACHE_DIR, "rolling_window_study_tables.md"))
say("Saved results; runtime %.1f minutes", runtime)
cat("RWS_DONE\n")
