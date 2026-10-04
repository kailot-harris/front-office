# summary_app.R
#
# Standalone WNBA Model Summary app (static-snapshot). Implements SA-1 from
# docs/SUMMARY_APP_SPEC.md / GitHub issue #55: an app skeleton (bslib navset_tab shell)
# plus Tab 1, "Season Standings & Projections".
#
# Pure static-snapshot design: reads only pre-computed .rds cache files at startup.
# No live model fitting, no wehoop/tidymodels dependency.
#
# Deliberately NOT shared with app.R: this file does not import or source the betting
# terminal app in any way, and relies only on plain bslib/fluidPage constructs (no
# dashboard-style UI package). No shared tabs or code path. Visual style (bslib default
# theme, simple fluidPage/navset_tab) is intentionally distinct from the betting-terminal
# app.R.

library(shiny)
library(bslib)
library(ggplot2)

STANDINGS_CACHE_PATH <- "cache/projected_wnba_standings.rds"

# ---- Startup-only cache load (fail-safe: never crash if the cache is missing) ----
standings_data <- NULL
standings_load_error <- NULL

if (file.exists(STANDINGS_CACHE_PATH)) {
  standings_data <- tryCatch(
    readRDS(STANDINGS_CACHE_PATH),
    error = function(e) {
      standings_load_error <<- conditionMessage(e)
      NULL
    }
  )
} else {
  standings_load_error <- paste("Cache file not found:", STANDINGS_CACHE_PATH)
}

ui <- page_fluid(
  theme = bs_theme(version = 5, bootswatch = "flatly"),
  titlePanel("WNBA Model Summary"),
  navset_tab(
    nav_panel(
      "Season Standings & Projections",
      br(),
      uiOutput("standings_status"),
      layout_columns(
        col_widths = c(7, 5),
        card(
          card_header("Projected Standings"),
          tableOutput("standings_table")
        ),
        card(
          card_header("Projected Wins by Team"),
          plotOutput("standings_chart", height = "500px")
        )
      )
    )
  )
)

server <- function(input, output, session) {

  output$standings_status <- renderUI({
    if (is.null(standings_data)) {
      div(
        class = "alert alert-warning",
        role = "alert",
        strong("No standings data available. "),
        "Placeholder state: ", standings_load_error
      )
    } else {
      NULL
    }
  })

  output$standings_table <- renderTable({
    if (is.null(standings_data)) {
      data.frame(
        Rank = integer(0), Team = character(0), Net_Rating = numeric(0),
        Proj_Wins = numeric(0), Proj_Losses = numeric(0), Win_Pct = numeric(0),
        Top_Core_Players = character(0)
      )
    } else {
      standings_data
    }
  }, striped = TRUE, hover = TRUE, bordered = TRUE)

  output$standings_chart <- renderPlot({
    if (is.null(standings_data) || nrow(standings_data) == 0) {
      return(
        ggplot() +
          annotate("text", x = 0, y = 0, label = "No data available") +
          theme_void()
      )
    }

    df <- standings_data
    df$Team <- factor(df$Team, levels = df$Team[order(df$Proj_Wins)])

    ggplot(df, aes(x = Team, y = Proj_Wins)) +
      geom_col(fill = "#2C3E50") +
      coord_flip() +
      labs(x = NULL, y = "Projected Wins", title = "Projected Wins by Team") +
      theme_minimal(base_size = 13)
  })
}

shinyApp(ui = ui, server = server)
