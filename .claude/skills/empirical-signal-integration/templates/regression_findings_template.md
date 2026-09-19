# <Signal Name>: Does It Predict <Outcome>?

**Date:** <YYYY-MM-DD>
**Author:** research task, follow-up to <originating file/task>
**Status:** WIRED IN | NOT WIRED IN — see "Decision" below.

## Research question

State plainly what's being tested and why it might matter to a real, already-existing consumer
(pricing engine, rating formula, etc.) — not just "is this interesting" but "would it change a
number this repo already produces, and how".

## Data and join-key verification (done empirically, not assumed)

List every cache/data source combined, with real column names and real row counts. For each join
between two sources, report the ACTUAL measured overlap (e.g. "1,950 of 1,953 game_ids in common,
99.85%"), not an assumption that two similarly-named columns line up. If a known ID-namespace trap
applies (see CLAUDE.md / this skill's "Known pitfalls"), say so explicitly and show the check that
ruled it out or worked around it.

## Circularity/endogeneity check

State explicitly whether the candidate predictor is computed from the same event as the outcome
being predicted. If yes, describe the trailing/lagged construction used to make it a genuine
forward-looking test instead, and what rolling window / minimum-history threshold was used and why
(cite `config.R`'s `ROLLING_WINDOW_SIZE` if reused, or justify a different one). If this trap
doesn't apply here, say so and why (e.g. the predictor and outcome are structurally independent
already).

## Panel construction

- Grain (player-game, team-game, etc.), exact filters applied and their thresholds (e.g. minimum
  attempts/games per entity), and the resulting sample size (rows AND distinct entities).
- Any keyword/bucketing logic reused from an existing production file — state that it was reused
  verbatim (not reinvented) so this analysis's numbers agree with whatever's already shipped.

## Regression methodology and results

- State the fixed-effects approach (demeaning, and/or an explicit `factor(id)` cross-check —
  report both and confirm they agree to several decimal places).
- Report every model tried (not just the winner) with coefficient, SE, t, p, n, and R² where
  relevant. Include a robustness check (e.g. with/without a control variable) if one was run.
- If a corroborating or contradicting check was run (e.g. a cross-sectional comparison), report it
  and explain WHY it might legitimately disagree in sign (confounding) rather than treating any
  disagreement as a contradiction to explain away.
- For multiple candidate terms: report a collinearity check (correlation and/or VIF) between them.

## Decision

State the decision rule applied (p < 0.05 + sign-sensible, or an explicitly justified variant) and
the outcome for EACH candidate term independently. If nothing cleared the bar, say so plainly —
this section existing with a null result is the point, not a failure.

## What was wired in (omit this section entirely if the answer is "nothing")

- Exact constants/functions added, with their file locations.
- The exact formula they're composed into, and confirmation that no existing term/weight was
  modified — only added alongside.
- Clamp bounds (if any) with the REAL observed range of the adjustment across current data,
  demonstrating the clamp doesn't bind by design.
- Every call site updated, including any place the same formula is independently recomputed
  (check for this explicitly — it has caused a real bug in this repo before).

### Verification

Real command(s) run and their real output (not paraphrased) confirming the wired-in change works,
plus a spot-check table of real entities (players/teams) showing the adjustment moves in the
documented direction with plausible magnitudes.
