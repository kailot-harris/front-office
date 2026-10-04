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
# Also implements SA-4 / GitHub issue #58: Tab 4, "Model Comparison" - a table of
# Logistic Regression / Random Forest / XGBoost benchmark metrics from
# data/model_benchmark_results.csv (produced by tools/build_model_benchmark_cache.R,
# which reuses WNBA_Analysis_Project.Rmd's build_feature_df()/build_wnba_recipe()/
# eval_model() logic), plus a rolling-window-size sweep chart (ROC-AUC vs. window size
# 3-25, 95% bootstrap CI ribbon) read directly from the already-cached
# data/window_sweep_3_25_results.csv.
# Also implements SA-5 / GitHub issue #59: Tab 5, "Prediction Accuracy Tracker" - reads
# cache/prediction_accuracy_log.rds, filtered STRICTLY to real, resolved rows
# (is_synthetic == FALSE & status == "RESOLVED"; ~36-39 rows out of 145 as of the last
# cache refresh). Synthetic DIAG_* rows, PENDING rows, and UNRESOLVABLE rows are excluded
# entirely from every value box, table row, and chart point on this tab -- no toggle, no
# code path that can surface them. Value boxes (accuracy %, Brier score, log-loss) reuse
# the already-logged per-row brier_component/log_loss_component columns (verified against
# a manual recompute from predicted_home_win_prob + actual_winner before use) rather than
# re-deriving the formulas inline a third time in this file.
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

# ---- Tab 4 (Model Comparison) cache paths ----
# Both are plain data/ CSV literals (not config.R constants), matching this app's existing
# convention for caches without a central constant (see CLAUDE.md). model_benchmark_results.csv
# is produced by tools/build_model_benchmark_cache.R; window_sweep_3_25_results.csv already
# exists as an authoritative artifact (config.R's ROLLING_WINDOW_SIZE comment) and is read here
# as-is, with no new computation.
MODEL_BENCHMARK_CACHE_PATH <- "data/model_benchmark_results.csv"
WINDOW_SWEEP_CACHE_PATH <- "data/window_sweep_3_25_results.csv"

# ---- Startup-only cache loads for Tab 4 (fail-safe: never crash if a cache is missing) ----
model_benchmark_data <- NULL
model_benchmark_load_error <- NULL

if (file.exists(MODEL_BENCHMARK_CACHE_PATH)) {
  model_benchmark_data <- tryCatch(
    utils::read.csv(MODEL_BENCHMARK_CACHE_PATH, check.names = FALSE, stringsAsFactors = FALSE),
    error = function(e) {
      model_benchmark_load_error <<- conditionMessage(e)
      NULL
    }
  )
} else {
  model_benchmark_load_error <- paste("Cache file not found:", MODEL_BENCHMARK_CACHE_PATH)
}

window_sweep_data <- NULL
window_sweep_load_error <- NULL

if (file.exists(WINDOW_SWEEP_CACHE_PATH)) {
  window_sweep_data <- tryCatch(
    utils::read.csv(WINDOW_SWEEP_CACHE_PATH, check.names = FALSE, stringsAsFactors = FALSE),
    error = function(e) {
      window_sweep_load_error <<- conditionMessage(e)
      NULL
    }
  )
} else {
  window_sweep_load_error <- paste("Cache file not found:", WINDOW_SWEEP_CACHE_PATH)
}

# ---- Tab 5 (Prediction Accuracy Tracker) cache path ----
# Not a config.R constant (same convention as the Tab 2/3 caches above).
PREDICTION_ACCURACY_CACHE_PATH <- "cache/prediction_accuracy_log.rds"

# ---- Startup-only cache load for Tab 5 (fail-safe: never crash if the cache is missing) ----
prediction_accuracy_data <- NULL
prediction_accuracy_load_error <- NULL

if (file.exists(PREDICTION_ACCURACY_CACHE_PATH)) {
  prediction_accuracy_data <- tryCatch(
    readRDS(PREDICTION_ACCURACY_CACHE_PATH),
    error = function(e) {
      prediction_accuracy_load_error <<- conditionMessage(e)
      NULL
    }
  )
} else {
  prediction_accuracy_load_error <- paste("Cache file not found:", PREDICTION_ACCURACY_CACHE_PATH)
}

ui <- page_fluid(
  theme = bs_theme(version = 5, bootswatch = "flatly"),
  div(
    style = "display: flex; align-items: center; justify-content: space-between;",
    titlePanel("WNBA Model Summary"),
    input_dark_mode(id = "dark_mode_toggle")
  ),
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
    ),
    nav_panel(
      "Model Comparison",
      br(),
      uiOutput("model_comparison_status"),
      card(
        card_header("Model Architecture Benchmark (Logistic Regression vs. Random Forest vs. XGBoost)"),
        tableOutput("model_benchmark_table")
      ),
      card(
        card_header("Rolling-Window-Size Sweep: Out-of-Sample ROC-AUC (Window Sizes 3-25)"),
        plotOutput("window_sweep_plot", height = "450px")
      )
    ),
    nav_panel(
      "Prediction Accuracy Tracker",
      br(),
      uiOutput("accuracy_status"),
      layout_columns(
        col_widths = c(4, 4, 4),
        uiOutput("vbox_accuracy_pct"),
        uiOutput("vbox_accuracy_brier"),
        uiOutput("vbox_accuracy_logloss")
      ),
      card(
        card_header("Real Resolved Predictions (synthetic/pending/unresolvable rows excluded)"),
        tableOutput("accuracy_table")
      ),
      card(
        card_header("Cumulative Accuracy Over Time (Running Win Rate as Games Resolve)"),
        plotOutput("accuracy_cumulative_plot", height = "450px")
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

  # ---- Tab 4: Model Comparison (SA-4 / GitHub issue #58) ----

  output$model_comparison_status <- renderUI({
    msgs <- character(0)
    if (is.null(model_benchmark_data)) {
      msgs <- c(msgs, paste0(
        "No model benchmark data available. Placeholder state: ", model_benchmark_load_error
      ))
    }
    if (is.null(window_sweep_data)) {
      msgs <- c(msgs, paste0(
        "No rolling-window-size sweep data available. Placeholder state: ",
        window_sweep_load_error
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

  output$model_benchmark_table <- renderTable({
    if (is.null(model_benchmark_data) || nrow(model_benchmark_data) == 0) {
      data.frame(
        Model = character(0), Accuracy = numeric(0), `ROC-AUC` = numeric(0),
        `Brier Score` = numeric(0), `Log-Loss` = numeric(0), check.names = FALSE
      )
    } else {
      model_benchmark_data
    }
  }, striped = TRUE, hover = TRUE, bordered = TRUE)

  output$window_sweep_plot <- renderPlot({
    if (is.null(window_sweep_data) || nrow(window_sweep_data) == 0) {
      return(
        ggplot() +
          annotate("text", x = 0, y = 0, label = "No rolling-window-size sweep data available") +
          theme_void()
      )
    }

    df <- window_sweep_data
    names(df)[names(df) == "ROC-AUC"] <- "ROC_AUC"
    names(df)[names(df) == "Brier Score"] <- "Brier_Score"

    ggplot(df, aes(x = Window_Size, y = ROC_AUC)) +
      geom_ribbon(
        aes(ymin = ROC_AUC_CI_Lower, ymax = ROC_AUC_CI_Upper),
        fill = "#2C3E50", alpha = 0.15
      ) +
      geom_line(color = "#2C3E50", linewidth = 1.1) +
      geom_point(color = "#18BC9C", size = 2) +
      scale_x_continuous(breaks = seq(3, 25, by = 2)) +
      labs(
        title = "Out-of-Sample ROC-AUC Across Rolling Window Sizes (3-25)",
        subtitle = "Shaded band: 95% bootstrap confidence interval",
        x = "Rolling Window Size (games)",
        y = "Out-of-Sample ROC-AUC"
      ) +
      theme_minimal(base_size = 13)
  })

  # ---- Tab 5: Prediction Accuracy Tracker (SA-5 / GitHub issue #59) ----
  #
  # This is the single most important filter in this tab: STRICTLY restrict to real,
  # resolved rows (is_synthetic == FALSE & status == "RESOLVED") before any value box,
  # table row, or chart point is computed/rendered. Synthetic DIAG_* rows, PENDING rows,
  # and UNRESOLVABLE rows must never reach any output below -- there is no toggle or
  # branch that relaxes this filter anywhere in this tab.

  r_accuracy_filtered <- reactive({
    if (is.null(prediction_accuracy_data) || nrow(prediction_accuracy_data) == 0) {
      return(NULL)
    }

    d <- prediction_accuracy_data
    keep <- !is.na(d$is_synthetic) & !is.na(d$status) &
      d$is_synthetic == FALSE & d$status == "RESOLVED"
    d <- d[keep, , drop = FALSE]

    if (nrow(d) == 0) {
      return(NULL)
    }

    d[order(d$game_date), ]
  })

  output$accuracy_status <- renderUI({
    real_rows <- r_accuracy_filtered()
    if (is.null(real_rows)) {
      msg <- if (is.null(prediction_accuracy_data)) {
        paste("No prediction accuracy data available. Placeholder state:",
              prediction_accuracy_load_error)
      } else {
        "No real, resolved predictions available yet (all rows are synthetic, pending, or unresolvable)."
      }
      div(
        class = "alert alert-warning",
        role = "alert",
        strong("No prediction accuracy data available. "),
        msg
      )
    } else {
      NULL
    }
  })

  output$vbox_accuracy_pct <- renderUI({
    real_rows <- r_accuracy_filtered()
    val <- if (!is.null(real_rows)) {
      sprintf("%.1f%%", mean(real_rows$correct) * 100)
    } else {
      "N/A"
    }
    value_box(
      title = "Overall Accuracy (real resolved games)",
      value = val,
      theme = "teal"
    )
  })

  output$vbox_accuracy_brier <- renderUI({
    real_rows <- r_accuracy_filtered()
    val <- if (!is.null(real_rows)) {
      sprintf("%.4f", mean(real_rows$brier_component))
    } else {
      "N/A"
    }
    value_box(
      title = "Brier Score (lower = better)",
      value = val,
      theme = "teal"
    )
  })

  output$vbox_accuracy_logloss <- renderUI({
    real_rows <- r_accuracy_filtered()
    val <- if (!is.null(real_rows)) {
      sprintf("%.4f", mean(real_rows$log_loss_component))
    } else {
      "N/A"
    }
    value_box(
      title = "Log-Loss (lower = better)",
      value = val,
      theme = "teal"
    )
  })

  output$accuracy_table <- renderTable({
    real_rows <- r_accuracy_filtered()
    if (is.null(real_rows)) {
      data.frame(
        game_date = character(0), home_team = character(0), away_team = character(0),
        predicted_winner = character(0), actual_winner = character(0), correct = logical(0)
      )
    } else {
      data.frame(
        game_date = as.character(real_rows$game_date),
        home_team = real_rows$home_team,
        away_team = real_rows$away_team,
        predicted_winner = real_rows$predicted_winner,
        actual_winner = real_rows$actual_winner,
        correct = real_rows$correct
      )
    }
  }, striped = TRUE, hover = TRUE, bordered = TRUE)

  output$accuracy_cumulative_plot <- renderPlot({
    real_rows <- r_accuracy_filtered()
    if (is.null(real_rows)) {
      return(
        ggplot() +
          annotate("text", x = 0, y = 0, label = "No prediction accuracy data available") +
          theme_void()
      )
    }

    df <- data.frame(
      game_date = real_rows$game_date,
      correct = as.numeric(real_rows$correct)
    )
    df$game_number <- seq_len(nrow(df))
    df$cumulative_accuracy <- cumsum(df$correct) / df$game_number

    ggplot(df, aes(x = game_date, y = cumulative_accuracy)) +
      geom_hline(yintercept = 0.5, linetype = "dashed", color = "#B0B0B0") +
      geom_line(color = "#2C3E50", linewidth = 1.1) +
      geom_point(color = "#18BC9C", size = 2) +
      scale_y_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0, 1)) +
      labs(
        title = "Cumulative Prediction Accuracy Over Time (Real Resolved Games Only)",
        subtitle = sprintf("Running win rate as each of the %d real resolved games resolves chronologically", nrow(df)),
        x = "Game Date",
        y = "Cumulative Accuracy"
      ) +
      theme_minimal(base_size = 13)
  })
}

shinyApp(ui = ui, server = server)
