# v0.7.0 release-candidate review

The preview descends from published v0.6.10 at `ae19b1954b535c714209096b6d237518b3258f45`. The named observation IDs below identify the retained read-only production audit. Provider payloads were fetched from public MusicBrainz outside production and replayed using disposable Rails data. No production observations or decisions were written.

## Implemented and verified

- **Recording identity.** A MusicBrainz source ID resolves through the latest append-only source decision, with the existing exact canonical MBID as the fallback. Confirmation can link a source ID when the evidence corroborates the identity and the sources do not already point to separate canonicals. Clean and explicit labels require a provider edit relationship or verified same-date companion programs of the same release group. Companion programs must match in ordered positions and credits, contain an unchanged recording anchor, and have compatible labeled edits of the same published duration in whole seconds. A shared title and duration cannot establish a match. The journal stores source metadata and comparison evidence. Confirmation rechecks the mapping head, target, and catalog plan inside the transaction.
- **Identity revisions.** The reviewed operator service `RecordingSourceDecision.revise!` takes the source evidence, target recording, expected current decision ID, actor, and reason. Passing an explicit nil target to an existing alias creates or restores its own source recording. A revision cannot reassign the source MBID of an already separate canonical recording. It can update catalog slot pointers for that source ID. Slot source recording and track MBIDs and the tracklist fingerprint are retained. Historic listener decisions are untouched. The regression covers a stale preview, a revision, and separately cataloged sources.
- **Original collections.** Recording-first discovery follows bounded pagination and verifies complete official edition tracklists. If recording browse is incomplete but lookup has release references, Muzeum can verify the referenced original via its release group. The incomplete browse is retained as such and cannot establish first publication. A provider failure for a separate release group does not erase a verified album. A first-publication compilation may be admitted when complete evidence supports it and no original album, single, or EP context competes. It remains a compilation. A synthetic fixture verifies this bounded positive path.
- **Catalog construction.** A confirmation admits zero or one release. The selected, authentic source edition provides its complete ordered tracklist and per-slot recording and track IDs. Alternate editions remain evidence. The selected base determines additional tracks and their provenance. The recording-only path describes missing release evidence.
- **Listening policy.** All base tracks count. Additional-only tracks default to excluded and have a listener, release, and recording preference in the inline checkbox. The shared membership query drives indexes, rankings, detail totals, and histories. A recording’s own play count stays visible. Tests exercise duplicate memberships, representative changes, and preservation of the 13-track Guilt Show base.
- **Investigation lifecycle.** The five-state line reflects persisted work, with only the active state colored. Worker heartbeats, execution records, and observed capacity distinguish pending, busy, unavailable, blocked, and stalled work. Action Cable refreshes recover on reconnect and preserve valid choices. An invalid edition choice requires renewed review. A completed investigation with a supported recording has no standalone completion badge.

## Named regression results

| Case | Evidence and result |
| --- | --- |
| **Lady Wood · 293072, Don’t Talk About It** | The prior assessment lacked recording-first publication and checked construction evidence, and an earlier provider browse returned HTTP 503. The current public recording browse returned nine appearances. The replay verifies the album and official 12-track US CD. Chrome selects the clean ID, confirms one canonical recording and one authentic 12-track release, and preserves the submitted source ID and observation. |
| **Lady Wood · 293087, Cool Girl** | Replayed 49 explicit-recording appearances in two pages and the separate clean history. The companion programs corroborate the two source IDs even though their ISRCs differ. The release proposal uses a complete 12-track album sequence. The August 4 single remains separately verified as earlier publication evidence, and an injected single-group provider outage leaves the verified album available. |
| **Queen of the Clouds · 293095** | Two individually selectable Canadian editions share the 16-track program. The Worldwide 20-track program differs after 15 tracks. Chrome verifies the unified comparison, exact source selection, and preference reinstatement when the base changes. Canadian selection yields Love Ballad, Over, Out Of Mind - Bonus Track, and Paradise in the three-edition fixture. Worldwide has no additions in that fixture. Both align the same Hippie Sabotage remix at different positions. The separately replayed 17-track deluxe and 19-track Canadian launch editions remain supporting evidence. The 19-track edition adds two distinct recordings relative to Worldwide when its evidence is present. |
| **Walk ’em With Grace · 293004** | Retained production request 73 was imported with zero retries and no lease. Assessment 149 contained two plausible recordings. A request replay with the audited source IDs reproduces Needs review, with neither an active progress display nor a queued attempt. |
| **No Sunlight · 293082** | The retained production assessment and request/Chrome regressions protect the May 13, 2008 11-track Narrow Stairs program. The single, later expanded edition, and Time Warner 2 remain evidence rather than automatic admissions. |
| **Guilt Show** | Chrome confirms the authenticated 13-track original and separate Japanese edition track. Its checkbox adds three plays and 12 minutes to the release totals and ranking and persists across reloads. The track’s play count stays visible when excluded. |

[Lady Wood official US CD](https://musicbrainz.org/release/e3f12607-2004-448a-9a6a-421a8a59ee9b) · [Queen of the Clouds Worldwide edition](https://musicbrainz.org/release/1f21b9a1-0b81-4f3b-8b1b-3ff9e44a91ae) · [Desktop and mobile design evidence](../design/v0.7.0/README.md) · [Draft release notes](release-notes.md)

## Implemented but not fully verified on production

The new application has been verified with the retained production evidence and with disposable provider, queue, and browser replays. The upgraded production web and worker, installed preflight, signed Shell, fresh encrypted backup, and isolated four-database recovery are checked by the existing authorized deployment procedure. This preview does not change that procedure.

Provider coverage is bounded. An unavailable launch edition can still prevent a proposal if its program cannot be verified. The report distinguishes verified sources from unchecked or temporarily unavailable evidence. Solid Queue does not publish a guaranteed start time. A queue position is a snapshot only when eligible workers share a known order. Abrupt worker loss is inferred from leases and available queue records. The long-wait threshold defaults to 300 seconds and can be set with `MUZEUM_INVESTIGATION_QUEUE_WAIT_SECONDS`.

## Blocked by unavailable evidence

Uncorroborated source identities remain separate or require review. Some provider results omit credits, durations, or complete official tracklists. These cases can result in recording-only resolution. The candidate does not treat missing evidence as a verified release.

## Deferred outside v0.7.0

A browser interface for operator-led identity revision, bulk reconciliation of existing duplicate canonicals, and automatic rewriting of historical listening decisions are outside the milestone. No new worker, queue, monitoring platform, or deployment gate is introduced.

## Migration and operations

- `20261123230000` adds an empty additional-track listening preference journal.
- `20261123231500` adds nullable source recording ID, duration, and artist-credit fields to catalog track slots.
- `20261124030000` adds an empty source identity journal with a recording foreign key and a source/revision lookup index. A transaction-scoped advisory lock serializes source binding and canonical creation with confirmation.

A populated disposable database started from the v0.6.10 schema. All three migrations preserved its source observation, catalog slot, recording, and canonical decision. The older v0.6.10 app also read the upgraded copy under read-only settings. The three files have matching reviewed entries in the existing deployment manifest. The migrations add schema without backfill. Older track slots retain their recording-MBID fallback, and older application code can read the additive schema. Once v0.7.0 writes new preferences or identity decisions, roll forward to preserve their interpretation. Retain the upgraded schema during application recovery. Use the established Muzeum-only deployment and encrypted four-database recovery workflow after authorization.
