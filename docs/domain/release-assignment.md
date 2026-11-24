# Per-play release assignment policy

Status: **Authoritative semantics; algorithmic thresholds remain open.** See [principles](principles.md), [recording resolution](recording-resolution.md), and [listening statistics](listening-statistics.md).

## Release listening context (v0.5.0)

**REL-001 — Membership defines the release history.** A recording can belong to multiple verified release collections. Each release contributes the distinct effective observations resolved to its member recordings regardless of the Last.fm album string. For multiple releases, count the union of observations. This history does not identify which edition played.

**REL-014 — Admission follows corroborated recording membership.** Confirmation may admit one supported original context when the recording has no verified membership in an admitted release. With a verified membership already present, confirmation admits zero new releases. Background enrichment from confirmation may update recording evidence and credits. Other releases require a separate catalog operation. Admission and ranking eligibility are independent. Reuse equivalent editions with matching ordered recording membership; check uncertain or conflicting collections separately and leave unresolved memberships pending. Keep the provider edition identifiers as evidence. Never recursively traverse the releases of imported tracks.

Recording identity, publication, collection membership, and source observation are independent. Lookup starts from the recording MBID and browses its release relationships within the existing provider budget. A checked official dated appearance may establish the earliest verified publication, even if it belongs to a different collection. Recording/session dates use separate evidence. An observed album caption may help discover candidates and never limits their publication history. A compilation or reissue can support an appearance without defining the original program. Equivalent original sequences have one representative. Materially different sequences require a choice. When evidence is incomplete, keep the history pending and preserve verified context already retained. Admit an edition-specific addition only for the recording being resolved.

For original-album construction, independent recording identity and verified edition appearances are separate evidence. Compare complete official editions at the release group's first publication date. Prefer an independently verified original sequence over an edition that appends bonus recordings. Equivalent sequences use a deterministic representative, preferring a supported artist-country match before presentation metadata such as format and packaging. Catalog the exact selected tracklist and retain its MusicBrainz release MBID in provenance. Conflicting original sequences require explicit selection. Later verified additions retain their own appearance and publication evidence.

**REL-015 — Keep source and interpretation separate.** Importing release tracks does not create observations. Preserve the immutable Last.fm input and effective recording override precedence. Each release retains its title, date and ordered tracks. Muzeum does not designate a primary release for listening attribution.

**REL-016 — Construct the musical collection from evidence.** Treat MusicBrainz editions as provenance for title, credits, dates, track order, and recording appearances. Construct the original published sequence when sufficiently supported. Retain additional edition tracks and their dates separately, without backdating additional recordings or inferring the edition played. Apply [STAT-003](listening-statistics.md#definitions) to release totals and retain the admitted membership regardless of the listener’s accounting preference. Resolve independent recording identity even while construction is pending.

Use one authentic representative release and copy its complete ordered source sequence. Each new slot retains the source recording MBID, track MBID, title, track duration, and recorded credits independently of the canonical recording it points to. Keep the representative release's source evidence even if a later decision maps another recording MBID to the same canonical recording.

Compare ordered musical tracks using source recording identity, titles, credited artists, durations, versions, and available corroboration. Distinct recording MBIDs are insufficient evidence of different music. Compatible matching metadata plus a shared ISRC or identical source track MBID can corroborate an equivalent comparison. A look-alike with insufficient corroboration stays uncertain. Retain competing original programs and uncertain matches as evidence. Additional edition tracks require a meaningful difference from the selected base. Representative selection weighs chronology, edition status, artist origin, country, and edition evidence together and leaves conflicts for review.


**REL-017 — Independent chronology.** Preserve recording date, canonical publication date, recording first publication, and specific edition appearances as distinct facts. Retain unknown dates and source precision, including ranges. A publication date cannot establish when a performance was captured.

The sections below describe the deferred per-play credit proposal. It does not govern v0.5.0 release histories or combined totals.

## Default evidence and chronology

**REL-004 — Surrounding listens are strong evidence.** Analyze neighboring plays in both directions, including chronological proximity, plausible duration/gaps, contiguous or nearly contiguous track positions, intervening songs, and shared release membership. A coherent sequence may outweigh an isolated recording's fallback release. A partial album sequence can suffice; do not require listening to a complete album.

**REL-005 — Source album metadata is evidence, not command.** Last.fm's reported album may reflect the listened collection and should inform defaults, particularly when neighbors corroborate it. It may be missing, inaccurate or inconsistent; do not force it over compelling contrary session evidence. Explicit listener selection is different from unverified source album text.

**REL-006 — Country-of-origin chronology.** When choosing a default release in the absence of persuasive listening context, prioritize the earliest qualifying appearance **in the artist's country of origin** rather than an earlier foreign release. Prefer a suitable original album collection over an earlier single when the song later appears on that album. Physical format/remaster is not the criterion. Do not silently choose a country for ambiguous artist origins; record uncertainty.

**REL-007 — Collections reflect experience.** A listener may credit a greatest-hits album or other compilation when that is what they experienced, regardless of the song's earliest appearance. Release identity is about song collection/ordering, not CD versus vinyl or remaster. Provider releases/masters/groups are evidence to reconcile, not unquestioned Muzeum identities.

**REL-008 — No arbitrary cutoff is yet established.** The exact time interval in which a later album supersedes an earlier single, and fallback when no domestic album exists, remain open. Do not invent a five-year rule or other threshold. Likewise, EP/album/compilation treatment requires explicit policy review.

## Background interpretation and history

**REL-009 — Confidence belongs to an assessment.** Every evaluation records the available evidence, competing release candidates, uncertainty/confidence, policy/algorithm version, actor and timestamp. New evidence can strengthen confidence without changing the credited release.

**REL-010 — Reassess affected context.** A background worker may reconsider a bounded neighborhood when later completed scrobbles arrive, a recording is resolved, source/provider metadata improves, or the listener changes a relevant assignment. Reevaluate nearby plays rather than repeatedly rescanning the entire archive.

**REL-011 — Changes require justification and stability.** Automatically revise effective credit only when new evidence materially supports a different candidate. Avoid oscillation between similarly supported choices. Numeric thresholds and cooldowns are implementation proposals to be validated, not established product policy.

**REL-012 — Append-only decision history.** Every effective assignment or reassignment records the prior and new credited release (including unresolved), actor (user or named worker), reason, evidence/assessment reference, time, and scope. Keep previous decisions. User-visible history supports reviewing, reverting and overriding. Restoring a past selection creates a new entry; it never erases later history. User overrides must never be silently overwritten.

**REL-013 — Reassignment is not a new play.** A change transfers release-ranking credit, including associated listening-time credit, without altering the immutable observation, canonical recording or recording play count. Rebuild derived statistics from current effective interpretations.

## Worked example: The Bends

A listener hears Radiohead's **High and Dry → Fake Plastic Trees → Bones** in order, with plausible gaps. This is strong evidence of an album sequence from *The Bends*, even if a standalone listen to *Fake Plastic Trees* might otherwise have a different default.

- Initially, each completed play may receive a provisional default.
- As subsequent plays arrive, a worker reassesses the small sequence and may credit those plays to *The Bends*.
- The assessment can change confidence without changing the effective credit.
- The listener may override one play to the *Fake Plastic Trees* single; that one play's credit changes, but its recording identity and play count do not.
- The override remains in effect across future automated reassessments unless the listener restores automatic management.
- Both *The Bends* and the single still show the recording's full listening history through membership.

## Open questions

- How to determine artist origin for collaborations, transnational acts, and uncertain country records.
- What qualifies as an album for the single-to-album preference; EPs, compilations, non-album tracks, and domestic-versus-foreign fallbacks.
- How to disambiguate multiple collections with near-identical tracks and different ordering.
- Minimum evidence for a session inference; time-gap, track-order and confidence thresholds.
- Whether and how a user can set an ongoing preference for future plays.
- Whether credit can be explicitly 'none' by user choice in addition to unresolved automation.

## Revision history

- v0.6.0: Clarified that edition evidence supports canonical release construction while recording, publication, and edition dates remain separate assertions.

- 2026-11-17: Clarified deliberate release admission, bounded full-tracklist enrichment and separation from per-play release credit.

- 2026-11-17: Initial policy for session inference, origin-country chronology, per-play credit and append-only reassessment.
