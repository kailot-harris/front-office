# ==============================================================================
# tests/test_phase5_maintenance.R
# Path: tests/test_phase5_maintenance.R
#
# Validation suite for Phase 5 Media Publishing & Issue #45 Maintenance Purge:
#   1. Sourcing and export validation for tools/purge_stale_media_assets.R and
#      tools/publish_web.R.
#   2. Validates publish_web media synchronization:
#      - Verifies that cache/*.gif and cache/*.png files are copied to web/public/media/.
#      - Verifies that .pw_sync_media(dry_run = TRUE) previews files without mutating disk.
#      - Verifies that .pw_sync_media(dry_run = FALSE) writes target files.
#   3. Validates purge_stale_media_assets:
#      - Age classification logic (0-30 days kept, 31-60 days purged, >60 days purged).
#      - Protection of canonical assets (^gif_elo_rank_bump, ^gif_net_rating_quadrant,
#        ^gif_point_diff_race) even when aged 45 or 90 days.
#      - Dry-run mode reports would-be purged files without deleting them from disk.
#      - Live purge mode removes 31-60 day files while keeping canonical and active assets intact.
#
# Usage:
#   Rscript tests/test_phase5_maintenance.R
# ==============================================================================

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  if (file.exists(file.path(base, "tools", "purge_stale_media_assets.R"))) {
    normalizePath(base, winslash = "/", mustWork = FALSE)
  } else if (file.exists(file.path(base, "..", "tools", "purge_stale_media_assets.R"))) {
    normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
  } else {
    getwd()
  }
})

cat("=== Phase 5 & Issue #45 Maintenance Test Suite ===\n")
cat(sprintf("Working root: %s\n", REPO_ROOT))

# ------------------------------------------------------------------------------
# Test 1: Sourcing and Function Existence
# ------------------------------------------------------------------------------
cat("\n[Test 1] Sourcing tools/publish_web.R and tools/purge_stale_media_assets.R...\n")
publish_script <- file.path(REPO_ROOT, "tools", "publish_web.R")
purge_script   <- file.path(REPO_ROOT, "tools", "purge_stale_media_assets.R")

stopifnot(file.exists(publish_script))
stopifnot(file.exists(purge_script))

source(publish_script)
source(purge_script)

stopifnot(exists(".pw_sync_media", mode = "function"))
stopifnot(exists("publish_web", mode = "function"))
stopifnot(exists("purge_stale_media_assets", mode = "function"))
stopifnot(exists("classify_media_asset", mode = "function"))
stopifnot(exists("is_canonical_asset", mode = "function"))
cat("  PASS: Scripts exist, source cleanly, and export expected functions.\n")

# ------------------------------------------------------------------------------
# Test 2: Media Synchronization (.pw_sync_media)
# ------------------------------------------------------------------------------
cat("\n[Test 2] Testing media synchronization into web/public/media/...\n")
temp_cache <- file.path(tempdir(), "test_phase5_cache")
temp_web_media <- file.path(tempdir(), "test_phase5_web_media")
if (dir.exists(temp_cache)) unlink(temp_cache, recursive = TRUE)
if (dir.exists(temp_web_media)) unlink(temp_web_media, recursive = TRUE)
dir.create(temp_cache, recursive = TRUE)
dir.create(temp_web_media, recursive = TRUE)

# Create mock media in cache
writeLines("mock gif 1", file.path(temp_cache, "anim1.gif"))
writeLines("mock png 1", file.path(temp_cache, "still1.png"))
writeLines("mock txt", file.path(temp_cache, "notes.txt")) # Non-media, should not sync

# Mock environment variables/paths for test
assign("CACHE_DIR", temp_cache, envir = .GlobalEnv)
assign("WEB_MEDIA_DIR", temp_web_media, envir = .GlobalEnv)

# Dry run test
dry_synced <- .pw_sync_media(dry_run = TRUE)
stopifnot(length(dry_synced) == 2L)
stopifnot(!file.exists(file.path(temp_web_media, "anim1.gif")))
stopifnot(!file.exists(file.path(temp_web_media, "still1.png")))
cat("  PASS: Dry-run preview identified 2 media files and did not modify target.\n")

# Live sync test
live_synced <- .pw_sync_media(dry_run = FALSE)
stopifnot(length(live_synced) == 2L)
stopifnot(file.exists(file.path(temp_web_media, "anim1.gif")))
stopifnot(file.exists(file.path(temp_web_media, "still1.png")))
stopifnot(!file.exists(file.path(temp_web_media, "notes.txt")))
cat("  PASS: Live sync copied all media (.gif / .png) files to target directory.\n")

# Cleanup mock env
unlink(temp_cache, recursive = TRUE)
unlink(temp_web_media, recursive = TRUE)

# Re-establish repo WEB_MEDIA_DIR
assign("CACHE_DIR", file.path(REPO_ROOT, "cache"), envir = .GlobalEnv)
assign("WEB_MEDIA_DIR", file.path(REPO_ROOT, "web", "public", "media"), envir = .GlobalEnv)

# ------------------------------------------------------------------------------
# Test 3: Asset Classification and Canonical Protection Logic
# ------------------------------------------------------------------------------
cat("\n[Test 3] Testing asset age classification and canonical protection...\n")
test_file_dir <- file.path(tempdir(), "test_phase5_classify")
if (dir.exists(test_file_dir)) unlink(test_file_dir, recursive = TRUE)
dir.create(test_file_dir, recursive = TRUE)

# Helper to create file with specific age in days
create_aged_file <- function(name, days_old) {
  p <- file.path(test_file_dir, name)
  writeLines(sprintf("content of %s", name), p)
  mtime <- Sys.time() - (days_old * 86400)
  Sys.setFileTime(p, mtime)
  p
}

# 1. Canonical asset aged 45 days (in 31-60 day range) -> MUST BE PROTECTED (KEEP)
p_canon_45 <- create_aged_file("gif_elo_rank_bump.gif", 45)
cl_canon_45 <- classify_media_asset(p_canon_45)
stopifnot(identical(cl_canon_45$is_canonical, TRUE))
stopifnot(identical(cl_canon_45$action, "KEEP"))
stopifnot(identical(cl_canon_45$status, "PROTECTED_CANONICAL"))

# 2. Canonical asset aged 75 days (> 60 days) -> MUST BE PROTECTED (KEEP)
p_canon_75 <- create_aged_file("gif_net_rating_quadrant.png", 75)
cl_canon_75 <- classify_media_asset(p_canon_75)
stopifnot(identical(cl_canon_75$is_canonical, TRUE))
stopifnot(identical(cl_canon_75$action, "KEEP"))

# 3. Canonical asset point diff race aged 50 days -> MUST BE PROTECTED (KEEP)
p_canon_50 <- create_aged_file("gif_point_diff_race.gif", 50)
cl_canon_50 <- classify_media_asset(p_canon_50)
stopifnot(identical(cl_canon_50$is_canonical, TRUE))
stopifnot(identical(cl_canon_50$action, "KEEP"))

# 4. Non-canonical asset aged 10 days (<= 30 days) -> ACTIVE WINDOW (KEEP)
p_active_10 <- create_aged_file("daily_shot_chart_20261019.png", 10)
cl_active_10 <- classify_media_asset(p_active_10)
stopifnot(identical(cl_active_10$is_canonical, FALSE))
stopifnot(identical(cl_active_10$action, "KEEP"))
stopifnot(identical(cl_active_10$status, "ACTIVE_WINDOW"))

# 5. Non-canonical asset aged 40 days (31-60 days) -> PURGE WINDOW (PURGE)
p_stale_40 <- create_aged_file("daily_shot_chart_20260919.png", 40)
cl_stale_40 <- classify_media_asset(p_stale_40)
stopifnot(identical(cl_stale_40$is_canonical, FALSE))
stopifnot(identical(cl_stale_40$action, "PURGE"))
stopifnot(identical(cl_stale_40$status, "PURGE_WINDOW"))

# 6. Non-canonical asset aged 70 days (> 60 days) -> PURGE WINDOW (PURGE)
p_stale_70 <- create_aged_file("old_simulation_frame_001.gif", 70)
cl_stale_70 <- classify_media_asset(p_stale_70)
stopifnot(identical(cl_stale_70$is_canonical, FALSE))
stopifnot(identical(cl_stale_70$action, "PURGE"))
cat("  PASS: Age classification correctly identifies active, stale (31-60d), and protected canonical assets.\n")

# ------------------------------------------------------------------------------
# Test 4: End-to-End Purge Execution (Dry-Run and Live)
# ------------------------------------------------------------------------------
cat("\n[Test 4] Executing purge routine in dry-run and live modes...\n")

# Dry run test on test_file_dir
res_dry <- purge_stale_media_assets(target_dirs = test_file_dir, dry_run = TRUE)
stopifnot(length(res_dry$purged) == 2L) # p_stale_40 and p_stale_70
stopifnot(length(res_dry$kept) == 4L)   # p_canon_45, p_canon_75, p_canon_50, p_active_10
# Verify that all files STILL exist on disk (dry-run should NOT delete)
stopifnot(file.exists(p_stale_40))
stopifnot(file.exists(p_stale_70))
stopifnot(file.exists(p_canon_45))
stopifnot(file.exists(p_active_10))
cat("  PASS: Dry-run reported correct purge counts without deleting any files.\n")

# Live purge test on test_file_dir
res_live <- purge_stale_media_assets(target_dirs = test_file_dir, dry_run = FALSE)
stopifnot(length(res_live$purged) == 2L)
stopifnot(length(res_live$kept) == 4L)
# Verify that purged files are gone
stopifnot(!file.exists(p_stale_40))
stopifnot(!file.exists(p_stale_70))
# Verify that protected and active files remain
stopifnot(file.exists(p_canon_45))
stopifnot(file.exists(p_canon_75))
stopifnot(file.exists(p_canon_50))
stopifnot(file.exists(p_active_10))
cat("  PASS: Live purge successfully deleted 31-60d stale assets while preserving canonical and active files.\n")

# Cleanup temporary classification directory
unlink(test_file_dir, recursive = TRUE)

# ------------------------------------------------------------------------------
# Test 5: Integration with live workspace cache and publish_web()
# ------------------------------------------------------------------------------
cat("\n[Test 5] Validating workspace cache media protection and publish_web dry-run...\n")
res_ws_dry <- purge_stale_media_assets(dry_run = TRUE)
# Any assets currently in cache (canonical) must be KEPT
for (cl in res_ws_dry$classified) {
  if (cl$is_canonical) {
    stopifnot(cl$action == "KEEP")
  }
}

pub_res <- publish_web(dry_run = TRUE)
stopifnot(!is.null(pub_res$synced_media))
cat(sprintf("  PASS: publish_web dry-run reported %d synced media assets.\n", length(pub_res$synced_media)))

cat("\n================================================================\n")
cat(">>> ALL PHASE 5 & MAINTENANCE TESTS PASSED SUCCESSFULLY! <<<\n")
cat("================================================================\n")
