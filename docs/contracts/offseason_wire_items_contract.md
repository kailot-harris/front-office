# Offseason Wire-Items Data Contract

**Artifact:** `cache/offseason_wire_items.json`
**Validator:** [`tools/offseason/wire_items_schema.R`](../../tools/offseason/wire_items_schema.R) — `validate_wire_items()`
**Offline sample:** [`data/fixtures/wire_items_sample.json`](../../data/fixtures/wire_items_sample.json)
**Status:** Normative. Issues #57 (producer), #58 (consumer) and #59 (freshness gate) build against this document.

> [!IMPORTANT]
> This document specifies an artifact and a validator only. It changes no pipeline behaviour. The producer (`ingest_all()`), the consumer (`build_offseason_monitor.R`) and the freshness helper are owned by #57, #58 and #59 respectively and are deliberately untouched here.

---

## 1. The Gap This Contract Closes

`build_offseason_monitor.R` advertises the DAG `Ingest -> Extract -> Reconcile -> CBT Sync -> Render -> Export JSON`. The first edge does not exist. The builder sources `extract_regex.R`, `reconcile_state.R` and `render_memo.R`, and never calls `ingest_all()`. Its only Step 2 input is a static test fixture (`build_offseason_monitor.R:132-143`, parsing `data/fixtures/official_wire_raw_samples.json`).

Symmetrically, `ingest_all()` (`tools/offseason/ingest_sources.R:396`) returns `raw_items` in memory and persists only `cache/ingestion_manifest.json` plus a raw archive snapshot under `cache/raw_ingest_archive/YYYYMMDD/`. It persists nothing the builder consumes.

> [!WARNING]
> **`data/fixtures/official_wire_raw_samples.json` is a benchmark fixture, not a production input.** It exists to assert known extraction tuples (`expected_tuples`) against `extract_regex_from_text()` in the test suite. Its misuse as the monitor's live Step 2 input is the root cause of this whole plan: the published memo is currently derived from a hand-curated 2026-10-29/30 sample rather than from the live wire, and no amount of correct ingestion changes that until a real artifact sits between the two stages. That artifact is `cache/offseason_wire_items.json`, specified below.

The two files share their **input** field names (`raw_text` / `date` / `source_url` / `team_id` / `transaction_id`) so that the consumer reads live items and benchmark fixtures through one code path. The benchmark's test-scaffolding keys — `id`, `_note`, `expected_tuples` — are **not** part of this contract and `validate_wire_items()` rejects them as unknown fields.

---

## 2. Artifact Shape

`cache/offseason_wire_items.json` is a **bare JSON array**, UTF-8, no BOM, one element per wire transaction. A bare array (rather than an envelope with metadata) is deliberate: it keeps the shape identical to the benchmark fixture, and run-level metadata already has a home in `cache/ingestion_manifest.json`, which is what the freshness gate consumes (§6).

```json
[
  {
    "transaction_id": 947273,
    "raw_text": "Athletics traded RHP Jareth Rayo to Boston Red Sox for LF Nate Eaton.",
    "date": "2026-10-29",
    "source_url": "https://statsapi.mlb.com/api/v1/transactions",
    "team_id": 111,
    "from_team_id": 133,
    "mlbam_id": 837078,
    "player_name": "Jareth Rayo",
    "type_code": "TR",
    "type_desc": "Trade",
    "roster_tier": "MAJOR_40_MAN"
  }
]
```

### Encoding

The upstream statsapi payload is UTF-8 and 26 of the 276 archived records carry an accented player name (`José Alvarado`, `Vidal Bruján`, `Jesús Broca`, …). Both sides must declare UTF-8 explicitly; the default Windows codepage mangles these names. Produce with `jsonlite::write_json(..., auto_unbox = TRUE, pretty = TRUE)` into a connection opened with `encoding = "UTF-8"`, and consume with `jsonlite::fromJSON(..., simplifyVector = FALSE, encoding = "UTF-8")`.

---

## 3. Field List

`Maps to` records the single justification for each field's existence: either a named argument of

```r
extract_regex_from_text(raw_text, baseline, as_of_date = "2026-10-31", source_url = NULL,
                        player_index = NULL, team_id = NULL, transaction_id = NULL)
```

(`tools/offseason/extract_regex.R:185`), or a specific documented gate/telemetry need. There are no speculative fields.

| Field | Type | Required | statsapi source / derivation | Maps to |
|:---|:---|:---:|:---|:---|
| `transaction_id` | integer | **yes** | `id` | `extract_regex_from_text(transaction_id=)` — also the dedup/idempotency key (§4) |
| `raw_text` | string | **yes** | `description`, verbatim | `extract_regex_from_text(raw_text=)` |
| `date` | string `YYYY-MM-DD` | **yes** | `date` | `extract_regex_from_text(as_of_date=)` |
| `source_url` | string (absolute http/https) | **yes** | constant `https://statsapi.mlb.com/api/v1/transactions` | `extract_regex_from_text(source_url=)`, i.e. `build_wire_source_url()`'s `default_url` fallback (§5) |
| `team_id` | integer | **yes** | `toTeam.id` | `extract_regex_from_text(team_id=)` |
| `from_team_id` | integer | no | `fromTeam.id` | Gate/telemetry: counterparty club on transfers. statsapi emits mirrored rows per club for the same trade `id`; this field is what makes the collapse in §4 auditable after the fact. Absent on free-agency declarations, assignments and retirements (29 of 276 archived records carry it). |
| `mlbam_id` | integer | no — see §7 | `person.id` | Gate/telemetry: player-resolution fallback and crosswalk key when the regex name match in `find_player_in_snippet()` misses; reported in the unresolved-player diagnostics. |
| `player_name` | string | no — see §7 | `person.fullName` | Gate/telemetry: names the subject in unresolved-player diagnostics, so a silent zero-delta extraction is attributable to a specific player. |
| `type_code` | string | **yes** | `typeCode` | Gate/telemetry: classification counts by type, and the audit trail for the `roster_tier` derivation in §8. Observed values: `DFA`, `SC`, `OUT`, `ASG`, `REL`, `TR`, `SFA`, `CLW`, `SE`, `DES`, `RET`. |
| `type_desc` | string | **yes** | `typeDesc` | Gate/telemetry: human-readable form of `type_code` in the ops memo and alert payloads. |
| `roster_tier` | enum `MAJOR_40_MAN` \| `MINOR_LEAGUE` | **yes** | Derived — see §8 | Gate/telemetry: the monitor's publish gate scopes confirmed changes to the 40-man population; minor-league churn (98 of the 274 distinct archived records under the derivation in §8) must be countable and excludable, not silently mixed in. |

### `description` -> `raw_text`

No transformation. statsapi's `description` is already natural-language prose of exactly the shape `extract_regex_from_text()` was built against — `"LHP José Alvarado elected free agency."`, `"Boston Red Sox traded SS Tsung-Che Cheng to Detroit Tigers for cash."`, `"San Francisco Giants sent RHP Jason Foley outright to Sacramento River Cats."` The regex patterns in `extract_regex.R` anchor on precisely these phrasings (`(?:declared|elected) free agency\.?$`, and so on). Copy `description` into `raw_text` byte-for-byte: no trimming, no case folding, no punctuation normalisation. Any cleanup belongs in the extractor's patterns, where the benchmark fixture can assert it.

---

## 4. Identity, Dedup and Ordering

* Exactly **one record per wire transaction**. `transaction_id` is unique across the artifact; `validate_wire_items()` enforces this.
* statsapi emits **mirrored rows for trades**: the same `id` appears once per club, with `fromTeam`/`toTeam` swapped. In the archive, `947461` and `947273` each appear twice (276 rows, 274 distinct ids). The producer must collapse them, keeping the **first occurrence in feed order**. That rule is stable and deterministic, and it costs nothing the extractor needs: `raw_text` is identical across mirrored rows and is the only field that carries trade direction, while `team_id` only seeds the `sourceUrl`, which is valid from either club's perspective.
* Records are emitted in feed order. Consumers must not depend on ordering beyond determinism for diffing.

---

## 5. `source_url` and How the Link Is Actually Derived

The record stores the **unresolved default**, not a pre-built link. `extract_regex_from_text()` calls

```r
build_wire_source_url(default_url, team_id = NULL, transaction_id = NULL, as_of_date = NULL)
```

(`extract_regex.R:167`) internally, which returns `…/transactions?teamId=<id>&transactionIds=<id>` when both ids are known, a team-and-date-scoped link when only `team_id` is known, and `default_url` otherwise. Because this contract requires both `team_id` and `transaction_id` on every record, every live item resolves to a transaction-specific link. Storing the bare endpoint in `source_url` and letting the extractor derive the rest keeps one URL-construction scheme in the codebase instead of two.

---

## 6. Freshness Gate — Declared Signature (#59)

Declared here, **not implemented here**. Do not create `tools/offseason/ingest_freshness.R` as part of this unit; #59 owns it.

```r
assert_ingest_freshness(manifest, now = Sys.time(), max_age_hours = 26, allow_stale = FALSE)
```

* `manifest` — the parsed `cache/ingestion_manifest.json` list, or the `manifest` element of `ingest_all()`'s return value. Its `ingest_timestamp` is already written as UTC ISO-8601 (`"%Y-%m-%dT%H:%M:%SZ"`, `ingest_sources.R:427`); parse it as UTC, not local time.
* `now` — injectable clock, so tests need no sleep and no system-time mutation.
* `allow_stale` — when `FALSE` (default), a `STALE` or `MISSING` verdict must `stop()`. When `TRUE`, the same verdict is returned without stopping, for `--allow-degraded` style runs.

Return shape — a list with exactly these elements:

| Element | Type | Meaning |
|:---|:---|:---|
| `status` | string | `"FRESH"` \| `"STALE"` \| `"MISSING"`. `MISSING` covers an absent manifest, an absent `ingest_timestamp`, or one that will not parse. |
| `age_hours` | numeric | Age in hours, `NA_real_` when `status == "MISSING"`. |
| `max_age_hours` | numeric | The threshold applied, echoed back so callers log the decision rather than re-deriving it. |
| `reason` | string | One human-readable sentence naming the status, the age and the threshold — suitable verbatim for a Discord ops alert. |

### Chosen threshold: `max_age_hours = 26`

Issue #66 converts this job from a **weekly Monday-09:00** cadence to a **daily 07:00** cadence (superseding #55's deferred cadence change). The threshold is set against the daily cadence, not the weekly one.

Under a daily 07:00 run, a healthy manifest is at most ~24 hours old at the moment immediately before the next run begins. 26 hours adds two hours of slack to absorb Task Scheduler start jitter and queued-on-wake starts after a missed window, in-run retry/backoff on the statsapi adapters, and the one-hour DST discontinuity. One missed daily run therefore trips the gate on the following morning, which is the intent.

The weekly-to-daily change is the whole point of stating the number: the equivalent weekly threshold would have been ~170 hours (168 + slack). Leaving anything near a week in place after #55 lands would let **six consecutive silent ingest failures** pass the gate while the monitor happily re-extracted a stale artifact and reported zero deltas as a quiet week.

---

## 7. `mlbam_id` Is Optional — Deviation From Issue #56

> [!CAUTION]
> Issue #56 lists `mlbam_id` among the **required** fields. **It cannot be required**, and this contract makes it optional.

Archived record `transaction_id: 947461` — `"Boston Red Sox traded SS Tsung-Che Cheng to Detroit Tigers for cash."`, `typeCode` `TR` — has **no `person` key at all** in its first (retained, per §4) feed occurrence, hence no person id and no person name. Requiring `mlbam_id` would make the producer either drop a real 40-man trade or fabricate an id.

The contract encodes statsapi's `person` optionality as a **co-requirement** on the pair:

* Neither `mlbam_id` nor `player_name` present -> **passes**. The upstream record carried no `person` object. Record `947461` is the live example.
* Both present -> **passes**.
* Exactly one present -> **fails** with `PERSON_INCOMPLETE`. A record that names a player must identify that player, and vice versa; a half-populated person is producer-side data loss, not an upstream gap.

Two further corrections to #56's text, both verified against `cache/raw_ingest_archive/20261031/`:

1. #56's quoted "verified live record" shows `person.nameSlug`. The archived records carry `person.link` (e.g. `/api/v1/people/553993`) and **no `nameSlug`**. This contract does not require, use, or carry `nameSlug`.
2. `fromTeam` is correctly described as optional and stays optional here as `from_team_id`.

Downstream consequence for #58: never dereference `mlbam_id` without a presence check. The regex extractor resolves players from `raw_text` by name, so an absent `mlbam_id` degrades telemetry, not extraction.

---

## 8. `roster_tier` Derivation

`roster_tier` has no direct source in the statsapi payload and must be derived. The derivation is **not new**: it is the existing `discriminate_roster_tier(tx_row, mlb_team_names, baseline_40_mlbam_ids)` in `tools/offseason/ingest_sources.R:339`, which already returns exactly `MAJOR_40_MAN` or `MINOR_LEAGUE`. This contract pins `roster_tier` to that function's output so the producer does not grow a second, divergent rule. Restated, in order — first match wins:

| # | Condition (on `description` lowercased, `typeDesc`, `toTeam.name`, `fromTeam.name`) | Result |
|:---:|:---|:---|
| 1 | `description` contains `outright`, or `typeDesc == "Outrighted"` | `MINOR_LEAGUE` |
| 2 | `description` contains `reserve list` (winter-league and international placements) | `MINOR_LEAGUE` |
| 3 | `description` contains `selected`, or `typeDesc == "Selected"` (contract selected onto the 40-man) | `MAJOR_40_MAN` |
| 4 | `toTeam.name` is present and is **not** one of the 30 clubs in `MLB_TEAMS_30$name` | `MINOR_LEAGUE` |
| 5 | `description` contains `assigned` / `typeDesc == "Assigned"` **and** `toTeam.name` is non-MLB | `MINOR_LEAGUE` |
| 6 | `description` contains `minor league` (minor-league free-agent signings) | `MINOR_LEAGUE` |
| 7 | `typeDesc == "Released"` or `description` contains `released`, **and** (origin non-MLB, or destination non-MLB, or the person id is not in the 40-man baseline) | `MINOR_LEAGUE` |
| — | **Fallback** | `MAJOR_40_MAN` |

**The fallback is explicit, not a guess.** Any type code not matched above — `DFA` and `SC` from an MLB club, `TR`, `CLW`, `DES` — is a major-league roster operation, and defaulting to `MAJOR_40_MAN` means an unrecognised or newly introduced `typeCode` surfaces in the monitor for human review rather than being silently excluded from the 40-man population. The cost of a wrong fallback in this direction is a reviewable row; in the other direction it is a missed roster move. Note the asymmetry this creates: `roster_tier == "MAJOR_40_MAN"` on an unfamiliar `type_code` means "not demonstrably minor league", so #58 should keep `type_code` visible wherever `roster_tier` is used for filtering.

Rule 7 is the only rule that needs state beyond the wire record itself: it consults the 40-man `mlbamId` set from `cache/league_state_baseline.json`. The producer must pass that baseline through; when it is unavailable the rule degrades to "released -> `MINOR_LEAGUE`", which is the conservative reading for a release not traceable to an MLB club.

Tier distribution across the 274 distinct archived records under this rule (with an empty 40-man baseline, i.e. rule 7's degraded reading): 176 `MAJOR_40_MAN`, 98 `MINOR_LEAGUE`.

---

## 9. Validator

`tools/offseason/wire_items_schema.R` exports:

```r
validate_wire_items(items,
                    require_unique_transaction_ids = TRUE,
                    allow_unknown_fields = FALSE)
```

It is **pure**: base R only, no network, no disk access, no `config.R` globals, no `httr`. It loads cleanly in a bare `Rscript --vanilla` session. Callers parse the JSON and hand it the resulting list (`jsonlite::fromJSON(path, simplifyVector = FALSE)`).

Returns a list with `pass` (logical), `n_records`, `n_errors`, `errors` (per-record, per-field structured diagnostics), `messages` (rendered strings) and `summary` (one line). Every diagnostic names the offending record by its `transaction_id`, falling back to its positional index when the id is itself missing or malformed, and names the offending field:

```
[record transaction_id=947273 (index 1)] field `roster_tier`: expected one of MAJOR_40_MAN | MINOR_LEAGUE, got 'AAA_TAXI_SQUAD'.
[record transaction_id=947273 (index 1)] field `date`: required field is present but NULL/empty.
```

Error codes: `ROOT_NULL`, `ROOT_NOT_LIST`, `ROOT_EMPTY`, `RECORD_NOT_OBJECT`, `REQUIRED_MISSING`, `UNKNOWN_FIELD`, `BAD_TYPE`, `BAD_FORMAT`, `BAD_ENUM`, `PERSON_INCOMPLETE`, `DUPLICATE_ID`.

An empty array is an **error**, not a vacuous pass: a zero-record artifact is indistinguishable from a silent ingest failure, and the quiet-week assertion must not be reachable that way.

### Both sides must call it

* **#57, producer:** validate the in-memory item list *before* persisting, and abort the ingest stage on failure. Do not emit an artifact that fails its own contract.
* **#58, consumer:** validate *after* parsing, and abort the extract stage on failure. This is the specific failure mode the seam exists to prevent — a schema drift that degrades into "zero deltas extracted", which the monitor would otherwise publish as a quiet week.

---

## 10. Offline Sample Fixture

`data/fixtures/wire_items_sample.json` — 15 records, already mapped into contract shape, drawn from `cache/raw_ingest_archive/20261031/mlb_transactions_catchup.json`. It is committed, network-free, and passes `validate_wire_items()`. Use it for #57's round-trip test, #58's consumer test, and #59's gate test.

Coverage:

| Requirement | Records |
|:---|:---|
| Trade carrying `fromTeam` | `947461` (no `person` — the §7 case), `947273` |
| Minor-league assignment | `947538` (`ASG` -> Gwinnett Stripers), `947492` (`ASG` -> Norfolk Tides) |
| Accented player name | `947428` `José Alvarado`, `947538`/`947536` `Vidal Bruján`, `947492` `Robinson Martínez`, `947473` `Wikelman González`, `947448` `Jesús Broca` |
| Both `roster_tier` values | 6 `MAJOR_40_MAN`, 9 `MINOR_LEAGUE` |
| Type-code spread | `TR`, `DFA`, `ASG`, `OUT`, `CLW`, `DES`, `SE`, `SFA`, `RET`, `SC`, `REL` |

**Date-window deviation.** Issue #56 asks for a sample from the live 2026-10-31 – 2026-11-06 window. The on-disk archive ends at **2026-10-31**, so the fixture spans **2026-10-29 to 2026-10-31** (11 / 3 / 1 records respectively). Requirement 5 of #56 is an offline, committed, network-free fixture; the exact calendar window is incidental, and fetching the later window would have meant live network access, which is out of scope for this unit. If a genuine Oct 31 – Nov 6 sample is wanted later, regenerate from a newer `cache/raw_ingest_archive/` snapshot — the mapping rules in §3, §4 and §8 are the whole recipe.
