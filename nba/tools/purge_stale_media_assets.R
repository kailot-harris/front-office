# ==============================================================================
# tools/purge_stale_media_assets.R
# Path: tools/purge_stale_media_assets.R
#
# Media Asset Maintenance & Purge Routine (Closes Issue #45)
#
# Retention Policy:
#   - Retain trailing 30 days of daily assets in memory / disk (days 0-30).
#   - Prune stale assets aged 31-60 days (days 31-60).
#   - Protect canonical / season-level assets via allowlist patterns:
#     * gif_elo_rank_bump*
#     * gif_net_rating_quadrant*
#     * gif_point_diff_race*
#     * any additional specified protected patterns.
#
# Usage:
#   Rscript tools/purge_stale_media_assets.R [--dry-run] [--target-dir=<path>]
# ==============================================================================

.purge_project_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  if (length(f) == 1L && nzchar(f) && file.exists(f)) {
    cand <- normalizePath(dirname(dirname(f)), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(cand, "config.R"))) return(cand)
  }
  d <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  for (i in 1:6) {
    if (file.exists(file.path(d, "config.R"))) return(d)
    p <- dirname(d)
    if (identical(p, d)) break
    d <- p
  }
  getwd()
}

local({
  root <- .purge_project_root()
  if (!identical(normalizePath(getwd(), winslash = "/", mustWork = FALSE), root)) setwd(root)
})

if (file.exists("config.R")) {
  source("config.R")
}

CANONICAL_MEDIA_ALLOWLIST <- c(
  "^gif_elo_rank_bump",
  "^gif_net_rating_quadrant",
  "^gif_point_diff_race",
  "^gif_player_shot_chart",
  "^nba_predictions_"
)

is_canonical_asset <- function(filename, allowlist = CANONICAL_MEDIA_ALLOWLIST) {
  base <- basename(filename)
  for (pat in allowlist) {
    if (grepl(pat, base, ignore.case = TRUE)) {
      return(TRUE)
    }
  }
  FALSE
}

classify_media_asset <- function(filepath, ref_time = Sys.time(),
                                 active_days = 30, purge_max_days = 60,
                                 allowlist = CANONICAL_MEDIA_ALLOWLIST) {
  fname <- basename(filepath)
  is_canon <- is_canonical_asset(fname, allowlist)
  
  info <- file.info(filepath)
  mtime <- info$mtime
  size <- info$size
  
  age_days <- as.numeric(difftime(ref_time, mtime, units = "days"))
  
  if (is_canon) {
    status <- "PROTECTED_CANONICAL"
    action <- "KEEP"
  } else if (age_days <= active_days) {
    status <- "ACTIVE_WINDOW"
    action <- "KEEP"
  } else if (age_days <= purge_max_days) {
    status <- "PURGE_WINDOW"
    action <- "PURGE"
  } else {
    # Beyond 60 days
    status <- "PURGE_WINDOW"
    action <- "PURGE"
  }
  
  list(
    file = fname,
    path = filepath,
    mtime = mtime,
    age_days = age_days,
    size_bytes = size,
    is_canonical = is_canon,
    status = status,
    action = action
  )
}

purge_stale_media_assets <- function(target_dirs = NULL,
                                     dry_run = FALSE,
                                     active_days = 30,
                                     purge_max_days = 60,
                                     allowlist = CANONICAL_MEDIA_ALLOWLIST,
                                     ref_time = Sys.time()) {
  if (is.null(target_dirs)) {
    cache_dir <- if (exists("CACHE_DIR")) CACHE_DIR else file.path(getwd(), "cache")
    web_media_dir <- if (exists("PROJECT_DIR")) {
      file.path(PROJECT_DIR, "web", "public", "media")
    } else {
      file.path(getwd(), "web", "public", "media")
    }
    target_dirs <- c(cache_dir, web_media_dir)
  }
  
  target_dirs <- unique(normalizePath(target_dirs[dir.exists(target_dirs)], winslash = "/", mustWork = FALSE))
  
  all_classified <- list()
  purged_files <- character(0)
  kept_files <- character(0)
  
  cat("================================================================\n")
  cat(sprintf("NBA Media Purge Routine (Issue #45) [%s]\n",
              if (dry_run) "DRY RUN - no files will be deleted" else "LIVE PURGE"))
  cat("================================================================\n")
  cat(sprintf("  Active window (retained): 0 to %d days\n", active_days))
  cat(sprintf("  Purge window (pruned)   : %d to %d+ days\n", active_days + 1L, purge_max_days))
  cat(sprintf("  Protected patterns      : %s\n", paste(allowlist, collapse = ", ")))
  cat(sprintf("  Target directories      :\n"))
  for (d in target_dirs) cat(sprintf("    - %s\n", d))
  cat("\n")
  
  for (d in target_dirs) {
    files <- list.files(d, pattern = "\\.(gif|png|jpg|jpeg)$", full.names = TRUE, ignore.case = TRUE)
    if (!length(files)) next
    
    for (f in files) {
      cl <- classify_media_asset(f, ref_time = ref_time,
                                 active_days = active_days,
                                 purge_max_days = purge_max_days,
                                 allowlist = allowlist)
      all_classified[[length(all_classified) + 1L]] <- cl
      
      if (cl$action == "PURGE") {
        if (!dry_run) {
          unlink(cl$path)
          cat(sprintf("  [PURGED] %s (age: %.1f days, %d bytes)\n", cl$file, cl$age_days, cl$size_bytes))
        } else {
          cat(sprintf("  [WOULD PURGE] %s (age: %.1f days, %d bytes)\n", cl$file, cl$age_days, cl$size_bytes))
        }
        purged_files <- c(purged_files, cl$path)
      } else {
        cat(sprintf("  [RETAINED - %s] %s (age: %.1f days)\n", cl$status, cl$file, cl$age_days))
        kept_files <- c(kept_files, cl$path)
      }
    }
  }
  
  cat("----------------------------------------------------------------\n")
  cat(sprintf("Summary: %d total inspected | %d kept | %d %s\n",
              length(all_classified), length(kept_files), length(purged_files),
              if (dry_run) "would be purged" else "purged"))
  cat("================================================================\n\n")
  
  invisible(list(
    dry_run = dry_run,
    target_dirs = target_dirs,
    classified = all_classified,
    purged = purged_files,
    kept = kept_files
  ))
}

# ------------------------------------------------------------------------------
# CLI Entrypoint
# ------------------------------------------------------------------------------
local({
  argv <- commandArgs(trailingOnly = FALSE)
  files <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (!any(grepl("purge_stale_media_assets\\.R$", files))) return(invisible(NULL))
  
  opts <- commandArgs(trailingOnly = TRUE)
  dry_run <- "--dry-run" %in% opts
  
  target_arg <- grep("^--target-dir=", opts, value = TRUE)
  target_dirs <- if (length(target_arg)) {
    sub("^--target-dir=", "", target_arg[length(target_arg)])
  } else {
    NULL
  }
  
  res <- purge_stale_media_assets(target_dirs = target_dirs, dry_run = dry_run)
  quit(status = 0L)
})
