# Muzeum repository assessment and development plan

Original assessment: 2026-11-15. Updated for confirmed P1 decisions on the same date. The source inventory and comparative findings below remain useful; the roadmap and P1.0 contract supersede earlier proposals. P1.0 installed the pinned local runtime/dependencies and tested disposable databases; no application changes, production writes, push or deployment. See [P1.0 contract/schema proposal](p1.0/foundation-and-data-contract.md), [baseline results](p1.0/baseline-results.md) and [250k import plan](p1.0/import-requirements.md).

## Recommendation

**Confirmed: muzeum is the definitive application.** Use muzeus only as a reference for browsing, navigation, presentation, and reporting; no legacy database migration. Keep one Rails application and one authoritative listening archive. Do not transplant the older ingestion, identity matching, SQL model layer, or authentication wholesale.

This recommendation follows the code, not the relative ages of the projects. Muzeus is substantially closer to a usable personal music application. Muzeum has a more suitable separation between observations and canonical identity, database uniqueness constraints, transactional release ingestion, isolated HTTP clients, and meaningful service specs. However, its ingestion is not yet reliably idempotent, its historical preservation guarantees exceed what the code enforces, and it has no listening interface. Establish the P1.0 design/baseline, implement the 250,000-observation import foundation in P1.1, then deliver read-only history without waiting for complete metadata resolution. Local Muzeum authentication precedes browser resolution actions and is independent of Last.fm public-history access.

## 1. Repository inventory and evidence

### Source recovery and history

| Item | muzeus | muzeum |
| --- | --- | --- |
| Local source | `/Users/jim/Code/muzeus`, clean at inspection | `/Users/jim/Code/muzeum`, clean at inspection |
| Inspected HEAD | `a84203c8d0231642b2f88524c8551aaf1d5d7520`, 2023-05-22 | `3fa3e0a076699c4ff21967805984eb60f25c5b20`, 2026-01-30 |
| Reachable HEAD history | 125 commits; first commit 2016-11-18 | 50 commits; first commit 2026-01-12 |
| Local branches / tracking refs | `master`, `origin/master`, same HEAD | `main`, `origin/main`, plus ten Dependabot branches |
| Tags | `v0.002`, `v0.003`, `v0.003.3`, `v0.003.4` | None locally |
| Configured remote | `git@github.com:harvj/muzeus.git` | `git@github.com:harvj/muzeum.git` |
| Other source evidence | Initial local reflog says clone from `gitlab.com:harvj/muzeus.git` | Separate initial Rails history; no evidence of a shared implementation ancestry |
| Documentation | README is a short MusicBrainz mapper TODO | README, architecture notes, ops notes, three dated AI context documents |

Authenticated GitHub inspection found `muzeus/master`, returned its README, and returned the same latest three commits as the local source. Thus **the older source is recovered and GitHub currently serves it**. Repository search still reports size zero and private visibility; that size is not evidence that the Git objects are absent. GitLab is a historically evidenced remote, not a verified current backup. No changes to either remote were made.

Remote evidence: [muzeus HEAD](https://github.com/harvj/muzeus/commit/a84203c8d0231642b2f88524c8551aaf1d5d7520), [muzeus README](https://github.com/harvj/muzeus/blob/master/README.md), [muzeum HEAD](https://github.com/harvj/muzeum/commit/3fa3e0a076699c4ff21967805984eb60f25c5b20). Private links require account access.

GitHub branch results match the local inventory: muzeus has master; muzeum has main and dependency branches for bootsnap, brakeman, http, kamal, Rails, rspec-rails, solid_queue, thruster, web-console, and webmock. These are dependency updates, not hidden product implementations. The history includes muzeus's merged artist date-filter work and muzeum's deliberate removal of provisional canonical records (`f0e40c8`), later candidate tools, ingest logs, and forced MBID lookup. Tags and merged history provide recovery checkpoints; no separate unfinished product branch was discovered.

### Technology and operating requirements

| Area | muzeus | muzeum |
| --- | --- | --- |
| Runtime / framework | Ruby pin 2.7.7; Rails lock 5.2.6; Puma 3 | Ruby pin 3.3.5; Rails lock 8.1.2; Puma; Thruster |
| Persistence | PostgreSQL; application-specific materialized views | PostgreSQL/jsonb; primary plus production cache, queue, and cable databases |
| UI | Server-rendered ERB, Sprockets, SassC, Uglifier, will_paginate, local Font Awesome assets | ERB layout, Propshaft, base CSS and PWA stubs; no product controllers/views |
| Integrations | HTTP; Last.fm JSON; MusicBrainz; Spotify OAuth and playlist-listing connector | HTTP; Last.fm XML via Nokogiri; MusicBrainz JSON; no Spotify integration |
| Identity / access | Devise from Git source, OmniAuth Spotify; tokens stored on users | Last.fm user records; no implemented authentication or admin authorization |
| Tests | RSpec, VCR, WebMock, Timecop; 3 spec files | RSpec, WebMock, JSON fixtures; 10 spec files |
| Automation | Only base ApplicationJob; browser-triggered ingestion and rake tasks | Only base ApplicationJob; CLI ingestion/resolution/search/select/ingest; Solid Queue infrastructure |
| Delivery | No checked-in CI/deployment runbook found | GitHub Actions DB prep, RSpec, lint/security scans; Dockerfile/Kamal scaffold; local `bin/ci` omits RSpec |

Muzeus requires external connector secrets, Spotify credentials for OAuth, assets/native gems, PostgreSQL, and materialized views beyond `schema.rb`. `lib/tasks/db.rake` defines six views using DROP/CREATE without a clean bootstrap procedure. A schema load alone cannot recreate its runtime query dependencies. Its retained migration sequence also starts after its original tables; schema-based bootstrap must be assessed separately from historical migrations.

Muzeum import requires `LASTFM_API_KEY` and an existing Last.fm User (seeds supply a default). MusicBrainz uses a hard-coded identifying User-Agent; clients instantiate lazily, so ordinary browsing should not need provider credentials. Production needs database connection/secrets for its configured databases, Rails secrets, assets, and a queue worker if automation is enabled. `config/deploy.yml` contains a placeholder private IP and local registry, no active domain/TLS configuration, and a storage volume that does not back up an external PostgreSQL server. `docs/ops.md` says PostgreSQL 15.x while CI uses 16: choose and test one operating target. No actual host, domain, production database, backup, or deployed behavior was verified.

### Data model inventory

**Muzeus:** Artist, Recording, Release; ordered artist joins (`cardinality`) and release-recording membership (`position`); Play with timestamp, recording, release, optional user; MuzeusMatch and MatchRecording for string-to-recording lookup; Playlist/PlaylistRecording; Spotify-backed User. Schema also retains aliases and user_artists/user_recordings/user_releases without corresponding active model workflows. Personal color/category and rotation status are implemented primarily on global entities, despite user-specific tables. No raw upstream event store is present.

**Muzeum:** User, ImportRun, immutable-in-intent Scrobble, RecordingSurface, canonical Artist/Recording, Release, ordered credit and track joins, DailyListen. Scrobbles have nullable surface/recording links. Surfaces hold observed strings/MBIDs, candidates, selection index, resolution pointers, observation count, and a JSON ingest log. Releases retain representative release MBID and release-group MBID with partial date fields. DailyListen and user_timezones tables exist, but no aggregation service or timezone model/workflow exists. No active merge/alias/action-history subsystem exists. See [schema](../db/schema.rb), [models](../app/models), and [services](../app/services).

### Verification limits

This was static code/history/configuration inspection plus authenticated remote reads. `ruby -v` and `bundle check` fail because pinned Ruby 3.3.5 is not installed. Installed Ruby 3.4.8 can run Bundler, but a read-only `RBENV_VERSION=3.4.8 bundle check` reports missing locked dependencies. No dependencies were installed or lockfiles changed. Neither test suite, app, database bootstrap, nor provider interaction was executed. Existing spec names and assertions show coverage intent, not passing results. This paragraph describes the original assessment, not the later executable baseline. The initial Last.fm archive is now specified as approximately 250,000 scrobbles; resolution coverage and upstream completeness remain to be measured. No legacy database recovery is planned. See the P1.0 baseline for executed results.

## 2. Comparative feature matrix

“Implemented” below means there is a concrete code path, not a claim of runtime verification.

| Feature | muzeus evidence / behavior | muzeum evidence / behavior | Remaining work / recovery decision |
| --- | --- | --- | --- |
| Listening ingestion | `Connectors::LastFm#next_play`, `ApplicationController#lastfm`; oldest next play after global latest timestamp | `Lastfm::Importer`, parser, ImportRun; paged oldest outstanding history, unique user/timestamp insert | Keep new importer boundary; prove pagination, retries, overlaps, gaps, failures, multi-user behavior |
| Source preservation | Stores resolved Plays; no raw payload; can manually create or expand one observation into several Plays | Stores parsed source fields and timestamp as jsonb, nullable canonical links | New payload is **not verbatim upstream data**; retain original response/event going forward; do not fabricate old payloads |
| Artist/recording identity | MBID-backed entities, ordered many-to-many artist credits | MBID-backed canonical entities, positioned credits, role/weight fields | Keep canonical boundary; validate required MBIDs and credits; repair associations |
| Releases and tracklists | Release MBID, partial dates, position membership; repeated same recording collapsed | Representative release plus group IDs; flattened multi-disc positions; video skip | Decide edition versus group semantics; support repeated recording occurrences and explicit release context |
| Last.fm integration | JSON connector, default hard-coded listener, config through secrets | XML client, timeouts, selected HTTP errors, API-key redaction, parser skips undated now-playing during insert | Handle API error envelopes, invalid XML, timestamp validation, late events, restart/concurrency |
| MusicBrainz integration | Query/get/import services, mappers, browser release import | Pure I/O client, search/extractor, database-aware candidates, CLI select and ingest; forced recording lookup | Reuse new pipeline; add provider pacing/retries, query escaping, redirect/invalid-ID behavior |
| Reconciliation | MuzeusMatch lookup strips remaster/version text and whitespace; remembered mappings can target multiple recordings | Conservative surface normalization; candidates grouped by release group; human CLI choice; canonical creation | Preserve ambiguity; use legacy matching behavior only as a reference; version new decisions and their evidence, scope and actor |
| Enrichment | Import release tracklist and credits; personal category propagation | Fetch release and create artists/recordings/joins; partial dates; ingest log | Reuse new clients/fixtures; explicit refresh policy, recording-vs-track metadata, incomplete releases, multiple secondary types |
| Browse/navigation | Artist/release/recording index/show, plays, cross-links, pagination, playlists, forms | Only `/up` route and base controller/layout | Recover older ERB structures and navigation progressively with new query services |
| Search/filter/sort | Name search on artists/recordings, category/status/year, artist/release, duration, ranks, date/hour/day/month/year/DOW filters; not all consistent across screens | None user-facing; provider search only | Start date range and observed artist/track search; then canonical filters; validate and bind all query input |
| Statistics/history | Counts/durations, first/last play, overall and filtered ranks/tier badges; yearly charts and release-year distribution | DailyListen schema/model only | Recover definitions and visual patterns; implement verified user-scoped queries; report unresolved coverage and missing duration |
| User workflows | Manual match, release import, metadata/category edit, manual Plays, Spotify sign-in, partial playlists | CLI-only operations; no end-user/archive workflow | Read-only timeline first; protected resolution workbench later; no synthetic scrobbles |
| Jobs/scheduling | No domain jobs or checked-in scheduler | Queue adapters/config and cleanup schedule, no ingestion/aggregation jobs | Add per-source-account serialized resumable import after correctness; shared application rate limiter; no separate services |
| Persistence/integrity | Mostly model validations, few DB uniqueness guarantees, no schema foreign keys; materialized views depend on global data | Unique canonical MBIDs, surface key, user/time, joins; many FKs; transaction around release ingest | Fix retry paths, missing scrobble-user and ingested-release FKs, destruction rules; audit data before adding constraints |
| Schema transition | Legacy database is out of scope | Existing muzeum records need an additive account/provenance transition | Preserve muzeum IDs, payloads and lineage; no legacy import or crosswalk |
| Testing | Three older connector/service specs; assertions reference older method names/classes | Ten specs cover clients/parser/importer/resolver/extractor/ingestor/logger/models; no request/system/aggregation coverage | Establish executable baseline; strengthen invariant tests before UI mutations |
| Deployment/readiness | Older runnable-looking UI but no reproducible deployment evidence; auth presence does not gate all mutators | CI/container infrastructure but no application home, admin guard, domain configuration, or proven restore | Private staging, restore drill and read-only release before public cutover |

Primary legacy recovery sources: `../muzeus/app/views/{plays,artists,releases,recordings,shared}`, `app/helpers/application_helper.rb`, `app/assets/stylesheets`, `app/query`, and the reporting methods in `app/models`. Primary new evidence: [routes](../config/routes.rb), [importer](../app/services/lastfm/importer.rb), [resolver](../app/services/scrobble_resolver.rb), [ingestor](../app/services/releases/release_ingestor.rb), [extractor](../app/services/musicbrainz/release_candidate_extractor.rb), [specs](../spec), and [CI](../.github/workflows/ci.yml).

## 3. Architectural assessment

### Retain

- **Immutable observed events, mutable interpretation.** Keep source account/time/content separate from scoped, versioned canonical interpretations. Relinking identity is legitimate; rewriting what Last.fm reported is not. State this distinction precisely in the architecture contract.
- **Surfaces before canonical entities.** The current code correctly stopped manufacturing provisional Recordings. Keep unresolved observations useful in the UI. Do not restore obsolete confidence/status buckets merely to match older design notes.
- **Conservative normalization.** Keep album context and punctuation. Muzeus's removal of “version”, “remaster”, and whitespace can erase meaningful recording differences. Its mappings may suggest candidates but must not silently authorize canonical identity.
- **Pure clients and service orchestration.** Keep new provider adapters independent of persistence. Retain release ingestion's transaction boundary, MBID uniqueness, and explicit candidate choice.
- **Legacy interaction design.** The older archive's cross-links, ranked lists, filters, compact tables, partial dates, artist ordering and yearly charts are useful specifications and recoverable presentation code. No architectural benefit comes from redesigning them all first.
- **Rebuildable summaries.** DailyListen must remain derived state, never a prerequisite for displaying raw history or the owner of historical truth.

### Revise before depending on the guarantees

1. **Payload preservation is overstated.** `RecentTracksParser` selects fields and strips text; Importer stores that parsed hash, not the original XML. There is no model or DB protection against source-field edits/deletes. Keep existing payloads unchanged and label their provenance honestly; preserve raw source on future imports using an explicit representation. Archive upstream response evidence separately if byte-level preservation is required.
2. **Resolution is not idempotent.** Resolver returns early only for a non-null recording. An unresolved scrobble already attached to a surface is processed again and increments observed_count; Runner repeatedly selects those rows. Its existing “already resolved” spec checks entity counts, not observed_count. Separate surface assignment from canonical assignment, count unique linked events, and make concurrent attachment atomic. Surface strings/MBIDs currently represent the first normalized observation, not every exact spelling/MBID claim; individual scrobbles must retain the differences. Normalize nil/blank albums safely.
3. **Release ingest retries can fail.** New-release ingestion uses `create!` for track and artist joins. Repeating the same in-memory candidate (or ingesting a different release sharing recordings) can violate unique indexes. A second freshly searched candidate may take the existing-release shortcut, hiding this failure. Test both routes, shared recordings, rollback, and concurrent submissions.
4. **Existing-release matching still uses title.** `ingest_existing_release!` chooses a case-insensitive title match and dereferences canonical.id without handling no match. The new-release path uses matched recording MBIDs but takes the first match if several are present. Require one verified recording identity or explicit ambiguity, never guess. A selected release containing no matching audio recording must produce a controlled outcome with no partial mutation.
5. **Release identity is unsettled.** README promises edition-level releases and country dates; January 16 notes explicitly choose conceptual release groups; current extractor groups by group and reuses a representative edition, while schema uniqueness is on edition MBID. This is a hybrid. Recommended near-term contract: stored Release is a concrete selected MusicBrainz edition; release_group_mbid enables grouping/navigation, not equivalence. Choosing another edition must not silently reuse a different tracklist. If conceptual albums are desired later, introduce a grouping layer rather than changing historical release meaning. This decision needs owner sign-off before schema work involving tracks or release summaries.
6. **Track occurrence differs from recording identity.** Unique `(release_id, recording_id)` prohibits the same recording appearing twice on a release. Flattening media and excluding video loses original numbering. Model track occurrences with release/medium/position identity, source track ID/title/duration, and canonical recording reference. Keep display flattening as presentation. Track title/duration should not overwrite recording-level facts; preserve ordered credit text/join phrases and avoid treating edition context as canonical recording metadata.
7. **Associations and deletion undermine preservation.** Artist.releases, Recording.releases and Release.recordings lack their intended `through` declarations and carry destructive dependent rules. Recording destroys surfaces; User destroys scrobbles. RecordingSurface still references removed IngestEvent. Correct relationships and prefer restricted deletion for historical facts. Add missing FKs only after auditing existing rows. Canonical presence validation alone does not prevent bulk inserts with null MBIDs.
8. **Release attribution must be explicit.** A recording can belong to several releases. Muzeus's reporting joins can credit one play to every release containing its recording. Muzeum has surface.ingested_release_id but no historical per-event release-resolution record. Preserve selected release context and distinguish “heard on this release” from “recording appears on this release”; never sum memberships as independent listens.
9. **Derived statistics need semantics.** Define per-user scope, historical timezone/day boundaries, DST, artist credit allocation, unknown durations, and selected release attribution. Legacy code mixes Chicago and Los Angeles timezones and a four-hour day offset. Do not silently import these rules. Show total event count alongside canonical coverage; a canonical-only summary must not appear complete.
10. **Operational state needs durable boundaries.** Importer uses maximum played_at as its cursor; that cannot repair older gaps or capture late older events. Unique user/time suppresses collisions without identifying differing payloads. Define overlap/replay and collision reporting. Handle Last.fm error envelopes, invalid timestamps and failures before ImportRun initialization; serialize imports per user. Fetch provider data before holding long DB transactions where practical, then atomically apply validated results. Persist failed attempts outside rolled-back ingest logs.

The guarantee “a user cannot have two scrobbles at the same timestamp” is an existing assumption, not proven upstream identity. P1 proposes account-scoped exact source fingerprints, preserved differing observations and explicit collision handling; see the P1.0 contract. Raw JSONB also cannot preserve byte-for-byte formatting; distinguish semantic source preservation from exact response archival.

### Discard or defer

Discard generated Plays, guessed successive recording IDs, selecting `recording.releases.first` as listening context, GET routes that mutate data, broad string equivalence, and global materialized-view refreshes per play. Do not copy interpolated legacy SQL, in-memory array pagination, or its globally scoped statistics into public query endpoints. Re-express useful formulas with validated parameters, user scope and database pagination.

Defer Spotify login/playlists, custom rank tiers, personal categories, automated merges, elaborate confidence scoring, and a generalized event-sourcing platform. No legacy database recovery is planned; any future personalization is new work based on demonstrated value. Reuse Font Awesome assets only after checking their redistribution license; simple text controls are enough initially.

### Documentation precedence

The January 19 “strict” plan describes provisional Recordings and a confidence-based resolver that the subsequent migrations removed. January 30 describes a working pipeline, but its completeness claims are not supported for retries, no-media ingestion or existing-release identity. `data-model.md` still describes removed status/confidence/merge columns. Preserve these documents as history and write a current contract referencing code/tests; do not treat every historical “locked” statement as simultaneously binding. January 30's token-in-query/no-auth proposal is superseded: users authenticate directly with Muzeum, Last.fm is a public source account, and browser resolution actions require server-enforced user/account permissions. Shared assertions and user-specific interpretations have distinct scope and actor attribution. CLI import and public read-only browsing must not wait for authentication.

## 4. Development strategy comparison

| Approach | Benefits | Costs / integrity risks | Judgment |
| --- | --- | --- | --- |
| 1. Continue muzeum; selective recovery | Keeps source/identity separation and focused service tests; reuses old UI concepts, assets, filters and formulas; small reviewable increments | Must repair ingestion and build query/UI layer; cannot claim feature parity immediately | **Recommended**; best fit for one developer and Codex |
| 2. Move substantial muzeus implementation | More screens appear quickly; much existing Rails/ERB code | Old controllers couple ingestion, identity and synthetic plays; models depend on global materialized views, old columns, timezone assumptions and Rails APIs; transplant requires extensive adaptation and regression work | Recover presentation selectively, not the application core; bulk migration is likely more work than bounded adaptation |
| 3. Change application boundary | Upgrading muzeus could preserve its workflows; a read-only legacy reference might help validation | Upgrade plus source-preservation redesign; dual apps duplicate operations and require cross-database identity synchronization; muzeus cannot safely become writer to new tables unchanged | Closed by confirmed decision: muzeum is definitive; no second production app or legacy database migration |

Use muzeus as a pinned presentation/reporting reference and behavior catalogue only. Do not import its database or remembered identity mappings. Keep a recovery ledger linking each ported feature to its old paths/commit and its new acceptance test. Direct reuse is appropriate for small ERB/table/chart/CSS fragments after adapting names and reviewing dependencies. Query formulas are specifications to verify, not SQL to paste. Shared extraction libraries and services are unnecessary at this scale.

## 5. Numbered implementation roadmap

This replaces the original seven-milestone proposal. Confirmed direction: no legacy database migration; approximately 250k source observations; immutable/inspectable source, independent bulk import, compatible surfaces, evidence-based incremental resolution with versioned decisions and independent human/process attribution. Authentication is local to Muzeum, not Last.fm OAuth. P1.0 design work is authorized; subsequent implementation requires proposal review.

### 1. P1.0 — Foundation, executable baseline and data contract

**Status:** baseline executed and design deliverables prepared for review. No schema/pipeline/auth changes implemented.

**Dependencies:** current source, pinned Ruby/locked gems, disposable PostgreSQL; no real listening archive or production access required.

**Work/results:** installed Ruby 3.3.5/Bundler 4.0.3/locked gems; schema load and migration replay agree; 49 existing examples pass on each; lint/eager loading/Brakeman pass; dependency audit fails with 237 scanner findings across 22 gems. Fixture diagnostics confirm false confidence in current retry/count tests. Documents compare the real model with the proposed account, source, scope, assessment and decision schema and propose benchmark gates.

**Acceptance:** reproducible original results and failures retained; explicit data-preserving muzeum transition; evidence/scope/actor constraints; 250k import acceptance plan; reviewed P1.1 sequence. A clean security audit or repaired pipeline is not claimed as a P1.0 result. The design review can complete despite known defects being explicitly assigned to implementation.

**Risks/decisions:** review source fingerprint/collision policy, raw storage budget and compatible/cohort scope applicability; identify actual existing muzeum data before a future migration. Detailed [contract/schema](p1.0/foundation-and-data-contract.md), [baseline](p1.0/baseline-results.md), [import requirements](p1.0/import-requirements.md).

### 2. P1.1 — Account/provenance transition and reliable bulk import

**Dependencies:** P1.0 schema/identity contract review; isolated test environment; backup/restore plan before touching existing muzeum data. No Last.fm user credentials, MusicBrainz, human login, surface assignment or canonical resolution required.

**Implementation slices:**

1. Add failing invariant tests and account/provenance migrations. Retain existing User IDs, create LastfmAccount and unverified user/account associations, backfill scrobble/import account links in bounded resumable batches. Inventory/checksum existing muzeum rows before switching event identity. No synthetic emails/passwords or fabricated historical raw XML.
2. Implement immutable raw-page capture and source observations; account-scoped versioned exact fingerprints, differing-metadata/timestamp collision evidence and bounded bulk writes. Replace old time-only uniqueness in a coordinated writer cutover after reconciliation. Preserve all received raw evidence and first-observation content.
3. Implement fixed-bound pagination/windows, overlap/replay, per-account serialization, application-wide pacing, atomic checkpoints and bounded progress/failure reporting. Trusted CLI/worker acts under a registered process identity and explicit source-account grant. No per-event DB callback loop, growing per-run JSON log or downstream metadata work in import.
4. Execute 250k cold/replay benchmarks and crash/collision/network regression fixtures; publish measurements, corpus hashes, source/checkpoint checksums and limits. A separately authorized live-source run validates provider timing/boundaries after local gates pass.

**Acceptance:** 250k local pipeline ≤120s proposed gate; DB ceiling ≥5k observations/s; RSS ≤512 MiB with bounded growth; replay creates no duplicate source rows or source edits; independent manifest reconciles all input/invalid/conflict counts. A restart cannot advance the checkpoint ahead of committed data. Changed upstream observations are retained/reported rather than overwriting historical facts. No provider calls other than Last.fm and no surface/canonical prerequisites. Review/calibrate proposed timing gates from recorded measurements, not assumptions.

**Risks:** upstream has no documented durable event ID; indistinguishable same-second duplicates and historical provider edits require explicit uncertainty. API pacing/duration is not a DB throughput test. Raw-page storage is measured. Account association is not provider ownership. Existing production-sized muzeum data remains unknown; no production changes are authorized by P1.0.

### 3. P1.2 — Useful read-only source archive

**Dependencies:** P1.1 source/provenance contract and representative data; explicit public source/history visibility and display timezone. Authentication is not a prerequisite for the public catalogue or approved public-history pages.

**Work:** root timeline with database keyset pagination, date range and observed artist/track search; show unresolved/colliding observations and raw provenance through appropriate inspectable views. Recover compact tables, navigation and chart concepts from muzeus as useful. Add canonical cross-links opportunistically, never hide unresolved history. Show imported range, freshness, pending collisions and canonical coverage. Private user notes/associations/interpretations are not exposed through public source browsing; private views wait for authenticated access.

**Acceptance:** 250k browse query plans retained; 100-row page p95 <200ms proposed target; no N+1 queries, full-Ruby-array pagination or provider dependency. UTC/DST boundaries, stable pagination, invalid filters, unresolved rows and two-account scope tests pass. An independently inspectable event shows original metadata separately from current interpretation. No browser write routes.

**Risks/decisions:** distinguish public Last.fm source from a person's private Muzeum annotations; decide what raw response fields to display. Do not claim a conflicted observation count is a verified listen total. Make useful data visible without waiting for canonical completeness.

### 4. P1.3 — Local authentication and scoped, versioned resolution

**Dependencies:** P1.0 resolution schema review; P1.1 account/source identities; tested auth/session and authorization policies **before any browser resolution actions**. CLI-based ledger tests may precede UI. Triage dependency audit and apply reviewed compatible updates with regression checks before exposing authenticated writes.

**Sequence:**

1. Adapt Rails local email/password/session patterns to retained Muzeum Users; provision accounts explicitly; implement server-side account/import/resolution grants, session revocation and CSRF checks. No Last.fm authentication, credentials or OAuth. Unverified account associations remain labeled unverified.
2. Add actor, scope, immutable assessment/evidence and decision revision tables; current-head FK/index; compatible signature filters, frozen cohorts and individual exceptions; stale-head/idempotency checks. Snapshot existing muzeum pointers as unverified current-baseline evidence, not invented historical decisions.
3. Correct surface-attachment/count behavior and canonical join/retry/MBID-matching defects, then route enrichment through assessments/decisions. Shared canonical assertions require approved curator/process authority. Ordinary user correction only changes that user's scoped interpretation. Retire global surface mass relinking as authority.
4. Add protected feedback/review/search/select/defer/ingest workflow with evidence, impact preview, revision reasons and decision history. Resolve edition/track occurrence semantics before claiming accurate tracklists/release context. No automatic ambiguous match or silent target selection.

**Acceptance:** one decision chain can serve thousands of compatible observations; different MBID claims do not inherit blindly; an individual/cohort exception affects only its recipients/user. Reevaluation can append evidence without new decisions. Ambiguity blocks assignment; explicit unresolved overrides do not fall through. Cross-user writes, spoofed actor IDs, revoked grants, stale forms and unauthorized shared edits are rejected. Real repeated ingestion, concurrent assignment and shared-recording cases pass. As-of decision/recipient/actor/evidence reconstruction is deterministic; current lookup is indexed. Original source checksums remain identical.

**Risks/decisions:** reusable surface evidence versus event-specific evidence; scope overlap/conflicts; curator permissions; metadata snapshot versus current labels; local account provisioning/reset. No generalized event-sourcing framework or redundant per-observation revision copies.

### 5. P1.4 — Verified reporting, automation and release readiness

**Dependencies:** stable account/source contract, tested scoped current/history resolution, chosen timezone/credit/release attribution, completed dependency remediation appropriate to exposure. Deployment remains a separately approved action.

**Work:** rebuildable scoped DailyListen aggregation; counts/durations/first-last listens and initial ranks/yearly charts adapted from legacy behavior. Explicit unresolved/unknown-duration/collision coverage. Per-account scheduled import through the same tested service with pacing/checkpoints. Rehearse isolated build, backups/restores, monitoring and rollback before a future muzeum.fm release; inspect hosting separately without changing deployment configuration in P1.0.

**Acceptance:** direct source+effective-resolution queries equal derived statistics; replay/revision updates affected old and new identity scopes; user corrections do not alter another user's summaries; no release-membership double count; DST/multi-credit/shared-account fixtures pass. Worker restarts/outages resume safely; import health visible. Read-only app boots without provider credentials; restore drill and proposed cutover checks documented. Public deployment/domain changes require explicit approval.

**Risks:** mixing source observations with verified event counts, stale aggregates, metadata fan-out and provider drift. Defer Spotify, playlists, personalized tiers/categories and broader catalogue work until this useful archive is reliable. No legacy data/parity migration gate.

## 6. P1.0 deliverables and next implementation proposal

The original “repair ingestion first” implementation proposal is superseded by a design-only P1.0 followed by reviewed P1.1. Deliverables:

1. [Executed baseline and reproduction](p1.0/baseline-results.md), including original advisory failures and fixture diagnostics; no application corrections were needed to run checks.
2. [Current/proposed data comparison](p1.0/foundation-and-data-contract.md#2-current-versus-proposed-model).
3. [Concrete additive schema proposal](p1.0/foundation-and-data-contract.md#4-concrete-relational-proposal) for users/accounts, immutable observations, evidence, scoped decisions, exceptions and current/history lookup.
4. [250k benchmark and idempotency regression plan](p1.0/import-requirements.md), distinguishing DB, local pipeline and network timing.
5. P1.0–P1.4 roadmap above, with dependencies, risks and acceptance criteria.
6. [Recommended P1.1 implementation sequence](p1.0/foundation-and-data-contract.md#6-recommended-p11-sequence-and-review-decisions).

P1.1 proposal: implement the account/source-provenance transition and reliable bulk import in small tested slices, beginning with additive schema and immutable-source fixtures. Do not implement the whole resolution ledger or browser authentication before source import. Do not publish performance claims until the 250k benchmark has run. Existing ingestion/resolution defects are recorded; no product behavior was changed in P1.0.

## 7. Remaining review decisions

| Decision | Proposed default | Gate |
| --- | --- | --- |
| Source fingerprint and collisions | Exact account/time/name tuple; preserve changing evidence; flag uncertainty, never silently drop/overwrite | P1.1 migrations/import |
| Raw evidence retention | Compressed immutable raw pages plus event locators; preserve old parsed-only records honestly | P1.1 storage budget |
| Existing muzeum data transition | Backup, inventory, keep User/scrobble IDs and original payloads; associations unverified | Before schema/data changes |
| Source visibility and import grants | Public read-only only by explicit policy; CLI allowlist/process actor; authenticated association-based browser permissions | P1.1/P1.2 |
| Authentication/provisioning | Local Muzeum credentials/sessions; explicit provisioning; Last.fm remains public source | Before P1.3 browser writes |
| Reusable rule vs cohort | Reusable only with compatible evidence; manual event-specific fixes default frozen cohort | P1.3 |
| Shared assertions vs personal correction | Approved curator/process authority for shared assertions; ordinary correction stays user/account scoped | P1.3 |
| Release/track identity | Concrete edition, group navigation, repeated track occurrences | Before P1.3 canonical ingest refinements |
| Historical reconstruction | Versioned decision/recipient/evidence history; metadata snapshots for old display labels | P1.3 |
| Timezone/credit/duration semantics | Explicit IANA zone, unknown duration coverage, selected release context | P1.2/P1.4 |
| Audit remediation and operations | Reviewed dependency updates; isolated release/restore rehearsal; no deployment changes now | Before authenticated exposure/release |

Muzeum's definitive role, no legacy database migration, public Last.fm access without OAuth, first-class local users, immutable observations and versioned scoped resolution are confirmed requirements, not open questions.
