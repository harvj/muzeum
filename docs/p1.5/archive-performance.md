# P1.5 Archive performance

## Production diagnosis

On the deployed revision `87c9d2cc2f1812a3fc9336b12f37e437fc739862`, 13 authenticated HTML completions for `GET /archive` correlated by request ID within a bounded 500-line Muzeum web journal sample. Rails took **3,788 ms p50 and 6,912 ms p95**. Active Record took 3,666 ms p50 and 6,454 ms p95 (15–16 statements). Views took 12.9 ms p50 and 64.8 ms p95. The log sample did not identify the archive size or cache temperature of each request.

The monitored archive contained 292,999 observations. Each read was timed once under a 1.5-second statement timeout. Production EXPLAIN was plan-only. No production data, configuration, or services were changed.

| Read | Production statement time |
| --- | ---: |
| First 50 plays | 1.0 ms |
| Effective recording lookup for those 50 IDs | 4.5 ms |
| Exact imported observation count | 43.6 ms |
| Distinct reported artists | 815 ms |
| Distinct reported artist/album pairs | 1,485 ms |
| Distinct reported artist/track pairs | 1,461 ms |

The three exact distinct aggregates alone took 3.76 seconds. The plan sorted JSON-derived keys after scanning the archive. On the disposable database, `EXPLAIN (ANALYZE, BUFFERS)` also showed disk spill for all three aggregates. Archive requests and changed-version dashboard polls each ran these counts plus the total and two date extrema. The SQL predates P1.5.1. The pre-P1.5.1 and deployed code report the same summary fields and share the same batched effective-resolution read. P1.5.1 added per-row presentation for partial and unresolved observations.

## Correction

The private Archive and changed-version dashboard poll no longer calculate account-wide counts or date extrema. Exact totals and date bounds remain under the authenticated **Archive summary** link, with Turbo hover prefetch disabled. The summary is still full-archive work when explicitly opened.

Archive reads up to 51 rows in descending `(played_at, id)` order, renders at most 50, and uses the extra row solely to decide whether to offer an older-page link. The cursor comes from the same authorized account, and its timestamp/ID pair handles equal timestamps without lost or duplicated observations. Latest plays refresh in place after an import. An older page stays at its cursor. Public profile pages continue to use the same pagination semantics.

The catalog loader passes only the page's recording claim fields and IDs as a bound recordset into the existing effective-resolution SQL. The ledger still checks current grants and uses the same precedence. This also eliminates a second scan of the observation table, which could appear even with an ID filter under unfavorable planner estimates. The recording/artist and release reads remain batched. No migration, observation update, or provider investigation is part of the correction.

Bounded plan-only checks of the corrected page query against production chose a backwards timestamp index scan with incremental sorting. The first and older page queries returned 51 rows in 8.5 and 2.0 ms in that diagnostic. Local plans with refreshed statistics used 52–53 index entries and 6–8 shared buffers. The ordered index is planner-selected. A stress run with stale local statistics instead scanned the synthetic archive to sort the first page and still recorded a warm server p95 of 50.5 ms. Production index choice should be rechecked after authorized rollout, especially on archives with a different distribution.

## Browser and request measurements

Chrome 157 on loopback drove authenticated Archive requests against 293,000 synthetic observations with timestamp ties and varied reported names. Twenty of the first fifty observations had actual fixture recording decisions. Each run used a first navigation after clearing the HTTP cache, 20 warm desktop navigations, and a 390-pixel mobile navigation. The PostgreSQL statistics were refreshed after seeding. “Cold” means first Archive navigation and browser resources, with the application and database already running. SQL counts exclude transaction control. A fresh local session avoids an external Auth introspection request.

| Local measurement | Pre-P1.5.1 `ddef753` | Deployed code `87c9d2c` | Corrected |
| --- | ---: | ---: | ---: |
| Cold server | 1,185 ms | 1,130 ms | 29 ms |
| Warm server p50 / p95 | 1,157 / 1,175 ms | 1,117 / 1,138 ms | 11.5 / 12.2 ms |
| Warm SQL p50 / p95 | 1,145 / 1,157 ms | 1,102 / 1,124 ms | 2.5 / 2.7 ms |
| Warm SQL statements | 17 | 17 | 11 |
| Warm template time p50 | 3.5 ms | 3.7 ms | 3.5 ms |
| Warm Rails allocations p50 | 13,967 | 14,070 | 12,873 |
| Cold browser TTFB / first contentful paint | 1,187 / 1,212 ms | 1,132 / 1,168 ms | 31 / 68 ms |
| Warm browser TTFB p50 / p95 | 1,158 / 1,176 ms | 1,118 / 1,139 ms | 12.6 / 13.5 ms |
| Warm browser first contentful paint p50 / p95 | 1,184 / 1,200 ms | 1,148 / 1,164 ms | 48 / 48 ms |
| Mobile server / first contentful paint | 1,164 / 1,180 ms | 1,105 / 1,128 ms | 12.5 / 44 ms |

The corrected local plans measured 0.035 ms for the initial 51-row query, 0.027 ms for an older page, and 0.435 ms for the 50-row effective-resolution lookup. The SQL-only plan timings exclude Ruby serialization and network round trips.

The local cold waterfall showed styles, modules, fonts and the fallback image loading after the response began. Warm Chrome script and layout CPU stayed in the low single-digit milliseconds. No external provider requests were observed. A separate anonymous production browser check used the shared Site Art layout. First contentful paint preceded both cold background completions. The cold light/dark image requests took approximately 1,518/286 ms in that browser, and the repeat visits used the cache. Standalone cold downloads from the same workstation were 1.35–1.50 seconds for the 3.40 MB light asset and 1.32–1.40 seconds for the 1.88 MB dark asset. Site Art can delay artwork appearance after paint. Its metadata refresh and image decode do not block the Archive server response. A live authenticated browser waterfall and candidate production response times were unavailable.

The production-scale regression verifies ordered page boundaries with equal timestamps, one bounded ledger lookup per page, no Archive aggregate or offset queries, and a cursor scoped to the active source account. Existing request and browser cases exercise public profile privacy, raw versus canonical labels, refresh after import, auth, and responsive appearance. The local benchmark navigated to an older page at mobile width.
