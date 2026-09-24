# Review Round 1 — Pointer to Pre-Submission Review of `WNBA_Analysis_Project.Rmd`

This file is a pointer, not the review itself. Per the `review-submission` skill's design, the
full report is deliberately kept outside this repo (it's a personal pre-submission check, not a
project artifact) — do not copy its contents into this repo; read it from its actual location:

**Full report:** `C:\Users\kailo\AppData\Local\Temp\review-submission-wnba\report.md`

## What it covers

A six-lens read-only review (code, prose, visualization, rubric-grading, integration/consistency,
reproducibility — with a blind cross-critique round) of `WNBA_Analysis_Project.Rmd`, `config.R`,
and `README.md`, graded against a generic data-analysis rubric weighted heavily toward
reproducibility (no instructor rubric was available for this assignment). Reviewed 2026-09-24.

## Headline findings (see the full report for line-level detail and resource pointers)

- **Reproducibility is the weakest dimension**: no dependency pin (`renv.lock`/`requirements.txt`),
  `config.R:15` hardcodes an absolute Windows `PROJECT_DIR`, the Monte Carlo `rbinom()` draw and all
  three model-fitting chunks are unseeded, and the Rmd's own status note admits it has never been
  knit end-to-end (every result table is pasted in from an out-of-band script run).
- **Unreconciled internal inconsistency**: the document declares `ROLLING_WINDOW_SIZE` updated from
  13→12 (`:291-292`), but the offseason-method and model-benchmark "actual result" tables right after
  it (`:348`, `:428`) are both explicitly captioned as run at `window_size=13`. `config.R:142-148`
  already has a "STALENESS FLAG" comment acknowledging this gap, but the Rmd itself never surfaces
  that caveat next to the affected tables.
- **Two real correctness bugs**: the `mean_regress`/`decay` offseason-transition methods only blend
  2-3 of 11 rolling columns at season boundaries (`:144-157`), muting the very comparison they're
  meant to test; and `team_profiles_current` (`:482-486`) is built only from each team's most recent
  *home* game, silently feeding a stale profile into the season simulation for any team whose actual
  last game was on the road.
- Narrative, visualization, and code-quality gaps of lower severity are cataloged in full in the
  report (e.g. `step_rm()` duplicated across three chunks, unlabeled ridge-plot reference line, an
  unbalanced "round-robin" schedule generator, jargon-heavy intro).

## Note for the next agent

This is a **review only** — per the skill's academic-integrity constraints, it contains no
replacement code or fixes, only pointers to learning resources. Read the full report before
drafting an implementation plan, and treat the reproducibility and correctness findings above as
the highest-priority items to address first, consistent with how the review itself weighted them.
