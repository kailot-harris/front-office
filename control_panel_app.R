# ==============================================================================
# control_panel_app.R
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/control_panel_app.R
#
# GitHub issue #46 (Slice 2 of issue #43's tree). Lets an operator pick exactly ONE stage
# from pipeline_stages.R's PIPELINE_STAGES registry, run it synchronously in-process (via
# source(), same call_fn/entry_fn contract as run_full_pipeline.R's run_stage() -- see
# run_pipeline_stage_captured() below), and see a pass/fail result plus the captured
# console output.
#
# SCOPE (explicit, per the issue): single-stage, synchronous/blocking execution only. No
# dependency-staleness checking (#47), no multi-select/queueing (#48), no inline
# chart/table rendering of a stage's *data* output (#49 -- this shows captured text output
# only), no auth/password gate or non-localhost exposure (#50). This is a TRIGGERING tool,
# not a read-only dashboard -- app.R (the existing shinydashboard) is a distinct file with a
# distinct job and is intentionally left untouched.
#
# EXECUTION MODEL: clicking "Run Stage" blocks the single R process for the duration of the
# stage (no background worker, no live log streaming -- out of scope per the issue). The run
# control is disabled the instant the button is clicked via an inline onclick handler (so the
# browser reflects "running" immediately, independent of the server round-trip that is about
# to block on the stage itself) and is re-enabled by the server once the blocking call
# returns and the result is ready to render.
#
# CONTRACT FIDELITY: run_pipeline_stage_captured() below mirrors run_full_pipeline.R's
# run_stage() stage-invocation contract (source() the script, then either call the named
# call_fn or verify the named entry_fn exists post-source, with the same .py -> system2()
# branch) rather than reimplementing a divergent version of it. It does NOT reuse run_stage()
# itself (that function is console-oriented: it writes straight to message()/cat() and
# returns a bare TRUE/FALSE, with no captured-output channel for a UI to display) and it does
# NOT alter run_full_pipeline.R in any way -- this file is loaded standalone, so
# run_full_pipeline.R's own 13-stage loop is unaffected by anything here.
# ==============================================================================

req_pkgs <- c("shiny", "shinyjs")
new_pkgs <- req_pkgs[!(req_pkgs %in% installed.packages()[, "Package"])]
if (length(new_pkgs)) install.packages(new_pkgs)

suppressPackageStartupMessages({
  library(shiny)
  library(shinyjs)
})

# No setwd() here, deliberately -- per CLAUDE.md's flat-layout convention every script in this
# repo (including app.R) assumes it is launched with the project root already as the working
# directory and sources siblings by bare filename. A hardcoded absolute-path setwd() here would
# silently escape into a *different* checkout (e.g. the main repo instead of a git worktree)
# whenever one happens to exist at that literal path, which is exactly what broke this app
# under shinytest2/git-worktree-based testing.

# Capture the working directory this file was sourced from (= project root, by the convention
# above) ONCE, at load time. shiny::runApp() pins the working directory to the app's own
# directory for the life of the R process and re-applies that pin around session/reactive
# dispatch -- harmless when control_panel_app.R is launched the normal way (its own directory
# IS the project root), but it means code inside a later reactive context cannot trust getwd()
# to still be the project root, only whatever it was at THIS source() call. Every later
# relative-path operation in this file (stage script paths) restores this dir explicitly
# instead of assuming getwd() is still correct by then.
.CONTROL_PANEL_ROOT <- getwd()

# Sourced in the same order run_full_pipeline.R requires (config.R before pipeline_stages.R,
# since several registry `output`/`inputs` entries reference config.R's CACHE_* constants
# unquoted).
source("config.R")
source("pipeline_stages.R")

# ------------------------------------------------------------------------------------------
# run_pipeline_stage_captured(stage)
#
# Runs a single PIPELINE_STAGES entry in-process, capturing stdout (cat()/print()) plus
# message()/warning() conditions into one ordered character vector, and reports pass/fail
# without ever propagating an error out of this function (callers -- i.e. the Shiny server
# below -- must not crash on a stage failure; that is the whole point of criterion 3).
#
# Mirrors run_stage()'s (run_full_pipeline.R, ~line 126) own logic point for point:
#   - stage$script must exist, else a clean fail (not a stop()).
#   - a .R/.r script is source()'d with local = FALSE (same as run_stage()); a .py script is
#     run via system2() with its exit status checked, exactly like run_stage()'s python
#     branch, since this stage-runner must support every registry entry, not just R ones.
#   - if stage$call_fn is set, that function is invoked after sourcing (run_stage() invokes
#     call_fn; it does NOT invoke entry_fn).
#   - if stage$entry_fn is set, only EXISTENCE is checked after sourcing (same as run_stage())
#     -- the script's own `if (!interactive())`-style footer is what actually runs it, and
#     this process (launched via Rscript) is non-interactive so that footer fires exactly as
#     it would under run_full_pipeline.R.
# ------------------------------------------------------------------------------------------
run_pipeline_stage_captured <- function(stage) {
  log_lines <- character(0)
  add_line <- function(x) log_lines <<- c(log_lines, x)

  start <- Sys.time()
  error_msg <- NULL

  # Restore the project root captured at load time -- see .CONTROL_PANEL_ROOT's comment above.
  # Every stage script in the registry (and anything it itself source()s) is written assuming
  # cwd = project root, same as run_full_pipeline.R's own run_stage().
  setwd(.CONTROL_PANEL_ROOT)

  ok <- tryCatch({
    withCallingHandlers(
      {
        captured <- capture.output({
          if (!file.exists(stage$script)) {
            stop(sprintf("Stage script not found: %s", stage$script))
          }
          if (grepl("\\.py$", stage$script)) {
            py_out <- system2("python", args = stage$script, stdout = TRUE, stderr = TRUE)
            cat(paste(py_out, collapse = "\n"), "\n")
            status <- attr(py_out, "status")
            if (!is.null(status) && !is.na(status) && status != 0) {
              stop(sprintf("Python stage %s exited with status %s", stage$script, status))
            }
          } else {
            source(stage$script, local = FALSE)
            if (!is.null(stage$call_fn)) {
              if (exists(stage$call_fn, envir = .GlobalEnv, mode = "function", inherits = FALSE)) {
                get(stage$call_fn, envir = .GlobalEnv, mode = "function", inherits = FALSE)()
              } else {
                warning(sprintf("call_fn '%s' not found as a function after sourcing %s.",
                                 stage$call_fn, stage$script))
              }
            }
            if (!is.null(stage$entry_fn) &&
                !exists(stage$entry_fn, envir = .GlobalEnv, mode = "function", inherits = FALSE)) {
              message(sprintf("Declared entry point '%s()' not found after sourcing %s.",
                               stage$entry_fn, stage$script))
            }
          }
        }, type = "output")
        log_lines <<- c(log_lines, captured)
        TRUE
      },
      message = function(m) {
        add_line(paste0("[message] ", sub("\n$", "", conditionMessage(m))))
        invokeRestart("muffleMessage")
      },
      warning = function(w) {
        add_line(paste0("[warning] ", conditionMessage(w)))
        invokeRestart("muffleWarning")
      }
    )
  }, error = function(e) {
    error_msg <<- conditionMessage(e)
    add_line(paste0("[error] ", conditionMessage(e)))
    FALSE
  })

  elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))
  list(
    success = isTRUE(ok),
    output  = log_lines,
    error   = error_msg,
    elapsed = elapsed
  )
}

# ------------------------------------------------------------------------------------------
# UI
# ------------------------------------------------------------------------------------------
stage_ids    <- names(PIPELINE_STAGES)
stage_labels <- vapply(PIPELINE_STAGES, function(s) s$description, character(1))
stage_choices <- setNames(stage_ids, stage_labels)

ui <- fluidPage(
  useShinyjs(),
  titlePanel("WNBA Analytics -- Pipeline Control Panel"),
  helpText(
    "Pick one pipeline stage from pipeline_stages.R's registry and run it synchronously,",
    "in-process (Issue #46). The app blocks for the duration of the run -- there is no",
    "live log streaming in this slice; captured output appears once the run completes."
  ),
  sidebarLayout(
    sidebarPanel(
      width = 4,
      selectInput("stage_id", "Pipeline stage", choices = stage_choices),
      actionButton(
        "run_btn", "Run Stage", icon = icon("play"),
        class = "btn-primary",
        # Instant client-side feedback independent of the (about to block) server
        # round-trip -- see the header comment's EXECUTION MODEL note.
        onclick = "this.disabled = true; this.innerHTML = 'Running...';"
      ),
      br(), br(),
      uiOutput("status_ui")
    ),
    mainPanel(
      width = 8,
      h4("Captured Output"),
      verbatimTextOutput("output_log")
    )
  )
)

# ------------------------------------------------------------------------------------------
# Server
# ------------------------------------------------------------------------------------------
server <- function(input, output, session) {
  result <- reactiveVal(NULL)

  output$output_log <- renderText("(no stage has been run yet)")
  output$status_ui <- renderUI(tags$em("Idle."))

  observeEvent(input$run_btn, {
    stage <- PIPELINE_STAGES[[input$stage_id]]
    res <- run_pipeline_stage_captured(stage)
    result(res)

    # Re-enable the control + restore its label/icon now that the blocking run is over; this
    # message is flushed to the client together with the output/status renders below, i.e.
    # right when the result appears -- never leaving the button stuck disabled.
    shinyjs::html("run_btn", html = paste(as.character(icon("play")), "Run Stage"))
    shinyjs::enable("run_btn")
    shinyjs::enable("stage_id")
  })

  observeEvent(result(), {
    res <- result()
    if (is.null(res)) return()

    output$status_ui <- renderUI({
      if (isTRUE(res$success)) {
        tags$strong(style = "color: #1a7a1a;", sprintf("PASS (%.2fs)", res$elapsed))
      } else {
        err <- if (is.null(res$error)) "(no error message captured)" else res$error
        tagList(
          tags$strong(style = "color: #b30000;", sprintf("FAIL (%.2fs)", res$elapsed)),
          tags$div(err)
        )
      }
    })

    output$output_log <- renderText({
      if (length(res$output) == 0) "(no output captured)" else paste(res$output, collapse = "\n")
    })
  })
}

shinyApp(ui = ui, server = server)
