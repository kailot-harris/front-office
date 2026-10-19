setwd("c:/Users/kailo/kayceeslices/NFL Analytics")
source("config.R")
sn <- nflreadr::load_snap_counts(seasons = CURRENT_SEASON)
cat(paste(names(sn), collapse=", "), "\n")
cat("nrow:", nrow(sn), "\n")
print(head(sn[, c("player","position","team","week","offense_pct","defense_pct")], 10))

ros <- readRDS(CACHE_ROSTERS)
rook <- ros[ros$entry_year == CURRENT_SEASON & ros$season == CURRENT_SEASON, ]
cat("distinct rookies in roster (season snapshot):", length(unique(rook$gsis_id)), "\n")
cat(paste(grep("gsis|pfr|espn", names(sn), ignore.case=TRUE, value=TRUE), collapse=", "), "\n")
