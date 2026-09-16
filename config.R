# ==============================================================================
# WNBA Analytics Pipeline - Global Configuration
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/config.R
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
PROJECT_DIR <- "c:/Users/kailo/kayceeslices/WNBA Analytics"
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
# WNBA_Analysis_Project.Rmd and cache/window_sweep_3_25_results.rds; the curve is genuinely
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
