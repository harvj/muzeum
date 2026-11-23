# Listening statistics and rankings

Status: **Authoritative accounting semantics.** See [principles](principles.md) and [release assignment](release-assignment.md).

## Definitions

**STAT-001 — One observation, one listening event.** An accepted scrobble contributes at most one play to any disjoint accounting total. Duplicate provider deliveries do not create extra plays. Ambiguous identical same-second deliveries cannot be resolved with invented source event IDs; distinguish pending ambiguity from accepted plays.

**STAT-002 — Recording totals.** A recording's play count is the number of accepted, currently resolved plays of that recording in the listener's authorized archive. Recording listening time derives from those plays under a consistent documented duration policy. Release credit never changes these totals.

**STAT-003 — Membership views show all recording activity.** A release page shows the distinct effective observations of its member recordings, regardless of the original source album. The same observation may contribute to multiple release contexts.

**STAT-004 — Union for combined contexts.** Use the union of distinct observations across selected releases for combined counts and estimated listening time.

**STAT-005 — Primary metrics.** Rank recordings by play count, with estimated listening time secondary on recording details. For artist and release contexts, report estimated listening time first and play count second. On the Artist page, use play-count bars for Recordings and listening-time bars for Releases.

**STAT-006 — Avoid double-counting within a collection.** A recording appearing more than once in a release's track list must not silently duplicate its full recording history in collection-level distinct-play statistics. Track-list presentation can show each position, but aggregation must specify whether counting distinct recordings/plays or track slots.

**STAT-007 — Artist totals are separately attributed.** Artist history derives from verified credits on effective canonical recordings, including featured artists. Count distinct observations once per artist regardless of repeated credits or overlapping release memberships.

**STAT-008 — Rebuildable derived data.** Counts, rankings and charts are projections of immutable observations and current scoped decisions. They must be reproducible and recalculated or incrementally corrected when assignments change. Source and decision history are authoritative; materialized totals are not.

**STAT-009 — Duration uncertainty must be visible.** Sum positive canonical recording durations across distinct effective observations to estimate listening time. Count observations without known durations in the play count and show the coverage of the estimate. A scrobble cannot establish actual elapsed playback.

**STAT-010 — User/account scope.** Shared Last.fm source accounts must not cause double counting for a user. Users with the same source archive may have different totals because their effective recording assignments differ.

**STAT-011 — Scrobble is not proof of complete playback.** Last.fm is authoritative for what it reported, not a guarantee of the duration or completeness of actual listening. A scrobble of a recording containing a guitar solo counts as a scrobble of that recording; it does not prove the listener reached the solo's timestamp. Keep recording-level exposure queries distinct from measured passage-level playback. Conversational wording such as "how many times have I heard" may be answered naturally, but label the underlying metric accurately. Do not manufacture playback completion, elapsed listening seconds or additional events.

**STAT-012 — Queryable listening preferences and annotation coverage.** Future "favorites" and "what next" queries may combine counts, recency and explicit listener preferences, with transparent criteria rather than assuming most-scrobbled equals favorite. When filtering by musical events, distinguish known matches, known nonmatches and unannotated/unknown recordings. Count distinct scrobbles of qualifying recordings without multiplying by the number of solos or contributors; passage-level exposure requires independent playback evidence.

## Worked example

The canonical Radiohead recording *Fake Plastic Trees* has **150 accepted plays** (illustrative). Both *The Bends* and the *Fake Plastic Trees* single contain that recording. Each release's track listing displays 150 plays for that recording. The recording page also displays 150.

The album and single each show 150 contributed observations. Their combined history contains 150 unique observations. Estimated listening time across both likewise uses those 150 observations once.

## Open questions

- How to reconcile conflicting provider durations when maintaining the canonical recording.
- Treatment of unresolved recording identity in aggregate totals.
- Whether releases with identical song collections but different ordering should be merged for ranking.
- Presentation of partial/incomplete listening sessions and confidence of release credit.

## Revision history

- v0.5.0: Defined overlapping membership, verified featured credits, listening-time estimates, and duration coverage.

- 2026-11-17: Clarified Last.fm's observation authority, non-guaranteed playback, and future shelf-selection/temporal annotation query semantics.

- 2026-11-17: Initial distinct membership-versus-credit and ranking semantics.


## Default release rankings (v0.6.6)

Rank eligible canonical releases by estimated listening time, breaking ties by title and canonical ID. Eligibility requires a verified original publication context or a verified first-publication appearance of a member recording; it does not follow from catalog membership alone. A listener’s latest explicit inclusion or exclusion supersedes the default. Keep preference history without changing catalog membership or observations. Release detail and combined histories continue to use all applicable memberships. Count distinct effective observations within each result, and use the union of observations for combined totals.
