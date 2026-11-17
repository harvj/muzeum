# Recording resolution policy

Status: **Authoritative principles; candidate algorithms and thresholds are not yet approved.** See [principles](principles.md) and [release assignment](release-assignment.md).

## Core contract

**REC-001 — Resolve observations to canonical recordings.** Last.fm artist/title/album text is evidence, not canonical identity. Multiple distinct observed strings may resolve to one recording. All compatible plays contribute to that recording's listening history and count. Distinct performances (studio/live, alternate take, remix) must not be merged merely because titles match.

**REC-002 — Keep recording and release decisions independent.** A play's canonical recording can stay fixed when its credited release changes. The recording can appear on multiple releases. Release credit does not determine which recording was heard.

**REC-003 — Suggest candidates automatically.** Muzeum should find and rank plausible MusicBrainz recording candidates for observed artist/title combinations, with Discogs as additional release/track-list evidence. Provide a clear path to review alternatives and correct any play or compatible group. A high textual similarity is not proof of identity.

**REC-004 — Evidence is multidimensional.** Consider reported MBIDs (verified, not blindly trusted), canonical artist/artist credit, normalized and original title, duration when reliably known, release/track context, version markers, neighboring listening context, and provider disagreements. Preserve contradictory evidence. A Discogs track listing alone cannot establish a specific MusicBrainz recording identity.

**REC-005 — Scoping prevents collateral changes.** A reusable assignment can cover many *compatible* observations, but not every row sharing a normalized title. Distinguish source MBID claims, exact/normalized artist and title, album context, version differences, and user-specific exceptions. Applying a surface assignment updates effective interpretations, never immutable source payloads. User-scoped decisions must not change other listeners' interpretations.

**REC-006 — Record assessments separately from decisions.** Persist provider identifiers, candidate sets or sufficient reproducible evidence, assessment version, reason, uncertainty, actor, time, and the scope affected. Reassessment may conclude 'no change.' Accepted and revised assignments form an append-only, attributable history; the effective mapping can be indexed for efficient reads.

**REC-007 — Automation starts conservatively.** Candidate suggestions can be broad. Automatic acceptance requires demonstrated precision and guardrails against contradictory evidence; no unvalidated numeric score or threshold is policy. Preserve unresolved/ambiguous states rather than manufacture a canonical match.

**REC-008 — Resolution is asynchronous.** Do not block Last.fm ingestion on MusicBrainz or Discogs. Trigger bounded downstream investigation from new observations, changed metadata, corrections or provider evidence. Prevent provider outages from interrupting source capture.

## Spotify compatibility (deferred)

**REC-009 — Support optional provider mappings.** One MusicBrainz recording may correspond to multiple Spotify track IDs, and a Spotify track ID is not the canonical identity. Record provider, identifier, match evidence and optionally a preferred playable equivalent with provenance. Spotify lookup, authorization and playlist export are later milestones. Muzeum playlists, when implemented, consist of ordered Muzeum recording references independently of Spotify.

## Example

Last.fm may deliver the same studio performance under multiple title spellings, with or without album text. If evidence supports the same canonical recording, aggregate the plays under that recording. If a similarly named live performance appears, treat it as a distinct candidate until established otherwise. Assigning one of those plays to a compilation for release-credit purposes must not change its recording.

## Open questions requiring evidence or user decision

- Exact normalization and compatibility scopes for automatic bulk matching.
- Confidence representation, validation dataset, and automatic-acceptance thresholds.
- Handling recordings with multiple credited artists, covers, remixes, medleys and uncertain durations.
- Which MusicBrainz relationships and Discogs evidence are reliable enough to establish a collection's track-to-recording membership.
- How Spotify track matching and territory availability will work when implemented.

## Revision history

- 2026-11-17: Initial consolidated recording identity and candidate-resolution policy.
