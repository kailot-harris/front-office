# ==============================================================================
# tests/test_momentum_dataset.R
#
# Core math of build_momentum_dataset.R and R/elo.R (NBA_analytics#237), on small
# hand-built fixtures (no cache needed):
#   1. possessions estimator and the shared-denominator game possessions
#   2. rolling windows (roll_sum, window_states) and the unranked rule
#   3. model residual uses RESOLVED LOGGED_PREGAME rows with a logged margin only
#   4. flag significance (binomial z, EB shrink, thresholds, null below min n)
#   5. Elo rules (K, home court, margin multiplier, zero-sum, daily series, changes)
#   6. change baseline = games before the window; null below 5 earlier games;
#      drivers and the trend component follow it, with no imputation
#   7. default window (80% rule)
#   8. rank-change null reasons
#
# Usage: Rscript tests/test_momentum_dataset.R
# ==============================================================================

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  if (basename(base) == "tests") normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
  else normalizePath(base, winslash = "/", mustWork = FALSE)
})

failures <- 0L
ok <- function(label, cond) {
  if (isTRUE(cond)) cat(sprintf("  PASS  %s\n", label))
  else { failures <<- failures + 1L; cat(sprintf("  FAIL  %s\n", label)) }
}
near <- function(a, b, tol = 1e-6) isTRUE(all(abs(a - b) < tol))

old_wd <- getwd()
setwd(REPO_ROOT)
Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")
env <- new.env(parent = globalenv())
suppressWarnings(suppressMessages(sys.source(file.path(REPO_ROOT, "build_momentum_dataset.R"), envir = env)))
Sys.unsetenv("NBA_SKIP_STAGE_AUTORUN")
setwd(old_wd)

# --- 1. Possessions -----------------------------------------------------------
cat("\n[possessions]\n")
ok("FGA - OREB + TOV + 0.44 * FTA", near(env$estimate_possessions(88, 10, 14, 25), 88 - 10 + 14 + 11))

# Fixture: two teams, four games, alternating home.
mk_rows <- function() {
  g <- data.frame(
    game_id = c("g1", "g2", "g3", "g4"),
    game_date = as.Date("2026-10-20") + c(0, 2, 4, 6),
    a_home = c(TRUE, FALSE, TRUE, FALSE),
    a_pts = c(110, 100, 120, 95), b_pts = c(100, 105, 101, 99),
    stringsAsFactors = FALSE)
  side <- function(team, opp, home, pts, opp_pts, fga, oreb, tov, fta)
    data.frame(game_id = g$game_id, game_date = g$game_date, team = team, team_name = team,
               team_id = team, opp = opp, home = home, pts = pts, opp_pts = opp_pts,
               fga = fga, fgm = 40, fg3a = 35, fg3m = 12, fta = fta, ftm = round(0.8 * fta),
               oreb = oreb, dreb = 33, tov = tov, stringsAsFactors = FALSE)
  rbind(side("AAA", "BBB", g$a_home, g$a_pts, g$b_pts, 88, 10, 14, 20),
        side("BBB", "AAA", !g$a_home, g$b_pts, g$a_pts, 90, 12, 12, 25))
}
p <- env$build_team_game_panel(mk_rows())
pa <- p[p$team == "AAA", ]
exp_poss <- ((88 - 10 + 14 + 0.44 * 20) + (90 - 12 + 12 + 0.44 * 25)) / 2
ok("game possessions = mean of both teams' estimates", near(pa$poss, rep(exp_poss, 4)))
ok("both sides share one denominator", near(p$poss[p$team == "AAA"], p$poss[p$team == "BBB"]))
ok("ORtg = 100 * pts / poss", near(pa$ortg, 100 * c(110, 100, 120, 95) / exp_poss))
ok("net = ortg - drtg", near(pa$net, pa$ortg - pa$drtg))

# --- 2. Rolling windows and the unranked rule ---------------------------------
cat("\n[rolling windows]\n")
ok("roll_sum over last 2", near(env$roll_sum(c(1, 2, 3, 4), 2), c(1, 3, 5, 7)))
ok("roll_sum window larger than series = cumulative", near(env$roll_sum(c(1, 2, 3), 5), c(1, 3, 6)))
p$adj_net <- p$net; p$elo_pre <- 1500; p$elo_post <- 1500
p$residual_eligible <- FALSE; p$residual <- NA_real_
st3 <- env$window_states(p, 3L)
a3 <- st3[st3$team == "AAA", ]
ok("games_in_window = min(games, window)", identical(as.integer(a3$games_in_window), c(1L, 2L, 3L, 3L)))
ok("unranked until the team has a full window", identical(a3$ranked, c(FALSE, FALSE, TRUE, TRUE)))
w_last <- pa[2:4, ]
ok("window net = aggregate over the last 3 games",
   near(a3$net[4], 100 * (sum(w_last$pts) - sum(w_last$opp_pts)) / sum(w_last$poss)))
ok("season net uses every game", near(a3$net_season[4], 100 * (sum(pa$pts) - sum(pa$opp_pts)) / sum(pa$poss)))
st5 <- env$score_states(env$states_as_of(env$window_states(p, 5L), as.Date("2026-10-26")))
ok("window 5 with 4 games: ranked = FALSE for every team", all(!st5$ranked))
ok("unranked teams get no combined rank", all(is.na(st5$combined_rank)))
ok("rank_ranked never ranks an unranked team",
   identical(env$rank_ranked(c(3, 1, 2), c(TRUE, FALSE, TRUE)), c(1L, NA, 2L)))
ok("rank_ranked lower is first (DRtg)",
   identical(env$rank_ranked(c(110, 105, 120), c(TRUE, TRUE, TRUE), descending = FALSE), c(2L, 1L, 3L)))
ok("states_as_of picks each team's latest game on or before the date",
   all(env$states_as_of(st3, as.Date("2026-10-23"))$game_index == 2L))

# --- 3. Residual: logged pregame margins only ---------------------------------
cat("\n[model residual]\n")
log <- data.frame(
  game_id = c("h1", "h2", "h3", "h4"),
  game_date = as.Date("2026-10-20") + c(0, 2, 4, 6),
  home_team = c("AAA", "BBB", "AAA", "BBB"), away_team = c("BBB", "AAA", "BBB", "AAA"),
  predicted_margin = c(5, NA, 3, -2),
  status = c("RESOLVED", "RESOLVED", "RESOLVED", "PENDING"),
  log_source = c("LOGGED_PREGAME", "LOGGED_PREGAME", "BACKTEST_PREWEEK", "LOGGED_PREGAME"),
  stringsAsFactors = FALSE)
el <- env$residual_eligible_log(log)
ok("only RESOLVED + LOGGED_PREGAME + non-missing margin qualify", identical(el$game_id, "h1"))
pr <- env$attach_prediction_log(env$build_team_game_panel(mk_rows()), log,
                                as.Date("2026-10-01"), as.Date("2027-04-30"))
ok("exactly one game per side carries a residual", sum(pr$residual_eligible) == 2L)
g1a <- pr[pr$game_id == "g1" & pr$team == "AAA", ]
g1b <- pr[pr$game_id == "g1" & pr$team == "BBB", ]
ok("home residual = actual margin - logged margin", near(g1a$residual, (110 - 100) - 5))
ok("away residual uses the flipped logged margin", near(g1b$residual, (100 - 110) + 5))
ok("games without a logged margin keep NA (no back-fill)",
   all(is.na(pr$projected_margin[pr$game_id != "g1"])) && all(is.na(pr$model_basis[pr$game_id != "g1"])))
pr$adj_net <- pr$net; pr$elo_pre <- 1500; pr$elo_post <- 1500
rs <- env$window_states(pr, 4L)
ra <- rs[rs$team == "AAA" & rs$game_index == 4L, ]
ok("residual_games_in_window counts logged games only", ra$residual_games == 1L)
ok("window residual = mean over logged games only", near(ra$residual, 5))
ok("residual unranked below ceiling(0.6 * window) logged games", !ra$residual_ranked)

# --- 4. Flag significance ----------------------------------------------------
cat("\n[flag significance]\n")
z <- env$binomial_z(60, 100, 0.5)
ok("binomial z = (k/n - p0) / sqrt(p0 (1 - p0) / n)", near(z, (0.6 - 0.5) / sqrt(0.25 / 100)))
ok("z is NA below the minimum sample", is.na(env$binomial_z(2, 3, 0.5)))
ok("EB shrink = (k + 15 p0) / (n + 15)", near(env$eb_shrink(6, 10, 0.4), (6 + 15 * 0.4) / 25))
ok("|z| >= 1.96 is significant (two-sided)", env$is_significant(-2.0) && !env$is_significant(1.9))
ok("one-sided high test ignores large negative z",
   !env$is_significant(-3, one_sided_high = TRUE) && env$is_significant(2.5, one_sided_high = TRUE))
ok("NA statistic is never significant", !env$is_significant(NA_real_))
f <- env$flag_obj(2, "opponent_three_pct", "luck", "x", "t", value = 0.03, statistic = NA_real_, significant = TRUE, n = 2)
ok("flag with no statistic: significant = FALSE and a null_reason", !f$significant && is.character(f$null_reason))
ok("Pythagorean win pct exponent 14", near(env$pythag_win_pct(110, 100), 110^14 / (110^14 + 100^14)))

# --- 5. Elo -----------------------------------------------------------------
cat("\n[elo]\n")
ok("K = 20, home court = 100, carry = 0.75", env$ELO_K == 20 && env$ELO_HOME_ADV == 100 && env$ELO_CARRY == 0.75)
u <- env$elo_update_game(1500, 1500, 110, 100)
e_home <- 1 / (1 + 10^(-100 / 400))
mult <- (10 + 3)^0.8 / (7.5 + 0.006 * 100)
ok("home win shift = K * MOV multiplier * (1 - E_home)", near(u[3], 20 * mult * (1 - e_home)))
ok("update is zero-sum", near(u[1] + u[2], 3000))
un <- env$elo_update_game(1500, 1500, 110, 100, neutral = TRUE)
ok("neutral site drops home court", near(un[3], 20 * ((13)^0.8 / 7.5) * 0.5))
games <- data.frame(game_id = c("a", "b", "c"), game_date = as.Date("2026-10-20") + c(0, 0, 3),
                    home = c("AAA", "CCC", "BBB"), away = c("BBB", "DDD", "AAA"),
                    home_pts = c(100, 90, 120), away_pts = c(95, 99, 100))
built <- env$elo_build_season(games, prior_games = NULL, season = 2027, end_date = as.Date("2026-10-30"),
                              cache_path = tempfile(fileext = ".rds"))
d <- built$daily
ok("daily series has a seed row the day before the first game", min(d$date) == as.Date("2026-10-19"))
ok("one row per team per day", nrow(d) == 4L * 12L)
ok("flat seed when no prior season", built$seed_method == "flat_1500" && all(d$elo[d$date == min(d$date)] == 1500))
ok("league mean stays 1500 every day", all(abs(tapply(d$elo, d$date, mean) - 1500) < 1e-9))
ch <- env$elo_changes(d, as.Date("2026-10-30"), days = c(7L, 14L))
ok("7d change = rating on end date minus rating 7 days earlier",
   near(ch$elo_change_7d[ch$team == "AAA"],
        d$elo[d$team == "AAA" & d$date == as.Date("2026-10-30")] - d$elo[d$team == "AAA" & d$date == as.Date("2026-10-23")]))
ok("14d change before the season falls back to the seed row",
   near(ch$elo_change_14d[ch$team == "AAA"], d$elo[d$team == "AAA" & d$date == as.Date("2026-10-30")] - 1500))
prior <- data.frame(game_id = "p", game_date = as.Date("2026-03-01"), home = "AAA", away = "BBB",
                    home_pts = 130, away_pts = 90)
b2 <- env$elo_build_season(games, prior_games = prior, season = 2027)
fin <- attr(env$elo_run_games(prior), "final")
ok("carry-over seed = 0.75 * final + 0.25 * 1500", near(b2$seed[["AAA"]], 0.75 * fin[["AAA"]] + 0.25 * 1500))

# Elo games from the panel: one row per game, neutral-site games included.
# g1: home game (AAA at home vs BBB). g2: neutral game, home-flagged team sorts
# second (ZZZ "home" vs AAA). g3: neutral game, home-flagged team sorts first.
eg_panel <- data.frame(
  game_id = c("g1", "g1", "g2", "g2", "g3", "g3"),
  game_date = as.Date("2026-11-01") + c(0, 0, 1, 1, 2, 2),
  team = c("AAA", "BBB", "ZZZ", "AAA", "CCC", "ZZZ"),
  opp  = c("BBB", "AAA", "AAA", "ZZZ", "ZZZ", "CCC"),
  home = c(TRUE, FALSE, TRUE, FALSE, TRUE, FALSE),
  pts = c(110, 100, 99, 104, 120, 118), opp_pts = c(100, 110, 104, 99, 118, 120),
  neutral = c(FALSE, FALSE, TRUE, TRUE, TRUE, TRUE), stringsAsFactors = FALSE)
eg <- env$elo_games_from_panel(eg_panel)
ok("elo games: exactly one row per game_id", nrow(eg) == 3L && !anyDuplicated(eg$game_id))
ok("elo games: non-neutral game keeps the home row", eg$home[eg$game_id == "g1"] == "AAA" && !eg$neutral[eg$game_id == "g1"])
ok("elo games: neutral games keep the neutral flag", all(eg$neutral[eg$game_id %in% c("g2", "g3")]))
ok("elo games: neutral game keeps the home-flagged row with its own score",
   identical(eg$home[eg$game_id == "g2"], "ZZZ") && identical(eg$home_pts[eg$game_id == "g2"], 99) && identical(eg$away_pts[eg$game_id == "g2"], 104))
old_filter <- eg_panel[eg_panel$home | (eg_panel$neutral & eg_panel$team < eg_panel$opp), ]
ok("elo games: the previous filter double-counted the neutral game", sum(old_filter$game_id == "g2") == 2L)
eg_noflag <- eg_panel; eg_noflag$home[eg_noflag$game_id == "g2"] <- FALSE
eg2 <- env$elo_games_from_panel(eg_noflag)
ok("elo games: neutral game with no home flag keeps the alphabetically first team",
   nrow(eg2) == 3L && identical(eg2$home[eg2$game_id == "g2"], "AAA"))
dup_panel <- rbind(eg_panel, eg_panel[1, ])
ok("elo games: duplicate game_id stops", inherits(tryCatch(env$elo_games_from_panel(dup_panel), error = function(e) e), "error"))

# --- 6. Change baseline: games before the window ------------------------------
cat("\n[change baseline]\n")
mk_rows_n <- function(n) {
  ids <- sprintf("n%02d", seq_len(n))
  dates <- as.Date("2026-10-20") + 2 * (seq_len(n) - 1L)
  a_pts <- 100 + seq_len(n) * 2; b_pts <- rep(105, n)
  side <- function(team, opp, home, pts, opp_pts, fgm, fta)
    data.frame(game_id = ids, game_date = dates, team = team, team_name = team, team_id = team,
               opp = opp, home = home, pts = pts, opp_pts = opp_pts, fga = 88, fgm = fgm,
               fg3a = 35, fg3m = 12, fta = fta, ftm = round(0.8 * fta), oreb = 10, dreb = 33,
               tov = 13, stringsAsFactors = FALSE)
  home <- rep(c(TRUE, FALSE), length.out = n)
  rbind(side("AAA", "BBB", home, a_pts, b_pts, 38 + seq_len(n) %% 5, 20 + seq_len(n) %% 3),
        side("BBB", "AAA", !home, b_pts, a_pts, 41, 22))
}
pn <- env$build_team_game_panel(mk_rows_n(8))
pn$adj_net <- pn$net; pn$elo_pre <- 1500; pn$elo_post <- 1500
pn$residual_eligible <- FALSE; pn$residual <- NA_real_
sb <- env$window_states(pn, 3L)
a8 <- sb[sb$team == "AAA" & sb$game_index == 8L, ]
a7 <- sb[sb$team == "AAA" & sb$game_index == 7L, ]
pa8 <- pn[pn$team == "AAA", ]
net_of <- function(g) 100 * (sum(g$pts) - sum(g$opp_pts)) / sum(g$poss)
ok("games_before = games played minus the window", a8$games_before == 5L && a7$games_before == 4L)
ok("change = window net minus net over the games BEFORE the window (not the season)",
   near(a8$net_change, net_of(pa8[6:8, ]) - net_of(pa8[1:5, ])))
ok("change is not window minus a season that contains the window",
   !near(a8$net_change, a8$net - a8$net_season))
ok("ORtg / DRtg change use the same baseline",
   near(a8$ortg_change, 100 * sum(pa8$pts[6:8]) / sum(pa8$poss[6:8]) - 100 * sum(pa8$pts[1:5]) / sum(pa8$poss[1:5])) &&
   near(a8$drtg_change, 100 * sum(pa8$opp_pts[6:8]) / sum(pa8$poss[6:8]) - 100 * sum(pa8$opp_pts[1:5]) / sum(pa8$poss[1:5])))
ok("fewer than 5 games before the window: every change is NA",
   is.na(a7$net_change) && is.na(a7$ortg_change) && is.na(a7$drtg_change) && !a7$baseline_ok)
ok("window covering the whole season has no baseline (0 earlier games)",
   all(is.na(sb$net_change[sb$games_before == 0L])) && all(is.na(sb$net_before[sb$games_before == 0L])))
ff <- env$fit_four_factor_model(pn)
dr_null <- env$window_drivers(pa8[5:8, ], pa8[1:4, ], ff, a7$net_change)
ok("drivers with fewer than 5 earlier games: every driver null with the stated reason",
   all(vapply(env$DRIVER_KEYS, function(k) is.null(dr_null[[k]]), logical(1))) &&
   identical(dr_null$null_reason, "too few games before this window") && dr_null$games_before_window == 4L)
dr_ok <- env$window_drivers(pa8[6:8, ], pa8[1:5, ], ff, a8$net_change)
ok("drivers with 5 earlier games are computed against those games",
   is.null(dr_ok$null_reason) && is.numeric(dr_ok$efg_offense) && dr_ok$games_before_window == 5L &&
   near(dr_ok$efg_offense, round(unname(coef(ff)["efg"] * (env$agg_factors(pa8[6:8, ])["efg"] - env$agg_factors(pa8[1:5, ])["efg"])), 2)))

# Trend null: no imputation, the combined score is null and unranked with a reason.
mk_state <- function(n_teams, trend) {
  data.frame(team = sprintf("T%02d", seq_len(n_teams)), games_in_window = 10L, ranked = TRUE,
             adj_form = seq_len(n_teams), net_change = trend, residual = seq_len(n_teams) / 2,
             residual_ranked = TRUE, residual_games = 10L, elo_change_window = rev(seq_len(n_teams)),
             games_before = ifelse(is.na(trend), 3L, 6L), baseline_ok = !is.na(trend), stringsAsFactors = FALSE)
}
ss <- env$score_states(mk_state(6, c(1, 4, 2, NA, 5, 3)))
ok("null trend: z_trend NA (not imputed) and combined score NA", is.na(ss$z_trend[4]) && is.na(ss$combined[4]))
ok("null trend: team gets no combined rank; others are ranked 1..5",
   is.na(ss$combined_rank[4]) && identical(sort(ss$combined_rank[-4]), 1:5))
ok("trend z uses only the teams that have the trend",
   near(ss$z_trend[1], (1 - mean(c(1, 4, 2, 5, 3))) / sd(c(1, 4, 2, 5, 3))))
ok("combined null reason names the missing baseline",
   grepl("too few games before this window \\(3 of 5", env$combined_null_reason(ss[4, ], 10L)))
ok("combined null reason is NULL when the score exists", is.null(env$combined_null_reason(ss[1, ], 10L)))

# --- 7. Default window (80% rule) ---------------------------------------------
cat("\n[default window]\n")
ok("4 of 30 teams at 18 games, all at 10: default 10",
   env$choose_default_window(c(rep(18L, 4), rep(15L, 26))) == 10L)
ok("24 of 30 teams at 18 games: default 18", env$choose_default_window(c(rep(18L, 24), rep(17L, 6))) == 18L)
ok("23 of 30 at 18 games is not enough", env$choose_default_window(c(rep(18L, 23), rep(12L, 7))) == 10L)
ok("23 of 30 at 10 games falls back to 5", env$choose_default_window(c(rep(10L, 23), rep(6L, 7))) == 5L)
ok("no window qualifies: the shortest window", env$choose_default_window(rep(2L, 30)) == 5L)
ok("rule text states the 80% threshold", grepl("80%", env$default_window_rule_text()) && grepl("24 of 30", env$default_window_rule_text()))

# --- 8. Rank-change null reasons ----------------------------------------------
cat("\n[rank-change null reasons]\n")
rc1 <- env$rank_change_null_reasons(NULL, as.Date("2026-11-15"), 10L, 3L, NULL)
ok("no games 7 days ago: both fields get a reason",
   grepl("no games played by 2026-11-15", rc1$rank_7d_ago) && identical(rc1$rank_change_7d, rc1$rank_7d_ago))
prev_unranked <- data.frame(games_in_window = 7L, ranked = FALSE, combined = NA_real_, combined_rank = NA_integer_)
rc2 <- env$rank_change_null_reasons(prev_unranked, as.Date("2026-11-15"), 10L, 3L, NULL)
ok("unranked 7 days ago: reason says so", grepl("^not ranked 7 days ago", rc2$rank_7d_ago) && grepl("fewer than 10 games", rc2$rank_7d_ago))
rc3 <- env$rank_change_null_reasons(ss[1, ], as.Date("2026-11-15"), 10L, NA_integer_, "trend component unavailable")
ok("ranked 7 days ago but no current rank: rank_7d_ago has no reason, the change does",
   is.null(rc3$rank_7d_ago) && grepl("^no current rank", rc3$rank_change_7d))

cat(sprintf("\n%d failure(s)\n", failures))
if (failures > 0L) quit(status = 1L)
