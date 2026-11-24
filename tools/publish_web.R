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
#   H  data manifest completeness + schedule-coverage lag (front-office#102, #191)
#      - corresponds to WNBA assertion I; scoped off-season (MLB-Analytics#147)
#      to live files while keeping completeness/stamp checks across all files.
#   L  landing digest contract (front-office#200, MLB-Analytics#124).
#   M  lifecycle (MLB-Analytics#147; corresponds to WNBA assertion L) - every
#      data file's manifest entry carries a lifecycle (live | season_final |
#      archived) that matches config.R, and every season_final file still
#      hashes to its frozen_sha256. A file with no lifecycle fails in both
#      modes. Off-season, F and H run in full on LIVE files only; season_final
#      files are pinned by M's hash check instead of being stamp/lag-checked;
#      archived files are listed. In-season, A-H are unchanged. Freeze a
#      finished season with tools/freeze_season.R.
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
#   Off-season (#74): the run start must be passed; omitting it fails closed.
#     Rscript tools/publish_web.R --mode=offseason --run-start=2026-11-18T07:00:00
#     Rscript tools/publish_web.R --mode=offseason   # BLOCKED: run start unknown
#   tools/offseason/test_dag_end_to_end.R Tests 7-9 run both against fixtures.
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

if (nzchar(Sys.getenv("R_LIBS_USER")) && dir.exists(Sys.getenv("R_LIBS_USER"))) {
  .libPaths(unique(c(Sys.getenv("R_LIBS_USER"), .libPaths())))
}

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
# Push with fetch-rebase-retry. Shared by .pw_do_publish() and
# .pw_promote_offseason_baseline().
#
# On 2026-11-24 a scheduled publish committed locally, then `git push origin
# HEAD` was rejected ("fetch first") because PRs merged into main while the
# pipeline ran. The local commit stayed behind, the checkout diverged from
# origin, and the next run's push would have failed the same way. So, after
# the publish commit:
#   1. git fetch origin <branch>
#   2. if origin/<branch> is not an ancestor of HEAD: git rebase origin/<branch>
#      (publish commits only touch generated data; never a merge commit)
#   3. push; if rejected, repeat 1-2 once and push once more
# If a rebase cannot complete (conflict, or git refuses because tracked files
# are modified outside the commit), or the second push is also rejected:
# `git rebase --abort`, then `git reset --mixed origin/<branch>` -- the branch
# is back in step with origin and the regenerated files stay in the working
# tree (no stash, no reset --hard) -- and the step fails with a message saying so.
# Each step is logged on its own line so pipeline_execution.log shows it.
# ------------------------------------------------------------------------------
.pw_push_with_rebase <- function(repo_root, branch = NULL, label = "MLB-Analytics") {
  if (is.null(branch) || is.na(branch) || !nzchar(branch)) {
    branch <- .pw_current_branch(repo_root)
  }
  if (is.na(branch)) {
    stop("publish_web: cannot push: HEAD is detached or the repository has no branch.")
  }
  remote_ref <- paste0("origin/", branch)
  steps <- list()
  note <- function(step, res) {
    steps[[length(steps) + 1L]] <<- list(label = step, ok = res$ok, out = res$out)
    invisible(res)
  }
  sha_of <- function(ref) {
    r <- .pw_git(repo_root, c("rev-parse", "--verify", "--quiet", ref))
    if (r$ok && length(r$out)) r$out[1] else NA_character_
  }
  fail_back_to_origin <- function(reason, out) {
    # A rebase in progress (conflict) is aborted; when none is in progress this
    # just exits non-zero and changes nothing.
    note("git rebase --abort", .pw_git(repo_root, c("rebase", "--abort")))
    reset <- note(sprintf("git reset --mixed %s", remote_ref),
                  .pw_git(repo_root, c("reset", "--mixed", "-q", remote_ref)))
    tip <- sha_of(remote_ref)
    msg <- if (reset$ok) {
      sprintf(paste0("publish_web: the publish commit was NOT pushed (%s). The checkout is back in step ",
                     "with %s (%s): the local publish commit was dropped with `git reset --mixed`, ",
                     "and the regenerated files are still in the working tree for the next run."),
              reason, remote_ref, tip)
    } else {
      sprintf(paste0("publish_web: the publish commit was NOT pushed (%s), and resetting the branch ",
                     "to %s also failed, so the local branch may still hold the unpushed publish ",
                     "commit. Inspect the checkout before the next run."),
              reason, remote_ref)
    }
    log_error(msg, script = .PW_LOG_SCRIPT)
    stop(paste(c(msg, out, if (!reset$ok) reset$out), collapse = "\n"), call. = FALSE)
  }
  sync_with_remote <- function() {
    f <- note(sprintf("git fetch origin %s", branch),
              .pw_git(repo_root, c("fetch", "origin",
                                   sprintf("+refs/heads/%s:refs/remotes/%s", branch, remote_ref))))
    if (!f$ok) {
      stop(sprintf("publish_web: git fetch origin %s failed; nothing was pushed and the local publish commit is still on %s:\n%s",
                   branch, branch, paste(f$out, collapse = "\n")), call. = FALSE)
    }
    tip <- sha_of(remote_ref)
    log_info(sprintf("publish_web: fetched origin %s (%s at %s).", branch, remote_ref, tip),
             script = .PW_LOG_SCRIPT)
    anc <- .pw_git(repo_root, c("merge-base", "--is-ancestor", remote_ref, "HEAD"))
    if (anc$ok) return(invisible(TRUE))
    rb <- note(sprintf("git rebase %s", remote_ref),
               .pw_git(repo_root, c("rebase", remote_ref)))
    if (!rb$ok) {
      fail_back_to_origin(sprintf("rebase onto %s at %s failed", remote_ref, tip), rb$out)
    }
    log_info(sprintf("publish_web: rebased the publish commit onto the remote tip %s (%s); HEAD is now %s.",
                     remote_ref, tip, sha_of("HEAD")), script = .PW_LOG_SCRIPT)
    invisible(TRUE)
  }
  push_once <- function() {
    note(sprintf("git push origin HEAD (%s)", label),
         .pw_git(repo_root, c("push", "origin", "HEAD")))
  }

  sync_with_remote()
  p <- push_once()
  if (!p$ok) {
    log_warn(sprintf("publish_web: push to origin %s was rejected; fetching and rebasing once more before retrying.",
                     branch), script = .PW_LOG_SCRIPT)
    sync_with_remote()
    p <- push_once()
    if (!p$ok) {
      # Refresh origin/<branch> so the reset below lands on the real remote tip.
      note(sprintf("git fetch origin %s", branch),
           .pw_git(repo_root, c("fetch", "origin",
                                sprintf("+refs/heads/%s:refs/remotes/%s", branch, remote_ref))))
      fail_back_to_origin(sprintf("push to origin %s was rejected twice", branch), p$out)
    }
  }
  log_info(sprintf("publish_web: pushed %s to origin %s.", sha_of("HEAD"), branch),
           script = .PW_LOG_SCRIPT)
  steps
}

# ------------------------------------------------------------------------------
# Off-season baseline promotion (blueprint section 2 & 7), called by
# publish_web() only after a successful publish commit, only in offseason mode
# and only without --allow-degraded. Copies <cache_root>/league_state_staged.json
# over league_state_baseline.json, then commits and pushes the baseline when it
# is this repo's tracked cache/ copy. Extracted so it can be tested against a
# throwaway repo (tests/testthat/test-offseason-baseline-promotion.R).
# ------------------------------------------------------------------------------
.pw_promote_offseason_baseline <- function(repo_root, cache_root, publish_branch = NULL) {
  staged_file <- file.path(cache_root, "league_state_staged.json")
  baseline_file <- file.path(cache_root, "league_state_baseline.json")
  if (file.exists(staged_file)) {
    file.copy(staged_file, baseline_file, overwrite = TRUE)
    log_info("publish_web: atomically promoted league_state_staged.json to league_state_baseline.json",
             script = .PW_LOG_SCRIPT)

    # The promotion lands AFTER publish_web()'s publish commit, so without this the
    # tracked baseline stays modified-but-uncommitted, and the next run's
    # checkout guard stashes it -- rolling the promotion back (MLB-Analytics#106).
    # Commit + push it as a follow-up commit, as WNBA_analytics#202 does.
    # Only when the promoted file IS this repo's tracked cache/ copy (MLB_ANALYTICS_ROOT
    # can point the cache elsewhere).
    baseline_rel <- "cache/league_state_baseline.json"
    in_repo <- !is.na(repo_root) &&
      identical(normalizePath(baseline_file, winslash = "/", mustWork = FALSE),
                normalizePath(file.path(repo_root, baseline_rel), winslash = "/", mustWork = FALSE))
    if (in_repo && .pw_git(repo_root, c("ls-files", "--error-unmatch", "--", baseline_rel))$ok) {
      # -f: when cache/ is gitignored, `git add` exits 1 on the ignored path even
      # though the file is already tracked (the 2026-11-20 off-season run failed
      # here). .gitignore now un-ignores this one file; -f keeps the promotion
      # working regardless. The ls-files guard above means -f can only ever stage
      # this already-tracked file, never add a new one.
      add_res <- .pw_git(repo_root, c("add", "-f", "--", baseline_rel))
      if (!add_res$ok) {
        stop("publish_web: failed to stage promoted baseline:\n", paste(add_res$out, collapse = "\n"))
      }
      staged_diff <- .pw_git(repo_root, c("diff", "--cached", "--quiet", "--", baseline_rel))
      if (!staged_diff$ok) {  # --quiet exits 1 when there ARE staged changes
        c_res <- .pw_git(repo_root, c("commit", "-m", shQuote("Promote MLB offseason baseline after publish"),
                                      "--", baseline_rel))
        if (!c_res$ok) {
          stop("publish_web: baseline commit failed; baseline is promoted on disk but NOT committed:\n",
               paste(c_res$out, collapse = "\n"))
        }
        # Same fetch-rebase-retry as the publish push; on failure it resets the
        # branch to origin and leaves the promoted baseline in the working tree.
        .pw_push_with_rebase(repo_root, publish_branch, label = "MLB-Analytics baseline")
        log_info("publish_web: committed and pushed promoted cache/league_state_baseline.json.",
                 script = .PW_LOG_SCRIPT)
      }
    }
  }
  invisible(NULL)
}

# ------------------------------------------------------------------------------
# Run-start discovery.
#
# Off-season (MLB-Analytics#74): the run start is passed in explicitly. The
# orchestrator (schedule_weekly_offseason.bat) records it once at the top of
# its run and hands it to Step 3 as --run-start=YYYY-MM-DDTHH:MM:SS (local
# time). It is NEVER inferred from the log: the off-season orchestrator does
# not emit "Pipeline run started", so a grep resolves to the last in-season
# run (frozen at 2026-10-31 09:00:19 once the in-season task was disabled),
# and Gate A then certified ten-day-old files as FRESH. A missing or
# unparseable run start resolves to NA, and NA fails closed: Gate A marks
# every dataset STALE (fatal), so nothing is published.
#
# In-season: unchanged. run_full_pipeline.R emits the "Pipeline run started."
# marker for its own run (logging_utils.R's
# "[YYYY-MM-DD HH:MM:SS] [LEVEL] [script] msg" format), so a NULL run_start
# still falls back to that grep there.
# ------------------------------------------------------------------------------
.pw_log_timestamp <- function(lines) {
  ts <- sub("^\\[([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})\\].*$", "\\1", lines)
  ts[!grepl("^[0-9]{4}-", ts)] <- NA_character_
  as.POSIXct(ts, format = "%Y-%m-%d %H:%M:%S", tz = "")
}

# Parses an explicitly passed run start. Accepts a length-1 POSIXct, or a
# "YYYY-MM-DDTHH:MM:SS" / "YYYY-MM-DD HH:MM:SS" local-time string. Anything
# else (NULL, "", garbage, a date with no time, an impossible value such as
# 2026-02-30) returns NA -- never a guessed value.
.pw_parse_run_start <- function(x) {
  na <- as.POSIXct(NA_character_, tz = "")
  if (inherits(x, "POSIXct")) return(if (length(x) == 1L) x else na)
  if (!is.character(x) || length(x) != 1L || is.na(x)) return(na)
  s <- sub("T", " ", trimws(x), fixed = TRUE)
  if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$", s)) return(na)
  out <- as.POSIXct(s, format = "%Y-%m-%d %H:%M:%S", tz = "")
  # Round-trip so strptime cannot silently roll an impossible value forward.
  if (is.na(out) || !identical(format(out, "%Y-%m-%d %H:%M:%S"), s)) return(na)
  out
}

# The single place publish_web() turns its run_start argument into the value
# every gate compares against. Off-season never reads the log for it.
.pw_resolve_run_start <- function(run_start, mode, log_lines) {
  if (identical(mode, "offseason")) {
    if (is.null(run_start)) return(as.POSIXct(NA_character_, tz = ""))
    return(.pw_parse_run_start(run_start))
  }
  if (is.null(run_start)) return(.pw_detect_run_start(log_lines))
  if (is.character(run_start)) return(.pw_parse_run_start(run_start))
  run_start
}

.pw_detect_run_start <- function(log_lines) {
  hits <- grep("Pipeline run started", log_lines, fixed = TRUE)
  if (!length(hits)) return(NA)
  tail(.pw_log_timestamp(log_lines[hits]), 1)
}

# ------------------------------------------------------------------------------
# Zero-Betting Policy Guard Check
# ------------------------------------------------------------------------------
# Commercial sportsbook bans while whitelisting mathematical modeling terms:
# draft lottery, lottery odds, arbitration model probability, projection interval.
.PW_FORBIDDEN_BETTING_DOMAINS <- c(
  "draftkings.com", "fanduel.com", "betmgm.com", "caesars.com/sportsbook",
  "pointsbet.com", "bovada.lv", "bet365.com", "betonline.ag", "barstoolsportsbook.com"
)

.PW_FORBIDDEN_BETTING_TERMS <- c(
  "sportsbook", "betmgm", "draftkings", "fanduel", "pointsbet", "bovada", "bet365",
  "moneyline", "runline", "over/under", "\\bparlay\\b", "\\bvig\\b", "\\bjuice\\b", "\\bprop bet\\b"
)

.assert_zero_betting <- function(files) {
  violations <- character(0)
  for (f in files) {
    if (!file.exists(f)) next
    txt <- tryCatch(readLines(f, warn = FALSE, encoding = "UTF-8"), error = function(e) character(0))
    if (!length(txt)) next
    
    # Check forbidden domains
    for (dom in .PW_FORBIDDEN_BETTING_DOMAINS) {
      if (any(grepl(dom, txt, ignore.case = TRUE))) {
        violations <- c(violations, sprintf("%s: forbidden sportsbook domain '%s'", basename(f), dom))
      }
    }
    
    # Check forbidden wagering terms
    for (term in .PW_FORBIDDEN_BETTING_TERMS) {
      matches <- grep(term, txt, ignore.case = TRUE)
      if (length(matches) > 0) {
        # Check against whitelisted context:
        # whitelist mathematical terms: draft lottery, lottery odds, arbitration model probability, projection interval
        viol_lines <- txt[matches]
        whitelisted <- grepl("draft lottery|lottery odds|arbitration model probability|projection interval",
                             viol_lines, ignore.case = TRUE)
        if (any(!whitelisted)) {
          violations <- c(violations, sprintf("%s: forbidden betting term '%s'", basename(f), term))
        }
      }
    }
  }
  
  pass <- length(violations) == 0
  list(id = "ZERO_BETTING", name = "zero-betting policy guard",
       pass = pass, fatal = TRUE, violations = violations,
       detail = if (length(violations)) paste0("    [VIOLATION] ", violations)
                else "    all published files strictly conform to zero-betting policy",
       summary = sprintf("%d zero-betting violation(s) detected", length(violations)))
}

# Files the zero-betting policy guard reads. In off-season mode
# cbt_payroll_sheet.json and projections_season_teams.json are not in
# WEB_DATA_FILES_OFFSEASON (the off-season run does not regenerate them), but
# their committed copies are still served, so the guard keeps reading them.
# This is a read-only content check, not a freshness check.
.policy_guard_files <- function(target_files, mode = "inseason") {
  if (identical(mode, "offseason")) {
    unique(c(target_files, WEB_JSON_CBT_PAYROLL_SHEET, WEB_JSON_PROJECTIONS_SEASON_TEAMS,
             WEB_JSON_LANDING_DIGEST))
  } else {
    target_files
  }
}

# ------------------------------------------------------------------------------
# ASSERTION A - mtime freshness
# ------------------------------------------------------------------------------
.assert_mtime_freshness <- function(run_start, mode = "inseason") {
  files <- if (identical(mode, "offseason")) WEB_DATA_FILES_OFFSEASON else WEB_DATA_FILES
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
  list(id = "A", name = sprintf("mtime freshness (%s datasets newer than run start)",
                                if (identical(mode, "offseason")) "WEB_DATA_FILES_OFFSEASON" else "WEB_DATA_FILES"),
       pass = length(stale) == 0, fatal = TRUE,
       detail = unlist(rows), stale = stale,
       summary = if (is.na(run_start)) {
         sprintf("run start unknown - all %d published datasets treated as STALE (fail closed)", length(files))
       } else {
         sprintf("%d/%d published datasets regenerated after run start %s",
                 length(files) - length(stale), length(files),
                 format(run_start, "%Y-%m-%d %H:%M:%S"))
       })
}

# ------------------------------------------------------------------------------
# ASSERTION B - slate agreement / offseason phase validation
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

.VALID_OFFSEASON_PHASES <- c(
  "Post-World Series Review",
  "Option & Qualifying Offer Window",
  "Pre-Lockout Surge",
  "Transaction Freeze",
  "Winter Meetings & Rule 5 Draft",
  "Arbitration Exchange & Hearings",
  "Spring Training Transition"
)

.assert_offseason_phase <- function(monitor_path = WEB_JSON_OFFSEASON_MONITOR) {
  if (!file.exists(monitor_path)) {
    return(list(id = "B", name = "offseason phase and week bounds validation",
                pass = FALSE, fatal = TRUE,
                detail = sprintf("    %s is absent", basename(monitor_path)),
                summary = "offseason monitor dataset absent"))
  }
  d <- tryCatch(jsonlite::fromJSON(monitor_path, simplifyDataFrame = FALSE), error = function(e) NULL)
  if (is.null(d)) {
    return(list(id = "B", name = "offseason phase and week bounds validation",
                pass = FALSE, fatal = TRUE,
                detail = "    cannot parse offseason_monitor.json",
                summary = "JSON parse error"))
  }
  
  phase <- d$activePhase
  week_num <- d$currentWeekNumber
  phase_ok <- !is.null(phase) && phase %in% .VALID_OFFSEASON_PHASES
  week_ok <- !is.null(week_num) && is.numeric(week_num) && week_num >= 1 && week_num <= 30
  
  pass <- phase_ok && week_ok
  detail <- c(
    sprintf("    activePhase       : %s [%s]", ifelse(is.null(phase), "<NULL>", phase), if (phase_ok) "VALID" else "INVALID"),
    sprintf("    currentWeekNumber : %s [%s]", ifelse(is.null(week_num), "<NULL>", week_num), if (week_ok) "IN BOUNDS (1-30)" else "OUT OF BOUNDS"),
    sprintf("    operatingStatus   : %s", ifelse(is.null(d$leagueOperatingStatus), "<NULL>", d$leagueOperatingStatus))
  )
  list(id = "B", name = "offseason phase and week bounds validation",
       pass = pass, fatal = TRUE,
       detail = detail,
       summary = sprintf("phase='%s' week=%s", ifelse(is.null(phase), "NULL", phase), ifelse(is.null(week_num), "NULL", week_num)))
}

.assert_slate_agreement <- function(season = MLB_CURRENT_SEASON,
                                    week_tolerance = 1L,
                                    published_override = NULL,
                                    mode = "inseason") {
  if (identical(mode, "offseason")) {
    return(.assert_offseason_phase())
  }
  
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
# ------------------------------------------------------------------------------
.pw_rel_to_repo <- function(path, repo_root) {
  if (is.na(repo_root)) return(path)
  p <- normalizePath(path, winslash = "/", mustWork = FALSE)
  r <- paste0(sub("/$", "", repo_root), "/")
  if (startsWith(p, r)) substring(p, nchar(r) + 1L) else p
}

.assert_nonempty_diff <- function(repo_root, mode = "inseason") {
  if (is.na(repo_root)) {
    return(list(id = "C", name = "non-empty diff under web/public/data",
                pass = FALSE, fatal = TRUE, changed = character(0), paths = character(0),
                detail = "    could not resolve a git repository for the working directory",
                summary = "no git repo"))
  }
  rel <- .pw_rel_to_repo(WEB_DATA_DIR, repo_root)
  r <- .pw_git(repo_root, c("status", "--porcelain", "--", rel))
  changed <- if (r$ok) r$out[nzchar(r$out)] else character(0)
  
  if (identical(mode, "offseason")) {
    # Off-season: check pending changes specifically in WEB_DATA_FILES_OFFSEASON
    off_rel <- vapply(WEB_DATA_FILES_OFFSEASON, function(p) .pw_rel_to_repo(p, repo_root), character(1))
    off_changed <- Filter(function(line) {
      any(vapply(off_rel, function(target) grepl(target, line, fixed = TRUE), logical(1)))
    }, changed)
    
    # Lockout tolerance check:
    # If ΔS = ∅, but freezeDayCount or lastPublished updated in offseason_monitor.json,
    # git status shows offseason_monitor.json modified, which satisfies off_changed > 0.
    # Furthermore, even if porcelain is clean, inspect if lastPublished or freezeDayCount advanced
    pass <- length(off_changed) > 0
    if (!pass && file.exists(WEB_JSON_OFFSEASON_MONITOR)) {
      # Check diff against HEAD for offseason_monitor.json
      monitor_rel <- .pw_rel_to_repo(WEB_JSON_OFFSEASON_MONITOR, repo_root)
      diff_head <- .pw_git(repo_root, c("diff", "HEAD", "--", monitor_rel))
      if (diff_head$ok && any(grepl('"lastPublished"|"freezeDayCount"', diff_head$out))) {
        pass <- TRUE
        off_changed <- c(off_changed, paste("M ", monitor_rel, "(lockout/timestamp advancement)"))
      }
    }
    
    # The edition archive is published with the monitor but is not one of the
    # freshness-checked files, so it has to be added to the staged paths here.
    # It used to be left out, which is why it stayed untracked: the live site
    # 404'd on it and the contract tests that read it failed in a fresh clone.
    stage_rel <- off_rel
    if (file.exists(WEB_JSON_OFFSEASON_ARCHIVE)) {
      stage_rel <- c(stage_rel, .pw_rel_to_repo(WEB_JSON_OFFSEASON_ARCHIVE, repo_root))
    }

    return(list(id = "C", name = "non-empty diff in offseason web data",
                pass = pass, fatal = TRUE, changed = off_changed, paths = stage_rel,
                detail = if (length(off_changed)) paste0("    ", off_changed)
                         else sprintf("    CLEAN against HEAD in offseason files (repo: %s)", repo_root),
                summary = sprintf("%d pending offseason change(s)", length(off_changed))))
  }
  
  list(id = "C", name = "non-empty diff under web/public/data",
       pass = length(changed) > 0, fatal = TRUE, changed = changed, paths = rel,
       detail = if (length(changed)) paste0("    ", changed)
                else sprintf("    CLEAN against HEAD - nothing to publish (repo: %s)", repo_root),
       summary = sprintf("%d pending change(s) under %s", length(changed), rel))
}

# ------------------------------------------------------------------------------
# ASSERTION D - exporter [WARN] scan & Ingestion Health
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

.assert_offseason_health <- function(allow_degraded = FALSE) {
  manifest_path <- file.path(MLB_CACHE_ROOT, "ingestion_manifest.json")
  if (!file.exists(manifest_path)) {
    # If no manifest exists, check if quiet week is being asserted
    return(list(id = "D", name = "ingestion health check (manifest composite_health)",
                pass = TRUE, fatal = TRUE,
                detail = "    [NOTE] ingestion_manifest.json not found; default HEALTHY assumed",
                summary = "no manifest (default HEALTHY)"))
  }
  manifest <- tryCatch(jsonlite::fromJSON(manifest_path, simplifyDataFrame = FALSE), error = function(e) NULL)
  comp_health <- if (!is.null(manifest$composite_health)) manifest$composite_health else "HEALTHY"
  
  pass <- identical(comp_health, "HEALTHY") || isTRUE(allow_degraded)
  
  # Wire adapter check
  wire_status <- if (!is.null(manifest$adapters$league_wire$status)) manifest$adapters$league_wire$status else "HEALTHY"
  if (identical(wire_status, "FAILED") && !allow_degraded) {
    pass <- FALSE
  }
  
  detail <- c(
    sprintf("    composite_health  : %s", comp_health),
    sprintf("    league_wire       : %s", wire_status),
    if (isTRUE(allow_degraded)) "    --allow-degraded flag active (advisory only; baseline promotion prohibited)"
  )
  
  list(id = "D", name = "ingestion health check (composite_health == HEALTHY)",
       pass = pass, fatal = TRUE,
       detail = detail,
       summary = sprintf("composite_health=%s wire=%s", comp_health, wire_status))
}

.assert_log_scan <- function(log_lines, run_start, fail_on_exporter_warnings,
                             mode = "inseason", allow_degraded = FALSE) {
  if (identical(mode, "offseason")) {
    return(.assert_offseason_health(allow_degraded))
  }
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

# Off-season scoping (MLB-Analytics#147). In-season F is unchanged: it walks
# WEB_DATA_FILES and an unstamped payload is reported, not failed. Off-season it
# walks every top-level data file by its manifest lifecycle:
#   live          stamp (generated_at, or lastPublished fallback for
#                 offseason_monitor.json) must be at or after run start; NO
#                 stamp FAILS, because a live off-season file is exactly what
#                 this run claims to rebuild
#   season_final  not read for a stamp; its bytes are pinned by frozen_sha256
#                 and assertion M fails on any change
#   archived      not read (static snapshot)
#   (none)        checked as live here, and assertion M fails it outright
.assert_payload_provenance <- function(run_start, mode = "inseason", manifest = NULL,
                                       data_dir = WEB_DATA_DIR) {
  if (identical(mode, "offseason")) {
    return(.assert_payload_provenance_offseason(run_start, manifest, data_dir))
  }
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
    rows <- c(rows, sprintf("    %-9s %-40s stamp=%s",
                            if (fresh) "[FRESH]" else "[STALE]", basename(f),
                            format(g, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")))
  }
  if (length(unstamped)) {
    rows <- c(rows,
              sprintf("    [NO STAMP] %d payload(s) carry no generated_at / lastPublished, so F cannot speak for them:",
                      length(unstamped)),
              paste0("               ", unstamped))
  }
  list(id = "F", name = "payload provenance (embedded timestamp at or after run start)",
       pass = length(stale) == 0, fatal = TRUE,
       stale = stale, unstamped = unstamped,
       detail = rows,
       summary = sprintf("%d stamped payload(s) fresh, %d stale, %d carry no stamp",
                         length(files) - length(stale) - length(unstamped),
                         length(stale), length(unstamped)))
}

.pw_manifest_entries <- function(manifest) {
  entries <- if (is.null(manifest) || !is.list(manifest$datasets)) list() else manifest$datasets
  names(entries) <- vapply(entries, function(e) as.character(e$file %||% ""), character(1))
  entries
}

.pw_data_files <- function(data_dir) {
  if (!dir.exists(data_dir)) return(character(0))
  setdiff(sort(list.files(data_dir, pattern = "[.]json$")), .PW_MANIFEST_FILE)
}

.pw_offseason_payload_stamp <- function(path, head_bytes = 4096L) {
  g <- .pw_payload_generated_at(path, head_bytes = head_bytes)
  if (!is.na(g) || !file.exists(path)) return(g)
  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw <- readBin(con, "raw", n = head_bytes)
  txt <- rawToChar(raw[raw != as.raw(0)])
  Encoding(txt) <- "UTF-8"
  m <- regmatches(txt, regexpr('"lastPublished"[[:space:]]*:[[:space:]]*"[^"]+"', txt))
  if (!length(m)) return(NA)
  val <- sub('^.*:[[:space:]]*"([^"]+)".*$', "\\1", m[1])
  as.POSIXct(val, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
}

.assert_payload_provenance_offseason <- function(run_start, manifest = NULL, data_dir = WEB_DATA_DIR) {
  if (is.null(manifest)) {
    mp <- file.path(data_dir, .PW_MANIFEST_FILE)
    if (file.exists(mp)) {
      manifest <- tryCatch(jsonlite::fromJSON(mp, simplifyVector = FALSE), error = function(e) NULL)
    }
  }
  entries <- .pw_manifest_entries(manifest)
  files <- .pw_data_files(data_dir)
  rows <- character(0); stale <- character(0); unstamped <- character(0)
  frozen <- character(0); archived <- character(0); checked <- 0L
  for (f in files) {
    lc <- entries[[f]]$lifecycle
    if (identical(lc, "season_final")) {
      frozen <- c(frozen, f)
      rows <- c(rows, sprintf("    %-9s %-40s season %s final (bytes pinned by frozen_sha256, see M)",
                              "[FROZEN]", f, as.character(entries[[f]]$season %||% "?")))
      next
    }
    if (identical(lc, "archived")) {
      archived <- c(archived, f)
      rows <- c(rows, sprintf("    %-9s %-40s archived snapshot, not rebuilt", "[ARCHIVED]", f))
      next
    }
    checked <- checked + 1L
    tag <- if (is.null(lc)) " (NO LIFECYCLE - checked as live)" else ""
    g <- .pw_offseason_payload_stamp(file.path(data_dir, f))
    if (is.na(g)) {
      unstamped <- c(unstamped, f)
      rows <- c(rows, sprintf("    %-9s %-40s live file carries no generated_at / lastPublished%s", "[NO STAMP]", f, tag))
      next
    }
    fresh <- !is.na(run_start) && g >= run_start
    if (!fresh) stale <- c(stale, f)
    rows <- c(rows, sprintf("    %-9s %-40s stamp=%s%s",
                            if (fresh) "[FRESH]" else "[STALE]", f,
                            format(g, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), tag))
  }
  if (length(stale) || length(unstamped)) {
    rows <- c(rows, "    A stale or unstamped LIVE file blocks. If it is a finished season's file that no",
              "    off-season stage rebuilds, freeze it: Rscript tools/freeze_season.R --season <yyyy>")
  }
  list(id = "F", name = "payload provenance (live files: embedded timestamp at or after run start)",
       pass = length(stale) == 0 && length(unstamped) == 0, fatal = TRUE,
       stale = stale, unstamped = unstamped, frozen = frozen, archived = archived,
       detail = rows,
       summary = sprintf("off-season: %d live file(s) checked - %d fresh, %d stale, %d unstamped; %d season_final, %d archived not stamp-checked",
                         checked, checked - length(stale) - length(unstamped), length(stale),
                         length(unstamped), length(frozen), length(archived)))
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
# ASSERTION H - data manifest completeness + schedule-coverage lag
# (front-office#102 sidecar manifest, front-office#191 lag gate).
#
# Reads web/public/data/data_manifest.json (written by
# tools/write_data_manifest.R; this file deliberately does NOT source that
# builder, so publish_web.R still sources on its own). Every top-level
# web/public/data/*.json must have a manifest entry with a valid UTC ISO-8601
# generated_at whose stamp_source is the payload itself or content-hash
# carry-forward. When schedule_through_date is known, each non-static
# game-dated dataset (through_date extracted from payload content) may lag it
# by at most max_lag_days; one whose through_date is on/after
# schedule_through_date (off-season: the schedule has ended) passes.
# not_game_dated datasets are labelled [UNDATED] and checked only on
# generated_at freshness. `static: true` passes only with a static_reason.
# Read-only: never writes to disk, so it is safe in dry runs.
# ------------------------------------------------------------------------------
.PW_MANIFEST_FILE <- "data_manifest.json"
.PW_MAX_LAG_DAYS  <- 3L

.pw_is_utc_iso <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) &&
    grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", x) &&
    !is.na(as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
}

# Off-season scoping (MLB-Analytics#147; corresponds to WNBA assertion I):
# with mode = "offseason", completeness (listed, valid UTC generated_at, allowed
# stamp_source) is still enforced for EVERY file, but the stamp/lag checks run
# on live files only. A season_final entry is reported [FROZEN] and its bytes
# are verified against frozen_sha256 by assertion M; an archived entry is
# reported [ARCHIVED]. An entry with no lifecycle is checked as live (and M
# fails it). In-season (the default) this function is unchanged.
# `manifest` lets the caller pass the manifest object to assert against (the
# off-season dry run passes an in-memory preview); NULL reads manifest_path.
.assert_manifest_and_coverage <- function(data_dir = WEB_DATA_DIR,
                                          manifest_path = file.path(data_dir, .PW_MANIFEST_FILE),
                                          max_lag_days = .PW_MAX_LAG_DAYS,
                                          schedule_through_date = NULL,
                                          mode = "inseason",
                                          manifest = NULL) {
  offseason <- identical(mode, "offseason")
  gate_name <- if (offseason) {
    "data manifest completeness + schedule-coverage lag (lag on live files)"
  } else {
    "data manifest completeness + schedule-coverage lag"
  }
  mk <- function(pass, summary, detail, coverage = list(), problems = character(0)) {
    list(id = "H", name = gate_name,
         pass = pass, fatal = TRUE, summary = summary, detail = detail,
         coverage = coverage, problems = problems)
  }
  on_disk <- if (dir.exists(data_dir)) {
    setdiff(list.files(data_dir, pattern = "[.]json$"), .PW_MANIFEST_FILE)
  } else character(0)
  if (is.null(manifest) && !file.exists(manifest_path)) {
    return(mk(FALSE, sprintf("%s absent - %d dataset(s) uncovered", .PW_MANIFEST_FILE, length(on_disk)),
              c(sprintf("    [MISSING] %s (run tools/write_data_manifest.R)", .PW_MANIFEST_FILE),
                sprintf("    [MISSING] %s", on_disk))))
  }
  m <- if (!is.null(manifest)) manifest else
    tryCatch(jsonlite::fromJSON(manifest_path, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(m) || !is.list(m$datasets)) {
    return(mk(FALSE, sprintf("%s unreadable", .PW_MANIFEST_FILE),
              sprintf("    [MISSING] %s does not parse as a manifest", .PW_MANIFEST_FILE)))
  }
  sched <- schedule_through_date
  if (is.null(sched)) sched <- m$schedule_through_date
  sched_d <- if (is.null(sched) || is.na(sched)) NA else as.Date(sched)

  entries <- list()
  for (e in m$datasets) if (is.list(e) && is.character(e$file)) entries[[e$file]] <- e

  rows <- character(0); bad <- character(0); problems <- character(0); coverage <- list()
  for (f in sort(union(on_disk, names(entries)))) {
    e <- entries[[f]]
    status <- "[OK]"; note <- ""; through <- NA_character_; lag <- NA_integer_
    if (is.null(e) || !.pw_is_utc_iso(e$generated_at)) {
      status <- "[MISSING]"
      note <- if (is.null(e)) "no manifest entry" else "no valid UTC ISO-8601 generated_at"
    } else if (!(f %in% on_disk)) {
      status <- "[MISSING]"; note <- "listed in manifest but absent on disk"
    } else if (!is.character(e$stamp_source) ||
               !grepl("^(payload:.+|manifest:content_hash)$", e$stamp_source)) {
      # FO#102: stamps come from the payload or content-hash carry-forward only,
      # never from file mtime, git history, or a sibling payload.
      status <- "[MISSING]"
      note <- sprintf("disallowed stamp_source '%s'", as.character(e$stamp_source %||% "<none>"))
    } else if (offseason && identical(e$lifecycle, "season_final")) {
      status <- "[FROZEN]"
      through <- if (is.character(e$final_through_date)) e$final_through_date else if (is.character(e$through_date)) e$through_date else NA_character_
      note <- sprintf("season %s final through %s (bytes checked by M)",
                      as.character(e$season %||% "?"),
                      as.character(e$final_through_date %||% "?"))
    } else if (offseason && identical(e$lifecycle, "archived")) {
      status <- "[ARCHIVED]"
      note <- sprintf("generated %s, not rebuilt", e$generated_at)
    } else if (isTRUE(e$static)) {
      if (is.character(e$static_reason) && nzchar(trimws(e$static_reason))) {
        status <- "[STATIC]"; note <- e$static_reason
      } else {
        status <- "[MISSING]"; note <- "static: true without static_reason"
      }
    } else if (identical(e$through_date_source, "not_game_dated")) {
      # FO#191: content carries no game dates, so only the build stamp can be
      # checked - and it never stands in for a through_date.
      status <- "[UNDATED]"
      gd <- as.Date(substr(e$generated_at, 1, 10))
      if (is.na(sched_d)) {
        note <- "schedule_through_date unknown - stamp freshness not measured"
      } else {
        lag <- max(0L, as.integer(sched_d - gd))
        if (lag > max_lag_days) {
          status <- "[LAGGING]"
          note <- sprintf("undated content; generated_at lags schedule %dd > %dd", lag, as.integer(max_lag_days))
        } else note <- sprintf("undated content; generated_at lag %dd", lag)
      }
    } else {
      through <- if (is.character(e$through_date)) e$through_date else NA_character_
      td <- suppressWarnings(as.Date(through))
      if (is.na(td) || !is.character(e$through_date_source) ||
          !startsWith(e$through_date_source, "payload:")) {
        status <- "[MISSING]"
        note <- "game-dated entry needs a through_date extracted from payload content"
      } else if (is.na(sched_d)) {
        note <- "schedule_through_date unknown - lag not measured"
      } else if (sched_d <= td) {
        lag <- 0L; note <- "covers the schedule (off-season or current)"
      } else {
        lag <- as.integer(sched_d - td)
        if (lag > max_lag_days) {
          status <- "[LAGGING]"; note <- sprintf("lag %dd > %dd", lag, as.integer(max_lag_days))
        } else note <- sprintf("lag %dd", lag)
      }
    }
    if (status %in% c("[MISSING]", "[LAGGING]")) {
      bad <- c(bad, f)
      problems <- c(problems, if (status == "[LAGGING]") sprintf("%s lagging %dd > %dd", f, lag, as.integer(max_lag_days))
                    else sprintf("%s %s", f, note))
    }
    coverage[[f]] <- list(file = f, status = gsub("[][]", "", status), through_date = through,
                          lag_days = lag)
    rows <- c(rows, sprintf("    %-9s %-40s through=%s %s", status, f,
                            if (is.na(through)) "-" else through, note))
  }
  mk(length(bad) == 0L,
     sprintf("%d/%d dataset(s) covered; schedule through %s; max lag %dd (%s)",
             length(coverage) - length(bad), length(coverage),
             if (is.na(sched_d)) "unknown" else format(sched_d), as.integer(max_lag_days), mode),
     rows, coverage, problems)
}

# ------------------------------------------------------------------------------
# ASSERTION L - landing digest contract (front-office#200, MLB-Analytics#124)
#
# landing_digest.json must parse and carry every top-level contract field,
# calibration buckets 50-100 by 10 and movers windows "1", "7", "21". Its
# betting check runs through ZERO_BETTING (it is a policy-guard file in both
# modes). Read-only.
# ------------------------------------------------------------------------------
.PW_LANDING_DIGEST_FIELDS <- c("schema_version", "sport", "generated_at", "slate_date",
                               "season_state", "next_milestone", "today", "yesterday",
                               "record", "calibration", "movers")

.assert_landing_digest_contract <- function(path = file.path(WEB_DATA_DIR, "landing_digest.json")) {
  mk <- function(problems) list(
    id = "L", name = "landing digest contract", pass = !length(problems), fatal = TRUE,
    detail = if (length(problems)) paste0("    [VIOLATION] ", problems)
             else "    landing_digest.json carries the full contract",
    summary = sprintf("%d landing digest contract problem(s)", length(problems)))
  if (!file.exists(path)) return(mk(sprintf("%s absent", basename(path))))
  j <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(j)) return(mk("does not parse"))
  p <- character(0)
  miss <- setdiff(.PW_LANDING_DIGEST_FIELDS, names(j))
  if (length(miss)) p <- c(p, paste("missing field(s):", paste(miss, collapse = ", ")))
  if (!identical(as.integer(j$schema_version), 1L)) p <- c(p, "schema_version != 1")
  if (!.pw_is_utc_iso(j$generated_at)) p <- c(p, "generated_at not UTC ISO-8601")
  if (!isTRUE(j$season_state %in% c("regular", "postseason", "offseason", "preseason")))
    p <- c(p, "season_state not in regular|postseason|offseason|preseason")
  if (!all(c("season", "last_7") %in% names(j$record))) p <- c(p, "record needs season and last_7")
  lo <- vapply(.dm_or_pw(j$calibration), function(b) as.integer(.dm_or_pw(b$lo, NA)), integer(1))
  if (!identical(lo, c(50L, 60L, 70L, 80L, 90L))) p <- c(p, "calibration buckets must be 50-100 by 10")
  if (!setequal(names(j$movers$windows), c("1", "7", "21")))
    p <- c(p, "movers.windows must be \"1\", \"7\", \"21\"")
  rows <- c(.dm_or_pw(j$today), .dm_or_pw(j$yesterday))
  bad_ps <- !vapply(rows, function(r) isTRUE(r$prediction_status %in%
                                                c("available", "no_model", "not_yet_run")), logical(1))
  if (any(bad_ps)) p <- c(p, sprintf("%d game row(s) with an invalid prediction_status", sum(bad_ps)))
  mk(p)
}
.dm_or_pw <- function(a, b = list()) if (is.null(a)) b else a

# ------------------------------------------------------------------------------
# ASSERTION M - data-file lifecycle + frozen-file integrity (MLB-Analytics#147;
# corresponds to WNBA assertion L). Both modes.
#
#   * every top-level data file must have a manifest entry with a lifecycle in
#     WEB_DATA_LIFECYCLES; no lifecycle FAILS (classify the file in config.R)
#   * the manifest's lifecycle must match what config.R assigns now
#     (`expected`), so a stale manifest cannot carry an old classification
#   * season_final entries must carry season, final_through_date, frozen_sha256
#     and frozen_at, and the file's current content hash (CRLF-normalised, see
#     config.R's mlb_lifecycle_sha256) must equal frozen_sha256; any change
#     to a frozen file FAILS
# ------------------------------------------------------------------------------
.assert_lifecycle <- function(data_dir = WEB_DATA_DIR, manifest = NULL,
                              expected = function(files) mlb_data_lifecycle(files)) {
  base <- list(id = "M", name = "data-file lifecycle + frozen-file integrity", fatal = TRUE)
  if (is.null(manifest)) {
    mpath <- file.path(data_dir, .PW_MANIFEST_FILE)
    manifest <- if (file.exists(mpath))
      tryCatch(jsonlite::fromJSON(mpath, simplifyVector = FALSE), error = function(e) NULL) else NULL
  }
  if (is.null(manifest) || !is.list(manifest$datasets)) {
    return(c(base, list(pass = FALSE, problems = "manifest absent or unreadable",
                        detail = "    [FAIL] no readable data_manifest.json to read lifecycles from",
                        summary = "manifest absent or unreadable")))
  }
  entries <- .pw_manifest_entries(manifest)
  files <- .pw_data_files(data_dir)
  exp <- if (is.function(expected)) expected(files) else list()
  problems <- character(0); lines <- character(0)
  counts <- c(live = 0L, season_final = 0L, archived = 0L)
  for (f in files) {
    e <- entries[[f]]
    lc <- e$lifecycle
    if (is.null(lc) || !nzchar(as.character(lc))) {
      lines <- c(lines, sprintf("    [NO LIFECYCLE] %s - assign one in config.R (WEB_DATA_SEASON_FILES / WEB_DATA_FILES_OFFSEASON / WEB_DATA_ARCHIVED_FILES)", f))
      problems <- c(problems, sprintf("%s has no lifecycle", f)); next
    }
    if (!lc %in% WEB_DATA_LIFECYCLES) {
      lines <- c(lines, sprintf("    [FAIL] %s - unknown lifecycle '%s'", f, lc))
      problems <- c(problems, sprintf("%s unknown lifecycle %s", f, lc)); next
    }
    want <- exp[[f]]$lifecycle
    if (is.function(expected) && !identical(as.character(want %||% "<none>"), as.character(lc))) {
      lines <- c(lines, sprintf("    [FAIL] %s - manifest says %s, config.R assigns %s (stale manifest?)",
                                f, lc, want %||% "<none>"))
      problems <- c(problems, sprintf("%s lifecycle %s != config %s", f, lc, want %||% "<none>")); next
    }
    counts[[lc]] <- counts[[lc]] + 1L
    if (!identical(lc, "season_final")) {
      lines <- c(lines, sprintf("    [%s] %s", toupper(lc), f)); next
    }
    miss <- Filter(function(k) {
      v <- e[[k]]
      is.null(v) || length(v) != 1L || is.na(v) || !nzchar(as.character(v))
    }, c("season", "final_through_date", "frozen_sha256", "frozen_at"))
    if (length(miss)) {
      lines <- c(lines, sprintf("    [FAIL] %s - season_final without %s", f, paste(miss, collapse = ", ")))
      problems <- c(problems, sprintf("%s season_final missing %s", f, paste(miss, collapse = ", "))); next
    }
    want_sha <- exp[[f]]$frozen_sha256
    if (is.function(expected) && !identical(as.character(want_sha %||% ""), as.character(e$frozen_sha256))) {
      lines <- c(lines, sprintf("    [FAIL] %s - manifest frozen_sha256 differs from the lifecycle registry", f))
      problems <- c(problems, sprintf("%s frozen_sha256 disagrees with registry", f)); next
    }
    actual <- mlb_lifecycle_sha256(file.path(data_dir, f))
    if (!identical(actual, as.character(e$frozen_sha256))) {
      lines <- c(lines, sprintf("    [CHANGED] %s - season %s was frozen at %s, content hash now %s (frozen %s)",
                                f, e$season, e$frozen_at, substr(actual, 1, 12), substr(e$frozen_sha256, 1, 12)))
      problems <- c(problems, sprintf("%s changed since frozen", f)); next
    }
    lines <- c(lines, sprintf("    [SEASON_FINAL] %s - season %s, hash matches frozen %s", f, e$season, e$frozen_at))
  }
  pass <- length(problems) == 0
  c(base, list(pass = pass, problems = problems, detail = lines, counts = counts,
               summary = if (pass) sprintf("%d file(s): %d live, %d season_final (hash verified), %d archived",
                                           length(files), counts[["live"]], counts[["season_final"]], counts[["archived"]])
                         else sprintf("%d problem(s): %s", length(problems), paste(problems, collapse = "; "))))
}

# Off-season dry run: the manifest a live run would assert against. A live run
# refreshes data_manifest.json before asserting; a dry run must not write, so
# it builds the same manifest in memory instead.
.pw_preview_manifest <- function() {
  writer <- file.path("tools", "write_data_manifest.R")
  if (!file.exists(writer)) return(NULL)
  env <- new.env()
  old <- Sys.getenv("MLB_SKIP_MANIFEST_AUTORUN")
  Sys.setenv(MLB_SKIP_MANIFEST_AUTORUN = "1")
  on.exit(if (!nzchar(old)) Sys.unsetenv("MLB_SKIP_MANIFEST_AUTORUN") else Sys.setenv(MLB_SKIP_MANIFEST_AUTORUN = old), add = TRUE)
  tryCatch({
    sys.source(writer, envir = env)
    env$build_data_manifest(data_dir = WEB_DATA_DIR)
  }, error = function(e) {
    log_warn(paste("publish_web: manifest preview failed:", conditionMessage(e)), script = .PW_LOG_SCRIPT)
    NULL
  })
}

# ------------------------------------------------------------------------------
# Commit / push sequence. ONLY reached when dry_run = FALSE and every fatal
# assertion passed. Commits the published tree and pushes MLB-Analytics --
# nothing more. The deploy belongs to the aggregator's sync-sports.yml.
# Assertion E guarantees HEAD is the branch sync-sports.yml pulls, so
# `push origin HEAD` reaches the ref CI will actually read.
# The push goes through .pw_push_with_rebase(): fetch, rebase onto
# origin/<publish_branch> if it moved during the run, push, retry once.
# ------------------------------------------------------------------------------
.pw_do_publish <- function(repo_root, rel_paths, commit_message, publish_branch = NULL) {
  steps <- list()
  record <- function(label, res) {
    steps[[length(steps) + 1L]] <<- list(label = label, ok = res$ok, out = res$out)
    if (!res$ok) stop(sprintf("publish_web: step failed: %s\n%s", label,
                              paste(res$out, collapse = "\n")))
    invisible(TRUE)
  }
  stage_paths <- rel_paths[!is.na(rel_paths) & nzchar(trimws(rel_paths))]
  if (!length(stage_paths)) {
    stop("publish_web: no target paths provided to stage.")
  }
  # Use -A scoped to stage_paths so in-season publishes stage added, modified,
  # and pruned spatial/<id>.json files under WEB_DATA_DIR while off-season
  # publishes remain scoped strictly to WEB_DATA_FILES_OFFSEASON (+ archive).
  # Always stage the sidecar manifest with the payloads it describes
  # (in-season it is already under WEB_DATA_DIR; off-season paths are scoped).
  manifest_rel <- .pw_rel_to_repo(file.path(WEB_DATA_DIR, .PW_MANIFEST_FILE), repo_root)
  if (file.exists(file.path(repo_root, manifest_rel))) {
    stage_paths <- unique(c(stage_paths, manifest_rel))
  }
  # The landing digest's ratings history (MLB-Analytics#127) is tracked and NOT
  # ignored, so a plain scoped add stages it (never -f).
  history_rel <- file.path("data", "history", "ratings_history.csv")
  if (file.exists(file.path(repo_root, history_rel))) {
    stage_paths <- unique(c(stage_paths, history_rel))
  }
  record("git add -A",
         .pw_git(repo_root, c("add", "-A", "--", stage_paths)))
  record("git commit (MLB-Analytics)",
         .pw_git(repo_root, c("commit", "-m", shQuote(commit_message))))
  # Fetch, rebase onto origin/<publish_branch> when main moved during the run,
  # push, and retry once (.pw_push_with_rebase). Never merges, stashes or
  # hard-resets; on failure the checkout is put back in step with origin.
  push_steps <- .pw_push_with_rebase(repo_root, publish_branch, label = "MLB-Analytics")
  c(steps, push_steps)
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
                        commit_message = NULL,
                        mode = "inseason",
                        allow_degraded = FALSE) {

  repo_root <- .pw_repo_root()
  log_lines <- if (file.exists(LOG_FILE)) readLines(LOG_FILE, warn = FALSE) else character(0)
  run_start_arg <- run_start
  run_start <- .pw_resolve_run_start(run_start, mode, log_lines)
  run_start_known <- length(run_start) == 1L && !is.na(run_start)
  run_start_label <- if (run_start_known) {
    format(run_start, "%Y-%m-%d %H:%M:%S")
  } else if (identical(mode, "offseason") && is.null(run_start_arg)) {
    "<unknown: no run start passed (--run-start=YYYY-MM-DDTHH:MM:SS); off-season never reads it from the log>"
  } else if (identical(mode, "offseason")) {
    sprintf("<unknown: unparseable run start '%s'>", paste(format(run_start_arg), collapse = " "))
  } else {
    "<undetected>"
  }
  if (is.null(commit_message)) {
    # Never invent a date: with an unknown run start Gate A fails closed and
    # nothing is published, so this text only ever shows up in the report.
    commit_message <- if (run_start_known) {
      sprintf("Publish MLB %s web artifacts from the %s pipeline run",
              mode, format(run_start, "%Y-%m-%d %H:%M"))
    } else {
      sprintf("Publish MLB %s web artifacts (run start unknown - publish blocked)", mode)
    }
  }

  target_files <- if (identical(mode, "offseason")) WEB_DATA_FILES_OFFSEASON else WEB_DATA_FILES
  policy_files <- .policy_guard_files(target_files, mode = mode)

  # Live publishes refresh the sidecar manifest first (optional builder: absent
  # when this file is sourced on its own). Dry runs never write to disk.
  if (!isTRUE(dry_run) && file.exists(file.path("tools", "write_data_manifest.R"))) {
    tryCatch({
      dm_env <- new.env()
      sys.source(file.path("tools", "write_data_manifest.R"), envir = dm_env)
      dm_env$write_data_manifest()
    }, error = function(e) log_warn(sprintf("publish_web: data manifest refresh failed: %s",
                                            conditionMessage(e)), script = .PW_LOG_SCRIPT))
  }
  # Manifest for F/H/M. Live: the refreshed file on disk. Off-season dry run:
  # an in-memory preview of what the live run would write (MLB-Analytics#147).
  # In-season dry run: the file on disk, as before.
  manifest_obj <- if (isTRUE(dry_run) && identical(mode, "offseason")) .pw_preview_manifest() else NULL
  if (is.null(manifest_obj)) {
    mp <- file.path(WEB_DATA_DIR, .PW_MANIFEST_FILE)
    manifest_obj <- if (file.exists(mp))
      tryCatch(jsonlite::fromJSON(mp, simplifyVector = FALSE), error = function(e) NULL) else NULL
    manifest_src <- "data_manifest.json on disk"
  } else {
    manifest_src <- "in-memory preview (dry run; nothing written)"
  }

  checks <- list(
    .assert_mtime_freshness(run_start, mode = mode),
    .assert_slate_agreement(season, mode = mode),
    .assert_nonempty_diff(repo_root, mode = mode),
    .assert_publish_branch(repo_root, publish_branch),
    .assert_log_scan(log_lines, run_start, fail_on_exporter_warnings, mode = mode, allow_degraded = allow_degraded),
    .assert_payload_provenance(run_start, mode = mode, manifest = manifest_obj),
    .assert_web_contracts(skip_contracts),
    .assert_zero_betting(policy_files),
    if (identical(mode, "offseason"))
      .assert_manifest_and_coverage(WEB_DATA_DIR, mode = mode, manifest = manifest_obj)
    else .assert_manifest_and_coverage(WEB_DATA_DIR),
    .assert_landing_digest_contract(),
    .assert_lifecycle(WEB_DATA_DIR, manifest = manifest_obj)
  )

  passed  <- vapply(checks, function(ch) isTRUE(ch$pass), logical(1))
  fatal   <- vapply(checks, function(ch) isTRUE(ch$fatal), logical(1))
  blocked <- any(!passed & fatal)
  # Belt and braces for #74: an off-season publish with no known run start is
  # blocked even if Gate A were somehow vacuous (for example an empty file list).
  if (identical(mode, "offseason") && !run_start_known) blocked <- TRUE

  # ---- report ----------------------------------------------------------------
  cat("\n================================================================\n")
  cat(sprintf("MLB web publish gate  [%s | mode: %s]\n",
              if (dry_run) "DRY RUN - nothing will be published" else "LIVE PUBLISH", mode))
  cat("================================================================\n")
  cat(sprintf("  repo root        : %s\n", ifelse(is.na(repo_root), "<not a git repo>", repo_root)))
  cat(sprintf("  publish branch   : %s\n", publish_branch))
  cat(sprintf("  season           : %d\n", as.integer(season)))
  cat(sprintf("  mode             : %s\n", mode))
  cat(sprintf("  pipeline log     : %s (%d lines)\n", LOG_FILE, length(log_lines)))
  cat(sprintf("  run start        : %s\n", run_start_label))
  if (!identical(mode, "offseason")) {
    cat(sprintf("  schedule cache   : %s\n", CACHE_MLB_SCHEDULE(season)))
  }
  cat(sprintf("  data manifest    : %s\n", manifest_src))
  cat("\n-- Assertions --------------------------------------------------\n")
  for (ch in checks) {
    cat(sprintf("  [%s] %s. %s - %s\n",
                if (ch$pass) "PASS" else if (ch$fatal) "FAIL" else "WARN",
                ch$id, ch$name, ch$summary))
    cat(paste0(ch$detail, collapse = "\n"), "\n", sep = "")
  }

  cat("\n-- Would publish -----------------------------------------------\n")
  cat(sprintf("  %d dataset(s) asserted from %s:\n", length(target_files), WEB_DATA_DIR))
  for (f in target_files) cat(sprintf("    - %s\n", basename(f)))
  if (!identical(mode, "offseason")) {
    slates <- if (dir.exists(WEB_MATCHUPS_DIR)) list.files(WEB_MATCHUPS_DIR) else character(0)
    cat(sprintf("  %d per-slate file(s) from %s (not individually asserted; see config.R section 7)\n",
                length(slates), WEB_MATCHUPS_DIR))
    spatial_files <- if (dir.exists(WEB_DIR_SPATIAL)) list.files(WEB_DIR_SPATIAL, pattern = "\\.json$") else character(0)
    cat(sprintf("  %d per-player spatial file(s) from %s (not individually asserted; see config.R section 7)\n",
                length(spatial_files), WEB_DIR_SPATIAL))
  }
  cat(sprintf("  commit message   : %s\n", commit_message))
  cat(sprintf("  push sequence    : commit -> push MLB-Analytics %s (deploy belongs to the aggregator's sync-sports.yml)\n",
              publish_branch))

  cat("\n-- Verdict -----------------------------------------------------\n")
  if (blocked) {
    cat("  BLOCKED - at least one fatal assertion failed. PUBLISHING NOTHING.\n")
    cat("  Yesterday's correct site stays up rather than a half-updated one.\n")
    if (!run_start_known) {
      cat("  Run start unknown - freshness cannot be verified, so the publish is blocked.\n")
    }
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
    mode = mode, repo_root = repo_root, publish_branch = publish_branch,
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
    contracts_pass = isTRUE(checks[[7]]$pass),
    manifest_coverage = checks[[9]]$coverage,
    checks = checks, published = FALSE, steps = list()
  )

  if (blocked || dry_run) {
    if (blocked && !dry_run) .pw_notify_discord(result)
    return(invisible(result))
  }

  result$steps <- .pw_do_publish(repo_root, checks[[3]]$paths, commit_message, publish_branch)
  result$published <- TRUE
  
  # Atomic Baseline Promotion (blueprint §2 & §7):
  # In offseason mode, promote cache/league_state_staged.json to cache/league_state_baseline.json
  # ONLY after successful git publish commit, and ONLY if NOT --allow-degraded
  if (identical(mode, "offseason") && !isTRUE(allow_degraded)) {
    .pw_promote_offseason_baseline(repo_root, MLB_CACHE_ROOT, publish_branch)
  }

  log_info(sprintf("publish_web: web artifacts committed and pushed to MLB-Analytics %s. The site changes when the aggregator's sync-sports.yml next pulls; this script does not deploy.",
                   publish_branch), script = .PW_LOG_SCRIPT)
  .pw_notify_discord(result)
  invisible(result)
}

# ------------------------------------------------------------------------------
# CLI wrapper. Keyed off commandArgs()
# ------------------------------------------------------------------------------
local({
  argv <- commandArgs(trailingOnly = FALSE)
  files <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (!any(grepl("publish_web\\.R$", files))) return(invisible(NULL))
  opts <- commandArgs(trailingOnly = TRUE)
  
  mode_val <- "inseason"
  mode_opt <- grep("^--mode=", opts, value = TRUE)
  if (length(mode_opt)) {
    mode_val <- sub("^--mode=", "", mode_opt[1])
  }
  
  # --run-start=YYYY-MM-DDTHH:MM:SS (local time), passed by the orchestrator
  # (MLB-Analytics#74). Given more than once is ambiguous, so it is treated as
  # unparseable and fails closed rather than picking one.
  run_start_val <- NULL
  rs_opt <- grep("^--run-start=", opts, value = TRUE)
  if (length(rs_opt) == 1L) {
    run_start_val <- sub("^--run-start=", "", rs_opt)
  } else if (length(rs_opt) > 1L) {
    run_start_val <- paste(sub("^--run-start=", "", rs_opt), collapse = " | ")
  }

  recognized <- c("--publish", "--strict-warnings", "--skip-contracts", "--allow-degraded")
  unknown <- setdiff(opts[!grepl("^--(mode|run-start)=", opts)], recognized)
  if (length(unknown) > 0) {
    cat(sprintf("[ERROR] publish_web.R: unknown CLI option(s): %s (allowed: --publish, --strict-warnings, --skip-contracts, --mode=inseason|offseason, --run-start=YYYY-MM-DDTHH:MM:SS, --allow-degraded)\n",
                paste(unknown, collapse = ", ")), file = stderr())
    quit(status = 2L)
  }
  res <- publish_web(dry_run = !("--publish" %in% opts),
                     run_start = run_start_val,
                     fail_on_exporter_warnings = "--strict-warnings" %in% opts,
                     skip_contracts = "--skip-contracts" %in% opts,
                     mode = mode_val,
                     allow_degraded = "--allow-degraded" %in% opts)
  quit(status = if (isTRUE(res$blocked)) 1L else 0L)
})
