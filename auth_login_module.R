# ==============================================================================
# WNBA Analytics - Reusable Login/Signup Shiny Module (GitHub issue #53,
# Slice 3 of #44)
# Path: <project root>/auth_login_module.R
#
# Mountable `mod_login_ui(id)` / `mod_login_server(id)` pair that any Shiny app
# in this repo can use to gate its own UI behind a successful login, without
# reimplementing any auth logic -- all verification/account-creation goes
# through auth_utils.R's verify_user() / create_account_if_authorized().
#
# Per CLAUDE.md: constants are read from config.R (via auth_utils.R's own
# source()), never hardcoded; auth_utils.R itself is read-only from here.
#
# -----------------------------------------------------------------------------
# Session persistence decision (issue #53 explicitly flags this as an
# ambiguity the spec text doesn't disambiguate -- documenting the call here):
#
#   Same-tab PAGE REFRESH (F5) vs. a brand-new browser session/tab are treated
#   IDENTICALLY: both require a fresh login. This module stores "is logged
#   in" purely in a `shiny::reactiveVal()` scoped to the current Shiny
#   session's server-function closure (no cookie, no on-disk session table,
#   no browser localStorage). A page refresh tears down and re-runs the whole
#   `server` function from scratch server-side -- Shiny gives every browser
#   page-load a brand-new session/socket, full stop, regardless of whether
#   the browser tab is "the same tab" from the user's point of view. There is
#   deliberately no mechanism here that would make refresh behave any
#   differently from closing and reopening the browser: that's exactly what
#   "no remember me" is asked to mean. See mod_login_server() below for the
#   one-line echo of this decision at the actual reactiveVal() definition.
# -----------------------------------------------------------------------------
#
# Server-side-enforced gating contract (how a host app is expected to use
# this module -- see tools/demo_login_app.R for a worked example):
#   logged_in <- mod_login_server("login")
#   # `logged_in` is a reactive(TRUE/FALSE). The host app must gate its own
#   # protected render*()/output assignments behind `if (!isTRUE(logged_in()))
#   # return(NULL)` (or wrap the whole protected UI region in
#   # shiny::req(logged_in())) INSIDE each protected render*() call -- not
#   # just hide the corresponding UI with CSS/conditionalPanel alone. Shiny
#   # only evaluates a render*() body when something reads its reactive
#   # output; gating inside the body means the body's own side effects
#   # (including any detectable "I actually ran" probe) never execute pre-
#   # login, not merely that their output element stays invisible.
# ==============================================================================

if (!requireNamespace("shiny", quietly = TRUE)) {
  stop("Package 'shiny' is required by auth_login_module.R.")
}

# auth_utils.R sources config.R itself (guarded), and defines verify_user() /
# create_account_if_authorized(). Guard this source() too so repeatedly
# sourcing auth_login_module.R (e.g. from a throwaway demo app that also
# sources it directly) doesn't re-run auth_utils.R's own setup redundantly.
if (!exists("verify_user", mode = "function", inherits = TRUE)) {
  source("auth_utils.R")
}

# ------------------------------------------------------------------------------
# UI
# ------------------------------------------------------------------------------

#' Login/signup module UI.
#'
#' Renders a login form with a toggle link to a signup form (Slice 2,
#' create_account_if_authorized()). Both forms live in the same UI block;
#' client-side JS (shiny::tagList + conditional visibility driven by a
#' server-rendered uiOutput, see mod_login_server()) swaps which one is
#' visible. This is purely a display toggle for the *form chooser* itself --
#' it does NOT gate the host app's protected content, which is enforced
#' server-side via the `logged_in` reactive returned by mod_login_server().
#'
#' @param id module namespace id, passed to shiny::NS().
mod_login_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::div(
    id = ns("login_module_root"),
    style = "max-width: 360px; margin: 40px auto; padding: 24px; border: 1px solid #ccc; border-radius: 8px; font-family: sans-serif;",
    shiny::uiOutput(ns("form_ui"))
  )
}

# ------------------------------------------------------------------------------
# Server
# ------------------------------------------------------------------------------

#' Login/signup module server.
#'
#' @param id module namespace id, must match the corresponding mod_login_ui(id).
#' @return a `shiny::reactive()` of a single logical scalar: TRUE once this
#'   session has successfully logged in, FALSE until then. The host app reads
#'   this reactive inside each protected render*() body to gate it
#'   server-side (see the contract comment at the top of this file).
mod_login_server <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {

    # Session-scoped login state. A fresh reactiveVal(FALSE) is created every
    # time this module's enclosing server function runs -- which is every
    # new Shiny session, including a same-tab page refresh (see the
    # session-persistence decision comment at the top of this file). There
    # is no reading of any cookie/localStorage/on-disk table here, by design.
    logged_in <- shiny::reactiveVal(FALSE)

    # Which form is currently shown: "login" or "signup". Does not affect
    # `logged_in` at all -- purely a UI chooser.
    active_form <- shiny::reactiveVal("login")

    # Generic, case-indistinguishable failure messages. Deliberately the same
    # literal string regardless of whether the username didn't exist or the
    # password was wrong, mirroring verify_user()'s own no-enumeration
    # guarantee -- this module must not undo that guarantee at the UI layer.
    LOGIN_FAIL_MSG <- "Incorrect username or password."
    SIGNUP_FAIL_MSG <- "Unable to create account. Check your key phrase and try a different username."
    SIGNUP_SUCCESS_MSG <- "Account created. You can now log in with that username and password."

    login_error <- shiny::reactiveVal(NULL)
    signup_error <- shiny::reactiveVal(NULL)
    signup_success <- shiny::reactiveVal(NULL)

    # --------------------------------------------------------------------
    # Form-chooser toggle links
    # --------------------------------------------------------------------
    shiny::observeEvent(input$go_to_signup, {
      login_error(NULL)
      active_form("signup")
    })
    shiny::observeEvent(input$go_to_login, {
      signup_error(NULL)
      signup_success(NULL)
      active_form("login")
    })

    # --------------------------------------------------------------------
    # Login submit
    # --------------------------------------------------------------------
    shiny::observeEvent(input$login_submit, {
      username <- input$login_username
      password <- input$login_password

      ok <- tryCatch(
        isTRUE(verify_user(username, password)),
        error = function(e) FALSE
      )

      if (ok) {
        login_error(NULL)
        logged_in(TRUE)
      } else {
        # Same literal message on every failure path -- see LOGIN_FAIL_MSG
        # comment above. No branching on which case failed.
        login_error(LOGIN_FAIL_MSG)
      }
    })

    # --------------------------------------------------------------------
    # Signup submit
    # --------------------------------------------------------------------
    shiny::observeEvent(input$signup_submit, {
      username <- input$signup_username
      password <- input$signup_password
      key_phrase <- input$signup_key_phrase

      result <- tryCatch(
        create_account_if_authorized(username, password, key_phrase),
        error = function(e) FALSE
      )

      if (isTRUE(result)) {
        signup_error(NULL)
        signup_success(SIGNUP_SUCCESS_MSG)
        active_form("login")
      } else {
        signup_success(NULL)
        signup_error(SIGNUP_FAIL_MSG)
      }
    })

    # --------------------------------------------------------------------
    # Render whichever form is active. Rendered entirely server-side inside
    # uiOutput("form_ui") so the inactive form's inputs don't even exist in
    # the DOM (not just hidden), avoiding any stray client-side state.
    # --------------------------------------------------------------------
    output$form_ui <- shiny::renderUI({
      ns <- session$ns

      if (isTRUE(logged_in())) {
        # Once logged in, this module's own UI collapses to nothing -- the
        # host app is responsible for showing its protected content via the
        # `logged_in` reactive this function returns.
        return(shiny::tagList())
      }

      if (identical(active_form(), "signup")) {
        shiny::tagList(
          shiny::h3("Create account"),
          shiny::textInput(ns("signup_username"), "Username"),
          shiny::passwordInput(ns("signup_password"), "Password"),
          shiny::passwordInput(ns("signup_key_phrase"), "Key phrase"),
          shiny::actionButton(ns("signup_submit"), "Create account", class = "btn-primary"),
          if (!is.null(signup_error())) {
            shiny::div(style = "color: red; margin-top: 8px;", signup_error())
          },
          if (!is.null(signup_success())) {
            shiny::div(style = "color: green; margin-top: 8px;", signup_success())
          },
          shiny::br(),
          shiny::actionLink(ns("go_to_login"), "Already have an account? Log in")
        )
      } else {
        shiny::tagList(
          shiny::h3("Log in"),
          shiny::textInput(ns("login_username"), "Username"),
          shiny::passwordInput(ns("login_password"), "Password"),
          shiny::actionButton(ns("login_submit"), "Log in", class = "btn-primary"),
          if (!is.null(login_error())) {
            shiny::div(style = "color: red; margin-top: 8px;", login_error())
          },
          if (!is.null(signup_success())) {
            shiny::div(style = "color: green; margin-top: 8px;", signup_success())
          },
          shiny::br(),
          shiny::actionLink(ns("go_to_signup"), "Need an account? Sign up")
        )
      }
    })

    shiny::reactive(isTRUE(logged_in()))
  })
}
