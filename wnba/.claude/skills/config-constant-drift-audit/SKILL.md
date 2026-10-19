---
name: config-constant-drift-audit
description: Audits the WNBA Analytics repo for hardcoded numeric literals that duplicate or silently diverge from a config.R constant (e.g. WNBA_HCA, WNBA_MARGIN_SIGMA). Use before merging any change that touches a modeling/structural constant, or when explicitly asked to check for "config drift", "hardcoded constants", or to re-verify a fix like the HCA transcription bug. Not for general code review.
---

# Config Constant Drift Audit

## Why this exists

This repo suffered a real, high-severity bug (Finding C-1): `market_odds_engine.R` set its
home-court-advantage input to `11.6` at the point of use, three lines below a comment stating the
intended value of `2.40`. The wrong value was apparently the NBA source system's unrelated
margin-standard-deviation constant, mispasted into the HCA slot. It ran without error, produced
plausible-looking (if biased) output, and was only caught by inspecting live betting
recommendations for an implausible pattern (all picks on the home side, all pinned at the max
Kelly cap). This skill mechanizes the check that would have caught it immediately: any numeric
literal near a constant-like name that doesn't match `config.R`'s value for that name, or that
contradicts a nearby comment.

## When to use

- Before merging/committing any diff that touches a numeric parameter used in modeling logic
  (ratings, HCA, sigma, K-factor, thresholds, penalties).
- When explicitly asked to "audit for hardcoded constants" or "check for config drift".
- As a periodic health check independent of any specific change.

Do not use this as a general-purpose linter or code-quality pass — it is narrowly scoped to
`config.R` constant duplication/drift, not style or correctness in general.

## Procedure

1. Run `Rscript.exe scripts/audit_constants.R` from the project root (use the full path from
   CLAUDE.md: `C:\Program Files\R\R-4.5.2\bin\Rscript.exe`). This script:
   - Parses every top-level `NAME <- value` constant out of `config.R`.
   - Greps every other `*.R`/`*.r` file in the repo for numeric literals appearing within a few
     lines of an identifier that looks like a known constant name (case-insensitive substring
     match, e.g. `hca`, `margin_sigma`, `rotation_size`, `roster_max`).
   - Flags any site where the nearby literal does not match `config.R`'s current value for that
     constant.
   - Separately flags (as HIGH severity) any site where a comment directly attached to that line
     — a trailing comment on the same line, or the immediately preceding comment line — states
     one numeric value while the code uses a different one: the exact signature of the original
     HCA bug. This check is deliberately scoped to the adjacent line only, not a wider window;
     an earlier version of this script used a +/-3-line window for the comment check too, which
     produced a false HIGH severity on a numeric literal that merely sat a few lines below an
     unrelated comment (caught by this skill's own test suite — see Limitations below).
2. Review the findings table the script prints. For each finding, open the file at the reported
   line and determine:
   - Is this a genuine drift bug (fix: replace the literal with a reference to the `config.R`
     constant, or update `config.R` if the literal is actually the intended new value)?
   - Is this a false positive (an unrelated numeric literal that happens to sit near a
     similarly-named identifier, e.g. a loop bound)? Note it and move on — do not "fix" it.
3. Report a summary: number of genuine findings, number of false positives excluded and why, and
   the specific file:line + suggested fix for each genuine finding. Do not silently auto-fix
   modeling constants — a mismatch might mean `config.R` is stale rather than the call site being
   wrong; surface both possibilities and let the user decide which side to correct.

## Known-clean baseline

As of the fix for Finding C-1, `market_odds_engine.R`'s HCA usage reads `WNBA_HCA` from
`config.R` (value `2.40`) rather than a hardcoded `11.6`. A clean run of this skill against the
current `main` branch should report **zero HIGH-severity findings tied to `WNBA_HCA`** — but do
not expect a literally empty findings list. The run will still surface a batch of low-severity
`review`-level candidates (the ±3-line name-proximity window catches plenty of unrelated numbers
that happen to sit near a constant-like identifier — e.g. Elo divisors, weighting coefficients,
`POSIXct` epoch literals) and it will also flag a handful of `tools/test_phase4_*.R` /
`tools/generate_diagnostic_data.R` lines that intentionally reference `11.6` or `2.40` for
regression-test purposes. Triage these as expected noise, not as a skill failure — the bar for
"clean" is no HIGH finding representing a genuine live-code drift, not zero output. If it ever
reports a genuine HIGH finding on `WNBA_HCA` outside a test/diagnostic file, treat that as a
high-priority regression of exactly the original bug.

## Limitations to disclose in the report

- This is a heuristic, name-proximity-based grep, not a static analyzer with real scope/type
  awareness. It cannot prove the absence of drift, only surface likely candidates.
- A mispasted constant that does not collide with any known constant *name* (e.g. a wrong number
  with no nearby identifier match) will not be caught. Recommend the user also spot-check any
  modeling formula changed in the diff being reviewed, not just rely on this tool.
- The HIGH-severity comment check only looks at the same line and the immediately preceding
  comment line by design (see Procedure above) — a comment two or more lines above the flagged
  literal will not trigger HIGH, only `review`. This trades a little recall for a large reduction
  in false positives; if a real bug ever hides behind a comment that isn't adjacent, it will still
  surface as a `review`-level candidate, just not escalated automatically.
- `review`-level findings on `tools/test_*.R` files are expected and usually not actionable —
  those scripts often assert against both the buggy and correct historical values on purpose.
