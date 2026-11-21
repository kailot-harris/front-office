# ==============================================================================
# render_weekly_gifs.R  (pipeline stage, front-office weekly GIF re-render)
#
# Re-renders the tools/gif_*.R charts about once a week so the landing page's 7-day
# slideshow always has current NFL GIFs. Runs when the season is in progress (the same
# ld_season_state() that feeds landing_digest.json's season_state: "regular" or
# "postseason") AND the last successful render is GIF_RERENDER_DAYS+ days old. Override
# with FO_FORCE_GIF_RENDER=1.
#
# "Last successful render" is `last_success_at` in cache/gif_render_status.json (the end of
# the last run that rendered at least one script). It is deliberately NOT the index's
# generated_at: for an unchanged file that is the last commit (publish) time, so a publish
# commit would restart the 6-day clock. Only when the status file is missing (fresh
# checkout) does it fall back to the newest GIF's mtime in media_dir.
#
# Each script runs in its own R process (they setwd() and define globals) with a 10-minute
# timeout. On Windows Rterm.exe is started directly through processx (no Rscript.exe
# launcher in between), and a timeout kills the whole process tree (`taskkill /T /F`), so no
# orphaned R/ffmpeg children survive. A failure logs ">>> [FAIL] <script>" and the next script runs; this
# function never stop()s. The scripts write their output to cache/; the export stage that
# follows (export_web_datasets.R) copies them into web/public/animations and rebuilds
# visual_media_index.json. It also writes cache/gif_render_outcome.json every run (rendered /
# failed scripts + run start); the exporter uses it to refuse a stale cache GIF left by a
# failed script (or an exit-0 script that did not rewrite its output) and copies with
# copy.date = TRUE, so a published file's mtime is always its real render time.
#
# Status file (cache/gif_render_status.json) is rewritten on every run that is not a total
# failure. run_full_pipeline.R declares it with strict_output = TRUE, so a run where every
# script failed is reported as a failed stage.
# ==============================================================================

GIF_RENDER_TIMEOUT_SEC <- 600

# Audit 2026-11-21 (all 17 tools/gif_*.R). No script hard-codes a path (all resolve the
# root via NFL_PROJECT_DIR / --file= / cwd with config.R); none plots random draws (the
# set.seed/slice_sample in gif_elo_heatmap.R picks console spot-check rows only). The
# exclusions below read history caches that no pipeline stage refreshes, so a weekly
# re-render would stamp weeks-old numbers with a fresh date.
GIF_RENDER_EXCLUDED <- c(
  "gif_playoff_odds_heatmap.R" = "reads CACHE_PLAYOFF_ODDS_HISTORY, built only by hand (tools/playoff_odds_history_backfill.R; weeks 1-6 as of 2026-11-21)",
  "gif_playoff_prob_bump.R"    = "reads CACHE_PLAYOFF_ODDS_HISTORY, built only by hand (tools/playoff_odds_history_backfill.R; weeks 1-6 as of 2026-11-21)",
  "gif_turnover_margin_race.R" = "reads CACHE_TURNOVER_HISTORY, built only by hand (tools/turnover_margin_history.R; weeks 1-5 as of 2026-11-21)"
)


list_gif_scripts <- function(tools_dir = "tools") {
  s <- sort(list.files(tools_dir, pattern = "^gif_.*\\.R$"))
  s <- s[!s %in% names(GIF_RENDER_EXCLUDED)]
  if (length(s)) file.path(tools_dir, s) else character(0)
}

gif_scripts_due <- function(newest_gif_time, now = Sys.time(), days = GIF_RERENDER_DAYS) {
  t <- newest_gif_time[!is.na(newest_gif_time)]
  if (!length(t)) return(TRUE)
  as.numeric(difftime(now, max(t), units = "days")) >= days
}

# Newest GIF mtime in media_dir (fallback only: see header).
newest_gif_time <- function(media_dir) {
  gifs <- list.files(media_dir, pattern = "\\.gif$", full.names = TRUE, ignore.case = TRUE)
  if (!length(gifs)) return(as.POSIXct(NA))
  max(file.mtime(gifs))
}

# Time the scripts last rendered successfully: the status file's last_success_at, else
# (status file missing) the newest GIF mtime. NA when neither exists (-> due).
last_gif_render_time <- function(status_path, media_dir) {
  if (file.exists(status_path)) {
    st <- tryCatch(jsonlite::fromJSON(status_path), error = function(e) NULL)
    ts <- st$last_success_at
    if (is.null(ts) || !nzchar(ts)) return(as.POSIXct(NA))
    return(as.POSIXct(ts, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  }
  newest_gif_time(media_dir)
}

# Run one script in its own R process. Returns its exit status, 124 on timeout.
run_gif_script <- function(script, log_file, timeout_sec = GIF_RENDER_TIMEOUT_SEC) {
  win <- .Platform$OS.type == "windows"
  r_bin <- file.path(R.home("bin"), if (win) "Rterm.exe" else "Rscript")
  args <- if (win) c("--no-echo", "--no-restore", "--no-save", paste0("--file=", script)) else script
  p <- processx::process$new(r_bin, args, stdout = log_file, stderr = "2>&1",
                             cleanup = TRUE, cleanup_tree = TRUE)
  p$wait(timeout = timeout_sec * 1000)
  if (p$is_alive()) {
    if (win) {
      suppressWarnings(system2("taskkill", c("/T", "/F", "/PID", p$get_pid()), stdout = FALSE, stderr = FALSE))
    }
    tryCatch(p$kill_tree(), error = function(e) NULL)
    return(124L)
  }
  as.integer(p$get_exit_status())
}

nfl_gif_in_season <- function(now = Sys.time()) {
  if (!exists("ld_season_state", mode = "function")) source("tools/build_landing_digest.R")
  if (!file.exists(CACHE_SCHEDULES)) return(FALSE)
  st <- ld_season_state(readRDS(CACHE_SCHEDULES), ld_slate_date(now), CURRENT_SEASON)$season_state
  isTRUE(st %in% c("regular", "postseason"))
}

.gif_log <- function(level, msg) {
  message(msg)
  fn <- paste0("log_", level)
  if (exists(fn, mode = "function")) get(fn, mode = "function")(msg, script = "render_weekly_gifs.R")
}

run_render_weekly_gifs <- function(media_dir = WEB_ANIM_DIR, scripts = list_gif_scripts(),
                                   in_season = nfl_gif_in_season(now), now = Sys.time(),
                                   status_path = file.path(CACHE_DIR, "gif_render_status.json"),
                                   outcome_path = file.path(dirname(status_path), "gif_render_outcome.json"),
                                   timeout_sec = GIF_RENDER_TIMEOUT_SEC) {
  force <- identical(Sys.getenv("FO_FORCE_GIF_RENDER"), "1")
  result <- list(rendered = character(0), failed = character(0), skipped_reason = NULL)
  fmt <- "%Y-%m-%dT%H:%M:%SZ"
  last_render <- last_gif_render_time(status_path, media_dir)
  write_status <- function(res, success_at) {
    jsonlite::write_json(list(run_at = format(now, fmt, tz = "UTC"),
                              last_success_at = if (is.na(success_at)) NULL else format(success_at, fmt, tz = "UTC"),
                              forced = force, rendered = res$rendered, failed = res$failed,
                              skipped_reason = res$skipped_reason),
                         status_path, auto_unbox = TRUE, null = "null", pretty = TRUE)
  }

  if (!force && !isTRUE(in_season)) {
    result$skipped_reason <- "offseason"
  } else if (!force && !gif_scripts_due(last_render, now)) {
    result$skipped_reason <- "not_due"
  }
  # Per-run outcome for the exporter (web_media_filter.R gif_cache_copy_ok): which scripts
  # exited 0 / failed THIS run and when the run began. Written on every run, including a total
  # failure and a skip (empty lists), so a previous run's failures never linger.
  write_outcome <- function(res) {
    jsonlite::write_json(list(run_at = format(now, fmt, tz = "UTC"),
                              rendered = res$rendered, failed = res$failed),
                         outcome_path, auto_unbox = FALSE, null = "null", pretty = TRUE)
  }
  if (!is.null(result$skipped_reason)) {
    .gif_log("info", sprintf(">>> [SKIP] weekly GIF render: %s", result$skipped_reason))
    write_outcome(result)
    write_status(result, last_render)
    return(result)
  }

  for (s in scripts) {
    log_file <- tempfile(paste0(tools::file_path_sans_ext(basename(s)), "_"), fileext = ".log")
    t0 <- Sys.time()
    st <- tryCatch(run_gif_script(s, log_file, timeout_sec), error = function(e) -1L)
    secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    if (identical(as.integer(st), 0L)) {
      result$rendered <- c(result$rendered, basename(s))
      message(sprintf(">>> [OK] %s (%.0f s)", basename(s), secs))
    } else {
      result$failed <- c(result$failed, basename(s))
      tail_txt <- if (file.exists(log_file)) paste(utils::tail(readLines(log_file, warn = FALSE), 5), collapse = " | ") else ""
      .gif_log("warn", sprintf(">>> [FAIL] %s (exit %s, %.0f s) %s", basename(s), st, secs, tail_txt))
    }
  }

  write_outcome(result)
  if (length(result$failed) && !length(result$rendered)) {
    .gif_log("error", ">>> [FAIL] weekly GIF render: every script failed; status file not rewritten")
  } else {
    write_status(result, if (length(result$rendered)) now else last_render)
  }
  .gif_log("info", sprintf("weekly GIF render: %d rendered, %d failed", length(result$rendered), length(result$failed)))
  result
}
