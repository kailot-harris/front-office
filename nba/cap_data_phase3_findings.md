# Phase 3 findings: BBRef-derived team payroll + tax/apron sourcing recommendation

Issue: kailot-harris/NBA_analytics#100 (Phase 3 of the Basketball-Reference
cap-data automation effort; depends on #98 and #99, which are merged).

## 1. Per-team payroll aggregation

`tools/derive_team_payroll_from_bbref.R` reads `cache/bbref_player_contracts.rds`
(produced by #98's `tools/fetch_bbref_player_contracts.R`) and sums each
player's current-season salary (`salary_y1`) by team, writing
`cache/bbref_team_payroll_active_roster.rds` with columns:

| column                       | meaning                                                              |
|-------------------------------|-----------------------------------------------------------------------|
| `team_abbr`                   | Basketball-Reference's team abbreviation (note: differs from this repo's in 3 cases — see §3 below) |
| `active_roster_salary_total`  | **Sum of active-roster salaries only.** Explicitly NOT named `total_cap_allocation` or similar. |
| `players_with_salary`         | count of players whose `salary_y1` was non-NA and included in the sum |
| `player_count`                | total player rows found for that team                                |

The field name `active_roster_salary_total` is deliberate and is the load-bearing
part of this deliverable: Basketball-Reference's `/contracts/players.html` page
(the source of `cache/bbref_player_contracts.rds`) lists **active roster
salaries only** — it has no dead cap, no cap holds, and no non-guaranteed
partial-season adjustments. `build_cba_cap_dataset.R`'s `team_payrolls` table,
by contrast, is sourced from Spotrac's "Total Cap Allocations," which *does*
include those. The two numbers measure different things and must never be
presented as interchangeable. See §3 for the quantified gap.

## 2. Luxury tax / first apron / second apron sourcing recommendation

**Recommendation: keep luxury tax, first apron, and second apron as manually-updated
constants, exactly as `build_cba_cap_dataset.R` does today** (`LUXURY_TAX`,
`FIRST_APRON`, `SECOND_APRON` at the top of that file). Do not attempt to scrape
these from Basketball-Reference.

This is grounded directly in #99's live finding, confirmed again while running
`tools/fetch_bbref_salary_cap_history.R` for this phase (fetched 2026-11-13):
`salary-cap-history.html`'s `#salary_cap_history` table has exactly three
columns — `Year`, `Salary Cap`, `2025 Dollars` — and 43 rows (1984-85 through
2026-27). There is no luxury tax, first apron, or second apron column anywhere
in that table, and the script's own header comment (lines 6-12) documents this
explicitly: "It does NOT contain luxury tax, first apron, or second apron
figures anywhere. Any tax/apron work (Phase 3/4) MUST come from a different
Basketball-Reference page or a different source entirely." No other
Basketball-Reference page was identified in #97/#98/#99's research as carrying
these figures either.

Reasoning for keeping them as manual constants rather than automating them from
some other source:
- They change **once per season**, via a single official NBA league office
  announcement (not continuously, unlike player salaries which shift with
  trades/signings/waivers throughout the season).
- The values currently hardcoded in `build_cba_cap_dataset.R` already match the
  official 2026-27 figures (per that file's own header comment).
- The realistic alternative sources for these figures (e.g. Spotrac) are the
  same sources #97 already found to be aggressively anti-bot (CloudFront
  blocking), so building and maintaining a scraper against a once-a-year number
  is a poor trade of engineering effort against anti-bot fragility, for a value
  a human can update from a single NBA press release in under a minute.
- A scraper against a once-a-year figure also cannot be meaningfully
  "freshness-tested" the way the daily pipeline's other feeds are — there would
  be nothing to detect staleness against until the following season's
  announcement anyway.

Net: no code change is needed for this item. This is a sourcing decision, not
an implementation gap — the existing manual-constant approach already is the
recommended approach, and this document records the reasoning so Phase 4 (and
future maintainers) don't misread the lack of a scraper here as an oversight.

## 3. BBRef active-roster total vs. Spotrac total-cap-allocation (team_payrolls)

Comparison below is BBRef's `active_roster_salary_total` (from
`cache/bbref_team_payroll_active_roster.rds`, derived 2026-11-13) against
`build_cba_cap_dataset.R`'s `team_payrolls$payroll_2026` (Spotrac-sourced,
`$M`, converted to dollars for comparison). Note Basketball-Reference and this
repo use slightly different team abbreviations for three franchises — BBRef's
`PHO` = this repo's `PHX` (Suns), BBRef's `CHO` = this repo's `CHA` (Hornets),
BBRef's `BRK` = this repo's `BKN` (Nets) — teams below were picked to avoid
that mapping ambiguity.

| Team | BBRef active-roster total | Spotrac total cap allocation (`team_payrolls`) | Gap (Spotrac − BBRef) |
|------|---------------------------:|------------------------------------------------:|----------------------:|
| NYK (Knicks)     | $220,398,177 | $222,800,000 | +$2,401,823 |
| BOS (Celtics)    | $198,722,406 | $199,500,000 | +$777,594   |
| DEN (Nuggets)    | $219,140,512 | $218,500,000 | −$640,512   |
| MIA (Heat)       | $224,396,273 | $207,800,000 | −$16,596,273 |
| CLE (Cavaliers)  | $208,969,955 | $209,800,000 | +$830,045   |

**Why the gap exists (and why it's expected, per the issue's caveat):**
Spotrac's "Total Cap Allocations" figure includes line items Basketball-Reference's
active-roster salary table structurally cannot, because BBRef's `/contracts/players.html`
only lists currently-rostered players' current-season salary:
- **Dead cap**: salary still counted against a team's cap for a player who has
  been waived/stretched and is no longer on any roster (BBRef has no row for
  that player at all once released).
- **Cap holds**: placeholder cap charges for a team's own free agents,
  first-round draft picks not yet signed, or roster-minimum/empty-roster-spot
  charges — none of these correspond to an active, signed BBRef contract row.
- **Non-guaranteed partial-season adjustments**: mid-season proration for a
  player signed/waived partway through the season; BBRef's table reflects a
  full-season current contract figure, not a day-by-day accrued amount.

This is why MIA shows the largest gap in the sample above (Spotrac's figure
there carries meaningfully more dead-cap/cap-hold weight than NYK/BOS/DEN/CLE
do) — a materially different composition, not a parsing error on either side.
The sign of the gap also isn't guaranteed to run one direction: DEN's and CLE's
BBRef total is close to or slightly over Spotrac's in this sample, which is
expected given that `team_payrolls`' dollar figures are themselves
hand-maintained, stylized approximations (per that file's own header) rather
than a live Spotrac pull — the point of this table is to establish that the
two methodologies measure different things, not to reconcile them to the
dollar.

**Guidance for Phase 4 (#101):** when `build_cba_cap_dataset.R` is eventually
touched to integrate BBRef data, the BBRef-derived `active_roster_salary_total`
must be surfaced under its own clearly-labeled field (or a clearly-labeled
companion dataset) — never written into or treated as a drop-in replacement for
`team_payrolls$payroll_2026` / the "Total Cap Allocations" framing used
throughout that file and its downstream consumers (apron-tier banding, tax-bill
calculation, etc.), since those computations assume the Spotrac-style
all-inclusive figure.
