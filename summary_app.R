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
library(png)
library(grid)
library(reactable)

# ---- Dark-mode-aware plotting/table helpers ----
# input_dark_mode() in the UI below only toggles Bootstrap's own CSS color-mode
# variables -- it has no effect on reactable's self-contained inline styles or
# on ggplot's rendered-to-PNG output, so both need their own explicit dark
# variant wired to the same input$dark_mode_toggle value (see r_dark_mode()
# near the top of server()).

gg_line_ink <- function(dark) if (isTRUE(dark)) "#5DADE2" else "#2C3E50"
gg_text_ink <- function(dark) if (isTRUE(dark)) "#ECECEC" else "#2C3E50"
gg_muted_ink <- function(dark) if (isTRUE(dark)) "#AAAAAA" else "#7F8C8D"

# Appended to every plot's theme chain (on top of theme_minimal()/theme_void()).
# Canvas is always transparent (paired with bg = "transparent" on every
# renderPlot() call below) so the card's own light/dark background shows
# through instead of a hardcoded white rectangle; axis/grid/title colors only
# change in dark mode.
gg_dark_overrides <- function(dark) {
  if (!isTRUE(dark)) {
    return(theme(
      plot.background = element_rect(fill = "transparent", color = NA),
      panel.background = element_rect(fill = "transparent", color = NA)
    ))
  }
  theme(
    plot.background = element_rect(fill = "transparent", color = NA),
    panel.background = element_rect(fill = "transparent", color = NA),
    text = element_text(color = "#ECECEC"),
    axis.text = element_text(color = "#CCCCCC"),
    axis.title = element_text(color = "#ECECEC"),
    plot.title = element_text(color = "#F5F5F5"),
    plot.subtitle = element_text(color = "#AAAAAA"),
    panel.grid.major = element_line(color = "#3A3A3A", linewidth = 0.3),
    panel.grid.minor = element_blank(),
    legend.text = element_text(color = "#ECECEC"),
    legend.title = element_text(color = "#ECECEC")
  )
}

# A separate, narrower override for theme_void()-based plots (the playoff
# bracket, and every "no data available" placeholder plot): theme_void()
# deliberately hides all axis text/titles, and gg_dark_overrides()'s
# axis.text/axis.title entries would silently re-enable them (confirmed live:
# the bracket plot grew visible numeric axis ticks/labels in dark mode without
# this). Only the transparent-canvas part applies here; any in-plot text in
# these charts is colored explicitly at the call site instead (see gg_text_ink()
# usage above).
gg_dark_overrides_void <- function(dark) {
  theme(
    plot.background = element_rect(fill = "transparent", color = NA),
    panel.background = element_rect(fill = "transparent", color = NA)
  )
}

# reactable::reactableTheme() for the three reactableOutput() tables below --
# the package's own light-mode defaults otherwise stay a plain white table
# regardless of bslib's dark-mode toggle.
reactable_dark_theme <- function(dark) {
  if (!isTRUE(dark)) return(reactable::reactableTheme())
  reactable::reactableTheme(
    color = "#ECECEC",
    backgroundColor = "#262626",
    borderColor = "#444444",
    stripedColor = "#2F2F2F",
    highlightColor = "#383838",
    cellPadding = "8px 10px",
    headerStyle = list(backgroundColor = "#1E1E1E", color = "#ECECEC", borderColor = "#444444")
  )
}

# config.R is the single source of truth for WNBA_TEAMS (abbreviation -> full name) and
# WNBA_SEASON_GAMES (needed for Tab 1's 50/50 reference line, at WNBA_SEASON_GAMES / 2
# wins) -- these are the two constants summary_app.R borrows from config.R; everything
# else about this app's "no shared code path with app.R" design (see header comment) is
# unaffected, since config.R is a pure constants file, not app.R itself. Fail-safe
# tryCatch matches the pattern app.R itself already uses to source config.R.
.config_constants <- tryCatch(
  {
    config_env <- new.env()
    source("config.R", local = config_env)
    config_env
  },
  error = function(e) NULL
)
WNBA_TEAMS <- if (!is.null(.config_constants)) get("WNBA_TEAMS", envir = .config_constants) else NULL
WNBA_SEASON_GAMES <- if (!is.null(.config_constants)) get("WNBA_SEASON_GAMES", envir = .config_constants) else 44

# ---- Team logo helpers ----
# Logos live in www/logos/<ABBR>_logo.png (ABBR matches config.R's WNBA_TEAMS names),
# fetched from ESPN's public team-logo CDN. Every lookup is fail-safe: a missing/unmapped
# team name returns NULL and callers fall back to text-only rendering, never an error.
#
# Filename is "<ABBR>_logo.png", NOT a bare "<ABBR>.png": Connecticut Sun's abbreviation
# is CON, and "CON.png"/"CON" is a reserved Windows device name (same family as PRN, AUX,
# NUL, COM1-9, LPT1-9) -- a bare CON.png cannot even be opened via a normal Win32 path,
# which made `git add` fail outright with "No such file or directory" despite the file
# visibly existing on disk. The _logo suffix sidesteps this for CON today and for any
# future team abbreviation that happens to collide with a reserved name.
#
# LOGO_DIR is resolved to an ABSOLUTE path once here, at source time -- not a bare
# relative "www/logos" string. shiny::runApp() changes the process working directory to
# the app's own directory for the life of the server (and a wrapper app.R that sources
# this file from a different directory, as this repo's own headless-probe convention
# does -- see CLAUDE.md -- makes that mismatch even more likely), so a relative path
# evaluated later inside a render/reactive context can silently resolve against the
# wrong directory and make every logo vanish with no error, caught only by actually
# looking at a live screenshot (confirmed empirically during this change: logos
# rendered fine in a standalone Rscript but were blank over shinytest2 until this fix).
LOGO_DIR <- normalizePath("www/logos", mustWork = FALSE)

# Likewise, the <img src="..."> tags used in the standings table rely on Shiny's static
# file serving, which by default only auto-mounts a "www/" folder relative to the app's
# own directory (the same mismatch risk as above). Registering an explicit resource
# path with an absolute target, once, here, decouples logo serving from wherever the
# app happens to be launched from.
tryCatch(
  shiny::addResourcePath("wnba_logos", LOGO_DIR),
  error = function(e) NULL
)

team_abbr_for <- function(team_full_name) {
  if (is.null(WNBA_TEAMS)) return(NA_character_)
  hit <- names(WNBA_TEAMS)[match(team_full_name, WNBA_TEAMS)]
  if (length(hit) == 0) NA_character_ else hit
}

team_logo_path <- function(team_full_name) {
  abbr <- team_abbr_for(team_full_name)
  if (is.na(abbr)) return(NULL)
  p <- file.path(LOGO_DIR, paste0(abbr, "_logo.png"))
  if (file.exists(p)) p else NULL
}

# Small in-session cache so each distinct team's PNG is only decoded once per app run,
# not once per plot re-render.
.logo_raster_cache <- new.env(parent = emptyenv())

team_logo_raster <- function(team_full_name) {
  path <- team_logo_path(team_full_name)
  if (is.null(path)) return(NULL)
  cached <- .logo_raster_cache[[path]]
  if (!is.null(cached)) return(cached)
  img <- tryCatch(png::readPNG(path), error = function(e) NULL)
  if (!is.null(img)) .logo_raster_cache[[path]] <- img
  img
}

# <img> tag for HTML table cells (sanitize.text.function must be identity at the call
# site for this to render as an image rather than escaped text).
team_logo_img_tag <- function(team_full_name, height_px = 24) {
  abbr <- team_abbr_for(team_full_name)
  if (is.na(abbr) || is.null(team_logo_path(team_full_name))) return("")
  sprintf(
    '<img src="wnba_logos/%s_logo.png" height="%d" style="vertical-align: middle;" alt="%s logo">',
    abbr, height_px, htmltools::htmlEscape(team_full_name)
  )
}

STANDINGS_CACHE_PATH <- "cache/projected_wnba_standings.rds"

# ---- Tab 2 (Playoff Bracket) cache path ----
# Not a config.R constant (per CLAUDE.md, this cache has no central constant);
# literal path matching the other consumers' convention.
#
# cache/playoff_series_wnba_demo.rds is deliberately NOT read here. It's
# genuinely stale demo output from playoff_simulator.R's own self-demo suite
# (e.g. it names a "Las Vegas Aces vs Minnesota Lynx" semifinal, but Minnesota
# was actually eliminated in Round 1 -- see tools/series_length_predictor.R's
# REAL_2026_BRACKET/REAL_2026_ROUND1_RESULTS for the real, confirmed bracket
# state). cache/series_length_predictions.rds is the one real-data source for
# this tab: its $round1_results is the real, decided Round 1 outcome, and its
# $semifinal_atl_ny/$semifinal_gs_lv$series fields carry a real simulated win
# probability for the two real confirmed semifinal matchups.
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

# ---- Startup-only cache load for Tab 2 (fail-safe: never crash if the cache is missing) ----
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
  # GitHub issue #63 (D&T visual pass 4/6): small-caps/letter-spacing section-label
  # treatment on every card_header() across all 5 tabs, plus consistent card
  # padding/spacing. No custom tags$style() block existed before this ticket beyond
  # bs_theme() itself.
  tags$style(HTML("
    .card-header {
      text-transform: uppercase;
      font-variant: small-caps;
      letter-spacing: 0.06em;
      font-size: 0.85rem;
      font-weight: 600;
    }
    .card {
      margin-bottom: 1rem;
    }
    .card-body {
      padding: 1rem 1.25rem;
    }
  ")),
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
          reactableOutput("standings_table")
        ),
        card(
          card_header("Projected Wins by Team"),
          plotOutput("standings_chart", height = "500px")
        )
      ),
      br(),
      card(
        card_header("Offense vs. Defense Quadrant (Team Ratings)"),
        plotOutput("ortg_drtg_quadrant_plot", height = "520px")
      ),
      br(),
      accordion(
        open = FALSE,
        accordion_panel(
          "Methodology: what does Net Rating mean, and how is it calculated?",
          p(strong("What a Net Rating of +10 means:"), "A team's Net Rating is its projected
            scoring margin, per 40-minute WNBA regulation game, against a perfectly
            ", em("league-average"), " opponent on a neutral court. The league's 15 teams are
            always centered to average exactly 0.00, so Net Rating is a relative strength
            scale, not an absolute points-per-game number — a +10.0 team is modeled to beat
            a league-average team by about 10 points on a neutral court, and a +10.0 team vs. a
            −5.0 team implies roughly a 15-point model margin before home-court advantage."),
          p(strong("How it's calculated (bottom-up from individual players, not from team
            win-loss record):")),
          tags$ol(
            tags$li("Every rostered player gets a Box Plus-Minus (BPM) rating: a 50/50 blend of
              a box-score-stat-derived component and a plus-minus-derived component, each
              shrunk toward 0.0 for players with limited career minutes so small samples don't
              produce extreme ratings (", code("roster_bottom_up_engine.R"), ")."),
            tags$li("For each team, the 8 players projected to play the most are selected as
              the active rotation (WNBA teams play 5-on-5, not full 12-15 man squads)."),
            tags$li("The team's 200 total on-court minutes for a regulation game (40 minutes
              × 5 players on the floor) are split across that 8-player rotation in
              proportion to each player's historical average minutes, adjusted down for any
              player listed as Out/Doubtful/Questionable on the current injury report."),
            tags$li("The team's raw rating is the minutes-weighted average BPM across the
              rotation, scaled to a 5-on-floor game margin."),
            tags$li("Finally, every team's raw rating is shifted by the same constant —
              the league-wide average raw rating — so the 15 teams' Net Ratings always
              average to exactly 0.00. This is what makes a single number directly comparable
              across teams and seasons: it answers “how much better/worse than a typical
              WNBA team is this roster, right now,” not “how many points per game does
              this team actually score.”")
          ),
          p(em("Net Rating is one of three inputs the model blends into actual game-level win
            probabilities and projected wins (alongside a team RAPM rating and an Elo rating);
            it is not, by itself, the final prediction shown elsewhere in this app."))
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
        reactableOutput("model_benchmark_table")
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
        card_header("Cumulative Accuracy Over Time (Running Win Rate as Games Resolve)"),
        plotOutput("accuracy_cumulative_plot", height = "450px")
      ),
      br(),
      accordion(
        open = FALSE,
        accordion_panel(
          "Real Resolved Predictions (synthetic/pending/unresolvable rows excluded)",
          reactableOutput("accuracy_table")
        )
      )
    )
  )
)

server <- function(input, output, session) {

  # Single reactive source of truth for "is the user currently in dark mode" --
  # feeds both the ggplot dark-mode overrides (gg_dark_overrides()) and
  # reactable's own theme (reactable_dark_theme()) below, so every output in
  # this app reacts to the same input_dark_mode() toggle defined in the UI.
  r_dark_mode <- reactive({
    isTRUE(input$dark_mode_toggle == "dark")
  })

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

  output$standings_table <- renderReactable({
    dark <- r_dark_mode()
    if (is.null(standings_data)) {
      empty_df <- data.frame(
        Logo = character(0), Rank = integer(0), Team = character(0), Net_Rating = numeric(0),
        Proj_Wins = numeric(0), Proj_Wins_SD = numeric(0), Proj_Losses = numeric(0),
        Win_Pct = numeric(0), Top_Core_Players = character(0)
      )
      return(reactable(empty_df, theme = reactable_dark_theme(dark)))
    }

    df <- standings_data
    df$Logo <- vapply(df$Team, team_logo_img_tag, character(1), height_px = 28)
    df <- df[, c("Logo", setdiff(names(df), "Logo"))]

    # Diverging bar cell for Net_Rating: centered at 0, with a distinct color/direction on
    # each side of center (not merely a shorter bar in the same direction) -- below-average
    # teams get a bar growing left from center in a muted/red tone, above-average teams get a
    # bar growing right from center in the app's teal accent (matches the flatly bootswatch
    # theme's primary color, same accent Dunks & Threes uses).
    max_abs_net_rating <- max(abs(df$Net_Rating), na.rm = TRUE)
    net_rating_cell <- function(value) {
      pct <- if (max_abs_net_rating > 0) min(abs(value) / max_abs_net_rating * 100, 100) else 0
      bar_color <- if (value >= 0) "#18BC9C" else "#E74C3C"
      htmltools::tags$div(
        style = "display: flex; align-items: center; width: 100%;",
        htmltools::tags$span(
          style = "width: 44px; text-align: right; margin-right: 6px; font-variant-numeric: tabular-nums;",
          sprintf("%+.2f", value)
        ),
        htmltools::tags$div(
          style = "flex-grow: 1; display: flex; align-items: center; height: 14px;",
          htmltools::tags$div(
            style = "flex: 1; height: 100%; display: flex; justify-content: flex-end;",
            if (value < 0) {
              htmltools::tags$div(style = sprintf(
                "background-color: %s; width: %s%%; height: 100%%; border-radius: 2px;",
                bar_color, pct
              ))
            }
          ),
          htmltools::tags$div(style = "width: 2px; height: 100%; background-color: #999999;"),
          htmltools::tags$div(
            style = "flex: 1; height: 100%; display: flex; justify-content: flex-start;",
            if (value > 0) {
              htmltools::tags$div(style = sprintf(
                "background-color: %s; width: %s%%; height: 100%%; border-radius: 2px;",
                bar_color, pct
              ))
            }
          )
        )
      )
    }

    # Plain 0-to-1 scale bar cell for Win_Pct (not diverging -- 0 is a real floor, not a
    # center point).
    win_pct_cell <- function(value) {
      pct <- max(min(value, 1), 0) * 100
      htmltools::tags$div(
        style = "display: flex; align-items: center; width: 100%;",
        htmltools::tags$span(
          style = "width: 42px; text-align: right; margin-right: 6px; font-variant-numeric: tabular-nums;",
          sprintf("%.3f", value)
        ),
        htmltools::tags$div(
          style = "flex-grow: 1; height: 14px; background-color: #e9ecef; border-radius: 2px;",
          htmltools::tags$div(style = sprintf(
            "background-color: #18BC9C; width: %s%%; height: 100%%; border-radius: 2px;", pct
          ))
        )
      )
    }

    reactable(
      df,
      striped = TRUE,
      bordered = TRUE,
      highlight = TRUE,
      defaultPageSize = 15,
      theme = reactable_dark_theme(dark),
      columns = list(
        Logo = colDef(name = "", html = TRUE, width = 50, sortable = FALSE),
        Rank = colDef(name = "Rank", width = 60),
        Team = colDef(name = "Team"),
        Net_Rating = colDef(name = "Net Rating", cell = net_rating_cell, align = "left"),
        Proj_Wins = colDef(name = "Proj. Wins", format = colFormat(digits = 1)),
        Proj_Wins_SD = colDef(name = "Proj. Wins SD", format = colFormat(digits = 2)),
        Proj_Losses = colDef(name = "Proj. Losses", format = colFormat(digits = 1)),
        Win_Pct = colDef(name = "Win %", cell = win_pct_cell, align = "left"),
        Top_Core_Players = colDef(name = "Top Core Players", minWidth = 220)
      )
    )
  })

  # Industry-standard season-projection chart (FiveThirtyEight/ESPN BPI style): a
  # horizontal dot-and-whisker plot ordered by projected wins, not a bar chart -- bars
  # imply 0 is the meaningful comparison point, but win totals are read against .500 (a
  # 50/50 reference line) and the playoff cutoff, not against zero. The whisker is a real
  # ~95% CI (Proj_Wins +/- 1.96*Proj_Wins_SD), not a fabricated band: Proj_Wins_SD is an
  # analytic standard deviation derived from the model's own per-opponent home/away win
  # probabilities (see roster_bottom_up_engine.R's project_all_wnba_teams(), the
  # expected_wins_var accumulator next to the existing expected_wins loop), treating each
  # team's season as a sum of independent Bernoulli trials.
  output$standings_chart <- renderPlot({
    dark <- r_dark_mode()
    if (is.null(standings_data) || nrow(standings_data) == 0) {
      return(
        ggplot() +
          annotate("text", x = 0, y = 0, label = "No data available", color = gg_text_ink(dark)) +
          theme_void() + gg_dark_overrides_void(dark)
      )
    }

    df <- standings_data
    has_sd <- "Proj_Wins_SD" %in% names(df) && !all(is.na(df$Proj_Wins_SD))
    df$sd <- if (has_sd) df$Proj_Wins_SD else 0
    df$y_pos <- rank(df$Proj_Wins, ties.method = "first")

    ci_mult <- 1.96  # ~95% normal-approximation interval
    df$ci_lower <- pmax(0, df$Proj_Wins - ci_mult * df$sd)
    df$ci_upper <- pmin(WNBA_SEASON_GAMES, df$Proj_Wins + ci_mult * df$sd)

    # 8 of 15 teams make the playoffs (see Tab 2's bracket: 4 best-of-X series in Round
    # 1), so Rank <= 8 is the playoff line -- matches the already-computed Rank column
    # rather than re-deriving a cutoff independently.
    df$playoff_bound <- df$Rank <= 8

    half_line_x <- WNBA_SEASON_GAMES / 2

    x_data_min <- min(df$ci_lower, half_line_x)
    x_data_max <- max(df$ci_upper, half_line_x)
    x_span     <- x_data_max - x_data_min

    logo_half_h <- 0.38
    logo_left   <- x_data_min - x_span * 0.16
    logo_right  <- x_data_min - x_span * 0.02

    p <- ggplot(df, aes(x = Proj_Wins, y = y_pos)) +
      geom_vline(xintercept = half_line_x, linetype = "dashed", color = "#B0B0B0", linewidth = 0.7) +
      annotate(
        "text", x = half_line_x, y = nrow(df) + 0.55, label = sprintf(".500 (%.0f wins)", half_line_x),
        size = 3.2, color = "#7F8C8D", vjust = 0
      ) +
      geom_errorbar(
        aes(xmin = ci_lower, xmax = ci_upper, color = playoff_bound),
        orientation = "y", width = 0.22, linewidth = 0.9, alpha = 0.75
      ) +
      geom_point(aes(color = playoff_bound), size = 3.4) +
      geom_text(
        aes(label = sprintf("%.1f", Proj_Wins), color = playoff_bound),
        hjust = -0.35, vjust = -0.9, size = 3.3, show.legend = FALSE
      )

    for (i in seq_len(nrow(df))) {
      raster <- team_logo_raster(df$Team[i])
      if (is.null(raster)) next
      p <- p + annotation_custom(
        rasterGrob(raster, interpolate = TRUE),
        xmin = logo_left, xmax = logo_right,
        ymin = df$y_pos[i] - logo_half_h, ymax = df$y_pos[i] + logo_half_h
      )
    }

    sd_caption <- if (has_sd) {
      "Whiskers: ~95% interval (projected wins +/- 1.96 SD) from the model's per-opponent win probabilities."
    } else {
      "Whiskers unavailable (Proj_Wins_SD not present in this cache) -- showing point estimates only."
    }

    p +
      scale_color_manual(
        values = c(`TRUE` = "#18BC9C", `FALSE` = "#7F93A8"),
        labels = c(`TRUE` = "Playoff position (top 8)", `FALSE` = "Outside playoff line"),
        name = NULL
      ) +
      scale_y_continuous(breaks = NULL) +
      coord_cartesian(
        xlim = c(logo_left, x_data_max + x_span * 0.08),
        ylim = c(0.3, nrow(df) + 0.9), clip = "off"
      ) +
      labs(
        x = "Projected Wins (44-game season)", y = NULL,
        title = "Projected Wins by Team",
        subtitle = sd_caption
      ) +
      theme_minimal(base_size = 13) +
      theme(
        axis.text.y = element_blank(),
        axis.ticks.y = element_blank(),
        legend.position = "top",
        legend.margin = margin(b = -5),
        plot.subtitle = element_text(size = 9, color = "#7F8C8D"),
        plot.margin = margin(10, 20, 10, 10)
      ) +
      gg_dark_overrides(dark)
  }, bg = "transparent")

  # Quadrant scatter chart: Offensive Rating (x) vs. Defensive Rating (y), one point per
  # team, rendered as that team's logo (GitHub issue #65 / D&T visual pass ticket 6).
  # Off_Rating/Def_Rating come straight from the standings cache (ticket 5 / #64) --
  # Off_Rating - Def_Rating == Net_Rating by construction there, not re-derived here.
  #
  # Sign convention (per #64): Def_Rating is lower-is-better (good defense -> more
  # negative). The y-axis is intentionally left in that natural, un-reversed orientation
  # (low y = good defense), so the "elite" quadrant is bottom-right (high Off_Rating, low
  # Def_Rating) -- NOT top-right. Reversing the axis to put "good defense" visually at the
  # top would make a bad defense's large positive Def_Rating look like it belongs in a
  # "good" quadrant merely because it's high up; this avoids that trap entirely by keeping
  # the axis literal and labeling the quadrants explicitly instead.
  output$ortg_drtg_quadrant_plot <- renderPlot({
    dark <- r_dark_mode()
    if (is.null(standings_data) || nrow(standings_data) == 0 ||
        !all(c("Off_Rating", "Def_Rating") %in% names(standings_data))) {
      return(
        ggplot() +
          annotate("text", x = 0, y = 0, label = "No offense/defense rating data available", color = gg_text_ink(dark)) +
          theme_void() + gg_dark_overrides_void(dark)
      )
    }

    df <- standings_data

    # 0 is the natural center for both axes here (not the sample mean): Off_Rating and
    # Def_Rating are each already league-centered to average ~0.00 by construction in
    # roster_bottom_up_engine.R (same centering convention as Net_Rating), so the
    # quadrant boundary a reader expects -- "league-average offense/defense" -- is x=0 and
    # y=0, not a recomputed sample mean that would drift with whichever 15 teams are in
    # the cache.
    x_span <- max(abs(df$Off_Rating)) * 1.25
    y_span <- max(abs(df$Def_Rating)) * 1.25

    logo_half <- min(x_span, y_span) * 0.09

    p <- ggplot(df, aes(x = Off_Rating, y = Def_Rating)) +
      geom_hline(yintercept = 0, linetype = "dashed", color = "#B0B0B0", linewidth = 0.5) +
      geom_vline(xintercept = 0, linetype = "dashed", color = "#B0B0B0", linewidth = 0.5) +
      annotate("text", x = x_span * 0.97, y = -y_span * 0.95, label = "Elite\n(Off+ / Def best)",
               hjust = 1, vjust = 0, size = 3, color = "#18BC9C", fontface = "italic") +
      annotate("text", x = -x_span * 0.97, y = -y_span * 0.95, label = "Good D, weak O",
               hjust = 0, vjust = 0, size = 3, color = "#7F8C8D", fontface = "italic") +
      annotate("text", x = x_span * 0.97, y = y_span * 0.95, label = "Good O, weak D",
               hjust = 1, vjust = 1, size = 3, color = "#7F8C8D", fontface = "italic") +
      annotate("text", x = -x_span * 0.97, y = y_span * 0.95, label = "Weakest\n(Off- / Def worst)",
               hjust = 0, vjust = 1, size = 3, color = "#E74C3C", fontface = "italic")

    for (i in seq_len(nrow(df))) {
      raster <- team_logo_raster(df$Team[i])
      if (is.null(raster)) next
      p <- p + annotation_custom(
        rasterGrob(raster, interpolate = TRUE),
        xmin = df$Off_Rating[i] - logo_half, xmax = df$Off_Rating[i] + logo_half,
        ymin = df$Def_Rating[i] - logo_half, ymax = df$Def_Rating[i] + logo_half
      )
    }

    p +
      coord_cartesian(xlim = c(-x_span, x_span), ylim = c(-y_span, y_span), clip = "off") +
      labs(
        x = "Offensive Rating (higher = better offense)",
        y = "Defensive Rating (lower = better defense)",
        title = "Offense vs. Defense: Team Quadrant",
        subtitle = "Dashed lines mark league-average (0.00) offense/defense; bottom-right is the elite quadrant"
      ) +
      theme_minimal(base_size = 13) +
      theme(
        panel.grid.major = element_line(color = "#EDEDED", linewidth = 0.3),
        panel.grid.minor = element_blank(),
        plot.subtitle = element_text(size = 9, color = "#7F8C8D"),
        plot.margin = margin(14, 24, 10, 10)
      ) +
      gg_dark_overrides(dark)
  }, bg = "transparent")

  # ---- Tab 2: Playoff Bracket (SA-2 / GitHub issue #56) ----

  output$bracket_status <- renderUI({
    if (!is.null(series_length_data)) {
      return(NULL)
    }
    div(
      class = "alert alert-warning",
      role = "alert",
      strong("Warning: "),
      "No series-length prediction data available. Placeholder state: ",
      series_length_load_error
    )
  })

  output$bracket_plot <- renderPlot({
    dark <- r_dark_mode()
    ink <- gg_text_ink(dark)

    # Fail-safe empty state: this whole tab now depends on a single real-data
    # source, series_length_predictions.rds -- see the cache-path comment above
    # for why cache/playoff_series_wnba_demo.rds is never read here.
    if (is.null(series_length_data) || is.null(series_length_data$round1_results)) {
      return(
        ggplot() +
          annotate("text", x = 0, y = 0, label = "No playoff bracket data available", color = ink) +
          theme_void() + gg_dark_overrides_void(dark)
      )
    }

    round1 <- series_length_data$round1_results
    sf_atl_ny <- series_length_data$semifinal_atl_ny$series
    sf_gs_lv  <- series_length_data$semifinal_gs_lv$series

    finals_note_text <- if (!is.null(series_length_data$finals_note)) {
      series_length_data$finals_note
    } else {
      "Finals status unknown."
    }
    finals_note_text <- paste(strwrap(finals_note_text, width = 30), collapse = "\n")

    fmt_pct <- function(p) sprintf("%.1f%%", p * 100)
    fmt_ml <- function(ml) {
      ml <- round(ml)
      if (ml > 0) sprintf("+%d", ml) else sprintf("%d", ml)
    }
    wrap_line <- function(txt, width = 14) {
      paste(strwrap(txt, width = width), collapse = "\n")
    }

    box_w        <- 3.3
    NODE_H       <- 1.0   # box height
    NODE_OFFSET  <- 0.65  # distance from a match's center y to each of its 2 nodes
    BOTTOM_EDGE  <- NODE_OFFSET + NODE_H / 2
    centers_x <- c(1.9, 6.9, 11.9)

    # Real, single-elimination bracket shape: 4 decided Round 1 series feed 2
    # real confirmed semifinal matchups, which feed 1 pending Finals slot.
    # tools/series_length_predictor.R's REAL_2026_ROUND1_RESULTS is listed in
    # seed order (1v8, 2v7, 3v6, 4v5), but the STANDARD bracket pairing puts
    # (1v8) adjacent to (4v5) -- not (2v7) -- since those are the two Round 1
    # matches whose winners actually meet in the Atlanta-vs-NY semifinal
    # (1=MIN lost to 8=NY; 4=ATL beat 5=WSH). (2v7) and (3v6) are the other
    # half, feeding Golden State-vs-Las Vegas. Reorder to that standard
    # top/bottom bracket-half grouping before laying out rows, rather than
    # trusting the cache's seed-ascending list order to already be bracket-
    # adjacent (it isn't -- that mismatch previously caused Round 1
    # connectors to visually wire into the wrong semifinal slot).
    bracket_half_order <- c(1, 4, 2, 3) # seed_high order, standard-bracket-adjacent
    round1 <- round1[order(match(
      vapply(round1, function(r) r$seed_high, numeric(1)), bracket_half_order
    ))]

    # Spacing (2.6) clears 2*NODE_OFFSET+NODE_H (2.3) so adjacent matches'
    # nearest boxes never overlap.
    match_y <- c(3.9, 1.3, -1.3, -3.9)

    # ---- Round 1 nodes: real decided results, not probabilities. ----
    build_decided_match <- function(res, y_mid) {
      data.frame(
        x = centers_x[1],
        y = c(y_mid + NODE_OFFSET, y_mid - NODE_OFFSET),
        team = c(res$team_high, res$team_low),
        record = c(
          sprintf("%s %d-%d", if (res$winner == res$team_high) "W" else "L", res$wins_high, res$wins_low),
          sprintf("%s %d-%d", if (res$winner == res$team_low) "W" else "L", res$wins_low, res$wins_high)
        ),
        is_favorite = c(res$winner == res$team_high, res$winner == res$team_low),
        pending = FALSE
      )
    }
    round1_nodes <- do.call(rbind, Map(build_decided_match, round1, match_y))

    # ---- Semifinal nodes: real simulated win probability for the real matchup. ----
    sf_y <- c(mean(match_y[1:2]), mean(match_y[3:4]))
    build_sf_match <- function(series, y_mid) {
      favorite_is_high <- series$p_high_seed_win >= series$p_low_seed_win
      data.frame(
        x = centers_x[2],
        y = c(y_mid + NODE_OFFSET, y_mid - NODE_OFFSET),
        team = c(series$high_seed, series$low_seed),
        record = c(fmt_pct(series$p_high_seed_win), fmt_pct(series$p_low_seed_win)),
        is_favorite = c(favorite_is_high, !favorite_is_high),
        pending = FALSE
      )
    }
    sf_nodes <- rbind(
      build_sf_match(sf_atl_ny, sf_y[1]),
      build_sf_match(sf_gs_lv, sf_y[2])
    )

    # ---- Finals nodes: genuinely pending. ----
    finals_y <- mean(sf_y)
    finals_nodes <- data.frame(
      x = centers_x[3], y = c(finals_y + NODE_OFFSET, finals_y - NODE_OFFSET),
      team = c("TBD", "TBD"), record = c("", ""),
      is_favorite = c(FALSE, FALSE), pending = TRUE
    )

    nodes_df <- rbind(round1_nodes, sf_nodes, finals_nodes)
    wrapped_team <- vapply(nodes_df$team, wrap_line, character(1))
    nodes_df$label <- ifelse(
      nodes_df$record == "",
      nodes_df$team,
      paste0(wrapped_team, "\n", nodes_df$record)
    )
    # Decided nodes get a team logo in the left third of their box, so the text label
    # shifts right to make room; pending ("TBD") nodes have no logo and stay centered.
    logo_x_offset <- 0.75
    nodes_df$text_x <- ifelse(nodes_df$pending, nodes_df$x, nodes_df$x + logo_x_offset)
    nodes_df$logo_x <- nodes_df$x - logo_x_offset

    caption_for <- function(series) {
      paste(
        series$format_label,
        paste0("Fair ML: ", fmt_ml(series$fair_ml_high), " / ", fmt_ml(series$fair_ml_low)),
        paste0("Avg series games: ", round(series$avg_series_games, 2)),
        sep = "\n"
      )
    }
    captions_df <- data.frame(
      x = c(centers_x[2], centers_x[2], centers_x[3]),
      y = c(sf_y[1] - BOTTOM_EDGE - 0.6, sf_y[2] - BOTTOM_EDGE - 0.6, finals_y - BOTTOM_EDGE - 0.6),
      label = c(caption_for(sf_atl_ny), caption_for(sf_gs_lv), finals_note_text)
    )

    round_titles <- data.frame(
      x = centers_x,
      y = max(match_y) + BOTTOM_EDGE + 0.5,
      label = c("First Round (Final)", "Semifinals", "Finals (TBD)")
    )

    # Elbow connector: a 3-segment "H"/"Z" shape from (cx_left, y_source) to
    # (cx_right, y_target).
    build_connector <- function(cx_left, cx_right, y_source, y_target) {
      xmid <- (cx_left + box_w / 2 + cx_right - box_w / 2) / 2
      data.frame(
        x    = c(cx_left + box_w / 2, xmid,     xmid),
        xend = c(xmid,                xmid,     cx_right - box_w / 2),
        y    = c(y_source,            y_source, y_target),
        yend = c(y_source,            y_target, y_target)
      )
    }

    # Round 1 -> Semifinals: looked up by the actual winning team's name in
    # both columns, rather than assumed from row position -- a literal
    # "winner advances to this exact slot" line, which is correct now that
    # Round 1 is fully decided and both semifinal matchups are real and
    # confirmed (unlike Tab 2's earlier single-series-per-round design, which
    # had no real per-team lineage to draw).
    node_y_for_team <- function(df, team_name) df$y[df$team == team_name][1]
    round1_to_sf_connectors <- do.call(rbind, lapply(round1, function(res) {
      y_source <- node_y_for_team(round1_nodes, res$winner)
      y_target <- node_y_for_team(sf_nodes, res$winner)
      if (is.na(y_source) || is.na(y_target)) return(NULL)
      build_connector(centers_x[1], centers_x[2], y_source, y_target)
    }))

    connectors <- rbind(
      round1_to_sf_connectors,
      build_connector(centers_x[2], centers_x[3], sf_y[1], finals_y + NODE_OFFSET),
      build_connector(centers_x[2], centers_x[3], sf_y[2], finals_y - NODE_OFFSET)
    )

    nodes_decided <- nodes_df[!nodes_df$pending, ]
    nodes_pending <- nodes_df[nodes_df$pending, ]

    p <- ggplot() +
      geom_segment(
        data = connectors,
        aes(x = x, xend = xend, y = y, yend = yend),
        linewidth = 0.9, color = "#B0B0B0"
      ) +
      geom_tile(
        data = nodes_decided,
        aes(x = x, y = y, fill = is_favorite),
        width = box_w, height = NODE_H, color = "#2C3E50", linewidth = 0.6
      ) +
      geom_tile(
        data = nodes_pending,
        aes(x = x, y = y),
        width = box_w, height = NODE_H, fill = "#F4F6F6",
        color = "#B0B0B0", linewidth = 0.8, linetype = "dashed"
      )

    # Team logos in the left portion of each decided box (see nodes_df$logo_x above);
    # pending ("TBD") boxes have no team yet, so no logo to draw.
    logo_half_w <- 0.42
    logo_half_h <- 0.40
    for (i in seq_len(nrow(nodes_decided))) {
      raster <- team_logo_raster(nodes_decided$team[i])
      if (is.null(raster)) next
      p <- p + annotation_custom(
        rasterGrob(raster, interpolate = TRUE),
        xmin = nodes_decided$logo_x[i] - logo_half_w, xmax = nodes_decided$logo_x[i] + logo_half_w,
        ymin = nodes_decided$y[i] - logo_half_h, ymax = nodes_decided$y[i] + logo_half_h
      )
    }

    p +
      geom_text(
        data = nodes_df,
        aes(x = text_x, y = y, label = label, color = is_favorite),
        fontface = "bold", size = 3.3, lineheight = 1.05
      ) +
      geom_text(
        data = round_titles,
        aes(x = x, y = y, label = label),
        fontface = "bold", size = 5, color = ink
      ) +
      geom_label(
        data = captions_df,
        aes(x = x, y = y, label = label),
        size = 3, lineheight = 1.15, label.padding = unit(0.35, "lines"),
        color = "#2C3E50", fill = "white"
      ) +
      scale_fill_manual(values = c(`TRUE` = "#18BC9C", `FALSE` = "#EAECEE"), guide = "none") +
      scale_color_manual(values = c(`TRUE` = "white", `FALSE` = "#2C3E50"), guide = "none") +
      xlim(centers_x[1] - box_w, centers_x[3] + box_w) +
      ylim(min(captions_df$y) - 0.9, max(round_titles$y) + 0.4) +
      theme_void() +
      gg_dark_overrides_void(dark)
  }, bg = "transparent")

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
    dark <- r_dark_mode()
    cal <- r_calibration_result()

    if (!cal$real) {
      return(
        ggplot() +
          annotate("text", x = 0, y = 0, label = "No calibration data available", color = gg_text_ink(dark)) +
          theme_void() + gg_dark_overrides_void(dark)
      )
    }

    cal_df <- cal$result$table

    ggplot(cal_df, aes(x = mean_predicted, y = observed_win_rate)) +
      geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "#e74c3c", linewidth = 1) +
      geom_line(color = if (dark) "#D7B4EA" else "#af7ac5", linewidth = 1.3) +
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
      # GitHub issue #63: minimal/thin gridlines, consistent with every other chart in this
      # file (standings_chart, ortg_drtg_quadrant_plot) -- same light-gray 0.3pt major grid,
      # no minor grid. The geom_abline() 45-degree reference line above is untouched: it
      # carries real semantic meaning (perfect calibration) and keeps its own color/weight.
      theme_minimal(base_size = 13) +
      theme(
        panel.grid.major = element_line(color = "#EDEDED", linewidth = 0.3),
        panel.grid.minor = element_blank(),
        plot.subtitle = element_text(size = 9, color = "#7F8C8D")
      ) +
      gg_dark_overrides(dark)
  }, bg = "transparent")

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

  output$model_benchmark_table <- renderReactable({
    dark <- r_dark_mode()
    if (is.null(model_benchmark_data) || nrow(model_benchmark_data) == 0) {
      empty_df <- data.frame(
        Model = character(0), Accuracy = numeric(0), `ROC-AUC` = numeric(0),
        `Brier Score` = numeric(0), `Log-Loss` = numeric(0), check.names = FALSE
      )
      return(reactable(empty_df, theme = reactable_dark_theme(dark)))
    }

    df <- model_benchmark_data

    # Shared red -> yellow -> green ramp for all bar cells below: "goodness" is always
    # passed in on a 0 (worst, red) to 1 (best, green) scale, so callers do the
    # direction/inversion math and this function only ever maps goodness -> color.
    bar_color_scale <- function(goodness) {
      goodness <- min(max(goodness, 0), 1)
      ramp <- grDevices::colorRampPalette(c("#E74C3C", "#F1C40F", "#18BC9C"))(101)
      ramp[round(goodness * 100) + 1]
    }

    bar_cell_html <- function(pct, color, label) {
      htmltools::tags$div(
        style = "display: flex; align-items: center; width: 100%;",
        htmltools::tags$span(
          style = "width: 50px; text-align: right; margin-right: 6px; font-variant-numeric: tabular-nums;",
          label
        ),
        htmltools::tags$div(
          style = "flex-grow: 1; height: 14px; background-color: #e9ecef; border-radius: 2px;",
          htmltools::tags$div(style = sprintf(
            "background-color: %s; width: %s%%; height: 100%%; border-radius: 2px;",
            color, pct
          ))
        )
      )
    }

    # Accuracy / ROC-AUC: 0-1 scale, higher-is-better ("normal direction" per issue #61 --
    # see Brier/Log-Loss comment below for the opposite convention). Bar length and color
    # both scale directly with the raw value: higher value = longer bar = greener.
    normal_bar_cell <- function(value) {
      pct <- max(min(value, 1), 0) * 100
      bar_cell_html(pct, bar_color_scale(value), sprintf("%.3f", value))
    }

    # Brier Score / Log-Loss: lower-is-better metrics. Inversion convention chosen for
    # issue #61 (option (b) from the ticket): bar LENGTH stays proportional to the raw
    # value (so these two differently-scaled columns remain visually comparable row to
    # row), but the COLOR scale is flipped relative to Accuracy/ROC-AUC above -- goodness
    # is computed as 1 - normalized_value, so the lowest raw value in the column reads as
    # the shortest *and* greenest bar (best model), and the highest raw value reads as the
    # longest *and* reddest bar (worst model). Do not reuse normal_bar_cell() for these.
    inverted_bar_cell <- function(value, col_values) {
      max_value <- max(col_values, na.rm = TRUE)
      min_value <- min(col_values, na.rm = TRUE)
      pct <- if (max_value > 0) (value / max_value) * 100 else 0
      goodness <- if (max_value > min_value) {
        1 - (value - min_value) / (max_value - min_value)
      } else {
        1
      }
      bar_cell_html(pct, bar_color_scale(goodness), sprintf("%.4f", value))
    }

    brier_values <- df[["Brier Score"]]
    logloss_values <- df[["Log-Loss"]]

    reactable(
      df,
      striped = TRUE,
      bordered = TRUE,
      highlight = TRUE,
      theme = reactable_dark_theme(dark),
      columns = list(
        Model = colDef(name = "Model"),
        Accuracy = colDef(name = "Accuracy", cell = normal_bar_cell, align = "left"),
        `ROC-AUC` = colDef(name = "ROC-AUC", cell = normal_bar_cell, align = "left"),
        `Brier Score` = colDef(
          name = "Brier Score", align = "left",
          cell = function(value) inverted_bar_cell(value, brier_values)
        ),
        `Log-Loss` = colDef(
          name = "Log-Loss", align = "left",
          cell = function(value) inverted_bar_cell(value, logloss_values)
        )
      )
    )
  })

  output$window_sweep_plot <- renderPlot({
    dark <- r_dark_mode()
    if (is.null(window_sweep_data) || nrow(window_sweep_data) == 0) {
      return(
        ggplot() +
          annotate("text", x = 0, y = 0, label = "No rolling-window-size sweep data available", color = gg_text_ink(dark)) +
          theme_void() + gg_dark_overrides_void(dark)
      )
    }

    df <- window_sweep_data
    names(df)[names(df) == "ROC-AUC"] <- "ROC_AUC"
    names(df)[names(df) == "Brier Score"] <- "Brier_Score"

    ggplot(df, aes(x = Window_Size, y = ROC_AUC)) +
      geom_ribbon(
        aes(ymin = ROC_AUC_CI_Lower, ymax = ROC_AUC_CI_Upper),
        fill = gg_line_ink(dark), alpha = 0.15
      ) +
      geom_line(color = gg_line_ink(dark), linewidth = 1.1) +
      geom_point(color = "#18BC9C", size = 2) +
      scale_x_continuous(breaks = seq(3, 25, by = 2)) +
      labs(
        title = "Out-of-Sample ROC-AUC Across Rolling Window Sizes (3-25)",
        subtitle = "Shaded band: 95% bootstrap confidence interval",
        x = "Rolling Window Size (games)",
        y = "Out-of-Sample ROC-AUC"
      ) +
      # GitHub issue #63: minimal/thin gridlines, same convention as the rest of this file.
      theme_minimal(base_size = 13) +
      theme(
        panel.grid.major = element_line(color = "#EDEDED", linewidth = 0.3),
        panel.grid.minor = element_blank(),
        plot.subtitle = element_text(size = 9, color = "#7F8C8D")
      ) +
      gg_dark_overrides(dark)
  }, bg = "transparent")

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

  output$accuracy_table <- renderReactable({
    dark <- r_dark_mode()
    real_rows <- r_accuracy_filtered()
    df <- if (is.null(real_rows)) {
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

    # Per-game log, not a numeric-metric table -- no bar cells here (contrast with
    # standings_table/model_benchmark_table). Instead, tint whole rows by outcome:
    # correct == TRUE gets the app's existing teal "good" accent (#18BC9C, same hue
    # used for positive signal elsewhere in this file, e.g. the win-probability fill
    # scale), correct == FALSE gets the matching red/muted "bad" accent (#E74C3C
    # family) used for worst-case/negative values in the other reactable tables.
    reactable(
      df,
      striped = TRUE,
      bordered = TRUE,
      highlight = TRUE,
      defaultPageSize = 15,
      theme = reactable_dark_theme(dark),
      # Row tint text colors are swapped for dark mode: the light-mode colors
      # below (#0B4A3E/#7B241C) are near-black and unreadable against a dark
      # table background, so dark mode gets a lighter tint + lighter ink
      # instead of reusing the light-mode pair at a different opacity.
      rowStyle = function(index) {
        if (isTRUE(df$correct[index])) {
          if (dark) {
            list(backgroundColor = "rgba(24, 188, 156, 0.25)", color = "#BFF5E6")
          } else {
            list(backgroundColor = "rgba(24, 188, 156, 0.18)", color = "#0B4A3E")
          }
        } else {
          if (dark) {
            list(backgroundColor = "rgba(231, 76, 60, 0.25)", color = "#FFD9D2")
          } else {
            list(backgroundColor = "rgba(231, 76, 60, 0.15)", color = "#7B241C")
          }
        }
      },
      columns = list(
        game_date = colDef(name = "Date"),
        home_team = colDef(name = "Home"),
        away_team = colDef(name = "Away"),
        predicted_winner = colDef(name = "Predicted Winner"),
        actual_winner = colDef(name = "Actual Winner"),
        correct = colDef(
          name = "Correct",
          cell = function(value) if (isTRUE(value)) "✓" else "✗"
        )
      )
    )
  })

  # Lives inside a closed-by-default accordion panel (see UI block above). Shiny
  # suspends rendering for outputs that start out hidden and, unlike a tabsetPanel,
  # a bslib accordion's expand/collapse doesn't trigger Shiny's own visibility-change
  # re-render hook -- without this, the table stays permanently blank even after the
  # panel is opened (confirmed live: aria-expanded flips to "true" on click, but
  # accuracy_table's innerHTML stays empty). suspendWhenHidden = FALSE forces it to
  # render in the background regardless of the accordion's open/closed state.
  outputOptions(output, "accuracy_table", suspendWhenHidden = FALSE)

  output$accuracy_cumulative_plot <- renderPlot({
    dark <- r_dark_mode()
    real_rows <- r_accuracy_filtered()
    if (is.null(real_rows)) {
      return(
        ggplot() +
          annotate("text", x = 0, y = 0, label = "No prediction accuracy data available", color = gg_text_ink(dark)) +
          theme_void() + gg_dark_overrides_void(dark)
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
      geom_line(color = gg_line_ink(dark), linewidth = 1.1) +
      geom_point(color = "#18BC9C", size = 2) +
      scale_y_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0, 1)) +
      labs(
        title = "Cumulative Prediction Accuracy Over Time (Real Resolved Games Only)",
        subtitle = sprintf("Running win rate as each of the %d real resolved games resolves chronologically", nrow(df)),
        x = "Game Date",
        y = "Cumulative Accuracy"
      ) +
      # GitHub issue #63: minimal/thin gridlines, same convention as the rest of this file.
      # The 0.5 (coin-flip baseline) geom_hline() above is untouched -- it already uses the
      # same light, thin styling this ticket establishes elsewhere, and carries real
      # semantic meaning (the reference an accuracy rate is actually judged against).
      theme_minimal(base_size = 13) +
      theme(
        panel.grid.major = element_line(color = "#EDEDED", linewidth = 0.3),
        panel.grid.minor = element_blank(),
        plot.subtitle = element_text(size = 9, color = "#7F8C8D")
      ) +
      gg_dark_overrides(dark)
  }, bg = "transparent")
}

shinyApp(ui = ui, server = server)
