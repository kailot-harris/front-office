# ==============================================================================
# tools/viz_common.R
# Path: tools/viz_common.R
#
# Minimal "no data, don't fabricate" helper for NFL Analytics chart scripts,
# ported from the NBA Analytics pilot (kailot-harris/front-office#142,
# NBA Analytics/tools/viz_common.R). No NFL chart script currently has a
# missing-data fallback branch that fabricates values (verified by
# .github/scripts/check-chart-authenticity.R against the current tree), so
# this file deliberately holds only the marker + helper, not NBA's larger
# theme/palette/logo surface - those concerns are not duplicated here because
# NFL's chart scripts (tools/gif_*.R, tools/plot_*.R) already have their own
# per-script dark themes and use nflplotR for team identity.
#
# Any future tools/gif_*.R or tools/plot_*.R fallback branch guarded by
# file.exists()/is.null() that would otherwise substitute invented values
# (random draws, hand-typed tables, an unvalidated formula) must call
# viz_stop_no_data() instead. check-chart-authenticity.R statically flags a
# missing-data fallback branch that builds a literal/random data table
# without calling this helper.
# ==============================================================================

# stop() rather than quit(): a chart script may also be source()d by a
# pipeline stage, where quit() would end the whole session. Run through
# Rscript this is a non-zero exit; tests/test_chart_viz.R recognizes the
# marker and reports a skip rather than a failure.
VIZ_NO_DATA_MARKER <- "[SKIP-NO-DATA]"

viz_stop_no_data <- function(script, reason) {
  stop(sprintf("%s %s: %s Nothing was rendered.", VIZ_NO_DATA_MARKER, script, reason),
       call. = FALSE)
}
