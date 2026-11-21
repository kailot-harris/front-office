# ==============================================================================
# render_weekly_gifs.R  (pipeline stage, front-office weekly GIF re-render)
#
# Re-renders the tools/gif_*.R charts about once a week so the landing page's 7-day
# slideshow always has current WNBA GIFs. Runs when the season is in progress (the same
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
# function never stop()s. The scripts write their output to cache/ and most also copy it into
# web/public/media; after each success sync_gif_to_media() copies cache/<name>.gif/.png into
# web/public/media when they differ (four scripts only wrote cache/), so every rendered GIF is
# published. The export stage that follows (export_visual_media_index.R) rebuilds
# visual_media_index.json from web/public/media.
#
# Status file (cache/gif_render_status.json) is rewritten on every run that is not a total
# failure. run_full_pipeline.R declares it with strict_output = TRUE, so a run where every
# script failed is reported as a failed stage.
# ==============================================================================

GIF_RENDER_TIMEOUT_SEC <- 600

# Audit 2026-11-21 (the 12 tools/gif_*.R plus tools/build_net_rating_trajectory_gif.R). No script
# hard-codes a worktree path (all resolve the root from --file= / here::here() / cwd); none plots
# random draws (no set.seed/sample/runif feeds a chart; the 2-D logo "jitter" is a deterministic
# label-collision nudge); no simulated or hand-typed data (internal-docs/hand-typed-media-for-removal.md
# lists none for WNBA). The 10 scheduled scripts write cache/ and copy to web/public/media through
# viz_render_frames(); sync_gif_to_media() below is a safety net for any that only wrote cache/.
# Exclusions:
GIF_RENDER_EXCLUDED <- c(
  "gif_rapm_leaders_2026.R"          = "TARGET_SEASON is the literal 2026 (and the title says 2026): once CURRENT_SEASON moves on, a re-render would stamp this week's date on 2026 numbers; it also writes cache/rapm_ratings_2026.rds as a side effect",
  "gif_finals_closing_stretch.R"     = "chart of one named game (2026 Finals Game 7) whose play-by-play wehoop has not ingested, so it always fails; it has no visual_media_index entry, so its output would never be published",
  "build_net_rating_trajectory_gif.R" = "Finals-only 2026 series, with a labeled hard-coded GS/ATL fallback pair when the backtest cache is unreadable; writes outside the gif_* naming and has no visual_media_index entry (listed as missing metadata in internal-docs/hand-typed-media-for-removal.md)"
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

# In season = the landing digest's season_state is "regular" or "postseason" (same
# ld_season_state() that feeds landing_digest.json), computed from matchups_slates.json.
wnba_gif_in_season <- function(now = Sys.time(),
                               matchups_path = file.path("web", "public", "data", "matchups_slates.json")) {
  if (!exists("ld_season_state", mode = "function")) source("tools/build_landing_digest.R")
  if (!file.exists(matchups_path)) {
    .gif_log("warn", sprintf(">>> [WARN] %s missing: season state unknown, treating as offseason", matchups_path))
    return(FALSE)
  }
  p <- tryCatch(jsonlite::fromJSON(matchups_path, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(p) || !length(p$matchups)) {
    .gif_log("warn", sprintf(">>> [WARN] %s unreadable or empty: season state unknown, treating as offseason", matchups_path))
    return(FALSE)
  }
  g <- ld_normalize_games(as.data.frame(p$matchups, stringsAsFactors = FALSE))
  st <- ld_season_state(g, ld_slate_date(now))
  isTRUE(st %in% c("regular", "postseason"))
}

# Copy cache/<stem>.gif and .png into media_dir when missing or different, so a script that
# only wrote cache/ still publishes. No-op for scripts that already copied (identical bytes).
# Only a source written during this script's run (mtime >= t0) is copied; a stale cache file is
# never published as if it were a fresh render.
sync_gif_to_media <- function(script, media_dir, cache_dir = CACHE_DIR, t0) {
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
                                   in_season = wnba_gif_in_season(now), now = Sys.time(),
                                   status_path = file.path(CACHE_DIR, "gif_render_status.json"),
                                   timeout_sec = GIF_RENDER_TIMEOUT_SEC,
                                   cache_dir = CACHE_DIR) {
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
