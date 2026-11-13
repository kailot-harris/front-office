# ==============================================================================
# tests/test_chart_viz_authenticity.R
#
# Minimal chart-script test harness for kailot-harris/front-office#142 (MLB
# share), ported from the NBA pilot's tests/test_batch_*_viz.R pattern.
#
# The old failure mode this guards against: a test harness that only checks
# "did a file get produced" never exercises the real-data path on a
# cache-less CI runner, so a chart script's fabricated fallback is the only
# thing ever tested - and it always "passes". This harness instead runs each
# tools/gif_*.R / tools/viz_*.R chart script (the same set the static
# .github/scripts/check-chart-authenticity.R check parses) via system2() and
# classifies the outcome three ways:
#
#   RENDERED (PASS)     - exit status 0 and the expected artifact file(s)
#                          exist with non-zero size.
#   SKIPPED-NO-DATA      - non-zero exit status, and the script's output
#                          contains the VIZ_NO_DATA_MARKER ("[SKIP-NO-DATA]")
#                          defined in tools/viz_common.R - the script refused
#                          to fabricate a chart rather than drawing one from
#                          invented values. Expected on a fresh clone or a
#                          cache-less CI runner.
#   FAILED               - non-zero exit status with no SKIP marker: a real
#                          error (missing package, bug, or a script whose
#                          own fallback message does not yet emit the
#                          marker).
#
# Usage:
#   Rscript tests/test_chart_viz_authenticity.R
#
# This is intentionally kept outside tests/testthat/ (which
# .github/scripts/run-tests.R runs as the gating unit-test suite) because it
# executes real chart scripts rather than asserting unit-level behaviour -
# same placement as the NBA pilot's tests/test_batch_*_viz.R files.
# ==============================================================================

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  if (file.exists(file.path(base, "tools", "viz_common.R"))) {
    normalizePath(base, winslash = "/", mustWork = FALSE)
  } else if (file.exists(file.path(base, "..", "tools", "viz_common.R"))) {
    normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
  } else {
    getwd()
  }
})

cat(sprintf("=== MLB Chart Authenticity Test Harness (Repo root: %s) ===\n", REPO_ROOT))

VIZ_NO_DATA_MARKER <- "[SKIP-NO-DATA]"

# Same file set as .github/scripts/check-chart-authenticity.R: every tracked
# tools/gif_*.R and tools/viz_*.R file, minus pure theme/helper modules with
# no plotted output of their own.
CHART_FILE_EXCLUDE <- c("viz_theme.R", "viz_common.R")

tools_dir <- file.path(REPO_ROOT, "tools")
chart_scripts <- sort(list.files(tools_dir, pattern = "^(gif_|viz_).*\\.R$"))
chart_scripts <- chart_scripts[!chart_scripts %in% CHART_FILE_EXCLUDE]

if (length(chart_scripts) == 0) {
  stop("No chart scripts found under tools/ - is this running from the repo root?")
}

cat(sprintf("\nRunning %d chart script(s) via system2()...\n\n", length(chart_scripts)))

classify_and_run <- function(script_name) {
  script_path <- file.path(tools_dir, script_name)
  res <- system2("Rscript", args = shQuote(script_path), stdout = TRUE, stderr = TRUE)
  status <- attr(res, "status")
  status <- if (is.null(status)) 0L else status

  if (status == 0L) {
    # A chart-producing script writes cache/viz/<basename-without-ext>.(gif|png).
    base_name <- sub("\\.[Rr]$", "", script_name)
    gif_path <- file.path(REPO_ROOT, "cache", "viz", paste0(base_name, ".gif"))
    png_path <- file.path(REPO_ROOT, "cache", "viz", paste0(base_name, ".png"))
    artifact <- if (file.exists(gif_path) && file.info(gif_path)$size > 0) {
      gif_path
    } else if (file.exists(png_path) && file.info(png_path)$size > 0) {
      png_path
    } else {
      NA_character_
    }
    if (is.na(artifact)) {
      return(list(script = script_name, outcome = "FAILED",
                  detail = "exit 0 but no non-zero-size artifact found under cache/viz/"))
    }
    return(list(script = script_name, outcome = "RENDERED",
                detail = sprintf("exit 0, artifact %s (%d bytes)", basename(artifact), file.info(artifact)$size)))
  }

  no_data <- grep(VIZ_NO_DATA_MARKER, res, fixed = TRUE, value = TRUE)
  if (length(no_data) > 0) {
    return(list(script = script_name, outcome = "SKIPPED-NO-DATA",
                detail = sub("^Error:\\s*", "", trimws(no_data[1]))))
  }

  tail_lines <- tail(res[nzchar(res)], 3)
  list(script = script_name, outcome = "FAILED",
       detail = paste(tail_lines, collapse = " | "))
}

results <- lapply(chart_scripts, classify_and_run)

counts <- table(vapply(results, function(r) r$outcome, character(1)))

for (r in results) {
  tag <- switch(r$outcome,
                "RENDERED" = "PASS",
                "SKIPPED-NO-DATA" = "SKIP",
                "FAILED" = "FAIL")
  cat(sprintf("  [%s] %-45s %s\n", tag, r$script, r$detail))
}

cat("\n--- Summary ---\n")
cat(sprintf("  Rendered (PASS):       %d\n", sum(vapply(results, function(r) r$outcome == "RENDERED", logical(1)))))
cat(sprintf("  Skipped (no data):     %d\n", sum(vapply(results, function(r) r$outcome == "SKIPPED-NO-DATA", logical(1)))))
cat(sprintf("  Failed:                %d\n", sum(vapply(results, function(r) r$outcome == "FAILED", logical(1)))))

cat(paste0(
  "\nNote: a script reported FAILED here because its own missing-input guard\n",
  "does not yet call viz_stop_no_data() / emit the ", VIZ_NO_DATA_MARKER, " marker (see\n",
  "tools/viz_common.R) is a candidate for that refactor, not a bug in this harness.\n",
  "This harness never fails the run on SKIPPED-NO-DATA or FAILED outcomes - it is a\n",
  "reporting tool, not a gate; wiring it into CI as a gate is future work.\n"
))
