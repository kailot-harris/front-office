# Quantitative Roadmap: Phase 4 Recommendations & Feature Wishlist

**Project:** NBA Game Outcome Prediction & Quantitative Sports Trading System  
**Document:** Future Research Horizons & Architectural Upgrades  
**Author / Roles:** Outgoing Quantitative Sports Trader & Market Microstructure Specialist  
**Status:** Queued for Phase 4 Execution  
**Target Directory:** `c:\Users\kailo\kayceeslices\NBA Analytics\`

---

## 1. Architectural Recommendations for Phase 4

### Recommendation 1: Terminal Dashboard Expansion (`app.R`)
The existing Shiny app (`app.R`) has 6 tabs developed in Phase 2. The Phase 3 alpha engines (`projected_30_team_standings.rds`, `latest_player_props.rds`, and rolling CLV metrics) must be integrated into the UI.
* **Add Tab 7: 30-Team Bottom-Up Standings & Head-to-Head Calculator:**  
  Interactive table displaying all 30 projected records with a live matchup simulator dropdown where selecting any two teams computes the fair spread and win probability.
* **Add Tab 8: Player Proposition Terminal (PRA Alpha):**  
  Searchable datatable of all 346 rotation players with filterable sliders for $\text{EV} \ge 5.0\%$, Over/Under recommendations, and Poisson projection distributions.
* **Bet Tracker Tab Upgrade:**  
  Add KPI metric boxes for **Rolling 7-Day CLV%**, **Rolling 30-Day CLV%**, and **Beat-CLV Rate (%)**.

### Recommendation 2: Live In-Play Line Scraper Integration (`live_game_listener.R`)
Currently, `live_game_listener.R` computes the model's live win probability based on game clock and score margin.
* **Next Step:** Integrate The Odds API live in-play endpoint (`markets=h2h&regions=us`) into the listener loop.
* **Execution:** Compare the live model probability against live sportsbook moneylines during timeouts. If a pre-game favorite is trailing by 8+ points in Q2 and the sportsbook live odds offer an edge $\text{EV} \ge +8.0\%$, dispatch an instant **"🚨 LIVE STEAM SNIPE"** alert to Discord.

### Recommendation 3: Move from Poisson to Zero-Inflated Negative Binomial (ZINB) for Props
While Poisson works well for Points, count stats like **Blocks, Steals, and 3-Pointers** exhibit excess zeros and overdispersion ($\sigma^2 > \mu$).
* Upgrade `player_props_engine.R` to estimate the dispersion parameter $\theta$ per stat category:
  $$P(X = k) = \frac{\Gamma(k + \theta)}{k! \, \Gamma(\theta)} \left(\frac{\theta}{\theta + \lambda}\right)^\theta \left(\frac{\lambda}{\theta + \lambda}\right)^k$$
  This prevents overvaluing extreme overs on low-count defensive props.

---

## 2. Quantitative Wishlist (W6 – W10)

| ID | Title | Analytical Domain | Value Proposition |
| :---: | :--- | :--- | :--- |
| **W6** | **In-Play Discord Steam Sniper** | Market Microstructure | Automatically triggers Discord alerts when recreational sportsbooks lag behind sharp in-game price movement during timeouts. |
| **W7** | **Bayesian Stint-Level RAPM Engine** | Player Modeling | Replaces regularized Box Plus-Minus with full possession-by-possession ridge regression (Regularized Adjusted Plus-Minus) using 5-man lineup stint matrices. |
| **W8** | **Interactive 8-Tab Shinydashboard** | UI & Visualization | Embeds the 30-team bottom-up power ratings, matchup spread calculator, and PRA props directly into the production GUI. |
| **W9** | **Automated Bankroll Drawdown & Stop-Loss Engine** | Risk Management | Implements rolling Drawdown monitors ($D_t = 1 - \frac{W_t}{\max W_\tau}$) that dynamically scale the Kelly fraction from $0.25 \to 0.10$ if bankroll experiences a $-5.0$ unit drawdown. |
| **W10**| **Monte Carlo Playoff Series Simulator** | Tournament Pricing | Simulates best-of-7 series (2-2-1-1-1 format) using 240-minute playoff shortened rotations (8-man rotations instead of 9-man regular season depth). |

---

## 3. Data Flow & Execution Sequence (Phase 4 Target)
[05:00 AM Task Scheduler: schedule_daily.bat]
│
├─ 1. sync_rosters.R (Pulls 556 active players & trades from live CDN)
├─ 2. injury_scraper.R (Ingests official scratches & updates availability)
├─ 3. run_full_pipeline.R (Box scores, embeddings, baseline RF calibration)
├─ 4. roster_bottom_up_engine (Calculates bottom-up spreads & 30-team matrix)
├─ 5. market_odds_engine.R (Live books vs. Pinnacle & Quarter-Kelly stakes)
├─ 6. player_props_engine.R (Over/Under PRA pricing across 346 players)
├─ 7. notify_bets.R (Pings Discord webhook with EV ≥ 5% & CLV > 0)
└─ 8. bet_tracker.R (Grades completed bets & updates CLV metrics)
[07:00 PM – 11:30 PM Game Nights]
└── live_game_listener.R (In-play scoreboard polling & real-time steam alerts)
[Anytime Interactive Analysis]
└── app.R (8-Tab Shiny Quantitative Terminal)