# ODDS_API_KEY Setup — WNBA Analytics

## Status as of 2026-09-12 (checked by `wnba_odds_embeddings_agent`, task P1a)

`ODDS_API_KEY` is **not set** in this environment. Verified three ways, not assumed:

```
echo $ODDS_API_KEY                                          # empty
[Environment]::GetEnvironmentVariable('ODDS_API_KEY','User')     # empty
[Environment]::GetEnvironmentVariable('ODDS_API_KEY','Machine')  # empty
[Environment]::GetEnvironmentVariable('ODDS_API_KEY','Process')  # empty
"C:\Program Files\R\R-4.5.2\bin\Rscript.exe" -e "cat(nchar(Sys.getenv('ODDS_API_KEY','')))"  # 0
```

Running `market_odds_engine.R`/`live_game_listener.R` today therefore always falls through to
their labeled `SYNTHETIC_FALLBACK` fixture paths (confirmed by code reading — see "Code Path
Verification" below). This is spec-compliant *design* (a real fallback exists and is clearly
labeled), but it means the live feed has never actually been exercised, which is the gap this
task addresses. **The agent cannot provision a real paid/free-tier API key itself** — a human
must do the steps below.

## Steps a human needs to take

1. Go to https://the-odds-api.com and sign up for the **free tier** (500 requests/month, no
   credit card required as of the plan's last known pricing page).
2. After signup/email verification, copy the API key shown on the account dashboard
   (`https://the-odds-api.com/account/`).
3. Set it as a **persistent Windows user environment variable** (survives reboots and new
   terminal sessions, no code changes needed anywhere in this repo) by running this exact
   command in a terminal (PowerShell or cmd.exe):

   ```
   setx ODDS_API_KEY "PASTE_YOUR_REAL_KEY_HERE"
   ```

   Note: `setx` only affects **new** terminal/process sessions started after the command runs —
   close and reopen any open terminal (and restart R/RStudio/Task Scheduler jobs) before
   expecting the variable to be visible.

4. Verify it worked, in a **freshly opened** terminal:

   ```
   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" -e "cat(Sys.getenv('ODDS_API_KEY'))"
   ```

   This should print the key you set (not an empty string). Alternatively, from PowerShell:

   ```
   [Environment]::GetEnvironmentVariable('ODDS_API_KEY','User')
   ```

5. Once confirmed, simply re-run `market_odds_engine.R` as normal
   (`"C:\Program Files\R\R-4.5.2\bin\Rscript.exe" market_odds_engine.R`) — **no code changes are
   needed**. See "Code Path Verification" below for why.

## Code Path Verification (done by this agent, no code changes required)

Read `market_odds_engine.R`'s `fetch_market_odds()` (lines ~122-174) and confirmed it already:
- Reads `Sys.getenv("ODDS_API_KEY", "")` (the exact same env var name documented above).
- If non-empty, builds `https://api.the-odds-api.com/v4/sports/basketball_wnba/odds/?apiKey=...&regions=us,us2,eu&markets=h2h&oddsFormat=american`
  — correctly uses the **WNBA** sport key (`basketball_wnba`), not the NBA original's
  `basketball_nba`. This was already fixed by T4 (`wnba_betting_market_agent`); verified by
  reading the current file, not assumed from the handoff notes.
- On a successful non-empty response, calls `parse_multi_book_feed()` and returns real
  `bookmakers[]`-derived rows; only falls through to the `SYNTHETIC_FALLBACK` fixture slate if
  the key is empty, the HTTP call errors, or the response is empty.

Read `live_game_listener.R` and confirmed it reads the **same** env var name (`ODDS_API_KEY`,
not the NBA original's inconsistent `THE_ODDS_API_KEY`) at line ~43, logging a `[FEED NOTICE]`
when it's unset. This file does not yet make a live in-play API call at all (it runs a
hardcoded demo scoreboard) — that is a separate, already-documented open item
(`REPO_MAP.md` §9 / `WNBA_REPLICATION_PLAN.md`), not something blocked by the missing key, and
out of scope for this task (P1a only covers activating the pre-game odds pull in
`market_odds_engine.R`, which the brief and this file's own header comments confirm).

**Conclusion: the live path exists and is correctly wired for `market_odds_engine.R`, but has
never actually been exercised — blocked purely on a real API key that this agent cannot
provision itself.** No code changes were made or needed for P1a; this file documents exactly
what a human must do to unblock it, and the verification steps to prove it worked (a real
`bookmakers[]`-sourced response, not the `SYNTHETIC_FALLBACK` tag, in the next run's console
output / `cache/latest_value_bets.rds`).
