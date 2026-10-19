---
name: orphaned-cache-audit
description: Audits every CACHE_* constant in config.R (plus known bare cache-path literals) for whether anything actually produces and consumes it, catching orphaned/dead/unused caches like features_cache.rds, which had a config.R constant and a health-probe check but zero producer for 3 remediation waves. Use before merging a change that adds/removes a CACHE_* constant or a saveRDS/readRDS call site, as a periodic health check, or when data_health_probe.R reports a cache missing and it's not obvious why.
---

# Orphaned Cache Audit

## Why this exists

`cache/features_cache.rds` had a `config.R` constant and a `tools/data_health_probe.R` existence
check since Phase 0, but nothing ever wrote it — `get_player_features()` was fully implemented and
never called. Three separate remediation waves flagged the resulting health-probe warning as
"pre-existing and unrelated" without tracing it that far (see `docs/HANDOFF.md`, 2026-09-17). This
skill mechanizes the check that would have caught it: for every declared cache path, is there a
real producer and a real consumer, not just a declaration and a health check.

## When to use

- Before merging a change that adds/removes a `CACHE_*` constant or a `saveRDS`/`readRDS` call site.
- As a periodic health check.
- When `tools/data_health_probe.R` reports a cache missing and the cause isn't immediately obvious.

## Procedure

1. Run `Rscript.exe scripts/audit_caches.R` from the project root (full path per CLAUDE.md:
   `C:\Program Files\R\R-4.5.2\bin\Rscript.exe`). It:
   - Parses every `config.R` constant whose value resolves under `cache/` or `data/`.
   - Also checks the known bare-literal exception documented in CLAUDE.md —
     `cache/projected_wnba_standings.rds` has no `config.R` constant at all, by design.
   - For each, greps the whole repo (`*.R`, `*.r`, `*.py`) for both the symbolic constant name AND
     its resolved literal path string, since real consumers/producers use either form.
   - Classifies each: `OK` (producer + consumer beyond `data_health_probe.R`'s own existence
     check), `ORPHANED` (consumer exists, no producer — the exact `features_cache.rds` shape),
     `DEAD` (producer exists, no consumer beyond the health probe), `UNUSED` (neither).
2. Review the findings table. For each `ORPHANED`/`DEAD`/`UNUSED` result, open the relevant
   file(s) and confirm by hand — the grep is name/literal matching, not a real call-graph, so
   confirm a hit is actually a `saveRDS`/`readRDS`/`write.csv`/`read.csv`/`file.exists` call site
   and not an unrelated comment or string.
3. For a genuine `ORPHANED` or `UNUSED` finding, do not silently wire something up — report it and
   let the user decide whether a producer is worth building (this is a discovery tool, not an
   auto-fix). For a genuine `DEAD` finding, note it as a candidate for removal or for finding a
   real consumer, same as `features_cache.rds`'s Tier 2 fix did.
4. Maintain the allowlist in `scripts/audit_caches.R` for legitimate exceptions (e.g. a
   diagnostic-only cache with no consumer by design). Any new allowlist entry must be justified in
   the script's own output, not silently excluded.
5. Print a one-line verdict: N caches OK, and the file:classification of every non-OK finding.

## Limitations to disclose

- Name/literal-string grep, not a real static call graph — cannot detect a producer/consumer
  reached only through indirection (e.g. a path built by string concatenation instead of the
  constant or a literal). Recommend a manual check of any script that looks like it *should*
  touch a flagged cache but didn't match.
- A cache written by a script that never actually runs (e.g. a dead pipeline stage) will still
  read as `OK` here if the code exists — this audit checks for a call site, not that the call site
  executes. Pair with `pipeline-freshness-audit` if execution, not just code presence, is in
  question.
