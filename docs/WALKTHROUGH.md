# Welcome to Front Office — First-Time User & Academic Reviewer Walkthrough

**Live Site:** **https://kailot-harris.github.io/front-office/**  
**Coverage:** NFL (13 Modules) • NBA (14 Modules) • WNBA (15 Modules) • MLB (14 Modules) — **56 Total Modules**

Welcome to **Front Office**, a multi-sport quantitative analytics, front-office salary cap, and probabilistic forecasting platform. Because 56 interactive modules across four professional sports leagues can feel expansive on a first visit, this guide provides a **5-Minute Express Tour**, a **Navigation Primer**, a **Code-Grounded Analytics Glossary**, and **Role-Specific Deep-Dive Trails**.

---

## 1. The 5-Minute Express Tour (Recommended for Academic Reviewers)

Follow these five stops in order to see the complete data lifecycle—from live in-season game ingestion and TreeSHAP explainability to out-of-sample calibration governance, high-dimensional player similarity vectors, CBA luxury tax modeling, and off-season transaction-wire reconciliation.

### Stop 1: The Portal Landing Page & Instant Cross-League Filter (30 Seconds)
- **URL:** [https://kailot-harris.github.io/front-office/](https://kailot-harris.github.io/front-office/)
- **What to Click & Try:**
  1. Press the **`/`** key anywhere on the page to focus the search bar (`Filter 56 modules…`).
  2. Type **`clutch`**, **`dna`**, **`diagnostics`**, or **`nba`** and watch the four league cards automatically expand, filter matching modules in real time, and announce the match count (`"4 modules in 4 leagues"`). Press **`Escape`** to restore your previous card state, or **`Enter`** to jump straight to the first match.
  3. Click any league header (e.g., **NBA** or **MLB**) or use the **Left/Right Arrow keys** on the `[NFL | NBA | WNBA | MLB]` pill tabs to rotate the **360° Hardware Showcase** between the Vince Lombardi, Larry O'Brien, WNBA Championship, and Commissioner's Trophies.
- **What Data Engineering Powers It Under the Hood:**
  - Zero-dependency vanilla HTML/CSS/JS (`front-office-aggregator/index.html`, 924 lines) using the **Hybrid B "Teal Current" (`#041313` / `#2dd4bf`)** design system with $6\text{px}$ luminous league status pips and $2\text{px}$ gradient rails.
  - The 360° video showcase (`assets/trophies/<sport>-turntable.mp4`, 130–249 KB each) uses `IntersectionObserver` to pause playback when scrolled off-screen and listens to `window.matchMedia('(prefers-reduced-motion: reduce)')` to strip video sources entirely and display lightweight 7–14 KB static `.webp` posters for reduced-motion visitors.
  - A CI pre-deploy guard (`tools/check_sport_nav_sync.mjs`, run in `.github/workflows/deploy.yml`) mechanically parses every sport's `web/components/Sidebar.tsx` and blocks deployment if `index.html`'s 56-module accordion ever drifts out of sync.

---

### Stop 2: In-Season Live Matchups & TreeSHAP Explainability (1 Minute)
- **URL:** [NBA Matchup Slates (`/front-office/nba/matchups/`)](https://kailot-harris.github.io/front-office/nba/matchups/) or [NFL Weekly Matchups (`/front-office/nfl/matchups/`)](https://kailot-harris.github.io/front-office/nfl/matchups/)
- **What to Click & Try:**
  1. Use the **Week / Slate Ribbon** at the top to switch between completed slates (showing graded model picks, actual final scores, and slate accuracy) and the active upcoming slate.
  2. Click any individual **Game Card** to open the **Game Detail & Explainability Drawer**.
  3. Inspect the **Points Waterfall / TreeSHAP Attribution Chart**, injury availability scratches, and rest/travel circadian fatigue badges.
- **What Data Engineering Powers It Under the Hood:**
  - **Hybrid 3-Slot Refresh Architecture:** Every day at **09:00 local (Slot A)**, the full R DAG (`run_full_pipeline.R`) ingests official box scores and play-by-play via `hoopR` / `nflreadr`, logs pre-game probabilities (`prediction_accuracy_logger.R`), and fits a secondary `xgboost` model (`xgboost_shap_engine.R`) to extract exact per-game **TreeSHAP (`predcontrib = TRUE`)** feature contributions.
  - At **18:00 (Slot B)** and **01:00 (Slot C)**, `tools/run_refresh_slot.ps1` runs `tools/refresh_live_results.R` inside a clean detached git worktree (`.refresh-worktrees/<sport>`). When new final scores are detected, it patches the slate JSON, triggers a local model rebuild so standings and playoff odds reflect the final score immediately, and re-applies live finals so games whose official box scores haven't landed in `hoopR` yet stay marked completed.
  - **Static Payload Chunking:** Rather than forcing the browser to download a 40 MB monolithic JSON file on page load, the page loads a lightweight slate index (`matchups_slates.json` or `matchups_current_week.json`) and lazily fetches per-game detail payloads (`data/games/{game_id}.json` and `data/explainability/{game_id}.json`) on click.

---

### Stop 3: Calibration Diagnostics & Model Variants (1 Minute)
- **URL:** [NFL Diagnostics (`/front-office/nfl/diagnostics/`)](https://kailot-harris.github.io/front-office/nfl/diagnostics/) and [NFL Model Variants (`/front-office/nfl/variants/`)](https://kailot-harris.github.io/front-office/nfl/variants/) *(also available in `/nba/`, `/wnba/`, `/mlb/`)*
- **What to Click & Try:**
  1. On **Diagnostics**, examine the **Reliability Calibration Curve** (predicted win probability deciles $0.0\text{–}0.1$ through $0.9\text{–}1.0$ plotted against observed win rates along the $y = x$ ideal diagonal) and compare the **Brier Score** against the $0.2500$ naive coin-flip benchmark.
  2. Notice the separate metric cards/toggles for **Genuine Pregame Forecasts** vs. **Historical Walk-Forward Backtest**.
  3. Navigate to **Model Variants (`/variants/`)** in the left sidebar to compare alternative modeling specifications side-by-side (e.g., Ridge-Massey vs. Dynamic Elo vs. Kalman State-Space vs. GBM/XGBoost in NFL; or 4-Factor Pitcher Elo vs. Hierarchical Empirical Bayes vs. Marcel vs. Pythagenpat in MLB).
- **What Data Engineering Powers It Under the Hood:**
  - **Strict Forecast Provenance (`Owner Decision D1`):** `prediction_accuracy_logger.R` and `accuracy_governance.R` tag every forecast row with `log_source`. Only predictions committed to `cache/prediction_accuracy_log.rds` *before* kickoff/tipoff receive `LOGGED_PREGAME`; historical walk-forward reconstructions are tagged `BACKTEST_PREWEEK` (`nfl/export_web_datasets.R` lines 1063–1128). This prevents look-ahead or backtest overfitting from masquerading as live prospective accuracy.

---

### Stop 4: Front-Office Economics (Cap/CBT) & High-Dimensional Player DNA (1.5 Minutes)
- **URLs:**
  - [MLB CBT Payroll Sheet (`/front-office/mlb/cap-sheet/`)](https://kailot-harris.github.io/front-office/mlb/cap-sheet/) or [NBA Cap & Aprons (`/front-office/nba/cap-sheet/`)](https://kailot-harris.github.io/front-office/nba/cap-sheet/)
  - [MLB Player DNA & Twins (`/front-office/mlb/player-dna/`)](https://kailot-harris.github.io/front-office/mlb/player-dna/) or [NBA Player DNA & Peer Comps (`/front-office/nba/player-dna/`)](https://kailot-harris.github.io/front-office/nba/player-dna/)
- **What to Click & Try:**
  1. On **MLB CBT Payroll Sheet**, sort the 30 franchises by 2026 CBT Payroll, inspect which clubs cross the **\$244M Base Threshold** up to the **\$304M Tier 3 Cohen Tax**, and drag the sliders on the **Surplus Value Calculator** (Salary, Projected WAR, and \$/WAR Market Rate) to compute contract surplus value in real time.
  2. On **Player DNA**, select any star player to view their **Multi-Axis Skill Radar**, **2D Stylistic Manifold Scatter Plot**, and **Top Cosine-Similarity Twins** (historical 1980–2026 peak comparables in MLB; current-season empirical peer comparables in NBA/WNBA).
- **What Data Engineering Powers It Under the Hood:**
  - In NBA (`nba/build_cba_cap_dataset.R`), `tools/fetch_bbref_player_contracts.R` scrapes Basketball-Reference's `/contracts/players.html` daily, normalizes franchise abbreviations (`PHO -> PHX`, `CHO -> CHA`, `BRK -> BKN`), and computes progressive 2023-CBA luxury tax bills and First/Second Apron structural handcuffs (with an automatic fallback to a verified Spotrac snapshot if BBRef is unreachable).
  - In Player DNA (`nba/build_player_dna_dataset.R`, `mlb/mlb_player_dna_engine.R`, `nfl/build_player_dna_dataset.R`), players are embedded into 15-D or 16-D percentile vectors derived strictly from empirical tracking and box caches (Statcast exit velocity/barrels/chase/OAA, NFL Next Gen Stats air-yards/separation/CPOE, or NBA Empirical-Bayes shrunk shooting + L2 Ridge RAPM). Missing tracking inputs are published as `null` rather than imputed with synthetic constants.

---

### Stop 5: Off-Season Dynamics Monitor & Transaction Reconciler (1 Minute)
- **URL:** [MLB 2026–2027 Off-Season Monitor (`/front-office/mlb/offseason-monitor/`)](https://kailot-harris.github.io/front-office/mlb/offseason-monitor/) or [WNBA Off-Season Monitor (`/front-office/wnba/offseason-monitor/`)](https://kailot-harris.github.io/front-office/wnba/offseason-monitor/)
- **What to Click & Try:**
  1. Inspect the **Active Off-Season Phase Banner** (e.g., *Pre-Lockout Surge* or *Draft Lottery & Overseas Tracking*), the **Weekly Front-Office Executive Memo**, and the **Confirmed Transactions vs. Unverified Rumor Wire** tables.
  2. On WNBA's monitor, check the **Media Sentiment Pulse** derived from 6 women's basketball beat RSS feeds.
  3. Switch between the latest edition and historical weekly editions using the edition selector.
- **What Data Engineering Powers It Under the Hood:**
  - `build_offseason_monitor.R` orchestrates a 6-stage deterministic reconciliation DAG (`Ingest -> Extract -> Reconcile -> Cap/CBT Sync -> Render Memo -> Export JSON`).
  - Raw HTML/JSON/XML responses from official league transaction wires and beat RSS feeds are snapshotted into `cache/raw_ingest_archive/YYYYMMDD/`, validated against a strict wire schema (`tools/offseason/wire_items_schema.R`), parsed via regex entity extraction (`extract_regex.R`), and reconciled against the baseline state $S_{\text{last}}$ (`cache/league_state_baseline.json`) via $S_t = S_{\text{last}} \oplus \Delta S_{\text{confirmed}}$.
  - **Fail-Closed Quiet-Week Precondition:** A "Quiet Week (0 transactions)" memo can only publish if the ingestion manifest proves all required upstream feeds were fetched freshly and returned records (`can_assert_quiet_week == TRUE`). A failed scrape blocks rather than publishing a false quiet week.

---

## 2. How to Navigate Front Office

### League Lifecycle Badges (`In-Season` vs. `Off-Season`)
On the portal landing page (`index.html`), each league card carries a monospace lifecycle badge above its title:
- **`IN-SEASON (LIVE SLATE)` (currently NFL & NBA):** The league is actively playing its regular season or postseason schedule. Standings, weekly matchup slates, injury reports, Monte Carlo playoff odds, and calibration diagnostics update daily (Slot A at 09:00 local, plus Slots B & C score/model refreshes at 18:00 and 01:00 local).
- **`OFF-SEASON (WEEKLY MONITOR)` (currently WNBA & MLB):** The league has concluded its 2026 championship and is in its winter transaction cycle. Its final regular-season and postseason modules remain available as a complete historical record (including dedicated **Retrospective** modules at `/wnba/retrospective/` and `/mlb/retrospective/`), while the **2026–2027 Off-Season Monitor** at the top of the menu updates weekly every Monday morning.

### Keyboard Shortcuts & Interactive UI Conventions
- **`/` (Forward Slash) on Landing Page:** Immediately focuses the cross-league module search input.
- **`Escape` / `Enter` in Search Input:** `Escape` clears the filter and restores your manually expanded league cards; `Enter` navigates directly to the first matching module.
- **`ArrowLeft` / `ArrowRight` / `Home` / `End` on Trophy Tabs:** Follows the WAI-ARIA roving-tabindex tabs pattern to switch the 360° championship trophy showcase via keyboard.
- **`How to Read This Page` Disclosures:** Nearly every module features a collapsible **"How to Read"** banner near the page header explaining in plain English what each chart and table column represents, along with honest disclosures of any data window caveats.
- **Interactive Glossary Tooltips (`<GlossaryTerm />`):** Dotted-underline terms in page headers and table descriptions open inline definitions of domain metrics.
- **CSV & PNG Export Buttons:** Shared utilities (`web/lib/exportToCsv.ts` and `web/lib/exportSvgAsPng.ts`, kept byte-identical across all 4 leagues via `.github/workflows/check-shared-file-drift.yml`) allow downloading tables as `.csv` and custom SVG charts as `.png`.

---

## 3. Reading the Analytics (Code-Grounded Mini Glossary)

Every definition below reflects **strictly how this codebase computes the metric** (with exact source script citations):

| Term / Metric | Leagues | Plain-English Definition & Exact Codebase Formula | Source Script |
| :--- | :---: | :--- | :--- |
| **EPA / Play & Situational Splits** | NFL | **Expected Points Added per Play:** How much a team's offense or defense shifts expected points on the current drive relative to down, distance, and field position, smoothed over a trailing rolling window. Includes situational splits for Red Zone ($\le 20$ yd line), Money Downs (3rd/4th down), Explosive Plays, and Garbage-Time Exclusion. | `nfl/epa_metrics_engine.R` |
| **CPOE** | NFL | **Completion Percentage Over Expected:** Actual pass completion rate minus the `nflverse` expected completion probability given air yards, throw location, and pass rush context. Early-season QB ratings (<35 attempts) are shrunk toward experience-tier priors (`nfl/export_web_datasets.R` lines 965–993). | `nfl/epa_metrics_engine.R`, `export_web_datasets.R` |
| **L2 Ridge RAPM (ORAPM / DRAPM)** | NBA, WNBA | **Regularized Adjusted Plus-Minus:** Estimates each player's offensive and defensive impact in points per 100 possessions while controlling for all 9 other teammates and opponents on the floor using L2 ridge regression (`glmnet`) fitted on possession-level play-by-play tables (`hoopR` / `wehoop`). | `nba/rapm_engine.R`, `wnba/rapm_engine.R` |
| **Spatial Shot Quality ($\text{xeFG\%}$) & Luck** | NBA, WNBA | **Expected Effective Field Goal Percentage:** Models expected points per shot from shot distance and zone over a 15-game rolling window (`ROLLING_WINDOW_SIZE`). The residual ($\text{Actual Pts} - \text{Expected Pts}$) quantifies unsustainable shooting luck to mean-regress in future projections. | `nba/shot_quality_engine.R`, `wnba/shot_quality_engine.R` |
| **4-Factor Starting Pitcher Elo & $\text{rGS}$** | MLB | **Pitcher-Adjusted Team Elo:** Base team Elo (initial 1500, $K=4.0$) adjusted pre-game for Home-Field Advantage ($+24$), travel distance ($-0.31 \times \text{miles}^{1/3}$), rest days ($+2.3/\text{day}$), and Starting Pitcher Rolling Game Score: $\Delta R_{\text{SP}} = 4.7 \times (\text{rGS}_{\text{pitcher}} - \text{rGS}_{\text{team}})$, where Tangotiger Game Score is $47.4 + K + 1.5\cdot\text{Outs} - 2\cdot\text{BB} - 2\cdot H - 3\cdot R - 4\cdot\text{HR}$. | `mlb/mlb_elo_engine.R` |
| **Pythagenpat & Pythagorean Win%** | MLB, NFL | **Run/Point-Differential Expected Win Percentage:** In MLB (`mlb_pythag_baseline.R`), uses the dynamic Pythagenpat exponent $\gamma = (\text{RPG}_{\text{scored}} + \text{RPG}_{\text{allowed}})^{0.287}$ with $W\% = \frac{R^\gamma}{R^\gamma + RA^\gamma}$. The gap between actual wins and Pythagenpat wins measures one-run/cluster "luck." In NFL (`team_ratings_engine.R`), uses fixed exponent $k = 2.37$ strictly as a reference column. | `mlb/mlb_pythag_baseline.R`, `nfl/team_ratings_engine.R` |
| **Marcel & Hierarchical Empirical Bayes** | MLB | **Marcel:** Tom Tango's 3-year weighted baseline (5/4/3 weights for seasons $t, t-1, t-2$), regressed toward league-average rates by playing time and adjusted for age curves. **Empirical Bayes (`mlb_bayes_pooling.R`):** Partially pools individual batter/pitcher rates toward position-level hyper-priors inversely proportional to sample size (PA/BF). | `mlb/mlb_marcel_baseline.R`, `mlb/mlb_bayes_pooling.R` |
| **True Clutch Index & USCI** | NBA, WNBA, NFL, MLB | **High-Leverage Late-Game Performance:** In NBA/WNBA (`build_clutch_dataset.R`), filters PBP to 4Q/OT $\le 5\text{:00}$ and margin $\le 5$ pts (min 5 clutch FGA) to compute **Unassisted Shot Creation Index ($\text{USCI} = \frac{\text{FGM}_{\text{unassisted}}}{\text{FGA}} \times \text{PPP}$)**, True Shooting Resilience ($\text{Clutch TS\%} - \text{Base TS\%}$), and Turnover Fragility ($\Delta\text{TOV\%}$). In NFL, filters to 4Q/OT margin $\le 8$ or WP $\in [10\%, 90\%]$ in final 5:00. In MLB, computes Tom Tango's Leverage Index ($\text{LI}$), Win Probability Added ($\text{WPA}$), and reliever inherited-runner strand ("Fireman") ratings. | `build_clutch_dataset.R`, `mlb_clutch_leverage_engine.R` |
| **Player DNA & Cosine Similarity Twins** | NBA, WNBA, MLB, NFL | **Multi-Dimensional Skill Embeddings:** Represents each player as a 15-D (NBA/WNBA), 16-D (MLB), or position-specific (NFL) empirical percentile vector across finishing, shooting/contact, playmaking/discipline, defense, and speed/athleticism. Similarity between players $\mathbf{a}$ and $\mathbf{b}$ is computed via 50-centered cosine similarity: $\text{Sim}\% = \max\left(0, \frac{(\mathbf{a}-50)\cdot(\mathbf{b}-50)}{\|\mathbf{a}-50\|\|\mathbf{b}-50\|}\right) \times 100$. | `build_player_dna_dataset.R`, `mlb_player_dna_engine.R` |
| **Defensive Versatility (Shannon Entropy)** | NBA, WNBA | **Positional Switchability Entropy:** Measures how evenly a defender's PBP matchup events (blocks, steals, shooting fouls paired with opponent position across PG, SG, SF, PF, C) are distributed across all 5 positions using normalized Shannon entropy $H = -\sum_{k=1}^5 p_k \ln(p_k) / \ln(5)$, combined with DRAPM and rim/POA rates. | `nba/build_defense_dataset.R`, `wnba/build_defense_dataset.R` |
| **TreeSHAP Attributions** | NFL, NBA | **Additive Game-Level Feature Explanations:** Exact Shapley values extracted from the secondary `xgboost` margin/win model (`predcontrib = TRUE`), decomposing how much each feature (rating differential, rest advantage, travel fatigue, turnover/EPA form) shifts a specific game's predicted margin or win probability from the league baseline. | `nfl/xgboost_shap_engine.R`, `nba/xgboost_shap_engine.R` |
| **Brier Score & Log-Loss** | All 4 Leagues | **Proper Probabilistic Scoring Rules:** Brier Score $= \frac{1}{N}\sum (\hat{p}_i - y_i)^2$ (lower is better; $0.2500$ is random 50/50 guessing; $0.0000$ is omniscient). Log-Loss $= -\frac{1}{N}\sum [y_i \ln \hat{p}_i + (1-y_i)\ln(1-\hat{p}_i)]$. Separated into `LOGGED_PREGAME` (prospective) vs. `BACKTEST_PREWEEK` (retrospective). | `accuracy_governance.R`, `prediction_accuracy_logger.R` |
| **CBA First/Second Aprons & MLB CBT Tiers** | NBA, MLB, NFL | **Collective Bargaining Agreement Payroll Constraints:** In NBA (`build_cba_cap_dataset.R`, 2026–27 thresholds): Soft Cap (\$165.0M), Luxury Tax (\$200.4M), **First Apron (\$209.0M)** (blocks sign-and-trades, buyout market, >100% salary match), and **Second Apron (\$221.7M)** (freezes 7-year-out 1st-round picks, blocks cash/aggregation in trades). In MLB (`mlb_cbt_payroll_engine.R`): **Base CBT (\$244M)**, **Tier 1 (\$264M)**, **Tier 2 (\$284M, draft pick drops 10 spots)**, and **Tier 3 Cohen Tax (\$304M, up to 110% repeater surcharge)**. | `nba/build_cba_cap_dataset.R`, `mlb/mlb_cbt_payroll_engine.R`, `nfl/export_web_datasets.R` |

---

## 4. Deep-Dive Paths by Reviewer Interest

### Path A: For Data Engineering, ETL & Architecture Reviewers
Focus on how multi-source ingestion, entity resolution, incremental caching, and publish gates operate:
1. **Cross-Vendor Entity Resolution:** Inspect `MLB Analytics/mlb_id_crosswalk.R` (5-way MLBAM/FanGraphs/BBRef/Retrosheet/ESPN crosswalk) and `NFL Analytics/injury_scraper.R` + `player_id_crosswalk.R` (ESPN Player-Card `href` athlete ID recovery + GSIS-to-ESPN enrichment).
2. **Memory-Bounded Incremental PBP & Concurrency:** Read `NFL Analytics/daily_ingest.R` (lines 35–179, 95% PBP RAM reduction via `.PBP_CACHE_COLUMNS` and fresh-first `bind_rows` content-diffing) and `WNBA Analytics/run_full_pipeline.R` (lines 326–384 & 511–570, `RENV_CONFIG_SANDBOX_ENABLED=FALSE` PSOCK worker fix and DuckDB per-PID TSV spill merging).
3. **The 7-Assertion Publish Gate & Hybrid Slot Runner:** Read `NBA Analytics/tools/publish_web.R` (lines 1–120, Assertions A–G) and `front-office-aggregator/tools/run_refresh_slot.ps1` (lines 1–250 & 511–646, detached `.refresh-worktrees` and `Assert-ScheduledCheckoutSafety`).
4. **Live UI Pages to Visit:** [MLB Off-Season Monitor](https://kailot-harris.github.io/front-office/mlb/offseason-monitor/) and [WNBA Off-Season Monitor](https://kailot-harris.github.io/front-office/wnba/offseason-monitor/) (see live ingestion manifests, feed health statuses, and reconciled wire deltas).

### Path B: For Quantitative, Statistical & Machine Learning Reviewers
Focus on model formulation, shrinkage, uncertainty quantification, and out-of-sample calibration:
1. **Calibration & Prospective Forecast Governance:** Visit [NFL Diagnostics (`/nfl/diagnostics/`)](https://kailot-harris.github.io/front-office/nfl/diagnostics/) and [NBA Diagnostics (`/nba/diagnostics/`)](https://kailot-harris.github.io/front-office/nba/diagnostics/), then inspect `NFL Analytics/accuracy_governance.R` and `prediction_accuracy_logger.R`.
2. **Model Family Comparisons & Backtest Harnesses:** Visit [NFL Model Variants (`/nfl/variants/`)](https://kailot-harris.github.io/front-office/nfl/variants/) and [MLB Model Variants (`/mlb/variants/`)](https://kailot-harris.github.io/front-office/mlb/variants/), backed by `NFL Analytics/tools/model_backtest_harness.R` (walk-forward comparison of Ridge-Massey, Dynamic Elo, Kalman State-Space, GBM, and Stacking Ensemble) and `MLB Analytics/mlb_bayes_pooling.R` / `mlb_elo_engine.R`.
3. **Possession-Level L2 Ridge RAPM & TreeSHAP:** Inspect `NBA Analytics/rapm_engine.R` (`glmnet` sparse possession design matrix) and `NBA Analytics/xgboost_shap_engine.R`, then click any game on [NBA Matchups (`/nba/matchups/`)](https://kailot-harris.github.io/front-office/nba/matchups/) to inspect game-level TreeSHAP waterfalls.

### Path C: For Sports Front-Office, Cap Economics & Scouting Analysts
Focus on roster construction, salary cap mechanics, spatial shot/pitch tracking, and player archetypes:
1. **CBA Aprons, CBT Luxury Tax & Contract Surplus:** Visit [MLB CBT Payroll Sheet (`/mlb/cap-sheet/`)](https://kailot-harris.github.io/front-office/mlb/cap-sheet/), [NBA Cap & Aprons (`/nba/cap-sheet/`)](https://kailot-harris.github.io/front-office/nba/cap-sheet/), and [NFL Salary Cap & OTC (`/nfl/salary-cap/`)](https://kailot-harris.github.io/front-office/nfl/salary-cap/).
2. **Spatial Tracking & Zone Efficiency:** Visit [MLB Spatial Analytics (`/mlb/spatial/`)](https://kailot-harris.github.io/front-office/mlb/spatial/) (1,279 player Statcast spray/pitch maps), [NFL Passing Charts (`/nfl/passing/`)](https://kailot-harris.github.io/front-office/nfl/passing/) (12-zone QB air-yards grids), and [NBA Shot Charts (`/nba/shots/`)](https://kailot-harris.github.io/front-office/nba/shots/).
3. **Player DNA, Defensive Versatility & Clutch Creation:** Visit [MLB Player DNA (`/mlb/player-dna/`)](https://kailot-harris.github.io/front-office/mlb/player-dna/), [NBA Defensive Versatility (`/nba/defense/`)](https://kailot-harris.github.io/front-office/nba/defense/), [NBA Coaching Staffs (`/nba/coaches/`)](https://kailot-harris.github.io/front-office/nba/coaches/) (empirical ATO PPP and challenge overturn rates), and [WNBA True Clutch Index (`/wnba/clutch/`)](https://kailot-harris.github.io/front-office/wnba/clutch/).
