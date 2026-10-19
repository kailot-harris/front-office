# ==============================================================================
# control_panel_app.R
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/control_panel_app.R
#
# GitHub issues #46 (Slice 2), #47 (Slice 3), and #48 (Slice 4) of issue #43's tree.
#
# #46 let an operator pick exactly ONE stage from pipeline_stages.R's PIPELINE_STAGES
# registry and run it synchronously in-process (via source(), same call_fn/entry_fn
# contract as run_full_pipeline.R's run_stage() -- see run_pipeline_stage_captured()
# below), showing a pass/fail result plus captured console output.
#
# #47 added a per-stage dependency-staleness gate (check_stage_staleness()) that
# hard-blocks a run on a missing/stale declared input unless the operator explicitly
# acknowledges an override.
#
# #48 (this slice) lets the operator multi-select several stages and queue them to run
# sequentially in the chosen order (a mini custom pipeline), re-checking #47's staleness
# gate for EACH stage individually at the moment it actually starts (not once for the whole
# queue at submission time -- see advance_queue() below for why that distinction matters),
# and adds a cross-session run lock so a second browser tab/user cannot start a second run
# (single or queued) while one is already in progress, racing on the same cache files.
#
# #50 made the app network-accessible (not localhost-only) behind a placeholder single
# shared-password gate (CONTROL_PANEL_PASSWORD). #54 (this slice) replaces that gate
# entirely with issue #44's real multi-user auth module: auth_utils.R's verify_user()/
# create_account_if_authorized() (issues #51/#52) mounted via auth_login_module.R's
# mod_login_ui()/mod_login_server() (issue #53). CONTROL_PANEL_PASSWORD is now fully dead --
# no reference to it remains anywhere in this file.
#
# SCOPE (explicit, per the issues): no inline chart/table rendering of a stage's *data*
# output (#49 -- this shows captured text output only, same as before). This is a
# TRIGGERING tool, not a read-only dashboard -- app.R (the existing shinydashboard) is a
# distinct file with a distinct job and is intentionally left untouched.
#
# EXECUTION MODEL: each queued stage still blocks the single R process for its own duration
# (no background worker, no live log streaming -- out of scope per #46). What #48 adds is
# that the queue as a WHOLE does NOT block the process for its entire duration in one
# uninterrupted call: advance_queue() runs one stage, then reschedules itself via
# later::later(..., delay = 0) instead of looping in place. Returning to Shiny's event loop
# between stages is not cosmetic -- it is the only way a second session's periodic lock-poll
# (see the "cross-session run lock" section below) or Shiny's own disconnect detection
# (session$onSessionEnded(), used to release the lock on an interrupted run) ever get a
# chance to run while a multi-stage queue is in flight. A plain for-loop inside one
# observeEvent would starve every other session on this single-threaded R process for the
# whole queue's runtime, defeating criterion 2 and 3 below before they could even be
# observed. The run control (button + stage picker + override checkbox) is disabled the
# instant the button is clicked via an inline onclick handler for the SAME-tab instant
# feedback #46 established, and is re-enabled by the server once the whole queue finishes
# (or is abandoned because the owning session ended).
#
# CONTRACT FIDELITY: run_pipeline_stage_captured() below mirrors run_full_pipeline.R's
# run_stage() stage-invocation contract (source() the script, then either call the named
# call_fn or verify the named entry_fn exists post-source, with the same .py -> system2()
# branch) rather than reimplementing a divergent version of it. It does NOT reuse run_stage()
# itself (that function is console-oriented: it writes straight to message()/cat() and
# returns a bare TRUE/FALSE, with no captured-output channel for a UI to display) and it does
# NOT alter run_full_pipeline.R in any way -- this file is loaded standalone, so
# run_full_pipeline.R's own 13-stage loop is unaffected by anything here.
# ==============================================================================

# GitHub issue #49 (Slice 5 of #43), second half: DT/ggplot2/dplyr/tidyr/scales/stringr/plotly
# added so dashboard_render_helpers.R's build_*() functions (sourced below, after
# pipeline_stages.R) -- which per that file's own header comment assume these packages are
# already attached by the caller -- behave identically here as they do in app.R, which
# attaches this same package set before sourcing dashboard_render_helpers.R itself.
req_pkgs <- c("shiny", "shinyjs", "DT", "ggplot2", "dplyr", "tidyr", "scales", "stringr", "plotly")
new_pkgs <- req_pkgs[!(req_pkgs %in% installed.packages()[, "Package"])]
if (length(new_pkgs)) install.packages(new_pkgs)

suppressPackageStartupMessages({
  library(shiny)
  library(shinyjs)
  library(DT)
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(scales)
  library(stringr)
  library(plotly)
})

# No setwd() here, deliberately -- per CLAUDE.md's flat-layout convention every script in this
# repo (including app.R) assumes it is launched with the project root already as the working
# directory and sources siblings by bare filename. A hardcoded absolute-path setwd() here would
# silently escape into a *different* checkout (e.g. the main repo instead of a git worktree)
# whenever one happens to exist at that literal path, which is exactly what broke this app
# under shinytest2/git-worktree-based testing.

# Capture the working directory this file was sourced from (= project root, by the convention
# above) ONCE, at load time. shiny::runApp() pins the working directory to the app's own
# directory for the life of the R process and re-applies that pin around session/reactive
# dispatch -- harmless when control_panel_app.R is launched the normal way (its own directory
# IS the project root), but it means code inside a later reactive context cannot trust getwd()
# to still be the project root, only whatever it was at THIS source() call. Every later
# relative-path operation in this file (stage script paths) restores this dir explicitly
# instead of assuming getwd() is still correct by then.
.CONTROL_PANEL_ROOT <- getwd()

# Sourced in the same order run_full_pipeline.R requires (config.R before pipeline_stages.R,
# since several registry `output`/`inputs` entries reference config.R's CACHE_* constants
# unquoted).
source("config.R")
source("pipeline_stages.R")
# GitHub issue #49 (Slice 5 of #43), second half: read-only use of app.R's 15 extracted
# build_*() render helpers (see the STAGE_PREVIEW_MAP section below) -- this file calls them,
# it does not edit dashboard_render_helpers.R itself.
source("dashboard_render_helpers.R")
# GitHub issue #54: real multi-user auth, replacing #50's placeholder CONTROL_PANEL_PASSWORD
# gate entirely. auth_utils.R defines verify_user()/create_account_if_authorized() (issues
# #51/#52); auth_login_module.R defines the mountable mod_login_ui()/mod_login_server() pair
# (issue #53) that calls them. Sourced here, before the UI/server definitions below, same
# ordering convention as config.R/pipeline_stages.R.
source("auth_utils.R")
source("auth_login_module.R")

# ------------------------------------------------------------------------------------------
# run_pipeline_stage_captured(stage)
#
# Runs a single PIPELINE_STAGES entry in-process, capturing stdout (cat()/print()) plus
# message()/warning() conditions into one ordered character vector, and reports pass/fail
# without ever propagating an error out of this function (callers -- i.e. the Shiny server
# below -- must not crash on a stage failure; that is the whole point of criterion 3).
#
# Mirrors run_stage()'s (run_full_pipeline.R, ~line 126) own logic point for point:
#   - stage$script must exist, else a clean fail (not a stop()).
#   - a .R/.r script is source()'d with local = FALSE (same as run_stage()); a .py script is
#     run via system2() with its exit status checked, exactly like run_stage()'s python
#     branch, since this stage-runner must support every registry entry, not just R ones.
#   - if stage$call_fn is set, that function is invoked after sourcing (run_stage() invokes
#     call_fn; it does NOT invoke entry_fn).
#   - if stage$entry_fn is set, only EXISTENCE is checked after sourcing (same as run_stage())
#     -- the script's own `if (!interactive())`-style footer is what actually runs it, and
#     this process (launched via Rscript) is non-interactive so that footer fires exactly as
#     it would under run_full_pipeline.R.
# ------------------------------------------------------------------------------------------
run_pipeline_stage_captured <- function(stage) {
  log_lines <- character(0)
  add_line <- function(x) log_lines <<- c(log_lines, x)

  start <- Sys.time()
  error_msg <- NULL

  # Restore the project root captured at load time -- see .CONTROL_PANEL_ROOT's comment above.
  # Every stage script in the registry (and anything it itself source()s) is written assuming
  # cwd = project root, same as run_full_pipeline.R's own run_stage().
  setwd(.CONTROL_PANEL_ROOT)

  ok <- tryCatch({
    withCallingHandlers(
      {
        captured <- capture.output({
          if (!file.exists(stage$script)) {
            stop(sprintf("Stage script not found: %s", stage$script))
          }
          if (grepl("\\.py$", stage$script)) {
            py_out <- system2("python", args = stage$script, stdout = TRUE, stderr = TRUE)
            cat(paste(py_out, collapse = "\n"), "\n")
            status <- attr(py_out, "status")
            if (!is.null(status) && !is.na(status) && status != 0) {
              stop(sprintf("Python stage %s exited with status %s", stage$script, status))
            }
          } else {
            source(stage$script, local = FALSE)
            if (!is.null(stage$call_fn)) {
              if (exists(stage$call_fn, envir = .GlobalEnv, mode = "function", inherits = FALSE)) {
                get(stage$call_fn, envir = .GlobalEnv, mode = "function", inherits = FALSE)()
              } else {
                warning(sprintf("call_fn '%s' not found as a function after sourcing %s.",
                                 stage$call_fn, stage$script))
              }
            }
            if (!is.null(stage$entry_fn) &&
                !exists(stage$entry_fn, envir = .GlobalEnv, mode = "function", inherits = FALSE)) {
              message(sprintf("Declared entry point '%s()' not found after sourcing %s.",
                               stage$entry_fn, stage$script))
            }
          }
        }, type = "output")
        log_lines <<- c(log_lines, captured)
        TRUE
      },
      message = function(m) {
        add_line(paste0("[message] ", sub("\n$", "", conditionMessage(m))))
        invokeRestart("muffleMessage")
      },
      warning = function(w) {
        add_line(paste0("[warning] ", conditionMessage(w)))
        invokeRestart("muffleWarning")
      }
    )
  }, error = function(e) {
    error_msg <<- conditionMessage(e)
    add_line(paste0("[error] ", conditionMessage(e)))
    FALSE
  })

  elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))
  list(
    success = isTRUE(ok),
    output  = log_lines,
    error   = error_msg,
    elapsed = elapsed
  )
}

# ------------------------------------------------------------------------------------------
# GitHub issue #47 (Slice 3 of #43). Before a selected stage runs, check its declared
# `inputs` (pipeline_stages.R) for staleness/missing files; hard-block the run with a clear
# per-input reason, but always offer an explicit, per-stage "I know, run it anyway" override.
#
# resolve_project_path(path)
#
# `stage$inputs` entries are all relative paths (e.g. "cache/rapm_ratings.rds",
# file.path(CACHE_DIR, "active_rosters_cache.rds")), written assuming cwd = project root --
# same convention as run_pipeline_stage_captured() itself. This runs from a reactive context,
# where getwd() cannot be trusted to still be .CONTROL_PANEL_ROOT (see that variable's own
# comment above), so every path is resolved against it explicitly rather than via a bare
# file.exists()/file.mtime() call that implicitly trusts getwd().
# ------------------------------------------------------------------------------------------
resolve_project_path <- function(path) {
  if (grepl("^([A-Za-z]:[\\\\/]|/)", path)) path else file.path(.CONTROL_PANEL_ROOT, path)
}

# STALE_THRESHOLD_HOURS: the issue text ("staleness/missing files") does not commit to a
# specific age threshold beyond "stale or missing" -- this is the documented, deliberately
# simple heuristic chosen for this ticket. The only scheduled driver of this pipeline today
# is schedule_daily.bat (once per day); 36 hours is one full day plus a generous buffer for a
# late or skipped run, so a healthy once-a-day cadence never trips this, but an input that
# silently stopped being regenerated for a day+ does. This is intentionally NOT a full
# cross-stage DAG freshness walk (comparing this stage's `inputs` against the *mtime of the
# other stage whose `output` produced that same path*) -- pipeline_stages.R's `output` field
# is heterogeneous (NULL / single path / vector) and several stages legitimately have no
# `output` at all (see e.g. `daily_ingest`'s own comment), so a robust producer-vs-consumer
# mtime comparison is materially more work than this slice's scope; a flat age threshold on
# the input file itself catches the common real failure (an upstream stage silently not
# rerun in days) without that complexity.
STALE_THRESHOLD_HOURS <- 36

# ------------------------------------------------------------------------------------------
# check_stage_staleness(stage)
#
# Checks every path in stage$inputs (character(0) is valid -- some stages, e.g.
# sync_rosters/injury_scraper, are pure live-API consumers with no file dependency at all,
# and must never be blocked). Returns:
#   list(blocked = logical, problems = data.frame(path, reason, detail))
# where `reason` is either "missing" (file.exists() is FALSE -- the unconditional, mandatory
# hard-block case per the issue) or "stale" (file exists but file.mtime() is older than
# STALE_THRESHOLD_HOURS). `blocked` is TRUE iff `problems` has at least one row of either
# kind -- missing and stale are both hard-blocking for this ticket, just labeled differently
# so the UI can show WHICH case applies to WHICH input, never a single generic message.
# ------------------------------------------------------------------------------------------
check_stage_staleness <- function(stage) {
  empty <- data.frame(path = character(0), reason = character(0), detail = character(0),
                       stringsAsFactors = FALSE)
  inputs <- stage$inputs
  if (is.null(inputs) || length(inputs) == 0) {
    return(list(blocked = FALSE, problems = empty))
  }

  rows <- lapply(inputs, function(p) {
    full_path <- resolve_project_path(p)
    if (!file.exists(full_path)) {
      return(data.frame(path = p, reason = "missing",
                         detail = sprintf("Declared input not found: %s", p),
                         stringsAsFactors = FALSE))
    }
    age_hours <- as.numeric(difftime(Sys.time(), file.mtime(full_path), units = "hours"))
    if (age_hours > STALE_THRESHOLD_HOURS) {
      return(data.frame(path = p, reason = "stale",
                         detail = sprintf("%s is %.1f hours old (stale threshold: %d hours)",
                                           p, age_hours, STALE_THRESHOLD_HOURS),
                         stringsAsFactors = FALSE))
    }
    NULL
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]
  problems <- if (length(rows) == 0) empty else do.call(rbind, rows)
  list(blocked = nrow(problems) > 0, problems = problems)
}

# ------------------------------------------------------------------------------------------
# GitHub issue #49 (Slice 5 of #43), second half. The first half (already on main,
# dashboard_render_helpers.R) extracted app.R's render-block logic into 15 plain build_*()
# functions, each taking already-computed data and returning a ggplot/plotly/datatable with no
# input$/session$ reference -- safe to call from this, a different Shiny app. This section
# wires a just-finished stage's cache output through the SAME build_*() helper app.R's own tab
# uses, so the control panel can show a real data preview next to the existing raw log dump (in
# addition to it, not instead -- output$output_log below is unchanged).
#
# STAGE_PREVIEW_MAP: keyed by PIPELINE_STAGES id. Only stages whose `output =` cache was
# confirmed (by reading app.R's matching reactive) to map cleanly onto one of the 15
# build_*() functions via a plain readRDS(cache_path) -> build_fn(raw_object) call -- i.e. with
# no further input$-driven filtering/selection, Shiny req(), or non-readRDS data source (e.g.
# team_embeddings' build_plot_embeddings_pca()/_heatmap() in app.R consume a duckdb query
# result, not a readRDS() of CACHE_EMBEDDINGS/CACHE_SIMILARITY, so that stage is deliberately
# left unmapped rather than reimplemented divergently) -- are listed here. Every other
# registered stage (data_health_probe, daily_ingest, sync_rosters, team_embeddings,
# the two prediction_accuracy_logger entries, the three latent_engines, copula_props_engine,
# playoff_simulator, risk_management_engine, notify_bets, bet_tracker) intentionally has no
# entry, per the brief: "many stages don't map ... show no extra preview, just the existing
# log" -- NOT an oversight.
# ------------------------------------------------------------------------------------------
#
# .normalize_value_bets_dates(df): build_tbl_daily_edges() requires a `norm_date` column
# (confirmed empirically: cache/latest_value_bets.rds as written by market_odds_engine.R has
# `game_date` but no `norm_date` -- calling build_tbl_daily_edges() on the raw readRDS() object
# directly errors with "object 'norm_date' not found"). app.R never calls the helper on raw
# cache data either -- its r_normalized_value_bets() reactive (app.R ~line 591) derives
# norm_date first, including a staggered-placeholder-date fallback for the common case where
# the real `game_date` column isn't yet distinct across rows (demo/thin-slate data). That logic
# is byte-for-byte replicated here (not sourced from app.R -- app.R is out of scope to touch,
# and its reactive can't be called outside a reactive context anyway) so this preview's content
# genuinely matches what app.R's Tab 1 (tab_daily_edges, "All Scheduled Dates" selection) shows
# for the same cache, rather than silently falling back to "no preview" on every real run.
.normalize_value_bets_dates <- function(df) {
  c_names <- names(df)
  d_col <- c_names[tolower(c_names) %in% c("game_date", "date", "commence_time")][1]

  has_distinct_dates <- FALSE
  if (!is.na(d_col)) {
    parsed <- suppressWarnings(as.Date(df[[d_col]]))
    if (sum(!is.na(parsed)) > 0 && length(unique(parsed[!is.na(parsed)])) > 1) {
      df$norm_date <- parsed
      has_distinct_dates <- TRUE
    }
  }

  if (!has_distinct_dates) {
    n_total <- nrow(df)
    staggered_dates <- c(
      rep("2026-05-08", min(2, n_total)),
      rep("2026-05-09", min(12, max(0, n_total - 2))),
      rep("2026-05-10", min(4,  max(0, n_total - 14))),
      rep("2026-05-11", min(10, max(0, n_total - 18))),
      rep("2026-05-12", min(7,  max(0, n_total - 28))),
      rep("2026-05-13", max(0, n_total - 35))
    )
    df$norm_date <- as.Date(staggered_dates[1:n_total])
  }
  df
}

STAGE_PREVIEW_MAP <- list(
  roster_bottom_up_engine = list(
    cache  = "cache/projected_wnba_standings.rds",
    render = function(raw) build_tbl_bottom_up_standings(raw)
  ),
  market_odds_engine = list(
    cache  = file.path(CACHE_DIR, "latest_value_bets.rds"),
    render = function(raw) build_tbl_daily_edges(.normalize_value_bets_dates(raw))
  ),
  injury_scraper = list(
    cache  = CACHE_INJURY_DATA,
    render = function(raw) build_tbl_injuries(TRUE, raw)
  ),
  player_props_engine = list(
    cache  = CACHE_PLAYER_PROPS,
    render = function(raw) build_tbl_props_terminal(raw)
  ),
  pbp_engine = list(
    cache  = CACHE_PLAYER_PBP_FEATURES,
    render = function(raw) build_tbl_clutch_shot_profile(raw, FALSE)
  )
)

# ------------------------------------------------------------------------------------------
# render_stage_preview(stage_id)
#
# Looks up stage_id in STAGE_PREVIEW_MAP AND cross-checks its registered `output =` path(s) in
# PIPELINE_STAGES -- the same registry field output$staleness_ui already reads elsewhere in
# this file -- so a future drift between this map and the registry's declared output is caught
# (returns NULL) rather than silently previewing the wrong/stale file. Reads the FRESH .rds the
# run just wrote and calls the matching build_*() helper.
#
# Fail-safe per CLAUDE.md: never throws. Returns NULL (no extra preview, log dump unaffected)
# if there is no mapping for this stage, the mapped cache isn't actually one of the stage's
# declared outputs, the file is missing, or readRDS()/the helper call errors for any reason
# (e.g. an unexpected schema, a half-written concurrent file).
# ------------------------------------------------------------------------------------------
render_stage_preview <- function(stage_id) {
  mapping <- STAGE_PREVIEW_MAP[[stage_id]]
  if (is.null(mapping)) return(NULL)

  stage <- PIPELINE_STAGES[[stage_id]]
  if (is.null(stage) || is.null(stage$output)) return(NULL)
  if (!(mapping$cache %in% stage$output)) return(NULL)

  full_path <- resolve_project_path(mapping$cache)
  if (!file.exists(full_path)) return(NULL)

  tryCatch({
    raw    <- readRDS(full_path)
    widget <- mapping$render(raw)
    tagList(
      tags$h5(sprintf("Preview: %s (%s)", stage_id, basename(mapping$cache))),
      widget
    )
  }, error = function(e) {
    message(sprintf("[render_stage_preview] %s: %s", stage_id, conditionMessage(e)))
    NULL
  })
}

# ------------------------------------------------------------------------------------------
# GitHub issue #48's cross-session run lock.
#
# shiny::runApp() (how this app is launched, same as app.R / summary_app.R elsewhere in this
# repo) serves EVERY browser tab/session from ONE single-threaded R process -- there is no
# per-session process isolation. That means a per-session reactiveVal/reactiveValues object
# (scoped to one server(input, output, session) closure) is invisible to a second tab: it
# would let two tabs each believe they alone are running a stage and race on the same cache
# files, which is exactly what this lock exists to prevent.
#
# MECHANISM CHOSEN: a plain environment, `.PIPELINE_RUN_LOCK`, created once at source() time
# in this file's top-level (package-level) environment -- NOT inside server(). Every
# session's server(input, output, session) call below is a closure whose enclosing
# environment is this same top-level environment (that is just how R's lexical scoping
# works for a function defined at a script's top level), so every session reads and mutates
# the SAME environment object. Mutating an environment's fields (rather than reassigning a
# binding) is visible immediately to any other closure holding a reference to it, with no
# serialization/IPC needed, because it is the same R process and the same object in memory.
# This is the "global variable in the server's enclosing environment" option the issue's own
# brief calls out, chosen over an on-disk lock file because every consumer of this lock is
# already guaranteed to be in this one process (no other process ever runs these stages
# concurrently -- run_full_pipeline.R and this app are never invoked against the same cache
# directory at the same time per this repo's existing operational convention), so a
# filesystem lock would add crash-recovery surface (an orphaned lock FILE surviving a process
# restart) without buying any additional correctness this script needs.
#
# SELF-RELEASE ON AN INTERRUPTED RUN -- the two-layer defense, and its real limitation:
#
#   1. PRIMARY: every session registers `session$onSessionEnded(function()
#      pipeline_lock_release(session$token))` near the top of server() below. Shiny invokes
#      onSessionEnded callbacks as soon as it notices the browser's websocket connection is
#      gone (e.g. a closed tab, or shinytest2's AppDriver$stop()) -- which, critically, it can
#      only notice while the R process is back at its event loop, not while R is itself busy
#      inside a blocking stage script's source() call. Because advance_queue() (below)
#      deliberately returns control to the event loop between every queued stage (see the
#      EXECUTION MODEL header comment above), an interrupted mid-queue run's disconnect is
#      typically noticed within one stage boundary, not only after the entire queue finishes
#      -- this is the main reason the queue is implemented as a reschedule-via-later() state
#      machine instead of a single synchronous loop.
#
#   2. FALLBACK, for when (1) never fires: a held lock also records `locked_at`
#      (Sys.time() when acquired). pipeline_lock_is_held() self-clears any lock older than
#      LOCK_MAX_AGE_SECS the next time ANY session asks whether the lock is held (lock-check
#      is on the hot path of every session's periodic poll below, so this is checked
#      frequently, not just when someone tries to acquire it). This is a deliberately crude
#      safety net, not a real lease-renewal protocol: it does NOT know whether a run that has
#      held the lock for that long is still legitimately in progress (e.g. a single very slow
#      real stage) or truly abandoned, so LOCK_MAX_AGE_SECS is set generously (20 minutes --
#      well beyond any single stage's realistic runtime observed in this repo) specifically so
#      it almost never fires in the course of ordinary queued runs, and exists purely to
#      bound the worst case (e.g. the entire R process wedged such that onSessionEnded's
#      callback queue itself never drains) rather than leaving the control stuck disabled
#      forever. Documented limitation: if a legitimate queue run ever needs more than 20
#      minutes, this fallback would incorrectly release its lock out from under it; that
#      trade-off is accepted for this ticket rather than building real lease renewal.
# ------------------------------------------------------------------------------------------
.PIPELINE_RUN_LOCK <- local({
  e <- new.env(parent = emptyenv())
  e$held        <- FALSE
  e$locked_at   <- NA_real_
  e$owner_token <- NA_character_
  e
})

LOCK_MAX_AGE_SECS <- 20 * 60  # see fallback-release rationale above.

# pipeline_lock_is_held(): the single read path every session's poll and every acquire
# attempt goes through -- also where the LOCK_MAX_AGE_SECS fallback release happens, so a
# stuck lock self-clears the next time *anyone* asks, not only on a future acquire attempt.
pipeline_lock_is_held <- function() {
  if (!isTRUE(.PIPELINE_RUN_LOCK$held)) return(FALSE)
  age <- suppressWarnings(as.numeric(difftime(Sys.time(), .PIPELINE_RUN_LOCK$locked_at, units = "secs")))
  if (!is.na(age) && age > LOCK_MAX_AGE_SECS) {
    pipeline_lock_release(.PIPELINE_RUN_LOCK$owner_token, force = TRUE)
    return(FALSE)
  }
  TRUE
}

# pipeline_lock_acquire(token): FALSE if already held (by anyone, including this same
# session -- re-entrant acquisition is not a supported case, there is only ever one queue
# per session at a time per the UI below).
pipeline_lock_acquire <- function(token) {
  if (pipeline_lock_is_held()) return(FALSE)
  .PIPELINE_RUN_LOCK$held        <- TRUE
  .PIPELINE_RUN_LOCK$locked_at   <- as.numeric(Sys.time())
  .PIPELINE_RUN_LOCK$owner_token <- token
  TRUE
}

# pipeline_lock_release(token, force = FALSE): only the session holding the lock may release
# it by token match (so one session's stale callback can never release a DIFFERENT session's
# live, legitimate run) -- `force = TRUE` is reserved for the LOCK_MAX_AGE_SECS fallback path
# above, which by definition has no live owner session left to ask.
pipeline_lock_release <- function(token, force = FALSE) {
  if (force || identical(.PIPELINE_RUN_LOCK$owner_token, token)) {
    .PIPELINE_RUN_LOCK$held        <- FALSE
    .PIPELINE_RUN_LOCK$locked_at   <- NA_real_
    .PIPELINE_RUN_LOCK$owner_token <- NA_character_
    return(TRUE)
  }
  FALSE
}

# ------------------------------------------------------------------------------------------
# UI
# ------------------------------------------------------------------------------------------
stage_ids    <- names(PIPELINE_STAGES)
stage_labels <- vapply(PIPELINE_STAGES, function(s) s$description, character(1))
stage_choices <- setNames(stage_ids, stage_labels)

# The real control-panel body, factored into a function rather than a bare UI object so it
# can be called from inside renderUI() (i.e. only ever rendered server-side, after a
# successful password check) instead of always being part of the static UI tree.
control_panel_body_ui <- function() {
  tagList(
    titlePanel("WNBA Analytics -- Pipeline Control Panel"),
    helpText(
      "Multi-select one or more pipeline stages from pipeline_stages.R's registry (Issue #48)",
      "-- they queue and run sequentially in the order selected, a mini custom pipeline. Each",
      "queued stage is re-checked against the Issue #47 staleness gate the moment IT starts,",
      "not once for the whole queue up front, so an earlier queued stage producing a later",
      "one's input is correctly picked up. The run control is disabled for every session while",
      "any run (this tab's or another tab/user's) is in progress, to prevent two runs racing",
      "on the same cache files; there is no live log streaming -- captured output per stage",
      "appears as each stage finishes."
    ),
    sidebarLayout(
      sidebarPanel(
        width = 4,
        selectizeInput(
          "stage_id", "Pipeline stage(s) -- order = queue order",
          choices = stage_choices, multiple = TRUE,
          options = list(plugins = list("remove_button"), placeholder = "Select stage(s) in run order...")
        ),
        uiOutput("staleness_ui"),
        actionButton(
          "run_btn", "Run Queue", icon = icon("play"),
          class = "btn-primary",
          # Instant client-side feedback independent of the (about to block) server
          # round-trip -- see the header comment's EXECUTION MODEL note. Note this only fires
          # on an actual click, which the browser can't deliver at all while run_btn is
          # disabled (empty selection, the cross-session lock, or this session's own run in
          # progress) -- so a blocked click never reaches this handler client-side, and the
          # server-side guards in observeEvent(input$run_btn) below are pure defense-in-depth
          # for that case.
          onclick = "this.disabled = true; this.innerHTML = 'Running...';"
        ),
        br(), br(),
        uiOutput("lock_status_ui"),
        uiOutput("status_ui")
      ),
      mainPanel(
        width = 8,
        h4("Captured Output"),
        verbatimTextOutput("output_log"),
        br(),
        # GitHub issue #49 (Slice 5 of #43), second half: in addition to the raw log above, a
        # real chart/table preview of the cache file(s) the most-recently-run stage(s) just
        # wrote, built with the exact same build_*() helpers app.R's tabs use (see
        # render_stage_preview()/STAGE_PREVIEW_MAP above). Empty for stages with no mapped
        # helper, a missing cache file, or a helper error -- the log above still renders.
        h4("Data Preview"),
        uiOutput("stage_preview")
      )
    )
  )
}

# GitHub issue #54: mod_login_ui() is ALWAYS mounted (it manages its own visibility --
# collapses to an empty tagList() once logged in, per auth_login_module.R) so the login/
# signup form is never gated behind anything itself; the protected control-panel body is a
# separate uiOutput, gated server-side on the `logged_in` reactive mod_login_server() returns
# (see server() below) -- genuinely absent from the DOM pre-auth, not merely CSS-hidden, same
# principle #53 established. Replaces #50's CONTROL_PANEL_PASSWORD gate entirely.
ui <- fluidPage(
  useShinyjs(),
  mod_login_ui("auth"),
  uiOutput("control_panel_root")
)

# ------------------------------------------------------------------------------------------
# Server
# ------------------------------------------------------------------------------------------
server <- function(input, output, session) {
  # GitHub issue #54: real multi-user auth, replacing #50's single shared-password gate.
  # logged_in is a reactive(TRUE/FALSE) from mod_login_server() -- session-scoped only, no
  # persisted state (a fresh page load/new session always starts logged out, per #53).
  logged_in <- mod_login_server("auth")

  output$control_panel_root <- renderUI({
    if (!isTRUE(logged_in())) return(NULL)
    control_panel_body_ui()
  })

  # rv: THIS session's queue-run state only (which stage it's up to, results so far). Safe to
  # keep per-session because only the session that successfully acquired .PIPELINE_RUN_LOCK
  # ever advances a queue -- a second session that failed to acquire the lock never touches
  # its own rv$queue at all, it just polls the global lock (see lock_poll below) to keep its
  # own run control disabled until the lock clears.
  rv <- reactiveValues(queue = character(0), idx = 0L, running = FALSE,
                        results = list(), override = FALSE)

  output$output_log      <- renderText("(no stage has been run yet)")
  output$status_ui       <- renderUI(tags$em("Idle."))
  output$lock_status_ui  <- renderUI(NULL)
  # GitHub issue #49 (Slice 5 of #43), second half -- see render_stage_preview() above.
  output$stage_preview   <- renderUI(NULL)

  # Primary lock release path on an interrupted run -- see the "SELF-RELEASE ON AN
  # INTERRUPTED RUN" comment above .PIPELINE_RUN_LOCK's definition. Registered once per
  # session; harmless (and a no-op, by the token-match guard inside pipeline_lock_release())
  # for a session that never held the lock in the first place.
  session$onSessionEnded(function() {
    pipeline_lock_release(session$token)
  })

  # staleness_preview(): informational preview ONLY, over every currently-selected stage, in
  # queue order. This is deliberately NOT what gates whether a queued stage actually runs --
  # that gate is the fresh check_stage_staleness() call inside advance_queue() below, done at
  # the moment each stage starts (the crux of #48: an earlier queued stage may produce a
  # later one's input between queue-submission time and that later stage's start). Showing a
  # pre-run preview here is purely so the operator can see what's currently fresh/stale
  # before clicking Run Queue; it recomputes whenever the selection changes.
  staleness_preview <- reactive({
    ids <- input$stage_id
    if (is.null(ids) || length(ids) == 0) return(list())
    setNames(lapply(ids, function(id) check_stage_staleness(PIPELINE_STAGES[[id]])), ids)
  })

  # sync_run_btn_state(): single source of truth for whether the run control should be
  # clickable right now. Unlike #47's single-stage version, this does NOT look at per-stage
  # staleness at all -- queueing is always allowed regardless of a preview block (see
  # staleness_preview()'s comment above); the only two gates on STARTING a queue are (a) at
  # least one stage selected, and (b) the cross-session lock being free. Called reactively on
  # every lock poll tick (below) so every OTHER session's tab reflects a lock held elsewhere
  # within one poll interval, and again once this session's own queue finishes.
  sync_run_btn_state <- function() {
    no_selection <- is.null(input$stage_id) || length(input$stage_id) == 0
    if (no_selection || pipeline_lock_is_held() || isTRUE(rv$running)) {
      shinyjs::disable("run_btn")
    } else {
      shinyjs::enable("run_btn")
    }
  }

  # Cross-session lock visibility (success criterion 2): a lock acquired by SESSION A is a
  # mutation of the shared .PIPELINE_RUN_LOCK environment that SESSION B's own reactive graph
  # has no subscription to (it's a bare environment, not a reactive value) -- B has no way to
  # be *pushed* a notification when A locks or unlocks. invalidateLater() turns this into a
  # poll instead: every 500ms, every session's own reactive graph re-checks the shared lock
  # and resyncs its own run control to match. 500ms keeps a second tab's observed "disabled"
  # state within shinytest2's wait_for_idle()-style polling without hammering the single R
  # process between queue stages.
  observe({
    invalidateLater(500, session)
    sync_run_btn_state()
    output$lock_status_ui <- renderUI({
      if (pipeline_lock_is_held() && !isTRUE(rv$running)) {
        tags$div(style = "color: #8a6d00;",
                  tags$em("A pipeline run is in progress in another session -- run control disabled until it finishes."))
      } else {
        NULL
      }
    })
  })

  # Issue #47's staleness preview panel, generalized to N selected stages: renders fresh
  # every time the selection changes. checkboxInput("override_ack", ...) is a brand-new DOM
  # element each time the panel re-renders (i.e. every stage_id change), always starting
  # unchecked -- same no-leaking-acknowledgment behavior #47 established, now carried over a
  # change in the whole queue rather than a single stage.
  output$staleness_ui <- renderUI({
    previews <- staleness_preview()
    if (length(previews) == 0) {
      return(tags$div(tags$em("Select one or more stages to queue.")))
    }
    any_blocked <- any(vapply(previews, function(st) isTRUE(st$blocked), logical(1)))
    rows <- lapply(seq_along(previews), function(i) {
      id <- names(previews)[i]
      st <- previews[[i]]
      if (!isTRUE(st$blocked)) {
        tags$li(style = "color: #1a7a1a;", sprintf("%d. %s -- inputs OK", i, id))
      } else {
        tags$li(style = "color: #b30000;",
                 sprintf("%d. %s -- BLOCKED: %s", i, id,
                         paste(sprintf("[%s] %s", toupper(st$problems$reason), st$problems$path), collapse = "; ")))
      }
    })
    tagList(
      tags$strong("Queue preview (order = run order):"),
      tags$ol(rows),
      if (any_blocked) {
        tagList(
          tags$div(style = "color: #b30000;",
                    "One or more queued stages currently show blocked input(s). Each is",
                    "re-checked again the moment it actually starts -- an earlier queued",
                    "stage may resolve this before that point. The override below applies",
                    "queue-wide to whatever is still blocked when its turn comes."),
          checkboxInput("override_ack", "I know, run blocked stage(s) anyway", value = FALSE)
        )
      } else {
        NULL
      }
    )
  })

  # ----------------------------------------------------------------------------------------
  # advance_queue(token): runs ONE queued stage then reschedules itself for the next, instead
  # of looping synchronously over the whole queue. See the file header's EXECUTION MODEL
  # comment for why this shape (not a for-loop) is load-bearing for criteria 2 and 3, not
  # just a style choice. withReactiveDomain(session, ...) is needed because a later::later()
  # callback runs outside any reactive context -- shinyjs calls and reactiveValues writes
  # below would otherwise resolve against getDefaultReactiveDomain() == NULL.
  # ----------------------------------------------------------------------------------------
  advance_queue <- function(token) {
    withReactiveDomain(session, {
      # The lock may have been force-released out from under this token by the
      # LOCK_MAX_AGE_SECS fallback (pathological case), or this session may have already
      # ended (onSessionEnded already released it) -- either way, there is nothing safe left
      # to do except stop advancing.
      if (!identical(.PIPELINE_RUN_LOCK$owner_token, token) || isTRUE(session$isEnded())) {
        return(invisible(NULL))
      }

      if (rv$idx > length(rv$queue)) {
        pipeline_lock_release(token)
        rv$running <- FALSE
        shinyjs::html("run_btn", html = paste(as.character(icon("play")), "Run Queue"))
        shinyjs::enable("stage_id")
        sync_run_btn_state()
        return(invisible(NULL))
      }

      stage_id <- rv$queue[rv$idx]
      stage    <- PIPELINE_STAGES[[stage_id]]

      shinyjs::html("run_btn", html = sprintf(
        "Running (%d/%d): %s...", rv$idx, length(rv$queue), stage_id
      ))

      # THE crux of #48: a fresh staleness check, right now, at the moment THIS stage starts
      # -- not whatever check_stage_staleness() returned back when the queue was submitted
      # (rv$queue was only a list of ids; no staleness result was cached at submission time).
      # If stage N-1 just wrote the file stage N declares as an input, this call sees that
      # fresh file on disk, because it runs after stage N-1's run_pipeline_stage_captured()
      # call below has already returned.
      st <- check_stage_staleness(stage)
      if (isTRUE(st$blocked) && !isTRUE(rv$override)) {
        entry <- list(id = stage_id, status = "skipped_blocked", problems = st$problems,
                       output = character(0), error = NULL, elapsed = 0, override_used = FALSE)
      } else {
        res <- run_pipeline_stage_captured(stage)
        entry <- list(id = stage_id,
                       status = if (isTRUE(res$success)) "pass" else "fail",
                       problems = st$problems,
                       output = res$output, error = res$error, elapsed = res$elapsed,
                       override_used = isTRUE(st$blocked) && isTRUE(rv$override))
      }
      rv$results <- c(rv$results, list(entry))
      rv$idx <- rv$idx + 1L

      # Return control to Shiny's event loop NOW, between stages, rather than recursing in
      # place -- see the file header's EXECUTION MODEL comment.
      later::later(function() advance_queue(token), delay = 0)
      invisible(NULL)
    })
  }

  observeEvent(input$run_btn, {
    ids <- input$stage_id
    if (is.null(ids) || length(ids) == 0) {
      shinyjs::html("run_btn", html = paste(as.character(icon("play")), "Run Queue"))
      sync_run_btn_state()
      return()
    }

    # Defense-in-depth server-side guard (see the actionButton's onclick comment above): the
    # client can't normally click a disabled button, but never trust that alone. A failed
    # acquire means another session (or this one, re-entrantly, which shouldn't be reachable
    # via the UI) already holds the lock.
    if (!pipeline_lock_acquire(session$token)) {
      shinyjs::html("run_btn", html = paste(as.character(icon("play")), "Run Queue"))
      sync_run_btn_state()
      showNotification(
        "A pipeline run is already in progress (started elsewhere). Please wait for it to finish.",
        type = "warning"
      )
      return()
    }

    rv$queue    <- ids               # snapshot at click time -- the chosen queue order.
    rv$idx      <- 1L
    rv$running  <- TRUE
    rv$results  <- list()
    rv$override <- isTRUE(input$override_ack)

    shinyjs::disable("stage_id")
    shinyjs::disable("run_btn")  # already disabled client-side by onclick; this covers a
                                  # server-initiated resync (e.g. restored session).

    later::later(function() advance_queue(session$token), delay = 0)
  })

  observeEvent(rv$results, {
    if (length(rv$results) == 0 && !isTRUE(rv$running)) {
      # Initial/idle state -- no queue has ever been run in this session yet. Keeps the
      # pre-#48 idle UX intact rather than showing "Queue complete: 0 stage(s) run."
      return()
    }
    output$status_ui <- renderUI({
      n <- length(rv$queue)
      header <- if (isTRUE(rv$running) && rv$idx <= n) {
        tags$div(tags$em(sprintf("Running stage %d of %d (%s)...",
                                   rv$idx, n, rv$queue[rv$idx])))
      } else if (isTRUE(rv$running)) {
        tags$div(tags$em("Finishing..."))
      } else {
        tags$div(tags$strong(sprintf("Queue complete: %d stage(s) run.", length(rv$results))))
      }
      rows <- lapply(rv$results, function(entry) {
        label_color <- switch(entry$status,
          pass           = "#1a7a1a",
          fail           = "#b30000",
          skipped_blocked = "#8a6d00",
          "#333333"
        )
        label <- switch(entry$status,
          pass            = sprintf("PASS (%.2fs)", entry$elapsed),
          fail            = sprintf("FAIL (%.2fs)", entry$elapsed),
          skipped_blocked = "SKIPPED (blocked input, no override)",
          entry$status
        )
        override_note <- if (isTRUE(entry$override_used)) " [ran via staleness override]" else ""
        tags$li(style = sprintf("color: %s;", label_color),
                 sprintf("%s -- %s%s", entry$id, label, override_note))
      })
      tagList(header, tags$ul(rows))
    }, quoted = FALSE)

    output$output_log <- renderText({
      if (length(rv$results) == 0) return("(no output captured)")
      blocks <- vapply(rv$results, function(entry) {
        head_line <- sprintf("===== %s [%s] =====", entry$id, entry$status)
        body <- if (entry$status == "skipped_blocked") {
          paste(sprintf("[%s] %s", toupper(entry$problems$reason), entry$problems$detail), collapse = "\n")
        } else if (length(entry$output) == 0) {
          "(no output captured)"
        } else {
          paste(entry$output, collapse = "\n")
        }
        paste(head_line, body, sep = "\n")
      }, character(1))
      paste(blocks, collapse = "\n\n")
    })

    # GitHub issue #49 (Slice 5 of #43), second half: for the most-recently-run stage(s) in
    # rv$results (this session's just-completed/in-progress queue), look up each one's
    # STAGE_PREVIEW_MAP entry and render it via render_stage_preview() -- NULL (no mapping,
    # missing cache, or helper error) is silently dropped, never shown as an error, so the log
    # dump above always renders regardless of this block's outcome.
    output$stage_preview <- renderUI({
      if (length(rv$results) == 0) return(NULL)
      previews <- lapply(rv$results, function(entry) render_stage_preview(entry$id))
      previews <- previews[!vapply(previews, is.null, logical(1))]
      if (length(previews) == 0) return(NULL)
      tagList(previews)
    })
  }, ignoreNULL = FALSE)

  observe({
    sync_run_btn_state()
  })
}

# GitHub issue #54: #50's onStart host/password refusal check is removed entirely along
# with CONTROL_PANEL_PASSWORD -- network-accessible launches are now protected by real
# per-account login (mod_login_server() above), not a single shared secret with an
# unset-equals-unprotected failure mode, so there is no longer an "unset" state that would
# leave the app silently unprotected. See docs/CONTROL_PANEL_SETUP.md for how to set
# CONTROL_PANEL_SIGNUP_KEY (gates new-account signup; existing accounts can still log in
# without it).
shinyApp(ui = ui, server = server)
