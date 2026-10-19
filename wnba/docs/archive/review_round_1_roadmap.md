# Review Round 1 — Implementation Roadmap

Source: `docs/Review-Round-1.md` (pointer) → full report at
`C:\Users\kailo\AppData\Local\Temp\review-submission-wnba\report.md` (2026-09-24 pre-submission
review of `WNBA_Analysis_Project.Rmd`, `config.R`, `README.md`).

This is the actionable breakdown of that review's findings, one task per finding, roughly ordered
by the rubric's own weighting (reproducibility weighted heaviest per the user's explicit request,
then correctness, then everything else). Each item below has a corresponding GitHub issue (see
issue number in parentheses) in `kailot-harris/WNBA_analytics`.

## Tier 1 — Reproducibility (rubric's heaviest weight; currently "Not met")

1. Add a dependency-pinning manifest (`renv.lock`) covering `tidyverse`, `tidymodels`, `wehoop`,
   `slider`, `xgboost`, `ggridges`. (#1)
2. Replace `config.R:15`'s hardcoded absolute Windows `PROJECT_DIR` with a portable
   project-relative path (e.g. `here::here()`). (#2)
3. Add `set.seed()` to each of the three model-fitting chunks (window-size sweep, offseason
   comparison, model benchmark) so the chunk itself is reproducible, not just an external script.
   (#3)
4. Add a dedicated `set.seed()` immediately before the Monte Carlo `rbinom()` draw (`:578`) — the
   only existing seed (`:489`) is fully consumed by the earlier schedule-sampling loop. (#4)
5. Actually knit/render `WNBA_Analysis_Project.Rmd` end-to-end via `rmarkdown::render()` and
   replace every hand-pasted result table with the adjacent chunk's real output. (#5)
6. Expand `README.md` with real setup/dependency-install/run instructions, including the
   `PROJECT_DIR` edit and cache-file dependency a fresh grader would need. (#6)
7. Reconcile the two sources of truth for the window-size sweep: the Rmd recomputes it from
   scratch while `config.R:110-116` cites `data/window_sweep_3_25_results.csv` as "authoritative"
   — pick one and have the other load/verify against it. (#7)

## Tier 2 — Correctness bugs

8. Fix `mean_regress`/`decay` offseason-transition methods (`:144-157`) to blend all 11 rolling
   columns at season boundaries instead of 2-3, so the three-method comparison actually exercises
   the difference it claims to test. (#8)
9. Fix `team_profiles_current` (`:482-486`) to use each team's actual most recent game regardless
   of home/away, instead of only its most recent home game. (#9)
10. Fix the schedule generator (`:495-504`) to enforce an actually-balanced round-robin (or rename
    it if independent random sampling is intentionally kept). (#10)

## Tier 3 — Integration / internal consistency

11. Make every prose mention of `ROLLING_WINDOW_SIZE` (Intro `:26`, window-size section `:291-292`,
    Conclusion `:645-647`) derive from the live constant via inline `` `r` `` code instead of
    restating it as a stale literal in multiple places. (#11)
12. Add an explicit in-document caveat next to the offseason (`:348`) and benchmark (`:428`)
    "Actual result" tables noting they were produced at `window_size=13`, not the now-current 12 —
    mirroring `config.R`'s existing "STALENESS FLAG (FINDING L-2, 2026-09-16)" comment. (#12)
13. Update `README.md`'s one-line description to mention the season-simulation / win-total
    projection work, currently the Rmd's most elaborate output but unmentioned in the README. (#13)

## Tier 4 — Narrative

14. Rewrite the Introduction (`:12-21`) to state the research question in plain terms before
    referencing internal process artifacts ("T2", `task_assignments.md`, "the agent brief"). (#14)
15. Rewrite the Conclusion (`:634-656`) to synthesize substantive findings (winning window,
    method, model, standings) instead of being almost entirely about process/next-steps. (#15)
16. Soften the model-benchmark conclusion's confidence language (`:437-442`, "does transfer to
    WNBA") to match the noise-level caveat the document itself applies to a similarly-sized
    ROC-AUC gap elsewhere. (#16)
17. Remove the third-person "authoring agent" self-reference register (`:38-47`, `:645-650`) so
    the document reads as a report addressed to a grader, not an internal engineering audit
    trail. (#17)

## Tier 5 — Visualization

18. Add a stability/bias caveat to the feature-importance chart (`:457-465`), or switch from
    single-fit Gini-impurity importance to permutation importance via the `vip` package. (#18)
19. Add an in-plot text label (`annotate(geom = "text")`) to the ridge plot's dashed `.500`
    reference line (`:624`). (#19)
20. Add a line/point chart of the 23-row window-size sweep (`:250-283`) alongside the existing
    `kable` table, since the prose already describes shape-of-curve findings a table can't show
    at a glance. (#20)
21. Add a caveat near the Monte Carlo/standings sections (`:468-632`) that the underlying schedule
    is a synthetic random draw, not a real fixture list. (#21)

## Tier 6 — Code quality

22. Extract the near-identical `step_rm()` exclusion list / model spec / workflow / metric
    extraction duplicated across three chunks (`:223-232`, `:318-327`, `:377-386`) into one shared
    function. (#22)
23. Validate one-row-per-team-per-game cardinality before `inner_join(home_df, away_df, by =
    "game_id")` (`:182`) instead of assuming it. (#23)
24. Apply the same `team_id` integer coercion used in `team_lookup` (`:477-480`) at every other
    join site (`:523-525`, `:556-557`, `:597`). (#24)
25. Report the row count dropped by the unconditional `drop_na()` in `build_feature_df()`
    (`:199`). (#25)
26. Replace `sapply()` (`:585-588`) with `vapply()`/`purrr::map_dbl()` for a type-stable return.
    (#26)
27. Replace the base-R accumulator loop in the schedule-building code (`:495-504`) with
    `purrr::map_dfr()`/`list_rbind()`. (#27)

## Notes

- This roadmap covers the academic-submission Rmd review only — separate from
  `docs/future-work.md`, which tracks the pipeline/production-repo wishlist.
- Per the `review-submission` skill's academic-integrity constraint, the review itself contains no
  replacement code — these are task descriptions only; implementation is a separate step the user
  does (or explicitly delegates) themselves.
