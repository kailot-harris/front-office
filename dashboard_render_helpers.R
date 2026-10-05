# ==============================================================================
# dashboard_render_helpers.R
#
# Pure "build the plot/table object from already-prepared data" helpers, extracted out of
# app.R's server function (GitHub issue #49, Slice 5 of #43, first half). Each function here
# takes explicit data arguments (data frames, vectors, lists) - never `input$`, `session`, or
# any other reactive object - and returns a ggplot/plotly/datatable object. This is a pure
# extraction: the body of each function below is byte-for-byte the same construction logic
# that used to live inline inside the matching `output$<id> <- render*(...)` block in app.R;
# only the input$-dependent reactive data-fetching/filtering was left behind in app.R.
#
# Designed so a later, separate piece of work (issue #49's second half) can call these same
# functions from a different Shiny app (control_panel_app.R) outside of app.R's reactive
# context, by just handing them already-computed data.
#
# Dependencies: assumes ggplot2, dplyr, tidyr, scales, stringr, DT, and plotly are already
# attached by the caller (app.R attaches all of these before sourcing this file) - this file
# does not call library()/require() itself.
# ==============================================================================

# ------------------------------------------------------------------------------
# Shared internal helper (used by the three Tab 8 diagnostics plotly builders below).
# Not one of the 15 "build_*" outputs itself - just de-duplicated support code that was
# previously a local closure (`.diag_empty_plot`) inside app.R's server function. Moved here
# because it contains no input$/session reference either.
# ------------------------------------------------------------------------------
.diag_empty_plot <- function(msg, size = 4.5, wrap_width = 40) {
  wrapped <- paste(strwrap(msg, width = wrap_width), collapse = "\n")
  ggplotly(
    ggplot() +
      annotate("text", x = 0, y = 0, label = wrapped, color = "#bdc3c7", size = size) +
      theme_void() +
      theme(plot.background = element_rect(fill = "#1a222d", color = NA))
  )
}

# ----------------------------------------------------------------------------
# Tab 1: Daily Edges -- output$tbl_daily_edges
# ----------------------------------------------------------------------------
build_tbl_daily_edges <- function(df) {
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
}

# ----------------------------------------------------------------------------
# Tab 2: Steam Radar -- output$tbl_steam_radar
#
# `hist_df` is the raw data frame read from cache/odds_history.rds by the caller (NULL if the
# cache file does not exist). All column-detection/summarise/format logic - previously wrapped
# in a tryCatch(..., error = function(e) NULL) directly inside the render block because any of
# the grep()/group_by() calls below could fail on an unexpected schema - stays wrapped here for
# the same fail-safe reason; a processing error still falls through to the "MONITORING ACTIVE"
# placeholder rather than crashing the tab.
# ----------------------------------------------------------------------------
build_tbl_steam_radar <- function(hist_df) {
  steam_df <- tryCatch({
    if (is.null(hist_df) || !is.data.frame(hist_df) || nrow(hist_df) == 0) {
      NULL
    } else {
      names(hist_df) <- tolower(names(hist_df))

      m_col <- grep("matchup|game|teams", names(hist_df), value = TRUE)[1] %||% "matchup"
      h_col <- grep("home_ml|current_ml|ml_home|line", names(hist_df), value = TRUE)[1] %||% "home_ml"
      s_col <- grep("consensus|sharp|pinnacle", names(hist_df), value = TRUE)[1]
      b_col <- grep("book|sportsbook", names(hist_df), value = TRUE)[1]

      if (!m_col %in% names(hist_df) || !h_col %in% names(hist_df)) {
        NULL
      } else {
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
              abs(Line_Drift) >= 20 ~ "\U0001F6A8 HEAVY SHARP STEAM",
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
  }, error = function(e) {
    NULL
  })

  if (is.null(steam_df) || nrow(steam_df) == 0) {
    datatable(
      data.frame(
        Status = "MONITORING ACTIVE",
        Details = "Gathering consecutive market snapshots. Steam signals populate as sportsbooks update lines. WNBA book coverage is thinner than NBA's, so this may take longer to populate than expected.",
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
}

# ----------------------------------------------------------------------------
# Tab 3: Injury Monitor -- output$tbl_injuries
#
# `cache_exists` / `inj_raw` are resolved by the caller before this is called: `cache_exists`
# is `file.exists("cache/injury_data_cache.rds")`, and `inj_raw` is the tryCatch-guarded
# readRDS() of that path (NULL if the cache is missing or the read failed). This preserves the
# three distinct messages the original inline code showed (cache pending / cache
# refreshing-or-corrupted / report clear) exactly.
# ----------------------------------------------------------------------------
build_tbl_injuries <- function(cache_exists, inj_raw) {
  if (!cache_exists) {
    return(datatable(tibble(Notice = "Injury scraper cache pending next pipeline execution."), rownames = FALSE))
  }
  if (is.null(inj_raw)) {
    return(datatable(tibble(
      Notice = "Injury cache is being refreshed right now (or was corrupted) - try again in a moment."
    ), rownames = FALSE))
  }
  if (nrow(inj_raw) > 0) {
    inj_display <- inj_raw %>%
      mutate(
        Status = status,
        Spread_Impact = case_when(
          grepl("OUT", status, ignore.case = TRUE) ~ "-3.5 to -5.0 pts",
          grepl("QUESTIONABLE", status, ignore.case = TRUE) ~ "-1.5 to -2.5 pts",
          TRUE ~ "-0.5 pts"
        ),
        Source = coalesce(data_source, "UNKNOWN")
      ) %>%
      select(
        Date = game_date,
        Team = team_name,
        Player = player_name,
        Status = status,
        Injury = injury_desc,
        `Est. Spread Drag` = Spread_Impact,
        `Data Source` = Source
      )
    datatable(inj_display, options = list(pageLength = 8, scrollX = TRUE), rownames = FALSE)
  } else {
    datatable(tibble(
      Status = "OFFICIAL REPORT CLEAR",
      Details = "No confirmed player scratches currently reported on the active slate. All rosters projected at 100% strength."
    ), rownames = FALSE)
  }
}

# ----------------------------------------------------------------------------
# Tab 4: Bet Tracker -- output$plot_bankroll_drawdown
# `ledger` is dat$ledger from r_risk_data() (the caller's req(dat$ledger) must run before this
# is invoked, since req() is a Shiny-reactive-context primitive and stays in app.R).
# ----------------------------------------------------------------------------
build_plot_bankroll_drawdown <- function(ledger) {
  ggplot(ledger, aes(x = date, y = bankroll)) +
    geom_area(fill = "#9b59b6", alpha = 0.25) +
    geom_line(color = "#af7ac5", linewidth = 1.2) +
    geom_hline(yintercept = 100, linetype = "dashed", color = "#7f8c8d") +
    labs(title = "Quantitative Portfolio Growth (Base 100.0 Units)", x = "Date", y = "Bankroll (Units)") +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "#1a222d", color = NA),
      panel.background = element_rect(fill = "#1a222d", color = NA),
      text = element_text(color = "#ecf0f1"),
      axis.text = element_text(color = "#bdc3c7")
    )
}

# ----------------------------------------------------------------------------
# Tab 4: Bet Tracker -- output$tbl_graded_ledger
# `ledger` is dat$ledger from r_risk_data() (caller's req(dat$ledger) runs before this).
# ----------------------------------------------------------------------------
build_tbl_graded_ledger <- function(ledger) {
  datatable(ledger, options = list(pageLength = 8, scrollX = TRUE), rownames = FALSE)
}

# ----------------------------------------------------------------------------
# Tab 5: Team Embeddings -- output$plot_embeddings_pca
# `emb` is the raw data frame from r_embeddings_raw() (NULL / 0-row if unavailable).
# ----------------------------------------------------------------------------
build_plot_embeddings_pca <- function(emb) {
  if (is.null(emb) || nrow(emb) == 0) {
    return(
      ggplot() +
        annotate("text", x = 1, y = 1, label = "team_embeddings.csv not found - run team_embeddings.py first.", color = "#bdc3c7", size = 5) +
        theme_void() + theme(plot.background = element_rect(fill = "#1a222d", color = NA))
    )
  }

  emb_cols <- grep("^emb_", names(emb), value = TRUE)
  if (length(emb_cols) < 2) {
    return(
      ggplot() +
        annotate("text", x = 1, y = 1, label = "team_embeddings.csv has fewer than 2 emb_* dims - cannot PCA-project.", color = "#bdc3c7", size = 5) +
        theme_void() + theme(plot.background = element_rect(fill = "#1a222d", color = NA))
    )
  }

  mat <- as.matrix(emb[, emb_cols, drop = FALSE])
  pca <- prcomp(mat, center = TRUE, scale. = TRUE)
  var_pct <- round(100 * (pca$sdev^2 / sum(pca$sdev^2))[1:2], 1)

  p_data <- tibble(
    team_id = emb$team_id,
    pc1 = pca$x[, 1],
    pc2 = pca$x[, 2]
  )

  ggplot(p_data, aes(x = pc1, y = pc2, label = paste("Team", team_id))) +
    geom_point(size = 5.5, alpha = 0.85, color = "#af7ac5") +
    geom_text(vjust = -1.2, color = "#ecf0f1", fontface = "bold", size = 3.5) +
    labs(
      title = "15 WNBA Teams: Real 16-D Embedding Vectors, PCA-Projected to 2D",
      subtitle = paste0("PC1 explains ", var_pct[1], "% of variance, PC2 explains ", var_pct[2], "% (real-data-trained as of P1, 2026-09-12 - see caveat above)"),
      x = "Principal Component 1", y = "Principal Component 2"
    ) +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "#1a222d", color = NA),
      panel.background = element_rect(fill = "#1a222d", color = NA),
      text = element_text(color = "#ecf0f1"),
      axis.text = element_text(color = "#bdc3c7")
    )
}

# ----------------------------------------------------------------------------
# Tab 5: Team Embeddings -- output$plot_embeddings_heatmap
# `sim` is the raw data frame from r_similarity_raw() (NULL / 0-row if unavailable).
# ----------------------------------------------------------------------------
build_plot_embeddings_heatmap <- function(sim) {
  if (is.null(sim) || nrow(sim) == 0) {
    return(
      ggplot() +
        annotate("text", x = 1, y = 1, label = "team_similarity_matrix.csv not found - run team_embeddings.py first.", color = "#bdc3c7", size = 5) +
        theme_void() + theme(plot.background = element_rect(fill = "#1a222d", color = NA))
    )
  }

  long_cols <- c("team_a", "team_b", "similarity")
  if (all(long_cols %in% names(sim))) {
    labels <- sort(unique(as.character(sim$team_a)))
    long_df <- sim %>%
      transmute(
        row_team = factor(as.character(team_a), levels = labels),
        col_team = factor(as.character(team_b), levels = labels),
        similarity = as.numeric(similarity)
      )
    return(
      ggplot(long_df, aes(x = col_team, y = row_team, fill = similarity)) +
        geom_tile() +
        scale_fill_gradient2(low = "#2c3e50", mid = "#af7ac5", high = "#ffffff",
                             midpoint = 0.5, name = "Cosine Sim") +
        labs(title = sprintf("%dx%d WNBA Team Embedding Cosine-Similarity Matrix",
                             length(labels), length(labels)), x = NULL, y = NULL) +
        theme_minimal() +
        theme(
          plot.background = element_rect(fill = "#1a222d", color = NA),
          panel.background = element_rect(fill = "#1a222d", color = NA),
          text = element_text(color = "#ecf0f1"),
          axis.text = element_text(color = "#bdc3c7"),
          axis.text.x = element_text(angle = 45, hjust = 1)
        )
    )
  }

  has_label_col <- ncol(sim) == nrow(sim) + 1
  if (has_label_col) {
    first_col <- sim[[1]]
    first_col_is_numeric_index <- is.numeric(first_col) ||
      (is.character(first_col) && !anyNA(suppressWarnings(as.numeric(first_col))))
    team_labels <- if (!first_col_is_numeric_index) as.character(first_col) else NULL
    mat_df <- sim[, -1, drop = FALSE]
  } else {
    team_labels <- NULL
    mat_df <- sim
  }
  n <- nrow(mat_df)
  mat <- as.matrix(mat_df)
  if (ncol(mat) != n) {
    return(
      ggplot() +
        annotate("text", x = 1, y = 1, size = 5, color = "#e74c3c",
                 label = sprintf("Similarity matrix is not square (%d rows x %d cols) - cannot render heatmap.",
                                 n, ncol(mat))) +
        theme_void() + theme(plot.background = element_rect(fill = "#1a222d", color = NA))
    )
  }
  labels <- if (!is.null(team_labels) && length(team_labels) == n) team_labels else paste0("T", 1:n)
  rownames(mat) <- labels
  colnames(mat) <- labels

  long_df <- as.data.frame(mat) %>%
    mutate(row_team = rownames(mat)) %>%
    pivot_longer(-row_team, names_to = "col_team", values_to = "similarity") %>%
    mutate(
      row_team = factor(row_team, levels = labels),
      col_team = factor(col_team, levels = labels)
    )

  ggplot(long_df, aes(x = col_team, y = row_team, fill = similarity)) +
    geom_tile() +
    scale_fill_gradient2(low = "#2c3e50", mid = "#af7ac5", high = "#ffffff", midpoint = 0.5, name = "Cosine Sim") +
    labs(title = "15x15 WNBA Team Embedding Cosine-Similarity Matrix", x = NULL, y = NULL) +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "#1a222d", color = NA),
      panel.background = element_rect(fill = "#1a222d", color = NA),
      text = element_text(color = "#ecf0f1"),
      axis.text = element_text(color = "#bdc3c7"),
      axis.text.x = element_text(angle = 45, hjust = 1)
    )
}

# ----------------------------------------------------------------------------
# Tab 6: Calibration Curve -- output$plot_calibration_curve
# `cal` is the list returned by r_calibration_result(): list(real, source_label, result).
# ----------------------------------------------------------------------------
build_plot_calibration_curve <- function(cal) {
  if (!cal$real) {
    probs <- seq(0.35, 0.75, by = 0.08)
    actual <- probs + rnorm(length(probs), 0, 0.015)
    df <- tibble(pred = probs, actual = actual)
    p <- ggplot(df, aes(x = pred, y = actual)) +
      geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "#e74c3c", linewidth = 1) +
      geom_line(color = "#af7ac5", linewidth = 1.3) +
      geom_point(color = "#2ecc71", size = 4.5) +
      scale_x_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0.25, 0.85)) +
      scale_y_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0.25, 0.85)) +
      labs(
        title = "SYNTHETIC FALLBACK — box_scores_cache.rds unavailable",
        subtitle = "Illustrative only. Not real model calibration.",
        x = "Model Predicted Win Probability",
        y = "Empirical Realized Win Rate"
      )
  } else {
    cal_df <- cal$result$table
    p <- ggplot(cal_df, aes(x = mean_predicted, y = observed_win_rate)) +
      geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "#e74c3c", linewidth = 1) +
      geom_line(color = "#af7ac5", linewidth = 1.3) +
      geom_point(aes(size = n_games), color = "#2ecc71") +
      scale_x_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0, 1)) +
      scale_y_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0, 1)) +
      labs(
        title = sprintf("Model Probability Calibration (Real WNBA Games) — Brier: %.4f | BSS: %.3f | Log-Loss: %.4f",
                         cal$result$brier, cal$result$bss, cal$result$log_loss),
        subtitle = "Ideal Calibration follows 45-degree dashed reference line (Expected Prob == Observed Win Rate)",
        x = "Model Predicted Win Probability",
        y = "Empirical Realized Win Rate",
        size = "Games in bin"
      )
  }

  p +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "#1a222d", color = NA),
      panel.background = element_rect(fill = "#1a222d", color = NA),
      text = element_text(color = "#ecf0f1"),
      axis.text = element_text(color = "#bdc3c7")
    )
}

# ----------------------------------------------------------------------------
# Tab 7: Standings & Calculator -- output$tbl_bottom_up_standings
# `std` is r_standings_data()'s result.
# ----------------------------------------------------------------------------
build_tbl_bottom_up_standings <- function(std) {
  display_df <- std %>% select(-starts_with("norm_"))

  if ("Win_Pct" %in% names(display_df) && is.numeric(display_df$Win_Pct)) {
    display_df$Win_Pct <- scales::percent(display_df$Win_Pct, accuracy = 0.1)
  }

  datatable(display_df, options = list(pageLength = 10), rownames = FALSE)
}

# ----------------------------------------------------------------------------
# Tab 8: Model Diagnostics -- output$plot_residual_scatter
# `df` is the already-chartable (NA-residual-filtered) data frame; the caller's req(!is.null(df))
# and the nrow(df) == 0 empty-state call into .diag_empty_plot() mirror app.R's original
# control flow exactly.
# ----------------------------------------------------------------------------
build_plot_residual_scatter <- function(df) {
  if (nrow(df) == 0) return(.diag_empty_plot("No chartable predictions yet\n(predicted_margin missing on all resolved rows)"))

  p <- ggplot(df, aes(x = predicted_margin, y = actual_margin)) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "#e74c3c", linewidth = 1) +
    geom_point(color = "#af7ac5", alpha = 0.6) +
    labs(title = "Predicted vs. Actual Margin", x = "Predicted Margin (Home - Away)", y = "Actual Margin") +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "#1a222d", color = NA),
      panel.background = element_rect(fill = "#1a222d", color = NA),
      text = element_text(color = "#ecf0f1"),
      axis.text = element_text(color = "#bdc3c7")
    )
  ggplotly(p)
}

# ----------------------------------------------------------------------------
# Tab 8: Model Diagnostics -- output$plot_residual_dist
# ----------------------------------------------------------------------------
build_plot_residual_dist <- function(df) {
  if (nrow(df) == 0) return(.diag_empty_plot("No chartable predictions yet (predicted_margin missing on all resolved rows)", size = 3.3, wrap_width = 20))

  p <- ggplot(df, aes(x = residual)) +
    geom_histogram(bins = 20, fill = "#af7ac5", color = "#ecf0f1", alpha = 0.8) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "#e74c3c", linewidth = 1) +
    labs(title = "Distribution of Residuals", x = "Residual (Actual - Predicted)", y = "Frequency") +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "#1a222d", color = NA),
      panel.background = element_rect(fill = "#1a222d", color = NA),
      text = element_text(color = "#ecf0f1"),
      axis.text = element_text(color = "#bdc3c7")
    )
  ggplotly(p)
}

# ----------------------------------------------------------------------------
# Tab 8: Model Diagnostics -- output$plot_team_bias
# ----------------------------------------------------------------------------
build_plot_team_bias <- function(df) {
  if (nrow(df) == 0) return(.diag_empty_plot("No chartable predictions yet\n(predicted_margin missing on all resolved rows)"))

  team_bias <- df |>
    group_by(home_team) |>
    summarise(mean_res = mean(residual, na.rm = TRUE)) |>
    arrange(desc(mean_res))

  p <- ggplot(team_bias, aes(x = reorder(home_team, mean_res), y = mean_res)) +
    geom_col(fill = "#af7ac5") +
    coord_flip() +
    labs(title = "Mean Residual by Team (Home Games)", x = "Team", y = "Mean Residual") +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "#1a222d", color = NA),
      panel.background = element_rect(fill = "#1a222d", color = NA),
      text = element_text(color = "#ecf0f1"),
      axis.text = element_text(color = "#bdc3c7")
    )
  ggplotly(p)
}

# ----------------------------------------------------------------------------
# Tab 9: Props Terminal -- output$tbl_props_terminal
# `df` is filtered_props()'s result.
# ----------------------------------------------------------------------------
build_tbl_props_terminal <- function(df) {
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
}

# ----------------------------------------------------------------------------
# Tab 9: Props Terminal -- output$plot_prop_zinb_curve
# `df` is filtered_props()'s result (used only for the empty-state check, as before); `sel` is
# the single selected-row data frame the caller already resolved from
# input$tbl_props_terminal_rows_selected (0 rows if df itself is empty). Both are plain data,
# no input$/session reference here.
# ----------------------------------------------------------------------------
build_plot_prop_zinb_curve <- function(df, sel) {
  if (nrow(df) == 0) {
    return(
      ggplot() +
        annotate("text", x = 1, y = 1, label = "No Props Matching Criteria", color = "#bdc3c7", size = 5) +
        theme_void() +
        theme(plot.background = element_rect(fill = "#1a222d", color = NA))
    )
  }

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
}

# ----------------------------------------------------------------------------
# Tab 10: Clutch & Shot Profile -- output$tbl_clutch_shot_profile
# `df` is r_pbp_features()'s result (NULL if the cache is missing/unreadable). `show_low_volume`
# is the caller's resolved boolean value of input$clutch_show_low_volume, passed in as a plain
# argument (not read via input$ inside this function).
# ----------------------------------------------------------------------------
build_tbl_clutch_shot_profile <- function(df, show_low_volume) {
  if (is.null(df) || nrow(df) == 0) {
    return(datatable(tibble(
      Notice = "Play-by-play player features not yet generated - run pbp_engine.R (or the full pipeline) to build cache/player_pbp_features.rds."
    ), rownames = FALSE, options = list(dom = "t")))
  }

  display_df <- df %>%
    mutate(
      clutch_fg_pct          = dplyr::coalesce(clutch_fg_pct, 0),
      pct_rim                = dplyr::coalesce(pct_rim, 0),
      pct_off_dribble_jumper = dplyr::coalesce(pct_off_dribble_jumper, 0),
      pct_catch_shoot_jumper = dplyr::coalesce(pct_catch_shoot_jumper, 0),
      pct_three              = dplyr::coalesce(pct_three, 0)
    )

  if (!isTRUE(show_low_volume)) {
    display_df <- display_df %>% filter(fga_total >= 20)
  }

  if (nrow(display_df) == 0) {
    return(datatable(tibble(
      Notice = "No players meet the current FGA threshold - check 'Show low-volume players' above."
    ), rownames = FALSE, options = list(dom = "t")))
  }

  display_view <- display_df %>%
    transmute(
      Player = player_name,
      Team = team_abbreviation,
      `Data Source` = data_source,
      FGA = fga_total,
      `Clutch Pts` = clutch_points,
      `Clutch FG%` = scales::percent(clutch_fg_pct, accuracy = 0.1),
      `Clutch Scoring Plays` = clutch_scoring_plays,
      Assists = assists,
      `Rim %` = scales::percent(pct_rim, accuracy = 0.1),
      `Off-Dribble Jumper %` = scales::percent(pct_off_dribble_jumper, accuracy = 0.1),
      `Catch & Shoot %` = scales::percent(pct_catch_shoot_jumper, accuracy = 0.1),
      `3PT Rate` = scales::percent(pct_three, accuracy = 0.1)
    ) %>%
    arrange(desc(`Clutch Pts`))

  datatable(display_view, options = list(pageLength = 12, scrollX = TRUE), rownames = FALSE)
}
