# #154: the ops Discord availability embed must read the scraper's own table
# (CACHE_INJURY_DATA, columns team_name/player_name/status), not a dead path.
NOTIFY_OPS_LIBRARY_ONLY <- TRUE
source("notify_pipeline_ops.R")
fails <- 0L
chk <- function(label, ok) { cat(if (isTRUE(ok)) "[PASS] " else "[FAIL] ", label, "\n", sep = ""); if (!isTRUE(ok)) fails <<- fails + 1L }

chk("empty table -> no embed", is.null(build_availability_embed(data.frame(team_name=character(), player_name=character(), status=character()))))
chk("NULL -> no embed", is.null(build_availability_embed(NULL)))
chk("only healthy -> no embed", is.null(build_availability_embed(data.frame(team_name="Boston Celtics", player_name="A B", status="Available", stringsAsFactors=FALSE))))
e <- build_availability_embed(data.frame(team_name="Boston Celtics", player_name="Jayson Tatum", status="Out", stringsAsFactors=FALSE))
chk("one Out row -> embed", is.list(e))
chk("real team name shown", grepl("Boston Celtics", e$description, fixed = TRUE))
chk("no placeholder 'Team'", !grepl("(Team)", e$description, fixed = TRUE))
chk("no betting terms", !grepl("bet|odds|wager|spread|parlay|sportsbook", paste(e$title, e$description), ignore.case = TRUE))
e2 <- build_availability_embed(data.frame(team_name=NA_character_, player_name="X Y", status="Doubtful", stringsAsFactors=FALSE))
chk("NA team does not print NA", !grepl("NA", e2$description, fixed = TRUE))
if (fails > 0L) quit(status = 1L)
cat("ALL PASSED\n")
