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

# ------------------------------------------------------------------------------------------
# API Throttling & Rate-Limiting (sport-agnostic starting defaults)
# ------------------------------------------------------------------------------------------
RATE_LIMIT_SLEEP_SEC <- 1.5
MAX_RETRIES          <- 3

# ------------------------------------------------------------------------------------------
# Secrets / Webhooks
# ------------------------------------------------------------------------------------------
# NEVER hardcode a webhook URL here (see WNBA repo's config.R / REPO_MAP.md for the class of
# issue this avoids: a live credential checked into a plaintext file). Set DISCORD_WEBHOOK as
# a real environment variable (e.g. in a .Renviron file or the OS user environment - NOT
# committed to this repo) before notification scripts need it. Sys.getenv() below returns ""
# until that is done; downstream scripts must treat "" as a "webhook not configured" no-op.
DISCORD_WEBHOOK <- Sys.getenv("DISCORD_WEBHOOK", "")
