# ==============================================================================
# NBA Analytics - Web Artifact Publish Gate
# Path: <repo root>/tools/publish_web.R
#
# Ported from NFL Analytics' tools/publish_web.R (its GitHub issue #38) on
# 2026-10-26, as step 3a of the four-sport publish-cadence work, by way of the
# MLB port written the same day. Read NFL's header for the full rationale behind
# the shared assertions; this header records only what is DIFFERENT about NBA,
# because a verbatim restatement would be a second copy free to drift.
#
# WHY THIS EXISTS
# ---------------
# run_stage() swallows a stage failure and the pipeline continues, so
# "the run finished" is not a safe precondition for deploying. This gate
# asserts on the ARTIFACTS, never on an exit code.
#
# Default mode is a DRY RUN: every assertion runs, a report is printed naming
# exactly what would be published, and nothing is committed or pushed. Any
# failed fatal assertion => publish nothing, exit non-zero, leave yesterday's
# correct site up rather than a half-updated one.
#
# WHAT NBA ALREADY HAD, AND WHY THIS IS STILL WORTH ADDING
# --------------------------------------------------------
# NBA is the one sport of the four that was not flying blind. It already has
# TWO staleness defences the siblings lack:
#   * .check_stage_output() (run_full_pipeline.R:20-47) checks every declared
#     stage output's mtime against that stage's own start, per stage, as it
#     goes; and
#   * the projection publish guard (run_full_pipeline.R:200-236) reads
#     projections_models_metadata.json's embedded generated_at and
#     season_label and HARD-STOPS the run when they do not describe this run.
# That second one is the same idea as assertion F below, and NBA had it first;
# the MLB port generalised it after finding a payload that a mtime check
# called fresh and a generated_at stamp called two days old.
#
# What NBA did NOT have is anything between "the pipeline produced good
# artifacts" and "the artifacts are on the live site". schedule_daily.bat
# committed and pushed web/public/data unconditionally, on the sole condition
# that run_full_pipeline.R exited 0 -- and the guards above cover 3 of the 12
# published payloads, so a stale cba_cap_sheet.json or matchups_slates.json
# shipped without a word. This gate covers all twelve and is the thing the
# .bat now calls instead of pushing on its own.
#
# THE ASSERTIONS
#   A  mtime freshness - every entry of config.R's WEB_DATA_FILES has an mtime
#      later than the run start. The twelve filenames are NEVER re-typed here;
#      they are read from config.R, which is also where each builder now gets
#      its output path. See config.R for the deliberate non-members
#      (offseason_transactions.json is an input catalog; the shots_* tree is
#      written out of band; projections_diagnostics.json has no writer at all).
#   B  slate agreement - the season game count and active slate are
#      INDEPENDENTLY recomputed from CACHE_MATCHUPS_SCHEDULE() and compared to
#      what build_matchups_dataset.R actually published in matchups_slates.json.
#      See .compute_slate_from_schedule() for the rule and for why it is
#      reimplemented rather than imported.
#   C  non-empty diff  - `git status --porcelain` must show real pending changes
#      under WEB_DATA_DIR before any commit is attempted. Without it a publish
#      reports success while pushing nothing.
#   D  warning scan    - surfaces run_stage()'s own [WARN] and [FAIL] lines
#      from the run window. Reporting-only by default, fatal under
#      --strict-warnings. NBA's equivalent of the sibling repos' exporter-log
#      scan; because this repo logs through message() rather than a structured
#      logger, the matcher keys off .check_stage_output()'s own output format.
#   E  publish branch  - HEAD must be on the branch the aggregator's
#      sync-sports.yml actually subtree-pulls (main). The commit+push below
#      pushes `origin HEAD`, so from a feature branch the data would be
#      committed there, pushed, and reported as published while
#      sync-sports.yml went on pulling main and the site never changed. Fatal,
#      and checked BEFORE anything is committed. schedule_daily.bat's old
#      `git push origin HEAD` had exactly this hole.
#   F  payload provenance - reads the embedded `generated_at` stamp of every
#      payload that carries one and requires it to be at or after the run
#      start. This generalises run_full_pipeline.R's existing projection guard
#      from 3 payloads to however many carry a stamp, and it is the assertion
#      that catches staleness A is structurally incapable of seeing: an mtime
#      is a property of the filesystem, so any git checkout, restore, stash or
#      merge satisfies A over unchanged bytes. (That is not hypothetical -- it
#      is how MLB's two-day-stale projections survived a green run and a clean
#      tree on 2026-10-25.)
#
#   G  web contracts  - runs the web suite's `contracts` stage against the
#      UNCOMMITTED payload, so a payload whose numbers disagree with each
#      other cannot be published. Every other assertion here asks when a file
#      was written, whether its bytes changed, what the log said or whose
#      branch it is on; none reads the numbers inside. Ported from WNBA on
#      2026-10-26 -- see this assertion's own header for what prompted it.
#      Fatal, with web/tests/known-issues.json as the documented escape valve.
#
#   H  data manifest + schedule coverage (front-office#102/#191) - every
#      top-level payload is stamped in web/public/data/data_manifest.json and
#      no non-static dataset trails the schedule by more than its max_lag_days.
#      Content-dated through_date; not-game-dated payloads checked on
#      generated_at ([UNDATED]). Live runs refresh the manifest first; dry
#      runs never write it.
#
#   L  data-file lifecycle + frozen-file integrity (NBA_analytics#235) - every
#      top-level payload in web/public/data/ (excluding data_manifest.json)
#      carries a valid `lifecycle` in c("live", "season_final", "archived") in
#      data_manifest.json; any missing or unknown lifecycle fails. Any
#      `season_final` entry must also carry season, final_through_date,
#      frozen_sha256 and frozen_at, and its bytes must still match
#      frozen_sha256. In season, every file is `live`; A-H are unchanged.
#
#      KNOWN GAP, reported rather than silently tolerated: only 2 of NBA's 12
#      published payloads carry a `generated_at` at all. F names the other ten
#      in its detail lines rather than implying it has checked them. Stamping
#      every payload is a builder change, not a gate change, and is left as
#      follow-up.
#
# ONE DEPLOY PATH
# ---------------
# This file commits and pushes NBA_analytics and NOTHING ELSE. It does not
# subtree-pull and it does not push front-office. The aggregator's
# .github/workflows/sync-sports.yml is the single mechanism that moves the live
# site. Pushing NBA_analytics triggers no deploy on its own -- it makes the
# artifacts available for sync-sports.yml to pull on its next run or dispatch.
#
# ------------------------------------------------------------------------------
# ## Failure reproductions
# ------------------------------------------------------------------------------
# A FAILS (no mutation, nothing written):
#     Rscript -e "source('tools/publish_web.R'); print(publish_web(dry_run = TRUE, run_start = Sys.time())\$assertions_failed)"
#
# B FAILS (no mutation):
#     Rscript -e "source('tools/publish_web.R'); print(.assert_slate_agreement(published_override = list(active_slate = 99L, total_games = 1L))\$summary)"
#
# C FAILS: the DEFAULT state of a checkout whose web/ tree is already committed,
#   so no setup is required. The dry run reports "CLEAN against HEAD".
#
# E FAILS (no mutation):
#     Rscript -e "source('tools/publish_web.R'); print(publish_web(dry_run = TRUE, publish_branch = 'no-such-branch')\$assertions_failed)"
#
# D's matcher, on synthetic text, with no setup:
#     Rscript -e "source('tools/publish_web.R'); print(.scan_stage_warnings(c('>>> NBA QUANTITATIVE ENGINE v5.0 STARTED: 2026-10-25 08:00:02', '>>> [WARN] build_x.R: declared output ... was NOT rewritten')))"
#
# F's parser, on one real file:
#     Rscript -e "source('tools/publish_web.R'); print(.pw_payload_generated_at(WEB_JSON_MATCHUPS_SLATES))"
# ==============================================================================

# ------------------------------------------------------------------------------
# Bootstrap: setwd() to this script's project root, then source config.R by bare
# filename (repo convention - the repo root is deliberately flat).
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

WEB_MEDIA_DIR <- file.path(PROJECT_DIR, "web", "public", "media")
if (!dir.exists(WEB_MEDIA_DIR)) dir.create(WEB_MEDIA_DIR, recursive = TRUE)

# Synchronize media outputs (cache/*.gif, cache/*.png) into web/public/media/
.pw_sync_media <- function(dry_run = FALSE) {
  if (!dir.exists(WEB_MEDIA_DIR)) dir.create(WEB_MEDIA_DIR, recursive = TRUE)
  source_cache <- if (exists("CACHE_DIR")) CACHE_DIR else file.path(PROJECT_DIR, "cache")
  if (!dir.exists(source_cache)) return(character(0))

  media_files <- list.files(source_cache, pattern = "\\.(gif|png)$", full.names = TRUE, ignore.case = TRUE)
  copied <- character(0)
  for (mf in media_files) {
    dest <- file.path(WEB_MEDIA_DIR, basename(mf))
    if (!dry_run) {
      ok <- file.copy(mf, dest, overwrite = TRUE)
      if (ok) copied <- c(copied, dest)
    } else {
      copied <- c(copied, dest)
    }
  }
  copied
}

# ------------------------------------------------------------------------------
# Small helpers
# ------------------------------------------------------------------------------
.pw_git <- function(repo, args) {
  # cmd.exe (and Task Scheduler's .bat-launched non-interactive session) does not
  # resolve HOME the way Git Bash does, so git can't find ~/.gitconfig and refuses
  # to commit with "unable to auto-detect email address" (NFL_analytics#53). Pass
  # identity explicitly via -c so commits don't depend on HOME/USERPROFILE
  # resolution in the invoking shell.
  # R on Windows rewrites HOME to "<USERPROFILE>/Documents", while Git for
  # Windows stores ~/.gitconfig at "<USERPROFILE>/.gitconfig". Point HOME at
  # USERPROFILE when .gitconfig lives there so both git config and git commit
  # resolve the user's global git config and credential helper.
  up <- Sys.getenv("USERPROFILE", "")
  if (nzchar(up) && file.exists(file.path(up, ".gitconfig"))) {
    Sys.setenv(HOME = up)
  }
  # `git rebase` writes commits too (the publish push step rebases onto
  # origin), so it gets the same explicit identity as `git commit`.
  if (args[1] %in% c("commit", "rebase")) {
    user_name <- Sys.getenv("GIT_AUTHOR_NAME", Sys.getenv("GIT_COMMITTER_NAME", ""))
    user_email <- Sys.getenv("GIT_AUTHOR_EMAIL", Sys.getenv("GIT_COMMITTER_EMAIL", ""))
    if (!nzchar(user_name) || !nzchar(user_email)) {
      cfg <- suppressWarnings(system2("git", c("-C", shQuote(repo), "config", "--global", "--get-regexp", "^user\\."),
                                       stdout = TRUE, stderr = TRUE,
                                       env = paste0("HOME=", Sys.getenv("USERPROFILE", Sys.getenv("HOME")))))
      if (is.null(attr(cfg, "status"))) {
        for (line in cfg) {
          if (startsWith(line, "user.name ")) user_name <- sub("^user\\.name ", "", line)
          if (startsWith(line, "user.email ")) user_email <- sub("^user\\.email ", "", line)
        }
      }
    }
    if (nzchar(user_name) && nzchar(user_email)) {
      args <- c("-c", shQuote(paste0("user.name=", user_name)),
                "-c", shQuote(paste0("user.email=", user_email)), args)
    }
  }
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

.pw_rel_to_repo <- function(path, repo_root) {
  if (is.na(repo_root)) return(path)
  p <- normalizePath(path, winslash = "/", mustWork = FALSE)
  r <- paste0(sub("/$", "", repo_root), "/")
  if (startsWith(p, r)) substring(p, nchar(r) + 1L) else p
}

# ------------------------------------------------------------------------------
# Run-start discovery.
#
# This repo has no structured logger. run_full_pipeline.R:6-9 prints
#   >>> NBA QUANTITATIVE ENGINE v5.0 STARTED: 2026-10-25 08:00:02
# through message(), and schedule_daily.bat redirects that into
# config.R's LOG_FILE. That banner is the only machine-readable run marker in
# the repo, so it is what this parses. The version number is matched loosely
# ("ENGINE.*STARTED") on purpose: the banner has been through at least one
# version bump, and a gate that silently stops finding the run start after the
# next one would fail open, which is the whole failure class this file exists
# to prevent. Overridable for tests and for republishing a historical run.
# ------------------------------------------------------------------------------
.pw_detect_run_start <- function(log_lines) {
  hits <- grep("NBA QUANTITATIVE ENGINE.*STARTED", log_lines)
  if (!length(hits)) return(NA)
  last <- log_lines[tail(hits, 1)]
  ts <- sub("^.*STARTED:[[:space:]]*", "", last)
  ts <- sub("[[:space:]]*$", "", ts)
  as.POSIXct(ts, format = "%Y-%m-%d %H:%M:%S", tz = "")
}

# ------------------------------------------------------------------------------
# ASSERTION A - mtime freshness
# ------------------------------------------------------------------------------
.assert_mtime_freshness <- function(run_start) {
  files <- WEB_DATA_FILES          # <- the twelve names come from config.R ONLY
  info  <- file.info(files)
  stale <- character(0)
  rows  <- vector("list", length(files))
  for (i in seq_along(files)) {
    f  <- files[i]
    mt <- info$mtime[i]
    present <- !is.na(info$size[i])
    fresh <- present && !is.na(mt) && !is.na(run_start) && mt > run_start
    rows[[i]] <- sprintf("    %-9s %-40s mtime=%s", if (fresh) "[FRESH]" else "[STALE]",
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
# ASSERTION B - slate agreement.
#
# Independent re-derivation of the published slate header from the schedule
# cache, using the same documented rule as build_matchups_dataset.R:
#   * drop TBD-vs-TBD fixtures -- ESPN ships NBA Cup knockout placeholders
#     before the groups finish, and they are not games yet
#     (build_matchups_dataset.R:229-236);
#   * season_start = the earliest remaining game date;
#   * slate index = floor((date - season_start) / 7) + 1;
#   * active slate = the slate whose date span contains today, else the first
#     slate before the season opens and the last one after it ends.
#
# The RULE is reimplemented here rather than imported, and that is the point:
# sourcing build_matchups_dataset.R would make this an echo of the thing under
# test (and would re-run a hoopR pull). What IS imported is every CONSTANT
# (MATCHUPS_HOOPR_SEASON, CACHE_MATCHUPS_SCHEDULE, WEB_JSON_MATCHUPS_SLATES),
# per CLAUDE.md's single-source-of-truth rule -- constants from config.R, logic
# independent. MATCHUPS_HOOPR_SEASON moved into config.R for exactly this
# reason; see the note there, and note that it is deliberately NOT
# CURRENT_SEASON.
# ------------------------------------------------------------------------------
.compute_slate_from_schedule <- function(season = MATCHUPS_HOOPR_SEASON,
                                         schedule_path = NULL) {
  if (is.null(schedule_path)) schedule_path <- CACHE_MATCHUPS_SCHEDULE(season)
  empty <- list(active_slate = NA_integer_, total_games = NA_integer_,
                season_start = NA, season_end = NA, path = schedule_path, note = NULL)
  if (!file.exists(schedule_path)) {
    empty$note <- sprintf("%s is absent", basename(schedule_path))
    return(empty)
  }
  sched <- tryCatch(as.data.frame(readRDS(schedule_path)), error = function(e) NULL)
  if (is.null(sched)) {
    empty$note <- "schedule cache unreadable"
    return(empty)
  }
  need <- c("game_date", "home_short_display_name", "away_short_display_name")
  if (!all(need %in% names(sched))) {
    empty$note <- sprintf("schedule cache lacks %s",
                          paste(setdiff(need, names(sched)), collapse = ", "))
    return(empty)
  }

  tbd <- sched$home_short_display_name == "TBD" | sched$away_short_display_name == "TBD"
  tbd[is.na(tbd)] <- FALSE
  s <- sched[!tbd, , drop = FALSE]
  gd <- as.Date(s$game_date)
  s <- s[!is.na(gd), , drop = FALSE]
  gd <- gd[!is.na(gd)]
  if (!nrow(s)) {
    empty$note <- "no dated games in the schedule cache"
    return(empty)
  }

  season_start <- min(gd)
  season_end   <- max(gd)
  slate <- as.integer(floor(as.numeric(gd - season_start) / 7) + 1)
  bounds <- data.frame(slate = slate, date = gd)
  starts <- tapply(bounds$date, bounds$slate, min)
  ends   <- tapply(bounds$date, bounds$slate, max)
  ids    <- as.integer(names(starts))
  starts <- as.Date(starts, origin = "1970-01-01")
  ends   <- as.Date(ends,   origin = "1970-01-01")

  today <- Sys.Date()
  in_today <- ids[starts <= today & ends >= today]
  active <- if (length(in_today) > 0) min(in_today)
            else if (today < season_start) min(ids)
            else max(ids)

  list(active_slate = as.integer(active),
       total_games = as.integer(nrow(s)),
       season_start = season_start, season_end = season_end,
       path = schedule_path, note = NULL)
}

.assert_slate_agreement <- function(season = MATCHUPS_HOOPR_SEASON,
                                    published_override = NULL) {
  computed <- .compute_slate_from_schedule(season)
  note <- computed$note
  published <- list(active_slate = NA_integer_, total_games = NA_integer_)

  if (!is.null(published_override)) {
    published <- published_override
  } else if (!file.exists(WEB_JSON_MATCHUPS_SLATES)) {
    note <- c(note, sprintf("%s is absent", basename(WEB_JSON_MATCHUPS_SLATES)))
  } else {
    j <- tryCatch(jsonlite::fromJSON(WEB_JSON_MATCHUPS_SLATES, simplifyVector = TRUE),
                  error = function(e) {
                    note <<- c(note, paste("unparseable JSON:", conditionMessage(e)))
                    NULL
                  })
    if (!is.null(j)) {
      if (!is.null(j$active_slate)) published$active_slate <- as.integer(j$active_slate[1])
      if (!is.null(j$total_games))  published$total_games  <- as.integer(j$total_games[1])
    }
  }

  have <- !is.na(computed$active_slate) && !is.na(published$active_slate) &&
          !is.na(computed$total_games) && !is.na(published$total_games)
  pass <- have &&
          identical(computed$active_slate, published$active_slate) &&
          identical(computed$total_games, published$total_games)

  list(id = "B", name = "slate agreement (schedule cache vs published matchups_slates)",
       pass = pass, fatal = TRUE,
       computed = computed, published = published,
       detail = c(
         sprintf("    recomputed from %-30s : slate=%s games=%s", basename(computed$path),
                 ifelse(is.na(computed$active_slate), "<NA>", computed$active_slate),
                 ifelse(is.na(computed$total_games), "<NA>", computed$total_games)),
         sprintf("    published in    %-30s : slate=%s games=%s", basename(WEB_JSON_MATCHUPS_SLATES),
                 ifelse(is.na(published$active_slate), "<NA>", published$active_slate),
                 ifelse(is.na(published$total_games), "<NA>", published$total_games)),
         sprintf("    hoopR season    : %d (NOT CURRENT_SEASON - see config.R)", as.integer(season)),
         if (length(note)) paste("    note:", note)),
       summary = sprintf("slate computed=%s published=%s | games computed=%s published=%s",
                         ifelse(is.na(computed$active_slate), "<NA>", computed$active_slate),
                         ifelse(is.na(published$active_slate), "<NA>", published$active_slate),
                         ifelse(is.na(computed$total_games), "<NA>", computed$total_games),
                         ifelse(is.na(published$total_games), "<NA>", published$total_games)))
}

# ------------------------------------------------------------------------------
# ASSERTION C - non-empty diff under the published tree (web/public/data or
# web/public/media). Resolved against the RUNTIME git root, never a hardcoded
# path, so a worktree is reported against its own repository.
# Media-only changes (e.g. Slot C regenerating nba_predictions_today.png on a
# quiet night when JSON payloads are unchanged) are valid publishes (#130).
# ------------------------------------------------------------------------------
.assert_nonempty_diff <- function(repo_root) {
  if (is.na(repo_root)) {
    return(list(id = "C", name = "non-empty diff under web/public/data or web/public/media",
                pass = FALSE, fatal = TRUE, changed = character(0), paths = character(0),
                detail = "    could not resolve a git repository for the working directory",
                summary = "no git repo"))
  }
  rel_data <- .pw_rel_to_repo(WEB_DATA_DIR, repo_root)
  rel_media <- if (exists("WEB_MEDIA_DIR") && nzchar(WEB_MEDIA_DIR)) {
    .pw_rel_to_repo(WEB_MEDIA_DIR, repo_root)
  } else {
    character(0)
  }
  watch_paths <- unique(c(rel_data, rel_media))
  r <- .pw_git(repo_root, c("status", "--porcelain", "--", watch_paths))
  changed <- if (r$ok) r$out[nzchar(r$out)] else character(0)
  list(id = "C", name = "non-empty diff under web/public/data or web/public/media",
       pass = length(changed) > 0, fatal = TRUE, changed = changed, paths = rel_data,
       detail = if (length(changed)) paste0("    ", changed)
                else sprintf("    CLEAN against HEAD - nothing to publish (repo: %s)", repo_root),
       summary = sprintf("%d pending change(s) under %s", length(changed),
                         paste(watch_paths, collapse = ", ")))
}

# ------------------------------------------------------------------------------
# ASSERTION D - stage warning scan for the run window.
#
# run_stage() and .check_stage_output() report through message(), in two fixed
# shapes (run_full_pipeline.R:40-46):
#     >>> [WARN] <script>: declared output '<path>' was NOT rewritten ...
#     >>> [FAIL] <script>: ...
# The log carries no per-line timestamps, so the run window is taken as
# "everything after the last run-start banner" rather than by parsing times --
# which is exactly as precise here, since the banner is printed once per run.
# ------------------------------------------------------------------------------
.scan_stage_warnings <- function(log_lines) {
  starts <- grep("NBA QUANTITATIVE ENGINE.*STARTED", log_lines)
  window <- if (length(starts)) log_lines[tail(starts, 1):length(log_lines)] else log_lines
  hits <- grep(">>> \\[(WARN|FAIL)\\]", window, value = TRUE)
  as.character(hits)
}

.assert_log_scan <- function(log_lines, fail_on_warnings) {
  warns <- .scan_stage_warnings(log_lines)
  list(id = "D", name = "stage [WARN]/[FAIL] scan of the pipeline log",
       pass = !(fail_on_warnings && length(warns) > 0),
       fatal = fail_on_warnings,
       warnings = warns,
       detail = if (length(warns)) paste0("    ", warns)
                else "    no stage [WARN]/[FAIL] lines since the last run-start banner",
       summary = sprintf("%d stage warning(s) surfaced%s", length(warns),
                         if (fail_on_warnings) " (fatal)" else " (reported, non-fatal)"))
}

# ------------------------------------------------------------------------------
# ASSERTION E - publish branch.
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
# ASSERTION F - payload provenance.
#
# Reads the `generated_at` stamp out of each WEB_DATA_FILES payload that has one
# and requires it to be no older than the run start. Generalises
# run_full_pipeline.R's existing projection publish guard to every stamped
# payload; see this file's header for why an mtime assertion cannot do this job.
#
# Only the top of each file is read: these payloads reach several MB and
# `generated_at` is written in the first object, so slurping the whole document
# through jsonlite to reach one scalar would slow every scheduled run for
# nothing. The regex is anchored on the key, not on a position.
#
# Timezone: NBA's two stamped payloads disagree with each other --
# projections_models_metadata.json writes "...Z" (UTC) and
# matchups_slates.json writes no suffix (local). Both are honoured rather than
# assumed: a trailing Z is parsed as UTC, its absence as local time. Guessing
# one convention for both would have made one of the two off by the UTC offset,
# which on a 08:00 local run is four hours -- easily enough to turn a fresh
# payload stale or a stale one fresh.
# ------------------------------------------------------------------------------
.pw_payload_generated_at <- function(path, head_bytes = 4096L) {
  if (!file.exists(path)) return(NA)
  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw <- readBin(con, "raw", n = head_bytes)
  txt <- rawToChar(raw[raw != as.raw(0)])
  Encoding(txt) <- "UTF-8"
  m <- regmatches(txt, regexpr('"generated_at"[[:space:]]*:[[:space:]]*"[^"]+"', txt))
  if (!length(m)) return(NA)
  val <- sub('^.*:[[:space:]]*"([^"]+)".*$', "\\1", m[1])
  if (grepl("Z$", val)) {
    as.POSIXct(sub("Z$", "", val), format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
  } else {
    as.POSIXct(val, format = "%Y-%m-%dT%H:%M:%S", tz = "")
  }
}

.assert_payload_provenance <- function(run_start) {
  files <- WEB_DATA_FILES
  rows <- character(0)
  stale <- character(0)
  unstamped <- character(0)
  for (f in files) {
    g <- .pw_payload_generated_at(f)
    if (is.na(g)) {
      unstamped <- c(unstamped, basename(f))
      next
    }
    fresh <- !is.na(run_start) && g >= run_start
    if (!fresh) stale <- c(stale, basename(f))
    rows <- c(rows, sprintf("    %-9s %-40s generated_at=%s",
                            if (fresh) "[FRESH]" else "[STALE]", basename(f),
                            format(g, "%Y-%m-%d %H:%M:%S %Z")))
  }
  if (length(unstamped)) {
    rows <- c(rows,
              sprintf("    [NO STAMP] %d payload(s) carry no generated_at, so F cannot speak for them:",
                      length(unstamped)),
              paste0("               ", unstamped))
  }
  list(id = "F", name = "payload provenance (embedded generated_at at or after run start)",
       pass = length(stale) == 0, fatal = TRUE,
       stale = stale, unstamped = unstamped,
       detail = rows,
       summary = sprintf("%d stamped payload(s) fresh, %d stale, %d carry no stamp",
                         length(files) - length(stale) - length(unstamped),
                         length(stale), length(unstamped)))
}

# ------------------------------------------------------------------------------
# ASSERTION G - web dataset contracts.
#
# Ported from WNBA Analytics' tools/publish_web.R on 2026-10-26, the same day
# and for the same reason: WNBA's gate reported all six of its assertions PASS
# at 08:01 over payloads its own web contract suite rejects -- projected wins
# summing to 331.00 against the total_schedule_games = 330 published beside
# them.
#
# The hole is not WNBA's. Every assertion in this file asks WHEN a payload was
# written, WHETHER its bytes changed, WHAT the log said or WHOSE branch it is
# on. None of them reads the numbers inside and asks whether they agree with
# each other, so a fresh, diffed, correctly-stamped payload full of wrong
# numbers clears every one of them.
#
# The suite that does ask already exists in this repo and runs in CI -- but CI
# runs over the COMMITTED tree, i.e. after a publish, which is too late to
# stop one. G points the same assertions at the UNCOMMITTED payload, through
# the suite's own `contracts` stage. Seconds: vitest over JSON, no browser and
# no build.
#
# ONLY the `contracts` stage. typecheck, lint, build and e2e are claims about
# the code, and the code is not what this gate is deciding about.
#
# Lettered G in all three repos even though this file has A to F, so the
# letter means the same thing in every sport's report.
#
# FATAL, with a documented escape valve: web/tests/known-issues.json. The
# runner reports a listed failure as KNOWN and still exits 0, so a defect
# judged shippable stays shippable - once someone has written down its id,
# severity, title and fix. An UNDOCUMENTED contract failure blocks the
# publish. That is the policy the merge gate already runs on; this reuses it
# rather than inventing a second one.
#
# "Cannot verify" is fatal too, not a silent pass: an absent web/node_modules
# means the check did not run, which is not the same as the check passing.
# --skip-contracts overrides that deliberately and says so in the report.
# ------------------------------------------------------------------------------
.PW_WEB_DIR     <- "web"
.PW_WEB_RUNNER  <- file.path("scripts", "run-test-suite.mjs")

.pw_contract_result <- function(pass, fatal, summary, detail) {
  list(id = "G", name = "web dataset contracts (vitest node project)",
       pass = pass, fatal = fatal, summary = summary, detail = detail)
}

.assert_web_contracts <- function(skip = FALSE) {
  if (isTRUE(skip)) {
    return(.pw_contract_result(
      TRUE, FALSE, "skipped at the caller's request (--skip-contracts)",
      "    [SKIP]    the payload's internal consistency was NOT checked this run"))
  }

  web_dir <- normalizePath(.PW_WEB_DIR, winslash = "/", mustWork = FALSE)
  runner  <- file.path(web_dir, .PW_WEB_RUNNER)

  if (!file.exists(runner)) {
    return(.pw_contract_result(
      FALSE, TRUE, sprintf("no contract runner at %s - cannot verify", runner),
      "    [BLOCK]   expected web/scripts/run-test-suite.mjs; this repo has no suite to point at"))
  }
  if (!dir.exists(file.path(web_dir, "node_modules"))) {
    return(.pw_contract_result(
      FALSE, TRUE, "web/node_modules is absent - cannot verify",
      c("    [BLOCK]   run `npm ci` in web/ once on this machine, then re-run the gate.",
        "    [BLOCK]   Not verifying is not the same as verifying: pass --skip-contracts",
        "    [BLOCK]   to publish anyway, and the report will say the check was skipped.")))
  }
  node <- Sys.which("node")
  if (!nzchar(node)) {
    return(.pw_contract_result(
      FALSE, TRUE, "node is not on PATH - cannot verify",
      "    [BLOCK]   the contract suite needs node; install it or pass --skip-contracts"))
  }

  # The runner resolves its own paths from import.meta.dirname, but it spawns
  # npx vitest, which does not - so the working directory has to be web/.
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(web_dir)
  out <- suppressWarnings(system2(node, c(shQuote(.PW_WEB_RUNNER), "--only=contracts"),
                                  stdout = TRUE, stderr = TRUE))
  st  <- attr(out, "status")
  setwd(old_wd)
  status <- if (is.null(st)) 0L else as.integer(st)
  out <- if (is.null(out)) character(0) else as.character(out)

  # The runner's own summary block is the report; quoting it beats
  # re-describing it, and it already distinguishes KNOWN from NEW.
  start <- grep("TEST SUITE SUMMARY", out, fixed = TRUE)
  tail_lines <- if (length(start)) out[seq(max(start), length(out))] else tail(out, 20)
  tail_lines <- tail_lines[nzchar(trimws(tail_lines))]
  detail <- paste0("    ", tail_lines)

  counts <- grep("passed", out, fixed = TRUE, value = TRUE)
  counts <- trimws(counts[length(counts)])

  .pw_contract_result(
    status == 0L, TRUE,
    sprintf("%s - %s", if (status == 0L) "no undocumented contract failures" else
            "payload FAILS the contract suite; publishing it would ship the defect",
            if (length(counts) && nzchar(counts)) counts else sprintf("runner exit %d", status)),
    detail)
}

# ------------------------------------------------------------------------------
# ASSERTION H - data manifest completeness + schedule coverage
# (front-office#102 sidecar, front-office#191 lag gate).
#
# web/public/data/data_manifest.json (tools/write_data_manifest.R) stamps every
# top-level payload with generated_at / through_date / builder / max_lag_days /
# static. H requires:
#   * the manifest exists and parses, and EVERY top-level *.json beside it is
#     listed with a UTC ISO-8601 generated_at, a builder and a boolean static
#     (always checked, even offline - an unlisted payload is unaccounted for);
#   * when the schedule's latest completed game date is known, every non-static
#     dataset's through_date trails it by at most max_lag_days (off-season, i.e.
#     schedule <= through_date, passes); a static dataset passes only with a
#     non-empty static_reason.
# With no schedule cache (CI, sandbox) only completeness is enforced, and the
# summary says so. Every dataset gets a detail line so a dry run prints each
# one's coverage date. Self-contained: works when write_data_manifest.R is not
# present beside this file (tests isolate publish_web.R).
# ------------------------------------------------------------------------------
.PW_MANIFEST_FILE <- "data_manifest.json"

.pw_dm_script <- function() file.path(PROJECT_DIR, "tools", "write_data_manifest.R")

.pw_latest_completed_schedule_date <- function(schedule_path) {
  if (exists("dm_latest_completed_schedule_date", mode = "function")) {
    return(dm_latest_completed_schedule_date(schedule_path))
  }
  if (is.null(schedule_path) || is.na(schedule_path) || !file.exists(schedule_path)) return(as.Date(NA))
  s <- tryCatch(as.data.frame(readRDS(schedule_path)), error = function(e) NULL)
  if (is.null(s) || !nrow(s) || !"game_date" %in% names(s)) return(as.Date(NA))
  done <- if ("status_type_completed" %in% names(s)) as.logical(s$status_type_completed)
          else if ("status_type_state" %in% names(s)) s$status_type_state == "post"
          else return(as.Date(NA))
  gd <- as.Date(as.character(s$game_date))[done %in% TRUE]
  gd <- gd[!is.na(gd)]
  if (!length(gd)) as.Date(NA) else max(gd)
}

.pw_nzstr <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)

.pw_is_utc_iso <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) &&
    grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", x) &&
    !is.na(as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
}

.pw_h_result <- function(pass, summary, detail, extra = list()) {
  c(list(id = "H", name = "data manifest completeness + schedule coverage (FO#102/#191)",
         pass = pass, fatal = TRUE, summary = summary, detail = detail), extra)
}

.assert_manifest_and_coverage <- function(web_data_dir = WEB_DATA_DIR,
                                          schedule_through_date = NULL,
                                          schedule_path = CACHE_MATCHUPS_SCHEDULE(MATCHUPS_HOOPR_SEASON)) {
  mpath <- file.path(web_data_dir, .PW_MANIFEST_FILE)
  if (!file.exists(mpath)) {
    return(.pw_h_result(FALSE, sprintf("%s is absent", .PW_MANIFEST_FILE),
                        "    [BLOCK]   run `Rscript tools/write_data_manifest.R`"))
  }
  m <- tryCatch(jsonlite::fromJSON(mpath, simplifyVector = FALSE), error = function(e) e)
  if (inherits(m, "error") || !is.list(m) || !is.list(m$datasets)) {
    return(.pw_h_result(FALSE, sprintf("%s does not parse as a manifest", .PW_MANIFEST_FILE),
                        paste("    [BLOCK]  ", if (inherits(m, "error")) conditionMessage(m) else "no datasets object")))
  }
  on_disk <- setdiff(sort(list.files(web_data_dir, pattern = "\\.json$")), .PW_MANIFEST_FILE)

  sched <- if (!is.null(schedule_through_date)) as.Date(schedule_through_date)
           else .pw_latest_completed_schedule_date(schedule_path)
  sched_known <- length(sched) == 1L && !is.na(sched)

  rows <- character(0); bad <- character(0)
  for (f in on_disk) {
    e <- m$datasets[[f]]
    if (is.null(e)) {
      bad <- c(bad, f)
      rows <- c(rows, sprintf("    %-10s %-36s not listed in %s", "[MISSING]", f, .PW_MANIFEST_FILE))
      next
    }
    problems <- c(
      if (!.pw_is_utc_iso(e$generated_at)) "generated_at not UTC ISO-8601",
      if (!is.character(e$builder) || !nzchar(e$builder) || identical(e$builder, "<unregistered>")) "no builder",
      if (!is.logical(e$static) || length(e$static) != 1L) "static not boolean",
      if (!.pw_nzstr(e$through_date_source)) "no through_date_source",
      if (!.pw_nzstr(e$stamp_source)) "no stamp_source",
      if (!is.null(e$content_sha256) && !grepl("^[0-9a-f]{64}$", as.character(e$content_sha256)[1])) "content_sha256 not sha256 hex",
      if (!is.null(e$coverage_note) && !.pw_nzstr(e$coverage_note)) "coverage_note not a string",
      if (identical(e$stamp_source, "manifest:content_hash") && is.null(e$content_sha256)) "content-hash stamp without content_sha256")
    if (length(problems)) {
      bad <- c(bad, f)
      rows <- c(rows, sprintf("    %-10s %-36s %s", "[UNSTAMPED]", f, paste(problems, collapse = "; ")))
      next
    }
    td <- if (is.null(e$through_date)) NA_character_ else as.character(e$through_date)
    if (isTRUE(e$static)) {
      ok <- is.character(e$static_reason) && nzchar(e$static_reason)
      if (!ok) bad <- c(bad, f)
      rows <- c(rows, sprintf("    %-10s %-36s through=%-10s %s", if (ok) "[STATIC]" else "[LAGGING]", f,
                              ifelse(is.na(td), "<none>", td),
                              if (ok) e$static_reason else "static without a static_reason"))
      next
    }
    lag_max <- suppressWarnings(as.integer(e$max_lag_days))
    if (!sched_known) {
      rows <- c(rows, sprintf("    %-10s %-36s through=%-10s (schedule unknown; lag not checked)",
                              if (is.na(td)) "[UNDATED]" else "[OK]", f, ifelse(is.na(td), "<none>", td)))
      next
    }
    if (identical(e$through_date_source, "not_game_dated") && is.na(td)) {
      # Content carries no game date: checked on generated_at freshness only,
      # never passed silently as fresh.
      gdate <- as.Date(substr(e$generated_at, 1L, 10L))
      if (length(lag_max) != 1L || is.na(lag_max)) {
        ok <- FALSE; lag <- NA_integer_
      } else {
        lag <- as.integer(sched - gdate); ok <- lag <= lag_max
      }
      if (!ok) bad <- c(bad, f)
      rows <- c(rows, sprintf("    %-10s %-36s generated=%s lag=%sd max=%sd%s", if (ok) "[UNDATED]" else "[LAGGING]",
                              f, format(gdate), ifelse(is.na(lag), "NA", max(lag, 0L)),
                              ifelse(is.na(lag_max), "NA", lag_max),
                              if (.pw_nzstr(e$coverage_note)) paste0(" (", e$coverage_note, ")") else ""))
      next
    }
    if (is.na(td) || length(lag_max) != 1L || is.na(lag_max)) {
      bad <- c(bad, f)
      rows <- c(rows, sprintf("    %-10s %-36s through=%-10s no through_date/max_lag_days on a non-static dataset",
                              "[LAGGING]", f, ifelse(is.na(td), "<none>", td)))
      next
    }
    lag <- as.integer(sched - as.Date(td))
    ok <- lag <= lag_max      # off-season / ahead of schedule => lag <= 0 => pass
    if (!ok) bad <- c(bad, f)
    rows <- c(rows, sprintf("    %-10s %-36s through=%s lag=%dd max=%dd", if (ok) "[OK]" else "[LAGGING]",
                            f, td, max(lag, 0L), lag_max))
  }
  phantom <- setdiff(names(m$datasets), on_disk)
  if (length(phantom)) rows <- c(rows, sprintf("    [NOTE]     manifest lists %s with no file on disk", phantom))

  summary <- if (!sched_known) {
    sprintf("%d/%d dataset(s) stamped; schedule cache absent; manifest completeness verified%s",
            length(on_disk) - length(bad), length(on_disk), if (length(bad)) " - FAILED" else "")
  } else {
    sprintf("%d/%d dataset(s) within lag of schedule through %s", length(on_disk) - length(bad),
            length(on_disk), format(sched))
  }
  .pw_h_result(length(bad) == 0L, summary,
               c(sprintf("    schedule through : %s", if (sched_known) format(sched) else "<unknown>"), rows),
               list(failing = bad, schedule_through_date = if (sched_known) format(sched) else NA_character_))
}

# Live publishes refresh the manifest right before the gate; dry runs never write.
.pw_refresh_manifest <- function(dry_run, web_data_dir = WEB_DATA_DIR,
                                 schedule_path = CACHE_MATCHUPS_SCHEDULE(MATCHUPS_HOOPR_SEASON)) {
  if (isTRUE(dry_run)) return(invisible(FALSE))
  script <- .pw_dm_script()
  if (!file.exists(script)) return(invisible(FALSE))
  env <- new.env()
  ok <- tryCatch({
    sys.source(script, envir = env)
    env$write_data_manifest(data_dir = web_data_dir, schedule_path = schedule_path)
    TRUE
  }, error = function(e) {
    message(sprintf(">>> [WARN] publish_web: data manifest refresh failed: %s", conditionMessage(e)))
    FALSE
  })
  invisible(ok)
}

# ------------------------------------------------------------------------------
# ASSERTION L - data-file lifecycle + frozen-file integrity (NBA_analytics#235).
#
# Every top-level web/public/data/*.json (excluding data_manifest.json) must
# have a manifest entry with a valid `lifecycle` in WEB_DATA_LIFECYCLES
# ("live", "season_final", "archived"). Missing or unknown lifecycle FAILS.
# Any `season_final` entry must carry season, final_through_date, frozen_sha256
# and frozen_at, and the file's current CRLF-normalised sha256 must match
# frozen_sha256.
# ------------------------------------------------------------------------------
.pw_valid_lifecycles <- function() {
  if (exists("WEB_DATA_LIFECYCLES")) WEB_DATA_LIFECYCLES else c("live", "season_final", "archived")
}

.pw_lifecycle_sha256 <- function(path) {
  if (exists("nba_lifecycle_sha256", mode = "function")) {
    return(nba_lifecycle_sha256(path))
  }
  if (!file.exists(path)) return(NA_character_)
  sz <- file.info(path)$size
  b <- if (is.na(sz) || sz == 0) raw(0) else readBin(path, "raw", n = sz)
  cr <- which(b == as.raw(13L))
  if (length(cr)) {
    crlf <- cr[cr < length(b) & b[pmin(cr + 1L, length(b))] == as.raw(10L)]
    if (length(crlf)) b <- b[-crlf]
  }
  unname(as.character(tools::sha256sum(bytes = b)))
}

.pw_l_result <- function(pass, summary, detail, extra = list()) {
  c(list(id = "L", name = "data-file lifecycle + frozen-file integrity (NBA#235)",
         pass = pass, fatal = TRUE, summary = summary, detail = detail), extra)
}

.assert_lifecycle <- function(web_data_dir = WEB_DATA_DIR,
                              manifest = NULL,
                              expected = NULL) {
  if (is.null(manifest)) {
    mpath <- file.path(web_data_dir, .PW_MANIFEST_FILE)
    if (!file.exists(mpath)) {
      return(.pw_l_result(FALSE, sprintf("%s is absent", .PW_MANIFEST_FILE),
                          "    [BLOCK]   run `Rscript tools/write_data_manifest.R`",
                          list(problems = sprintf("%s is absent", .PW_MANIFEST_FILE), failing = character(0))))
    }
    manifest <- tryCatch(jsonlite::fromJSON(mpath, simplifyVector = FALSE), error = function(e) e)
    if (inherits(manifest, "error")) {
      msg <- conditionMessage(manifest)
      return(.pw_l_result(FALSE, sprintf("%s does not parse as a manifest", .PW_MANIFEST_FILE),
                          paste("    [BLOCK]  ", msg),
                          list(problems = msg, failing = character(0))))
    }
  }
  if (!is.list(manifest) || !is.list(manifest$datasets)) {
    return(.pw_l_result(FALSE, sprintf("%s does not parse as a manifest", .PW_MANIFEST_FILE),
                        "    [BLOCK]   no datasets object",
                        list(problems = "no datasets object", failing = character(0))))
  }

  on_disk <- setdiff(sort(list.files(web_data_dir, pattern = "\\.json$")), .PW_MANIFEST_FILE)
  valid_lc <- .pw_valid_lifecycles()
  exp <- if (is.function(expected)) expected(on_disk) else NULL

  problems <- character(0)
  failing <- character(0)
  lines <- character(0)
  counts <- stats::setNames(integer(length(valid_lc)), valid_lc)

  for (f in on_disk) {
    e <- manifest$datasets[[f]]
    if (is.null(e) || !is.list(e)) {
      failing <- c(failing, f)
      problems <- c(problems, sprintf("%s not listed in %s", f, .PW_MANIFEST_FILE))
      lines <- c(lines, sprintf("    %-14s %-36s not listed in %s", "[MISSING]", f, .PW_MANIFEST_FILE))
      next
    }
    lc <- e$lifecycle
    if (is.null(lc) || (is.character(lc) && length(lc) == 1L && (is.na(lc) || !nzchar(trimws(lc))))) {
      failing <- c(failing, f)
      problems <- c(problems, sprintf("%s has no lifecycle", f))
      lines <- c(lines, sprintf("    %-14s %-36s missing lifecycle", "[NO LIFECYCLE]", f))
      next
    }
    if (!is.character(lc) || length(lc) != 1L || !(lc %in% valid_lc)) {
      lc_str <- paste(as.character(lc), collapse = ",")
      failing <- c(failing, f)
      problems <- c(problems, sprintf("%s unknown lifecycle '%s'", f, lc_str))
      lines <- c(lines, sprintf("    %-14s %-36s unknown lifecycle '%s'", "[FAIL]", f, lc_str))
      next
    }
    if (!is.null(exp)) {
      want <- exp[[f]]$lifecycle
      if (!identical(as.character(if (is.null(want)) "<none>" else want), lc)) {
        failing <- c(failing, f)
        problems <- c(problems, sprintf("%s lifecycle %s != config %s", f, lc, if (is.null(want)) "<none>" else want))
        lines <- c(lines, sprintf("    %-14s %-36s manifest says %s, config assigns %s",
                                  "[FAIL]", f, lc, if (is.null(want)) "<none>" else want))
        next
      }
    }
    counts[[lc]] <- counts[[lc]] + 1L
    if (!identical(lc, "season_final")) {
      lines <- c(lines, sprintf("    %-14s %s", sprintf("[%s]", toupper(lc)), f))
      next
    }
    req_fields <- c("season", "final_through_date", "frozen_sha256", "frozen_at")
    miss <- Filter(function(k) {
      v <- e[[k]]
      is.null(v) || length(v) != 1L || is.na(v) || !nzchar(trimws(as.character(v)))
    }, req_fields)
    if (length(miss)) {
      failing <- c(failing, f)
      problems <- c(problems, sprintf("%s season_final missing %s", f, paste(miss, collapse = ", ")))
      lines <- c(lines, sprintf("    %-14s %-36s season_final without %s", "[FAIL]", f, paste(miss, collapse = ", ")))
      next
    }
    if (!grepl("^[0-9a-f]{64}$", as.character(e$frozen_sha256))) {
      failing <- c(failing, f)
      problems <- c(problems, sprintf("%s invalid frozen_sha256", f))
      lines <- c(lines, sprintf("    %-14s %-36s frozen_sha256 not 64-char hex", "[FAIL]", f))
      next
    }
    if (!is.null(exp) && !is.null(exp[[f]]$frozen_sha256) &&
        !identical(as.character(exp[[f]]$frozen_sha256), as.character(e$frozen_sha256))) {
      failing <- c(failing, f)
      problems <- c(problems, sprintf("%s frozen_sha256 disagrees with registry", f))
      lines <- c(lines, sprintf("    %-14s %-36s manifest frozen_sha256 differs from expected", "[FAIL]", f))
      next
    }
    actual <- .pw_lifecycle_sha256(file.path(web_data_dir, f))
    if (!identical(actual, as.character(e$frozen_sha256))) {
      failing <- c(failing, f)
      problems <- c(problems, sprintf("%s changed since frozen", f))
      lines <- c(lines, sprintf("    %-14s %-36s season %s frozen at %s, hash now %s (frozen %s)",
                                "[CHANGED]", f, as.character(e$season), as.character(e$frozen_at),
                                substr(actual, 1L, 12L), substr(as.character(e$frozen_sha256), 1L, 12L)))
      next
    }
    lines <- c(lines, sprintf("    %-14s %-36s season %s, hash matches frozen %s",
                              "[SEASON_FINAL]", f, as.character(e$season), as.character(e$frozen_at)))
  }

  pass <- length(problems) == 0L
  summary <- if (pass) {
    sprintf("%d file(s): %d live, %d season_final (hash verified), %d archived",
            length(on_disk), counts[["live"]], counts[["season_final"]], counts[["archived"]])
  } else {
    sprintf("%d problem(s): %s", length(problems), paste(problems, collapse = "; "))
  }
  .pw_l_result(pass, summary, lines, list(problems = problems, failing = failing, counts = counts))
}

# ------------------------------------------------------------------------------
# Commit / push sequence. ONLY reached when dry_run = FALSE and every fatal
# assertion passed. Commits the published tree and pushes NBA_analytics --
# nothing more. The deploy belongs to the aggregator's sync-sports.yml.
#
# Commits can land on origin/<publish_branch> while the pipeline runs (on
# 2026-11-24 two dependency PRs merged mid-run, the plain push was rejected
# with "fetch first", and the publish commit was stranded locally). So after
# committing, the push step:
#   1. fetches origin/<publish_branch>;
#   2. if that tip is not already an ancestor of HEAD, rebases the publish
#      commit onto it (publish commits only touch generated data, so a rebase
#      is right; never a merge commit, never an autostash);
#   3. pushes; if the push is rejected, repeats 1-2 once and pushes once more.
# Any failure after the commit (fetch error, rebase conflict, second push
# rejection) aborts the rebase if one is in progress and moves the branch back
# to origin/<publish_branch> with `git reset --mixed`, which touches no
# working-tree file. No local commit is left behind, the checkout is in step
# with origin, and the regenerated files stay in the working tree for the next
# run. Never `reset --hard`, never `git stash` (the stash stack is shared by
# every checkout of the repo).
# ------------------------------------------------------------------------------
.pw_short_sha <- function(repo_root, ref) {
  r <- .pw_git(repo_root, c("rev-parse", "--short=12", ref))
  if (r$ok && length(r$out)) r$out[[1]] else "<unknown>"
}

.pw_do_publish <- function(repo_root, rel_paths, commit_message, publish_branch = "main") {
  steps <- list()
  note <- function(label, res) {
    steps[[length(steps) + 1L]] <<- list(label = label, ok = res$ok, out = res$out)
    invisible(res$ok)
  }
  record <- function(label, res) {
    note(label, res)
    if (!res$ok) stop(sprintf("publish_web: step failed: %s\n%s", label,
                              paste(res$out, collapse = "\n")), call. = FALSE)
    invisible(TRUE)
  }
  remote_ref <- paste0("origin/", publish_branch)

  # Undo the local publish commit without touching the working tree, then fail.
  abandon <- function(label, res) {
    note(label, res)
    # Harmless when no rebase is in progress; its result is recorded either way.
    note("git rebase --abort (NBA_analytics)",
         .pw_git(repo_root, c("rebase", "--abort")))
    reset <- .pw_git(repo_root, c("reset", "--mixed", "-q", remote_ref))
    note(sprintf("git reset --mixed %s (NBA_analytics)", remote_ref), reset)
    state <- if (reset$ok) {
      sprintf(paste0("The local %s branch was moved back to %s (%s), so the checkout is ",
                     "in step with origin and no local publish commit is left behind. ",
                     "The regenerated files are still in the working tree for the next run."),
              publish_branch, remote_ref, .pw_short_sha(repo_root, remote_ref))
    } else {
      sprintf(paste0("ALSO, moving the local %s branch back to %s FAILED, so the local ",
                     "publish commit may still be on the branch; inspect `git status` ",
                     "and `git log %s..HEAD` before the next run.\n%s"),
              publish_branch, remote_ref, remote_ref, paste(reset$out, collapse = "\n"))
    }
    stop(sprintf(paste0("publish_web: step failed: %s\n%s\n",
                        "publish_web: the publish commit was NOT pushed to NBA_analytics %s. %s"),
                 label, paste(res$out, collapse = "\n"), publish_branch, state),
         call. = FALSE)
  }

  # Steps 1-2: fetch the remote tip and rebase the publish commit onto it.
  sync_onto_remote <- function() {
    fetch_label <- sprintf("git fetch origin %s (NBA_analytics)", publish_branch)
    fetched <- .pw_git(repo_root, c("fetch", "origin", publish_branch))
    if (!fetched$ok) abandon(fetch_label, fetched)
    note(fetch_label, fetched)
    tip <- .pw_short_sha(repo_root, remote_ref)
    message(sprintf(">>> publish_web: fetched %s (remote tip %s).", remote_ref, tip))
    anc <- .pw_git(repo_root, c("merge-base", "--is-ancestor", remote_ref, "HEAD"))
    if (anc$ok) {
      message(sprintf(">>> publish_web: HEAD already contains %s %s; no rebase needed.",
                      remote_ref, tip))
      return(invisible(TRUE))
    }
    rebase_label <- sprintf("git rebase %s (NBA_analytics)", remote_ref)
    rebased <- .pw_git(repo_root, c("rebase", "--no-autostash", remote_ref))
    if (!rebased$ok) abandon(sprintf("%s - conflict or error, rebase aborted", rebase_label), rebased)
    note(rebase_label, rebased)
    message(sprintf(">>> publish_web: rebased the publish commit onto the remote tip %s %s (HEAD now %s).",
                    remote_ref, tip, .pw_short_sha(repo_root, "HEAD")))
    invisible(TRUE)
  }

  rel_media <- .pw_rel_to_repo(WEB_MEDIA_DIR, repo_root)
  # Landing-digest ratings history (NBA#213), the Momentum Board's rank
  # history (MOMENTUM_RANK_HISTORY in config.R) and its forward log
  # (MOMENTUM_FORWARD_LOG in config.R): tracked, outside web/public,
  # and staged by their exact paths without -f (they must never be gitignored),
  # each only when it exists.
  hist_paths <- c("data/history/ratings_history.csv",
                  "data/history/momentum_rank_history.csv",
                  "data/history/momentum_forward_log.csv")
  rel_hist <- hist_paths[file.exists(file.path(repo_root, hist_paths))]
  all_paths <- unique(c(rel_paths, rel_media, rel_hist))
  record("git add web/public/data & web/public/media",
         .pw_git(repo_root, c("add", "-A", "--", all_paths)))
  record("git commit (NBA_analytics)",
         .pw_git(repo_root, c("commit", "-m", shQuote(commit_message))))

  sync_onto_remote()
  push_label <- "git push origin HEAD (NBA_analytics)"
  pushed <- .pw_git(repo_root, c("push", "origin", "HEAD"))
  if (!pushed$ok) {
    note(sprintf("%s - rejected, retrying once after fetch + rebase", push_label), pushed)
    message(sprintf(">>> publish_web: push to %s was rejected; fetching and rebasing once more.",
                    remote_ref))
    sync_onto_remote()
    pushed <- .pw_git(repo_root, c("push", "origin", "HEAD"))
    if (!pushed$ok) abandon(sprintf("%s - rejected a second time", push_label), pushed)
  }
  note(push_label, pushed)
  message(sprintf(">>> publish_web: pushed %s to %s.", .pw_short_sha(repo_root, "HEAD"), remote_ref))
  steps
}

# ------------------------------------------------------------------------------
# Deploy observability notification (ported from NFL_analytics#40 / #41).
#
# Posts the publish gate outcome to NBA_DISCORD_WEBHOOK (with fallback to
# DISCORD_WEBHOOK_URL, read via Sys.getenv, never hardcoded):
#   * On success or dry-run pass: active_slate, total_games, and any stage
#     [WARN]/[FAIL] lines surfaced during the run window.
#   * On blocked gate: the specific assertion(s) that failed plus any stage
#     [WARN]/[FAIL] lines.
# ------------------------------------------------------------------------------
.pw_notify_discord <- function(result) {
  webhook_url <- Sys.getenv("NBA_DISCORD_WEBHOOK", Sys.getenv("DISCORD_WEBHOOK_URL", ""))
  slate <- if (!is.null(result$slate_published)) result$slate_published$active_slate else NA
  tot_games <- if (!is.null(result$slate_published)) result$slate_published$total_games else NA
  warns <- result$stage_warnings

  status_label <- if (isTRUE(result$blocked)) {
    "BLOCKED (Assertion Failed)"
  } else if (isTRUE(result$published)) {
    "PUBLISHED TO MAIN"
  } else {
    "DRY RUN PASSED"
  }

  color <- if (isTRUE(result$blocked)) 15158332L else if (isTRUE(result$published)) 3066993L else 3447003L

  failed_checks <- Filter(function(ch) !isTRUE(ch$pass) && isTRUE(ch$fatal), result$checks)
  failed_text <- if (length(failed_checks)) {
    paste(vapply(failed_checks, function(ch) sprintf("**%s (%s):** %s", ch$id, ch$name, ch$summary), character(1)),
          collapse = "\n")
  } else {
    "None (all fatal assertions passed)"
  }

  warn_text <- if (length(warns)) {
    paste(head(warns, 5), collapse = "\n")
  } else {
    "None in run window"
  }
  if (nchar(warn_text) > 950) warn_text <- paste0(substr(warn_text, 1, 950), "...")

  fields <- list(
    list(name = "Status", value = sprintf("`%s`", status_label), inline = TRUE),
    list(name = "Active Slate", value = sprintf("`%s`", ifelse(is.na(slate), "<NA>", slate)), inline = TRUE),
    list(name = "Total Games", value = sprintf("`%s`", ifelse(is.na(tot_games), "<NA>", tot_games)), inline = TRUE),
    list(name = "Fatal Gate Failures", value = failed_text, inline = FALSE),
    list(name = "Stage [WARN]/[FAIL] Lines", value = paste0("```\n", warn_text, "\n```"), inline = FALSE)
  )

  payload <- list(
    username = "NBA Quant Terminal",
    embeds = list(
      list(
        title = paste("NBA Web Publish Gate \u2022", status_label),
        description = sprintf("Run start: `%s` | Passed: `%s`",
                              if (is.na(result$run_start)) "<undetected>" else format(result$run_start, "%Y-%m-%d %H:%M:%S"),
                              paste(result$assertions_passed, collapse = ", ")),
        color = color,
        fields = fields,
        footer = list(text = paste("tools/publish_web.R \u2022", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
      )
    )
  )

  if (!nzchar(webhook_url)) {
    message(sprintf(">>> publish_web: NBA_DISCORD_WEBHOOK / DISCORD_WEBHOOK_URL not set; skipping Discord notification (status=%s, slate=%s, total_games=%s, warnings=%d).",
                    status_label, ifelse(is.na(slate), "NA", slate), ifelse(is.na(tot_games), "NA", tot_games), length(warns)))
    return(invisible(FALSE))
  }

  if (!requireNamespace("httr", quietly = TRUE)) {
    message(">>> [WARN] publish_web: httr not installed; cannot post Discord notification.")
    return(invisible(FALSE))
  }

  res <- tryCatch(
    httr::POST(webhook_url, body = payload, encode = "json", httr::timeout(6)),
    error = function(e) list(status_code = 500L, message = conditionMessage(e))
  )
  ok <- !is.null(res$status_code) && res$status_code %in% c(200L, 204L)
  if (ok) {
    message(sprintf(">>> publish_web: posted deploy outcome to NBA_DISCORD_WEBHOOK (status_code=%s).", res$status_code))
  } else {
    message(sprintf(">>> [WARN] publish_web: Discord webhook POST did not return 200/204 (status_code=%s).", res$status_code))
  }
  invisible(ok)
}

# ------------------------------------------------------------------------------
# GitHub issue notification for a blocked live publish (NBA_analytics#145).
#
# The Discord path above needs a webhook that is not set on the host, so a
# blocked 09:00 run went unnoticed for ~100 minutes. This reports the block
# where the owner already gets notified: a GitHub issue labelled
# `publish-blocked`, through the host's existing `gh` login.
#   * BLOCKED and live: comment on the open `publish-blocked` issue, or (after
#     making sure the label exists) open one. Never a second open one.
#   * Successful live publish: if one is open, comment that publishing has
#     recovered and close it.
#   * Dry runs never call gh (the call sites only fire on live runs, and the
#     notifier refuses a dry-run result as well).
#
# NOTIFICATION NEVER CHANGES THE GATE'S OUTCOME. Every gh failure (binary
# missing, not logged in, no network, non-zero exit, timeout) is caught and
# logged as a `>>> publish_web:` line; nothing here touches `result` or the
# exit code. Each gh call is bounded by system2(timeout = .PW_GH_TIMEOUT_SEC).
#
# The gh call is injectable (`runner`, and publish_web(gh_runner = )) so the
# tests drive this with a recording fake and never touch GitHub. A runner is
# function(args) -> list(status = <int>, out = <character>).
#
# The repo is private, but issue text still leaves this machine (GitHub email
# and mobile notifications, and anyone later given access), so every line goes
# through .pw_sanitize_public(), which strips the repo root, the home
# directory, any remaining absolute path, the host name and the user name.
# ------------------------------------------------------------------------------
.PW_GH_REPO        <- "kailot-harris/NBA_analytics"
.PW_GH_LABEL       <- "publish-blocked"
.PW_GH_TIMEOUT_SEC <- 60
.PW_GH_FALLBACK    <- "C:/Program Files/GitHub CLI/gh.exe"

# Task Scheduler's PATH may not include gh: NBA_GH_BIN override, then PATH,
# then the host's install location. "" when none exists.
.pw_gh_bin <- function() {
  override <- Sys.getenv("NBA_GH_BIN", "")
  if (nzchar(override)) return(if (file.exists(override)) override else "")
  on_path <- unname(Sys.which("gh"))
  if (nzchar(on_path)) return(on_path)
  if (file.exists(.PW_GH_FALLBACK)) return(.PW_GH_FALLBACK)
  ""
}

.pw_gh_default_runner <- function(args) {
  gh <- .pw_gh_bin()
  if (!nzchar(gh)) stop("gh CLI not found (checked NBA_GH_BIN, PATH and ", .PW_GH_FALLBACK, ")")
  old <- Sys.getenv(c("GH_PROMPT_DISABLED", "GH_NO_UPDATE_NOTIFIER"), unset = NA)
  on.exit({
    for (nm in names(old)) if (is.na(old[[nm]])) Sys.unsetenv(nm) else do.call(Sys.setenv, as.list(old[nm]))
  }, add = TRUE)
  Sys.setenv(GH_PROMPT_DISABLED = "1", GH_NO_UPDATE_NOTIFIER = "1")
  out <- suppressWarnings(system2(gh, shQuote(args), stdout = TRUE, stderr = TRUE,
                                  timeout = .PW_GH_TIMEOUT_SEC))
  st <- attr(out, "status")
  list(status = if (is.null(st)) 0L else as.integer(st),
       out = if (is.null(out)) character(0) else as.character(out))
}

.pw_regex_escape <- function(s) gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", s, perl = TRUE)

# Strip machine-specific detail from text bound for the GitHub issue tracker.
.pw_sanitize_public <- function(x,
                                repo_root = c(.pw_repo_root(), if (exists("PROJECT_DIR")) PROJECT_DIR),
                                home = c(Sys.getenv("USERPROFILE"), Sys.getenv("HOME"), path.expand("~")),
                                host = c(Sys.info()[["nodename"]], Sys.getenv("COMPUTERNAME")),
                                user = c(Sys.info()[["user"]], Sys.getenv("USERNAME"))) {
  if (!length(x)) return(character(0))
  x <- as.character(x)
  x[is.na(x)] <- ""
  variants <- function(p) {
    p <- p[!is.na(p) & nzchar(p)]
    if (!length(p)) return(character(0))
    fwd <- gsub("\\\\", "/", p)
    v <- unique(c(fwd, gsub("/", "\\\\", fwd), gsub("/", "\\\\\\\\", fwd)))
    v[order(nchar(v), decreasing = TRUE)]
  }
  replace_paths <- function(x, paths, placeholder) {
    for (p in variants(paths)) x <- gsub(.pw_regex_escape(p), placeholder, x, perl = TRUE, ignore.case = TRUE)
    x
  }
  # Longest first: the repo root lives under the home directory.
  x <- replace_paths(x, repo_root, "<repo>")
  x <- replace_paths(x, home, "<home>")
  # Any absolute path left over (another drive, a temp dir, a profile path).
  x <- gsub("(?<![A-Za-z0-9])[A-Za-z]:[\\\\/][^\\s'\"`<>|]*", "<path>", x, perl = TRUE)
  x <- gsub("(?<![A-Za-z0-9._-])/(?:home|Users)/[^\\s/'\"`<>|]+", "<home>", x, perl = TRUE)
  for (w in unique(c(host, user))) {
    if (is.na(w) || nchar(w) < 2L) next
    x <- gsub(sprintf("(?<![A-Za-z0-9])%s(?![A-Za-z0-9])", .pw_regex_escape(w)),
              if (w %in% host) "<host>" else "<user>", x, perl = TRUE, ignore.case = TRUE)
  }
  x
}

.pw_run_date <- function(result) {
  if (!is.null(result$run_start) && !is.na(result$run_start)) format(result$run_start, "%Y-%m-%d") else format(Sys.Date())
}

.pw_failed_fatal <- function(result) {
  Filter(function(ch) !isTRUE(ch$pass) && isTRUE(ch$fatal), result$checks)
}

.pw_gh_issue_title <- function(result) {
  ids <- vapply(.pw_failed_fatal(result), function(ch) as.character(ch$id), character(1))
  .pw_sanitize_public(sprintf("Publish gate blocked on %s: assertion%s %s",
                              .pw_run_date(result), if (length(ids) == 1L) "" else "s",
                              if (length(ids)) paste(ids, collapse = ", ") else "<none recorded>"))
}

.pw_gh_issue_body <- function(result, heading = "The NBA web publish gate blocked a live run") {
  fence <- function(lines) c("```", gsub("```", "'''", lines, fixed = TRUE), "```")
  run_time <- if (!is.null(result$run_start) && !is.na(result$run_start)) format(result$run_start, "%Y-%m-%d %H:%M") else "<undetected>"
  failed <- .pw_failed_fatal(result)
  body <- c(sprintf("## %s (%s)", heading, .pw_run_date(result)), "",
            sprintf("Run start: `%s`. Nothing was published; the live site still shows the last published data.", run_time),
            "", "### Failing fatal assertions", "")
  if (!length(failed)) body <- c(body, "- none recorded")
  for (ch in failed) body <- c(body, sprintf("- **%s** (%s): %s", ch$id, ch$name, ch$summary))
  for (ch in failed) {
    detail <- trimws(as.character(unlist(ch$detail)), which = "right")
    detail <- detail[nzchar(trimws(detail))]
    if (!length(detail)) next
    body <- c(body, "", sprintf("#### %s: first lines of output", ch$id), "", fence(head(detail, 15)))
    if (length(detail) > 15) body <- c(body, sprintf("(%d more line(s) in the local log)", length(detail) - 15))
  }
  warns <- as.character(unlist(result$stage_warnings))
  body <- c(body, "", sprintf("### Stage warnings (%d in the run window%s)", length(warns),
                              if (length(warns) > 5) ", first 5 shown" else ""), "")
  body <- c(body, if (length(warns)) fence(head(warns, 5)) else "None in the run window.")
  body <- c(body, "", "---",
            sprintf("Posted by `tools/publish_web.R` (#145). This issue is closed automatically by the next successful live publish."))
  paste(.pw_sanitize_public(body), collapse = "\n")
}

.pw_gh_recovery_body <- function(result) {
  run_time <- if (!is.null(result$run_start) && !is.na(result$run_start)) format(result$run_start, "%Y-%m-%d %H:%M") else "<undetected>"
  paste(.pw_sanitize_public(c(
    sprintf("## Publishing recovered (%s)", .pw_run_date(result)), "",
    sprintf("The run starting `%s` passed every fatal assertion and pushed to `%s`. Closing.",
            run_time, if (is.null(result$publish_branch)) "main" else result$publish_branch),
    "", "---", "Posted by `tools/publish_web.R` (#145).")), collapse = "\n")
}

.pw_notify_github <- function(result, runner = NULL, repo = .PW_GH_REPO, label = .PW_GH_LABEL) {
  if (is.null(runner)) runner <- .pw_gh_default_runner
  tryCatch({
    if (isTRUE(result$dry_run)) return(invisible("skipped: dry run"))
    blocked   <- isTRUE(result$blocked)
    published <- isTRUE(result$published)
    if (!blocked && !published) return(invisible("skipped: not a live outcome"))

    gh <- function(args, what) {
      res <- tryCatch(runner(args), error = function(e) list(status = NA_integer_, out = conditionMessage(e)))
      st <- suppressWarnings(as.integer(res$status))
      if (length(st) != 1L || is.na(st) || st != 0L) {
        stop(sprintf("gh %s failed (exit %s%s): %s", what,
                     if (length(st) == 1L && !is.na(st)) st else "NA",
                     if (identical(st, 124L)) ", timed out" else "",
                     paste(head(as.character(res$out), 3), collapse = " | ")), call. = FALSE)
      }
      as.character(res$out)
    }
    with_body <- function(text, f) {
      path <- tempfile("publish_web_gh_", fileext = ".md")
      on.exit(unlink(path), add = TRUE)
      writeLines(text, path, useBytes = TRUE)
      f(path)
    }

    open_out <- gh(c("issue", "list", "--repo", repo, "--label", label, "--state", "open",
                     "--json", "number", "--jq", ".[].number", "--limit", "20"), "issue list")
    open_nums <- suppressWarnings(as.integer(trimws(open_out)))
    open_nums <- sort(open_nums[!is.na(open_nums)])
    existing <- if (length(open_nums)) open_nums[[1]] else NA_integer_

    if (blocked) {
      if (!is.na(existing)) {
        with_body(.pw_gh_issue_body(result, "Blocked again"), function(p)
          gh(c("issue", "comment", existing, "--repo", repo, "--body-file", p), "issue comment"))
        message(sprintf(">>> publish_web: commented on open %s issue #%d.", label, existing))
        return(invisible(sprintf("commented #%d", existing)))
      }
      labels <- gh(c("label", "list", "--repo", repo, "--search", label, "--json", "name",
                     "--jq", ".[].name", "--limit", "100"), "label list")
      if (!(label %in% trimws(labels))) {
        gh(c("label", "create", label, "--repo", repo, "--color", "B60205",
             "--description", "The publish gate blocked a live run (opened by tools/publish_web.R)"),
           "label create")
        message(sprintf(">>> publish_web: created the %s label.", label))
      }
      out <- with_body(.pw_gh_issue_body(result), function(p)
        gh(c("issue", "create", "--repo", repo, "--title", .pw_gh_issue_title(result),
             "--label", label, "--body-file", p), "issue create"))
      message(sprintf(">>> publish_web: opened %s issue %s", label, paste(tail(out, 1), collapse = "")))
      return(invisible("created"))
    }

    # Successful live publish.
    if (is.na(existing)) return(invisible("nothing open"))
    with_body(.pw_gh_recovery_body(result), function(p)
      gh(c("issue", "comment", existing, "--repo", repo, "--body-file", p), "issue comment"))
    gh(c("issue", "close", existing, "--repo", repo), "issue close")
    message(sprintf(">>> publish_web: publishing recovered; closed %s issue #%d.", label, existing))
    invisible(sprintf("closed #%d", existing))
  }, error = function(e) {
    message(sprintf(">>> [WARN] publish_web: GitHub %s notification skipped: %s",
                    label, conditionMessage(e)))
    invisible("failed")
  })
}

# ------------------------------------------------------------------------------
# Pipeline-crash alert (NBA_analytics#161, follow-up to #145).
#
# #145 covered the gate only. When run_full_pipeline.R itself exits non-zero,
# schedule_daily.bat never reaches publish_web.R, so nothing is opened and the
# site goes stale silently. tools/notify_pipeline_failure.R (called from the
# .bat's failure branch) calls .pw_notify_pipeline_failure() below: it opens one
# `pipeline-failed` issue, or comments on the open one, carrying a sanitized
# tail of the run log. Same contract as .pw_notify_github(): the gh runner is
# injectable, every line goes through .pw_sanitize_public(), and nothing here
# can throw or touch an exit code. The issue is closed by hand once the
# pipeline is healthy again (a recurring crash comments on it instead of
# opening a new one each night).
# ------------------------------------------------------------------------------
.PW_GH_LABEL_CRASH <- "pipeline-failed"

.pw_pipeline_failure_body <- function(exit_code, log_tail, when, heading) {
  fence <- function(lines) c("```", gsub("```", "'''", lines, fixed = TRUE), "```")
  body <- c(sprintf("## %s (%s)", heading, format(when, "%Y-%m-%d %H:%M")), "",
            sprintf("`run_full_pipeline.R` exited with code `%s` before the publish gate ran.", exit_code),
            "Nothing was published; the live site still shows the last published data.", "",
            sprintf("### Last %d line(s) of the run log", length(log_tail)), "",
            if (length(log_tail)) fence(log_tail) else "The run log could not be read.",
            "", "---",
            "Posted by `tools/notify_pipeline_failure.R` (#161). Close this issue once a scheduled run is healthy again.")
  paste(.pw_sanitize_public(body), collapse = "\n")
}

.pw_notify_pipeline_failure <- function(exit_code, log_path = NULL, runner = NULL,
                                        repo = .PW_GH_REPO, label = .PW_GH_LABEL_CRASH,
                                        tail_lines = 40L, when = Sys.time()) {
  if (is.null(runner)) runner <- .pw_gh_default_runner
  tryCatch({
    log_tail <- character(0)
    if (!is.null(log_path) && file.exists(log_path)) {
      log_tail <- tryCatch(utils::tail(readLines(log_path, warn = FALSE, encoding = "UTF-8"), tail_lines),
                           error = function(e) character(0))
      log_tail <- log_tail[nzchar(trimws(log_tail))]
    }
    gh <- function(args, what) {
      res <- tryCatch(runner(args), error = function(e) list(status = NA_integer_, out = conditionMessage(e)))
      st <- suppressWarnings(as.integer(res$status))
      if (length(st) != 1L || is.na(st) || st != 0L) {
        stop(sprintf("gh %s failed (exit %s): %s", what, if (length(st) == 1L && !is.na(st)) st else "NA",
                     paste(head(as.character(res$out), 3), collapse = " | ")), call. = FALSE)
      }
      as.character(res$out)
    }
    with_body <- function(text, f) {
      path <- tempfile("pipeline_failed_gh_", fileext = ".md")
      on.exit(unlink(path), add = TRUE)
      writeLines(text, path, useBytes = TRUE)
      f(path)
    }
    open_out <- gh(c("issue", "list", "--repo", repo, "--label", label, "--state", "open",
                     "--json", "number", "--jq", ".[].number", "--limit", "20"), "issue list")
    open_nums <- sort(suppressWarnings(as.integer(trimws(open_out))))
    open_nums <- open_nums[!is.na(open_nums)]
    if (length(open_nums)) {
      with_body(.pw_pipeline_failure_body(exit_code, log_tail, when, "Failed again"), function(p)
        gh(c("issue", "comment", open_nums[[1]], "--repo", repo, "--body-file", p), "issue comment"))
      message(sprintf(">>> notify_pipeline_failure: commented on open %s issue #%d.", label, open_nums[[1]]))
      return(invisible(sprintf("commented #%d", open_nums[[1]])))
    }
    labels <- gh(c("label", "list", "--repo", repo, "--search", label, "--json", "name",
                   "--jq", ".[].name", "--limit", "100"), "label list")
    if (!(label %in% trimws(labels))) {
      gh(c("label", "create", label, "--repo", repo, "--color", "B60205",
           "--description", "run_full_pipeline.R crashed before the publish gate (opened by tools/notify_pipeline_failure.R)"),
         "label create")
    }
    title <- .pw_sanitize_public(sprintf("Pipeline crashed on %s (exit %s)", format(when, "%Y-%m-%d"), exit_code))
    out <- with_body(.pw_pipeline_failure_body(exit_code, log_tail, when, "The NBA pipeline crashed before the publish gate"),
                     function(p) gh(c("issue", "create", "--repo", repo, "--title", title,
                                      "--label", label, "--body-file", p), "issue create"))
    message(sprintf(">>> notify_pipeline_failure: opened %s issue %s", label, paste(tail(out, 1), collapse = "")))
    invisible("created")
  }, error = function(e) {
    message(sprintf(">>> [WARN] notify_pipeline_failure: GitHub %s notification skipped: %s", label, conditionMessage(e)))
    invisible("failed")
  })
}

# ------------------------------------------------------------------------------
# publish_web() - the explicitly-callable entry point.
#
# Deliberately NOT guarded by a `sys.nframe() == 0`-style top-level-only check:
# that is a documented silent-no-op failure mode across this estate (it is
# issue #1 in this very repo), because source()ing from an orchestrator changes
# frame depth, so the guard no-ops while still reporting success. Callers invoke
# this function explicitly; the CLI wrapper at the bottom keys off
# commandArgs(), not frame depth.
# ------------------------------------------------------------------------------
publish_web <- function(dry_run = TRUE,
                        run_start = NULL,
                        season = MATCHUPS_HOOPR_SEASON,
                        publish_branch = "main",
                        fail_on_exporter_warnings = FALSE,
                        skip_contracts = FALSE,
                        commit_message = NULL,
                        gh_runner = NULL) {
  # gh_runner: injectable gh call for .pw_notify_github() (tests only); NULL
  # means the real gh CLI. It never affects the gate's decision.

  repo_root <- .pw_repo_root()
  log_lines <- if (file.exists(LOG_FILE)) readLines(LOG_FILE, warn = FALSE) else character(0)
  if (is.null(run_start)) run_start <- .pw_detect_run_start(log_lines)
  if (is.null(commit_message)) {
    commit_message <- sprintf("Publish NBA web artifacts from the %s pipeline run",
                              if (is.na(run_start)) format(Sys.Date()) else format(run_start, "%Y-%m-%d %H:%M"))
  }

  synced_media <- .pw_sync_media(dry_run = dry_run)
  .pw_refresh_manifest(dry_run, schedule_path = CACHE_MATCHUPS_SCHEDULE(season))

  checks <- list(
    .assert_mtime_freshness(run_start),
    .assert_slate_agreement(season),
    .assert_nonempty_diff(repo_root),
    .assert_publish_branch(repo_root, publish_branch),
    .assert_log_scan(log_lines, fail_on_exporter_warnings),
    .assert_payload_provenance(run_start),
    .assert_web_contracts(skip_contracts),
    .assert_manifest_and_coverage(WEB_DATA_DIR, schedule_path = CACHE_MATCHUPS_SCHEDULE(season)),
    .assert_lifecycle(WEB_DATA_DIR)
  )

  passed  <- vapply(checks, function(ch) isTRUE(ch$pass), logical(1))
  fatal   <- vapply(checks, function(ch) isTRUE(ch$fatal), logical(1))
  blocked <- any(!passed & fatal)

  # ---- report ----------------------------------------------------------------
  cat("\n================================================================\n")
  cat(sprintf("NBA web publish gate  [%s]\n",
              if (dry_run) "DRY RUN - nothing will be published" else "LIVE PUBLISH"))
  cat("================================================================\n")
  cat(sprintf("  repo root        : %s\n", ifelse(is.na(repo_root), "<not a git repo>", repo_root)))
  cat(sprintf("  publish branch   : %s\n", publish_branch))
  cat(sprintf("  hoopR season     : %d\n", as.integer(season)))
  cat(sprintf("  pipeline log     : %s (%d lines)\n", LOG_FILE, length(log_lines)))
  cat(sprintf("  run start        : %s\n",
              ifelse(is.na(run_start), "<undetected>", format(run_start, "%Y-%m-%d %H:%M:%S"))))
  cat(sprintf("  schedule cache   : %s\n", CACHE_MATCHUPS_SCHEDULE(season)))
  cat("\n-- Assertions --------------------------------------------------\n")
  for (ch in checks) {
    cat(sprintf("  [%s] %s. %s - %s\n",
                if (ch$pass) "PASS" else if (ch$fatal) "FAIL" else "WARN",
                ch$id, ch$name, ch$summary))
    cat(paste0(ch$detail, collapse = "\n"), "\n", sep = "")
  }

  cat("\n-- Would publish -----------------------------------------------\n")
  cat(sprintf("  %d dataset(s) asserted from %s:\n", length(WEB_DATA_FILES), WEB_DATA_DIR))
  for (f in WEB_DATA_FILES) cat(sprintf("    - %s\n", basename(f)))
  cat(sprintf("  commit message   : %s\n", commit_message))
  cat(sprintf("  push sequence    : commit -> fetch + rebase onto origin -> push NBA_analytics %s (deploy belongs to the aggregator's sync-sports.yml)\n",
              publish_branch))

  cat("\n-- Verdict -----------------------------------------------------\n")
  if (blocked) {
    cat("  BLOCKED - at least one fatal assertion failed. PUBLISHING NOTHING.\n")
    cat("  Yesterday's correct site stays up rather than a half-updated one.\n")
    for (ch in checks[!passed & fatal]) {
      message(sprintf(">>> [WARN] publish_web: assertion %s FAILED (%s) - publishing nothing. %s",
                      ch$id, ch$name, ch$summary))
    }
  } else if (dry_run) {
    cat("  ALL ASSERTIONS PASSED - a live run would publish the artifacts listed above.\n")
  } else {
    cat("  ALL ASSERTIONS PASSED - proceeding to commit and push.\n")
  }
  cat("================================================================\n\n")

  result <- list(
    dry_run = dry_run, blocked = blocked, run_start = run_start, season = as.integer(season),
    repo_root = repo_root, publish_branch = publish_branch,
    assertions_passed = as.character(vapply(checks[passed], function(ch) ch$id, character(1))),
    assertions_failed = as.character(vapply(checks[!passed], function(ch) ch$id, character(1))),
    slate_computed = checks[[2]]$computed,
    slate_published = checks[[2]]$published,
    publish_branch_actual = checks[[4]]$branch,
    stage_warnings = checks[[5]]$warnings,
    stale_payloads = checks[[6]]$stale,
    unstamped_payloads = checks[[6]]$unstamped,
    pending_changes = checks[[3]]$changed,
    synced_media = synced_media,
    contracts_pass = isTRUE(checks[[7]]$pass),
    manifest_pass = isTRUE(checks[[8]]$pass),
    lifecycle_pass = isTRUE(checks[[9]]$pass),
    checks = checks, published = FALSE, steps = list()
  )

  if (blocked || dry_run) {
    if (blocked && !dry_run) {
      .pw_notify_discord(result)
      .pw_notify_github(result, runner = gh_runner)
    }
    return(invisible(result))
  }

  result$steps <- .pw_do_publish(repo_root, checks[[3]]$paths, commit_message, publish_branch)
  result$published <- TRUE
  message(sprintf(">>> publish_web: web artifacts committed and pushed to NBA_analytics %s. The site changes when the aggregator's sync-sports.yml next pulls; this script does not deploy.",
                  publish_branch))
  .pw_notify_discord(result)
  .pw_notify_github(result, runner = gh_runner)
  invisible(result)
}

# ------------------------------------------------------------------------------
# CLI wrapper. Keyed off commandArgs() - i.e. "was I invoked as
# `Rscript tools/publish_web.R`" - NOT off sys.nframe(). source()ing this file
# from another script or from `Rscript -e` defines the function and runs
# nothing.
#   Rscript tools/publish_web.R                  # dry run (default)
#   Rscript tools/publish_web.R --publish        # live publish
#   Rscript tools/publish_web.R --strict-warnings
#   Rscript tools/publish_web.R --skip-contracts   # G cannot run; say so loudly
# Exit status: 0 only when nothing fatal failed; 1 on any fatal failure, so a
# scheduled caller can branch on it.
# ------------------------------------------------------------------------------
local({
  argv <- commandArgs(trailingOnly = FALSE)
  files <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (!any(grepl("publish_web\\.R$", files))) return(invisible(NULL))
  opts <- commandArgs(trailingOnly = TRUE)
  known_opts <- c("--publish", "--strict-warnings", "--skip-contracts")
  unknown_opts <- setdiff(opts, known_opts)
  if (length(unknown_opts)) {
    stop(sprintf(
      "publish_web.R: unknown CLI option(s): %s. Valid options: %s",
      paste(shQuote(unknown_opts), collapse = ", "),
      paste(known_opts, collapse = ", ")
    ), call. = FALSE)
  }
  res <- publish_web(dry_run = !("--publish" %in% opts),
                     fail_on_exporter_warnings = "--strict-warnings" %in% opts,
                     skip_contracts = "--skip-contracts" %in% opts)
  quit(status = if (isTRUE(res$blocked)) 1L else 0L)
})
