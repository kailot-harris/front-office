# ==============================================================================
# tools/rederive_m4_slope.R
# Re-derives finding M-4's opponent-defence slope against the CURRENT caches,
# after #79's sign flip and #81's refit.
#
# Why this exists: the M-4 write-up in player_props_engine.R records +0.2591
# absolute / +0.0256 fractional, measured in an earlier session. Re-measuring on
# the live caches gives a materially larger magnitude. This script reproduces all
# three estimators the write-up cites so the gap can be judged, and prints a
# significance-gated verdict rather than asserting a number.
#
# READ-ONLY: writes nothing. Reports; does not change OPP_DEF_MU_SLOPE.
#
# Usage: "C:/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/rederive_m4_slope.R
# ==============================================================================

local({
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
  root <- if (length(file_arg)) {
    dirname(dirname(normalizePath(file_arg[1], winslash = "/", mustWork = FALSE)))
  } else getwd()
  if (!file.exists(file.path(root, "config.R")))
    stop(sprintf("rederive_m4_slope.R: cannot locate the repo root (no config.R at '%s')", root))
  setwd(root)
})

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
})
source("config.R")
source("rapm_join_utils.R")

# OPP_DEF_MU_SLOPE / OPP_DEF_MU_CLAMP live in player_props_engine.R, not config.R
# (that gap is issue #82). Sourcing that file would execute its trailing
# !interactive() block and rewrite the props cache, so extract just these two
# constant assignments and evaluate them in isolation — no side effects.
local({
  src <- parse("player_props_engine.R")
  wanted <- c("OPP_DEF_MU_SLOPE", "OPP_DEF_MU_CLAMP")
  for (expr in src) {
    if (is.call(expr) && identical(as.character(expr[[1]]), "<-") &&
        is.name(expr[[2]]) && as.character(expr[[2]]) %in% wanted) {
      assign(as.character(expr[[2]]), eval(expr[[3]]), envir = globalenv())
    }
  }
  missing <- setdiff(wanted, ls(globalenv()))
  if (length(missing))
    stop("could not extract: ", paste(missing, collapse = ", "))
})

rapm <- readRDS(file.path(CACHE_DIR, "rapm_ratings.rds"))
ros  <- readRDS(file.path(CACHE_DIR, "active_rosters_cache.rds"))
pb   <- readRDS(CACHE_PLAYER_BOX)

cat("=== cache provenance ===\n")
cat(sprintf("rapm_ratings.rds : %d rows, mean(drapm) = %+0.5f, convention = %s\n",
            nrow(rapm), mean(rapm$drapm, na.rm = TRUE),
            if (max(abs(rapm$total_rapm - (rapm$orapm + rapm$drapm)), na.rm = TRUE) <= 0.015)
              "SUM (post-#79)" else "subtraction (pre-#79)"))

# Team aggregate exactly as get_team_def_rapm() builds it: possession-weighted
# mean of rostered players' drapm, via the canonical collision-resolving join.
joined <- join_rapm_to_roster(ros, rapm, matched_only = TRUE)
team_def <- joined %>%
  group_by(team_name) %>%
  summarise(def_rapm = sum(drapm * n_def_poss, na.rm = TRUE) /
                       sum(n_def_poss, na.rm = TRUE), .groups = "drop") %>%
  filter(is.finite(def_rapm))
league_avg <- mean(team_def$def_rapm, na.rm = TRUE)
cat(sprintf("team aggregates  : %d teams, league mean def_rapm = %+0.4f\n",
            nrow(team_def), league_avg))

abbr <- tibble(team_name = unname(WNBA_TEAMS), abbr = names(WNBA_TEAMS))
td <- team_def %>% inner_join(abbr, by = "team_name")

d <- pb %>%
  filter(season %in% 2024:2026, !is.na(points), !is.na(minutes), minutes > 0) %>%
  mutate(opp_abbr = if_else(opponent_team_abbreviation == "CONN", "CON",
                            opponent_team_abbreviation)) %>%
  inner_join(td %>% select(opp_abbr = abbr, opp_def = def_rapm), by = "opp_abbr") %>%
  group_by(athlete_id) %>% filter(n() >= 5) %>%
  mutate(player_mean = mean(points, na.rm = TRUE),
         resid = points - player_mean,
         opp_c = opp_def - league_avg) %>%
  ungroup()

cat(sprintf("sample           : %d player-games, %d players, mean points = %.3f\n\n",
            nrow(d), n_distinct(d$athlete_id), mean(d$points, na.rm = TRUE)))

report <- function(label, fit, recorded) {
  co <- summary(fit)$coefficients
  s <- co["opp_c", 1]; se <- co["opp_c", 2]
  t <- co["opp_c", 3]; p <- co["opp_c", 4]
  cat(sprintf("%-34s %+0.4f  (SE %0.4f, t = %+0.2f, p = %.3g)   recorded %+0.4f  ratio %.2fx\n",
              label, s, se, t, p, recorded, abs(s / recorded)))
  invisible(c(slope = s, p = p))
}

cat("=== the three estimators the M-4 write-up cites ===\n")
a1 <- report("absolute scale",
             lm(resid ~ opp_c, data = d), -0.2591)
a2 <- report("absolute + minutes control",
             lm(resid ~ opp_c + minutes, data = d), -0.2586)
# Direct fractional: response is each player's own proportional deviation.
dfrac <- d %>% filter(player_mean > 0) %>% mutate(frac = resid / player_mean)
a3 <- report("direct fractional (the shipped form)",
             lm(frac ~ opp_c, data = dfrac), -0.0256)

cat(sprintf("\nabsolute / mean points -> fractional  : %+0.4f  (corroborating estimate)\n",
            a1["slope"] / mean(d$points, na.rm = TRUE)))

cat("\n=== verdict ===\n")
shipped <- OPP_DEF_MU_SLOPE
measured <- a3["slope"]; pv <- a3["p"]
cat(sprintf("shipped OPP_DEF_MU_SLOPE = %+0.4f\n", shipped))
cat(sprintf("re-measured (same estimand) = %+0.4f at p = %.3g\n", measured, pv))
if (pv >= 0.01) {
  cat("GATE FAILED: not significant at p < 0.01. Do NOT change the constant.\n")
} else if (sign(measured) != sign(shipped)) {
  cat("SIGN DISAGREEMENT: stop. The flip premise would be wrong.\n")
} else {
  ratio <- abs(measured / shipped)
  cat(sprintf("Sign agrees, significant. Magnitude ratio %.2fx.\n", ratio))
  if (ratio > 1.25 || ratio < 0.8) {
    cat("MATERIAL DRIFT (>25%): the shipped magnitude understates the measured\n")
    cat("effect. Changing it WOULD move live projections, so it is an owner\n")
    cat("decision, not a mechanical follow-on from #79. Unchanged by this script.\n")
  } else {
    cat("Within 25% of shipped; no action indicated.\n")
  }
}

# How much would a re-derived magnitude actually move a projection?
cat("\n=== blast radius if the magnitude were adopted ===\n")
clamp_mult <- function(slope, opp, avg)
  pmin(pmax(1 + slope * (opp - avg), OPP_DEF_MU_CLAMP[1]), OPP_DEF_MU_CLAMP[2])
cmp <- team_def %>%
  mutate(mult_shipped  = clamp_mult(shipped,  def_rapm, league_avg),
         mult_measured = clamp_mult(measured, def_rapm, league_avg),
         pct_change    = 100 * (mult_measured / mult_shipped - 1)) %>%
  arrange(desc(abs(pct_change)))
print(as.data.frame(cmp %>% select(team_name, mult_shipped, mult_measured, pct_change)),
      row.names = FALSE, digits = 4)
cat(sprintf("\nlargest single-team swing: %+0.2f%% on a projection\n",
            cmp$pct_change[1]))
cat(sprintf("clamp binds under the measured magnitude for %d of %d teams\n",
            sum(cmp$mult_measured %in% OPP_DEF_MU_CLAMP), nrow(cmp)))
cat("\nNothing was written.\n")
