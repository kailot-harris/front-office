# NBA Analytics Feature & Architecture Wishlist

This wishlist tracks high-priority features, enhancements, and roadmap items for expanding the NBA Game Outcome Prediction & Season Simulation system beyond team-level box score aggregations.

---

## 1. Player-Level Analytics & Lineup Modeling *(Next Phase)*

> [!IMPORTANT]
> Transitioning from team-level rolling averages to player-level impact metrics captures roster moves, injuries, and load management that standard box score aggregates miss.

* **Impact Metric Integration (RAPM / EPM / BPM / LEBRON):**
  * Incorporate player-level Regularized Adjusted Plus-Minus (RAPM), Estimated Plus-Minus (EPM), or Box Plus-Minus (BPM) into game projections.
  * Weighted player minute projections: calculate projected team strength based on active depth chart minutes.
* **Injury & Load Management Tracking:**
  * Ingest official NBA Injury Reports prior to tip-off to adjust team ratings when star players are OUT or questionable.
  * Account for back-to-back rest days at the player level (e.g., veteran rest days).
* **Lineup Synergy & Staggering Metrics:**
  * Evaluate top 5-man unit net ratings and 2-player synergy combinations.

---

## 2. Advanced Offseason & Roster Dynamics

* **Roster Turnover & Offseason Adjustment Engine:**
  * Model free agency transfers, trades, and draft pick additions when transitioning between historical seasons.
  * Weight prior-season baseline stats based on roster continuity percentage (e.g., returning minutes %).
* **Rookie & Young Player Development Trajectories:**
  * Apply age-curve adjustments for developing players (ages 19–23) and aging veterans (ages 33+).

---

## 3. Advanced Modeling & Probability Calibration

* **Player & Team Embedding Networks:**
  * Train neural entity embeddings for teams and players to capture style matchups (e.g., high-pace vs. heavy-rebounding teams).
* **Live In-Play Simulation & Market Odds Calibration:**
  * Benchmark projected win probabilities against consensus Vegas closing moneyline odds and point spreads.
  * Evaluate Brier Score calibration for live in-game outcome forecasting.

---

## 4. Automation & Data Pipeline Infrastructure

* **Automated Daily Schedule & Box Score Ingestion:**
  * Set up automated pipelines via `hoopR` to pull daily completed box scores and update rolling features dynamically.
  * Generate an interactive web dashboard (e.g., R Shiny or Streamlit) for live season standings projections.
