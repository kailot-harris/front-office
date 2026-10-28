# ==============================================================================
# MLB Analytics - Web Artifact Publish Gate
# Path: <repo root>/tools/publish_web.R
#
# Ported from NFL Analytics' tools/publish_web.R (its GitHub issue #38) on
# 2026-10-26, as step 3a of the four-sport publish-cadence work. The NFL file is
# the reference implementation; read its header for the full rationale behind
# each assertion. This header records only what is DIFFERENT about MLB, because
# a verbatim restatement would be a second copy free to drift from the original.
#
# WHY THIS EXISTS
# ---------------
# run_full_pipeline.R's run_stage() swallows stage failures and the pipeline
# still exits 0. "Pipeline exited 0" is therefore not a safe precondition for
# deploying. MLB's own live proof, found while porting this file: the
# 2026-10-25 20:51 run reported 18/18 stages OK, and
# web/public/data/projections_models_metadata.json still carried
# "generated_at": "2026-10-23T05:40:32Z" -- two days stale, on a green run,
# with a clean working tree. This gate asserts on the ARTIFACTS, never on an
# exit code.
#
# Default mode is a DRY RUN: every assertion runs, a report is printed naming
# exactly what would be published, and nothing is committed or pushed. Any
# failed fatal assertion => publish nothing, exit non-zero, leave yesterday's
# correct site up rather than a half-updated one.
#
# THE FIVE ASSERTIONS
#   A  mtime freshness - every entry of config.R's WEB_DATA_FILES has an mtime
#      later than the run start. The ten filenames are NEVER re-typed here;
#      they are read from config.R, which is also where run_full_pipeline.R's
#      web stages now get their `output =` paths. See config.R section 7 for
#      the three deliberate non-members and why each is excluded.
#
#      A IS THE ASSERTION THAT MATTERS MOST FOR MLB, and this is where MLB
#      differs from NFL. The next-agent brief that scheduled this work said to
#      prioritise D because "all three have the same verbatim-republish
#      fallback". Checked against the source: MLB does NOT. There is no
#      republish-previous-bytes path anywhere in tools/export_web_data.R. MLB's
#      silent-staleness mode is the opposite one -- export_matchup_slates() and
#      export_spatial_analytics() are wrapped in tryCatch handlers that
#      log_warn() and continue (tools/export_web_data.R:975-990), so a failed
#      sub-export leaves the PREVIOUSLY COMMITTED file untouched on disk. An
#      untouched file keeps its old mtime, which is precisely what A sees. For
#      NFL, A is structurally blind to its republish fallbacks and D is the only
#      signal; for MLB it is the other way round.
#   B  slate agreement - active_week AND the season game count are
#      INDEPENDENTLY recomputed from CACHE_MLB_SCHEDULE(season) and compared to
#      the active_week / total_games that the exporter actually published in
#      matchups_index.json. NFL's equivalent assertion cross-checks
#      active_week alone; MLB gets the game count too, because MLB's week index
#      is pure calendar arithmetic that cannot detect a truncated schedule pull,
#      whereas a game count can. See .compute_slate_from_schedule() for the
#      rule and for why it is reimplemented rather than imported.
#   C  non-empty diff  - `git status --porcelain` must show real pending changes
#      under WEB_DATA_DIR before any commit is attempted. Without it a publish
#      reports success while pushing nothing.
#   E  publish branch  - HEAD must be on the branch the aggregator's
#      sync-sports.yml actually subtree-pulls (main). The commit+push below
#      pushes `origin HEAD`, so from a feature branch the data would be
#      committed there, pushed, and reported as published while
#      sync-sports.yml went on pulling main and the site never changed. Fatal,
#      and deliberately checked BEFORE anything is committed. (This assertion
#      was added to the NFL original after exactly that happened to it.)
#   D  log scan        - surfaces every [WARN] line attributable to
#      export_web_data.R in the run window. Reporting-only by default, fatal
#      under --strict-warnings. For MLB the warnings worth reading are the two
#      non-fatal tryCatch handlers named under A, and the market-provenance
#      gate's "withheld N/M value bet(s)" line.
#   F  payload provenance - reads the `generated_at` STAMP INSIDE each payload
#      that carries one and requires it to be at or after the run start. Added
#      here, with no NFL counterpart, because the first dry run of this gate
#      found A passing for the wrong reason:
#
#        projections_models_metadata.json   mtime 2026-10-25 20:52:27
#                                           generated_at 2026-10-23T05:40:32Z
#
#      The file was last COMMITTED on 2026-10-24 (08e010a) carrying content
#      generated on 10-23, and the working tree was CLEAN against HEAD. So the
#      2026-10-25 20:47 run did not regenerate it -- a git operation in the same
#      window (the merge at eddc10d rewrites these paths) refreshed the mtime
#      over unchanged bytes. Assertion A compares mtimes, and an mtime is a
#      property of the filesystem, not of the data: ANY git checkout, restore,
#      stash or merge satisfies A without a single byte of new output.
#
#      F is immune to that, because `generated_at` is written by the exporter
#      itself (tools/export_web_data.R:736, :1249) from Sys.time() at the
#      moment the payload is built. It is the MLB analogue of NFL's assertion
#      D -- the check that catches staleness A is structurally incapable of
#      seeing -- and the two gates are stronger together than either rule
#      ported alone.
#
#      REMAINING GAP, deliberately reported rather than silently tolerated:
#      8 of the 10 WEB_DATA_FILES now carry a stamp. The follow-up work named
#      here is done for every payload that can take one -- see the exporter
#      sites listed below -- and the two that remain unstamped are unstamped
#      for a STRUCTURAL reason, not an unfinished one:
#
#        projections_season_teams.json     top-level JSON ARRAY
#        projections_season_players.json   top-level JSON ARRAY
#
#      Both are jsonlite::write_json() of a data frame, so the document root is
#      `[...]`, which has nowhere to hang a scalar key. Stamping them means
#      either wrapping the array in an object (a breaking change for every web
#      reader, and MLB is the one sport with no web test suite to catch it) or
#      repeating the stamp on all ~1000 rows. Neither is worth it: assertion A
#      already covers both files on mtime, and these two are regenerated in the
#      same write block as the metadata payload F does speak for, three lines
#      apart, so a run that staled them would stale that one too.
#
#      F names both in its detail lines, so the gate still does not report
#      confidence it does not have.
#
#      Stamp-writing sites, all `format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ",
#      tz = "UTC")` and all FIRST in their object because .pw_payload_
#      generated_at() reads only the first 4096 bytes:
#        tools/export_web_data.R       metadata, matchups_index, diagnostics,
#                                      postseason_ops
#        mlb_series_simulator.R        playoff_series_matchups
#        mlb_player_dna_engine.R       player_dna_profiles
#        mlb_clutch_leverage_engine.R  clutch_leverage_metrics
#        mlb_cbt_payroll_engine.R      cbt_payroll_sheet
#
# ONE DEPLOY PATH
# ---------------
# This file commits and pushes MLB-Analytics and NOTHING ELSE. It does not
# subtree-pull, and it does not push front-office. The aggregator's
# .github/workflows/sync-sports.yml is the single mechanism that moves the live
# site; two pushers meant whichever ran second hit a non-fast-forward. Pushing
# MLB-Analytics triggers no deploy on its own -- it makes the artifacts
# available for sync-sports.yml to pull on its next run or dispatch.
#
# ------------------------------------------------------------------------------
# ## Failure reproductions
# ------------------------------------------------------------------------------
# A (mtime freshness) FAILS:
#     Rscript -e "source('tools/publish_web.R'); print(publish_web(dry_run = TRUE, run_start = Sys.time())$assertions_failed)"
#   Passing run_start = now makes every published file older than the run start
#   by construction. Nothing is written; no restore needed.
#
# B (slate agreement) FAILS, with no mutation:
#     Rscript -e "source('tools/publish_web.R'); print(.assert_slate_agreement(published_override = list(active_week = 99L, total_games = 1L)))"
#   Compares the real recomputation against a deliberately wrong published
#   pair. The mutating variant edits matchups_index.json's active_week and
#   restores it from a copy, as NFL's header describes for its own file.
#
# C (non-empty diff) FAILS:
#   The DEFAULT state of a checkout whose web/ tree is already committed, so no
#   setup is required. Run the dry run on a clean tree and C reports
#   "CLEAN against HEAD - nothing to publish".
#
# E (publish branch) FAILS, with no mutation:
#     Rscript -e "source('tools/publish_web.R'); print(publish_web(dry_run = TRUE, publish_branch = 'no-such-branch')$assertions_failed)"
#
# D (log scan) matcher, on synthetic text, with no setup:
#     Rscript -e "source('tools/publish_web.R'); print(.scan_exporter_warnings(c('[2026-10-25 20:51:00] [WARN] [export_web_data.R] fabricated stale warning'), as.POSIXct('2026-10-25 20:00:00')))"
#
# F (payload provenance) FAILS against the real tree as committed on
#   2026-10-26, which is how it was found -- no setup required:
#     Rscript -e "source('tools/publish_web.R'); print(.assert_payload_provenance(as.POSIXct('2026-10-25 20:47:13'))\$summary)"
#   Reports projections_models_metadata.json stamped 2026-10-23T05:40:32Z
#   against a 2026-10-25 20:47 run start. Its parser is inspectable alone:
#     Rscript -e "source('tools/publish_web.R'); print(.pw_payload_generated_at('web/public/data/projections_models_metadata.json'))"
# ==============================================================================

# ------------------------------------------------------------------------------
# Bootstrap: setwd() to this script's project root, then source siblings by bare
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
source("logging_utils.R")
source("config.R")

.PW_LOG_SCRIPT <- "publish_web.R"

# ------------------------------------------------------------------------------
# Small helpers
# ------------------------------------------------------------------------------
.pw_git <- function(repo, args) {
  # Task Scheduler / PowerShell / cmd.exe non-interactive sessions do not
  # set HOME the way Git Bash does, so git can fail to find ~/.gitconfig and
  # refuse to commit with "unable to auto-detect email address" (cf. NFL #53).
  # Pass identity explicitly via -c so commits do not depend on HOME resolution.
  # R on Windows rewrites HOME to "<USERPROFILE>/Documents", while Git for
  # Windows stores ~/.gitconfig at "<USERPROFILE>/.gitconfig". Point HOME at
  # USERPROFILE when .gitconfig lives there so both git config and git commit
  # resolve the user's global git config and credential helper.
  up <- Sys.getenv("USERPROFILE", "")
  if (nzchar(up) && file.exists(file.path(up, ".gitconfig"))) {
    Sys.setenv(HOME = up)
  }
  if (identical(args[1], "commit")) {
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
# Run-start discovery. Parsed from LOG_FILE's own "Pipeline run started." marker
# (run_full_pipeline.R:177, in logging_utils.R's
# "[YYYY-MM-DD HH:MM:SS] [LEVEL] [script] msg" format), so a scheduled
# unattended run has nothing to pass in. Overridable for tests and for
# republishing a specific historical run.
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
  files <- WEB_DATA_FILES          # <- the ten names come from config.R ONLY
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
# cache, using the same documented rule as tools/export_web_data.R:
#   * keep only MATCHUP_GAME_TYPES (config.R) - regular season plus the four
#     postseason rounds;
#   * collapse duplicate game_pk rows, which the MLB Stats API emits for
#     suspended-and-resumed and rescheduled games;
#   * week index = round((monday_of(date) - monday_of(first game date)) / 7) + 1;
#   * active_week = the week holding today when today is inside the season's
#     date span, else the week holding the last scheduled date.
#
# The RULE is reimplemented here rather than imported from the exporter, and
# that is the whole point: calling the exporter's build_matchup_slates() would
# make this an echo of the thing under test. What IS imported is every
# CONSTANT (MATCHUP_GAME_TYPES, MLB_CURRENT_SEASON, CACHE_MLB_SCHEDULE,
# WEB_JSON_MATCHUPS_INDEX), per CLAUDE.md's single-source-of-truth rule --
# constants from config.R, logic independent.
#
# One deliberate difference from the exporter: the exporter's "else" arm walks
# back to the latest GRADED result in the Elo history, which lives in a
# different cache this gate does not read. This implementation falls back to the
# last scheduled date instead. Both land on the same week whenever the schedule
# is complete and the season is in progress, and `week_tolerance` (default 1)
# absorbs the boundary case rather than making B flap once a year. A disagreement
# larger than the tolerance is a real disagreement.
# ------------------------------------------------------------------------------
.pw_monday_of <- function(d) {
  d <- as.Date(d)
  d - (as.integer(format(d, "%u")) - 1L)
}

.compute_slate_from_schedule <- function(season = MLB_CURRENT_SEASON,
                                         schedule_path = NULL) {
  if (is.null(schedule_path)) schedule_path <- CACHE_MLB_SCHEDULE(season)
  empty <- list(active_week = NA_integer_, total_games = NA_integer_,
                path = schedule_path, note = NULL)
  if (!file.exists(schedule_path)) {
    empty$note <- sprintf("%s is absent", basename(schedule_path))
    return(empty)
  }
  sched <- tryCatch(readRDS(schedule_path), error = function(e) NULL)
  if (is.null(sched)) {
    empty$note <- "schedule cache unreadable"
    return(empty)
  }
  sched <- as.data.frame(sched, stringsAsFactors = FALSE)
  need <- c("game_type", "game_pk", "official_date")
  if (!all(need %in% names(sched))) {
    empty$note <- sprintf("schedule cache lacks %s",
                          paste(setdiff(need, names(sched)), collapse = ", "))
    return(empty)
  }

  keep <- sched$game_type %in% MATCHUP_GAME_TYPES
  s <- sched[keep, , drop = FALSE]
  # Collapse duplicate game_pk rows. The exporter ranks the duplicates by
  # status and keeps the most settled one; the choice only affects which row's
  # SCORE survives, never the count or the date, so for a count-and-date
  # cross-check plain first-wins dedupe is equivalent and carries no copy of
  # the exporter's status-rank table.
  s <- s[!duplicated(s$game_pk), , drop = FALSE]
  gd <- as.Date(substr(as.character(s$official_date), 1, 10))
  s <- s[!is.na(gd), , drop = FALSE]
  gd <- gd[!is.na(gd)]
  if (!nrow(s)) {
    empty$note <- "no dated season games in the schedule cache"
    return(empty)
  }

  anchor <- .pw_monday_of(min(gd))
  week_of <- function(d) {
    as.integer(round(as.numeric(difftime(.pw_monday_of(d), anchor, units = "days")) / 7)) + 1L
  }
  today <- Sys.Date()
  ref <- if (today >= min(gd) && today <= max(gd)) today else max(gd)

  list(active_week = week_of(ref),
       total_games = as.integer(nrow(s)),
       path = schedule_path,
       note = NULL)
}

.assert_slate_agreement <- function(season = MLB_CURRENT_SEASON,
                                    week_tolerance = 1L,
                                    published_override = NULL) {
  computed <- .compute_slate_from_schedule(season)
  note <- computed$note
  published <- list(active_week = NA_integer_, total_games = NA_integer_)

  if (!is.null(published_override)) {
    published <- published_override
  } else if (!file.exists(WEB_JSON_MATCHUPS_INDEX)) {
    note <- c(note, sprintf("%s is absent", basename(WEB_JSON_MATCHUPS_INDEX)))
  } else {
    j <- tryCatch(jsonlite::fromJSON(WEB_JSON_MATCHUPS_INDEX, simplifyVector = TRUE),
                  error = function(e) {
                    note <<- c(note, paste("unparseable JSON:", conditionMessage(e)))
                    NULL
                  })
    if (!is.null(j)) {
      if (!is.null(j$active_week)) published$active_week <- as.integer(j$active_week[1])
      if (!is.null(j$total_games)) published$total_games <- as.integer(j$total_games[1])
    }
  }

  have <- !is.na(computed$active_week) && !is.na(published$active_week) &&
          !is.na(computed$total_games) && !is.na(published$total_games)
  week_ok  <- have && abs(computed$active_week - published$active_week) <= week_tolerance
  games_ok <- have && identical(computed$total_games, published$total_games)
  pass <- isTRUE(week_ok) && isTRUE(games_ok)

  list(id = "B", name = "slate agreement (schedule cache vs published matchups_index)",
       pass = pass, fatal = TRUE,
       computed = computed, published = published,
       detail = c(
         sprintf("    recomputed from %-30s : week=%s games=%s", basename(computed$path),
                 ifelse(is.na(computed$active_week), "<NA>", computed$active_week),
                 ifelse(is.na(computed$total_games), "<NA>", computed$total_games)),
         sprintf("    published in    %-30s : week=%s games=%s", basename(WEB_JSON_MATCHUPS_INDEX),
                 ifelse(is.na(published$active_week), "<NA>", published$active_week),
                 ifelse(is.na(published$total_games), "<NA>", published$total_games)),
         sprintf("    week tolerance  : +/-%d (see the fallback note in this file's header)",
                 as.integer(week_tolerance)),
         if (length(note)) paste("    note:", note)),
       summary = sprintf("week computed=%s published=%s | games computed=%s published=%s",
                         ifelse(is.na(computed$active_week), "<NA>", computed$active_week),
                         ifelse(is.na(published$active_week), "<NA>", published$active_week),
                         ifelse(is.na(computed$total_games), "<NA>", computed$total_games),
                         ifelse(is.na(published$total_games), "<NA>", published$total_games)))
}

# ------------------------------------------------------------------------------
# ASSERTION C - non-empty diff under the published tree.
# Resolved against the RUNTIME git root, never a hardcoded path: config.R's
# MLB_ROOT_DIR is an absolute path into the main checkout, so a worktree would
# otherwise be reported against the wrong repository.
# WEB_DATA_DIR covers web/public/data/matchups/ as well, since git status takes
# a directory prefix. MLB has no animations tree (cf. NFL's WEB_ANIM_DIR).
# ------------------------------------------------------------------------------
.pw_rel_to_repo <- function(path, repo_root) {
  if (is.na(repo_root)) return(path)
  p <- normalizePath(path, winslash = "/", mustWork = FALSE)
  r <- paste0(sub("/$", "", repo_root), "/")
  if (startsWith(p, r)) substring(p, nchar(r) + 1L) else p
}

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
# ASSERTION D - exporter [WARN] scan for the run window.
# Matches "export_web_data" anywhere in the line rather than only in the log's
# script field: log_warn() calls made from inside a sourced function body can
# record the script as something other than the file name, so a script-field
# match is free to find nothing while warnings are being logged.
# ------------------------------------------------------------------------------
.scan_exporter_warnings <- function(log_lines, run_start) {
  idx <- grep("\\[WARN\\].*export_web_data", log_lines)
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
                else "    no export_web_data [WARN] lines in the run window",
       summary = sprintf("%d exporter warning(s) surfaced%s", length(warns),
                         if (fail_on_exporter_warnings) " (fatal)" else " (reported, non-fatal)"))
}

# ------------------------------------------------------------------------------
# ASSERTION F - payload provenance.
#
# Reads the `generated_at` stamp out of each WEB_DATA_FILES payload that has
# one and requires it to be no older than the run start. See this file's header
# for why an mtime assertion cannot do this job and how the gap was found.
#
# Only the top of each file is read. These payloads reach 1.6 MB (the season's
# matchups) and `generated_at` is written in the first object, so slurping the
# whole document through jsonlite to reach one scalar would make the gate
# noticeably slower on every scheduled run for nothing. The regex is anchored
# on the key, not on a position, so it does not care where in the head it sits.
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
  # The exporter writes "%Y-%m-%dT%H:%M:%SZ" in UTC. Parsed as UTC and returned
  # as a POSIXct so it is directly comparable with run_start, which comes from
  # the log in local time -- POSIXct comparison is absolute, not wall-clock, so
  # no timezone arithmetic is needed or wanted here.
  as.POSIXct(val, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
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
                            format(g, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")))
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
# Runs the vitest node contract suite (`web/scripts/run-test-suite.mjs
# --only=contracts`) over the uncommitted `web/public/data/*.json` payloads
# before a publish commit can happen. Seconds: vitest over JSON, no browser and
# no build.
#
# FATAL, with a documented escape valve: web/tests/known-issues.json. The
# runner reports a listed failure as KNOWN and still exits 0, so a defect
# judged shippable stays shippable - once someone has written down its id,
# severity, title and fix. An UNDOCUMENTED contract failure blocks the
# publish.
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

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(web_dir)
  out <- suppressWarnings(system2(node, c(shQuote(.PW_WEB_RUNNER), "--only=contracts"),
                                  stdout = TRUE, stderr = TRUE))
  st  <- attr(out, "status")
  setwd(old_wd)
  status <- if (is.null(st)) 0L else as.integer(st)
  out <- if (is.null(out)) character(0) else as.character(out)

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
# Commit / push sequence. ONLY reached when dry_run = FALSE and every fatal
# assertion passed. Commits the published tree and pushes MLB-Analytics --
# nothing more. The deploy belongs to the aggregator's sync-sports.yml.
# Assertion E guarantees HEAD is the branch sync-sports.yml pulls, so
# `push origin HEAD` reaches the ref CI will actually read.
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
  record("git commit (MLB-Analytics)",
         .pw_git(repo_root, c("commit", "-m", shQuote(commit_message))))
  record("git push origin HEAD (MLB-Analytics)",
         .pw_git(repo_root, c("push", "origin", "HEAD")))
  steps
}

# ------------------------------------------------------------------------------
# Deploy observability notification (ported from NFL_analytics#40 / #41).
#
# Posts the publish gate outcome to MLB_DISCORD_WEBHOOK (with fallback to
# DISCORD_WEBHOOK_URL, read via Sys.getenv, never hardcoded):
#   * On success or dry-run pass: active_week, published value-bet count, and
#     any exporter [WARN] lines surfaced during the run window.
#   * On blocked gate: the specific assertion(s) that failed plus any exporter
#     [WARN] lines.
# ------------------------------------------------------------------------------
.pw_value_bet_count <- function() {
  if (!file.exists(WEB_JSON_PROJECTIONS_POSTSEASON_OPS)) return(NA_integer_)
  j <- tryCatch(jsonlite::fromJSON(WEB_JSON_PROJECTIONS_POSTSEASON_OPS, simplifyVector = TRUE),
                error = function(e) NULL)
  if (is.null(j)) return(NA_integer_)
  if (!is.null(j$value_bets_provenance) && !is.null(j$value_bets_provenance$n_published)) {
    return(as.integer(j$value_bets_provenance$n_published[1]))
  }
  if (!is.null(j$value_bets) && is.data.frame(j$value_bets)) return(as.integer(nrow(j$value_bets)))
  if (is.list(j$value_bets)) return(as.integer(length(j$value_bets)))
  NA_integer_
}

.pw_notify_discord <- function(result) {
  webhook_url <- Sys.getenv("MLB_DISCORD_WEBHOOK", Sys.getenv("DISCORD_WEBHOOK_URL", ""))
  vb_count <- .pw_value_bet_count()
  wk <- if (!is.null(result$slate_published)) result$slate_published$active_week else NA
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
    list(name = "Active Slate", value = sprintf("`%s`", ifelse(is.na(wk), "<NA>", wk)), inline = TRUE),
    list(name = "Value Bets Published", value = sprintf("`%s`", ifelse(is.na(vb_count), "<NA>", vb_count)), inline = TRUE),
    list(name = "Fatal Gate Failures", value = failed_text, inline = FALSE),
    list(name = "Exporter [WARN] Lines", value = paste0("```\n", warn_text, "\n```"), inline = FALSE)
  )

  payload <- list(
    username = "MLB Quant Terminal",
    embeds = list(
      list(
        title = paste("MLB Web Publish Gate \u2022", status_label),
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
    log_info(sprintf("publish_web: MLB_DISCORD_WEBHOOK / DISCORD_WEBHOOK_URL not set; skipping Discord notification (status=%s, slate=%s, value_bets=%s, warnings=%d).",
                     status_label, ifelse(is.na(wk), "NA", wk), ifelse(is.na(vb_count), "NA", vb_count), length(warns)),
             script = .PW_LOG_SCRIPT)
    return(invisible(FALSE))
  }

  if (!requireNamespace("httr", quietly = TRUE)) {
    log_warn("publish_web: httr not installed; cannot post Discord notification.", script = .PW_LOG_SCRIPT)
    return(invisible(FALSE))
  }

  res <- tryCatch(
    httr::POST(webhook_url, body = payload, encode = "json", httr::timeout(6)),
    error = function(e) list(status_code = 500L, message = conditionMessage(e))
  )
  ok <- !is.null(res$status_code) && res$status_code %in% c(200L, 204L)
  if (ok) {
    log_info("publish_web: posted deploy outcome to MLB_DISCORD_WEBHOOK.", script = .PW_LOG_SCRIPT, status_code = res$status_code)
  } else {
    log_warn("publish_web: Discord webhook POST did not return 200/204.", script = .PW_LOG_SCRIPT, status_code = res$status_code)
  }
  invisible(ok)
}

# ------------------------------------------------------------------------------
# publish_web() - the explicitly-callable entry point.
#
# Deliberately NOT guarded by a `sys.nframe() == 0`-style top-level-only check:
# that is a documented silent-no-op failure mode across this estate, because
# source()ing from an orchestrator changes frame depth, so the guard no-ops
# while still reporting success. Callers invoke this function explicitly; the
# CLI wrapper at the bottom of this file keys off commandArgs(), not frame depth.
# ------------------------------------------------------------------------------
publish_web <- function(dry_run = TRUE,
                        run_start = NULL,
                        season = MLB_CURRENT_SEASON,
                        publish_branch = "main",
                        fail_on_exporter_warnings = FALSE,
                        skip_contracts = FALSE,
                        commit_message = NULL) {

  repo_root <- .pw_repo_root()
  log_lines <- if (file.exists(LOG_FILE)) readLines(LOG_FILE, warn = FALSE) else character(0)
  if (is.null(run_start)) run_start <- .pw_detect_run_start(log_lines)
  if (is.null(commit_message)) {
    commit_message <- sprintf("Publish MLB web artifacts from the %s pipeline run",
                              if (is.na(run_start)) format(Sys.Date()) else format(run_start, "%Y-%m-%d %H:%M"))
  }

  checks <- list(
    .assert_mtime_freshness(run_start),
    .assert_slate_agreement(season),
    .assert_nonempty_diff(repo_root),
    .assert_publish_branch(repo_root, publish_branch),
    .assert_log_scan(log_lines, run_start, fail_on_exporter_warnings),
    .assert_payload_provenance(run_start),
    .assert_web_contracts(skip_contracts)
  )

  passed  <- vapply(checks, function(ch) isTRUE(ch$pass), logical(1))
  fatal   <- vapply(checks, function(ch) isTRUE(ch$fatal), logical(1))
  blocked <- any(!passed & fatal)

  # ---- report ----------------------------------------------------------------
  cat("\n================================================================\n")
  cat(sprintf("MLB web publish gate  [%s]\n",
              if (dry_run) "DRY RUN - nothing will be published" else "LIVE PUBLISH"))
  cat("================================================================\n")
  cat(sprintf("  repo root        : %s\n", ifelse(is.na(repo_root), "<not a git repo>", repo_root)))
  cat(sprintf("  publish branch   : %s\n", publish_branch))
  cat(sprintf("  season           : %d\n", as.integer(season)))
  cat(sprintf("  pipeline log     : %s (%d lines)\n", LOG_FILE, length(log_lines)))
  cat(sprintf("  run start        : %s\n",
              ifelse(is.na(run_start), "<undetected>", format(run_start, "%Y-%m-%d %H:%M:%S"))))
  cat(sprintf("  schedule cache   : %s\n", CACHE_MLB_SCHEDULE(season)))
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
  slates <- if (dir.exists(WEB_MATCHUPS_DIR)) list.files(WEB_MATCHUPS_DIR) else character(0)
  cat(sprintf("  %d per-slate file(s) from %s (not individually asserted; see config.R section 7)\n",
              length(slates), WEB_MATCHUPS_DIR))
  cat(sprintf("  commit message   : %s\n", commit_message))
  cat(sprintf("  push sequence    : commit -> push MLB-Analytics %s (deploy belongs to the aggregator's sync-sports.yml)\n",
              publish_branch))

  cat("\n-- Verdict -----------------------------------------------------\n")
  if (blocked) {
    cat("  BLOCKED - at least one fatal assertion failed. PUBLISHING NOTHING.\n")
    cat("  Yesterday's correct site stays up rather than a half-updated one.\n")
    for (ch in checks[!passed & fatal]) {
      log_warn(sprintf("publish_web: assertion %s FAILED (%s) - publishing nothing. %s",
                       ch$id, ch$name, ch$summary), script = .PW_LOG_SCRIPT)
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
    exporter_warnings = checks[[5]]$warnings,
    stale_payloads = checks[[6]]$stale,
    unstamped_payloads = checks[[6]]$unstamped,
    pending_changes = checks[[3]]$changed,
    value_bets_published = .pw_value_bet_count(),
    contracts_pass = isTRUE(checks[[length(checks)]]$pass),
    checks = checks, published = FALSE, steps = list()
  )

  if (blocked || dry_run) {
    if (blocked && !dry_run) .pw_notify_discord(result)
    return(invisible(result))
  }

  result$steps <- .pw_do_publish(repo_root, checks[[3]]$paths, commit_message)
  result$published <- TRUE
  log_info(sprintf("publish_web: web artifacts committed and pushed to MLB-Analytics %s. The site changes when the aggregator's sync-sports.yml next pulls; this script does not deploy.",
                   publish_branch), script = .PW_LOG_SCRIPT)
  .pw_notify_discord(result)
  invisible(result)
}

# ------------------------------------------------------------------------------
# CLI wrapper. Keyed off commandArgs() - i.e. "was I invoked as
# `Rscript tools/publish_web.R`" - NOT off sys.nframe(). source()ing this file
# from another script or from `Rscript -e` defines the function and runs
# nothing, which is what makes the function callable without surprise side
# effects.
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
  unknown <- setdiff(opts, c("--publish", "--strict-warnings", "--skip-contracts"))
  if (length(unknown) > 0) {
    cat(sprintf("[ERROR] publish_web.R: unknown CLI option(s): %s (allowed: --publish, --strict-warnings, --skip-contracts)\n",
                paste(unknown, collapse = ", ")), file = stderr())
    quit(status = 2L)
  }
  res <- publish_web(dry_run = !("--publish" %in% opts),
                     fail_on_exporter_warnings = "--strict-warnings" %in% opts,
                     skip_contracts = "--skip-contracts" %in% opts)
  quit(status = if (isTRUE(res$blocked)) 1L else 0L)
})
