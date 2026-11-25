# ==============================================================================
# NFL Analytics - publish the Momentum Board methodology data for the web
# Path: <repo root>/tools/publish_momentum_methodology.R   (NFL_analytics#226)
#
# Writes web/public/data/momentum_methodology.json (config.R:
# WEB_JSON_MOMENTUM_METHODOLOGY), the only data behind /momentum/methodology.
# It EXTRACTS and CHECKS only:
#   * no random numbers, no recomputed metrics, no hand-entered numbers;
#   * every study figure is copied from the two study results files, at the
#     commits that produced them:
#       docs/research/rolling_window_study_results.json   (#227, MOMENTUM_BOARD_STUDY_COMMIT)
#       docs/research/momentum_measures_study_results.json (#221, MOMENTUM_BOARD_MEASURES_STUDY_COMMIT)
#     Each extract (MMP_EXTRACTS) copies a subtree as is; a few row arrays are
#     narrowed by a row filter or a field list, recorded in the output so the
#     contract test can re-apply it and compare;
#   * the one exception (owner decision): the NBA-style comparison weights
#     0.7/0.1/0.1/0.1 are in neither results file. They are parsed from the
#     NBA_W line of tools/rolling_window_study.R read with `git show` at
#     MOMENTUM_BOARD_STUDY_COMMIT, the Elo-change share derived from the
#     script's sum-to-1 grid rule. If the parse fails the script stops; it never
#     falls back to typed-in values;
#   * the input files must match the files stored at those commits (line
#     endings normalised to LF), or nothing is written;
#   * the output is re-parsed and every extract compared with the source
#     before the file is moved into place.
# The output has no timestamp, so re-running on the same inputs gives the same
# bytes (tests/test_momentum_methodology.R checks this).
#
# Static research artifact: NOT a run_full_pipeline.R stage and not in
# WEB_DATA_FILES (data_manifest.json marks it static). Run it again only when a
# study is re-run.
#
# Usage:  Rscript tools/publish_momentum_methodology.R
# Exit status: 0 written; 1 any check failed (nothing written).
# ==============================================================================

suppressPackageStartupMessages(library(jsonlite))

MMP_SCHEMA_VERSION <- 1L
MMP_STUDY_SCRIPT   <- "tools/rolling_window_study.R"
MMP_SOURCES <- list(
  rolling_window = list(
    file = "docs/research/rolling_window_study_results.json",
    report = "docs/research/rolling_window_study.md",
    script = "tools/rolling_window_study.R",
    issue = 227L, merged_in = 228L,
    commit_var = "MOMENTUM_BOARD_STUDY_COMMIT"),
  momentum_measures = list(
    file = "docs/research/momentum_measures_study_results.json",
    report = "docs/research/momentum_measures_study.md",
    script = "tools/momentum_measures_study.R",
    issue = 221L, merged_in = 221L,
    commit_var = "MOMENTUM_BOARD_MEASURES_STUDY_COMMIT")
)

# What the page reads. path: dot path into the results file. where: keep rows
# whose field is one of the values. fields: keep only these fields of each row.
MMP_EXTRACTS <- list(
  rolling_window = list(
    list(path = "meta"),
    list(path = "stronger_arm.selections"),
    list(path = "stronger_arm.selection_rule"),
    list(path = "stronger_arm.table",
         where = list(field = "target",
                      values = c("margin_beyond_elo", "win_beyond_elo_logloss_gain", "win_beyond_elo_auc_gain"))),
    list(path = "replication_arm.best"),
    list(path = "replication_arm.test_season"),
    list(path = "weights.grid"),
    list(path = "weights.components"),
    list(path = "weights.standardisation"),
    list(path = "weights.score"),
    list(path = "weights.table"),
    list(path = "weights.detail",
         fields = c("method", "window", "target", "rows", "best_weights", "best_r2", "best_ci",
                    "nba_r2", "nba_ci", "best_minus_nba", "best_minus_nba_ci", "equal_r2", "equal_ci",
                    "form_only_r2", "form_only_ci", "flat_n_within_best_ci", "flat_share_within",
                    "flat_weight_ranges")),
    list(path = "flags.note"),
    list(path = "flags.definitions"),
    list(path = "flags.detection"),
    list(path = "flags.power_threshold"),
    list(path = "availability.fully_covered_from"),
    list(path = "availability.covered_threshold"),
    list(path = "availability.coverage"),
    list(path = "availability.key_players")
  ),
  momentum_measures = list(
    list(path = "study"),
    list(path = "targets"),
    list(path = "measures"),
    list(path = "series"),
    list(path = "single_feature_results"),
    list(path = "combination_search.target"),
    list(path = "combination_search.rows"),
    list(path = "combination_search.pooled_r2_gain"),
    list(path = "combination_search.pooled_ci_95"),
    list(path = "combination_search.comparisons"),
    list(path = "combination_search.permutation"),
    list(path = "combination_search.final_choice"),
    list(path = "combination_search.reliability_checks"),
    list(path = "combination_search.final_verdict"),
    list(path = "flags"),
    list(path = "holdout"),
    list(path = "limits")
  )
)

# Grid column names in tools/rolling_window_study.R -> board component names.
MMP_COMPONENT_NAMES <- c(form = "form", trend = "trend", resid = "residual", elo = "elo_change")

mmp_fail <- function(...) stop(sprintf(...), call. = FALSE)
`%||%` <- function(a, b) if (is.null(a)) b else a

mmp_lf <- function(txt) gsub("\r\n", "\n", txt, fixed = TRUE)

mmp_read_text <- function(path) {
  sz <- file.info(path)$size
  if (is.na(sz) || sz == 0) mmp_fail("input %s is empty or missing", path)
  txt <- rawToChar(readBin(path, "raw", n = sz))
  Encoding(txt) <- "UTF-8"
  mmp_lf(txt)
}

# sha256 of text (written as UTF-8 bytes, LF line endings).
mmp_sha256_text <- function(txt) {
  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  con <- file(tmp, open = "wb"); writeBin(charToRaw(enc2utf8(txt)), con); close(con)
  unname(as.character(tools::sha256sum(tmp)))
}

mmp_git <- function(root, args) {
  git <- Sys.which("git")
  if (!nzchar(git)) mmp_fail("git not found; the sources cannot be checked against their commits")
  out <- suppressWarnings(system2(git, c("-C", shQuote(root), args), stdout = TRUE, stderr = FALSE))
  st <- attr(out, "status")
  if (!is.null(st) && st != 0L) mmp_fail("git %s failed (exit %s)", paste(args, collapse = " "), st)
  out
}

# File content at a commit, LF line endings.
mmp_git_show <- function(root, commit, path) {
  if (!grepl("^[0-9a-f]{40}$", commit)) mmp_fail("commit must be a full 40-character hex sha, got '%s'", commit)
  lines <- mmp_git(root, c("show", paste0(commit, ":", path)))
  txt <- paste0(paste(lines, collapse = "\n"), "\n")
  Encoding(txt) <- "UTF-8"
  mmp_lf(sub("\r$", "", txt))
}

mmp_get <- function(x, path) {
  for (k in strsplit(path, ".", fixed = TRUE)[[1]]) {
    if (!is.list(x) || is.null(names(x)) || !k %in% names(x)) return(NULL)
    x <- x[[k]]
  }
  x
}

mmp_set <- function(x, path, value) {
  keys <- strsplit(path, ".", fixed = TRUE)[[1]]
  if (length(keys) == 1L) { x[keys] <- list(value); return(x) }
  inner <- x[[keys[1]]] %||% setNames(list(), character(0))
  x[keys[1]] <- list(mmp_set(inner, paste(keys[-1], collapse = "."), value))
  x
}

# Apply one extract spec to a parsed results file.
mmp_apply_extract <- function(src, spec) {
  v <- mmp_get(src, spec$path)
  if (is.null(v)) mmp_fail("results file has no '%s'", spec$path)
  if (!is.null(spec$where)) {
    if (!is.list(v)) mmp_fail("'%s' is not a list of rows", spec$path)
    keep <- vapply(v, function(r) isTRUE(as.character(r[[spec$where$field]] %||% NA) %in% spec$where$values), logical(1))
    if (!any(keep)) mmp_fail("'%s' has no row with %s in {%s}", spec$path, spec$where$field,
                             paste(spec$where$values, collapse = ", "))
    v <- v[keep]
  }
  if (!is.null(spec$fields)) {
    v <- lapply(v, function(r) {
      miss <- setdiff(spec$fields, names(r))
      if (length(miss)) mmp_fail("a '%s' row lacks: %s", spec$path, paste(miss, collapse = ", "))
      r[spec$fields]
    })
  }
  v
}

# JSON form of an extract spec, as recorded in the output.
mmp_spec_json <- function(spec) {
  out <- list(path = spec$path)
  if (!is.null(spec$where)) out$where <- list(field = spec$where$field, values = as.list(spec$where$values))
  if (!is.null(spec$fields)) out$fields <- as.list(spec$fields)
  out
}

# ---- NBA-style comparison weights from the study script ------------------------
# Parses the GRID line (column names, the 0:N steps and the sum-to-1 rule) and
# the NBA_W line (three fixed shares). The fourth share is what the rule leaves.
# `lines`: the script, one element per line. Stops on anything unexpected.
mmp_parse_comparison_weights <- function(lines) {
  grid_i <- grep("^GRID <- ", lines)
  if (length(grid_i) != 1L) mmp_fail("expected exactly one 'GRID <- ' line, found %d", length(grid_i))
  grid <- lines[grid_i]
  eg <- regmatches(grid, regexec("expand\\.grid\\(([^)]*)\\)", grid))[[1]]
  if (length(eg) != 2L) mmp_fail("GRID line has no expand.grid(...) call")
  parts <- trimws(strsplit(eg[2], ",", fixed = TRUE)[[1]])
  m <- regmatches(parts, regexec("^([a-z_]+) = 0:([0-9]+)$", parts))
  if (length(m) != 4L || any(lengths(m) != 3L)) mmp_fail("GRID expand.grid() is not four 'name = 0:N' columns")
  cols <- vapply(m, `[`, "", 2)
  steps <- as.integer(vapply(m, `[`, "", 3))
  if (!identical(sort(cols), sort(names(MMP_COMPONENT_NAMES))))
    mmp_fail("GRID columns are %s, expected %s", paste(cols, collapse = ", "), paste(names(MMP_COMPONENT_NAMES), collapse = ", "))
  if (length(unique(steps)) != 1L) mmp_fail("GRID columns do not share one step count")
  rule_re <- sprintf("subset\\(expand\\.grid\\([^)]*\\), %s == ([0-9]+)\\)\\) / ([0-9]+)$",
                     paste(cols, collapse = " \\+ "))
  rule <- regmatches(grid, regexec(rule_re, grid))[[1]]
  if (length(rule) != 3L) mmp_fail("GRID line has no '%s == N)) / D' sum rule", paste(cols, collapse = " + "))
  total <- as.integer(rule[2]); denom <- as.integer(rule[3])
  if (total != denom || total != steps[1]) mmp_fail("GRID rule is %d / %d over 0:%d steps, not a sum-to-1 grid", total, denom, steps[1])

  nba_i <- grep("^NBA_W <- ", lines)
  if (length(nba_i) != 1L) mmp_fail("expected exactly one 'NBA_W <- ' line, found %d", length(nba_i))
  nba <- lines[nba_i]
  conds <- regmatches(nba, gregexpr("abs\\(GRID\\[, ([0-9])\\] - ([0-9.]+)\\) < 1e-9", nba))[[1]]
  if (length(conds) != 3L) mmp_fail("NBA_W line does not fix exactly three grid columns")
  idx <- as.integer(sub("^abs\\(GRID\\[, ([0-9])\\].*$", "\\1", conds))
  val <- as.numeric(sub("^.* - ([0-9.]+)\\) < 1e-9$", "\\1", conds))
  if (anyDuplicated(idx) || any(idx < 1L | idx > 4L) || anyNA(val)) mmp_fail("NBA_W line fixes an invalid grid column")
  units <- val * denom
  if (any(abs(units - round(units)) > 1e-9)) mmp_fail("an NBA_W share is not on the 1/%d grid", denom)
  free <- setdiff(1:4, idx)
  shares <- integer(4); shares[idx] <- as.integer(round(units))
  shares[free] <- total - sum(shares[idx])
  if (shares[free] < 0L) mmp_fail("NBA_W shares sum to more than 1")
  w <- setNames(shares / denom, MMP_COMPONENT_NAMES[cols])
  list(
    weights = as.list(w[unname(MMP_COMPONENT_NAMES)]),
    derived = unname(MMP_COMPONENT_NAMES[cols[free]]),
    nba_w_line_number = nba_i, nba_w_line = nba,
    grid_line_number = grid_i, grid_line = grid,
    rule = sprintf("GRID rows are %s = 0..%d with %s == %d, divided by %d, so every weighting sums to 1; NBA_W fixes %s and %s takes the rest.",
                   paste(cols, collapse = ", "), steps[1], paste(cols, collapse = " + "), total, denom,
                   paste(sprintf("%s = %s", cols[idx], format(val)), collapse = ", "), cols[free])
  )
}

# ---- build ---------------------------------------------------------------------

mmp_cfg <- function(name) {
  if (!exists(name, inherits = TRUE)) mmp_fail("config.R does not define %s", name)
  get(name, inherits = TRUE)
}

# Board selection: which carry method and windows of the weights table the board
# uses (config.R), and the check that the study's best weights there are the
# weights in config.R. The values shown come from the results rows.
mmp_board_block <- function(rw) {
  method <- mmp_cfg("MOMENTUM_BOARD_CARRY_METHOD")
  windows <- mmp_cfg("MOMENTUM_BOARD_WINDOWS")
  cfg_w <- mmp_cfg("MOMENTUM_BOARD_WEIGHTS")
  target <- "next_game"
  for (w in windows) {
    row <- Filter(function(d) identical(d$method, method) && identical(as.character(d$window), as.character(w)) &&
                    identical(d$target, target), rw$weights$detail)
    if (length(row) != 1L) mmp_fail("weights.detail has %d rows for %s / %s / %s", length(row), method, w, target)
    best <- unlist(row[[1]]$best_weights)
    want <- unname(cfg_w[[as.character(w)]][unname(MMP_COMPONENT_NAMES)])
    if (length(best) != 4L || any(abs(best - want) > 1e-9))
      mmp_fail("study best weights at %s games (%s) differ from config.R MOMENTUM_BOARD_WEIGHTS (%s)", w,
               paste(best, collapse = "/"), paste(want, collapse = "/"))
  }
  list(carry_method = method, windows = as.list(as.integer(windows)), weights_target = target,
       weights_order = as.list(unname(MMP_COMPONENT_NAMES)),
       selection = paste("Rows of rolling_window.weights.detail with method = MOMENTUM_BOARD_CARRY_METHOD,",
                         "window in MOMENTUM_BOARD_WINDOWS and target next_game (config.R); their best_weights",
                         "were checked equal to MOMENTUM_BOARD_WEIGHTS when this file was published."),
       settings_url = mmp_cfg("MOMENTUM_BOARD_SETTINGS_URL"))
}

build_momentum_methodology <- function(root = ".") {
  out <- list(schema_version = MMP_SCHEMA_VERSION,
              publisher = "tools/publish_momentum_methodology.R",
              board_issue = 226L,
              sources = list())
  parsed <- list()
  for (key in names(MMP_SOURCES)) {
    s <- MMP_SOURCES[[key]]
    commit <- mmp_cfg(s$commit_var)
    txt <- mmp_read_text(file.path(root, s$file))
    at_commit <- mmp_git_show(root, commit, s$file)
    if (!identical(sub("\n+$", "", txt), sub("\n+$", "", at_commit)))
      mmp_fail("%s does not match the file at %s (%s)", s$file, s$commit_var, commit)
    j <- tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE),
                  error = function(e) mmp_fail("%s is not valid JSON: %s", s$file, conditionMessage(e)))
    parsed[[key]] <- j
    block <- setNames(list(), character(0))
    for (spec in MMP_EXTRACTS[[key]]) block <- mmp_set(block, spec$path, mmp_apply_extract(j, spec))
    out[[key]] <- block
    out$sources[[key]] <- list(
      file = s$file, report = s$report, script = s$script, issue = s$issue, merged_in = s$merged_in,
      commit = commit, commit_config = s$commit_var,
      sha256_lf = mmp_sha256_text(txt),
      extracts = lapply(MMP_EXTRACTS[[key]], mmp_spec_json))
  }

  commit <- mmp_cfg("MOMENTUM_BOARD_STUDY_COMMIT")
  script_txt <- mmp_git_show(root, commit, MMP_STUDY_SCRIPT)
  script_lines <- strsplit(sub("\n$", "", script_txt), "\n", fixed = TRUE)[[1]]
  cw <- mmp_parse_comparison_weights(script_lines)
  blob <- mmp_git(root, c("rev-parse", paste0(commit, ":", MMP_STUDY_SCRIPT)))
  out$sources$rolling_window$nba_comparison_weights <- c(
    cw$weights,
    list(provenance = list(
      file = MMP_STUDY_SCRIPT, commit = commit, blob_sha1 = blob[1],
      line = cw$nba_w_line_number, line_text = cw$nba_w_line,
      grid_line = cw$grid_line_number, grid_line_text = cw$grid_line,
      derived_component = cw$derived, rule = cw$rule,
      note = "Not in either results file (owner decision, #226): read from the study script at the study commit.")))

  out$board <- mmp_board_block(parsed$rolling_window)
  list(payload = out, parsed = parsed)
}

mmp_to_json <- function(x) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA, pretty = FALSE))
}

# Re-parse the output and compare every extract with its source.
mmp_verify <- function(txt, parsed) {
  back <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
  for (key in names(MMP_EXTRACTS)) {
    for (spec in MMP_EXTRACTS[[key]]) {
      if (!identical(mmp_get(back[[key]], spec$path), mmp_apply_extract(parsed[[key]], spec)))
        mmp_fail("%s.%s did not round-trip; nothing written", key, spec$path)
    }
  }
  invisible(back)
}

publish_momentum_methodology <- function(root = ".", out_path = WEB_JSON_MOMENTUM_METHODOLOGY) {
  b <- build_momentum_methodology(root)
  txt <- paste0(mmp_to_json(b$payload), "\n")
  mmp_verify(txt, b$parsed)
  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
  tmp_out <- paste0(out_path, ".tmp")
  con <- file(tmp_out, open = "wb")
  writeBin(charToRaw(enc2utf8(txt)), con)
  close(con)
  if (file.exists(out_path)) unlink(out_path)
  if (!file.rename(tmp_out, out_path)) mmp_fail("could not move %s into place", tmp_out)
  message(sprintf(">>> publish_momentum_methodology: wrote %s (%d bytes; %d measure rows, %d weight rows)",
                  out_path, nchar(txt, type = "bytes"),
                  length(b$payload$momentum_measures$single_feature_results),
                  length(b$payload$rolling_window$weights$table)))
  invisible(out_path)
}

local({
  argv <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (!any(grepl("publish_momentum_methodology\\.R$", f))) return(invisible(NULL))
  root <- normalizePath(dirname(dirname(f[1])), winslash = "/", mustWork = FALSE)
  setwd(root)
  source("config.R")
  ok <- tryCatch({
    publish_momentum_methodology(root)
    TRUE
  }, error = function(e) {
    message(sprintf("[FAIL] publish_momentum_methodology: %s", conditionMessage(e)))
    FALSE
  })
  quit(status = if (ok) 0L else 1L, save = "no")
})
