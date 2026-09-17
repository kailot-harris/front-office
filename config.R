# ==============================================================================
# NFL Analytics Pipeline - Global Configuration
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/config.R
#
# Ported from the WNBA Analytics repo's config.R (itself ported from an NBA Analytics
# repo) - see that repo's config.R header and its Finding C-1 for the class of bug this
# structure exists to prevent: a modeling constant silently drifting between config.R and
# call sites because it was hardcoded a second place instead of only living here. Every
# other script in THIS repo must source() this file and reference these constants directly
# - never re-type a literal value that already has a name here.
#
# All empirically-derived constants below (NFL_MARGIN_SIGMA, NFL_HCA) were computed from
# REAL nflreadr::load_schedules() data on 2026-09-16 by tools/derive_nfl_constants.R - see
# that script for full methodology, window rationale, and per-season breakdown. Structural
# facts (roster limits, season length, playoff format, team abbreviations) were verified via
# live web search / nflreadr::load_teams() on 2026-09-16, not recalled from training data.
# Re-run the derivation script and re-verify structural facts at the start of each new
# season before trusting downstream modeling.
# ==============================================================================

# Working and Cache Directories
PROJECT_DIR <- "c:/Users/kailo/kayceeslices/NFL Analytics"
CACHE_DIR   <- file.path(PROJECT_DIR, "cache")
if (!dir.exists(CACHE_DIR)) dir.create(CACHE_DIR, recursive = TRUE)

# ------------------------------------------------------------------------------------------
# NFL-specific structural constants
# ------------------------------------------------------------------------------------------
# Verified via live web search on 2026-09-16 (Giants.com/ESPN/CBS Sports 2026 roster-cutdown
# coverage): each of the 32 teams carries a 53-man active roster during the regular season.
# Only 47 (or 48, if a team dresses an 8th offensive lineman) of those 53 may actually dress
# and play on a given gameday - the rest are healthy scratches. Both numbers are kept below;
# use NFL_ROSTER_MAX for roster-construction/depth-chart logic and NFL_GAMEDAY_ACTIVE_MAX for
# anything modeling who can actually play in a given game.
NFL_ROSTER_MAX          <- 53  # regular-season active roster cap per team
NFL_GAMEDAY_ACTIVE_MAX  <- 48  # max players a team may dress for a given game (47 if only 7 OL dressed)
NFL_PRACTICE_SQUAD_SIZE <- 16  # standard 2026 practice squad size (not part of the 53-man cap)

NFL_GAME_MINUTES <- 60   # 4x15-minute quarters (regulation; overtime is separate/sport-specific)

# Current official NFL regular-season game count per team. Verified via live web search on
# 2026-09-16: the league expanded from 16 to 17 games per team starting with the 2021 season
# (approved March 2021) - the first change to season length since 1978. Re-verify if the
# league ever moves to an 18-game season (has been publicly discussed but not adopted as of
# this verification date).
NFL_SEASON_GAMES       <- 17
NFL_SEASON_GAMES_SINCE <- 2021L  # first season the 17-game schedule applied

# Centralized NFL franchise list - single source of truth for team abbreviations/names.
# Verified empirically via nflreadr::load_teams(current = TRUE) on 2026-09-16 (data as
# nflverse last updated 2026-03-27) - all 32 abbreviations/names below are a direct dump of
# that call's output, not typed from memory. This deliberately uses nflverse's own
# abbreviation conventions (e.g. "LA" = Rams, "LAC" = Chargers, "LV" = Raiders, "WAS" =
# Commanders) so joins against nflreadr-sourced data (schedules, pbp, rosters, etc.) work
# without a remapping step. Every other script in this repo must reference NFL_TEAMS rather
# than hardcoding its own copy of this list (per the WNBA repo's risk-mitigation precedent).
#
# NOTE FOR FUTURE AGENTS: re-run nflreadr::load_teams(current = TRUE) at the start of each new
# season and diff against this list before trusting it - franchise relocations/renames (e.g.
# the Washington franchise's multiple name changes, prior Raiders/Chargers/Rams relocations)
# have happened before and are exactly the kind of stale-constant bug this file exists to avoid.
NFL_TEAMS <- c(
  ARI = "Arizona Cardinals",
  ATL = "Atlanta Falcons",
  BAL = "Baltimore Ravens",
  BUF = "Buffalo Bills",
  CAR = "Carolina Panthers",
  CHI = "Chicago Bears",
  CIN = "Cincinnati Bengals",
  CLE = "Cleveland Browns",
  DAL = "Dallas Cowboys",
  DEN = "Denver Broncos",
  DET = "Detroit Lions",
  GB  = "Green Bay Packers",
  HOU = "Houston Texans",
  IND = "Indianapolis Colts",
  JAX = "Jacksonville Jaguars",
  KC  = "Kansas City Chiefs",
  LA  = "Los Angeles Rams",
  LAC = "Los Angeles Chargers",
  LV  = "Las Vegas Raiders",
  MIA = "Miami Dolphins",
  MIN = "Minnesota Vikings",
  NE  = "New England Patriots",
  NO  = "New Orleans Saints",
  NYG = "New York Giants",
  NYJ = "New York Jets",
  PHI = "Philadelphia Eagles",
  PIT = "Pittsburgh Steelers",
  SEA = "Seattle Seahawks",
  SF  = "San Francisco 49ers",
  TB  = "Tampa Bay Buccaneers",
  TEN = "Tennessee Titans",
  WAS = "Washington Commanders"
)
NFL_TEAM_COUNT <- length(NFL_TEAMS)  # 32 as of the 2026 season (16 per conference, 8 divisions)

# ------------------------------------------------------------------------------------------
# Playoff Format / Bracket Structure
# ------------------------------------------------------------------------------------------
# Verified via live web search on 2026-09-16: the 14-team format (expanded from 12) has been
# in place since the 2020 season and remains current. 7 teams per conference (4 division
# winners seeded 1-4, 3 wild cards seeded 5-7). Only the #1 seed in each conference earns a
# first-round bye - re-verify if the league ever changes bye allocation (e.g. proposals to
# expand to 16 teams / remove byes entirely have been floated but not adopted as of this date).
NFL_PLAYOFF_FIELD          <- 14L  # total playoff teams league-wide
NFL_PLAYOFF_TEAMS_PER_CONF <- 7L   # per conference (AFC/NFC)
NFL_PLAYOFF_DIVISION_WINNERS_PER_CONF <- 4L  # seeds 1-4
NFL_PLAYOFF_WILDCARDS_PER_CONF        <- 3L  # seeds 5-7
NFL_PLAYOFF_BYES_PER_CONF             <- 1L  # only the #1 seed per conference
NFL_PLAYOFF_ROUNDS <- c("wild_card", "divisional", "conference_championship", "super_bowl")

# Added by playoff_simulator.R (Phase 4, task P4-A) per docs/task_assignments_phase3.md's
# "Constants note" pattern - same narrowly-scoped, documented exception as CACHE_EPA_METRICS /
# CACHE_TEAM_RATINGS / CACHE_FATIGUE_METRICS above (playoff_simulator.R does not own config.R;
# it owns only this new team->conference/division mapping).
#
# Verified via live web search on 2026-09-16 (ESPN/vsporto/sportDA 2026 team-by-division
# coverage, cross-checked against NFL_TEAMS above): the current 8-division / 32-team structure
# has been in place since the 2002 realignment (see MODERN_ERA_START_SEASON) and is confirmed
# UNCHANGED for the 2026 season - no team relocated or changed divisions this offseason. Each
# entry maps an NFL_TEAMS abbreviation to "CONF North/South/East/West" (4 teams per division,
# 4 divisions per conference, 8 divisions total). Re-verify at the start of each future season -
# realignment has happened before (most recently 2002) and is exactly the class of structural
# fact this repo re-checks rather than assumes.
NFL_DIVISIONS <- c(
  BUF = "AFC East",  MIA = "AFC East",  NE  = "AFC East",  NYJ = "AFC East",
  BAL = "AFC North", CIN = "AFC North", CLE = "AFC North", PIT = "AFC North",
  HOU = "AFC South", IND = "AFC South", JAX = "AFC South", TEN = "AFC South",
  DEN = "AFC West",  KC  = "AFC West",  LV  = "AFC West",  LAC = "AFC West",
  DAL = "NFC East",  PHI = "NFC East",  WAS = "NFC East",  NYG = "NFC East",
  CHI = "NFC North", DET = "NFC North", GB  = "NFC North", MIN = "NFC North",
  ATL = "NFC South", CAR = "NFC South", NO  = "NFC South", TB  = "NFC South",
  ARI = "NFC West",  LA  = "NFC West",  SF  = "NFC West",  SEA = "NFC West"
)

# ------------------------------------------------------------------------------------------
# Data Horizons
# ------------------------------------------------------------------------------------------
# Verified empirically via nflreadr::load_schedules() on 2026-09-16: the earliest season
# available is 1999. HISTORICAL_SEASONS below is intentionally narrower than "all available
# history" - see tools/derive_nfl_constants.R for the full rationale (2002 league realignment
# to the current 32-team / 8-division structure is treated as the start of the "modern era"
# for modeling purposes; pre-2002 games reflect a genuinely different league shape).
EARLIEST_AVAILABLE_SEASON <- 1999L  # nflreadr::load_schedules()/load_pbp() floor, verified 2026-09-16
MODERN_ERA_START_SEASON   <- 2002L  # post-realignment, current 32-team structure

HISTORICAL_SEASONS <- MODERN_ERA_START_SEASON:2025L
CURRENT_SEASON      <- 2026L  # in progress as of this file's creation (2026-09-16); partial
                               # schedule data only - exclude from any mean/variance derivation
                               # until the season completes (see derive_nfl_constants.R's
                               # has_na_by_season completeness check for why)
ALL_SEASONS         <- MODERN_ERA_START_SEASON:CURRENT_SEASON

# ------------------------------------------------------------------------------------------
# Margin -> Win-Probability Sigma (pnorm()-style win-probability / spread-to-prob conversions)
# ------------------------------------------------------------------------------------------
# EMPIRICALLY DERIVED - see tools/derive_nfl_constants.R for the full script and methodology.
# This is the SINGLE SOURCE for this constant; per the WNBA repo's Finding C-1 (a hardcoded
# sigma silently drifted between config.R and a live call site until it implied a wildly wrong
# win-probability curve), no other script in this repo may restate this literal.
#
# Derivation run 2026-09-16 against real nflreadr::load_schedules() data:
#   sd(home_score - away_score), modern 32-team era (2002-2025 seasons, n = 6,499 completed
#   games, current in-progress 2026 season excluded) = 14.60
# For comparison (see the script's per-season table): full 1999-2025 history = 14.59,
# recent-10-seasons (2016-2025) = 14.16, recent-5-seasons (2021-2025) = 14.17. Sigma is stable
# across windows (unlike NFL_HCA below), so the longer modern-era window is used for a
# lower-noise estimate rather than a short recent window.
NFL_MARGIN_SIGMA <- 14.60

# ------------------------------------------------------------------------------------------
# Home-Field Advantage (points added to the home side's projected margin)
# ------------------------------------------------------------------------------------------
# EMPIRICALLY DERIVED - see tools/derive_nfl_constants.R. SINGLE SOURCE; do not restate.
#
# Derivation run 2026-09-16: mean(home_score - away_score) shows real, sustained downward
# drift across the modern era's per-season breakdown (script output: 2002-2025 full-window
# mean = 2.29, but the per-season table trends lower in recent years - widely attributed
# league-wide to reduced/normalized crowd-noise effects, more accurate officiating via
# expanded replay review, and increased short-week/travel parity). Recent-season figures are
# accordingly compressed relative to the long-run average:
#   recent 10 seasons (2016-2025, n = 2,761 games) = 1.93  <- USED BELOW
#   recent 5 seasons  (2021-2025, n = 1,424 games) = 2.25  (secondary/comparison figure -
#                                                            noisier, smaller sample, but
#                                                            directionally consistent)
#   full modern era   (2002-2025, n = 6,499 games) = 2.29  (NOT used - overstates current HCA)
# The recent-10-season figure is used as the config default: large enough sample to be stable,
# recent enough to reflect the current (compressed) HCA regime rather than the 2000s-era level.
NFL_HCA <- 1.93

# ------------------------------------------------------------------------------------------
# Rolling Window & Modeling Hyperparameters
# ------------------------------------------------------------------------------------------
# Carried over as reasonable Phase 0 starting defaults, sport-agnostic pending real
# out-of-sample tuning against NFL data (analogous to the WNBA repo's later Phase 2 sweep -
# NOT yet performed here; a future agent should re-run an equivalent window sweep before
# relying on this number for anything high-stakes). NFL's 17-game season is far shorter than
# WNBA's 44 or NBA's 82, so a proportionally much smaller window is a reasonable starting
# placeholder, not a validated value.
ROLLING_WINDOW_SIZE <- 4
OFFSEASON_METHOD    <- "reset"  # "reset", "mean_regress", or "decay" - not yet re-benchmarked for NFL
REST_DAYS_CAP       <- 14       # NFL byes/short weeks span a wider range than WNBA's back-to-backs
N_SIMULATIONS       <- 10000

# Added by team_ratings_engine.R (Phase 8, task P8-A) per docs/task_assignments_phase7.md's
# "Constants note" pattern - a narrowly-scoped, documented exception (team_ratings_engine.R does
# not own config.R; it owns only this one new constant). Controls how heavily a team's blended
# power rating leans on its prior-season final rating vs. its real current-season EPA, via
# weight = games_played / (games_played + RATING_SHRINKAGE_GAMES_K).
#
# EMPIRICALLY BACKTESTED 2026-09-17 - see tools/backtest_shrinkage_optimizer.R (walk-forward,
# out-of-sample; each game's rating built only from EPA data strictly before that game's week -
# no lookahead) and cache/phase8_constant_backtest.rds for the full run. Objective: minimize
# Brier score of home_win_prob vs. real game outcomes, seasons 2003-2025 (n=5,548 games),
# optimized via stats::optimize() (golden-section search, not a grid search) over K in [0.1, 30].
#   Optimizer result: K = 3.56 -> Brier = 0.245643
#   Prior starting heuristic (K = 4): Brier = 0.245698 (already within 0.00006 of optimal)
#   Naive baseline K->Inf (pure prior-season rating, never shrinks toward current form): Brier = 0.290935
#   Naive baseline K->0   (pure current-season rating, no shrinkage at all):             Brier = 0.255067
# The starting K=4 heuristic turned out to be nearly optimal - kept at the backtested value
# (rounded to 1 decimal place, not the raw optimizer float, since the objective surface is
# essentially flat near the optimum and a 2-sig-fig value is more honest about precision than a
# spurious 3.56). Re-run the backtest script whenever CACHE_EPA_METRICS gains a new completed
# season and update this value/comment if the recommendation shifts materially.
RATING_SHRINKAGE_GAMES_K <- 3.6

# Added by market_odds_engine.R (Phase 8, task P8-B) per docs/task_assignments_phase7.md's
# "Constants note" pattern - a narrowly-scoped, documented exception (market_odds_engine.R does
# not own config.R; it owns only this one new constant). Distinct from RATING_SHRINKAGE_GAMES_K
# above - that constant shapes the rating BLEND (prior-season vs. current-season weighting);
# this one gates STAKING only (whether a real bankroll recommendation is ever issued for a game),
# and the two must not be conflated into a single constant even though both are "some number of
# games" (per the Constraints section of docs/task_assignments_phase7.md). When either team in a
# matchup has played fewer than MIN_SAMPLE_GAMES_FOR_STAKE real current-season games,
# market_odds_engine.R forces Bankroll_Rec to 0 and marks the row's Status as an insufficient-
# sample flag, regardless of how large the model's computed EV looks - a well-calibrated model
# still should not drive a real stake off 1-2 games of noisy current-season data.
#
# EMPIRICALLY BACKTESTED 2026-09-17 - see tools/backtest_shrinkage_optimizer.R and
# cache/phase8_constant_backtest.rds for the full run. Objective: maximize the Sharpe ratio
# (mean / sd of per-bet pct return) of a real quarter-Kelly staking simulation, RATING_
# SHRINKAGE_GAMES_K applied, run against REAL historical Vegas closing moneylines already
# present in CACHE_SCHEDULES (seasons 2010-2025 only - reliable moneyline coverage; sparse/
# absent 2002-2009, excluded), n=4,009 games with real odds, optimized via stats::optimize()
# (golden-section search, not a grid search) over the threshold in [0, 12].
#   Optimizer result: tau=9  -> n_bets=1,749  Sharpe=-0.0119  cumulative pct return = -62.9%
#   Prior starting heuristic (tau=3): n_bets=3,088  Sharpe=-0.0296  cumulative pct return = -270.6%
#   No gate at all (tau=0):           n_bets=3,755  Sharpe=-0.0134  cumulative pct return = -152.0%
#
# IMPORTANT - READ BEFORE STAKING REAL MONEY: Sharpe is NEGATIVE at every threshold tested,
# including tau=9. This backtest does NOT show a profitable staking strategy at any gate value -
# it only shows that gating out low-sample-size games meaningfully reduces the model's historical
# losses against real closing lines (tau=9 loses ~4x less cumulative % than tau=3, and ~2.4x less
# than no gate). Raising this constant to 9 is the empirically-best MITIGATION found among the
# options tested, not a validated edge. The underlying rating model (EPA-differential power
# rating, see team_ratings_engine.R) has not been shown to beat the closing line historically -
# that is a modeling problem this constant cannot fix, and real-money staking should stay paused
# (per docs/HANDOFF.md Known Issue #5) until a model revision is separately backtested to
# real, positive Sharpe against closing lines, not just re-tuned on this one threshold.
MIN_SAMPLE_GAMES_FOR_STAKE <- 9

# Added by team_ratings_engine.R (Phase 9/model-quality remediation, "Phase 1" of
# docs/HANDOFF.md's post-backtest roadmap) - a narrowly-scoped, documented exception
# (team_ratings_engine.R does not own config.R; it owns only these two new constants).
# Weight given to devigged historical market probability when blended with the EPA
# power-rating model's own probability: blended_prob = MARKET_BLEND_WEIGHT * market_prob +
# (1 - MARKET_BLEND_WEIGHT) * model_prob. Written into CACHE_PROJECTED_MATCHUPS.home_win_prob
# directly (market_odds_engine.R's consumption contract - "home_win_prob is the sole model-
# probability source" - is unchanged; the blend happens upstream, not in that file).
#
# EMPIRICALLY DERIVED 2026-09-17 - see tools/derive_market_blend_weight.R and
# cache/market_blend_weight_derivation.rds for the full run. Walk-forward, out-of-sample,
# optimized via stats::optimize() (golden-section search, not a grid search) minimizing Brier
# score, seasons 2010-2025 (n=4,009 games) - restricted to this window because real historical
# closing moneylines only exist in CACHE_SCHEDULES from 2010 onward (unlike RATING_SHRINKAGE_
# GAMES_K/QB_INJURY_RATING_PENALTY_PTS's full 2003-2025 window - do not silently widen this
# constant's derivation window without a real historical odds source for 2003-2009).
#   Model only  (w=0): Brier = 0.243271
#   Market only (w=1): Brier = 0.210505
#   Optimizer result:  w=0.969 -> Brier = 0.210472
# The optimizer found the market alone (w~0.97) is very close to optimal - consistent with the
# sports-forecasting literature (Wunderlich & Memmert 2018, PLOS ONE) finding the market is
# close to a "sufficient statistic" once it's in a blend. This means the EPA model contributes
# very little on top of the market by itself - see QB_INJURY_RATING_PENALTY_PTS below for the
# piece expected to carry genuine incremental signal instead of re-deriving what the market
# already prices.
MARKET_BLEND_WEIGHT <- 0.97

# QB-injury/backup-starter rating adjustment: rating points subtracted from a team's power
# rating (added to its opponent's relative margin) when tools/qb_injury_features.R's real,
# no-lookahead depth-chart data shows a backup QB started that week instead of the team's own
# "primary" QB (as of that week). See tools/qb_injury_features.R's header for why this needed
# no nflreadr::load_ff_playerids() crosswalk (depth charts are already gsis_id-keyed, same as
# CACHE_ROSTERS/CACHE_INJURY_DATA - no ID-scheme mixing to reconcile at this join point,
# verified live rather than assumed).
#
# EMPIRICALLY DERIVED 2026-09-17 - see tools/derive_qb_injury_penalty.R and
# cache/qb_injury_penalty_derivation.rds for the full run. Walk-forward, out-of-sample,
# optimized via stats::optimize() (golden-section search, not a grid search) minimizing Brier
# score, seasons 2003-2025 (n=5,548 games; 774 home-team and 777 away-team backup-QB games;
# 499 games had an unknown backup-QB flag and received zero adjustment rather than a guess).
#   No adjustment (penalty=0):        Brier = 0.245644
#   Optimizer result: penalty=1.56 pts -> Brier = 0.245437
QB_INJURY_RATING_PENALTY_PTS <- 1.6

# Added by tools/elo_model.R (Phase 3, model-quality remediation) - a narrowly-scoped,
# documented exception (tools/elo_model.R does not own config.R; it owns only this one
# constant plus three literature-reference constants kept LOCAL to that file - see its own
# header for why ELO_HCA_POINTS/ELO_MOV_C/ELO_POINTS_PER_MARGIN_PT are NOT here: they are
# taken directly from FiveThirtyEight's public NFL Elo methodology rather than independently
# re-derived, a deliberate, documented deviation from this file's usual derive-everything
# convention, not an oversight). ELO_K_FACTOR controls how sharply a team's Elo rating moves
# after each game (rating_shift = K * mov_multiplier * (actual_outcome - predicted_prob)).
#
# EMPIRICALLY DERIVED 2026-09-17 - see tools/derive_elo_k.R and cache/elo_k_derivation.rds.
# Walk-forward, out-of-sample (Elo's own sequential game-by-game updates make this
# automatically no-lookahead - each game's prediction only ever uses ratings as they stood
# strictly before that game), optimized via stats::optimize() (golden-section search, not a
# grid search) minimizing Brier score, seasons 2003-2025 (2002 = Elo's own "burn-in" season,
# every team starts at ELO_INITIAL_RATING with no real history yet - not scored, same role
# 2002 already plays for RATING_SHRINKAGE_GAMES_K's prior-season fallback).
#   Optimizer result: K=28.31 -> Brier = 0.220483
# For comparison: this Elo candidate (with tools/elo_model.R's fatigue-as-additive-margin
# covariate folded in) scored BETTER than both the original baseline (Brier 0.2456) and the
# Phase 2 ridge candidate ALONE (Brier 0.2317) on this same metric, using no market data at
# all - see tools/model_backtest_harness.R's comparison table for the full picture including
# how it stacks against the market-blended candidates.
ELO_K_FACTOR <- 28

# ------------------------------------------------------------------------------------------
# Cache Filepaths
# ------------------------------------------------------------------------------------------
CACHE_PBP             <- file.path(CACHE_DIR, "pbp_cache.rds")
CACHE_SCHEDULES       <- file.path(CACHE_DIR, "schedules_cache.rds")
CACHE_ROSTERS         <- file.path(CACHE_DIR, "rosters_cache.rds")
CACHE_INJURY_DATA     <- file.path(CACHE_DIR, "injury_data_cache.rds")
CACHE_PARTICIPATION   <- file.path(CACHE_DIR, "participation_cache.rds")
CACHE_NEXTGEN_STATS   <- file.path(CACHE_DIR, "nextgen_stats_cache.rds")
CACHE_PLAYER_PROPS    <- file.path(CACHE_DIR, "latest_player_props.rds")
# Added by epa_metrics_engine.R (Phase 2, task P2-A) per docs/task_assignments_phase2.md's
# "Constants note" - a narrowly-scoped, documented exception to that script's single-file
# ownership (epa_metrics_engine.R does not own config.R; it owns only this one new constant).
CACHE_EPA_METRICS     <- file.path(CACHE_DIR, "team_epa_metrics.rds")
# Added by team_ratings_engine.R (Phase 2, task P2-B) per docs/task_assignments_phase2.md's
# "Constants note" - same narrowly-scoped, documented exception pattern as CACHE_EPA_METRICS
# above (team_ratings_engine.R does not own config.R; it owns only these two new constants).
CACHE_TEAM_RATINGS        <- file.path(CACHE_DIR, "team_ratings.rds")
CACHE_PROJECTED_MATCHUPS  <- file.path(CACHE_DIR, "projected_matchups.rds")
# Added by fatigue_engine.R (Phase 3, task P3-A) per docs/task_assignments_phase2.md's
# "Constants note" pattern - same narrowly-scoped, documented exception as CACHE_EPA_METRICS /
# CACHE_TEAM_RATINGS above (fatigue_engine.R does not own config.R; it owns only this constant).
CACHE_FATIGUE_METRICS <- file.path(CACHE_DIR, "fatigue_metrics.rds")
# Added by playoff_simulator.R (Phase 4, task P4-A) per docs/task_assignments_phase3.md's
# "Constants note" pattern - same narrowly-scoped, documented exception as CACHE_EPA_METRICS /
# CACHE_TEAM_RATINGS / CACHE_FATIGUE_METRICS above (playoff_simulator.R does not own config.R;
# it owns only this constant and NFL_DIVISIONS above).
CACHE_PLAYOFF_SIMULATION <- file.path(CACHE_DIR, "playoff_simulation.rds")
# Added by risk_management_engine.R (Phase 5, task P5-A) per docs/task_assignments_phase4.md's
# "Constants note" pattern - same narrowly-scoped, documented exception as CACHE_EPA_METRICS /
# CACHE_TEAM_RATINGS / CACHE_FATIGUE_METRICS / CACHE_PLAYOFF_SIMULATION above
# (risk_management_engine.R does not own config.R; it owns only this one new constant).
CACHE_RISK_STATE <- file.path(CACHE_DIR, "risk_state.rds")
# Added by market_odds_engine.R (Phase 6, task P6-A) per docs/task_assignments_phase5.md's
# "Constants note" pattern - same narrowly-scoped, documented exception as CACHE_EPA_METRICS /
# CACHE_TEAM_RATINGS / CACHE_FATIGUE_METRICS / CACHE_PLAYOFF_SIMULATION / CACHE_RISK_STATE above
# (market_odds_engine.R does not own config.R; it owns only these two new constants).
CACHE_LATEST_VALUE_BETS <- file.path(CACHE_DIR, "latest_value_bets.rds")
CACHE_ODDS_HISTORY      <- file.path(CACHE_DIR, "odds_history.rds")

# ------------------------------------------------------------------------------------------
# API Throttling & Rate-Limiting (sport-agnostic starting defaults)
# ------------------------------------------------------------------------------------------
RATE_LIMIT_SLEEP_SEC <- 1.5
MAX_RETRIES          <- 3

# ------------------------------------------------------------------------------------------
# Secrets / Webhooks
# ------------------------------------------------------------------------------------------
# NEVER hardcode a webhook URL here (see WNBA repo's config.R / REPO_MAP.md for the class of
# issue this avoids: a live credential checked into a plaintext file). Set NFL_DISCORD_WEBHOOK
# as a real environment variable (e.g. in a .Renviron file or the OS user environment - NOT
# committed to this repo) before notification scripts need it. Sys.getenv() below returns ""
# until that is done; downstream scripts must treat "" as a "webhook not configured" no-op.
#
# Deliberately namespaced NFL_DISCORD_WEBHOOK, NOT the plain DISCORD_WEBHOOK name the WNBA
# repo's config.R uses - both repos' Sys.getenv() calls can share one machine's environment
# (a single user-level .Renviron), and a plain DISCORD_WEBHOOK name would silently let one
# repo's pipeline post notifications to the other sport's Discord channel. ODDS_API_KEY is
# NOT namespaced the same way (still just ODDS_API_KEY) because both repos legitimately share
# one real Odds API account/key - that collision is intentional, not a bug.
NFL_DISCORD_WEBHOOK <- Sys.getenv("NFL_DISCORD_WEBHOOK", "")
