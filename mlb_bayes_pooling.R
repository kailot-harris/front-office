# ==============================================================================
# mlb_bayes_pooling.R — Closed-Form Hierarchical Empirical Bayes Partial Pooling
# Path: c:/Users/kailo/kayceeslices/MLB Analytics/mlb_bayes_pooling.R
#
# Phase 3 Specialty Models (Issue #25)
#
# Closed-form empirical Bayes partial-pooling engine for MLB batter, pitcher,
# and team talent metrics without heavy MCMC or Stan compiler dependencies.
#
# Literature Precedent:
#   - Jensen, S. T., McShane, B. B., & Wyner, A. J. (2009). "Hierarchical
#     Bayesian Modeling of Hitting Performance in Baseball." Bayesian Analysis,
#     4(4), 631-652.
#   - Deshpande, S. K., & Wyner, A. J. (2017). "A Hierarchical Bayesian Model
#     of Pitch Framing." Journal of Quantitative Analysis in Sports, 13(3), 95-112.
#
# Mathematical Formulation:
#   1. Group Adjustment: Park Neutralization
#      Observed metrics are neutralized by 3-year venue factors from fg_park.rds
#      prior to empirical Bayes shrinkage.
#   2. Rate Metrics (K%, BB%):
#      Beta-Binomial conjugate updating:
#      Prior: Beta(alpha_0, beta_0) where mu_0 = alpha_0 / (alpha_0 + beta_0),
#             M_0 = alpha_0 + beta_0
#      Posterior mean: theta_hat = (k_i + alpha_0) / (n_i + alpha_0 + beta_0)
#      Shrinkage factor B = n_i / (n_i + M_0), monotonic with sample size n_i.
#   3. Continuous Metrics (wOBA, ISO, xFIP):
#      Normal-Normal / James-Stein shrinkage:
#      True talent theta_i ~ N(mu_0, sigma_0^2), y_i ~ N(theta_i, sigma_i^2 / n_i)
#      Posterior mean: theta_hat = B * y_i + (1 - B) * mu_0
#      Shrinkage factor B = sigma_0^2 / (sigma_0^2 + sigma_i^2 / n_i)
#      Shrinkage toward league average: (1 - B) strictly decreases with n_i.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "mlb_bayes_pooling.R"

# ------------------------------------------------------------------------------
# Park Factors Integration: Group Adjustment Factors (Line 50)
# ------------------------------------------------------------------------------
# Park factors from fg_park.rds (3-year venue factors) are integrated as
# group adjustment factors prior to shrinkage to neutralize venue effects
# per Jensen, McShane, & Wyner (2009).

FG_TEAM_TO_PARK <- c(
  "LAA" = "Angels",       "BAL" = "Orioles",      "BOS" = "Red Sox",
  "CHW" = "White Sox",    "CWS" = "White Sox",    "CLE" = "Guardians",
  "DET" = "Tigers",       "KCR" = "Royals",       "KC"  = "Royals",
  "MIN" = "Twins",        "NYY" = "Yankees",      "OAK" = "Athletics",
  "ATH" = "Athletics",    "SEA" = "Mariners",     "TBR" = "Rays",
  "TB"  = "Rays",         "TEX" = "Rangers",      "TOR" = "Blue Jays",
  "ARI" = "Diamondbacks", "AZ"  = "Diamondbacks", "ATL" = "Braves",
  "CHC" = "Cubs",         "CIN" = "Reds",         "COL" = "Rockies",
  "MIA" = "Marlins",      "HOU" = "Astros",       "LAD" = "Dodgers",
  "MIL" = "Brewers",      "WSN" = "Nationals",    "WSH" = "Nationals",
  "NYM" = "Mets",         "PHI" = "Phillies",     "PIT" = "Pirates",
  "STL" = "Cardinals",    "SDP" = "Padres",       "SD"  = "Padres",
  "SFG" = "Giants",       "SF"  = "Giants"
)

#' Load Park Factors from Cache as Group Adjustment Factors
#'
#' @param season Target season integer (default 2024)
#' @return Named list containing lookup table and venue factor vector
load_park_factors <- function(season = 2024) {
  park_file <- cache_path("stats_sync", "fg_park.rds", create = FALSE)
  if (!file.exists(park_file)) {
    log_warn("fg_park.rds cache missing; defaulting park factors to neutral (1.0)",
             script = .LOG_SCRIPT)
    return(list(park_df = NULL, lookup_3yr = numeric(0)))
  }
  
  pk <- as.data.frame(readRDS(park_file))
  if (nrow(pk) == 0 || !"home_team" %in% names(pk)) {
    return(list(park_df = pk, lookup_3yr = numeric(0)))
  }
  
  # Filter by season if multiple seasons are present
  if ("season" %in% names(pk) && any(pk$season == season)) {
    pk <- pk[pk$season == season, ]
  }
  
  # 3-year venue factors from fg_park.rds
  pf_col <- if ("3yr" %in% names(pk)) "3yr" else if ("basic_5yr" %in% names(pk)) "basic_5yr" else names(pk)[3]
  lookup_3yr <- setNames(as.numeric(pk[[pf_col]]), as.character(pk[["home_team"]]))
  
  list(park_df = pk, lookup_3yr = lookup_3yr)
}

#' Neutralize Metrics by Park Factors (Group Adjustment Prior to Shrinkage)
#'
#' @param team_vec Character vector of team abbreviations
#' @param park_lookup Named numeric vector of 3-year park factors (100 = neutral)
#' @return Numeric vector of park multipliers centered around 1.0
get_team_park_factors <- function(team_vec, park_lookup) {
  n <- length(team_vec)
  pf_season <- rep(1.0, n)
  if (length(park_lookup) == 0) return(pf_season)
  
  for (i in seq_len(n)) {
    tm <- as.character(team_vec[i] %||% "")
    if (!nzchar(tm) || tm == "- - -") {
      pf_season[i] <- 1.0
      next
    }
    park_name <- FG_TEAM_TO_PARK[[tm]] %||% tm
    pf_3yr_val <- park_lookup[[park_name]] %||% 100
    # Balanced season schedule: 50% home, 50% neutral road games
    pf_season[i] <- (pf_3yr_val / 100.0 + 1.0) / 2.0
  }
  pf_season
}

# ------------------------------------------------------------------------------
# Closed-Form Empirical Bayes Estimation Functions
# ------------------------------------------------------------------------------

#' Fit Beta-Binomial Prior Hyperparameters via Method of Moments
#'
#' @param successes Numeric vector of observed counts or effective successes
#' @param trials Numeric vector of trials (e.g. PA or TBF)
#' @param min_trials Minimum trials threshold to include in prior estimation
#' @return Named list with mu_0, M_0, alpha_0, beta_0
fit_beta_binomial_prior <- function(successes, trials, min_trials = 50) {
  valid <- !is.na(successes) & !is.na(trials) & (trials >= min_trials)
  if (sum(valid) < 10) {
    # Fallback to general sabermetric baseline
    return(list(mu_0 = 0.22, M_0 = 50, alpha_0 = 11, beta_0 = 39))
  }
  
  p_obs <- successes[valid] / trials[valid]
  mu_0  <- weighted.mean(p_obs, trials[valid], na.rm = TRUE)
  var_p <- var(p_obs, na.rm = TRUE)
  
  # Method of moments for Beta distribution: Var(p) = mu(1-mu) / (M + 1)
  denom <- max(1e-6, var_p)
  M_0   <- max(10, (mu_0 * (1 - mu_0) / denom) - 1)
  
  alpha_0 <- mu_0 * M_0
  beta_0  <- (1 - mu_0) * M_0
  
  list(mu_0 = mu_0, M_0 = M_0, alpha_0 = alpha_0, beta_0 = beta_0)
}

#' Closed-Form Beta-Binomial Shrinkage Update
#'
#' @param successes Numeric vector of park-neutralized successes
#' @param trials Numeric vector of trials (PA or TBF)
#' @param alpha_0 Prior alpha parameter
#' @param beta_0 Prior beta parameter
#' @return Named list of B (weight on sample), shrink (weight on prior), and pooled_rate
update_beta_binomial <- function(successes, trials, alpha_0, beta_0) {
  M_0    <- alpha_0 + beta_0
  mu_0   <- alpha_0 / M_0
  n_safe <- pmax(0, trials, na.rm = TRUE)
  
  # Shrinkage factor B = n_i / (n_i + M_0)
  B <- n_safe / (n_safe + M_0)
  shrink <- M_0 / (n_safe + M_0)
  
  # Posterior mean = (k_i + alpha_0) / (n_i + alpha_0 + beta_0)
  #                = B * (k_i / n_i) + (1 - B) * mu_0
  k_safe <- pmax(0, successes, na.rm = TRUE)
  pooled_rate <- (k_safe + alpha_0) / (n_safe + M_0)
  
  # Zero-trial guard
  zero_idx <- is.na(trials) | trials == 0
  if (any(zero_idx)) {
    B[zero_idx] <- 0
    shrink[zero_idx] <- 1.0
    pooled_rate[zero_idx] <- mu_0
  }
  
  list(B = B, shrink = shrink, pooled_rate = pooled_rate, mu_0 = mu_0, M_0 = M_0)
}

#' Fit Normal-Normal Prior via Empirical Bayes Variance Decomposition
#'
#' Estimates true talent variance sigma_0^2 and per-observation variance sigma^2
#' using the regression relationship: E[(y_i - mu_0)^2 | n_i] = sigma_0^2 + sigma^2 / n_i
#'
#' @param values Numeric vector of continuous observations (e.g. wOBA, ISO, xFIP)
#' @param n_trials Numeric vector of sample sizes (PA or TBF)
#' @param min_trials Minimum sample size threshold
#' @return Named list with mu_0, sigma0_sq, sigma_sq
fit_normal_normal_prior <- function(values, n_trials, min_trials = 30) {
  valid <- !is.na(values) & !is.na(n_trials) & (n_trials >= min_trials)
  if (sum(valid) < 10) {
    # Robust fallback
    return(list(mu_0 = mean(values, na.rm = TRUE), sigma0_sq = 0.001, sigma_sq = 0.40))
  }
  
  val_v <- values[valid]
  n_v   <- n_trials[valid]
  mu_0  <- weighted.mean(val_v, n_v, na.rm = TRUE)
  
  # OLS fit on squared deviations vs 1/n
  sq_dev <- (val_v - mu_0)^2
  inv_n  <- 1.0 / n_v
  fit    <- tryCatch(lm(sq_dev ~ inv_n), error = function(e) NULL)
  
  if (!is.null(fit) && !is.na(coef(fit)[1]) && coef(fit)[1] > 0 && coef(fit)[2] > 0) {
    sigma0_sq <- as.numeric(coef(fit)[1])
    sigma_sq  <- as.numeric(coef(fit)[2])
  } else {
    # Direct method of moments fallback
    total_var <- var(val_v, na.rm = TRUE)
    sigma0_sq <- max(1e-5, total_var * 0.4)
    sigma_sq  <- max(1e-3, total_var * median(n_v) * 0.6)
  }
  
  list(mu_0 = mu_0, sigma0_sq = sigma0_sq, sigma_sq = sigma_sq)
}

#' Closed-Form Normal-Normal / James-Stein Shrinkage Update
#'
#' Formula: B = sigma_0^2 / (sigma_0^2 + sigma_i^2 / n_i)
#' Posterior mean: theta_hat = B * y_i + (1 - B) * mu_0
#'
#' @param values Numeric vector of park-neutralized observations
#' @param n_trials Numeric vector of sample sizes (PA or TBF)
#' @param mu_0 League prior mean
#' @param sigma0_sq True talent between-player variance
#' @param sigma_sq Within-player per-event sampling variance
#' @return Named list of B (weight on sample), shrink (weight on prior), and pooled_val
update_normal_normal <- function(values, n_trials, mu_0, sigma0_sq, sigma_sq) {
  n_safe <- pmax(1e-6, n_trials, na.rm = TRUE)
  
  # Shrinkage factor B = sigma_0^2 / (sigma_0^2 + sigma_i^2 / n_i)
  sampling_var <- sigma_sq / n_safe
  B <- sigma0_sq / (sigma0_sq + sampling_var)
  shrink <- 1.0 - B
  
  # Posterior mean theta_hat = B * y_i + (1 - B) * mu_0
  v_safe <- ifelse(is.na(values), mu_0, values)
  pooled_val <- B * v_safe + (1.0 - B) * mu_0
  
  # Zero-sample guard
  zero_idx <- is.na(n_trials) | n_trials == 0
  if (any(zero_idx)) {
    B[zero_idx] <- 0
    shrink[zero_idx] <- 1.0
    pooled_val[zero_idx] <- mu_0
  }
  
  list(B = B, shrink = shrink, pooled_val = pooled_val, mu_0 = mu_0,
       sigma0_sq = sigma0_sq, sigma_sq = sigma_sq)
}

# ------------------------------------------------------------------------------
# Core Pooling Runners: Batters & Pitchers
# ------------------------------------------------------------------------------

#' Pool Batter Metrics using Closed-Form Empirical Bayes Shrinkage
#'
#' @param df_batters Data.frame of FanGraphs batter leaders
#' @param park_lookup Named vector of 3-year park factors
#' @param season Target season
#' @return Tibble of partially-pooled batter metrics
pool_batters <- function(df_batters, park_lookup, season = 2024) {
  df <- as.data.frame(df_batters)
  if (nrow(df) == 0) return(tibble::tibble())
  
  # 1. Park Factors Integration (Group Adjustment prior to shrinkage)
  df$park_factor <- get_team_park_factors(df$team_name, park_lookup)
  
  # Park-neutralize metrics
  df$wOBA_adj   <- df$wOBA / df$park_factor
  df$ISO_adj    <- df$ISO / df$park_factor
  df$K_pct_adj  <- df$K_pct / df$park_factor
  df$BB_pct_adj <- df$BB_pct / df$park_factor
  
  # Effective counts
  k_count  <- df$K_pct_adj * df$PA
  bb_count <- df$BB_pct_adj * df$PA
  
  # 2. Beta-Binomial shrinkage for rate stats (K%, BB%)
  prior_k  <- fit_beta_binomial_prior(k_count, df$PA, min_trials = 50)
  post_k   <- update_beta_binomial(k_count, df$PA, prior_k$alpha_0, prior_k$beta_0)
  
  prior_bb <- fit_beta_binomial_prior(bb_count, df$PA, min_trials = 50)
  post_bb  <- update_beta_binomial(bb_count, df$PA, prior_bb$alpha_0, prior_bb$beta_0)
  
  # 3. James-Stein / Normal-Normal shrinkage for continuous metrics (wOBA, ISO)
  prior_woba <- fit_normal_normal_prior(df$wOBA_adj, df$PA, min_trials = 30)
  post_woba  <- update_normal_normal(df$wOBA_adj, df$PA, prior_woba$mu_0,
                                     prior_woba$sigma0_sq, prior_woba$sigma_sq)
  
  prior_iso  <- fit_normal_normal_prior(df$ISO_adj, df$PA, min_trials = 30)
  post_iso   <- update_normal_normal(df$ISO_adj, df$PA, prior_iso$mu_0,
                                     prior_iso$sigma0_sq, prior_iso$sigma_sq)
  
  # Assemble output tibble
  out <- tibble::tibble(
    playerid        = df$playerid,
    PlayerName      = df$PlayerName,
    team_name       = df$team_name,
    PA              = df$PA,
    season          = season,
    park_factor     = round(df$park_factor, 4),
    
    # Raw observed
    wOBA_raw        = df$wOBA,
    ISO_raw         = df$ISO,
    K_pct_raw       = df$K_pct,
    BB_pct_raw      = df$BB_pct,
    
    # Park-neutralized
    wOBA_adj        = round(df$wOBA_adj, 4),
    ISO_adj         = round(df$ISO_adj, 4),
    K_pct_adj       = round(df$K_pct_adj, 4),
    BB_pct_adj      = round(df$BB_pct_adj, 4),
    
    # Shrinkage factors (B = weight on sample, shrink = 1 - B weight on prior)
    B_wOBA          = round(post_woba$B, 4),
    shrink_wOBA     = round(post_woba$shrink, 4),
    B_ISO           = round(post_iso$B, 4),
    shrink_ISO      = round(post_iso$shrink, 4),
    B_K_pct         = round(post_k$B, 4),
    shrink_K_pct    = round(post_k$shrink, 4),
    B_BB_pct        = round(post_bb$B, 4),
    shrink_BB_pct   = round(post_bb$shrink, 4),
    
    # Partially-pooled estimates
    wOBA_pooled     = round(post_woba$pooled_val, 4),
    ISO_pooled      = round(post_iso$pooled_val, 4),
    K_pct_pooled    = round(post_k$pooled_rate, 4),
    BB_pct_pooled   = round(post_bb$pooled_rate, 4)
  )
  
  out
}

#' Pool Pitcher Metrics using Closed-Form Empirical Bayes Shrinkage
#'
#' @param df_pitchers Data.frame of FanGraphs pitcher leaders
#' @param park_lookup Named vector of 3-year park factors
#' @param season Target season
#' @return Tibble of partially-pooled pitcher metrics
pool_pitchers <- function(df_pitchers, park_lookup, season = 2024) {
  df <- as.data.frame(df_pitchers)
  if (nrow(df) == 0) return(tibble::tibble())
  
  # Sample size: TBF (Total Batters Faced), fallback to IP * 4.25
  sample_size <- if ("TBF" %in% names(df)) {
    as.numeric(df$TBF)
  } else if ("IP" %in% names(df)) {
    round(as.numeric(df$IP) * 4.25)
  } else {
    rep(100, nrow(df))
  }
  sample_size[is.na(sample_size)] <- 0
  df$n_sample <- sample_size
  
  # 1. Park Factors Integration (Group Adjustment prior to shrinkage)
  df$park_factor <- get_team_park_factors(df$team_name, park_lookup)
  
  # Park-neutralize metrics (xFIP in run-heavy park is deflated toward neutral)
  df$xFIP_adj   <- df$xFIP / df$park_factor
  df$K_pct_adj  <- df$K_pct / df$park_factor
  df$BB_pct_adj <- df$BB_pct / df$park_factor
  
  # Effective counts
  k_count  <- df$K_pct_adj * df$n_sample
  bb_count <- df$BB_pct_adj * df$n_sample
  
  # 2. Beta-Binomial shrinkage for rate stats (K%, BB%)
  prior_k  <- fit_beta_binomial_prior(k_count, df$n_sample, min_trials = 50)
  post_k   <- update_beta_binomial(k_count, df$n_sample, prior_k$alpha_0, prior_k$beta_0)
  
  prior_bb <- fit_beta_binomial_prior(bb_count, df$n_sample, min_trials = 50)
  post_bb  <- update_beta_binomial(bb_count, df$n_sample, prior_bb$alpha_0, prior_bb$beta_0)
  
  # 3. James-Stein / Normal-Normal shrinkage for xFIP
  prior_xfip <- fit_normal_normal_prior(df$xFIP_adj, df$n_sample, min_trials = 30)
  post_xfip  <- update_normal_normal(df$xFIP_adj, df$n_sample, prior_xfip$mu_0,
                                     prior_xfip$sigma0_sq, prior_xfip$sigma_sq)
  
  # Assemble output tibble
  out <- tibble::tibble(
    playerid        = df$playerid,
    PlayerName      = df$PlayerName,
    team_name       = df$team_name,
    IP              = df$IP,
    TBF             = df$n_sample,
    season          = season,
    park_factor     = round(df$park_factor, 4),
    
    # Raw observed
    xFIP_raw        = df$xFIP,
    K_pct_raw       = df$K_pct,
    BB_pct_raw      = df$BB_pct,
    
    # Park-neutralized
    xFIP_adj        = round(df$xFIP_adj, 4),
    K_pct_adj       = round(df$K_pct_adj, 4),
    BB_pct_adj      = round(df$BB_pct_adj, 4),
    
    # Shrinkage factors (B = weight on sample, shrink = 1 - B weight on prior)
    B_xFIP          = round(post_xfip$B, 4),
    shrink_xFIP     = round(post_xfip$shrink, 4),
    B_K_pct         = round(post_k$B, 4),
    shrink_K_pct    = round(post_k$shrink, 4),
    B_BB_pct        = round(post_bb$B, 4),
    shrink_BB_pct   = round(post_bb$shrink, 4),
    
    # Partially-pooled estimates
    xFIP_pooled     = round(post_xfip$pooled_val, 4),
    K_pct_pooled    = round(post_k$pooled_rate, 4),
    BB_pct_pooled   = round(post_bb$pooled_rate, 4)
  )
  
  out
}

#' Compute Bayes Team Talent Ratings by Aggregating Partially-Pooled Player Metrics
#'
#' @param pooled_batters Data.frame of pooled batters
#' @param pooled_pitchers Data.frame of pooled pitchers
#' @param season Target season
#' @return Tibble of team-level talent ratings across all 30 MLB franchises
compute_bayes_team_talent <- function(pooled_batters, pooled_pitchers, season = 2024) {
  b <- as.data.frame(pooled_batters)
  p <- as.data.frame(pooled_pitchers)
  
  # Identify all 30 MLB franchises
  all_teams <- sort(setdiff(unique(c(b$team_name, p$team_name)), c("- - -", "", NA)))
  
  team_rows <- lapply(all_teams, function(tm) {
    b_tm <- b[b$team_name == tm & !is.na(b$PA) & b$PA > 0, ]
    p_tm <- p[p$team_name == tm & !is.na(p$TBF) & p$TBF > 0, ]
    
    bat_pa  <- sum(b_tm$PA)
    w_woba  <- if (nrow(b_tm) > 0) weighted.mean(b_tm$wOBA_pooled, b_tm$PA, na.rm = TRUE) else 0.310
    w_iso   <- if (nrow(b_tm) > 0) weighted.mean(b_tm$ISO_pooled, b_tm$PA, na.rm = TRUE) else 0.150
    w_bat_k <- if (nrow(b_tm) > 0) weighted.mean(b_tm$K_pct_pooled, b_tm$PA, na.rm = TRUE) else 0.225
    w_bat_bb<- if (nrow(b_tm) > 0) weighted.mean(b_tm$BB_pct_pooled, b_tm$PA, na.rm = TRUE) else 0.080
    
    pitch_tbf <- sum(p_tm$TBF)
    pitch_ip  <- sum(as.numeric(p_tm$IP), na.rm = TRUE)
    w_xfip    <- if (nrow(p_tm) > 0) weighted.mean(p_tm$xFIP_pooled, p_tm$TBF, na.rm = TRUE) else 4.10
    w_pit_k   <- if (nrow(p_tm) > 0) weighted.mean(p_tm$K_pct_pooled, p_tm$TBF, na.rm = TRUE) else 0.220
    w_pit_bb  <- if (nrow(p_tm) > 0) weighted.mean(p_tm$BB_pct_pooled, p_tm$TBF, na.rm = TRUE) else 0.085
    
    data.frame(
      team_name           = tm,
      season              = season,
      total_bat_pa        = bat_pa,
      team_wOBA_pooled    = round(w_woba, 4),
      team_ISO_pooled     = round(w_iso, 4),
      team_bat_K_pct      = round(w_bat_k, 4),
      team_bat_BB_pct     = round(w_bat_bb, 4),
      total_pitch_tbf     = pitch_tbf,
      total_pitch_ip      = round(pitch_ip, 1),
      team_xFIP_pooled    = round(w_xfip, 4),
      team_pitch_K_pct    = round(w_pit_k, 4),
      team_pitch_BB_pct   = round(w_pit_bb, 4),
      stringsAsFactors    = FALSE
    )
  })
  
  df_teams <- dplyr::bind_rows(team_rows)
  
  # Compute composite standardized talent z-scores
  w_sd <- sd(df_teams$team_wOBA_pooled, na.rm = TRUE) %||% 0.010
  x_sd <- sd(df_teams$team_xFIP_pooled, na.rm = TRUE) %||% 0.250
  if (w_sd == 0) w_sd <- 0.010
  if (x_sd == 0) x_sd <- 0.250
  
  df_teams$offense_talent_z  <- round((df_teams$team_wOBA_pooled - mean(df_teams$team_wOBA_pooled)) / w_sd, 3)
  # Pitching z-score inverted: lower xFIP means stronger pitching
  df_teams$pitching_talent_z <- round(-(df_teams$team_xFIP_pooled - mean(df_teams$team_xFIP_pooled)) / x_sd, 3)
  df_teams$net_talent_score  <- round(df_teams$offense_talent_z + df_teams$pitching_talent_z, 3)
  
  # Rank franchises by overall net talent
  df_teams <- df_teams %>%
    dplyr::arrange(desc(net_talent_score)) %>%
    dplyr::mutate(talent_rank = dplyr::row_number())
  
  tibble::as_tibble(df_teams)
}

# ------------------------------------------------------------------------------
# Top-Level Callable Stage Runner
# ------------------------------------------------------------------------------

#' Run Closed-Form Hierarchical Empirical Bayes Pooling for Batters, Pitchers, and Teams
#'
#' @param seasons Integer vector of seasons (defaults to 2024)
#' @param force_refresh If TRUE, recomputes bypassing existing cache files
#' @return Named list of pooled data frames (batters, pitchers, team_talent)
run_bayes_pooling <- function(seasons = 2024, force_refresh = FALSE) {
  season <- seasons[1] %||% 2024
  
  cache_batters <- cache_path("specialty", "bayes_pooled_batters.rds")
  cache_pitch   <- cache_path("specialty", "bayes_pooled_pitchers.rds")
  cache_teams   <- cache_path("specialty", "bayes_team_talent.rds")
  
  if (!force_refresh && file.exists(cache_batters) && file.exists(cache_pitch) && file.exists(cache_teams)) {
    log_info(sprintf("Empirical Bayes pooling cache found for season %d; loading existing results.", season),
             script = .LOG_SCRIPT)
    return(invisible(list(
      batters     = readRDS(cache_batters),
      pitchers    = readRDS(cache_pitch),
      team_talent = readRDS(cache_teams)
    )))
  }
  
  log_info(sprintf("Running closed-form Empirical Bayes pooling for season %d (force_refresh=%s)...",
                   season, force_refresh), script = .LOG_SCRIPT)
  
  # 1. Ingest required caches
  fg_bat_file   <- cache_path("stats_sync", "fg_batters.rds", create = FALSE)
  fg_pitch_file <- cache_path("stats_sync", "fg_pitchers.rds", create = FALSE)
  
  if (!file.exists(fg_bat_file) || !file.exists(fg_pitch_file)) {
    stop("Required FanGraphs stats caches (fg_batters.rds / fg_pitchers.rds) not found. Run mlb_stats_sync.R first.")
  }
  
  df_batters  <- readRDS(fg_bat_file)
  df_pitchers <- readRDS(fg_pitch_file)
  
  # 2. Load Park Factors
  pk_info     <- load_park_factors(season = season)
  park_lookup <- pk_info$lookup_3yr
  
  # 3. Partially-pool Batters and Pitchers
  pooled_batters  <- pool_batters(df_batters, park_lookup, season = season)
  pooled_pitchers <- pool_pitchers(df_pitchers, park_lookup, season = season)
  
  # 4. Aggregate Team Talent
  team_talent     <- compute_bayes_team_talent(pooled_batters, pooled_pitchers, season = season)
  
  # 5. Persist Output Caches
  saveRDS(pooled_batters, cache_batters)
  saveRDS(pooled_pitchers, cache_pitch)
  saveRDS(team_talent, cache_teams)
  
  log_info(sprintf("Saved Bayes pooled estimates: %d batters, %d pitchers, %d teams.",
                   nrow(pooled_batters), nrow(pooled_pitchers), nrow(team_talent)),
           script = .LOG_SCRIPT,
           out_batters = cache_batters,
           out_pitchers = cache_pitch,
           out_teams = cache_teams)
  
  invisible(list(
    batters     = pooled_batters,
    pitchers    = pooled_pitchers,
    team_talent = team_talent
  ))
}
