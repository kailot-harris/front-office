---
name: deep-review-to-manuscript
description: Runs a structured deep review of the WNBA Analytics pipeline (via a fresh subagent following a fixed doc/code reading order) and drafts a peer-review-style Quarto manuscript from the findings. Use when asked for a comprehensive/deep review of the project intended to produce a written report, whitepaper, or manuscript-style document — not for small-scope code review of a single PR or file.
---

# Deep Review to Manuscript

## Why this exists

This is the exact workflow used to produce `docs/WNBA_Pipeline_Manuscript.qmd`: a fresh
general-purpose subagent read the codebase in a specific order (project conventions first, then
orchestration, then modeling code, then validation reports, then bug-history docs) and returned a
structured findings report, which was then shaped into a manuscript with a fixed academic
section skeleton. Doing this well depends on two things that are easy to skip under time
pressure: giving the review subagent a *reading order* (not just "go read the repo") so it builds
context in dependency order rather than randomly, and treating the subagent's report as raw
material to be organized into prose, not as prose to copy-paste directly.

## When to use

- "Do a deep review of the project and write it up" / "draft a manuscript describing the
  methodology" / similar requests for a comprehensive, structured writeup.
- Not for: reviewing a single file or PR (too much overhead — just read the file), or for
  requests that want a quick summary rather than a citable, structured document.

## Procedure

1. **Spawn one fresh subagent** (general-purpose, not a fork — this needs zero contamination
   from prior conversation framing so it reads the code cold) using the prompt template in
   `templates/review_subagent_prompt.md`. Fill in the specific scope if the user asked for
   something narrower than the whole pipeline (e.g. "just the modeling engines" or "just the
   security/data-integrity angle") — do not send the full-repo prompt for a narrow request; it
   wastes tokens and dilutes the report's focus.
2. Read `CLAUDE.md` yourself before writing the subagent prompt, if you haven't already this
   session — the reading order and known-quirks list in the template are derived from it, and it
   may have been updated since the template was last touched.
3. Wait for the subagent's structured report. Do not fabricate or predict its findings while
   waiting.
4. Draft the manuscript from `templates/manuscript_skeleton.qmd`, mapping the subagent's report
   sections onto the skeleton's sections (Data Sources, Pipeline Architecture, Methodology per
   component, Validation Results, Discovered Defects, Discussion of divergence from plan,
   Conclusion). Do not simply paste the subagent's report verbatim — it's organized for
   completeness, not for manuscript prose; rewrite for a reader, keep the specific numbers and
   file references.
5. Flag, in the manuscript's own text (not just in a side note to the user), any numeric claim
   that was taken from the subagent's report without independent re-derivation — e.g. "we report
   this as an external benchmark comparison; see docs/ML_BENCHMARK_REPORT.md for the underlying
   run." A manuscript that silently launders unverified numbers into confident prose is worse
   than one that is explicit about its provenance.
6. **Invoke `render-and-inspect-quarto`** on the finished `.qmd` before reporting it as done —
   this workflow's own output is exactly the kind of document that skill exists to catch defects
   in (this is literally how the "Invalid Date" bug was found the first time this workflow ran).
7. Tell the user where the file lives and what, if anything, still needs independent
   verification before the document should be treated as final.

## Cost note

A whole-repo review subagent run costs roughly 70k+ tokens and several minutes. For a narrower
ask, scope the subagent prompt down accordingly (e.g. name 2-3 specific scripts instead of the
full reading list) rather than always running the maximal version.
