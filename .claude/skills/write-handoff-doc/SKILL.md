---
name: write-handoff-doc
description: Regenerates docs/HANDOFF.md from scratch against current repo ground truth (git log, config.R, run_full_pipeline.R, cache/, docs/) for a future LLM/agent picking this repo up cold. Use after completing a meaningfully-complete unit of work (a shipped phase, a merged bug fix with real behavior change, a full session's worth of changes) or when explicitly asked for "a handoff doc" / "an updated handoff" / "summarize repo state for whoever's next." Not for logging routine, in-progress, or per-commit detail — that belongs in commit messages and docs/task_assignments_phaseN.md's Handoff Notes, not this file.
---

# Write Handoff Doc

## Why this exists

`docs/HANDOFF.md` is this repo's single canonical "read this first" entry point for a future
agent/LLM picking the project up cold — it existed before this skill did, built up phase by phase
across a long working session by repeatedly appending a new section after each shipped piece of
work. That worked, but it has a real failure mode: **accretion**. Each append is locally reasonable
(document what just happened) but nothing ever gets *consolidated* — numbers from three phases ago
sit next to numbers from five minutes ago with no re-verification that they're still both true, the
"Current state" pipeline table can silently drift out of sync with what `run_full_pipeline.R`
actually runs, and a cold reader has to wade through session-by-session narrative to find out what's
actually live in production right now. This skill's job is to fix that failure mode specifically:
**treat every invocation as a full rewrite against freshly-checked ground truth, not another
append** — the previous `docs/HANDOFF.md` is a source to mine for content, never a source to trust
verbatim.

This is also why this skill does not create dated/versioned handoff files
(`HANDOFF_2026-09-17.md`, `HANDOFF_v2.md`, etc.). A handoff doc's entire value is "the one place
that's unambiguously current" — two live copies means a future reader has to guess which one to
trust, which defeats the purpose. History is already tracked by `git log` and by each
`docs/task_assignments_phaseN.md`'s own append-only Handoff Notes section (see
`.claude/skills/remediation-phase-scaffold`) — this skill does not duplicate that, it points to it.

## When to use

- After shipping a phase of work, a significant bug fix, or reaching a natural stopping point in a
  long session — the same cadence the existing `docs/HANDOFF.md` was actually updated at across its
  history (roughly once per phase), not after every small edit.
- When the user explicitly asks for a handoff doc, an updated handoff, or "summarize state for
  whoever picks this up next."
- Not for: routine per-commit notes (that's what commit messages are for), or scaffolding a new
  multi-agent phase plan (that's `.claude/skills/remediation-phase-scaffold` — a phase-tracker doc
  and a handoff doc serve different readers: the phase tracker is for agents executing a specific,
  bounded plan; the handoff doc is for whoever arrives with zero context and needs the whole
  picture).

## Ground truth sources (check ALL of these before writing a single line — never write from memory of a prior handoff doc)

1. **`CLAUDE.md`** — read it fresh even if you read it earlier this session; it may have been
   updated. The handoff doc should never restate CLAUDE.md's content, only point to it (per this
   repo's own established convention — the existing doc's opening line is "read this before
   touching anything, then read CLAUDE.md for environment/data-quirk details this doc doesn't
   repeat").
2. **`git log --oneline -30`** (or further back if the handoff doc's "Build history" table needs
   extending) — the authoritative record of what shipped and in what order. Do not describe a
   change the doc doesn't have a corresponding commit for, and do not omit a shipped commit from
   the Build history table.
3. **`git status --short`** — flag anything uncommitted; the handoff doc should never imply a clean
   state that isn't real.
4. **`run_full_pipeline.R`** — grep its `run_stage(...)` calls directly to build/verify the
   "Current state" pipeline table. Do not trust the previous handoff doc's version of this table;
   stage scripts get added, reordered, or change what they write over a session.
5. **`config.R`** — every constant's current value AND its derivation comment. If the handoff doc
   cites a specific number (a Brier score, a derived weight), re-check it against `config.R`'s own
   comment or the `cache/*_derivation.rds`/`cache/model_comparison_backtest.rds` artifact it came
   from — never carry a number forward from the previous handoff doc without this check, numbers
   drift as constants get re-derived.
6. **`docs/` directory listing** — confirm every `task_assignments_phaseN.md`, plan doc (e.g.
   `NFL_REPLICATION_PLAN.md`, `memory_optimization_plan.md`), etc. that should be cross-referenced
   still exists at the path being cited, and that the phase-number sequence cited is current (this
   repo has a documented file-numbering-vs-content-phase-numbering offset from Phase 0 — see the
   existing doc's "File-numbering vs. content note" for the exact reason; preserve that note, don't
   silently drop it).
7. **`cache/` directory listing** — confirms which pipeline stages have actually produced real
   output, useful for sanity-checking claims about what's "live"/"deployed" vs. still
   harness-only/experimental.
8. **The previous `docs/HANDOFF.md`** — read last, as raw material and a checklist of topics that
   may still be relevant (Known Issues that weren't resolved, Suggested Next Steps that weren't
   done), never copied verbatim. Anything it says about "current production behavior" must be
   re-verified against the actual current source file, not trusted — source code is ground truth,
   a previous handoff doc's description of it is not (this is exactly the class of bug this repo's
   own model-quality work found once already: a previous description of what `market_odds_engine.R`
   consumed turned out to be stale relative to what the code actually did).

## Procedure

1. Gather all eight ground-truth sources above.
2. Write a fresh `docs/HANDOFF.md`, overwriting the previous one, using
   `templates/handoff_template.md`'s section skeleton. Do not add ad hoc top-level sections beyond
   that skeleton without a real reason — consistency across rewrites is part of what makes this
   useful to a cold reader who's seen the shape before.
3. For the "recent work" narrative sections: **compress, don't transcribe.** If a commit message
   already contains the full investigation narrative (this repo's commit messages are written at
   that level of detail deliberately), the handoff doc's job is a one-paragraph takeaway plus the
   commit hash, not a re-paste of the commit message. A future reader who needs the full story can
   run `git show <hash>`; the handoff doc is for orientation, not archaeology.
4. Every numbered "Known issues" / "Suggested next steps" item must be independently re-justified
   against current state, not copied forward — an issue from three rewrites ago may already be
   fixed (drop it, or move it to a brief "resolved since last handoff" note if the fix is worth a
   future reader knowing about specifically) or may have changed shape (rewrite it against what's
   actually true now).
5. Self-check before finishing:
   - Does the "Current state" pipeline table's stage count and script list match
     `run_full_pipeline.R`'s actual `run_stage()` calls, counted directly (not assumed)?
   - Does every file path mentioned in the doc actually exist (spot-check at least the ones central
     to the "recent work" sections)?
   - Does every cited number have a traceable source (a `config.R` comment, a commit hash, a
     `cache/*.rds` artifact) rather than being asserted bare?
   - Is `git status --short` clean, or does the doc explicitly note what's uncommitted and why?
6. Do not touch any other file in `docs/` — this skill owns `docs/HANDOFF.md` only.
   `task_assignments_phaseN.md` files, `NFL_REPLICATION_PLAN.md`, and topic-specific plan docs
   (e.g. `memory_optimization_plan.md`) are separate, independently-owned artifacts this doc
   points to, not content it absorbs.

## Section skeleton (see `templates/handoff_template.md` for the fillable version)

1. **Header** — last-updated date, most recent commit hash + one-line message, pointer to read
   `CLAUDE.md` next.
2. **What this repo is** — 2-3 sentences: origin/architecture lineage, remote URL, real-vs-synthetic
   data posture.
3. **Current state: N-stage pipeline** — table of stage # / script / exposed function / real
   output, built from `run_full_pipeline.R` directly.
4. **Build history** — commit hash / phase / one-line description table, from `git log`.
5. **Recent work** (one subsection per meaningfully distinct effort since the last full rewrite) —
   compressed per-effort: what changed, why, the one number/finding that matters, pointer to full
   detail (commit hash / doc / cache artifact). This is where most content differs rewrite to
   rewrite; everything above it is close to boilerplate.
6. **Known issues / unfinished business** — numbered, each with enough context to act on without
   re-deriving, re-justified against current state per step 4 above.
7. **Environment specifics** — R path, credential status, machine-specific quirks a fresh agent
   would otherwise waste time rediscovering.
8. **Suggested next steps** — priority-ordered, re-justified against current state.

## What this skill does not do

- Does not scaffold a new multi-agent phase plan (`.claude/skills/remediation-phase-scaffold`).
- Does not audit for constant drift (`.claude/skills/config-constant-drift-audit`) — though if
  writing the handoff doc surfaces a suspicious constant mismatch, flag it to the user rather than
  silently "fixing" the number in the handoff doc to match one side or the other.
- Does not verify a full pipeline run actually did something
  (`.claude/skills/pipeline-freshness-audit`) — if the handoff doc needs to claim "verified via a
  full pipeline run," that claim should already be backed by real evidence gathered separately, not
  asserted on faith while writing documentation.
