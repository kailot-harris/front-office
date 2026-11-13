# ==============================================================================
# tools/viz_common.R
#
# Minimal "no data, don't fabricate" helper for MLB chart/GIF scripts, ported
# from the NBA pilot (kailot-harris/front-office#142).
#
# When a chart script's real input is unavailable, it must refuse to render
# rather than fall back to invented values (random draws, hand-typed tables,
# unvalidated formulas). Call viz_stop_no_data() from that fallback branch
# instead of constructing a substitute data table; the static check in
# .github/scripts/check-chart-authenticity.R recognizes this call as the
# compliant "no data" arm and does not flag it.
# ==============================================================================

# stop() rather than quit(): chart scripts are also source()d by pipeline
# stages, where quit() would end the whole session. Run through Rscript this
# is a non-zero exit, and tests/*-authenticity* / chart test harnesses can
# grep stdout/stderr for VIZ_NO_DATA_MARKER to report a skip rather than a
# failure.
VIZ_NO_DATA_MARKER <- "[SKIP-NO-DATA]"

viz_stop_no_data <- function(script, reason) {
  stop(sprintf("%s %s: %s Nothing was rendered.", VIZ_NO_DATA_MARKER, script, reason),
       call. = FALSE)
}
