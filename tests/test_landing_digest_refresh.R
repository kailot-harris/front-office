# tests/test_landing_digest_refresh.R - NBA#211: slots B/C patch yesterday,
# record and calibration in landing_digest.json. Offline (fake ESPN fetcher).
# Usage: Rscript tests/test_landing_digest_refresh.R
local({
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  source(file.path(dirname(normalizePath(f)), "landing_digest_helpers.R"), chdir = FALSE)
}, envir = globalenv())
source(file.path(REPO_ROOT, "tools", "refresh_live_results.R"))

d <- tempfile("ldr_"); dir.create(d)
m <- rbind(mrow("1", "2026-11-19", "BOS", "NYK", 0.62, NA, NA),
           mrow("2", "2026-11-19", "LAL", "GSW", 0.40, NA, NA),
           mrow("9", "2026-11-18", "MIA", "ORL", 0.80, 100, 90))
m$slate <- 1L; m$predicted_winner <- c("BOS", "GSW", "MIA")
m$actual_margin <- NA_integer_; m$actual_winner <- NA_character_; m$prediction_correct <- NA
m$actual_margin[3] <- 10L; m$actual_winner[3] <- "MIA"; m$prediction_correct[3] <- TRUE
p <- list(season_start_date = "2026-10-20", season_end_date = "2027-04-11",
          completed_games = 1L, pending_games = 2L, matchups = m,
          slates = data.frame(slate = 1L, graded_total = 1L, correct_total = 1L, accuracy_pct = 100))
mp <- file.path(d, "matchups_slates.json")
writeLines(jsonlite::toJSON(p, auto_unbox = TRUE, na = "null", pretty = TRUE), mp)

# Slot A digest built the morning before games went final.
dp <- file.path(d, "landing_digest.json")
build_landing_digest(matchups_path = mp, schedule_path = NULL, ratings_path = file.path(d, "none.rds"),
                     history_path = file.path(d, "h.csv"), out_path = dp,
                     now = as.POSIXct("2026-11-20 12:00:00", tz = "UTC"))
before <- jsonlite::fromJSON(dp, simplifyVector = FALSE)
check(before$record$season$games == 1 && !before$yesterday[[1]]$final, "fixture: yesterday pending before refresh")
before$today <- list(list(game_id = "keep-me"))
writeLines(jsonlite::toJSON(before, auto_unbox = TRUE, null = "null", na = "null", pretty = TRUE), dp)

fake <- function(dates) data.frame(game_id = c("1", "2"), is_final = TRUE,
                                   home_score = c(110L, 99L), away_score = c(100L, 101L))
r <- refresh_live_results(dates = "2026-11-19", payload_path = mp, fetcher = fake, today = as.Date("2026-11-20"),
                          now = as.POSIXct("2026-11-20 20:00:00", tz = "UTC"))
check(r$n_changed == 2 && identical(normalizePath(r$digest), normalizePath(dp)), "refresh reports the digest as rewritten")
x <- jsonlite::fromJSON(dp, simplifyVector = FALSE)
y <- setNames(x$yesterday, vapply(x$yesterday, `[[`, "", "game_id"))
check(isTRUE(y[["1"]]$final) && y[["1"]]$home_score == 110 && isTRUE(y[["1"]]$hit), "yesterday patched with score and hit")
check(isTRUE(y[["2"]]$hit) && y[["2"]]$predicted_winner == "GSW", "away pick graded")
check(x$record$season$games == 3 && x$record$season$hits == 3 && x$record$last_7$games == 3, "record recomputed")
check(sum(vapply(x$calibration, `[[`, 0L, "games")) == 3, "calibration recomputed")
check(length(x$today) == 0 && x$slate_date == "2026-11-20" && is.null(x$today_pending),
      "same-day refresh keeps slate_date and re-derives today from the payload")
r2 <- refresh_live_results(dates = "2026-11-19", payload_path = mp, fetcher = fake, today = as.Date("2026-11-20"),
                          now = as.POSIXct("2026-11-20 20:00:00", tz = "UTC"))
check(r2$n_changed == 0, "re-run is a no-op")
finish()
