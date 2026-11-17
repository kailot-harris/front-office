# #171: the box cache is refreshed before the SHAP stage, with keep-on-failure semantics.
source("config.R")
source("tools/refresh_matchups_team_box.R")
fails <- 0L
chk <- function(l, ok) { cat(if (isTRUE(ok)) "[PASS] " else "[FAIL] ", l, "\n", sep = ""); if (!isTRUE(ok)) fails <<- fails + 1L }

p <- tempfile(fileext = ".rds"); old <- data.frame(game_id = "1", n = 1); saveRDS(old, p)
r <- refresh_matchups_team_box(2027L, p, function() data.frame(game_id = c("1", "2"), n = 1:2))
chk("successful pull overwrites cache", identical(r, "refreshed") && nrow(readRDS(p)) == 2L)
r <- refresh_matchups_team_box(2027L, p, function() stop("network down"))
chk("failed pull keeps cache", identical(r, "kept") && nrow(readRDS(p)) == 2L)
r <- refresh_matchups_team_box(2027L, p, function() data.frame())
chk("empty pull keeps cache", identical(r, "kept") && nrow(readRDS(p)) == 2L)
q <- tempfile(fileext = ".rds")
chk("failed pull with no cache reports missing, no throw", identical(refresh_matchups_team_box(2027L, q, function() stop("x")), "missing"))

# Wiring: the refresh stage must precede the SHAP stage in the pipeline.
pl <- readLines("run_full_pipeline.R", warn = FALSE)
rs <- grep('run_stage("tools/refresh_matchups_team_box.R"', pl, fixed = TRUE)
sh <- grep('run_stage("xgboost_shap_engine.R"', pl, fixed = TRUE)
mb <- grep('run_stage("build_matchups_dataset.R"', pl, fixed = TRUE)
chk("pipeline refreshes the box cache before SHAP, SHAP before matchups",
    length(rs) == 1L && length(sh) == 1L && length(mb) == 1L && rs < sh && sh < mb)
if (fails > 0L) quit(status = 1L)
cat("ALL PASSED\n")
