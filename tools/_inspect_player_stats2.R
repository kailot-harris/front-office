setwd("c:/Users/kailo/kayceeslices/NFL Analytics")
source("config.R")
ps <- nflreadr::load_player_stats(seasons = CURRENT_SEASON)
cat(paste(names(ps), collapse=", "), "\n")
qb <- ps[ps$position == "QB", ]
print(head(qb[order(-qb$passing_epa), c("player_display_name","week","team","passing_epa","attempts","completions","passing_tds","passing_interceptions")], 10))
