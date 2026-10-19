# Research Side Project: Prediction-Market Alpha from the WNBA Models — 2026-09-17

**Status:** feasibility confirmed, scaffolding started. **Not wired into the live pipeline** —
this is a `tools/`-only research track per the standard "research first, ask before folding into
production" default (see `empirical-signal-integration` skill's Step 2). No real money has been
risked; all API calls so far are public, read-only, unauthenticated market-data pulls.

## The question

Do this repo's existing model outputs (game margin/win probability from
`roster_bottom_up_engine.R`, player prop distributions from `player_props_engine.R` /
`copula_props_engine.R`, team-strength ratings from `rapm_engine.R`) diverge enough from
prediction-market prices to be tradeable, net of fees and execution risk — as opposed to
sportsbook lines, which `market_odds_engine.R` already compares against?

## Revenue-stream hypotheses (in rough order of how directly they map onto existing model outputs)

1. **Buy-and-hold mispriced game/series contracts.** Enter a Kalshi/Polymarket binary contract
   pre-game when its implied probability diverges from the model's win probability by more than
   the round-trip fee + a margin of safety, hold to resolution. Closest existing analog:
   `market_odds_engine.R`'s value-bet logic against sportsbook lines — same idea, different market.
2. **Same-day scalp: enter on divergence, exit before resolution.** Enter when the model/market gap
   is real but the position doesn't need to be held to resolution — exit once the market converges
   toward the model's view (or toward the eventual line move as new information, e.g. a starter's
   late-scratch, arrives) rather than waiting out full game variance. Requires **intraday
   liquidity** in the specific contract, which needs to be checked market-by-market, not assumed.
3. **Player-prop contracts** (`KXWNBAPTS`, `KXWNBAREB`, `KXWNBAAST`, `KXWNBAH2HPTS`,
   `KXWNBAH2HPRA`) against `copula_props_engine.R`'s existing Wilson/copula PRA distributions —
   this is the most direct reuse of an existing, already-validated model output of any revenue
   stream here.
4. **Season-long futures** (MVP/DPOY/ROY/Coach of the Year, win totals, seed/playoff-qualifier
   markets, championship) against `roster_bottom_up_engine.R`'s season projections
   (`cache/projected_wnba_standings.rds`) — much longer holding period, much lower bet frequency,
   but potentially the least efficiently priced markets (thinnest volume, least professional
   money) and a very direct reuse of existing output with no new model work.
5. **Cross-venue arbitrage** (same game, same side, priced differently on Kalshi vs. Polymarket vs.
   a sportsbook's implied probability) — doesn't require the WNBA model to be right at all, only
   requires the two venues to disagree. Worth scoping as a side quest since it's the lowest-risk of
   the five (not exposed to the model being wrong), but it's a market-microstructure project, not a
   modeling one — flagging it as a separate, smaller research thread rather than folding it into
   the model-vs-market comparison above.
6. **Quarter/half-winner and live in-game markets** (`KXWNBA1QWINNER`, `KXWNBA2HWINNER`, etc.) —
   would require a live win-probability model conditioned on real-time score/clock state, which
   this repo does not currently have (`roster_bottom_up_engine.R`'s live rating is pre-game only).
   Flagging as a real possible revenue stream but explicitly **out of scope** until/unless a
   live in-game WP model is built — do not attempt without one.

## Feasibility findings (2026-09-17, real API calls — see "How this was checked" below)

- **Kalshi**: fully public, unauthenticated REST API at
  `https://api.elections.kalshi.com/trade-api/v2` (`/markets`, `/series`, `/candlesticks`). No API
  key needed for read-only market data; trading requires a funded account + KYC.
  [Kalshi API docs](https://docs.kalshi.com), confirmed live 2026-09-17.
- **Coverage is broad and maps almost 1:1 onto this repo's existing model surface**: found live
  series for game moneyline (`KXWNBAGAME`), spreads/totals (`KXWNBASPREAD`, `KXWNBATOTAL`),
  quarter/half winners, player points/rebounds/assists/threes props (including
  head-to-head player props: `KXWNBAH2HPTS`, `KXWNBAH2HPRA`), season awards (MVP, DPOY, ROY, Coach,
  Sixth Player), win totals, seeds, and championship futures — confirmed via a live `/series` pull
  (161 WNBA-tagged series as of 2026-09-17).
- **Real intraday price history exists and is pullable**: confirmed on a real settled game
  (`KXWNBAGAME-26AUG30CONNDAL-DAL`), 1,199 one-minute candlesticks with open/high/low/close
  bid/ask and volume, tracking price convergence from ~$0.87 pre-resolution toward $1.00 at
  settlement. This is sufficient granularity for backtesting both the buy-and-hold and same-day
  scalp hypotheses above.
- **Real join-key trap found, same shape as the documented `CONN`/`CON` wehoop issue** (see
  CLAUDE.md): Kalshi's own event tickers use `CONN` for the Connecticut Sun
  (`KXWNBAGAME-26AUG30CONNDAL-CONN`), while `config.R`'s `WNBA_TEAMS` uses `CON`. **A second,
  independent mismatch was found empirically on `tools/research_prediction_markets.R`'s first real
  run** (not assumed, not from a wehoop precedent): Kalshi uses `PDX` for the Portland Fire, while
  `WNBA_TEAMS` uses `POR`. Additionally, Kalshi's human-readable team labels
  (`yes_sub_title`/`no_sub_title`) are **city-only** ("Washington", "Golden State", "Portland") not
  full franchise names ("Washington Mystics", "Golden State Valkyries", "Portland Fire") — a naive
  exact-string join against `WNBA_TEAMS`'s values will silently return zero matches for every team.
  Both code mismatches are now handled in `tools/research_prediction_markets.R`'s
  `normalize_kalshi_team_code()` / `KALSHI_TEAM_CODE_MAP`, verified to produce a real 15/15 match
  against `WNBA_TEAMS`. **Use that shared helper for any future join** (mirroring
  `normalize_team_abbreviation()`'s role for wehoop) rather than reimplementing the mapping ad hoc
  — and re-run the overlap check whenever a new team code is encountered, since this is exactly the
  kind of drift that silently corrupts a join if assumed rather than checked.
- **Polymarket**: also has live WNBA markets and a public CLOB API; Polymarket US (the
  CFTC-regulated venue, launched Dec 2025) is the only lawful venue for US residents to actually
  trade on. Some states have separate cease-and-desist / gray-zone status on prediction markets
  generally (irrelevant to research/backtesting with public market data, relevant only before any
  live trading). Not yet API-tested from this machine — next step, see below.

## How this was checked

Live, unauthenticated `curl` calls against `https://api.elections.kalshi.com/trade-api/v2/{markets,series,candlesticks}` during this session, plus `WebSearch` for Polymarket/Kalshi legal and API-access status. No credentials used or required. No temp files were kept — this doc is the durable record of what was pulled.

## Explicitly deferred / not yet done

- No backtest has been run yet. Real intraday price paths exist (confirmed above) but no
  model-vs-market divergence has actually been measured.
- No Polymarket API call has been made yet from this machine (Kalshi checked first since it has
  the more clearly public, no-auth API).
- No paper-trading or live-trading infrastructure exists. This is a research-only track;
  standing up real order execution would be a separate, much larger, explicitly-authorized project
  given it involves real money and a regulated venue.
- The `normalize_kalshi_team_code()` mapping described above has not been built yet — needed
  before any real join between Kalshi contracts and this repo's team-keyed caches.

## Next steps (in order)

1. ~~Build `normalize_kalshi_team_code()` ... confirm a real 15/15 team match against
   `WNBA_TEAMS`~~ **DONE** (`tools/research_prediction_markets.R`, real 15/15 match confirmed).
2. ~~Pull a real historical sample of settled `KXWNBAGAME` contracts ... measure divergence against
   a retrospective, no-lookahead win probability~~ **DONE 2026-09-17, real result: NO EDGE FOUND.**
   Full writeup: `docs/prediction_market_divergence_findings.md`, reproducible in
   `tools/research_prediction_market_divergence.R`. N=52 real games (2026-07-13 to 2026-08-30):
   model Brier score (0.2047) worse than the market's (0.1963), and at every divergence threshold
   tested the **market's** favored side won substantially more often than the model's favored side
   (≈67-71% vs ≈37-44%) — the opposite of what a tradeable-edge hypothesis needs. **Recommendation:
   do NOT proceed to step 3 (backtest/P&L infrastructure) for hypotheses #1/#2 (game-market
   buy-and-hold/scalp) — close that thread as "tested, no edge found."** See the findings doc's
   "Limitations" section for the real caveats (N=52 is small, single 7-week window, 60% of matched
   games lacked a usable pre-tip-off candlestick) before treating this as fully conclusive, but it
   is not a promising enough signal to justify building staking/execution infrastructure on.
3. ~~If #2 shows a real, statistically defensible divergence: build a proper backtest~~ **NOT
   STARTED, and per the above, not currently recommended for hypotheses #1/#2** — #2 showed the
   opposite of the needed result. Do not build P&L/staking logic against the game-market hypothesis
   without a materially different (larger-N, full-season) re-measurement first.
4. ~~Repeat the same divergence-measurement methodology for player props (hypothesis #3) and
   season futures (hypothesis #4)~~ **DONE 2026-09-17, including a follow-up re-test of #4 with a
   larger sample and a better-calibrated probability model.** Full writeup:
   `docs/prediction_market_divergence_findings.md`. **#3: no edge found** (model Brier 0.1977 vs
   market's 0.1931, market's favored side right more often at most divergence thresholds) — close as
   tested, same as #1/#2. **#4: v1 looked promising (N=26, model favored-side right 84% vs market's
   60%) but did NOT survive a harder re-test.** The re-test (`tools/research_prediction_market_futures_divergence.R`,
   rewritten) fixed two real weaknesses: (a) sample size, via multi-snapshot sampling of each
   market's full daily candlestick history (907 snapshots / 53 real markets, clustered stats
   reported since within-market snapshots aren't independent) instead of one price-at-open
   observation per market; (b) calibration, via a Beta-Binomial replacing the plug-in binomial (which
   had produced near-0/near-1 overconfident probabilities). The re-test ALSO caught and corrected a
   real evaluation bug: `KXWNBAWINS` markets close early once mathematically decided, so snapshots
   close to a market's real close date are trivially easy for both sides to call correctly — splitting
   into EARLY (≥30 days before close, the genuine forecasting test) vs LATE regimes showed the
   market's favored side right 96.2% vs the model's 75.5% in the EARLY regime, reversing v1's
   conclusion. **Net result: all four tested hypotheses (#1/#2, #3, #4) now close as "no confirmed
   edge."** MVP/DPOY/ROY/COY/championship futures checked and have ZERO settled Kalshi markets as of
   2026-09-17 (2026 season awards not yet decided) — not testable, and this repo has no
   award-prediction model to compare against regardless.
5. **Do not build backtest/staking/P&L infrastructure (old step 3) for any hypothesis tested so
   far** — none showed a defensible edge after appropriately rigorous (leakage-free, clustered,
   regime-aware) measurement. The #4 reversal is itself the most useful finding on this thread: a
   promising-looking first-pass result did not survive a harder re-test, which is the concrete case
   for why this plan's "measure before building" discipline exists.
6. Scope the cross-venue arbitrage idea (#5) as its own small side-thread once Polymarket's API has
   been checked the same way Kalshi's was here — unaffected by any of the above results since it
   doesn't depend on the WNBA model being right.
