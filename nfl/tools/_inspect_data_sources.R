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

cat("=== CACHE_ROSTERS columns ===\n")
ros <- readRDS(CACHE_ROSTERS)
print(names(ros))
cat("entry_year / rookie_year candidates present?\n")
cat(paste(grep("year|rookie|exp", names(ros), ignore.case = TRUE, value = TRUE), collapse=", "), "\n")
cat("sample rows for rookies (entry_year == CURRENT_SEASON if exists):\n")
if ("entry_year" %in% names(ros)) {
  print(table(ros$entry_year == CURRENT_SEASON))
}
if ("years_exp" %in% names(ros)) {
  print(table(ros$years_exp, useNA="always")[1:5])
}

cat("\n=== CACHE_PBP relevant columns ===\n")
pbp <- readRDS(CACHE_PBP)
cat(paste(grep("passer|qb|epa", names(pbp), ignore.case = TRUE, value = TRUE), collapse=", "), "\n")
cat("season range:", paste(range(pbp$season), collapse="-"), "\n")
cur <- pbp[pbp$season == CURRENT_SEASON & !is.na(pbp$passer_player_name) & pbp$pass == 1, ]
cat("current season pass plays:", nrow(cur), "\n")
print(head(sort(table(cur$passer_player_name), decreasing = TRUE), 15))
