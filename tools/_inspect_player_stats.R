setwd("c:/Users/kailo/kayceeslices/NFL Analytics")
source("config.R")
ps <- nflreadr::load_player_stats(seasons = CURRENT_SEASON, stat_type = "offense")
cat("ncol:", ncol(ps), " nrow:", nrow(ps), "\n")
print(grep("pass|qb|epa|name|position|team|week", names(ps), ignore.case = TRUE, value = TRUE))
qb <- ps[ps$position == "QB", ]
cat("QB rows:", nrow(qb), "distinct QBs:", length(unique(qb$player_display_name)), "\n")
print(head(qb[order(-qb$passing_epa), c("player_display_name","week","recent_team","passing_epa","attempts","passer_rating")], 10))
