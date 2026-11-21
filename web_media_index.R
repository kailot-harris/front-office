# ==============================================================================
# web_media_index.R
#
# Pure builder for web/public/data/visual_media_index.json items. Sourced by
# export_web_datasets.R (real cache/ files and the media_metadata list) and by
# tests/test_visual_media_index.R (fixtures). Needs R/gif_duration.R sourced.
#
# Per item: generated_at is that file's OWN modification time (UTC ISO-8601), never
# the run's start time; duration_ms is one GIF loop (NA -> JSON null when the GIF
# cannot be read) and is absent for images. Files with no entry in `metadata` are
# logged with warning() and omitted: no placeholder item is ever written.
# ==============================================================================

#' @param files    character vector of file paths that exist on disk
#' @param metadata named list keyed by basename: list(title, category, desc)
#' @return list of items (possibly empty)
build_media_index <- function(files, metadata) {
  index <- list()
  for (f in files) {
    bname <- basename(f)
    if (!file.exists(f)) {
      warning(sprintf("build_media_index: %s does not exist - omitted from visual_media_index", bname),
              call. = FALSE)
      next
    }
    meta <- metadata[[bname]]
    if (is.null(meta)) {
      warning(sprintf("build_media_index: no metadata for %s - omitted from visual_media_index", bname),
              call. = FALSE)
      next
    }
    is_gif <- grepl("\\.gif$", bname, ignore.case = TRUE)
    item <- list(
      generated_at = format(file.mtime(f), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      filename     = bname,
      title        = meta$title,
      category     = meta$category,
      description  = meta$desc,
      type         = if (is_gif) "gif" else "image",
      size_bytes   = file.size(f)
    )
    if (is_gif) item$duration_ms <- gif_duration_ms(f)
    index[[length(index) + 1L]] <- item
  }
  index
}
