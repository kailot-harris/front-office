# ==============================================================================
# .github/scripts/check-chart-authenticity.R
#
# Pilot implementation for kailot-harris/front-office#142 (NBA share).
#
# Problem it guards against (see front-office#143 / NBA_analytics#103,
# already fixed in this repo): a chart script whose real input is missing
# silently drawing invented numbers - random draws, hand-typed tables, or an
# unvalidated formula - instead of refusing to render. Because the old test
# harness only checked "did a file get produced", a cache-less CI runner
# never exercised the real-data path at all; the fallback output was the
# only thing ever tested, and it always "passed".
#
# This is a static check: it parses (never executes) every tools/gif_*.R and
# tools/plot_*.R file - the chart/GIF producers - and flags three shapes of
# invented-data code path:
#
#   1. Random/periodic generators that can feed a plotted aesthetic:
#      rnorm, runif, rbinom, rpois, rexp, rgamma, rbeta, sample, and sin/cos
#      (sin/cos are legitimate for arc/geometry layout - see the allowlist
#      mechanism below - but are exactly how a "simulated" data series gets
#      drawn too, so they are flagged by default).
#   2. Literal data tables feeding plotted data: tribble(...), or a
#      data.frame(...) call whose arguments assign actual column values
#      (not an empty `data.frame()` no-data sentinel, and not a pass-through
#      of an already-loaded real data frame).
#   3. A fallback branch - an `if`/`else` arm guarded by a file-existence or
#      null check (file.exists, is.null) - that constructs one of the above
#      instead of calling viz_stop_no_data() (tools/viz_common.R). A branch
#      that calls viz_stop_no_data() anywhere in its body is compliant and
#      is not flagged, regardless of what else is in it.
#
# Allowlisting genuine layout/decoration code (court-line coordinates,
# confetti animation, bracket geometry, etc.): put a one-line-reason comment
# on the flagged line itself, or on the line directly above it:
#
#   arcx <- cos(theta)  # chart-authenticity-allow: fixed court-geometry angle, not data
#
# or
#
#   # chart-authenticity-allow: 3PT arc radius is a fixed regulation constant
#   arc_3pt <- calc_arc(c(0, 5.25), radius = 23.75, angle_corner_r, angle_corner_l)
#
# A marker with no text after the colon does not count - the reason is
# mandatory. NBA_TEAM_COLORS-style static color/name tables are not chart
# *data* (they do not vary with results) and do not need an allowlist entry.
#
# Usage:
#   Rscript .github/scripts/check-chart-authenticity.R [file ...]
#
# With no arguments, checks every tracked tools/gif_*.R and tools/plot_*.R
# file. With arguments, checks exactly those files (used by this script's
# own fixture-based self-test; not needed for normal CI use).
#
# Base R only (parse(), utils::getParseData()) - no packages, no execution.
# ==============================================================================

ALLOW_MARKER_RE <- "chart-authenticity-allow:\\s*(.+)$"

RANDOM_FUNCS <- c("rnorm", "runif", "rbinom", "rpois", "rexp", "rgamma", "rbeta", "sample")
TRIG_FUNCS   <- c("sin", "cos")
TABLE_FUNCS  <- c("tribble")

#' Look for a `chart-authenticity-allow: <reason>` comment on `line` itself
#' or on the line immediately before it. Returns the reason string, or NA if
#' there is no (valid, non-empty) allowlist comment.
find_allow_reason <- function(src_lines, line) {
  for (ln in c(line, line - 1L)) {
    if (ln < 1L || ln > length(src_lines)) next
    m <- regmatches_first(src_lines[ln], ALLOW_MARKER_RE)
    if (!is.na(m) && nzchar(trimws(m))) return(trimws(m))
  }
  NA_character_
}

regmatches_first <- function(x, pattern) {
  m <- regexec(pattern, x, perl = TRUE)
  g <- regmatches(x, m)[[1]]
  if (length(g) >= 2) g[2] else NA_character_
}

#' True if `text` (source for a data.frame()/tribble() call or an enclosing
#' branch) hand-types a *vector* of literal values - c() with two or more
#' numeric or quoted-string literal elements. A single scalar literal
#' (step = 0L, a "Season Open" label, a team code used as a key) is normal
#' real-data plumbing, not a fabricated table; a hard-coded multi-element
#' vector standing in for a column of results is what this flags, e.g.:
#'   data.frame(x = c(-3, 3), y = c(4, 4))                 -- layout coords
#'   data.frame(team = teams, rating = c(104, 98, 111, 87)) -- invented stats
NUM_LIT  <- "-?[0-9]+(\\.[0-9]+)?"
STR_LIT  <- '(?:"[^"]*"|\'[^\']*\')'
LIT_ELEM <- sprintf("(?:%s|%s)", NUM_LIT, STR_LIT)
LIT_VECTOR_RE <- sprintf("\\bc\\s*\\(\\s*%s\\s*(,\\s*%s\\s*)+\\)", LIT_ELEM, LIT_ELEM)

looks_like_literal_table <- function(text) {
  grepl(LIT_VECTOR_RE, text, perl = TRUE)
}

#' Real-data-loading calls. A branch that reads one of these is treated as
#' the "data is available" arm, even if it later builds a data.frame() from
#' what it read - that is normal data handling, not fabrication.
REAL_DATA_LOAD_RE <- "\\b(readRDS|read\\.csv|read_csv|read\\.table|fromJSON|dbGetQuery|scan)\\s*\\("

#' Join full source lines line1:line2 (1-based, inclusive) into one string,
#' for regex checks that don't need to be more precise than "is this text
#' somewhere inside this parsed node's span".
span_text <- function(src_lines, line1, line2) {
  line2 <- min(line2, length(src_lines))
  paste(src_lines[line1:line2], collapse = "\n")
}

#' Check one chart script. Returns a data.frame of findings (zero rows if
#' clean) with columns: file, line, kind, detail.
check_file <- function(path) {
  src_lines <- readLines(path, warn = FALSE)
  parsed <- tryCatch(parse(path, keep.source = TRUE), error = function(e) e)
  if (inherits(parsed, "error")) {
    return(data.frame(
      file = path, line = NA_integer_, kind = "parse-error",
      detail = conditionMessage(parsed), stringsAsFactors = FALSE
    ))
  }

  pd <- utils::getParseData(parsed)
  findings <- list()

  add_finding <- function(line, kind, detail) {
    findings[[length(findings) + 1L]] <<- data.frame(
      file = path, line = line, kind = kind, detail = detail,
      stringsAsFactors = FALSE
    )
  }

  # ---- 1 & 2: flagged function calls (random generators, trig, tribble) ----
  calls <- pd[pd$token == "SYMBOL_FUNCTION_CALL", ]
  for (i in seq_len(nrow(calls))) {
    fn <- calls$text[i]
    ln <- calls$line1[i]

    if (fn %in% RANDOM_FUNCS) {
      reason <- find_allow_reason(src_lines, ln)
      if (is.na(reason)) {
        add_finding(ln, "random-generator",
                    sprintf("%s() can feed a plotted aesthetic with non-data-derived values.", fn))
      }
    } else if (fn %in% TRIG_FUNCS) {
      reason <- find_allow_reason(src_lines, ln)
      if (is.na(reason)) {
        add_finding(ln, "trig-generator",
                    sprintf("%s() outside an allowlisted geometry/layout line - could be feeding a simulated data series.", fn))
      }
    } else if (fn %in% TABLE_FUNCS) {
      reason <- find_allow_reason(src_lines, ln)
      if (is.na(reason)) {
        add_finding(ln, "literal-table",
                    sprintf("%s() is a hand-typed data table.", fn))
      }
    }
  }

  # ---- 2b: data.frame(...) calls that assign literal column values -------
  # (data.frame() with no args, or data.frame(existing_df) pass-through, is
  # not a literal table and is not flagged here.)
  df_calls <- calls[calls$text == "data.frame", ]
  for (i in seq_len(nrow(df_calls))) {
    ln <- df_calls$line1[i]
    # The grammar wraps a call as: expr -> expr(the callee name) '(' args ')'.
    # The SYMBOL_FUNCTION_CALL's immediate parent is only the callee-name
    # wrapper expr (same single line as the name); its *own* parent is the
    # expr spanning the whole call, args included - that's the span we need
    # so a multi-line call's later lines aren't missed.
    name_expr_id <- df_calls$parent[i]
    full_call_id <- pd$parent[pd$id == name_expr_id]
    call_row <- pd[pd$id == full_call_id, ]
    if (nrow(call_row) == 0) next
    call_text <- span_text(src_lines, call_row$line1[1], call_row$line2[1])
    if (looks_like_literal_table(call_text)) {
      reason <- find_allow_reason(src_lines, ln)
      if (is.na(reason)) {
        add_finding(ln, "literal-table",
                    "data.frame() call constructs literal column values (not an empty sentinel or pass-through).")
      }
    }
  }

  # ---- 3: fallback branches guarded by file/cache-missing checks ---------
  if_tokens <- pd[pd$token == "IF", ]
  for (i in seq_len(nrow(if_tokens))) {
    if_expr_id <- if_tokens$parent[i]
    children <- pd[pd$parent == if_expr_id & pd$token == "expr", ]
    if (nrow(children) == 0) next
    children <- children[order(children$line1, children$col1), ]

    cond <- children[1, ]
    cond_text <- span_text(src_lines, cond$line1, cond$line2)
    guards_missing_data <- grepl("file\\.exists|is\\.null", cond_text)
    if (!guards_missing_data) next

    branches <- children[-1, , drop = FALSE]
    for (b in seq_len(nrow(branches))) {
      branch <- branches[b, ]
      branch_text <- span_text(src_lines, branch$line1, branch$line2)
      if (grepl("viz_stop_no_data", branch_text, fixed = TRUE)) next  # compliant arm
      if (grepl(REAL_DATA_LOAD_RE, branch_text, perl = TRUE)) next     # "data is available" arm

      has_tribble <- grepl("\\btribble\\s*\\(", branch_text)
      has_df_literal <- grepl("\\bdata\\.frame\\s*\\(", branch_text) && looks_like_literal_table(branch_text)
      if (has_tribble || has_df_literal) {
        reason <- find_allow_reason(src_lines, branch$line1)
        if (is.na(reason)) {
          add_finding(branch$line1, "fabricated-fallback",
                      sprintf("branch guarded by '%s' constructs a data table instead of calling viz_stop_no_data().",
                              trimws(strsplit(cond_text, "\n")[[1]][1])))
        }
      }
    }
  }

  if (length(findings) == 0) {
    data.frame(file = character(), line = integer(), kind = character(), detail = character(), stringsAsFactors = FALSE)
  } else {
    do.call(rbind, findings)
  }
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main <- function() {
  args <- commandArgs(trailingOnly = TRUE)

  if (length(args) > 0) {
    chart_files <- args
  } else {
    tools_files <- system2("git", c("ls-files", "tools"), stdout = TRUE)
    tools_files <- tools_files[nzchar(tools_files)]
    tools_files <- tools_files[grepl("[.][Rr]$", tools_files)]
    chart_files <- tools_files[grepl("^tools/(gif_|plot_)", tools_files)]
  }

  if (length(chart_files) == 0) {
    stop("check-chart-authenticity: no chart scripts found (expected tools/gif_*.R or tools/plot_*.R) - is this running from the repo root?")
  }

  cat(sprintf("Checking %d chart script(s) for non-data-derived plotted values...\n", length(chart_files)))

  all_findings <- do.call(rbind, lapply(chart_files, check_file))

  if (is.null(all_findings) || nrow(all_findings) == 0) {
    cat("PASS: no unallowlisted invented-data code paths found.\n")
    quit(status = 0L, save = "no")
  }

  cat(sprintf("\nFAILED: %d finding(s):\n\n", nrow(all_findings)))
  for (i in seq_len(nrow(all_findings))) {
    f <- all_findings[i, ]
    loc <- if (is.na(f$line)) f$file else sprintf("%s:%d", f$file, f$line)
    cat(sprintf("  [%s] %s\n    %s\n", f$kind, loc, f$detail))
  }
  cat(paste0(
    "\nIf any of these are genuine layout/decoration (court lines, animation easing,\n",
    "bracket geometry, etc.), add a one-line reason comment on the flagged line or\n",
    "the line above it:\n\n  # chart-authenticity-allow: <why this is not chart data>\n\n",
    "Otherwise, replace the invented values with real data or a viz_stop_no_data() call.\n"
  ))
  quit(status = 1L, save = "no")
}

main()
