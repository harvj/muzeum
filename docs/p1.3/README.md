# P1.3a — Canonical recording resolution

**Status:** Implemented for a bounded assessment-only pilot in disposable development or staging data. The [P1.3b workspace and canonical library](workspace-and-canonical-library.md) use the manual ledger and effective reads. Production pilot execution and automatic acceptance are disabled. See the [live pilot report](live-provider-pilot-2026-11-17.md) for both catalog evaluations and review findings.

## Repository assessment

The deployed reference is P1.2 at `8942bc41ae76f3c4e3d63a20552b0541c5cd3412`. The local review began at `2b1706e`. The [P1.0 foundation proposal](../p1.0/foundation-and-data-contract.md) describes earlier plans, including superseded authentication and ownership assumptions. The current PostgreSQL contract is in [structure.sql](../../db/structure.sql), with the P1.2 account cutover and immutable lineage in the November migrations.

| Component | Finding | Disposition |
| --- | --- | --- |
| Last.fm import and access | `lastfm_account_id` identifies the shared archive. The legacy `scrobbles.user_id` is retained for lineage. `UserLastfmAccount` governs current user access. Source triggers preserve original observations and evidence. | Retain ingestion, IDs, raw pages, account associations and Auth OIDC. |
| [Resolver](../../app/services/scrobble_resolver.rb) and [runner](../../app/services/scrobble_resolver/runner.rb) | Reprocessing an unresolved row already attached to a surface increments `observed_count` again. The unique normalized-key index prevents duplicate keys but does not make the find/create/attach sequence atomic. The global key omits account and MBID claims. The runner still keys on the legacy username and user ownership and allows an unbounded run. | Replace the write path and runner. Preserve old assignments as historical evidence. |
| [Recording surface](../../app/models/recording_surface.rb) | Stores a mutable candidate array and chosen array index, no assessment or revision chain. Reordering the array can change what that index means. A global surface assignment can leak into unrelated accounts and a shared row has no place for independent listener corrections. | Leave legacy rows intact. Introduce versioned, archive-scoped grouping and separately scoped decisions. |
| [MusicBrainz client](../../app/clients/clients/musicbrainz.rb) and [search wrapper](../../app/services/musicbrainz/recording_search.rb) | HTTPS, request timeouts and a contact User-Agent are reusable. Search interpolates Lucene text, treats a missing envelope as empty, discards pagination metadata, and can constrain discovery to an unreliable observed album. The client handles 429 but treats documented 503 throttling as a generic invalid response. There is no shared budget, cache or durable retry. | Retain transport conventions. Replace the search wrapper and harden the adapter before downstream use. |
| [Candidate extractor](../../app/services/musicbrainz/release_candidate_extractor.rb) and [release ingestor](../../app/services/releases/release_ingestor.rb) | The extractor collapses editions by release group and heuristically disfavors some countries. The ingestor picks the first matching recording MBID from a track list or matches by title on an existing release. It fetches within a write transaction and bulk-updates every scrobble attached to the surface. The schema cannot represent one recording at two positions on one release. | Retire these paths from the new flow. Keep provider release and track relationships as evidence pending P1.3c. |
| Canonical entities and tests | Recording and artist MBIDs already have unique indexes. Legacy release ingestion may have populated recording titles and lengths from track-level fields. Existing fixture-backed service specs cover legacy behavior, including country preference and surface-wide writes. | Reuse verified artist and recording IDs. Review metadata before promotion and preserve the existing fixtures as provider examples. |

The repository demonstrates exposure to cross-user leakage through the legacy write path. This review did not measure production incidence. P1.2 import and routes do not invoke that resolver.

## Persistence and effective reads

| Relation | Purpose |
| --- | --- |
| `resolution_surfaces` | Archive-scoped, exact artist/album/title tuple. SQL uses a generated digest for indexed lookup and verifies exact text before membership and reads. SQL NULL and an empty album string have distinct keys. |
| `resolution_memberships` | One immutable membership per selected observation. An insert guard verifies the observation’s archive and exact tuple. |
| `resolution_groups` | Investigation signature of surface ID, compatibility version and source MBID claims. Grouping is independent of authoritative surface equality. |
| `resolution_assessments` | Append-only evidence, candidate IDs, uncertainty reasons, worker and evaluation version, request provenance, timestamp and an optional single suggested recording. Repeating equivalent evidence reuses the assessment by group/version/digest. |
| `resolution_decisions` | Append-only automatic surface, listener/surface and listener/scrobble streams. Rows carry the reason, mode, recording and assessment references where applicable, listener or worker actor, version, time and same-stream predecessor. Foreign keys, a unique no-branch predecessor index and scope triggers enforce the stream relationships. |
| `resolution_pilots`, `resolution_work` | Frozen archive and upper ID, selection cursor, counters, leases, retry due times and completion or terminal failure. |
| `resolution_provider_budgets`, `resolution_request_cache` | Shared provider cooldown and request spacing, plus size- and time-bounded projected request cache. |

`RecordingResolution::Ledger.effective(listener)` starts with the current OIDC user's active archive grants and returns scrobbles with `effective_recording_id`, `effective_recording_decision_id` and `effective_recording_mode`. Use normal Rails filters and keyset pagination on this relation. It checks the latest scrobble decision, then the listener surface decision, then the automatic surface decision. Explicit unresolved entries mask lower-priority layers. An inherit head releases that layer only. The lookup uses exact source text, so a future scrobble inherits even before pilot membership exists. Revocation takes effect on the next query.

`Ledger.record!` requires the authenticated listener, a scrobble from a currently granted archive, a scope (`:surface` or `:scrobble`), mode, reason and the expected current head ID (nil for a first decision). Pass a verified catalog recording for resolved entries and optionally an assessment from the same surface. A stale head fails without branching history. Returning to inheritance appends a decision. `Ledger.history(listener)` exposes only that user's authorized history and any shared automatic decisions. `Ledger.assessments(listener)` exposes only provider assessments from authorized archives. This version shares provider evidence within an archive and excludes other listeners' choices and private reasoning from candidate evaluation.

Successful suggestions may insert verified canonical recording and artist MBIDs or attach missing artist links. Existing IDs and metadata are preserved. Ordered credits with credited names and join phrases are retained in the assessment. Release relationships are evidence for identity corroboration and create no release membership or attribution writes.

## Running the bounded pilot

Use a disposable Rails development database with explicitly chosen observations and a separate Solid Queue database. Each invocation selects up to 100 observations by keyset; at most 1,000 observations, 100 groups, 300 MusicBrainz requests and 150 Discogs requests are allowed per pilot. The upper observation ID must already belong to the selected archive. The cutoffs are resource limits. Fixture mode uses deterministic synthetic catalog records, so use disposable databases where fixture recordings cannot be mistaken for real catalog entries.

```sh
export RAILS_ENV=development MUZEUM_RESOLUTION_QUEUE=1
export SOLID_QUEUE_CONFIG=config/recording_resolution_queue.yml
export SOLID_QUEUE_SKIP_RECURRING=true
# Set DATABASE_URL and QUEUE_DATABASE_URL to separate disposable databases.
bin/rails db:prepare
ARCHIVE_ID=<archive-id> UPPER_ID=<observation-id> bin/rails recording_resolution:start
# Start bin/jobs start in a separate terminal with the same environment.
PILOT_ID=<reported-id> bin/rails recording_resolution:dispatch
```

Replace the angle-bracket placeholders with numeric IDs. For a supported fixture result, seed an event for Night Lines / Night Drive / Signals with `FixtureTransport::IDS[:studio]` as the track MBID. Repeat dispatch for the same pilot to advance selection and recover due retries, expired leases or a failed queue handoff. Stop once selection is finished and no work is pending or leased. The normal failure ceiling is five attempts. Shared rate-budget deferrals use durable due times and do not consume that ceiling. Provider failures leave scoped, append-only partial assessments and a terminal work failure stays visible. After correcting the cause, start a fresh bounded pilot if replay is warranted.

The worker obtains a lease before provider I/O, rechecks ownership on each request reservation and at finalization, and records assessment and completion atomically. Cached results prevent throttled attempts from repeating completed requests. Neither provider is called from Last.fm ingestion. No production queue, jobs schedule or ingestion hook was added. Starting or processing a pilot in Rails production is blocked.

## Validation and migration evidence

The synthetic labeled corpus had **2 supported suggestions out of 2 emitted** (100% fixture precision) and **8 abstentions out of 10 cases** (80%). One intentional Discogs disagreement was observed and abstained. The corpus covers a valid redirect, an incorrect/missing MBID, missing album, a truncated search, indistinguishable candidates and studio/live/remix distinctions. These fixture metrics do not establish precision on real catalog data. No effective automatic decisions were emitted.

Both migrations are additive and registered in [the exact-hash manifest](../../config/deploy/migrations.json). An isolated PostgreSQL rehearsal loaded the pre-change structure, seeded 10,000 observations with legacy recording/surface references and applied both migrations. Before/after row digests matched for source observations (including fingerprints), legacy recordings and surfaces, users, archives and source tables. The new concurrent archive/ID index was valid and used for a 100-row keyset query. A second rehearsal included real importer-generated fetch, delivery, raw page and checkpoint lineage. The fixture job ran through the isolated Solid Queue worker, and a two-connection PostgreSQL run yielded one assessment from competing jobs. A production migration requires the established [deployment and recovery gates](../deployment/workflow.md).

## P1.3b workspace and library

The [implementation and readiness notes](workspace-and-canonical-library.md) describe the authenticated workspace, canonical pages, bounded catalog import and the remaining review questions. P1.3a's assessment-only pilot remains available for disposable catalog evaluation.

## Open decisions

- **Open — Automatic acceptance.** Review labeled real-catalog decisions and the operating precision/abstention target before authorizing writes. Consider conflicting claims across groups that share a surface.
- **Open — Discogs verification and retention.** The live pilots verified protected credentials, authenticated search, and bounded release-detail comparisons. Review the exact-match and edition-cap limitations and verify current endpoint limits and display obligations before display.
- **Open — Legacy interpretations and provider changes.** Review legacy assignments with incomplete actor provenance, MusicBrainz redirect chains and conflicting/existing catalog metadata. Provider aliases and broader compatibility need independent review.
- **Open — Release relationship policy.** P1.3c owns collection equivalence, chronology fallbacks and contextual release credit.

See the [provider contracts, credential setup and verification matrix](providers-and-verification.md).
