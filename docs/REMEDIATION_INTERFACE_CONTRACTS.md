# Phase 4 Interface Contracts

These names/types/signatures are fixed **before** Wave 2 starts so that `agent_engine`,
`agent_dashboard`, `agent_pipeline`, and `agent_props` — which run concurrently and do not see each
other's code — can build against them independently with zero runtime coordination. Do not rename
or reshape any of these without updating this file and re-notifying every consumer.

| Contract | Type / Signature | Writer(s) | Reader(s) |
|---|---|---|---|
| `WNBA_HCA` | `numeric`, `config.R` constant, value `2.40` | `agent_foundation` (Wave 1) | `agent_engine`, `agent_dashboard`, `agent_pipeline` |
| `%||%` (canonical) | `function(a, b)` using `is.na(a)[1]` hardened form, defined once in `logging_utils.R` | `agent_foundation` (Wave 1) | `agent_engine`, `agent_dashboard` (both delete their local copies) |
| `join_rapm_to_roster(rost, rapm)` | Returns a data frame keyed by `(team_abbreviation, player identity)` with at least `total_rapm`, using the `(team full name, normalized last name)` match. New file `rapm_join_utils.R`. | `agent_foundation` (Wave 1) | `agent_pipeline` (`roster_bottom_up_engine.R`), `agent_props` (`player_props_engine.R`) |
| `is_synthetic` | `logical` column on `prediction_accuracy_log.rds` (schema_version bump) | `agent_props` | `agent_dashboard` (Tab 8 filter) |
| `market_data_source` | `character`: `"LIVE_ODDS_API"` \| `"SYNTHETIC_FALLBACK"`, field on `fetch_market_odds()`'s return value and column on `prediction_accuracy_log.rds` | `agent_engine` (return value), `agent_props` (log column) | (consumed by a future reporting task, out of scope this phase) |
| `Win_Pct` | `numeric` proportion (`0.793`, not `"79.3%"`) in `projected_wnba_standings.rds` | `agent_pipeline` | `agent_dashboard` (formats with `scales::percent()` at display time) |
| `CACHE_PLAYER_PROPS` | existing `config.R` constant; becomes the **sole** write/read target for `latest_player_props.rds` | `agent_props` (write) | `agent_dashboard` (read) |
| `CACHE_TEAM_BOX` | existing `config.R` constant; `app.R` switches to reading it instead of a stale bare literal | (already exists, `config.R`) | `agent_dashboard` |

## Rules
- If an agent discovers mid-task that a contract needs to change shape, it must stop, update this
  file, and note the change in its Handoff Notes entry rather than silently diverging — a sibling
  agent may already be building against the old shape.
- No Wave 2 agent may introduce a *new* cross-agent contract without adding a row here first.
