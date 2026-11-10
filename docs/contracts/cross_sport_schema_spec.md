# Cross-Sport Schema Specification & Harmonization Guide (Issue #95)

- **Issue:** #95 — Harmonize cross-sport JSON dictionary structures and naming conventions across analytics boards
- **Scope:** `mlb`, `nba`, `nfl`, `wnba`, and `front-office-aggregator`
- **Status:** Canonical Contract Specification (Draft / Stage 1)
- **Author:** Front Office Core Architecture & Inter-Sport Parity WG
- **Date:** 2026-11-10

---

## 1. Executive Summary & Context

Across the Front Office multi-sport analytics platform (MLB, NBA, NFL, WNBA), independent evolutionary cycles have led to subtle but consequential divergences in JSON serialization contracts. The **Inter-Sport Schema Linter** identified **3 fundamental structural divergences** and **5 cross-sport nomenclature drifts** across shared core analytics boards:

```
Shared Endpoint Families:
1. coaching    - Staff efficiency, play-calling, impact ratings, tenure
2. clutch      - High-leverage player metrics, shot/plate discipline, win-probability delta
3. defense     - Defensive rating, versatile positional metrics, EPA/play deterrence
4. cap_sheet   - CBA/CBT financial sheets, payroll commitments, apron thresholds
5. player_dna  - Player archetype clustering, statistical radar percentiles, similarity vectors
6. standings   - Projected regular season standings, win totals, conference/division ladders
```

This specification establishes the **canonical cross-sport contract** for shared JSON payloads. It defines:
1. **Canonical Field Nomenclature**: Consistent key identifiers eliminating naming ambiguity.
2. **Standardized Structural Envelope**: A deterministic root object structure separating execution metadata from domain entity payloads.
3. **Cross-Sport Field Crosswalks**: Concrete translation tables mapping existing sport exporters to canonical definitions across all 6 endpoint families.
4. **Resilient Migration Protocol**: Backward-compatible ingestion patterns enabling client frontends and R pipelines to migrate without service interruptions.

---

## 2. The 3 Structural Divergences & Unified Envelope Architecture

The Inter-Sport Schema Linter surfaced three primary structural inconsistencies in how payloads are serialized across sports:

```
+---------------------------------------------------------------------------------------------------+
| STRUCTURAL DIVERGENCE COMPARISON                                                                  |
+------------------------------------+--------------------------------------------------------------+
| Inconsistency                      | Manifestation Across Sport Repositories                      |
+------------------------------------+--------------------------------------------------------------+
| 1. Root Envelope vs Bare Array     | MLB & NFL wrap in root objects { data: [...], generated_at }; |
|                                    | NBA & WNBA emit bare JSON arrays [ {...}, {...} ].           |
+------------------------------------+--------------------------------------------------------------+
| 2. Metadata & Timestamp Placement  | NFL duplicates generated_at on every array row;              |
|                                    | NBA injects per-row provenance maps;                         |
|                                    | WNBA injects season into individual records.                 |
+------------------------------------+--------------------------------------------------------------+
| 3. Collection Strategy (Flat vs    | MLB bundles leader partitions (clutchLeaderBatters) next     |
|    Partitioned Catalogs)           | to raw profiles; NFL bundles team totals and player ranks;   |
|                                    | NBA/WNBA emit flat entity lists.                             |
+------------------------------------+--------------------------------------------------------------+
```

### 2.1 Canonical Structural Envelope

All shared endpoints must standardize on the **Level-1 Canonical Envelope**. Bare JSON arrays are deprecated.

```json
{
  "$schema": "https://front-office.kayceeslices.internal/schemas/v1/envelope.json",
  "schema_version": "1.0",
  "generated_at": "2026-11-10T06:00:00Z",
  "season": "2026",
  "sport": "wnba",
  "endpoint": "clutch",
  "metadata": {
    "sample_size": 221,
    "source_system": "WNBA_CLUTCH_ENGINE_V2",
    "git_commit": "ca3ea93",
    "parameters": {
      "leverage_index_threshold": 1.5,
      "min_minutes": 50
    },
    "partitions": {
      "leaders": []
    }
  },
  "data": [
    {
      "playerId": "1628932",
      "playerName": "A'ja Wilson",
      "teamAbbr": "LVA"
    }
  ]
}
```

### 2.2 Structural Envelope Field Rules

1. **`schema_version` (string, required):** Semantic schema version format (`"1.0"`).
2. **`generated_at` (string, ISO 8601 UTC, required):** Exact pipeline export timestamp (`"YYYY-MM-DDTHH:MM:SSZ"`). Row-level timestamp pollution is forbidden.
3. **`season` (string, required):** Season identifier (e.g. `"2026"` for MLB/NFL/WNBA, `"2026-2027"` for NBA). If an exporter generates an integer, loaders must coerce it to string.
4. **`sport` (string, enum, required):** Sport code in lowercase: `"mlb"`, `"nba"`, `"nfl"`, or `"wnba"`.
5. **`endpoint` (string, enum, required):** Endpoint family identifier: `"coaching"`, `"clutch"`, `"defense"`, `"cap_sheet"`, `"player_dna"`, or `"standings"`.
6. **`metadata` (object, required):** Execution metadata, global thresholds, partition indexes, and pipeline diagnostic tags. Domain rows must NOT store pipeline-level metadata.
7. **`data` (array of objects, required):** The canonical collection of domain entities. For endpoints with auxiliary partitions (e.g., MLB clutch leaders), the full population remains in `data`, while index references or leaders reside under `metadata.partitions`.

---

## 3. Canonical Field Nomenclature Guide (5 Core Drifts)

The Inter-Sport Schema Linter isolated **5 active nomenclature drifts** across repos:

```
+---------------------------------------------------------------------------------------------------------+
| CANONICAL NOMENCLATURE HARMONIZATION                                                                    |
+----+----------------------+-------------------+--------------------------+------------------------------+
| #  | Canonical Field Name | Legacy / Drifted  | Divergent Sport Usage    | Harmonization Resolution     |
+----+----------------------+-------------------+--------------------------+------------------------------+
| 1  | teamAbbr             | team, team_abbr   | NFL uses team;           | Standardize on teamAbbr for  |
|    |                      |                   | NBA/WNBA clutch uses team| 2-4 letter uppercase code    |
+----+----------------------+-------------------+--------------------------+------------------------------+
| 2  | headCoach            | head_coach        | NFL uses head_coach;     | Standardize on headCoach     |
|    |                      |                   | NBA/WNBA use headCoach   | (camelCase entity contract)  |
+----+----------------------+-------------------+--------------------------+------------------------------+
| 3  | win_pct              | win_pct_pyth,     | NFL uses win_pct_pyth;   | Standardize on win_pct as    |
|    |                      | Win_Pct, winPct   | WNBA RDS used Win_Pct    | 3-decimal proportion [0, 1]  |
+----+----------------------+-------------------+--------------------------+------------------------------+
| 4  | salaryCap            | hardSalaryCap,    | WNBA: hardSalaryCap;     | Standardize on salaryCap for |
|    |                      | baseThreshold,    | MLB: baseThreshold;      | primary team ceiling/limit;  |
|    |                      | cap_ceiling       | NFL: cap_ceiling         | sub-limits in extensions     |
+----+----------------------+-------------------+--------------------------+------------------------------+
| 5  | playerId             | player_id,        | Projections: player_id;  | Standardize on playerId for  |
|    |                      | (missing in NFL)  | NFL QB: no ID field      | all player entity records    |
+----+----------------------+-------------------+--------------------------+------------------------------+
```

### 3.1 `teamAbbr` vs `team`

- **Canonical Standard:** `teamAbbr`
- **Definition:** Uppercase 2-4 character franchise abbreviation (e.g., `"BOS"`, `"KC"`, `"NYL"`, `"LAD"`).
- **Secondary Standard:** `teamName` for full human-readable franchise name (e.g., `"Kansas City Chiefs"`, `"New York Liberty"`). `teamId` is reserved for integer IDs.
- **Migration Rule:** Web loaders must alias: `teamAbbr: row.teamAbbr ?? row.team ?? row.team_abbr`.

### 3.2 `headCoach` vs `head_coach`

- **Canonical Standard:** `headCoach`
- **Definition:** Full string name of the head coach or manager.
- **Secondary Standard:** Assistant coaches or coordinators must use camelCase: `offensiveCoordinator`, `defensiveCoordinator`, `benchCoach`, `pitchingCoach`.
- **Migration Rule:** Web loaders must alias: `headCoach: row.headCoach ?? row.head_coach`.

### 3.3 `win_pct` Variants

- **Canonical Standard:** `win_pct`
- **Definition:** Normalized numeric decimal float between `0.000` and `1.000` representing projected or actual win percentage (e.g., `0.625`, not `"62.5%"` or `62.5`).
- **Derived / Model-Specific Variants:**
  - Pythagorean expectation must be explicitly named `win_pct_pythagorean`.
  - Machine learning / ensemble model variants must use nested attributes or explicit prefixes (e.g., `win_pct_rapm`, `win_pct_sim`).
- **Migration Rule:** Web loaders must alias: `win_pct: Number(row.win_pct ?? row.win_pct_pyth ?? row.winPct ?? row.Win_Pct ?? 0)`.

### 3.4 `salaryCap` Variants

- **Canonical Standard:** `salaryCap`
- **Definition:** The primary official league spending threshold or ceiling expressed in Millions of USD (float or integer, e.g., `165.0` for NBA, `7.0` for WNBA, `244.0` for MLB CBT base threshold, `301.2` for NFL).
- **Sport-Specific Financial Extensions:**
  - Hard cap flags: `isHardCap: boolean` (true for NFL, WNBA; false for NBA soft cap, MLB CBT).
  - Secondary thresholds reside in domain-specific extensions:
    - NBA: `luxuryTaxThreshold`, `firstApron`, `secondApron`.
    - MLB: `cbtBaseThreshold`, `tier1Threshold`, `tier2Threshold`, `tier3Threshold`.
    - WNBA: `capFloor`, `supermaxSalary`, `vetMaxSalary`, `rookieMinSalary`.
    - NFL: `cashSpending`, `deadMoney`, `capSpace`.
- **Migration Rule:** Web loaders must alias: `salaryCap: row.salaryCap ?? row.hardSalaryCap ?? row.baseThreshold ?? row.cap_ceiling`.

### 3.5 `playerId` vs `player_id`

- **Canonical Standard:** `playerId`
- **Definition:** Primary unique string identifier for a player within the sport domain (e.g. ESPN ID, MLBAM ID, NBA Stats ID, or persistent internal UUID).
- **Companion Field:** `playerName` (string, full display name).
- **Migration Rule:** Web loaders must alias: `playerId: String(row.playerId ?? row.player_id ?? row.id ?? "")`. Exporters for sports without explicit IDs (such as NFL QB profiles) must generate deterministic slug IDs based on name and position (e.g., `"patrick-mahomes-qb"`).

---

## 4. Contract Specifications for the 6 Shared Endpoint Families

---

### 4.1 Endpoint Family 1: `coaching`

#### Scope & Files
- **NBA:** `web/public/data/coaching_metrics.json`
- **WNBA:** `web/public/data/coaching_metrics.json`
- **NFL:** `web/public/data/coaching_profiles.json`
- **MLB:** `web/public/data/coaching_metrics.json` (Manager & bullpen decision profiles)

#### Canonical Schema (TypeScript / Zod)
```typescript
export const CanonicalCoachingMetricSchema = z.object({
  teamAbbr: z.string().min(2).max(4),
  teamName: z.string().min(2),
  headCoach: z.string().min(2),
  tenureYears: z.number().nonnegative(),
  coordinators: z.object({
    offensive: z.string().optional(),
    defensive: z.string().optional(),
    bench: z.string().optional()
  }).optional(),
  metrics: z.object({
    coachImpactRating: z.number().min(0).max(100),
    coachingWinsAdded: z.number(),
    timeoutGrade: z.enum(['A+', 'A', 'A-', 'B+', 'B', 'B-', 'C+', 'C', 'C-', 'D', 'F']).optional(),
    fourthDownAggressionIndex: z.number().optional(),
    passRateOverExpected: z.number().optional()
  }),
  radarPercentiles: z.record(z.string(), z.number().min(0).max(100)).optional()
});
```

#### Field Crosswalk Matrix
| Canonical Field | Type | Description | NBA Current | WNBA Current | NFL Current | MLB Current |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `teamAbbr` | string | 2-4 char team code | `teamAbbr` | `teamAbbr` | `team` | `teamAbbr` |
| `teamName` | string | Full franchise name | `teamName` | `teamName` | *(derived)* | `teamName` |
| `headCoach` | string | Head Coach / Manager | `headCoach` | `headCoach` | `head_coach` | `manager` |
| `tenureYears`| number | Years with team | `metrics.tenure` | `metrics.tenure`| `tenure_years` | `tenureYears` |
| `coachingWinsAdded` | number | Wins added by staff | `coachingWinsAdded`| `coachingWinsAdded`| *(derived)* | `winsAdded` |
| `radarPercentiles` | object | Stat percentile map | `radarPercentiles`| `radarPercentiles`| *(derived)* | `radarPercentiles`|

---

### 4.2 Endpoint Family 2: `clutch`

#### Scope & Files
- **NBA:** `web/public/data/clutch_leverage_metrics.json`
- **WNBA:** `web/public/data/clutch_leverage_metrics.json`
- **MLB:** `web/public/data/clutch_leverage_metrics.json`
- **NFL:** `web/public/data/clutch_leverage_metrics.json`

#### Canonical Schema (TypeScript / Zod)
```typescript
export const CanonicalClutchProfileSchema = z.object({
  playerId: z.string().min(1),
  playerName: z.string().min(2),
  teamAbbr: z.string().min(2).max(4),
  position: z.string().min(1),
  clutchArchetype: z.string().min(2),
  leverageRating: z.number().min(0).max(100),
  clutchEfficiency: z.number(),
  winProbabilityAdded: z.number(),
  highLeverageVolume: z.number().nonnegative(),
  stats: z.record(z.string(), z.union([z.number(), z.string()])).optional()
});
```

#### Field Crosswalk Matrix
| Canonical Field | Type | Description | NBA Current | WNBA Current | MLB Current | NFL Equivalent |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `playerId` | string | Unique player ID | `playerId` | `playerId` | `playerId` | `player_id` |
| `playerName` | string | Full player name | `playerName` | `playerName` | `playerName` | `player_name` |
| `teamAbbr` | string | Team abbreviation | `team` | `team` | `teamAbbr` | `team` |
| `position` | string | Primary position | `position` | `position` | `position` | `position` |
| `clutchArchetype` | string | Behavioral category | `clutchArchetype` | `clutchArchetype` | `clutchArchetype` | `archetype` |
| `winProbabilityAdded`| number | Cumulative WPA | `metrics.wpa` | `metrics.wpa` | `wpaClutch` | `epa_clutch` |

---

### 4.3 Endpoint Family 3: `defense`

#### Scope & Files
- **NBA:** `web/public/data/defensive_metrics.json`
- **WNBA:** `web/public/data/defensive_metrics.json`
- **NFL:** `web/public/data/team_epa_profiles.json` (Defensive EPA slice)
- **MLB:** `web/public/data/statcast_spatial_analytics.json` (OAA / DRS / Range)

#### Canonical Schema (TypeScript / Zod)
```typescript
export const CanonicalDefensiveProfileSchema = z.object({
  playerId: z.string().min(1),
  playerName: z.string().min(2),
  teamAbbr: z.string().min(2).max(4),
  position: z.string().min(1),
  defensiveRole: z.string().min(2),
  versatilityScore: z.number().min(0).max(100),
  defensiveRating: z.number(),
  impactDelta: z.number(),
  percentiles: z.record(z.string(), z.number().min(0).max(100)).optional()
});
```

#### Field Crosswalk Matrix
| Canonical Field | Type | Description | NBA Current | WNBA Current | NFL Current | MLB Current |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `playerId` | string | Unique player ID | `playerId` | `playerId` | *(team-level / qb)* | `playerId` |
| `playerName` | string | Player name | `playerName` | `playerName` | `player_name` | `playerName` |
| `teamAbbr` | string | Team abbreviation | `team` | `team` | `team` | `teamAbbr` |
| `defensiveRole` | string | Defensive archetype | `defensiveRole` | `defensiveRole` | `coverage_scheme` | `fielding_tier` |
| `versatilityScore`| number | Multi-position index | `versatilityScore`| `versatilityScore`| `scheme_versatility`| `range_versatility`|
| `defensiveRating` | number | Baseline defensive val| `drapm` | `drapm` | `def_epa_per_play` | `drs` / `oaa` |

---

### 4.4 Endpoint Family 4: `cap_sheet`

#### Scope & Files
- **NBA:** `web/public/data/cba_cap_sheet.json`
- **WNBA:** `web/public/data/cba_cap_sheet.json`
- **MLB:** `web/public/data/cbt_payroll_sheet.json`
- **NFL:** `web/public/data/salary_cap_profiles.json`

#### Canonical Schema (TypeScript / Zod)
```typescript
export const CanonicalCapSheetEnvelopeSchema = z.object({
  schema_version: z.literal("1.0"),
  generated_at: z.string().datetime(),
  season: z.string(),
  sport: z.enum(['mlb', 'nba', 'nfl', 'wnba']),
  endpoint: z.literal("cap_sheet"),
  salaryCap: z.number().positive(),
  isHardCap: z.boolean(),
  totalLeaguePayroll: z.number().positive().optional(),
  leagueTaxCollected: z.number().nonnegative().optional(),
  teams: z.array(z.object({
    teamAbbr: z.string().min(2).max(4),
    teamName: z.string().min(2),
    conference: z.string().optional(),
    division: z.string().optional(),
    activePayroll: z.number().nonnegative(),
    capSpace: z.number(),
    taxObligation: z.number().nonnegative().optional(),
    topPaidPlayers: z.array(z.object({
      playerId: z.string().optional(),
      playerName: z.string(),
      salary: z.number().positive(),
      capPercentage: z.number().min(0).max(100).optional()
    })).optional()
  }))
});
```

#### Field Crosswalk Matrix
| Canonical Field | Type | Description | NBA Current | WNBA Current | MLB Current | NFL Current |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `salaryCap` | number | League cap ceiling ($M) | `salaryCap` | `hardSalaryCap` | `baseThreshold` | `cap_ceiling` |
| `isHardCap` | boolean| Hard cap vs soft/CBT | `false` | `true` | `false` | `true` |
| `teamAbbr` | string | Franchise abbreviation | `teamAbbr` | `teamAbbr` | `teamAbbr` | `team` |
| `teamName` | string | Full team name | `teamName` | `teamName` | `teamName` | *(derived)* |
| `activePayroll` | number | Current season payroll | `totalPayroll2026` | `totalPayroll2026`| `payroll2026` | `total_active_apy`|
| `capSpace` | number | Room under cap | `capRoom` | `capSpace` | `cbtSpace` | `cap_space` |

---

### 4.5 Endpoint Family 5: `player_dna`

#### Scope & Files
- **NBA:** `web/public/data/player_dna_profiles.json`
- **WNBA:** `web/public/data/player_dna_profiles.json` (and legacy `player_dna.json`)
- **MLB:** `web/public/data/player_dna_profiles.json`
- **NFL:** `web/public/data/player_qb_profiles.json` (and upcoming skill DNA)

#### Canonical Schema (TypeScript / Zod)
```typescript
export const CanonicalPlayerDnaProfileSchema = z.object({
  playerId: z.string().min(1),
  playerName: z.string().min(2),
  teamAbbr: z.string().min(2).max(4),
  position: z.string().min(1),
  archetype: z.string().min(2),
  clusterId: z.number().int().nonnegative().optional(),
  radarScores: z.record(z.string(), z.number().min(0).max(100)),
  similarityScores: z.array(z.object({
    playerId: z.string().optional(),
    playerName: z.string(),
    similarityPct: z.number().min(0).max(100)
  })).optional(),
  projections: z.record(z.string(), z.union([z.number(), z.string()])).optional()
});
```

#### Field Crosswalk Matrix
| Canonical Field | Type | Description | NBA Current | WNBA Current | MLB Current | NFL Current |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `playerId` | string | Player unique ID | `playerId` | `playerId` | `playerId` | `player_id` / *(name)* |
| `playerName` | string | Player name | `playerName` | `playerName` | `playerName` | `player_name` |
| `teamAbbr` | string | Team abbreviation | `team` | `team` | `teamAbbr` | `team` |
| `archetype` | string | Cluster assignment | `archetype` | `archetype` | `primaryArchetype`| `passer_archetype`|
| `radarScores` | object | Percentile attributes | `radarScores` | `radarScores` | `statcastRadar` | `qb_radar_scores` |
| `similarityScores`| array | Closest statistical comps| `similarPlayers` | `similarPlayers` | `similarBatters` | `similar_qbs` |

---

### 4.6 Endpoint Family 6: `standings`

#### Scope & Files
- **NBA:** `web/public/data/projections_season_teams.json`
- **WNBA:** `web/public/data/projections_season_teams.json`
- **MLB:** `web/public/data/projections_season_teams.json`
- **NFL:** `web/public/data/standings_projections.json`

#### Canonical Schema (TypeScript / Zod)
```typescript
export const CanonicalStandingsRowSchema = z.object({
  rank: z.number().int().positive(),
  teamAbbr: z.string().min(2).max(4),
  teamName: z.string().min(2),
  conference: z.string().optional(),
  division: z.string().optional(),
  projectedWins: z.number().nonnegative(),
  projectedLosses: z.number().nonnegative(),
  win_pct: z.number().min(0).max(1),
  ensembleMeanWins: z.number().nonnegative().optional(),
  pythagoreanWins: z.number().nonnegative().optional(),
  playoffProb: z.number().min(0).max(100).optional(),
  championshipProb: z.number().min(0).max(100).optional()
});
```

#### Field Crosswalk Matrix
| Canonical Field | Type | Description | NBA Current | WNBA Current | MLB Current | NFL Current |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `teamAbbr` | string | Team abbreviation | `team` | `team` | `team` | `team` |
| `teamName` | string | Full team name | `team_name` | `team_name` | `team_name` | `team_name` |
| `projectedWins`| number | Mean projected wins | `proj_wins` | `proj_wins` | `proj_wins` | `projected_wins` |
| `projectedLosses`| number | Mean projected losses | `proj_losses` | `proj_losses` | `proj_losses` | `projected_losses`|
| `win_pct` | number | Win percentage [0, 1] | `win_pct` | `win_pct` | `win_pct` | `win_pct_pyth` |
| `playoffProb` | number | Postseason probability | `playoff_prob` | `playoff_prob` | `postseason_prob` | `playoff_probability` |

---

## 5. Non-Breaking Ingestion Helper (TypeScript)

To satisfy the zero-breakage constraint, frontends must ingest payloads through the **Harmonized Envelope Unwrapper** (`unwrapCrossSportPayload`). This helper transparently handles bare arrays, legacy root keys, and field drifts:

```typescript
/**
 * Unwraps cross-sport payloads safely handling both legacy bare arrays
 * and modern Level-1 Canonical Envelopes.
 */
export function unwrapCrossSportPayload<T>(
  raw: unknown,
  fieldExtractor?: (item: Record<string, unknown>) => T
): { data: T[]; metadata: Record<string, unknown>; generated_at: string } {
  if (!raw || typeof raw !== 'object') {
    return { data: [], metadata: {}, generated_at: new Date().toISOString() };
  }

  // Case 1: Bare JSON array (legacy NBA/WNBA)
  if (Array.isArray(raw)) {
    const data = fieldExtractor
      ? raw.map((item) => fieldExtractor(item as Record<string, unknown>))
      : (raw as T[]);
    return {
      data,
      metadata: { format: 'legacy_bare_array' },
      generated_at: (raw[0] as Record<string, unknown>)?.generated_at as string ?? new Date().toISOString()
    };
  }

  const dict = raw as Record<string, unknown>;

  // Case 2: Canonical Envelope
  if (Array.isArray(dict.data)) {
    const data = fieldExtractor
      ? dict.data.map((item) => fieldExtractor(item as Record<string, unknown>))
      : (dict.data as T[]);
    return {
      data,
      metadata: (dict.metadata as Record<string, unknown>) ?? {},
      generated_at: (dict.generated_at as string) ?? new Date().toISOString()
    };
  }

  // Case 3: Partitioned Catalogs (MLB profiles, NFL teams)
  const collectionKey = ['profiles', 'teams', 'players'].find((k) => Array.isArray(dict[k]));
  if (collectionKey) {
    const list = dict[collectionKey] as Record<string, unknown>[];
    const data = fieldExtractor ? list.map((item) => fieldExtractor(item)) : (list as unknown as T[]);
    return {
      data,
      metadata: dict,
      generated_at: (dict.generated_at as string) ?? new Date().toISOString()
    };
  }

  return { data: [], metadata: dict, generated_at: new Date().toISOString() };
}
```

---

## 6. Phased Implementation Roadmap

```
+---------------------------------------------------------------------------------------------------+
| PHASED ROLLOUT ROADMAP                                                                            |
+-------------+---------------------------------------+---------------------------------------------+
| Phase       | Target Scope                          | Actions & Deliverables                      |
+-------------+---------------------------------------+---------------------------------------------+
| Phase 1     | Aggregator & Contracts                | Land Issue #95 canonical contract spec      |
| (Current)   | (docs/contracts/cross_sport_spec.md)  | Establish crosswalks and field mappings     |
+-------------+---------------------------------------+---------------------------------------------+
| Phase 2     | Web Client Loaders                    | Add unwrapCrossSportPayload helper          |
|             | (MLB, NBA, NFL, WNBA web/lib/)        | Accept both canonical and legacy aliases    |
+-------------+---------------------------------------+---------------------------------------------+
| Phase 3     | R Pipeline Exporters                  | Update export_web_json.R scripts across     |
|             | (mlb, nba, nfl, wnba pipelines)       | sports to wrap outputs in canonical envelope|
+-------------+---------------------------------------+---------------------------------------------+
| Phase 4     | Deprecation & Invariant Enforcement   | Transition Zod contract tests to enforce    |
|             | (web/tests/contracts/)                | Level-1 envelope strictly; purge fallbacks  |
+-------------+---------------------------------------+---------------------------------------------+
```

---

## 7. Compliance Verification & Invariants

Each sport's Vitest contract test suite (`web/tests/contracts/`) will validate the following invariants against exported data:

1. **`teamAbbr` Format:** Must match `^[A-Z]{2,4}$`.
2. **`headCoach` Format:** Non-empty string with at least two space-separated words or single word mononym (`min(2)`).
3. **`win_pct` Invariant:** `0 <= win_pct <= 1.000`. Must be numeric float.
4. **`salaryCap` Invariant:** Positive finite number (`> 0`).
5. **`playerId` Invariant:** Non-empty string or integer string (`min(1)`).
6. **`generated_at` Invariant:** Valid ISO 8601 UTC timestamp format (`^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$`).
