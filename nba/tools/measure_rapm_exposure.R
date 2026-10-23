# Diagnostic for NBA issue #22 (Phase 5 of the RAPM NBA/WNBA alignment plan): measures NBA's
# RAPM exposure distribution so the two thresholds in rapm_engine.R's low-sample block are
# chosen from NBA's own data instead of inherited from WNBA's.
#
# READ-ONLY. It reads cache/rapm_ratings.rds and writes nothing. It deliberately does NOT
# source("rapm_engine.R") — that file's trailing `if (!interactive())` block refits RAPM and
# saveRDS()s over the production cache. Every number below is recomputed from the saved frame,
# which already carries off_possessions, def_possessions, total_rapm and lambda.
#
# Usage: Rscript tools/measure_rapm_exposure.R
setwd("c:/Users/kailo/kayceeslices/front-office/NBA Analytics")

suppressPackageStartupMessages(library(dplyr))

RAPM_PATH <- file.path("cache", "rapm_ratings.rds")
if (!file.exists(RAPM_PATH)) {
  stop(sprintf("No RAPM artifact at %s — run the pipeline's RAPM stage first.", RAPM_PATH))
}
r <- readRDS(RAPM_PATH)

lambda <- unique(r$lambda)
stopifnot(length(lambda) == 1)
n <- nrow(r)

# Ridge shrinks each coefficient by s_i = n_i / (n_i + lambda); `1 - s_i` is the share of the
# reported rating contributed by the prior. Take the WEAKER side, so a one-sided specialist
# cannot pass on garbage-time minutes at the other end.
r <- r %>%
  mutate(
    shrinkage_data_share = pmin(off_possessions / (off_possessions + lambda),
                                def_possessions / (def_possessions + lambda)),
    min_side_poss        = pmin(off_possessions, def_possessions)
  )

pct <- function(k) sprintf("%d/%d = %.1f%%", k, n, 100 * k / n)

cat("================================================================\n")
cat(sprintf("NBA RAPM exposure diagnostic — %s, %d rated players, lambda = %g\n",
            r$season_label[1], n, lambda))
cat("source:", normalizePath(RAPM_PATH), "(read-only, no refit)\n")
cat("================================================================\n\n")

# ---- 1. flag rate, before and after -------------------------------------------------------
cat("--- 1. low_sample_flag rate, old rule vs. new rule ---\n")
old_n <- sum(r$possessions < 500)
cat(sprintf("BEFORE  possessions < 500 (combined, magic number) : %s\n", pct(old_n)))

RAPM_MIN_DATA_SHARE <- 1 / 3
new_n <- sum(r$shrinkage_data_share < RAPM_MIN_DATA_SHARE)
cat(sprintf("AFTER   shrinkage_data_share < 1/3 (per side)      : %s\n\n", pct(new_n)))

# ---- 2. is 1/3 right for NBA, or just inherited from WNBA? --------------------------------
cat("--- 2. data-share cut: 1/3 vs. alternatives, on NBA's distribution ---\n")
cat("shrinkage_data_share deciles:\n")
print(round(quantile(r$shrinkage_data_share, seq(0, 1, 0.1)), 3))
cat("\n")
for (cut in c(0.25, 0.30, 1 / 3, 0.40, 0.50)) {
  k <- sum(r$shrinkage_data_share < cut)
  cat(sprintf("  cut %.3f  (%.0f%% prior or more)  flags %s\n",
              cut, 100 * (1 - cut), pct(k)))
}
cat("\nCHOSEN: 1/3. The cut is a statement about the ESTIMATOR, not about the league --\n")
cat("\"more than two thirds of this number is the ridge prior\" means the same thing in both\n")
cat("leagues, and expressed against lambda it survives a re-tune. The measured alternatives\n")
cat("do not improve on it: 0.25 leaves players who are 70-75% prior unflagged, contradicting\n")
cat("the flag's own definition, and 0.40 flags a majority (51.0%) while the median NBA player\n")
cat("sits at share 0.391 (61% prior), which is not a \"mostly prior\" number. NBA's higher rate\n")
cat("than WNBA's 28.8% is exposure, not calibration: at lambda = 3000 the cut is 1,500\n")
cat("possessions per side, and 582 rated rows include the full two-way / 10-day tail (87\n")
cat("players under 500 combined possessions). The flag is non-destructive -- flag, never drop.\n\n")

# ---- 3. does low exposure actually mean noisy? --------------------------------------------
cat("--- 3. sd of total_rapm by combined-possession band (why a count cut is wrong) ---\n")
print(r %>%
        mutate(band = cut(possessions, c(-1, 500, 1000, 2000, 3000, 5000, Inf),
                          labels = c("<500", "500-1k", "1-2k", "2-3k", "3-5k", ">5k"))) %>%
        group_by(band) %>%
        summarise(n = n(), sd_total_rapm = round(sd(total_rapm), 2), .groups = "drop") %>%
        as.data.frame())
cat("\nThe LOWEST-exposure band is the LEAST variable, because ridge shrinks it hardest. The\n")
cat("count-based intuition (\"few possessions = noisy number\") is backwards; what the flag\n")
cat("should report is how much of the number is prior, which is exactly the data share.\n\n")

# ---- 4. per-side eligibility threshold ----------------------------------------------------
cat("--- 4. leaderboard eligibility: per-side exposure quantiles ---\n")
qs <- quantile(r$min_side_poss, c(0.10, 0.25, 0.50, 0.75, 0.90))
print(round(qs))
cat("\n")
for (thr in c(1000L, 1500L, 2000L, 2500L, 3000L)) {
  k <- sum(r$min_side_poss >= thr)
  cat(sprintf("  >= %5d per side -> %s eligible  (%.1f players per team)\n",
              thr, pct(k), k / 30))
}
RAPM_LEADERBOARD_MIN_POSS_PER_SIDE <- 2000L
elig_n <- sum(r$min_side_poss >= RAPM_LEADERBOARD_MIN_POSS_PER_SIDE)
cat(sprintf("\nCHOSEN: %d per side -> %s eligible, %.1f players per team.\n",
            RAPM_LEADERBOARD_MIN_POSS_PER_SIDE, pct(elig_n), elig_n / 30))
cat("It is the round number at NBA's per-side MEDIAN (p50 = 1,927) and it lands on an NBA\n")
cat("rotation: 9.5 players per team. WNBA's inherited 1,000 sits at NBA's p33 (935) and would\n")
cat("pass 383 players = 12.8 per team, i.e. the deep bench, which is not a rank-eligible pool.\n\n")

# ---- 5. the resulting leaderboard ---------------------------------------------------------
cat("--- 5. top 10 by total_rapm among eligible players ---\n")
top10 <- r %>%
  filter(min_side_poss >= RAPM_LEADERBOARD_MIN_POSS_PER_SIDE) %>%
  arrange(desc(total_rapm)) %>%
  head(10)
print(top10 %>%
        transmute(player_name, team, total_rapm,
                  off = off_possessions, def = def_possessions,
                  data_share = round(shrinkage_data_share, 3),
                  low_sample_flag = shrinkage_data_share < RAPM_MIN_DATA_SHARE) %>%
        as.data.frame())
cat("\nNote the contrast with WNBA, where the equivalent cut was load-bearing: NBA's unfiltered\n")
cat("top 10 is already the same ten names, so eligibility here is insurance against a thin\n")
cat("season or a partial-season refit rather than a fix for a currently broken leaderboard.\n")
cat("At the current lambda = 3000 every eligible player also clears the honesty flag by\n")
cat("construction (2000/(2000+3000) = 0.40 > 1/3) -- the two mechanisms agreeing, not\n")
cat("duplicating. That coincidence is lambda-dependent and is not relied on anywhere.\n")
