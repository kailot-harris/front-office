# ==============================================================================
# team_name_resolver.R
# Path: c:/Users/kailo/kayceeslices/front-office/NBA Analytics/team_name_resolver.R
#
# SINGLE SOURCE OF TRUTH for NBA team-name normalization.
#
# Maps any team spelling a bookmaker feed, an ESPN pull or a cached artifact can
# produce (full name, city, nickname, 2-4 letter abbreviation) onto the short
# franchise nickname used as the canonical key across this pipeline - the same
# vocabulary as `team_short_display_name` in box_scores_cache.rds and
# `home_short_display_name` / `away_short_display_name` in the matchups schedule
# spine.
#
# This file used to exist twice: `prediction_accuracy_logger.R` carried
# `.resolve_team_name` and `market_odds_engine.R` carried `resolve_team_name`,
# with byte-identical bodies (GitHub issue 24). Two copies of a 30-branch lookup
# table drift, and a drift here silently publishes a prediction row whose teams
# do not join the schedule spine. There is now exactly one definition; both
# callers source this file.
#
# The 30 regex branches and their outputs are DELIBERATELY unchanged from the
# deduplicated originals - this file is behaviour-preserving by construction.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
})

# Canonical set of short franchise nicknames this resolver can emit. Exported so
# callers (and tests) can assert that a resolved name is a real franchise rather
# than an unrecognized passthrough.
NBA_CANONICAL_NICKNAMES <- c(
  "Celtics", "Thunder", "Cavaliers", "Spurs", "Warriors", "Rockets", "Knicks",
  "Pistons", "Nuggets", "Heat", "76ers", "Pacers", "Trail Blazers",
  "Timberwolves", "Magic", "Grizzlies", "Lakers", "Raptors", "Hawks",
  "Mavericks", "Clippers", "Bucks", "Suns", "Jazz", "Hornets", "Nets", "Bulls",
  "Pelicans", "Wizards", "Kings"
)

# Resolve any team spelling to its short franchise nickname.
# Vectorized over `tm_raw`. An unrecognized input passes through unchanged, so
# callers that need a hard guarantee should check against NBA_CANONICAL_NICKNAMES.
resolve_team_name <- function(tm_raw) {
  s <- tolower(trimws(as.character(tm_raw)))
  dplyr::case_when(
    grepl("celtic|\\bbos\\b|boston", s)                       ~ "Celtics",
    grepl("thunder|\\bokc\\b|oklahoma", s)                    ~ "Thunder",
    grepl("cavalier|\\bcle\\b|cleveland|cavs", s)             ~ "Cavaliers",
    grepl("spur|\\bsas?\\b|san antonio", s)                   ~ "Spurs",
    grepl("warrior|\\bgsw?\\b|golden state|dubs", s)          ~ "Warriors",
    grepl("rocket|\\bhou\\b|houston", s)                      ~ "Rockets",
    grepl("knick|\\bnyk?\\b|new york", s)                     ~ "Knicks",
    grepl("piston|\\bdet\\b|detroit", s)                      ~ "Pistons",
    grepl("nugget|\\bden\\b|denver", s)                       ~ "Nuggets",
    grepl("heat|\\bmia\\b|miami", s)                          ~ "Heat",
    grepl("76er|sixer|\\bphi\\b|philadelphia", s)             ~ "76ers",
    grepl("pacer|\\bind\\b|indiana", s)                       ~ "Pacers",
    grepl("blazer|\\bpor\\b|portland", s)                     ~ "Trail Blazers",
    grepl("timberwolv|\\bmin\\b|minnesota|wolves", s)         ~ "Timberwolves",
    grepl("magic|\\borl\\b|orlando", s)                       ~ "Magic",
    grepl("grizzl|\\bmem\\b|memphis", s)                      ~ "Grizzlies",
    grepl("laker|\\blal\\b|los angeles lakers", s)            ~ "Lakers",
    grepl("raptor|\\btor\\b|toronto", s)                      ~ "Raptors",
    grepl("hawk|\\batl\\b|atlanta", s)                        ~ "Hawks",
    grepl("maverick|\\bdal\\b|dallas|mavs", s)                ~ "Mavericks",
    grepl("clipper|\\blac\\b|los angeles clippers", s)        ~ "Clippers",
    grepl("buck|\\bmil\\b|milwaukee", s)                      ~ "Bucks",
    grepl("sun|\\bphx\\b|phoenix", s)                         ~ "Suns",
    grepl("jazz|\\butah?\\b", s)                              ~ "Jazz",
    grepl("hornet|\\bcha\\b|charlotte", s)                    ~ "Hornets",
    grepl("net|\\bbkn?\\b|brooklyn", s)                       ~ "Nets",
    grepl("bull|\\bchi\\b|chicago", s)                        ~ "Bulls",
    grepl("pelican|\\bnop?\\b|new orleans", s)                ~ "Pelicans",
    grepl("wizard|\\bwas\\b|\\bwsh\\b|washington", s)         ~ "Wizards",
    grepl("king|\\bsac\\b|sacramento", s)                     ~ "Kings",
    TRUE                                                      ~ as.character(tm_raw)
  )
}
