# Recording resolution policy

Status: **Authoritative principles; candidate algorithms and thresholds are not yet approved.** See [principles](principles.md) and [release assignment](release-assignment.md).

## Core contract

**REC-001 — Resolve observations to canonical recordings.** Last.fm artist/title/album text is evidence, not canonical identity. Multiple distinct observed strings may resolve to one recording. All compatible plays contribute to that recording's listening history and count. Distinct performances (studio/live, alternate take, remix) must not be merged merely because titles match.

**REC-002 — Keep recording and release decisions independent.** A play's canonical recording can stay fixed when its credited release changes. The recording can appear on multiple releases. Release credit does not determine which recording was heard.

**REC-003 — Suggest candidates automatically.** Muzeum should find and rank plausible MusicBrainz recording candidates for observed artist/title combinations, with retained historical Discogs provenance and MusicBrainz as the active external provider. Provide a clear path to review alternatives and correct any play or compatible group. A high textual similarity is not proof of identity.

**REC-004 — Evidence is multidimensional.** Consider reported MBIDs (verified, not blindly trusted), canonical artist/artist credit, normalized and original title, duration when reliably known, release/track context, version markers, neighboring listening context, and provider disagreements. Preserve contradictory evidence. A Discogs track listing alone cannot establish a specific MusicBrainz recording identity.

**REC-005 — Scoping prevents collateral changes.** A reusable assignment can cover many *compatible* observations, but not every row sharing a normalized title. Distinguish source MBID claims, exact/normalized artist and title, album context, version differences, and user-specific exceptions. Applying a surface assignment updates effective interpretations, never immutable source payloads. User-scoped decisions must not change other listeners' interpretations.

**REC-006 — Record assessments separately from decisions.** Persist provider identifiers, candidate sets or sufficient reproducible evidence, assessment version, reason, uncertainty, actor, time, and the scope affected. Reassessment may conclude 'no change.' Accepted and revised assignments form an append-only, attributable history; the effective mapping can be indexed for efficient reads.

**REC-007 — Automation starts conservatively.** Candidate suggestions can be broad. Automatic acceptance requires demonstrated precision and guardrails against contradictory evidence; no unvalidated numeric score or threshold is policy. Preserve unresolved/ambiguous states rather than manufacture a canonical match.

**REC-008 — Resolution is asynchronous.** Do not block Last.fm ingestion on catalog providers. Trigger bounded downstream investigation from new observations, changed metadata, corrections or provider evidence. Prevent provider outages from interrupting source capture.

## Last.fm surface identity and listener precedence

**REC-010 — Exact observed surface.** A Last.fm recording surface is the tuple of observed **artist string, album string, and track string**, including a missing album as a distinct value. Preserve the source text; do not make lossy normalization, source MBID claims, or a provider's release choice part of the authoritative equality rule. Matching and investigation groups may incorporate additional evidence, but must not silently redefine exact-surface identity. Explicitly version any future change to equality semantics.

**REC-011 — Persistent user surface assignment.** When a listener explicitly assigns an exact surface to a canonical recording, that decision applies to **all existing and future scrobbles** with that surface in the listener's authorized archive, unless a particular scrobble has its own explicit exception. Do not copy the decision to each event as an immutable fact; resolve inheritance through the effective query. A later listener-directed surface revision changes inherited interpretations, not source observations or protected per-play overrides.

**REC-012 — Individual scrobble exception.** The listener may explicitly assign a particular immutable scrobble to a different canonical recording even when its observed artist/album/track tuple matches other plays. This decision affects that event only. It survives regrouping, provider changes, algorithm revisions, historical reprocessing, later arrivals, and revisions to surface defaults. Only the listener can revise it or explicitly return it to surface inheritance. No automated process may overwrite a manual per-scrobble assignment.

**REC-013 — Precedence for effective recording.** For the authorized listener and observation, use (1) current explicit per-scrobble decision, including explicit unresolved; (2) current explicit user+surface decision; (3) current accepted automatic surface resolution under the user's scope/policy; (4) unresolved. A listener's explicit return-to-inheritance decision removes that layer's *effective precedence*, not its historical ledger entries. If the listener's surface assignment is explicitly unresolved, it masks an automatic default. A user can revise or release their own manual choices; automation cannot.

**REC-014 — Cross-user learning without cross-user authority.** Another listener's surface resolution may inform candidate ordering or confidence as separately labeled evidence. It is never itself a binding recording decision for the current listener. Do not expose another listener's private history, scrobble details, identity, or correction rationale through such evidence. A shared archive may have one reusable automatic assessment while distinct listeners retain independent surface defaults and event exceptions.

**REC-015 — Assessment is not authority.** New MusicBrainz, neighboring-listen, or cross-user evidence may generate a fresh assessment or suggestion, even contradicting an existing manual assignment. Record that disagreement without changing the protected effective choice. Changed evidence with unchanged choice need not create a new decision. Record actual changes and user confirmations/rejections as attributable, append-only events.

### Example: one surface, different recordings

The surface `Radiohead / The Bends / Fake Plastic Trees` is explicitly assigned by a listener to the studio recording. Friday's scrobble inherits that recording. The listener knows Sunday's identical surface was a live performance and explicitly assigns **Sunday's scrobble** to the live recording. When Muzeum later updates the surface assessment or the listener changes their surface default, Friday follows the current surface default while Sunday's manual live assignment remains untouched. The same surface for another listener receives independent interpretation; the first listener's choice is candidate evidence only.

## Future resolution decision journal (not P1.3a implementation)

**REC-016 — Explain meaningful decision points.** Eventually expose a listener-visible, durable review trail of new evidence, competing candidates, automatic decisions and reassessments, confidence changes, disagreement with protected manual choices, and user responses. Distinguish an actual change already applied from a **suggestion requiring confirmation**. Preserve evidence references, timing, actor, algorithm version, scope, reasons and outcome without leaking other listeners' private data.

**REC-017 — Explicit scope at confirmation.** A review prompt may offer **Apply to all** (establish or revise this listener's exact-surface assignment for inherited existing and future plays), **Only this time** (set an explicit per-scrobble override), and **Dismiss/defer** (no effective change; retain the review event). Applying to all never overwrites existing manual scrobble exceptions. Provide a separate action to return an exception or surface decision to automatic inheritance. User confirmation, dismissal, reversal and override are auditable; historical entries are not erased.

**REC-018 — Preserve future journal affordances now.** P1.3a needs durable, correctly scoped assessments, suggestions, candidate/evidence provenance, decision modes and histories that could support this UI later. **Do not build the interactive journal, notification feed, or its Apply-to-all/Only-this-time controls in P1.3a.** Schedule user-facing review and corrections in P1.3b or a subsequent numbered refinement after agreement on interaction design.

## Spotify compatibility (deferred)

**REC-009 — Support optional provider mappings.** One MusicBrainz recording may correspond to multiple Spotify track IDs, and a Spotify track ID is not the canonical identity. Record provider, identifier, match evidence and optionally a preferred playable equivalent with provenance. Spotify lookup, authorization and playlist export are later milestones. Muzeum playlists, when implemented, consist of ordered Muzeum recording references independently of Spotify.

## Example

Last.fm may deliver the same studio performance under multiple title spellings, with or without album text. If evidence supports the same canonical recording, aggregate the plays under that recording. If a similarly named live performance appears, treat it as a distinct candidate until established otherwise. Assigning one of those plays to a compilation for release-credit purposes must not change its recording.

## Open questions requiring evidence or user decision

- Automatic investigation-group compatibility and normalization beyond the authoritative exact artist/album/track surface tuple; group evidence may include MBID claims without redefining surface equality.
- Confidence representation, validation dataset, and automatic-acceptance thresholds.
- Handling recordings with multiple credited artists, covers, remixes, medleys and uncertain durations.
- Which MusicBrainz relationships and Discogs evidence are reliable enough to establish a collection's track-to-recording membership.
- How Spotify track matching and territory availability will work when implemented.

## Revision history

- 2026-11-19: Retired new Discogs API investigation under #26. Preserve prior Discogs evidence and record its original provider.

- 2026-11-17: Added persistent user-scoped exact-surface defaults, immutable per-scrobble manual exceptions, cross-user evidence boundaries, and deferred resolution decision journal with explicit action scope.

- 2026-11-17: Initial consolidated recording identity and candidate-resolution policy.
