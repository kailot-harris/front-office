---
name: config-constant-drift-audit
description: Audits the NFL Analytics repo for hardcoded numeric literals that duplicate or silently diverge from a config.R constant (e.g. an HCA constant, a margin-sigma constant). Use before merging any change that touches a modeling/structural constant, or when explicitly asked to check for "config drift", "hardcoded constants", or to re-verify a fix to a constant-transcription bug. Not for general code review.
---

# Config Constant Drift Audit

## Why this exists

This check was ported from the WNBA Analytics repo's identically-shaped bug: a modeling script
there set a structural constant (home-court-advantage) to a hardcoded literal at the point of use,
a few lines below a comment stating a different intended value. The wrong number was apparently an
unrelated constant mispasted into the wrong slot. It ran without error, produced plausible-looking
(if biased) output, and was only caught by inspecting live output for an implausible pattern — not
by any automated check. The lesson generalizes directly to this repo: any numeric literal near a
constant-like name that doesn't match `config.R`'s value for that name, or that contradicts a
nearby comment, is exactly the kind of silent, high-severity drift that won't surface as an error
and needs a mechanized check rather than relying on someone noticing biased live output.

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
   - Parses every top-level `NAME <- value` constant out of `config.R`, and auto-detects whatever
     naming prefix (if any) this repo's constants share — e.g. a common `NFL_` prefix — rather
     than assuming a specific sport's naming convention, so the script doesn't need editing again
     if it's ever ported to another repo.
   - Greps every other `*.R`/`*.r` file in the repo for numeric literals appearing within a few
     lines of an identifier that looks like a known constant name (case-insensitive substring
     match on the name with its detected prefix stripped, e.g. `hca`, `margin_sigma`,
     `injury_penalty`, `roster_max` — whatever this repo's actual constants are named).
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

This repo is a fresh scaffold (`config.R` and the modeling engines that will consume it are
Phase 1+ work) and has no established "known-clean" run of this audit yet — there is no equivalent
of the WNBA repo's post-fix `WNBA_HCA` baseline to compare against here. Once `config.R` and the
modeling scripts exist, expect the same general shape of result the WNBA repo settled into: **zero
HIGH-severity findings** against any live modeling constant, plus a nonzero number of low-severity
`review`-level candidates that are expected noise rather than a skill failure — the ±3-line
name-proximity window will catch unrelated numbers that happen to sit near a constant-like
identifier (divisors, weighting coefficients, timestamp literals), and any `tools/test_*.R` /
diagnostic-data scripts that intentionally reference both a buggy and a correct historical value
for regression-test purposes will also surface as `review`, not HIGH. The bar for "clean" is no
HIGH finding representing genuine live-code drift, not a literally empty findings list. Update this
section with this repo's own real baseline the first time a full clean run is done against a
populated `config.R`.

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
