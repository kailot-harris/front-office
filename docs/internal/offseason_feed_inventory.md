# WNBA Offseason Dynamics Monitor — Feed Inventory Spike
**Document:** `docs/internal/offseason_feed_inventory.md`  
**Task / Context:** Issue #160 / Unit B Feed Inventory Spike (Tier 0)  
**Execution Date:** 2026-11-07  
**Author:** Unit B Spike Subagent (`feat/offseason-tier0-unitB`)  

---

## 1. Executive Summary

This feed inventory spike investigates the persistent failure of `poll_team_releases()` and assesses the health of `poll_beat_feeds()` in `tools/offseason/ingest_sources.R`. In the 2026-11-06 ingestion manifest, all 15 franchise feeds failed (`feeds_succeeded: 0`), holding composite ingestion health in a perpetual `DEGRADED` state and risking an unhandled `FAILED` gate trip whenever any beat feed fluctuates.

### Key Findings
1. **Franchise Feeds (`team_releases`): 100% Inactive / Non-Existent**
   - All 15 franchise URLs (`https://www.wnba.com/{abbr}/news/rss`) are non-existent. Probing with HTTP/2 yields HTTP 404 (origin Envoy / Next.js application); probing via standard HTTP/1.1 curl yields HTTP 403 Forbidden (Akamai edge WAF block).
   - Comprehensive probing across team subdomains (`{team}.wnba.com` and `valkyries.com`) confirms that **no public RSS or XML feed exists** on the modern WNBA digital platform. The league migrated to a Next.js single-page application without RSS syndication endpoints.
2. **Beat Feeds (`beat_feeds`): 5 of 6 Fully Functional**
   - 5 feeds are healthy, providing robust XML RSS data (The Next Hoops, Winsidr, Her Hoop Stats, ESPN Women's Hoops Desk, Swish Appeal).
   - 1 feed fails: `athletic_wnba` (`https://theathletic.com/wnba/feed/`). It returns HTTP 301 redirecting to `https://www.nytimes.com/athletic/wnba/feed/`, which responds with HTTP 404 Not Found following the NYT platform integration.
   - Identified viable drop-in replacements: *Just Women's Sports* (`https://justwomenssports.com/feed/`, HTTP 200, 10 items) and *New York Times Pro Basketball* (`https://rss.nytimes.com/services/xml/rss/nyt/ProBasketball.xml`, HTTP 200).
3. **Core Tier 1 Recommendation:**
   - **Retire / prune `team_releases`** from composite health evaluation. Retaining a phantom adapter querying 15 non-existent endpoints introduces permanent degradation and operational risk.
   - **Repair or prune `athletic_wnba`** in `DEFAULT_BEAT_SOURCES` to restore `beat_feeds` to 100% `HEALTHY`.

---

## 2. Franchise Feeds Probe Table (15 Franchises)

### Methodology & Test Environment
- **Test Method 1 (Production Adapter Simulation):** Invoked via R's `curl::curl_fetch_memory()`, matching the exact runtime environment of `poll_team_releases()`. Negotiates HTTP/2 over TLS with default libcurl options.
- **Test Method 2 (CLI Inspection):** Invoked via `curl.exe -I` / `curl.exe -s -D` (HTTP/1.1) to observe edge behavior.
- **Test Method 3 (Browser User-Agent Override):** Probed using desktop Chrome User-Agent header (`Mozilla/5.0...`).
- **All tests conducted on:** 2026-11-07 04:25–04:29 UTC.

### Probe Results Table

| Abbr | Franchise Name | Configured Target URL | HTTP Status (R / libcurl) | HTTP Status (curl CLI) | Response Server / Tech | Content Type | Verdict |
|:---|:---|:---|:---:|:---:|:---|:---|:---|
| **ATL** | Atlanta Dream | `https://www.wnba.com/atl/news/rss` | **404** | **403** | Next.js / Envoy / Akamai | `text/html; charset=utf-8` | No public feed exists |
| **CHI** | Chicago Sky | `https://www.wnba.com/chi/news/rss` | **404** | **403** | Next.js / Envoy / Akamai | `text/html; charset=utf-8` | No public feed exists |
| **CON** | Connecticut Sun | `https://www.wnba.com/con/news/rss` | **404** | **403** | Next.js / Envoy / Akamai | `text/html; charset=utf-8` | No public feed exists |
| **DAL** | Dallas Wings | `https://www.wnba.com/dal/news/rss` | **404** | **403** | Next.js / Envoy / Akamai | `text/html; charset=utf-8` | No public feed exists |
| **GS** | Golden State Valkyries | `https://www.wnba.com/gs/news/rss` | **404** | **403** | Next.js / Envoy / Akamai | `text/html; charset=utf-8` | No public feed exists |
| **IND** | Indiana Fever | `https://www.wnba.com/ind/news/rss` | **404** | **403** | Next.js / Envoy / Akamai | `text/html; charset=utf-8` | No public feed exists |
| **LV** | Las Vegas Aces | `https://www.wnba.com/lv/news/rss` | **404** | **403** | Next.js / Envoy / Akamai | `text/html; charset=utf-8` | No public feed exists |
| **LA** | Los Angeles Sparks | `https://www.wnba.com/la/news/rss` | **404** | **403** | Next.js / Envoy / Akamai | `text/html; charset=utf-8` | No public feed exists |
| **MIN** | Minnesota Lynx | `https://www.wnba.com/min/news/rss` | **404** | **403** | Next.js / Envoy / Akamai | `text/html; charset=utf-8` | No public feed exists |
| **NY** | New York Liberty | `https://www.wnba.com/ny/news/rss` | **404** | **403** | Next.js / Envoy / Akamai | `text/html; charset=utf-8` | No public feed exists |
| **PHX** | Phoenix Mercury | `https://www.wnba.com/phx/news/rss` | **404** | **403** | Next.js / Envoy / Akamai | `text/html; charset=utf-8` | No public feed exists |
| **POR** | Portland Fire | `https://www.wnba.com/por/news/rss` | **404** | **403** | Next.js / Envoy / Akamai | `text/html; charset=utf-8` | No public feed exists |
| **SEA** | Seattle Storm | `https://www.wnba.com/sea/news/rss` | **404** | **403** | Next.js / Envoy / Akamai | `text/html; charset=utf-8` | No public feed exists |
| **TOR** | Toronto Tempo | `https://www.wnba.com/tor/news/rss` | **404** | **403** | Next.js / Envoy / Akamai | `text/html; charset=utf-8` | No public feed exists |
| **WSH** | Washington Mystics | `https://www.wnba.com/wsh/news/rss` | **404** | **403** | Next.js / Envoy / Akamai | `text/html; charset=utf-8` | No public feed exists |

### Analysis of Response Headers & Origin Behavior
- **Edge Layer (Akamai):** Standard CLI requests via HTTP/1.1 are intercepted by Akamai (`Server: AkamaiGHost`) and rejected with `403 Forbidden` due to automated-agent bot defense policies.
- **Origin Layer (Next.js / Envoy):** When requests connect via libcurl with HTTP/2 negotiation, Akamai passes the request upstream to the Envoy proxy and Next.js cluster (`server: envoy`, `x-powered-by: Next.js`, `x-vcl-version: NBA.com prod 1.7b`). Next.js routes the path `/{abbr}/news/rss` to its global 404 handler (`<link rel="canonical" href="/404"/>`, payload 113,358 bytes HTML).
- **Custom User-Agent:** Providing a legitimate browser User-Agent header still produces HTTP 404, proving conclusively that the path `/{abbr}/news/rss` does not exist on WNBA.com.

### Investigation of Alternate Franchise Endpoints
To verify whether feeds exist at different paths or subdomains, an exhaustive sweep was conducted across all 15 franchises probing common syndication patterns: `/rss`, `/feed`, `/news/rss`, `/news/feed`, `/rss.xml`, `/feed.xml`, `/api/news`, `/feed/rss2`.
- **Active Team Subdomains (`dream.wnba.com`, `sky.wnba.com`, `wings.wnba.com`, `valkyries.com`, `fever.wnba.com`, `aces.wnba.com`, `sparks.wnba.com`, `lynx.wnba.com`, `liberty.wnba.com`, `mercury.wnba.com`, `storm.wnba.com`, `mystics.wnba.com`):**
  - All tested syndication paths returned HTTP 404 HTML.
  - The team websites run on the unified Next.js/React platform without public RSS endpoints.
  - `sun.wnba.com` routes all syndication endpoints to an Akamai WAF access denial page (`failover-waf.nba.com/error-pages/wnba/index.html`).
- **Expansion Franchises (`portland.wnba.com`, `toronto.wnba.com`):**
  - DNS resolution failed (`Could not resolve host`). These expansion franchise subdomains have not been provisioned with DNS A/AAAA records.

**Conclusion:** There are no active, public RSS feeds for any of the 15 WNBA franchises.

---

## 3. Beat Feeds Inventory & Analysis (6 Feeds)

### Inventory Table

| Source ID | Source Name | Feed URL | HTTP Status | Content Type | Size (Bytes) | Items Parsed | State |
|:---|:---|:---|:---:|:---|:---:|:---:|:---:|
| `the_next_hoops` | The Next Hoops | `https://thenexthoops.com/feed/` | **200 OK** | `application/rss+xml; charset=UTF-8` | 228,943 | 10 | **HEALTHY** |
| `winsidr` | Winsidr | `https://winsidr.com/feed/` | **200 OK** | `application/rss+xml; charset=UTF-8` | 105,945 | 10 | **HEALTHY** |
| `her_hoop_stats` | Her Hoop Stats | `https://herhoopstats.substack.com/feed` | **200 OK** | `application/xml; charset=utf-8` | 426,227 | 20 | **HEALTHY** |
| `espn_wnba_beat` | ESPN Women's Hoops Desk | `https://www.espn.com/espn/rss/wnba/news` | **200 OK** | `text/xml; charset=UTF-8` | 11,651 | 20 | **HEALTHY** |
| `athletic_wnba` | The Athletic WNBA Wire | `https://theathletic.com/wnba/feed/` | **404 Not Found** (via 301) | `text/html; charset=utf-8` | 204,352 | 0 | **FAILED** |
| `swish_appeal` | Swish Appeal | `https://www.swishappeal.com/rss/index.xml` | **200 OK** | `application/xml; charset=UTF-8` | 111,416 | 10 | **HEALTHY** |

### Root Cause Analysis of Failing Feed (`athletic_wnba`)
- **Initial URL:** `https://theathletic.com/wnba/feed/`
- **Redirect Response:** HTTP 301 Moved Permanently with `Location: https://www.nytimes.com/athletic/wnba/feed/` (Cloudflare edge).
- **Target Response:** `https://www.nytimes.com/athletic/wnba/feed/` returns HTTP 404 Not Found (`server: envoy`, `x-envoy-decorator-operation: athletic.theathletic.nyti.nyt.net:443/*`, length 204,321 bytes HTML).
- **Structural Cause:** Following the integration of *The Athletic* into *The New York Times*, legacy WordPress-style `/feed/` endpoints were sunset. The root `/feed/` now redirects to the paywalled homepage (`https://www.nytimes.com/athletic/`), and sub-topic feeds return 404. Public RSS syndication for The Athletic has been retired.

### Evaluated Replacement Candidates

1. **Candidate A: Just Women's Sports Feed**
   - **URL:** `https://justwomenssports.com/feed/`
   - **HTTP Status:** 200 OK
   - **Content-Type:** `application/rss+xml; charset=UTF-8`
   - **Payload:** ~85 KB, 10 active items
   - **Relevance:** Dedicated daily coverage of WNBA transactions, free agency rumors, roster cuts, and expansion drafts. Highly active and structurally identical to WordPress RSS.

2. **Candidate B: New York Times Pro Basketball Feed**
   - **URL:** `https://rss.nytimes.com/services/xml/rss/nyt/ProBasketball.xml`
   - **HTTP Status:** 200 OK
   - **Content-Type:** `application/xml`
   - **Payload:** ~40 KB, syndicated NYT basketball articles including WNBA offseason coverage.

---

## 4. Per-Source Verdicts and Rationales

### Franchise Feeds (15 Sources)
- **Verdict:** **No public feed exists.**
- **Rationale:** 
  1. The configured `https://www.wnba.com/{abbr}/news/rss` endpoints return 404 from the Next.js origin server.
  2. Probes across franchise subdomains (`{abbr}.wnba.com`) demonstrate that modern WNBA team sites do not provide RSS/Atom feeds; content is rendered client-side via React/Next.js and protected by Akamai WAF.
  3. Expansion teams (`POR`, `TOR`) have no registered DNS web hosts.
  4. Attempting to scrape HTML news pages would require brittle DOM parsing and bot-evasion tactics, violating project governance and anti-scraping guidelines.

### Beat Feeds (6 Sources)
- **`the_next_hoops`:** **Working URL.** Delivers comprehensive beat reporting, 10 items, 200 OK.
- **`winsidr`:** **Working URL.** Delivers independent WNBA analysis, 10 items, 200 OK.
- **`her_hoop_stats`:** **Working URL.** Delivers salary cap, CBA, and roster analytics via Substack, 20 items, 200 OK.
- **`espn_wnba_beat`:** **Working URL.** Delivers mainstream transaction notices and reporting, 20 items, 200 OK.
- **`athletic_wnba`:** **No public feed exists.** The Athletic has discontinued RSS syndication after migrating under NYT infrastructure.
- **`swish_appeal`:** **Working URL.** Delivers Vox Media/SB Nation community and news coverage, 10 items, 200 OK.

---

## 5. Architectural & Governance Impact

In `tools/offseason/ingest_sources.R`, adapter health and composite health are calculated as follows:

```r
# Adapter 2: poll_team_releases()
status <- if (feeds_succeeded == feeds_polled) {
  "HEALTHY"
} else if (feeds_succeeded > 0) {
  "DEGRADED"
} else {
  "FAILED"
}

# Composite Health Policy: compute_composite_health()
compute_composite_health <- function(wire_res, releases_res, beat_res) {
  if (identical(wire_res$status, "HEALTHY") &&
      identical(releases_res$status, "HEALTHY") &&
      identical(beat_res$status, "HEALTHY")) {
    return("HEALTHY")
  }
  if (identical(wire_res$status, "FAILED") ||
      (identical(releases_res$status, "FAILED") && identical(beat_res$status, "FAILED"))) {
    return("FAILED")
  }
  "DEGRADED"
}
```

### Consequences of Current Implementation:
1. **Permanent `DEGRADED` Trap:** Because `feeds_succeeded` is permanently `0 / 15`, `releases_res$status` is always `"FAILED"`. Consequently, composite health **can never achieve `HEALTHY`**, even if `league_wire` and `beat_feeds` are 100% operational.
2. **Imminent Pipeline Blockade:** Because `releases_res$status` is `"FAILED"`, any transient outage in the beat feeds adapter (e.g. if network failure causes `beat_res$status == "FAILED"`) immediately triggers:
   `(identical(releases_res$status, "FAILED") && identical(beat_res$status, "FAILED")) -> "FAILED"`, which blocks the publication gate:
   `check_publication_gate(manifest, allow_degraded = FALSE)`.
3. **Quiet Week Assertion Disabled:** `can_assert_quiet_week()` requires `manifest$composite_health == "HEALTHY"`. With `releases_res` permanently failed, quiet weeks can never be programmatically asserted during the offseason.

---

## 6. Recommendations for Tier 1 Implementation

### Recommendation 1: Retire `team_releases` Adapter
- **Action:** Remove `team_releases` from active polling in `run_ingest_pipeline()` and retire it from the composite health calculation in `compute_composite_health()`.
- **Rationale:** No public feeds exist for WNBA franchises. Polling 15 dead endpoints introduces latency, spammy warning logs, and false failure signals.
- **Implementation Design in Tier 1:**
  - Either remove Adapter 2 entirely, or mark it as an advisory/dormant module (`status: "DORMANT"` or `"RETIRED"`) that does not poll network endpoints and does not downgrade composite health.
  - Simplify `compute_composite_health(wire_res, beat_res)` so that composite health is `HEALTHY` when `wire_res == "HEALTHY"` and `beat_res == "HEALTHY"`.

### Recommendation 2: Repair `DEFAULT_BEAT_SOURCES`
- **Action:** Replace `athletic_wnba` with `just_womens_sports` in `DEFAULT_BEAT_SOURCES`:
  ```r
  list(
    id = "just_womens_sports",
    name = "Just Women's Sports",
    url = "https://justwomenssports.com/feed/"
  )
  ```
  *(Alternative: prune `athletic_wnba` to maintain 5 high-fidelity feeds).*
- **Rationale:** Replacing the dead Athletic feed with *Just Women's Sports* restores `beat_feeds` to 6/6 `HEALTHY` without loss of beat coverage breadth.

### Projected Pipeline State Post-Tier 1
With both recommendations implemented:
- `league_wire`: `HEALTHY` (ESPN API + WNBA Wire)
- `beat_feeds`: `HEALTHY` (6/6 sources operational)
- `team_releases`: Retired / Excluded from health gate
- **Composite Health:** **`HEALTHY`**
- **Publication Gate:** **Passed** (`allowed: TRUE`), quiet week assertions enabled.
