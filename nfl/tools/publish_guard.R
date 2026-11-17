# ==============================================================================
# tools/publish_guard.R  (NFL_analytics#154)
#
# Classifies the dirty paths in the working tree for schedule_publish.bat's
# checkout guard.
#
# For the 04:15 pipeline, any dirty tree is stashed before it runs. For the publish
# step the pipeline's own output is the INPUT, so it must stay in place for
# tools/publish_web.R to check and commit. This script splits `git status` into:
#
#   output : paths under config.R's PIPELINE_OUTPUT_DIRS (the same vector
#            publish_web.R uses for assertion C and `git add`)
#   other  : everything else (code, config, docs, ...)
#
# CLI:  Rscript tools/publish_guard.R <other_out_file> <output_out_file>
#   Writes NUL-separated repo-relative paths to each file (for
#   `git stash push --pathspec-from-file=... --pathspec-file-nul`), prints one summary
#   line and exits 0. A non-zero exit means git could not be queried.
# ==============================================================================

#' Split `git status --porcelain=v1 -z` output into pipeline-output vs other paths.
#'
#' @param status_z Character vector: the NUL-split fields of the -z output.
#' @param output_dirs Repo-relative output directories.
#' @return list(output = chr, other = chr)
classify_dirty_paths <- function(status_z, output_dirs) {
  status_z <- status_z[nzchar(status_z)]
  paths <- character(0)
  i <- 1L
  while (i <= length(status_z)) {
    entry <- status_z[i]
    xy <- substr(entry, 1L, 2L)
    path <- substring(entry, 4L)
    paths <- c(paths, path)
    # Renames/copies carry the ORIGINAL path in the next field; it is dirty too.
    if (grepl("[RC]", xy)) {
      if (i + 1L <= length(status_z)) paths <- c(paths, status_z[i + 1L])
      i <- i + 2L
    } else {
      i <- i + 1L
    }
  }
  paths <- unique(gsub("\\\\", "/", paths))
  prefixes <- paste0(sub("/+$", "", gsub("\\\\", "/", output_dirs)), "/")
  is_output <- vapply(paths, function(p) any(startsWith(p, prefixes)), logical(1))
  list(output = paths[is_output], other = paths[!is_output])
}

# Read raw `git status -z` bytes and split on NUL (system2 drops NULs).
guard_status_fields <- function(repo_dir) {
  tmp <- tempfile("guard_status_")
  on.exit(unlink(tmp), add = TRUE)
  rc <- system2("git", c("-C", shQuote(repo_dir), "status", "--porcelain=v1", "-z", "-uall"),
                stdout = tmp, stderr = FALSE)
  if (!identical(as.integer(rc), 0L)) stop("git status failed with exit code ", rc)
  raw <- readBin(tmp, "raw", file.size(tmp))
  if (!length(raw)) return(character(0))
  cuts <- c(0L, which(raw == as.raw(0L)))
  fields <- vapply(seq_len(length(cuts) - 1L), function(k) {
    seg <- raw[(cuts[k] + 1L):cuts[k + 1L]]
    seg <- seg[seg != as.raw(0L)]
    rawToChar(seg)
  }, character(1))
  Encoding(fields) <- "UTF-8"
  fields
}

write_nul_list <- function(paths, file) {
  con <- file(file, "wb")
  on.exit(close(con), add = TRUE)
  for (p in paths) {
    writeBin(charToRaw(enc2utf8(p)), con)
    writeBin(as.raw(0L), con)
  }
  invisible(file)
}

if (sys.nframe() == 0L && !interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) != 2L) {
    cat("usage: Rscript tools/publish_guard.R <other_out_file> <output_out_file>\n")
    quit(status = 2L)
  }
  source("config.R")
  res <- tryCatch(
    classify_dirty_paths(guard_status_fields(getwd()), PIPELINE_OUTPUT_DIRS),
    error = function(e) { cat("[publish_guard] ERROR:", conditionMessage(e), "\n"); NULL }
  )
  if (is.null(res)) quit(status = 1L)
  write_nul_list(res$other, args[1])
  write_nul_list(res$output, args[2])
  cat(sprintf("[publish_guard] dirty paths: %d pipeline output (kept), %d other (to stash)\n",
              length(res$output), length(res$other)))
  quit(status = 0L)
}
