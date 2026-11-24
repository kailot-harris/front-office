# ==============================================================================
# tests/test_coaching_dataset.R
#
# Regression suite for NBA_analytics#188: build_coaching_dataset.R must not
# publish hand-typed/unsourced coaching registry columns (head coach names,
# tenure, coaching tree, assistant staff, tactical archetypes, or career
# records) without a verified source & as-of date.
#
# Runs completely in-memory with NBA_SKIP_STAGE_AUTORUN=1.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(tibble)
})

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  if (basename(base) == "tests") {
    normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
  } else {
    normalizePath(base, winslash = "/", mustWork = FALSE)
  }
})

failures <- 0L
checks   <- 0L

ok <- function(label, cond) {
  checks <<- checks + 1L
  if (isTRUE(cond)) {
    cat(sprintf("  PASS  %s\n", label))
  } else {
    failures <<- failures + 1L
    cat(sprintf("  FAIL  %s\n", label))
  }
}

old_skip <- Sys.getenv("NBA_SKIP_STAGE_AUTORUN", unset = NA_character_)
Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")
on.exit({
  if (is.na(old_skip)) Sys.unsetenv("NBA_SKIP_STAGE_AUTORUN")
  else Sys.setenv(NBA_SKIP_STAGE_AUTORUN = old_skip)
}, add = TRUE)

old_wd <- getwd()
setwd(REPO_ROOT)
on.exit(setwd(old_wd), add = TRUE)

source(file.path(REPO_ROOT, "build_coaching_dataset.R"))

cat("=== test_coaching_dataset.R ===\n")

# 1. Registry schema: only canonical team_abbr and team_name remain
ok("coaching_registry_raw has 30 teams", nrow(coaching_registry_raw) == 30L)
ok("coaching_registry_raw has only team_abbr and team_name",
   identical(sort(names(coaching_registry_raw)), c("team_abbr", "team_name")))

forbidden_cols <- c(
  "head_coach", "tenure_years", "coaching_tree",
  "assoc_head_coach", "offensive_coord", "defensive_coord",
  "player_dev_lead", "tactical_archetype",
  "career_games", "career_win_pct"
)
ok("coaching_registry_raw omits all hand-typed coaching columns",
   length(intersect(names(coaching_registry_raw), forbidden_cols)) == 0L)

# 2. Unobserved tactical_events: omits headCoach/assistants and publishes NA/unobserved
unobs <- compute_coaching_metrics(coaching_registry_raw, tactical_events = NULL, teams_proj_df = NULL)
ok("compute_coaching_metrics returns 30 entries", length(unobs) == 30L)

forbidden_json_keys <- c("headCoach", "assistants", "careerGames", "careerWinPct")
ok("no entry contains headCoach, assistants, careerGames, or careerWinPct",
   all(vapply(unobs, function(x) length(intersect(names(x), forbidden_json_keys)) == 0L, logical(1))))

ok("unobserved atoMetrics provenance is 'unobserved'",
   all(vapply(unobs, function(x) identical(x$provenance$atoMetrics, "unobserved"), logical(1))))
ok("unobserved atoOffensivePpp is NA",
   all(vapply(unobs, function(x) is.na(x$metrics$atoOffensivePpp), logical(1))))
ok("unobserved coachImpactRating is NA",
   all(vapply(unobs, function(x) is.na(x$metrics$coachImpactRating), logical(1))))
ok("unobserved observedSeasons is NULL",
   all(vapply(unobs, function(x) is.null(x$provenance$observedSeasons), logical(1))))

# 3. Observed tactical_events for teams: emits observed_pbp and measured metrics
mock_events <- list(
  ato_off = c(OKC = 1.12, BOS = 1.08),
  ato_def = c(OKC = 0.98, BOS = 1.01),
  ato_off_poss = c(OKC = 100L, BOS = 95L),
  ato_def_poss = c(OKC = 105L, BOS = 98L),
  challenge = c(OKC = 0.60, BOS = 0.55),
  challenge_attempts = c(OKC = 25L, BOS = 20L),
  n_events = 438L,
  season_label = "2025-2026"
)
obs <- compute_coaching_metrics(coaching_registry_raw, tactical_events = mock_events, teams_proj_df = NULL)
okc <- obs[[1]]
ok("observed OKC entry has teamAbbr == OKC", identical(okc$teamAbbr, "OKC"))
ok("observed OKC entry has observed_pbp atoMetrics", identical(okc$provenance$atoMetrics, "observed_pbp"))
ok("observed OKC entry has observedSeasons == '2025-2026'", identical(okc$provenance$observedSeasons, "2025-2026"))
ok("observed OKC entry has non-NA coachImpactRating", !is.na(okc$metrics$coachImpactRating))

cat(sprintf("\n%d passed, %d failed\n", checks - failures, failures))
if (failures > 0L) quit(status = 1L)
