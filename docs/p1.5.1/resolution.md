# P1.5.1 Canonical resolution

[Issue #28](https://github.com/harvj/muzeum/issues/28)

## Production baseline

Measured 2026-11-20 at 01:44 UTC on `ddef753e1d2be2c1e3e99c3353dae9d22fcf9982` with a read-only PostgreSQL connection and a 30-second statement timeout. The reference archive contained all 292,999 production observations and had one active login-enabled listener grant. Effective assignment uses the listener ledger precedence. No production rows were written.

| Measure | Result |
| --- | ---: |
| Total observations | 292,999 |
| Effective recording assignment with an MBID and a recording catalog revision | 1 |
| Effective recording assignment without a valid recording MBID | 0 |
| No effective recording assignment | 292,998 |
| Unassigned artist/title claim groups | 51,999 |
| Observations whose exact surface has historical candidate evidence | 11 |
| Observations whose exact surface has a historical ambiguity flag | 0 |

The claim-group count folds case and collapses whitespace in reported artist and title, ignoring reported album. It measures text reuse. The candidate and ambiguity counts join exact surfaces to any stored assessment, so they are upper-bound coverage indicators across possible per-play ID-claim differences. An absent ambiguity flag means no stored finding. Production has no per-play release-credit relation, so a credited-release count is unavailable. Source album names and catalog release membership do not supply that denominator. There is no separately persisted artist-only observation decision.

Observation `292992` had one exact match, source artist and track MBID claims, no attached resolution surface, and zero groups, assessments, or investigation requests. The deployed GET only reads assessments. The old button creates the request in a POST. The observation had therefore never been investigated by this workflow. The claimed IDs still require verification.

## Candidate and review model

Use the existing exact-surface ledger for assignment scope. Reuse a completed assessment only for the same exact surface and source ID claims. Local identity lookup and cached MusicBrainz search can discover candidates across repeated textual claims. Edition evidence and scoring must use the particular observation context. Leave broader normalized-group reuse open until versions and compatibility can be reviewed.

Record deterministic ranking inputs and explanations in existing assessment JSONB, with the scoring version and assessment time. Use an ordinal point score for relative ordering. Verified claimed identifiers and checked edition slots are stronger signals than title or credit text. Version and identifier contradictions lower rank. Missing signals add no points and remain visible. Exact text can establish a candidate for review. Acceptance requires a listener decision or later independently approved policy. Confirming a candidate records the action automatically. Optional comments and historical reasons remain readable. Decision JSONB retains the structured action code, the previous assignment, scope, candidate scores and evidence references. No schema migration is planned for this revision.

Run new investigation through the bounded catalog assessment lease, request cache, and MusicBrainz budget. Schedule only authorized observation reviews. End the request independently of provider work. Reuse completed results and refresh deliberately. New production automatic investigation requires separate activation. Shadow evaluation may compare ranked candidates with reviewed assignments without writing effective assignments.

Compare against the previous local 293,000-observation budgets of 500 ms for the warmed median index and 100 ms for detail, with zero synchronous provider calls. Record actual candidate measurements separately. These budgets come from the [Issue #25 fixture](../p1.4/resolution/README.md).


## Local verification

Seven warmed Rails requests per route on 293,000 synthetic observations spanning 60,001 exact surfaces. The worker used projected MusicBrainz fixtures. It made no HTTP requests and wrote no assignments. These timings are local and are not production latency or provider throughput.

| Route | Median wall time | Median SQL time | Queries | HTML bytes |
| --- | ---: | ---: | ---: | ---: |
| Resolution index | 115.07 ms | 109.31 ms | 4 | 13,793 |
| Prioritized queue | 117.04 ms | 111.86 ms | 4 | 15,144 |
| Investigation pending | 9.02 ms | 2.55 ms | 17 | 9,413 |
| Ranked candidates | 10.26 ms | 2.47 ms | 17 | 12,780 |

The stubbed worker completed the first investigation in 8.31 ms and measured 292.8 completed investigations per second over 20 sequential fixture jobs. The latter is a local processing measurement with network and rate limiting excluded. Production provider dispatch remains limited to one MusicBrainz request per second across workers, with the existing request and retry limits and a one-day investigation lifetime. The search request cache can reuse equivalent searches across exact surfaces. Verification, release checks and score evaluation stay context-specific.

Run `bin/rails runner script/resolution_shadow.rb spec/fixtures/recording_resolution/shadow_cases.json` to reproduce the labeled simulation. Five synthetic cases exercise a verified studio version, indistinguishable titles, an alternate artist credit, a misleading source ID, and an unrelated record. The outcome was one correct recommendation, one false positive against the independently supplied label, one ambiguous case, one review required and one unsupported case. Confidence calibration and an automatic threshold remain open. The sample is deliberately adversarial and does not estimate population accuracy.


### Interface captures

Synthetic listening and MusicBrainz fixtures with bundled stone textures in Chromium.

- [Pending investigation, desktop](screenshots/pending-desktop.webp)
- [Ranked recommendation and confirmation, desktop](screenshots/ranked-desktop.webp)
- [Tied recordings, mobile](screenshots/ambiguous-mobile.webp)
- [Inherited resolved identity, mobile](screenshots/resolved-mobile.webp)

### Activation and remaining work

P1.5.1 uses existing catalog import, assessment, group and decision tables. It introduces no migrations. The new on-open workflow is gated by the existing catalog worker and `MUZEUM_RESOLUTION_INVESTIGATION=1` in production. Activating the latter is an operator decision after deployment review. Deliberate lookups remain available through the existing authorized catalog worker. The existing ingestion and catalog enrichment queues keep their subscriptions. No provider credentials or historical evidence are removed. In-app assessment detail keeps historical Discogs provenance and suppresses the historical comparison display.

The shortlist uses a bounded local lookup and a single bounded MusicBrainz search page, with recording identifier and edition checks where available. No listening duration is inferred. Independent corroboration, a reviewed real-world corpus, safe reuse across differing normalized source claims, separate artist-only assignments and calibrated acceptance rules remain open. The prioritized queue groups exact surfaces and uses frequency first. It does not bulk-enqueue its items. Pending results can be refreshed on the page. #21 remains deferred.


### Production activation

On November 20 UTC, the guarded workflow deployed `8e8a38d4f5a39b405bc2daec14c2e09a00dd93a7` with no pending migrations. On-open investigation was then enabled with a targeted Muzeum web restart. The existing catalog worker stayed running. Its subscription and heartbeats passed, and the three-minute post-activation queue check found 182 completed Last.fm jobs, zero unfinished and zero failed.

Opening observation `292992` produced one completed investigation, three MusicBrainz calls with zero counted failures, and one ranked candidate. The listener decision count stayed at one and the automatic decision count stayed at zero. The operational checks were scoped to Muzeum. [GitHub deployment history](https://github.com/harvj/muzeum/deployments)
