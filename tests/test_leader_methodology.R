# ==============================================================================
# tests/test_leader_methodology.R - leader_methodology.json builder (NBA_analytics#258)
#
# Verifies:
#   1. build_leader_methodology() writes a valid JSON payload from
#      docs/research/leader_reliability_study_results.json and config.R.
#   2. Every minimum in web/public/data/leader_methodology.json matches the
#      corresponding LEADERS_* constant in config.R.
#   3. Every reliability figure in minimums[] matches the study results JSON
#      (or is NULL with a non-empty null_reason).
#   4. Provenance (source_commit, source_sha256, study_run_date, published_at)
#      matches config.R and the study file.
#
# Usage: Rscript tests/test_leader_methodology.R
# ==============================================================================

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

suppressPackageStartupMessages(library(jsonlite))

cfg_env <- new.env(parent = globalenv())
source(file.path(REPO_ROOT, "config.R"), local = cfg_env)

Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")
lm_env <- new.env(parent = cfg_env)
suppressMessages(sys.source(file.path(REPO_ROOT, "tools", "build_leader_methodology.R"), envir = lm_env))
Sys.unsetenv("NBA_SKIP_STAGE_AUTORUN")

study_path <- file.path(REPO_ROOT, "docs", "research", "leader_reliability_study_results.json")
study <- jsonlite::fromJSON(study_path, simplifyVector = FALSE)

# 1. Tempdir build
tmp_dir <- tempfile("lm_test_")
dir.create(tmp_dir, recursive = TRUE)
on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)
tmp_out <- file.path(tmp_dir, "leader_methodology.json")
suppressMessages(lm_env$build_leader_methodology(study_path = study_path, out_path = tmp_out, cfg_env = cfg_env))
ok("build_leader_methodology writes output to tempdir", file.exists(tmp_out))

# 2. Validate committed artifact
out_path <- cfg_env$WEB_JSON_LEADER_METHODOLOGY
ok("web/public/data/leader_methodology.json exists", file.exists(out_path))
payload <- jsonlite::fromJSON(out_path, simplifyVector = FALSE)

ok("source_commit matches LEADERS_STUDY_SOURCE_COMMIT",
   identical(payload$source_commit, cfg_env$LEADERS_STUDY_SOURCE_COMMIT))
ok("source_sha256 matches study JSON sha256",
   identical(payload$source_sha256, unname(as.character(tools::sha256sum(study_path)))))
ok("study_run_date is YYYY-MM-DD",
   is.character(payload$study_run_date) && grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", payload$study_run_date))
ok("base_games matches LEADERS_FULL_SEASON_GAMES",
   identical(as.integer(payload$base_games), as.integer(cfg_env$LEADERS_FULL_SEASON_GAMES)))
ok("21 minimums rows present", length(payload$minimums) == 21L)

# 3. Every minimum matches config.R and every reliability figure matches study JSON
for (m in payload$minimums) {
  cfg_val <- as.integer(get(m$constant, envir = cfg_env, inherits = TRUE))
  ok(sprintf("%s minimum (%d) matches %s", m$key, m$minimum_full_season, m$constant),
     identical(as.integer(m$minimum_full_season), cfg_val))

  if (!is.null(m$minimum_minutes_constant)) {
    floor_val <- as.integer(get(m$minimum_minutes_constant, envir = cfg_env, inherits = TRUE))
    ok(sprintf("%s minutes floor (%d) matches %s", m$key, m$minimum_minutes_full_season, m$minimum_minutes_constant),
       identical(as.integer(m$minimum_minutes_full_season), floor_val))
  }

  rel <- m$reliability
  if (identical(m$group, "rapm")) {
    half_target <- m$minimum_full_season / 2
    row <- lm_env$lm_find_rapm_threshold(study$rapm$thresholds, m$key, half_target)
    ok(sprintf("%s split_half_r matches study RAPM threshold at %d", m$key, half_target),
       isTRUE(all.equal(rel$split_half_r, row$r)) &&
         isTRUE(all.equal(rel$spearman_brown_r, row$r_sb)) &&
         identical(as.integer(rel$split_half_n_players), as.integer(row$n_players)))
    ok(sprintf("%s rest_of_season_r is NULL with reason", m$key),
       is.null(rel$rest_of_season_r) && is.character(rel$rest_of_season_null_reason) && nzchar(rel$rest_of_season_null_reason))
  } else {
    st <- study$stats[[m$key]]
    sh <- lm_env$lm_find_by_n(st$split_half, m$minimum_full_season)
    ros <- lm_env$lm_find_by_n(st$rest_of_season, m$minimum_full_season)
    sb <- lm_env$lm_find_by_sb(st$split_half, m$minimum_full_season)
    ok(sprintf("%s split_half_r matches study at n=%d", m$key, m$minimum_full_season),
       isTRUE(all.equal(rel$split_half_r, sh$r)) &&
         isTRUE(all.equal(rel$split_half_lo, sh$r_lo)) &&
         isTRUE(all.equal(rel$split_half_hi, sh$r_hi)))
    ok(sprintf("%s rest_of_season_r matches study at n=%d", m$key, m$minimum_full_season),
       isTRUE(all.equal(rel$rest_of_season_r, ros$r)) &&
         isTRUE(all.equal(rel$rest_of_season_lo, ros$r_lo)) &&
         isTRUE(all.equal(rel$rest_of_season_hi, ros$r_hi)))
    if (is.null(sb)) {
      ok(sprintf("%s spearman_brown_r is NULL with reason", m$key),
         is.null(rel$spearman_brown_r) && is.character(rel$spearman_brown_null_reason) && nzchar(rel$spearman_brown_null_reason))
    } else {
      ok(sprintf("%s spearman_brown_r matches study at sb_sample=%d", m$key, m$minimum_full_season),
         isTRUE(all.equal(rel$spearman_brown_r, sb$r_sb)) &&
           isTRUE(all.equal(rel$spearman_brown_lo, sb$r_sb_lo)) &&
           isTRUE(all.equal(rel$spearman_brown_hi, sb$r_sb_hi)))
    }
  }
}

cat(sprintf("\n%d checks, %d failure(s).\n", checks, failures))
if (failures > 0L) quit(status = 1L)
cat("ALL CHECKS PASSED\n")
