# ==============================================================================
# pipeline_stages.R
# Path: pipeline_stages.R
#
# GitHub issue #45 (kailot-harris/WNBA_analytics) — Slice 1 of issue #43's tree. Pure
# representation refactor: this file centralizes the stage metadata that used to be
# hardcoded as 20 separate run_stage() call sites (18 distinct scripts; 2 of the 18 --
# prediction_accuracy_logger.R and rapm_engine.R via the parallel groups below -- are wired
# at two DAG points each) directly inside run_full_pipeline.R. Zero change to runtime
# behavior is intended here: every field below evaluates to exactly the same value the
# pre-refactor run_stage() call it replaces passed for `script`, `description`,
# `call_fn`/`entry_fn`, and `output` (same literal strings, or the same config.R
# symbol/expression where the original call site used one -- e.g. `output = CACHE_FEATURES`
# stays the bare symbol CACHE_FEATURES here, not a quoted copy of its name, so it still
# resolves to config.R's actual current path), plus one NEW field, `inputs`, documented
# below.
#
# SOURCING ORDER REQUIREMENT: this file must be source()'d AFTER config.R (which defines
# CACHE_DIR, CACHE_TEAM_BOX, CACHE_PLAYER_BOX, CACHE_FEATURES, CACHE_INJURY_DATA,
# CACHE_PLAYER_PROPS, CACHE_EMBEDDINGS, CACHE_SIMILARITY, CACHE_PLAYER_PBP_FEATURES) --
# several `output`/`inputs` entries below reference those symbols directly (unquoted) so
# they evaluate to config.R's real current paths, exactly like the original run_stage()
# call sites did.
#
# WHY A REGISTRY: this is the foundation every later slice of issue #43 depends on -- e.g.
# #47 (dependency-staleness detection) needs a machine-readable input->stage edge list,
# which cannot be derived from run_stage() call sites alone.
#
# SHAPE: `PIPELINE_STAGES` is a named list of stage-entry lists, in DAG execution order.
# Each entry has:
#   - id          : unique stage identifier (used by run_full_pipeline.R to look up this
#                   entry at its DAG point; NOT a filename, since prediction_accuracy_logger.R
#                   needs two distinct entries keyed separately, one per call_fn).
#   - script      : script filename, exactly as passed to run_stage() before.
#   - description : the human-readable description string, exactly as passed before.
#   - call_fn     : (optional, mutually exclusive with entry_fn) exactly as passed before.
#   - entry_fn    : (optional, mutually exclusive with call_fn) exactly as passed before.
#   - output      : (optional) evaluates to exactly the value the original call site passed
#                   -- NULL where the original call site had no `output =` argument at all
#                   (see each entry's own comment for why, carried over from
#                   run_full_pipeline.R's pre-refactor comments).
#   - inputs      : NEW. Character vector (possibly empty, character(0)) of the real
#                   upstream cache/file paths this stage's script actually reads via
#                   readRDS()/read.csv()/pd.read_csv(), derived by reading that stage's own
#                   script body -- NOT guessed from DAG position. Each entry's comment cites
#                   the exact script.R:line the read call lives at. A script that only hits a
#                   live API (no upstream file dependency) is `character(0)`, not omitted --
#                   omission would be indistinguishable from "not yet checked".
#   - group       : (optional) NULL for a free-standing run_stage() call, or one of
#                   "latent_engines" / "props_engines" for the two DAG points that are
#                   executed via future_lapply() inside the existing plan(multisession)/
#                   plan(sequential) block in run_full_pipeline.R. Grouping is REPRESENTATION
#                   ONLY -- run_full_pipeline.R still calls future_lapply() over the group's
#                   members at exactly the same two DAG points; this field is what lets it
#                   look the group up from the registry instead of an inline list literal.
# ==============================================================================

PIPELINE_STAGES <- list(

  # ---------------------------------------------------------------------------------------
  # 0. Pre-flight Data Integrity Check
  # FINDING C-2 (extension found by agent_pipeline, NOT in the review's list of four): this
  # file's footer is `if (sys.nframe() == 0)` too, so stage 0 was a FIFTH silent no-op -- it
  # defined check_cache_health() and returned without running a single check.
  # tools/data_health_probe.R is outside agent_pipeline's Wave 2 file ownership, so rather
  # than edit it, the entry point is invoked explicitly here via the existing `call_fn`
  # mechanism.
  # ---------------------------------------------------------------------------------------
  data_health_probe = list(
    id          = "data_health_probe",
    script      = "tools/data_health_probe.R",
    description = "Run Data Health Probe",
    call_fn     = "check_cache_health",
    entry_fn    = NULL,
    output      = NULL,
    # inputs: check_cache_health()'s own caches_to_check list (data_health_probe.R:34-41),
    # readRDS'd inside its per-path loop (data_health_probe.R:73, 94).
    inputs      = c(CACHE_TEAM_BOX, CACHE_PLAYER_BOX, CACHE_FEATURES, CACHE_INJURY_DATA,
                     CACHE_PLAYER_PROPS, file.path(CACHE_DIR, "projected_wnba_standings.rds")),
    group       = NULL
  ),

  # ---------------------------------------------------------------------------------------
  # 0.5. Box-Score Ingestion
  # FINDING L-4 (docs/SECURITY_TECHNICAL_REVIEW.md): daily_ingest.R was never a DAG stage;
  # box-score ingestion happened only as an implicit side effect of
  # prediction_accuracy_logger.R sourcing daily_ingest.R. Placed after the health probe and
  # before the IO block that loads the caches this stage refreshes.
  #
  # TWO DELIBERATE CHOICES, per agent_props' spec -- do not "tidy" either one:
  #  1. `call_fn`, NOT `entry_fn` -- daily_ingest.R's own footer guard is
  #     `sys.nframe() == 0`, which stays dormant under run_stage()'s source(); firing it via
  #     entry_fn AND the footer guard together would double-ingest.
  #  2. NO `output =` declaration, even though this stage owns CACHE_TEAM_BOX --
  #     daily_box_ingest() legitimately skips the write when there are no new games
  #     (daily_ingest.R:124), so asserting freshness here would false-positive on quiet days.
  # ---------------------------------------------------------------------------------------
  daily_ingest = list(
    id          = "daily_ingest",
    script      = "daily_ingest.R",
    description = "Ingest Latest WNBA Team Box Scores (Incremental)",
    call_fn     = "daily_box_ingest",
    entry_fn    = NULL,
    output      = NULL,
    # inputs: daily_box_ingest() reads its own prior output to merge in new games
    # (daily_ingest.R:64-65, `existing_box <- readRDS(CACHE_TEAM_BOX)`).
    inputs      = c(CACHE_TEAM_BOX),
    group       = NULL
  ),

  # ---------------------------------------------------------------------------------------
  # 0.7. Player Team-Game Features (BPM / minutes-concentration) -- Tier 1 fix (2026-09-17).
  # `call_fn`, not `entry_fn`: player_metrics.R is deliberately side-effect-free on a bare
  # source() (roster_bottom_up_engine.R also sources it below purely for its function
  # definitions, and must not trigger a recompute as a side effect of that).
  # ---------------------------------------------------------------------------------------
  player_metrics = list(
    id          = "player_metrics",
    script      = "player_metrics.R",
    description = "Compute Player Team-Game Features (BPM / Minutes Concentration)",
    call_fn     = "compute_and_cache_player_features",
    entry_fn    = NULL,
    output      = CACHE_FEATURES,
    # inputs: get_player_box_scores_chunked(), called from compute_and_cache_player_features(),
    # loads the cached player box scores if present instead of re-pulling wehoop live
    # (player_metrics.R:48-50, `if (file.exists(CACHE_PLAYER_BOX)) ... readRDS(CACHE_PLAYER_BOX)`).
    inputs      = c(CACHE_PLAYER_BOX),
    group       = NULL
  ),

  # ---------------------------------------------------------------------------------------
  # 1. Official Data Feed & Ingestion
  # Output: cache/active_rosters_cache.rds (T1 Handoff Notes: 209 rows x 7 cols, 15 teams)
  # ---------------------------------------------------------------------------------------
  sync_rosters = list(
    id          = "sync_rosters",
    script      = "sync_rosters.R",
    description = "Sync Active WNBA Rosters (12-Player Cap) & Mid-Season Signings",
    call_fn     = NULL,
    entry_fn    = "sync_active_rosters",
    output      = file.path(CACHE_DIR, "active_rosters_cache.rds"),
    # inputs: sync_active_rosters() is a pure live-API consumer (ESPN teams/roster
    # endpoints, sync_rosters.R:35-50) -- no readRDS()/read.csv() call anywhere in the file.
    # config.R's WNBA_TEAMS is used for canonicalization (sync_rosters.R:58) but that is a
    # config.R constant, not an upstream cache/file dependency.
    inputs      = character(0),
    group       = NULL
  ),

  # Output: cache/injury_data_cache.rds (T1 Handoff Notes: 42 rows, data_source column added)
  injury_scraper = list(
    id          = "injury_scraper",
    script      = "injury_scraper.R",
    description = "Scrape Official WNBA Injury Scratches & Availability Updates",
    call_fn     = NULL,
    entry_fn    = "fetch_live_wnba_injuries",
    output      = CACHE_INJURY_DATA,
    # inputs: fetch_live_wnba_injuries() is a pure live-API consumer (ESPN injuries endpoint,
    # injury_scraper.R:79-89) -- no readRDS()/read.csv() call anywhere in the file; the
    # documented offseason fallback (header comment) generates a synthetic sample in-process,
    # it does not read one from disk.
    inputs      = character(0),
    group       = NULL
  ),

  # Output: logs/analytics.duckdb (tables `team_embeddings` + `team_similarity`), PLUS
  # data/team_embeddings.csv + data/team_similarity_matrix.csv (config.R's CACHE_EMBEDDINGS /
  # CACHE_SIMILARITY).
  team_embeddings = list(
    id          = "team_embeddings",
    script      = "team_embeddings.py",
    description = "Train Team Style Embeddings & Similarity Matrix (PyTorch)",
    call_fn     = NULL,
    entry_fn    = NULL,
    output      = c("logs/analytics.duckdb", CACHE_EMBEDDINGS, CACHE_SIMILARITY),
    # inputs: CSV_TRAIN_SOURCE constant (team_embeddings.py:8, "cache/games_for_embeddings.csv",
    # a Python-side relative literal, not an R config.R symbol), read via
    # `df = pd.read_csv(CSV_TRAIN_SOURCE)` (team_embeddings.py:143).
    inputs      = c("cache/games_for_embeddings.csv"),
    group       = NULL
  ),

  # ---------------------------------------------------------------------------------------
  # 1.5. Prediction-Accuracy Logging -- Reconciliation
  # First of TWO distinct registry entries for prediction_accuracy_logger.R -- this one runs
  # early (reconcile_predictions), the other (prediction_accuracy_logger_log) runs later
  # (log_todays_predictions). Keyed as two separate entries so the second invocation cannot
  # silently disappear during the refactor.
  # ---------------------------------------------------------------------------------------
  prediction_accuracy_logger_reconcile = list(
    id          = "prediction_accuracy_logger_reconcile",
    script      = "prediction_accuracy_logger.R",
    description = "Reconcile Pending Model Predictions Against Completed WNBA Games",
    call_fn     = "reconcile_predictions",
    entry_fn    = NULL,
    output      = NULL,
    # inputs: reconcile_predictions() calls get_prediction_log() (prediction_accuracy_logger.R:584),
    # which readRDS()'s PRED_LOG_RDS (prediction_accuracy_logger.R:278; PRED_LOG_RDS =
    # file.path(CACHE_DIR, "prediction_accuracy_log.rds") per line 90); it also directly reads
    # the team-box cache to check for newly-completed games (prediction_accuracy_logger.R:597,
    # `if (file.exists(CACHE_TEAM_BOX)) readRDS(CACHE_TEAM_BOX)`).
    inputs      = c(file.path(CACHE_DIR, "prediction_accuracy_log.rds"), CACHE_TEAM_BOX),
    group       = NULL
  ),

  # ---------------------------------------------------------------------------------------
  # 2. Physics & Biometric Latent Engines (Phase 3) -- Parallel Group 1 (future_lapply,
  # plan(multisession)/plan(sequential) per the memory-adaptive check in run_full_pipeline.R).
  # These three are independent and only depend on base ingestion.
  # ---------------------------------------------------------------------------------------
  shot_quality_engine = list(
    id          = "shot_quality_engine",
    script      = "shot_quality_engine.R",
    description = "Calculate WNBA Spatial Shot Quality (xeFG%) & Luck",
    call_fn     = NULL,
    entry_fn    = NULL,
    output      = "cache/team_shot_quality.rds",
    # inputs: box_path fallback chain (shot_quality_engine.R:196-197) --
    # `box_path <- if (exists("CACHE_TEAM_BOX") ...) CACHE_TEAM_BOX else "data/box_scores_cache.rds"`,
    # then `box <- if (file.exists(box_path)) readRDS(box_path) else NULL`. (Its own
    # self-produced shot cache, cache/wnba_shots_cache.rds, read at line 99 as a
    # skip-if-cached optimization, is not counted as an upstream dependency.)
    inputs      = c(CACHE_TEAM_BOX),
    group       = "latent_engines"
  ),

  fatigue_travel_engine = list(
    id          = "fatigue_travel_engine",
    script      = "fatigue_travel_engine.R",
    description = "Compute Haversine Flight Miles & Circadian Drag",
    call_fn     = NULL,
    entry_fn    = "evaluate_slate_fatigue",
    output      = "cache/travel_fatigue_metrics.rds",
    # inputs: evaluate_slate_fatigue() builds a SYNTHETIC/DEMO sample_schedule in-process
    # (fatigue_travel_engine.R:142-153, "no real WNBA schedule" per its own header comment)
    # -- no readRDS()/read.csv() call anywhere in the file. Flagging for the orchestrator:
    # this looks like a real gap (a "latent engine" with no real upstream schedule input),
    # not something in scope to fix here.
    inputs      = character(0),
    group       = "latent_engines"
  ),

  rapm_engine = list(
    id          = "rapm_engine",
    script      = "rapm_engine.R",
    description = "Estimate Real Possession-Level RAPM (L2 Ridge Regression)",
    call_fn     = NULL,
    entry_fn    = "estimate_rapm_ratings",
    output      = CACHE_RAPM_RATINGS,
    # inputs: primary path is a live wehoop::load_wnba_stats_possessions() pull (no file
    # input); its own PBP possessions cache (cache/wnba_pbp_cache.rds, rapm_engine.R:134-138)
    # is self-produced/self-consumed, not counted as upstream. The documented fallback,
    # estimate_rapm_box_plusminus_fallback(), reads CACHE_PLAYER_BOX when the live pull fails
    # entirely (rapm_engine.R:279-283, `readRDS(box_path)` where
    # box_path = "cache/player_box_scores_cache.rds", i.e. CACHE_PLAYER_BOX's value).
    # active_rosters_cache.rds is also a real read as of the 2026-10-07 current-team
    # re-attribution fix (reattribute_to_current_roster_team(), called from both the
    # live-pull and fallback paths) — without it, traded/signed/expansion-drafted players'
    # `team` column silently stays on their historical-possession-plurality team and drops
    # out of rapm_join_utils.R::join_rapm_to_roster()'s inner join.
    inputs      = c(CACHE_PLAYER_BOX, file.path(CACHE_DIR, "active_rosters_cache.rds")),
    group       = "latent_engines"
  ),

  # ---------------------------------------------------------------------------------------
  # 2.5. Play-by-Play Player Features -- deliberately SEQUENTIAL, not folded into the
  # "latent_engines" future_lapply group above (see run_full_pipeline.R's 2026-09-17 OOM
  # comment, preserved there verbatim -- this file only re-describes the DAG-placement
  # rationale that belongs on the STAGE, not the parallel-group mechanism itself).
  # ---------------------------------------------------------------------------------------
  pbp_engine = list(
    id          = "pbp_engine",
    script      = "pbp_engine.R",
    description = "Compute Real Play-by-Play Clutch/Assist/Shot-Mix Player Features",
    call_fn     = NULL,
    entry_fn    = "compute_player_pbp_features",
    output      = CACHE_PLAYER_PBP_FEATURES,
    # inputs: compute_player_pbp_features() reads the active rosters cache
    # (pbp_engine.R:340, 370, `roster <- readRDS(roster_path) |> distinct(...)` where
    # roster_path = file.path(CACHE_DIR, "active_rosters_cache.rds")). Its own raw PBP event
    # cache (CACHE_PBP_RAW, read at pbp_engine.R:131-133) is self-produced/self-consumed.
    inputs      = c(file.path(CACHE_DIR, "active_rosters_cache.rds")),
    group       = NULL
  ),

  # ---------------------------------------------------------------------------------------
  # 3. Microstructure & Player Valuation Engines (depends on rapm_engine.R)
  # ---------------------------------------------------------------------------------------
  roster_bottom_up_engine = list(
    id          = "roster_bottom_up_engine",
    script      = "roster_bottom_up_engine.R",
    description = "Generate 15-Team WNBA Bottom-Up Standings & Fair Spreads",
    call_fn     = NULL,
    entry_fn    = "project_all_wnba_teams",
    output      = "cache/projected_wnba_standings.rds",
    # inputs: CACHE_TEAM_BOX (roster_bottom_up_engine.R:76-78, `if (!file.exists(CACHE_TEAM_BOX))
    # stop(...); games <- readRDS(CACHE_TEAM_BOX)`); rapm_ratings.rds
    # (roster_bottom_up_engine.R:124-126); CACHE_PLAYER_BOX (roster_bottom_up_engine.R:222-227,
    # falls back to GLOBAL_PLAYER_BOX if already loaded); CACHE_FEATURES
    # (roster_bottom_up_engine.R:511-525); active_rosters_cache.rds
    # (roster_bottom_up_engine.R:519, 589-595, falls back to GLOBAL_ACTIVE_ROSTERS);
    # CACHE_INJURY_DATA (roster_bottom_up_engine.R:606, `readRDS(CACHE_INJURY_DATA)`).
    inputs      = c(CACHE_TEAM_BOX, CACHE_RAPM_RATINGS, CACHE_PLAYER_BOX, CACHE_FEATURES,
                     file.path(CACHE_DIR, "active_rosters_cache.rds"), CACHE_INJURY_DATA),
    group       = NULL
  ),

  # ---------------------------------------------------------------------------------------
  # 4. Market Arbitrage & Limits (depends on roster_bottom_up_engine.R, shot_quality_engine.R,
  # fatigue_travel_engine.R)
  # ---------------------------------------------------------------------------------------

  # ---------------------------------------------------------------------------------------
  # 4.5. Prediction-Accuracy Logging -- Log Today's Predictions. Second of the two distinct
  # registry entries for prediction_accuracy_logger.R (see prediction_accuracy_logger_reconcile
  # above).
  # ---------------------------------------------------------------------------------------
  prediction_accuracy_logger_log = list(
    id          = "prediction_accuracy_logger_log",
    script      = "prediction_accuracy_logger.R",
    description = "Log Today's Real Model Win-Probability Predictions",
    call_fn     = "log_todays_predictions",
    entry_fn    = NULL,
    output      = NULL,
    # inputs: latest_value_bets.rds (prediction_accuracy_logger.R:359, 366, `slate <-
    # readRDS(val_path)`); CACHE_INJURY_DATA via .current_injury_data_source(), called at
    # line 450 (readRDS at line 303); team_shot_quality.rds via
    # .current_shot_quality_data_source(), called at line 451 (readRDS via sq_path at
    # line 328-330); prediction_accuracy_log.rds via get_prediction_log(), called at line 493
    # for dedup against already-logged rows (readRDS at line 278).
    inputs      = c(file.path(CACHE_DIR, "latest_value_bets.rds"), CACHE_INJURY_DATA,
                     file.path(CACHE_DIR, "team_shot_quality.rds"),
                     file.path(CACHE_DIR, "prediction_accuracy_log.rds")),
    group       = NULL
  ),

  # ---------------------------------------------------------------------------------------
  # 5. Advanced Proposition Distributions -- Parallel Group 2 (future_lapply,
  # depends on market_odds_engine.R)
  # ---------------------------------------------------------------------------------------


  # ---------------------------------------------------------------------------------------
  # 6. Postseason Simulation
  # ---------------------------------------------------------------------------------------
  playoff_simulator = list(
    id          = "playoff_simulator",
    script      = "playoff_simulator.R",
    description = "Execute WNBA Playoff Series Monte Carlo (Bo3 First Round / Bo5 Semis / Bo7 Finals)",
    call_fn     = NULL,
    entry_fn    = "simulate_playoff_suite",
    output      = "cache/playoff_series_wnba_demo.rds",
    # inputs: rapm_ratings.rds (playoff_simulator.R:85-86, contender-leverage bump, falls
    # back to a hand-set bump if missing); projected_wnba_standings.rds
    # (playoff_simulator.R:199-201, seeds the bracket, falls back to a placeholder 4-team
    # slate if missing).
    inputs      = c(CACHE_RAPM_RATINGS, "cache/projected_wnba_standings.rds"),
    group       = NULL
  ),

  # ---------------------------------------------------------------------------------------
  # 6b. Current-Season Playoff Bracket: results beside predictions (GitHub issue #92)
  #
  # Placed immediately after playoff_simulator and well before export_web_json, which is
  # this artifact's only consumer — the exporter reshapes it into
  # web/public/data/playoff_bracket_2026.json and must not read a stale copy.
  #
  # group = NULL (serial) on purpose, not in a parallel group: the script source()s
  # tools/series_length_predictor.R, which in turn source()s playoff_simulator.R, and
  # playoff_simulator.R self-runs a 10,000-sim suite on source. Running that inside a
  # future_lapply worker alongside the other Monte Carlo stages is exactly the parallel
  # memory pressure the pipeline's own OOM note warns about, for a stage that takes ~2s
  # serially.
  #
  # entry_fn (not call_fn): the script self-runs via its own `if (!interactive())` guard,
  # so entry_fn verifies the entry point exists without invoking it a second time — the
  # double-execution trap documented in run_stage().
  # ---------------------------------------------------------------------------------------
  playoff_bracket_current = list(
    id          = "playoff_bracket_current",
    script      = "build_playoff_bracket_2026.R",
    description = "Build Current-Season Playoff Bracket (resolved results + per-series predictions)",
    call_fn     = NULL,
    entry_fn    = "build_playoff_bracket_current",
    output      = CACHE_PLAYOFF_BRACKET_CURRENT,
    # inputs: box_scores_cache.rds (the resolved series and the season_type == 2 ratings
    # behind the Round 1 reconstruction; a missing file yields an empty, clearly labeled
    # artifact rather than a crash). series_length_predictions.rds holds the archived
    # 2026-10-04 semifinal forecasts, read verbatim and never rewritten; if it is missing,
    # those rounds are marked prediction-unavailable.
    inputs      = c(CACHE_TEAM_BOX, file.path(CACHE_DIR, "series_length_predictions.rds")),
    group       = NULL
  ),

  # ---------------------------------------------------------------------------------------
  # 6c. Finals per-game predictions (#94).
  #
  # Runs strictly AFTER playoff_bracket_current above: the Finals matchup and the played
  # Finals results are read off that stage's artifact, so placing this earlier (or in a
  # parallel group beside it) would read a stale or absent bracket. Serial for the same
  # reason, and because, like 6b, it is a seconds-long reshape whose only heavy dependency
  # (the series-length DP) is exact rather than simulated.
  #
  # entry_fn (not call_fn): the script self-runs via its own `if (!interactive())` guard,
  # so entry_fn verifies the entry point exists without invoking it a second time.
  # ---------------------------------------------------------------------------------------
  finals_game_predictions = list(
    id          = "finals_game_predictions",
    script      = "build_finals_game_predictions.R",
    description = "Build Finals Per-Game Predictions (home court, rest, P(game played))",
    call_fn     = NULL,
    entry_fn    = "build_finals_game_predictions",
    output      = CACHE_FINALS_GAME_PREDICTIONS,
    # inputs: the #92 bracket artifact (the Finals matchup and its played results),
    # CACHE_TEAM_BOX (the season_type == 2 ratings behind both sides' net rating), and the
    # #93 schedule cache (per-game days_rest / is_back_to_back, including for games not yet
    # played). A missing bracket or missing seeds yields an empty, clearly labeled artifact
    # and the web route's empty state; a missing schedule degrades the section to
    # home-court-advantage only rather than crashing.
    inputs      = c(CACHE_PLAYOFF_BRACKET_CURRENT, CACHE_TEAM_BOX, CACHE_WNBA_SCHEDULE),
    group       = NULL
  ),

  # ---------------------------------------------------------------------------------------
  # 7. Portfolio Risk Management & Capital Preservation
  # ---------------------------------------------------------------------------------------

  # ---------------------------------------------------------------------------------------
  # 8. Notification & Settlement
  # ---------------------------------------------------------------------------------------

  # Output: cache/rolling_bet_metrics.rds (every run) and cache/betting_ledger.rds
  # (CONDITIONAL -- only rewritten when at least one pending bet actually grades). Only the
  # unconditional output is declared for the freshness assertion.

  # ---------------------------------------------------------------------------------------
  # 9. Next.js Static Web JSON Export (Phase 1)
  # ---------------------------------------------------------------------------------------
    # ---------------------------------------------------------------------------------------
    # 8.5. Forecast Accuracy Governance & Calibration Engine (Issue #17)
    # ---------------------------------------------------------------------------------------
    accuracy_governance = list(
      id          = "accuracy_governance",
      script      = "accuracy_governance.R",
      description = "Compute Model Forecast Governance & Calibration Diagnostics",
      call_fn     = "run_wnba_accuracy_governance",
      entry_fn    = NULL,
      output      = file.path(CACHE_DIR, "accuracy_governance.rds"),
      inputs      = c(file.path(CACHE_DIR, "model_calibration_input.rds"),
                      file.path(CACHE_DIR, "prediction_accuracy_log.rds")),
      group       = NULL
    ),
    # ---------------------------------------------------------------------------------------
    # 8.6. Front-Office Operations Alert Dispatcher (Issue #18)
    # ---------------------------------------------------------------------------------------
    notify_pipeline_ops = list(
      id          = "notify_pipeline_ops",
      script      = "notify_pipeline_ops.R",
      description = "Dispatch Front-Office Operations & Calibration Telemetry",
      call_fn     = "run_notify_pipeline_ops",
      entry_fn    = NULL,
      output      = NULL,
      inputs      = c(file.path(CACHE_DIR, "accuracy_governance.rds")),
      group       = NULL
    ),

  export_web_json = list(
    id          = "export_web_json",
    script      = "export_web_json.R",
    description = "Export Static JSON Datasets for Next.js Web App",
    call_fn     = NULL,
    entry_fn    = "export_web_json",
    output      = WEB_JSON_PROJECTIONS_SEASON_TEAMS,
    inputs      = c(file.path(CACHE_DIR, "projected_wnba_standings.rds"),
                    file.path(CACHE_DIR, "rapm_ratings.rds"),
                    file.path(CACHE_DIR, "team_shot_quality.rds"),
                    file.path("data", "team_embeddings.csv"),
                    file.path(CACHE_DIR, "active_rosters_cache.rds"),
                    file.path(CACHE_DIR, "player_box_scores_cache.rds"),
                    file.path(CACHE_DIR, "model_calibration_input.rds")),
    group       = NULL
  ),

  # ---------------------------------------------------------------------------------------
  # 10. WNBA 14-Zone Shot Chart Spatial Extraction (Phase 3)
  # ---------------------------------------------------------------------------------------
  shot_chart_dataset = list(
    id          = "shot_chart_dataset",
    script      = "build_shot_chart_dataset.R",
    description = "Extract WNBA Shot Locations & 14-Zone Baselines for Web App",
    call_fn     = NULL,
    entry_fn    = NULL,
    output      = WEB_JSON_SHOTS_INDEX,
    inputs      = c(file.path(CACHE_DIR, "wnba_espn_pbp_cache.rds"),
                    WEB_JSON_PROJECTIONS_SEASON_PLAYERS),
    group       = NULL
  ),

  # ---------------------------------------------------------------------------------------
  # 11. WNBA Offseason Moves & Roster Landscape (Phase 3)
  # ---------------------------------------------------------------------------------------
  offseason_dataset = list(
    id          = "offseason_dataset",
    script      = "build_offseason_dataset.R",
    description = "Compile Offseason Roster Moves, Cap Space & Draft Board",
    call_fn     = NULL,
    entry_fn    = NULL,
    output      = WEB_JSON_OFFSEASON_TRANSACTIONS,
    inputs      = c(WEB_JSON_PROJECTIONS_SEASON_PLAYERS,
                    WEB_JSON_PROJECTIONS_SEASON_TEAMS),
    group       = NULL
  ),

  # ---------------------------------------------------------------------------------------
  # 12. WNBA Coaching Staff & Tactical Analytics (Phase 3)
  # ---------------------------------------------------------------------------------------
  coaching_dataset = list(
    id          = "coaching_dataset",
    script      = "build_coaching_dataset.R",
    description = "Compile Coaching Staffs, ATO Efficiency & Tactical Ratings",
    call_fn     = NULL,
    entry_fn    = NULL,
    output      = WEB_JSON_COACHING_METRICS,
    inputs      = c(WEB_JSON_PROJECTIONS_SEASON_TEAMS),
    group       = NULL
  ),

  # ---------------------------------------------------------------------------------------
  # 13. WNBA Defensive Versatility & Rim Deterrence (Phase 3)
  # ---------------------------------------------------------------------------------------
  defense_dataset = list(
    id          = "defense_dataset",
    script      = "build_defense_dataset.R",
    description = "Compile Defensive Versatility Entropy & Rim Suppression Matrix",
    call_fn     = NULL,
    entry_fn    = NULL,
    output      = WEB_JSON_DEFENSIVE_METRICS,
    inputs      = c(WEB_JSON_PROJECTIONS_SEASON_PLAYERS),
    group       = NULL
  ),

  # ---------------------------------------------------------------------------------------
  # 14. WNBA High-Dimensional Player DNA & Historical Twins (Phase 3)
  # ---------------------------------------------------------------------------------------
  player_dna_dataset = list(
    id          = "player_dna_dataset",
    script      = "build_player_dna_dataset.R",
    description = "Compile 16-D Skill Vectors & Cosine Historical Archetype Twins",
    call_fn     = NULL,
    entry_fn    = NULL,
    output      = WEB_JSON_PLAYER_DNA_PROFILES,
    inputs      = c(WEB_JSON_PROJECTIONS_SEASON_PLAYERS),
    group       = NULL
  ),

  # ---------------------------------------------------------------------------------------
  # 15. WNBA True Clutch & Leverage Creation Index (Phase 3)
  # ---------------------------------------------------------------------------------------
  clutch_dataset = list(
    id          = "clutch_dataset",
    script      = "build_clutch_dataset.R",
    description = "Compile True Clutch Shot Creation, Pressure TS% & c-dWPA",
    call_fn     = NULL,
    entry_fn    = NULL,
    output      = WEB_JSON_CLUTCH_LEVERAGE_METRICS,
    inputs      = c(WEB_JSON_PROJECTIONS_SEASON_PLAYERS,
                    file.path(CACHE_DIR, "player_pbp_features.rds")),
    group       = NULL
  ),

  # ---------------------------------------------------------------------------------------
  # 16. WNBA Hard Salary Cap, Rookie Scale & Roster Crunch (Phase 3)
  # ---------------------------------------------------------------------------------------
  cba_cap_dataset = list(
    id          = "cba_cap_dataset",
    script      = "build_cba_cap_dataset.R",
    description = "Compile WNBA Hard Salary Cap Sheets, Supermax Tags & 11-vs-12 Crunch",
    call_fn     = NULL,
    entry_fn    = NULL,
    output      = WEB_JSON_CBA_CAP_SHEET,
    inputs      = c(WEB_JSON_PROJECTIONS_SEASON_PLAYERS),
    group       = NULL
  ),

  # ---------------------------------------------------------------------------------------
  # 17. Per-game Matchups dataset (#74): week ribbon, graded past weeks, pending future.
  #
  # ORDERING. This stage reads four artifacts and must run after ALL of their producers,
  # which is why it sits here at the end rather than beside the other schedule-fed stages:
  #   * CACHE_WNBA_SCHEDULE + CACHE_TEAM_BOX   <- daily_ingest (stage 2)
  #   * cache/prediction_accuracy_log.rds      <- prediction_accuracy_logger_log (stage 11)
  #       AND prediction_accuracy_logger_reconcile (stage 7), which is what turns a logged
  #       prediction into a GRADED one. Running before the reconcile would publish a week
  #       as ungraded that had in fact just been graded.
  #   * cache/projected_wnba_standings.rds     <- roster_bottom_up_engine (stage 10, written
  #       at roster_bottom_up_engine.R:838). This is the fallback projection basis for every
  #       game the accuracy log never predicted -- 311 of 355 for the 2026 season -- so a
  #       stale or missing standings file degrades most of the page. export_web_json already
  #       hard-stops without it (export_web_json.R:58); this stage does the same.
  #
  # It does NOT depend on export_web_json: it writes its own payload directly, like the
  # other build_*_dataset stages above, and shares no artifact with that stage.
  #
  # entry_fn (not call_fn): the script self-runs under its own `if (!interactive())` guard,
  # so entry_fn only verifies the entry point exists rather than invoking it a second time.
  # ---------------------------------------------------------------------------------------
  matchups_dataset = list(
    id          = "matchups_dataset",
    script      = "build_matchups_dataset.R",
    description = "Build Per-Game Matchups Dataset (week ribbon, scores, graded predictions)",
    call_fn     = NULL,
    entry_fn    = "build_matchups_dataset",
    output      = WEB_JSON_MATCHUPS_SLATES,
    inputs      = c(CACHE_WNBA_SCHEDULE, CACHE_TEAM_BOX,
                    file.path(CACHE_DIR, "prediction_accuracy_log.rds"),
                    file.path(CACHE_DIR, "projected_wnba_standings.rds")),
    group       = NULL
  )
)

# ------------------------------------------------------------------------------------------
# Helper accessors for run_full_pipeline.R
# ------------------------------------------------------------------------------------------

# Returns a single stage entry by id, stop()-ing loudly if the id is unknown -- a typo'd id in
# run_full_pipeline.R should fail fast at the lookup, not silently skip a DAG stage.
get_pipeline_stage <- function(id) {
  if (!id %in% names(PIPELINE_STAGES)) {
    stop(sprintf("pipeline_stages.R: unknown stage id '%s'.", id))
  }
  PIPELINE_STAGES[[id]]
}

# Returns all stage entries belonging to a given parallel group, in registry order, for
# run_full_pipeline.R's future_lapply() calls.
get_pipeline_stage_group <- function(group_name) {
  members <- Filter(function(s) identical(s$group, group_name), PIPELINE_STAGES)
  if (length(members) == 0) {
    stop(sprintf("pipeline_stages.R: no stages found for group '%s'.", group_name))
  }
  unname(members)
}
