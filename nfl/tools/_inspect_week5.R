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
x <- readRDS("cache/projected_matchups.rds")
cat("cols:", paste(names(x), collapse=", "), "\n")
cat("weeks present:", paste(sort(unique(x$week)), collapse=","), "\n")
w5 <- x[x$week == 5, ]
cat("n week5 rows:", nrow(w5), "\n")
print(w5[order(-w5$home_win_prob), c("home_team","away_team","home_win_prob","projected_margin")])
