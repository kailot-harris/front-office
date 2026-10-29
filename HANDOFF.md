# Engineering Handoff: Front-Office Multi-Sport Platform

**Date:** 2026-10-29 (~08:15 EDT local time)  
**Author / Audience:** Antigravity / Next Developer or Agent resuming platform work  
**Primary Tracker:** [`kailot-harris/front-office`](https://github.com/kailot-harris/front-office)  
**Aggregator HEAD:** [`4e8c326`](https://github.com/kailot-harris/front-office/commit/4e8c326010e4d3c81357d7adfbe96961eb3ad55d) (`Include WNBA in refresh slot dispatch and sync (Closes #38)`)  
**Status:** All milestone issues closed (#8–#39 across Epics #31 & #33); live multi-sport site deployed and automated.

---

## 1. What This Project Is

This repository and workspace comprise the **Front Office Quantitative Sports Analytics Platform**, spanning four major North American sports leagues:
- **MLB Analytics** ([`kailot-harris/MLB-Analytics`](https://github.com/kailot-harris/MLB-Analytics))
- **NBA Analytics** ([`kailot-harris/NBA_analytics`](https://github.com/kailot-harris/NBA_analytics))
- **NFL Analytics** ([`kailot-harris/NFL_analytics`](https://github.com/kailot-harris/NFL_analytics))
- **WNBA Analytics** ([`kailot-harris/WNBA_analytics`](https://github.com/kailot-harris/WNBA_analytics))
- **Aggregator / Hub** ([`kailot-harris/front-office`](https://github.com/kailot-harris/front-office) hosted at [`https://kailot-harris.github.io/front-office/`](https://https://kailot-harris.github.io/front-office/))

### Core Architecture & Boundaries
1. **Zero-Betting Constraint:** The platform is strictly a **pure front-office quantitative sports analytics platform**. Commercial gambling apparatuses (The Odds API, devigging functions, betting spreads, fractional Kelly staking, closing line value loggers, `value_bets.json`) have been completely purged (Epic #31). Models rely exclusively on endogenous mathematical modeling, open-data schedule feeds (`nflreadr`, `baseballr`, `hoopR`, `wehoop`), and standard calibration/governance engines (`accuracy_governance.R`).
2. **Aggregator Subtree Model:** `front-office-aggregator` embeds each sport frontend under subfolders `mlb/`, `nba/`, `nfl/`, and `wnba/` via `git subtree`. Pushes to individual sport repos do not deploy GitHub Pages; Pages is deployed exclusively from `front-office-aggregator` via `deploy.yml`.

---

## 2. Issues Closed & Work History

| Issue | Category | Description | Status & Evidence |
|---|---|---|---|
| **#8–#29** | Epic #31 | Betting decommission Phases 0 through 5 | Closed. Purged odds APIs, betting engines, Kelly sizing, value_bets web exports, and cleansed config/README. |
| **#30** | Epic #31 | Verification: full 4-sport pipeline, contract test, static build, & rollout | Closed (`2026-10-29T00:58:09Z`). Verified 4-sport pipeline runs, static builds, and live deployment. |
| **#31** | Epic #31 | EPIC: Decommission betting apparatuses & delink prediction pipelines | Closed (`2026-10-29T00:58:25Z`). Master epic fully completed. |
| **#32** | WNBA | Add 2026 Playoffs link to WNBA card in aggregator `index.html` | Closed (`2026-10-25T15:58:25Z`). |
| **#33** | Epic #33 | EPIC: Restore active tab sidebar navigation highlighting | Closed (`2026-10-29T04:36:00Z`). Master epic across NBA, WNBA, and MLB. |
| **#34** | Epic #33 | Phase 1: NBA active tab sidebar highlighting | Closed (`f003d83`). Normalized trailing slashes in Next.js subroutes. |
| **#35** | Epic #33 | Phase 2: WNBA active tab sidebar highlighting | Closed (`623da89`). Normalized trailing slashes in Next.js subroutes. |
| **#36** | Epic #33 | Phase 3: MLB active tab sidebar highlighting | Closed (`2c17dc1`). Normalized trailing slashes in Next.js subroutes. |
| **#37** | Epic #33 | Phase 4: Verification — Aggregator subtree sync and live rollout gate | Closed (`8a6bba2`). Verified live deploy run `40818391375`. |
| **#38** | Orchestration | Include WNBA in Slot B & C refresh dispatch (`tools/run_refresh_slot.ps1`) | Closed (`4e8c326`). Dispatches `WNBA_analytics#103` in all unattended refresh runs. |
| **#39** | Verification | Live test refresh dispatch and aggregator sync across all 4 sports | Closed. Verified Slot B and Slot C runs clean end-to-end. |
| **—** | CI Maintenance | Prune redundant 22:00/05:00 UTC schedule crons | Completed (`c8b0ac6`, `b66d98a`, `cdaa889`, `c4e6e87`). Replaced delayed GitHub schedule runners with local workstation Task Scheduler triggers. |

---

## 3. Current Automation & Scheduling Architecture

```
SLOT A — Full Pipeline & 7-Assertion Publish Gate (Workstation local morning)
  NFL:  05:15 local -> NFL_analytics_task_01 (schedule_daily.bat) -> 27-stage R DAG (generates web/public/data/*)
        09:00 local -> NFL_analytics_publish_01 (schedule_publish.bat publish) -> publish_web.R (A–G) -> git push
  MLB:  09:00 local -> MLB_Analytics_Scheduled_Pipeline (run_pipeline_task.ps1 -Mode publish) -> 18-stage R DAG -> publish_web.R (A–G) -> git push
  NBA:  09:00 local -> NBA Analytics Daily Pipeline (schedule_daily.bat) -> 25-stage R DAG -> publish_web.R (A–G) -> git push
  WNBA: 09:00 local -> WNBA Analytics Schedule Daily (schedule_daily.bat) -> 31-stage R DAG -> publish_web.R (A–G) -> git push
  Aggregator Downstream Sync:
        13:30 UTC -> sync-sports.yml (cron '30 13 * * *') -> subtree-pulls all 4 sports -> deploy.yml

SLOTS B & C — Live Score Refresh & Incremental Deploy (Workstation orchestrator -> GitHub Actions)
  Workstation Task Scheduler:
    • Front Office Refresh Slot B (18:00 local)
    • Front Office Refresh Slot C (01:00 local)
    Both invoke: tools/run_refresh_slot.ps1 -Slot [B|C] -LogDir logs
      1. Dispatches 'Refresh live results' via gh workflow run in MLB, NFL, NBA, and WNBA (waits for all).
      2. Dispatches 'Sync sport subtrees and deploy' in front-office-aggregator with sports="mlb nfl nba wnba".
      3. Aggregator subtree-pulls new commits and dispatches deploy.yml (completes in ~3.5 min).
```

### GitHub Scheduled Cron Lateness vs. Workstation Task Scheduler
- GitHub Actions `schedule:` crons run **5 to 6 hours late** (observed 10 of 10 runs). All redundant 22:00/05:00 UTC schedule crons have been excised from the sport repositories and aggregator.
- Workstation Windows Task Scheduler fires within **1–2 seconds** of nominal schedule. Slot B (`18:00 local`) and Slot C (`01:00 local`) have both fired unattended and completed with exit code 0 (`LastTaskResult: 0`).
- Pre-pipeline morning safety cron (`0 11 * * *` / 07:00 ET) is intentionally retained in MLB to ensure postseason banner scores refresh even if workstation Slot A is missed.
- Aggregator morning downstream sync cron (`30 13 * * *` / 09:30 ET) is intentionally retained in `sync-sports.yml` to automatically capture Slot A 09:00 local publishes.

---

## 4. Current Repository State

Root folder: `C:\Users\kailo\kayceeslices\front-office`

| Directory | Branch | Status | Notes |
|---|---|---|---|
| **`front-office-aggregator`** | `main` | Clean, in sync with `origin/main` | HEAD `4e8c326`. Crons pruned (`c4e6e87`), WNBA added (`4e8c326`). |
| **`MLB Analytics`** | `main` | Clean, in sync with `origin/main` | HEAD `c8b0ac6`. Crons pruned (`c8b0ac6`). |
| **`NBA Analytics`** | `main` | Clean, in sync with `origin/main` | HEAD `b66d98a`. Crons pruned (`b66d98a`). |
| **`NFL Analytics`** | `main` | Clean working tree; staged local dataset | Clean git tracking. Working tree has newly regenerated datasets from 05:15 AM Slot A run waiting for 09:00 AM Slot A publish gate (`NFL_analytics_publish_01`). |
| **`WNBA Analytics`** | `main` | Clean, in sync with `origin/main` | HEAD `ca3ea93`. Refresh workflow and scoreboard patched (Closes #103). |

---

## 5. Tooling, Environment & Known Gotchas

1. **R Environment:**
   - MLB & WNBA use `renv.lock`.
   - NFL & NBA use `.github/r-dependencies.txt` without `renv`.
   - In NFL Analytics, `Rscript.exe` segfaults (exit 139) if called with a non-existent relative file path. Always specify valid absolute paths or test file presence first.
2. **Path Convention:**
   - All sibling repositories sit under `C:\Users\kailo\kayceeslices\front-office\`.
   - The aggregator repository sits alongside them at `C:\Users\kailo\kayceeslices\front-office\front-office-aggregator\`.
3. **Subtree Synchronization:**
   - Do NOT edit sport app frontend files inside `front-office-aggregator/{sport}/` directly. Always edit within the authoritative sport repos (`MLB Analytics/web`, `NBA Analytics/web`, etc.), commit/push there, and then subtree-pull into `front-office-aggregator` using `tools/run_refresh_slot.ps1` or `gh workflow run "Sync sport subtrees and deploy"`.
4. **Publish Freshness Gate (`tools/publish_web.R`):**
   - Enforces all 7 assertions (`A B C D E F G`): mtime freshness, week/slate alignment, non-empty diff, warning scan, branch verification, UTC `Z` `generated_at` provenance, and uncommitted vitest execution.
   - Posts webhook notifications via `DISCORD_OPS_WEBHOOK_URL` / `DISCORD_WEBHOOK` (fails gracefully when unset).

---

## 6. What's Next / Immediate Verification Items

1. **Observe 09:00 AM Local Slot A Publish:**
   - NFL's 05:15 AM pipeline run already produced fresh datasets at `09:24 UTC` (`05:24 EDT`).
   - At `09:00 AM EDT today` (`10/29/2026`), `NFL_analytics_publish_01`, `MLB_Analytics_Scheduled_Pipeline`, `NBA Analytics Daily Pipeline`, and `WNBA Analytics Schedule Daily` will fire on Windows Task Scheduler.
   - Confirm that all four sports publish and push clean commits to `origin/main`.
2. **Observe 09:30 AM EDT Downstream Aggregator Sync:**
   - Confirm that the `30 13 * * *` UTC cron on `sync-sports.yml` triggers (or manual dispatch if GitHub schedule lags) to pull the 09:00 AM Slot A publishes and deploy to GitHub Pages.
3. **No Open Issues:**
   - The issue tracker currently has **0 open issues**. All feature epics, hygiene passes, and cron prunings are complete.
