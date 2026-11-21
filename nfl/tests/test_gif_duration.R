# tests/test_gif_duration.R
# Offline tests for R/gif_duration.R: gif_duration_ms() reads one loop's length
# from a GIF's frame delays. GIFs are built byte-by-byte into tempfile()s.
# Shared file: identical in every sport repo.
failures <- 0L
ok <- function(label, cond) {
  if (isTRUE(cond)) cat(sprintf("[PASS] %s\n", label))
  else { cat(sprintf("[FAIL] %s\n", label)); failures <<- failures + 1L }
}
source("R/gif_duration.R")

# Default image data: one 2-byte sub-block.
plain_data <- list(as.raw(c(0x44, 0x01)))

# Colour table of 3 * 2^(n+1) bytes.
colour_table <- function(n) as.raw(rep(0x7F, 3L * 2L^(n + 1L)))

# Frame spec: list(delay = hundredths or NULL for "no GCE", local_ct = NULL or n,
# data = list of raw sub-block payloads, pre = raw bytes placed before the frame).
frame_bytes <- function(f) {
  d <- f$delay
  gce <- if (is.null(d)) raw(0) else
    as.raw(c(0x21, 0xF9, 0x04, 0x00, d %% 256, d %/% 256, 0x00, 0x00))
  packed <- if (is.null(f$local_ct)) 0x00 else bitwOr(0x80L, as.integer(f$local_ct))
  desc <- as.raw(c(0x2C, 0, 0, 0, 0, 1, 0, 1, 0, packed))
  ct <- if (is.null(f$local_ct)) raw(0) else colour_table(f$local_ct)
  data <- if (is.null(f$data)) plain_data else f$data
  blocks <- unlist(lapply(data, function(p) c(as.raw(length(p)), p)))
  c(if (is.null(f$pre)) raw(0) else f$pre, gce, desc, ct, as.raw(0x02), blocks, as.raw(0x00))
}

# `frames`: list of frame specs. `global_ct`: NULL or n (flag 0x80, size bits n).
# `trailer = FALSE` leaves the 0x3B off; `truncate_at` cuts the file to that many bytes.
make_gif <- function(frames, global_ct = NULL, trailer = TRUE, truncate_at = NULL) {
  packed <- if (is.null(global_ct)) 0x00 else bitwOr(0x80L, as.integer(global_ct))
  header <- c(charToRaw("GIF89a"), as.raw(c(1, 0, 1, 0, packed, 0, 0)))
  ct <- if (is.null(global_ct)) raw(0) else colour_table(global_ct)
  bytes <- c(header, ct, unlist(lapply(frames, frame_bytes)),
             if (trailer) as.raw(0x3B) else raw(0))
  if (!is.null(truncate_at)) bytes <- bytes[seq_len(truncate_at)]
  path <- tempfile(fileext = ".gif")
  writeBin(bytes, path)
  path
}
fr <- function(delay, ...) c(list(delay = delay), list(...))
file_len <- function(p) file.size(p)

ok("two frames, delays 50 and 70 -> 1200", identical(gif_duration_ms(make_gif(list(fr(50), fr(70)))), 1200L))
ok("frame delay 0 counts as 100 ms", identical(gif_duration_ms(make_gif(list(fr(0)))), 100L))
ok("frame delay 1 counts as 100 ms", identical(gif_duration_ms(make_gif(list(fr(1)))), 100L))
ok("frame delay 2 is taken as is (20 ms)", identical(gif_duration_ms(make_gif(list(fr(2)))), 20L))
ok("no GCE -> each frame 100 ms", identical(gif_duration_ms(make_gif(list(fr(NULL), fr(NULL)))), 200L))
ok("GCE applies to its own frame only (delay, then none)",
   identical(gif_duration_ms(make_gif(list(fr(50), fr(NULL)))), 600L))

# Colour tables: sizes must be skipped exactly or the walk lands mid-table.
ok("global colour table (flag 0x80, n=1 -> 12 bytes) is skipped",
   identical(gif_duration_ms(make_gif(list(fr(50), fr(70)), global_ct = 1)), 1200L))
ok("global colour table with n=7 (768 bytes) is skipped",
   identical(gif_duration_ms(make_gif(list(fr(50)), global_ct = 7)), 500L))
ok("local colour table on a frame is skipped",
   identical(gif_duration_ms(make_gif(list(fr(50, local_ct = 2), fr(70)))), 1200L))
ok("global and local colour tables together",
   identical(gif_duration_ms(make_gif(list(fr(30, local_ct = 3), fr(40, local_ct = 0)), global_ct = 2)), 700L))

# Block-walk, not byte-scan: image data may contain 21 F9 04 .. which is not a GCE.
decoy <- as.raw(c(0x21, 0xF9, 0x04, 0x00, 0x63, 0x00, 0x00, 0x00))
ok("21 F9 bytes inside image data do not count as a delay",
   identical(gif_duration_ms(make_gif(list(fr(50, data = list(decoy)), fr(70)))), 1200L))
ok("a frame with two data sub-blocks",
   identical(gif_duration_ms(make_gif(list(fr(50, data = list(as.raw(1:5), decoy)), fr(70)))), 1200L))

# Application extension (NETSCAPE2.0 loop block) before the first frame.
netscape <- c(as.raw(c(0x21, 0xFF, 0x0B)), charToRaw("NETSCAPE2.0"),
              as.raw(c(0x03, 0x01, 0x00, 0x00, 0x00)))
ok("21 FF application extension before the first frame is skipped",
   identical(gif_duration_ms(make_gif(list(fr(50, pre = netscape), fr(70)))), 1200L))
comment_ext <- as.raw(c(0x21, 0xFE, 0x03, 0x61, 0x62, 0x63, 0x00))
ok("21 FE comment extension is skipped",
   identical(gif_duration_ms(make_gif(list(fr(50, pre = comment_ext)))), 500L))

# NA cases.
not_gif <- tempfile(fileext = ".gif")
writeBin(charToRaw("this is definitely not a gif file"), not_gif)
ok("non-GIF file -> NA", is.na(gif_duration_ms(not_gif)))
ok("missing file -> NA", is.na(gif_duration_ms(tempfile(fileext = ".gif"))))

full <- make_gif(list(fr(50), fr(70)))
n_full <- file_len(full)
ok("truncated inside the image descriptor -> NA",
   is.na(gif_duration_ms(make_gif(list(fr(50), fr(70)), truncate_at = n_full - 12L))))
# Cut inside the last frame's data sub-block (trailer + 0 terminator + 1 data byte removed).
ok("truncated inside sub-block data -> NA",
   is.na(gif_duration_ms(make_gif(list(fr(50), fr(70)), truncate_at = n_full - 3L))))
ok("truncated in the first frame's sub-block data -> NA",
   is.na(gif_duration_ms(make_gif(list(fr(50, data = list(as.raw(1:10)))), truncate_at = 13L + 8L + 10L + 5L))))
ok("trailer (0x3B) missing -> NA", is.na(gif_duration_ms(make_gif(list(fr(50), fr(70)), trailer = FALSE))))
ok("header only (no frames) -> NA", is.na(gif_duration_ms(make_gif(list()))))
ok("truncated inside a global colour table -> NA",
   is.na(gif_duration_ms(make_gif(list(fr(50)), global_ct = 7, truncate_at = 100L))))

if (failures > 0L) { cat(sprintf("\n%d FAILURE(S)\n", failures)); quit(status = 1L) }
cat("\nAll gif_duration tests passed.\n")
