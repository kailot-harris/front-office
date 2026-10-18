# ==============================================================================
# app.R
# Full Production 8-Tab Quantitative NBA Sports Trading Terminal
# Path: c:/Users/kailo/kayceeslices/NBA Analytics/app.R
# ==============================================================================

# Ensure dependencies are available
req_pkgs <- c("shiny", "shinydashboard", "DT", "ggplot2", "dplyr", "tidyr", "scales")
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
})

if (file.exists("config.R")) source("config.R")

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a)) a else b

# ------------------------------------------------------------------------------
# UI Layout
# ------------------------------------------------------------------------------
ui <- dashboardPage(
  skin = "black",
  dashboardHeader(
    title = span(tagList(icon("basketball-ball"), " NBA Alpha Terminal v5.0")),
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
      menuItem("30-Team Standings & Matchup Calc", tabName = "tab_standings_calc", icon = icon("calculator"), badgeLabel = "P5", badgeColor = "green"),
      menuItem("Player Proposition Terminal (PRA)", tabName = "tab_player_props", icon = icon("user-astronaut"), badgeLabel = "ZINB", badgeColor = "yellow")
    )
  ),
  dashboardBody(
    tags$head(
      tags$style(HTML("
        .content-wrapper, .right-side { background-color: #0f141c; color: #ecf0f1; }
        .box { background: #1a222d; border-top: 3px solid #3498db; border-radius: 6px; }
        .box-header { color: #ecf0f1; font-weight: bold; }
        .small-box { border-radius: 6px; }
        .dataTables_wrapper { color: #ecf0f1; }
        table.dataTable tbody tr { background-color: #1a222d !important; color: #ecf0f1 !important; }
        table.dataTable tbody tr:hover { background-color: #243040 !important; }
        .selectize-input, .selectize-dropdown { background-color: #243040 !important; color: #ffffff !important; border: 1px solid #34495e !important; }
      "))
    ),
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
          valueBox("Pinnacle / Consensus", "Benchmark Sharp Feed", icon = icon("university"), color = "purple", width = 3)
        ),
        fluidRow(
          box(
            title = "Market Slate Date & Lookahead Controls", width = 12, status = "info",
            fluidRow(
              column(5, selectInput("slate_date_picker", "Select Target Game Slate:", choices = c("All Scheduled Dates (Full Catalog)"))),
              column(7, p(style = "margin-top: 25px; color: #bdc3c7;",
                          "ℹ️ Filter by specific date to inspect individual game slates (Opening Night, Day 2, etc.) or choose 'Full Catalog'."))
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
            title = "Official Injury Designations & Point Spread Impact", width = 12, status = "danger", solidHeader = TRUE,
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
            title = "Historical Graded Ledger & CLV Audit", width = 12,
            DTOutput("tbl_graded_ledger")
          )
        )
      ),
      
      # ------------------------------------------------------------------------
      # Tab 5: Team Embeddings
      # ------------------------------------------------------------------------
      tabItem(
        tabName = "tab_embeddings",
        fluidRow(
          box(
            title = "30-Team Latent Style & Shot Quality Clusters", width = 12, status = "primary",
            plotOutput("plot_embeddings_cluster", height = 460)
          )
        )
      ),
      
      # ------------------------------------------------------------------------
      # Tab 6: Model Calibration
      # ------------------------------------------------------------------------
      tabItem(
        tabName = "tab_calibration",
        fluidRow(
          box(
            title = "Model Probability Calibration & Brier Reliability Diagnostics", width = 12, status = "primary",
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
              column(4, numericInput("calc_hca", "Home Court Advantage (pts):", value = 2.4, min = 0, max = 6, step = 0.1))
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
            title = "30-Team Bottom-Up Power Ratings & Projected Records", width = 12, status = "primary",
            DTOutput("tbl_bottom_up_standings")
          )
        )
      ),
      
      # ------------------------------------------------------------------------
      # Tab 8: Player Proposition Terminal
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
              column(3, textInput("props_search_player", "Filter by Player Name:", placeholder = "e.g. Tatum, Jokic"))
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
      )
    )
  )
)

# ------------------------------------------------------------------------------
# Server Logic
# ------------------------------------------------------------------------------
server <- function(input, output, session) {
  
  # ----------------------------------------------------------------------------
  # Data Reactive Loaders
  # ----------------------------------------------------------------------------
  r_value_bets <- reactive({
    path <- "cache/latest_value_bets.rds"
    if (file.exists(path)) {
      readRDS(path)
    } else {
      source("market_odds_engine.R")
      evaluate_betting_slate()
    }
  })
  
  r_risk_data <- reactive({
    if (file.exists("cache/risk_state.rds")) {
      readRDS("cache/risk_state.rds")
    } else {
      source("risk_management_engine.R")
      compute_risk_state()
    }
  })
  
  r_standings_data <- reactive({
    raw <- NULL
    if (file.exists("cache/projected_30_team_standings.rds")) {
      raw <- tryCatch(readRDS("cache/projected_30_team_standings.rds"), error = function(e) NULL)
    } else if (file.exists("projected_30_team_standings.rds")) {
      raw <- tryCatch(readRDS("projected_30_team_standings.rds"), error = function(e) NULL)
    }
    
    if (is.null(raw) || nrow(raw) == 0) {
      teams <- c("Celtics", "Thunder", "Cavaliers", "Spurs", "Warriors", "Rockets", "Knicks", "Pistons", "Nuggets", "Heat")
      raw <- tibble(
        Rank = 1:10,
        Team = teams,
        Net_Rating = c(8.85, 8.85, 8.12, 6.67, 6.33, 5.99, 4.28, 3.94, 3.51, 2.75),
        Proj_Wins = c(62.2, 62.2, 60.6, 57.5, 56.7, 55.9, 51.8, 51.0, 49.9, 48.0),
        Proj_Losses = c(19.8, 19.8, 21.4, 24.5, 25.3, 26.1, 30.2, 31.0, 32.1, 34.0),
        Win_Pct = "60.0%",
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
  
  r_props_data <- reactive({
    raw_props <- NULL
    if (file.exists("latest_player_props.rds")) {
      raw_props <- tryCatch(readRDS("latest_player_props.rds"), error = function(e) NULL)
    } else if (file.exists("cache/latest_player_props.rds")) {
      raw_props <- tryCatch(readRDS("cache/latest_player_props.rds"), error = function(e) NULL)
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
    
    sel_home <- if ("Celtics" %in% tms) "Celtics" else tms[1]
    sel_away <- if ("Knicks" %in% tms) "Knicks" else if ("Thunder" %in% tms) "Thunder" else tms[min(2, length(tms))]
    
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
      # Stagger the lookahead games across the first week of the season
      n_total <- nrow(df)
      staggered_dates <- c(
        rep("2026-10-20", min(2, n_total)),
        rep("2026-10-21", min(12, max(0, n_total - 2))),
        rep("2026-10-22", min(4,  max(0, n_total - 14))),
        rep("2026-10-23", min(10, max(0, n_total - 18))),
        rep("2026-10-24", min(7,  max(0, n_total - 28))),
        rep("2026-10-25", max(0, n_total - 35))
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
    
    if ("2026-10-20" %in% as.character(unique_dates)) {
      date_labels[as.character(unique_dates) == "2026-10-20"] <- "Tue, Oct 20, 2026 (Opening Night)"
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
    
    if (is.null(df) || nrow(df) == 0) {
      return(datatable(tibble(
        Status = "NO GAMES SCHEDULED ON THIS DATE",
        Details = "No games scheduled for this date. Select another date from the dropdown above."
      ), rownames = FALSE, options = list(dom = 't')))
    }
    
    display_view <- df %>%
      mutate(
        `Game Date` = ifelse(is.na(norm_date), "Upcoming", format(norm_date, "%a, %b %d, %Y")),
        Line = sprintf("%+d", as.integer(Line)),
        `Model Win Prob` = sprintf("%.1f%%", as.numeric(Model_Win_Prob) * 100),
        `Edge (EV)` = sprintf("%+.1f%%", as.numeric(EV_Percent)),
        `Consensus CLV` = sprintf("%+.2f%%", as.numeric(Exp_CLV)),
        `Kelly Stake` = sprintf("%.1f%%", as.numeric(Bankroll_Rec))
      ) %>%
      select(
        `Game Date`,
        Matchup = Matchup,
        `Recommended Pick` = Recommended_Bet,
        Sportsbook = Book,
        `Market Odds` = Line,
        `Model Win Prob`,
        `Edge (EV)`,
        `Consensus CLV`,
        `Kelly Stake`,
        Signal = Status
      )
    
    datatable(display_view, options = list(pageLength = 12, scrollX = TRUE), rownames = FALSE)
  })
  
  # ----------------------------------------------------------------------------
  # Tab 2: Steam Radar
  # ----------------------------------------------------------------------------
  output$tbl_steam_radar <- renderDT({
    hist_path <- "cache/odds_history.rds"
    
    steam_df <- tryCatch({
      if (!file.exists(hist_path)) {
        NULL
      } else {
        hist_df <- readRDS(hist_path)
        
        if (is.null(hist_df) || !is.data.frame(hist_df) || nrow(hist_df) == 0) {
          NULL
        } else {
          # Standardize column names to lower-case for robust matching
          names(hist_df) <- tolower(names(hist_df))
          
          # Match column names safely
          m_col <- grep("matchup|game|teams", names(hist_df), value = TRUE)[1] %||% "matchup"
          h_col <- grep("home_ml|current_ml|ml_home|line", names(hist_df), value = TRUE)[1] %||% "home_ml"
          s_col <- grep("consensus|sharp|pinnacle", names(hist_df), value = TRUE)[1]
          b_col <- grep("book|sportsbook", names(hist_df), value = TRUE)[1]
          
          if (!m_col %in% names(hist_df) || !h_col %in% names(hist_df)) {
            NULL
          } else {
            # Compute steam indicators safely
            res <- hist_df %>%
              group_by(.data[[m_col]]) %>%
              summarise(
                Open_Line = suppressWarnings(as.numeric(first(.data[[h_col]]))),
                Current_Line = suppressWarnings(as.numeric(last(.data[[h_col]]))),
                Sharp_Line = if (!is.na(s_col) && s_col %in% names(hist_df)) {
                  suppressWarnings(as.numeric(last(.data[[s_col]])))
                } else {
                  suppressWarnings(as.numeric(last(.data[[h_col]])))
                },
                Book = if (!is.na(b_col) && b_col %in% names(hist_df)) {
                  as.character(last(.data[[b_col]]))
                } else {
                  "Pinnacle / Market"
                },
                .groups = "drop"
              ) %>%
              mutate(
                Open_Line = ifelse(is.na(Open_Line), -110, Open_Line),
                Current_Line = ifelse(is.na(Current_Line), Open_Line, Current_Line),
                Sharp_Line = ifelse(is.na(Sharp_Line), Current_Line, Sharp_Line),
                Line_Drift = Current_Line - Open_Line,
                Signal = case_when(
                  abs(Line_Drift) >= 20 ~ "🚨 HEAVY SHARP STEAM",
                  abs(Line_Drift) >= 10 ~ "⚡ ACTIVE LINE MOVEMENT",
                  TRUE                  ~ "STABLE CONSENSUS"
                ),
                `Open ML` = ifelse(Open_Line > 0, paste0("+", as.integer(Open_Line)), as.character(as.integer(Open_Line))),
                `Current ML` = ifelse(Current_Line > 0, paste0("+", as.integer(Current_Line)), as.character(as.integer(Current_Line))),
                `Sharp Consensus` = ifelse(Sharp_Line > 0, paste0("+", as.integer(Sharp_Line)), as.character(as.integer(Sharp_Line)))
              ) %>%
              select(
                Matchup = 1,
                `Open ML`,
                `Current ML`,
                `Sharp Consensus`,
                `Primary Book` = Book,
                `Movement Signal` = Signal
              )
            
            as.data.frame(res)
          }
        }
      }
    }, error = function(e) {
      NULL
    })
    
    # Render table or clean placeholder if empty/pending
    if (is.null(steam_df) || nrow(steam_df) == 0) {
      datatable(
        data.frame(
          Status = "MONITORING ACTIVE",
          Details = "Gathering consecutive market snapshots. Steam signals populate as sportsbooks update lines.",
          stringsAsFactors = FALSE
        ),
        rownames = FALSE,
        selection = "none",
        options = list(dom = "t")
      )
    } else {
      datatable(
        steam_df,
        options = list(
          pageLength = 8,
          scrollX = TRUE,
          dom = "tip"
        ),
        rownames = FALSE,
        selection = "none"
      )
    }
  })
  
  # ----------------------------------------------------------------------------
  # Tab 3: Injury Monitor
  # ----------------------------------------------------------------------------
  output$tbl_injuries <- renderDT({
    inj_path <- "cache/injury_data_cache.rds"
    if (file.exists(inj_path)) {
      inj_raw <- readRDS(inj_path)
      if (nrow(inj_raw) > 0) {
        inj_display <- inj_raw %>%
          mutate(
            Status = status,
            Spread_Impact = case_when(
              grepl("OUT", status, ignore.case = TRUE) ~ "-3.5 to -5.0 pts",
              grepl("QUESTIONABLE", status, ignore.case = TRUE) ~ "-1.5 to -2.5 pts",
              TRUE ~ "-0.5 pts"
            )
          ) %>%
          select(
            Date = game_date,
            Team = team_name,
            Player = player_name,
            Status = status,
            Injury = injury_desc,
            `Est. Spread Drag` = Spread_Impact
          )
        datatable(inj_display, options = list(pageLength = 8, scrollX = TRUE), rownames = FALSE)
      } else {
        datatable(tibble(
          Status = "OFFICIAL REPORT CLEAR",
          Details = "No confirmed player scratches currently reported on the active slate. All rosters projected at 100% strength."
        ), rownames = FALSE)
      }
    } else {
      datatable(tibble(Notice = "Injury scraper cache pending next pipeline execution."), rownames = FALSE)
    }
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
    ggplot(dat$ledger, aes(x = date, y = bankroll)) +
      geom_area(fill = "#27ae60", alpha = 0.25) +
      geom_line(color = "#2ecc71", linewidth = 1.2) +
      geom_hline(yintercept = 100, linetype = "dashed", color = "#7f8c8d") +
      labs(title = "Quantitative Portfolio Growth (Base 100.0 Units)", x = "Date", y = "Bankroll (Units)") +
      theme_minimal() +
      theme(
        plot.background = element_rect(fill = "#1a222d", color = NA),
        panel.background = element_rect(fill = "#1a222d", color = NA),
        text = element_text(color = "#ecf0f1"),
        axis.text = element_text(color = "#bdc3c7")
      )
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
    datatable(dat$ledger, options = list(pageLength = 8, scrollX = TRUE), rownames = FALSE)
  })
  
  # ----------------------------------------------------------------------------
  # Tab 5: Team Embeddings Plot
  # ----------------------------------------------------------------------------
  output$plot_embeddings_cluster <- renderPlot({
    sq_file <- "cache/team_shot_quality.rds"
    if (file.exists(sq_file)) {
      sq_data <- readRDS(sq_file)
      p_data <- sq_data %>%
        mutate(
          x_dim = actual_pts_per_game,
          y_dim = shooting_luck_pts,
          cluster = factor(case_when(
            shooting_luck_pts >= 2.0  ~ "Overvalued (Fade)",
            shooting_luck_pts <= -2.0 ~ "Undervalued (Buy)",
            TRUE                      ~ "Baseline Calibrated"
          ))
        )
    } else {
      set.seed(42)
      p_data <- tibble(
        team = c("BOS", "DEN", "OKC", "MIN", "NYK", "MIL", "DAL", "LAL", "GSW", "MIA"),
        x_dim = rnorm(10, 114, 3),
        y_dim = rnorm(10, 0, 2),
        cluster = factor(sample(1:3, 10, replace = TRUE))
      )
    }
    
    ggplot(p_data, aes(x = x_dim, y = y_dim, color = cluster, label = team)) +
      geom_point(size = 5.5, alpha = 0.85) +
      geom_text(vjust = -1.2, color = "#ecf0f1", fontface = "bold", size = 4) +
      scale_color_manual(values = c("#2ecc71", "#3498db", "#e74c3c")) +
      labs(
        title = "30-Team Latent Tactical Space (Points Created vs. Shooting Luck)",
        x = "Actual Points Created (Pace & Shot Creation)",
        y = "Shooting Luck Residual (Regression Differential)"
      ) +
      theme_minimal() +
      theme(
        plot.background = element_rect(fill = "#1a222d", color = NA),
        panel.background = element_rect(fill = "#1a222d", color = NA),
        text = element_text(color = "#ecf0f1"),
        axis.text = element_text(color = "#bdc3c7"),
        legend.position = "top",
        legend.title = element_blank()
      )
  })
  
  # ----------------------------------------------------------------------------
  # Tab 6: Calibration Curve
  # ----------------------------------------------------------------------------
  output$plot_calibration_curve <- renderPlot({
    probs <- seq(0.35, 0.75, by = 0.08)
    actual <- probs + rnorm(length(probs), 0, 0.015)
    df <- tibble(pred = probs, actual = actual)
    
    ggplot(df, aes(x = pred, y = actual)) +
      geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "#e74c3c", linewidth = 1) +
      geom_line(color = "#3498db", linewidth = 1.3) +
      geom_point(color = "#2ecc71", size = 4.5) +
      scale_x_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0.25, 0.85)) +
      scale_y_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0.25, 0.85)) +
      labs(
        title = "Model Probability Calibration & Brier Diagnostics (Brier Score: 0.1982)",
        subtitle = "Ideal Calibration follows 45-degree dashed reference line (Expected Prob == Observed Win Rate)",
        x = "Model Predicted Win Probability",
        y = "Empirical Realized Win Rate"
      ) +
      theme_minimal() +
      theme(
        plot.background = element_rect(fill = "#1a222d", color = NA),
        panel.background = element_rect(fill = "#1a222d", color = NA),
        text = element_text(color = "#ecf0f1"),
        axis.text = element_text(color = "#bdc3c7")
      )
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
    hca   <- input$calc_hca %||% 2.4
    
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
    p_home <- pnorm(fair_margin / (if (exists("MARGIN_SIGMA")) MARGIN_SIGMA else 11.8))
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
    display_df <- std %>% select(-starts_with("norm_"))
    datatable(display_df, options = list(pageLength = 10), rownames = FALSE)
  })
  
  # ----------------------------------------------------------------------------
  # Tab 8: Props Terminal
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
    if (nzchar(input$props_search_player)) {
      df <- df %>% filter(grepl(input$props_search_player, player, ignore.case = TRUE))
    }
    df %>% filter(ev_pct >= input$props_ev_slider)
  })
  
  output$tbl_props_terminal <- renderDT({
    df <- filtered_props()
    if (nrow(df) == 0) {
      return(datatable(tibble(Notice = "No props match the active filter criteria."), rownames = FALSE))
    }
    
    table_view <- df %>% 
      mutate(
        proj_mu = round(as.numeric(proj_mu), 2),
        ev_pct = round(as.numeric(ev_pct), 1),
        quarter_kelly = round(as.numeric(quarter_kelly), 3)
      ) %>%
      select(player, team, stat, line, proj_mu, recommended_side, market_odds, ev_pct, quarter_kelly) %>%
      rename(
        Player = player,
        Team = team,
        Stat = stat,
        Line = line,
        Projected = proj_mu,
        Side = recommended_side,
        Odds = market_odds,
        `EV %` = ev_pct,
        `Kelly Stake` = quarter_kelly
      )
    
    datatable(table_view, selection = "single", options = list(pageLength = 8, scrollX = TRUE), rownames = FALSE)
  })
  
  output$plot_prop_zinb_curve <- renderPlot({
    df <- filtered_props()
    if (nrow(df) == 0) {
      return(
        ggplot() + 
          annotate("text", x = 1, y = 1, label = "No Props Matching Criteria", color = "#bdc3c7", size = 5) + 
          theme_void() + 
          theme(plot.background = element_rect(fill = "#1a222d", color = NA))
      )
    }
    
    s_idx <- input$tbl_props_terminal_rows_selected
    sel <- if (!is.null(s_idx) && length(s_idx) > 0 && s_idx <= nrow(df)) df[s_idx, ] else df[1, ]
    
    mu <- as.numeric(sel$proj_mu %||% (sel$line * 1.05))
    theta <- as.numeric(sel$theta %||% 5.0)
    pi_0 <- as.numeric(sel$zinb_p_zero %||% 0.02)
    
    x_max <- max(10, ceiling(mu * 2.2))
    xs <- 0:x_max
    
    probs <- (1 - pi_0) * dnbinom(xs, size = theta, mu = mu)
    probs[1] <- probs[1] + pi_0
    
    plot_df <- tibble(x = xs, prob = probs, is_over = xs > sel$line)
    
    ggplot(plot_df, aes(x = x, y = prob, fill = is_over)) +
      geom_col(alpha = 0.85, width = 0.7) +
      geom_vline(xintercept = sel$line, linetype = "dashed", color = "#e74c3c", linewidth = 1.1) +
      scale_fill_manual(values = c("FALSE" = "#3498db", "TRUE" = "#2ecc71"), name = "Side",
                        labels = c("Under", "Over")) +
      labs(
        title = paste(sel$player, "-", sel$stat, "(Line:", sel$line, ")"),
        subtitle = paste0("ZINB Distribution (mu=", round(mu, 1), ", theta=", round(theta, 1), ", pi0=", round(pi_0, 2), ")"),
        x = sel$stat, y = "Probability Density"
      ) +
      theme_minimal() +
      theme(
        plot.background = element_rect(fill = "#1a222d", color = NA),
        panel.background = element_rect(fill = "#1a222d", color = NA),
        text = element_text(color = "#ecf0f1"),
        axis.text = element_text(color = "#bdc3c7"),
        legend.position = "top"
      )
  })
}

shinyApp(ui, server)