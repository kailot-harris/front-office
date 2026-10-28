# ==============================================================================
# WNBA Analytics - Web Artifact Publish Gate
# Path: <repo root>/tools/publish_web.R
#
# Ported from NFL Analytics' tools/publish_web.R (its GitHub issue #38) on
# 2026-10-26, as step 3a of the four-sport publish-cadence work, by way of the
# MLB and NBA ports written the same day. Read NFL's header for the full
# rationale behind the shared assertions; this header records only what is
# DIFFERENT about WNBA, because a verbatim restatement would be a second copy
# free to drift from the original.
#
# WHY THIS EXISTS
# ---------------
# Every script in this repo is deliberately fail-safe: "check file.exists(),
# fall back to a clearly labeled synthetic value, never hard-crash the
# pipeline" (CLAUDE.md). That is the right design for a daily unattended run,
# and it is exactly why a pipeline exit code cannot authorise a deploy -- a run
# that fell back to synthetic data for every stage still exits 0. This gate
# asserts on the ARTIFACTS, never on an exit code.
#
# Default mode is a DRY RUN: every assertion runs, a report is printed naming
# exactly what would be published, and nothing is committed or pushed. Any
# failed fatal assertion => publish nothing, exit non-zero, leave yesterday's
# correct site up rather than a half-updated one.
#
# WHAT WNBA HAD BEFORE THIS
# -------------------------
# No publish path at all. schedule_daily.bat ran the pipeline, graded bets and
# refreshed the slate, and then stopped -- no commit, no push. Every byte of
# output this repo produced reached the live site only when a human ran a sync
# by hand. That is the gap 3b closes, and this file is the gate it closes it
# behind.
#
# THE SEVEN ASSERTIONS
#   A  mtime freshness - every entry of config.R's WEB_DATA_FILES has an mtime
#      later than the run start. The nineteen filenames are NEVER re-typed
#      here; they are read from config.R, which is now also where
#      pipeline_stages.R's stage `output =` fields and export_web_json.R's
#      write targets get their paths. Unlike the NBA and MLB ports, WNBA has no
#      non-members: every JSON in web/public/data is written by a stage this
#      pipeline runs. See config.R for why that differs from NBA despite the
#      two repos looking alike.
#   B  schedule coverage - the season, the team count and the game count are
#      INDEPENDENTLY recomputed from CACHE_WNBA_SCHEDULE and compared to the
#      header projections_models_metadata.json actually published. See
#      .compute_coverage_from_schedule() for the rule, and read the note there
#      about `total_schedule_games` before treating its sub-check as a bug.
#   C  non-empty diff  - `git status --porcelain` must show real pending changes
#      under WEB_DATA_DIR / WEB_MEDIA_DIR before any commit is attempted.
#      WEB_MEDIA_DIR is included because the bracket page's net-rating
#      trajectory GIF is a published artifact too (config.R's
#      MEDIA_NET_RATING_TRAJECTORY_GIF), and a publish that committed the JSON
#      without it would ship a page referencing last week's animation.
#   D  fallback scan   - surfaces SYNTHETIC_FALLBACK and [WARN] lines from the
#      run window. This is WNBA's most load-bearing reporting assertion, and it
#      is the one that differs most from the siblings: because every script here
#      falls back to labelled synthetic values rather than failing, the log is
#      the ONLY place that substitution is visible. The artifact looks
#      structurally perfect either way. Reporting-only by default, fatal under
#      --strict-warnings.
#   E  publish branch  - HEAD must be on the branch the aggregator's
#      sync-sports.yml actually subtree-pulls (main). The commit+push below
#      pushes `origin HEAD`, so from a feature branch the data would be
#      committed there, pushed, and reported as published while
#      sync-sports.yml went on pulling main and the site never changed. Fatal,
#      and checked BEFORE anything is committed.
#   F  payload provenance - reads the embedded `generated_at` stamp of every
#      payload that carries one and requires it to be at or after the run
#      start. It is the assertion that catches staleness A is structurally
#      incapable of seeing: an mtime is a property of the filesystem, so any
#      git checkout, restore, stash or merge satisfies A over unchanged bytes.
#      That is not hypothetical -- it is how MLB's two-day-stale projections
#      survived a green run and a clean tree on 2026-10-25, which is where this
#      assertion came from.
#
#      KNOWN GAP, reported rather than silently tolerated: only 1 of WNBA's 18
#      published payloads carries a `generated_at` at all -- the weakest
#      coverage of the four sports. F names the other seventeen in its detail
#      lines rather than implying it has checked them. Stamping every payload is
#      an exporter change, not a gate change, and is left as follow-up; it is
#      the single highest-value follow-up this port leaves behind.
#
#   G  web contracts - runs the web suite's `contracts` stage against the
#      UNCOMMITTED payload. A to F ask when a file was written, whether its
#      bytes changed, what the log said, whose branch it is on and when the
#      payload says it was generated; none of them reads the numbers inside
#      and asks whether they agree with each other. Added 2026-10-26 after
#      all six passed at 08:01 over a payload whose projected wins summed to
#      331 against the 330 published beside them. Fatal, with
#      web/tests/known-issues.json as the documented escape valve.
#
# SEASONAL SCOPE
# --------------
# The WNBA season runs ~May to end of October and schedule_daily.bat refuses to
# run the pipeline outside it (see that file's seasonal guard, and
# WNBA_REPLICATION_PLAN.md (e) risk #1). This gate does NOT carry its own
# seasonal guard, on purpose: out of season there is no run, so there is no run
# start, so assertion A fails and the gate blocks. Blocking is the correct
# out-of-season behaviour and it falls out of the existing assertions rather
# than needing a second copy of the season window to drift from the .bat's.
#
# ONE DEPLOY PATH
# ---------------
# This file commits and pushes WNBA_analytics and NOTHING ELSE. It does not
# subtree-pull and it does not push front-office. The aggregator's
# .github/workflows/sync-sports.yml is the single mechanism that moves the live
# site. Pushing WNBA_analytics triggers no deploy on its own -- it makes the
# artifacts available for sync-sports.yml to pull on its next run or dispatch.
#
# ------------------------------------------------------------------------------
# ## Failure reproductions
# ------------------------------------------------------------------------------
# Per CLAUDE.md, inline multi-line `Rscript -e` segfaults on this machine, so
# each of these is written as a one-liner. Anything longer goes in a temp .R
# file.
#
# A FAILS (no mutation, nothing written):
#     Rscript -e "source('tools/publish_web.R'); print(publish_web(dry_run = TRUE, run_start = Sys.time())$assertions_failed)"
#
# B FAILS (no mutation):
#     Rscript -e "source('tools/publish_web.R'); print(.assert_schedule_coverage(published_override = list(season = 1999L, teams_count = 2L, total_schedule_games = 1L))$summary)"
#
# C FAILS: the DEFAULT state of a checkout whose web/ tree is already
#   committed, so no setup is required. The dry run reports "CLEAN against HEAD".
#
# E FAILS (no mutation):
#     Rscript -e "source('tools/publish_web.R'); print(publish_web(dry_run = TRUE, publish_branch = 'no-such-branch')$assertions_failed)"
#
# D's matcher, on synthetic text, with no setup:
#     Rscript -e "source('tools/publish_web.R'); print(.scan_fallback_warnings(c('[2026-10-25 08:00:00] [WARN] [x.R] Using SYNTHETIC_FALLBACK roster'), as.POSIXct('2026-10-25 07:00:00')))"
#
# F's parser, on the one stamped payload:
#     Rscript -e "source('tools/publish_web.R'); print(.pw_payload_generated_at(WEB_JSON_PROJECTIONS_MODELS_METADATA))"
# ==============================================================================

# ------------------------------------------------------------------------------
# Bootstrap. tools/ scripts in this repo setwd() to the project root before
# source()ing dependencies by bare filename (CLAUDE.md, "Folder layout"), so
# they run correctly regardless of invocation location. The root is DERIVED,
# never hardcoded -- a second absolute path would be a second thing to drift.
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

.pw_rel_to_repo <- function(path, repo_root) {
  if (is.na(repo_root)) return(path)
  p <- normalizePath(path, winslash = "/", mustWork = FALSE)
  r <- paste0(sub("/$", "", repo_root), "/")
  if (startsWith(p, r)) substring(p, nchar(r) + 1L) else p
}

# ------------------------------------------------------------------------------
# Run-start discovery. Parsed from LOG_FILE's own "Pipeline run started." marker
# (run_full_pipeline.R:47, in logging_utils.R's
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
  files <- WEB_DATA_FILES          # <- the nineteen names come from config.R ONLY
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
# ASSERTION B - schedule coverage.
#
# Independent re-derivation of the published metadata header from the schedule
# cache. CACHE_WNBA_SCHEDULE is long-form -- one row per TEAM per scheduled
# game, so twice the game count (config.R documents this) -- which is itself the
# reason this has to be recomputed rather than read: a naive nrow() would report
# double and look plausible.
#
#   * season       : CURRENT_SEASON, cross-checked against the `season` column
#                    actually present in the cache AND against the season the
#                    exporter published. Three-way, because this repo has a
#                    documented history of season-scope slips.
#   * teams_count  : distinct franchise abbreviations in the schedule, after
#                    dropping the exhibition/All-Star codes wehoop ships
#                    (CLAUDE.md: DEL, WIL, ALL, USA, STE, CLA, COL, COOP,
#                    SPO...). The filter is `%in% names(WNBA_TEAMS)`, the
#                    documented rule, with CONN -> CON normalised first --
#                    without that normalisation the Connecticut Sun are silently
#                    dropped, which is the exact ported bug CLAUDE.md warns
#                    about.
#   * total_schedule_games : the distinct regular-season (season_type == 2)
#                    game count.
#
# READ THIS BEFORE TREATING THE GAME-COUNT SUB-CHECK AS A BUG. The exporter's
# published `total_schedule_games` is NOT measured from the schedule at all --
# export_web_json.R:419 computes it as WNBA_TEAM_COUNT * WNBA_SEASON_GAMES / 2,
# i.e. 15 * 44 / 2 = 330, a pure structural constant. The real 2026 schedule
# holds 332 distinct regular-season games. So the published figure is a
# league-structure expectation wearing a measurement's name, and it is off by
# two against the actual slate.
#
# This sub-check is therefore REPORTED, NOT FATAL, and carries a tolerance. It
# is kept rather than dropped because the comparison is genuinely useful -- a
# schedule that diverged from 15*44/2 by twenty games would mean a truncated or
# wrong-season wehoop pull -- but failing a publish over a two-game gap that is
# the exporter's own arithmetic, not a data defect, would make the gate
# permanently red, and a permanently red gate is one everybody learns to
# ignore. The right fix is for the exporter to publish the measured count (and
# ideally both); that is an exporter change, noted here as follow-up.
# ------------------------------------------------------------------------------
.pw_normalize_team_abbr <- function(x) {
  # The CONN -> CON normalisation documented in CLAUDE.md. Deliberately not
  # imported from daily_ingest.R's normalize_team_abbreviation(): sourcing that
  # file runs an ingestion script. This is the one rule it applies that matters
  # for a team COUNT, and it is stated here with that limitation named rather
  # than silently reimplementing the whole helper.
  x <- as.character(x)
  ifelse(x == "CONN", "CON", x)
}

.compute_coverage_from_schedule <- function(season = CURRENT_SEASON,
                                            schedule_path = CACHE_WNBA_SCHEDULE) {
  empty <- list(season = NA_integer_, teams_count = NA_integer_,
                total_schedule_games = NA_integer_, completed_games = NA_integer_,
                last_completed = NA, path = schedule_path, note = NULL)
  if (!file.exists(schedule_path)) {
    empty$note <- sprintf("%s is absent", basename(schedule_path))
    return(empty)
  }
  sched <- tryCatch(as.data.frame(readRDS(schedule_path)), error = function(e) NULL)
  if (is.null(sched)) {
    empty$note <- "schedule cache unreadable"
    return(empty)
  }
  need <- c("game_id", "game_date", "season", "season_type", "team_abbreviation")
  if (!all(need %in% names(sched))) {
    empty$note <- sprintf("schedule cache lacks %s",
                          paste(setdiff(need, names(sched)), collapse = ", "))
    return(empty)
  }

  s <- sched[!is.na(sched$season) & as.integer(sched$season) == as.integer(season), , drop = FALSE]
  if (!nrow(s)) {
    empty$note <- sprintf("schedule cache holds no season-%d rows", as.integer(season))
    return(empty)
  }

  abbr <- .pw_normalize_team_abbr(s$team_abbreviation)
  franchises <- unique(abbr[abbr %in% names(WNBA_TEAMS)])

  games <- s[!duplicated(s$game_id), , drop = FALSE]
  regular <- games[!is.na(games$season_type) & as.integer(games$season_type) == 2L, , drop = FALSE]

  completed <- if ("is_completed" %in% names(games)) {
    games[!is.na(games$is_completed) & as.logical(games$is_completed), , drop = FALSE]
  } else {
    games[0, , drop = FALSE]
  }
  last_completed <- if (nrow(completed)) max(as.Date(completed$game_date), na.rm = TRUE) else NA

  list(season = as.integer(season),
       teams_count = length(franchises),
       total_schedule_games = as.integer(nrow(regular)),
       completed_games = as.integer(nrow(completed)),
       last_completed = last_completed,
       path = schedule_path, note = NULL)
}

.assert_schedule_coverage <- function(season = CURRENT_SEASON,
                                      game_count_tolerance = 8L,
                                      published_override = NULL) {
  computed <- .compute_coverage_from_schedule(season)
  note <- computed$note
  published <- list(season = NA_integer_, teams_count = NA_integer_,
                    total_schedule_games = NA_integer_)

  if (!is.null(published_override)) {
    published <- published_override
  } else if (!file.exists(WEB_JSON_PROJECTIONS_MODELS_METADATA)) {
    note <- c(note, sprintf("%s is absent", basename(WEB_JSON_PROJECTIONS_MODELS_METADATA)))
  } else {
    j <- tryCatch(jsonlite::fromJSON(WEB_JSON_PROJECTIONS_MODELS_METADATA,
                                     simplifyVector = TRUE),
                  error = function(e) {
                    note <<- c(note, paste("unparseable JSON:", conditionMessage(e)))
                    NULL
                  })
    if (!is.null(j)) {
      if (!is.null(j$season))      published$season      <- as.integer(j$season[1])
      if (!is.null(j$teams_count)) published$teams_count <- as.integer(j$teams_count[1])
      if (!is.null(j$total_schedule_games)) {
        published$total_schedule_games <- as.integer(j$total_schedule_games[1])
      }
    }
  }

  # FATAL sub-checks: the season the site claims, and the number of franchises.
  season_ok <- !is.na(published$season) && identical(published$season, as.integer(season))
  teams_ok  <- !is.na(computed$teams_count) && !is.na(published$teams_count) &&
               identical(computed$teams_count, published$teams_count) &&
               identical(computed$teams_count, as.integer(WNBA_TEAM_COUNT))
  # REPORTED sub-check: see the long note above on why this one is not fatal.
  games_gap <- if (is.na(computed$total_schedule_games) || is.na(published$total_schedule_games)) {
    NA_integer_
  } else {
    as.integer(abs(computed$total_schedule_games - published$total_schedule_games))
  }
  games_within <- !is.na(games_gap) && games_gap <= game_count_tolerance

  pass <- isTRUE(season_ok) && isTRUE(teams_ok)

  list(id = "B", name = "schedule coverage (schedule cache vs published metadata header)",
       pass = pass, fatal = TRUE,
       computed = computed, published = published, games_gap = games_gap,
       detail = c(
         sprintf("    season        computed=%s published=%s  %s",
                 ifelse(is.na(computed$season), "<NA>", computed$season),
                 ifelse(is.na(published$season), "<NA>", published$season),
                 if (season_ok) "[OK]" else "[FAIL]"),
         sprintf("    franchises    computed=%s published=%s  (WNBA_TEAM_COUNT=%d) %s",
                 ifelse(is.na(computed$teams_count), "<NA>", computed$teams_count),
                 ifelse(is.na(published$teams_count), "<NA>", published$teams_count),
                 as.integer(WNBA_TEAM_COUNT),
                 if (teams_ok) "[OK]" else "[FAIL]"),
         sprintf("    reg. games    measured=%s published=%s  gap=%s tol=%d %s",
                 ifelse(is.na(computed$total_schedule_games), "<NA>", computed$total_schedule_games),
                 ifelse(is.na(published$total_schedule_games), "<NA>", published$total_schedule_games),
                 ifelse(is.na(games_gap), "<NA>", games_gap),
                 as.integer(game_count_tolerance),
                 if (games_within) "[reported, not fatal]" else "[reported, OUT OF TOLERANCE]"),
         "    note: the published game count is WNBA_TEAM_COUNT * WNBA_SEASON_GAMES / 2,",
         "          a structural constant, not a measurement - see this assertion's header.",
         sprintf("    completed     %s game(s), last on %s",
                 ifelse(is.na(computed$completed_games), "<NA>", computed$completed_games),
                 ifelse(is.na(computed$last_completed), "<NA>", format(computed$last_completed))),
         sprintf("    recomputed from %s", basename(computed$path)),
         if (length(note)) paste("    note:", note)),
       summary = sprintf("season=%s teams=%s/%s games measured=%s published=%s (gap %s)",
                         ifelse(is.na(published$season), "<NA>", published$season),
                         ifelse(is.na(computed$teams_count), "<NA>", computed$teams_count),
                         ifelse(is.na(published$teams_count), "<NA>", published$teams_count),
                         ifelse(is.na(computed$total_schedule_games), "<NA>", computed$total_schedule_games),
                         ifelse(is.na(published$total_schedule_games), "<NA>", published$total_schedule_games),
                         ifelse(is.na(games_gap), "<NA>", games_gap)))
}

# ------------------------------------------------------------------------------
# ASSERTION C - non-empty diff under the published trees.
# Resolved against the RUNTIME git root, never a hardcoded path.
# WEB_MEDIA_DIR is included alongside WEB_DATA_DIR; see the header note on the
# bracket page's trajectory GIF.
# ------------------------------------------------------------------------------
.assert_nonempty_diff <- function(repo_root) {
  if (is.na(repo_root)) {
    return(list(id = "C", name = "non-empty diff under web/public/{data,media}",
                pass = FALSE, fatal = TRUE, changed = character(0), paths = character(0),
                detail = "    could not resolve a git repository for the working directory",
                summary = "no git repo"))
  }
  rel <- c(.pw_rel_to_repo(WEB_DATA_DIR, repo_root),
           .pw_rel_to_repo(WEB_MEDIA_DIR, repo_root))
  r <- .pw_git(repo_root, c("status", "--porcelain", "--", rel))
  changed <- if (r$ok) r$out[nzchar(r$out)] else character(0)
  list(id = "C", name = "non-empty diff under web/public/{data,media}",
       pass = length(changed) > 0, fatal = TRUE, changed = changed, paths = rel,
       detail = if (length(changed)) paste0("    ", changed)
                else sprintf("    CLEAN against HEAD - nothing to publish (repo: %s)", repo_root),
       summary = sprintf("%d pending change(s) under %s", length(changed),
                         paste(rel, collapse = " / ")))
}

# ------------------------------------------------------------------------------
# ASSERTION D - synthetic-fallback and warning scan for the run window.
#
# Matches both the repo's SYNTHETIC_FALLBACK marker and plain [WARN] lines.
# SYNTHETIC_FALLBACK is matched case-sensitively on the marker itself rather
# than on a script field, because the fallback is logged from inside sourced
# function bodies whose recorded script name is not reliably the file name --
# the same reason NFL's exporter scan matches on the message instead.
# ------------------------------------------------------------------------------
.scan_fallback_warnings <- function(log_lines, run_start) {
  idx <- grep("SYNTHETIC_FALLBACK|\\[WARN\\]", log_lines)
  if (!length(idx)) return(character(0))
  hits <- log_lines[idx]
  if (!is.na(run_start)) {
    ts <- .pw_log_timestamp(hits)
    hits <- hits[!is.na(ts) & ts >= run_start]
  }
  as.character(hits)
}

.assert_log_scan <- function(log_lines, run_start, fail_on_warnings) {
  warns <- .scan_fallback_warnings(log_lines, run_start)
  synth <- grep("SYNTHETIC_FALLBACK", warns, value = TRUE)
  list(id = "D", name = "synthetic-fallback / [WARN] scan of the pipeline log",
       pass = !(fail_on_warnings && length(warns) > 0),
       fatal = fail_on_warnings,
       warnings = warns, synthetic = synth,
       detail = if (length(warns)) paste0("    ", warns)
                else "    no SYNTHETIC_FALLBACK or [WARN] lines in the run window",
       summary = sprintf("%d warning(s), %d of them SYNTHETIC_FALLBACK%s",
                         length(warns), length(synth),
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
# Only the top of each file is read: these payloads reach several MB and
# `generated_at` is written in the first object, so slurping each whole document
# through jsonlite to reach one scalar would slow every scheduled run for
# nothing. The regex is anchored on the key, not on a position.
#
# A trailing "Z" is parsed as UTC and its absence as local time. WNBA's single
# stamped payload writes the Z form, but the NBA port found two payloads in one
# repo disagreeing about it, so the parser handles both rather than assuming the
# convention holds -- on an 08:00 local run, guessing wrong is a four-hour
# error, easily enough to call a stale payload fresh.
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
              sprintf("    [NO STAMP] %d of %d payload(s) carry no generated_at, so F cannot speak",
                      length(unstamped), length(files)),
              "               for them. This is the weakest provenance coverage of the four",
              "               sports; stamping the rest is the top follow-up from this port.",
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
# THE GAP THIS CLOSES, measured 2026-10-26. That morning the gate reported all
# six assertions PASS at 08:01 over payloads the web contract suite REJECTS:
# web/tests/contracts/invariants.test.ts' zero-sum check reads
# sum(proj_wins) = 331.00 against the total_schedule_games = 330 published in
# the same payload set.
#
# A to F ask WHEN a file was written, WHETHER its bytes changed, WHAT the log
# said, WHOSE branch it is on and WHEN the payload says it was generated. Not
# one of them reads the numbers inside and asks whether they agree with each
# other. A fresh, diffed, correctly-stamped payload full of wrong numbers
# passes all six.
#
# The suite that does ask already exists, and as of today it runs in CI - but
# CI runs over the COMMITTED tree, i.e. after a publish, which is too late to
# stop one. Pointing its `contracts` stage at the uncommitted payload is the
# whole of this assertion. It is vitest over JSON: no browser, no build,
# about three seconds.
#
# ONLY the `contracts` stage. typecheck, lint, build and e2e are claims about
# the code, and the code is not what this gate is deciding about.
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
# assertion passed. Commits the published trees and pushes WNBA_analytics --
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
  record("git add web/public/{data,media}",
         .pw_git(repo_root, c("add", "--", rel_paths)))
  record("git commit (WNBA_analytics)",
         .pw_git(repo_root, c("commit", "-m", shQuote(commit_message))))
  record("git push origin HEAD (WNBA_analytics)",
         .pw_git(repo_root, c("push", "origin", "HEAD")))
  steps
}

# ------------------------------------------------------------------------------
# publish_web() - the explicitly-callable entry point.
#
# Deliberately NOT guarded by a `sys.nframe() == 0`-style top-level-only check:
# that is a documented silent-no-op failure mode originating in THIS repo
# (docs/WNBA_REPLICATION_PLAN.md section 1, cited by all three sibling repos),
# because source()ing from an orchestrator changes frame depth, so the guard
# no-ops while still reporting success. Callers invoke this function
# explicitly; the CLI wrapper at the bottom keys off commandArgs(), not frame
# depth.
# ------------------------------------------------------------------------------
publish_web <- function(dry_run = TRUE,
                        run_start = NULL,
                        season = CURRENT_SEASON,
                        publish_branch = "main",
                        fail_on_exporter_warnings = FALSE,
                        skip_contracts = FALSE,
                        commit_message = NULL) {

  repo_root <- .pw_repo_root()
  log_lines <- if (file.exists(LOG_FILE)) readLines(LOG_FILE, warn = FALSE) else character(0)
  if (is.null(run_start)) run_start <- .pw_detect_run_start(log_lines)
  if (is.null(commit_message)) {
    commit_message <- sprintf("Publish WNBA web artifacts from the %s pipeline run",
                              if (is.na(run_start)) format(Sys.Date()) else format(run_start, "%Y-%m-%d %H:%M"))
  }

  checks <- list(
    .assert_mtime_freshness(run_start),
    .assert_schedule_coverage(season),
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
  cat(sprintf("WNBA web publish gate  [%s]\n",
              if (dry_run) "DRY RUN - nothing will be published" else "LIVE PUBLISH"))
  cat("================================================================\n")
  cat(sprintf("  repo root        : %s\n", ifelse(is.na(repo_root), "<not a git repo>", repo_root)))
  cat(sprintf("  publish branch   : %s\n", publish_branch))
  cat(sprintf("  season           : %d\n", as.integer(season)))
  cat(sprintf("  pipeline log     : %s (%d lines)\n", LOG_FILE, length(log_lines)))
  cat(sprintf("  run start        : %s\n",
              ifelse(is.na(run_start), "<undetected>", format(run_start, "%Y-%m-%d %H:%M:%S"))))
  cat(sprintf("  schedule cache   : %s\n", CACHE_WNBA_SCHEDULE))
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
  media <- if (dir.exists(WEB_MEDIA_DIR)) list.files(WEB_MEDIA_DIR) else character(0)
  cat(sprintf("  %d visual-media file(s) from %s\n", length(media), WEB_MEDIA_DIR))
  cat(sprintf("  commit message   : %s\n", commit_message))
  cat(sprintf("  push sequence    : commit -> push WNBA_analytics %s (deploy belongs to the aggregator's sync-sports.yml)\n",
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
    coverage_computed = checks[[2]]$computed,
    coverage_published = checks[[2]]$published,
    publish_branch_actual = checks[[4]]$branch,
    fallback_warnings = checks[[5]]$warnings,
    synthetic_fallbacks = checks[[5]]$synthetic,
    stale_payloads = checks[[6]]$stale,
    unstamped_payloads = checks[[6]]$unstamped,
    contracts_pass = isTRUE(checks[[7]]$pass),
    pending_changes = checks[[3]]$changed,
    checks = checks, published = FALSE, steps = list()
  )

  if (blocked || dry_run) return(invisible(result))

  result$steps <- .pw_do_publish(repo_root, checks[[3]]$paths, commit_message)
  result$published <- TRUE
  log_info(sprintf("publish_web: web artifacts committed and pushed to WNBA_analytics %s. The site changes when the aggregator's sync-sports.yml next pulls; this script does not deploy.",
                   publish_branch), script = .PW_LOG_SCRIPT)
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
