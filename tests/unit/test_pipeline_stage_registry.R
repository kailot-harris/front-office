# ==============================================================================
# test_pipeline_stage_registry.R
# Invariant tests for run_full_pipeline.R <-> pipeline_stages.R (Issue #209)
#
# Verifies statically (without executing the live pipeline) that every
# `run_registered_stage("...")` and `get_pipeline_stage_group("...")` call in
# `run_full_pipeline.R` resolves to an active entry in `pipeline_stages.R`,
# archived stages are absent from `run_full_pipeline.R`, and unknown stage IDs
# fail both the registry lookup and the static coverage check.
# ==============================================================================

# ------------------------------------------------------------------------------
# Root-resolution prelude (Issue #90 Working Directory Trap)
# ------------------------------------------------------------------------------
args_all <- commandArgs(trailingOnly = FALSE)
f <- sub("^--file=", "", args_all[grepl("^--file=", args_all)])
if (length(f) == 1 && nzchar(f) && file.exists(f)) {
  cand <- normalizePath(dirname(dirname(dirname(f))), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(cand, "config.R"))) setwd(cand)
}
cur <- getwd()
while (!file.exists(file.path(cur, "config.R")) && dirname(cur) != cur) {
  cur <- dirname(cur)
}
if (file.exists(file.path(cur, "config.R"))) setwd(cur)

# Ensure user library is accessible even when running inside an isolated renv sandbox
user_lib <- Sys.getenv("R_LIBS_USER")
if (nzchar(user_lib) && dir.exists(user_lib) && !(user_lib %in% .libPaths())) {
  .libPaths(c(.libPaths(), user_lib))
} else {
  default_user_lib <- file.path(
    Sys.getenv("LOCALAPPDATA", file.path(Sys.getenv("USERPROFILE"), "AppData", "Local")),
    "R", "win-library", "4.5"
  )
  if (dir.exists(default_user_lib) && !(default_user_lib %in% .libPaths())) {
    .libPaths(c(.libPaths(), default_user_lib))
  }
}

suppressPackageStartupMessages({
  library(testthat)
})

source("config.R")
source("pipeline_stages.R")

# ------------------------------------------------------------------------------
# AST helpers for static stage-registry verification
# ------------------------------------------------------------------------------

extract_call_string_args <- function(pipeline_path, fn_name, arg_name) {
  exprs <- parse(pipeline_path, keep.source = FALSE)
  values <- character(0)
  invalid <- character(0)
  proto <- eval(parse(text = sprintf("function(%s) NULL", arg_name))[[1]])

  walk <- function(node) {
    if (is.call(node)) {
      head <- node[[1]]
      if (is.symbol(head) && identical(as.character(head), fn_name)) {
        matched <- tryCatch(match.call(proto, node), error = function(e) NULL)
        arg_val <- if (!is.null(matched)) matched[[arg_name]] else NULL
        if (is.character(arg_val) && length(arg_val) == 1L && nzchar(trimws(arg_val))) {
          values <<- c(values, arg_val)
        } else {
          invalid <<- c(invalid, paste(deparse(node), collapse = " "))
        }
      }
      for (i in seq_along(node)) walk(node[[i]])
    } else if (is.pairlist(node) || is.expression(node)) {
      for (i in seq_along(node)) walk(node[[i]])
    }
  }

  walk(exprs)
  list(values = values, invalid = invalid)
}

check_pipeline_stage_registry <- function(pipeline_path = "run_full_pipeline.R",
                                          registry = PIPELINE_STAGES,
                                          check_scripts = TRUE) {
  stage_calls <- extract_call_string_args(pipeline_path, "run_registered_stage", "id")
  group_calls <- extract_call_string_args(pipeline_path, "get_pipeline_stage_group", "group_name")

  stage_ids <- stage_calls$values
  group_names <- group_calls$values
  missing_stages <- setdiff(stage_ids, names(registry))

  missing_groups <- character(0)
  for (g in unique(group_names)) {
    members <- Filter(function(s) identical(s$group, g), registry)
    if (length(members) == 0L) missing_groups <- c(missing_groups, g)
  }

  missing_scripts <- character(0)
  mismatched_ids <- character(0)
  for (id in intersect(stage_ids, names(registry))) {
    entry <- registry[[id]]
    if (!identical(entry$id, id)) mismatched_ids <- c(mismatched_ids, id)
    if (isTRUE(check_scripts) && (is.null(entry$script) || !file.exists(entry$script))) {
      missing_scripts <- c(missing_scripts, paste0(id, "->", as.character(entry$script %||% "")))
    }
  }

  ok <- length(stage_calls$invalid) == 0L &&
    length(group_calls$invalid) == 0L &&
    length(missing_stages) == 0L &&
    length(missing_groups) == 0L &&
    length(missing_scripts) == 0L &&
    length(mismatched_ids) == 0L

  list(
    ok = ok,
    stage_ids = stage_ids,
    invalid_stage_calls = stage_calls$invalid,
    group_names = group_names,
    invalid_group_calls = group_calls$invalid,
    missing_stages = missing_stages,
    missing_groups = missing_groups,
    missing_scripts = missing_scripts,
    mismatched_ids = mismatched_ids
  )
}

assert_pipeline_stage_registry <- function(pipeline_path = "run_full_pipeline.R",
                                           registry = PIPELINE_STAGES,
                                           check_scripts = TRUE) {
  res <- check_pipeline_stage_registry(
    pipeline_path = pipeline_path,
    registry = registry,
    check_scripts = check_scripts
  )
  if (!isTRUE(res$ok)) {
    stop(sprintf(
      "Stage registry invariant failed for %s: missing_stages=[%s] missing_groups=[%s] missing_scripts=[%s]",
      pipeline_path,
      paste(res$missing_stages, collapse = ", "),
      paste(res$missing_groups, collapse = ", "),
      paste(res$missing_scripts, collapse = ", ")
    ))
  }
  invisible(res)
}

# ------------------------------------------------------------------------------
# Tests
# ------------------------------------------------------------------------------

test_that("run_full_pipeline.R parses cleanly and drops archived stages (#209)", {
  expect_no_error(parse("run_full_pipeline.R"))
  stage_calls <- extract_call_string_args("run_full_pipeline.R", "run_registered_stage", "id")

  expect_gt(length(stage_calls$values), 0L)
  expect_equal(length(stage_calls$invalid), 0L)
  expect_false("offseason_dataset" %in% stage_calls$values)
  expect_false("cba_cap_dataset" %in% stage_calls$values)
})

test_that("Every run_registered_stage() and group call in run_full_pipeline.R exists in pipeline_stages.R", {
  res <- check_pipeline_stage_registry("run_full_pipeline.R", PIPELINE_STAGES, check_scripts = TRUE)

  expect_true(res$ok, info = paste(
    "missing_stages:", paste(res$missing_stages, collapse = ", "),
    "missing_groups:", paste(res$missing_groups, collapse = ", "),
    "missing_scripts:", paste(res$missing_scripts, collapse = ", ")
  ))
  expect_equal(res$missing_stages, character(0))
  expect_equal(res$missing_groups, character(0))
  expect_equal(res$missing_scripts, character(0))
  expect_equal(res$mismatched_ids, character(0))

  # Verify runtime accessor succeeds for every referenced ID and group
  for (id in res$stage_ids) {
    st <- get_pipeline_stage(id)
    expect_identical(st$id, id)
  }
  for (g in res$group_names) {
    grp <- get_pipeline_stage_group(g)
    expect_gt(length(grp), 0L)
  }

  expect_no_error(assert_pipeline_stage_registry("run_full_pipeline.R"))
})

test_that("Unknown or archived stage IDs fail get_pipeline_stage() and the invariant check", {
  expect_error(get_pipeline_stage("unknown_stage_id"), "unknown stage id")
  expect_error(get_pipeline_stage("offseason_dataset"), "unknown stage id")
  expect_error(get_pipeline_stage("cba_cap_dataset"), "unknown stage id")
  expect_error(get_pipeline_stage_group("unknown_group"), "no stages found")

  tmp_pipeline <- tempfile(fileext = ".R")
  on.exit(unlink(tmp_pipeline), add = TRUE)
  writeLines(c(
    'run_registered_stage("data_health_probe")',
    'run_registered_stage("unknown_stage_id")',
    'run_registered_stage("offseason_dataset")',
    'run_registered_stage("cba_cap_dataset")'
  ), tmp_pipeline)

  res <- check_pipeline_stage_registry(tmp_pipeline, PIPELINE_STAGES, check_scripts = FALSE)
  expect_false(res$ok)
  expect_setequal(res$missing_stages, c("unknown_stage_id", "offseason_dataset", "cba_cap_dataset"))
  expect_error(
    assert_pipeline_stage_registry(tmp_pipeline, PIPELINE_STAGES, check_scripts = FALSE),
    "unknown_stage_id"
  )
})
