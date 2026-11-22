# tests/test_data_manifest_and_lag_gate.R  (front-office#102, front-office#191)
# Offline tests for tools/write_data_manifest.R and publish_web.R assertion H.
# Uses temp directories only; no network, no git, no schedules cache required.
failures <- 0L
ok <- function(label, cond) {
  if (isTRUE(cond)) cat(sprintf("[PASS] %s\n", label))
  else { cat(sprintf("[FAIL] %s\n", label)); failures <<- failures + 1L }
}
suppressPackageStartupMessages(library(jsonlite))
root <- normalizePath(getwd(), winslash = "/")
source("tools/publish_web.R")   # sources config.R and the manifest helpers
setwd(root)

ok("sourcing defines helpers without writing", exists("write_data_manifest", mode = "function") &&
     exists(".assert_manifest_and_coverage", mode = "function"))

# Synthetic payloads. `last_game` is the latest COMPLETED gameday in the
# schedule payload; `stamp` is the build stamp embedded in every stamped file.
mk <- function(last_game = "2026-11-15", stamp = "2026-11-16T05:00:00Z") {
  d <- tempfile("dm_"); dir.create(d)
  w <- function(f, x) writeLines(toJSON(x, auto_unbox = TRUE, null = "null"), file.path(d, f))
  lg <- as.Date(last_game)
  w("matchups_current_week.json", list(generated_at = stamp, matchups = list(
    list(week = 1, gameday = format(lg - 7), is_completed = TRUE),
    list(week = 2, gameday = format(lg), is_completed = TRUE),
    list(week = 3, gameday = format(lg + 7), is_completed = FALSE))))
  w("coaching_profiles.json", list(generated_at = stamp, season = 2026, through_week = 2))
  w("passing_metadata.json", list(updated_at = stamp))
  w("player_dna_profiles.json", list(season = 2026, throughWeek = 2, generatedAt = stamp))
  w("salary_cap_profiles.json", list(generated_at = "2025-03-01T00:00:00Z"))
  w("standings_projections.json", list(generated_at = stamp, teams = list()))
  writeLines('[{"a": 1}]', file.path(d, "passing_index.json"))
  d
}
now <- as.POSIXct("2026-11-16 06:00:00", tz = "UTC")
rd <- function(d) fromJSON(file.path(d, "data_manifest.json"), simplifyVector = FALSE)

# --- manifest builder ---------------------------------------------------------
d <- mk()
write_data_manifest(d, schedule_through_date = "2026-11-15", now = now)
m <- rd(d)
ok("manifest covers every top-level json (not itself)",
   setequal(names(m$datasets), setdiff(list.files(d, "[.]json$"), "data_manifest.json")))
ok("manifest top-level keys", m$schema_version == 1 && m$sport == "nfl" &&
     m$generated_at == "2026-11-16T06:00:00Z" && m$schedule_through_date == "2026-11-15")
ok("updated_at / generatedAt stamps are read as payload stamps",
   m$datasets$passing_metadata.json$stamp_source == "payload:updated_at" &&
     m$datasets$player_dna_profiles.json$stamp_source == "payload:generatedAt")
ok("through_date extracted from completed gamedays, not generated_at",
   m$datasets$matchups_current_week.json$through_date == "2026-11-15" &&
     startsWith(m$datasets$matchups_current_week.json$through_date_source, "payload:"))
ok("week-numbered payload resolved to that week's gameday",
   m$datasets$coaching_profiles.json$through_date == "2026-11-15" &&
     m$datasets$player_dna_profiles.json$through_date == "2026-11-15")
ok("non-game-dated payload: through_date null, source not_game_dated, coverage_note set",
   is.null(m$datasets$standings_projections.json$through_date) &&
     m$datasets$standings_projections.json$through_date_source == "not_game_dated" &&
     nzchar(m$datasets$standings_projections.json$coverage_note))
ok("salary cap is static with reason", isTRUE(m$datasets$salary_cap_profiles.json$static) &&
     nzchar(m$datasets$salary_cap_profiles.json$static_reason))
ok("every entry has a content_sha256", all(vapply(m$datasets, function(e) grepl("^[0-9a-f]{64}$", e$content_sha256), logical(1))))
ok("absent schedules cache => NA", is.na(dm_schedule_through_date(file.path(d, "nope.rds"))))

# --- content-hash carry-forward (FO#102) -------------------------------------
pi <- m$datasets$passing_index.json
ok("unstamped payload stamped by manifest:content_hash at writer run time",
   pi$stamp_source == "manifest:content_hash" && pi$generated_at == "2026-11-16T06:00:00Z")
later <- now + 86400
write_data_manifest(d, schedule_through_date = "2026-11-15", now = later)
m2 <- rd(d)
ok("same bytes -> generated_at carried forward", m2$datasets$passing_index.json$generated_at == "2026-11-16T06:00:00Z")
ok("nothing changed -> manifest top-level generated_at unchanged", m2$generated_at == m$generated_at)
writeLines('[{"a": 2}]', file.path(d, "passing_index.json"))
write_data_manifest(d, schedule_through_date = "2026-11-15", now = later)
m3 <- rd(d)
ok("changed bytes -> new stamp", m3$datasets$passing_index.json$generated_at == "2026-11-17T06:00:00Z")
ok("an entry changed -> manifest top-level generated_at advances", m3$generated_at == "2026-11-17T06:00:00Z")
src <- paste(readLines(file.path(root, "tools", "write_data_manifest.R")), collapse = "\n")
code <- gsub("#[^\n]*", "", src)
ok("manifest writer never calls file.info / file.mtime / file.size / git",
   !grepl("file\\.(info|mtime|size)\\s*\\(", code) && !grepl("\"git\"|system2?\\(", code))

d2 <- mk(); write_data_manifest(d2, schedule_through_date = NA_character_, now = now)
ok("unknown schedule date written as JSON null",
   grepl('"schedule_through_date": null', paste(readLines(file.path(d2, "data_manifest.json")), collapse = "\n")))

# --- schedules cache reader -----------------------------------------------------
rds <- tempfile(fileext = ".rds")
saveRDS(data.frame(season = c(2025, 2026, 2026, 2026), gameday = c("2026-01-04", "2026-11-09", "2026-11-16", "2026-11-23"),
                   result = c(3, 7, -2, NA)), rds)
ok("schedule through date = max completed gameday in season", dm_schedule_through_date(rds, 2026L) == "2026-11-16")

# --- assertion H ----------------------------------------------------------------
d <- mk(); write_data_manifest(d, schedule_through_date = "2026-11-15", now = now); m <- rd(d)
h <- .assert_manifest_and_coverage(d, schedule_through_date = "2026-11-15")
ok("fresh manifest passes H", isTRUE(h$pass) && h$id == "H" && isTRUE(h$fatal))
ok("dry-run detail lists every dataset",
   all(vapply(names(m$datasets), function(f) any(grepl(f, h$detail, fixed = TRUE)), logical(1))))
ok("game-dated line shows [OK] with through_date",
   any(grepl("[OK]", h$detail, fixed = TRUE) & grepl("through_date=2026-11-15", h$detail, fixed = TRUE)))
ok("not-game-dated line shows [UNDATED]", any(grepl("[UNDATED]", h$detail, fixed = TRUE) &
                                              grepl("standings_projections.json", h$detail, fixed = TRUE)))
ok("static dataset passes and is marked [STATIC]", any(grepl("[STATIC]", h$detail, fixed = TRUE) &
                                                       grepl("salary_cap_profiles.json", h$detail, fixed = TRUE)))

# FO#191 acceptance: rebuilt today from an out-of-date cache -> brand-new stamp,
# old content. The gate must fail on the game-dated payloads.
ds <- mk(last_game = "2026-10-11", stamp = "2026-11-16T05:00:00Z")
write_data_manifest(ds, schedule_through_date = "2026-11-15", now = now)
h <- .assert_manifest_and_coverage(ds, schedule_through_date = "2026-11-15")
ok("stale content with brand-new stamp FAILS H",
   !isTRUE(h$pass) && all(c("matchups_current_week.json", "coaching_profiles.json", "player_dna_profiles.json") %in% h$lagging) &&
     !"standings_projections.json" %in% h$lagging && !"salary_cap_profiles.json" %in% h$lagging)

h <- .assert_manifest_and_coverage(d, schedule_through_date = "2026-12-20")
ok("schedule far ahead: game-dated and undated both [LAGGING]", !isTRUE(h$pass) &&
     all(c("matchups_current_week.json", "standings_projections.json") %in% h$lagging) &&
     !"salary_cap_profiles.json" %in% h$lagging)

h <- .assert_manifest_and_coverage(d, schedule_through_date = "2026-02-08")
ok("off-season (schedule before through_date) passes", isTRUE(h$pass))

h <- .assert_manifest_and_coverage(d2, schedule_through_date = NA_character_)
ok("unknown schedule date: lag not enforced, passes", isTRUE(h$pass) && any(grepl("lag not enforced", h$detail)))

writeLines('{"generated_at": "2026-11-15T05:00:00Z"}', file.path(d, "brand_new.json"))
h <- .assert_manifest_and_coverage(d, schedule_through_date = "2026-11-15")
ok("unlisted file fails H with [MISSING]", !isTRUE(h$pass) && identical(h$missing, "brand_new.json"))
invisible(file.remove(file.path(d, "brand_new.json")))

wm <- function(x) writeLines(toJSON(x, auto_unbox = TRUE, null = "null"), file.path(d, "data_manifest.json"))
mm <- m; mm$datasets$standings_projections.json$generated_at <- "yesterday"; wm(mm)
h <- .assert_manifest_and_coverage(d, schedule_through_date = "2026-11-15")
ok("unstamped (non-ISO generated_at) entry fails H", !isTRUE(h$pass) && "standings_projections.json" %in% h$missing)

mm <- m; mm$datasets$matchups_current_week.json$through_date_source <- "generated_at"; wm(mm)
h <- .assert_manifest_and_coverage(d, schedule_through_date = "2026-11-15")
ok("through_date not sourced from payload fails H", !isTRUE(h$pass) && "matchups_current_week.json" %in% h$missing)

mm <- m; mm$datasets$salary_cap_profiles.json$static_reason <- NULL; wm(mm)
h <- .assert_manifest_and_coverage(d, schedule_through_date = "2026-11-15")
ok("static without static_reason fails H", !isTRUE(h$pass))

invisible(file.remove(file.path(d, "data_manifest.json")))
h <- .assert_manifest_and_coverage(d, schedule_through_date = "2026-11-15")
ok("absent manifest fails H", !isTRUE(h$pass) && any(grepl("[MISSING]", h$detail, fixed = TRUE)))

# --- check lookup by id -----------------------------------------------------------
ok(".pw_check finds a check by id regardless of position",
   identical(.pw_check(list(list(id = "H", v = 1), list(id = "G", v = 2)), "G")$v, 2) &&
     length(.pw_check(list(), "G")) == 0L)

# --- committed manifest -----------------------------------------------------------
h <- .assert_manifest_and_coverage(WEB_DATA_DIR, schedule_through_date = NA_character_)
ok("committed web/public/data manifest passes H (coverage)", isTRUE(h$pass))

unlink(c(d, d2, ds), recursive = TRUE)
cat(sprintf("\n%d failure(s)\n", failures))
# front-office#211 follow-up: an array catalog is stamped by its NEWEST item,
# not by item [0] (which made the NFL gallery catalog permanently "37 days old").
arr <- list(list(filename = "old.png", generated_at = "2026-10-13T06:04:38Z"),
            list(filename = "new.gif", generated_at = "2026-11-21T06:41:51Z"),
            list(filename = "mid.gif", generated_at = "2026-11-01T00:00:00Z"))
st <- dm_embedded_stamp(arr)
ok("array payload stamp is the newest item's generated_at",
   !is.null(st) && identical(st$value, "2026-11-21T06:41:51Z") && identical(st$field, "[max].generated_at"))
ok("object payload stamp is unchanged by the array rule",
   identical(dm_embedded_stamp(list(generated_at = "2026-11-16T05:00:00Z"))$field, "generated_at"))

quit(status = if (failures) 1L else 0L)
