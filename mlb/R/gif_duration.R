# ==============================================================================
# R/gif_duration.R
#
# gif_duration_ms(): length of one full loop of a GIF, from its frame delays.
# Shared, byte-identical across the sport repos (drift-checked by the aggregator),
# so keep it free of sport-specific code.
#
# Walks the GIF block structure (never byte-scans: image data can contain 21 F9).
# Each frame's delay is the last Graphic Control Extension delay seen before it
# (0 if none); a delay of 0 or 1 hundredths counts as 100 ms, as browsers do.
#
# @param path character(1) path to a .gif
# @return integer(1) milliseconds, or NA_integer_ if the file is missing, is not
#   a GIF, is truncated, or has no frames.
# ==============================================================================
gif_duration_ms <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path)) {
    return(NA_integer_)
  }
  size <- file.size(path)
  if (is.na(size) || size < 14) return(NA_integer_)
  bytes <- tryCatch(readBin(path, "raw", size), error = function(e) NULL, warning = function(w) NULL)
  if (is.null(bytes) || length(bytes) < 14) return(NA_integer_)
  n <- length(bytes)
  if (!(rawToChar(bytes[1:6]) %in% c("GIF87a", "GIF89a"))) return(NA_integer_)

  b <- as.integer(bytes)
  pos <- 14L  # 1-based index of the byte after header + logical screen descriptor
  if (bitwAnd(b[11], 0x80L) != 0L) {
    pos <- pos + 3L * bitwShiftL(1L, bitwAnd(b[11], 7L) + 1L)
  }

  # Skip data sub-blocks from `p` to just past the 0-length terminator; NA if truncated.
  skip_sub_blocks <- function(p) {
    repeat {
      if (p > n) return(NA_integer_)
      len <- b[p]
      p <- p + 1L + len
      if (len == 0L) return(p)
    }
  }

  delays <- integer(0)
  pending <- 0L
  repeat {
    if (pos > n) return(NA_integer_)  # ran off the end without a trailer
    intro <- b[pos]
    if (intro == 0x3BL) break
    if (intro == 0x21L) {
      if (pos + 1L > n) return(NA_integer_)
      if (b[pos + 1L] == 0xF9L) {
        if (pos + 5L > n) return(NA_integer_)
        pending <- b[pos + 4L] + 256L * b[pos + 5L]
      }
      pos <- skip_sub_blocks(pos + 2L)
    } else if (intro == 0x2CL) {
      if (pos + 9L > n) return(NA_integer_)
      packed <- b[pos + 9L]
      pos <- pos + 10L
      if (bitwAnd(packed, 0x80L) != 0L) pos <- pos + 3L * bitwShiftL(1L, bitwAnd(packed, 7L) + 1L)
      pos <- pos + 1L  # LZW minimum code size
      pos <- skip_sub_blocks(pos)
      delays <- c(delays, pending)
      pending <- 0L
    } else {
      return(NA_integer_)
    }
    if (is.na(pos)) return(NA_integer_)
  }

  if (length(delays) == 0L) return(NA_integer_)
  delays[delays <= 1L] <- 10L
  as.integer(sum(delays) * 10L)
}
