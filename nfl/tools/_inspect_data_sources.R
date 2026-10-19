setwd("c:/Users/kailo/kayceeslices/NFL Analytics")
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
