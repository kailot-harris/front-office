# ==============================================================================
# tests/test_xgboost_stage_output.R
# Offline Regression Test for NFL_analytics#157
#
# Verifies:
#   1. run_full_pipeline.R declares `output = CACHE_XGBOOST_SHAP` (excluding
#      CACHE_XGBOOST_MODEL) for the xgboost_shap_engine.R stage, with an inline
#      comment explaining CACHE_XGBOOST_MODEL is reused by design unless
#      force_retrain = TRUE.
#   2. In an isolated temp sandbox, `.check_stage_output()` emits `[FRESH]` and
#      zero `silent no-op` warnings when CACHE_XGBOOST_SHAP is newly written
#      while CACHE_XGBOOST_MODEL keeps an old mtime.
#   3. `.check_stage_output()` still emits `[WARN]` (finding C-2) when
#      CACHE_XGBOOST_SHAP itself is stale (or missing).
#
# Note: run_full_pipeline.R executes stages at top level on source() without a
# guard, so following tests/test_pure_functions.R and tests/test_clutch_dataset.R
# this suite extracts functions and inspects the stage declaration via parse()
# (`load_ast_symbols`) without sourcing run_full_pipeline.R.
#
# Runs via:
#   Rscript --vanilla tests/test_xgboost_stage_output.R
# ==============================================================================

root_dir <- if (file.exists("config.R")) {
  normalizePath(getwd(), winslash = "/", mustWork = FALSE)
} else if (file.exists("../config.R")) {
  normalizePath("..", winslash = "/", mustWork = FALSE)
} else {
  normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}

source(file.path(root_dir, "config.R"))

failures <- 0L
ok <- function(label, cond, detail = NULL) {
  if (isTRUE(cond)) {
    cat(sprintf("[PASS] %s%s\n", label, if (!is.null(detail)) paste0("  -- ", detail) else ""))
  } else {
    cat(sprintf("[FAIL] %s%s\n", label, if (!is.null(detail)) paste0("  -- ", detail) else ""))
    failures <<- failures + 1L
  }
}

# AST helper (same pattern as tests/test_pure_functions.R and tests/test_clutch_dataset.R):
# evaluate selected top-level assignments without executing top-level pipeline calls.
load_ast_symbols <- function(path, symbols, env) {
  exprs <- parse(file = path, keep.source = FALSE)
  for (e in exprs) {
    if (is.call(e) && length(e) >= 3L &&
        as.character(e[[1L]]) %in% c("<-", "=") &&
        is.symbol(e[[2L]]) &&
        as.character(e[[2L]]) %in% symbols) {
      eval(e, envir = env)
    }
  }
  env
}

cat("=== NFL Analytics XGBoost Stage Output C-2 Regression Tests (#157) ===\n\n")

pipeline_path <- file.path(root_dir, "run_full_pipeline.R")
pipeline_exprs <- parse(file = pipeline_path, keep.source = FALSE)
pipeline_lines <- readLines(pipeline_path, warn = FALSE)

stage_env <- new.env(parent = globalenv())
stage_env$warn_calls <- list()
stage_env$log_warn <- function(msg, script = NULL, ...) {
  stage_env$warn_calls[[length(stage_env$warn_calls) + 1L]] <- c(
    list(msg = msg, script = script),
    list(...)
  )
  invisible(NULL)
}
invisible(load_ast_symbols(pipeline_path, c(".check_stage_output", "run_stage"), stage_env))

ok("XSO-1 `.check_stage_output()` and `run_stage()` loaded safely from AST",
   is.function(stage_env$.check_stage_output) && is.function(stage_env$run_stage),
   "Extracted without executing run_full_pipeline.R")

# ------------------------------------------------------------------------------
# Test 1: Inspect run_stage("xgboost_shap_engine.R", ...) declaration & comment
# ------------------------------------------------------------------------------
xgb_calls <- list()
for (e in pipeline_exprs) {
  if (is.call(e) && identical(as.character(e[[1L]]), "run_stage")) {
    mc <- match.call(stage_env$run_stage, e)
    if (identical(mc$script_name, "xgboost_shap_engine.R")) {
      xgb_calls[[length(xgb_calls) + 1L]] <- mc
    }
  }
}

ok("XSO-2 Exactly one run_stage(\"xgboost_shap_engine.R\", ...) call declared",
   length(xgb_calls) == 1L &&
     identical(xgb_calls[[1L]]$call_fn, "run_xgboost_shap_engine"),
   sprintf("calls=%d", length(xgb_calls)))

output_expr <- if (length(xgb_calls) == 1L) xgb_calls[[1L]]$output else NULL
output_src <- if (!is.null(output_expr)) paste(deparse(output_expr), collapse = " ") else ""
ok("XSO-3 Stage output declares CACHE_XGBOOST_SHAP and excludes CACHE_XGBOOST_MODEL",
   identical(output_expr, as.symbol("CACHE_XGBOOST_SHAP")) &&
     !grepl("CACHE_XGBOOST_MODEL", output_src, fixed = TRUE),
   sprintf("output=%s", output_src))

stage_line_idx <- grep('run_stage\\("xgboost_shap_engine\\.R"', pipeline_lines)
nearby_lines <- if (length(stage_line_idx) == 1L) {
  lo <- max(1L, stage_line_idx - 6L)
  hi <- min(length(pipeline_lines), stage_line_idx + 4L)
  paste(pipeline_lines[lo:hi], collapse = "\n")
} else {
  ""
}
ok("XSO-4 Inline/adjacent comment documents CACHE_XGBOOST_MODEL reuse unless force_retrain = TRUE (#157)",
   grepl("CACHE_XGBOOST_MODEL", nearby_lines, fixed = TRUE) &&
     grepl("force_retrain\\s*=\\s*TRUE", nearby_lines) &&
     grepl("157", nearby_lines, fixed = TRUE),
   sprintf("checked lines around line %s", paste(stage_line_idx, collapse = ",")))

# ------------------------------------------------------------------------------
# Test 2: Isolated temp sandbox verification of .check_stage_output()
# ------------------------------------------------------------------------------
sandbox_dir <- tempfile("xgb_stage_output_")
dir.create(sandbox_dir, recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(sandbox_dir, recursive = TRUE), add = TRUE)

sandbox_model <- file.path(sandbox_dir, basename(CACHE_XGBOOST_MODEL))
sandbox_shap  <- file.path(sandbox_dir, basename(CACHE_XGBOOST_SHAP))

cfg_env <- new.env(parent = baseenv())
cfg_env$CACHE_XGBOOST_MODEL <- sandbox_model
cfg_env$CACHE_XGBOOST_SHAP  <- sandbox_shap
declared_output <- eval(output_expr, envir = cfg_env)

ok("XSO-5 Evaluated output expression resolves solely to sandbox CACHE_XGBOOST_SHAP",
   identical(declared_output, sandbox_shap) && length(declared_output) == 1L,
   declared_output)

capture_check <- function(output_paths, start_time) {
  stage_env$warn_calls <- list()
  msgs <- character(0)
  withCallingHandlers(
    stage_env$.check_stage_output(
      "xgboost_shap_engine.R",
      "Extract Secondary Model TreeSHAP Feature Attributions",
      output_paths,
      start_time
    ),
    message = function(m) {
      msgs <<- c(msgs, sub("\n$", "", conditionMessage(m)))
      invokeRestart("muffleMessage")
    }
  )
  list(msgs = msgs, warns = stage_env$warn_calls)
}

now <- Sys.time()
stage_start <- now - 5

# Seed model with an old mtime (48 hours ago) and SHAP with a fresh mtime (now)
saveRDS(list(stub = "reused_model"), sandbox_model)
saveRDS(list(stub = "fresh_shap"), sandbox_shap)
Sys.setFileTime(sandbox_model, now - 48 * 3600)
Sys.setFileTime(sandbox_shap, now)

model_mtime <- file.info(sandbox_model)$mtime
shap_mtime  <- file.info(sandbox_shap)$mtime
ok("XSO-6 Sandbox precondition: model mtime is >24h before stage_start and SHAP mtime is >= stage_start",
   as.numeric(difftime(model_mtime, stage_start, units = "secs")) < -24 * 3600 &&
     as.numeric(difftime(shap_mtime, stage_start, units = "secs")) >= 0,
   sprintf("model_diff=%.0fs, shap_diff=%.1fs",
           as.numeric(difftime(model_mtime, stage_start, units = "secs")),
           as.numeric(difftime(shap_mtime, stage_start, units = "secs"))))

# Normal scheduled run: reused model (old mtime) + newly written SHAP (fresh mtime)
res_fresh <- capture_check(declared_output, stage_start)
all_warn_text_fresh <- paste(vapply(res_fresh$warns, function(w) w$msg, character(1)), collapse = "\n")
ok("XSO-7 Reused old model + fresh SHAP emits [FRESH] and zero silent no-op warnings",
   length(res_fresh$msgs) == 1L &&
     grepl(">>> \\[FRESH\\] xgboost_shap_engine\\.R", res_fresh$msgs[1]) &&
     grepl(basename(sandbox_shap), res_fresh$msgs[1], fixed = TRUE) &&
     !any(grepl("\\[WARN\\]", res_fresh$msgs)) &&
     !any(grepl("silent no-op", res_fresh$msgs, ignore.case = TRUE)) &&
     length(res_fresh$warns) == 0L &&
     !grepl("silent no-op", all_warn_text_fresh, ignore.case = TRUE),
   res_fresh$msgs[1])

# Negative control: old declaration c(model, shap) would have falsely triggered C-2 on old model
res_pre_fix <- capture_check(c(sandbox_model, sandbox_shap), stage_start)
ok("XSO-8 Negative control: including old model in output reproduces the #157 C-2 false warning",
   any(grepl("\\[WARN\\]", res_pre_fix$msgs) & grepl("finding C-2", res_pre_fix$msgs, fixed = TRUE) &
         grepl(basename(sandbox_model), res_pre_fix$msgs, fixed = TRUE)) &&
     length(res_pre_fix$warns) == 1L &&
     identical(res_pre_fix$warns[[1]]$output, sandbox_model),
   sprintf("pre-fix warn count=%d", length(res_pre_fix$warns)))

# Stale SHAP case: CACHE_XGBOOST_SHAP itself has old mtime -> finding C-2 still triggers
Sys.setFileTime(sandbox_shap, now - 2 * 3600)
res_stale <- capture_check(declared_output, stage_start)
ok("XSO-9 Stale CACHE_XGBOOST_SHAP still triggers [WARN] (finding C-2) and log_warn()",
   length(res_stale$msgs) == 1L &&
     grepl(">>> \\[WARN\\] xgboost_shap_engine\\.R", res_stale$msgs[1]) &&
     grepl("Possible silent no-op", res_stale$msgs[1], fixed = TRUE) &&
     grepl("finding C-2", res_stale$msgs[1], fixed = TRUE) &&
     !any(grepl("\\[FRESH\\]", res_stale$msgs)) &&
     length(res_stale$warns) == 1L &&
     grepl("C-2", res_stale$warns[[1]]$msg, fixed = TRUE) &&
     identical(res_stale$warns[[1]]$output, sandbox_shap),
   res_stale$msgs[1])

# Missing SHAP case: CACHE_XGBOOST_SHAP missing -> [WARN] missing output still triggers
unlink(sandbox_shap)
res_missing <- capture_check(declared_output, stage_start)
ok("XSO-10 Missing CACHE_XGBOOST_SHAP emits missing-output [WARN] and log_warn()",
   length(res_missing$msgs) == 1L &&
     grepl(">>> \\[WARN\\] xgboost_shap_engine\\.R: declared output", res_missing$msgs[1]) &&
     grepl("does not exist", res_missing$msgs[1], fixed = TRUE) &&
     length(res_missing$warns) == 1L &&
     grepl("missing", res_missing$warns[[1]]$msg, ignore.case = TRUE),
   res_missing$msgs[1])

cat(sprintf("\n=== XGBoost Stage Output Tests Summary: %d failure(s) ===\n", failures))
quit(status = if (failures == 0L) 0L else 1L)
