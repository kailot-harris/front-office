# Review Round 2 — Implementation Roadmap

Source: `docs/Review-Round-2.md` (pointer) → full report at
`C:\Users\kailo\AppData\Local\Temp\review-submission-scratch\review-submission\report.md`
(2026-09-25 pre-submission re-review of `WNBA_Analysis_Project.Rmd`, run via the
`review-submission` skill: six independent lenses — code, prose, visualization,
rubric-grading, integration/consistency, reproducibility — plus one blind cross-critique
round). No instructor rubric was supplied; graded against a generic data-analysis rubric.

This is the actionable breakdown of that review's findings, one task per finding, ordered
by severity (real bugs first, then reproducibility/integration gaps, then narrative,
visualization, and code quality). Unlike `docs/archive/review_round_1_roadmap.md`, no
GitHub issues have been filed for these yet — file one per item before starting work on
it, per `HANDOFF.md` §5's pattern.

## Tier 1 — Correctness bugs (highest confidence findings; independently confirmed by
   multiple reviewers reading the source directly)

1. Fix the no-cache fallback branch for box scores (`WNBA_Analysis_Project.Rmd:82-94`,
   specifically the else-branch at `:86-87`): it filters `team_abbreviation %in%
   names(WNBA_TEAMS)` without first calling `normalize_team_abbreviation()`, reintroducing
   the documented CONN→CON Connecticut Sun data-loss bug on any fresh checkout with no
   pre-existing cache — exactly the scenario a grader is likely to hit. The prose's claim
   that normalization is "already applied" doesn't hold for this branch.
2. Fix the `mean_regress`/`decay` "Method B" offseason-transition code (`:159-189`): it
   computes `mean(team_score, na.rm = TRUE)` (and equivalents for all `roll_*` stats)
   grouped only by `team_id`, over the *entire* column with no season-boundary cutoff —
   this both regresses toward each team's own long-run average rather than the "league
   average" the prose describes, and leaks future/current-season score data into a feature
   evaluated out-of-sample (look-ahead bias).

## Tier 2 — Reproducibility gaps

3. Seed each iteration of the `map_dfr()` sweeps (`:286-319, 394-417`) individually (e.g.
   via `withr::with_seed()`) instead of one `set.seed(42)` before the whole sweep, so
   individual sweep rows stay reproducible if the sweep's order or length changes later.
4. Add a staleness check (hash or date comparison) between `data/window_sweep_3_25_results.csv`
   and the current `box_scores_cache.rds` (`:314-319`), so a stale CSV isn't silently reused
   instead of recomputing `eval_window_size()`.
5. Tie the hand-pasted "Actual result" tables (`:334-339, 421-423, 497-499`) mechanically
   to their adjacent live chunk's own `kable()` output (e.g. via inline `` `r` `` expressions
   or a second `kable()` call reading the same variable), so a reader/grader can't get a
   pasted table that's silently drifted from what the live code actually produces.

## Tier 3 — Integration / narrative

6. Derive the Introduction's hardcoded row count ("3,906 real team-game rows",
   `:28`) from the live `nrow(box_scores)` value via an inline `` `r` `` expression instead
   of restating it as a static literal, matching how other data-dependent numbers in the
   document are already linked.
7. Move internal engineering bookkeeping (issue numbers like "#22/#23/#25/#26/#27", agent
   codenames like "T2/wnba_rating_engine_agent", references to `task_assignments.md`) out
   of the academic prose and code comments (`:29-33` and comments at `:214, 241, 252, 608,
   705`) — keep that context in `HANDOFF.md`/`task_assignments*.md`, not in a report a
   grader reads standalone.
8. Break up the long, em-dash-heavy chained sentences in the Introduction and results
   framing (`:15-23, 51-63, 365-373`) into shorter, single-idea sentences.
9. Tone down the defensive "A note on this document's provenance" paragraph (`:51-63`) to
   state the reproducibility method matter-of-factly rather than repeatedly rebutting an
   unstated accusation.

## Tier 4 — Visualization

10. Add `fig.cap` to every `ggplot` chunk (`:322-331, 539-548, 742-767`) so figures get
    numbered captions in the rendered output, matching how every table already does via
    `kable()`.
11. Switch the ridge plot's `fill = team_name` (`:742-767`) to a colorblind-safe discrete
    palette (e.g. `scale_fill_viridis_d()` or a qualitative `scale_fill_brewer()` palette)
    instead of ggplot2's default categorical hue palette.
12. Add an uncertainty representation (error bars/bands from resampling, e.g. via the
    tidymodels `tune` package's `autoplot()`/`collect_metrics()` workflow) to the
    window-size sweep chart (`:322-331`) instead of a single point estimate per window,
    since the adjacent prose already notes the top candidates differ by noise-level
    margins the chart alone doesn't show.

## Tier 5 — Code quality

13. Factor the duplicated ~20-line feature-computation block (eFG%/TOV%/FTR/TS% and the
    `roll_*` `slide_dbl()` columns, `:111-157`) — currently repeated verbatim between the
    "reset" and "mean_regress/decay" branches of `build_feature_df()` — into one shared
    helper called from both branches.
14. Add `vip` as a pinned dependency (`renv::install()` + `renv::snapshot()`) and switch
    the feature-importance chart (`:551-563`) to (or add alongside) permutation importance,
    resolving the Gini-impurity bias the document already flags but doesn't act on.

## Notes

- This roadmap covers the academic-submission Rmd re-review only — separate from
  `docs/future-work.md`, which tracks the pipeline/production-repo wishlist.
- Per the `review-submission` skill's academic-integrity constraint, the review itself
  contains no replacement code — these are task descriptions only; implementation is a
  separate step you do (or explicitly delegate) yourself.
- Round 1 (`docs/archive/review_round_1_roadmap.md`, 27 issues) is fully closed as of
  2026-09-25 and is not superseded by this list — this is a fresh pass over the document
  as it now stands, not a re-check of Round 1's items.
