# ==============================================================================
# test_offseason_memo_milestones_encoding.R
# Unit tests for the off-season memo's Block 4 milestone bucketing (run-date
# aware) and for locale-independent em dashes in the rendered memo.
# ==============================================================================

# ------------------------------------------------------------------------------
# Root-resolution prelude (Issue #90 Working Directory Trap)
# ------------------------------------------------------------------------------
args_all <- commandArgs(trailingOnly = FALSE)
f <- sub("^--file=", "", args_all[grepl("^--file=", args_all)])
if (length(f) == 1 && nzchar(f) && file.exists(f)) {
  cand <- normalizePath(dirname(dirname(dirname(f))), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(cand, "config.R"))) setwd(cand)
}
cur <- getwd()
while (!file.exists(file.path(cur, "config.R")) && dirname(cur) != cur) {
  cur <- dirname(cur)
}
if (file.exists(file.path(cur, "config.R"))) setwd(cur)

suppressPackageStartupMessages({
  library(testthat)
})

source(file.path("tools", "offseason", "render_memo.R"))

LOTTERY_URL <- "https://www.espn.com/wnba/story/_/id/50497107/toronto-tempo-win-2027-wnba-draft-lottery"
SEASON_URL <- "https://www.espn.com/wnba/story/_/id/50466261/sources-2027-wnba-season-start-7"

# Same shape the builder passes to the renderer (date NULL = Date TBD), with the
# events seeded by tools/offseason/capture_baseline_s0.R.
seeded_milestones <- function() {
  list(
    list(date = "2026-11-15",
         event = sprintf("2027 WNBA Draft Lottery: Toronto Tempo won the No. 1 pick, Houston Comets No. 2 (ESPN, 2026-11-15, %s)", LOTTERY_URL),
         status = "Confirmed"),
    list(date = NULL, event = "Free Agency Qualifying Offer & Core Designation Filing Window", status = "Tentative"),
    list(date = NULL, event = "Free Agency Negotiation & Contract Execution Period", status = "Tentative"),
    list(date = "2027-04-12", event = "2027 WNBA Draft", status = "Confirmed"),
    list(date = "2027-04-25", event = "2027 Training Camps Open (Hand-off to Daily In-Season Pipeline)", status = "Tentative"),
    list(date = "2027-05-07",
         event = sprintf("2027 WNBA season window, reported, not confirmed: expected to open May 7 and end no later than Oct. 24 (reported by ESPN 2026-11-13, %s)", SEASON_URL),
         status = "Tentative")
  )
}

block_lines <- function(txt) strsplit(txt, "\n", fixed = TRUE)[[1]]

test_that("Block 4 for a 2026-11-23 run: lottery recently passed, TBD kept, 2027 dates on Later line", {
  b4 <- render_block_4_milestones(seeded_milestones(), run_date = as.Date("2026-11-23"))
  cat("\n---- rendered Block 4 (run date 2026-11-23) ----\n", b4, "\n------------------------------------------------\n", sep = "")
  ln <- block_lines(b4)

  expect_identical(ln[1], "### 4. Next 30 Days (Milestone Calendar)")

  # The past lottery is never listed as upcoming ...
  expect_false(any(grepl("^- \\[ \\] 2026-11-15", ln)))
  # ... and sits under "Recently passed" with its sourced result.
  rp <- which(ln == "**Recently passed:**")
  expect_length(rp, 1L)
  lottery_line <- sprintf("- [x] 2026-11-15: 2027 WNBA Draft Lottery: Toronto Tempo won the No. 1 pick, Houston Comets No. 2 (ESPN, 2026-11-15, %s)", LOTTERY_URL)
  expect_identical(ln[rp + 1L], lottery_line)

  # Date TBD items stay under the 30-day heading.
  expect_true("- [ ] [Date TBD]: Free Agency Qualifying Offer & Core Designation Filing Window" %in% ln)
  expect_true("- [ ] [Date TBD]: Free Agency Negotiation & Contract Execution Period" %in% ln)

  # Dated items beyond 30 days are on exactly one "Later" line, in date order,
  # and never as their own upcoming checkbox.
  later <- ln[grepl("^- \\*\\*Later:\\*\\* ", ln)]
  expect_length(later, 1L)
  expect_true(grepl("2027-04-12: 2027 WNBA Draft; 2027-04-25: 2027 Training Camps Open", later, fixed = TRUE))
  expect_true(grepl("2027-05-07: 2027 WNBA season window, reported, not confirmed", later, fixed = TRUE))
  expect_true(grepl(SEASON_URL, later, fixed = TRUE))
  expect_false(any(grepl("^- \\[ \\] 2027-", ln)))
  expect_lt(which(grepl("^- \\*\\*Later:\\*\\*", ln)), rp)
})

test_that("Block 4 lists dated items inside 30 days and drops items passed more than 14 days ago", {
  ms <- seeded_milestones()
  # 2026-11-02 run: lottery is 13 days ahead, so it is upcoming.
  b_early <- block_lines(render_block_4_milestones(ms, run_date = "2026-11-02"))
  expect_true(any(grepl("^- \\[ \\] 2026-11-15: 2027 WNBA Draft Lottery", b_early)))
  expect_false(any(b_early == "**Recently passed:**"))

  # 2026-11-29 run: 14 days after the lottery, still recently passed.
  b_edge <- block_lines(render_block_4_milestones(ms, run_date = "2026-11-29"))
  expect_true(any(grepl("^- \\[x\\] 2026-11-15", b_edge)))

  # 2026-11-30 run: 15 days after, dropped entirely.
  b_late <- block_lines(render_block_4_milestones(ms, run_date = "2026-11-30"))
  expect_false(any(grepl("2026-11-15", b_late)))
  expect_false(any(b_late == "**Recently passed:**"))

  # 2027-03-20 run: the draft (23 days out) is upcoming; camps and season window are Later.
  b_spring <- block_lines(render_block_4_milestones(ms, run_date = "2027-03-20"))
  expect_true("- [ ] 2027-04-12: 2027 WNBA Draft" %in% b_spring)
  expect_true(any(grepl("^- \\*\\*Later:\\*\\* 2027-04-25", b_spring)))
})

test_that("Block 4 handles empty input and JSON-style empty dates", {
  b_empty <- render_block_4_milestones(list(), run_date = "2026-11-23")
  expect_identical(block_lines(b_empty)[2], "- No milestones scheduled in the next 30 days.")

  # jsonlite reads a baseline "date": {} as an empty list; that is Date TBD.
  b_json <- render_block_4_milestones(list(list(date = setNames(list(), character(0)), event = "X")),
                                      run_date = "2026-11-23")
  expect_identical(block_lines(b_json)[2], "- [ ] [Date TBD]: X")
})

test_that("render_7_block_memo passes its publish date to Block 4", {
  memo <- render_7_block_memo(week_number = 2, publish_date = "2026-11-23",
                              elapsed_days = 16, baseline_date = "2026-11-07",
                              upcoming_milestones = seeded_milestones())$markdown
  expect_true(grepl("- [x] 2026-11-15: 2027 WNBA Draft Lottery", memo, fixed = TRUE))
  expect_false(grepl("- [ ] 2026-11-15", memo, fixed = TRUE))
})

test_that("Memo header has a real em dash when rendered under a Windows-1252 locale", {
  old_ctype <- Sys.getlocale("LC_CTYPE")
  set_ok <- suppressWarnings(Sys.setlocale("LC_CTYPE", "English_United States.1252"))
  skip_if(!nzchar(set_ok), "Windows-1252 locale not available on this machine")
  on.exit(suppressWarnings(Sys.setlocale("LC_CTYPE", old_ctype)), add = TRUE)

  # Re-source the renderer while the non-UTF-8 locale is active, the way
  # Rscript reads it when the session's native code page is 1252.
  env <- new.env()
  sys.source(file.path("tools", "offseason", "render_memo.R"), envir = env)
  memo <- env$render_7_block_memo(week_number = 2, publish_date = "2026-11-23",
                                  elapsed_days = 16, baseline_date = "2026-11-07")$markdown
  header <- block_lines(memo)[1]
  header_utf8 <- enc2utf8(header)
  cat("\nLC_CTYPE during render: ", Sys.getlocale("LC_CTYPE"), "\n", sep = "")
  cat("header code points: ", paste(sprintf("U+%04X", utf8ToInt(header_utf8)[9:13]), collapse = " "), "\n", sep = "")

  expect_true(grepl("\u2014", header_utf8, fixed = TRUE))
  expect_false(grepl("\u00e2\u20ac", header_utf8, fixed = TRUE))
  expect_identical(header_utf8, "## Week 2 \u2014 Monday, 23 November 2026")
})
