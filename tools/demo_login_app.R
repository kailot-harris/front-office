# ==============================================================================
# tools/demo_login_app.R
# Throwaway standalone Shiny app used ONLY to demo/QA the reusable login
# module (auth_login_module.R, GitHub issue #53, Slice 3 of #44). NOT wired
# into control_panel_app.R -- that's issue #54. Not part of
# run_full_pipeline.R's DAG.
#
# Per CLAUDE.md's tools/ convention, this script setwd()s to the absolute
# project root before source()-ing siblings by bare filename, so it runs
# correctly regardless of invocation cwd.
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" -e "shiny::runApp('tools/demo_login_app.R', port = 7658)"
# or point shinytest2::AppDriver at this file directly (shinytest2 looks for
# a literal app.R by default, so a wrapper dir is used in the headless
# probe -- see tools/headless_login_module_probe.R).
#
# What this app demonstrates:
#  - mod_login_ui("auth") / mod_login_server("auth") gate a trivial
#    "protected" panel.
#  - The protected panel's own render logic increments a counter
#    (protected_render_count) ONLY when it actually executes. Pre-login,
#    output$protected_counter_probe must read "0" -- not just be invisible --
#    proving the protected render body never ran, not merely that it was
#    hidden via CSS.
# ==============================================================================

PROJECT_ROOT <- tryCatch(here::here(), error = function(e) NA_character_)
if (is.na(PROJECT_ROOT) || !file.exists(file.path(PROJECT_ROOT, "config.R"))) {
  this_file <- normalizePath(sub("^--file=", "", commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))]))
  PROJECT_ROOT <- dirname(dirname(this_file))
}
if (!is.na(PROJECT_ROOT) && nzchar(PROJECT_ROOT) && file.exists(file.path(PROJECT_ROOT, "config.R"))) {
  setwd(PROJECT_ROOT)
}

suppressMessages(library(shiny))

source("config.R")
source("auth_utils.R")
source("auth_login_module.R")

ui <- shiny::fluidPage(
  shiny::titlePanel("Login module demo (issue #53)"),
  mod_login_ui("auth"),
  shiny::hr(),
  # Protected region: always present as a mount point in the DOM, but its
  # CONTENTS are only ever populated server-side after a successful login --
  # see the server function below. This is the "wrapped app's UI" being
  # gated by the module.
  shiny::div(
    id = "protected_region",
    shiny::uiOutput("protected_ui")
  )
)

server <- function(input, output, session) {
  logged_in <- mod_login_server("auth")

  # Counts how many times the protected render body has actually executed.
  # This is the detectable side effect for success criterion 1: pre-login it
  # must stay 0 (the render body must never have run), not merely be hidden.
  protected_render_count <- shiny::reactiveVal(0)

  output$protected_ui <- shiny::renderUI({
    # Server-side gate: if not logged in, this returns NULL and nothing below
    # ever executes for this reactive flush -- the protected content's own
    # markup/outputs are genuinely absent from the DOM, not display:none.
    if (!isTRUE(logged_in())) {
      return(NULL)
    }

    protected_render_count(protected_render_count() + 1)

    shiny::tagList(
      shiny::h3("Secret dashboard"),
      shiny::p("You are logged in. This content was server-rendered only after a successful login."),
      shiny::textOutput("protected_counter_probe")
    )
  })

  # Always registered (so the headless probe can query it at any time), but
  # its VALUE only changes because of the gated increment above -- reading
  # "0" before login (or the element being entirely absent, since it's
  # nested inside protected_ui's NULL) is the proof the gated body never ran.
  output$protected_counter_probe <- shiny::renderText({
    as.character(protected_render_count())
  })
}

shiny::shinyApp(ui, server)
