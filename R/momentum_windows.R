# ==============================================================================
# R/momentum_windows.R - the one definition of the Momentum Board window sizes
#
# The board (build_momentum_dataset.R, MOMENTUM_WINDOWS) and its forward log
# (tools/log_momentum_forward.R, FORWARD_LOG_WINDOWS) both take their windows
# from this function, so the logger can never drift from the board.
#
#   Windows   5 and 10 most recent games, plus ROLLING_WINDOW_SIZE (config.R),
#             the original ROC-AUC window test (18 today).
#
# No defaults are filled in: a missing or invalid setting is an error.
# ==============================================================================

momentum_windows <- function(rolling_window_size) {
  if (missing(rolling_window_size) || length(rolling_window_size) != 1L ||
      !is.numeric(rolling_window_size) || !is.finite(rolling_window_size) ||
      rolling_window_size != round(rolling_window_size) || rolling_window_size < 1)
    stop("momentum_windows: ROLLING_WINDOW_SIZE must be one positive whole number.", call. = FALSE)
  c(5L, 10L, as.integer(rolling_window_size))
}
