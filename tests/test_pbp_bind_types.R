# ==============================================================================
# tests/test_pbp_bind_types.R
#
# NBA_analytics#143: the play-by-play stages bind two hoopR seasons whose column
# types disagree (`id` numeric in 2025-26, character in 2026-27), and the current
# season's cache must refresh when it is behind while completed seasons stay
# cached. Covers pbp_cache_utils.R without the network: every fetch goes to a
# fake function, and the frames are tiny hand-built tables describing column
# types only, not sports data.
#
# Usage: Rscript tests/test_pbp_bind_types.R
# ==============================================================================

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
})
source(file.path(REPO_ROOT, "pbp_cache_utils.R"))

n_pass <- 0L
n_fail <- 0L
check <- function(cond, label) {
  if (isTRUE(cond)) {
    n_pass <<- n_pass + 1L
    cat("  PASS:", label, "\n")
  } else {
    n_fail <<- n_fail + 1L
    cat("  FAIL:", label, "\n")
  }
}
quiet <- function(expr) suppressMessages(expr)

cat("== binding: numeric id + character id ==\n")
past <- data.frame(id = c(4018599674, 4018599677), game_id = c(1L, 1L),
                   game_date = as.Date(c("2026-06-01", "2026-06-01")), stringsAsFactors = FALSE)
cur  <- data.frame(id = c("4019099604", "4019099607"), game_id = c(2L, 2L),
                   game_date = as.Date(c("2026-11-01", "2026-11-01")), stringsAsFactors = FALSE)
check(inherits(try(dplyr::bind_rows(past, cur), silent = TRUE), "try-error"),
      "plain bind_rows() fails on the mismatch (the #143 failure is reproduced)")
mm <- pbp_type_mismatches(list(past, cur), c("season_2026", "season_2027"))
check(identical(mm$name, "id") && mm$season_2026 == "numeric" && mm$season_2027 == "character",
      "mismatch report lists id as numeric vs character")
b <- quiet(pbp_bind_seasons(list(past, cur), c("season_2026", "season_2027")))
check(is.data.frame(b) && nrow(b) == 4L, "bind succeeds with all rows")
check(is.character(b$id), "id is character after the bind")
check(identical(b$id, c("4018599674", "4018599677", "4019099604", "4019099607")),
      "numeric ids become plain digit strings (no scientific notation)")
check(is.integer(b$game_id) && inherits(b$game_date, "Date"), "matching columns keep their type")

cat("== binding: other mismatched columns ==\n")
f1 <- data.frame(a = c(1L, NA), b = c(TRUE, FALSE), c = c(1.5, 2), d = factor(c("x", "y")),
                 only1 = 1:2, stringsAsFactors = FALSE)
f2 <- data.frame(a = c(3.5, 4), b = c(1L, NA), c = c("p", NA), d = c("z", "x"),
                 stringsAsFactors = FALSE)
mm2 <- pbp_type_mismatches(list(f1, f2), c("s1", "s2"))
check(setequal(mm2$name, c("a", "b", "c", "d")), "every differing column is listed, columns in one frame only are not")
b2 <- quiet(pbp_bind_seasons(list(f1, f2), c("s1", "s2")))
check(is.numeric(b2$a) && identical(b2$a, c(1, NA, 3.5, 4)), "integer + double -> numeric, values kept")
check(is.numeric(b2$b) && identical(b2$b, c(1, 0, 1, NA)), "logical + integer -> numeric")
check(is.character(b2$c) && identical(b2$c, c("1.5", "2", "p", NA)), "double + character -> character, NA kept")
check(is.character(b2$d) && identical(b2$d, c("x", "y", "z", "x")), "factor + character -> character labels")
check(identical(b2$only1, c(1L, 2L, NA, NA)), "a column in one season only is NA-filled")
check(is.null(pbp_bind_seasons(list(NULL, f1[0, ]))), "no non-empty frames -> NULL")
check(identical(nrow(quiet(pbp_bind_seasons(list(f1)))), 2L), "a single frame passes through")

cat("== staleness decision ==\n")
today <- as.Date("2026-11-16")
check(pbp_cache_decision(2027, 2027, 80424, as.Date("2026-11-10"), 120, today) == "refetch",
      "stale current season -> refetch")
check(pbp_cache_decision(2026, 2027, 642472, as.Date("2026-06-13"), 600, today) == "cache",
      "complete past season -> cache")
check(pbp_cache_decision(2027, 2027, 98854, as.Date("2026-11-15"), 120, today) == "cache",
      "current season through yesterday -> cache")
check(pbp_cache_decision(2027, 2027, 80424, as.Date("2026-11-10"), 1, today) == "cache",
      "current season refreshed within the last hours -> cache (no refetch loop)")
check(pbp_cache_decision(2027, 2027, 0, NA, NA, today) == "fetch", "empty cache -> fetch")
check(pbp_cache_decision(2026, 2027, 0, NA, NA, today) == "fetch", "missing past season -> fetch")

cat("== loader: refetch, keep-on-failure ==\n")
tmp <- file.path(tempdir(), "pbp143"); dir.create(tmp, showWarnings = FALSE)
old_cur <- data.frame(id = c("1", "2"), game_date = as.Date(c("2026-11-09", "2026-11-10")))
new_cur <- data.frame(id = c("1", "2", "3"), game_date = as.Date(c("2026-11-09", "2026-11-10", "2026-11-15")))
old_past <- data.frame(id = c(9, 10), game_date = as.Date(c("2026-06-12", "2026-06-13")))
age_file <- function(p, hours) Sys.setFileTime(p, Sys.time() - hours * 3600)
calls <- 0L
fetch_ok   <- function(seasons) { calls <<- calls + 1L; new_cur }
fetch_fail <- function(seasons) { calls <<- calls + 1L; stop("network down") }
fetch_none <- function(seasons) { calls <<- calls + 1L; new_cur[0, ] }

p27 <- file.path(tmp, "nba_pbp_2027.rds"); p26 <- file.path(tmp, "nba_pbp_2026.rds")
saveRDS(old_past, p26); age_file(p26, 600)
calls <- 0L
got <- quiet(load_pbp_season_cached(2026, tmp, 2027, fetch_ok, today = today))
check(calls == 0L && identical(got$id, c(9, 10)), "past season read from cache, no fetch")

saveRDS(old_cur, p27); age_file(p27, 120)
calls <- 0L
got <- quiet(load_pbp_season_cached(2027, tmp, 2027, fetch_ok, today = today))
check(calls == 1L && nrow(got) == 3L && nrow(readRDS(p27)) == 3L, "stale current season refetched and cache rewritten")

saveRDS(old_cur, p27); age_file(p27, 120)
calls <- 0L
msgs <- character(0)
got <- withCallingHandlers(load_pbp_season_cached(2027, tmp, 2027, fetch_fail, today = today),
                           message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") })
check(calls == 1L && identical(got$id, c("1", "2")), "failed fetch -> existing cache returned")
check(identical(readRDS(p27)$id, c("1", "2")), "failed fetch -> cache file left intact")
check(any(grepl("^>>> \\[WARN\\]", msgs)), "failed fetch logs a >>> [WARN] line")

saveRDS(old_cur, p27); age_file(p27, 120)
got <- quiet(load_pbp_season_cached(2027, tmp, 2027, fetch_none, today = today))
check(identical(got$id, c("1", "2")) && nrow(readRDS(p27)) == 2L, "empty fetch -> cache kept, not emptied")

unlink(tmp, recursive = TRUE)
cat(sprintf("\n%d passed, %d failed\n", n_pass, n_fail))
if (n_fail > 0) quit(status = 1L)
