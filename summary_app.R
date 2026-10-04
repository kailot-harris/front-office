# summary_app.R
#
# Standalone WNBA Model Summary app (static-snapshot). Implements SA-1 from
# docs/SUMMARY_APP_SPEC.md / GitHub issue #55: an app skeleton (bslib navset_tab shell)
# plus Tab 1, "Season Standings & Projections". Also implements SA-2 / GitHub issue #56:
# Tab 2, "Playoff Bracket" (ggplot2-rendered bracket graphic).
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

# ---- Tab 2 (Playoff Bracket) cache paths ----
# Not config.R constants (per CLAUDE.md, these two caches have no central constant);
# literal paths matching the other consumers' convention.
PLAYOFF_SERIES_CACHE_PATH <- "cache/playoff_series_wnba_demo.rds"
SERIES_LENGTH_CACHE_PATH <- "cache/series_length_predictions.rds"

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

# ---- Startup-only cache loads for Tab 2 (fail-safe: never crash if a cache is missing) ----
playoff_series_data <- NULL
playoff_series_load_error <- NULL

if (file.exists(PLAYOFF_SERIES_CACHE_PATH)) {
  playoff_series_data <- tryCatch(
    readRDS(PLAYOFF_SERIES_CACHE_PATH),
    error = function(e) {
      playoff_series_load_error <<- conditionMessage(e)
      NULL
    }
  )
} else {
  playoff_series_load_error <- paste("Cache file not found:", PLAYOFF_SERIES_CACHE_PATH)
}

series_length_data <- NULL
series_length_load_error <- NULL

if (file.exists(SERIES_LENGTH_CACHE_PATH)) {
  series_length_data <- tryCatch(
    readRDS(SERIES_LENGTH_CACHE_PATH),
    error = function(e) {
      series_length_load_error <<- conditionMessage(e)
      NULL
    }
  )
} else {
  series_length_load_error <- paste("Cache file not found:", SERIES_LENGTH_CACHE_PATH)
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
    ),
    nav_panel(
      "Playoff Bracket",
      br(),
      uiOutput("bracket_status"),
      card(
        card_header("Playoff Bracket: First Round → Semifinals → Finals (TBD)"),
        plotOutput("bracket_plot", height = "550px")
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

  # ---- Tab 2: Playoff Bracket (SA-2 / GitHub issue #56) ----

  output$bracket_status <- renderUI({
    msgs <- character(0)
    if (is.null(playoff_series_data)) {
      msgs <- c(msgs, paste0(
        "No playoff series data available. Placeholder state: ", playoff_series_load_error
      ))
    }
    if (is.null(series_length_data)) {
      msgs <- c(msgs, paste0(
        "No series-length prediction data available. Placeholder state: ",
        series_length_load_error
      ))
    }
    if (length(msgs) == 0) {
      return(NULL)
    }
    div(
      class = "alert alert-warning",
      role = "alert",
      lapply(msgs, function(m) tagList(strong("Warning: "), m, br()))
    )
  })

  output$bracket_plot <- renderPlot({

    # Fail-safe empty state: First Round + Semifinals rendering needs
    # playoff_series_data; the Finals slot needs series_length_data's finals_note.
    # If either cache is missing we still render what we can, with a clearly
    # labeled placeholder for the missing piece (never crash).
    if (is.null(playoff_series_data)) {
      return(
        ggplot() +
          annotate("text", x = 0, y = 0, label = "No playoff bracket data available") +
          theme_void()
      )
    }

    # finals_note is read ONLY from series_length_predictions.rds. The Finals
    # matchup inside playoff_series_wnba_demo.rds$finals is intentionally never
    # read or rendered anywhere in this tab -- series_length_predictions.rds's
    # "pending" stance is the source of truth for Finals status.
    finals_note_text <- if (!is.null(series_length_data) &&
                             !is.null(series_length_data$finals_note)) {
      series_length_data$finals_note
    } else {
      "Series-length prediction data unavailable; Finals status unknown."
    }
    finals_note_text <- paste(strwrap(finals_note_text, width = 26), collapse = "\n")

    fr <- playoff_series_data$first_round
    sf <- playoff_series_data$semifinals

    fmt_pct <- function(p) sprintf("%.1f%%", p * 100)
    fmt_ml <- function(ml) {
      ml <- round(ml)
      if (ml > 0) sprintf("+%d", ml) else sprintf("%d", ml)
    }
    wrap_line <- function(txt, width = 26) {
      paste(strwrap(txt, width = width), collapse = "\n")
    }

    make_box_label <- function(series) {
      paste(
        wrap_line(paste0(series$high_seed, " vs ", series$low_seed)),
        series$format_label,
        wrap_line(paste0(
          "P(", series$high_seed, " wins): ", fmt_pct(series$p_high_seed_win)
        )),
        wrap_line(paste0(
          "Fair ML: ", series$high_seed, " ", fmt_ml(series$fair_ml_high),
          " / ", series$low_seed, " ", fmt_ml(series$fair_ml_low)
        )),
        paste0("Avg series games: ", round(series$avg_series_games, 2)),
        sep = "\n"
      )
    }

    box_w <- 2.6
    box_h <- 2.1
    centers_x <- c(1.5, 5, 8.5)
    y_center <- 2

    boxes <- data.frame(
      xmin = centers_x - box_w / 2,
      xmax = centers_x + box_w / 2,
      ymin = y_center - box_h / 2,
      ymax = y_center + box_h / 2,
      round_label = c("First Round", "Semifinals", "Finals")
    )

    labels_df <- data.frame(
      x = centers_x,
      y = y_center,
      label = c(make_box_label(fr), make_box_label(sf), finals_note_text)
    )

    round_titles <- data.frame(
      x = centers_x,
      y = y_center + box_h / 2 + 0.25,
      label = c("First Round", "Semifinals", "Finals (TBD)")
    )

    connectors <- data.frame(
      x = c(centers_x[1] + box_w / 2, centers_x[2] + box_w / 2),
      xend = c(centers_x[2] - box_w / 2, centers_x[3] - box_w / 2),
      y = y_center,
      yend = y_center
    )

    box_fill <- c("#2C3E50", "#18BC9C", "#B0B0B0")

    ggplot() +
      geom_rect(
        data = boxes,
        aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
        fill = box_fill, color = "black", alpha = 0.15
      ) +
      geom_segment(
        data = connectors,
        aes(x = x, xend = xend, y = y, yend = yend),
        linewidth = 1, color = "#2C3E50",
        arrow = arrow(length = unit(0.2, "cm"))
      ) +
      geom_text(
        data = round_titles,
        aes(x = x, y = y, label = label),
        fontface = "bold", size = 5
      ) +
      geom_label(
        data = labels_df,
        aes(x = x, y = y, label = label),
        size = 3.3, lineheight = 1.1, label.padding = unit(0.4, "lines")
      ) +
      xlim(centers_x[1] - box_w, centers_x[3] + box_w) +
      ylim(y_center - box_h, y_center + box_h + 0.6) +
      theme_void()
  })
}

shinyApp(ui = ui, server = server)
