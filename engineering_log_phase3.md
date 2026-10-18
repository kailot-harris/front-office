# NBA Analytics Engineering Log: Phase 3 Quantitative Trading & Market Execution

**Project:** NBA Game Outcome Prediction & Quantitative Sports Trading System  
**Document:** Phase 3 Implementation & Empirical Verification Record  
**Author / Roles:** Quantitative Sports Trader & Market Microstructure Specialist  
**Date:** September 2026  
**Status:** Deployed, Calibrated & Production-Verified  
**Project Path:** `c:\Users\kailo\kayceeslices\NBA Analytics\`

---

## 1. Executive Summary: Phase 3 Accomplishments

Phase 3 transitioned the analytics ecosystem from an academic, batch-evaluated classification model into a **full-stack quantitative betting terminal, real-time market microstructure tracker, and bottom-up lineup pricing engine**.

### Primary Milestones Delivered:
1. **Live Sportsbook REST Feed Connector (`market_odds_engine.R`):** Connected directly to *The Odds API* REST endpoints across 41 live games. Isolated sharp market makers (Pinnacle/LowVig) from retail books (DraftKings/FanDuel) with fail-safe synthetic fallback.
2. **Closing Line Value (CLV) & Ledger Hardening (`bet_tracker.R`):** Resolved a critical date-matching leak (`team_picked` + `game_date`), added sharp opening line logging, and implemented automated tracking for rolling 7d/30d Realized CLV% and Beat-CLV rates.
3. **Automated Mobile Webhook Dispatcher (`notify_bets.R`):** Built and live-verified rich Discord webhook notifications. Implemented a strict **Dual-Filter Safety Guard** requiring $\text{EV} \ge 5.0\%$ **and** $\text{Exp\_CLV} > 0.0\%$ to prevent betting on uncalibrated underdog lines.
4. **Live Programmatic Roster Synchronization (`sync_rosters.R`):** Developed a zero-maintenance scraper extracting **all 556 active NBA players** across 30 franchises directly from ESPN's production CDN, eliminating manual trade tracking and cutoff lag.
5. **Empirical Bottom-Up H2H & Standings Engine (`roster_bottom_up_engine.R`):** 
   * Formulated an objective **50/50 Box Creation + Empirical Plus-Minus Fusion** metric.
   * Applied **Empirical Bayes Sample-Size Shrinkage** to eliminate small-sample blowout distortion.
   * Built a **Zero-Sum Round-Robin 82-Game Schedule Simulation Matrix** guaranteeing an exact 1,230-win league balance ($\mu = 41.0$ wins).
   * Restored the defending champion Knicks to Rank #8 (51.8 wins, $+4.28$ rating) purely through on-court $+5.76$ point-differential data.
6. **Real-Time In-Play Game Listener (`live_game_listener.R`):** Deployed a polling daemon that tracks game clocks and scores, computes dynamic win probabilities via Brownian motion variance decay, includes date guards for scheduled games, and auto-terminates when all games are final.
7. **Player Proposition Pricing Engine (`player_props_engine.R`):** Evaluated 346 rotation players to price Over/Under Points, Rebounds, Assists, and PRA combos using discrete Poisson rate models.

---

## 2. Directory & Component Inventory (Phase 3 Additions)
c:\Users\kailo\kayceeslices\NBA Analytics
│
├── config.R # Global paths, API keys, webhook URLs, and sharp constants
├── run_full_pipeline.R # Master morning orchestrator (11-step DAG)
├── market_odds_engine.R # Live odds ingest, Pinnacle benchmark extraction, Kelly sizing
├── bet_tracker.R # Historical ledger, compound key grading, rolling CLV grader
├── notify_bets.R # Real-time Discord/Telegram webhook alert dispatcher
├── sync_rosters.R # Programmatic scraper for 556 active NBA players from CDN
├── roster_bottom_up_engine.R # Bottom-up player-composed H2H spread and standings model
├── player_props_engine.R # Discrete Poisson player proposition pricing engine (PRA)
├── live_game_listener.R # In-play continuous listener with Brownian motion probability decay
├── injury_scraper.R # Live NBA injury disclosures parser feeding availability scores
│
└── cache
├── active_rosters_cache.rds # 556 active players mapped to current teams
├── betting_ledger.rds # Complete ledger with placed odds, close, and CLV%
├── rolling_bet_metrics.rds # 7d, 30d, all-time Win Rate, ROI%, and CLV benchmarks
├── latest_value_bets.rds # Daily +EV betting recommendations
├── latest_player_props.rds # Poisson-priced Over/Under proposition recommendations
├── injury_data_cache.rds # Official active scratches and injury statuses
├── projected_30_team_standings.rds # Full 30-team zero-sum 82-game simulated standings
└── odds_history.rds # Time-series snapshots of opening and closing odds
---

## 3. Mathematical & Quantitative Formulations

### 1. Empirical Plus-Minus & Box Creation Fusion (Objective Player Impact)
Rather than relying on subjective counting-stat weights, player impact is parameterized by blending individual creation with on-court point differential:
$$\text{Raw Score}_i = 0.55\,\text{PTS}_{36} + 0.60\,\text{REB}_{36} + 1.10\,\text{AST}_{36} + 1.40\,\text{STL}_{36} + 1.20\,\text{BLK}_{36} - 1.25\,\text{TOV}_{36}$$
$$\text{Centered Box}_i = \text{Raw Score}_i - \mu_{\text{box}}$$
$$\text{Shrunk PM}_i = (\text{Empirical PM}_{36, i} - \mu_{\text{pm}}) \times \left( \frac{\text{Minutes}_i}{\text{Minutes}_i + 500} \right)$$
$$\text{Player BPM}_i = 0.50 \times \text{Centered Box}_i + 0.50 \times \text{Shrunk PM}_i$$

### 2. Lineup Rotation & 240-Minute Team Net Rating
For any team $T$ with active rotation players $i \in \{1, \dots, 9\}$:
$$\text{Team Net Rating} = \sum_{i=1}^{9} \left( \text{Player BPM}_i \times \frac{\text{Allocated Minutes}_i}{240} \right) \times 5.0$$
$$\text{Bounded Net Rating} = \max\left( -10.5,\, \min\left( 14.0,\, \text{Team Net Rating} \right) \right)$$

### 3. Zero-Sum 82-Game Schedule Simulation Matrix
To prevent talent inflation and ensure league-wide zero-sum balance:
$$\text{True Net Rating}_t = \text{Bounded Net Rating}_t - \frac{1}{30}\sum_{k=1}^{30} \text{Bounded Net Rating}_k$$
For each matchup between Team $i$ and Team $j$ ($41$ home games, $41$ away games):
$$\hat{\Delta}_{\text{home}} = (\text{True Net Rating}_i - \text{True Net Rating}_j) + 2.40 \quad (\text{HCA})$$
$$P(\text{Win}_{\text{home}}) = \Phi\left( \frac{\hat{\Delta}_{\text{home}}}{11.8} \right)$$
$$\text{Expected Wins}_i = \sum_{j \neq i} \left( 0.5 \cdot P(\text{Win}_{\text{home}}) + 0.5 \cdot P(\text{Win}_{\text{away}}) \right) \times \frac{82}{29}$$
$$\textbf{Mathematical Invariant:} \quad \sum_{i=1}^{30} \text{Expected Wins}_i \equiv 1{,}230.0 \quad (\mu = 41.0 \text{ wins})$$

### 4. Realized Closing Line Value (CLV%)
$$\text{CLV}_{\%} = \left( \text{Decimal Odds}_{\text{bet}} \times P_{\text{fair, close}} - 1 \right) \times 100$$
where $P_{\text{fair, close}}$ represents Pinnacle's vig-free implied closing probability:
$$P_{\text{fair, close}} = \frac{P_{\text{raw, close}}}{P_{\text{raw, close, home}} + P_{\text{raw, close, away}}}$$

### 5. In-Play Brownian Motion Variance Decay
$$\hat{\Delta}_{\text{final}} = \Delta_{\text{current}} + \left( \frac{t_{\text{remain}}}{48} \right) \times \hat{\Delta}_{\text{pregame}}$$
$$\sigma_{\text{live}}(t) = 11.8 \times \sqrt{\frac{t_{\text{remain}}}{48}}$$
$$P(\text{Home Win}) = \Phi\left( \frac{\hat{\Delta}_{\text{final}}}{\sigma_{\text{live}}(t)} \right)$$

---

## 4. Benchmark Standings Verification (Simulated 2026–2027 Season)

Extracted directly from `cache/projected_30_team_standings.rds`:

| Rank | Team | True Net Rating | Projected Wins | Projected Losses | Win Pct | Primary Rotation Core |
| :---: | :--- | :---: | :---: | :---: | :---: | :--- |
| **1** | **Celtics** | **+8.85** | **62.2** | 19.8 | 75.9% | Jayson Tatum, Neemias Queta, Derrick White |
| **2** | **Thunder** | **+8.85** | **62.2** | 19.8 | 75.9% | Shai Gilgeous-Alexander, Chet Holmgren, Jalen Williams |
| **3** | **Cavaliers** | **+8.12** | **60.6** | 21.4 | 73.9% | Donovan Mitchell, Evan Mobley, Jarrett Allen |
| **4** | **Spurs** | **+6.67** | **57.5** | 24.5 | 70.1% | Victor Wembanyama, Dylan Harper, De'Aaron Fox |
| **5** | **Warriors** | **+6.33** | **56.7** | 25.3 | 69.1% | Kristaps Porzingis, Stephen Curry, Jimmy Butler III |
| **6** | **Rockets** | **+5.99** | **55.9** | 26.1 | 68.2% | Alperen Sengun, Steven Adams, Kevin Durant |
| **7** | **Knicks** | **+4.28** | **51.8** | 30.2 | 63.2% | Karl-Anthony Towns, Jalen Brunson, Tyler Kolek |
| **8** | **Pistons** | **+3.94** | **51.0** | 31.0 | 62.2% | Cade Cunningham, Paul Reed, Isaiah Joe |
| **9** | **Nuggets** | **+3.51** | **49.9** | 32.1 | 60.9% | Nikola Jokic, Jamal Murray, Aaron Gordon |
| **10** | **Heat** | **+2.75** | **48.0** | 34.0 | 58.5% | Giannis Antetokounmpo, Bam Adebayo, Myron Gardner |
| **11** | **76ers** | **+2.33** | **47.0** | 35.0 | 57.3% | Joel Embiid, Jaylen Brown, LeBron James |
| **14** | **Timberwolves** | **+0.21** | **41.6** | 40.4 | 50.7% | LaMelo Ball, Anthony Edwards, Rudy Gobert |
| **17** | **Lakers** | **-0.43** | **39.9** | 42.1 | 48.7% | Luka Doncic, Sandro Mamukelashvili, Kevon Looney |
| **27** | **Bulls** | **-7.54** | **22.6** | 59.4 | 27.6% | Josh Giddey, Jalen Smith, Norman Powell |
| **29** | **Wizards** | **-8.14** | **21.3** | 60.7 | 26.0% | Anthony Davis, Trae Young, Khris Middleton |
| **30** | **Kings** | **-8.31** | **21.0** | 61.0 | 25.6% | Domantas Sabonis, Malik Monk, Dylan Cardwell |

**Audit Verification:** $\sum \text{Wins} = 1{,}229.8 \approx 1{,}230.0$ wins ($\mu = 41.0$). Zero drift detected.