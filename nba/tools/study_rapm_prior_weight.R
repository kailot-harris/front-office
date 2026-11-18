# ==============================================================================
# tools/study_rapm_prior_weight.R
#
# Issue #146: is 25% still the right ensemble weight for prior-season RAPM
# during 2026-27? A hindsight-free study. It changes no published weight.
#
# WHAT IT USES
#   cache/prediction_accuracy_log.rds   the logged weekly forecast. For every
#       LOGGED_PREGAME row written by tools/project_week_predictions.R the log
#       keeps the four weighted component differentials (comp_bottom_up,
#       comp_rapm, comp_shot_fatigue, comp_embeddings), the home-court and
#       schedule terms and the per-game sigma, all frozen at
#       prediction_timestamp. Those are re-blended here for any RAPM weight w.
#   cache/matchups_schedule_2027.rds    tip-off times (no-hindsight check) and
#       each team's games played before a game (decay variant).
#   cache/rapm_ratings.rds              only to report how many rated players
#       were re-attributed to a new team (descriptive, not used in scoring).
#   cache/ensemble_team_ratings.rds     today's daily ensemble, used only to
#       prove that the weight rule at w = 0.25 reproduces today's blend.
#
# WEIGHT RULE
#   RAPM gets w; BPM, shot quality/fatigue and embeddings share (1 - w) in their
#   current 0.35 : 0.20 : 0.20 proportions. Because the log stores
#   comp_k = W0_k * (home_k - away_k) with W0 = (0.35, 0.25, 0.20, 0.20):
#     margin(w) = (w / 0.25) * comp_rapm
#               + ((1 - w) / 0.75) * (comp_bottom_up + comp_shot_fatigue + comp_embeddings)
#               + comp_home_court + comp_schedule (0 where the log records the gap)
#   At w = 0.25 both factors are exactly 1, so margin(0.25) is the logged blend.
#   p(w) = pnorm(margin(w) / sigma_game), sigma_game taken from the log row and
#   held fixed across w (sqrt(11.8^2 + sd_home^2 + sd_away^2), as written by
#   tools/project_week_predictions.R).
#
# Outputs (tools/output/rapm_weight_study/): grid.csv, descent_trace.csv,
#   variants.csv, calibration.csv, no_hindsight_sample.csv, README.md.
# Deterministic: fixed seed, no wall-clock values in any output.
#
# Run from the project root:  Rscript tools/study_rapm_prior_weight.R
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
})

SEED        <- 146L
N_BOOT      <- 2000L
W0          <- c(bottom_up = 0.35, rapm = 0.25, shot_fatigue = 0.20, embeddings = 0.20)
W_LO        <- 0.025
W_HI        <- 0.500
GRID        <- round(seq(W_LO, W_HI, by = 0.025), 3)
FD_H        <- 0.0025     # central-difference half-width
PGD_TOL     <- 1e-5       # stop when |w_{k+1} - w_k| < PGD_TOL
PGD_MAXIT   <- 500L
PGD_ALPHA0  <- 1.0        # initial step per unit gradient; halved until Armijo holds
ARMIJO_C    <- 1e-4
EPS_P       <- 1e-15      # probability clip for log loss
FLAT_TOL    <- 0.001      # grid curve called "flat" when max - min log loss < this
REPRO_TOL_P <- 0.001      # reproduction tolerance on the home win probability
DECAY_TAUS  <- c(2.5, 5, 10, 20, 40, 80, 160)
MIN_GAMES   <- 3L         # hard floor: below this the script refuses to run
TARGET_GAMES <- 250L      # sample size at which the study should be re-run
REPRO_TOL_ENS <- 0.01     # tolerance on today's team ensemble rating (2-dp rounding)

root <- normalizePath(getwd(), winslash = "/")
if (!file.exists(file.path(root, "config.R"))) stop("Run from the project root.")
cache_dir <- file.path(root, "cache")
out_dir   <- file.path(root, "tools", "output", "rapm_weight_study")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

fmt <- function(x, d = 4) formatC(x, format = "f", digits = d)

# ------------------------------------------------------------------------------
# 1. Load the log and keep rows that can be re-blended without hindsight
# ------------------------------------------------------------------------------
log_path <- file.path(cache_dir, "prediction_accuracy_log.rds")
if (!file.exists(log_path)) stop("cache/prediction_accuracy_log.rds not found")
lg <- as.data.frame(readRDS(log_path))

comp_cols <- c("comp_bottom_up", "comp_rapm", "comp_shot_fatigue", "comp_embeddings",
               "comp_home_court", "sigma_game")
lg$game_date <- as.Date(lg$game_date)
lg$has_comps <- Reduce(`&`, lapply(comp_cols, function(c) is.finite(as.numeric(lg[[c]]))))
lg$resolved  <- lg$status == "RESOLVED" & !is.na(lg$target_home_win)

inventory <- lg %>%
  mutate(season_label = ifelse(game_date >= as.Date("2026-07-01"), "2026-27",
                        ifelse(game_date >= as.Date("2025-07-01"), "2025-26",
                        ifelse(game_date >= as.Date("2024-07-01"), "2024-25", "earlier")))) %>%
  group_by(season_label, log_source) %>%
  # resolved_with_components must come before `resolved` is summarised: dplyr
  # evaluates in order, so a later expression would see the scalar total.
  summarise(rows = n(), resolved_with_components = sum(resolved & has_comps),
            resolved = sum(resolved), with_components = sum(has_comps), .groups = "drop") %>%
  select(season_label, log_source, rows, resolved, with_components, resolved_with_components) %>%
  arrange(season_label, log_source)

# Tip-off times from the schedule spine.
sched_path <- file.path(cache_dir, "matchups_schedule_2027.rds")
if (!file.exists(sched_path)) stop("cache/matchups_schedule_2027.rds not found")
sp <- as.data.frame(readRDS(sched_path))
sp$game_id   <- as.character(sp$game_id)
sp$game_date <- as.Date(sp$game_date)
tip_col <- if ("game_date_time" %in% names(sp)) "game_date_time" else "start_date"
tip_raw <- sp[[tip_col]]
sp$tip_utc <- if (inherits(tip_raw, "POSIXct")) {
  as.POSIXct(format(tip_raw, tz = "UTC", usetz = FALSE), tz = "UTC")
} else {
  s <- sub("Z$", "", as.character(tip_raw))
  as.POSIXct(s, format = "%Y-%m-%dT%H:%M", tz = "UTC")
}

d <- lg %>%
  filter(has_comps, resolved) %>%
  mutate(game_id = as.character(game_id))
d$tip_utc <- sp$tip_utc[match(d$game_id, sp$game_id)]
d$pred_utc <- as.POSIXct(format(as.POSIXct(d$prediction_timestamp), tz = "UTC"), tz = "UTC")
d$pregame_ok <- !is.na(d$tip_utc) & !is.na(d$pred_utc) & d$pred_utc < d$tip_utc
n_candidates <- nrow(d)
n_not_pregame <- sum(!d$pregame_ok)
d <- d[d$pregame_ok, , drop = FALSE]
d <- d[order(d$tip_utc, d$game_id), , drop = FALSE]
if (nrow(d) < MIN_GAMES) stop(sprintf("Only %d usable games; too few to study.", nrow(d)))
first_comp_ts <- min(d$pred_utc)

d$y <- as.numeric(d$target_home_win %in% c("Win", "1", "TRUE", "Home", "home"))
d$sched <- ifelse(is.finite(as.numeric(d$comp_schedule)), as.numeric(d$comp_schedule), 0)
d$c_rapm  <- as.numeric(d$comp_rapm)
d$c_other <- as.numeric(d$comp_bottom_up) + as.numeric(d$comp_shot_fatigue) +
  as.numeric(d$comp_embeddings)
d$c_fixed <- as.numeric(d$comp_home_court) + d$sched
d$sigma   <- as.numeric(d$sigma_game)

# Games played before this game, per team, from the schedule spine: completed
# games on earlier dates only (known before tip-off).
done_col <- intersect(c("status_type_completed", "completed"), names(sp))
sp_done <- if (length(done_col)) sp[as.logical(sp[[done_col[1]]]) %in% TRUE, , drop = FALSE] else sp
gp_before <- function(team_short, date) {
  sum(sp_done$game_date < date &
        (sp_done$home_short_display_name == team_short |
           sp_done$away_short_display_name == team_short))
}
d$gp_home <- mapply(gp_before, d$home_team, d$game_date)
d$gp_away <- mapply(gp_before, d$away_team, d$game_date)
d$gp_mean <- (d$gp_home + d$gp_away) / 2

# ------------------------------------------------------------------------------
# 2. Scoring helpers
# ------------------------------------------------------------------------------
prob_w <- function(w, idx = seq_len(nrow(d))) {
  m <- (w / W0[["rapm"]]) * d$c_rapm[idx] + ((1 - w) / (1 - W0[["rapm"]])) * d$c_other[idx] +
    d$c_fixed[idx]
  pnorm(m / d$sigma[idx])
}
ll_vec <- function(p, y) { p <- pmin(pmax(p, EPS_P), 1 - EPS_P); -(y * log(p) + (1 - y) * log(1 - p)) }
metrics <- function(p, y) c(n = length(y), accuracy = mean((p >= 0.5) == (y == 1)),
                           brier = mean((p - y)^2), log_loss = mean(ll_vec(p, y)))
obj <- function(w, idx = seq_len(nrow(d))) mean(ll_vec(prob_w(w, idx), d$y[idx]))

# ------------------------------------------------------------------------------
# 3. Reproduction check at w = 0.25
# ------------------------------------------------------------------------------
stopifnot(identical(W0[["rapm"]] / W0[["rapm"]], 1), identical((1 - 0.25) / (1 - W0[["rapm"]]), 1))
p25 <- prob_w(0.25)
m25 <- d$c_rapm + d$c_other + d$c_fixed
repro_dp  <- max(abs(p25 - as.numeric(d$predicted_home_win_prob)))
repro_dm  <- if ("predicted_margin" %in% names(d) && any(is.finite(as.numeric(d$predicted_margin)))) {
  max(abs(m25 - as.numeric(d$predicted_margin)), na.rm = TRUE)
} else NA_real_
if (repro_dp > REPRO_TOL_P) {
  stop(sprintf("Re-blend at w = 0.25 does not reproduce the logged probability: max |dp| = %.6f", repro_dp))
}
cat(sprintf("[REPRO] n = %d, max |p(0.25) - logged p| = %.6f, max |margin(0.25) - logged margin| = %.4f\n",
            nrow(d), repro_dp, repro_dm))

# Same rule applied to today's daily ensemble (cache/ensemble_team_ratings.rds):
# rating(w) = w * rapm + (1 - w) * (0.35 bu + 0.20 sf + 0.20 emb) / 0.75.
ens_path <- file.path(cache_dir, "ensemble_team_ratings.rds")
repro_ens <- NA_real_
if (file.exists(ens_path)) {
  et <- as.data.frame(readRDS(ens_path))
  blend_ens <- function(w) {
    w * as.numeric(et$rating_rapm) + (1 - w) / (1 - W0[["rapm"]]) *
      (W0[["bottom_up"]] * as.numeric(et$rating_bottom_up) +
         W0[["shot_fatigue"]] * as.numeric(et$rating_shot_fatigue) +
         W0[["embeddings"]] * as.numeric(et$rating_embeddings))
  }
  repro_ens <- max(abs(blend_ens(0.25) - as.numeric(et$ensemble_net_rating)))
  if (repro_ens > REPRO_TOL_ENS) {
    stop(sprintf("Weight rule at w = 0.25 does not reproduce today's ensemble: max |diff| = %.4f", repro_ens))
  }
  cat(sprintf("[REPRO] %d teams, max |rating(0.25) - ensemble_net_rating| = %.4f\n", nrow(et), repro_ens))
}

# No-hindsight check over every scored game (not only the sample).
hrs_before <- as.numeric(difftime(d$tip_utc, d$pred_utc, units = "hours"))
cat(sprintf("[NO-HINDSIGHT] %d of %d scored games forecast before tip-off; min lead %.1f h; RAPM fit season 2025-26\n",
            sum(hrs_before > 0), nrow(d), min(hrs_before)))

# ------------------------------------------------------------------------------
# 4. Grid and projected gradient descent (full sample, in-sample)
# ------------------------------------------------------------------------------
grid_tbl <- do.call(rbind, lapply(GRID, function(w) {
  mt <- metrics(prob_w(w), d$y)
  data.frame(w = w, n_games = mt[["n"]], log_loss = mt[["log_loss"]],
             brier = mt[["brier"]], accuracy = mt[["accuracy"]])
}))
grid_tbl$log_loss_minus_w025 <- grid_tbl$log_loss - grid_tbl$log_loss[grid_tbl$w == 0.25]

curve_shape <- function(ll) {
  k <- length(ll)
  locmin <- which(sapply(seq_len(k), function(i) {
    (i == 1 || ll[i] <= ll[i - 1]) && (i == k || ll[i] <= ll[i + 1])
  }))
  second <- diff(ll, differences = 2)
  shape <- if (max(ll) - min(ll) < FLAT_TOL) "flat"
           else if (length(locmin) > 1) "more than one minimum"
           else if (all(second >= -1e-12)) "convex"
           else "single minimum, not convex everywhere"
  list(shape = shape, n_local_min = length(locmin), range = max(ll) - min(ll))
}
shape_full <- curve_shape(grid_tbl$log_loss)

pgd <- function(start, f) {
  w <- start; trace <- list(); fw <- f(w)
  for (it in seq_len(PGD_MAXIT)) {
    lo <- max(W_LO, w - FD_H); hi <- min(W_HI, w + FD_H)
    g <- (f(hi) - f(lo)) / (hi - lo)
    alpha <- PGD_ALPHA0; w_new <- w; f_new <- fw
    repeat {
      cand <- min(W_HI, max(W_LO, w - alpha * g))
      f_c <- f(cand)
      if (f_c <= fw - ARMIJO_C * g * (w - cand) || alpha < 1e-8) { w_new <- cand; f_new <- f_c; break }
      alpha <- alpha / 2
    }
    trace[[it]] <- data.frame(start = start, iter = it, w = w, log_loss = fw, gradient = g,
                              step = alpha, w_next = w_new)
    step_size <- abs(w_new - w)
    w <- w_new; fw <- f_new
    if (step_size < PGD_TOL) break
  }
  list(w = w, f = fw, trace = do.call(rbind, trace))
}
starts <- c(0.025, 0.25, 0.50)
runs_full <- lapply(starts, pgd, f = function(w) obj(w))
trace_tbl <- do.call(rbind, lapply(runs_full, `[[`, "trace"))
pgd_w <- sapply(runs_full, `[[`, "w"); pgd_f <- sapply(runs_full, `[[`, "f")
best_w <- pgd_w[which.min(pgd_f)]
grid_best_w <- grid_tbl$w[which.min(grid_tbl$log_loss)]
on_boundary <- function(w) abs(w - W_LO) < 1e-4 || abs(w - W_HI) < 1e-4

# Exact argmin used inside the bootstrap (bounded 1-D search, endpoints checked).
argmin_w <- function(idx) {
  f <- function(w) obj(w, idx)
  o <- optimize(f, c(W_LO, W_HI), tol = 1e-5)
  cand <- c(W_LO, o$minimum, W_HI); fv <- sapply(cand, f)
  cand[which.min(fv)]
}

# ------------------------------------------------------------------------------
# 5. Time-ordered split: choose on the earlier half, score on the later half
# ------------------------------------------------------------------------------
n <- nrow(d)
n_train <- floor(n / 2)
idx_tr <- seq_len(n_train); idx_te <- (n_train + 1):n
runs_tr <- lapply(starts, pgd, f = function(w) obj(w, idx_tr))
w_split <- sapply(runs_tr, `[[`, "w")[which.min(sapply(runs_tr, `[[`, "f"))]
split_cut_date <- d$game_date[n_train]

# Decay: w(g) = 0.25 * tau / (tau + g), g = mean games played of the two teams
# before the game (the log stores only the home-minus-away RAPM difference, so
# the decay cannot be applied per team). tau fitted on the earlier half.
prob_decay <- function(tau, idx = seq_len(n)) {
  w <- 0.25 * tau / (tau + d$gp_mean[idx])
  m <- (w / W0[["rapm"]]) * d$c_rapm[idx] + ((1 - w) / (1 - W0[["rapm"]])) * d$c_other[idx] +
    d$c_fixed[idx]
  pnorm(m / d$sigma[idx])
}
tau_ll_tr <- sapply(DECAY_TAUS, function(t) mean(ll_vec(prob_decay(t, idx_tr), d$y[idx_tr])))
tau_fit <- DECAY_TAUS[which.min(tau_ll_tr)]

# ------------------------------------------------------------------------------
# 6. Bootstrap over games
# ------------------------------------------------------------------------------
set.seed(SEED)
boot_idx <- replicate(N_BOOT, sample.int(n, n, replace = TRUE), simplify = FALSE)
ll_mat_full <- function(pfun) {
  # per-game log loss under a variant, full sample
  ll_vec(pfun, d$y)
}
ll25 <- ll_vec(p25, d$y)
boot_best_w <- sapply(boot_idx, argmin_w)
q95 <- function(x) unname(quantile(x, c(0.025, 0.975), type = 7))

variant_probs <- list(
  "w=0.25 (current)"                  = p25,
  "w=0.15"                             = prob_w(0.15),
  "w=0.05"                             = prob_w(0.05),
  "w=best in-sample (PGD)"             = prob_w(best_w),
  "w=chosen on earlier half"           = prob_w(w_split),
  "decay w=0.25*tau/(tau+gp), tau fit on earlier half" = prob_decay(tau_fit)
)
variant_w <- c(0.25, 0.15, 0.05, best_w, w_split, NA)

variants <- do.call(rbind, lapply(seq_along(variant_probs), function(i) {
  p <- variant_probs[[i]]; llv <- ll_vec(p, d$y)
  diffs <- sapply(boot_idx, function(b) mean(llv[b]) - mean(ll25[b]))
  full <- metrics(p, d$y); tr <- metrics(p[idx_tr], d$y[idx_tr]); te <- metrics(p[idx_te], d$y[idx_te])
  data.frame(
    variant = names(variant_probs)[i],
    w = ifelse(is.na(variant_w[i]), NA, round(variant_w[i], 4)),
    n_games = full[["n"]], accuracy = full[["accuracy"]], brier = full[["brier"]],
    log_loss = full[["log_loss"]],
    log_loss_diff_vs_025 = full[["log_loss"]] - mean(ll25),
    diff_ci95_lo = q95(diffs)[1], diff_ci95_hi = q95(diffs)[2],
    n_earlier = tr[["n"]], log_loss_earlier = tr[["log_loss"]], brier_earlier = tr[["brier"]],
    accuracy_earlier = tr[["accuracy"]],
    n_later = te[["n"]], log_loss_later = te[["log_loss"]], brier_later = te[["brier"]],
    accuracy_later = te[["accuracy"]],
    stringsAsFactors = FALSE
  )
}))
best_diff_ci <- unlist(variants[variants$variant == "w=best in-sample (PGD)", c("diff_ci95_lo", "diff_ci95_hi")])
best_w_ci <- q95(boot_best_w)
variants$bootstrap_resamples <- N_BOOT
variants$w_ci95_lo <- ifelse(variants$variant == "w=best in-sample (PGD)", best_w_ci[1], NA)
variants$w_ci95_hi <- ifelse(variants$variant == "w=best in-sample (PGD)", best_w_ci[2], NA)
split_diff_later <- variants$log_loss_later[variants$variant == "w=chosen on earlier half"] -
  variants$log_loss_later[variants$variant == "w=0.25 (current)"]

# ------------------------------------------------------------------------------
# 7. Calibration (10 equal-width probability bins)
# ------------------------------------------------------------------------------
calib <- do.call(rbind, lapply(c("w=0.25 (current)", "w=best in-sample (PGD)"), function(v) {
  p <- variant_probs[[v]]
  bin <- cut(p, breaks = seq(0, 1, 0.1), include.lowest = TRUE, right = FALSE)
  data.frame(variant = v, bin = levels(bin)) %>%
    left_join(data.frame(bin = as.character(bin), p = p, y = d$y) %>%
                group_by(bin) %>%
                summarise(n_games = n(), mean_pred_home_win = mean(p),
                          observed_home_win_rate = mean(y), .groups = "drop"),
              by = "bin") %>%
    mutate(n_games = ifelse(is.na(n_games), 0L, n_games))
}))

# ------------------------------------------------------------------------------
# 8. No-hindsight sample and RAPM provenance
# ------------------------------------------------------------------------------
rapm_note <- "cache/rapm_ratings.rds not present"
rapm_path <- file.path(cache_dir, "rapm_ratings.rds")
rapm_label <- NA_character_
if (file.exists(rapm_path)) {
  rr <- readRDS(rapm_path)
  rapm_label <- if ("season_label" %in% names(rr)) as.character(unique(rr$season_label))[1]
                else if (!is.null(attr(rr, "season_label"))) attr(rr, "season_label") else NA_character_
  if ("on_current_roster" %in% names(rr)) {
    rapm_note <- sprintf("%d rated players; %d matched to a current roster (team re-attributed to it), %d unmatched (keep 2025-26 possession-modal team)",
                         nrow(rr), sum(rr$on_current_roster %in% TRUE), sum(!(rr$on_current_roster %in% TRUE)))
  } else rapm_note <- sprintf("%d rated players; no on_current_roster column", nrow(rr))
}
samp_idx <- unique(round(seq(1, n, length.out = min(12, n))))
nh <- data.frame(
  game_id = d$game_id[samp_idx], game_date = format(d$game_date[samp_idx]),
  home_team = d$home_team[samp_idx], away_team = d$away_team[samp_idx],
  log_source = d$log_source[samp_idx],
  prediction_timestamp_utc = format(d$pred_utc[samp_idx], "%Y-%m-%d %H:%M:%S"),
  tipoff_utc = format(d$tip_utc[samp_idx], "%Y-%m-%d %H:%M:%S"),
  hours_before_tip = round(as.numeric(difftime(d$tip_utc[samp_idx], d$pred_utc[samp_idx], units = "hours")), 1),
  rapm_fit_season = ifelse(is.na(rapm_label), "2025-26 (RAPM_SEASON default)", rapm_label),
  gp_home_before = d$gp_home[samp_idx], gp_away_before = d$gp_away[samp_idx],
  stringsAsFactors = FALSE
)

# Re-run date: the schedule date on which TARGET_GAMES games will have been
# played since component logging began (first game with logged components),
# assuming the weekly forecast keeps logging components for every game.
last_date <- max(d$game_date)
first_comp_date <- min(d$game_date)
future <- sp[sp$game_date >= first_comp_date, , drop = FALSE]
future <- future[order(future$game_date), , drop = FALSE]
rerun_date <- if (nrow(future) >= TARGET_GAMES) format(future$game_date[TARGET_GAMES]) else format(max(sp$game_date))

# ------------------------------------------------------------------------------
# 9. Recommendation (follows from the intervals)
# ------------------------------------------------------------------------------
ci_has_zero <- best_diff_ci[1] <= 0 && best_diff_ci[2] >= 0
recommendation <- if (ci_has_zero) {
  sprintf("Not enough evidence yet: keep 25%% for now and re-run on or after %s.", rerun_date)
} else if (best_diff_ci[2] < 0 && split_diff_later < 0) {
  sprintf("Change it: the data favour w = %s over 0.25, in-sample and on the later half. A weight change needs its own owner-approved PR.", fmt(best_w, 3))
} else {
  sprintf("Not enough evidence yet: the in-sample gain does not hold on the later half. Keep 25%% and re-run on or after %s.", rerun_date)
}

# ------------------------------------------------------------------------------
# 10. Write outputs
# ------------------------------------------------------------------------------
wcsv <- function(x, f) {
  num <- vapply(x, is.numeric, logical(1))
  x[num] <- lapply(x[num], function(v) signif(round(v, 6), 8))
  utils::write.csv(x, file.path(out_dir, f), row.names = FALSE, na = "")
}
wcsv(grid_tbl, "grid.csv")
wcsv(trace_tbl, "descent_trace.csv")
wcsv(variants, "variants.csv")
wcsv(calib, "calibration.csv")
wcsv(nh, "no_hindsight_sample.csv")
wcsv(as.data.frame(inventory), "log_inventory.csv")

src_counts <- table(d$log_source)
src_txt <- paste(sprintf("%s = %d", names(src_counts), as.integer(src_counts)), collapse = ", ")
vt <- variants
vt_md <- paste0(
  "| Variant | w | Games | Accuracy | Brier | Log loss | Log-loss diff vs 0.25 (95% CI) | Later-half log loss |\n",
  "|---|---|---|---|---|---|---|---|\n",
  paste(sprintf("| %s | %s | %d | %s | %s | %s | %s (%s to %s) | %s |",
                vt$variant, ifelse(is.na(vt$w), "varies", fmt(vt$w, 3)), vt$n_games,
                fmt(vt$accuracy, 3), fmt(vt$brier, 4), fmt(vt$log_loss, 4),
                fmt(vt$log_loss_diff_vs_025, 4), fmt(vt$diff_ci95_lo, 4), fmt(vt$diff_ci95_hi, 4),
                fmt(vt$log_loss_later, 4)), collapse = "\n"))
trace_md <- paste(sprintf("- start %s: %d iterations, ended at w = %s (log loss %s)",
                          fmt(starts, 3), sapply(runs_full, function(r) nrow(r$trace)),
                          fmt(pgd_w, 4), fmt(pgd_f, 5)), collapse = "\n")

readme <- c(
  "# Prior-season RAPM weight study (issue #146)",
  "",
  "Generated by `tools/study_rapm_prior_weight.R`. **This study changes no published ensemble weight.** A weight change would be a separate, owner-approved pull request.",
  "",
  "## Recommendation",
  "",
  recommendation,
  "",
  "Applies to: the **logged weekly forecast** path (`tools/project_week_predictions.R`, rows with `log_source = LOGGED_PREGAME` in `cache/prediction_accuracy_log.rds`). The daily ensemble baseline (`build_matchups_dataset.R`, `projection_basis = primary_ensemble`) re-reads today's `cache/ensemble_team_ratings.rds`, which is overwritten each run and keeps no per-game history, so it cannot be scored without hindsight and no result here rests on it. Both paths use the same four-component blend and the same margin-to-probability mapping, so the direction of the finding carries over, but it was measured on the weekly path only.",
  "",
  "## Data",
  "",
  sprintf("- Games scored: %d resolved 2026-27 games, %s to %s. Log sources: %s.", n, format(min(d$game_date)), format(last_date), src_txt),
  sprintf("- Candidate rows with all components and a result: %d; dropped because the forecast was not timestamped before tip-off: %d.", n_candidates, n_not_pregame),
  sprintf("- **Sample gap.** The weekly forecast began storing the four component differentials only with the forecast made %s UTC. Earlier 2026-27 `LOGGED_PREGAME` rows (%d resolved) keep only the final margin and probability, so they cannot be re-weighted and are excluded, not imputed. %d further component rows are still pending (games not yet played). With %d games every interval below is very wide; the study is mainly the machinery to re-run.",
          format(first_comp_ts, "%Y-%m-%d %H:%M"),
          sum(lg$log_source == "LOGGED_PREGAME" & lg$resolved & !lg$has_comps & lg$game_date >= as.Date("2026-07-01")),
          sum(lg$has_comps & !lg$resolved), n),
  "- Full inventory of the log by season and source: `log_inventory.csv`.",
  sprintf("- Reproduction at w = 0.25: max |re-blended p - logged p| = %s (tolerance %s; logged p is rounded to 4 dp, components to 4 dp). Max |re-blended margin - logged margin| = %s points.", format(signif(repro_dp, 3)), REPRO_TOL_P, ifelse(is.na(repro_dm), "n/a", format(signif(repro_dm, 3)))),
  sprintf("- Reproduction of today's daily ensemble (`cache/ensemble_team_ratings.rds`, 30 teams): max |rating(0.25) - ensemble_net_rating| = %s (tolerance %s; ratings are stored to 2 dp).", ifelse(is.na(repro_ens), "n/a (file absent)", format(signif(repro_ens, 3))), REPRO_TOL_ENS),
  "",
  "## Method",
  "",
  "- Weight rule: RAPM gets w, the other three share 1 - w in 0.35 : 0.20 : 0.20. At w = 0.25 this is today's blend (scale factors w/0.25 and (1-w)/0.75 both equal 1).",
  sprintf("- Probability: pnorm(margin / sigma_game) with home court %s points and the logged per-game sigma_game = sqrt(11.8^2 + sd_home^2 + sd_away^2) (MARGIN_SIGMA = 11.8), held fixed across w. The schedule term is the logged comp_schedule, or 0 where the log records it as unavailable.", "2.40"),
  sprintf("- Objective: mean log loss of the home win probability (clipped at %g). Brier score and accuracy reported alongside.", EPS_P),
  sprintf("- Search: projected gradient descent on [%s, %s], central-difference gradient (h = %s, one-sided at a bound), step alpha * gradient with alpha starting at %s and halved until the Armijo condition (c = %g) holds, then projected onto the interval; stop when |w_next - w| < %g. Starts at 0.025, 0.25 and 0.50. Confirmed against a 20-point grid at 0.025 steps (`grid.csv`); full trace in `descent_trace.csv`.", W_LO, W_HI, FD_H, PGD_ALPHA0, ARMIJO_C, PGD_TOL),
  sprintf("- Time-ordered split: games ordered by tip-off; w chosen on the earlier %d games (through %s) and scored on the later %d.", n_train, format(split_cut_date), n - n_train),
  sprintf("- Bootstrap: %d resamples of games (seed %d). For each resample the minimizing w is found by bounded 1-D search; the log-loss difference is paired (same resampled games for both weights).", N_BOOT, SEED),
 paste("- Decay variant: w(g) = 0.25 * tau / (tau + g), where g is the mean number of games the two teams had played before the game (from the schedule spine). The log stores only the home-minus-away RAPM difference, so the decay is applied per game, not per team. tau was chosen from {", paste(DECAY_TAUS, collapse = ", "), "} on the earlier half (larger tau = slower decay; tau -> infinity is the fixed 0.25).", sep = ""),
  "",
  "## Results",
  "",
  "Gradient descent:",
  "",
  trace_md,
  "",
  sprintf("- Minimizing w (in-sample): **%s**; grid minimum at %s. %s", fmt(best_w, 4), fmt(grid_best_w, 3),
          if (on_boundary(best_w)) sprintf("The minimum sits on the boundary (%s).", fmt(best_w, 3)) else "The minimum is inside the interval, not on a boundary."),
  sprintf("- Curve shape over the grid: **%s** (%d local minimum/minima; log loss varies by %s across the range).", shape_full$shape, shape_full$n_local_min, fmt(shape_full$range, 5)),
  sprintf("- Bootstrap 95%% interval for the minimizing w: %s to %s.", fmt(best_w_ci[1], 3), fmt(best_w_ci[2], 3)),
  sprintf("- Bootstrap 95%% interval for log loss(best w) - log loss(0.25): %s to %s. %s", fmt(best_diff_ci[1], 4), fmt(best_diff_ci[2], 4),
          if (ci_has_zero) "The interval includes 0: the best w and 0.25 cannot be told apart on these games." else "The interval excludes 0."),
  sprintf("- Split: w chosen on the earlier half = %s; on the later half its log loss minus that of 0.25 = %s.", fmt(w_split, 4), fmt(split_diff_later, 4)),
  sprintf("- Decay: tau fitted on the earlier half = %s.%s", tau_fit, if (tau_fit == max(DECAY_TAUS)) " This is the largest tau tried (the slowest decay, closest to a fixed 0.25), so the fit sits at the edge of its grid." else if (tau_fit == min(DECAY_TAUS)) " This is the smallest tau tried, so the fit sits at the edge of its grid." else ""),
  "",
  vt_md,
  "",
  "Calibration (10 probability bins): `calibration.csv`. Variants with intervals and both halves: `variants.csv`.",
  "",
  "## Earlier seasons (2024-25, 2025-26)",
  "",
  "Not run. Re-blending without hindsight needs each component's rating as it stood before each game. The 2024-25 and 2025-26 rows in the log are `BACKTEST_SEEDED` / `BACKTEST_PREWEEK` rows with no component values (see `log_inventory.csv`). `cache/ensemble_team_ratings.rds` is overwritten on every run and keeps no history, and the committed per-game web artifacts carry component values only from 2026-11-16 onward. Rebuilding point-in-time BPM, shot quality and fatigue, and embeddings ratings for those seasons would mean re-running those engines on truncated data, which this study does not do. Prior-season RAPM alone could be fitted for those seasons, but without the other three components as of each game the blend could not be re-weighted honestly.",
  "",
  "## How RAPM is assigned today",
  "",
  "- RAPM is fitted on 2025-26 possessions (`rapm_engine.R:136-138`, RAPM_SEASON = 2026 in hoopR end-year numbering).",
  "- Players who changed teams: `rapm_engine.R:452-499` re-attributes each rated player to the team whose current roster (`cache/active_rosters_cache.rds`) has an unambiguous full-name match; unmatched or ambiguous names keep their 2025-26 possession-modal team.",
  sprintf("- In the copied cache: %s.", rapm_note),
  "- Rookies and anyone with no 2025-26 possessions have no row in `rapm_ratings.rds`, so they contribute nothing: `season_simulator.R:221-228` sums the top 10 rated players listed on each team (sorted by total_rapm, not minutes) with fixed rotation weights; a team with fewer than 5 rated players gets 0. The team values are then centred (`season_simulator.R:234`).",
  "- Position-based constants where RAPM is missing (reported, not fixed; neither feeds the ensemble RAPM component): `build_player_dna_dataset.R:199` (dRAPM 0.85 C / 0.25 F / -0.15 otherwise) and `build_defense_dataset.R:211-215` (same constants).",
  "",
  "## No-hindsight check",
  "",
  "Every scored row has prediction_timestamp before the scheduled tip-off (rows that do not are dropped and counted above). Components were frozen in the log at prediction time; RAPM is from the prior season. Sample in `no_hindsight_sample.csv`.",
  "",
  sprintf("Re-run on or after %s: by then about %d games will have been played since component logging began, if the weekly forecast keeps logging components for every game.", rerun_date, TARGET_GAMES)
)
writeLines(readme, file.path(out_dir, "README.md"), useBytes = TRUE)

cat(sprintf("[RESULT] n = %d, best_w = %.4f (grid %.3f), shape = %s, boundary = %s\n", n, best_w, grid_best_w,
            shape_full$shape, on_boundary(best_w)))
cat(sprintf("[RESULT] best_w CI95 = [%.4f, %.4f]; diff CI95 = [%.5f, %.5f]; w_split = %.4f; tau = %s\n",
            best_w_ci[1], best_w_ci[2], best_diff_ci[1], best_diff_ci[2], w_split, tau_fit))
cat(sprintf("[RESULT] %s\n", recommendation))
