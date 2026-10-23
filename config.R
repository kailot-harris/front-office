# ==============================================================================
# WNBA Analytics Pipeline - Global Configuration
# Path: <project root>/config.R (PROJECT_DIR is derived portably via here::here(), not hardcoded)
#
# Ported from the NBA Analytics repo's config.R (see REPO_MAP.md / WNBA_REPLICATION_PLAN.md
# in this folder for full context). This is Phase 0 (T0) of the WNBA replication project —
# every other script in this repo sources this file.
#
# All season-range constants below were validated empirically against live `wehoop` data
# on 2026-09-12 (see PHASE0_VALIDATION_NOTES.md for the full methodology, row counts, and
# caveats). Do NOT blindly widen/narrow these ranges without re-running that validation.
# ==============================================================================

# Working and Cache Directories
# Derived portably via here::here() (infers the project root from the nearest .git directory/
# file or other rprojroot marker) instead of a hardcoded absolute path, so this repo runs on
# any machine without manual editing (GitHub issue #2).
if (!requireNamespace("here", quietly = TRUE)) {
  stop("Package 'here' is required to derive PROJECT_DIR portably. Install it with install.packages('here').")
}
PROJECT_DIR <- here::here()
CACHE_DIR   <- file.path(PROJECT_DIR, "cache")
if (!dir.exists(CACHE_DIR)) dir.create(CACHE_DIR, recursive = TRUE)

# ------------------------------------------------------------------------------------------
# WNBA-specific structural constants (no NBA equivalent, or different from NBA's values)
# ------------------------------------------------------------------------------------------
WNBA_ROSTER_MAX   <- 12   # WNBA active roster cap (vs NBA's 15-man active roster)
WNBA_GAME_MINUTES <- 40   # 4x10-minute quarters (vs NBA's 4x12 = 48)

# Current official WNBA regular-season game count per team. This has changed across recent
# seasons (34 -> 36 -> 40 -> 44) as the league has expanded its schedule. Verified via web
# search on 2026-09-12: the 2026 season (WNBA's 30th) is 44 games/team (22 home, 22 away).
# Re-verify at the start of each new season before trusting downstream schedule math
# (roster_bottom_up_engine.R's games_per_opponent, zero-sum standings invariant, etc.).
WNBA_SEASON_GAMES <- 44

# Centralized WNBA franchise list (per WNBA_REPLICATION_PLAN.md §(e) risk #5: the NBA repo
# scatters its 30-team list across multiple files via ad hoc `case_when` blocks; that is a
# known risk-mitigation item this repo must NOT repeat, especially given the WNBA's active
# expansion). This is the single source of truth for team abbreviations/names — every other
# script (sync_rosters.R, market_odds_engine.R, ARENA_DB, synthetic roster generators, etc.)
# must reference WNBA_TEAMS rather than hardcoding its own copy.
#
# Verified via (a) web search on 2026-09-12 (15 teams for the 2026 season, including the
# Toronto Tempo and Portland Fire expansion franchises that joined in 2026), and (b)
# cross-checked empirically against wehoop::load_wnba_team_box(seasons = 2026)'s actual
# distinct team_abbreviation values (after excluding non-franchise All-Star/exhibition rows
# — see PHASE0_VALIDATION_NOTES.md). Both sources agree on this 15-team list as of 2026-09-12.
#
# NOTE FOR FUTURE AGENTS: the WNBA has publicly announced further expansion (Cleveland 2028,
# Detroit 2029, Philadelphia 2030) - re-verify this vector at the start of each new season.
WNBA_TEAMS <- c(
  ATL = "Atlanta Dream",
  CHI = "Chicago Sky",
  CON = "Connecticut Sun",
  DAL = "Dallas Wings",
  GS  = "Golden State Valkyries",
  IND = "Indiana Fever",
  LV  = "Las Vegas Aces",
  LA  = "Los Angeles Sparks",
  MIN = "Minnesota Lynx",
  NY  = "New York Liberty",
  PHX = "Phoenix Mercury",
  POR = "Portland Fire",
  SEA = "Seattle Storm",
  TOR = "Toronto Tempo",
  WSH = "Washington Mystics"
)
WNBA_TEAM_COUNT <- length(WNBA_TEAMS)  # 15 as of the 2026 season

# Rotation depth (top-N players per team used for team-rating/props aggregation).
# Originally defined only inside roster_bottom_up_engine.R (T2); centralized here
# during T4 (wnba_betting_market_agent) because player_props_engine.R also needs
# the exact same number for consistency (per task_assignments.md's T4 brief:
# "match whatever T2 chose for its rotation depth ... use the same number for
# consistency"). Value (8) and rationale unchanged from T2's original choice -
# see task_assignments.md's T2 Handoff Notes: chosen over 7 for one extra buffer
# rotation player against injury/foul trouble, shallower than NBA's top-9 given
# WNBA's 12-player active roster cap (vs NBA's 15). NOT yet validated against
# real WNBA per-player minutes distributions - a good next step for whoever
# revisits this constant.
WNBA_ROTATION_SIZE <- 8

# ------------------------------------------------------------------------------------------
# Data Horizons
# ------------------------------------------------------------------------------------------
# These were validated empirically (not assumed) against wehoop::load_wnba_team_box()/
# load_wnba_player_box() for seasons 2019-2026 on 2026-09-12. Full methodology, row counts,
# and per-season caveats (All-Star/exhibition noise rows, the 2020 bubble season's short
# 22-game schedule, evolving ESPN schema column counts) are in PHASE0_VALIDATION_NOTES.md.
#
# IMPORTANT CAVEAT carried forward from that validation: raw wehoop team/player box data for
# every season includes extra non-franchise "team" rows for All-Star-game draft squads and
# Team USA exhibitions (e.g. STE/WIL/USA/WNBASTARS/CLA/COL/COOP/SPO depending on season).
# Any script that loads box data MUST filter to `team_abbreviation %in% names(WNBA_TEAMS)`
# (or the historical equivalent for that season) before aggregating - this was NOT needed for
# hoopR/NBA and is a real behavioral difference, not a copy-paste artifact.
HISTORICAL_SEASONS <- 2019:2025
TEST_SEASON        <- 2026
CURRENT_SEASON      <- 2026  # 2026 season data was live/partial at validation time (max
                              # game_date observed: 2026-08-30, season_type == regular season
                              # only - playoffs not yet reflected in the feed as of validation)
ALL_SEASONS        <- 2019:2026
SIMULATION_SEASON  <- 2027

# ------------------------------------------------------------------------------------------
# Rolling Window & Modeling Hyperparameters
# ------------------------------------------------------------------------------------------
# NBA used ROLLING_WINDOW_SIZE <- 18 out of an 82-game season (~22%). The original proportional
# placeholder here was 9 (18 * 44/82 ~= 9.66 -> 9). Per WNBA_REPLICATION_PLAN.md §(b)/(d), this
# WAS actually re-tested on real WNBA data (not just assumed) in WNBA_Analysis_Project.Rmd. An
# initial narrow sweep {5,7,9,11,13} looked monotonically improving and produced ROLLING_WINDOW_SIZE
# <- 13, but that was an artifact of only sampling odd points on a noisier curve - re-run with the
# full 3-25 sweep (matching the NBA baseline's own tested range) on 2026-09-12 against the same
# real box_scores_cache.rds/293 held-out CURRENT_SEASON games. Full result in
# WNBA_Analysis_Project.Rmd and `data/window_sweep_3_25_results.csv` — that CSV is the
# AUTHORITATIVE artifact for this sweep (FINDING L-2: this comment previously cited only
# `cache/window_sweep_3_25_results.rds`, wrong directory *and* wrong extension). A
# `cache/window_sweep_3_25_results.rds` does also exist; verified 2026-09-16 that the two hold
# identical numbers for all 23 window sizes, differing only in column naming (`ROC-AUC` in the
# .rds vs `ROC.AUC` after CSV round-tripping). Prefer the CSV; the .rds is a redundant copy.
# The curve is genuinely
# non-monotonic (e.g. window=5 dips below window=3/4). Peak: window=12 -> Accuracy 0.645 / ROC-AUC
# 0.678 / Brier 0.225, narrowly ahead of window=13 (0.663 AUC) and window=15 (0.675 AUC), with no
# further improvement out to window=25 (oscillates 0.65-0.67 AUC).
# Updated to 12 based on this real, wider result. CAVEAT: windows 12/13/15 differ by only
# 0.003-0.015 ROC-AUC on a 293-game test set - plausibly within sampling noise from a single
# train/test split (set.seed(42), not cross-validated). Treat 12 as "best point in this specific
# sweep," not a statistically confirmed global optimum; a leave-one-season-out CV re-selection
# (as already used for the final model benchmark in ML_BENCHMARK_REPORT.md) would be the more
# rigorous next step before relying on this number for anything high-stakes.
ROLLING_WINDOW_SIZE <- 12

# Carried over from NBA as reasonable starting defaults - these are largely sport-agnostic
# per WNBA_REPLICATION_PLAN.md. Re-tune later if WNBA-specific behavior (e.g. much shorter
# season, longer offseason) suggests they should differ.
OFFSEASON_METHOD <- "reset"  # "reset", "mean_regress", or "decay"
# RE-BENCHMARKED for WNBA (T2 / WNBA_Analysis_Project.Rmd), not just carried over on
# assumption. Contrary to the plan's speculation that a shorter WNBA season might favor a
# continuity-weighted method, "reset" actually won on real 2026-season out-of-sample data
# (window_size=13, RF classifier): reset AUC 0.660/Brier 0.227, mean_regress AUC 0.632/Brier
# 0.235, decay AUC 0.657/Brier 0.230. mean_regress edged out reset on raw accuracy (0.612 vs
# 0.604) but lost on both AUC and Brier, which weight probability quality more directly - kept
# "reset" as the default. Single train/test split, not cross-validated; re-run if the box score
# cache grows substantially or behavior seems off.
#
# STALENESS FLAG (FINDING L-2, 2026-09-16) — RESOLVED 2026-09-24: the benchmark above was originally
# run at window_size = 13, before ROLLING_WINDOW_SIZE was lowered to 12 by the wider 3-25 sweep.
# `WNBA_Analysis_Project.Rmd`'s offseason-transition section has since re-run the three-method
# comparison at the live ROLLING_WINDOW_SIZE (=12 at the time of that re-run): reset AUC 0.672/Brier
# 0.226, mean_regress AUC 0.658/Brier 0.232, decay AUC 0.656/Brier 0.233 — "reset" won again on both
# AUC and Brier, same ranking as the window_size=13 run. Still a single train/test split, not
# cross-validated. If ROLLING_WINDOW_SIZE changes again, re-run that Rmd section (read the constant,
# do not hardcode a window size) rather than assuming this ranking still holds.
REST_DAYS_CAP  <- 7
N_SIMULATIONS  <- 10000

# ------------------------------------------------------------------------------------------
# Margin -> Win-Probability Sigma (roster_bottom_up_engine.R / playoff-style pnorm() calls)
# ------------------------------------------------------------------------------------------
# The NBA repo hardcodes 11.8 (roster_bottom_up_engine.R) / 11.2 (market_odds_engine.R) — two
# slightly different, never-reconciled sigma constants fit to NBA score-margin variance (see
# REPO_MAP.md §9). WNBA_REPLICATION_PLAN.md §(b) Tier 3 explicitly warns not to reuse either
# blindly: WNBA games are 40 min (not 48) with different pace, so margin variance differs.
#
# UNLIKE the plan's worst-case assumption ("you likely do not have real WNBA game margins
# loaded yet"), T1's `box_scores_cache.rds` (3,906 real team-game rows, 2019-2026) was already
# available at Phase 2 time, so this was actually empirically derived rather than left as a
# bare TODO:
#   home_rows   <- box_scores_cache |> filter(team_home_away == "home")
#   margin      <- home_rows$team_score - home_rows$opponent_team_score
#   sd(margin)  == 14.01  (n = 1,953 real home team-games, 2019-2026; per-season sd ranged
#                          12.7-15.0, no season is a wild outlier - see per-season table in
#                          task_assignments.md T2 Handoff Notes)
# Rounded to 14.0. This IS a real empirically-derived WNBA constant, not an NBA number dressed
# up as validated - re-run the same sd() computation once more current-season games accumulate
# in the cache to keep it current (WNBA margins run wider than NBA's ~11.8-11.2 because there
# are fewer possessions per game to regress extreme quarters back toward the mean).
WNBA_MARGIN_SIGMA <- 14.0

# ------------------------------------------------------------------------------------------
# Offensive/Defensive BPM split (GitHub issue #64)
# ------------------------------------------------------------------------------------------
# roster_bottom_up_engine.R::get_player_bpm_ratings() derives per-player Off_Rating/Def_Rating
# components downstream of player_metrics.R's existing (unmodified) BPM box-score weights by
# splitting the single `rebounds` box-score term into its offensive/defensive rebound shares
# (`offensive_rebounds` / `defensive_rebounds`, both already present in CACHE_PLAYER_BOX's raw
# wehoop schema). This constant is ONLY the fallback used when a player's aggregated
# offensive_rebounds + defensive_rebounds totals zero (so the split would otherwise be 0/0) -
# it is not used for any player with real rebound totals, who get their own actual split.
# Empirically derived from CACHE_PLAYER_BOX (all seasons, 2026-10-05):
#   sum(offensive_rebounds) == 32541, sum(defensive_rebounds) == 101164,
#   sum(rebounds) == 133705 == oreb+dreb exactly (no team-rebound discrepancy in this feed).
#   share = 32541 / (32541 + 101164) = 0.2434, rounded to 0.24.
WNBA_OFF_REB_SHARE <- 0.24

# ------------------------------------------------------------------------------------------
# Home-Court Advantage (points added to the home side's projected margin)
# ------------------------------------------------------------------------------------------
# FINDING C-1 (docs/SECURITY_TECHNICAL_REVIEW.md): this value was previously restated as a bare
# literal at eight call sites. Seven of them said 2.40; market_odds_engine.R's LIVE code path had
# drifted to 11.6 (apparently the NBA original's ~11.2-family *sigma* constant pasted into the HCA
# slot) while its own comment three lines above still documented 2.40 — and
# tools/backtest_margin_hyperparams.R had since enshrined 11.6 as ground truth. At hca=11.6 with
# WNBA_MARGIN_SIGMA=14 the model implies a 79.6% home win rate for two identical teams (real WNBA
# is ~55-58%), which turned the bet recommender into an "always bet the home team at max Kelly
# stake" machine. This constant is now the SINGLE SOURCE — no script may restate the literal.
#
# PROVENANCE: 2.40 is NBA-inherited per T2's note and has NOT been independently re-derived for
# the WNBA. Deliberately not re-derived here (Phase 4 Wave 1 scope is centralization only);
# re-running tools/optimize_hca.R against real WNBA margins is a separate, tracked decision.
WNBA_HCA <- 2.40

# ------------------------------------------------------------------------------------------
# Cache Filepaths (mirrors NBA config.R's constants 1:1, repointed at this project's folder)
# ------------------------------------------------------------------------------------------
# NOTE (tidy-up pass, 2026-09-12): these five used to be bare PROJECT_DIR-root files.
# They now live in data/ (see docs/task_assignments_phase2.md's tidy-up section) — updated
# here so every reader/writer of these constants continues to resolve to a real file.
CACHE_TEAM_BOX     <- file.path(PROJECT_DIR, "data", "box_scores_cache.rds")
CACHE_PLAYER_BOX   <- file.path(CACHE_DIR, "player_box_scores_cache.rds")
CACHE_FEATURES     <- file.path(CACHE_DIR, "features_cache.rds")
CACHE_EMBEDDINGS   <- file.path(PROJECT_DIR, "data", "team_embeddings.csv")
CACHE_SIMILARITY   <- file.path(PROJECT_DIR, "data", "team_similarity_matrix.csv")
CACHE_INJURY_DATA  <- file.path(CACHE_DIR, "injury_data_cache.rds")
CACHE_PLAYER_PROPS <- file.path(CACHE_DIR, "latest_player_props.rds")
CACHE_PLAYER_ID_CROSSWALK <- file.path(CACHE_DIR, "player_id_crosswalk.rds")
CACHE_RAPM_RATINGS        <- file.path(CACHE_DIR, "rapm_ratings.rds")

# Promoted from pbp_engine.R's bare literals (2026-09-17): now a two-consumer path
# (pbp_engine.R writer + run_full_pipeline.R stage + app.R's "Clutch & Shot Profile"
# tab reader), which crosses this repo's own stated threshold for centralizing a
# cache literal here rather than leaving it repeated across files.
CACHE_PBP_RAW               <- file.path(CACHE_DIR, "wnba_espn_pbp_cache.rds")
CACHE_PLAYER_PBP_FEATURES   <- file.path(CACHE_DIR, "player_pbp_features.rds")

# ------------------------------------------------------------------------------------------
# RAPM & Opponent Adjustments (GitHub issues #71, #76, #77, #78, #79, #82)
# ------------------------------------------------------------------------------------------
# Ridge regression penalty parameter (lambda) for possession-level RAPM.
# Defaults to 900 (coarse-grid baseline); 5-fold cross-validation via tune_lambda_cv()
# on the 2019-2025 pooled dataset identifies 5000 as the out-of-sample MSE minimum.
# Can be overridden via RAPM_LAMBDA environment variable or tuned via RAPM_TUNE_LAMBDA=TRUE.
RAPM_LAMBDA      <- as.numeric(Sys.getenv("RAPM_LAMBDA", "900"))
RAPM_TUNE_LAMBDA <- isTRUE(as.logical(Sys.getenv("RAPM_TUNE_LAMBDA", "FALSE")))

# Low-sample-size honesty flag (rapm_engine.R::fit_rapm_ratings() -> `low_sample_flag`):
# WNBA's ~44-game seasons and 12-player rosters mean far fewer possessions per player than
# NBA over the same calendar span. Flag (not drop) the noisiest ratings so downstream
# consumers/humans know which ones not to trust.
#
# RULE CHANGED from a raw possession count to a SHRINKAGE rule (issue #71, fix A).
#
# The old `(n_off_poss + n_def_poss) < 300` cut flagged 63 of 430 players (14.7%) and caught
# NONE of the low-exposure players topping the Total RAPM leaderboard -- Dungee (391
# combined), Nivar (561), Clouden (1,662), Jaquez (1,931), Park (2,207) all ranked 3rd-10th
# league-wide while unflagged. But raising the count is the wrong instrument, and the
# intuition behind it ("low exposure = noisy") is empirically BACKWARDS here: measured sd of
# total_rapm by combined-possession band is 1.48 (<500), 2.51 (500-1k), 2.87 (1-2k), 3.29
# (2-3k), 2.71 (>5k). The LOWEST-exposure band is the LEAST variable, because ridge shrinks
# it hardest. Shrinkage dominates MORE at low exposure, not less. A count-based cut also
# lands arbitrarily: the league median combined exposure is 2,597, so any threshold near
# 2,500 flags ~half the league by construction rather than by evidence.
#
# What actually matters is HOW MUCH OF A RATING IS DATA vs. PRIOR. Ridge shrinks each
# coefficient by roughly s_i = n_i / (n_i + lambda), so `1 - s_i` is the fraction of the
# reported number contributed by the shrinkage prior rather than by the player's own
# possessions. Flag a player when the weaker of their two sides is more than two-thirds
# prior (s < 1/3, i.e. fewer than lambda/2 possessions on that side). This is why Dungee
# ranks 5th at +6.19 on 194 offensive possessions: she is 82% prior, shrunk ~5x toward zero
# and still top-five, so her unshrunk signal is ~+34/100 -- lineup luck, not a player effect.
# Measured: flags 124 of 430 (28.8%), catching Dungee (82% prior) and Nivar (76%).
#
# Kept as the expression `1 / 3`, not a rounded decimal: the rule is "more than two-thirds
# prior", and expressing it against `lambda` rather than a hardcoded possession count means
# it stays correct if lambda is ever re-tuned (see RAPM_LAMBDA above -- issue #78). Flag,
# never drop.
RAPM_MIN_DATA_SHARE <- 1 / 3

# Leaderboard rank-eligibility cut (rapm_engine.R::fit_rapm_ratings() ->
# `leaderboard_eligible`, and summary_app.R's Tab 6 "Minimum possessions" UI default, which
# reads THIS constant so the two can never drift apart again -- the duplication issue #82
# exists to kill).
#
# Eligibility is a SEPARATE mechanism from the honesty flag above (issue #71, fix A).
# `low_sample_flag` answers "how much of this one number is prior?"; eligibility answers
# "should this row compete for a top-N rank at all?". Conflating them into one boolean was
# what forced the earlier 48.8% flag rate -- a dataset-level claim that half the league is
# untrustworthy, in order to clean a presentation-level ranking.
#
# Require >= 1,000 possessions on BOTH sides (not combined, which lets a one-sided specialist
# through on garbage-time minutes; the previous combined default of 2,500 was also doing the
# same job as the dataset-level low_sample_flag). Measured: 242 of 430 eligible, and the
# resulting top ten is Parker, Delle Donne, Park, Prince, Jones, Gray, Miles, Diggins-Smith,
# Burton, Clark -- no sub-1,000-possession row. Consumers that rank or sort should filter on
# this column; consumers that display a single player's rating should use `low_sample_flag`
# instead. Integer (`L`) on purpose, compared against integer possession counts.
RAPM_LEADERBOARD_MIN_POSS_PER_SIDE <- 1000L
RAPM_MIN_POSS_PER_SIDE_DEFAULT     <- 1000L

# Fractional change in a player's projected mean per +1.00 of opponent team
# possession-weighted `drapm` (Finding M-4). DERIVED EMPIRICALLY, not asserted:
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
#   The signs flipped at #79; the magnitudes did not flip with them -- they GREW.
#
#   SUPERSEDED FIGURES, kept so each change stays auditable. Two generations now:
#
#     gen 1, original derivation: -0.2591 absolute / -0.0296 via mean points /
#       -0.0256 direct fractional / -0.2598 for 2026 alone / -2.26 and r = -0.675 at
#       team level (written up with the opposite signs, pre-#79).
#     gen 2, re-derived 2026-10-22 on the post-#79/#81 cache: -0.4159 / -0.0474 /
#       -0.0409 / -0.3676 / -3.13 and r = -0.652. Adopted at 03bb12e. That drift was
#       NOT a convention or cache artifact -- the identical regression against the
#       pre-#79, pre-centring cache also returned |0.4160|, so it was accumulated
#       2026 data since gen 1.
#
#   Gen 3 (above) has a DIFFERENT cause, and it is worth not conflating them: the
#   data is unchanged from gen 2 (same 16,657 player-games, same mean points 8.768),
#   but issue #76 centred the ridge target, which re-split every player's O/D rating
#   by exposure and so MOVED THE REGRESSOR ITSELF.
#
#   We take the direct fractional estimate, -0.0504, since it is the estimand that
#   matches the multiplicative form actually used. The absolute-scale estimate
#   (-0.0569) is the corroborating upper bound; both are the same sign at p < 1e-7.
#   Adopting -0.0504 over -0.0409 moves a projection by at most 1.14% on a single
#   team (Dallas Wings, the league's weakest defence on the post-#76 aggregates) and
#   leaves the clamp binding for 0 of 15 teams, so no projection is clamp-limited by
#   the change. NOTE that tools/rederive_m4_slope.R's own gate reads "within 25% of
#   shipped; no action indicated" at this ratio -- adoption here was a deliberate
#   owner decision to keep the constant matched to the post-#76 regressor rather
#   than a threshold firing.
OPP_DEF_MU_SLOPE <- -0.0504

# Multiplier clamp bounds (+/- 15%) for adjust_mu_for_opponent().
# Re-measured 2026-10-23 under the -0.0504 slope and the post-#76 cache: the unclamped
# estimate spans 0.95x (Washington Mystics, the strongest defense) to 1.06x (Dallas Wings,
# the weakest) across the 15 real 2026 team aggregates, so the clamp still does not bind on
# real data for any team -- it exists purely so that a future degenerate RAPM cache cannot
# swing a projection arbitrarily (the OLD formula's raw ratio spanned roughly 0x to 2.2x and
# would have flipped a projection's sign outright on a negative team aggregate).
OPP_DEF_MU_CLAMP <- c(0.85, 1.15)

# ------------------------------------------------------------------------------------------
# API Throttling & Rate-Limiting (carried over from NBA as reasonable starting defaults -
# sport-agnostic, per WNBA_REPLICATION_PLAN.md)
# ------------------------------------------------------------------------------------------
RATE_LIMIT_SLEEP_SEC <- 1.5
MAX_RETRIES          <- 3

# ------------------------------------------------------------------------------------------
# Secrets / Webhooks
# ------------------------------------------------------------------------------------------
# The NBA repo hardcodes a LIVE Discord webhook URL directly in config.R via Sys.setenv() -
# this is a known, flagged issue (see REPO_MAP.md §2/§10: "treat as a real credential checked
# into a plaintext file"). Ground Rules for Every Agent (task_assignments.md, rule 4)
# explicitly forbid reusing that webhook. DO NOT hardcode a URL here.
#
# ACTION REQUIRED (human/future agent): create a NEW Discord server/channel webhook for the
# WNBA project, then set it as a real environment variable (e.g. in a `.Renviron` file or the
# Windows user environment - NOT committed to this repo in plaintext) named DISCORD_WEBHOOK.
# Sys.getenv() below returns "" until that is done, which notify_bets.R / live_game_listener.R
# already handle as a "webhook not configured" no-op state.
DISCORD_WEBHOOK <- Sys.getenv("DISCORD_WEBHOOK", "")
