# Offseason Wire Items Contract Specification (Issue #159)

## 1. Overview and Context

The WNBA Offseason Monitor DAG tracks roster mutations, front office movements, free agency signings, waiver claims, trades, and contract designations between seasons. Historically, the monitor pipeline had an architectural boundary gap:
1. **Ingestion subsystem** (`tools/offseason/ingest_sources.R`) queried external endpoints (ESPN transactions, team releases, beat RSS/Atom feeds) but returned coarse aggregated counts (`items_found`, `bytes_captured`, adapter health metrics) rather than normalized transaction entities.
2. **Extraction subsystem** and Step 2 of `build_offseason_monitor.R` relied on a static frozen fixture (`data/fixtures/official_wire_raw_samples.json`) rather than reading structured data emitted from live ingestion.

Issue #159 establishes the canonical **Wire Items Contract**—a unified, schema-validated interface connecting Ingestion adapters (producers) with Extraction parsers and Monitor DAG steps (consumers).

```
+-------------------------------------------------------------------------------+
|                             INGESTION (Tier 1 Producer)                      |
|  - ESPN Transactions API (JSON)                                               |
|  - Team Releases RSS/Atom (XML)                                               |
|  - Beat Feeds RSS/Atom (XML)                                                  |
+-------------------------------------------------------------------------------+
                                       |
                                       v
                    [ Normalize to Wire Item Contract ]
                                       |
                                       v
+-------------------------------------------------------------------------------+
|                       CANONICAL WIRE ITEMS FIXTURE / HANDOFF                  |
|                   Schema: validate_wire_items() (Tier 0)                      |
|                   Format: JSON array of normalized objects                    |
+-------------------------------------------------------------------------------+
                                       |
                                       v
+-------------------------------------------------------------------------------+
|                             EXTRACTION (Tier 2 Consumer)                      |
|  - Multi-event sentence & clause splitting                                    |
|  - Regex & LLM candidate delta extraction                                     |
|  - Entity resolution & reconciliation                                         |
+-------------------------------------------------------------------------------+
```

---

## 2. Schema Specification

A normalized wire item represents a single ingested transaction notice, report, or feed item with all available publisher metadata preserved in standard form.

### 2.1 Canonical Fields

| Field Name | Type | Nullable | Required | Description | Example |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `item_id` | Character | No | Yes | Deterministic unique identifier for the wire item (e.g. source-prefixed hash or native UUID). | `"wire_espn_20261023_001"` |
| `source_family` | Character | No | Yes | Categorical classification of the ingestion source family. Allowed values: `league_wire`, `beat_feeds`, `team_releases`. | `"league_wire"` |
| `source_id` | Character | No | Yes | Specific adapter or feed identifier producing the item. Examples: `"espn"`, `"espn_wnba_beat"`, `"swish_appeal"`, `"the_next_hoops"`, `"winsidr"`, `"her_hoop_stats"`, `"wnba_com"`, or team code. | `"espn"` |
| `source_url` | Character | Yes | Yes | Link back to the canonical item, article, or source endpoint. Empty or `null` if unavailable. | `"https://www.espn.com/wnba/team/_/name/ind/indiana-fever"` |
| `observed_at` | Character | No | Yes | ISO 8601 UTC timestamp recording when the item was observed and ingested by the pipeline. Format: `YYYY-MM-DDTHH:MM:SSZ`. | `"2026-11-06T11:42:45Z"` |
| `event_date` | Character | No | Yes | ISO 8601 date or datetime of the event as reported by the source. Format: `YYYY-MM-DD` or `YYYY-MM-DDTHH:MM:SSZ`. | `"2026-10-23T07:00Z"` |
| `raw_text` | Character | No | Yes | Exact text of the transaction description, article title/summary, or report wire. Leading/trailing whitespace trimmed. Must not be empty. | `"Announced Kelly Krauskopf stepped down as president. Fired general manager Amber Cox"` |
| `team_abbr` | Character | Yes | Yes | Structural sibling field specifying the WNBA team abbreviation associated with this item, or `null`/`NA` if source lacks structured team metadata. | `"IND"` |

### 2.2 JSON Schema Representation

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "WireItem",
  "type": "object",
  "required": [
    "item_id",
    "source_family",
    "source_id",
    "observed_at",
    "event_date",
    "raw_text"
  ],
  "properties": {
    "item_id": {
      "type": "string",
      "minLength": 1,
      "description": "Unique identifier for the item"
    },
    "source_family": {
      "type": "string",
      "enum": ["league_wire", "beat_feeds", "team_releases"],
      "description": "Ingestion source family"
    },
    "source_id": {
      "type": "string",
      "minLength": 1,
      "description": "Source adapter or outlet identifier"
    },
    "source_url": {
      "type": ["string", "null"],
      "description": "Canonical URL for the item"
    },
    "observed_at": {
      "type": "string",
      "pattern": "^\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}(:\\d{2})?(Z|[+-]\\d{2}:?\\d{2})?$",
      "description": "ISO 8601 timestamp of ingestion observation"
    },
    "event_date": {
      "type": "string",
      "pattern": "^\\d{4}-\\d{2}-\\d{2}([T ]\\d{2}:\\d{2}(:\\d{2})?(Z|[+-]\\d{2}:?\\d{2})?)?$",
      "description": "ISO 8601 date or datetime reported by the publisher"
    },
    "raw_text": {
      "type": "string",
      "minLength": 1,
      "description": "Raw unparsed text of transaction description or feed headline"
    },
    "team_abbr": {
      "type": ["string", "null"],
      "pattern": "^[A-Z]{2,4}$",
      "description": "Structural sibling field for team abbreviation (e.g. IND, GS, MIN)"
    }
  },
  "additionalProperties": false
}
```

---

## 3. Architectural Decisions

### 3.1 Structural Sibling Field for `team_abbr`

**Decision:** `team_abbr` is treated as a first-class structural sibling field on the wire item, populated directly from structural metadata in the ingestion source payload, rather than parsed from the `raw_text`.

**Rationale & Source Disparities:**
1. **ESPN Transactions API:** The endpoint (`site.api.espn.com/apis/site/v2/sports/basketball/wnba/transactions`) emits structured JSON where each transaction entry includes a nested `team` object:
   ```json
   {
     "date": "2026-10-23T07:00Z",
     "description": "Announced Kelly Krauskopf stepped down as president. Fired general manager Amber Cox",
     "team": {
       "id": "5",
       "location": "Indiana",
       "name": "Fever",
       "abbreviation": "IND",
       "displayName": "Indiana Fever"
     }
   }
   ```
   In this payload, ESPN provides the authoritative team attribution (`IND`) structurally. The description text does *not* mention the word "Indiana" or "Fever". Attempting to parse `team_abbr` from `raw_text` would fail or require brittle heuristics. Preserving `team_abbr` as a structural sibling directly from `team.abbreviation` captures the true publisher attribution with zero extraction ambiguity.
2. **RSS / Atom Beat Feeds:** In contrast, beat feeds (`Swish Appeal`, `The Next Hoops`, `Winsidr`, etc.) emit standard syndication XML (`<item>` / `<entry>`) without structured team identifiers. For these sources, `team_abbr` is set to `null` (`NA_character_` in R).
3. **Downstream Consumption:** The extraction engine uses `team_abbr` as an authoritative hint when present, bypassing ambiguous team entity matching. When `team_abbr` is `null`, extraction falls back to full entity resolution on `raw_text`.

---

## 4. Multi-Event Splitting Strategy

**Decision:** Multi-event records (entries containing multiple distinct roster or personnel transactions within a single text string) MUST NOT be split during ingestion; they are split during downstream extraction.

**Rationale:**
1. **Source Payload Fidelity & Provenance:**
   Real-world league wire records frequently combine multiple operations into a single publisher bulletin. For example:
   - *"Signed C Aminata Gueye to a Rest-of-Season Hardship contract. Waived C Nadia Fingall."* (Golden State Valkyries, 2026-09-20)
   - *"Released F Saylor Poffenbarger. Signed G Shay Ciezki to a rest of season contract. Signed F Saylor Poffenbarger to a player development contract."* (Phoenix Mercury, 2026-09-18)
   - *"Announced Kelly Krauskopf stepped down as president. Fired general manager Amber Cox"* (Indiana Fever, 2026-10-23)
   If ingestion attempts to split these compound sentences, the 1:1 mapping between ingested wire items and raw publisher archives (`cache/raw_ingest_archive/`) is lost, complicating audit trails, idempotency hashes, and deduplication.
2. **Separation of Concerns:**
   Ingestion is responsible for HTTP capture, archival snapshots, format parsing (JSON/XML to normalized fields), and health gates. Decomposing compound clauses into atomic mutation deltas requires domain knowledge, entity dictionary matching, sentence segmentation, regex patterns, or LLM parsing. That logic belongs strictly in Tier 2 Extraction (`tools/offseason/extract_regex.R` and `tools/offseason/extract_llm.R`).
3. **Extraction Invariant:**
   Tier 2 extraction takes one `wire_item` and may emit zero, one, or multiple candidate deltas:
   ```
   1 wire_item (Aminata Gueye / Nadia Fingall)
       |
       +---> Candidate Delta 1: SIGNING (Gueye, Aminata -> GS)
       +---> Candidate Delta 2: WAIVER (Fingall, Nadia -> GS)
   ```
   Both deltas retain the originating `item_id` as their provenance parent.

---

## 5. Ingestion and Extraction Workflow

1. **Ingest Phase:**
   - Ingestion fetches raw payloads and writes archive snapshots to `cache/raw_ingest_archive/<date>/`.
   - Ingestion adapters map raw records to the canonical wire item schema.
   - All produced items are validated via `validate_wire_items()`.
   - Ingestion writes normalized items to `data/fixtures/wire_items_sample.json` (testing) or `cache/raw_ingest_archive/<date>/wire_items_normalized.json` (DAG runs).
2. **Extraction Phase:**
   - Consumer reads normalized wire items.
   - For each item, extraction evaluates whether `raw_text` contains multiple sentences or delimiters (`. `, `; `, `\n`).
   - Candidate deltas are extracted and linked to `item_id`.

---

## 6. Validation and Error Handling Policy

Validation is enforced by `tools/offseason/wire_items_schema.R:validate_wire_items()`. The validator operates under a **fail-closed** policy:
- Records missing `item_id`, `observed_at`, `event_date`, or `raw_text` are strictly invalid.
- Non-character or empty-string values for required fields fail validation.
- Invalid date or timestamp formats fail validation.
- Unrecognized `source_family` values fail validation.
- Callers may specify `stop_on_error = TRUE` to halt execution on invalid items or `detailed = TRUE` to inspect structured error lists.
