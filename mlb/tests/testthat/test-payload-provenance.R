if (!file.exists("config.R")) {
  proj_dir <- if (file.exists("../../config.R")) {
    normalizePath("../..", winslash = "/")
  } else {
    stop("Cannot locate the project root: no config.R at ./ or ../../. Run tests from the repo root or from tests/testthat/.", call. = FALSE)
  }
  setwd(proj_dir)
}

suppressPackageStartupMessages({
  library(testthat)
  library(jsonlite)
})

# ------------------------------------------------------------------------------
# Payload provenance stamping.
#
# tools/publish_web.R's assertion F is the only check in the gate that can see
# staleness assertion A is structurally blind to (A reads mtimes, and any git
# checkout refreshes an mtime over unchanged bytes). F works by reading a
# `generated_at` key out of each payload, and it does that by scanning only the
# FIRST 4096 BYTES of the file, because these payloads reach 1.2 MB and
# slurping them through jsonlite on every scheduled run to reach one scalar
# would be wasted time.
#
# That 4096-byte window makes the stamp's POSITION load-bearing: a payload
# whose stamp is written last is, to F, a payload with no stamp at all -- and F
# reports an unstamped payload as "cannot speak for", which PASSES. So the
# failure mode this file guards is silent: the exporter looks stamped, the gate
# looks green, and provenance is not actually being checked.
#
# These tests therefore assert on the three things that have to hold together:
# the stamp parses, it is recognised as fresh against a run start, and it is
# still found once the payload is realistically large. The negative control at
# the bottom is the point of the file -- it proves the window is real.
#
# Stamped at: tools/export_web_data.R (metadata, matchups_index, diagnostics,
# postseason_ops), mlb_series_simulator.R, mlb_player_dna_engine.R,
# mlb_clutch_leverage_engine.R, mlb_cbt_payroll_engine.R.
#
# Deliberately NOT stamped: projections_season_teams.json and
# projections_season_players.json are top-level JSON arrays (write_json of a
# data frame), which have no root object to hold a scalar key. See the KNOWN
# GAP note in tools/publish_web.R's header.
# ------------------------------------------------------------------------------

# The format every stamp site writes. One definition, so a drift in the
# exporters shows up here rather than 24 hours later in an unattended run.
STAMP_FMT <- "%Y-%m-%dT%H:%M:%SZ"
make_stamp <- function(t = Sys.time()) format(t, STAMP_FMT, tz = "UTC")

# Verbatim copy of .pw_payload_generated_at() from tools/publish_web.R.
#
# Copied rather than sourced on purpose: sourcing publish_web.R executes a gate
# that reads git state and the scheduled-run log. The copy is the thing under
# test, so if the gate's reader changes and this does not, these tests keep
# passing while the gate stops working -- which is why the format string and
# the 4096 default are asserted against the real file below.
pw_payload_generated_at <- function(path, head_bytes = 4096L) {
  if (!file.exists(path)) return(NA)
  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw <- readBin(con, "raw", n = head_bytes)
  txt <- rawToChar(raw[raw != as.raw(0)])
  Encoding(txt) <- "UTF-8"
  m <- regmatches(txt, regexpr('"generated_at"[[:space:]]*:[[:space:]]*"[^"]+"', txt))
  if (!length(m)) return(NA)
  val <- sub('^.*:[[:space:]]*"([^"]+)".*$', "\\1", m[1])
  as.POSIXct(val, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
}

# Big enough that anything not near the top of the document falls outside the
# 4096-byte window, which is the condition the real payloads all satisfy.
bulk_rows <- function(n = 4000) {
  lapply(seq_len(n), function(i) {
    list(id = i, name = paste0("player_", i), value = i / 7)
  })
}

write_payload <- function(obj, how = c("write_json", "toJSON")) {
  how <- match.arg(how)
  f <- tempfile(fileext = ".json")
  if (how == "toJSON") {
    # The idiom the four engine files use.
    write(toJSON(obj, auto_unbox = TRUE, pretty = TRUE), f)
  } else {
    # The idiom tools/export_web_data.R uses.
    jsonlite::write_json(obj, f, pretty = TRUE, auto_unbox = TRUE)
  }
  f
}

test_that("the gate still reads a 4096-byte head and the documented format", {
  gate <- readLines("tools/publish_web.R", warn = FALSE)

  # If either of these fails, the exporters and the gate have drifted apart and
  # the rest of this file is testing a reader the gate no longer uses.
  expect_true(any(grepl("head_bytes = 4096L", gate, fixed = TRUE)),
              info = "assertion F's head window changed; update bulk_rows() and this file's reasoning")
  expect_true(any(grepl('as.POSIXct(val, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")',
                        gate, fixed = TRUE)),
              info = "assertion F's parse format changed; update STAMP_FMT and every exporter stamp site")
})

test_that("a stamp written first is found and parsed in every payload shape", {
  run_start <- Sys.time() - 60

  shapes <- list(
    # mlb_series_simulator.R - generated_at first, local-time updatedAt retained
    list(label = "playoff_series_matchups",
         obj = list(generated_at = make_stamp(),
                    updatedAt = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                    nSims = 10000, teams = bulk_rows(), matchups = bulk_rows()),
         how = "toJSON"),
    # mlb_cbt_payroll_engine.R
    list(label = "cbt_payroll_sheet",
         obj = list(generated_at = make_stamp(), season = "2026",
                    baseThreshold = 244, teams = bulk_rows()),
         how = "write_json"),
    # tools/export_web_data.R - stamp first in the literal
    list(label = "projections_postseason_ops",
         obj = list(generated_at = make_stamp(), season = 2026L,
                    n_sims = 10000L, bracket = bulk_rows()),
         how = "write_json"),
    # tools/export_web_data.R - stamp PREPENDED with c() to an object built in
    # one of two branches upstream
    list(label = "projections_diagnostics",
         obj = c(list(generated_at = make_stamp()),
                 list(totalResolvedGames = 2430L, overallAccuracy = 0.566,
                      calibration = bulk_rows())),
         how = "write_json")
  )

  for (sh in shapes) {
    f <- write_payload(sh$obj, sh$how)
    on.exit(unlink(f), add = TRUE)

    g <- pw_payload_generated_at(f)
    expect_false(is.na(g),
                 info = sprintf("%s: no generated_at in the first 4096 bytes", sh$label))
    expect_true(g >= run_start,
                info = sprintf("%s: stamp did not read as fresh against run start", sh$label))

    # The payload has to stay valid JSON of the same root type for the web app.
    whole <- jsonlite::fromJSON(f, simplifyVector = FALSE)
    expect_type(whole, "list")
    expect_equal(names(whole)[1], "generated_at",
                 info = sprintf("%s: generated_at is no longer the first key", sh$label))

    # And the stamp must not be the only thing that survived.
    expect_gt(length(whole), 1L)
  }
})

test_that("c() prepend preserves the object it is prepended to", {
  # The diagnostics payload is built in two separate branches upstream, so the
  # stamp is prepended at the write site rather than added to both literals.
  # This asserts that does not reorder or drop anything.
  built <- list(totalResolvedGames = 2430L, overallAccuracy = 0.566,
                calibrationStatus = "OPTIMAL")
  stamped <- c(list(generated_at = make_stamp()), built)

  expect_equal(names(stamped), c("generated_at", names(built)))
  expect_equal(stamped[names(built)], built)
})

test_that("a stamp written LAST is invisible to the gate (negative control)", {
  # This is the failure this file exists to catch. If this test ever passes by
  # finding the stamp, the 4096-byte window has changed and the position rule
  # in every exporter is no longer load-bearing -- which would be good news,
  # but it has to be a deliberate change, not a discovery.
  f <- write_payload(c(list(teams = bulk_rows()),
                       list(generated_at = make_stamp())))
  on.exit(unlink(f), add = TRUE)

  expect_gt(file.info(f)$size, 4096)
  expect_true(is.na(pw_payload_generated_at(f)),
              info = "a trailing stamp was found, so the head-scan window is no longer 4096 bytes")

  # ...and it IS there if you read the whole document, so the test is about
  # position, not about the stamp being absent.
  whole <- jsonlite::fromJSON(f, simplifyVector = FALSE)
  expect_false(is.null(whole$generated_at))
})

test_that("an unstamped payload is reported, not silently passed", {
  # The two array payloads look like this. F must return NA for them so that
  # .assert_payload_provenance() counts them as "carry no stamp" and names
  # them, rather than treating them as fresh.
  f <- write_payload(bulk_rows(50))
  on.exit(unlink(f), add = TRUE)

  expect_true(is.na(pw_payload_generated_at(f)))
})
