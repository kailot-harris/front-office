# ==============================================================================
# NFL Analytics - Web Artifact Publish Gate  (GitHub issue #38, Phase 2)
# Path: <repo root>/tools/publish_web.R
#
# WHY THIS EXISTS
# ---------------
# run_full_pipeline.R's run_stage() deliberately swallows stage failures and the
# pipeline still exits 0. The real 2026-10-23 05:15 run exited 0 while logging
#   [WARN] Stale stage output (possible silent no-op, C-2): .../betting_ledger.rds
# and falling back to a SYNTHETIC_FALLBACK risk state. "Pipeline exited 0" is
# therefore NOT a safe precondition for deploying. This gate asserts on the
# ARTIFACTS, never on an exit code.
#
# Default mode is a DRY RUN: every assertion runs, a report is printed naming
# exactly what would be published, and nothing is committed or pushed. Any failed
# assertion => publish nothing, exit non-zero, leave yesterday's correct site up
# rather than a half-updated one.
#
# THE FIVE ASSERTIONS
#   A  mtime freshness - every entry of config.R's WEB_DATA_FILES has an mtime
#      later than the run start. The nine filenames are NEVER re-typed here; they
#      are read from config.R, per CLAUDE.md's single-source-of-truth convention.
#   B  week agreement  - active_week is INDEPENDENTLY recomputed from
#      CACHE_SCHEDULES (lowest CURRENT_SEASON week whose max(gameday) >=
#      Sys.Date(), else max(week) - the same rule as
#      export_web_datasets.R:443-456) and compared to the active_week the
#      exporter actually published in matchups_current_week.json. Recomputing
#      rather than importing the exporter's variable is the whole point: this is a
#      cross-check, not an echo.
#   C  non-empty diff  - `git status --porcelain` must show real pending changes
#      under WEB_DATA_DIR / WEB_ANIM_DIR before any commit is attempted. Found
#      during the issue-#38 Phase 0 audit: web/public/data was CLEAN against HEAD
#      with 2026-10-19 mtimes despite a "successful" run, so a publish without
#      this assertion reports success while pushing nothing.
#   E  publish branch  - HEAD must be on the branch the aggregator's
#      sync-sports.yml actually subtree-pulls (main). Added after the gate's
#      own silent-no-op was found on 2026-10-26: the commit+push below pushes
#      `origin HEAD`, so running this from a feature branch committed the data
#      to that branch, pushed it, and returned published = TRUE while
#      sync-sports.yml went on pulling `main` and the site never changed. That
#      is precisely the failure class this file exists to prevent, reproduced
#      one layer up in the gate itself. Fatal, and deliberately checked BEFORE
#      anything is committed.
#   D  log scan        - surfaces every [WARN] line attributable to
#      export_web_datasets.R in the run window. NOT redundant with A: the
#      exporter's verbatim-republish fallbacks (export_web_datasets.R:77, :85,
#      :1030, :1036, :1135) rewrite a file's existing bytes, which ADVANCES the
#      mtime. An mtime check is structurally incapable of catching a stale
#      salary_cap_profiles.json or value_bets.json; the log_warn() is the only
#      staleness signal for those. See config.R:676-711.
#
# ONE DEPLOY PATH (2026-10-26)
# -----------------------------
# This script used to finish by subtree-pulling into a local
# front-office-aggregator checkout and pushing front-office main itself. The
# aggregator's own .github/workflows/sync-sports.yml does the same thing in CI,
# so both mechanisms pushed the same branch and whichever ran second hit a
# non-fast-forward or an avoidable merge. The CI one is now the only one: it
# needs no workstation awake, and its comments encode three hard-won findings
# (persist-credentials: false, the explicit `gh workflow run` dispatch because a
# GITHUB_TOKEN push does not trigger another workflow, and the API preflight
# because a fine-grained PAT returns 404 rather than 403).
#
# What remains here is the part that was never duplicated: the assertions, and
# the commit + push of NFL_analytics itself. Pushing NFL_analytics triggers no
# deploy on its own -- it makes the artifacts available for sync-sports.yml to
# pull on its next run or dispatch. This script no longer deploys, and no longer
# pretends to.
#
# PATH / WORKTREE NOTE (tracked as issue #43, deliberately NOT fixed here)
# -----------------------------------------------------------------------
# config.R:22 hardcodes PROJECT_DIR as an absolute path to the main checkout, so
# every CACHE_* constant resolves there no matter which checkout is running. The
# WEB_* constants, by contrast, are RELATIVE (config.R: file.path("web","public"))
# and so resolve against the working directory. This script does not paper over
# that split: it sources config.R for the names (as the conventions require) and
# resolves anything git-related at RUNTIME via `git rev-parse --show-toplevel`,
# so it is correct when it eventually runs from the main checkout and merely
# reports honestly when run from a worktree. No second absolute path is hardcoded.
#
# ------------------------------------------------------------------------------
# ## Failure reproductions
# ------------------------------------------------------------------------------
# Each assertion's FAILURE path is reproducible by hand. None of these mutate the
# real checkout except where noted, and each notes its restore step.
#
# A (mtime freshness) FAILS:
#     Rscript -e "source('tools/publish_web.R'); print(publish_web(dry_run = TRUE, run_start = Sys.time())$assertions_failed)"
#   Passing run_start = now makes every published file older than the run start by
#   construction, so A fails for all nine and the exit status is non-zero.
#   Nothing is written; no restore needed. (Equivalent no-argument form: push one
#   file's mtime backwards with Sys.setFileTime() and re-run.)
#
# B (week agreement) FAILS:
#     cp web/public/data/matchups_current_week.json /tmp/mcw.bak
#     Rscript -e "p <- 'web/public/data/matchups_current_week.json'; l <- readLines(p, warn=FALSE); writeLines(sub('\"active_week\": *[0-9]+', '\"active_week\": 99', l), p)"
#     Rscript -e "source('tools/publish_web.R'); publish_web(dry_run = TRUE)"
#   Verified live 2026-10-23: reports
#     [FAIL] B. week agreement ... - computed=7 published=99
#   (and C now PASSES, because the edit made web/ dirty - a neat demonstration
#   that the two assertions are independent).
#     Restore:  cp /tmp/mcw.bak web/public/data/matchups_current_week.json
#   Zero-mutation variant of the same comparison, exercising the recomputation
#   against a deliberately wrong published value:
#     Rscript -e "source('tools/publish_web.R'); stopifnot(.compute_active_week_from_schedules() != 99L)"
#
# E (publish branch) FAILS:
#     git switch -c scratch/anything
#     Rscript -e "source('tools/publish_web.R'); publish_web(dry_run = TRUE)"
#   Reports [FAIL] E ... HEAD=scratch/anything expected=main and blocks. Before
#   E existed this combination published "successfully" to the scratch branch and
#   left the site untouched.
#     Restore:  git switch main && git branch -d scratch/anything
#   Zero-mutation variant, asserting against a branch that is not the real one:
#     Rscript -e "source('tools/publish_web.R'); print(publish_web(dry_run = TRUE, publish_branch = 'no-such-branch')$assertions_failed)"
#
# C (non-empty diff) FAILS:
#   This is the DEFAULT state of a checkout whose web/ tree is already committed -
#   no setup required at all. Observed live on the main checkout on 2026-10-23:
#   `git status --porcelain -- web/public/data web/public/animations` printed
#   nothing while all nine files carried fresh 18:35 mtimes, i.e. exactly the
#   issue-#38 Phase 0 defect. Run
#     Rscript -e "source('tools/publish_web.R'); publish_web(dry_run = TRUE)"
#   on any clean tree and C fails with "CLEAN against HEAD - nothing to publish".
#
# D (log scan) is a REPORTING assertion by default (warnings are surfaced, not
#   fatal), because coaching_profiles.json emits a benign republish warning on
#   every single run by design (config.R:676-711) and making that fatal would make
#   the gate permanently red. Its FAILING form is opt-in and reproducible:
#     Rscript -e "source('tools/publish_web.R'); publish_web(dry_run = TRUE, fail_on_exporter_warnings = TRUE)"
#   Against the real log this fails on the live "republished coaching_profiles.json
#   VERBATIM" warning. To reproduce a warning that SHOULD always be treated as
#   fatal (a genuinely stale published dataset), move cache/latest_value_bets.rds
#   aside so the exporter's republish branch at export_web_datasets.R:1135 fires,
#   re-run the exporter, and D then surfaces "value_bets.json NOT refreshed ...
#   may now be stale".
#     Restore:  move cache/latest_value_bets.rds back.
#   Zero-setup inspection of D's matcher on synthetic text:
#     Rscript -e "source('tools/publish_web.R'); print(.scan_exporter_warnings(c('[2026-10-23 05:16:00] [WARN] [R] export_web_datasets: fabricated stale warning'), as.POSIXct('2026-10-23 05:00:00')))"
# ==============================================================================

# ------------------------------------------------------------------------------
# Bootstrap: setwd() to this script's project root, then source siblings by bare
# filename (repo convention - the repo is deliberately flat).
# ------------------------------------------------------------------------------
.publish_web_project_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  if (length(f) == 1 && nzchar(f) && file.exists(f)) {
    cand <- normalizePath(dirname(dirname(f)), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(cand, "config.R"))) return(cand)
  }
  # source()d (no --file=): walk up from the working directory looking for config.R.
  d <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  for (i in 1:6) {
    if (file.exists(file.path(d, "config.R"))) return(d)
    p <- dirname(d)
    if (identical(p, d)) break
    d <- p
  }
  stop("publish_web.R: cannot locate the project root (no config.R found).")
}

local({
  root <- .publish_web_project_root()
  if (!identical(normalizePath(getwd(), winslash = "/", mustWork = FALSE), root)) setwd(root)
})

suppressPackageStartupMessages({
  library(jsonlite)
})
source("config.R")
source("logging_utils.R")

# ------------------------------------------------------------------------------
# Small helpers
# ------------------------------------------------------------------------------
.pw_git <- function(repo, args) {
  out <- suppressWarnings(system2("git", c("-C", shQuote(repo), args),
                                  stdout = TRUE, stderr = TRUE))
  status <- attr(out, "status")
  list(ok = is.null(status) || identical(as.integer(status), 0L),
       out = if (is.null(out)) character(0) else as.character(out))
}

.pw_repo_root <- function(start = getwd()) {
  r <- .pw_git(start, c("rev-parse", "--show-toplevel"))
  if (!r$ok || !length(r$out)) return(NA_character_)
  normalizePath(r$out[1], winslash = "/", mustWork = FALSE)
}

# ------------------------------------------------------------------------------
# Run-start discovery. The gate needs the START of the pipeline run whose output
# it is publishing. Parsed from LOG_FILE's own "Pipeline run started." marker
# (logging_utils.R's format: "[YYYY-MM-DD HH:MM:SS] [LEVEL] [script] msg"), so
# there is nothing to pass in on a scheduled unattended run. Overridable for
# tests and for republishing a specific historical run.
# ------------------------------------------------------------------------------
.pw_log_timestamp <- function(lines) {
  ts <- sub("^\\[([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})\\].*$", "\\1", lines)
  ts[!grepl("^[0-9]{4}-", ts)] <- NA_character_
  as.POSIXct(ts, format = "%Y-%m-%d %H:%M:%S", tz = "")
}

.pw_detect_run_start <- function(log_lines) {
  hits <- grep("Pipeline run started", log_lines, fixed = TRUE)
  if (!length(hits)) return(NA)
  tail(.pw_log_timestamp(log_lines[hits]), 1)
}

# ------------------------------------------------------------------------------
# ASSERTION A - mtime freshness
# ------------------------------------------------------------------------------
.assert_mtime_freshness <- function(run_start) {
  files <- WEB_DATA_FILES          # <- the nine names come from config.R ONLY
  info  <- file.info(files)
  stale <- character(0)
  rows  <- vector("list", length(files))
  for (i in seq_along(files)) {
    f  <- files[i]
    mt <- info$mtime[i]
    present <- !is.na(info$size[i])
    fresh <- present && !is.na(mt) && !is.na(run_start) && mt > run_start
    rows[[i]] <- sprintf("    %-9s %-34s mtime=%s", if (fresh) "[FRESH]" else "[STALE]",
                         basename(f),
                         if (present && !is.na(mt)) format(mt, "%Y-%m-%d %H:%M:%S") else "<absent>")
    if (!fresh) stale <- c(stale, f)
  }
  list(id = "A", name = "mtime freshness (WEB_DATA_FILES newer than run start)",
       pass = length(stale) == 0, fatal = TRUE,
       detail = unlist(rows), stale = stale,
       summary = sprintf("%d/%d published datasets regenerated after run start %s",
                         length(files) - length(stale), length(files),
                         if (is.na(run_start)) "<unknown>" else format(run_start, "%Y-%m-%d %H:%M:%S")))
}

# ------------------------------------------------------------------------------
# ASSERTION B - week agreement.
# Independent re-derivation of active_week from CACHE_SCHEDULES, using the same
# calendar rule as export_web_datasets.R:443-456: the lowest CURRENT_SEASON week
# whose LAST scheduled gameday has not yet passed (max(gameday) >= today),
# falling back to max(week) once the regular season is over. The superseded
# min(week)-of-unplayed-games rule pinned the site to a finished week whenever a
# single game was postponed or left ungraded (export_web_datasets.R:420-442).
# ------------------------------------------------------------------------------
.compute_active_week_from_schedules <- function(schedules_path = CACHE_SCHEDULES) {
  if (!file.exists(schedules_path)) return(NA_integer_)
  sched <- tryCatch(readRDS(schedules_path), error = function(e) NULL)
  if (is.null(sched) || !all(c("season", "week", "gameday") %in% names(sched))) return(NA_integer_)
  s <- sched[!is.na(sched$season) & as.integer(sched$season) == CURRENT_SEASON, ]
  wk <- as.integer(s$week)
  gd <- as.Date(as.character(s$gameday))
  ok <- !is.na(wk) & !is.na(gd)
  if (!any(ok)) return(NA_integer_)
  wk <- wk[ok]; gd <- gd[ok]
  last_gameday <- as.Date(tapply(gd, wk, max), origin = "1970-01-01")
  weeks <- as.integer(names(last_gameday))
  not_finished <- weeks[last_gameday >= Sys.Date()]
  as.integer(if (length(not_finished) > 0) min(not_finished) else max(weeks))
}

.assert_week_agreement <- function() {
  computed  <- .compute_active_week_from_schedules()
  published <- NA_integer_
  note <- NULL
  if (!file.exists(WEB_JSON_MATCHUPS_CURRENT_WEEK)) {
    note <- sprintf("%s is absent", WEB_JSON_MATCHUPS_CURRENT_WEEK)
  } else {
    j <- tryCatch(jsonlite::fromJSON(WEB_JSON_MATCHUPS_CURRENT_WEEK, simplifyVector = TRUE),
                  error = function(e) { note <<- paste("unparseable JSON:", conditionMessage(e)); NULL })
    if (!is.null(j) && !is.null(j$active_week)) published <- as.integer(j$active_week[1])
  }
  pass <- !is.na(computed) && !is.na(published) && identical(computed, published)
  list(id = "B", name = "week agreement (CACHE_SCHEDULES vs published active_week)",
       pass = pass, fatal = TRUE,
       computed = computed, published = published,
       detail = c(sprintf("    recomputed from %-28s : %s", basename(CACHE_SCHEDULES),
                          ifelse(is.na(computed), "<NA>", computed)),
                  sprintf("    published in   %-28s : %s", basename(WEB_JSON_MATCHUPS_CURRENT_WEEK),
                          ifelse(is.na(published), "<NA>", published)),
                  if (!is.null(note)) paste("    note:", note)),
       summary = sprintf("computed=%s published=%s",
                         ifelse(is.na(computed), "<NA>", computed),
                         ifelse(is.na(published), "<NA>", published)))
}

# ------------------------------------------------------------------------------
# ASSERTION C - non-empty diff under the published trees.
# Resolved against the RUNTIME git root (see the issue-#43 note in the header),
# never a hardcoded path.
# ------------------------------------------------------------------------------
.assert_nonempty_diff <- function(repo_root) {
  if (is.na(repo_root)) {
    return(list(id = "C", name = "non-empty diff under web/public/{data,animations}",
                pass = FALSE, fatal = TRUE, changed = character(0),
                detail = "    could not resolve a git repository for the working directory",
                summary = "no git repo"))
  }
  r <- .pw_git(repo_root, c("status", "--porcelain", "--", WEB_DATA_DIR, WEB_ANIM_DIR))
  changed <- if (r$ok) r$out[nzchar(r$out)] else character(0)
  list(id = "C", name = "non-empty diff under web/public/{data,animations}",
       pass = length(changed) > 0, fatal = TRUE, changed = changed,
       detail = if (length(changed)) paste0("    ", changed)
                else sprintf("    CLEAN against HEAD - nothing to publish (repo: %s)", repo_root),
       summary = sprintf("%d pending change(s) under %s / %s",
                         length(changed), WEB_DATA_DIR, WEB_ANIM_DIR))
}

# ------------------------------------------------------------------------------
# ASSERTION D - exporter [WARN] scan for the run window.
# Matched on the MESSAGE prefix "export_web_datasets" rather than the log's
# script field: log_warn() calls made from inside the exporter's sourced function
# body record the script as "[R]", not "[export_web_datasets.R]", so a
# script-field match would silently find nothing. Verified against the real
# logs/nfl_pipeline.log.
# ------------------------------------------------------------------------------
.scan_exporter_warnings <- function(log_lines, run_start) {
  idx <- grep("\\[WARN\\].*export_web_datasets", log_lines)
  if (!length(idx)) return(character(0))
  hits <- log_lines[idx]
  if (!is.na(run_start)) {
    ts <- .pw_log_timestamp(hits)
    hits <- hits[!is.na(ts) & ts >= run_start]
  }
  as.character(hits)
}

.assert_log_scan <- function(log_lines, run_start, fail_on_exporter_warnings) {
  warns <- .scan_exporter_warnings(log_lines, run_start)
  list(id = "D", name = "exporter [WARN] scan of the pipeline log",
       pass = !(fail_on_exporter_warnings && length(warns) > 0),
       fatal = fail_on_exporter_warnings,
       warnings = warns,
       detail = if (length(warns)) paste0("    ", warns)
                else "    no export_web_datasets [WARN] lines in the run window",
       summary = sprintf("%d exporter warning(s) surfaced%s", length(warns),
                         if (fail_on_exporter_warnings) " (fatal)" else " (reported, non-fatal)"))
}

# ------------------------------------------------------------------------------
# ASSERTION E - publish branch.
# `.pw_do_publish` pushes `origin HEAD`, while the aggregator's sync-sports.yml
# subtree-pulls a fixed branch. If those disagree the push lands on a ref CI
# never reads: the commit succeeds, the push succeeds, published = TRUE is
# returned, and the site does not move. The branch name is a parameter rather
# than a constant so the mismatch can be exercised without switching branches,
# but its default must stay in step with the ref sync-sports.yml pulls.
# ------------------------------------------------------------------------------
.pw_current_branch <- function(repo_root) {
  if (is.na(repo_root)) return(NA_character_)
  r <- .pw_git(repo_root, c("rev-parse", "--abbrev-ref", "HEAD"))
  if (!r$ok || !length(r$out)) return(NA_character_)
  b <- trimws(r$out[1])
  if (!nzchar(b) || identical(b, "HEAD")) NA_character_ else b
}

.assert_publish_branch <- function(repo_root, publish_branch) {
  branch <- .pw_current_branch(repo_root)
  pass <- !is.na(branch) && identical(branch, publish_branch)
  list(id = "E", name = "publish branch (HEAD is the ref the aggregator pulls)",
       pass = pass, fatal = TRUE, branch = branch,
       detail = c(sprintf("    HEAD is on                 : %s",
                          ifelse(is.na(branch), "<detached HEAD or no repo>", branch)),
                  sprintf("    sync-sports.yml pulls      : %s", publish_branch),
                  if (!pass)
                    "    note: `push origin HEAD` would land on a ref CI never reads - the push would succeed and the site would not change."),
       summary = sprintf("HEAD=%s expected=%s",
                         ifelse(is.na(branch), "<NA>", branch), publish_branch))
}

# ------------------------------------------------------------------------------
# Commit / push sequence. ONLY reached when dry_run = FALSE and every fatal
# assertion passed. Commits the two published trees and pushes NFL_analytics --
# nothing more. The deploy belongs to the aggregator's sync-sports.yml (see "ONE
# DEPLOY PATH" in the header); this function deliberately does not push
# front-office, so there is exactly one mechanism that can.
# Assertion E guarantees HEAD is the branch sync-sports.yml pulls, so `push
# origin HEAD` reaches the ref that CI will actually read.
# ------------------------------------------------------------------------------
.pw_do_publish <- function(repo_root, commit_message) {
  steps <- list()
  record <- function(label, res) {
    steps[[length(steps) + 1L]] <<- list(label = label, ok = res$ok, out = res$out)
    if (!res$ok) stop(sprintf("publish_web: step failed: %s\n%s", label,
                              paste(res$out, collapse = "\n")))
    invisible(TRUE)
  }
  record("git add web/public/{data,animations}",
         .pw_git(repo_root, c("add", "--", WEB_DATA_DIR, WEB_ANIM_DIR)))
  record("git commit (NFL_analytics)",
         .pw_git(repo_root, c("commit", "-m", shQuote(commit_message))))
  record("git push origin HEAD (NFL_analytics)",
         .pw_git(repo_root, c("push", "origin", "HEAD")))
  steps
}

# ------------------------------------------------------------------------------
# publish_web() - the explicitly-callable entry point.
#
# Deliberately NOT guarded by a `sys.nframe() == 0`-style top-level-only check:
# that is a documented silent-no-op failure mode in this repo (CLAUDE.md), because
# source()ing from an orchestrator changes frame depth, so the guard no-ops while
# still reporting success. Callers invoke this function explicitly; the CLI
# wrapper at the bottom of this file keys off commandArgs(), not frame depth.
# ------------------------------------------------------------------------------
publish_web <- function(dry_run = TRUE,
                        run_start = NULL,
                        publish_branch = "main",
                        fail_on_exporter_warnings = FALSE,
                        commit_message = NULL) {

  repo_root <- .pw_repo_root()
  log_lines <- if (file.exists(LOG_FILE)) readLines(LOG_FILE, warn = FALSE) else character(0)
  if (is.null(run_start)) run_start <- .pw_detect_run_start(log_lines)
  if (is.null(commit_message)) {
    commit_message <- sprintf("Publish NFL web artifacts from the %s pipeline run",
                              if (is.na(run_start)) format(Sys.Date()) else format(run_start, "%Y-%m-%d %H:%M"))
  }

  checks <- list(
    .assert_mtime_freshness(run_start),
    .assert_week_agreement(),
    .assert_nonempty_diff(repo_root),
    .assert_publish_branch(repo_root, publish_branch),
    .assert_log_scan(log_lines, run_start, fail_on_exporter_warnings)
  )

  passed  <- vapply(checks, function(ch) isTRUE(ch$pass), logical(1))
  fatal   <- vapply(checks, function(ch) isTRUE(ch$fatal), logical(1))
  blocked <- any(!passed & fatal)

  # ---- report ----------------------------------------------------------------
  cat("\n================================================================\n")
  cat(sprintf("NFL web publish gate  [%s]\n",
              if (dry_run) "DRY RUN - nothing will be published" else "LIVE PUBLISH"))
  cat("================================================================\n")
  cat(sprintf("  repo root        : %s\n", ifelse(is.na(repo_root), "<not a git repo>", repo_root)))
  cat(sprintf("  publish branch   : %s\n", publish_branch))
  cat(sprintf("  pipeline log     : %s (%d lines)\n", LOG_FILE, length(log_lines)))
  cat(sprintf("  run start        : %s\n",
              ifelse(is.na(run_start), "<undetected>", format(run_start, "%Y-%m-%d %H:%M:%S"))))
  cat(sprintf("  schedules cache  : %s\n", CACHE_SCHEDULES))
  cat("\n-- Assertions --------------------------------------------------\n")
  for (ch in checks) {
    cat(sprintf("  [%s] %s. %s - %s\n",
                if (ch$pass) "PASS" else if (ch$fatal) "FAIL" else "WARN",
                ch$id, ch$name, ch$summary))
    cat(paste0(ch$detail, collapse = "\n"), "\n", sep = "")
  }

  cat("\n-- Would publish -----------------------------------------------\n")
  cat(sprintf("  %d dataset(s) from %s:\n", length(WEB_DATA_FILES), WEB_DATA_DIR))
  for (f in WEB_DATA_FILES) cat(sprintf("    - %s\n", basename(f)))
  anim <- if (dir.exists(WEB_ANIM_DIR)) list.files(WEB_ANIM_DIR) else character(0)
  cat(sprintf("  %d visual-media file(s) from %s\n", length(anim), WEB_ANIM_DIR))
  cat(sprintf("  commit message   : %s\n", commit_message))
  cat(sprintf("  push sequence    : commit -> push NFL_analytics %s (deploy belongs to the aggregator's sync-sports.yml)\n",
              publish_branch))

  cat("\n-- Verdict -----------------------------------------------------\n")
  if (blocked) {
    cat("  BLOCKED - at least one fatal assertion failed. PUBLISHING NOTHING.\n")
    cat("  Yesterday's correct site stays up rather than a half-updated one.\n")
    for (ch in checks[!passed & fatal]) {
      log_warn(sprintf("publish_web: assertion %s FAILED (%s) - publishing nothing. %s",
                       ch$id, ch$name, ch$summary))
    }
  } else if (dry_run) {
    cat("  ALL ASSERTIONS PASSED - a live run would publish the artifacts listed above.\n")
  } else {
    cat("  ALL ASSERTIONS PASSED - proceeding to commit and push.\n")
  }
  cat("================================================================\n\n")

  result <- list(
    dry_run = dry_run, blocked = blocked, run_start = run_start,
    repo_root = repo_root, publish_branch = publish_branch,
    assertions_passed = as.character(vapply(checks[passed], function(ch) ch$id, character(1))),
    assertions_failed = as.character(vapply(checks[!passed], function(ch) ch$id, character(1))),
    active_week_computed = checks[[2]]$computed,
    active_week_published = checks[[2]]$published,
    publish_branch_actual = checks[[4]]$branch,
    exporter_warnings = checks[[5]]$warnings,
    pending_changes = checks[[3]]$changed,
    checks = checks, published = FALSE, steps = list()
  )

  if (blocked || dry_run) return(invisible(result))

  result$steps <- .pw_do_publish(repo_root, commit_message)
  result$published <- TRUE
  log_info(sprintf("publish_web: web artifacts committed and pushed to NFL_analytics %s. The site changes when the aggregator's sync-sports.yml next pulls; this script no longer deploys.",
                   publish_branch))
  invisible(result)
}

# ------------------------------------------------------------------------------
# CLI wrapper. Keyed off commandArgs() - i.e. "was I invoked as
# `Rscript tools/publish_web.R`" - NOT off sys.nframe(). source()ing this file
# from another script or from `Rscript -e` defines the function and runs nothing,
# which is what makes the function callable without surprise side effects.
#   Rscript tools/publish_web.R                  # dry run (default)
#   Rscript tools/publish_web.R --publish        # live publish
#   Rscript tools/publish_web.R --strict-warnings
# Exit status: 0 only when nothing fatal failed; 1 on any fatal failure, so a
# scheduled caller can branch on it.
# ------------------------------------------------------------------------------
local({
  argv <- commandArgs(trailingOnly = FALSE)
  files <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (!any(grepl("publish_web\\.R$", files))) return(invisible(NULL))
  opts <- commandArgs(trailingOnly = TRUE)
  res <- publish_web(dry_run = !("--publish" %in% opts),
                     fail_on_exporter_warnings = "--strict-warnings" %in% opts)
  quit(status = if (isTRUE(res$blocked)) 1L else 0L)
})
