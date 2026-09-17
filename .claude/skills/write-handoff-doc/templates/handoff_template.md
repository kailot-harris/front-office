# NFL Analytics — Handoff Document

**Last updated**: YYYY-MM-DD, after commit `<short-hash>` ("<commit one-line message>"). Written
for a future LLM/agent picking this repo back up cold — read this before touching anything, then
read `CLAUDE.md` for environment/data-quirk details this doc doesn't repeat.

## What this repo is

<2-3 sentences: architecture lineage (e.g. "a port of the WNBA Analytics repo's architecture"),
remote URL, real-vs-synthetic data posture (this repo's convention: call out explicitly if
anything still uses synthetic/fallback data, per CLAUDE.md's honesty discipline).>

**Read `docs/NFL_REPLICATION_PLAN.md` first** if you haven't — <one line on what it is and its
staleness posture, matching the existing doc's framing: "live-verified research foundation...
re-verify anything date-sensitive.">

## Current state: N-stage pipeline

<One sentence: does the pipeline run end-to-end against real live data, any known exceptions
(synthetic fallbacks), pointer to the exception list below if any.>

| # | Stage script | Exposed function | Real output |
|---|---|---|---|
<one row per run_stage() call in run_full_pipeline.R, in that order — grep it directly, don't
transcribe from memory or from the previous version of this table>

<Any cross-cutting pipeline convention worth restating briefly (e.g. the call_fn-only convention,
no auto-run guards, the C-2 staleness check) — keep to 1 short paragraph; full detail belongs in
run_full_pipeline.R's own header comment, this doc only orients.>

## Build history (chronological, one git commit per phase)

| Commit | Phase | What it added |
|---|---|---|
<from `git log --oneline`, oldest relevant to newest — extend/trim the range covered as this doc
gets rewritten over time; doesn't need to go back to the very first commit forever if that
history is no longer load-bearing for understanding current state>

<Any phase-file-numbering-vs-content-numbering offset note, if one still applies — check the
previous handoff doc for this exact note before dropping it silently.>

## Recent work

<One subsection per meaningfully distinct effort since the last full rewrite of this doc. Compress
— see SKILL.md's "compress, don't transcribe" instruction. Suggested shape per subsection:>

### <Effort name> (commit `<hash>`, YYYY-MM-DD)

<What changed, why, in 2-4 sentences. Then:>
- **Result**: <the one number/finding that matters, with its source (config.R comment / cache
  artifact / harness output) — never asserted bare>
- **Status**: <deployed to production / harness-only / documented-not-implemented / etc. — state
  explicitly, don't leave a reader to infer deployment status>
- **Full detail**: `git show <hash>`<, or a specific doc/cache path if the commit message alone
  isn't the full story>

## Known issues / unfinished business

<Numbered list. Each item re-justified against CURRENT state, not copied from the previous
handoff doc — confirm still true, still relevant, and still stated accurately before including
it. Enough context that a future agent can act without re-deriving background.>

## Environment specifics a fresh agent needs

<R interpreter path, confirmed-working vs. broken credentials, any machine-specific quirks that
would otherwise waste a fresh agent's time rediscovering (matching the existing doc's convention
of including a footgun like "inline Rscript -e segfaulted once, write to a temp file instead").>

## Suggested next steps, roughly in priority order

<Priority-ordered list, re-justified against current state — an item already done should be
struck through with a pointer to the commit that did it (matching this repo's existing convention
for a completed roadmap item), not silently deleted (a struck-through completed item is useful
signal that the roadmap is being tracked accurately).>
