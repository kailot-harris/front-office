# HANDOFF: NBA Analytics Visualization Suite & Cap-Data Sourcing

**Written:** November 12, 2026
**Latest commit on `main`:** `1f94a8a` (`Merge branch 'fix/clutch-chart-title-staleness'`)
**Uncommitted at time of writing:** `build_cba_cap_dataset.R`, `web/public/data/cba_cap_sheet.json` — see §2 "Not yet committed" before touching either.
**Audience:** Next engineer or autonomous subagent resuming work on the NBA Analytics visualization/data platform. Zero prior-session context assumed.

---

## 1. Project Overview & Boundaries

The **NBA Analytics** project (`C:\Users\kailo\kayceeslices\front-office\NBA Analytics`) is an automated quantitative analytics engine and Next.js static front-office web app (`/nba` route on `https://kailot-harris.github.io/front-office/nba/`). GitHub repo: `kailot-harris/NBA_analytics`.

### Authoritative architecture & references
1. **Pipeline execution:** `run_full_pipeline.R` (scheduled via `schedule_daily.bat`) — Elo, Four Factors, RAPM, shot charts, predictions, cap sheet, web sync.
2. **Aggregator root:** `C:\Users\kailo\kayceeslices\front-office\front-office-aggregator` embeds this repo as a git subtree under `nba/`. Any commit here must be subtree-pulled into the aggregator before it's live (see §4).
3. **Hard policy boundary — Zero-Betting Policy.** All public assets, docs, UI, and tests must exclude betting terminology (lines, spreads, over/under, moneylines, value bets). Projections are presented as win probabilities / score forecasts / power ratings only.
4. **Synthetic-data policy (active, repo-wide audit in progress — see §2's `synthetic-data`-labeled issues):** a fabricated-but-plausible value asserted as fact about a real person/team is treated as a defect, not a stylistic nit. The repo's own decision rule (settled on `kailot-harris/NFL_analytics#48`, not to be re-opened here): if a real source exists, derive from it and delete the fabricated draw; if no real source exists, **remove the field** rather than seed-and-label it synthetic. This is the lens this session's work (§2, §3) was conducted under.

---

## 2. Issue Tracking & Status

**Do not trust the previous version of this table** — it only covered issues #34-#59 (the original viz-suite build-out) and none of the synthetic-data-audit or cap-data work below. Cross-checked against live tracker state (`gh issue list --repo kailot-harris/NBA_analytics --state all`) as of this writing.

### This session's work

| Issue # | Status | Description | Evidence |
|---|---|---|---|
| **#75** | **OPEN — not yet closed, see flag below** | Confirm/refute: does `build_cba_cap_dataset.R` fabricate salaries? | Confirmed **yes** — the file's own code comments admitted `team_payrolls`/thresholds were "stylized round numbers," not sourced figures. Fixed this session (see "Not yet committed" below) but the fix is **uncommitted** and no closing comment has been posted to #75 yet. |
| **#97** | OPEN (new) | Cap-data automation Phase 1: verify Basketball-Reference reachability + table structure via `httr2`/`rvest` | Filed, not started |
| **#98** | OPEN (new) | Phase 2a: `tools/fetch_bbref_player_contracts.R` | Filed, not started. Depends on #97; parallel with #99 |
| **#99** | OPEN (new) | Phase 2b: `tools/fetch_bbref_salary_cap_history.R` | Filed, not started. Depends on #97; parallel with #98 |
| **#100** | OPEN (new) | Phase 3: derive team payroll totals from BBRef data, resolve the tax/apron source gap | Filed, not started. Depends on #98+#99 |
| **#101** | OPEN (new) | Phase 4: integrate automated BBRef sourcing into `build_cba_cap_dataset.R`, wire into `schedule_daily.bat` | Filed, not started. Depends on #100 |
| **#102** | OPEN (new) | Phase 5: end-to-end verification of the automated pipeline, close out #75 | Filed, not started. Depends on #101 |
| n/a — no issue filed | done, merged | `tools/gif_player_shot_chart.R` had no entry point; `generate_player_shot_chart_gif()` was defined but never called from anywhere | Commit `c69194e` on `main`. Regression against closed issues #39/#40 (never flagged as an issue of its own — see tracker-hygiene flag below) |
| n/a — no issue filed | done, merged | `tools/gif_clutch_shot_worm.R` always re-rendered the same hardcoded LAL-DEN game (`game_id == 401810829`) from a past season, and its rendered title carried a stale `"(Issue #58)"` string | Commit `2b5c866` on `main`. Regression against **closed** issue #58 |
| n/a — no issue filed | done, merged | `tools/gif_elo_delta_race.R`'s "week-over-week" animation snapshotted once per calendar date, not per week, so ~16-24 of 30 teams mechanically showed `+0.0` in most frames | Commit `c402325` on `main`. Regression against **closed** issue #52 |

**⚠ Tracker-hygiene flags (surfaced, not fixed — owner should decide):**
- Issues #39, #40, #52, #58 are marked **CLOSED** in the tracker but all four had real residual defects fixed in this session, with no issue ever reopened or filed to track the regression. Consider whether this repo's "closed" bar needs tightening, or whether these three ad-hoc fixes should get their own issue numbers filed retroactively for traceability.
- #75 is still open despite the fabrication it asks about being confirmed and (partially) fixed this session. See "Not yet committed" below — closing/commenting on #75 is appropriately gated on that work actually landing, and #102 (Phase 5) already carries an acceptance criterion to post the closing comment once the automation lands. Don't close #75 prematurely off the interim manual fix alone — it only resolves the symptom (one Spotrac snapshot), not the root cause (no repeatable sourcing), which #97-#102 address.

### Prior work (for context, abbreviated — see git log for full history)
Issues #1-#59 (original engine build-out + full 7-phase animated viz suite) and #69-#70 (UI header work) are closed and stable; not re-verified this session. Issues #76-#90 are a parallel, still-open synthetic-data audit thread (other builders: coaching, clutch, defense/DNA datasets) — **not touched this session**, listed here only so the next reader doesn't confuse them with #75/#97-#102.

---

## 3. What's Actually Implemented / Changed This Session

### Cap sheet data sourcing (`build_cba_cap_dataset.R`, 552 lines) — **UNCOMMITTED**
- `team_payrolls` tribble: replaced invented "stylized round numbers" with real "Total Cap Allocations" for all 30 teams, 2026-27/2027-28/2028-29, fetched live from Spotrac's cap tracker (`spotrac.com/nba/cap/_/year/{2026,2027,2028}`) via the Claude Browser pane on 2026-11-12 — **not** via a script, since Spotrac returns HTTP 403 (CloudFront bot-protection) to plain `curl`/`httr2`/`WebFetch` requests. This is a one-time manual snapshot; it will not refresh itself. See #97-#102 for the plan to make this unattended via Basketball-Reference instead.
- League-wide cap/tax/apron constants (`SALARY_CAP`, `LUXURY_TAX`, `FIRST_APRON`, `SECOND_APRON`) were already correct (matched the NBA's official July 2026 announcement) — untouched.
- `verified_contracts` (per-player breakdowns for ~20 marquee franchises): left as-is but now explicitly labeled **illustrative** (not individually re-verified against Spotrac) in both code comments and the exported `cbaThresholdSources` string, since re-verifying ~150 individual player salaries was out of scope for this fix.
- **Action needed:** this change (plus the regenerated `web/public/data/cba_cap_sheet.json`) is sitting uncommitted in the working tree. Commit it (and decide whether/how to comment on #75) before starting any of #97-#102, so Phase 4's eventual replacement of this same tribble doesn't conflict with uncommitted work.

### Three chart fixes (all committed and merged to `main`)
| File | Lines | What changed | Commit |
|---|---|---|---|
| `tools/gif_player_shot_chart.R` | 242 | Added a standalone entry point (`is_main` guard) that loads real cached shot data via `load_nba_shots_cache()`, picks the player with the most cached shots (≥30 threshold), renders GIF+PNG. Previously the file only defined a function nothing called. | `c69194e` |
| `tools/gif_clutch_shot_worm.R` | 363 | Replaced hardcoded `game_id == 401810829` / LAL-DEN with dynamic selection: scans the current season's pbp cache for 4th-quarter games with ≤8pt margin in the final 5 minutes, picks the most recent one with ≥8 tracked clutch shots. Dropped `"(Issue #58)"` from the rendered `plot_annotation()` title (still present in the file's header comment, which is fine — only the rendered title mattered). | `2b5c866` |
| `tools/gif_elo_delta_race.R` | 304 | Root cause: frames were snapshotted once per calendar game-date, but only ~10-14/30 teams play on a given night, so most teams showed `+0.0` in a frame that claimed to be "week-over-week." Fixed by binning dates into real 7-day calendar weeks (anchored to the first loaded game date) before each snapshot. Verified independently: flat-delta count dropped from 24/30 (old, mid-season date) to 0/30 (new, complete weeks). | `c402325` |

All three were built and verified via the **`subagent-brief` skill** (`C:\Users\kailo\.claude\skills\subagent-brief`) — each ran as an isolated subagent in its own git worktree under `front-office/.nba-worktrees/`, with a validated brief, independently re-verified by the coordinating session (not just taken on the subagent's word) before merging. Run log/evidence: `.subagent-runs/` in this repo (labels `shot-chart`, `clutch-chart`, `elo-chart` — `python <skill>/scripts/runlog.py labels` to list, `show --label <x>` for detail). Two out-of-scope side effects produced by the subagents' own test runs (a regenerated `gif_rapm_race` artifact and a resurrected `gif_rookie_impact_race` artifact — that chart was deliberately removed earlier for using simulated data, see commit `bf880bd`) were caught and stripped before merging; worth re-checking for the same pattern if `tests/test_batch_c_viz.R` is run again from a worktree.

### Cap-data automation plan (designed, not built)
A 5-phase plan to replace the uncommitted Spotrac manual-snapshot fix above with an unattended Basketball-Reference scrape, using the same `httr2`+`rvest` approach a sibling project already validated there. Filed as issues #97-#102 (see §2) with explicit dependency ordering: #97 (reachability/structure gate) → #98 ∥ #99 (parallel fetchers) → #100 (team-payroll derivation + tax/apron source gap) → #101 (integration) → #102 (verification, closes #75).

**Known gap this plan must carry forward:** Basketball-Reference's player-contracts page is **active-roster-salary only** (no dead cap, no cap holds) — it will not produce numbers matching Spotrac's "Total Cap Allocations" methodology team-for-team. #100 is scoped specifically to document and label this honestly rather than present it as a drop-in replacement.

---

## 4. Environment & Tooling Gotchas

1. **Spotrac blocks scripted requests.** `curl`, `httr2`, and the `WebFetch` tool all get blocked (403/402) by Spotrac's CloudFront bot-protection. The only way to read Spotrac data in this session was the Claude Browser pane (a real rendered browser session), which isn't something a cron job can invoke. Do not build automation that tries to defeat this (spoofing fingerprints to evade CloudFront) — that's bypassing anti-bot protection, not scraping a public page. This is *why* the cap-data plan (§3, #97-#102) targets Basketball-Reference instead.
2. **`cache/` is gitignored, and a git worktree does not get its parent checkout's cache files.** Several `tools/gif_*.R` scripts' `find_cache_file()` helper has a hardcoded absolute-path fallback (`C:/Users/kailo/kayceeslices/front-office/NBA Analytics/cache/<file>`) specifically because of this — when running from a worktree, the relative/local cache lookups miss and it falls through to that absolute path into the *main* checkout. This is pre-existing, not something introduced this session, but it means **worktree-isolated subagent work is implicitly reading real data from the main checkout**, not a self-contained copy. Don't "fix" this fallback away without checking every sibling script that relies on it.
3. **`subagent-brief` skill worktree hygiene:** running a batch-style test suite (e.g. `tests/test_batch_c_viz.R`) from inside a task-scoped worktree regenerates *all* batch scripts' output artifacts as a side effect, not just the one file in scope. Always `git status` the worktree before committing a subagent's work — strip anything outside the brief's declared scope (see §3's rapm_race/rookie_impact_race example).
4. **PowerShell quote/symbol escaping** (carried over from prior session): inline `&`, `%`, `$`, and double-quotes in `powershell -Command "..."` frequently fail. Write scratch `.R`/`.py` files and run them directly via `Rscript`/`python` instead of inlining long scripts.
5. **Aggregator subtree workflow** (carried over, unverified this session): commits here must be subtree-pulled into `front-office-aggregator` before they're live — see that repo's own handoff/docs for the exact command. Local `main` here is currently 5 commits ahead of `origin/main` and not yet pushed (plus 1 commit behind on an unrelated automated data-refresh commit — `6a55c90`, no conflict).

---

## 5. The Reusable Workflow (for delegated/parallel work in this repo)

This session's three chart fixes followed, and validates, this pattern — repeat it rather than improvising:
1. Diagnose the defect yourself first (read the actual source, don't delegate diagnosis blind) — this session's Elo-chart root-cause hypothesis was written into the brief *as a hypothesis to verify*, not a given, and the subagent was explicitly told to confirm or refute it against real cache data rather than take it on faith.
2. Write a `subagent-brief`-template brief (`full.md` template) naming exact files in/out of scope, concrete success criteria each with a `Verify:` command, and Tier 0-1 only (no Tier 2/3 needed for file-local R edits).
3. `git worktree add` a dedicated branch per task, dispatch via the `Agent` tool pointed at that worktree's absolute path (not via the skill's own `isolation: worktree` param, since the worktree was created manually ahead of time here).
4. **Independently re-run** whatever command the subagent cited as evidence yourself, from the same worktree, before trusting the result — this caught the rapm_race/rookie_impact_race side effect in the clutch-chart task, which the subagent's own report didn't flag as a problem.
5. Commit on the task's branch (subagents in this session left changes uncommitted — don't assume a "success" report means a commit exists), then `git merge --no-edit <branch>` into `main` from the primary checkout.
6. `git worktree remove` once merged, then `check_storage.py` to confirm nothing's accumulating unbounded.

---

## 6. Concrete Next Step

**Commit the uncommitted cap-sheet fix first** (`build_cba_cap_dataset.R` + `web/public/data/cba_cap_sheet.json`, currently sitting dirty in the main checkout — see §3) before touching anything else, so it isn't sitting exposed to being clobbered by #101's later rewrite of the same file. Decide at that point whether to also post an interim comment on #75 (confirmed-fabricated, partially fixed, full fix tracked at #97-#102) — #102 already carries the formal closing-comment criterion, but a note now would keep #75 accurate in the meantime.

**Then:** start #97 (Basketball-Reference reachability + structure verification) — it's the gate for #98/#99, which can run in parallel once it's done. See #97's issue body for the exact two URLs and what to check. One step further ahead: #98 and #99 are independent files and are the natural candidates for two parallel subagent-brief dispatches once #97 clears, following the workflow in §5.

Separately, unrelated to this thread but visible in the tracker: #76/#77/#80/#81/#82/#84/#85/#87/#88/#89/#90 are open issues from a parallel synthetic-data-audit effort across other builders (coaching, clutch, defense/DNA) — not part of this session's work, flagged here only so the next reader doesn't conflate them with the cap-data thread above.
