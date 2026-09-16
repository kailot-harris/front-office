# Review subagent prompt template

Fill in [SCOPE] with either "the full pipeline" (default) or a narrower named subset of files if
the user's request was scoped down. Fill in [FOCUS] with any specific angle requested (e.g.
"data-integrity", "modeling methodology only", "security"); default to covering all of section 2
below if no specific focus was requested.

---

You are reviewing the codebase at "C:\Users\kailo\kayceeslices\WNBA Analytics" (a WNBA
sports-analytics/betting pipeline written mostly in R, some Python). Your job is to produce a
deep, accurate technical review of [SCOPE], thorough enough that another agent can use it to draft
a peer-review-style manuscript describing the methodology stage by stage. Focus area: [FOCUS].

Read CLAUDE.md at the project root first — it documents known data quirks, join gotchas, and
conventions that are load-bearing for correctness. Treat it as ground truth.

Then read, in this priority order:
1. docs/REPO_MAP.md and docs/WNBA_REPLICATION_PLAN.md — historical design references for the
   original NBA system and the initial port plan. CLAUDE.md says treat these as historical, NOT
   current ground truth — call out any places current code has diverged.
2. run_full_pipeline.R — the actual DAG/orchestration of stages.
3. config.R — every structural/modeling constant and how it's derived.
4. The core modeling scripts relevant to [SCOPE], in dependency order.
5. docs/ML_BENCHMARK_REPORT.md, docs/model_error_analysis_report.md,
   docs/SPEC_COMPLIANCE_REPORT.md, docs/PHASE0_VALIDATION_NOTES.md — measured
   performance/validation numbers and known gaps.
6. docs/SECURITY_TECHNICAL_REVIEW.md and docs/SECURITY_REMEDIATION_VERIFICATION.md — for a
   methods-integrity/data-governance angle if relevant to [FOCUS].
7. docs/task_assignments*.md Handoff Notes sections — skim for discrepancies between planned and
   actual implementation.
8. app.R — skim to understand what's user-facing vs. backend pipeline, if relevant to [SCOPE].

Do NOT modify any files. This is read-only research.

Produce a structured report (your only deliverable) covering:
- Architecture: ordered stages, what each does, inputs/outputs, how they're wired together.
- For each major modeling component in scope: the method actually implemented (read the code, not
  the plan docs), key assumptions, known limitations or validated performance if documented.
- Data sources and known data-quality issues/corrections applied.
- Validation/backtesting results actually reported anywhere — pull concrete numbers.
- Known gaps and remediated bugs of methodological significance — good material for a
  "threats to validity" discussion.
- Anything materially different between historical design docs and current implementation.

Organize with clear headers for easy extraction into manuscript sections. Include specific
file/line references where useful. Comprehensive coverage over brevity.
