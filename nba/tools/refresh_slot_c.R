# ==============================================================================
# tools/refresh_slot_c.R - Slot C (01:00 local) daily predictions graphic refresh
#
# Regenerates nba_predictions_<date>.png/.gif and nba_predictions_today.png/.gif
# in cache/ and web/public/media/ for Sys.Date() (or --date=YYYY-MM-DD),
# including the deterministic no-games / offseason fallback card when zero
# games are scheduled today (NBA_analytics#130, Part 2).
#
# When invoked with --dry-run or --publish, also runs tools/publish_web.R so
# media-only diffs (e.g. a quiet night where JSON payloads did not change) are
# gated and published cleanly through Assertion C.
#
# Usage:
#   Rscript --vanilla tools/refresh_slot_c.R                   # render only
#   Rscript --vanilla tools/refresh_slot_c.R --dry-run         # render + gate dry run
#   Rscript --vanilla tools/refresh_slot_c.R --publish         # render + live publish
#   Rscript --vanilla tools/refresh_slot_c.R --date=2026-11-24 # explicit date
# ==============================================================================

.slotc_project_root <- function() {
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
  stop("refresh_slot_c.R: cannot locate the project root (no config.R found).")
}

local({
  root <- .slotc_project_root()
  if (!identical(normalizePath(getwd(), winslash = "/", mustWork = FALSE), root)) setwd(root)
})

source("config.R")

.slotc_load_plot_env <- function(project_root = PROJECT_DIR) {
  plot_script <- file.path(project_root, "tools", "plot_today_predictions.R")
  if (!file.exists(plot_script)) {
    stop(sprintf("refresh_slot_c.R: plot script not found: %s", plot_script), call. = FALSE)
  }
  old_skip <- Sys.getenv("NBA_SKIP_STAGE_AUTORUN", unset = NA)
  old_wd <- getwd()
  on.exit({
    if (is.na(old_skip)) Sys.unsetenv("NBA_SKIP_STAGE_AUTORUN") else Sys.setenv(NBA_SKIP_STAGE_AUTORUN = old_skip)
    setwd(old_wd)
  }, add = TRUE)
  Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")
  env <- new.env(parent = globalenv())
  sys.source(plot_script, envir = env, keep.source = FALSE)
  env
}

.slotc_load_publish_env <- function(project_root = PROJECT_DIR) {
  pub_script <- file.path(project_root, "tools", "publish_web.R")
  if (!file.exists(pub_script)) {
    stop(sprintf("refresh_slot_c.R: publish script not found: %s", pub_script), call. = FALSE)
  }
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  env <- new.env(parent = globalenv())
  sys.source(pub_script, envir = env, keep.source = FALSE)
  env
}

run_slot_c_refresh <- function(target_date = Sys.Date(),
                               pred_log_file = file.path(CACHE_DIR, "prediction_accuracy_log.rds"),
                               cache_dir = CACHE_DIR,
                               web_media_dir = file.path(PROJECT_DIR, "web", "public", "media"),
                               run_gate = FALSE,
                               publish = FALSE,
                               strict_warnings = FALSE,
                               skip_contracts = FALSE,
                               commit_message = NULL,
                               project_root = PROJECT_DIR) {
  target_date <- as.Date(target_date)
  if (is.na(target_date)) {
    stop("refresh_slot_c.R: invalid target_date; expected Date or YYYY-MM-DD.", call. = FALSE)
  }

  plot_env <- .slotc_load_plot_env(project_root)
  plot_res <- plot_env$plot_today_predictions(
    target_date = target_date,
    pred_log_file = pred_log_file,
    cache_dir = cache_dir,
    web_media_dir = web_media_dir
  )

  pub_res <- NULL
  if (isTRUE(run_gate) || isTRUE(publish)) {
    pub_env <- .slotc_load_publish_env(project_root)
    if (is.null(commit_message)) {
      commit_message <- sprintf("chore(media): Slot C daily predictions refresh (%s)",
                                format(target_date, "%Y-%m-%d"))
    }
    pub_res <- pub_env$publish_web(
      dry_run = !isTRUE(publish),
      fail_on_exporter_warnings = isTRUE(strict_warnings),
      skip_contracts = isTRUE(skip_contracts),
      commit_message = commit_message
    )
  }

  invisible(list(
    target_date = target_date,
    plot_result = plot_res,
    publish_result = pub_res
  ))
}

local({
  if (nzchar(Sys.getenv("NBA_SKIP_STAGE_AUTORUN"))) return(invisible(NULL))
  argv <- commandArgs(trailingOnly = FALSE)
  files <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (!any(grepl("refresh_slot_c\\.R$", files))) return(invisible(NULL))

  opts <- commandArgs(trailingOnly = TRUE)
  known_flags <- c("--publish", "--dry-run", "--strict-warnings", "--skip-contracts")
  target_date <- Sys.Date()
  unknown <- character(0)
  for (opt in opts) {
    if (grepl("^--date=", opt)) {
      target_date <- as.Date(sub("^--date=", "", opt))
      if (is.na(target_date)) stop("refresh_slot_c.R: invalid --date value; expected --date=YYYY-MM-DD.", call. = FALSE)
    } else if (!(opt %in% known_flags)) {
      unknown <- c(unknown, opt)
    }
  }
  if (length(unknown)) {
    stop(sprintf(
      "refresh_slot_c.R: unknown CLI option(s): %s. Valid options: %s, --date=YYYY-MM-DD",
      paste(shQuote(unknown), collapse = ", "),
      paste(known_flags, collapse = ", ")
    ), call. = FALSE)
  }

  do_publish <- "--publish" %in% opts
  do_gate <- do_publish || ("--dry-run" %in% opts)
  res <- run_slot_c_refresh(
    target_date = target_date,
    run_gate = do_gate,
    publish = do_publish,
    strict_warnings = "--strict-warnings" %in% opts,
    skip_contracts = "--skip-contracts" %in% opts
  )
  if (!is.null(res$publish_result) && isTRUE(res$publish_result$blocked)) {
    quit(status = 1L)
  }
  quit(status = 0L)
})
