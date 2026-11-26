# ==============================================================================
# tests/test_momentum_methodology.R - /momentum/methodology data (NFL_analytics#226)
# Offline, base R plus jsonlite. Writes only to temp files.
#   1. config: WEB_JSON_MOMENTUM_METHODOLOGY under WEB_DATA_DIR, NOT a WEB_DATA_FILES member
#   2. manifest: the file is registered static, with a reason
#   3. NBA-style comparison weights: parsed from tools/rolling_window_study.R, equal
#      to the published file, provenance recorded; a broken script stops the parse
#   4. published file: every extract equals the study results file; source sha256s
#   5. rebuild: re-running the publisher gives the committed bytes (needs git and
#      the study commits; [SKIP] in a shallow clone)
# Run: Rscript tests/test_momentum_methodology.R
# ==============================================================================
failures <- 0L
ok <- function(label, cond) {
  if (isTRUE(cond)) cat(sprintf("[PASS] %s\n", label))
  else { cat(sprintf("[FAIL] %s\n", label)); failures <<- failures + 1L }
}
root_dir <- if (file.exists("config.R")) getwd() else normalizePath("..", winslash = "/")
setwd(root_dir)
suppressPackageStartupMessages(library(jsonlite))
source("config.R")
source("tools/publish_momentum_methodology.R")
Sys.setenv(NFL_SKIP_MANIFEST_AUTORUN = "1")
source("tools/write_data_manifest.R")

norm <- function(p) normalizePath(p, winslash = "/", mustWork = FALSE)

# ---- 1. config ------------------------------------------------------------------
mm_path <- WEB_JSON_MOMENTUM_METHODOLOGY
ok("MM-01 WEB_JSON_MOMENTUM_METHODOLOGY is momentum_methodology.json under WEB_DATA_DIR",
   is.character(mm_path) && length(mm_path) == 1L &&
     identical(basename(mm_path), "momentum_methodology.json") &&
     identical(norm(dirname(mm_path)), norm(WEB_DATA_DIR)))
ok("MM-02 WEB_JSON_MOMENTUM_METHODOLOGY stays out of WEB_DATA_FILES (static, not rewritten nightly)",
   !(mm_path %in% WEB_DATA_FILES) && !(norm(mm_path) %in% norm(WEB_DATA_FILES)))
ok("MM-03 the publisher is not a run_full_pipeline.R stage",
   !any(grepl("publish_momentum_methodology", readLines("run_full_pipeline.R", warn = FALSE), fixed = TRUE)))

# ---- 2. manifest ---------------------------------------------------------------------
spec <- DATA_MANIFEST_SPECS[["momentum_methodology.json"]]
ok("MM-04 manifest spec marks momentum_methodology.json static with a reason",
   !is.null(spec) && isTRUE(spec$static) && is.character(spec$static_reason) && nzchar(spec$static_reason) &&
     identical(spec$builder, "tools/publish_momentum_methodology.R"))
man <- jsonlite::fromJSON(file.path(WEB_DATA_DIR, "data_manifest.json"), simplifyVector = FALSE)
e <- man$datasets[["momentum_methodology.json"]]
ok("MM-05 data_manifest.json lists it static, with no max_lag_days",
   !is.null(e) && isTRUE(e$static) && nzchar(e$static_reason %||% "") && is.null(e$max_lag_days))
ok("MM-06 manifest content_sha256 matches the file on disk",
   !is.null(e) && identical(e$content_sha256, dm_sha256(mm_path)))
tmpd <- tempfile("mm_manifest_"); dir.create(tmpd)
writeLines('{"schema_version":1}', file.path(tmpd, "momentum_methodology.json"))
bm <- build_data_manifest(data_dir = tmpd, schedule_through_date = NA_character_, previous = NULL)
ok("MM-07 build_data_manifest() marks a fresh momentum_methodology.json static",
   isTRUE(bm$datasets[["momentum_methodology.json"]]$static))

# ---- 3. comparison weights ----------------------------------------------------------------
script_lines <- sub("\r$", "", readLines(MMP_STUDY_SCRIPT, warn = FALSE))
cw <- mmp_parse_comparison_weights(script_lines)
ok("MM-08 NBA_W in tools/rolling_window_study.R parses to form 0.7, trend 0.1, residual 0.1, Elo change 0.1",
   isTRUE(all.equal(unlist(cw$weights), c(form = 0.7, trend = 0.1, residual = 0.1, elo_change = 0.1))) &&
     identical(cw$derived, "elo_change"))
ok("MM-09 the parsed weights sum to 1 (the script's grid rule)", abs(sum(unlist(cw$weights)) - 1) < 1e-12)

pub <- jsonlite::fromJSON(mm_path, simplifyVector = FALSE)
pw <- pub$sources$rolling_window$nba_comparison_weights
ok("MM-10 published comparison weights equal the script's NBA_W line",
   !is.null(pw) && identical(unlist(pw[c("form", "trend", "residual", "elo_change")]), unlist(cw$weights)))
ok("MM-11 provenance names the script, the study commit and the NBA_W line",
   identical(pw$provenance$file, "tools/rolling_window_study.R") &&
     identical(pw$provenance$commit, MOMENTUM_BOARD_STUDY_COMMIT) &&
     identical(as.integer(pw$provenance$line), cw$nba_w_line_number) &&
     identical(pw$provenance$line_text, script_lines[cw$nba_w_line_number]) &&
     identical(pw$provenance$grid_line_text, script_lines[cw$grid_line_number]) &&
     grepl("^[0-9a-f]{40}$", pw$provenance$blob_sha1))

broken <- script_lines
broken[cw$nba_w_line_number] <- "NBA_W <- 1L"
ok("MM-12 a script without a parseable NBA_W line stops the parse (no typed-in fallback)",
   inherits(tryCatch(mmp_parse_comparison_weights(broken), error = function(e) e), "error"))
broken <- script_lines[-cw$grid_line_number]
ok("MM-13 a script without the GRID sum-to-1 rule stops the parse",
   inherits(tryCatch(mmp_parse_comparison_weights(broken), error = function(e) e), "error"))
broken <- script_lines
broken[cw$nba_w_line_number] <- sub("- 0.7)", "- 0.95)", broken[cw$nba_w_line_number], fixed = TRUE)
ok("MM-14 shares above 1 stop the parse",
   inherits(tryCatch(mmp_parse_comparison_weights(broken), error = function(e) e), "error"))

# ---- 4. published file vs the results files --------------------------------------------------
for (key in names(MMP_SOURCES)) {
  s <- MMP_SOURCES[[key]]
  txt <- mmp_read_text(s$file)
  src <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
  ok(sprintf("MM-15 %s: recorded sha256 (LF) matches %s", key, s$file),
     identical(pub$sources[[key]]$sha256_lf, mmp_sha256_text(txt)))
  ok(sprintf("MM-16 %s: recorded commit is config.R %s", key, s$commit_var),
     identical(pub$sources[[key]]$commit, get(s$commit_var)))
  same <- vapply(MMP_EXTRACTS[[key]], function(sp) identical(mmp_get(pub[[key]], sp$path), mmp_apply_extract(src, sp)), logical(1))
  ok(sprintf("MM-17 %s: all %d extracts equal the results file", key, length(same)), all(same))
}
ok("MM-18 board weights shown are the study's best weights at the config windows",
   identical(unlist(pub$board$windows), as.integer(MOMENTUM_BOARD_WINDOWS)) &&
     all(vapply(MOMENTUM_BOARD_WINDOWS, function(w) {
       d <- Filter(function(r) r$method == pub$board$carry_method && r$window == as.character(w) &&
                     r$target == pub$board$weights_target, pub$rolling_window$weights$detail)
       length(d) == 1L && isTRUE(all.equal(unlist(d[[1]]$best_weights),
                                          unname(MOMENTUM_BOARD_WEIGHTS[[as.character(w)]])))
     }, logical(1))))
raw <- mmp_read_text(mm_path)
ok("MM-19 no betting vocabulary in the published file",
   !grepl("\\b(odds|spreads?|picks?|props?|wagers?|edges?|bets?|betting|sportsbook|moneyline|parlay)\\b", raw, ignore.case = TRUE, perl = TRUE))
ok("MM-20 no NaN / Infinity / \"NA\" values", !grepl(':\\s*(NaN|-?Infinity|"NA")', raw, perl = TRUE))

# ---- 5. rebuild -------------------------------------------------------------------------------
reachable <- nzchar(Sys.which("git")) && all(vapply(c(MOMENTUM_BOARD_STUDY_COMMIT, MOMENTUM_BOARD_MEASURES_STUDY_COMMIT), function(c) {
  st <- suppressWarnings(system2("git", c("cat-file", "-e", paste0(c, "^{commit}")), stdout = FALSE, stderr = FALSE))
  identical(as.integer(st), 0L)
}, logical(1)))
if (!reachable) {
  cat("[SKIP] MM-21 rebuild check: git or the study commits are not available in this clone\n")
} else {
  out <- tempfile(fileext = ".json")
  publish_momentum_methodology(root_dir, out_path = out)
  ok("MM-21 re-running the publisher reproduces the committed momentum_methodology.json",
     identical(mmp_read_text(out), raw))
}

cat(sprintf("\n%s\n", if (failures == 0L) "ALL PASS" else sprintf("%d FAILURE(S)", failures)))
quit(status = if (failures == 0L) 0L else 1L, save = "no")
