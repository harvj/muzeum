# P1.0 — Import performance and idempotency requirements

Status: proposed acceptance gates, not measured pipeline performance. Approximately 250,000 source scrobbles; P1.0 ran the existing small suite only. See the [schema/identity proposal](foundation-and-data-contract.md#42-observation-and-import-extension) and [baseline](baseline-results.md).

## Provider contract and limits

Use documented `user.getRecentTracks` with the application's API key and public source username. It needs no Last.fm user authentication. The documented page limit is 200, supports UTC `from`/`to` bounds, and may include an undated now-playing item. Design for that documented limit rather than higher unofficial limits. [Last.fm method documentation](https://www.last.fm/api/show/user.getRecentTracks).

250,000 / 200 = 1,250 full data pages, excluding retries, overlaps, boundary windows and metadata requests. The existing importer asks for metadata and then the oldest outstanding page in every iteration, roughly doubling the request count. It also uses maximum stored time + 1 as a cursor and cannot repair old gaps. Propose bounded historical windows with fixed upper cutoff, persisted per-window pagination and overlapping second boundaries. The client must add `to`; it currently supports `from` only. Avoid requesting page 1 merely to rediscover page totals on every loop.

Page numbers are not durable event identity. A fixed upper bound prevents newer listens shifting the latest page but cannot freeze edits/deletions to older upstream history. Persist request bounds, response metadata and digests; detect drift and replay affected windows. Never infer “complete” from latest timestamp or a single empty response following an API error. At a page boundary, refetch enough of the exact boundary second to enumerate all source items there. Do not simply increment the timestamp and skip remaining same-second items. If a time bucket exceeds one page, paginate that bucket; if the provider cannot expose it fully, record incomplete coverage and stop claiming completeness.

Use a shared application/IP request limiter, initially **one request start per second**, serialized per source account. This is a conservative application setting, not a guaranteed provider quota. Handle HTTP 429/5xx/timeouts and Last.fm envelope errors, including rate-limit code 29, with bounded exponential backoff/jitter and Retry-After when supplied. Persist paused/retryable state after the retry budget rather than marking complete or deleting progress. Invalid key or denied/private resource is an actionable failure. [Last.fm error documentation](https://www.last.fm/api/errorcodes).

No live API calls were used for this milestone. Retrieval of the documentation directly failed through the web gateway; the official search-indexed method/error documentation was available and used. Confirm boundary semantics using recorded/live fixtures before choosing inclusive/exclusive arithmetic in code. Preserve boundary overlap even after that validation.

## Benchmark design

Run on pinned Ruby 3.3.5, locked gems, PostgreSQL 16.15 (the P1.0 disposable target), one importer process, ordinary durable PostgreSQL settings, local SSD. Record machine/CPU/RAM/OS, PG settings, database/index size, Ruby RSS, fixture manifest/hash, code revision and command. Do not disable fsync, uniqueness, immutable-source enforcement, provenance storage or indexes to meet a throughput target.

Prepare a deterministic streaming source manifest with 250,000 distinct timestamped observations spread over many years and a realistic mix of repeated surfaces, missing albums/MBIDs, long/Unicode strings and payload sizes. Include separate adversarial fixtures rather than assuming every input has a unique timestamp. Each fixture page has expected received/inserted/repeat/conflict/invalid/now-playing counts and an independently computed source digest. Generate/read at most a page plus a bounded write buffer; do not create a 250k Ruby array before timing. Corpus design and construction command must be committed in P1.1, with reproducible seed and digest, not credentials or real listening data.

| Benchmark | Included | Excluded / purpose |
| --- | --- | --- |
| A. Bulk database insertion | Prebuilt rows, real constraints/indexes, immutable raw provenance and transaction/checkpoint costs; 200/500/1,000-row bounded batches where feasible | No HTTP, parsing or surface/MB operations; measures DB write ceiling |
| B. Local end-to-end import | Stream raw XML fixtures → parse → page capture → identity/conflict checks → bulk inserts/checkpoint/progress | HTTP stub returns immediately; main reproducible application gate |
| C. Paced network simulation | B plus 1,250+ page requests, limiter and injected latencies/errors | No provider traffic; separates network/sleep/retry cost from local work |
| D. Live source import | Approved account, fixed cutoff, recorded page counts/digests, provider timing, limiter/backoff | Manual separately authorized validation, not mandatory CI traffic; no guaranteed provider SLA |

Measure cold initial import and warm replay separately. Run A/B at least three times in fresh dedicated databases plus one replay per populated database; report each time, median and worst time, not only best. Use wall-clock monotonic timing; separate fetch wait, rate-limit sleep, retry delay, XML parse/hash time, DB transaction time and logging time. Record transaction/query counts, rows/second, commit p50/p95, peak RSS, page latency and database/storage growth. Keep WAL/index/provenance cost in the reported DB result.

### Proposed first gates

These are reviewable initial budgets, to be calibrated against the first P1.1 run without quietly weakening integrity. They are **not current measurements**.

| Metric | Initial gate |
| --- | --- |
| A: initial database writes | At least 5,000 observations/second (250k in at most 50 seconds), with all associated required provenance/checkpoint writes |
| B: complete local fixture pipeline | 250k in at most 120 seconds, at least 2,083 observations/second; no provider or identity-resolution calls |
| B: full replay | At most 120 seconds; zero new scrobbles, zero source updates/deletes, zero new resolution decisions, unchanged source digest |
| Memory | Peak importer RSS ≤512 MiB; growth from 25k to 250k ≤64 MiB after warmup; buffers never exceed 1,000 event rows plus current raw page |
| Writes/queries | No per-event SELECT/INSERT/UPDATE callback loop; publish actual counts. Routine ingestion target ≤15 DB statements per clean 200-item page, plus bounded run startup/finalization; explicitly measure conflict-page costs |
| Restart | Replay at most one uncommitted page/window checkpoint unit in the normal case; final evidence/source digest equals uninterrupted run |
| Progress | Numeric committed counters and heartbeat at least every five seconds or each completed page; errors show account/run/page/bounds with secrets removed |
| Read-only lookup | Indexed keyset history page of 100 rows p95 <200 ms at 250k, excluding first boot, no per-row queries; EXPLAIN (ANALYZE, BUFFERS) retained |

At one request/second and 1,250 data pages, request-start spacing alone is about 20.8 minutes. With sequential one-second request latency, approximately 21 minutes plus local work/overlap is plausible; at two-second latency it is roughly 42 minutes. Existing two-request loops can approximately double those request counts. These are scenarios, not Last.fm guarantees. For C, record the scheduler model explicitly: start-to-start pacing can overlap latency; “sleep one second after every response” adds a different cost. Gate C at the simulated schedule plus measured B cost plus 10% overhead, with explicit retry allowances. For D report actual end-to-end duration and network share; alert on sustained slowdown and checkpoint safely rather than asserting a fixed live completion SLA. Never include provider latency in “database rows/second.”

A replay may append new import runs/pages/assessments of conflicting source delivery; it must not modify old evidence, create duplicate listens, alter surface attachments or revise resolution decisions. Audit storage growth is measured and distinct from source idempotency. Successful network replay cannot prove unchanged Last.fm history if upstream has edited it: retain new evidence and report differences, do not rewrite first observations.

## Regression matrix

| Input / fault | Acceptance oracle |
| --- | --- |
| Clean 250k, no MB/surfaces/login | All expected observations/provenance present; no canonical/surface/decision rows created; all provider calls confined to Last.fm |
| Exact replay, overlapping/reordered/repeated pages | Fingerprint set and first-source checksums unchanged; repeats counted, not inserted; deterministic collision status |
| Same timestamp, different track | Both observed tuples preserved and conflict reported; no silent overwrite or automatic two-listen claim |
| Same tuple, changed MBID/loved/image | Original immutable payload survives; changed evidence retained on source page/issue; no automatic extra event or identity reassignment |
| Identical items repeated within source page | Multiplicity evidence retained and ambiguity reported; repeated page delivery never increments plays |
| New source account with identical times/text | Separate account observations; two associated Muzeum users reuse the same account archive without duplicate source import |
| Username capitalization / association change | Account lookup deterministic; cannot impersonate owner or change another user's association/interpretation |
| Now-playing / missing date / malformed date | Retained evidence plus excluded/invalid counters; no epoch-zero or invented timestamp |
| Empty/malformed XML, provider error in HTTP 200 | Distinct failure/incomplete status; no silent “empty history” success or checkpoint advancement |
| Later new scrobbles during historical import | Fixed cutoff respected; next incremental run imports the later range |
| Late older event or edit/delete in a prior page | Window/full replay finds additions/differences; no source deletion; upstream drift and coverage gaps visible |
| 201st item in same-second boundary bucket | Boundary replay/pagination preserves every distinguishable tuple; no max-time+1 loss |
| Crash before commit / after commit before client acknowledgment | Atomic rollback or safe exact retry; cursor never ahead of data; committed page may be reread without duplicate source |
| DB failure after issue/page insert or before checkpoint | Whole processing unit consistent; failed attempt/response remains inspectable using separately committed fetch evidence |
| Concurrent requests for one account | One authorized active importer; no duplicate runs/corrupt cursor; different accounts can progress under global rate limiter |
| Permission revoked while queued/running | Server rechecks; future work stops safely at bounded transaction boundary; no cross-user mutation |
| Timeout/429/11/16/29 and eventual recovery | Bounded retries, visible delay, checkpoint resume; key redacted; paused distinct from completed |
| Backlog exceeds page budget | Run paused/partial with durable continuation; never reported complete merely because default budget ended |
| Direct SQL/bulk update/delete attempts | Protected source columns/evidence reject mutation; interpretation-only revision leaves source digest unchanged |

Each oracle compares against an independent manifest, not merely the importer's own counters. Run a small adversarial suite on each change; run the complete 250k fixture gate for importer/schema changes and before releasing P1.1. Network simulation and live validation are separate from everyday unit tests. Retain failed-run manifests, exact configuration and measurements for review. Archive completeness means coverage of a recorded source interval with documented exceptions, not agreement with a potentially different profile playcount.
