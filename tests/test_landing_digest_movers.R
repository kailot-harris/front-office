# tests/test_landing_digest_movers.R - NBA#213: tracked ratings history and the
# 1/7/21-day movers with nearest-earlier compared_to. Offline.
# Usage: Rscript tests/test_landing_digest_movers.R
local({
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  source(file.path(dirname(normalizePath(f)), "landing_digest_helpers.R"), chdir = FALSE)
}, envir = globalenv())

cat("History file is tracked, not ignored\n")
rc <- system2("git", c("-C", shQuote(REPO_ROOT), "check-ignore", "-q", LD_HISTORY_PATH))
check(rc == 1L, "git check-ignore reports data/history/ratings_history.csv as NOT ignored")
check(!grepl("^(cache|web/public)/", LD_HISTORY_PATH), "history lives outside cache/ and web/public/")
h0 <- utils::read.csv(file.path(REPO_ROOT, LD_HISTORY_PATH), stringsAsFactors = FALSE)
check(identical(names(h0), c("date", "team", "metric", "value")), "columns date, team, metric, value")

cat("Update + prune\n")
p <- tempfile(fileext = ".csv")
rt <- function(v) data.frame(team = c("BOS", "NYK", "LAL"), value = v)
ld_update_history(rt(c(1, 2, 3)), "2025-01-01", p)
ld_update_history(rt(c(5, 5, 5)), "2026-11-01", p)
ld_update_history(rt(c(6, 6, 6)), "2026-11-01", p)           # same-day re-run replaces
h <- ld_update_history(rt(c(9, 1, 5)), "2026-11-20", p)
check(!"2025-01-01" %in% h$date, "rows older than ~400 days pruned")
check(sum(h$date == "2026-11-01") == 3 && all(h$value[h$date == "2026-11-01"] == 6), "one row per team per day")

cat("Movers\n")
mv <- ld_movers(h)
check(identical(names(mv$windows), c("1", "7", "21")) && mv$metric == LD_METRIC, "windows + metric")
check(mv$windows[["1"]]$compared_to == "2026-11-01" && mv$windows[["7"]]$compared_to == "2026-11-01",
      "no exact-date row -> nearest earlier date as compared_to")
it <- mv$windows[["1"]]$items
check(length(it) == 3 && it[[1]]$team == "NYK" && it[[1]]$delta == -5 && it[[2]]$team == "BOS",
      "sorted by absolute change")
check(is.na(mv$windows[["21"]]$compared_to) && !length(mv$windows[["21"]]$items), "not enough history -> empty list")
big <- data.frame(date = rep(c("2026-11-19", "2026-11-20"), each = 8), team = rep(LETTERS[1:8], 2),
                  metric = LD_METRIC, value = c(rep(0, 8), 1:8))
check(length(ld_movers(big)$windows[["1"]]$items) == 5, "top 5 only")
check(!length(ld_movers(big[big$date == "2026-11-20", ])$windows[["1"]]$items), "single day -> empty")
finish()
