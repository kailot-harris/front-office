# HANDOFF: NBA Analytics Animated & Static Visualization Suite

**Written:** October 29, 2026 (12:40 PM EDT)  
**Latest Commits:** 
- `c07cb03` (`NBA_analytics`): `fix(viz): calibrate rookie impact race to 2026-2027 draft class (#59)`
- `a9642aa` (`front-office` / aggregator): `chore: subtree-pull nba (update 2026-27 rookie race)`
**Audience:** Next engineer or autonomous subagent resuming work on the NBA Analytics visualization platform.

---

## 1. Project Overview & Boundaries

The **NBA Analytics** project (`C:\Users\kailo\kayceeslices\front-office\NBA Analytics`) is an automated quantitative analytics engine and Next.js static front-office web application (`/nba` route on the aggregator site `https://kailot-harris.github.io/front-office/nba/`).

### Authoritative Architecture & References
1. **Pipeline Execution:** `run_full_pipeline.R` (daily scheduled execution of Elo, Four Factors, RAPM, shot charts, predictions, and web sync).
2. **Aggregator Root:** `C:\Users\kailo\kayceeslices\front-office\front-office-aggregator` embeds `NBA Analytics` as a git subtree under `nba/`.
3. **Hard Policy Boundary:** **Zero-Betting Policy**. All public assets, documentation, UI badges, and test fixtures must strictly exclude betting terminology (lines, spreads, over/under, moneylines, value bets). Projections are strictly presented as win probabilities, score forecasts, and power ratings.

---

## 2. Issue Tracking & Status Matrix

| Issue # | Status | Description / Asset | Commit / Evidence |
|---|---|---|---|
| **#34** | CLOSED | Phase 1: Core theme (`theme_nba_dark()`), palette, team logo helpers | `66c8d7f` |
| **#35** | CLOSED | Phase 1: Dual-output renderer (`render_animated_artifact()`) GIF + PNG | `66c8d7f` |
| **#36** | CLOSED | Phase 2: Elo rank bump chart animation (`gif_elo_rank_bump.R`) | `4d49ad5` |
| **#37** | CLOSED | Phase 2: Net rating ORtg vs. DRtg quadrant scatter (`gif_net_rating_quadrant.R`) | `4d49ad5` |
| **#38** | CLOSED | Phase 2: Cumulative point differential line race (`gif_point_diff_race.R`) | `4d49ad5` |
| **#39** | CLOSED | Phase 3: Player shot chart evolution GIF (`gif_player_shot_chart.R`) | `b3be70a` |
| **#40** | CLOSED | Phase 3: High-res shot chart exporter (`plot_shot_chart.R`) | `b3be70a` |
| **#41** | DUP / OBS | Phase 3: Player RAPM & impact trajectory bar race | Re-filed and resolved under **#57** |
| **#42** | CLOSED | Phase 4: Playoff series net rating trajectory GIF | `035d149` (7-game trajectory removed week 2 per request) |
| **#43** | CLOSED | Phase 4: Playoff & play-in leverage probability bump (`gif_playoff_prob_bump.R`) | `035d149` |
| **#44** | CLOSED | Phase 5: Web media asset integration & daily pipeline hook (`publish_web.R`) | `ab23415` |
| **#45** | CLOSED | Maintenance: Monthly cron job to purge daily generated media older than 30d (`purge_stale_media_assets.R`) | `ab23415` |
| **#46** | CLOSED | Phase 6: Frontend UI embedding with `prefers-reduced-motion` fallback (`AnimatedMediaCard.tsx`) | `fcd9428` |
| **#47** | CLOSED | Phase 7: Full pipeline generation, git commit, push, and deployment verification | `f043074` |
| **#48** | CLOSED | Fix: Embed `gif_player_shot_chart` into `/shots` and `/gallery` | `e98da7c` |
| **#49** | CLOSED | Fix: Embed `plot_today_predictions` into `/matchups` and `/gallery` | `e98da7c` |
| **#50** | CLOSED | Batch A: Division standings animated race (`gif_division_standings_race.R`) | `b784308` |
| **#51** | CLOSED | Batch A: Elo trajectory heatmap grid (`gif_elo_heatmap.R`) | `b784308` |
| **#52** | CLOSED | Batch A: Week-over-week Elo delta power rankings race (`gif_elo_delta_race.R`) | `b784308` |
| **#53** | CLOSED | Batch B: Pace vs. Net Rating tactical quadrant scatter (`gif_pace_efficiency_quadrant.R`) | `f5d4ff3` |
| **#54** | CLOSED | Batch B: Points scored vs. allowed scatter with Elo bubble size (`gif_pf_pa_scatter_elo.R`) | `f5d4ff3` |
| **#55** | CLOSED | Batch B: Turnover & Four Factors margin race (`gif_turnover_margin_race.R`) | `f5d4ff3` |
| **#56** | CLOSED | Batch B: Season upset timeline & underdog victory tracker (`gif_upset_timeline.R`) | `f5d4ff3` |
| **#57** | CLOSED | Batch C: Player RAPM & impact trajectory bar race (`gif_rapm_race.R`) | `483ef7d` |
| **#58** | CLOSED | Batch C: Clutch margin win probability worm & shot map (`gif_clutch_shot_worm.R`) | `483ef7d` |
| **#59** | CLOSED | Batch C: Rookie class scoring volume & TS% efficiency race (`gif_rookie_impact_race.R`) | `c07cb03` (Calibrated to 2026-27 draft class) |
| **#33** | OPEN | Scheduled pipeline: Wire `project_week_predictions.R` into scheduled pipeline (replaces value bets slate) | **Next Up for scheduled pipeline optimization** |

---

## 3. Implemented Components & Canonical Files

### R Visualization & Tooling Scripts (`tools/`)
All visualization generators enforce dark theme standards (`theme_nba_dark()`), canonical franchise colors, and output dual media files (`.gif` + static `.png`):
- [tools/viz_common.R](file:///c:/Users/kailo/kayceeslices/front-office/NBA%20Analytics/tools/viz_common.R) (356 lines): Central palette (`NBA_COLORS`), team primary/secondary hex maps, `theme_nba_dark()`, and `render_animated_artifact()` using `gifski` and `magick`.
- [tools/gif_elo_rank_bump.R](file:///c:/Users/kailo/kayceeslices/front-office/NBA%20Analytics/tools/gif_elo_rank_bump.R) (221 lines): Elo rank bump race across season milestones.
- [tools/gif_net_rating_quadrant.R](file:///c:/Users/kailo/kayceeslices/front-office/NBA%20Analytics/tools/gif_net_rating_quadrant.R) (241 lines): ORtg vs. DRtg tactical quadrant scatter.
- [tools/gif_point_diff_race.R](file:///c:/Users/kailo/kayceeslices/front-office/NBA%20Analytics/tools/gif_point_diff_race.R) (193 lines): Cumulative point differential progression line chart.
- [tools/plot_shot_chart.R](file:///c:/Users/kailo/kayceeslices/front-office/NBA%20Analytics/tools/plot_shot_chart.R) (339 lines): Court layout generator and high-res hexbin/scatter PNG shot chart builder.
- [tools/gif_player_shot_chart.R](file:///c:/Users/kailo/kayceeslices/front-office/NBA%20Analytics/tools/gif_player_shot_chart.R) (165 lines): Cumulative player shot selection and volume animated evolution.
- [tools/plot_today_predictions.R](file:///c:/Users/kailo/kayceeslices/front-office/NBA%20Analytics/tools/plot_today_predictions.R) (140 lines): Slate match-up win probability and projected score board.
- [tools/gif_playoff_prob_bump.R](file:///c:/Users/kailo/kayceeslices/front-office/NBA%20Analytics/tools/gif_playoff_prob_bump.R) (310 lines): Playoff seed and play-in leverage trajectory.
- [tools/gif_division_standings_race.R](file:///c:/Users/kailo/kayceeslices/front-office/NBA%20Analytics/tools/gif_division_standings_race.R) (236 lines): Animated race across 6 NBA divisions.
- [tools/gif_elo_heatmap.R](file:///c:/Users/kailo/kayceeslices/front-office/NBA%20Analytics/tools/gif_elo_heatmap.R) (218 lines): Team Elo progression heatmap tiles.
- [tools/gif_elo_delta_race.R](file:///c:/Users/kailo/kayceeslices/front-office/NBA%20Analytics/tools/gif_elo_delta_race.R) (227 lines): Week-over-week Elo momentum bar race.
- [tools/gif_pace_efficiency_quadrant.R](file:///c:/Users/kailo/kayceeslices/front-office/NBA%20Analytics/tools/gif_pace_efficiency_quadrant.R) (241 lines): Pace vs. Net Rating scatter animation.
- [tools/gif_pf_pa_scatter_elo.R](file:///c:/Users/kailo/kayceeslices/front-office/NBA%20Analytics/tools/gif_pf_pa_scatter_elo.R) (274 lines): Points scored vs. allowed with Elo bubble sizing.
- [tools/gif_turnover_margin_race.R](file:///c:/Users/kailo/kayceeslices/front-office/NBA%20Analytics/tools/gif_turnover_margin_race.R) (216 lines): Four Factors turnover margin trajectory.
- [tools/gif_upset_timeline.R](file:///c:/Users/kailo/kayceeslices/front-office/NBA%20Analytics/tools/gif_upset_timeline.R) (260 lines): Pre-game win probability upset timeline.
- [tools/gif_rapm_race.R](file:///c:/Users/kailo/kayceeslices/front-office/NBA%20Analytics/tools/gif_rapm_race.R) (221 lines): Top 10 player regularized adjusted plus-minus leaderboard bar race.
- [tools/gif_clutch_shot_worm.R](file:///c:/Users/kailo/kayceeslices/front-office/NBA%20Analytics/tools/gif_clutch_shot_worm.R) (270 lines): Clutch win probability worm and shot timeline.
- [tools/gif_rookie_impact_race.R](file:///c:/Users/kailo/kayceeslices/front-office/NBA%20Analytics/tools/gif_rookie_impact_race.R) (284 lines): 2026–2027 rookie draft class scoring volume vs. True Shooting % (cross-referenced with `web/public/data/offseason_draft.json`).
- [tools/purge_stale_media_assets.R](file:///c:/Users/kailo/kayceeslices/front-office/NBA%20Analytics/tools/purge_stale_media_assets.R) (155 lines): 30-day trailing asset retention maintenance script.

### Web Application Components (`web/`)
- [web/components/AnimatedMediaCard.tsx](file:///c:/Users/kailo/kayceeslices/front-office/NBA%20Analytics/web/components/AnimatedMediaCard.tsx): Accessible media wrapper respecting `prefers-reduced-motion` with toggleable pause/play and PNG fallback.
- [web/components/GalleryClient.tsx](file:///c:/Users/kailo/kayceeslices/front-office/NBA%20Analytics/web/components/GalleryClient.tsx): Unified `/gallery` catalog showcasing all 14 animated and static visualizations filtered by category (Macro Team, Shot Tracking, Tactical & Matchups, Playoff & Roster).
- [web/components/Sidebar.tsx](file:///c:/Users/kailo/kayceeslices/front-office/NBA%20Analytics/web/components/Sidebar.tsx): Global sidebar navigation with active model evaluation badge (`Brier 0.2279`) and `Visual Gallery` entry.

---

## 4. Environment & Tooling Gotchas

1. **PowerShell Quote & Symbol Escaping**:
   - In Windows PowerShell, inline commands with `&`, `%`, `$`, and double-quotes frequently fail with syntax errors (`AmpersandNotAllowed` or `ExpectedValueExpression`).
   - **Fix**: Never pass long R or Python scripts in `powershell -Command "..."`. Write scratch `.R` or `.py` files and execute them directly via `Rscript script.R` or `python script.py`.
2. **Aggregator Subtree Workflow**:
   - Upstream GitHub Pages deployment runs from `front-office-aggregator` (`main` branch).
   - Any commit in `NBA Analytics` must be synchronized to `front-office-aggregator` using:
     ```bash
     cd C:\Users\kailo\kayceeslices\front-office\front-office-aggregator
     git subtree pull --prefix=nba "https://github.com/kailot-harris/NBA_analytics.git" main -m "chore: subtree-pull nba (automated sync)"
     git push origin main
     gh workflow run "Build and deploy GitHub Pages"
     ```
   - If merge conflicts occur on `GalleryClient.tsx` or `Sidebar.tsx`, resolve using `--theirs` (favoring the NBA analytics child repo) or inspect manually before pushing.
3. **Vitest Regression Checks**:
   - `web/tests/unit/data.test.ts` asserts on total games processed and model metrics.
   - When ESPN scores update regular-season games (e.g. from 2687 to 2699 games), reconcile the test count and `Sidebar.tsx` badge to avoid pipeline blocking.

---

## 5. Verification State

- **Unit Tests**: 158 passed (16 test files) in `web` (`npm run test:unit`).
- **All Batch Visualizations Generated**: Non-zero `.gif` and `.png` verified in `web/public/media/` and `cache/`.
- **Git State**: Clean working tree on `main` in both `NBA Analytics` and `front-office-aggregator`.
- **Live Deployment**: Workflow run dispatched on `front-office` GitHub Actions.
