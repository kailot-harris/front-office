==================================================================
           WNBA VALUE BETTING & CLV ENGINE (+EV IDENTIFIER)        
==================================================================

[FEED] Querying live multi-region WNBA odds from The Odds API...
[2026-09-12 08:13:47] [INFO] [market_odds_engine.R] Querying live multi-region WNBA odds from The Odds API. | call: fetch_market_odds()
[FEED SUCCESS] Parsing 8 live WNBA games from API.
[2026-09-12 08:13:47] [INFO] [market_odds_engine.R] Odds API returned 8 live WNBA games. | call: fetch_market_odds() | rows: 8
[2026-09-12 08:13:47] [INFO] [market_odds_engine.R] Parsed 8 live games with usable bookmaker odds. | call: parse_multi_book_feed() | rows: 8


game_date    tip_time_est   Matchup                                    Recommended_Bet             Book           Line   Model_Win_Prob   EV_Percent   Exp_CLV   Bankroll_Rec  Status                           
-----------  -------------  -----------------------------------------  --------------------------  -----------  ------  ---------------  -----------  --------  -------------  ---------------------------------
2026-09-17   20:00          Washington Mystics vs. Chicago Sky         Chicago Sky (Home)          1xBet           139            0.833        99.09     -2.45           3.00  ★ VALUE BET (+EV)                
2026-09-17   20:00          Los Angeles Sparks vs. Dallas Wings        Los Angeles Sparks (Away)   DraftKings      270            0.349        29.13     -1.07           2.70  ★ VALUE BET (+EV)                
2026-09-17   22:00          Phoenix Mercury vs. Portland Fire          Phoenix Mercury (Away)      1xBet           104            0.616        25.66      5.45           3.00  🔥 SHARP +EV (EV ≥ 5% & CLV > 0) 
2026-09-17   22:00          Las Vegas Aces vs. Seattle Storm           Las Vegas Aces (Away)       DraftKings     -353            0.790         1.38     -2.52           1.22  No Action                        
2026-09-17   19:30          Connecticut Sun vs. Atlanta Dream          Atlanta Dream (Home)        GTbets        -1110            0.929         1.27     -3.92           3.00  No Action                        
2026-09-18   22:00          Portland Fire vs. Golden State Valkyries   Portland Fire (Away)        DraftKings      895            0.192        91.04     36.86           2.54  🔥 SHARP +EV (EV ≥ 5% & CLV > 0) 
2026-09-18   19:30          New York Liberty vs. Minnesota Lynx        New York Liberty (Away)     DraftKings      262            0.497        79.91      9.37           3.00  🔥 SHARP +EV (EV ≥ 5% & CLV > 0) 
2026-09-18   19:30          Indiana Fever vs. Toronto Tempo            Toronto Tempo (Home)        FanDuel         490            0.225        32.75      1.72           1.67  🔥 SHARP +EV (EV ≥ 5% & CLV > 0) 

[SUCCESS] Timezone-calibrated WNBA value bets saved to: c:/Users/kailo/kayceeslices/WNBA Analytics/cache/latest_value_bets.rds
[2026-09-12 08:13:48] [INFO] [market_odds_engine.R] Saved 8 value bets to c:/Users/kailo/kayceeslices/WNBA Analytics/cache/latest_value_bets.rds. | call: evaluate_betting_slate() | rows: 8 | out_path: c:/Users/kailo/kayceeslices/WNBA Analytics/cache/latest_value_bets.rds
# A tibble: 8 × 14
  game_date  tip_time_est Matchup                                  Recommended_Bet          Team  Book   Line Model_Win_Prob EV_Percent Exp_CLV Bankroll_Rec Status sharp_line game_id
  <date>     <chr>        <chr>                                    <chr>                    <chr> <chr> <dbl>          <dbl>      <dbl>   <dbl>        <dbl> <chr>       <dbl> <chr>  
1 2026-09-17 20:00        Washington Mystics vs. Chicago Sky       Chicago Sky (Home)       Chic… 1xBet   139          0.833      99.1    -2.45         3    "★ VA…        145 e1345b…
2 2026-09-17 20:00        Los Angeles Sparks vs. Dallas Wings      Los Angeles Sparks (Awa… Los … Draf…   270          0.349      29.1    -1.07         2.7  "★ VA…        274 61b156…
3 2026-09-17 22:00        Phoenix Mercury vs. Portland Fire        Phoenix Mercury (Away)   Phoe… 1xBet   104          0.616      25.7     5.45         3    "\U00…       -107 58a4c9…
4 2026-09-17 22:00        Las Vegas Aces vs. Seattle Storm         Las Vegas Aces (Away)    Las … Draf…  -353          0.79        1.38   -2.52         1.22 "No A…       -316 b9b0b2…
5 2026-09-17 19:30        Connecticut Sun vs. Atlanta Dream        Atlanta Dream (Home)     Atla… GTbe… -1110          0.929       1.27   -3.92         3    "No A…       -743 0fd1d4…
6 2026-09-18 22:00        Portland Fire vs. Golden State Valkyries Portland Fire (Away)     Port… Draf…   895          0.192      91.0    36.9          2.54 "\U00…        627 210b4f…
7 2026-09-18 19:30        New York Liberty vs. Minnesota Lynx      New York Liberty (Away)  New … Draf…   262          0.497      79.9     9.37         3    "\U00…        231 59427f…
8 2026-09-18 19:30        Indiana Fever vs. Toronto Tempo          Toronto Tempo (Home)     Toro… FanD…   490          0.225      32.8     1.72         1.67 "\U00…        480 51b442…