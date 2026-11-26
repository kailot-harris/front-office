# tests/test_landing_digest_game_end.R - front-office#240: the slot B/C refresh
# keeps landing_digest.json current after each game ends. today rows carry
# results, a same-day refresh re-derives today, and after midnight ET the digest
# rolls forward to the new Eastern date. Offline (fake ESPN fetcher).
# Usage: Rscript tests/test_landing_digest_game_end.R
local({
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  source(file.path(dirname(normalizePath(f)), "landing_digest_helpers.R"), chdir = FALSE)
}, envir = globalenv())
source(file.path(REPO_ROOT, "tools", "refresh_live_results.R"))

utc <- function(x) as.POSIXct(x, tz = "UTC")
by_id <- function(rows) setNames(rows, vapply(rows, `[[`, "", "game_id"))
raw_of <- function(path) readBin(path, "raw", file.size(path))

# Payload in the shape refresh_live_results() patches.
write_payload <- function(m, path) {
  m$slate <- 1L
  m$predicted_winner <- ifelse(m$predicted_home_win_prob > 0.5, m$home_team, m$away_team)
  m$actual_margin <- ifelse(m$is_completed, m$home_score - m$away_score, NA_integer_)
  m$actual_winner <- ifelse(m$is_completed, ifelse(m$home_score > m$away_score, m$home_team, m$away_team), NA_character_)
  m$prediction_correct <- ifelse(m$is_completed, m$predicted_winner == m$actual_winner, NA)
  p <- list(season_start_date = "2026-10-20", season_end_date = "2027-04-11",
            completed_games = sum(m$is_completed), pending_games = sum(!m$is_completed), matchups = m,
            slates = data.frame(slate = 1L, graded_total = 0L, correct_total = 0L, accuracy_pct = NA_real_))
  writeLines(jsonlite::toJSON(p, auto_unbox = TRUE, na = "null", pretty = TRUE), path)
}

# Slot A digest with tip-off times from a schedule cache.
slot_a <- function(dir, mp, ids, starts, dates) {
  sched <- data.frame(game_id = ids, start_date = starts, status_type_name = "STATUS_SCHEDULED",
                      status_type_state = "pre", season_type = 2L, game_date = dates)
  sp <- file.path(dir, "sched.rds"); saveRDS(sched, sp)
  dp <- file.path(dir, "landing_digest.json")
  build_landing_digest(matchups_path = mp, schedule_path = sp, ratings_path = file.path(dir, "none.rds"),
                       history_path = file.path(dir, "h.csv"), out_path = dp,
                       now = utc("2026-11-20 14:00:00"))
  dp
}

none <- function(dates) data.frame(game_id = character(0), is_final = logical(0),
                                   home_score = integer(0), away_score = integer(0))
finals <- function(ids, hs, as_) function(dates) data.frame(game_id = ids, is_final = TRUE,
                                                            home_score = hs, away_score = as_)

# ------------------------------------------------------------------------------
cat("Slot A today rows carry the result fields, never today_pending\n")
d <- tempfile("ldge_"); dir.create(d)
m <- rbind(mrow("9", "2026-11-19", "MIA", "ORL", 0.80, 100, 90),
           mrow("1", "2026-11-20", "BOS", "NYK", 0.62),
           mrow("2", "2026-11-20", "LAL", "GSW", 0.40),
           mrow("3", "2026-11-21", "DEN", "PHX", 0.55))
mp <- file.path(d, "matchups_slates.json"); write_payload(m, mp)
dp <- slot_a(d, mp, c("9", "1", "2", "3"),
             c("2026-11-20T00:30Z", "2026-11-21T00:30Z", "2026-11-21T03:00Z", "2026-11-22T01:00Z"),
             c("2026-11-19", "2026-11-20", "2026-11-20", "2026-11-21"))
x <- jsonlite::fromJSON(dp, simplifyVector = FALSE)
t1 <- by_id(x$today)[["1"]]
check(all(c("final", "home_score", "away_score", "predicted_winner", "hit") %in% names(t1)),
      "slot A today row has final, home_score, away_score, predicted_winner, hit")
check(identical(t1$final, FALSE) && is.null(t1$home_score) && is.null(t1$away_score) && is.null(t1$hit),
      "slot A today row not final: scores and hit are null")
check(t1$predicted_winner == "BOS" && by_id(x$today)[["2"]]$predicted_winner == "GSW",
      "slot A today predicted_winner graded like yesterday")
check(is.null(x$today_pending), "slot A never writes today_pending")
check(identical(sort(names(t1)), sort(names(x$yesterday[[1]]))), "today and yesterday rows share one shape")

# ------------------------------------------------------------------------------
cat("Same-day refresh marks a finished today game final\n")
r <- refresh_live_results(dates = "2026-11-20", payload_path = mp, fetcher = finals("1", 110L, 100L),
                          today = as.Date("2026-11-20"), now = utc("2026-11-21 03:00:00"))  # 22:00 ET
x <- jsonlite::fromJSON(dp, simplifyVector = FALSE)
t <- by_id(x$today)
check(!is.null(r$digest) && x$slate_date == "2026-11-20", "same-day refresh rewrites the digest, slate unchanged")
check(isTRUE(t[["1"]]$final) && t[["1"]]$status == "final" && t[["1"]]$home_score == 110 &&
        t[["1"]]$away_score == 100 && isTRUE(t[["1"]]$hit), "finished today game is final with scores and hit")
check(t[["1"]]$start_time_utc == "2026-11-21T00:30:00Z" && t[["2"]]$start_time_utc == "2026-11-21T03:00:00Z",
      "start times carried from the slot A today rows")
check(identical(t[["2"]]$final, FALSE) && t[["2"]]$status == "scheduled" && is.null(t[["2"]]$hit),
      "unfinished today game stays scheduled with null hit")
check(x$record$season$games == 1, "record still through the day before slate_date")
check(is.null(x$today_pending), "same-day refresh writes no today_pending")

cat("No-change refresh leaves the file byte-identical\n")
b0 <- raw_of(dp); mt0 <- file.mtime(dp)
r <- refresh_live_results(dates = "2026-11-20", payload_path = mp, fetcher = finals("1", 110L, 100L),
                          today = as.Date("2026-11-20"), now = utc("2026-11-21 03:30:00"))
check(r$n_changed == 0 && is.null(r$digest), "no-change refresh reports the digest unchanged")
check(identical(raw_of(dp), b0) && identical(file.mtime(dp), mt0), "digest bytes and generated_at unchanged")

# ------------------------------------------------------------------------------
cat("Roll-over with rows for the new date\n")
r <- refresh_live_results(dates = "2026-11-20", payload_path = mp, fetcher = finals("2", 99L, 101L),
                          today = as.Date("2026-11-21"), now = utc("2026-11-21 06:30:00"))  # 01:30 ET
x <- jsonlite::fromJSON(dp, simplifyVector = FALSE)
y <- by_id(x$yesterday)
check(!is.null(r$digest) && x$slate_date == "2026-11-21", "slate_date moves to the new Eastern date")
check(identical(sort(names(y)), c("1", "2")) && isTRUE(y[["1"]]$final) && isTRUE(y[["2"]]$final) &&
        y[["2"]]$home_score == 99 && y[["2"]]$away_score == 101 && isTRUE(y[["2"]]$hit),
      "yesterday holds the finished games with scores and hits")
check(y[["1"]]$start_time_utc == "2026-11-21T00:30:00Z" && y[["2"]]$start_time_utc == "2026-11-21T03:00:00Z",
      "yesterday start times carried from the old today rows")
check(length(x$today) == 1 && x$today[[1]]$game_id == "3" && is.null(x$today[[1]]$start_time_utc) &&
        x$today[[1]]$status == "scheduled", "today = payload rows for the new date, unknown start time null")
check(is.null(x$today_pending), "roll-over with rows writes no today_pending")
check(x$record$season$games == 3 && x$record$season$hits == 3 &&
        sum(vapply(x$calibration, `[[`, 0L, "games")) == 3, "record and calibration through the new yesterday")
check(x$season_state == "regular" && identical(names(x$movers$windows), c("1", "7", "21")),
      "season_state and movers carried")

# ------------------------------------------------------------------------------
cat("Roll-over without rows sets today_pending; a later refresh with rows removes it\n")
d2 <- tempfile("ldge2_"); dir.create(d2)
m2 <- rbind(mrow("1", "2026-11-20", "BOS", "NYK", 0.62, 110, 100),
            mrow("2", "2026-11-20", "LAL", "GSW", 0.40))
mp2 <- file.path(d2, "matchups_slates.json"); write_payload(m2, mp2)
dp2 <- slot_a(d2, mp2, c("1", "2"), c("2026-11-21T00:30Z", "2026-11-21T03:00Z"), c("2026-11-20", "2026-11-20"))
r <- refresh_live_results(dates = "2026-11-20", payload_path = mp2, fetcher = none,
                          today = as.Date("2026-11-21"), now = utc("2026-11-21 06:30:00"))
x <- jsonlite::fromJSON(dp2, simplifyVector = FALSE)
txt <- paste(readLines(dp2), collapse = "\n")
check(r$n_changed == 0 && !is.null(r$digest), "roll-over runs even when no scores changed")
check(x$slate_date == "2026-11-21" && isTRUE(x$today_pending) && length(x$today) == 0 &&
        grepl('"today": []', txt, fixed = TRUE), "no rows for the new date: today [] and today_pending true")
check(length(x$yesterday) == 2 && isTRUE(by_id(x$yesterday)[["1"]]$final), "yesterday still filled on the roll-over")
m2 <- rbind(m2, mrow("4", "2026-11-21", "CHI", "DET", 0.66))
write_payload(m2, mp2)
r <- refresh_live_results(dates = "2026-11-20", payload_path = mp2, fetcher = none,
                          today = as.Date("2026-11-21"), now = utc("2026-11-21 08:00:00"))
x <- jsonlite::fromJSON(dp2, simplifyVector = FALSE)
check(is.null(x$today_pending) && length(x$today) == 1 && x$today[[1]]$game_id == "4",
      "later refresh with rows for the date removes today_pending")
finish()
