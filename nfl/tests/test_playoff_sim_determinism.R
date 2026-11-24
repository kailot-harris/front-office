# ==============================================================================
# tests/test_playoff_sim_determinism.R
# Verifies deterministic RNG seeding, .Random.seed restoration, and non-degenerate
# Monte Carlo variation for playoff_simulator.R and playoff_odds_engine.R.
# ==============================================================================

failures <- 0L
ok <- function(label, cond, detail = NULL) {
  if (isTRUE(cond)) {
    cat(sprintf("[PASS] %s%s\n", label, if (!is.null(detail)) paste0("  -- ", detail) else ""))
  } else {
    cat(sprintf("[FAIL] %s%s\n", label, if (!is.null(detail)) paste0("  -- ", detail) else ""))
    failures <<- failures + 1L
  }
}

Sys.setenv(NFL_DISCORD_WEBHOOK = "")
source("playoff_odds_engine.R")

cat("=== Playoff Simulator & Odds Engine Determinism Tests ===\n")

# ---- 1. .simulate_bracket() determinism & RNG state preservation ----
afc_teams <- names(NFL_DIVISIONS)[grepl("^AFC", NFL_DIVISIONS)][1:7]
nfc_teams <- names(NFL_DIVISIONS)[grepl("^NFC", NFL_DIVISIONS)][1:7]
seed_tables <- list(
  AFC = data.frame(seed = 1:7, team = afc_teams, power_rating = rep(0, 7), stringsAsFactors = FALSE),
  NFC = data.frame(seed = 1:7, team = nfc_teams, power_rating = rep(0, 7), stringsAsFactors = FALSE)
)

set.seed(999L)
expected_next <- runif(1)
set.seed(999L)

b1 <- .simulate_bracket(seed_tables, n_sims = 40L)
actual_next <- runif(1)
b2 <- .simulate_bracket(seed_tables, n_sims = 40L)
b3 <- .simulate_bracket(seed_tables, n_sims = 40L, seed = 101L)

ok("PS-1 .simulate_bracket() is identical across consecutive default-seed runs",
   identical(b1, b2))
ok("PS-2 .simulate_bracket() varies with a different seed",
   !identical(b1, b3))
ok("PS-3 .simulate_bracket() restores caller .Random.seed on exit",
   identical(actual_next, expected_next))
ok("PS-4 .simulate_bracket() advances RNG across sims (non-degenerate SB winners)",
   sum(b1$sb_wins > 0L) >= 2L,
   sprintf("%d distinct SB winners in 40 sims", sum(b1$sb_wins > 0L)))

# ---- 2. .simulate_one_season() & run_playoff_odds_engine() determinism ----
tmp_dir <- tempfile("nfl_sim_det_")
dir.create(tmp_dir, recursive = TRUE)
on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

CACHE_TEAM_RATINGS <- file.path(tmp_dir, "team_ratings.rds")
CACHE_SCHEDULES <- file.path(tmp_dir, "schedules.rds")
CACHE_PLAYOFF_ODDS <- file.path(tmp_dir, "playoff_odds.rds")
CACHE_PLAYOFF_SIMULATION <- file.path(tmp_dir, "playoff_sim.rds")
N_SEASON_SIMULATIONS <- 12L
N_SIMULATIONS <- 20L

all_teams <- names(NFL_TEAMS)
saveRDS(data.frame(team = all_teams, power_rating = rep(0, length(all_teams)), stringsAsFactors = FALSE),
        CACHE_TEAM_RATINGS)

# Build a minimal schedule: 16 completed games + 16 remaining games so tiebreakers & RNG both run
sch <- data.frame(
  season = CURRENT_SEASON,
  game_type = "REG",
  home_team = c(all_teams[1:16], all_teams[17:32]),
  away_team = c(all_teams[17:32], all_teams[1:16]),
  home_score = c(rep(21, 16), rep(NA_real_, 16)),
  away_score = c(rep(14, 16), rep(NA_real_, 16)),
  stringsAsFactors = FALSE
)
saveRDS(sch, CACHE_SCHEDULES)

set.seed(777L)
expected_after <- runif(1)
set.seed(777L)

s1 <- .simulate_one_season(seed = 42L)
actual_after <- runif(1)
s2 <- .simulate_one_season(seed = 42L)
s3 <- .simulate_one_season(seed = 99L)

ok("PO-1 .simulate_one_season(seed=42L) returns 14 teams and is reproducible",
   length(s1) == 14L && identical(s1, s2))
ok("PO-2 .simulate_one_season() varies with a different seed",
   !identical(s1, s3))
ok("PO-3 .simulate_one_season(seed=42L) restores caller .Random.seed on exit",
   identical(actual_after, expected_after))

ok1 <- run_playoff_odds_engine()
res1 <- readRDS(CACHE_PLAYOFF_ODDS)$field
ok2 <- run_playoff_odds_engine()
res2 <- readRDS(CACHE_PLAYOFF_ODDS)$field

ok("PO-4 run_playoff_odds_engine() produces identical playoff_prob across runs",
   isTRUE(ok1) && isTRUE(ok2) && identical(res1, res2))
ok("PO-5 run_playoff_odds_engine() Monte Carlo trials vary across the loop (fractional probs exist)",
   any(res1$playoff_prob > 0 & res1$playoff_prob < 1),
   sprintf("%d teams with 0 < p < 1", sum(res1$playoff_prob > 0 & res1$playoff_prob < 1)))

ok_sim1 <- run_playoff_simulator()
sim1 <- readRDS(CACHE_PLAYOFF_SIMULATION)$field
ok_sim2 <- run_playoff_simulator()
sim2 <- readRDS(CACHE_PLAYOFF_SIMULATION)$field

ok("PS-5 run_playoff_simulator() produces identical field probabilities across runs",
   isTRUE(ok_sim1) && isTRUE(ok_sim2) && identical(sim1, sim2))

cat(sprintf("\n=== Playoff Sim Determinism Summary: %d failure(s) ===\n", failures))
if (failures > 0L) quit(status = 1L)
