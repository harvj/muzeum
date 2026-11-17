# P1.2 measurements

Synthetic fixtures only; no real Last.fm requests or second production import. Detailed per-trial rows, SQL timings, p50/p95 page latency, RSS samples, storage/WAL values, independent digests and EXPLAIN plans are retained in `evidence/benchmark-*.json`.

## Environment and method

Measurements use implementation `1ca96bcafa10f17b2b010699b2e02252f746c50e` (individual tree digests retained). The final provider-limit guard also preserves Retry-After values beyond the ordinary retry ceiling; it does not change the measured ordinary-retry cases.

Apple M4 Pro (14 cores), 24 GiB RAM, macOS 26.6.2 arm64; Ruby 3.4.12 / locked gems; isolated PostgreSQL **16.15** with 128 MiB shared buffers, `fsync=on`, `synchronous_commit=on`, `full_page_writes=on`. The historical Ruby 3.3.5 proposal is superseded by P1.1 dependency modernization. One importer per trial, fresh dedicated database and Ruby process for each cold/replay pair. Cold means an empty database, not purged OS disk caches. Some local verification work overlapped trials; cluster-wide WAL includes any such activity and is not an isolated per-import WAL claim.

The deterministic v2 generator streams 250,000 synthetic timestamped tuples spanning 2006–2022, Unicode/long labels, missing albums and mixed present/missing observed MBIDs. It creates independently hashed raw pages and a tuple manifest. No MBIDs are resolved. The independent ordered fingerprint SHA-256 is `0194c967c2fa89cc0327657ad3c4555999f17ec6a06e3807591964a970ea2c2f`. [Corpus summary](evidence/fixture-manifest.json), [complete page manifest](evidence/fixture-pages.json).

A measures prebuilt 200-row page transactions with raw evidence, delivery/issue writes, immutable constraints, indexes and checkpoints; file/JSON decoding remains included, XML parsing and HTTP are excluded. It leaves the explicit boundary traversal pending and is a write-ceiling test, not a coverage-complete import. B runs the real XML parser/importer with immediate synthetic responses, including exact-second boundary sweeps: **2,500 requests**, not just 1,250 main pages. Each mode has three fresh cold databases and warm replays. A uses the actual 200-row atomic page unit; 500/1,000-row cross-page batches were not substituted for that integrity contract.

A1 retained the redundant old per-user active-run index in its disposable clone; it was removed for correct multi-account serialization in the final schema. A2/A3 and all B/C trials use the final account-scoped index contract. This conservative variant and every source-tree digest are disclosed in the trial files; no integrity protections were disabled to meet a number.

## Timings

| Mode | Phase | Trial seconds | Median | Worst | Proposed gate |
| --- | --- | --- | --- | --- | --- |
| A | cold | 41.63, 50.42, 51.73 | 50.42 s | 51.73 s | 50 s |
| A | replay | 34.16, 36.14, 38.95 | 36.14 s | 38.95 s | not separately proposed for A replay |
| B | cold | 69.11, 74.66, 71.02 | 71.02 s | 74.66 s | 120 s |
| B | replay | 49.51, 49.09, 48.75 | 49.09 s | 49.51 s | 120 s |

A’s cold median/worst slightly miss the 50-second proposal; this is retained transparently. B cold and replay meet 120 seconds with zero replay insertions and the same independent source digest. The practical importer remains dominated by the configured provider pacing rather than this small bulk-write-budget miss. No protection was weakened.

## Resource and query evidence

Whole-process OS-measured peak RSS across trials is **255.4 MiB**, including verification, below 512 MiB. The actual B cold-ingestion samples include both approximately 25k and 250k committed observations:

- B1: 25,000→250,000 observations, RSS growth **3.4 MiB**; indexed 100-row lookup p95 **0.42 ms**.
- B2: 25,000→250,000 observations, RSS growth **3.3 MiB**; indexed 100-row lookup p95 **0.45 ms**.
- B3: 25,000→250,000 observations, RSS growth **3.3 MiB**; indexed 100-row lookup p95 **0.51 ms**.

The ingestion buffers hold at most 201 parsed items and bounded incoming/lookup/write sets; verification uses separate 1,000-row reads. Whole-process peak includes digest verification. The fixture gate’s B memory-growth and indexed lookup budgets are met; EXPLAIN (ANALYZE, BUFFERS) plans are in each JSON receipt.

| Representative cold trial | Statements | Statements/main page | Database growth |
| --- | --- | --- | --- |
| benchmark-a2 | 22,516 | 18.01 | 287.0 MiB |
| benchmark-b2 | 67,517 | 54.01 | 289.4 MiB |
| benchmark-c1 | 90,715 | 72.57 | 289.4 MiB |

The ≤15-statement diagnostic target is missed. B/C figures include both main and boundary fetch/commit units, while the denominator remains 1,250 main pages for comparability. There is no per-event SELECT/INSERT callback loop: source matching, timestamp collision counts, observation inserts and delivery writes are bounded bulk operations. Durable fetch evidence, authorization checks, serialization and checkpoints remain intact. Audit storage grows on replay by design; the per-trial receipts separate that from observation idempotency. Capacity planning must include ongoing raw/delivery/issue growth, not just distinct scrobbles.

## C: virtual paced network with real pipeline/budget/retries

C uses the real PostgreSQL budget and persisted retry/error path with **virtual** request time, 200 ms simulated response latency, one start/second and a transient failure every 100th request. It makes no HTTP calls and does not actually sleep for nearly an hour. A one-millisecond virtual retry-deadline margin avoids float/database timestamp rounding; real production clock logic is unchanged. Phase/SQL timings use monotonic notifications so frozen wall time cannot hide local work.

- cold: 2,525 attempts, **83.60 s** actual local work; virtual limiter/latency/retry waits **1999.20/505.00/750.02 s**. Conservative combined model **3337.82 s**. New observations: **250,000**.

- replay: 2,525 attempts, **58.18 s** actual local work; virtual limiter/latency/retry waits **2000.00/505.00/750.02 s**. Conservative combined model **3313.20 s**. New observations: **0**.

The model stays within simulated request schedule plus measured B cost and 10% overhead, with retries reported separately. This is not a live Last.fm SLA or measured Internet latency. Failed/preliminary harness trials remain under `evidence/initial-trial/`; an incomplete virtual-clock-stall database was retained locally instead of being presented as a successful run.

## Central scheduler capacity

The deterministic model follows one-second dispatch, oldest-due per-page fairness, a 48-hour overlap, fixed windows, adaptive activity intervals, the population floor and one global request/second. Each distinct source has two associated users but only one schedule. Mix: 10% active (20 events/hour), 10% occasional, 80% inactive. It models provider outages/throttling, lost process queues and lease recovery; a separate 1,000-account case starts with a 14-day backlog. This is a capacity simulation, not 10,000 simultaneous real APIs or a full Rails load test.

| Accounts | Faults | Event lag p50 / p95 | Pending visible events | Sources never polled |
| --- | --- | --- | --- | --- |
| 1 | none | 36 / 54 s | 1 | 0 |
| 1 | outage/throttle/restart | 42 / 66 s | 1 | 0 |
| 100 | none | 264 / 497 s | 8 | 0 |
| 100 | outage/throttle/restart | 283 / 646 s | 4 | 0 |
| 1,000 | none | 1,904 / 4,384 s | 841 | 0 |
| 1,000 | outage/throttle/restart | 1,916 / 4,435 s | 952 | 0 |
| 10,000 | none | 16,752 / 29,398 s | 212,911 | 0 |
| 10,000 | outage/throttle/restart | 18,185 / 28,012 s | 209,327 | 0 |
| 1,000 (14-day backlog) | outage/throttle/restart | 1,934 / 13,944 s | 921 | 0 |

Lag percentiles describe committed simulated events; pending events are separately visible and are not silently discarded from a freshness claim. All modeled sources receive service. At 10,000 accounts a one-request/second budget necessarily yields hours of lag and a material pending backlog. That is the explicitly understood capacity limit, not a fixed 30–60-second promise or a reason to add credentials/circumvent quotas. Small active populations achieve approximately 30–60 seconds when request demand/latency permit. Dashboard delivery adds up to ten seconds after commit.

## Reproduction

Use dedicated synthetic databases only. Generate `python3 ops/ingestion/generate_fixture.py /private/tmp/muzeum-p12-fixture`. Build a fresh `muzeum_p12_template` on an isolated PostgreSQL 16 instance from migrations (use a new SCHEMA output path to force replay). The recorded macOS setup uses localhost port 56491 and user jim; `python3 ops/ingestion/run_benchmarks.py` deliberately permits only `muzeum_p12_bench_[abc][123]` targets and replaces only those disposable databases. The script uses `/usr/bin/time -l`, writes individual JSON receipts and stops on any manifest/count/canonical-row mismatch. `python3 ops/ingestion/simulate_scheduler.py` reproduces the capacity model. Do not substitute production URLs or another real Last.fm import.
