# ==============================================================================
# NBA Analytics - publish the momentum measures study for the web
# Path: <repo root>/tools/publish_momentum_methodology.R
#
# Copies the momentum measures study's results file into
# web/public/data/momentum_methodology.json (config.R:
# WEB_JSON_MOMENTUM_METHODOLOGY), the data behind the /momentum/methodology
# page. It COPIES and CHECKS only:
#   * no random numbers, no hard-coded metric values, no hand-entered numbers;
#   * every figure in the output is the study's own, byte for byte: the output
#     is the input text with three provenance keys spliced in after the opening
#     brace (source_commit, source_sha256, published_at);
#   * the script re-parses its output and refuses to write unless the result,
#     minus those three keys, is identical to the parsed input.
#
# Frozen study artifact: NOT a run_full_pipeline.R stage and not in
# WEB_DATA_FILES. Run it again only when the study itself is re-run.
#
# Usage:
#   Rscript tools/publish_momentum_methodology.R <study_results.json> <source_commit>
#
#   <study_results.json>  the study's docs/research/momentum_measures_study_results.json
#   <source_commit>       the 40-character commit the file was taken from. When git
#                         can read that commit, the input must match the file stored
#                         there byte for byte, or nothing is written.
#
# Exit status: 0 written; 1 any check failed (nothing written).
# ==============================================================================

suppressPackageStartupMessages(library(jsonlite))

MM_STUDY_REPO_PATH <- "docs/research/momentum_measures_study_results.json"
MM_PROVENANCE_KEYS <- c("source_commit", "source_sha256", "published_at")

# Keys the page reads. Each entry: a path into the parsed study, as a character
# vector of names. Validation fails on the first missing one.
MM_REQUIRED_PATHS <- list(
  c("study", "title"), c("study", "run_date"), c("study", "seasons"), c("study", "holdout"),
  c("study", "protocol"), c("study", "runtime_minutes"), c("study", "permutation_minutes"),
  c("targets"), c("measures"), c("series"),
  c("single_feature_results"), c("single_feature_sensitivity_primary"),
  c("families", "measure_families"), c("families", "series_families"),
  c("families", "measure_mean_abs_r"), c("families", "series_mean_abs_r"),
  c("families", "feature_clusters_abs_r_0_7"),
  c("combination_search", "target"), c("combination_search", "folds"),
  c("combination_search", "pooled_r2_gain"), c("combination_search", "pooled_ci_95"),
  c("combination_search", "comparisons"), c("combination_search", "selection_stability"),
  c("combination_search", "permutation"), c("combination_search", "final_choice"),
  c("combination_search", "reliability_checks"), c("combination_search", "final_verdict"),
  c("combination_search", "sensitivity_without_2019_20_2020_21"),
  c("blend_weights"), c("holdout", "note"), c("holdout", "part_a"), c("holdout", "part_b"),
  c("limits")
)
MM_RESULT_FIELDS <- c("feature", "series", "measure", "target", "incremental_ic", "ic_metric",
                      "r2_gain", "gain_metric", "ci_95", "fdr_q_value", "p_value", "n",
                      "missing_count", "verdict", "reason")
MM_VERDICTS <- c("kept", "discarded", "inconclusive")
MM_MEASURE_FIELDS <- c("id", "name", "field_of_origin", "forward_only_definition")
MM_BLEND_FIELDS <- c("window", "target", "rows", "current_weights", "current_r2_gain",
                     "best_weights", "best_r2_gain", "best_vs_current", "flatness",
                     "loso_selected", "nonnegative_regression", "recommendation")

mm_fail <- function(...) stop(sprintf(...), call. = FALSE)

mm_get <- function(x, path) {
  for (k in path) {
    if (!is.list(x) || is.null(names(x)) || !k %in% names(x)) return(NULL)
    x <- x[[k]]
  }
  x
}

mm_is_ci <- function(v) {
  is.list(v) && length(v) == 2L && all(vapply(v, function(e) is.numeric(e) && length(e) == 1L && is.finite(e), logical(1))) &&
    v[[1]] <= v[[2]]
}

# Structural checks only: presence, types, and internal consistency of counts
# the file itself declares. No expected value is typed here.
mm_validate_study <- function(j) {
  if (!is.list(j) || is.null(names(j))) mm_fail("study JSON is not an object")
  clash <- intersect(MM_PROVENANCE_KEYS, names(j))
  if (length(clash)) mm_fail("study JSON already carries provenance key(s): %s", paste(clash, collapse = ", "))
  for (p in MM_REQUIRED_PATHS) {
    if (is.null(mm_get(j, p))) mm_fail("study JSON is missing required key: %s", paste(p, collapse = "."))
  }

  ids <- function(xs) vapply(xs, function(e) as.character(e$id), character(1))
  measure_ids <- ids(j$measures)
  series_ids <- ids(j$series)
  target_ids <- ids(j$targets)
  for (m in j$measures) {
    miss <- setdiff(MM_MEASURE_FIELDS, names(m))
    if (length(miss)) mm_fail("measure %s lacks: %s", m$id %||% "?", paste(miss, collapse = ", "))
  }
  primaries <- vapply(j$targets, function(t) isTRUE(t$primary), logical(1))
  if (sum(primaries) != 1L) mm_fail("expected exactly one primary target, found %d", sum(primaries))

  rows <- j$single_feature_results
  expected_rows <- length(measure_ids) * length(series_ids) * length(target_ids)
  if (length(rows) != expected_rows) {
    mm_fail("single_feature_results has %d rows; measures x series x targets gives %d",
            length(rows), expected_rows)
  }
  seen <- character(length(rows))
  for (i in seq_along(rows)) {
    r <- rows[[i]]
    miss <- setdiff(MM_RESULT_FIELDS, names(r))
    if (length(miss)) mm_fail("single_feature_results[%d] lacks: %s", i, paste(miss, collapse = ", "))
    if (!r$verdict %in% MM_VERDICTS) mm_fail("single_feature_results[%d] has unknown verdict '%s'", i, r$verdict)
    if (!nzchar(r$reason)) mm_fail("single_feature_results[%d] has an empty reason", i)
    if (!mm_is_ci(r$ci_95)) mm_fail("single_feature_results[%d] has no valid 95%% interval", i)
    if (!r$series %in% series_ids || !r$measure %in% measure_ids || !r$target %in% target_ids) {
      mm_fail("single_feature_results[%d] names an unknown series, measure or target", i)
    }
    seen[i] <- paste(r$series, r$measure, r$target, sep = "|")
  }
  if (anyDuplicated(seen)) mm_fail("single_feature_results repeats a series x measure x target row")

  for (k in c("measure_mean_abs_r", "series_mean_abs_r")) {
    mat <- j$families[[k]]
    want <- if (k == "measure_mean_abs_r") measure_ids else series_ids
    if (!identical(names(mat), want)) mm_fail("families.%s rows are not in %s order", k, sub("_mean_abs_r", "", k))
    bad <- vapply(mat, function(row) length(row) != length(want), logical(1))
    if (any(bad)) mm_fail("families.%s is not square", k)
  }

  for (b in j$blend_weights) {
    miss <- setdiff(MM_BLEND_FIELDS, names(b))
    if (length(miss)) mm_fail("blend_weights window %s lacks: %s", b$window %||% "?", paste(miss, collapse = ", "))
  }
  if (!mm_is_ci(j$combination_search$pooled_ci_95)) mm_fail("combination_search.pooled_ci_95 is not a valid interval")
  if (!is.character(j$limits) && !is.list(j$limits)) mm_fail("limits is not a list")
  invisible(TRUE)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

mm_read_text <- function(path) {
  sz <- file.info(path)$size
  if (is.na(sz) || sz == 0) mm_fail("input %s is empty or missing", path)
  txt <- rawToChar(readBin(path, "raw", n = sz))
  Encoding(txt) <- "UTF-8"
  txt
}

# When git knows the commit, the input must equal the file stored there.
mm_check_commit <- function(input_path, commit) {
  if (!grepl("^[0-9a-f]{40}$", commit)) mm_fail("source_commit must be a full 40-character hex sha, got '%s'", commit)
  git <- Sys.which("git")
  if (!nzchar(git)) {
    message("[WARN] git not found; source_commit recorded without a byte check")
    return(invisible("unchecked"))
  }
  tmp <- tempfile(fileext = ".json")
  on.exit(unlink(tmp), add = TRUE)
  status <- suppressWarnings(system2(git, c("show", paste0(commit, ":", MM_STUDY_REPO_PATH)),
                                     stdout = tmp, stderr = FALSE))
  if (!identical(as.integer(status), 0L) || !file.exists(tmp) || file.info(tmp)$size == 0) {
    message(sprintf("[WARN] git cannot read %s at %s here; source_commit recorded without a byte check",
                    MM_STUDY_REPO_PATH, commit))
    return(invisible("unchecked"))
  }
  a <- unname(as.character(tools::sha256sum(input_path)))
  b <- unname(as.character(tools::sha256sum(tmp)))
  if (!identical(a, b)) mm_fail("input does not match %s at commit %s (sha256 %s vs %s)", MM_STUDY_REPO_PATH, commit, a, b)
  invisible("matched")
}

mm_build_output <- function(txt, commit, sha, published_at) {
  open_at <- regexpr("^\\s*\\{", txt)
  if (open_at < 0) mm_fail("study JSON text does not start with an object")
  brace <- open_at + attr(open_at, "match.length") - 1L
  prov <- sprintf('\n  "source_commit": %s,\n  "source_sha256": %s,\n  "published_at": %s,',
                  jsonlite::toJSON(commit, auto_unbox = TRUE),
                  jsonlite::toJSON(sha, auto_unbox = TRUE),
                  jsonlite::toJSON(published_at, auto_unbox = TRUE))
  paste0(substr(txt, 1L, brace), prov, substr(txt, brace + 1L, nchar(txt)))
}

publish_momentum_methodology <- function(input_path, commit, out_path = WEB_JSON_MOMENTUM_METHODOLOGY,
                                         now = Sys.time()) {
  if (!file.exists(input_path)) mm_fail("input %s does not exist", input_path)
  txt <- mm_read_text(input_path)
  study <- tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE),
                    error = function(e) mm_fail("input is not valid JSON: %s", conditionMessage(e)))
  mm_validate_study(study)
  check <- mm_check_commit(input_path, commit)

  sha <- unname(as.character(tools::sha256sum(input_path)))
  published_at <- format(as.POSIXct(now), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  out_txt <- mm_build_output(txt, commit, sha, published_at)

  back <- jsonlite::fromJSON(out_txt, simplifyVector = FALSE)
  if (!identical(back$source_commit, commit) || !identical(back$source_sha256, sha) ||
      !identical(back$published_at, published_at)) mm_fail("provenance did not round-trip")
  back[MM_PROVENANCE_KEYS] <- NULL
  if (!identical(back, study)) mm_fail("output minus provenance differs from the study JSON; nothing written")

  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
  tmp_out <- paste0(out_path, ".tmp")
  con <- file(tmp_out, open = "wb")
  writeBin(charToRaw(enc2utf8(out_txt)), con)
  close(con)
  if (!file.rename(tmp_out, out_path)) mm_fail("could not move %s into place", tmp_out)
  message(sprintf(">>> publish_momentum_methodology: wrote %s (%d result rows, commit %s, byte check %s)",
                  out_path, length(study$single_feature_results), commit, check))
  invisible(out_path)
}

local({
  argv <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (!any(grepl("publish_momentum_methodology\\.R$", f))) return(invisible(NULL))
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) != 2L) {
    message("usage: Rscript tools/publish_momentum_methodology.R <study_results.json> <source_commit>")
    quit(status = 1L, save = "no")
  }
  input <- normalizePath(args[[1]], winslash = "/", mustWork = FALSE)
  root <- normalizePath(dirname(dirname(f[1])), winslash = "/", mustWork = FALSE)
  setwd(root)
  source("config.R")
  ok <- tryCatch({
    publish_momentum_methodology(input, tolower(args[[2]]))
    TRUE
  }, error = function(e) {
    message(sprintf("[FAIL] publish_momentum_methodology: %s", conditionMessage(e)))
    FALSE
  })
  quit(status = if (ok) 0L else 1L, save = "no")
})
