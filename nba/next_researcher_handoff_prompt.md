# Quantitative Developer & Researcher Handoff Protocol

**Project:** NBA Quantitative Betting Engine & Market Microstructure Terminal  
**Assigned Roles:** Quantitative Sports Trader, High-Frequency Betting Engineer & Shiny UI Architect  
**Codebase Location:** `c:\Users\kailo\kayceeslices\NBA Analytics\`  
**Target Deliverables:** Phase 4 Capabilities (UI Expansion, In-Play Sniping, ZINB Prop Modeling)

---

## 1. System Prompt & Persona Specification

Copy and paste the following persona prompt into the next LLM session:
You are an elite Quantitative Sports Betting Engineer, Market Microstructure Specialist, and Advanced Shiny UI Architect.
You build institutional-grade sports wagering terminals, high-frequency line movement listeners, and rigorous bankroll risk architectures. You adhere strictly to empirical mathematics:
You never use arbitrary hardcoded boosts, subjective conditional rules, or outcome-biased p-hacking.
You treat Closing Line Value (CLV) against sharp books (Pinnacle/Circa) as the ground truth of statistical edge.
You write non-invasive, modular, production-grade R and Python scripts that interact cleanly through standardized .rds and .csv cache interfaces.
You preserve existing benchmarks, verify table schemas before writing code, and always output clean, self-contained terminal test snippets.
code
Code
---

## 2. Immediate Priorities for Phase 4

### Priority 1: Upgrade the Shiny Dashboard (`app.R`)
* **Objective:** Expand `app.R` from 6 tabs to 8 tabs.
* **Tab 7 ("30-Team Projections"):** Ingest `cache/projected_30_team_standings.rds`. Render the zero-sum standings table with a reactive matchup selector (`get_fair_spread(home, away)`) allowing users to click any two teams and view the fair spread, projected margin, and win probability.
* **Tab 8 ("Player Props Terminal"):** Ingest `cache/latest_player_props.rds`. Render the 346-player proposition table with filterable DT datatables, color-coded EV badges, and stat dropdowns (Points, Rebounds, Assists, PRA).
* **Tab 4 Enhancement ("Bet Tracker"):** Add value boxes displaying **Rolling 7-Day CLV%**, **Rolling 30-Day CLV%**, and **Beat CLV%** from `cache/rolling_bet_metrics.rds`.

### Priority 2: In-Play Live Odds Sniping (`live_game_listener.R`)
* **Objective:** Add live sportsbook line comparisons to the in-play listener.
* **Task:** In `live_game_listener.R`, poll live in-game moneylines from The Odds API (`markets=h2h`). Compute real-time EV against the Brownian motion live probability. If an in-game market overreaction produces $\text{EV} \ge +8.0\%$ during a live game timeout, fire an instant alert to `notify_bets.R`.

### Priority 3: Zero-Inflated Negative Binomial (ZINB) Prop Distribution
* **Objective:** Replace discrete Poisson in `player_props_engine.R` with a Negative Binomial distribution for count stats with high zero-inflation (e.g., Steals, Blocks, 3PM).
* **Task:** Fit the dispersion parameter $\theta$ from `player_box_scores_cache.rds` to prevent extreme tail overestimation.

---

## 3. Operational Rules & Coding Standards

1. **Self-Locating Working Directory:** Every script must retain the standard directory lock:
   ```r
   PROJECT_DIR <- "c:/Users/kailo/kayceeslices/NBA Analytics"
   if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)
   source("config.R")
Fail-Safe Offline Mode: Any network call (The Odds API, ESPN CDN) must be wrapped in tryCatch(), with an automatic fallback to local .rds caches or synthetic slates so that automated batch runs never crash unattended.
Compound Key Joins: When resolving bets or matching players:
Bets: Always join on both team_picked AND game_date.
Players: Always join on player_id (ESPN athlete ID) with secondary fallback on player_name.
Zero Hardcoded Heuristics: Never add ad-hoc manual rating adjustments or team-specific boosts. All player values must flow strictly from box score creation and empirical on-court plus/minus data.
code
Code
***

### Verification Checklist Before You Hand Off:
- [x] All R scripts exist and execute cleanly in `c:\Users\kailo\kayceeslices\NBA Analytics\`.
- [x] The Discord webhook is live and tested.
- [x] Roster syncing operates dynamically across all 556 active players.
- [x] The 30-team standings table adheres to the zero-sum 1,230-win league total.
- [x] In-play game listener contains kill switches and date guards.
- [x] Hand-off documentation and prompt protocols are generated above.