# summary_app.R
#
# Standalone WNBA Model Summary app (static-snapshot). Implements SA-1 from
# docs/SUMMARY_APP_SPEC.md / GitHub issue #55: an app skeleton (bslib navset_tab shell)
# plus Tab 1, "Season Standings & Projections". Also implements SA-2 / GitHub issue #56:
# Tab 2, "Playoff Bracket" (ggplot2-rendered bracket graphic). Also implements SA-3 /
# GitHub issue #57: Tab 3, "Model Calibration & Reliability" — ported essentially
# verbatim from app.R (UI ~lines 277-292, server ~lines 1123-1200), reading
# cache/model_calibration_input.rds and reproducing the same Brier/BSS/Log-loss value
# boxes and calibration curve plot. The Brier/BSS/Log-loss/binning math itself is
# copy/adapted inline from live_calibration.R::calibration_analysis() (sport-agnostic
# math, no NBA-specific constants) rather than sourcing app.R or live_calibration.R,
# per the no-shared-code-path constraint established in SA-1.
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

# ---- Tab 3 (Model Calibration & Reliability) cache path ----
# Also not a config.R constant (same convention as the Tab 2 caches above).
CALIBRATION_CACHE_PATH <- "cache/model_calibration_input.rds"

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

# ---- Startup-only cache load for Tab 3 (fail-safe: never crash if the cache is missing) ----
calibration_data <- NULL
calibration_load_error <- NULL

if (file.exists(CALIBRATION_CACHE_PATH)) {
  calibration_data <- tryCatch(
    readRDS(CALIBRATION_CACHE_PATH),
    error = function(e) {
      calibration_load_error <<- conditionMessage(e)
      NULL
    }
  )
} else {
  calibration_load_error <- paste("Cache file not found:", CALIBRATION_CACHE_PATH)
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
    ),
    nav_panel(
      "Model Calibration & Reliability",
      br(),
      uiOutput("calibration_status"),
      layout_columns(
        col_widths = c(4, 4, 4),
        uiOutput("vbox_brier"),
        uiOutput("vbox_bss"),
        uiOutput("vbox_logloss")
      ),
      card(
        card_header("Model Probability Calibration & Brier Reliability Diagnostics"),
        uiOutput("calibration_source_caption"),
        plotOutput("calibration_curve_plot", height = "450px")
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

  # ---- Tab 3: Model Calibration & Reliability (SA-3 / GitHub issue #57) ----
  #
  # Ported essentially verbatim from app.R's Tab 6 (UI ~lines 277-292, server
  # ~lines 1123-1200): same Brier score / Brier Skill Score / Log-Loss formulas and
  # same 10%-wide predicted-probability-bin calibration curve, computed independently
  # here (copy/adapted from live_calibration.R::calibration_analysis() inline, rather
  # than sourcing app.R or live_calibration.R) against cache/model_calibration_input.rds.

  r_calibration_result <- reactive({
    if (is.null(calibration_data) || nrow(calibration_data) == 0) {
      return(list(real = FALSE, source_label = paste(
        "No calibration data available. Placeholder state:",
        calibration_load_error
      ), result = NULL))
    }

    preds <- calibration_data
    win_actual <- ifelse(preds$target_home_win == "Win", 1, 0)

    # Brier score: mean squared error of predicted probability vs. actual outcome.
    brier <- mean((win_actual - preds$.pred_Win)^2)
    # Brier Skill Score vs. a 50/50-baseline Brier of 0.25.
    brier_baseline <- 0.25
    bss <- 1 - (brier / brier_baseline)
    # Log-loss (binary cross-entropy), clamped away from 0/1 to avoid -Inf.
    log_loss <- -mean(
      win_actual * log(pmax(1e-6, preds$.pred_Win)) +
        (1 - win_actual) * log(pmax(1e-6, 1 - preds$.pred_Win))
    )

    # Calibration curve: bin predicted probability into 10%-wide buckets, compare
    # mean predicted probability to observed win rate within each bucket.
    bin <- cut(preds$.pred_Win, breaks = seq(0, 1, by = 0.10), include.lowest = TRUE)
    cal_df <- aggregate(
      cbind(mean_predicted = .pred_Win, observed_win_rate = win_actual) ~ bin,
      data = data.frame(bin = bin, .pred_Win = preds$.pred_Win, win_actual = win_actual),
      FUN = mean
    )
    n_games <- as.integer(table(bin)[as.character(cal_df$bin)])
    cal_df$n_games <- n_games

    list(
      real = TRUE,
      source_label = paste(
        "Real data:", CALIBRATION_CACHE_PATH,
        "(1,902 real WNBA games, 2019-2026; point-in-time rolling-margin model vs.",
        "real recorded outcomes)."
      ),
      result = list(table = cal_df, brier = brier, bss = bss, log_loss = log_loss)
    )
  })

  output$calibration_status <- renderUI({
    cal <- r_calibration_result()
    if (!cal$real) {
      div(
        class = "alert alert-warning",
        role = "alert",
        strong("No calibration data available. "),
        "Placeholder state: ", cal$source_label
      )
    } else {
      NULL
    }
  })

  output$calibration_source_caption <- renderUI({
    cal <- r_calibration_result()
    p(style = if (cal$real) "color: #2C3E50; font-size: 12px;" else "color: #e74c3c; font-size: 12px;",
      cal$source_label)
  })

  output$vbox_brier <- renderUI({
    cal <- r_calibration_result()
    val <- if (cal$real) sprintf("%.4f", cal$result$brier) else "N/A"
    value_box(
      title = "Brier Score (lower = better)",
      value = val,
      theme = "purple"
    )
  })

  output$vbox_bss <- renderUI({
    cal <- r_calibration_result()
    val <- if (cal$real) sprintf("%.3f", cal$result$bss) else "N/A"
    value_box(
      title = "Brier Skill Score (vs. 50/50 baseline)",
      value = val,
      theme = "purple"
    )
  })

  output$vbox_logloss <- renderUI({
    cal <- r_calibration_result()
    val <- if (cal$real) sprintf("%.4f", cal$result$log_loss) else "N/A"
    value_box(
      title = "Log-Loss (lower = better)",
      value = val,
      theme = "purple"
    )
  })

  output$calibration_curve_plot <- renderPlot({
    cal <- r_calibration_result()

    if (!cal$real) {
      return(
        ggplot() +
          annotate("text", x = 0, y = 0, label = "No calibration data available") +
          theme_void()
      )
    }

    cal_df <- cal$result$table

    ggplot(cal_df, aes(x = mean_predicted, y = observed_win_rate)) +
      geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "#e74c3c", linewidth = 1) +
      geom_line(color = "#af7ac5", linewidth = 1.3) +
      geom_point(aes(size = n_games), color = "#18BC9C") +
      scale_x_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0, 1)) +
      scale_y_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0, 1)) +
      labs(
        title = sprintf(
          "Model Probability Calibration (Real WNBA Games) — Brier: %.4f | BSS: %.3f | Log-Loss: %.4f",
          cal$result$brier, cal$result$bss, cal$result$log_loss
        ),
        subtitle = "Ideal Calibration follows 45-degree dashed reference line (Expected Prob == Observed Win Rate)",
        x = "Model Predicted Win Probability",
        y = "Empirical Realized Win Rate",
        size = "Games in bin"
      ) +
      theme_minimal(base_size = 13)
  })
}

shinyApp(ui = ui, server = server)
