# ==============================================================================
# tests/test_stage_bootstrap.R
#
# Every pipeline stage entrypoint must resolve its own location instead of
# setwd()-ing to a hardcoded absolute path. The original pattern
#
#     PROJECT_DIR <- "c:/Users/.../NBA Analytics"
#     if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)
#     source("config.R")
#
# ran before config.R could derive PROJECT_DIR from its own location, so from a
# git worktree a stage silently relocated into the main checkout and read that
# tree's config, caches and siblings - or failed outright when a sibling existed
# only on the branch under test.
#
# Two layers of coverage:
#
#   1. Static, for all seven entrypoints: no hardcoded authoring path, no
#      top-level setwd(), no working-directory-relative source(), and a
#      bootstrap block that is identical (as parsed code) across every file -
#      the drift guard, since the block has to be duplicated per entrypoint by
#      nature: it is what finds config.R.
#   2. Behavioural, for the six with an entrypoint function: source the real
#      file from a scratch working directory that is not the repo root, with
#      NBA_SKIP_STAGE_AUTORUN=1, and assert PROJECT_DIR lands on THIS checkout.
#      This is the layer that actually fails when the defect comes back.
#
# enhanced_model.R is static-only: it is a top-to-bottom training script with no
# entrypoint function, so it cannot be loaded without training a model.
#
# Usage: Rscript tests/test_stage_bootstrap.R
# ==============================================================================

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
})

failures <- 0L
checks   <- 0L

ok <- function(label, cond) {
  checks <<- checks + 1L
  if (isTRUE(cond)) {
    cat(sprintf("  PASS  %s\n", label))
  } else {
    failures <<- failures + 1L
    cat(sprintf("  FAIL  %s\n", label))
  }
}
section <- function(title) cat(sprintf("\n== %s ==\n", title))
canon <- function(x) normalizePath(x, winslash = "/", mustWork = FALSE)

# Entrypoint -> the function its trailing guarded call invokes, or NA for a
# straight-line script that cannot be loaded without doing its work.
ENTRYPOINTS <- c(
  "prediction_accuracy_logger.R" = "run_prediction_accuracy_logger",
  "bet_tracker.R"                = "grade_yesterday_bets",
  "injury_scraper.R"             = "fetch_live_nba_injuries",
  "market_odds_engine.R"         = "evaluate_betting_slate",
  "roster_bottom_up_engine.R"    = "project_all_30_teams",
  "sync_rosters.R"               = "sync_active_rosters",
  "enhanced_model.R"             = NA_character_
)

# ------------------------------------------------------------------------------
section("Static: no stage hardcodes its own location")

bootstrap_code <- function(path) {
  for (e in parse(path)) {
    if (is.call(e) && length(e) == 3L &&
        as.character(e[[1]]) %in% c("<-", "=") &&
        is.name(e[[2]]) && identical(as.character(e[[2]]), ".THIS_DIR")) {
      return(paste(deparse(e[[3]]), collapse = "\n"))
    }
  }
  NA_character_
}

reference <- NULL
for (fn in names(ENTRYPOINTS)) {
  path  <- file.path(REPO_ROOT, fn)
  lines <- readLines(path, warn = FALSE)

  ok(sprintf("%-29s no hardcoded authoring path", fn),
     !any(grepl("kayceeslices", lines, fixed = TRUE)))

  # Textual, not top-level-only: the original defect hid the call inside an
  # `if (dir.exists(PROJECT_DIR))`, so a check that only read top-level call
  # heads saw an `if` and passed. A stage has no business calling setwd() at all.
  # Comments stripped first: each file's bootstrap comment names setwd() as the
  # thing it replaced. Crude (a "#" inside a string literal would over-strip),
  # which is fine here - over-stripping can only make this check more lenient
  # about comments, never about code.
  code_lines <- sub("#.*$", "", lines)
  ok(sprintf("%-29s never calls setwd()", fn),
     !any(grepl("setwd(", code_lines, fixed = TRUE)))

  # A relative source("x.R") depends on the working directory; the fixed form
  # is source(file.path(.THIS_DIR, "x.R")).
  rel_source <- startsWith(lines, "source(\"")
  ok(sprintf("%-29s no cwd-relative source()", fn), !any(rel_source))

  code <- bootstrap_code(path)
  ok(sprintf("%-29s defines a .THIS_DIR bootstrap", fn), !is.na(code))
  if (is.null(reference)) {
    reference <- code
  } else {
    # Drift guard: the block is duplicated by necessity, so require it to stay
    # byte-identical as parsed code (comments around it may differ).
    ok(sprintf("%-29s bootstrap matches the others exactly", fn),
       identical(code, reference))
  }
}

# ------------------------------------------------------------------------------
section("Behavioural: each stage loads from a foreign working directory")

load_stage <- function(fn) {
  env     <- new.env(parent = globalenv())
  home    <- canon(getwd())
  old_env <- Sys.getenv("NBA_SKIP_STAGE_AUTORUN", unset = NA)
  scratch <- file.path(tempdir(), "stage-load-scratch")
  dir.create(scratch, showWarnings = FALSE, recursive = TRUE)
  Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")
  setwd(scratch)
  on.exit({
    setwd(home)
    if (is.na(old_env)) Sys.unsetenv("NBA_SKIP_STAGE_AUTORUN")
    else Sys.setenv(NBA_SKIP_STAGE_AUTORUN = old_env)
  }, add = TRUE)
  wd_during <- canon(getwd())
  out <- capture.output(suppressMessages(suppressWarnings(
    source(file.path(REPO_ROOT, fn), local = env))))
  list(env = env, wd_during = wd_during, wd_after = canon(getwd()), output = out)
}

for (fn in names(ENTRYPOINTS)) {
  entry <- ENTRYPOINTS[[fn]]
  if (is.na(entry)) {
    cat(sprintf("  SKIP  %-29s straight-line script, static coverage only\n", fn))
    next
  }
  res <- tryCatch(load_stage(fn), error = function(e) e)
  if (inherits(res, "error")) {
    ok(sprintf("%-29s sources from a scratch cwd", fn), FALSE)
    cat(sprintf("        %s\n", conditionMessage(res)))
    next
  }
  ok(sprintf("%-29s loaded from outside the repo root", fn),
     !identical(res$wd_during, canon(REPO_ROOT)))
  ok(sprintf("%-29s defines %s()", fn, entry),
     is.function(tryCatch(get(entry, envir = res$env), error = function(e) NULL)))
  ok(sprintf("%-29s PROJECT_DIR is this checkout", fn),
     identical(canon(get("PROJECT_DIR", envir = res$env)), canon(REPO_ROOT)))
  ok(sprintf("%-29s CACHE_DIR is under this checkout", fn),
     identical(canon(get("CACHE_DIR", envir = res$env)),
               canon(file.path(REPO_ROOT, "cache"))))
  ok(sprintf("%-29s left the working directory alone", fn),
     identical(res$wd_after, res$wd_during))
}

# ------------------------------------------------------------------------------
cat(sprintf("\n%d checks, %d failure(s).\n", checks, failures))
if (failures > 0L) quit(status = 1L)
cat("ALL CHECKS PASSED\n")
