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
# ASSERTION C - non-empty diff under the published tree.
# Resolved against the RUNTIME git root, never a hardcoded path, so a worktree
# is reported against its own repository.
# ------------------------------------------------------------------------------
.assert_nonempty_diff <- function(repo_root) {
  if (is.na(repo_root)) {
    return(list(id = "C", name = "non-empty diff under web/public/data",
                pass = FALSE, fatal = TRUE, changed = character(0), paths = character(0),
                detail = "    could not resolve a git repository for the working directory",
                summary = "no git repo"))
  }
  rel <- .pw_rel_to_repo(WEB_DATA_DIR, repo_root)
  r <- .pw_git(repo_root, c("status", "--porcelain", "--", rel))
  changed <- if (r$ok) r$out[nzchar(r$out)] else character(0)
  list(id = "C", name = "non-empty diff under web/public/data",
       pass = length(changed) > 0, fatal = TRUE, changed = changed, paths = rel,
       detail = if (length(changed)) paste0("    ", changed)
                else sprintf("    CLEAN against HEAD - nothing to publish (repo: %s)", repo_root),
       summary = sprintf("%d pending change(s) under %s", length(changed), rel))
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
# Commit / push sequence. ONLY reached when dry_run = FALSE and every fatal
# assertion passed. Commits the published tree and pushes NBA_analytics --
# nothing more. The deploy belongs to the aggregator's sync-sports.yml.
# ------------------------------------------------------------------------------
.pw_do_publish <- function(repo_root, rel_paths, commit_message) {
  steps <- list()
  record <- function(label, res) {
    steps[[length(steps) + 1L]] <<- list(label = label, ok = res$ok, out = res$out)
    if (!res$ok) stop(sprintf("publish_web: step failed: %s\n%s", label,
                              paste(res$out, collapse = "\n")))
    invisible(TRUE)
  }
  record("git add web/public/data",
         .pw_git(repo_root, c("add", "--", rel_paths)))
  record("git commit (NBA_analytics)",
         .pw_git(repo_root, c("commit", "-m", shQuote(commit_message))))
  record("git push origin HEAD (NBA_analytics)",
         .pw_git(repo_root, c("push", "origin", "HEAD")))
  steps
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
                        commit_message = NULL) {

  repo_root <- .pw_repo_root()
  log_lines <- if (file.exists(LOG_FILE)) readLines(LOG_FILE, warn = FALSE) else character(0)
  if (is.null(run_start)) run_start <- .pw_detect_run_start(log_lines)
  if (is.null(commit_message)) {
    commit_message <- sprintf("Publish NBA web artifacts from the %s pipeline run",
                              if (is.na(run_start)) format(Sys.Date()) else format(run_start, "%Y-%m-%d %H:%M"))
  }

  checks <- list(
    .assert_mtime_freshness(run_start),
    .assert_slate_agreement(season),
    .assert_nonempty_diff(repo_root),
    .assert_publish_branch(repo_root, publish_branch),
    .assert_log_scan(log_lines, fail_on_exporter_warnings),
    .assert_payload_provenance(run_start),
    .assert_web_contracts(skip_contracts)
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
  cat(sprintf("  push sequence    : commit -> push NBA_analytics %s (deploy belongs to the aggregator's sync-sports.yml)\n",
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
    contracts_pass = isTRUE(checks[[length(checks)]]$pass),
    checks = checks, published = FALSE, steps = list()
  )

  if (blocked || dry_run) return(invisible(result))

  result$steps <- .pw_do_publish(repo_root, checks[[3]]$paths, commit_message)
  result$published <- TRUE
  message(sprintf(">>> publish_web: web artifacts committed and pushed to NBA_analytics %s. The site changes when the aggregator's sync-sports.yml next pulls; this script does not deploy.",
                  publish_branch))
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
  res <- publish_web(dry_run = !("--publish" %in% opts),
                     fail_on_exporter_warnings = "--strict-warnings" %in% opts,
                     skip_contracts = "--skip-contracts" %in% opts)
  quit(status = if (isTRUE(res$blocked)) 1L else 0L)
})
