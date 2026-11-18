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
ps <- nflreadr::load_player_stats(seasons = CURRENT_SEASON, stat_type = "offense")
cat("ncol:", ncol(ps), " nrow:", nrow(ps), "\n")
print(grep("pass|qb|epa|name|position|team|week", names(ps), ignore.case = TRUE, value = TRUE))
qb <- ps[ps$position == "QB", ]
cat("QB rows:", nrow(qb), "distinct QBs:", length(unique(qb$player_display_name)), "\n")
print(head(qb[order(-qb$passing_epa), c("player_display_name","week","recent_team","passing_epa","attempts","passer_rating")], 10))
