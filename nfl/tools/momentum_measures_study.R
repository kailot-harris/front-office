# ==============================================================================
# tools/momentum_measures_study.R - does team momentum predict how an NFL team
# plays over its next game and next 3 games, beyond team strength (Elo)?
# Research only (issue #220); NOT part of the pipeline and not sourced by it.
#
# 11 momentum measures x 11 team stat series = 121 features. Each is scored on
# what it adds, on seasons it never saw, to a baseline of the team's Elo after
# its latest game plus its season-to-date point margin per game:
#   1. single-feature screening (team-season block-bootstrap 95% CI,
#      Benjamini-Hochberg false discovery rate),
#   2. redundancy families (correlation clusters across measures and series),
#   3. a nested small-combination search (top 6 series x top 6 measures ranked on
#      training seasons only -> C(6,3)^2 = 400 combinations of 3 series x 3
#      measures, ridge regression, chosen by inner leave-one-season-out),
#      compared with an elastic net over all 121 and greedy forward selection,
#   4. a permutation baseline (targets shuffled among teams within each date,
#      the whole nested search rerun each time),
#   5. selection stability,
#   6. the QB-change, bye and week-18 flags as their own rows,
#   7. sensitivity runs: without 2020 (no crowds) and with windows that span the
#      previous season's last games.
# The protocol and the measure code are reused from the NBA momentum study
# (NBA_analytics, tools/momentum_measures_study.R); windows, series and targets
# are adapted to the NFL as agreed in issue #220.
#
# Protocol: leave-one-season-out (LOSO) over the regular seasons 2012-2025,
# pooled out-of-fold predictions, paired bootstrap with 2,000 resamples of whole
# team-seasons (next-3 targets overlap from game to game, so rows are not
# independent). 2026 to date is a forward test, scored ONCE (section 10), after
# every choice is fixed, and only when MOMENTUM_STUDY_SCORE_HOLDOUT=1 (the final
# run). Test runs never score it.
#
# NO LOOK-AHEAD: every feature for a team after its game k uses only games 1..k;
# cross-team z-scores on date d use each team's latest state on or before d; the
# targets use only games k+1 .. k+h. Fitted parameters (Kalman variances, ridge
# and regression coefficients, series/measure rankings, selections) come from
# training seasons only. NO IMPUTATION: missing values stay missing and are
# counted per feature.
#
# Data: nflreadr play-by-play and schedules cached as
#   cache/momentum_study_pbp_<season>.rds (2011-2026; 2011 only seeds the
#   cross-season sensitivity run) and cache/momentum_study_schedules.rds
#   (2002-2026; Elo runs from 2002 like the production rating).
#   Missing cache files are downloaded with nflreadr::load_pbp()/load_schedules().
#
# Output: cache/momentum_measures_study_results.rds,
#         docs/research/momentum_measures_study_results.json,
#         cache/momentum_measures_study_tables.md (tables for the report).
# Run:  Rscript tools/momentum_measures_study.R
#       MOMENTUM_STUDY_N_PERM / MOMENTUM_STUDY_N_BOOT override the run sizes for a
#       smoke test only (the published run uses 200 / 2000);
#       MOMENTUM_STUDY_SCORE_HOLDOUT=1 is set ONLY for the final run.
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
    if (identical(parent, root)) stop("momentum_measures_study.R: cannot find config.R at or above ", start)
    root <- parent
  }
  normalizePath(root, winslash = "/")
})
setwd(STUDY_ROOT)   # config.R resolves PROJECT_DIR / CACHE_DIR from the working directory

suppressPackageStartupMessages({ library(dplyr); library(jsonlite); library(glmnet) })
source(file.path(STUDY_ROOT, "config.R"))
source(file.path(STUDY_ROOT, "tools", "elo_model.R"))   # run_elo_walkforward() and its constants

t_start <- Sys.time()
elapsed <- function() as.numeric(difftime(Sys.time(), t_start, units = "mins"))
say <- function(...) cat(sprintf("[%5.1f min] ", elapsed()), sprintf(...), "\n", sep = "")

# ------------------------------------------------------------------------------
# 0. Settings (every window is stated in the report)
# ------------------------------------------------------------------------------
STUDY_SEED <- 20261124L
N_BOOT <- as.integer(Sys.getenv("MOMENTUM_STUDY_N_BOOT", "2000"))
N_PERM <- as.integer(Sys.getenv("MOMENTUM_STUDY_N_PERM", "200"))
SCORE_HOLDOUT <- identical(Sys.getenv("MOMENTUM_STUDY_SCORE_HOLDOUT", ""), "1")   # final run only
HIST_SEASONS <- 2012:2025
FLAGGED_SEASONS <- 2020L          # no crowds
SENS_SEASONS <- setdiff(HIST_SEASONS, FLAGGED_SEASONS)
HOLDOUT_SEASON <- CURRENT_SEASON  # 2026: forward test, scored once
SEED_SEASON <- min(HIST_SEASONS) - 1L   # 2011: only feeds the cross-season sensitivity windows
ELO_FIRST_SEASON <- MODERN_ERA_START_SEASON   # Elo runs from 2002, as in production

# Windows scaled to a 17-game season (NBA study: short 5 / long 10, EWMA spans 5 and 15).
MIN_GAMES <- 3L        # warm-up: no measure until a team has 3 values of the series that season
SHORT_W <- 3L          # ROC, Z-score numerator, acceleration lag, growth halves
LONG_W <- 6L           # velocity fit, RSI
EWMA_FAST <- 2L        # MACD fast span, EWMA of changes
EWMA_SLOW <- 6L        # MACD slow span
ROC_BASE_MIN <- SHORT_W   # box-series ROC needs at least this many games before the last SHORT_W
IMPULSE_DECAY <- 0.75  # half-life about 2.4 games (NBA: 0.85, half-life about 4.3 of 82 games)
BYE_DAYS <- 10L        # previous game more than 10 days earlier within the season = coming off a bye
MIN_Z_TEAMS <- 10L     # a date's cross-team z needs this many teams with the value
RIDGE_ALPHAS <- c(0.01, 0.1, 1)   # ridge penalty = alpha x training rows (features are unit-scale z)
TOP_K <- 6L
FDR_Q <- 0.05
STABLE_SHARE <- 0.5
HOLDOUT_MIN_ROWS <- 20L
season_name <- function(s) as.character(s)

SERIES <- c(elo = "Elo rating", margin = "Point margin (opponent-adjusted)",
            off_epa = "Offensive EPA/play", def_epa = "Defensive EPA/play allowed",
            off_sr = "Offensive success rate", def_sr = "Defensive success rate allowed",
            pass_epa = "Pass EPA/play (offense)", rush_epa = "Rush EPA/play (offense)",
            pass_epa_def = "Pass EPA/play allowed", rush_epa_def = "Rush EPA/play allowed",
            tom = "Turnover margin")
MEASURES <- c(roc3 = "ROC-3", macd = "MACD", velocity = "Velocity", acceleration = "Acceleration",
              ewma_change = "EWMA of changes", zscore = "Z-score", rsi = "RSI", growth = "Growth difference",
              kalman = "Kalman slope", streak = "Streak", impulse = "Impulse")
FEATURES <- as.vector(t(outer(names(SERIES), names(MEASURES), paste, sep = "__")))
FEAT_SERIES <- rep(names(SERIES), each = length(MEASURES))
FEAT_MEASURE <- rep(names(MEASURES), times = length(SERIES))
KCOL <- which(FEAT_MEASURE == "kalman")
NF <- length(FEATURES)
stopifnot(NF == 121L)

TARGETS <- data.frame(
  id = c("margin3_beyond_elo", "next_margin_beyond_elo", "next_game_win"),
  definition = c(
    sprintf("Mean over the team's next 3 games of (point margin minus the margin Elo expected). The expectation is the opponent adjustment: it uses the team's Elo after game k, the opponent's pregame Elo and home field, (Elo - opp Elo + %d x home sign) / %d points (tools/elo_model.R constants).", ELO_HCA_POINTS, ELO_POINTS_PER_MARGIN_PT),
    "Same for the team's next game only.",
    "Next game won by the home team (one row per game; ties left out and counted), logistic model on the pregame Elo difference with home field plus the season-to-date margin-per-game difference; scored by log loss and ROC-AUC."),
  primary = c(TRUE, FALSE, FALSE),
  kind = c("continuous", "continuous", "binary"), stringsAsFactors = FALSE)
CONT_TARGETS <- TARGETS$id[TARGETS$kind == "continuous"]
PRIMARY <- "margin3_beyond_elo"
TARGET_H <- c(margin3_beyond_elo = 3L, next_margin_beyond_elo = 1L)

# ------------------------------------------------------------------------------
# 1. Data: nflreadr play-by-play and schedules (cached under cache/)
# ------------------------------------------------------------------------------
PBP_COLS <- c("game_id", "season", "week", "season_type", "game_date", "home_team", "away_team", "posteam", "defteam",
              "play_type", "pass", "rush", "qb_dropback", "passer_player_id", "passer_player_name", "rusher_player_id",
              "rusher_player_name", "epa", "success", "interception", "fumble_lost", "fumbled_1_team")
pbp_path <- function(s) file.path(CACHE_DIR, sprintf("momentum_study_pbp_%d.rds", s))
SCHED_PATH <- file.path(CACHE_DIR, "momentum_study_schedules.rds")
for (s in SEED_SEASON:HOLDOUT_SEASON) if (!file.exists(pbp_path(s))) {
  say("Downloading play-by-play %d with nflreadr", s)
  p <- as.data.frame(nflreadr::load_pbp(s)); saveRDS(p[, PBP_COLS], pbp_path(s))
}
if (!file.exists(SCHED_PATH)) {
  say("Downloading schedules %d-%d with nflreadr", ELO_FIRST_SEASON, HOLDOUT_SEASON)
  saveRDS(as.data.frame(nflreadr::load_schedules(ELO_FIRST_SEASON:HOLDOUT_SEASON)), SCHED_PATH)
}
# Franchise keys: schedules use the abbreviation of the time (OAK, SD, STL); the
# play-by-play uses today's. The study keys every franchise by today's abbreviation.
FRANCHISE <- c(OAK = "LV", SD = "LAC", STL = "LA")
canon <- function(x) ifelse(x %in% names(FRANCHISE), FRANCHISE[x], x)

SCHED <- as.data.frame(readRDS(SCHED_PATH), stringsAsFactors = FALSE)
SCHED$home_team <- canon(SCHED$home_team); SCHED$away_team <- canon(SCHED$away_team)
SCHED$gameday <- as.Date(SCHED$gameday)
COMPLETED <- SCHED[!is.na(SCHED$home_score) & !is.na(SCHED$away_score) &
                     SCHED$season >= ELO_FIRST_SEASON & SCHED$season <= HOLDOUT_SEASON, , drop = FALSE]

# Elo: the production walk-forward (tools/elo_model.R, K = ELO_K_FACTOR), every
# completed game from 2002 (regular season and playoffs), PRE-game ratings only.
# The fatigue table is empty: fatigue enters only the final probability, never the
# rating update. The post-game rating (needed for the Elo series and as "Elo after
# game k") is the pre-game rating plus the same update the walk-forward applies;
# within a season it is checked against the team's next pre-game rating.
say("Running the production Elo walk-forward on %d completed games (%d-%d)", nrow(COMPLETED), ELO_FIRST_SEASON, HOLDOUT_SEASON)
ELO <- run_elo_walkforward(COMPLETED, data.frame(game_id = character(0), team = character(0), fatigue_drag_pts = numeric(0)), ELO_K_FACTOR)
ELO <- merge(ELO, COMPLETED[, c("game_id", "home_score", "away_score", "gameday", "game_type")], by = "game_id")
local({
  ed <- (ELO$home_elo_pre + ELO_HCA_POINTS) - ELO$away_elo_pre
  y <- ifelse(ELO$home_score == ELO$away_score, 0.5, as.numeric(ELO$home_score > ELO$away_score))
  wd <- ifelse(ELO$home_score > ELO$away_score, ed, -ed)
  mult <- log(pmax(abs(ELO$home_score - ELO$away_score), 1) + 1) * (ELO_MOV_C / (0.001 * wd + ELO_MOV_C))
  shift <- ELO_K_FACTOR * mult * (y - ELO$elo_prob_pure)
  ELO$home_elo_post <<- ELO$home_elo_pre + shift; ELO$away_elo_post <<- ELO$away_elo_pre - shift
})

# Per game x team play-by-play aggregates (regular season). Team EPA/play and
# success rate follow epa_metrics_engine.R (every play with posteam, defteam and
# EPA); pass and rush EPA use pass == 1 / rush == 1 plays. Turnovers: interceptions
# thrown plus fumbles lost (charged to the fumbling team). The starting QB is the
# passer with the most dropbacks (passer id, or the rusher id on scrambles).
pbp_team_game <- function(s) {
  p <- as.data.frame(readRDS(pbp_path(s)), stringsAsFactors = FALSE)
  p <- p[p$season_type == "REG", , drop = FALSE]
  side_of <- function(tm) ifelse(tm == p$home_team, "home", ifelse(tm == p$away_team, "away", NA_character_))
  p$off_side <- side_of(p$posteam)
  e <- p[!is.na(p$posteam) & !is.na(p$defteam) & !is.na(p$epa) & !is.na(p$off_side), , drop = FALSE]
  key <- paste(e$game_id, e$off_side)
  agg <- function(v, w) { v <- ifelse(rep_len(w, length(v)), v, NA_real_); r <- tapply(v, key, function(z) if (all(is.na(z))) NA_real_ else mean(z, na.rm = TRUE)); r }
  out <- data.frame(key = names(agg(e$epa, TRUE)), stringsAsFactors = FALSE)
  out$off_epa <- as.numeric(agg(e$epa, TRUE)[out$key])
  out$off_sr <- as.numeric(agg(e$success, TRUE)[out$key])
  out$pass_epa <- as.numeric(agg(e$epa, e$pass %in% 1)[out$key])
  out$rush_epa <- as.numeric(agg(e$epa, e$rush %in% 1)[out$key])
  # giveaways
  fum_side <- side_of(ifelse(is.na(p$fumbled_1_team), p$posteam, p$fumbled_1_team))
  gv_int <- tapply(p$interception %in% 1 & !is.na(p$off_side), paste(p$game_id, p$off_side), sum)
  fl <- p$fumble_lost %in% 1 & !is.na(fum_side)
  gv_fum <- tapply(fl, paste(p$game_id, fum_side), sum)
  out$giveaways <- as.numeric(ifelse(is.na(gv_int[out$key]), 0, gv_int[out$key])) + as.numeric(ifelse(is.na(gv_fum[out$key]), 0, gv_fum[out$key]))
  # starting QB
  d <- p[p$qb_dropback %in% 1 & !is.na(p$off_side), , drop = FALSE]
  d$qb_id <- ifelse(is.na(d$passer_player_id), d$rusher_player_id, d$passer_player_id)
  d$qb_name <- ifelse(is.na(d$passer_player_id), d$rusher_player_name, d$passer_player_name)
  d <- d[!is.na(d$qb_id), , drop = FALSE]
  cnt <- aggregate(list(n = rep(1L, nrow(d))), list(key = paste(d$game_id, d$off_side), qb_id = d$qb_id), sum)
  cnt <- cnt[order(cnt$key, -cnt$n, cnt$qb_id), ]; cnt <- cnt[!duplicated(cnt$key), ]
  nm <- d[!duplicated(d$qb_id), c("qb_id", "qb_name")]
  out$qb_id <- cnt$qb_id[match(out$key, cnt$key)]
  out$qb_name <- nm$qb_name[match(out$qb_id, nm$qb_id)]
  out$qb_dropbacks <- cnt$n[match(out$key, cnt$key)]
  out
}

build_season <- function(s) {
  g <- SCHED[SCHED$season == s & SCHED$game_type == "REG" & !is.na(SCHED$home_score) & !is.na(SCHED$away_score), , drop = FALSE]
  mk <- function(side) {
    home <- side == "home"
    data.frame(season = s, game_id = g$game_id, game_date = g$gameday, week = g$week, side = side,
               team = if (home) g$home_team else g$away_team, opp = if (home) g$away_team else g$home_team,
               home = home, neutral = g$location == "Neutral",
               pts = if (home) g$home_score else g$away_score, opp_pts = if (home) g$away_score else g$home_score,
               stringsAsFactors = FALSE)
  }
  p <- rbind(mk("home"), mk("away"))
  p$margin <- p$pts - p$opp_pts
  p$win <- ifelse(p$margin > 0, 1, ifelse(p$margin < 0, 0, 0.5))
  e <- ELO[match(p$game_id, ELO$game_id), ]
  p$elo_pre <- ifelse(p$home, e$home_elo_pre, e$away_elo_pre); p$opp_elo_pre <- ifelse(p$home, e$away_elo_pre, e$home_elo_pre)
  p$elo_post <- ifelse(p$home, e$home_elo_post, e$away_elo_post)
  pb <- pbp_team_game(s)
  me <- match(paste(p$game_id, p$side), pb$key); op <- match(paste(p$game_id, ifelse(p$home, "away", "home")), pb$key)
  p$off_epa <- pb$off_epa[me]; p$def_epa <- pb$off_epa[op]
  p$off_sr <- pb$off_sr[me]; p$def_sr <- pb$off_sr[op]
  p$pass_epa <- pb$pass_epa[me]; p$rush_epa <- pb$rush_epa[me]
  p$pass_epa_def <- pb$pass_epa[op]; p$rush_epa_def <- pb$rush_epa[op]
  p$tom <- pb$giveaways[op] - pb$giveaways[me]
  p$qb_id <- pb$qb_id[me]; p$qb_name <- pb$qb_name[me]; p$qb_dropbacks <- pb$qb_dropbacks[me]
  p$pbp_found <- !is.na(me)
  p <- p[order(p$team, p$game_date, p$game_id), , drop = FALSE]
  p$game_index <- ave(seq_len(nrow(p)), p$team, FUN = seq_along)
  prev_date <- ave(as.numeric(p$game_date), p$team, FUN = function(v) c(NA, v[-length(v)]))
  p$bye <- !is.na(prev_date) & (as.numeric(p$game_date) - prev_date) > BYE_DAYS
  prev_qb <- ave(p$qb_id, p$team, FUN = function(v) c(NA, v[-length(v)]))
  p$qb_change <- ifelse(is.na(prev_qb) | is.na(p$qb_id), NA, p$qb_id != prev_qb)
  p$week18 <- p$week == 18L
  p$final_week <- p$week == max(SCHED$week[SCHED$season == s & SCHED$game_type == "REG"])
  rownames(p) <- NULL
  p
}

say("Building team-game panels %d-%d", SEED_SEASON, HOLDOUT_SEASON)
PANELS <- list()
for (s in SEED_SEASON:HOLDOUT_SEASON) PANELS[[as.character(s)]] <- build_season(s)

# Elo consistency check: within a season, Elo after game k equals the pre-game Elo of game k+1.
elo_gap <- unlist(lapply(PANELS, function(p) {
  nx <- ave(p$elo_pre, p$team, FUN = function(v) c(v[-1], NA)); abs(nx - p$elo_post)
}))
stopifnot(max(elo_gap, na.rm = TRUE) < 1e-6)
pbp_missing <- sum(!unlist(lapply(PANELS, `[[`, "pbp_found")))
cat(sprintf("    Elo post-game check: max |Elo after k - pregame Elo k+1| = %.2e; team-games without play-by-play: %d\n",
            max(elo_gap, na.rm = TRUE), pbp_missing))

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
SERIES_DEF <- list(margin = c("margin", "neg_margin", "for"),
                   off_epa = c("off_epa", "def_epa", "for"), def_epa = c("off_epa", "def_epa", "against"),
                   off_sr = c("off_sr", "def_sr", "for"), def_sr = c("off_sr", "def_sr", "against"),
                   pass_epa = c("pass_epa", "pass_epa_def", "for"), rush_epa = c("rush_epa", "rush_epa_def", "for"),
                   pass_epa_def = c("pass_epa", "pass_epa_def", "against"), rush_epa_def = c("rush_epa", "rush_epa_def", "against"),
                   tom = c("tom", "neg_tom", "for"))

season_rows <- function(p) {
  p$neg_margin <- -p$margin; p$neg_tom <- -p$tom
  p$home_sign <- ifelse(p$home, 1, -1)   # production Elo gives the listed home team home field at every site
  oi <- match(paste(p$game_id, p$opp), paste(p$game_id, p$team))
  out <- data.frame(season = p$season, team = p$team, game_id = p$game_id, game_date = p$game_date, week = p$week,
                    k = p$game_index, win = p$win, home = p$home, neutral = p$neutral, opp = p$opp,
                    elo_pre = p$elo_pre, elo_post = p$elo_post, opp_elo_pre = p$opp_elo_pre,
                    margin = p$margin, home_sign = p$home_sign, qb_id = p$qb_id, qb_name = p$qb_name,
                    qb_change = p$qb_change, bye = p$bye, week18 = p$week18, final_week = p$final_week,
                    stringsAsFactors = FALSE)
  out$s_elo <- p$elo_post
  for (nm in names(SERIES_DEF)) {
    d <- SERIES_DEF[[nm]]
    if (d[3] == "for") out[[paste0("s_", nm)]] <- p[[d[1]]] - prior_mean_by_team(p[[d[2]]], p$team)[oi]
    else out[[paste0("s_", nm)]] <- p[[d[2]]] - prior_mean_by_team(p[[d[1]]], p$team)[oi]
  }
  # Baseline covariates known after game k: Elo after game k (= pregame Elo for k+1)
  # and season-to-date point margin per game through game k.
  out$elo_c <- p$elo_post - ELO_INITIAL_RATING
  out$snet <- ave(p$margin, p$team, FUN = cumsum) / p$game_index
  # Targets: games k+1 .. k+h only.
  for (h in c(1L, 3L)) {
    acc_m <- 0
    for (i in seq_len(h)) {
      m <- lead_in_team(p$margin, p$team, i); oe <- lead_in_team(p$opp_elo_pre, p$team, i)
      hs <- lead_in_team(p$home_sign, p$team, i)
      d <- p$elo_post - oe + hs * ELO_HCA_POINTS
      acc_m <- acc_m + m - d / ELO_POINTS_PER_MARGIN_PT
    }
    out[[if (h == 1L) "next_margin_beyond_elo" else "margin3_beyond_elo"]] <- acc_m / h
  }
  # Flags for the target window (schedule facts known before the games; the QB
  # change is the latest game's, known after game k).
  for (h in c(1L, 3L)) {
    by <- 0; wk <- 0; fw <- 0; qc <- 0; nn <- 0
    for (i in seq_len(h)) {
      by <- by + lead_in_team(as.numeric(p$bye), p$team, i); wk <- wk + lead_in_team(as.numeric(p$week18), p$team, i)
      fw <- fw + lead_in_team(as.numeric(p$final_week), p$team, i); qc <- qc + lead_in_team(as.numeric(p$qb_change), p$team, i)
    }
    out[[sprintf("bye_w%d", h)]] <- as.numeric(by > 0); out[[sprintf("week18_w%d", h)]] <- as.numeric(wk > 0)
    out[[sprintf("final_week_w%d", h)]] <- as.numeric(fw > 0); out[[sprintf("qb_change_in_w%d", h)]] <- as.numeric(qc > 0)
  }
  out$qb_change_last <- as.numeric(p$qb_change)
  out
}
TG <- do.call(rbind, lapply(PANELS, season_rows)); rownames(TG) <- NULL
stopifnot(!anyDuplicated(paste(TG$season, TG$game_id, TG$team)))   # one row per team per game
TG$block <- paste(TG$season, TG$team)
NTG <- nrow(TG)

# Next-game rows: one per game (the listed home team); features come from the
# cross-section of the previous league date.
NG <- do.call(rbind, lapply(PANELS, function(p) {
  g <- p[p$home, , drop = FALSE]
  dates <- sort(unique(p$game_date)); pos <- match(g$game_date, dates)
  oi <- match(paste(g$game_id, g$opp), paste(p$game_id, p$team))
  data.frame(season = g$season, game_id = g$game_id, game_date = g$game_date, week = g$week,
             prev_date = as.Date(ifelse(pos > 1L, as.character(dates[pmax(pos - 1L, 1L)]), NA_character_)),
             home = g$team, away = g$opp, home_win = ifelse(g$margin == 0, NA_real_, as.numeric(g$margin > 0)),
             elo_diff = g$elo_pre - g$opp_elo_pre + ELO_HCA_POINTS,
             bye_diff = as.numeric(g$bye) - as.numeric(p$bye[oi]), week18 = as.numeric(g$week18), final_week = as.numeric(g$final_week),
             stringsAsFactors = FALSE)
}))
rownames(NG) <- NULL
NG$block <- paste(NG$season, NG$home)
stopifnot(all(is.na(NG$prev_date) | NG$prev_date < NG$game_date))   # look-ahead guard

season_table <- do.call(rbind, lapply(PANELS, function(p) data.frame(
  season = season_name(p$season[1]),
  role = if (p$season[1] == HOLDOUT_SEASON) "forward test (in progress; scored once)" else if (p$season[1] == SEED_SEASON) "seed for the cross-season windows only"
         else if (p$season[1] %in% FLAGGED_SEASONS) "LOSO (flagged; dropped in sensitivity run)" else "LOSO",
  games = length(unique(p$game_id)), team_games = nrow(p), teams = length(unique(p$team)),
  first = format(min(p$game_date)), last = format(max(p$game_date)), last_week = max(p$week),
  ties = length(unique(p$game_id[p$margin == 0])), neutral_games = length(unique(p$game_id[p$neutral])),
  qb_changes = sum(p$qb_change %in% TRUE), byes = sum(p$bye), stringsAsFactors = FALSE)))
rownames(season_table) <- NULL
cat("\n>>> Seasons\n"); print(season_table, row.names = FALSE)
cat(sprintf("    Historical team-games 2012-2025: %d\n", sum(season_table$team_games[season_table$season %in% HIST_SEASONS])))

# ------------------------------------------------------------------------------
# 3. The 11 measures, forward-only (each value after game k uses games 1..k)
# ------------------------------------------------------------------------------
ewma_vec <- function(x, span) {
  a <- 2 / (span + 1); out <- x; n <- length(x)
  if (n > 1) for (i in 2:n) out[i] <- a * x[i] + (1 - a) * out[i - 1L]
  out
}
trail <- function(x, f) if (length(x) < length(f)) rep(NA_real_, length(x)) else as.numeric(stats::filter(x, f, sides = 1))   # trailing window only
lagn <- function(x, L) { n <- length(x); if (L >= n) rep(NA_real_, n) else c(rep(NA_real_, L), x[seq_len(n - L)]) }
VEL_W <- seq_len(LONG_W) - (LONG_W + 1) / 2

# v: the team's series in game order (missing games removed); for Elo the level is
# the post-game rating and the "change" the per-game Elo change (post - pre); for a
# box series the "change" is the surprise: game value minus the team's own mean of
# its EARLIER values. sgn: game result sign (Elo streak).
compute_measures <- function(v, is_elo, elo_pre = NULL, sgn = NULL) {
  n <- length(v)
  out <- matrix(NA_real_, n, length(MEASURES), dimnames = list(NULL, names(MEASURES)))
  if (n < MIN_GAMES) return(out)
  k <- seq_len(n)
  if (is_elo) { chg <- v - elo_pre }
  else { chg <- v - c(NA_real_, cumsum(v)[-n] / seq_len(n - 1L)) }
  # ROC-3: Elo = (Elo after game k - Elo before game k-2) / 3; box = mean of the last
  # 3 values minus the mean of the team's values before them (at least 3 earlier).
  if (is_elo) { L <- c(elo_pre[1], v); roc <- (L[k + 1L] - L[pmax(k - SHORT_W, 0L) + 1L]) / SHORT_W; roc[k < SHORT_W] <- NA_real_ }
  else {
    cs <- cumsum(v); nb <- k - SHORT_W
    roc <- trail(v, rep(1 / SHORT_W, SHORT_W)) - ifelse(nb >= ROC_BASE_MIN, cs[pmax(nb, 1L)] / pmax(nb, 1L), NA_real_)
  }
  out[, "roc3"] <- roc
  out[, "macd"] <- ewma_vec(v, EWMA_FAST) - ewma_vec(v, EWMA_SLOW)        # recursive, one-sided
  # Velocity: slope of a least-squares line through the trailing 6 values (not a
  # whole-season smoother); acceleration: velocity now minus 3 values earlier.
  vel <- trail(v, rev(VEL_W) / sum(VEL_W^2))
  out[, "velocity"] <- vel
  out[, "acceleration"] <- vel - lagn(vel, SHORT_W)
  s0 <- if (is_elo) 1L else 2L
  ew <- rep(NA_real_, n); ew[s0:n] <- ewma_vec(chg[s0:n], EWMA_FAST); out[, "ewma_change"] <- ew
  # Z-score: ROC-3 / sd of the team's changes in games 1..k only (expanding window).
  ok <- !is.na(chg); m <- cumsum(ok); s1 <- cumsum(ifelse(ok, chg, 0)); s2 <- cumsum(ifelse(ok, chg^2, 0))
  sdc <- sqrt(pmax((s2 - s1^2 / m) / (m - 1), 0)); sdc[m < 2] <- NA_real_
  out[, "zscore"] <- ifelse(!is.na(sdc) & sdc > 0, roc / sdc, NA_real_)
  G <- trail(pmax(chg, 0), rep(1 / LONG_W, LONG_W)); Lo <- trail(pmax(-chg, 0), rep(1 / LONG_W, LONG_W))
  out[, "rsi"] <- ifelse(G + Lo > 0, 100 * G / (G + Lo), NA_real_)
  sw <- trail(chg, rep(1, SHORT_W))
  out[, "growth"] <- sw - lagn(sw, SHORT_W)                                # difference, not the unstable ratio
  sg <- if (is_elo) sgn else ifelse(is.na(chg), 0, sign(chg))
  st <- numeric(n); st[1] <- sg[1]
  if (n > 1) for (i in 2:n) st[i] <- if (sg[i] == 0) 0 else if (sign(st[i - 1L]) == sg[i]) st[i - 1L] + sg[i] else sg[i]
  out[, "streak"] <- st
  mm <- numeric(n); acc <- 0
  for (i in k) { acc <- IMPULSE_DECAY * acc + ifelse(is.na(chg[i]), 0, chg[i]); mm[i] <- acc }
  out[, "impulse"] <- mm
  out[k < MIN_GAMES, ] <- NA_real_
  out
}

# Feature sets. "main": windows restart every season (issue #220). "cross": the
# sensitivity run - each team-season's series is preceded by the same franchise's
# last LONG_W values of the previous regular season, so windows span the season
# break; values are kept only for the current season's rows.
TG_ORDER <- order(TG$block, TG$k)
build_features <- function(cross) {
  FR <- matrix(NA_real_, NTG, NF, dimnames = list(NULL, FEATURES)); UNITS <- list()
  blocks <- split(TG_ORDER, TG$block[TG_ORDER])
  for (sn in names(SERIES)) {
    col <- paste0("s_", sn); units <- list()
    for (b in names(blocks)) {
      r <- blocks[[b]]
      v <- TG[[col]][r]; keep <- !is.na(v); rr <- r[keep]
      if (!length(rr)) next
      vals <- v[keep]; pre <- TG$elo_pre[rr]; sg <- sign(TG$margin[rr]); npre <- 0L; pre_season <- NA_integer_
      if (cross) {
        pb <- paste(TG$season[rr[1]] - 1L, TG$team[rr[1]])
        if (!is.null(blocks[[pb]])) {
          q <- blocks[[pb]]; q <- q[!is.na(TG[[col]][q])]; q <- utils::tail(q, LONG_W)
          npre <- length(q); pre_season <- TG$season[rr[1]] - 1L
          vals <- c(TG[[col]][q], vals); pre <- c(TG$elo_pre[q], pre); sg <- c(sign(TG$margin[q]), sg)
        }
      }
      M <- compute_measures(vals, sn == "elo", elo_pre = pre, sgn = sg)
      FR[rr, paste(sn, colnames(M), sep = "__")] <- M[npre + seq_along(rr), , drop = FALSE]
      units[[b]] <- list(season = TG$season[rr[1]], pre_season = pre_season, rows = rr, vals = vals, npre = npre)
    }
    UNITS[[sn]] <- units
  }
  list(FR = FR, UNITS = UNITS)
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
kalman_version <- function(UNITS, train_seasons) {
  K <- matrix(NA_real_, NTG, length(SERIES), dimnames = list(NULL, FEATURES[KCOL])); pars <- list()
  for (si in seq_along(SERIES)) {
    units <- UNITS[[names(SERIES)[si]]]
    units <- units[vapply(units, function(u) length(u$vals) >= 2L, logical(1))]
    # training units: current season AND any prepended season are training seasons
    tr <- units[vapply(units, function(u) u$season %in% train_seasons && (is.na(u$pre_season) || u$pre_season %in% train_seasons), logical(1))]
    allv <- unlist(lapply(tr, `[[`, "vals")); mu <- mean(allv); sdv <- stats::sd(allv)
    Ytr <- (unit_matrix(tr) - mu) / sdv
    fit <- stats::optim(c(log(0.5), log(0.05), log(0.001)), function(lp) kalman_run(Ytr, lp),
                        method = "Nelder-Mead", control = list(maxit = 400))
    S <- kalman_run((unit_matrix(units) - mu) / sdv, fit$par, slope = TRUE) * sdv
    for (i in seq_along(units)) {
      u <- units[[i]]; pos <- u$npre + seq_along(u$rows); sl <- S[i, pos]; sl[pos < MIN_GAMES] <- NA_real_
      K[u$rows, si] <- sl
    }
    pars[[names(SERIES)[si]]] <- c(obs_var = exp(fit$par[1]), level_var = exp(fit$par[2]), slope_var = exp(fit$par[3]),
                                   scale_sd = sdv, converged = fit$convergence == 0)
  }
  list(K = K, pars = pars)
}

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
NG$qb_change_diff <- TG$qb_change_last[NG$h_row] - TG$qb_change_last[NG$a_row]

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

make_feature_set <- function(cross, label) {
  say("Computing 121 features (%s; Kalman slopes are fitted per fold below)", label)
  bf <- build_features(cross)
  say("  fitting Kalman variances per fold (training seasons only)")
  KV <- list()
  for (s in HIST_SEASONS) KV[[as.character(s)]] <- kalman_version(bf$UNITS, setdiff(HIST_SEASONS, s))
  KV[["full"]] <- kalman_version(bf$UNITS, HIST_SEASONS)
  say("  cross-team z-scores")
  zb <- zdate(bf$FR, MIN_Z_TEAMS)
  list(label = label, ZB = zb$Z, ZBN = zb$ZN, ZK = lapply(KV, function(v) zdate(v$K, MIN_Z_TEAMS)),
       pars = lapply(KV, `[[`, "pars"))
}
FSETS <- list(main = make_feature_set(FALSE, "windows restart each season"))
CUR <- "main"
getZ <- function(key) { f <- FSETS[[CUR]]; Z <- f$ZB; Z[, KCOL] <- f$ZK[[key]]$Z; Z }
getZN <- function(key) { f <- FSETS[[CUR]]; Z <- f$ZBN; Z[, KCOL] <- f$ZK[[key]]$ZN; Z }

# Feature count and missing counts (historical team-game rows).
hist_rows <- TG$season %in% HIST_SEASONS
Zfull <- getZ("full")
feat_missing <- data.frame(feature = FEATURES, series = FEAT_SERIES, measure = FEAT_MEASURE,
                           present = colSums(!is.na(Zfull[hist_rows, ])), missing = colSums(is.na(Zfull[hist_rows, ])),
                           missing_with_primary_target = colSums(is.na(Zfull[hist_rows & !is.na(TG[[PRIMARY]]), ])),
                           stringsAsFactors = FALSE)
cat(sprintf("\n>>> Features computed: %d (%d series x %d measures) on %d historical team-game rows\n",
            NF, length(SERIES), length(MEASURES), sum(hist_rows)))
cat("    Missing count per measure (summed over the 11 series; missing = before 3 values of the series, warm-up of the measure, or no z that date):\n")
print(tapply(feat_missing$missing, factor(feat_missing$measure, levels = names(MEASURES)), sum))
cat("    Missing count per series (summed over the 11 measures):\n")
print(tapply(feat_missing$missing, factor(feat_missing$series, levels = names(SERIES)), sum))
cat(sprintf("    Missing per feature: min %d, median %d, max %d of %d rows\n",
            min(feat_missing$missing), as.integer(stats::median(feat_missing$missing)), max(feat_missing$missing), sum(hist_rows)))
series_missing <- vapply(names(SERIES), function(sn) sum(is.na(TG[[paste0("s_", sn)]][hist_rows])), 0)
cat("    Missing raw series values (historical rows; game 1 has no opponent history for the adjusted series):\n"); print(series_missing)

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

BASELINE_TEXT <- "Elo plus season-to-date margin"
verdict_of <- function(gain, lo, q, n_tests = NF) {
  if (is.na(gain)) return(c("inconclusive", "not enough rows to score"))
  if (gain <= 0) return(c("discarded", sprintf("adds nothing to %s on unseen seasons (out-of-fold gain is zero or negative)", BASELINE_TEXT)))
  if (lo > 0 && q < FDR_Q) return(c("kept", sprintf("adds to %s on unseen seasons; the 95%% interval is above zero and it survives the false-discovery correction (q < %.2f)", BASELINE_TEXT, FDR_Q)))
  if (lo > 0) return(c("inconclusive", sprintf("positive with an interval above zero, but it does not survive the false-discovery correction across %d tests", n_tests)))
  c("inconclusive", "small positive gain, but the 95% interval includes zero")
}

target_frame <- function(tid, seasons, cnt) {
  if (tid != "next_game_win") {
    y <- TG[[tid]]; Xb <- cbind(1, TG$elo_c, TG$snet); sea <- TG$season; blkv <- match(TG$block, cnt$levels)
  } else {
    y <- NG$home_win; Xb <- cbind(NG$elo_diff, NG$snet_diff); sea <- NG$season; blkv <- match(NG$block, cnt$levels)
  }
  list(y = y, Xb = Xb, sea = sea, blk = blkv, base_ok = sea %in% seasons & !is.na(y) & stats::complete.cases(Xb))
}
# Out-of-fold baseline vs baseline + extra columns X (one LOSO pass).
oof_pair <- function(tf, X, seasons, binary) {
  pb <- pc <- rep(NA_real_, length(tf$y)); okx <- stats::complete.cases(X)
  for (s in seasons) {
    tr <- tf$base_ok & okx & tf$sea != s; te <- tf$base_ok & okx & tf$sea == s
    if (sum(te) == 0 || sum(tr) < 50) next
    if (!binary) {
      Xb <- tf$Xb; bb <- solve_safe(crossprod(Xb[tr, ]), crossprod(Xb[tr, ], tf$y[tr])); pb[te] <- Xb[te, ] %*% bb
      Xc <- cbind(Xb, X); bc <- solve_safe(crossprod(Xc[tr, ]), crossprod(Xc[tr, ], tf$y[tr])); pc[te] <- Xc[te, ] %*% bc
    } else {
      pb[te] <- logit_pred(logit_fit(tf$Xb[tr, , drop = FALSE], tf$y[tr]), tf$Xb[te, , drop = FALSE])
      Xc <- cbind(tf$Xb, X); pc[te] <- logit_pred(logit_fit(Xc[tr, , drop = FALSE], tf$y[tr]), Xc[te, , drop = FALSE])
    }
  }
  list(pb = pb, pc = pc)
}

screen_target <- function(tid, seasons) {
  cnt <- get_counts(seasons); binary <- tid == "next_game_win"; tf <- target_frame(tid, seasons, cnt)
  y <- tf$y; base_ok <- tf$base_ok; blkv <- tf$blk
  PB <- matrix(NA_real_, length(y), NF); PC <- PB
  for (s in seasons) {
    Z <- if (binary) getZN(as.character(s)) else getZ(as.character(s))
    tr0 <- base_ok & tf$sea != s; te0 <- base_ok & tf$sea == s
    for (j in seq_len(NF)) {
      okj <- !is.na(Z[, j]); tr <- tr0 & okj; te <- te0 & okj
      if (sum(te) == 0 || sum(tr) < 50) next
      if (!binary) {
        Xb <- tf$Xb; bb <- solve_safe(crossprod(Xb[tr, ]), crossprod(Xb[tr, ], y[tr])); PB[te, j] <- Xb[te, ] %*% bb
        Xc <- cbind(Xb, Z[, j]); bc <- solve_safe(crossprod(Xc[tr, ]), crossprod(Xc[tr, ], y[tr])); PC[te, j] <- Xc[te, ] %*% bc
      } else {
        PB[te, j] <- logit_pred(logit_fit(tf$Xb[tr, , drop = FALSE], y[tr]), tf$Xb[te, , drop = FALSE])
        Xc <- cbind(tf$Xb, Z[, j]); PC[te, j] <- logit_pred(logit_fit(Xc[tr, ], y[tr]), Xc[te, ])
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
# 6. Single features and redundancy families
# ------------------------------------------------------------------------------
say("Step 1: single-feature screening, %d targets x %d features, LOSO over %d seasons", nrow(TARGETS), NF, length(HIST_SEASONS))
SINGLE <- do.call(rbind, lapply(TARGETS$id, function(tid) { r <- screen_target(tid, HIST_SEASONS); say("  %s done", tid); r }))
rownames(SINGLE) <- NULL
prim <- SINGLE[SINGLE$target == PRIMARY, ]; prim <- prim[order(-prim$r2_gain), ]
cat("\n>>> Top 10 single features on the primary target (pooled OOF R^2 gain, 95% CI, q):\n")
print(head(prim[, c("feature", "r2_gain", "ci_lo", "ci_hi", "incremental_ic", "q_value", "n", "verdict")], 10), row.names = FALSE)
cat("    Verdicts by target:\n"); print(table(SINGLE$target, SINGLE$verdict))

say("Step 2: redundancy families")
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
# 7. Nested combination search, comparisons, permutations, stability
# ------------------------------------------------------------------------------
SER_TRIPLES <- utils::combn(TOP_K, 3); MEA_TRIPLES <- utils::combn(TOP_K, 3)
fcol <- function(si, mi) 3L + (si - 1L) * length(MEASURES) + mi   # column in [1, elo, snet, Z]

# Sufficient statistics per fold version and season (X'X does not change under permutation).
# Rows: every feature exists (so all candidates are scored on the same rows).
prep_comb <- function(seasons) {
  Zf <- getZ("full")
  rows <- TG$season %in% seasons & !is.na(TG[[PRIMARY]]) & !is.na(TG$elo_c) & !is.na(TG$snet) & stats::complete.cases(Zf)
  ri <- which(rows)
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

# Comparisons on the same rows and folds: elastic net (all 121) and greedy forward
# selection. (The NBA study also compared its board's score; the NFL has no momentum board.)
compare_models <- function(P, y) {
  sea <- P$sea; pe <- pg <- pb <- rep(NA_real_, length(y)); greedy_sel <- list(); enet_n <- list()
  for (s in P$seasons) {
    key <- as.character(s); X <- P$X[[key]]; tr <- sea != s; te <- sea == s; train <- setdiff(P$seasons, s)
    pb[te] <- X[te, 1:3] %*% solve_safe(crossprod(X[tr, 1:3]), crossprod(X[tr, 1:3], y[tr]))
    set.seed(STUDY_SEED + s)
    fid <- match(sea[tr], train)
    cvf <- glmnet::cv.glmnet(X[tr, -1], y[tr], foldid = fid, alpha = 0.5, penalty.factor = c(0, 0, rep(1, NF)))
    pe[te] <- as.numeric(stats::predict(cvf, X[te, -1], s = "lambda.min"))
    co <- as.matrix(stats::coef(cvf, s = "lambda.min"))[-(1:3), 1]; enet_n[[season_name(s)]] <- sum(co != 0)
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
  }
  list(pb = pb, enet = pe, greedy = pg, greedy_selected = greedy_sel, enet_nonzero = enet_n)
}

summ_gain <- function(y, pb, pc, blk, cnt) { st <- cont_stats(y, pb, pc, blk, cnt); list(r2_gain = st$r2_gain, ci = st$ci, ic = st$ic, boot = st$boot) }

run_search <- function(seasons, label) {
  say("Step 3 (%s): nested combination search over %s", label, paste(season_name(seasons), collapse = ", "))
  P <- prep_comb(seasons); y <- TG[[PRIMARY]][P$ri]
  cnt <- get_counts(seasons); blk <- match(TG$block[P$ri], cnt$levels)
  real <- combo_search(P, y)
  real_stats <- summ_gain(y, real$pb, real$pc, blk, cnt)
  say("  combination search done: %d rows, pooled OOF R^2 gain %.5f [%.5f, %.5f]", length(y), real_stats$r2_gain, real_stats$ci[1], real_stats$ci[2])
  cmp <- compare_models(P, y)
  comps <- list(elastic_net = summ_gain(y, cmp$pb, cmp$enet, blk, cnt), greedy_forward = summ_gain(y, cmp$pb, cmp$greedy, blk, cnt))
  for (nm in names(comps)) comps[[nm]]$boot <- NULL
  say("  comparisons done")
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
              comparisons = comps,
              greedy_selected = cmp$greedy_selected, elastic_net_nonzero = cmp$enet_nonzero,
              stability = list(series_counts = as.list(ser_counts), measure_counts = as.list(mea_counts),
                               series_family_counts = as.list(ser_fam_counts), measure_family_counts = as.list(mea_fam_counts),
                               distinct_combinations = length(unique(combo_ids)), combination_counts = as.list(table(combo_ids)),
                               folds_needed = need, stable_exact = stable_exact, stable_family = stable_family,
                               seasons_with_positive_gain = sum(season_gain > 0), of_seasons = nfold))
  out$P <- P; out$y <- y; out$blk <- blk
  out
}

# Final selection on all historical seasons (fixed BEFORE the forward test is looked at),
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
       tied_with_best = ties, of_combinations = nrow(cand), coef = fit_cols(best), cols = best$cols)
}

A_MAIN <- run_search(HIST_SEASONS, "main (14 seasons)")

# Permutation baseline (the long step): the whole nested search with targets shuffled
# among teams within each date.
say("Step 4: permutation baseline, %d runs (each = full nested search)", N_PERM)
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
# The final choice is now FIXED. Nothing below changes it.

# ------------------------------------------------------------------------------
# 8. Sensitivity runs
# ------------------------------------------------------------------------------
say("Sensitivity 1: without 2020")
SENS_SINGLE <- screen_target(PRIMARY, SENS_SEASONS)
A_SENS <- run_search(SENS_SEASONS, "sensitivity (13 seasons, no 2020)")

say("Sensitivity 2: windows span the previous season's last %d games (flagged)", LONG_W)
FSETS$cross <- make_feature_set(TRUE, sprintf("windows span the previous season's last %d games", LONG_W))
CUR <- "cross"
Zx <- getZ("full")
cross_missing <- data.frame(feature = FEATURES, missing = colSums(is.na(Zx[hist_rows, ])), stringsAsFactors = FALSE)
CROSS_SINGLE <- screen_target(PRIMARY, HIST_SEASONS)
A_CROSS <- run_search(HIST_SEASONS, sprintf("sensitivity (14 seasons, windows span the previous season's last %d games)", LONG_W))
CUR <- "main"
cat(sprintf("    Cross-season windows: missing per feature min %d, median %d, max %d of %d rows (main run: median %d)\n",
            min(cross_missing$missing), as.integer(stats::median(cross_missing$missing)), max(cross_missing$missing), sum(hist_rows),
            as.integer(stats::median(feat_missing$missing))))

# ------------------------------------------------------------------------------
# 9. Flags: QB change, bye, week 18 (their own rows; no row is dropped)
# ------------------------------------------------------------------------------
say("Flags: QB change, bye, week 18")
cnt_h <- get_counts(HIST_SEASONS)
flag_defs <- list(
  qb_change_last = list(label = "Starting QB changed in the team's latest game (known after game k)", cont = function(h) "qb_change_last", bin = "qb_change_diff", known = TRUE),
  bye = list(label = "Coming off a bye (previous game more than 10 days earlier) in the target window", cont = function(h) sprintf("bye_w%d", h), bin = "bye_diff", known = TRUE),
  week18 = list(label = "Week 18 game in the target window (2021 onward; teams resting starters)", cont = function(h) sprintf("week18_w%d", h), bin = "week18", known = TRUE),
  final_week = list(label = "Supplementary: final regular-season week in the target window (week 17 in 2012-2020, week 18 from 2021)", cont = function(h) sprintf("final_week_w%d", h), bin = "final_week", known = TRUE),
  qb_change_in_window = list(label = "Descriptive only (not known before the games): starting QB changed in a game inside the target window", cont = function(h) sprintf("qb_change_in_w%d", h), bin = NA_character_, known = FALSE))
FLAGS <- list()
for (fid in names(flag_defs)) for (tid in TARGETS$id) {
  fd <- flag_defs[[fid]]; binary <- tid == "next_game_win"
  tf <- target_frame(tid, HIST_SEASONS, cnt_h)
  if (!binary) { fcol_name <- fd$cont(TARGET_H[[tid]]); f <- TG[[fcol_name]] } else {
    if (is.na(fd$bin)) next
    fcol_name <- fd$bin; f <- NG[[fcol_name]]
  }
  ok <- tf$base_ok & !is.na(f)
  row <- list(flag = fid, target = tid, definition = fd$label, column = fcol_name, known_before_games = fd$known,
              rows = sum(ok), missing = sum(tf$base_ok & is.na(f)))
  if (!binary) {
    yb <- tf$y[ok]; fb <- f[ok]; bl <- tf$blk[ok]; nb <- length(cnt_h$levels)
    row$flagged_rows <- sum(fb == 1); row$unflagged_rows <- sum(fb == 0)
    row$teams_seasons_flagged <- length(unique(bl[fb == 1]))
    S <- block_sums(cbind(fb == 1, ifelse(fb == 1, yb, 0), fb == 0, ifelse(fb == 0, yb, 0)), bl, nb)
    pt <- colSums(S); BT <- cnt_h$C %*% S
    row$mean_target_flagged <- pt[2] / pt[1]; row$mean_target_unflagged <- pt[4] / pt[3]
    d <- BT[, 2] / BT[, 1] - BT[, 4] / BT[, 3]
    row$difference <- row$mean_target_flagged - row$mean_target_unflagged; row$difference_ci_95 <- q95(d)
    if (fid %in% c("week18", "final_week")) {
      # Every team plays in these weeks, so the flagged mean is zero by construction
      # (each game's two margins beyond Elo cancel). The question is whether stronger
      # teams (Elo above 1500 after game k) fall short of Elo there.
      st <- tf$Xb[ok, 2] > 0
      S2 <- block_sums(cbind(fb == 1 & st, ifelse(fb == 1 & st, yb, 0), fb == 1 & !st, ifelse(fb == 1 & !st, yb, 0)), bl, nb)
      p2 <- colSums(S2); B2 <- cnt_h$C %*% S2
      row$mean_target_flagged_elo_above_1500 <- p2[2] / p2[1]; row$mean_target_flagged_elo_below_1500 <- p2[4] / p2[3]
      row$strong_minus_weak_flagged <- p2[2] / p2[1] - p2[4] / p2[3]; row$strong_minus_weak_ci_95 <- q95(B2[, 2] / B2[, 1] - B2[, 4] / B2[, 3])
    }
  } else {
    row$flagged_rows <- sum(f[ok] != 0); row$unflagged_rows <- sum(f[ok] == 0)
  }
  if (fd$known) {
    X <- if (fid %in% c("week18", "final_week")) { if (binary) cbind(f, f * NG$elo_diff) else cbind(f, f * TG$elo_c) } else matrix(f)
    op <- oof_pair(tf, X, HIST_SEASONS, binary)
    okp <- tf$base_ok & !is.na(op$pc)
    st <- if (!binary) cont_stats(tf$y[okp], op$pb[okp], op$pc[okp], tf$blk[okp], cnt_h) else bin_stats(tf$y[okp], op$pb[okp], op$pc[okp], tf$blk[okp], cnt_h)
    row$added_to_baseline <- list(model = if (binary && fid %in% c("week18", "final_week")) "flag plus flag x Elo difference" else if (fid %in% c("week18", "final_week")) "flag plus flag x team Elo (Elo - 1500)" else if (binary) "home minus away flag" else "flag (0/1)",
                                  r2_gain = st$r2_gain, ci_95 = st$ci, p_value = st$p, n = st$n,
                                  auc_change = if (binary) st$ic else NULL)
    v <- verdict_of(st$r2_gain, st$ci[1], st$p, n_tests = 1)
    row$verdict <- v[1]; row$reason <- sub("false-discovery correction \\(q < 0.05\\)", "bootstrap test (p < 0.05; single test, not part of the 121-feature correction)", v[2])
  } else { row$verdict <- "descriptive"; row$reason <- "uses games after game k, so it cannot be a predictor; shown to describe the target only" }
  FLAGS[[paste(fid, tid, sep = "__")]] <- row
}
# Robustness: the best single feature on the primary target re-scored on rows whose
# target window has no QB change, no bye and no final-week game (the rows are
# chosen with future facts, so this describes, it does not predict).
best_single <- prim$feature[1]
clean <- TG$qb_change_in_w3 %in% 0 & TG$bye_w3 %in% 0 & TG$final_week_w3 %in% 0 & TG$qb_change_last %in% 0
tf <- target_frame(PRIMARY, HIST_SEASONS, cnt_h)
rob <- list()
for (nm in c("all_rows", "clean_rows")) {
  keep <- if (nm == "all_rows") rep(TRUE, NTG) else clean
  tf2 <- tf; tf2$base_ok <- tf$base_ok & keep
  pb <- pc <- rep(NA_real_, NTG)
  for (s in HIST_SEASONS) {
    Z <- getZ(as.character(s))[, best_single]
    tr <- tf2$base_ok & !is.na(Z) & TG$season != s; te <- tf2$base_ok & !is.na(Z) & TG$season == s
    Xb <- tf$Xb; bb <- solve_safe(crossprod(Xb[tr, ]), crossprod(Xb[tr, ], tf$y[tr])); pb[te] <- Xb[te, ] %*% bb
    Xc <- cbind(Xb, Z); bc <- solve_safe(crossprod(Xc[tr, ]), crossprod(Xc[tr, ], tf$y[tr])); pc[te] <- Xc[te, ] %*% bc
  }
  okp <- tf2$base_ok & !is.na(pc)
  st <- cont_stats(tf$y[okp], pb[okp], pc[okp], tf$blk[okp], cnt_h)
  rob[[nm]] <- list(rows = st$n, r2_gain = st$r2_gain, ci_95 = st$ci)
}
FLAG_ROBUST <- list(feature = best_single, target = PRIMARY,
                    rule = "clean rows: no QB change in the latest game or in the next 3 games, no bye and no final-week game in the next 3 games",
                    all_rows = rob$all_rows, clean_rows = rob$clean_rows)
cat("\n>>> Flags (primary target):\n")
for (r in FLAGS) if (r$target == PRIMARY) cat(sprintf("    %-20s flagged %5d of %5d rows; mean beyond Elo flagged %+.2f vs %+.2f; added-to-baseline gain %s\n",
                                                     r$flag, r$flagged_rows, r$rows, r$mean_target_flagged, r$mean_target_unflagged,
                                                     if (is.null(r$added_to_baseline)) "n/a" else sprintf("%+.5f [%+.5f, %+.5f]", r$added_to_baseline$r2_gain, r$added_to_baseline$ci_95[1], r$added_to_baseline$ci_95[2])))
cat(sprintf("    Robustness (%s): all rows %+.5f [%+.5f, %+.5f] (n %d); clean rows %+.5f [%+.5f, %+.5f] (n %d)\n", best_single,
            rob$all_rows$r2_gain, rob$all_rows$ci_95[1], rob$all_rows$ci_95[2], rob$all_rows$rows,
            rob$clean_rows$r2_gain, rob$clean_rows$ci_95[1], rob$clean_rows$ci_95[2], rob$clean_rows$rows))

# ------------------------------------------------------------------------------
# 10. FORWARD TEST 2026 - scored ONCE, here, after every choice above is fixed,
#     and only in the final run (MOMENTUM_STUDY_SCORE_HOLDOUT=1).
# ------------------------------------------------------------------------------
hold_rows <- TG$season == HOLDOUT_SEASON
hold_counts <- list(team_games = sum(hold_rows), games = length(unique(TG$game_id[hold_rows])),
                    last_week = max(TG$week[hold_rows]), last_date = format(max(TG$game_date[hold_rows])))
if (SCORE_HOLDOUT) {
  say("FORWARD TEST %d: scoring the fixed choice once", HOLDOUT_SEASON)
  HOLD <- list(scored = TRUE,
               note = sprintf("Scored once, in the final run, after the combination was fixed on %d-%d. Rows need the 9 chosen features and 3 (or 1) later games for the target.", min(HIST_SEASONS), max(HIST_SEASONS)),
               season_to_date = hold_counts)
  Zh <- getZ("full")
  holdout_score <- function(tid, cols_feat, alpha) {
    trr <- hist_rows & !is.na(TG[[tid]]) & !is.na(TG$elo_c) & !is.na(TG$snet) & stats::complete.cases(Zh[, cols_feat, drop = FALSE])
    ter <- hold_rows & !is.na(TG[[tid]]) & !is.na(TG$elo_c) & !is.na(TG$snet) & stats::complete.cases(Zh[, cols_feat, drop = FALSE])
    X <- cbind(1, TG$elo_c, TG$snet, Zh[, cols_feat, drop = FALSE]); y <- TG[[tid]]
    out <- list(target = tid, rows = sum(ter), teams = length(unique(TG$team[ter])),
                rows_with_target = sum(hold_rows & !is.na(TG[[tid]])))
    if (sum(ter) < HOLDOUT_MIN_ROWS) { out$result <- sprintf("too few %d rows to score yet (needs at least %d)", HOLDOUT_SEASON, HOLDOUT_MIN_ROWS); return(out) }
    pen <- diag(c(0, 0, 0, rep(1, length(cols_feat)))) * alpha * sum(trr)
    b <- solve_safe(crossprod(X[trr, ]) + pen, crossprod(X[trr, ], y[trr])); bb <- solve_safe(crossprod(X[trr, 1:3]), crossprod(X[trr, 1:3], y[trr]))
    pc <- X[ter, ] %*% b; pb <- X[ter, 1:3] %*% bb; yt <- y[ter]
    out$r2_gain <- (sum((yt - pb)^2) - sum((yt - pc)^2)) / sum((yt - mean(yt))^2)
    out$mse_baseline <- mean((yt - pb)^2); out$mse_combination <- mean((yt - pc)^2); out$result <- "scored"
    out
  }
  HOLD$choice <- list(series = FINAL_A$series, measures = FINAL_A$measures, ridge_alpha = FINAL_A$alpha, reliable = COMBO_RELIABLE)
  HOLD$primary <- holdout_score(PRIMARY, FINAL_A$features, FINAL_A$alpha)
  HOLD$next_game <- holdout_score("next_margin_beyond_elo", FINAL_A$features, FINAL_A$alpha)
  str(HOLD, max.level = 3)
} else {
  say("FORWARD TEST %d: NOT scored in this run (test run; set MOMENTUM_STUDY_SCORE_HOLDOUT=1 only for the final run)", HOLDOUT_SEASON)
  HOLD <- list(scored = FALSE, note = "Not scored in this run: test runs never score the forward test.", season_to_date = hold_counts)
}

# ------------------------------------------------------------------------------
# 11. Save results (RDS, JSON for a future methodology page, report tables)
# ------------------------------------------------------------------------------
total_min <- elapsed()
RESULTS <- list(meta = list(run_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"), seed = STUDY_SEED, n_boot = N_BOOT, n_perm = N_PERM,
                            holdout_scored = SCORE_HOLDOUT, seasons = season_table, runtime_min = total_min,
                            permutation_minutes = perm_minutes, team_games_without_pbp = pbp_missing,
                            windows = list(min_games = MIN_GAMES, short = SHORT_W, long = LONG_W, ewma_fast = EWMA_FAST, ewma_slow = EWMA_SLOW,
                                           roc_base_min = ROC_BASE_MIN, impulse_decay = IMPULSE_DECAY, bye_days = BYE_DAYS, min_z_teams = MIN_Z_TEAMS)),
                feature_missing = feat_missing, series_missing = series_missing, single = SINGLE, single_sensitivity = SENS_SINGLE,
                single_cross_season = CROSS_SINGLE, cross_season_missing = cross_missing,
                families = list(features = feat_families, measure = split(names(MEASURES), measure_cl), series = split(names(SERIES), series_cl),
                                measure_mean_abs_r = RM, series_mean_abs_r = RS),
                kalman_parameters = FSETS$main$pars, kalman_parameters_cross = FSETS$cross$pars,
                search = A_MAIN[setdiff(names(A_MAIN), c("P", "y", "blk"))], search_sensitivity = A_SENS[setdiff(names(A_SENS), c("P", "y", "blk"))],
                search_cross_season = A_CROSS[setdiff(names(A_CROSS), c("P", "y", "blk"))],
                permutation = list(gains = PERM, p95 = perm_p95, minutes = perm_minutes),
                final_choice = FINAL_A, reliability = crit, combination_verdict = combo_verdict,
                flags = FLAGS, flag_robustness = FLAG_ROBUST, holdout = HOLD)
saveRDS(RESULTS, file.path(CACHE_DIR, "momentum_measures_study_results.rds"))

measure_text <- c(
  roc3 = "Elo: (Elo after game k - Elo before game k-2) / 3. Box series: mean of the last 3 values minus the mean of the team's values before them (at least 3 earlier values).",
  macd = "Exponentially weighted mean of the series with span 2 minus the same with span 6, updated game by game from the season's first value.",
  velocity = "Slope of a least-squares line through the trailing 6 values of the series.",
  acceleration = "Velocity after game k minus velocity 3 values earlier.",
  ewma_change = "Exponentially weighted mean (span 2) of the per-game change (Elo) or surprise (box series: game value minus the team's own mean of its earlier values).",
  zscore = "ROC-3 divided by the standard deviation of the team's changes or surprises in games 1..k (expanding window).",
  rsi = "Over the last 6 changes or surprises: 100 x average gain / (average gain + average loss); recent gains vs losses on a 0-100 scale.",
  growth = "Sum of the last 3 changes or surprises minus the sum of the 3 before them (a difference, because the ratio is unstable near zero).",
  kalman = "Filtered slope of a local linear trend model (level + slope + noise) run forward through games 1..k; its three noise variances are fitted by maximum likelihood on the training seasons only.",
  streak = "Signed length of the current run: wins/losses for Elo, positive/negative surprises for the other series.",
  impulse = "m[k] = 0.75 x m[k-1] + change or surprise in game k, from the season's first value.")
measure_field <- c(roc3 = "finance (rate of change)", macd = "finance (moving-average convergence/divergence)", velocity = "physics (kinematics)",
                   acceleration = "physics (kinematics)", ewma_change = "signal processing", zscore = "sports analytics (hot-hand style)",
                   rsi = "finance (relative strength index)", growth = "epidemiology (growth of an outbreak)", kalman = "econometrics (state-space models)",
                   streak = "basketball hot-hand literature", impulse = "control theory (damped impulse response)")
series_text <- c(elo = sprintf("Production Elo rating after each game (tools/elo_model.R: K %d, home field %d Elo points, margin-of-victory multiplier, 2/3 season carry-over; every completed game from %d).", ELO_K_FACTOR, ELO_HCA_POINTS, ELO_FIRST_SEASON),
                 margin = "Point margin minus the opponent's season-to-date average margin allowed (earlier games only).",
                 off_epa = "Offensive EPA per play (all plays with an EPA, as epa_metrics_engine.R) minus the opponent's season-to-date average allowed.",
                 def_epa = "Defensive EPA per play allowed minus the opponent's season-to-date average produced; lower is better.",
                 off_sr = "Offensive success rate minus the opponent's season-to-date average allowed.",
                 def_sr = "Defensive success rate allowed minus the opponent's season-to-date average produced; lower is better.",
                 pass_epa = "EPA per pass play (pass == 1: dropbacks incl. sacks and scrambles) minus the opponent's season-to-date average allowed.",
                 rush_epa = "EPA per designed run (rush == 1) minus the opponent's season-to-date average allowed.",
                 pass_epa_def = "EPA per pass play allowed minus the opponent's season-to-date average produced; lower is better.",
                 rush_epa_def = "EPA per designed run allowed minus the opponent's season-to-date average produced; lower is better.",
                 tom = "Takeaways minus giveaways (interceptions plus fumbles lost) minus the opponent's season-to-date average turnover margin allowed.")
cvec <- function(x) as.list(x)
fold_json <- function(A) lapply(A$folds, function(f) f)
single_json <- function(D) lapply(seq_len(nrow(D)), function(i) { r <- D[i, ]
  list(feature = r$feature, r2_gain = r$r2_gain, ci_95 = c(r$ci_lo, r$ci_hi), fdr_q_value = r$q_value, n = r$n, missing_count = r$missing, verdict = r$verdict) })
json <- list(
  study = list(title = "NFL momentum measures study: does team momentum predict the next game and the next 3 games beyond team strength (Elo)?",
               issue = "kailot-harris/NFL_analytics#220",
               run_date = format(Sys.Date()), seasons = lapply(seq_len(nrow(season_table)), function(i) as.list(season_table[i, ])),
               holdout = sprintf("%d regular season to date: forward test, scored once in the final run after every choice was fixed (scored in this run: %s)", HOLDOUT_SEASON, SCORE_HOLDOUT),
               baseline = "Team Elo after its latest game (pregame Elo for the next game) plus season-to-date point margin per game",
               windows = list(warmup_values = MIN_GAMES, short = SHORT_W, long = LONG_W, ewma_spans = c(EWMA_FAST, EWMA_SLOW),
                              roc_baseline_min_values = ROC_BASE_MIN, impulse_decay = IMPULSE_DECAY, bye_days = BYE_DAYS, min_teams_for_z = MIN_Z_TEAMS),
               protocol = c(sprintf("Leave-one-season-out over %d-%d with pooled out-of-fold predictions", min(HIST_SEASONS), max(HIST_SEASONS)),
                            sprintf("Paired bootstrap, %d resamples of whole team-seasons (next-3 targets overlap from game to game)", N_BOOT),
                            "Baseline: Elo after the game plus season-to-date margin per game; candidates scored on what they add",
                            "Every feature uses only the team's earlier games; cross-team z-scores per date use each team's latest state on or before that date",
                            "No imputation; missing values are counted per feature",
                            sprintf("Benjamini-Hochberg false discovery rate across the 121 features per target (q < %.2f)", FDR_Q),
                            "Nested combination search: top 6 series x top 6 measures ranked on training seasons only, 400 combinations x 3 ridge penalties chosen by inner leave-one-season-out",
                            sprintf("Permutation baseline: %d reruns of the whole nested search with the target shuffled among teams within each date", N_PERM),
                            "Flags (QB change, bye, week 18) reported as their own rows; no row is dropped",
                            "Sensitivity runs: without 2020; windows spanning the previous season's last 6 games"),
               seeds = list(study = STUDY_SEED, permutation = STUDY_SEED + 999L, bootstrap = "STUDY_SEED + number of seasons in the run"),
               runtime_minutes = total_min, permutation_minutes = perm_minutes),
  targets = lapply(seq_len(nrow(TARGETS)), function(i) list(id = TARGETS$id[i], definition = TARGETS$definition[i], primary = TARGETS$primary[i])),
  measures = lapply(names(MEASURES), function(m) list(id = m, name = MEASURES[[m]], field_of_origin = measure_field[[m]],
                                                      forward_only_definition = paste(measure_text[[m]], "Uses only the team's games up to and including the latest one; no value before the team's 3rd value of the series that season."))),
  series = lapply(names(SERIES), function(s) list(id = s, name = SERIES[[s]], definition = series_text[[s]],
                                                  missing_raw_values = unname(series_missing[[s]]))),
  single_feature_results = lapply(seq_len(nrow(SINGLE)), function(i) {
    r <- SINGLE[i, ]
    list(feature = r$feature, series = r$series, measure = r$measure, target = r$target, incremental_ic = r$incremental_ic, ic_metric = r$ic_metric,
         r2_gain = r$r2_gain, gain_metric = r$gain_metric, ci_95 = c(r$ci_lo, r$ci_hi), fdr_q_value = r$q_value, p_value = r$p_value,
         n = r$n, missing_count = r$missing, verdict = r$verdict, reason = r$reason)
  }),
  single_feature_sensitivity_primary = single_json(SENS_SINGLE),
  families = list(feature_clusters_abs_r_0_7 = unname(lapply(feat_families, identity)),
                  measure_families = unname(split(names(MEASURES), measure_cl)), series_families = unname(split(names(SERIES), series_cl)),
                  measure_mean_abs_r = lapply(as.data.frame(round(RM, 4)), identity), series_mean_abs_r = lapply(as.data.frame(round(RS, 4)), identity)),
  combination_search = list(target = PRIMARY, rows = A_MAIN$rows, folds = fold_json(A_MAIN),
                            pooled_r2_gain = A_MAIN$pooled_r2_gain, pooled_ci_95 = A_MAIN$pooled_ci, pooled_incremental_ic = A_MAIN$pooled_ic,
                            comparisons = A_MAIN$comparisons, combination_vs_board_score = NULL,
                            greedy_selected_by_fold = A_MAIN$greedy_selected, elastic_net_nonzero_by_fold = A_MAIN$elastic_net_nonzero,
                            selection_stability = A_MAIN$stability,
                            permutation = list(runs = N_PERM, p95 = perm_p95, mean = mean(PERM), max = max(PERM), share_at_or_above_real = mean(PERM >= A_MAIN$pooled_r2_gain), minutes = perm_minutes),
                            final_choice = list(series = FINAL_A$series, measures = FINAL_A$measures, ridge_alpha = FINAL_A$alpha, inner_r2_gain = FINAL_A$inner_r2_gain,
                                                tied_with_best_within_ci = FINAL_A$tied_with_best, of_combinations = FINAL_A$of_combinations),
                            reliability_checks = as.list(crit), final_verdict = combo_verdict,
                            sensitivity_without_2020 = list(rows = A_SENS$rows, folds = fold_json(A_SENS), pooled_r2_gain = A_SENS$pooled_r2_gain,
                                                            pooled_ci_95 = A_SENS$pooled_ci, comparisons = A_SENS$comparisons, selection_stability = A_SENS$stability),
                            sensitivity_cross_season_windows = list(note = sprintf("Flagged sensitivity: each team-season's series is preceded by the same franchise's last %d values of the previous regular season, so windows span the season break; the in-season warm-up no longer applies.", LONG_W),
                                                                    rows = A_CROSS$rows, folds = fold_json(A_CROSS), pooled_r2_gain = A_CROSS$pooled_r2_gain,
                                                                    pooled_ci_95 = A_CROSS$pooled_ci, comparisons = A_CROSS$comparisons, selection_stability = A_CROSS$stability,
                                                                    single_features_primary = single_json(CROSS_SINGLE))),
  flags = list(definitions = list(qb_change = "The starting QB is the passer with the most dropbacks for the team in the game; the flag is set when it differs from the team's previous game that season.",
                                  bye = sprintf("The team's previous game was more than %d days earlier within the same season.", BYE_DAYS),
                                  week18 = "week == 18 (only 2021 onward has a week 18)."),
               rows = unname(FLAGS), robustness_best_single_feature = FLAG_ROBUST),
  blend_weights = NULL,
  holdout = HOLD,
  limits = c("The NFL has no momentum board yet, so there are no blend weights to test; blend_weights is null.",
             "Effects are small: regression to the mean dominates NFL results over 1-3 games, and the next-3 target is noisy.",
             sprintf("The combination search uses rows where all 121 features exist (from about a team's %dth game, because acceleration needs 9 values of a series) so every candidate is scored on the same rows; single features use all rows where they exist.", MIN_GAMES + LONG_W),
             "Opponent-adjusted series have no value in a team's first game (the opponent has no earlier games that season), so their measures start one game later than Elo's.",
             "Kalman variances are fitted on the outer training seasons and reused in the inner loop; the without-2020 sensitivity reuses the 14-season fold fits.",
             "Bootstrap intervals for the incremental IC hold the ranks at their full-sample values.",
             "The next-game win target is scored by log loss; its ROC-AUC change is a point estimate without an interval.",
             "The week-18 flag exists only from 2021 (17-game seasons); a supplementary final-week flag covers week 17 in 2012-2020.",
             "Elo gives the listed home team home field at every site, as tools/elo_model.R does; neutral-site games are not treated separately.",
             "Franchises that moved (OAK/LV, SD/LAC, STL/LA) are keyed by today's abbreviation so their Elo carries over.",
             sprintf("2026 is in progress (through week %d); it is a single small forward test.", hold_counts$last_week))
)
dir.create(file.path(STUDY_ROOT, "docs", "research"), recursive = TRUE, showWarnings = FALSE)
namify <- function(x) {
  if (is.data.frame(x)) return(lapply(seq_len(nrow(x)), function(i) namify(as.list(x[i, , drop = FALSE]))))
  if (is.matrix(x) && !is.null(rownames(x))) return(lapply(setNames(seq_len(nrow(x)), rownames(x)), function(i) namify(x[i, ])))
  if (is.list(x)) return(lapply(x, namify))
  if (is.atomic(x) && !is.null(names(x)) && length(x) > 0) return(as.list(x))
  x
}
json <- namify(json)
json["blend_weights"] <- list(NULL); json$combination_search["combination_vs_board_score"] <- list(NULL)
jsonlite::write_json(json, file.path(STUDY_ROOT, "docs", "research", "momentum_measures_study_results.json"),
                     auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null", null = "null")

# Report tables (markdown) - every number pasted into the report comes from here.
f4 <- function(x) ifelse(is.na(x), "NA", sprintf("%.4f", x)); f5 <- function(x) ifelse(is.na(x), "NA", sprintf("%+.5f", x))
f2 <- function(x) ifelse(is.na(x), "NA", sprintf("%+.2f", x))
md <- c("## Seasons", "", "| Season | Role | Games | Team-games | First | Last | Last week | Ties | QB changes | Byes |", "|---|---|---|---|---|---|---|---|---|---|",
        sprintf("| %s | %s | %d | %d | %s | %s | %d | %d | %d | %d |", season_table$season, season_table$role, season_table$games, season_table$team_games,
                season_table$first, season_table$last, season_table$last_week, season_table$ties, season_table$qb_changes, season_table$byes), "",
        sprintf("Historical team-games: %d. Team-games without play-by-play: %d.", sum(hist_rows), pbp_missing), "",
        "## Missing values", "", "| Measure | Missing (summed over 11 series) |", "|---|---|",
        sprintf("| %s | %d |", names(MEASURES), as.integer(tapply(feat_missing$missing, factor(feat_missing$measure, levels = names(MEASURES)), sum))), "",
        "| Series | Missing raw values | Missing features (summed over 11 measures) |", "|---|---|---|",
        sprintf("| %s | %d | %d |", names(SERIES), as.integer(series_missing), as.integer(tapply(feat_missing$missing, factor(feat_missing$series, levels = names(SERIES)), sum))), "",
        sprintf("Per feature: min %d, median %d, max %d of %d rows.", min(feat_missing$missing), as.integer(stats::median(feat_missing$missing)), max(feat_missing$missing), sum(hist_rows)), "",
        "## Verdicts by target", "", "| Target | kept | inconclusive | discarded |", "|---|---|---|---|",
        vapply(TARGETS$id, function(t) { x <- SINGLE[SINGLE$target == t, ]; sprintf("| %s | %d | %d | %d |", t, sum(x$verdict == "kept"), sum(x$verdict == "inconclusive"), sum(x$verdict == "discarded")) }, ""), "")
for (t in TARGETS$id) {
  x <- SINGLE[SINGLE$target == t, ]; x <- head(x[order(-x$r2_gain), ], 10)
  md <- c(md, sprintf("## Top 10 single features: %s", t), "", "| Feature | Gain | 95% CI | IC / AUC change | q | n | Missing | Verdict |", "|---|---|---|---|---|---|---|---|",
          sprintf("| %s | %s | [%s, %s] | %s | %s | %d | %d | %s |", x$feature, f5(x$r2_gain), f5(x$ci_lo), f5(x$ci_hi), f5(x$incremental_ic), f4(x$q_value), x$n, x$missing, x$verdict), "")
}
for (nm in c("SENS_SINGLE", "CROSS_SINGLE")) {
  xs <- get(nm); xs <- head(xs[order(-xs$r2_gain), ], 10)
  md <- c(md, sprintf("## %s: top 10 single features, primary target", if (nm == "SENS_SINGLE") "Sensitivity without 2020" else "Sensitivity with cross-season windows"),
          "", "| Feature | Gain | 95% CI | q | n | Verdict |", "|---|---|---|---|---|---|",
          sprintf("| %s | %s | [%s, %s] | %s | %d | %s |", xs$feature, f5(xs$r2_gain), f5(xs$ci_lo), f5(xs$ci_hi), f4(xs$q_value), xs$n, xs$verdict), "",
          sprintf("Verdicts: kept %d, inconclusive %d, discarded %d.", sum(get(nm)$verdict == "kept"), sum(get(nm)$verdict == "inconclusive"), sum(get(nm)$verdict == "discarded")), "")
}
fold_tab <- function(A) c("| Held-out season | Series | Measures | Ridge alpha | Inner gain | Held-out gain | Rows |", "|---|---|---|---|---|---|---|",
  vapply(A$folds, function(f) sprintf("| %s | %s | %s | %g | %s | %s | %d |", f$held_out, paste(f$series, collapse = ", "), paste(f$measures, collapse = ", "), f$ridge_alpha, f5(f$inner_r2_gain), f5(f$held_out_r2_gain), f$held_out_rows), ""))
stab_line <- function(A) sprintf("Stability: %d distinct combinations in %d folds; series counts %s; measure counts %s; seasons with positive held-out gain %d of %d.",
                                 A$stability$distinct_combinations, A$stability$of_seasons,
                                 paste(sprintf("%s %d", names(A$stability$series_counts), unlist(A$stability$series_counts)), collapse = ", "),
                                 paste(sprintf("%s %d", names(A$stability$measure_counts), unlist(A$stability$measure_counts)), collapse = ", "),
                                 A$stability$seasons_with_positive_gain, A$stability$of_seasons)
md <- c(md, "## Measure families (mean |r| across series >= 0.5)", "", vapply(split(names(MEASURES), measure_cl), function(v) paste("-", paste(v, collapse = ", ")), ""), "",
        "## Series families (mean |r| across measures >= 0.5)", "", vapply(split(names(SERIES), series_cl), function(v) paste("-", paste(v, collapse = ", ")), ""), "",
        sprintf("Feature clusters with every pair |r| >= 0.7: %d clusters, %d with more than one feature.", length(feat_families), sum(lengths(feat_families) > 1)), "",
        "## Combination search by outer fold (primary target)", "", fold_tab(A_MAIN), "",
        "## Combination search summary", "", "| Model | Rows | Pooled OOF R^2 gain | 95% CI |", "|---|---|---|---|",
        sprintf("| Nested 3x3 combination | %d | %s | [%s, %s] |", A_MAIN$rows, f5(A_MAIN$pooled_r2_gain), f5(A_MAIN$pooled_ci[1]), f5(A_MAIN$pooled_ci[2])),
        vapply(names(A_MAIN$comparisons), function(n) { c0 <- A_MAIN$comparisons[[n]]; sprintf("| %s | %d | %s | [%s, %s] |", n, A_MAIN$rows, f5(c0$r2_gain), f5(c0$ci[1]), f5(c0$ci[2])) }, ""),
        sprintf("| Sensitivity without 2020: nested 3x3 combination | %d | %s | [%s, %s] |", A_SENS$rows, f5(A_SENS$pooled_r2_gain), f5(A_SENS$pooled_ci[1]), f5(A_SENS$pooled_ci[2])),
        vapply(names(A_SENS$comparisons), function(n) { c0 <- A_SENS$comparisons[[n]]; sprintf("| Sensitivity without 2020: %s | %d | %s | [%s, %s] |", n, A_SENS$rows, f5(c0$r2_gain), f5(c0$ci[1]), f5(c0$ci[2])) }, ""),
        sprintf("| Sensitivity cross-season windows: nested 3x3 combination | %d | %s | [%s, %s] |", A_CROSS$rows, f5(A_CROSS$pooled_r2_gain), f5(A_CROSS$pooled_ci[1]), f5(A_CROSS$pooled_ci[2])),
        vapply(names(A_CROSS$comparisons), function(n) { c0 <- A_CROSS$comparisons[[n]]; sprintf("| Sensitivity cross-season windows: %s | %d | %s | [%s, %s] |", n, A_CROSS$rows, f5(c0$r2_gain), f5(c0$ci[1]), f5(c0$ci[2])) }, ""), "",
        sprintf("Permutation baseline: %d runs, 95th percentile %s, mean %s, max %s; share of runs at or above the real gain %s; runtime %.1f min.",
                N_PERM, f5(perm_p95), f5(mean(PERM)), f5(max(PERM)), f4(mean(PERM >= A_MAIN$pooled_r2_gain)), perm_minutes),
        stab_line(A_MAIN),
        sprintf("Final choice on all 14 seasons: %s x %s (ridge alpha %g); %d of %d other combinations tie with it within the bootstrap interval.",
                paste(FINAL_A$series, collapse = ", "), paste(FINAL_A$measures, collapse = ", "), FINAL_A$alpha, FINAL_A$tied_with_best, FINAL_A$of_combinations - 1L),
        sprintf("Reliability checks: %s. Verdict: %s.", paste(sprintf("%s = %s", names(crit), crit), collapse = "; "), combo_verdict), "",
        "## Sensitivity without 2020 by fold", "", fold_tab(A_SENS), "", stab_line(A_SENS), "",
        "## Sensitivity with cross-season windows by fold", "", fold_tab(A_CROSS), "", stab_line(A_CROSS), "",
        "## Flags", "", "| Flag | Target | Rows | Flagged | Mean beyond Elo: flagged | not flagged | Difference [95% CI] | Added to baseline: gain [95% CI] | Verdict |", "|---|---|---|---|---|---|---|---|---|")
for (r in FLAGS) md <- c(md, sprintf("| %s | %s | %d | %d | %s | %s | %s | %s | %s |", r$flag, r$target, r$rows, r$flagged_rows,
                                     if (is.null(r$mean_target_flagged)) "" else f2(r$mean_target_flagged), if (is.null(r$mean_target_unflagged)) "" else f2(r$mean_target_unflagged),
                                     if (is.null(r$difference)) "" else sprintf("%s [%s, %s]", f2(r$difference), f2(r$difference_ci_95[1]), f2(r$difference_ci_95[2])),
                                     if (is.null(r$added_to_baseline)) "n/a" else sprintf("%s [%s, %s]", f5(r$added_to_baseline$r2_gain), f5(r$added_to_baseline$ci_95[1]), f5(r$added_to_baseline$ci_95[2])),
                                     r$verdict))
for (r in FLAGS) if (!is.null(r$strong_minus_weak_flagged)) md <- c(md, "", sprintf("%s, %s: flagged rows of teams with Elo above 1500 %s, below 1500 %s; difference %s [%s, %s].",
  r$flag, r$target, f2(r$mean_target_flagged_elo_above_1500), f2(r$mean_target_flagged_elo_below_1500), f2(r$strong_minus_weak_flagged), f2(r$strong_minus_weak_ci_95[1]), f2(r$strong_minus_weak_ci_95[2])))
md <- c(md, "", sprintf("Robustness: %s on the primary target, all rows %s [%s, %s] (n %d); clean rows %s [%s, %s] (n %d). Clean rows: %s.", best_single,
                        f5(rob$all_rows$r2_gain), f5(rob$all_rows$ci_95[1]), f5(rob$all_rows$ci_95[2]), rob$all_rows$rows,
                        f5(rob$clean_rows$r2_gain), f5(rob$clean_rows$ci_95[1]), f5(rob$clean_rows$ci_95[2]), rob$clean_rows$rows, FLAG_ROBUST$rule), "",
        sprintf("## Forward test %d", HOLDOUT_SEASON), "",
        sprintf("Season to date: %d games, %d team-games, through week %d (%s).", hold_counts$games, hold_counts$team_games, hold_counts$last_week, hold_counts$last_date))
if (isTRUE(HOLD$scored)) {
  for (nm in c("primary", "next_game")) { h <- HOLD[[nm]]
    md <- c(md, sprintf("- %s (%s): rows %d (teams %d; rows with a target %d): %s%s", nm, h$target, h$rows, h$teams, h$rows_with_target, h$result,
                        if (!is.null(h$r2_gain)) sprintf(", R^2 gain %s (MSE baseline %.3f, combination %.3f)", f5(h$r2_gain), h$mse_baseline, h$mse_combination) else "")) }
} else md <- c(md, "- Not scored in this run (test run).")
md <- c(md, "", "## Recommendation (rule-based)", "", paste("-", combo_verdict), "",
        sprintf("Runtime: %.1f minutes in total (permutations %.1f minutes).", total_min, perm_minutes))
writeLines(md, file.path(CACHE_DIR, "momentum_measures_study_tables.md"))

cat("\n================ SUMMARY ================\n")
cat(sprintf("Features: %d; single-feature rows: %d (%d targets)\n", NF, nrow(SINGLE), nrow(TARGETS)))
cat(sprintf("Combination search: pooled OOF R^2 gain %.5f [%.5f, %.5f]; permutation p95 %.5f (%d runs, %.1f min)\n",
            A_MAIN$pooled_r2_gain, A_MAIN$pooled_ci[1], A_MAIN$pooled_ci[2], perm_p95, N_PERM, perm_minutes))
cat(sprintf("Verdict: %s\n", combo_verdict))
cat(sprintf("Forward test scored in this run: %s\n", SCORE_HOLDOUT))
cat("Results: cache/momentum_measures_study_results.rds, docs/research/momentum_measures_study_results.json, cache/momentum_measures_study_tables.md\n")
cat(sprintf("Total runtime: %.1f minutes\n", total_min))
