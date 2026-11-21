# ==============================================================================
# render_weekly_gifs.R  (pipeline stage, front-office weekly GIF re-render)
#
# Re-renders the tools/gif_*.R charts about once a week so the landing page's 7-day
# slideshow always has current MLB GIFs. Runs when the season is in progress (the season_state
# that tools/export_landing_digest.R publishes in web/public/data/landing_digest.json, stage 14c,
# earlier in the same run: "regular" or "postseason") AND the last successful render is GIF_RERENDER_DAYS+ days old. Override
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
# function never stop()s. The scripts write their output to cache/viz/ and (unlike other sports) none copies it into
# web/public/media; after each success sync_gif_to_media() copies cache/viz/<name>.gif/.png into
# web/public/media when they differ (these scripts only write cache/viz), so every rendered GIF is
# published. The export stage that follows (export_visual_media_index.R) rebuilds
# visual_media_index.json from web/public/media.
#
# Status file (cache/gif_render_status.json) is rewritten on every run that is not a total
# failure. run_full_pipeline.R declares it with strict_output = TRUE, so a run where every
# script failed is reported as a failed stage.
# ==============================================================================

GIF_RENDER_TIMEOUT_SEC <- 600

# Audit 2026-11-21 of all 21 tools/gif_*.R. Every script writes cache/viz/<name>.gif/.png (the
# scripts do not copy to web/public/media; sync_gif_to_media() below publishes them). Every
# script defaults to season = 2026 (the value of MLB_CURRENT_SEASON), so the stage refuses to run
# when MLB_CURRENT_SEASON moves past GIF_RENDER_SCRIPT_SEASON (see run_render_weekly_gifs): a
# 2027 re-render of 2026 data must never be stamped with a new date. Nothing hard-codes a worktree
# path. internal-docs/hand-typed-media-for-removal.md lists one MLB file (the payroll bubble).
# Exclusions (the 13 not listed here are scheduled):
GIF_RENDER_SCRIPT_SEASON <- 2026L
GIF_RENDER_EXCLUDED <- c(
  "gif_payroll_efficiency_bubble.R"  = "hand-typed TEAM_PAYROLL_2026 table, 35.0 WAR imputed and missing payroll filled with 150.0 (hand-typed-media-for-removal.md); not built from real data end to end, absent from visual_media_index",
  "gif_elo_trajectories.R"           = "writes cache/viz/elo_trajectories_<season>.gif (not the gif_<name> naming, no still frame) and has no visual_media_index entry, so its output could never be published",
  "gif_trophy_lift_champions.R"      = "set.seed(20261030) then runif/rnorm/sample draw the confetti positions, sizes, shapes and colours shown in the chart (random draws that affect the chart); also a one-off 2026 World Series finale",
  "gif_trade_deadline_splits.R"      = "hard-codes deadline_date = \"2026-08-01\", so the before/after split is a typed 2026 date, not read from data",
  "gif_bracket_progression.R"        = "replays one finished postseason (season = 2026): its inputs only cover that old postseason, so a weekly re-render would stamp it as new",
  "gif_pennant_showdown.R"           = "replays the 2026 League Championship Series (season = 2026); inputs only cover that finished series",
  "gif_postseason_leverage.R"        = "2026 postseason relief workload (schedule game types F/D/L plus world_series.json); inputs only cover that old postseason",
  "gif_world_series_wpa_worm.R"      = "2026 World Series win-probability worm read from world_series.json; inputs only cover that old series"
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

# In season = landing_digest.json's season_state is "regular" or "postseason" (written by
# tools/export_landing_digest.R, stage 14c, earlier in the same pipeline run).
mlb_gif_in_season <- function(now = Sys.time(),
                              digest_path = file.path("web", "public", "data", "landing_digest.json")) {
  if (!file.exists(digest_path)) {
    .gif_log("warn", sprintf(">>> [WARN] %s missing: season state unknown, treating as offseason", digest_path))
    return(FALSE)
  }
  p <- tryCatch(jsonlite::fromJSON(digest_path, simplifyVector = FALSE), error = function(e) NULL)
  st <- if (is.null(p)) NULL else p$season_state
  if (is.null(st) || !is.character(st) || length(st) != 1L || !nzchar(st)) {
    .gif_log("warn", sprintf(">>> [WARN] %s unreadable or has no season_state: season state unknown, treating as offseason", digest_path))
    return(FALSE)
  }
  st %in% c("regular", "postseason")
}

# Copy cache/<stem>.gif and .png into media_dir when missing or different, so a script that
# only wrote cache/ still publishes. No-op for scripts that already copied (identical bytes).
# Only a source written during this script's run (mtime >= t0) is copied; a stale cache file is
# never published as if it were a fresh render.
sync_gif_to_media <- function(script, media_dir, cache_dir = file.path(MLB_CACHE_ROOT, "viz"), t0) {
  stem <- tools::file_path_sans_ext(basename(script))
  for (ext in c(".gif", ".png")) {
    src <- file.path(cache_dir, paste0(stem, ext)); dst <- file.path(media_dir, paste0(stem, ext))
    if (!file.exists(src)) next
    if (file.mtime(src) < t0 - 2) {  # 2 s slack for coarse filesystem timestamps
      .gif_log("warn", sprintf(">>> [WARN] %s exited 0 but did not rewrite %s", basename(script), basename(src)))
      next
    }
    if (file.exists(dst) && file.size(dst) == file.size(src) &&
        identical(readBin(dst, "raw", file.size(dst)), readBin(src, "raw", file.size(src)))) next
    if (!dir.exists(media_dir)) dir.create(media_dir, recursive = TRUE)
    file.copy(src, dst, overwrite = TRUE, copy.date = TRUE)
  }
  invisible(NULL)
}

.gif_log <- function(level, msg) {
  message(msg)
  fn <- paste0("log_", level)
  if (exists(fn, mode = "function")) get(fn, mode = "function")(msg, script = "render_weekly_gifs.R")
}

run_render_weekly_gifs <- function(media_dir = file.path("web", "public", "media"), scripts = list_gif_scripts(),
                                   in_season = mlb_gif_in_season(now), now = Sys.time(),
                                   status_path = file.path(MLB_CACHE_ROOT, "gif_render_status.json"),
                                   timeout_sec = GIF_RENDER_TIMEOUT_SEC,
                                   cache_dir = file.path(MLB_CACHE_ROOT, "viz"),
                                   current_season = MLB_CURRENT_SEASON) {
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
  } else if (!force && !identical(as.integer(current_season), GIF_RENDER_SCRIPT_SEASON)) {
    result$skipped_reason <- "scripts_pinned_to_other_season"
  } else if (!force && !gif_scripts_due(last_render, now)) {
    result$skipped_reason <- "not_due"
  }
  if (!is.null(result$skipped_reason)) {
    .gif_log("info", sprintf(">>> [SKIP] weekly GIF render: %s", result$skipped_reason))
    write_status(result, last_render)
    return(result)
  }

  for (s in scripts) {
    log_file <- tempfile(paste0(tools::file_path_sans_ext(basename(s)), "_"), fileext = ".log")
    t0 <- Sys.time()
    st <- tryCatch(run_gif_script(s, log_file, timeout_sec), error = function(e) -1L)
    secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    if (identical(as.integer(st), 0L)) {
      tryCatch(sync_gif_to_media(s, media_dir, cache_dir, t0), error = function(e)
        .gif_log("warn", sprintf(">>> [WARN] %s: could not sync to %s: %s", basename(s), media_dir, conditionMessage(e))))
      result$rendered <- c(result$rendered, basename(s))
      message(sprintf(">>> [OK] %s (%.0f s)", basename(s), secs))
    } else {
      result$failed <- c(result$failed, basename(s))
      tail_txt <- if (file.exists(log_file)) paste(utils::tail(readLines(log_file, warn = FALSE), 5), collapse = " | ") else ""
      .gif_log("warn", sprintf(">>> [FAIL] %s (exit %s, %.0f s) %s", basename(s), st, secs, tail_txt))
    }
  }

  if (length(result$failed) && !length(result$rendered)) {
    .gif_log("error", ">>> [FAIL] weekly GIF render: every script failed; status file not rewritten")
  } else {
    write_status(result, if (length(result$rendered)) now else last_render)
  }
  .gif_log("info", sprintf("weekly GIF render: %d rendered, %d failed", length(result$rendered), length(result$failed)))
  result
}
