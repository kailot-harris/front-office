# ==============================================================================
# player_props_engine.R (WNBA port)
# Phase 4 (T4) — Zero-Inflated Negative Binomial (ZINB) & PRA Alpha Engine
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/player_props_engine.R
#
# ZINB pricing math (dzinb/pzinb/pzinb_over/price_prop_zinb) is ported BYTE-FOR-BYTE
# unchanged from the NBA original — it is sport-agnostic count-model math with no
# NBA-specific constants.
#
# *** UPDATE (Task P3-2.3, 2026-09-15): Empirical Parameterization ***
# The dispersion (theta) and zero-inflation (pi_0) constants were derived from
# the real WNBA rotation distribution in `cache/player_box_scores_cache.rds`.
# Logic:
#   - pi_0 = empirical proportion of zero-observations for the stat.
#   - theta = mu^2 / (Var(X) - mu), derived from rotation-player distributions.
#
# REAL BUG FIX (per REPO_MAP.md §6/§9 and task_assignments.md's T4 brief — this is
# the one thing this file is required to actually fix rather than reproduce):
# the NBA original's `generate_active_props_table()` reads `cache/active_rosters.rds`,
# but the NBA `sync_rosters.R` writes `cache/active_rosters_cache.rds` — those two
# filenames never match, so the NBA props engine ALWAYS silently falls back to its
# fabricated roster, even though a real roster cache sits right next to it on disk.
# This WNBA port reads the EXACT filename T1's sync_rosters.R actually wrote:
# `cache/active_rosters_cache.rds` (209 rows, verified in task_assignments.md's T1
# Handoff Notes) — the filename mismatch bug is FIXED here, not reproduced.
#
# SECOND REAL FIX beyond the filename (required for the fix above to be more than
# cosmetic): T1's `active_rosters_cache.rds` schema is `team_abbreviation, team_name,
# team_id, player_id, player_name, position, jersey` — it has NO per-player stat-mean
# columns (pts_mu/reb_mu/etc.), unlike what the NBA original's `generate_active_props_table()`
# implicitly assumed a "real" roster cache would already contain. Simply fixing the
# filename would have loaded a real roster with no usable stat projections and
# crashed downstream (`p$pts_mu` would be NULL for every row). Instead, real
# per-player stat means are computed here from T1's real
# `cache/player_box_scores_cache.rds` (44,675 rows, 2019-2026), joined to the roster
# on `player_id == athlete_id` (both are real ESPN athlete IDs per T1's Handoff
# Notes), averaged over CURRENT_SEASON's real games. This is what actually lets the
# props engine price real WNBA players off real 2026-season per-game production
# instead of always falling back to synthetic data.
#
# Roster fallback per-team player count shrunk from the NBA original's `1:8`
# (hardcoded literal) to `config.R`'s WNBA_ROTATION_SIZE constant (8, chosen by T2 to
# match its own rotation-depth choice in roster_bottom_up_engine.R — see
# task_assignments.md T2 Handoff Notes) referenced by name, not re-hardcoded, and the
# fallback team list is WNBA's real 15 franchises (WNBA_TEAMS) instead of 30 NBA
# teams. NOTE: 8 happens to numerically match the NBA original's hardcoded 8 — the
# "shrink" here is about correctness (WNBA_ROTATION_SIZE is a named, greppable,
# empirically-chosen WNBA constant) and about using the real 15-team list, not about
# the raw number changing.
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/WNBA Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(jsonlite)
})

source("config.R")
# FINDING H-2 (Phase 4): the RAPM<->roster join lives in exactly one place now.
# Do not reimplement it here — see rapm_join_utils.R's header for why.
source("rapm_join_utils.R")

# FINDING M-6 (Phase 4 Wave 4): this file carried its own unhardened scalar %||%
# (errors on a length>1 vector), identical to the app.R/market_odds_engine.R copies
# M-6 fixed. Source the single canonical hardened definition instead of restating it.
source("logging_utils.R")

if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)

message(">>> [PROPS] Initializing WNBA Zero-Inflated Negative Binomial (ZINB) Props Engine...")

# Category Dispersion Parameters (Theta) — derived empirically from WNBA rotation data (2026-09-15).
# Low theta = high overdispersion; Large theta -> Poisson limit
PROP_DISPERSION <- list(
  "PTS"  = 2.4,
  "REB"  = 2.8,
  "AST"  = 2.1,
  "FG3M" = 1.4,
  "STL"  = 3.9,
  "BLK"  = 1.0
)

# Zero-inflation structural propensity parameters (pi_0) — derived empirically from WNBA rotation data (2026-09-15).
ZERO_INFLATION_PI <- list(
  "PTS"  = 0.08,
  "REB"  = 0.08,
  "AST"  = 0.19,
  "FG3M" = 0.49,
  "STL"  = 0.43,
  "BLK"  = 0.66
)

# ------------------------------------------------------------------------------
# ZINB Probability Functions (ported byte-for-byte, sport-agnostic)
# ------------------------------------------------------------------------------

dzinb <- function(x, mu, theta, pi_zero = 0.0) {
  # Handle vector mu/theta by using ifelse
  p_nb <- dnbinom(x, size = theta, mu = mu)
  prob <- (1 - pi_zero) * p_nb

  # For x == 0, we add the zero-inflation probability
  # Use logical indexing to handle vectors of x
  if (length(x) > 0) {
    zero_idx <- (x == 0)
    if (any(zero_idx)) {
      prob[zero_idx] <- pi_zero + (1 - pi_zero) * dnbinom(0, size = theta, mu = mu)[zero_idx]
    }
  }

  # Final guard for invalid mu/theta (should be handled by input, but for safety:)
  prob <- ifelse(mu <= 0 | theta <= 0, as.numeric(x == 0), prob)
  return(prob)
}

pzinb <- function(q, mu, theta, pi_zero = 0.0) {
  if (q < 0) return(0)
  k_vals <- 0:floor(q)
  sum(dzinb(k_vals, mu, theta, pi_zero))
}

pzinb_over <- function(line, mu, theta, pi_zero = 0.0) {
  floor_line <- floor(line)
  1 - pzinb(floor_line, mu, theta, pi_zero)
}

# Vectorize the CDF functions to handle vectors of q/line and mu
pzinb_vec <- Vectorize(pzinb)
pzinb_over_vec <- Vectorize(pzinb_over)

# ------------------------------------------------------------------------------
# RAPM-based Opponent Adjustment for Props (Task P3-2.4)
# ------------------------------------------------------------------------------
# FINDING H-2 (docs/SECURITY_TECHNICAL_REVIEW.md): this function used to left_join()
# active_rosters to rapm_df keyed on the raw player_id column of each,
# which hard-errored EVERY NIGHT ("Can't join `x$player_id` with `y$player_id` due to
# incompatible types: <integer> vs <character>") and was swallowed by run_stage()'s
# fail-safe tryCatch, leaving data/latest_player_props.rds frozen at 2026-09-14 09:51.
# The two caches use disjoint ID schemes (zero overlap even coerced to one type).
# Fixed by calling the shared join_rapm_to_roster() helper, which joins on
# (team full name, normalized last name) AND resolves the 15 (team, last_name)
# collision groups on the RAPM side to one row each — critical here, because this
# function builds a POSSESSION-WEIGHTED aggregate and a naive fan-out join would
# double-count the duplicated players' possessions (see rapm_join_utils.R header).
#
# Returns one row per WNBA franchise with `def_rapm` = possession-weighted mean of
# the team's rostered players' `drapm`. The league centre used by
# adjust_mu_for_opponent() is attached as the "league_avg_def" attribute.
#
# *** drapm SIGN CONVENTION (GitHub issue #79) ***
# In cache/rapm_ratings.rds, `total_rapm == orapm + drapm`. rapm_engine.R negates
# the ridge's defensive coefficient block before export, so `drapm` is an IMPACT
# quantity on the conventional orientation: HIGHER drapm = BETTER defender, and 0 is
# a league-average defence (the block is also league-centred, issue #71 fix A).
#
# HISTORICAL NOTE — the PRE-#79 convention, for anyone reading an older cache or an
# older revision of this file: `drapm` used to be exported un-negated, so the total
# was `orapm - drapm` and LOWER drapm meant the better defender. That is no longer
# true anywhere in this repo. The flip is exactly ranking-neutral — `orapm - d_raw`
# is identically `orapm + (-d_raw)` — so no player's total_rapm or rank moved; only
# the standalone `drapm` column's sign, and `OPP_DEF_MU_SLOPE`'s sign below, changed.
# Earlier revisions also described an uncentred all-positive `drapm` level (min
# -0.70, max 15.75, mean 7.12); that predates issue #71's centring.
#
# Nothing in the aggregation below is sign-sensitive: adjust_mu_for_opponent()
# consumes only the DIFFERENCE `opp_def_rapm - league_avg_def`, where both terms come
# from the same `drapm` column (league_avg_def is recomputed from the team aggregates
# below, not hardcoded), so the adjustment is shift-invariant by construction and the
# negation simply flips the bracketed difference — which is why negating
# OPP_DEF_MU_SLOPE alongside it leaves every multiplier bit-identical. Team-level
# centring below is still load-bearing: the possession-weighted team mean differs
# from the player-level mean (it was 9.99 vs 7.12 before centring, and differs from 0
# by the same gap after), so the team aggregates are NOT automatically mean-zero just
# because the player column is.
get_team_def_rapm <- function(active_rosters) {
  rapm_path <- CACHE_RAPM_RATINGS

  neutral <- function(v) {
    out <- tibble(team_name = unname(WNBA_TEAMS), def_rapm = as.numeric(v))
    attr(out, "league_avg_def") <- as.numeric(v)
    out
  }

  if (!file.exists(rapm_path)) {
    message("[PROPS WARNING] cache/rapm_ratings.rds not found — opponent adjustment disabled (neutral multiplier).")
    return(neutral(1))
  }
  rapm_df <- readRDS(rapm_path)

  joined <- join_rapm_to_roster(active_rosters, rapm_df, matched_only = TRUE)

  if (nrow(joined) == 0 || !all(c("drapm", "n_def_poss") %in% names(joined))) {
    message("[PROPS WARNING] RAPM/roster join produced no usable rows — opponent adjustment disabled (neutral multiplier).")
    return(neutral(mean(rapm_df$drapm, na.rm = TRUE)))
  }

  team_def <- joined |>
    group_by(team_name) |>
    summarise(
      def_rapm = sum(drapm * n_def_poss, na.rm = TRUE) / sum(n_def_poss, na.rm = TRUE),
      .groups = "drop"
    ) |>
    filter(is.finite(def_rapm))

  # M-4 CENTRING FIX. (Numbers below are from the pre-issue-#71 uncentred cache; the
  # argument is unchanged after centring, only shifted — the player-level and
  # possession-weighted-team-level means still differ by the same ~2.9.)
  # The old code centred on `mean(rapm_df$drapm)` = 7.12, a
  # PLAYER-level mean over all 430 RAPM rows including deep-bench/low-possession
  # players. The possession-weighted mean of the 15 real TEAM aggregates is 9.99.
  # Centring a team-level quantity on a player-level mean made every one of the 15
  # opponents score as "above average", i.e. the adjustment had a large baked-in
  # bias instead of being mean-zero across the league. Centre on the team mean.
  league_avg_def <- mean(team_def$def_rapm, na.rm = TRUE)
  if (!is.finite(league_avg_def)) league_avg_def <- mean(rapm_df$drapm, na.rm = TRUE)

  out <- tibble(team_name = unname(WNBA_TEAMS)) |>
    left_join(team_def, by = "team_name") |>
    mutate(def_rapm = coalesce(def_rapm, league_avg_def))

  attr(out, "league_avg_def") <- league_avg_def
  out
}

# Fractional change in a player's projected mean per +1.00 of opponent team
# possession-weighted `drapm`. DERIVED EMPIRICALLY (M-4), not asserted:
#
#   Within-player fixed-effects regression on the real cache/player_box_scores_cache.rds,
#   seasons 2024-2026, 16,657 player-games / 267 players with >= 5 games. Response is
#   each player's points minus their own mean (so player quality is differenced out);
#   regressor is the opponent's possession-weighted team drapm, centred on the league
#   team mean.
#
#   RE-DERIVED 2026-10-23 against the post-#76 caches. Reproduce with
#   tools/rederive_m4_slope.R, which prints all five figures below plus a
#   significance-gated verdict:
#
#     absolute scale   : -0.4987 pts per +1 drapm  (SE 0.0634, |t| = 7.86, p = 3.9e-15)
#     + minutes control: -0.5475  (SE 0.0588, |t| = 9.31, p = 1.4e-20)
#                                 (so it is not a playing-time artifact)
#     / mean points 8.768                        -> -0.0569 fractional per unit
#     direct within-player FRACTIONAL regression : -0.0504 per unit
#                                                  (SE 0.0096, |t| = 5.26, p = 1.5e-07)
#     season-2026-only absolute slope            : -0.4355 (|t| = 4.60, p = 4.3e-06,
#                                                  n = 5,910) -- same sign
#
#   Team-level corroboration (2026, points allowed per game vs. def_rapm):
#     slope -3.55 pts allowed per +1 def_rapm, r = -0.579 (n = 15 teams).
#
#   NEGATIVE because `drapm` is a defensive IMPACT measure (issue #79: higher =
#   better defender), so facing a higher-drapm opponent SUPPRESSES a player's output.
#   The signs flipped at #79; the magnitudes did not flip with them — they GREW.
#
#   SUPERSEDED FIGURES, kept so each change stays auditable. Two generations now:
#
#     gen 1, original derivation: -0.2591 absolute / -0.0296 via mean points /
#       -0.0256 direct fractional / -0.2598 for 2026 alone / -2.26 and r = -0.675 at
#       team level (written up with the opposite signs, pre-#79).
#     gen 2, re-derived 2026-10-22 on the post-#79/#81 cache: -0.4159 / -0.0474 /
#       -0.0409 / -0.3676 / -3.13 and r = -0.652. Adopted at 03bb12e. That drift was
#       NOT a convention or cache artifact — the identical regression against the
#       pre-#79, pre-centring cache also returned |0.4160|, so it was accumulated
#       2026 data since gen 1.
#
#   Gen 3 (above) has a DIFFERENT cause, and it is worth not conflating them: the
#   data is unchanged from gen 2 (same 16,657 player-games, same mean points 8.768),
#   but issue #76 centred the ridge target, which re-split every player's O/D rating
#   by exposure and so MOVED THE REGRESSOR ITSELF. The team aggregates this slope is
#   measured against are post-#76 values; the league team mean def_rapm is now
#   +0.1892. 1.23x on the shipped estimand is the measured consequence of that
#   re-split, not new data and not a correction of an error. All three generations
#   agree in sign at p < 1e-6; only the size has moved, twice, for two unrelated
#   reasons.
#
#   We take the direct fractional estimate, -0.0504, since it is the estimand that
#   matches the multiplicative form actually used. The absolute-scale estimate
#   (-0.0569) is the corroborating upper bound; both are the same sign at p < 1e-7.
#   Adopting -0.0504 over -0.0409 moves a projection by at most 1.14% on a single
#   team (Dallas Wings, the league's weakest defence on the post-#76 aggregates) and
#   leaves the clamp binding for 0 of 15 teams, so no projection is clamp-limited by
#   the change. NOTE that tools/rederive_m4_slope.R's own gate reads "within 25% of
#   shipped; no action indicated" at this ratio — adoption here was a deliberate
#   owner decision to keep the constant matched to the post-#76 regressor rather
#   than a threshold firing.
# OPP_DEF_MU_SLOPE defined centrally in config.R (GitHub issue #82)
# Clamp bounds: +/-15%. Re-measured 2026-10-23 under the -0.0504 slope and the
# post-#76 cache: the unclamped estimate spans 0.95x (Washington Mystics, the
# strongest defense) to 1.06x (Dallas Wings, the weakest) across the 15 real 2026
# team aggregates, so the clamp still does not bind on real data for any team
# — it exists purely so that a future degenerate RAPM cache cannot swing a
# projection arbitrarily (the OLD formula's raw ratio spanned roughly 0x to 2.2x and
# would have flipped a projection's sign outright on a negative team aggregate).
# OPP_DEF_MU_CLAMP defined centrally in config.R (GitHub issue #82)

adjust_mu_for_opponent <- function(base_mu, opp_def_rapm, league_avg_def) {
  # FINDING M-4 (docs/SECURITY_TECHNICAL_REVIEW.md). The previous implementation was
  #   base_mu * (opp_def_rapm / league_avg_def)
  # carrying a comment that asserted the formula was backwards and then shipped it
  # anyway "because the prompt says so". That rationale is deleted; the direction is
  # now settled against real data (see OPP_DEF_MU_SLOPE's derivation above).
  #
  # WHAT THE DATA ACTUALLY SAYS. Since issue #79, `drapm` is a defensive IMPACT measure
  # (total_rapm = orapm + drapm, HIGHER drapm = BETTER defense), and the measured
  # within-player slope on it is NEGATIVE (-0.50 pts per +1 opponent drapm, p = 3.9e-15,
  # re-measured 2026-10-23 on the post-#76 cache; it read -0.26 at the original
  # derivation and -0.42 at 03bb12e — see OPP_DEF_MU_SLOPE's SUPERSEDED FIGURES):
  # facing a HIGH-drapm (i.e. STRONG) defense lowers a player's output, and facing a
  # LOW-drapm (i.e. WEAK) defense raises it. That is the correct, intuitive behaviour,
  # and it now reads the intuitive way too — negative slope against a
  # better-is-higher defensive rating.
  #
  # The M-4 finding predates that flip: it was measured on the un-negated
  # points-allowed `drapm` and written up as a POSITIVE +0.26. Nothing about the
  # finding changed — the regressor's sign did, so the shipped slope's sign did with
  # it (see OPP_DEF_MU_SLOPE above), leaving every multiplier identical. What M-4
  # genuinely fixed was elsewhere: an uncentred ratio over a player-level league mean
  # (see get_team_def_rapm()), and no clamp over a denominator that the cache allows
  # to approach zero.
  #
  # Now ADDITIVE-in-log-space (a multiplier centred on 1.0 built by ADDING a centred
  # deviation) rather than a raw ratio, which removes the division entirely and hence
  # the near-zero-denominator blowup the review flagged.
  if (!is.finite(league_avg_def)) return(base_mu)
  ratio <- 1 + OPP_DEF_MU_SLOPE * (opp_def_rapm - league_avg_def)
  ratio <- pmin(pmax(ratio, OPP_DEF_MU_CLAMP[1]), OPP_DEF_MU_CLAMP[2])
  ratio <- ifelse(is.finite(ratio), ratio, 1)
  base_mu * ratio
}

# ------------------------------------------------------------------------------
# Shot-Mix (rim-attempt share) Scoring-Efficiency Adjustment for PTS props
# (research task, 2026-09-17) — see docs/pbp_shot_mix_regression_findings.md for
# the full write-up. Added ALONGSIDE the RAPM opponent adjustment above, never
# touching that code path (per explicit instruction). Applies to PTS pricing
# ONLY: the underlying signal (rim shots are the highest-efficiency shot type)
# has no theoretical link to REB/AST/FG3M/STL/BLK, so it is not wired into those.
#
# METHODOLOGY (mirrors OPP_DEF_MU_SLOPE's rigor exactly):
#   Per-player-per-game panel built directly from CACHE_PBP_RAW (763,018 real
#   ESPN events, 2019-2026), re-deriving that game's pct_rim with the EXACT same
#   type_text keyword buckets pbp_engine.R already ships (rim = Layup/Dunk/
#   Putback/Tip Shot/Tip-In, out of 2PA attempts only), joined to that game's
#   real points/minutes from cache/player_box_scores_cache.rds on the CONFIRMED
#   direct (game_id, athlete_id) key -- both caches are ESPN-backed integer IDs
#   in the same namespace (empirically verified: 99.8% of box game_ids found in
#   the PBP game_id set; 83.2% of box player-games matched a PBP player-game row,
#   the unmatched 16.8% being real 0-FGA player-games that never appear as a
#   shooter event, which is expected and correctly excluded rather than a join
#   failure).
#
#   Filtered to player-games with >= 3 FGA (so pct_rim is not a 0/1 artifact of
#   1-2 shot attempts) and players with >= 5 such qualifying games (same
#   >= 5-games threshold player_props_engine.R/OPP_DEF_MU_SLOPE already uses
#   elsewhere in this repo) -> 13,037 player-games across 235 distinct players.
#
#   WITHIN-PLAYER fixed-effects regression (player-demeaned points/pct_rim/
#   minutes, so player-level scoring ability is differenced out exactly like
#   OPP_DEF_MU_SLOPE's methodology; cross-checked against an explicit
#   `lm(points ~ pct_rim + minutes + factor(athlete_id))` on the same panel,
#   which reproduces the identical pct_rim coefficient (0.9586) to 4 decimal
#   places, confirming the demeaning shortcut is not silently biased):
#
#     absolute scale    : +0.9586 pts per +1.0 pct_rim (full 0->1 range),
#                          controlling for minutes (SE 0.1630, t = +5.88,
#                          p = 4.2e-09), n = 13,037 player-games / 235 players.
#     direct fractional  : +0.1174 fractional pts per +1.0 pct_rim, controlling
#                          for minutes (SE 0.0160, t = +7.33, p = 2.5e-13) --
#                          this is the estimand used below, matching the
#                          multiplicative form actually applied (same choice
#                          OPP_DEF_MU_SLOPE made between its absolute and
#                          fractional estimates).
#     no-minutes-control : +1.0416 pts per +1.0 pct_rim (t = +5.56, p = 2.8e-08)
#                          -- same sign/significance without the control, so the
#                          effect is not an artifact of the minutes control.
#
#   Sign is theoretically sensible: rim shots are the highest-efficiency, lowest-
#   variance shot type, so a player scores MORE than their own average in a game
#   where a larger share of their (non-3PT) attempts came at the rim.
#
#   CROSS-SECTIONAL CORROBORATION CHECK CAME BACK THE OPPOSITE SIGN, AND THAT IS
#   EXPECTED, NOT A CONTRADICTION: player-season pct_rim vs. season PPG (current-
#   season players, >= 5 games) is NEGATIVELY correlated (r = -0.138, p = 0.0026).
#   That is a BETWEEN-player comparison confounded by role/usage (low-usage bigs
#   who rarely shoot outside the paint have a high season pct_rim but score less
#   than high-usage perimeter scorers who take a lot of pull-ups/step-backs) --
#   precisely the confound within-player fixed effects are designed to remove.
#   The within-player estimate above is the causally relevant one for adjusting
#   a specific player's own projection; the negative cross-sectional number is
#   reported here for transparency, not used for anything.
#
#   DECISION: p = 2.5e-13 at n = 13,037 comfortably clears the p < 0.05 bar and
#   the sign matches theory once the within-player differencing is applied ->
#   wired in below, additive-in-log-space centred multiplier exactly like
#   adjust_mu_for_opponent(), composed multiplicatively ON TOP of (not replacing)
#   the opponent adjustment.
SHOT_MIX_PTS_SLOPE <- 0.1174
# Clamp bounds: +/-10%. Real current-roster players' season-aggregated pct_rim
# (cache/player_pbp_features.rds, players with >= 20 FGA, n = 184) ranges from
# 0.127 to 0.955 around a league mean of 0.593, which maps to an UNCLAMPED ratio
# range of only 0.945x-1.042x -- the clamp does not bind on real data, exactly
# like OPP_DEF_MU_CLAMP; it exists purely so a future degenerate/corrupted PBP
# features cache cannot swing a projection arbitrarily.
SHOT_MIX_PTS_CLAMP <- c(0.90, 1.10)

adjust_mu_for_shot_mix <- function(base_mu, player_pct_rim, league_avg_pct_rim) {
  # Fail-safe, mirrors adjust_mu_for_opponent(): if the league average isn't a
  # real finite number (e.g. cache/player_pbp_features.rds is missing/empty),
  # no-op rather than fabricate an adjustment.
  if (!is.finite(league_avg_pct_rim)) return(base_mu)
  ratio <- 1 + SHOT_MIX_PTS_SLOPE * (player_pct_rim - league_avg_pct_rim)
  ratio <- pmin(pmax(ratio, SHOT_MIX_PTS_CLAMP[1]), SHOT_MIX_PTS_CLAMP[2])
  # A player with no real pct_rim (e.g. no PBP events yet) yields ratio == NA
  # here; resolve that to a neutral 1x rather than propagating NA into adj_pts,
  # same pattern adjust_mu_for_opponent() uses for a non-finite ratio.
  ratio <- ifelse(is.finite(ratio), ratio, 1)
  base_mu * ratio
}

# Loads cache/player_pbp_features.rds (CACHE_PLAYER_PBP_FEATURES, config.R) and
# returns a (player_id, pct_rim) lookup with the league mean pct_rim carried as
# the "league_avg_pct_rim" attribute, mirroring get_team_def_rapm()'s
# neutral()/attribute pattern. Read-only consumer of pbp_engine.R's shipped
# cache -- never recomputes or overwrites it.
get_player_pct_rim <- function() {
  if (!file.exists(CACHE_PLAYER_PBP_FEATURES)) {
    message("[PROPS WARNING] cache/player_pbp_features.rds not found — shot-mix PTS adjustment disabled (neutral multiplier).")
    out <- tibble(player_id = integer(0), pct_rim = numeric(0))
    attr(out, "league_avg_pct_rim") <- NA_real_
    return(out)
  }
  feats <- readRDS(CACHE_PLAYER_PBP_FEATURES)
  out <- feats |> select(player_id, pct_rim) |> filter(!is.na(pct_rim))
  league_avg <- mean(out$pct_rim, na.rm = TRUE)
  attr(out, "league_avg_pct_rim") <- if (is.finite(league_avg)) league_avg else NA_real_
  out
}

price_prop_zinb <- function(player_names, teams, stat_cat, projected_mus, lines,
                                over_odds = -110, under_odds = -110) {
  theta <- PROP_DISPERSION[[stat_cat]] %||% 5.0
  pi_0  <- ZERO_INFLATION_PI[[stat_cat]] %||% 0.05

  p_over  <- pzinb_over_vec(lines, mu = projected_mus, theta = theta, pi_zero = pi_0)
  p_under <- 1 - p_over

  dec_over  <- ifelse(over_odds > 0, 1 + over_odds / 100, 1 + 100 / abs(over_odds))
  dec_under <- ifelse(under_odds > 0, 1 + under_odds / 100, 1 + 100 / abs(under_odds))

  ev_over  <- (p_over * dec_over) - 1
  ev_under <- (p_under * dec_under) - 1

  b_over  <- dec_over - 1
  b_under <- dec_under - 1
  kelly_over  <- pmax(0, ((p_over * b_over) - (1 - p_over)) / b_over) * 0.25
  kelly_under <- pmax(0, ((p_under * b_under) - (1 - p_under)) / b_under) * 0.25

  best_side <- ifelse(ev_over > ev_under, "OVER", "UNDER")
  best_ev   <- pmax(ev_over, ev_under)
  best_prob <- ifelse(best_side == "OVER", p_over, p_under)
  best_kelly <- ifelse(best_side == "OVER", kelly_over, kelly_under)
  book_odds <- ifelse(best_side == "OVER", over_odds, under_odds)

  tibble(
    player = player_names,
    team = teams,
    stat = stat_cat,
    line = lines,
    proj_mu = round(projected_mus, 2),
    theta = theta,
    zinb_p_zero = pi_0,
    p_over = round(p_over, 4),
    p_under = round(p_under, 4),
    recommended_side = best_side,
    market_odds = book_odds,
    ev_pct = round(best_ev * 100, 2),
    quarter_kelly = round(best_kelly, 4),
    is_edge = (best_ev >= 0.05)
  )
}

# ------------------------------------------------------------------------------
# Build REAL per-player stat projections from T1's real box-score cache, joined
# to T1's real active-roster cache.
# ------------------------------------------------------------------------------
build_real_rotation_table <- function(rosters) {
  # IO Optimization: use GLOBAL_PLAYER_BOX if available
  pbox <- if (exists("GLOBAL_PLAYER_BOX", inherits = FALSE)) {
    GLOBAL_PLAYER_BOX
  } else if (file.exists(CACHE_PLAYER_BOX)) {
    readRDS(CACHE_PLAYER_BOX)
  } else {
    message("[PROPS WARNING] cache/player_box_scores_cache.rds not found — cannot compute real stat means.")
    return(NULL)
  }

  # Prefer CURRENT_SEASON per-game means (most representative of "today's" rotation
  # production); fall back to ALL_SEASONS history for any player with no
  # current-season box rows yet (e.g. a rookie who just debuted, or a mid-season
  # signee), matching the fail-safe pattern used elsewhere in this repo.
  cur <- pbox |>
    filter(season == CURRENT_SEASON, !is.na(athlete_id)) |>
    group_by(athlete_id) |>
    summarise(
      games      = n(),
      pts_mu     = mean(points, na.rm = TRUE),
      reb_mu     = mean(rebounds, na.rm = TRUE),
      ast_mu     = mean(assists, na.rm = TRUE),
      fg3m_mu    = mean(three_point_field_goals_made, na.rm = TRUE),
      stl_mu     = mean(steals, na.rm = TRUE),
      blk_mu     = mean(blocks, na.rm = TRUE),
      avg_min    = mean(minutes, na.rm = TRUE),
      .groups = "drop"
    )

  hist <- pbox |>
    filter(!is.na(athlete_id)) |>
    group_by(athlete_id) |>
    summarise(
      games_hist   = n(),
      pts_mu_hist  = mean(points, na.rm = TRUE),
      reb_mu_hist  = mean(rebounds, na.rm = TRUE),
      ast_mu_hist  = mean(assists, na.rm = TRUE),
      fg3m_mu_hist = mean(three_point_field_goals_made, na.rm = TRUE),
      stl_mu_hist  = mean(steals, na.rm = TRUE),
      blk_mu_hist  = mean(blocks, na.rm = TRUE),
      avg_min_hist = mean(minutes, na.rm = TRUE),
      .groups = "drop"
    )

  joined <- rosters |>
    left_join(cur, by = c("player_id" = "athlete_id")) |>
    left_join(hist, by = c("player_id" = "athlete_id")) |>
    mutate(
      data_source = case_when(
        !is.na(pts_mu) ~ "REAL_CURRENT_SEASON",
        !is.na(pts_mu_hist) ~ "REAL_HISTORICAL_FALLBACK",
        TRUE ~ "SYNTHETIC_NO_BOX_DATA"
      ),
      pts_mu  = coalesce(pts_mu, pts_mu_hist, 4.0),
      reb_mu  = coalesce(reb_mu, reb_mu_hist, 2.0),
      ast_mu  = coalesce(ast_mu, ast_mu_hist, 1.0),
      fg3m_mu = coalesce(fg3m_mu, fg3m_mu_hist, 0.3),
      stl_mu  = coalesce(stl_mu, stl_mu_hist, 0.5),
      blk_mu  = coalesce(blk_mu, blk_mu_hist, 0.2),
      avg_min = coalesce(avg_min, avg_min_hist, 10.0)
    )

  n_synth <- sum(joined$data_source == "SYNTHETIC_NO_BOX_DATA")
  if (n_synth > 0) {
    message(sprintf("[PROPS] %d/%d roster players have no box-score history (rookies/late signees) — flagged with data_source == 'SYNTHETIC_NO_BOX_DATA' and given a minimal bench-level fallback mean, not fabricated star numbers.", n_synth, nrow(joined)))
  }

  # Select the real rotation: top WNBA_ROTATION_SIZE players per team by average
  # minutes played (matches T2's own rotation-depth logic in
  # roster_bottom_up_engine.R for consistency across the WNBA repo).
  joined |>
    group_by(team_abbreviation) |>
    arrange(desc(avg_min), .by_group = TRUE) |>
    slice_head(n = WNBA_ROTATION_SIZE) |>
    ungroup() |>
    transmute(
      player_id   = player_id,
      player_name = player_name,
      team        = team_abbreviation,
      pts_mu      = pts_mu,
      reb_mu      = reb_mu,
      ast_mu      = ast_mu,
      fg3m_mu     = fg3m_mu,
      stl_mu      = stl_mu,
      blk_mu      = blk_mu,
      data_source = data_source
    )
}

# ------------------------------------------------------------------------------
# Generate Rotation Props Database
# Output: ONE canonical file, config.R's CACHE_PLAYER_PROPS
# (cache/latest_player_props.rds) — see FINDING L-6 at the write site below.
# ------------------------------------------------------------------------------

generate_active_props_table <- function() {
  # IO Optimization: use GLOBAL_ACTIVE_ROSTERS if available
  roster_cache <- CACHE_DIR |> file.path("active_rosters_cache.rds")
  rosters <- NULL

  if (exists("GLOBAL_ACTIVE_ROSTERS", inherits = FALSE)) {
    rosters <- build_real_rotation_table(GLOBAL_ACTIVE_ROSTERS)
  } else if (file.exists(roster_cache)) {
    raw_rosters <- readRDS(roster_cache)
    rosters <- build_real_rotation_table(raw_rosters)
  }

  if (is.null(rosters) || nrow(rosters) == 0) {
    message("[PROPS NOTICE] Real roster cache unavailable or unjoinable — using SYNTHETIC_FALLBACK rotation.")
    teams <- names(WNBA_TEAMS)
    per_team_pts <- head(c(24.5, 18.2, 14.4, 11.8, 9.2, 7.5, 5.8, 4.2), WNBA_ROTATION_SIZE)
    per_team_reb <- head(c(7.2, 7.8, 4.8, 3.9, 5.0, 2.9, 2.6, 2.1), WNBA_ROTATION_SIZE)
    per_team_ast <- head(c(5.8, 3.9, 3.4, 2.6, 1.6, 1.9, 1.2, 1.0), WNBA_ROTATION_SIZE)
    per_team_fg3 <- head(c(2.6, 2.0, 1.5, 1.3, 1.0, 0.8, 0.6, 0.4), WNBA_ROTATION_SIZE)
    per_team_stl <- head(c(1.2, 1.0, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3), WNBA_ROTATION_SIZE)
    per_team_blk <- head(c(1.0, 0.7, 0.5, 0.4, 0.3, 0.3, 0.2, 0.1), WNBA_ROTATION_SIZE)

    rosters <- bind_rows(lapply(teams, function(tm) {
      tibble(
        player_name = paste0(tm, " Player ", seq_len(WNBA_ROTATION_SIZE)),
        team = tm,
        pts_mu = per_team_pts,
        reb_mu = per_team_reb,
        ast_mu = per_team_ast,
        fg3m_mu = per_team_fg3,
        stl_mu = per_team_stl,
        blk_mu = per_team_blk,
        data_source = "SYNTHETIC_FALLBACK"
      )
    }))
  } else {
    message(sprintf("[PROPS] Loaded REAL WNBA rotation: %d players across %d teams.",
                    nrow(rosters), length(unique(rosters$team))))
  }

  # Task P3-2.4: Opponent Adjustment
  matchups_file <- file.path(CACHE_DIR, "latest_value_bets.rds")
  def_rapm_df <- get_team_def_rapm(if (exists("GLOBAL_ACTIVE_ROSTERS", inherits = FALSE)) GLOBAL_ACTIVE_ROSTERS else readRDS(roster_cache))

  # M-4: the league centre is now computed alongside the team aggregates and carried
  # on the returned frame, so the adjustment is centred on the mean TEAM defense
  # rather than on mean(rapm$drapm) — a player-level mean 2.87 units below the team
  # mean, which biased every single opponent adjustment in the same direction.
  league_avg_def <- attr(def_rapm_df, "league_avg_def")
  if (is.null(league_avg_def) || !is.finite(league_avg_def)) {
    league_avg_def <- mean(def_rapm_df$def_rapm, na.rm = TRUE)
  }
  message(sprintf("[PROPS] Opponent adjustment centred on league mean team def_rapm = %.3f (slope %.4f/unit, clamped to [%.2f, %.2f]).",
                  league_avg_def, OPP_DEF_MU_SLOPE, OPP_DEF_MU_CLAMP[1], OPP_DEF_MU_CLAMP[2]))

  # Shot-mix PTS-only adjustment (research task, 2026-09-17) — see
  # docs/pbp_shot_mix_regression_findings.md and the SHOT_MIX_PTS_SLOPE block
  # above for the derivation. Loaded alongside, not instead of, the RAPM
  # opponent adjustment.
  pct_rim_df <- get_player_pct_rim()
  league_avg_pct_rim <- attr(pct_rim_df, "league_avg_pct_rim")
  if (is.null(league_avg_pct_rim) || !is.finite(league_avg_pct_rim)) {
    league_avg_pct_rim <- NA_real_
  }
  message(sprintf("[PROPS] Shot-mix PTS adjustment centred on league mean pct_rim = %s (slope %.4f/unit, clamped to [%.2f, %.2f]).",
                  if (is.finite(league_avg_pct_rim)) sprintf("%.3f", league_avg_pct_rim) else "NA (disabled)",
                  SHOT_MIX_PTS_SLOPE, SHOT_MIX_PTS_CLAMP[1], SHOT_MIX_PTS_CLAMP[2]))

  matchups <- if (file.exists(matchups_file)) readRDS(matchups_file) else tibble()

  # Map players to their opponent for today (Vectorized)
  player_opponents <- tibble()
  if (nrow(matchups) > 0) {
    game_pairs <- matchups |>
      mutate(teams = str_split(Matchup, " vs\\. ")) |>
      unnest(teams) |>
      group_by(game_id) |>
      summarise(
        t1 = first(teams),
        t2 = last(teams),
        .groups = "drop"
      )

    player_opponents <- rosters |>
      mutate(team_full = WNBA_TEAMS[team]) |>
      left_join(game_pairs, by = c("team_full" = "t1")) |>
      mutate(opponent = t2) |>
      select(player_name, opponent) |>
      bind_rows(
        rosters |>
          mutate(team_full = WNBA_TEAMS[team]) |>
          left_join(game_pairs, by = c("team_full" = "t2")) |>
          mutate(opponent = t1) |>
          select(player_name, opponent)
      ) |>
      filter(!is.na(opponent))
  }

  # Vectorized Prop Calculation
  # 1. Join rosters with opponent ratings
  props_base <- rosters |>
    left_join(player_opponents, by = "player_name") |>
    left_join(def_rapm_df, by = c("opponent" = "team_name")) |>
    mutate(
      opp_def_rapm = coalesce(def_rapm, league_avg_def)
    )

  # Direct ESPN-namespace join (player_id == player_id, no name matching needed
  # — see pbp_engine.R's header). SYNTHETIC_FALLBACK rosters have no player_id
  # column at all; in that case pct_rim is simply NA for every row, which
  # adjust_mu_for_shot_mix() already resolves to a neutral 1x, so this degrades
  # safely rather than erroring.
  if ("player_id" %in% names(props_base)) {
    props_base <- props_base |> left_join(pct_rim_df, by = "player_id")
  } else {
    props_base <- props_base |> mutate(pct_rim = NA_real_)
  }

  # 2. Calculate all adjusted mus and random lines in one go
  # Noise vectors for each stat category
  n_players <- nrow(props_base)
  props_base <- props_base |>
    mutate(
      # PTS composes BOTH adjustments: opponent-defense first, then the
      # shot-mix scoring-efficiency adjustment multiplicatively on top (each
      # factor is its own centred-on-1.0 multiplier, so chaining them
      # multiplies the two independent ratios rather than re-deriving a joint
      # coefficient — documented choice, see SHOT_MIX_PTS_SLOPE block above).
      # REB/AST/FG3M/STL/BLK deliberately keep ONLY the opponent adjustment —
      # the shot-mix signal is specifically about scoring efficiency and has no
      # theoretical link to those categories (out of scope per this task).
      adj_pts  = adjust_mu_for_shot_mix(
                   adjust_mu_for_opponent(pts_mu, opp_def_rapm, league_avg_def),
                   pct_rim, league_avg_pct_rim
                 ),
      adj_reb  = adjust_mu_for_opponent(reb_mu, opp_def_rapm, league_avg_def),
      adj_ast  = adjust_mu_for_opponent(ast_mu, opp_def_rapm, league_avg_def),
      adj_fg3m = adjust_mu_for_opponent(fg3m_mu, opp_def_rapm, league_avg_def),
      adj_stl  = adjust_mu_for_opponent(stl_mu, opp_def_rapm, league_avg_def),
      adj_blk  = adjust_mu_for_opponent(blk_mu, opp_def_rapm, league_avg_def),

      line_pts  = round(adj_pts + rnorm(n_players, 0, 1.2) * 0.5) + 0.5,
      line_reb  = round(adj_reb + rnorm(n_players, 0, 0.8) * 0.5) + 0.5,
      line_ast  = round(adj_ast + rnorm(n_players, 0, 0.7) * 0.5) + 0.5,
      line_fg3  = pmax(0.5, round(adj_fg3m + rnorm(n_players, 0, 0.5) * 0.5) + 0.5),
      line_stl  = 1.5,
      line_blk  = 0.5
    )

  # 3. Generate results by category using vectorized price_prop_zinb
  all_props <- bind_rows(
    price_prop_zinb(props_base$player_name, props_base$team, "PTS", props_base$adj_pts, props_base$line_pts, -110, -110),
    price_prop_zinb(props_base$player_name, props_base$team, "REB", props_base$adj_reb, props_base$line_reb, -115, -105),
    price_prop_zinb(props_base$player_name, props_base$team, "AST", props_base$adj_ast, props_base$line_ast, -108, -112),
    price_prop_zinb(props_base$player_name, props_base$team, "FG3M", props_base$adj_fg3m, props_base$line_fg3, -110, -110),
    price_prop_zinb(props_base$player_name, props_base$team, "STL", props_base$adj_stl, props_base$line_stl, +115, -145),
    price_prop_zinb(props_base$player_name, props_base$team, "BLK", props_base$adj_blk, props_base$line_blk, -120, -102)
  ) %>%
    arrange(desc(ev_pct))

  # FINDING L-6 (docs/SECURITY_TECHNICAL_REVIEW.md): this used to write TWO full
  # copies —  "data/latest_player_props.rds" AND "cache/latest_player_props.rds" —
  # with app.R silently preferring data/ while tools/data_health_probe.R validated
  # cache/. Any partial write or single-location update produced a split-brain where
  # the health probe reported green on a file nobody displayed. Now exactly ONE
  # canonical write, to config.R's CACHE_PLAYER_PROPS (= cache/latest_player_props.rds).
  # app.R is repointed at the same constant by agent_dashboard in this same wave.
  saveRDS(all_props, CACHE_PLAYER_PROPS)

  edges_found <- sum(all_props$is_edge)
  n_teams <- length(unique(rosters$team))
  message(sprintf(">>> [PROPS] Processed %d total props across %d teams. Discovered %d positive EV (>= +5.0%%) edges.",
                  nrow(all_props), n_teams, edges_found))

  return(all_props)
}

if (!interactive()) {
  invisible(generate_active_props_table())
}
