# tests/test_landing_digest_build.R - NBA#210: slot A landing digest, hit rule,
# manifest coverage. Offline. Usage: Rscript tests/test_landing_digest_build.R
local({
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  source(file.path(dirname(normalizePath(f)), "landing_digest_helpers.R"), chdir = FALSE)
}, envir = globalenv())

cat("Hit rule\n")
g <- ld_grade("BOS", "NYK", 0.62, 110, 100, TRUE)
check(isTRUE(g$hit) && g$graded && g$predicted_winner == "BOS", "win at >50% is a hit")
g <- ld_grade("BOS", "NYK", 0.62, 90, 100, TRUE)
check(identical(g$hit, FALSE) && g$graded, "loss at >50% is a miss")
g <- ld_grade("BOS", "NYK", 0.30, 90, 100, TRUE)
check(isTRUE(g$hit) && g$predicted_winner == "NYK", "away pick (home <50%) graded on away")
g <- ld_grade("BOS", "NYK", 0.5, 110, 100, TRUE)
check(is.na(g$hit) && g$excluded && !g$graded && is.na(g$predicted_winner), "exactly 50% -> null, excluded")
g <- ld_grade("BOS", "NYK", 0.7, 100, 100, TRUE)
check(is.na(g$hit) && g$excluded && !g$graded, "tie -> null, excluded")
g <- ld_grade("BOS", "NYK", 0.7, NA, NA, FALSE, "postponed")
check(is.na(g$hit) && g$excluded, "postponed -> null, excluded")
g <- ld_grade("BOS", "NYK", 0.7, NA, NA, FALSE, "cancelled")
check(is.na(g$hit) && g$excluded, "cancelled -> null, excluded")
g <- ld_grade("BOS", "NYK", 0.7, NA, NA, FALSE, "scheduled")
check(is.na(g$hit) && !g$excluded && !g$graded, "pending -> null, not counted")

cat("Build on a fixture\n")
d <- tempfile("ld_"); dir.create(d)
m <- rbind(mrow("1", "2026-11-19", "BOS", "NYK", 0.62, 110, 100),
           mrow("2", "2026-11-19", "LAL", "GSW", 0.40, 99, 101),
           mrow("3", "2026-11-19", "DEN", "PHX", 0.55, NA, NA),
           mrow("4", "2026-11-20", "MIA", "ORL", 0.58),
           mrow("5", "2026-11-20", "CHI", "DET", 0.66, logged = FALSE))
p <- list(season_start_date = "2026-10-20", season_end_date = "2027-04-11", matchups = m)
mp <- file.path(d, "matchups_slates.json"); writeLines(jsonlite::toJSON(p, auto_unbox = TRUE, na = "null"), mp)
sched <- data.frame(game_id = c("1", "2", "3", "4", "5"),
                    start_date = c("2026-11-20T00:30Z", "2026-11-20T03:00Z", "2026-11-20T02:00Z", "2026-11-21T00:00Z", "2026-11-21T01:00Z"),
                    status_type_name = c("STATUS_FINAL", "STATUS_FINAL", "STATUS_POSTPONED", "STATUS_SCHEDULED", "STATUS_SCHEDULED"),
                    status_type_state = c("post", "post", "pre", "pre", "pre"), season_type = 2L,
                    game_date = c(rep("2026-11-19", 3), rep("2026-11-20", 2)))
sp <- file.path(d, "sched.rds"); saveRDS(sched, sp)
out <- file.path(d, "landing_digest.json")
now <- as.POSIXct("2026-11-20 17:00:00", tz = "UTC")
r <- build_landing_digest(matchups_path = mp, schedule_path = sp, ratings_path = file.path(d, "none.rds"),
                          history_path = file.path(d, "h.csv"), out_path = out, now = now)
x <- jsonlite::fromJSON(out, simplifyVector = FALSE)
check(all(c("schema_version", "sport", "generated_at", "slate_date", "season_state", "next_milestone",
            "today", "yesterday", "record", "calibration", "movers") %in% names(x)), "all contract fields present")
check(x$slate_date == "2026-11-20" && x$season_state == "regular" && x$next_milestone$date == "2027-04-11",
      "slate date (US Eastern), season_state and milestone")
check(length(x$today) == 2 && x$today[[1]]$start_time_utc == "2026-11-21T00:00:00Z", "today rows with UTC start")
check(x$today[[2]]$prediction_status == "not_yet_run" && is.null(x$today[[2]]$home_win_prob),
      "unlogged game listed with null probability, never invented")
y <- setNames(x$yesterday, vapply(x$yesterday, `[[`, "", "game_id"))
check(isTRUE(y[["1"]]$hit) && isTRUE(y[["2"]]$hit), "yesterday hits graded")
check(y[["3"]]$status == "postponed" && is.null(y[["3"]]$hit), "postponed game -> hit null")
check(x$record$season$games == 2 && x$record$season$hits == 2 && x$record$season$excluded == 1,
      "record counts the postponed game as excluded")
check(identical(names(x$movers$windows), c("1", "7", "21")), "movers windows 1/7/21")

cat("Manifest + betting guard\n")
Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")
source(file.path(REPO_ROOT, "tools", "write_data_manifest.R"))
e <- DM_COVERAGE[["landing_digest.json"]](x)
check(e$date == "2026-11-19" && e$source == "payload:yesterday[final].game_date", "through_date from the latest final in yesterday")
e2 <- DM_COVERAGE[["landing_digest.json"]](list(yesterday = list()))
check(is.na(e2$date), "no final -> no through_date (not_game_dated path)")
check(!is.null(DM_SPEC[["landing_digest.json"]]), "digest registered in DM_SPEC")
check(inherits(try(ld_assert_no_betting(list(a = "moneyline")), silent = TRUE), "try-error"), "betting term refused")
txt <- tolower(paste(readLines(file.path(REPO_ROOT, "web/public/data/landing_digest.json")), collapse = ""))
check(!grepl("odds|spread|moneyline|over/under", txt), "committed digest carries no betting terms")
finish()
