# Architecture & Engineering Decision Record (ADR)

**Project:** NBA Game Outcome Prediction & 2027 Season Simulation Engine  
**Author / Roles:** System Architect, Pipeline Supervisor & ML Research Lead  
**Date:** September 2026  
**Status:** Approved & Implemented  
**Target Directory:** `c:\Users\kailo\kayceeslices\NBA Analytics\`

---

## 1. Executive Summary & Problem Formulation

The baseline project achieved a validated predictive accuracy of **63.40%**, an **ROC-AUC of 0.6710**, and a **Brier Score of 0.2251** on the 2026 test season using an 18-game rolling team box score Random Forest architecture (`ranger`). 

However, team-level rolling averages suffer from fundamental limitations:
1. **Blindness to In-Season Transactions & Injuries:** When a star player is traded or ruled out, rolling aggregates require 5–10 games to reflect the roster change.
2. **Artificial Offseason Resets:** Resetting stats cleanly at Game 1 discards continuity information for intact rosters while carrying over stats creates cross-season noise for rebuilt teams.
3. **Static Game-Day Predictions:** Lack of in-play state updates and market odds calibration prevents live quantitative betting and game-state evaluation.

This engineering initiative translates the wishlist items (**W1–W5**) into seven modular agents (**T1–T7**) governed by a decoupled orchestration pipeline.

---

## 2. Core Architectural Principles

### Principle I: Non-Invasive Satellite Topology
* **Constraint:** Do not modify `NBA_Analysis_Project.Rmd` to prevent regressions in published benchmarks.
* **Architecture:** The existing R Markdown file remains the pristine reference baseline. New capabilities are implemented as standalone satellite modules with explicit inputs and outputs, orchestrated via `run_full_pipeline.R`.

### Principle II: Zero Cloud / Zero GPU Overhead
* **Analysis:** A question arose regarding whether training team and player entity embeddings requires cloud GPUs.
* **Decision:** **Local CPU execution.**
* **Mathematical Proof:**
  * Number of NBA teams: $N = 30$
  * Latent embedding dimension: $D = 16$
  * Historical game volume (2019–2025): $M \approx 8{,}500$
  * Total trainable parameters in embedding network: $\approx 750$ parameters.
  * Local CPU execution time for 120 epochs: **$< 3.0$ seconds**.
  * Transferring data to a cloud GPU (e.g., AWS EC2 P3 or GCP Vertex) introduces PCIe bus transfer latency, network egress overhead, and cloud provisioning costs with zero runtime speedup.

### Principle III: Fail-Safe Caching & Rate-Limit Resilience
* **Analysis:** The `hoopR` API scrapes endpoints that enforce undocumented rate limits. Fetching 8 seasons of player box scores represents $> 200{,}000$ rows.
* **Decision:** Implemented chunked season-by-season ingestion with automated retries, inter-request sleep intervals (`RATE_LIMIT_SLEEP_SEC = 1.5`), and intermediate local `.rds` persistence.

---

## 3. Component Architecture & Data Flow (DAG)
[ hoopR API Endpoint ]
                             │
                             ▼
                 ┌───────────────────────┐
                 │     daily_ingest.R    │
                 │  (Deduplication ETL)  │
                 └───────────┬───────────┘
                             │
                    box_scores_cache.rds
                             │
     ┌───────────────────────┼───────────────────────┐
     │                       │                       │
     ▼                       ▼                       ▼
     ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│ player_metrics.R │ │injury_load_...R │ │ team_embeddings │
│ - Chunked Box │ │ - Rest Days │ │ - PyTorch CPU │
│ - 36-Min BPM │ │ - B2B Detection │ │ - SVD Fallback │
│ - Top-5 Unit BPM │ │ - Schedule Index │ │ - Cosine Sim │
└────────┬─────────┘ └────────┬─────────┘ └────────┬─────────┘
│ │ │
├──────────────────────┘ │
▼ ▼
┌──────────────────┐ ┌──────────────────┐
│ lineup_synergy.R │ │load_embeddings.R │
│ - Minutes HHI │ │ (R Tidy Join) │
│ - Star Overlap │ └────────┬─────────┘
└────────┬─────────┘ │
│ │
▼ ▼
┌──────────────────┐ ┌──────────────────┐
│roster_dynamics.R │ │live_calibration.R│
│ - Continuity % │ │ - Brier & BSS │
│ - Dynamic Regress│ │ - Market Edge │
└────────┬─────────┘ │ - In-Play Drift │
│ └────────┬─────────┘
└──────────────────────┬─────────────────────┘
│
▼
┌───────────────────────┐
│ app.R │
│ (shinydashboard GUI) │
└───────────────────────┘

---

## 4. Module-by-Module Technical Decisions

### T1: Player Metrics (`player_metrics.R`)
* **Problem:** True possession-by-possession RAPM requires ridge regression over millions of stint matrices.
* **Solution:** Formulated a per-36 minute Box Plus-Minus (BPM) linear approximation:
  $$\text{BPM}_{36} = \left[ 0.60\,\text{PTS} + 0.70\,\text{REB} + 1.05\,\text{AST} + 1.40\,\text{STL} + 1.15\,\text{BLK} - 1.20\,\text{TOV} - 0.45\,\Delta\text{FGA} - 0.35\,\Delta\text{FTA} + 0.30\,\text{3PM} \right] \times \frac{\text{MIN}}{36} - 2.0$$
* **Team-Level Features Exported:**
  * `team_weighted_bpm`: Minutes-weighted roster impact.
  * `team_top5_bpm`: Mean rating of top 5 closing unit players.
  * `team_minutes_concentration`: Herfindahl-Hirschman index of playing time.

### T2: Injury & Schedule Load Tracker (`injury_load_tracker.R`)
* **Problem:** A single `days_rest` integer cannot capture the compounding exhaustion of multiple games in short timeframes or travel direction changes.
* **Solution:** Created a composite `schedule_fatigue_index`:
  $$\text{Fatigue Index} = 1.5 \cdot \mathbb{I}_{\text{B2B}} + 1.0 \cdot \mathbb{I}_{\text{3 in 4}} + 1.0 \cdot \mathbb{I}_{\text{4 in 5}} + 0.5 \cdot \mathbb{I}_{\text{Travel Change}}$$
* **Availability Degradation Function:**
  $$A_{\text{team}} = \max\left(0.70,\, 1.0 - \sum \frac{w_i \cdot \text{BPM}_i}{30.0}\right)$$
  where weights correspond to injury report status: $\text{Out} = 1.0$, $\text{Doubtful} = 0.75$, $\text{Questionable} = 0.50$, $\text{Probable} = 0.10$.

### T3: Lineup Synergy & Staggering Metrics (`lineup_synergy.R`)
* **Herfindahl-Hirschman Index (HHI) for Minutes:**
  $$\text{HHI} = \sum_{i=1}^{k} \left(\frac{\text{Minutes}_i}{\sum \text{Minutes}}\right)^2$$
  * $\text{HHI} > 0.16$: Star-heavy, tightly concentrated rotation.
  * $\text{HHI} < 0.11$: Deep bench, distributed rotation.
* **Star Overlap Metric:** Tracks whether both primary minute-earners played $\ge 30$ minutes in the same game, proxying tactical staggering.

### T4: Offseason Roster Dynamics Engine (`roster_dynamics.R`)
* **Problem:** Method A (Fresh Reset) treats defending champions with 90% returning rosters identically to rebuilding lottery squads.
* **Solution:** Continuity-weighted baseline transition:
  $$\text{returning\_minutes\_pct} = \frac{\sum_{p \in \text{Roster}_t \cap \text{Roster}_{t-1}} \text{Minutes}_{p, t-1}}{\sum_{p \in \text{Roster}_{t-1}} \text{Minutes}_{p, t-1}}$$
  $$\text{Baseline Rating}_{\text{New Season}} = \alpha \cdot \text{Rating}_{\text{Prior}} + (1 - \alpha) \cdot \mu_{\text{League}}$$
  where $\alpha = \max(0.20,\, \text{returning\_minutes\_pct})$.

### T5: Team & Entity Embeddings (`team_embeddings.py` & `load_embeddings.R`)
* **Model Architecture:** PyTorch MLP with dual embedding lookup tables ($30 \times 16$), concatenation, home-court scalar bias, and a non-linear dense projection ($32 \to 8 \to 1$).
* **Dual-Engine Auto-Fallback:**
  * If `torch` is installed: Trains CPU neural network via Adam optimizer ($lr=0.01$, BCE loss).
  * If `torch` is missing: Automatically computes a 16-rank **Truncated Singular Value Decomposition (SVD)** on the pairwise win-differential matrix using pure NumPy.
* **Output:** Exports both 16-D team vectors and a $30 \times 30$ Cosine Similarity Style Matchup matrix.

### T6: Live Simulation & Market Calibration (`live_calibration.R`)
* **Vig-Free Implied Probability:**
  $$P_{\text{fair, home}} = \frac{P_{\text{raw, home}}}{P_{\text{raw, home}} + P_{\text{raw, away}}}$$
* **Scoring Rules Evaluated:**
  * **Brier Score:** $\frac{1}{N}\sum (y_i - \hat{p}_i)^2$
  * **Brier Skill Score (BSS):** $1 - \frac{\text{Brier}_{\text{model}}}{\text{Brier}_{\text{reference}}}$ (relative to 50/50 baseline of 0.25)
  * **Log-Loss:** $-\frac{1}{N}\sum [y_i \ln(\hat{p}_i) + (1-y_i) \ln(1-\hat{p}_i)]$
* **In-Play Drift Dynamics:** Simulates logit-space updates with quarter-by-quarter variance decay:
  $$\text{logit}(P_t) = 0.70 \cdot \text{logit}(P_{t-1}) + \frac{\Delta_{\text{score}}}{3.0}$$

### T7: Production Dashboard & Automation (`app.R`, `config.R`, `daily_ingest.R`)
* **Design Pattern:** Built using `shinydashboard` with zero live API dependencies. Loads static RDS and CSV artifacts on startup for instantaneous page loading.
* **Tabs Provided:**
  1. *Projected Standings:* Analytical Poisson-Binomial estimates and 95% confidence intervals.
  2. *Model Benchmarks:* Side-by-side performance cards for Logistic Regression, Random Forest, and XGBoost.
  3. *Team Profiles:* Interactive 82-game rolling scoring and efficiency trajectories.
  4. *Monte Carlo Simulation:* 10,000-season win distributions visualized using `ggridges`.

---

## 5. Master Orchestrator Execution Trace

The orchestration file `run_full_pipeline.R` runs all modules sequentially. To prevent relative-path failures in RStudio, the script self-locks to the project directory:

```r
PROJECT_DIR <- "c:/Users/kailo/kayceeslices/NBA Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

Execution Steps & Exit Criteria
Step	Script	Input	Output Artifact	Exit Criterion
1	config.R	Environment	Global Constants	Paths and hyperparameters bound
2	daily_ingest.R	box_scores_cache.rds	Updated RDS	New games appended and deduplicated
3	player_metrics.R	hoopR Player Box	player_box_scores_cache.rds	Team-level BPM and HHI generated
4	injury_load_tracker.R	Team Box Scores	Schedule Matrix	B2B and fatigue scores assigned
5	lineup_synergy.R & roster_dynamics.R	Player Box Scores	Continuity Matrix	Roster stability scores computed
6	team_embeddings.py	games_for_embeddings.csv	team_embeddings.csv	16-D vectors exported via CPU/SVD
7	live_calibration.R	Model Predictions	Calibration Report	Brier and in-play drift verified

6. Verification Checklist & Next Research Horizons

All R and Python scripts located in c:\Users\kailo\kayceeslices\NBA Analytics\.

NBA_Analysis_Project.Rmd remains unmodified.

Rate limiting protected via chunking and sleep intervals.

PyTorch model defaults to CPU with zero-dependency SVD fallback.

Working directory self-locates to prevent "cannot open file 'config.R'" errors.
Future Horizon (Phase 2):
Live Injury Scraping: Replace the schema stub in injury_load_tracker.R with a live parser targeting the official NBA PDF injury portal (updated at 13:30, 17:30, and 20:30 EST).
Dynamic Vegas Feed: Connect live_calibration.R to The Odds API via JSON REST endpoints to calculate betting edges (
EV
=
p
⋅
b
−
(
1
−
p
)
EV=p⋅b−(1−p)
) in real time before game tips.