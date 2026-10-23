# ==============================================================================
# NFL Analytics Pipeline - Global Configuration
# Path: c:/Users/kailo/kayceeslices/front-office/nfl analytics/config.R
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
PROJECT_DIR <- "c:/Users/kailo/kayceeslices/front-office/nfl analytics"
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

# Added per docs/SPEC_playoff_odds_table.md decision #3 (GitHub issue #11, "Playoff Odds 1" -
# first slice of the playoff-clinching probability feature, issues #11-#16). Number of Monte
# Carlo trials for the NEW full-season-to-playoff-odds simulation (the future
# playoff_odds_engine.R, issue #12): each trial simulates every remaining regular-season game
# for all 32 teams, then runs the real tiebreaker procedure (nfl_tiebreakers.R) to resolve
# seeding/playoff berths. Deliberately a SEPARATE constant from N_SIMULATIONS above, not a
# reuse of it - N_SIMULATIONS backs playoff_simulator.R's much cheaper bracket-only sim (32
# teams already seeded, single-elimination bracket draws only), whereas this constant's trials
# each do far more work (full remaining-schedule simulation + real standings/tiebreaker logic),
# so the two are independently tunable and must not be conflated even though both are "some
# number of Monte Carlo trials" (same discipline as RATING_SHRINKAGE_GAMES_K vs.
# MIN_SAMPLE_GAMES_FOR_STAKE above - two "games" constants that look similar but gate different
# things).
#
# EMPIRICALLY DERIVED 2026-10-05 - see tools/time_playoff_odds_engine.R (GitHub issue #16,
# "Playoff Odds 6") for the full timing/stability harness this value and its evidence below
# came from. Run against the REAL CACHE_SCHEDULES/CACHE_TEAM_RATINGS snapshot already in
# cache/ on this machine, not a synthetic benchmark.
#
# TIMING TABLE (trial count -> wall-clock seconds):
#   n=30    -> 8.54 sec   (0.2846 sec/trial)              [DIRECTLY MEASURED, this run]
#   n=50    -> 16.78 sec  (0.3356 sec/trial)               [DIRECTLY MEASURED, this run]
#   n=1000  -> 204.94 sec (run A) / 308.54 sec (run B)     [DIRECTLY MEASURED, this run -
#                                                            two full run_playoff_odds_engine()
#                                                            calls; the ~100 sec spread between
#                                                            run A and run B at the SAME n is
#                                                            itself evidence of real machine-
#                                                            load variance, not a bug]
#   n=1000  -> 362.58 sec (0.363 sec/trial)                [DIRECTLY MEASURED separately, issue
#                                                            #13's own verification run, prior
#                                                            data point - consistent order of
#                                                            magnitude with the two runs above]
#   n=200   -> ~62 sec (~1.0 min)                          [EXTRAPOLATED: avg 0.3101 sec/trial
#                                                            from the n=30/n=50 direct
#                                                            measurements x 200]
#   n=500   -> ~155 sec (~2.6 min)                         [EXTRAPOLATED, same method x 500]
#   n=2000  -> ~620 sec (~10.3 min)                        [EXTRAPOLATED, same method x 2000]
# Extrapolation is valid here because .simulate_one_season() (playoff_odds_engine.R) is a
# fresh, independent computation on every call - it re-reads both caches from disk each trial
# and keeps no shared state/memoization across trials - so per-trial cost does not change with
# trial count; only wall-clock scales linearly.
#
# STABILITY CHECK: ran run_playoff_odds_engine() twice in a row at n=1000 against the IDENTICAL
# cache snapshot (same tools/time_playoff_odds_engine.R run) and diffed playoff_prob for all 32
# NFL_TEAMS. Max abs diff across all 32 teams = 0.052 (DEN: 0.631 vs 0.579); mean abs diff =
# 0.009. TOLERANCE: +/-0.06 (6 percentage points) per team, chosen because this number is read
# by humans on Discord as a rounded percentage, not used as a precision-critical input - the
# observed 5.2-point max swing (DEN, a near-50/50 team where variance is structurally highest)
# sits inside that tolerance, and the binomial standard-error formula sqrt(p*(1-p)/n) confirms
# this is consistent with ordinary Monte Carlo noise at n=1000, not an instability: worst-case
# SE (p=0.5) = sqrt(0.25/1000) = 0.0158, so a ~2-3 SE swing on one trial pair is unsurprising;
# teams at extreme probabilities (JAX/MIA at 0.000-1.000, SEA/MIN near 0.998) showed zero or
# near-zero diff, exactly as the same formula predicts (SE shrinks toward 0 as p -> 0 or 1).
#
# DECISION: kept at 1000 (not changed from the prior starting value - re-confirmed via real
# measurement rather than kept by default without evidence). Reasoning: this stage runs once per DAILY
# run_full_pipeline.R run alongside other stages (see that file's header), so a ~3.5-5 min cost
# at n=1000 is comfortably affordable; n=2000 would roughly double that (~10 min) for a modest
# noise reduction (SE ~0.0158 -> ~0.0112, worst case) that is not needed given the n=1000
# stability check above already lands inside the stated tolerance; n=500 would roughly halve
# runtime but increase worst-case SE to ~0.0224, close enough to the observed 5.2-point max diff
# at n=1000 that halving n risks pushing real swings outside the stated tolerance rather than
# comfortably inside it. 1000 is the point in the timing table that balances both constraints.
N_SEASON_SIMULATIONS <- 1000

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
#
# RE-CHECKED AGAINST A SHARPE OBJECTIVE 2026-09-17 (tools/derive_market_blend_weight_sharpe.R) -
# this constant was only ever optimized for Brier/calibration, never for staking profitability,
# and this session's Phase 4/5 findings (situational EPA, Kalman state-space) both showed Brier
# improvements can come with Sharpe REGRESSIONS - so the question was worth asking directly
# against the deployed ensemble_ridge_elo formula and its real staking gates
# (MIN_SAMPLE_GAMES_FOR_STAKE + LONGSHOT_DECIMAL_ODDS_CAP). Result: Sharpe is NEGATIVE across the
# ENTIRE [0, 1] weight grid (walk-forward, 2010-2025, n=4,009 games with real moneylines) -
# roughly -0.05 to -0.06 for w in [0, 0.9], degrading further as w -> 1 (n=0 bets at w=1.00 - a
# model identical to the market has no edge over its own devigged price, so no positive-EV bet
# is ever found). The Sharpe-optimal weight (w=0.748, Sharpe=-0.0506, n=1,197 bets) is a real but
# modest per-bet improvement over w=0.97's Sharpe=-0.0909, but it comes from staking on ~25x more
# games - LOWERING the weight would mean much larger ABSOLUTE cumulative losses (-80% vs. -0.6%
# over this window), not a fix. NOT changed as a result of this check: w=0.97's very thin bet
# volume is arguably the safer property given no real edge exists at any weight, not a flaw to
# correct. Real-money staking should stay paused regardless (Known Issue #4).
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

# Added by market_odds_engine.R (model-quality remediation, investigation of docs/HANDOFF.md
# Known Issue #5) - a narrowly-scoped, documented exception (market_odds_engine.R does not own
# config.R; it owns only this one new constant). Caps staking to bets whose decimal odds on the
# picked side are <= this value - i.e. gates OUT long-shot underdog prices beyond this point,
# regardless of how large the model's computed EV looks for them.
#
# ROOT CAUSE this mitigates (see tools/investigate_ev_clustering.R's output, run 2026-09-17):
# home_ev/away_ev = model_prob * decimal_odds - 1. Since MARKET_BLEND_WEIGHT=0.97 anchors 97%
# of model_prob to the SAME game's own devigged market probability used to derive decimal_odds
# here, apparent EV is driven almost entirely by the model's remaining 3% disagreement with the
# market - a roughly fixed absolute probability delta. decimal_odds scales inversely with market
# probability, so that same fixed delta produces a small EV% at short (favorite) odds and an
# explosive EV% at long (underdog) odds - an artifact of the EV formula's odds-scaling, not
# genuine model skill. Confirmed empirically against the production ensemble_ridge_elo formula:
# 100% (124/124, pre-fix run) of Kelly-positive bets were on the underdog side, and mean EV%
# was strictly DECREASING as model probability rose (2.26% in the [0,0.1] bin down to 0.46% in
# the (0.4,0.5] bin) - the "edge" gets larger, not smaller, the longer the odds, concentrated in
# exactly the noisiest games (backup QBs, rested starters, clinched-playoff-seed week-17 games -
# 29% of all Kelly-positive bets fell in week 17 alone in that same run).
#
# NOTE ON REPRODUCIBILITY: tools/ridge_massey_model.R's cv.glmnet() call had no fixed seed
# before this same investigation found and fixed it (see that file's own comment) - CV-fold
# randomness alone swung n_bets 124 -> 56 and Sharpe -0.08 -> -0.15 between two runs of the
# IDENTICAL formula/data. This constant's derivation below was run only after that fix, so its
# figures are reproducible run-to-run (re-verified twice, both giving n=56, Sharpe=-0.1461 at
# no cap) - but this means any EARLIER Brier/Sharpe figure in docs/HANDOFF.md that used the
# ridge model (ridge_only/ridge_phase1_combined/ensemble_ridge_elo) was computed under the old
# non-deterministic behavior and should be re-verified, not assumed exact, before being cited.
#
# EMPIRICALLY BACKTESTED 2026-09-17 - see tools/derive_longshot_odds_cap.R and
# cache/longshot_odds_cap_derivation.rds. Walk-forward, out-of-sample, quarter-Kelly staking
# simulation against REAL historical closing moneylines, MIN_SAMPLE_GAMES_FOR_STAKE gate
# applied, production ensemble_ridge_elo formula, seasons 2010-2025 (same window as
# MARKET_BLEND_WEIGHT/MIN_SAMPLE_GAMES_FOR_STAKE - real moneylines only from 2010 onward),
# n=56 Kelly-positive bets at this staking gate before any odds cap, optimized via
# stats::optimize() (golden-section search, not a grid search) maximizing Sharpe over the cap
# in [1.5, 15] decimal odds.
#   No cap (tau=9 gate only, current production behavior): n=56  Sharpe=-0.1461  cum%=-1.1%
#   Optimizer result: cap=9.68 -> n=48  Sharpe=-0.0809  cum%=-0.6%
#   Grid reference (see the derivation script's own printed table): Sharpe is NEGATIVE at
#   every cap tested from 3.5 to 15 except a thin, low-n (n=13) local bump at cap=4.0
#   (Sharpe=+0.0069) that is not distinguishable from noise at that sample size.
#
# IMPORTANT - READ BEFORE STAKING REAL MONEY: same honesty discipline as
# MIN_SAMPLE_GAMES_FOR_STAKE's own comment - Sharpe is NEGATIVE at every cap tested. This is a
# MITIGATION (removes the odds range where the EV formula's own artifact concentrates,
# roughly halving cumulative loss vs. no cap) not a validated edge. Real-money staking should
# stay paused (docs/HANDOFF.md Known Issue #4) regardless of this constant's value.
LONGSHOT_DECIMAL_ODDS_CAP <- 9.7

# ------------------------------------------------------------------------------------------
# Situational EPA Feature Thresholds (Phase 4 model-quality remediation: situational-feature
# engineering, docs/HANDOFF.md's "situational EPA splits" roadmap item)
# ------------------------------------------------------------------------------------------
# NOT locally derived/backtested from this repo's own data - these are standard, widely-cited
# sabermetric convention thresholds (same status as team_ratings_engine.R's own
# .PYTHAGOREAN_EXPONENT <- 2.37: carried over from public research as a reasonable starting
# definition, not tuned against this repo's outcomes). A future agent revisiting Phase 4/5
# should treat these as candidates to sweep/validate, not settled values.
#   - RED_ZONE_YARDLINE_MAX: nflverse's own `yardline_100` is always measured as "yards to the
#     opponent's end zone" regardless of possession side, so `yardline_100 <= 20` is the
#     league's own standard red-zone definition (no ambiguity/derivation needed here, unlike
#     the two below).
#   - EXPLOSIVE_PASS_YARDS / EXPLOSIVE_RUSH_YARDS: the common nflfastR-community explosive-play
#     convention (10+ yard rush, 15+ yard pass) - see e.g. rbsdm.com/stats and widely-used EPA
#     write-ups; not the only convention in public use, but the most common one.
#   - MONEY_DOWN_MIN: down >= 3 (3rd/4th down), the standard "passing down" / conversion-
#     pressure split used throughout public NFL analytics.
#   - GARBAGE_TIME_ABS_SCORE_DIFF: |score_differential| > 16 in the 4th quarter (or OT) is a
#     common nflfastR-community garbage-time heuristic; used here only to EXCLUDE plays from
#     situational EPA/PROE aggregates, never to drop plays from the base off_epa_per_play/
#     def_epa_per_play_allowed aggregates in epa_metrics_engine.R (those stay full-game, matching
#     their existing validated behavior - narrowing scope only for the new situational columns).
RED_ZONE_YARDLINE_MAX      <- 20
EXPLOSIVE_PASS_YARDS       <- 15
EXPLOSIVE_RUSH_YARDS       <- 10
MONEY_DOWN_MIN             <- 3
GARBAGE_TIME_ABS_SCORE_DIFF <- 16

# Single source of truth for the situational rolling-column NAMES epa_metrics_engine.R computes
# (CACHE_EPA_METRICS) and tools/backtest_common.R's build_week_snapshot()/build_walkforward_
# games() carry through into the walk-forward game table - avoids the two files' column lists
# silently drifting apart (this repo's CLAUDE.md constants-drift lesson applied to a column-name
# list, not just a numeric literal).
SITUATIONAL_EPA_ROLL_COLS <- c(
  "off_epa_early_down_roll", "off_success_early_down_roll",
  "off_epa_money_down_roll", "off_success_money_down_roll",
  "off_redzone_success_rate_roll", "off_explosive_rate_roll", "off_proe_roll",
  "def_epa_early_down_allowed_roll", "def_success_early_down_allowed_roll",
  "def_epa_money_down_allowed_roll", "def_success_money_down_allowed_roll",
  "def_redzone_success_rate_allowed_roll", "def_explosive_rate_allowed_roll", "def_proe_allowed_roll"
)

# ------------------------------------------------------------------------------------------
# Kalman State-Space Model Hyperparameters (Phase 5, model-quality remediation)
# ------------------------------------------------------------------------------------------
# EMPIRICALLY DERIVED - see tools/derive_kalman_params.R (stats::optim(), method = "L-BFGS-B",
# box-constrained joint search over all four params, walk-forward Brier minimization - same
# discipline as ELO_K_FACTOR's tools/derive_elo_k.R, generalized from one parameter to four).
# Derivation run 2026-09-17 against real CACHE_SCHEDULES data, seasons 2002-2025 (2002 burn-in,
# scored 2003-2025, n=6,499 games): Brier at optimum = 0.2202 (vs. 0.2225 at literature-informed
# starting values - KALMAN_INITIAL_VARIANCE/KALMAN_OBSERVATION_VARIANCE started near
# NFL_MARGIN_SIGMA^2, KALMAN_SEASON_CARRYOVER started at ELO_SEASON_CARRYOVER's 2/3 literature
# value, KALMAN_PROCESS_VARIANCE started at a small placeholder - see that script's header for
# the full starting-value rationale). See tools/kalman_state_space_model.R's header for what
# each parameter means (initial/process/observation variance of the per-team Gaussian random
# walk, and the season-boundary carryover fraction).
KALMAN_INITIAL_VARIANCE     <- 213.1376
KALMAN_PROCESS_VARIANCE     <- 0.5596
KALMAN_OBSERVATION_VARIANCE <- 149.6345
KALMAN_SEASON_CARRYOVER     <- 0.7169

# ------------------------------------------------------------------------------------------
# Cache Filepaths
# ------------------------------------------------------------------------------------------
CACHE_PBP             <- file.path(CACHE_DIR, "pbp_cache.rds")
CACHE_SCHEDULES       <- file.path(CACHE_DIR, "schedules_cache.rds")
CACHE_ROSTERS         <- file.path(CACHE_DIR, "rosters_cache.rds")
CACHE_INJURY_DATA     <- file.path(CACHE_DIR, "injury_data_cache.rds")
CACHE_PARTICIPATION   <- file.path(CACHE_DIR, "participation_cache.rds")
# Added by tools/participation_features.R (Known Issue #7 pickup, 2026-09-17) - a
# tools/-only, backtest-only historical feature pipeline, deliberately NOT part of
# run_full_pipeline.R's DAG. See that file's header for why: nflreadr::load_participation()
# is 2016+ only and, per this repo's earlier live verification (CLAUDE.md / docs/
# NFL_REPLICATION_PLAN.md), 2023+ data is FTN-sourced and released only AFTER the current
# season's postseason completes - LIVE-RE-VERIFIED 2026-09-17: load_participation(seasons=2026)
# returns a real 404 (0 rows) against the current in-progress season, confirming this is a hard
# data-availability wall, not a stale claim. CACHE_PARTICIPATION_FEATURES is the derived
# per-team-per-game rolling table (personnel/box-count/pressure features), analogous to
# CACHE_EPA_METRICS but for a fundamentally backtest-only, never-live-usable feature set.
CACHE_PARTICIPATION_FEATURES <- file.path(CACHE_DIR, "participation_features.rds")
PARTICIPATION_MIN_SEASON <- 2016L  # nflreadr::load_participation()'s own hard floor, verified live
CACHE_NEXTGEN_STATS   <- file.path(CACHE_DIR, "nextgen_stats_cache.rds")
CACHE_PLAYER_PROPS    <- file.path(CACHE_DIR, "latest_player_props.rds")
# Added by player_id_crosswalk.R's load_player_id_crosswalk() (cross-source NFL player-ID
# crosswalk, nflreadr::load_ff_playerids() - see that file's header for the live-verified
# schema/quirks). A narrow documented exception, same pattern as CACHE_EPA_METRICS etc. below
# (player_id_crosswalk.R does not own config.R; it owns only this one constant).
CACHE_PLAYER_ID_CROSSWALK <- file.path(CACHE_DIR, "player_id_crosswalk.rds")
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
# Added by bet_tracker.r (model-quality remediation, Known Issue #2) - a narrowly-scoped,
# documented exception (bet_tracker.r does not own config.R; it owns only this one new
# constant). Per risk_management_engine.R's own header comment (written when it was built,
# before a real ledger existed): "the placeholder path ... should become a real
# CACHE_BETTING_LEDGER constant in config.R" once bet_tracker.r exists and writes it - this is
# that promised follow-through, not a new decision. risk_management_engine.R's
# load_real_ledger()/run_risk_management() now read this constant instead of a literal
# "cache/betting_ledger.rds" string.
CACHE_BETTING_LEDGER <- file.path(CACHE_DIR, "betting_ledger.rds")
# Added per docs/SPEC_accuracy_trajectory_monitoring.md decision #6 (GitHub issue #4,
# "Accuracy Tracker 2") - prep infrastructure for the future accuracy_tracker.R pipeline stage
# (issue #5) and its grading logic (issue #2's grade_walkforward_games()). A narrowly-scoped,
# documented exception, same pattern as CACHE_EPA_METRICS / CACHE_BETTING_LEDGER above (the
# init/append helpers in tools/backtest_common.R do not own config.R; they own only this one
# new constant).
#
# Purpose: persisted season-to-date accuracy history across runs of accuracy_tracker.R, so the
# model's prediction accuracy trajectory can be posted to Discord and inspected over time
# (unlike tools/weekly_accuracy_report.R's CACHE_WEEKLY_ACCURACY_REPORT-style caches, which
# overwrite in place on every run with no history). Per decision #5, one row is appended per
# *run that detects newly-completed/graded games* (not one row per NFL week) - a run that finds
# nothing new graded since the last row is a no-op and appends nothing.
#
# Row schema (one row per data.frame row, `newly_graded_games` a list-column holding a
# data.frame of that run's newly-graded games - usually 1 row, but >1 when multiple games
# complete between runs, e.g. a full Sunday slate graded in one pass):
#   run_timestamp      <POSIXct> - wall-clock time this row was appended (Sys.time())
#   season             <integer> - NFL season these games belong to (CURRENT_SEASON)
#   newly_graded_games <list>    - one data.frame per row, columns:
#       game_id              <character> - nflverse game_id, joins back to CACHE_SCHEDULES
#       matchup              <character> - "AWAY @ HOME" display string
#       predicted_winner     <character> - team abbreviation the model favored pre-game
#       actual_winner        <character> - team abbreviation that actually won
#       correct              <logical>   - predicted_winner == actual_winner
#       predicted_win_prob   <numeric>   - model's pre-game home_win_prob (or winner-side prob)
#   overall_accuracy   <numeric> - cumulative season-to-date accuracy across ALL graded games
#                                  for `season` as of this run (not just newly_graded_games)
#   overall_brier      <numeric> - cumulative season-to-date Brier score, same scope as above
#   overall_logloss    <numeric> - cumulative season-to-date log-loss, same scope as above
#   n_games_graded     <integer> - total count of games underlying the three cumulative metrics
#                                  above (i.e. nrow() of issue #2's grade_walkforward_games()
#                                  per_game table for `season`, as of this run)
# This shape is designed to hold whatever issue #2's grade_walkforward_games() eventually
# returns (documented there as list(per_game, by_week, overall_accuracy, overall_brier,
# overall_logloss)) without needing a schema change once that function exists.
CACHE_ACCURACY_HISTORY <- file.path(CACHE_DIR, "accuracy_history.rds")
# Added per docs/SPEC_playoff_odds_table.md decision #5 (GitHub issue #11, "Playoff Odds 1" -
# first slice of the playoff-clinching probability feature, issues #11-#16) - prep
# infrastructure for the future playoff_odds_engine.R pipeline stage (issue #12). A narrowly-
# scoped, documented exception, same pattern as CACHE_EPA_METRICS / CACHE_PLAYOFF_SIMULATION /
# CACHE_ACCURACY_HISTORY above (playoff_odds_engine.R does not own config.R; it will own only
# this one new constant once it exists).
#
# Purpose: persisted output of the new N_SEASON_SIMULATIONS-trial full-season Monte Carlo
# simulation - per-team playoff-clinching/seeding probabilities, distinct from
# CACHE_PLAYOFF_SIMULATION above (that cache holds playoff_simulator.R's cheaper bracket-only
# sim output, seeded teams only; this one will hold the heavier regular-season-to-playoff-odds
# sim's output, computed for all 32 teams including those not yet clinched/eliminated).
# Row schema is not yet defined - that is left to issue #12 (playoff_odds_engine.R itself),
# not decided here; this slice only reserves the constant/filepath so later issues in the
# chain can reference CACHE_PLAYOFF_ODDS from the start rather than hardcoding a path string.
CACHE_PLAYOFF_ODDS <- file.path(CACHE_DIR, "playoff_odds.rds")

# Added per docs/task_assignments_phase8.md Wave 0 (Phase 9 visualization-GIF build, GitHub
# issues #18/#19). Narrowly-scoped documented exceptions, same pattern as CACHE_PLAYOFF_ODDS
# above: tools/playoff_odds_history_backfill.R and tools/turnover_margin_history.R each own
# exactly one of these constants' producing script, not config.R itself.
#
# CACHE_PLAYOFF_ODDS_HISTORY: one row per (week, team) - columns week, team,
# division_win_prob, playoff_prob, bye_prob. Same per-team fields CACHE_PLAYOFF_ODDS already
# produces for "now", snapshotted across every historical week instead of just the latest.
CACHE_PLAYOFF_ODDS_HISTORY <- file.path(CACHE_DIR, "playoff_odds_history.rds")
# CACHE_TURNOVER_HISTORY: one row per (week, team) - columns week, team, takeaways,
# giveaways, turnover_margin, cumulative_margin. No turnover data existed anywhere in this
# repo's caches before this phase (issue #19).
CACHE_TURNOVER_HISTORY <- file.path(CACHE_DIR, "turnover_margin_history.rds")

# ------------------------------------------------------------------------------------------
# Web application export paths (web/public/...)
# ------------------------------------------------------------------------------------------
# Added by export_web_datasets.R when it was promoted from a detached tools/ one-off into a
# real terminal stage of run_full_pipeline.R's DAG. A narrowly-scoped, documented exception to
# that script's single-file ownership, exactly the pattern CACHE_EPA_METRICS /
# CACHE_TEAM_RATINGS / CACHE_PLAYOFF_ODDS above already follow (export_web_datasets.R does not
# own config.R; it owns only these constants).
#
# Why these live here at all: the exporter previously hardcoded
#   PROJECT_ROOT <- "c:/Users/kailo/kayceeslices/front-office/nfl analytics"; setwd(PROJECT_ROOT)
# and then rebuilt its own file.path(PROJECT_ROOT, "web", "public", "data") literals at the
# call site. That is the exact class of duplicated-constant drift CLAUDE.md forbids (sibling
# WNBA repo Finding C-1: a hardcoded home-court-advantage constant silently diverged from
# config.R's value), and the absolute PROJECT_ROOT additionally made the script unrunnable
# from any other checkout - including a git worktree. Paths are therefore RELATIVE here, same
# as CACHE_DIR above, because every script in this flat repo is run with the repo root as the
# working directory (run_full_pipeline.R's run_stage() source()s siblings by bare filename).
#
# WEB_DATA_FILES is the aggregate run_full_pipeline.R passes to run_stage()'s `output =`, so
# the C-2 staleness assertion (.check_stage_output()) covers every published JSON file. The
# exporter writes all of these unconditionally on every run, which is what makes declaring
# them correct here (unlike accuracy_tracker.R / bet_tracker.r, which legitimately no-op on a
# quiet day and therefore deliberately omit `output =`).
WEB_PUBLIC_DIR   <- file.path("web", "public")
WEB_DATA_DIR     <- file.path(WEB_PUBLIC_DIR, "data")
WEB_ANIM_DIR     <- file.path(WEB_PUBLIC_DIR, "animations")

WEB_JSON_VISUAL_MEDIA_INDEX    <- file.path(WEB_DATA_DIR, "visual_media_index.json")
WEB_JSON_STANDINGS_PROJECTIONS <- file.path(WEB_DATA_DIR, "standings_projections.json")
WEB_JSON_MATCHUPS_CURRENT_WEEK <- file.path(WEB_DATA_DIR, "matchups_current_week.json")
WEB_JSON_TEAM_EPA_PROFILES     <- file.path(WEB_DATA_DIR, "team_epa_profiles.json")
WEB_JSON_PLAYOFF_PICTURE       <- file.path(WEB_DATA_DIR, "playoff_picture.json")
WEB_JSON_PLAYER_QB_PROFILES    <- file.path(WEB_DATA_DIR, "player_qb_profiles.json")
WEB_JSON_MODEL_DIAGNOSTICS     <- file.path(WEB_DATA_DIR, "model_diagnostics.json")
WEB_JSON_SALARY_CAP_PROFILES   <- file.path(WEB_DATA_DIR, "salary_cap_profiles.json")
WEB_JSON_COACHING_PROFILES     <- file.path(WEB_DATA_DIR, "coaching_profiles.json")
WEB_JSON_VALUE_BETS            <- file.path(WEB_DATA_DIR, "value_bets.json")

WEB_DATA_FILES <- c(
  WEB_JSON_VISUAL_MEDIA_INDEX,
  WEB_JSON_STANDINGS_PROJECTIONS,
  WEB_JSON_MATCHUPS_CURRENT_WEEK,
  WEB_JSON_TEAM_EPA_PROFILES,
  WEB_JSON_PLAYOFF_PICTURE,
  WEB_JSON_PLAYER_QB_PROFILES,
  WEB_JSON_MODEL_DIAGNOSTICS,
  WEB_JSON_SALARY_CAP_PROFILES,
  WEB_JSON_COACHING_PROFILES,
  WEB_JSON_VALUE_BETS
)

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
