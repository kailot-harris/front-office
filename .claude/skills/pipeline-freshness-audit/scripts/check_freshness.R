# Pipeline Freshness Audit
#
# Mechanical half of the pipeline-freshness-audit skill. Checks that every stage's declared
# output cache in run_full_pipeline.R actually advanced its mtime past a given run-start
# timestamp -- the check that would have caught the silent no-op stages (sys.nframe() == 0 guard
# bug) immediately instead of relying on someone noticing an anomalously fast stage. Ported from
# the WNBA Analytics repo, which hit exactly this bug across four of its pipeline stages.
#
# Usage: Rscript.exe check_freshness.R "2026-09-16 16:00:00"

PROJECT_ROOT <- "C:/Users/kailo/kayceeslices/NFL Analytics"
setwd(PROJECT_ROOT)
source("config.R")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Usage: Rscript.exe check_freshness.R \"YYYY-MM-DD HH:MM:SS\"")
}
run_start <- as.POSIXct(args[1], tz = Sys.timezone())
if (is.na(run_start)) stop("Could not parse run-start timestamp: ", args[1])

# TODO(NFL pipeline DAG): this manifest is a PLACEHOLDER. The WNBA Analytics repo's version of
# this script hardcoded its real stage -> output-cache manifest here, mirroring the `output = `
# arguments in that repo's run_full_pipeline.R. This repo does not have a run_full_pipeline.R yet
# (it's Phase 1+ work) so there is no real DAG to mirror -- do NOT fabricate NFL stage/script names
# to fill this in. Once run_full_pipeline.R exists here, populate this list with one entry per
# stage using the same `list(stage = "<script>", outputs = <path(s)>)` shape as below, and update
# the "Stage -> output manifest" table in this skill's SKILL.md to match.
manifest <- list(
  # list(stage = "PLACEHOLDER_STAGE_SCRIPT.R", outputs = "cache/PLACEHOLDER_OUTPUT.rds")
)

if (length(manifest) == 0) {
  stop(paste(
    "check_freshness.R: no stage manifest populated yet -- this repo's run_full_pipeline.R DAG",
    "does not exist yet (Phase 1+ work). Populate the `manifest` list in this script (and the",
    "matching table in SKILL.md) once the real pipeline stages/outputs are known, then rerun."
  ))
}

cat(sprintf("Freshness audit: run start = %s\n\n", format(run_start)))

n_fresh <- 0L
n_stale <- 0L
n_missing <- 0L

for (m in manifest) {
  for (path in m$outputs) {
    if (!file.exists(path)) {
      cat(sprintf("[MISSING] %-28s %s\n", m$stage, path))
      n_missing <- n_missing + 1L
      next
    }
    mt <- file.info(path)$mtime
    if (mt >= run_start) {
      cat(sprintf("[FRESH]   %-28s %s (mtime %s)\n", m$stage, path, format(mt)))
      n_fresh <- n_fresh + 1L
    } else {
      cat(sprintf("[STALE]   %-28s %s (mtime %s, before run start)\n", m$stage, path, format(mt)))
      n_stale <- n_stale + 1L
    }
  }
}

cat(sprintf("\n%d fresh, %d stale, %d missing.\n", n_fresh, n_stale, n_missing))
if (n_stale > 0 || n_missing > 0) {
  cat(paste(
    "\nVERDICT: one or more stages did not demonstrably regenerate their output during this run.",
    "Do not trust downstream numbers from a stale/missing stage until investigated -- check",
    "whether the stage legitimately had nothing new to do (e.g. incremental ingestion) versus",
    "silently failing to execute (e.g. an invocation-guard bug).\n"
  ))
} else {
  cat("\nVERDICT: all declared stage outputs advanced during this run.\n")
}
