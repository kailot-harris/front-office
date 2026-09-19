# AGENTS.md — guidance for AI coding agents working in this repo

This file complements `CLAUDE.md` (project working notes/environment quirks). Read that
first for environment setup and data quirks; this file covers process guidance for how
an agent should safely operate on this repo, starting with one incident-driven rule.

## Testing scripts with real save side effects

**Incident (2026-09-19):** a one-off `.R` test script sourced the full
`prediction_accuracy_logger.R` (to unit-test `migrate_prediction_log()`'s classification
logic) after pre-setting local `PRED_LOG_RDS`/`PRED_LOG_CSV` variables to `tempfile()`
paths. Sourcing the production file re-ran `config.R`'s top-level assignment of the real
cache paths, silently overwriting the temp-path override. `migrate_prediction_log()` then
called its real `saveRDS(df, PRED_LOG_RDS)` / `write.csv(df, PRED_LOG_CSV)` against the
real paths — using a 4-row synthetic test dataframe — clobbering the real, 118-row
`cache/prediction_accuracy_log.rds`/`.csv`. Caught immediately via `git status` and
recovered with `git checkout --` only because the real file happened to already be
committed; a script run against uncommitted or newly-modified data would have lost it
permanently.

**Rule:** before sourcing any script that has real file-write side effects (`saveRDS`,
`write.csv`, `readr::write_*`, DB writes, etc.) purely to test one function in it:
1. Prefer calling the function with an explicit, injectable path/flag parameter over
   relying on a pre-set global surviving the source. If the function doesn't have one,
   add one (see `migrate_prediction_log(df, rds_path=, csv_path=, persist=)` in
   `prediction_accuracy_logger.R` for the pattern — defaults to the real production
   globals so no caller behavior changes, but a test can pass `persist = FALSE` or a
   temp path explicitly).
2. If adding a parameter isn't practical, verify the actual resolved value of every
   global save-path constant the function will use *immediately before calling it* —
   after sourcing, not before — since sourcing itself can silently reset your override.
3. When in doubt, checksum (`md5sum`) or diff the real cache file before and after
   running any test script that touches production code, so an accidental overwrite is
   caught immediately rather than discovered later.
4. `git status` after any test run that touched a script with save side effects, same as
   the existing pre-destructive-command habit — an unexpected `modified:` on a cache
   file is the tell.

This generalizes beyond `prediction_accuracy_logger.R`: any script in this repo that
`source()`s `config.R` inherits its cache-path constants as globals, and many of this
repo's engines (`market_odds_engine.R`, `rapm_engine.R`, `player_props_engine.R`, etc.)
have their own `saveRDS()`/cache-write calls gated only on those globals, not on
injectable parameters. Apply the same explicit-parameter pattern when adding tests for
them, rather than assuming a global override will hold.
