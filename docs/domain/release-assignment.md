# Per-play release assignment policy

Status: **Authoritative semantics; algorithmic thresholds remain open.** See [principles](principles.md), [recording resolution](recording-resolution.md), and [listening statistics](listening-statistics.md).

## Release listening context (v0.5.0)

**REL-001 — Membership defines the release history.** A recording can belong to multiple verified release collections. Each release contributes the distinct effective observations resolved to its member recordings regardless of the Last.fm album string. For multiple releases, count the union of observations. This history does not identify which edition played.

**REL-014 — Admission follows corroborated recording membership.** Confirmation queues verification of original MusicBrainz albums, singles and EPs that contain the exact recording. Reuse equivalent editions with matching ordered recording membership; check uncertain or conflicting collections separately and leave unresolved memberships pending. Keep the provider edition identifiers as evidence. Never recursively traverse the releases of imported tracks.

**REL-015 — Keep source and interpretation separate.** Importing release tracks does not create observations. Preserve the immutable Last.fm input and effective recording override precedence. Each release retains its title, date and ordered tracks. Muzeum does not designate a primary release for listening attribution.

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

- 2026-11-17: Clarified deliberate release admission, bounded full-tracklist enrichment and separation from per-play release credit.

- 2026-11-17: Initial policy for session inference, origin-country chronology, per-play credit and append-only reassessment.
