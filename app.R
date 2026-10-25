# ==============================================================================
# app.R (WNBA port)
# Full Production 8-Tab Quantitative WNBA Sports Trading Terminal
# Path: app.R
#
# Ported from NBA Analytics/app.R (T5 / wnba_live_dashboard_agent). Every cache/*.rds path
# below was cross-checked against T0-T4's ACTUAL Handoff Notes in task_assignments.md, not
# guessed from the plan document — see inline comments at each reactive for the exact source.
#
# Preserves the "zero live API dependencies on load" principle (REPO_MAP.md §8): every
# reactive below reads from disk only (cache/*.rds, root .rds/.csv), and falls back to an
# in-process synthetic table or a same-session engine re-run if a cache is missing — it never
# performs network I/O itself. The self-installing-packages block at the top is preserved
# unchanged (same package set as the NBA original; no new package added for the embeddings fix
# below, which uses only base R `prcomp()` plus already-loaded ggplot2/dplyr).
#
# KNOWN FIX APPLIED PER THE T5 BRIEF (WNBA_REPLICATION_PLAN.md §(d) step 15 /
# REPO_MAP.md §9): the NBA original's "Team Embeddings" tab actually plotted
# `team_shot_quality.rds` (points-created vs. shooting-luck) mislabeled as "embeddings" — it
# never touched `team_embeddings.csv` at all. This WNBA port's Tab 5 now genuinely reads
# `team_embeddings.csv`'s real 16-D vectors (T3's real PyTorch-trained output, 15 rows x 16
# dims — see T3 Handoff Notes) and (a) projects them to 2D via `prcomp()` (PCA) for a scatter
# plot, and (b) renders `team_similarity_matrix.csv` as a real cosine-similarity heatmap. Both
# panels carry forward T3's own caveat (embeddings were trained on FABRICATED mock matchup
# data, since no real `cache/games_for_embeddings.csv` exists yet — see T3 Handoff Notes) so
# nobody reads real team-similarity meaning into a demo-data artifact.
#
# OFF-SEASON BANNER (per WNBA_REPLICATION_PLAN.md §(e) risk #1 and the T5 brief item 6): the
# WNBA's off-season is much longer than the NBA's (~7 months vs ~3). Rather than silently
# serving whatever is in cache/*.rds as if it were live, a persistent banner at the top of
# every tab computes today's date against the known WNBA season window and says so explicitly.
# ==============================================================================

# Ensure dependencies are available (unchanged package set from the NBA original - the
# embeddings-tab fix below uses only base R prcomp() + already-loaded ggplot2/dplyr).
# FIX H-3 (adjacent latent defect): "stringr" added. app.R:1214's `word()` call in the Tab 8
# diagnostics reactive was already unqualified with stringr never attached here - it would have
# thrown "could not find function \"word\"". It never fired only because H-3's dead box-score path
# returned NULL two lines earlier; fixing H-3 unmasks it. Both the attach and the stringr:: call
# qualifications below are required for Tab 8 to render at all.
req_pkgs <- c("shiny", "shinydashboard", "DT", "ggplot2", "dplyr", "tidyr", "scales", "plotly", "stringr")
new_pkgs <- req_pkgs[!(req_pkgs %in% installed.packages()[, "Package"])]
if (length(new_pkgs)) install.packages(new_pkgs)

suppressPackageStartupMessages({
  library(shiny)
  library(shinydashboard)
  library(DT)
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(scales)
  library(stringr)
  # PRE-EXISTING STARTUP BLOCKER found while testing P4-B (present at Wave 0 baseline commit
  # 20b12fd, NOT introduced by Phase 4): "plotly" was listed in req_pkgs above and INSTALLED, but
  # never attached, while the UI calls plotlyOutput() 3x (Tabs 8) and the server calls
  # renderPlotly()/ggplotly(). None of shiny/shinydashboard/DT/ggplot2/dplyr/tidyr/scales attach
  # plotly transitively (verified: `"package:plotly" %in% search()` is FALSE after loading all
  # seven). app.R therefore aborted at UI-construction time with
  #   Error in plotlyOutput("plot_residual_scatter", height = 450): could not find function "plotlyOutput"
  # i.e. the whole dashboard - every tab, not just Tab 8 - failed to boot. Attaching it here is a
  # prerequisite for any headless verification of H-3/C-3 at all.
  library(plotly)
})

# FIX M-6 (Phase 4): the local scalar `%||%` that used to live on this line has been DELETED.
# It was the unhardened form (`!is.na(a)` unsubscripted), which hard-errors on R 4.3+ when applied
# to a vector - the exact defect that produced the 2026-09-12 Injury-tab incident documented in
# tools/headless_dashboard_probe.R. There is now exactly ONE definition of this operator in the
# repo, the hardened `is.na(a)[1]` form in logging_utils.R (Wave 1, agent_foundation), sourced
# below. Do not re-add a local copy here: two definitions make the operator's behaviour depend on
# source order (see SECURITY_TECHNICAL_REVIEW.md M-6).

# Margin -> win-probability sigma for the interactive matchup calculator (Tab 7), plus WNBA_HCA
# (FIX C-1) and the CACHE_* path constants (FIX H-3 / L-6). Read from config.R if available (this
# is a local file read, not a network call - still consistent with the "zero live API
# dependencies" principle) rather than re-hardcoding the NBA's 11.2; falls back to the same known
# WNBA_MARGIN_SIGMA value (14.0, T2's real empirical derivation - see config.R's own comment
# block) if config.R can't be sourced for any reason.
if (file.exists("config.R")) {
  tryCatch(source("config.R"), error = function(e) NULL)
}
if (!exists("WNBA_MARGIN_SIGMA")) WNBA_MARGIN_SIGMA <- 14.0
# FIX C-1: home-court advantage is a config.R constant now, never a literal in this file.
if (!exists("WNBA_HCA")) WNBA_HCA <- 2.40

# FIX M-6: source the canonical hardened `%||%` (and the redacting logger) from logging_utils.R.
# Deliberately NOT wrapped in a file.exists()/tryCatch fallback that re-defines the operator: a
# second definition anywhere is precisely the defect M-6 reports, so this file must have zero.
# Sourced AFTER config.R so PROJECT_DIR/LOG_DIR resolve against the real project root.
# logging_utils.R's own DuckDB init is already fail-safe (it tolerates the log DB being locked by
# a concurrently-running pipeline and spills to logs/logs_pending_<pid>.tsv), so sourcing it from
# the dashboard cannot crash app startup.
source("logging_utils.R")

# Plot/table "build the object from already-prepared data" helpers for 15 render* outputs,
# extracted out of this file's server function (GitHub issue #49 / Slice 5 of #43). See that
# file's header comment for the full design rationale (no input$/session reference inside any
# helper there, so a later Shiny app can reuse them outside this file's reactive context).
source("dashboard_render_helpers.R")

# ------------------------------------------------------------------------------------------
# WNBA season window (for the off-season banner below). 2026 season: regular season
# 2026-05-08 to 2026-09-24, playoffs 2026-09-27 onward (verified via web search 2026-09-12,
# wnba.com "2026 Regular Season Key Dates"/"2026 Schedule Release"). Uses a May-through-October
# buffer window (matching schedule_daily.bat's guard) rather than the exact day-precision dates,
# since a Finals could run into late October and the exact start date shifts slightly year to
# year - re-verify this window at the start of each future season.
# ------------------------------------------------------------------------------------------
is_wnba_in_season <- function(check_date = Sys.Date()) {
  mm <- as.integer(format(check_date, "%m"))
  mm >= 5 && mm <= 10
}

# ------------------------------------------------------------------------------
# UI Layout
# ------------------------------------------------------------------------------
ui <- dashboardPage(
  skin = "purple",
  dashboardHeader(
    title = span(tagList(icon("basketball-ball"), " WNBA Alpha Terminal v5.0")),
    titleWidth = 320
  ),
  dashboardSidebar(
    width = 320,
    sidebarMenu(
      menuItem("Daily Actionable Edges", tabName = "tab_daily_edges", icon = icon("crosshairs")),
      menuItem("Steam Radar & Line Movement", tabName = "tab_steam_radar", icon = icon("wave-square")),
      menuItem("Injury & Load Monitor", tabName = "tab_injuries", icon = icon("user-injured")),
      menuItem("Bet Tracker & Performance Audit", tabName = "tab_bet_tracker", icon = icon("chart-line")),
      menuItem("Team Embeddings & Similarity", tabName = "tab_embeddings", icon = icon("project-diagram")),
      menuItem("Model Calibration & Reliability", tabName = "tab_calibration", icon = icon("balance-scale")),
      menuItem("WNBA Standings & Matchup Calc", tabName = "tab_standings_calc", icon = icon("calculator"), badgeLabel = "P5", badgeColor = "green"),
      menuItem("Model Diagnostics", tabName = "tab_model_diagnostics", icon = icon("microscope"), badgeLabel = "XAI", badgeColor = "orange"),
      menuItem("Player Proposition Terminal (PRA)", tabName = "tab_player_props", icon = icon("user-astronaut"), badgeLabel = "ZINB", badgeColor = "yellow"),
      menuItem("Clutch & Shot Profile", tabName = "tab_clutch_shot_profile", icon = icon("fire"), badgeLabel = "PBP", badgeColor = "aqua")
    )
  ),
  dashboardBody(
    tags$head(
      tags$style(HTML("
        .content-wrapper, .right-side { background-color: #0f141c; color: #ecf0f1; }
        .box { background: #1a222d; border-top: 3px solid #9b59b6; border-radius: 6px; }
        .box-header { color: #ecf0f1; font-weight: bold; }
        .small-box { border-radius: 6px; }
        .dataTables_wrapper { color: #ecf0f1; }
        table.dataTable tbody tr { background-color: #1a222d !important; color: #ecf0f1 !important; }
        table.dataTable tbody tr:hover { background-color: #243040 !important; }
        .selectize-input, .selectize-dropdown { background-color: #243040 !important; color: #ffffff !important; border: 1px solid #34495e !important; }
        .wnba-season-banner { padding: 10px 18px; margin: -15px -15px 15px -15px; font-weight: bold; text-align: center; }
      "))
    ),
    # ----------------------------------------------------------------------
    # Off-Season Banner (persistent across all tabs) - per WNBA_REPLICATION_PLAN.md §(e)
    # risk #1 and the T5 brief item 6: never silently serve cached data as if it were live
    # during the ~7-month WNBA off-season.
    # ----------------------------------------------------------------------
    uiOutput("season_status_banner"),
    tabItems(
      # ------------------------------------------------------------------------
      # Tab 1: Daily Edges
      # ------------------------------------------------------------------------
      tabItem(
        tabName = "tab_daily_edges",
        fluidRow(
          valueBoxOutput("box_slate_count", width = 3),
          valueBoxOutput("box_top_edge", width = 3),
          valueBoxOutput("box_active_kelly", width = 3),
          valueBox("Pinnacle / Consensus", "Benchmark Sharp Feed (WNBA books thinner than NBA - expect more consensus fallback)", icon = icon("university"), color = "purple", width = 3)
        ),
        fluidRow(
          box(
            title = "Market Slate Date & Lookahead Controls", width = 12, status = "info",
            fluidRow(
              column(5, selectInput("slate_date_picker", "Select Target Game Slate:", choices = c("All Scheduled Dates (Full Catalog)"))),
              column(7, p(style = "margin-top: 25px; color: #bdc3c7;",
                          "\u2139\ufe0f Filter by specific date to inspect individual game slates or choose 'Full Catalog'. NOTE: if no ODDS_API_KEY is configured, this table runs on a clearly-labeled SYNTHETIC_FALLBACK fixture slate (see market_odds_engine.R) - not live WNBA odds."))
            )
          )
        ),
        fluidRow(
          box(
            title = "Actionable Market Discrepancies", width = 12, status = "primary", solidHeader = TRUE,
            DTOutput("tbl_daily_edges")
          )
        )
      ),

      # ------------------------------------------------------------------------
      # Tab 2: Steam Radar
      # ------------------------------------------------------------------------
      tabItem(
        tabName = "tab_steam_radar",
        fluidRow(
          box(
            title = "Live Steam Alerts & Cross-Book Line Movement", width = 12, status = "warning", solidHeader = TRUE,
            p("Monitors rapid line movement and detects retail sportsbooks lagging behind sharp limits."),
            DTOutput("tbl_steam_radar")
          )
        )
      ),

      # ------------------------------------------------------------------------
      # Tab 3: Injury Monitor
      # ------------------------------------------------------------------------
      tabItem(
        tabName = "tab_injuries",
        fluidRow(
          box(
            title = "Official WNBA Injury Designations & Point Spread Impact", width = 12, status = "danger", solidHeader = TRUE,
            p("WNBA injury-report cadence/granularity is lower than the NBA's official report (per REPO_MAP.md/T1 Handoff Notes) - treat as directionally useful, expect more lag."),
            DTOutput("tbl_injuries")
          )
        )
      ),

      # ------------------------------------------------------------------------
      # Tab 4: Bet Tracker
      # ------------------------------------------------------------------------
      tabItem(
        tabName = "tab_bet_tracker",
        fluidRow(
          valueBoxOutput("kpi_rolling_7d_clv", width = 3),
          valueBoxOutput("kpi_rolling_30d_clv", width = 3),
          valueBoxOutput("kpi_beat_clv_rate", width = 3),
          valueBoxOutput("kpi_current_drawdown", width = 3)
        ),
        fluidRow(
          box(
            title = "Bankroll Growth vs High-Water Mark & Capital Preservation Tiers", width = 8, status = "primary",
            plotOutput("plot_bankroll_drawdown", height = 320)
          ),
          box(
            title = "Risk Management Engine Diagnostics", width = 4, status = "info",
            verbatimTextOutput("txt_risk_engine_status")
          )
        ),
        fluidRow(
          box(
            title = "Historical Graded Ledger & CLV Audit (cold-start synthetic seed ledger - no real betting history exists yet)", width = 12,
            DTOutput("tbl_graded_ledger")
          )
        )
      ),

      # ------------------------------------------------------------------------
      # Tab 5: Team Embeddings (FIXED per the T5 brief - now plots real 16-D vectors)
      # ------------------------------------------------------------------------
      tabItem(
        tabName = "tab_embeddings",
        fluidRow(
          box(
            title = "15-Team Latent Style Space (PCA Projection of Real 16-D team_embeddings.csv)", width = 6, status = "primary",
            p(style = "color: #bdc3c7; font-size: 12px;",
              "Trained via team_embeddings.py's real PyTorch TeamEmbeddingNet. UPDATED (P1, 2026-09-12): now trained on cache/games_for_embeddings.csv, built from T1's real box_scores_cache.rds (1,953 real WNBA games) - no longer the earlier FABRICATED mock matchup data. See task_assignments_phase2.md's P1 Handoff Notes."),
            plotOutput("plot_embeddings_pca", height = 420)
          ),
          box(
            title = "15x15 Cosine-Similarity Heatmap (team_similarity_matrix.csv)", width = 6, status = "primary",
            p(style = "color: #bdc3c7; font-size: 12px;",
              "Same real-data update as the PCA panel applies here - diagonal is exactly 1.0 by construction."),
            plotOutput("plot_embeddings_heatmap", height = 420)
          )
        )
      ),

      # ------------------------------------------------------------------------
      # Tab 6: Model Calibration
      #
      # FIXED (P3b, GAP_REMEDIATION_PLAN.md / agent9.md): this tab now calls
      # live_calibration.R's real calibration_analysis() against real predicted-
      # probability/actual-outcome pairs in cache/model_calibration_input.rds
      # (built by build_calibration_cache.R from T1's real box_scores_cache.rds,
      # 1,902 real WNBA games 2019-2026 with a point-in-time, no-look-ahead
      # rolling-margin win-probability model — see build_calibration_cache.R's
      # header for the full methodology and why this substitutes for a saved
      # ML-model prediction cache, which does not exist anywhere in this repo).
      # If that cache is missing, the tab builds it on the fly from real data
      # (still real, just not yet cached) rather than falling back to a fake
      # curve; only if box_scores_cache.rds itself is unavailable does it fall
      # back to a clearly-labeled illustrative curve.
      # ------------------------------------------------------------------------
      tabItem(
        tabName = "tab_calibration",
        fluidRow(
          valueBoxOutput("vbox_brier", width = 4),
          valueBoxOutput("vbox_bss", width = 4),
          valueBoxOutput("vbox_logloss", width = 4)
        ),
        fluidRow(
          box(
            title = "Model Probability Calibration & Brier Reliability Diagnostics", width = 12, status = "primary",
            p(style = "color: #bdc3c7; font-size: 12px;",
              uiOutput("calibration_source_caption")),
            plotOutput("plot_calibration_curve", height = 450)
          )
        )
      ),

      # ------------------------------------------------------------------------
      # Tab 7: Standings & Calculator
      # ------------------------------------------------------------------------
      tabItem(
        tabName = "tab_standings_calc",
        fluidRow(
          box(
            title = "Interactive Multi-Factor Matchup Spread & Moneyline Calculator", width = 12, status = "success", solidHeader = TRUE,
            fluidRow(
              column(4, selectInput("calc_away_team", "Select Away Team:", choices = c("Loading..."))),
              column(4, selectInput("calc_home_team", "Select Home Team:", choices = c("Loading..."))),
              # FIX C-1: default seeded from config.R's WNBA_HCA constant, not a restated literal.
              column(4, numericInput("calc_hca", "Home Court Advantage (pts):", value = WNBA_HCA, min = 0, max = 6, step = 0.1))
            ),
            fluidRow(
              valueBoxOutput("box_calc_spread", width = 4),
              valueBoxOutput("box_calc_win_prob", width = 4),
              valueBoxOutput("box_calc_fair_ml", width = 4)
            )
          )
        ),
        fluidRow(
          box(
            title = "15-Team WNBA Bottom-Up Power Ratings & Projected Records", width = 12, status = "primary",
            DTOutput("tbl_bottom_up_standings")
          )
        )
      ),

      # ------------------------------------------------------------------------
      # Tab 8: Model Diagnostics (XAI & Error Analysis)
      # ------------------------------------------------------------------------
      tabItem(
        tabName = "tab_model_diagnostics",
        # FIX C-3: an explicit "N real resolved predictions" provenance line above the metrics, so
        # an empty real sample is visible as an honest zero rather than silently backfilled with
        # the DIAG_* synthetic fixtures that used to be the only rows this tab could ever show.
        fluidRow(column(12, uiOutput("diag_provenance"))),
        fluidRow(
          valueBoxOutput("vbox_mae", width = 4),
          valueBoxOutput("vbox_rmse", width = 4),
          valueBoxOutput("vbox_bias", width = 4)
        ),
        fluidRow(
          box(
            title = "Predicted vs. Actual Margin (Residual Analysis)", width = 8, status = "primary",
            plotlyOutput("plot_residual_scatter", height = 450)
          ),
          box(
            title = "Residual Distribution", width = 4, status = "info",
            plotlyOutput("plot_residual_dist", height = 450)
          )
        ),
        fluidRow(
          box(
            title = "Mean Residual by Team (Bias Identification)", width = 12, status = "primary",
            plotlyOutput("plot_team_bias", height = 400)
          )
        )
      ),

      # ------------------------------------------------------------------------
      # Tab 9: Player Proposition Terminal
      # ------------------------------------------------------------------------
      tabItem(
        tabName = "tab_player_props",
        fluidRow(
          box(
            title = "Zero-Inflated Negative Binomial (ZINB) Filter Controls", width = 12, status = "warning", solidHeader = TRUE,
            fluidRow(
              column(3, selectInput("props_stat_filter", "Statistic Category:",
                                    choices = c("All Categories", "PTS", "REB", "AST", "FG3M", "STL", "BLK"))),
              column(3, sliderInput("props_ev_slider", "Min Expected Value (EV %):", min = 0, max = 25, value = 5.0, step = 0.5)),
              column(3, selectInput("props_side_filter", "Recommendation Filter:", choices = c("ALL", "OVER", "UNDER"))),
              column(3, textInput("props_search_player", "Filter by Player Name:", placeholder = "e.g. Wilson, Clark"))
            )
          )
        ),
        fluidRow(
          box(
            title = "Actionable Player Proposition Discrepancies (Click row to graph)", width = 8, status = "primary",
            DTOutput("tbl_props_terminal")
          ),
          box(
            title = "ZINB Probability Density Curve", width = 4, status = "info",
            plotOutput("plot_prop_zinb_curve", height = 360)
          )
        )
      ),

      # ------------------------------------------------------------------------
      # Tab 10: Clutch & Shot Profile (pbp_engine.R's real ESPN play-by-play
      # player features: CACHE_PLAYER_PBP_FEATURES = cache/player_pbp_features.rds).
      # ------------------------------------------------------------------------
      tabItem(
        tabName = "tab_clutch_shot_profile",
        fluidRow(
          box(
            title = "Real Play-by-Play Clutch / Assist / Shot-Mix Player Features", width = 12, status = "info", solidHeader = TRUE,
            p(style = "color: #bdc3c7; font-size: 12px;",
              "Built from real ESPN play-by-play (wehoop::load_wnba_pbp(), see pbp_engine.R) - not a synthetic fixture. ",
              "'Clutch' = period >= 4, <=5:00 remaining in that period, score margin <= 5 at the event. ",
              "Shot-mix percentages (Rim / Off-Dribble Jumper / Catch & Shoot) are computed over 2-point attempts only; ",
              "3PT rate is computed over all shot attempts (a different denominator - see pbp_engine.R header for why these ",
              "are not forced into one mutually-exclusive breakdown). REAL_HISTORICAL_FALLBACK rows had zero CURRENT_SEASON ",
              "PBP events and instead show career-to-date (ALL_SEASONS) figures."),
            fluidRow(
              column(4, checkboxInput("clutch_show_low_volume", "Show low-volume players (FGA < 20)", value = FALSE)),
              column(8, p(style = "color: #bdc3c7; font-size: 12px; margin-top: 6px;",
                          "Percentage columns are noisy on very few attempts, so low-FGA players are hidden by default rather than ",
                          "letting a 2-for-3 shooter sort to the top of a % column - fga_total is always shown so sample size stays visible."))
            ),
            DTOutput("tbl_clutch_shot_profile")
          )
        )
      )
    )
  )
)

# ------------------------------------------------------------------------------
# Server Logic
# ------------------------------------------------------------------------------
server <- function(input, output, session) {

  # ----------------------------------------------------------------------------
  # Off-season banner (renders on every tab; disk/date-only, no live API call)
  # ----------------------------------------------------------------------------
  output$season_status_banner <- renderUI({
    if (is_wnba_in_season()) {
      div(class = "wnba-season-banner", style = "background-color: #1e5631; color: #ecf0f1;",
          paste0("\u25CF WNBA SEASON ACTIVE (", format(Sys.Date(), "%Y"),
                 ") - data below reflects the current in-season pipeline run."))
    } else {
      div(class = "wnba-season-banner", style = "background-color: #7a4a00; color: #fff8e1;",
          paste0("\u26A0 WNBA SEASON INACTIVE (regular season runs ~May-October) - showing the LAST COMPLETED ",
                 "pipeline run's cached ratings/odds/props, not live data. Re-run run_full_pipeline.R once the ",
                 "season resumes before trusting these numbers as current."))
    }
  })

  # ----------------------------------------------------------------------------
  # Data Reactive Loaders
  # ----------------------------------------------------------------------------
  # T4 Handoff Notes: cache/latest_value_bets.rds, written by evaluate_betting_slate()
  # (market_odds_engine.R). SYNTHETIC_FALLBACK slate expected in this environment (no
  # ODDS_API_KEY set) - see banner note in Tab 1's UI above.
  r_value_bets <- reactive({
    path <- "cache/latest_value_bets.rds"
    if (file.exists(path)) {
      readRDS(path)
    } else {
      source("market_odds_engine.R")
      evaluate_betting_slate()
    }
  })

  # XAI/Diagnostics: Prediction Accuracy Log
  r_pred_log <- reactive({
    path <- "cache/prediction_accuracy_log.rds"
    if (file.exists(path)) {
      readRDS(path)
    } else {
      tibble()
    }
  })

  # T4 Handoff Notes: cache/risk_state.rds, written by compute_risk_state() (risk_management_engine.R)

  r_risk_data <- reactive({
    if (file.exists("cache/risk_state.rds")) {
      readRDS("cache/risk_state.rds")
    } else {
      source("risk_management_engine.R")
      compute_risk_state()
    }
  })

  # T2 Handoff Notes: cache/projected_wnba_standings.rds (NOT projected_30_team_standings.rds -
  # that NBA filename is intentionally not read here at all), written by project_all_wnba_teams()
  r_standings_data <- reactive({
    raw <- NULL
    if (file.exists("cache/projected_wnba_standings.rds")) {
      raw <- tryCatch(readRDS("cache/projected_wnba_standings.rds"), error = function(e) NULL)
    }

    if (is.null(raw) || nrow(raw) == 0) {
      # Fallback placeholder uses real current WNBA franchises (config.R's WNBA_TEAMS), not
      # NBA team names, in case this cache has never been generated yet.
      teams <- c("Minnesota Lynx", "New York Liberty", "Las Vegas Aces", "Indiana Fever",
                 "Atlanta Dream", "Seattle Storm", "Phoenix Mercury", "Golden State Valkyries",
                 "Washington Mystics", "Chicago Sky")
      raw <- tibble(
        Rank = 1:10,
        Team = teams,
        Net_Rating = c(12.14, 12.09, 8.5, 6.2, 4.8, 3.9, 2.6, 1.8, 0.5, -0.4),
        Proj_Wins = c(34.9, 34.9, 30.1, 27.4, 25.0, 23.8, 21.5, 19.9, 17.2, 16.1),
        Proj_Losses = c(9.1, 9.1, 13.9, 16.6, 19.0, 20.2, 22.5, 24.1, 26.8, 27.9),
        # FIX M-8: numeric proportion, matching the type agent_pipeline's roster_bottom_up_engine.R
        # now writes to the real cache. Formatting happens at display time only.
        Win_Pct = round(Proj_Wins / (Proj_Wins + Proj_Losses), 3),
        Top_Core_Players = "Star Core"
      )
    }

    c_names <- names(raw)
    tm_col <- c_names[tolower(c_names) %in% c("team", "team_code", "team_name")][1] %||% c_names[1]
    net_col <- c_names[tolower(c_names) %in% c("net_rating", "bottom_up_net_rating", "net_rtg")][1] %||% c_names[2]

    raw$norm_team <- as.character(raw[[tm_col]])
    raw$norm_net  <- as.numeric(raw[[net_col]])
    return(raw)
  })

  # T4 Handoff Notes: written by generate_active_props_table() (player_props_engine.R) - 720 props
  # across 15 teams, real active_rosters_cache.rds-backed rotation per T4's live run.
  #
  # FIX L-6: this used to read data/latest_player_props.rds and silently FALL BACK to
  # cache/latest_player_props.rds. Two copies with an undocumented precedence rule means a partial
  # write to one location produces a split-brain where the dashboard displays one file while
  # tools/data_health_probe.R validates (and reports green on) the other. There is now a single
  # canonical location: config.R's CACHE_PLAYER_PROPS, which is also the sole write target as of
  # agent_props' Wave 2 change to player_props_engine.R.
  r_props_data <- reactive({
    raw_props <- NULL
    if (file.exists(CACHE_PLAYER_PROPS)) {
      raw_props <- tryCatch(readRDS(CACHE_PLAYER_PROPS), error = function(e) NULL)
    }

    if (is.null(raw_props) || nrow(raw_props) == 0) {
      source("player_props_engine.R")
      raw_props <- generate_active_props_table()
    }

    cols <- tolower(names(raw_props))
    norm <- raw_props

    p_idx <- which(cols %in% c("player", "player_name", "name"))[1]
    if (!is.na(p_idx)) norm$player <- as.character(raw_props[[p_idx]])

    t_idx <- which(cols %in% c("team", "team_abbrev", "tm"))[1]
    if (!is.na(t_idx)) norm$team <- as.character(raw_props[[t_idx]])

    s_idx <- which(cols %in% c("stat", "stat_cat", "stat_type", "prop_type", "market"))[1]
    if (!is.na(s_idx)) norm$stat <- as.character(raw_props[[s_idx]])

    l_idx <- which(cols %in% c("line", "prop_line", "target"))[1]
    if (!is.na(l_idx)) norm$line <- as.numeric(raw_props[[l_idx]])

    m_idx <- which(cols %in% c("proj_mu", "projected_mu", "mean", "pred", "projection"))[1]
    norm$proj_mu <- if (!is.na(m_idx)) as.numeric(raw_props[[m_idx]]) else norm$line * 1.05

    if (!"theta" %in% names(norm)) norm$theta <- 5.0
    if (!"zinb_p_zero" %in% names(norm)) norm$zinb_p_zero <- 0.02

    side_idx <- which(cols %in% c("recommended_side", "side", "recommendation", "pick"))[1]
    norm$recommended_side <- if (!is.na(side_idx)) as.character(raw_props[[side_idx]]) else "OVER"

    odds_idx <- which(cols %in% c("market_odds", "odds", "book_odds", "line_odds"))[1]
    norm$market_odds <- if (!is.na(odds_idx)) as.numeric(raw_props[[odds_idx]]) else -110

    ev_idx <- which(cols %in% c("ev_pct", "ev", "edge_pct", "edge"))[1]
    if (!is.na(ev_idx)) {
      raw_ev <- as.numeric(raw_props[[ev_idx]])
      norm$ev_pct <- if (max(raw_ev, na.rm = TRUE) <= 1.0) round(raw_ev * 100, 2) else round(raw_ev, 2)
    } else {
      norm$ev_pct <- 6.5
    }

    k_idx <- which(cols %in% c("quarter_kelly", "kelly", "stake", "recommended_units"))[1]
    norm$quarter_kelly <- if (!is.na(k_idx)) as.numeric(raw_props[[k_idx]]) else 0.04

    return(norm)
  })

  # Populate Matchup Dropdowns (Tab 7)
  observe({
    std <- r_standings_data()
    req(std, nrow(std) > 0)
    tms <- sort(unique(std$norm_team))

    sel_home <- if ("Minnesota Lynx" %in% tms) "Minnesota Lynx" else tms[1]
    sel_away <- if ("New York Liberty" %in% tms) "New York Liberty" else tms[min(2, length(tms))]

    updateSelectInput(session, "calc_away_team", choices = tms, selected = sel_away)
    updateSelectInput(session, "calc_home_team", choices = tms, selected = sel_home)
  })

  # ----------------------------------------------------------------------------
  # Tab 1: Dynamic Date Slicing & Value Table
  # ----------------------------------------------------------------------------
  r_normalized_value_bets <- reactive({
    df <- r_value_bets()
    req(df, nrow(df) > 0)

    c_names <- names(df)
    d_col <- c_names[tolower(c_names) %in% c("game_date", "date", "commence_time")][1]

    has_distinct_dates <- FALSE
    if (!is.na(d_col)) {
      parsed <- suppressWarnings(as.Date(df[[d_col]]))
      if (sum(!is.na(parsed)) > 0 && length(unique(parsed[!is.na(parsed)])) > 1) {
        df$norm_date <- parsed
        has_distinct_dates <- TRUE
      }
    }

    if (!has_distinct_dates) {
      # Stagger the lookahead games across the first week of the WNBA season (2026-05-08
      # kickoff, per wnba.com's key-dates release) instead of the NBA original's October dates.
      n_total <- nrow(df)
      staggered_dates <- c(
        rep("2026-05-08", min(2, n_total)),
        rep("2026-05-09", min(12, max(0, n_total - 2))),
        rep("2026-05-10", min(4,  max(0, n_total - 14))),
        rep("2026-05-11", min(10, max(0, n_total - 18))),
        rep("2026-05-12", min(7,  max(0, n_total - 28))),
        rep("2026-05-13", max(0, n_total - 35))
      )
      df$norm_date <- as.Date(staggered_dates[1:n_total])
    }
    return(df)
  })

  observe({
    df <- r_normalized_value_bets()
    req(df, nrow(df) > 0)

    unique_dates <- sort(unique(df$norm_date))
    date_labels  <- format(unique_dates, "%a, %b %d, %Y")

    if ("2026-05-08" %in% as.character(unique_dates)) {
      date_labels[as.character(unique_dates) == "2026-05-08"] <- "Fri, May 08, 2026 (Opening Night)"
    }

    choices_vec <- c("All Scheduled Dates (Full Catalog)", as.character(unique_dates))
    names(choices_vec) <- c("All Scheduled Dates (Full Catalog)", date_labels)

    curr_sel <- isolate(input$slate_date_picker)
    if (is.null(curr_sel) || !curr_sel %in% choices_vec) curr_sel <- choices_vec[1]

    updateSelectInput(session, "slate_date_picker", choices = choices_vec, selected = curr_sel)
  })

  r_filtered_value_bets <- reactive({
    df <- r_normalized_value_bets()
    req(df)

    selected_val <- input$slate_date_picker %||% "All Scheduled Dates (Full Catalog)"

    if (grepl("^\\d{4}-\\d{2}-\\d{2}$", selected_val)) {
      target_d <- as.Date(selected_val)
      df <- df %>% filter(norm_date == target_d)
    }
    return(df)
  })

  output$box_slate_count <- renderValueBox({
    df <- r_filtered_value_bets()
    count_val <- if (!is.null(df)) nrow(df) else 0
    selected_val <- input$slate_date_picker %||% ""
    sub_title <- if (selected_val == "All Scheduled Dates (Full Catalog)" || !nzchar(selected_val)) {
      "Full Lookahead Catalog"
    } else {
      "Games Scheduled on Date"
    }
    valueBox(paste(count_val, "Games"), sub_title, icon = icon("calendar-day"), color = ifelse(count_val > 0, "blue", "navy"))
  })

  output$box_top_edge <- renderValueBox({
    df <- r_filtered_value_bets()
    has_rows <- !is.null(df) && nrow(df) > 0
    top_ev <- if (has_rows) max(as.numeric(df$EV_Percent), na.rm = TRUE) else 0.0
    if (is.infinite(top_ev) || is.na(top_ev)) top_ev <- 0.0

    valueBox(sprintf("+%.1f%%", top_ev), "Top Edge on Slate",
             icon = icon("bolt"), color = ifelse(top_ev >= 5.0, "green", "navy"))
  })

  output$box_active_kelly <- renderValueBox({
    dat <- r_risk_data()
    val <- dat$active_kelly_multiplier %||% 0.25
    valueBox(sprintf("%.3f", val), paste0("Active Kelly Tier (", dat$risk_status %||% "OPTIMAL", ")"),
             icon = icon("shield-alt"), color = ifelse(val >= 0.20, "yellow", "red"))
  })

  output$tbl_daily_edges <- renderDT({
    df <- r_filtered_value_bets()
    build_tbl_daily_edges(df)
  })

  # ----------------------------------------------------------------------------
  # Tab 2: Steam Radar
  # ----------------------------------------------------------------------------
  output$tbl_steam_radar <- renderDT({
    hist_path <- "cache/odds_history.rds"
    # Guarded exactly like the pre-extraction inline tryCatch: a raw readRDS() error (e.g. a
    # concurrently-written/partial cache file) must fall through to build_tbl_steam_radar(NULL)'s
    # "MONITORING ACTIVE" placeholder, not propagate as an uncaught render error.
    hist_df <- if (file.exists(hist_path)) {
      tryCatch(readRDS(hist_path), error = function(e) NULL)
    } else {
      NULL
    }
    build_tbl_steam_radar(hist_df)
  })

  # ----------------------------------------------------------------------------
  # Tab 3: Injury Monitor
  # ----------------------------------------------------------------------------
  output$tbl_injuries <- renderDT({
    inj_path <- "cache/injury_data_cache.rds"
    inj_exists <- file.exists(inj_path)
    # Guarded like every other cache read in this app (see e.g. the standings/props/embeddings
    # reactives above) - injury_data_cache.rds is rewritten daily by the scheduled pipeline run,
    # so a read that races a concurrent write can throw a raw readRDS() error (truncated/partial
    # file). Previously unguarded here, this was the one reactive in the app that could surface a
    # raw R error condition straight to the browser (Shiny/DT renders that as "[object Object]"
    # instead of a message) rather than falling back gracefully like every other tab does.
    inj_raw <- if (inj_exists) {
      tryCatch(readRDS(inj_path), error = function(e) {
        message("[tbl_injuries] Failed to read ", inj_path, ": ", conditionMessage(e))
        NULL
      })
    } else {
      NULL
    }
    build_tbl_injuries(inj_exists, inj_raw)
  })

  # ----------------------------------------------------------------------------
  # Tab 4: Bet Tracker
  # ----------------------------------------------------------------------------
  output$kpi_rolling_7d_clv <- renderValueBox({
    dat <- r_risk_data()
    val <- dat$rolling_7d_clv_pct %||% 3.2
    valueBox(paste0(ifelse(val > 0, "+", ""), val, "%"), "Rolling 7-Day CLV",
             icon = icon("arrow-trend-up"), color = ifelse(val >= 1.5, "green", "yellow"))
  })

  output$kpi_rolling_30d_clv <- renderValueBox({
    dat <- r_risk_data()
    val <- dat$rolling_30d_clv_pct %||% 2.6
    valueBox(paste0(ifelse(val > 0, "+", ""), val, "%"), "Rolling 30-Day CLV",
             icon = icon("calendar-check"), color = ifelse(val >= 2.0, "green", "blue"))
  })

  output$kpi_beat_clv_rate <- renderValueBox({
    dat <- r_risk_data()
    val <- dat$beat_clv_rate_pct %||% 76.7
    valueBox(paste0(val, "%"), "Beat-CLV Rate",
             icon = icon("trophy"), color = ifelse(val >= 60.0, "green", "purple"))
  })

  output$kpi_current_drawdown <- renderValueBox({
    dat <- r_risk_data()
    val <- dat$current_dd_units %||% 1.18
    valueBox(paste0("-", val, " U"), paste0("Current Drawdown (", dat$risk_status %||% "OPTIMAL", ")"),
             icon = icon("shield-alt"), color = ifelse(val <= 3.0, "green", ifelse(val <= 5.0, "yellow", "red")))
  })

  output$plot_bankroll_drawdown <- renderPlot({
    dat <- r_risk_data()
    req(dat$ledger)
    build_plot_bankroll_drawdown(dat$ledger)
  })

  output$txt_risk_engine_status <- renderText({
    dat <- r_risk_data()
    paste0(
      "RISK STATE AUDIT\n",
      "====================================\n",
      "Status: ", dat$risk_status, "\n",
      "Active Kelly Tier: ", dat$active_kelly_multiplier, " Kelly\n",
      "Current Drawdown: -", dat$current_dd_units, " Units (-", dat$current_dd_pct, "%)\n",
      "Max Peak Drawdown: -", dat$max_dd_units, " Units (-", dat$max_dd_pct, "%)\n",
      "Bankroll: ", dat$current_bankroll, " Units\n",
      "Total Bets Audited: ", dat$total_bets_audited, "\n\n",
      "Directive: ", dat$status_message
    )
  })

  output$tbl_graded_ledger <- renderDT({
    dat <- r_risk_data()
    req(dat$ledger)
    build_tbl_graded_ledger(dat$ledger)
  })

  # ----------------------------------------------------------------------------
  # Tab 5: Team Embeddings (FIXED - real 16-D embeddings, not shot-quality mislabeled as such)
  # ----------------------------------------------------------------------------
  r_embeddings_raw <- reactive({
    db_path <- "logs/analytics.duckdb"
    if (!file.exists(db_path)) return(NULL)
    tryCatch({
      con <- dbConnect(duckdb(), db_path)
      res <- dbGetQuery(con, "SELECT * FROM team_embeddings")
      dbDisconnect(con, immediate = TRUE)
      res
    }, error = function(e) NULL)
  })

  r_similarity_raw <- reactive({
    db_path <- "logs/analytics.duckdb"
    if (!file.exists(db_path)) return(NULL)
    tryCatch({
      con <- dbConnect(duckdb(), db_path)
      res <- dbGetQuery(con, "SELECT * FROM team_similarity")
      dbDisconnect(con, immediate = TRUE)
      res
    }, error = function(e) NULL)
  })

  output$plot_embeddings_pca <- renderPlot({
    emb <- r_embeddings_raw()
    build_plot_embeddings_pca(emb)
  })

  output$plot_embeddings_heatmap <- renderPlot({
    sim <- r_similarity_raw()
    build_plot_embeddings_heatmap(sim)
  })

  # ----------------------------------------------------------------------------
  # Tab 6: Calibration Curve
  #
  # FIXED (P3b): real data source is cache/model_calibration_input.rds (built by
  # build_calibration_cache.R from T1's real box_scores_cache.rds — 1,902 real
  # WNBA games, 2019-2026, with a point-in-time no-look-ahead rolling-margin win
  # probability vs. the real recorded outcome; NOT WNBA_Analysis_Project.Rmd's
  # Random Forest, since no saved prediction cache from that notebook exists in
  # this repo — see build_calibration_cache.R's header for the full rationale).
  # live_calibration.R::calibration_analysis() is called on this real data to
  # produce the real reliability plot + Brier/BSS/Log-Loss numbers below.
  # ----------------------------------------------------------------------------
  r_calibration_result <- reactive({
    cal_path <- "cache/model_calibration_input.rds"
    source_label <- NULL
    preds <- NULL

    if (file.exists(cal_path)) {
      preds <- readRDS(cal_path)
      source_label <- "Real data: cache/model_calibration_input.rds (1,902 real WNBA games, 2019-2026; point-in-time rolling-margin model vs. real recorded outcomes — see tools/build_calibration_cache.R)."
    } else if (file.exists("data/box_scores_cache.rds")) {
      tryCatch({
        source("tools/build_calibration_cache.R")
        preds <- build_model_calibration_input()
        source_label <- "Real data: built on-the-fly from data/box_scores_cache.rds (cache/model_calibration_input.rds did not exist yet — see tools/build_calibration_cache.R)."
      }, error = function(e) NULL)
    }

    if (is.null(preds) || nrow(preds) == 0) {
      list(real = FALSE, source_label =
        "FALLBACK: data/box_scores_cache.rds unavailable — showing an illustrative synthetic curve, not real model calibration.",
        result = NULL)
    } else {
      if (!exists("calibration_analysis")) source("live_calibration.R")
      list(real = TRUE, source_label = source_label, result = calibration_analysis(preds))
    }
  })

  output$calibration_source_caption <- renderUI({
    cal <- r_calibration_result()
    span(style = if (cal$real) "color: #2ecc71;" else "color: #e74c3c;", cal$source_label)
  })

  output$vbox_brier <- renderValueBox({
    cal <- r_calibration_result()
    val <- if (cal$real) sprintf("%.4f", cal$result$brier) else "N/A"
    valueBox(val, "Brier Score (lower = better)", icon = icon("bullseye"), color = "purple")
  })
  output$vbox_bss <- renderValueBox({
    cal <- r_calibration_result()
    val <- if (cal$real) sprintf("%.3f", cal$result$bss) else "N/A"
    valueBox(val, "Brier Skill Score (vs. 50/50 baseline)", icon = icon("chart-bar"), color = "purple")
  })
  output$vbox_logloss <- renderValueBox({
    cal <- r_calibration_result()
    val <- if (cal$real) sprintf("%.4f", cal$result$log_loss) else "N/A"
    valueBox(val, "Log-Loss (lower = better)", icon = icon("wave-square"), color = "purple")
  })

  output$plot_calibration_curve <- renderPlot({
    cal <- r_calibration_result()
    build_plot_calibration_curve(cal)
  })

  # ----------------------------------------------------------------------------
  # Tab 7: Standings & Calculator
  # ----------------------------------------------------------------------------
  calc_matchup <- reactive({
    std <- r_standings_data()
    req(input$calc_away_team, input$calc_home_team)

    away_row <- std %>% filter(norm_team == input$calc_away_team)
    home_row <- std %>% filter(norm_team == input$calc_home_team)

    if (nrow(away_row) == 0 || nrow(home_row) == 0) {
      return(list(spread = 0.0, prob = 0.50, ml = -110))
    }

    h_net <- home_row$norm_net[1] %||% 0.0
    a_net <- away_row$norm_net[1] %||% 0.0
    # FIX C-1: fall back to config.R's WNBA_HCA constant if the numericInput is blank/NA.
    hca   <- input$calc_hca %||% WNBA_HCA

    sq_path <- "cache/team_shot_quality.rds"
    if (file.exists(sq_path)) {
      sq_db <- readRDS(sq_path)
      h_luck <- sq_db$shooting_luck_pts[sq_db$team == input$calc_home_team][1] %||% 0.0
      a_luck <- sq_db$shooting_luck_pts[sq_db$team == input$calc_away_team][1] %||% 0.0
      h_net <- h_net - (0.50 * h_luck)
      a_net <- a_net - (0.50 * a_luck)
    }

    fair_margin <- (h_net - a_net) + hca
    fair_spread <- -fair_margin
    # WNBA_MARGIN_SIGMA (14.0, T2's real empirical derivation) replaces the NBA original's
    # hardcoded 11.2 - see the source("config.R") block near the top of this file.
    p_home <- pnorm(fair_margin / WNBA_MARGIN_SIGMA)
    p_home <- min(max(p_home, 0.01), 0.99)

    fair_ml <- ifelse(p_home >= 0.5,
                      round(-100 * p_home / (1 - p_home)),
                      round(100 * (1 - p_home) / p_home))

    list(spread = fair_spread, prob = p_home, ml = fair_ml)
  })

  output$box_calc_spread <- renderValueBox({
    m <- calc_matchup()
    valueBox(sprintf("%+.1f", m$spread), paste(input$calc_home_team, "Fair Spread"),
             icon = icon("arrows-alt-h"), color = "blue")
  })

  output$box_calc_win_prob <- renderValueBox({
    m <- calc_matchup()
    valueBox(sprintf("%.1f%%", m$prob * 100), paste(input$calc_home_team, "Win Probability"),
             icon = icon("percent"), color = "green")
  })

  output$box_calc_fair_ml <- renderValueBox({
    m <- calc_matchup()
    valueBox(sprintf("%+d", m$ml), paste(input$calc_home_team, "Fair Moneyline"),
             icon = icon("dollar-sign"), color = "purple")
  })

  output$tbl_bottom_up_standings <- renderDT({
    std <- r_standings_data()
    build_tbl_bottom_up_standings(std)
  })

  # ----------------------------------------------------------------------------
  # Tab 8: Model Diagnostics Logic
  # ----------------------------------------------------------------------------
  # FIX C-3: identify synthetic/diagnostic fixture rows in the prediction log.
  # The contracted provenance flag (docs/task_assignments_phase4.md, "Interface contracts") is the
  # logical column `is_synthetic`, written by agent_props via tools/generate_diagnostic_data.R and
  # log_todays_predictions(). We build against that exact name/type. Because this dashboard must
  # never hard-crash on an older on-disk schema (repo fail-safe convention), a log written before
  # that migration is classified by the two provenance markers the DIAG_ fixtures actually carry -
  # a "DIAG_" game_id prefix and injury_data_source == "DIAGNOSTIC" - rather than by trusting an
  # absent column and silently treating fixtures as real measurements.
  .flag_synthetic <- function(log) {
    if (is.null(log) || nrow(log) == 0) return(logical(0))
    if ("is_synthetic" %in% names(log)) {
      return(dplyr::coalesce(as.logical(log$is_synthetic), FALSE))
    }
    gid  <- if ("game_id" %in% names(log)) as.character(log$game_id) else rep(NA_character_, nrow(log))
    isrc <- if ("injury_data_source" %in% names(log)) as.character(log$injury_data_source) else rep(NA_character_, nrow(log))
    dplyr::coalesce(startsWith(gid, "DIAG_"), FALSE) |
      dplyr::coalesce(toupper(isrc) == "DIAGNOSTIC", FALSE)
  }

  # FIX C-3: counts backing the visible provenance label, so an empty REAL sample renders as an
  # honest zero instead of being silently backfilled with diagnostic fixtures.
  r_diag_provenance <- reactive({
    log <- r_pred_log()
    if (is.null(log) || nrow(log) == 0) {
      return(list(total = 0L, resolved = 0L, real_resolved = 0L, synth_resolved = 0L,
                  has_flag = FALSE, box_ok = file.exists(CACHE_TEAM_BOX), chartable = 0L))
    }
    syn <- .flag_synthetic(log)
    is_res <- dplyr::coalesce(log$status == "RESOLVED", FALSE)
    # 2026-09-18 finding: reconcile_predictions() never backfills predicted_margin (it's only
    # ever set once, at PENDING-insertion time, from that day's latest_value_bets.rds slate) -
    # a handful of already-logged real resolved rows have NA predicted_margin from whatever
    # slate produced them, and residual = actual_margin - predicted_margin is NA for those rows.
    # ggplot silently drops NA-aesthetic rows, so the charts below rendered blank while the
    # value boxes correctly showed an em dash. Surface the chartable count so the gap is visible.
    n_chartable <- {
      df <- tryCatch(r_diagnostics_df(), error = function(e) NULL)
      if (is.null(df)) 0L else sum(!is.na(df$predicted_margin))
    }
    list(
      total          = nrow(log),
      resolved       = sum(is_res),
      real_resolved  = sum(is_res & !syn),
      synth_resolved = sum(is_res & syn),
      has_flag       = "is_synthetic" %in% names(log),
      box_ok         = file.exists(CACHE_TEAM_BOX),
      chartable      = n_chartable
    )
  })

  r_diagnostics_df <- reactive({
    log <- r_pred_log()
    if (is.null(log) || nrow(log) == 0) return(NULL)

    # FIX C-3: RESOLVED *and* non-synthetic. Previously this filtered on status alone, so the 100
    # DIAG_* fixture rows (zero game_id overlap with the real box cache, 68 of them dated outside
    # the May-Oct WNBA season) were the ONLY thing the accuracy scoreboard could ever display -
    # a fabricated "83% accuracy / 0.131 Brier" presented as measured performance.
    resolved <- log |> filter(dplyr::coalesce(status == "RESOLVED", FALSE) & !.flag_synthetic(log))
    if (nrow(resolved) == 0) return(NULL)

    # FIX H-3: was the bare literal "cache/box_scores_cache.rds" - a path that has not existed
    # since the 2026-09-12 tidy-up moved the artifact to data/. file.exists() was FALSE on every
    # render, so this reactive returned NULL every time and the value boxes below fell through to
    # their old `else 0.0` default, displaying a confident "0 pts MAE" produced by a missing file.
    # CACHE_TEAM_BOX is config.R's single source of truth for this path.
    if (!file.exists(CACHE_TEAM_BOX)) return(NULL)
    box_scores <- readRDS(CACHE_TEAM_BOX)

    # Normalize home_team to short nickname for join (stringr::word - see the req_pkgs note above).
    resolved <- resolved |>
      mutate(.home_short = stringr::word(unname(WNBA_TEAMS[home_team]), -1))

    # FIX H-3: real column names are team_score / opponent_team_score. The previous
    # select(home_score = score, away_score = opponent_score) referenced columns that do not exist
    # in this cache and would have errored the moment the path above was corrected.
    game_outcomes <- box_scores |>
      filter(team_home_away == "home") |>
      mutate(game_date = as.Date(game_date)) |>
      select(game_date, home_team_short = team_short_display_name,
             home_score = team_score, away_score = opponent_team_score) |>
      distinct()

    analysis_df <- resolved |>
      inner_join(game_outcomes, by = c("game_date" = "game_date", ".home_short" = "home_team_short")) |>
      mutate(
        actual_margin = home_score - away_score,
        residual = actual_margin - predicted_margin
      )

    if (nrow(analysis_df) == 0) return(NULL)
    analysis_df
  })

  # FIX C-3: visible provenance banner. The point of the scoreboard is that its denominator is
  # legible: if there are zero real resolved predictions, the tab says so in words rather than
  # rendering fixture-derived numbers that look like measured model performance.
  output$diag_provenance <- renderUI({
    p <- r_diag_provenance()
    n <- p$real_resolved
    headline <- sprintf("%d real resolved prediction%s", n, if (n == 1) "" else "s")
    detail <- sprintf(
      "%d row%s in cache/prediction_accuracy_log.rds | %d RESOLVED | %d excluded as synthetic/diagnostic fixtures%s",
      p$total, if (p$total == 1) "" else "s", p$resolved, p$synth_resolved,
      if (p$has_flag) "" else " (no is_synthetic column on this log yet - classified by DIAG_ game_id / DIAGNOSTIC injury source)"
    )
    warn <- if (!p$box_ok) {
      sprintf("DIAGNOSTICS UNAVAILABLE - box score cache not found at %s. Metrics below show an em dash, not zero.", CACHE_TEAM_BOX)
    } else if (n == 0) {
      "DIAGNOSTICS UNAVAILABLE - no real (non-synthetic) resolved predictions to score yet. Metrics below show an em dash, not zero."
    } else if (p$chartable == 0) {
      sprintf("CHARTS UNAVAILABLE - all %d real resolved prediction%s logged with a missing predicted_margin (older log rows from before that field was reliably captured); metrics/charts below show an em dash / placeholder, not zero.",
              n, if (n == 1) "" else "s")
    } else if (p$chartable < n) {
      sprintf("%d of %d real resolved predictions are missing predicted_margin and are excluded from the charts below.",
              n - p$chartable, n)
    } else NULL

    div(
      style = "padding:10px 14px;margin-bottom:10px;border-radius:4px;background:#1a222d;border-left:5px solid #af7ac5;color:#ecf0f1;",
      tags$strong(style = "font-size:16px;", headline),
      tags$span(style = "opacity:0.75;margin-left:10px;", detail),
      if (!is.null(warn)) tags$div(style = "margin-top:6px;color:#e74c3c;font-weight:bold;", warn)
    )
  })

  # FIX H-3: render an em dash, never 0.0, when the diagnostics frame is NULL. A missing data
  # source must never be visually indistinguishable from a perfect-model reading.
  .diag_metric <- function(df, f) {
    if (is.null(df) || nrow(df) == 0) return("—")
    v <- suppressWarnings(f(df))
    if (!is.finite(v)) return("—")
    paste0(round(v, 2), " pts")
  }

  output$vbox_mae <- renderValueBox({
    val <- .diag_metric(r_diagnostics_df(), function(d) mean(abs(d$residual), na.rm = TRUE))
    valueBox(val, "Mean Absolute Error (MAE)", icon = icon("bullseye"), color = "purple")
  })

  output$vbox_rmse <- renderValueBox({
    val <- .diag_metric(r_diagnostics_df(), function(d) sqrt(mean(d$residual^2, na.rm = TRUE)))
    valueBox(val, "Root Mean Square Error (RMSE)", icon = icon("chart-line"), color = "purple")
  })

  output$vbox_bias <- renderValueBox({
    # FIX H-3: em dash, not 0.0, on missing data (a 0.0 here reads as "perfectly unbiased").
    val <- .diag_metric(r_diagnostics_df(), function(d) mean(d$residual, na.rm = TRUE))
    valueBox(val, "Mean Bias (Home Bias)", icon = icon("balance-scale"), color = "purple")
  })

  # 2026-09-18 finding: rows with NA predicted_margin have an NA residual, and ggplot silently
  # drops NA-aesthetic rows - so a df that passes req(df) (non-NULL, nrow > 0) could still render
  # a blank chart with zero visible data points. Filter to chartable rows here so the "not enough
  # data" case is an honest annotated message instead of an empty plot.
  .diag_chartable <- function(df) if (is.null(df)) NULL else df[!is.na(df$residual), , drop = FALSE]

  # NOTE: `.diag_empty_plot()` (the shared "no chartable predictions yet" plotly builder used by
  # the three outputs below) now lives in dashboard_render_helpers.R, sourced near the top of
  # this file - it contained no input$/session reference, so it moved along with the three
  # build_plot_* functions that call it.

  output$plot_residual_scatter <- renderPlotly({
    df <- .diag_chartable(r_diagnostics_df())
    req(!is.null(df))
    build_plot_residual_scatter(df)
  })

  output$plot_residual_dist <- renderPlotly({
    df <- .diag_chartable(r_diagnostics_df())
    req(!is.null(df))
    build_plot_residual_dist(df)
  })

  output$plot_team_bias <- renderPlotly({
    df <- .diag_chartable(r_diagnostics_df())
    req(!is.null(df))
    build_plot_team_bias(df)
  })

  # ----------------------------------------------------------------------------
  # Tab 9: Props Terminal
  # ----------------------------------------------------------------------------
  filtered_props <- reactive({

    df <- r_props_data()
    req(df, nrow(df) > 0)

    if (input$props_stat_filter != "All Categories") {
      df <- df %>% filter(toupper(stat) == toupper(input$props_stat_filter))
    }
    if (input$props_side_filter != "ALL") {
      df <- df %>% filter(toupper(recommended_side) == toupper(input$props_side_filter))
    }
    # FIX M-3: this was grepl(input$props_search_player, player, ignore.case = TRUE), which treats
    # raw keystrokes as a REGEX. Shiny's textInput fires on every character, so a user mid-typing a
    # name hits a partial pattern like "(" or "[" and grepl() hard-errors ("invalid regular
    # expression"), throwing this reactive and putting all three dependent outputs into Shiny's
    # opaque error state. Not a ReDoS (measured: TRE is non-backtracking here) - a plain crash.
    # NOTE: the obvious fix, grepl(..., fixed = TRUE), is WRONG - R silently discards ignore.case
    # under fixed = TRUE. Re-verified on this machine 2026-09-16 against a 3-name fixture:
    #   grepl("wilson", fixed = TRUE, ignore.case = TRUE) -> 1 match  [+ "ignore.case will be ignored" warning]
    #   grepl("wilson", ignore.case = TRUE)               -> 2 matches
    #   str_detect(fixed("wilson", ignore_case = TRUE))   -> 2 matches  <- correct, and no error on "("
    # stringr::fixed(..., ignore_case = TRUE) is the only form that keeps literal matching AND
    # case-insensitivity. stringr is already a dependency (tidyverse; word() is used above).
    if (nzchar(input$props_search_player)) {
      df <- df %>% filter(stringr::str_detect(
        player, stringr::fixed(input$props_search_player, ignore_case = TRUE)
      ))
    }
    df %>% filter(ev_pct >= input$props_ev_slider)
  })

  output$tbl_props_terminal <- renderDT({
    df <- filtered_props()
    build_tbl_props_terminal(df)
  })

  output$plot_prop_zinb_curve <- renderPlot({
    df <- filtered_props()

    # Row-selection logic depends on input$tbl_props_terminal_rows_selected, so it stays here
    # rather than inside the helper; only the resolved `sel` (single-row data frame, 0 rows if
    # df itself is empty - matching the original's nrow(df) == 0 early-return path) is handed to
    # build_plot_prop_zinb_curve().
    s_idx <- input$tbl_props_terminal_rows_selected
    sel <- if (nrow(df) == 0) {
      df
    } else if (!is.null(s_idx) && length(s_idx) > 0 && s_idx <= nrow(df)) {
      df[s_idx, ]
    } else {
      df[1, ]
    }

    build_plot_prop_zinb_curve(df, sel)
  })

  # ----------------------------------------------------------------------------
  # Tab 10: Clutch & Shot Profile (pbp_engine.R output, config.R's CACHE_PLAYER_PBP_FEATURES)
  # ----------------------------------------------------------------------------
  # Fail-safe per repo convention: never crash the app if the pipeline stage hasn't run yet.
  # Guarded read (mirrors the injury-tab pattern above) rather than a bare readRDS(), since this
  # cache is also rewritten by a scheduled pipeline run and a read could race a partial write.
  r_pbp_features <- reactive({
    if (!file.exists(CACHE_PLAYER_PBP_FEATURES)) return(NULL)
    tryCatch(readRDS(CACHE_PLAYER_PBP_FEATURES), error = function(e) {
      message("[tbl_clutch_shot_profile] Failed to read ", CACHE_PLAYER_PBP_FEATURES, ": ", conditionMessage(e))
      NULL
    })
  })

  output$tbl_clutch_shot_profile <- renderDT({
    df <- r_pbp_features()
    build_tbl_clutch_shot_profile(df, input$clutch_show_low_volume)
  })
}

shinyApp(ui, server)
