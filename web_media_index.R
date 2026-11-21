# ==============================================================================
# web_media_index.R
#
# Pure builder for web/public/data/visual_media_index.json items. Sourced by
# export_web_datasets.R (real cache/ files and the media_metadata list) and by
# tests/test_visual_media_index.R (fixtures). Needs R/gif_duration.R and
# R/media_generated_at.R sourced.
#
# Per item: generated_at is when that file was really built (UTC ISO-8601), never the
# run's start time: media_generated_at() (R/media_generated_at.R) on the published copy
# in `published_dir` when it holds the same bytes (tracked + unchanged -> the time of the
# last commit that changed it, i.e. its PUBLISH time, which may be later than the render
# but never makes an old file look new after a copy or fresh clone), else on the file
# itself (re-rendered or untracked -> its mtime). The git state of `published_dir` is read
# once per call (media_git_state()), not per file; duration_ms is one GIF loop (NA -> JSON null when the GIF
# cannot be read) and is absent for images. Files with no entry in `metadata` are
# logged with warning() and omitted: no placeholder item is ever written.
# ==============================================================================

#' @param files    character vector of file paths that exist on disk
#' @param metadata named list keyed by basename: list(title, category, desc)
#' @param published_dir optional directory holding the published copies (WEB_ANIM_DIR)
#' @param repo     git repo root for media_generated_at()
#' @return list of items (possibly empty)
build_media_index <- function(files, metadata, published_dir = NULL, repo = ".") {
  index <- list()
  git_state <- if (!is.null(published_dir) && length(files)) media_git_state(published_dir, repo) else NULL
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
      generated_at = .media_index_stamp(f, published_dir, repo, git_state),
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

# Date the published copy when it is byte-identical to `f` (its git history is the honest
# record); otherwise `f` itself.
.media_index_stamp <- function(f, published_dir, repo, git_state = NULL) {
  if (!is.null(published_dir)) {
    pub <- file.path(published_dir, basename(f))
    if (file.exists(pub) && file.size(pub) == file.size(f) &&
        identical(readBin(pub, "raw", file.size(pub)), readBin(f, "raw", file.size(f)))) {
      return(media_generated_at(pub, repo = repo, git_state = git_state))
    }
  }
  media_generated_at(f, repo = repo)
}
