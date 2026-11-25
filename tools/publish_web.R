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
# THE ASSERTIONS
#   A  mtime freshness - every entry of config.R's WEB_DATA_FILES has an mtime
#      later than the run start. The filenames are NEVER re-typed here; they
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
#   F  payload provenance - reads the embedded ISO-8601 UTC `generated_at`
#      stamp out of every WEB_DATA_FILES payload and requires it to be no older
#      than the run start. Catches verbatim-republish fallbacks and file copies
#      that advance mtime without regenerating the payload content.
#   G  web contracts  - runs the web suite's `contracts` stage against the
#      UNCOMMITTED payload, so a payload whose numbers disagree with each
#      other cannot be published. Every other assertion here asks when a file
#      was written, whether its bytes changed, what the log said or whose
#      branch it is on; none reads the numbers inside. Ported from WNBA on
#      2026-10-26 -- see this assertion's own header for what prompted it.
#      Fatal, with web/tests/known-issues.json as the documented escape valve.
#   L  lifecycle (NFL_analytics#214) - every top-level web/public/data/*.json
#      (excluding data_manifest.json) carries a valid `lifecycle` in
#      WEB_DATA_LIFECYCLES ("live" | "season_final" | "archived"), and any
#      "season_final" entry carries its freeze metadata and still matches its
#      frozen_sha256. Any file with no or unknown lifecycle FAILS.
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
#   construction, so A fails for every listed file and the exit status is non-zero.
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
#   fatal). It was made non-fatal while coaching_profiles.json was a hand-typed
#   file the exporter republished verbatim, with a benign warning, on every run.
#   Since NFL_analytics#171 that file is built from nflverse data by
#   build_coaching_dataset.R and is a WEB_DATA_FILES member, so a stale copy is
#   caught by A and F and no longer produces an exporter warning. D stays
#   reporting-only because salary_cap_profiles.json can still fall back to a
#   verbatim republish (which F also catches). Its FAILING form is opt-in:
#     Rscript -e "source('tools/publish_web.R'); publish_web(dry_run = TRUE, fail_on_exporter_warnings = TRUE)"
#   It fails whenever the run window holds any exporter [WARN] line. To reproduce a warning that SHOULD always be treated as
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
# Manifest helpers (assertion H). Optional: publish_web.R stays sourceable
# without it; H then falls back to the manifest's own schedule_through_date.
if (file.exists(file.path("tools", "write_data_manifest.R"))) {
  local({
    old <- Sys.getenv("NFL_SKIP_MANIFEST_AUTORUN", NA)
    Sys.setenv(NFL_SKIP_MANIFEST_AUTORUN = "1")
    on.exit(if (is.na(old)) Sys.unsetenv("NFL_SKIP_MANIFEST_AUTORUN") else Sys.setenv(NFL_SKIP_MANIFEST_AUTORUN = old))
    sys.source(file.path("tools", "write_data_manifest.R"), envir = globalenv())
  })
}

# ------------------------------------------------------------------------------
# Small helpers
# ------------------------------------------------------------------------------
.pw_git <- function(repo, args) {
  # cmd.exe (and Task Scheduler's .bat-launched non-interactive session) does not
  # resolve HOME the way Git Bash does, so git can't find ~/.gitconfig and refuses
  # to commit with "unable to auto-detect email address". Pass identity explicitly
  # via -c so commits don't depend on HOME/USERPROFILE resolution in the invoking shell.
  # R on Windows rewrites HOME to "<USERPROFILE>/Documents", while Git for
  # Windows stores ~/.gitconfig at "<USERPROFILE>/.gitconfig". Point HOME at
  # USERPROFILE when .gitconfig lives there so both git config and git commit
  # resolve the user's global git config and credential helper.
  up <- Sys.getenv("USERPROFILE", "")
  if (nzchar(up) && file.exists(file.path(up, ".gitconfig"))) {
    Sys.setenv(HOME = up)
  }
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
  files <- WEB_DATA_FILES          # <- the names come from config.R ONLY
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
  r <- .pw_git(repo_root, c("status", "--porcelain", "--", PIPELINE_OUTPUT_DIRS))
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
# ASSERTION F - payload provenance.
#
# Reads the `generated_at` stamp out of each WEB_DATA_FILES payload that has
# one and requires it to be no older than the run start. Verbatim republish
# fallbacks (republish_json_verbatim) advance the file's mtime while preserving
# the older embedded `generated_at`, so Assertion F structurally catches what
# an mtime check (Assertion A) cannot.
#
# Only the top of each file is read. `generated_at` is written as the first
# key of the root object (or first array element), so reading the first 4096
# bytes avoids slurping large JSON documents through jsonlite.
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
  as.POSIXct(val, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
}

.pw_payload_is_array <- function(path) {
  if (!file.exists(path)) return(FALSE)
  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw <- readBin(con, "raw", n = 64L)
  txt <- trimws(rawToChar(raw[raw != as.raw(0)]))
  startsWith(sub("^﻿", "", txt), "[")
}

.assert_payload_provenance <- function(run_start) {
  files <- WEB_DATA_FILES
  rows <- character(0)
  stale <- character(0)
  unstamped <- character(0)
  catalogs <- character(0)
  for (f in files) {
    # A top-level ARRAY payload (visual_media_index.json) is a catalog: each
    # item carries the time that item was made, and items legitimately outlive
    # a run (a GIF re-renders weekly, a still image may never). There is no
    # run-level stamp to check, so F does not speak for it; Assertion A still
    # requires the catalog itself to be rewritten this run, and H judges its
    # age by the newest item (write_data_manifest.R). Reading item [0] here
    # blocked every publish once #192 made per-item stamps honest.
    if (.pw_payload_is_array(f)) {
      catalogs <- c(catalogs, basename(f))
      rows <- c(rows, sprintf("    %-9s %-40s per-item stamps; rebuild checked by A", "[CATALOG]", basename(f)))
      next
    }
    g <- .pw_payload_generated_at(f)
    if (is.na(g)) {
      unstamped <- c(unstamped, basename(f))
      next
    }
    fresh <- !is.na(run_start) && g >= run_start
    if (!fresh) stale <- c(stale, basename(f))
    rows <- c(rows, sprintf("    %-9s %-40s generated_at=%s",
                            if (fresh) "[FRESH]" else "[STALE]", basename(f),
                            format(g, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")))
  }
  if (length(unstamped)) {
    rows <- c(rows,
              sprintf("    [NO STAMP] %d payload(s) carry no generated_at, so F cannot speak for them:",
                      length(unstamped)),
              paste0("               ", unstamped))
  }
  list(id = "F", name = "payload provenance (embedded generated_at at or after run start)",
       pass = length(stale) == 0 && length(unstamped) == 0, fatal = TRUE,
       stale = stale, unstamped = unstamped,
       detail = rows,
       summary = sprintf("%d stamped payload(s) fresh, %d stale, %d carry no stamp",
                         length(files) - length(stale) - length(unstamped) - length(catalogs),
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
# Lettered G in all three repos even though this file has A to E, so the
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
# ASSERTION I - landing digest (NFL_analytics#182, front-office#200).
#
# web/public/data/landing_digest.json is what the front-office landing page
# reads. H already requires it in the manifest; I checks the payload itself:
# every top-level contract field present, schema_version 1, sport "nfl",
# movers windows "1"/"7"/"21", generated_at at or after run start (when the
# run start is known), every `hit` consistent with the shared hit rule, and no
# betting vocabulary anywhere in the bytes.
# Reproduce a failure: delete a top-level key from the digest, then
#   Rscript -e "source('tools/publish_web.R'); publish_web(dry_run = TRUE)"
# ------------------------------------------------------------------------------
.PW_DIGEST_FIELDS <- c("schema_version", "sport", "generated_at", "slate_date", "season_state",
                       "next_milestone", "today", "yesterday", "record", "calibration", "movers")
.PW_BETTING_RE <- "odds|spread|moneyline|over/under|sportsbook|wager"

.assert_landing_digest <- function(run_start = NA, path = file.path(WEB_DATA_DIR, "landing_digest.json")) {
  res <- function(pass, summary, detail) list(id = "I", name = "landing digest contract",
                                              pass = pass, fatal = TRUE, summary = summary, detail = detail)
  if (!file.exists(path)) return(res(FALSE, "landing_digest.json is absent",
                                     "    [MISSING]  run Rscript tools/build_landing_digest.R"))
  txt <- paste(readLines(path, warn = FALSE), collapse = "
")
  d <- tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(d)) return(res(FALSE, "landing_digest.json is not valid JSON", "    [BAD]      unparseable"))
  problems <- character(0)
  miss <- setdiff(.PW_DIGEST_FIELDS, names(d))
  if (length(miss)) problems <- c(problems, sprintf("missing field(s): %s", paste(miss, collapse = ", ")))
  if (!identical(as.integer(d$schema_version), 1L)) problems <- c(problems, "schema_version is not 1")
  if (!identical(d$sport, "nfl")) problems <- c(problems, "sport is not \"nfl\"")
  if (!all(c("1", "7", "21") %in% names(d$movers$windows))) problems <- c(problems, "movers.windows lacks 1/7/21")
  g <- as.POSIXct(d$generated_at %||% NA_character_, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  if (is.na(g)) problems <- c(problems, "generated_at missing or not ISO-8601 UTC")
  else if (!is.null(run_start) && !is.na(run_start) && g < run_start) problems <- c(problems, "generated_at predates the run start")
  for (r in d$yesterday) {
    p <- r$home_win_prob
    want <- if (is.null(p) || !isTRUE(r$final) || is.null(r$home_score) || is.null(r$away_score) ||
                r$home_score == r$away_score || p == 0.5) NULL else (p > 0.5) == (r$home_score > r$away_score)
    if (!identical(r$hit, want)) problems <- c(problems, sprintf("%s: hit disagrees with the hit rule", r$game_id))
  }
  if (grepl(.PW_BETTING_RE, tolower(txt))) problems <- c(problems, "betting vocabulary present")
  if (length(problems)) return(res(FALSE, sprintf("%d problem(s)", length(problems)), paste0("    [FAIL]     ", problems)))
  res(TRUE, sprintf("slate %s, %s, %d today / %d yesterday", d$slate_date, d$season_state %||% "null",
                    length(d$today), length(d$yesterday)),
      sprintf("    [OK]       generated_at=%s", d$generated_at))
}

# ------------------------------------------------------------------------------
# ASSERTION H - data manifest completeness + schedule-lag (front-office#102, #191).
#
# web/public/data/data_manifest.json (written by tools/write_data_manifest.R)
# must list EVERY top-level web/public/data/*.json with a valid ISO-8601 UTC
# generated_at. When the schedule's latest completed game date is known
# (recomputed from CACHE_SCHEDULES, else the manifest's own
# schedule_through_date), each non-static dataset's lag
#   lag_days = schedule_through_date - through_date
# must be <= its max_lag_days. lag <= 0 (off-season, or data ahead of the
# schedule cache) passes. static: true with a static_reason is exempt.
# Unknown schedule date => lag is not enforced and the report says so.
# Reproduce a failure: delete or hand-edit data_manifest.json, then
#   Rscript -e "source('tools/publish_web.R'); publish_web(dry_run = TRUE)"
# ------------------------------------------------------------------------------
# Look a check up by its id letter, so adding a check never shifts a lookup.
.pw_check <- function(checks, id) {
  hit <- Filter(function(ch) identical(ch$id, id), checks)
  if (length(hit)) hit[[1]] else list()
}

.pw_manifest_fallback_schedule_date <- function(schedules_path) {
  if (exists("dm_schedule_through_date", mode = "function"))
    return(dm_schedule_through_date(schedules_path))
  NA_character_
}

.assert_manifest_and_coverage <- function(data_dir = WEB_DATA_DIR,
                                          schedule_through_date = .pw_manifest_fallback_schedule_date(CACHE_SCHEDULES)) {
  res <- function(pass, summary, detail, lagging = character(0), missing = character(0)) {
    list(id = "H", name = "data manifest completeness + schedule lag",
         pass = pass, fatal = TRUE, summary = summary, detail = detail,
         lagging = lagging, missing = missing)
  }
  mpath <- file.path(data_dir, "data_manifest.json")
  if (!file.exists(mpath)) {
    return(res(FALSE, "data_manifest.json is absent - cannot account for the payloads",
               "    [MISSING]  data_manifest.json (run Rscript tools/write_data_manifest.R)",
               missing = "data_manifest.json"))
  }
  m <- tryCatch(jsonlite::fromJSON(mpath, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(m) || !is.list(m$datasets)) {
    return(res(FALSE, "data_manifest.json is unreadable or has no datasets map",
               "    [MISSING]  data_manifest.json is not valid manifest JSON",
               missing = "data_manifest.json"))
  }
  iso_ok <- function(x) is.character(x) && length(x) == 1 &&
    grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", x) &&
    !is.na(as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))

  sched <- schedule_through_date
  if (is.null(sched) || is.na(sched)) sched <- if (is.null(m$schedule_through_date)) NA_character_ else m$schedule_through_date
  sched_d <- suppressWarnings(as.Date(sched))

  on_disk <- setdiff(sort(list.files(data_dir, pattern = "\\.json$")), "data_manifest.json")
  rows <- sprintf("    schedule_through_date : %s%s",
                  if (is.na(sched_d)) "<unknown>" else format(sched_d),
                  if (is.na(sched_d)) " (lag not enforced)" else "")
  lagging <- character(0); missing <- character(0)
  for (f in on_disk) {
    e <- m$datasets[[f]]
    if (is.null(e)) {
      missing <- c(missing, f)
      rows <- c(rows, sprintf("    %-10s %-34s not listed in data_manifest.json", "[MISSING]", f))
      next
    }
    if (!iso_ok(e$generated_at)) {
      missing <- c(missing, f)
      rows <- c(rows, sprintf("    %-10s %-34s generated_at missing or not ISO-8601 UTC", "[MISSING]", f))
      next
    }
    if (isTRUE(e$static)) {
      if (is.null(e$static_reason) || !nzchar(e$static_reason)) {
        missing <- c(missing, f)
        rows <- c(rows, sprintf("    %-10s %-34s static: true without a static_reason", "[MISSING]", f))
      } else {
        rows <- c(rows, sprintf("    %-10s %-34s generated_at=%s static (%s)", "[STATIC]", f,
                                e$generated_at, e$static_reason))
      }
      next
    }
    maxlag <- if (is.null(e$max_lag_days)) NA_real_ else as.numeric(e$max_lag_days)
    tds <- if (is.null(e$through_date_source)) "" else e$through_date_source
    if (is.na(maxlag) || !nzchar(tds) || is.null(e$stamp_source)) {
      missing <- c(missing, f)
      rows <- c(rows, sprintf("    %-10s %-34s max_lag_days / through_date_source / stamp_source missing", "[MISSING]", f))
      next
    }
    if (identical(tds, "not_game_dated")) {
      # Content carries no game date: freshness falls back to the generation
      # stamp (never silently passed), and the line says so.
      gd <- as.Date(substr(e$generated_at, 1, 10))
      lag <- if (is.na(sched_d)) NA_real_ else as.numeric(sched_d - gd)
      is_lag <- !is.na(lag) && lag > maxlag
      if (is_lag) lagging <- c(lagging, f)
      rows <- c(rows, sprintf("    %-10s %-34s not game-dated; generated_at=%s lag_days=%s max_lag_days=%d%s",
                              if (is_lag) "[LAGGING]" else "[UNDATED]", f, e$generated_at,
                              if (is.na(lag)) "n/a" else format(max(lag, 0)), as.integer(maxlag),
                              if (is.null(e$coverage_note)) "" else paste0(" (", e$coverage_note, ")")))
      next
    }
    td <- suppressWarnings(as.Date(if (is.null(e$through_date)) NA_character_ else e$through_date))
    if (is.na(td) || !startsWith(tds, "payload:")) {
      missing <- c(missing, f)
      rows <- c(rows, sprintf("    %-10s %-34s through_date missing or not extracted from payload content", "[MISSING]", f))
      next
    }
    lag <- if (is.na(sched_d)) NA_real_ else as.numeric(sched_d - td)
    is_lag <- !is.na(lag) && lag > maxlag
    if (is_lag) lagging <- c(lagging, f)
    rows <- c(rows, sprintf("    %-10s %-34s through_date=%s lag_days=%s max_lag_days=%d",
                            if (is_lag) "[LAGGING]" else "[OK]", f, format(td),
                            if (is.na(lag)) "n/a" else format(max(lag, 0)), as.integer(maxlag)))
  }
  pass <- length(lagging) == 0 && length(missing) == 0
  res(pass,
      sprintf("%d payload(s): %d missing/unstamped, %d lagging the schedule",
              length(on_disk), length(missing), length(lagging)),
      rows, lagging = lagging, missing = missing)
}

# ------------------------------------------------------------------------------
# ASSERTION L - data-file lifecycle + frozen-file integrity (NFL_analytics#214).
#
#   * every top-level web/public/data/*.json (excluding data_manifest.json) must
#     have a manifest entry with a valid lifecycle in WEB_DATA_LIFECYCLES
#     (c("live", "season_final", "archived")); missing or unknown lifecycle FAILS
#   * when `expected` is supplied as a function(files), the manifest's lifecycle
#     must match what expected(files) assigns
#   * season_final entries must carry season, final_through_date, frozen_sha256
#     and frozen_at, and the file's content hash (CRLF-normalised) must match
#     frozen_sha256; any change to a frozen file FAILS
# ------------------------------------------------------------------------------
.pw_data_files <- function(data_dir) {
  setdiff(sort(list.files(data_dir, pattern = "\\.json$")), "data_manifest.json")
}

.pw_manifest_entries <- function(manifest) {
  entries <- if (is.null(manifest) || !is.list(manifest$datasets)) list() else manifest$datasets
  if (length(entries) && is.null(names(entries))) return(list())
  entries
}

.pw_lifecycle_sha256 <- function(path) {
  if (exists("nfl_lifecycle_sha256", mode = "function")) return(nfl_lifecycle_sha256(path))
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

.assert_lifecycle <- function(data_dir = WEB_DATA_DIR, manifest = NULL, expected = NULL) {
  base <- list(id = "L", name = "data-file lifecycle + frozen-file integrity", fatal = TRUE)
  if (is.null(manifest)) {
    mpath <- file.path(data_dir, "data_manifest.json")
    manifest <- if (file.exists(mpath))
      tryCatch(jsonlite::fromJSON(mpath, simplifyVector = FALSE), error = function(e) NULL) else NULL
  }
  if (is.null(manifest) || !is.list(manifest$datasets)) {
    return(c(base, list(pass = FALSE, problems = "manifest absent or unreadable",
                        detail = "    [FAIL] no readable data_manifest.json to read lifecycles from",
                        summary = "manifest absent or unreadable")))
  }
  lifecycles <- if (exists("WEB_DATA_LIFECYCLES")) WEB_DATA_LIFECYCLES else c("live", "season_final", "archived")
  entries <- .pw_manifest_entries(manifest)
  files <- .pw_data_files(data_dir)
  exp <- if (is.function(expected)) expected(files) else list()
  problems <- character(0); lines <- character(0)
  counts <- c(live = 0L, season_final = 0L, archived = 0L)
  for (f in files) {
    e <- entries[[f]]
    lc <- if (is.list(e)) e$lifecycle else NULL
    if (is.null(lc) || length(lc) == 0L ||
        (is.character(lc) && length(lc) == 1L && !nzchar(trimws(lc))) ||
        (length(lc) == 1L && is.na(lc))) {
      lines <- c(lines, sprintf("    [NO LIFECYCLE] %s - assign a valid lifecycle in data_manifest.json", f))
      problems <- c(problems, sprintf("%s has no lifecycle", f)); next
    }
    if (!is.character(lc) || length(lc) != 1L || !(lc %in% lifecycles)) {
      lc_str <- paste(as.character(unlist(lc)), collapse = ",")
      lines <- c(lines, sprintf("    [FAIL] %s - unknown lifecycle '%s'", f, lc_str))
      problems <- c(problems, sprintf("%s unknown lifecycle %s", f, lc_str)); next
    }
    if (is.function(expected)) {
      want <- exp[[f]]$lifecycle
      want_str <- if (is.null(want) || length(want) != 1L || is.na(want) || !nzchar(as.character(want))) "<none>" else as.character(want)
      if (!identical(want_str, lc)) {
        lines <- c(lines, sprintf("    [FAIL] %s - manifest says %s, expected %s", f, lc, want_str))
        problems <- c(problems, sprintf("%s lifecycle %s != expected %s", f, lc, want_str)); next
      }
    }
    counts[[lc]] <- counts[[lc]] + 1L
    if (!identical(lc, "season_final")) {
      lines <- c(lines, sprintf("    [%s] %s", toupper(lc), f)); next
    }
    miss <- Filter(function(k) {
      v <- e[[k]]
      is.null(v) || length(v) != 1L || is.na(v) || !nzchar(trimws(as.character(v)))
    }, c("season", "final_through_date", "frozen_sha256", "frozen_at"))
    if (length(miss)) {
      lines <- c(lines, sprintf("    [FAIL] %s - season_final without %s", f, paste(miss, collapse = ", ")))
      problems <- c(problems, sprintf("%s season_final missing %s", f, paste(miss, collapse = ", "))); next
    }
    if (is.function(expected)) {
      want_sha <- exp[[f]]$frozen_sha256
      if (!is.null(want_sha) && !identical(as.character(want_sha), as.character(e$frozen_sha256))) {
        lines <- c(lines, sprintf("    [FAIL] %s - manifest frozen_sha256 differs from expected", f))
        problems <- c(problems, sprintf("%s frozen_sha256 disagrees with expected", f)); next
      }
    }
    actual <- .pw_lifecycle_sha256(file.path(data_dir, f))
    if (!identical(actual, as.character(e$frozen_sha256))) {
      lines <- c(lines, sprintf("    [CHANGED] %s - season %s was frozen at %s, content hash now %s (frozen %s)",
                                f, e$season, e$frozen_at, substr(actual, 1, 12), substr(e$frozen_sha256, 1, 12)))
      problems <- c(problems, sprintf("%s changed since frozen", f)); next
    }
    lines <- c(lines, sprintf("    [SEASON_FINAL] %s - season %s, hash matches frozen %s", f, e$season, e$frozen_at))
  }
  pass <- length(problems) == 0L
  c(base, list(
    pass = pass, problems = problems, detail = lines, counts = counts,
    summary = if (pass) sprintf("%d file(s): %d live, %d season_final (hash verified), %d archived",
                                length(files), counts[["live"]], counts[["season_final"]], counts[["archived"]])
              else sprintf("%d problem(s): %s", length(problems), paste(problems, collapse = "; "))
  ))
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
.pw_do_publish <- function(repo_root, commit_message, publish_branch = "main") {
  steps <- list()
  record <- function(label, res) {
    steps[[length(steps) + 1L]] <<- list(label = label, ok = res$ok, out = res$out)
    if (!res$ok) stop(sprintf("publish_web: step failed: %s\n%s", label,
                              paste(res$out, collapse = "\n")))
    invisible(TRUE)
  }
  record("git add web/public/{data,animations}",
         .pw_git(repo_root, c("add", "--", PIPELINE_OUTPUT_DIRS)))
  # Tracked ratings history behind the landing digest's movers (NFL_analytics#185).
  # Plain `git add`, never -f: if an ignore rule ever swallows it, this fails loudly.
  hist <- file.path("data", "history", "ratings_history.csv")
  if (file.exists(file.path(repo_root, hist)))
    record("git add data/history/ratings_history.csv", .pw_git(repo_root, c("add", "--", hist)))
  # Append-only forward log (tools/log_qb_change_forward.R, issue #220 follow-up). Same rule:
  # exact path, plain `git add`, never -f.
  fwd <- if (exists("FORWARD_LOG_QB_CHANGE")) FORWARD_LOG_QB_CHANGE else
    file.path("data", "history", "qb_change_forward_log.csv")
  if (file.exists(file.path(repo_root, fwd)))
    record("git add data/history/qb_change_forward_log.csv", .pw_git(repo_root, c("add", "--", fwd)))
  # Append-only Momentum Board rank history (build_momentum_board.R, NFL_analytics#226). Same
  # rule: exact path, plain `git add`, never -f.
  mrh <- if (exists("MOMENTUM_RANK_HISTORY")) MOMENTUM_RANK_HISTORY else
    file.path("data", "history", "momentum_rank_history.csv")
  if (file.exists(file.path(repo_root, mrh)))
    record("git add data/history/momentum_rank_history.csv", .pw_git(repo_root, c("add", "--", mrh)))
  record("git commit (NFL_analytics)",
         .pw_git(repo_root, c("commit", "-m", shQuote(commit_message))))
  c(steps, .pw_push_with_rebase(repo_root, publish_branch))
}

# ------------------------------------------------------------------------------
# Push that survives commits landing on the publish branch mid-run.
# 2026-11-24: a run committed its publish, then `push origin HEAD` was rejected
# ("fetch first") because PRs merged into main during the run; the local commit
# stayed behind and the checkout diverged. Now: fetch, rebase the publish commit
# onto origin/<branch> (publish commits only touch generated data, so never a
# merge commit), push; on rejection fetch + rebase + push exactly once more.
# On a rebase conflict or a second rejection: `rebase --abort`, then
# `reset --mixed origin/<branch>` (moves the branch back, leaves every
# working-tree file alone; never --hard, never stash), and fail loudly. No local
# commit is ever left behind; the regenerated files stay in the working tree.
# ------------------------------------------------------------------------------
.pw_push_log <- function(msg) {
  if (exists("log_info", mode = "function")) {
    tryCatch(log_info(msg), error = function(e) cat(msg, "\n", sep = ""))
  } else cat(msg, "\n", sep = "")
}

.pw_push_with_rebase <- function(repo_root, publish_branch) {
  steps <- list()
  remote_ref <- paste0("origin/", publish_branch)
  add <- function(label, res) {
    steps[[length(steps) + 1L]] <<- list(label = label, ok = res$ok, out = res$out)
    res
  }
  sha <- function(ref) {
    r <- .pw_git(repo_root, c("rev-parse", ref))
    if (r$ok && length(r$out)) r$out[1] else NA_character_
  }
  roll_back <- function(why, detail) {
    add("git rebase --abort (NFL_analytics)", .pw_git(repo_root, c("rebase", "--abort")))
    reset <- add(sprintf("git reset --mixed %s (NFL_analytics)", remote_ref),
                 .pw_git(repo_root, c("reset", "--mixed", "-q", remote_ref)))
    msg <- sprintf(paste0(
      "publish_web: %s. The publish commit was NOT pushed. %s ",
      "The regenerated files are still in the working tree for the next run.\n%s"),
      why,
      if (reset$ok) sprintf("The checkout is back in step with %s (%s); no local commit is left behind.",
                            remote_ref, sha("HEAD"))
      else sprintf("WARNING: resetting the branch to %s also failed - fix the checkout by hand.\n%s",
                   remote_ref, paste(reset$out, collapse = "\n")),
      paste(detail, collapse = "\n"))
    .pw_push_log(msg)
    stop(msg, call. = FALSE)
  }
  sync <- function() {
    f <- add(sprintf("git fetch origin %s (NFL_analytics)", publish_branch),
             .pw_git(repo_root, c("fetch", "origin", publish_branch)))
    if (!f$ok) roll_back(sprintf("git fetch origin %s failed", publish_branch), f$out)
    .pw_push_log(sprintf("publish_web: fetched origin %s (remote tip %s).", publish_branch, sha(remote_ref)))
    anc <- .pw_git(repo_root, c("merge-base", "--is-ancestor", remote_ref, "HEAD"))
    if (anc$ok) {
      .pw_push_log(sprintf("publish_web: %s is already an ancestor of HEAD; no rebase needed.", remote_ref))
      return(invisible(TRUE))
    }
    rb <- add(sprintf("git rebase %s (NFL_analytics)", remote_ref),
              .pw_git(repo_root, c("rebase", remote_ref)))
    if (!rb$ok) roll_back(sprintf("rebasing the publish commit onto %s hit a conflict", remote_ref), rb$out)
    .pw_push_log(sprintf("publish_web: rebased the publish commit onto the remote tip %s (%s).",
                         remote_ref, sha(remote_ref)))
    invisible(TRUE)
  }
  for (attempt in 1:2) {
    sync()
    p <- add(sprintf("git push origin HEAD (NFL_analytics, attempt %d)", attempt),
             .pw_git(repo_root, c("push", "origin", "HEAD")))
    if (p$ok) {
      .pw_push_log(sprintf("publish_web: pushed %s to origin %s.", sha("HEAD"), publish_branch))
      return(steps)
    }
    .pw_push_log(sprintf("publish_web: push attempt %d rejected:\n%s", attempt, paste(p$out, collapse = "\n")))
  }
  roll_back("the push was rejected twice", p$out)
}

# ------------------------------------------------------------------------------
# Deploy observability notification (GitHub issue #40).
#
# Posts the publish gate outcome to NFL_DISCORD_WEBHOOK (read via Sys.getenv,
# never hardcoded):
#   * On success or dry-run pass: active_week, published value-bet count, and
#     any exporter [WARN] lines surfaced during the run window.
#   * On blocked gate: the specific assertion(s) that failed plus any exporter
#     [WARN] lines.
# ------------------------------------------------------------------------------
.pw_value_bet_count <- function() {
  NA_integer_
}

.pw_notify_discord <- function(result) {
  webhook_url <- Sys.getenv("NFL_DISCORD_WEBHOOK", "")
  vb_count <- .pw_value_bet_count()
  wk <- result$active_week_published
  warns <- result$exporter_warnings

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
    list(name = "Active Week", value = sprintf("`%s`", ifelse(is.na(wk), "<NA>", wk)), inline = TRUE),
    list(name = "Value Bets Published", value = sprintf("`%s`", ifelse(is.na(vb_count), "<NA>", vb_count)), inline = TRUE),
    list(name = "Fatal Gate Failures", value = failed_text, inline = FALSE),
    list(name = "Exporter [WARN] Lines", value = paste0("```\n", warn_text, "\n```"), inline = FALSE)
  )

  payload <- list(
    username = "NFL Quant Terminal",
    embeds = list(
      list(
        title = paste("NFL Web Publish Gate \u2022", status_label),
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
    log_info(sprintf("publish_web: NFL_DISCORD_WEBHOOK not set; skipping Discord notification (status=%s, week=%s, value_bets=%s, warnings=%d).",
                     status_label, ifelse(is.na(wk), "NA", wk), ifelse(is.na(vb_count), "NA", vb_count), length(warns)))
    return(invisible(FALSE))
  }

  if (!requireNamespace("httr", quietly = TRUE)) {
    log_warn("publish_web: httr not installed; cannot post Discord notification.")
    return(invisible(FALSE))
  }

  res <- tryCatch(
    httr::POST(webhook_url, body = payload, encode = "json", httr::timeout(6)),
    error = function(e) list(status_code = 500L, message = conditionMessage(e))
  )
  ok <- !is.null(res$status_code) && res$status_code %in% c(200L, 204L)
  if (ok) {
    log_info("publish_web: posted deploy outcome to NFL_DISCORD_WEBHOOK.", status_code = res$status_code)
  } else {
    log_warn("publish_web: Discord webhook POST did not return 200/204.", status_code = res$status_code)
  }
  invisible(ok)
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
                        skip_contracts = FALSE,
                        commit_message = NULL) {

  repo_root <- .pw_repo_root()
  log_lines <- if (file.exists(LOG_FILE)) readLines(LOG_FILE, warn = FALSE) else character(0)
  if (is.null(run_start)) run_start <- .pw_detect_run_start(log_lines)
  if (is.null(commit_message)) {
    commit_message <- sprintf("Publish NFL web artifacts from the %s pipeline run",
                              if (is.na(run_start)) format(Sys.Date()) else format(run_start, "%Y-%m-%d %H:%M"))
  }

  # Live runs refresh the sidecar manifest so it describes exactly the payloads
  # about to be committed; dry runs never write.
  if (!dry_run && exists("write_data_manifest", mode = "function")) {
    tryCatch(write_data_manifest(WEB_DATA_DIR),
             error = function(e) log_warn(sprintf("publish_web: manifest refresh failed: %s", conditionMessage(e))))
  }

  checks <- list(
    .assert_mtime_freshness(run_start),
    .assert_week_agreement(),
    .assert_nonempty_diff(repo_root),
    .assert_publish_branch(repo_root, publish_branch),
    .assert_log_scan(log_lines, run_start, fail_on_exporter_warnings),
    .assert_payload_provenance(run_start),
    .assert_web_contracts(skip_contracts),
    .assert_manifest_and_coverage(),
    .assert_landing_digest(run_start),
    .assert_lifecycle(WEB_DATA_DIR)
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
    active_week_computed = .pw_check(checks, "B")$computed,
    active_week_published = .pw_check(checks, "B")$published,
    publish_branch_actual = .pw_check(checks, "E")$branch,
    exporter_warnings = .pw_check(checks, "D")$warnings,
    pending_changes = .pw_check(checks, "C")$changed,
    stale_payloads = .pw_check(checks, "F")$stale,
    unstamped_payloads = .pw_check(checks, "F")$unstamped,
    value_bets_published = .pw_value_bet_count(),
    contracts_pass = isTRUE(.pw_check(checks, "G")$pass),
    manifest_missing = .pw_check(checks, "H")$missing,
    manifest_lagging = .pw_check(checks, "H")$lagging,
    checks = checks, published = FALSE, steps = list()
  )

  if (blocked || dry_run) {
    if (blocked && !dry_run) .pw_notify_discord(result)
    return(invisible(result))
  }

  result$steps <- .pw_do_publish(repo_root, commit_message, publish_branch)
  result$published <- TRUE
  log_info(sprintf("publish_web: web artifacts committed and pushed to NFL_analytics %s. The site changes when the aggregator's sync-sports.yml next pulls; this script no longer deploys.",
                   publish_branch))
  .pw_notify_discord(result)
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
