# Resolution performance and provider reliability

[Issue #25](https://github.com/harvj/muzeum/issues/25) · Production baseline `c051be9ad7565bf3746c0214f90119941ed5f089`

## Production investigation

The authenticated detail request sampled for observation 292965 took **328 ms** in Rails, including **262 ms in Active Record** across 15 queries and **14 ms in views**. Three nearby authenticated Resolution index requests took **2,868–4,510 ms**, with **2,854–4,504 ms in Active Record** across four queries. This is a small log sample. A read-only PostgreSQL plan for the exact surface count took **67 ms** and scanned about 293,000 observations. The retained partial assessment occupied **2,250 bytes** in PostgreSQL. The Rails logs did not report authenticated response bytes, so the HTML measurements below come from matched local requests.

The GET actions read stored observations, decisions, requests and assessment evidence. Both baseline and candidate rendered the authenticated fixture with zero MusicBrainz or Discogs requests. The provider check is a separate POST that dispatches background work.

The final partial assessment for observation 292965 records an HTTP 500 on Discogs `GET /database/search`, page 1, type `release`, with exact artist and observed album text and a page size of 25. The HTTP transport received the status before the JSON parser or response projector ran. The historical response body, headers and request ID were discarded, so the origin service versus an upstream edge and the presence of a Retry-After header cannot be established. An earlier assessment also recorded a MusicBrainz 503. The catalog request ended after **five counted failures and eight provider calls**. That counter spans both providers. The final partial evidence still held one MusicBrainz recording candidate and no verified release track slot.

A disposable transport fixture reproduced the Discogs 500, then exercised both recovery and persistent failure. The candidate respects a valid Retry-After on Discogs 5xx responses and extends the shared provider cooldown when that header is available. Counted retries wait at least the existing exponential delay, stop after the existing five-failure ceiling, and preserve partial MusicBrainz evidence. Shared-budget deferrals do not consume failure attempts. The retained diagnostics add the HTTP status alongside the endpoint and parameters. Credentials and raw error bodies stay out of assessment evidence.

## Candidate measurements

Authenticated Rails requests on the same local test configuration and a synthetic archive of **293,000 observations** across 60,000 exact surfaces plus one detail fixture. Seven measured requests per route after one warm-up. Times are medians in milliseconds. SQL counts include uncached request queries and exclude transaction and schema instrumentation. Bytes are decoded HTML and exclude assets. Production storage and cache behavior can differ from this fixture.

| Route | Total before → after | SQL before → after | Queries | View before → after | HTML bytes before → after |
| --- | ---: | ---: | ---: | ---: | ---: |
| Resolution index | 575 → 399 | 569 → 390 | 4 → 4 | 1.7 → 0.9 | 12,885 → 12,226 |
| Unresolved filter | 587 → 400 | 581 → 391 | 4 → 4 | 2.6 → 2.8 | 12,927 → 12,268 |
| Observation detail | 51 → 44 | 42 → 36 | 14 → 14 | 1.2 → 1.0 | 10,361 → 9,503 |

The index aggregates exact observations before looking up filter state and skips decision joins for the unfiltered list. Filters evaluate decisions on attached surfaces and compare exact source text with null-safe equality. Detail obtains the observation count and visible IDs in a single pass, applies listener-effective decisions to that page, and reads only the fields displayed in assessment history. The candidate meets the proposed warm-fixture median budgets of **500 ms for the index and unresolved filter**, **100 ms for detail**, and **zero synchronous catalog-provider requests**. Production candidate latency remains unmeasured.

## Recording and release choices

The recording form saves only the recording decision. The existing background path may admit one justified contextual release or leave the release pending. After the recording is assigned, a separate release form offers distinguishable appearances for explicit verification using stored date, country or checked track-slot evidence where available. Tied labels are withheld, provider IDs remain in retained evidence, and complete track-list verification still gates admission. Alternative track-list modeling remains tracked in [Issue #23](https://github.com/harvj/muzeum/issues/23).

The matched desktop browser screenshots use synthetic observations and evidence.

- [Before · release control in the recording form](before.png)
- [Candidate · recording confirmation](confirm-recording.png)
- [Candidate · recording saved with insufficient edition evidence](release-pending.png)

Request and service tests cover listener scope, stale heads, append-only decisions, archive revocation, distinct release admission, and retry recovery and exhaustion without automatic decisions. The read-only production readiness check recorded **1,961 completed Last.fm import jobs** since the P1.4 deployment report, with zero unfinished or failed imports. Production remained at the baseline SHA.
