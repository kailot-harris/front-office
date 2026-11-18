setwd(local({
  # Repo root: NFL_PROJECT_DIR if set, else this script's parent directory (it lives in
  # tools/), else the working directory if it holds config.R. No hard-coded fallback.
  env_root <- Sys.getenv("NFL_PROJECT_DIR", "")
  f <- sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
  f <- gsub("~+~", " ", f, fixed = TRUE)
  script_root <- if (length(f) == 1L) {
    dirname(dirname(normalizePath(f, winslash = "/", mustWork = FALSE)))
  } else ""
  root <- if (nzchar(env_root)) {
    env_root
  } else if (nzchar(script_root) && file.exists(file.path(script_root, "config.R"))) {
    script_root
  } else if (file.exists("config.R")) {
    getwd()
  } else {
    stop("Cannot locate the NFL Analytics project root: set NFL_PROJECT_DIR or run from the repo root.")
  }
  normalizePath(root, winslash = "/", mustWork = FALSE)
}))
source("config.R")
sn <- nflreadr::load_snap_counts(seasons = CURRENT_SEASON)
cat(paste(names(sn), collapse=", "), "\n")
cat("nrow:", nrow(sn), "\n")
print(head(sn[, c("player","position","team","week","offense_pct","defense_pct")], 10))

ros <- readRDS(CACHE_ROSTERS)
rook <- ros[ros$entry_year == CURRENT_SEASON & ros$season == CURRENT_SEASON, ]
cat("distinct rookies in roster (season snapshot):", length(unique(rook$gsis_id)), "\n")
cat(paste(grep("gsis|pfr|espn", names(sn), ignore.case=TRUE, value=TRUE), collapse=", "), "\n")
