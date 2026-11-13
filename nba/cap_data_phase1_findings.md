# Cap-Data Phase 1 Findings — Basketball-Reference Reachability & Table Structure

Resolves GitHub issue #97 (gate for Phase 2, #98/#99). Research/documentation only —
no fetch/parse scripts were written for this issue.

Verified live from this repo's worktree (`.nba-worktrees/nov13-issue97`) on 2026-11-13,
using R 4.5.2 with `httr2` (desktop Chrome User-Agent string, 30s timeout). Raw HTML
dumps and the probe/parse scripts used to produce this doc were deleted after use —
this document is the record of what they found.

## 1. Reachability verdict

Both target URLs returned **HTTP 200** via live `httr2::req_perform()` calls made directly
from this environment (not assumed from the sibling project's result):

| URL | Status |
|---|---|
| `https://www.basketball-reference.com/contracts/players.html` | **200** |
| `https://www.basketball-reference.com/contracts/salary-cap-history.html` | **200** |

This confirms the sibling project's finding holds here too. Unlike Spotrac (which 403s
scripted `httr2`/`rvest` requests behind CloudFront bot-protection), Basketball-Reference
did not block this request.

## 2. `robots.txt` findings

Fetched live from `https://www.basketball-reference.com/robots.txt` (also 200).

- `User-agent: *` block does **not** disallow `/contracts/` — the path this project needs
  is not restricted.
- `User-agent: *` disallows: `/basketball/`, `/blazers/`, `/dump/`, `/fc/`, `/my/`, `/7103`,
  `/play-index/*.cgi?*`, `/play-index/plus/*.cgi?*`, `*/gamelog/`, `*/splits/`, `*/on-off/`,
  `*/lineups/`, `*/shooting/`, `/req/`, `/short/`, `/nocdn/` — none of these overlap with
  `/contracts/players.html` or `/contracts/salary-cap-history.html`.
- **`Crawl-delay: 3`** is specified for `User-agent: *`. Phase 2's fetch script should
  throttle requests to at least 3 seconds apart to respect this.
- Separately, `AhrefsBot` and `GPTBot` are fully disallowed (`Disallow: /`), and a handful
  of named bots (`SlySearch`, `GroundControl`, `Carmine`, `Skynet`, `HAL9000`, etc.) are
  also fully disallowed — irrelevant here since this project's requests will use a generic
  browser-style User-Agent, not one of those identifiers.
- **Verdict: no restrictions found on the paths this project needs; one directive to honor
  (`Crawl-delay: 3`).**

## 3. `#player-contracts` live structure (`contracts/players.html`)

- Table element `#player-contracts` is present and parses with `rvest::html_element()`.
- Total `<tr>` elements in the table: **509** (includes both data rows and repeating
  header rows).
- Repeating header rows (rows containing a `<th>` with text `Rk`) occur at positions
  2, 24, 46, 68, 90, 112, 134, 156, 178, 200, … — **24 header rows total**, recurring at a
  **fixed interval of 22 rows** (i.e. a header row every 22nd row, meaning 21 data rows
  between repeats, except the first header at row 2).
- Data (player) rows: **485** (509 total rows − 24 header rows). This is close to, but not
  identical to, the issue's stated expectation of "508 active NBA player rows" — treat that
  figure as approximate/stale; 485 is what this environment observed live today.
- Current column names (from `<th>` text in a header row):
  `Rk | Player | Tm | 2026-27 | 2027-28 | 2028-29 | 2029-30 | 2030-31 | 2031-32 | Guaranteed`
- Corresponding stable `data-stat` attribute names (from a data row, for parser use since
  the season-year column headers will shift year to year):
  `ranker | player | team_id | y1 | y2 | y3 | y4 | y5 | y6 | remain_gtd`

## 4. `salary-cap-history.html` table structure

- The table is wrapped in an HTML comment (`<!-- ... -->`) in the raw response, as expected.
  Of 69 total HTML comments in the page, exactly **1** contains a `<table>` element.
- After stripping the `<!--`/`-->` markers and re-parsing that fragment with `rvest`, the
  table's `id` attribute is **`salary_cap_history`**.
- Row count: **43** (one row per season, 1984-85 through the current/most recent season).
- Actual column list: **`Year | Salary Cap | 2025 Dollars`** — exactly 3 columns.
- **Explicit answer on luxury tax / first apron / second apron:** **No.** The table contains
  only the base salary cap (nominal, column "Salary Cap") and its inflation-adjusted
  equivalent (column "2025 Dollars"). There is no luxury tax threshold, first apron, or
  second apron figure anywhere in this table. This confirms the issue's expectation and
  directly scopes Phase 3: any luxury-tax/apron figures will have to come from a different
  source, not this table.

## Implications for Phase 2/3

- Basketball-Reference is reachable from this repo's environment via `httr2` with a
  standard browser User-Agent; no CloudFront-style block was encountered (unlike Spotrac).
- Phase 2's fetch script must respect `Crawl-delay: 3` from `robots.txt`.
- Phase 2's parser for `#player-contracts` should skip rows matching the repeating header
  pattern (every 22nd row, `<th>` text `Rk`) or, more robustly, select rows by `data-stat`
  presence rather than fixed offsets, since Basketball-Reference's HTML header-row placement
  has been known to shift across season snapshots. Column semantics: `y1`...`y6` map to
  the six displayed contract years (2026-27 through 2031-32 as of this writing), not a fixed
  calendar mapping — Phase 2 should resolve these dynamically from the header text rather
  than hardcoding years.
- Phase 3 (luxury tax / apron figures) cannot be sourced from `salary-cap-history.html` —
  that table is base-cap-only. A different Basketball-Reference page or source will be
  needed if those figures are still in scope.
