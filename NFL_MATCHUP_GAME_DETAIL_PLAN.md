# NFL Matchup Game Detail & Model Attribution Plan (v2)

Written 2026-11-15, revised the same day after both owner decisions were made and a four-variant formula comparison was run (section 5.1). Supersedes the v1 plan of the same date. Repository: `kailot-harris/NFL_analytics`. Surface: `/matchups`.
Reference: the NBA game-detail work shipped in NBA_analytics #117–#128 and its contract in `web/lib/gameDetailTypes.ts`.

> **Veracity rule.** Every figure in a game file is either arithmetic on `nflreadr` data or a component of the exact model that produced the number on the card. No invented weights, no placeholder numbers, no second model shown without its own track record.

## Changelog from v1

1. **Accuracy headline needs an owner decision** before the provenance work starts (section 2, D1).
2. **Formula unification gets a before-and-after test.** It is a model change and is treated as one (section 5.1).
3. **`impact_score` removed.** Its weights had no derivation. Leaders are shown per category by a published measure (section 4.3).
4. **"Inactives" renamed and scoped** to what the data is: injury-report designations entering the game (section 4.4).
5. **Attribution is kept out of `matchups_current_week.json`.** That file holds all 272 games and is rewritten by the live score refresh (section 3.2).
6. **Secondary XGBoost model gets guard rails:** trained once per season, fixed seed, saved model, published out-of-sample record, one tolerance (section 5.4).
7. **Contract aligned with NBA as shipped,** so the modal components can be shared (section 4.1).
8. **Nullable fields made nullable; `_index.json` dropped; Phase 2 Tier 1a split into three issues.**
9. **New Phase 0:** three existing problems in the live matchups payload, found while checking this plan (section 3.0).
10. Wording: the baseline section is called "Baseline check", and no issue title uses betting vocabulary.

## 1. Baseline check (NFL `origin/main`, 2026-11-15)

| Claim | Status |
|---|---|
| Upcoming games: `projected_margin = 0.5·ridge_margin + 0.5·elo_margin`, Elo margin without fatigue, `home_win_prob = pnorm(margin / 14.60)` (`team_ratings_engine.R`) | Confirmed |
| Completed games: Elo margin includes `fatigue_adj`; probability is the average of two probabilities; margin is back-solved with `qnorm` (`tools/backtest_common.R`, `export_web_datasets.R`) | Confirmed |
| `team_ratings_engine.R` runs before `fatigue_engine.R` in `run_full_pipeline.R` | Confirmed |
| Completed games carry power ratings of 0.0 | Confirmed: 137 of 145 in the live file |
| `matchupGameSchema` is `.strict()` | Confirmed |
| `tools/gbm_model.R` trains an XGBoost classifier and is not a pipeline stage | Confirmed |
| `matchups_current_week.json` holds all 272 games (233 KB) | Confirmed |
| `projected_total` is the constant 44.5 on all 272 rows, set in `export_web_datasets.R` | Confirmed |
| A fallback branch writes margin 2.5 and probability 0.57 for a game with no prediction | Confirmed in code; no current row uses it |
| Row counts for `load_team_stats`, `load_player_stats`, `load_snap_counts`, and the 20-stat exact reconciliation | From v1; **not re-run here** |
| `web/tests/drift/content-drift.test.ts` holds the zero-betting term list | False. That file tests numeric literals. The pull-request template lists the banned terms (confirmed); a second agent reports a pre-flight script that scans `web/` for a short list, which was **not found on this machine**. There is no in-repo test scanning published payloads |
| Ridge model has four features: `diff_raw`, `diff_prior`, and each multiplied by average games played (`tools/ridge_massey_model.R`) | Confirmed in code. A second agent reports the two-step decomposition reproduces the model's prediction on all 145 games to 1.8e-15; not re-run here |
| `grade_walkforward_games()` passes one season to the ridge predictor, which finds no earlier seasons and falls back to the shrinkage blend for every 2026 game | **Confirmed in code.** The published 2026 record is graded with the fallback, not the stated model |

## 2. Owner decisions

- **D1. Accuracy headline.** NFL has never recorded a forecast before kickoff; all 145 graded games are walk-forward reconstructions. The NBA rule (headline covers pre-game forecasts only, backtests reported separately) applied here means the NFL headline starts empty at Week 11 and the season-to-date record is shown as "backtest". **Decided by the owner, 2026-11-15:** show both. The headline counts pre-game forecasts only, as in NBA, and the backtest record is shown beside it, labelled as a backtest. The two figures are never merged into one number. The backtest record stays beside the headline for the whole season, not only while the pre-game sample is small.
- **D2. Forecast formula. Decided by the owner, 2026-11-15: average the two margins, no fatigue term** (variant 1 in section 5.1). It is the formula upcoming games already use, it matches the NBA structure, and it makes the points waterfall exact. The fatigue term is removed from the forecast because it did not improve any measure in either sample and its weights were carried over from another sport without being fitted to NFL results. Rest days and travel miles remain on the card as context.

## 3. Phase 0 and wiring

### 3.0 Phase 0: fix the live site first (4 issues, independent of everything else)

1. **`projected_total` is a constant.** 44.5 on every game is not a projection. Remove the field from the payload, schema, types and card, or replace it with a real model output. Removal is recommended.
2. **Placeholder forecast branch.** Replace margin 2.5 / probability 0.57 with nulls and `has_projection: false`, and make the card render "No forecast recorded".
3. **Field names.** `projected_spread`, `projected_total` and `key_number_flag` are betting vocabulary in a published payload. Rename or remove: `projected_spread` duplicates `projected_margin` with the sign flipped; `key_number_flag` has no meaning outside that context.

4. **Grading uses the wrong model (bug).** `grade_walkforward_games()` builds its table from the current season only, so the ridge predictor has no training rows and silently uses the fallback shrinkage blend. The published 2026 record (91 of 145, 62.8%) is therefore not the stated model's record. Fix: pass the historical seasons as the upcoming path does, and make the fallback loud (log a warning and mark the rows) instead of silent. Reported effect: 89 of 145 (61.4%) with a better Brier score, so the published accuracy figure goes down. Filed and fixed on its own, ahead of Phase 2, with the before-and-after figures in the pull request.

Zeroed power ratings on completed games are fixed in Phase 2 (section 5.3), where the stored snapshot supplies them.

### 3.1 Which run writes what

- **Daily pipeline:** ingest (now including team stats, player stats, snap counts), engines, export. Writes `matchups_current_week.json` and game files. `publish_web.R` stages all of `web/public/data`. Game files are **not** added to `WEB_DATA_FILES`, because most are not rewritten on a given day and would fail the freshness assertion.
- **Live score refresh** (`tools/refresh_live_results.R`): rewrites `matchups_current_week.json` only. It must carry `has_box_score` and `has_game_detail` through untouched. A test round-trips the file through the refresh with no finished games and requires byte-identical output.
- **Lag:** a game can be final before `nflreadr` publishes its stats. Then `has_box_score` is false and the modal says "Final. Box score is added on a later data refresh."

### 3.2 What goes in which file

| File | Contents |
|---|---|
| `matchups_current_week.json` | Existing rows plus two booleans: `has_box_score`, `has_game_detail`. Nothing nested is added. |
| `games/<game_id>.json` | One per game with a box score. Box score, efficiency, splits; from Phase 2, the frozen attribution for that game. |
| `week_attribution/<season>_<week>.json` | Phase 2. Attribution for unplayed games of that week. Changes daily; one file, not sixteen. |

Card summary strips (EPA per play, yards per play, turnovers, leaders) are read from the game file on demand, or from a small `game_summaries.json` if the card needs them without a click. They are not embedded in the 272-row file.

### 3.3 Churn control

Same rule as NBA: build a candidate if the game is within 7 days, has no file, or the schema version changed; compare bytes with `generated_at` stripped; write only on difference. Two consecutive builder runs on the same caches must change zero files.

## 4. Phase 1: box score, efficiency, modal

### 4.1 Contract

Use the NBA envelope and conventions unchanged: `schema_version`, `generated_at`, `sport: 'nfl'`, `endpoint: 'game_detail'`, `season`, `season_label`, `data`. Identity fields are camelCase (`teamAbbr`, `teamName`, `playerId`, `playerName`); everything else is snake_case. `slate` is the week number and `slate_label` is "Week 10".

NFL-specific parts of `data`:

```ts
export interface NflEfficiencyFactorItem {
  key: 'epa_per_play' | 'success_rate' | 'dropback_epa' | 'rush_epa' | 'cpoe'
     | 'yards_per_play' | 'early_down_epa' | 'late_down_success_rate';
  label: string;
  away_value: number | null;     // null when the source has no value
  home_value: number | null;
  unit: 'epa' | 'pct' | 'yards';
  higher_is_better: boolean;
  description: string;           // the formula in words
}

export type NflBoxCategory = 'passing' | 'rushing' | 'receiving' | 'defense' | 'kicking';

export interface NflPlayerBoxRow {
  playerId: string; playerName: string; position: string | null;
  categories: NflBoxCategory[];  // every table the player appears in
  snap_pct: number | null;       // null when the id join fails
  // counting stats as in v1, all numbers
  // EPA fields: number | null
}

export interface CategoryLeader {
  category: NflBoxCategory;
  teamAbbr: string; playerId: string; playerName: string;
  stat_line: string;             // built from counting stats only
}

export interface InjuryDesignationRow {
  playerId: string | null; playerName: string; position: string | null;
  designation: 'Out' | 'IR' | 'Doubtful' | 'Questionable';
  body_part: string | null;
  played: boolean;               // true when the player has a stat or snap row for the game
}
```

Every forecast field in the payload is nullable. A game with no recorded forecast shows none.

### 4.2 Reconciliation test

For every team-game, active player rows sum exactly to team totals for the 20 counting stats listed in v1. This is asserted in the contract suite against all game files, not only quoted from a one-time check. Any stat that fails in practice gets a documented tolerance and a list of affected games in the test output, as was done for NBA rebounds.

Stats outside the 20 (total yards, plays, penalties) come from the team feed only and are not summed from players.

### 4.3 Leaders, not a composite score

`impact_score` is removed everywhere. In its place:

- **Category leaders** per team: passing yards, rushing yards, receiving yards, and for defense sacks then interceptions then solo tackles as tie-breakers. Ties broken by `playerName`.
- **Card strip:** the passing leader's stat line for each team. No ranking across positions.
- Player EPA columns stay in the tables, labelled as `nflreadr` values, with a note that EPA is a model estimate published by that source.

### 4.4 Injury designations

The section is titled "Injury report designations entering the game". It lists players with a designation on the final report before the game, and marks with `played` whether each appeared. It is not called "Inactives" unless a true game-day inactive list is sourced.

### 4.5 Modal

Same component structure as NBA: dialog semantics, focus trap, `Escape`, focus return, `?game=` deep link, tabs for Overview & Efficiency, Team Comparison, Player Box Score. Missing-data states as in section 3.1. Charts have visible numbers or an equivalent table.

### 4.6 Phase 1 issues (6)

| # | Title | Gate |
|---|---|---|
| 1a | Ingest team, player and snap caches; add `game_details_builder.R` | One file per game with a box score; second run changes zero files |
| 1b | TypeScript and Zod contracts for game detail | Type check and contract tests green; strict schema updated in the same change |
| 2a | Add the two booleans to the matchups payload; preserve them in the live refresh | Refresh round-trip is byte-identical |
| 2b | `GameDetailModal` tabs 1–3 | Component tests for focus, `Escape`, deep link, both missing-data states |
| 3a | Card strip and click wiring | Clicking a completed card opens the modal |
| 3b | Contract suite over all game files | Reconciliation exact on the 20 stats; no `NaN` or `Infinity`; term guard passes |

## 5. Phase 2: one formula, recorded forecasts, attribution

### 5.1 One formula (issue 2-1)

The comparison has been run by a second agent, walking forward over 2003–2025 (5,535 games) and 2026 to date (145 games). Figures are theirs and were not re-run here.

| Variant | Accuracy 2003–2025 | Brier 2003–2025 | Brier 2026 |
|---|---|---|---|
| 1. Margin average, no fatigue | 64.083% | 0.222670 | 0.224160 |
| 2. Margin average, with fatigue | 64.047% | 0.222843 | 0.224973 |
| 3. Probability average, no fatigue | 64.083% | 0.222710 | 0.224333 |
| 4. Probability average, with fatigue | 64.047% | 0.222867 | 0.225214 |

Reading: margin and probability averaging always pick the same winner and differ by 0.00004 in Brier score, which is noise. Fatigue is slightly worse on every measure in both samples. Decision D2 selects variant 1.

Work:

1. One shared function computes margin and probability from the inputs. The upcoming path and the walk-forward path both call it; the second implementation in `tools/backtest_common.R` and the back-solving in `export_web_datasets.R` are deleted.
2. `fatigue_adj` is removed from the forecast. The fatigue stage keeps running because the card shows rest and travel; the stage reorder in v1 is no longer needed.
3. Acceptance: for any game, both paths give the same margin and probability from the same inputs, to 1e-9. The four-variant table and the script that produced it are committed under `tools/` so the comparison can be repeated.

### 5.2 Points waterfall

Five steps, in points from the home side, plus rounding:

| Step | Formula |
|---|---|
| Current-season EPA | 0.5 × (b_raw + b_raw_gp × average games played) × (home raw − away raw) |
| Pre-season prior | 0.5 × (b_prior + b_prior_gp × average games played) × (home prior − away prior) |
| Elo differential | 0.5 × (home Elo − away Elo) / 25 |
| Home field | (1 − neutral) × (0.5 × ridge intercept + 0.5 × 48 / 25) |
| Starting quarterback | 1.60 × (away backup − home backup) |
| Rounding | projected margin − sum of the five steps; at most 0.02, asserted in tests |

The ridge coefficients are those of the fit for that season (trained on earlier seasons only) and are stored with the forecast, so a later refit cannot change a past game's waterfall. One conversion step to probability: Φ(margin / 14.60).

### 5.3 Forecast log (issues 2-2 and 2-3)

- **2-2, logger:** a stage after the ratings engine writes each unplayed game's forecast once it is within the logging window, with `log_source = "LOGGED_PREGAME"`, the five step values, the ridge coefficients used, sigma and both power ratings. The writer sets the label; nothing is inferred from dates. A logged row is never overwritten.
- **2-3, backfill and reporting:** the 145 completed games are written once from the walk-forward reconstruction with `log_source = "BACKTEST_PREWEEK"`, using the unified formula. Accuracy reporting follows decision D1. Completed-game cards read power ratings from the log, which removes the zeroed ratings.

Note on honesty of the label: the reconstruction uses only information available before each week, so `BACKTEST_PREWEEK` is accurate. It is not what the site showed at the time, because the site used the other formula. The provenance text says "Rebuilt afterwards from data available before the game", not "the forecast shown before the game".

### 5.4 Secondary model (issue 2-4)

Kept as a labelled second opinion, under these conditions:

- **Trained once per season** on seasons before the current one, fixed seed, single thread, saved with `xgb.save`. Retrained only by an explicit command. Daily runs load the saved model, so values do not drift between runs.
- **Its own record is published beside it:** out-of-sample accuracy, Brier score and log loss from walk-forward seasons, and its current-season record once games accrue. Without that record the block is not shown.
- **Features are entering values only,** and the plan states what a team's Week 1 features are (prior-season carry-over or missing). Feature construction is identical for training rows and current rows, and a test checks that on a held-out past week.
- **One tolerance:** SHAP values plus base value equal the model's logit within 1e-4, and the sigmoid of that equals the stated probability within 1e-4.
- **Display:** its probability is labelled "Second model" and never replaces or is averaged with the card's number. The agree/differ badge compares picks only.

### 5.5 Entering baselines

Season-to-date values over earlier games only, from pooled totals. `prior_games_n` always shown; flagged low-sample under 4 games; null in Week 1. The "divergence" line is descriptive: it names the factor with the largest gap between entering value and realized value, and makes no causal claim.

### 5.6 Phase 2 issues (8)

| # | Title | Depends on |
|---|---|---|
| 2-1 | Single shared forecast function (variant 1); remove fatigue from the forecast; commit the comparison script | Phase 0 item 4 |
| 2-2 | Forecast logger with step snapshot | 2-1 |
| 2-3 | Backfill 145 games as backtests; accuracy reporting per D1 (pre-game headline with backtest record beside it); power ratings from the log | 2-2 |
| 2-4 | Secondary model stage, saved model, published record | none |
| 2-5 | Contracts for attribution, waterfall, second model | 2-1 |
| 2-6 | Export: frozen attribution in game files, weekly attribution file for unplayed games | 2-2, 2-4, 2-5 |
| 2-7 | Modal tab 4; unplayed cards open to it | 2-6 |
| 2-8 | Contract tests: waterfall sum, additivity, baselines use earlier games only | 2-6 |

## 6. Traps specific to this repo

1. **Strict schema.** Any new field on a matchups row must be added to `matchupGameSchema` in the same change.
2. **Live refresh.** It parses and rewrites the matchups file. Keep nested objects out of it (section 3.2) and keep the round-trip test.
3. **Publish gate.** Do not list game files in `WEB_DATA_FILES`.
4. **Term guard.** Find where the repo's zero-betting check actually lives and what it bans before choosing field names. NBA shipped a field named `shap_log_odds`, so that term passed there; do not assume the same here.
5. **Fallbacks must be loud.** The grading bug went unnoticed because a fallback was silent. Any fallback in a forecast or grading path logs a warning and marks the affected rows.
6. **Open pull request with failing tests.** NFL_analytics#93 has six real failures unrelated to this work; do not build on that branch.

## 7. Order of work

Phase 0 (four fixes) can start now; item 4, the grading bug, goes first because it affects a figure on the live site. Phase 1 can start now and does not depend on Phase 0. Both owner decisions are made, so Phase 2 can start once Phase 0 item 4 is merged; issue 2-4 is independent and can run alongside Phase 1.

## 8. Follow-ups outside this plan

1. **Sigma looks too wide.** In all four variants the calibration tables show the same pattern: teams given about 74% win about 79% of the time, and teams given about 46% win about 42%. Refit `NFL_MARGIN_SIGMA` walk-forward and compare calibration. Likely a larger gain than the averaging choice.
2. **NBA fatigue term.** The NBA plan added its schedule adjustment to both forecast paths without a comparison like this one. Run the same with-and-without test there.
3. **In-repo term guard.** Add a test that scans published payloads and UI source for betting vocabulary, as Phase 1 issue 3b; today nothing in the repo's test suite does.
