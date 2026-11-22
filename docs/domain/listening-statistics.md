# Listening statistics and rankings

Status: **Authoritative accounting semantics; aggregation implementation and duration fallback are open.** See [principles](principles.md) and [release assignment](release-assignment.md).

## Definitions

**STAT-001 — One observation, one listening event.** An accepted scrobble contributes at most one play to any disjoint accounting total. Duplicate provider deliveries do not create extra plays. Ambiguous identical same-second deliveries cannot be resolved with invented source event IDs; distinguish pending ambiguity from accepted plays.

**STAT-002 — Recording totals.** A recording's play count is the number of accepted, currently resolved plays of that recording in the listener's authorized archive. Recording listening time derives from those plays under a consistent documented duration policy. Release credit never changes these totals.

**STAT-003 — Membership views show all recording activity.** A release page lists its member recordings and, for each, shows the **complete recording listening history**, regardless of which release received credit for those events. This may repeat the same event across different release pages as a *view*, not as multiple source listens.

**STAT-004 — Deferred per-play credit.** v0.5.0 release histories use recording membership. Combined counts use the union of distinct observations across selected releases. For a future distinct per-play credit statistic, For rankings by play count or listening time, each play contributes to **at most one** credited release. Unassigned/unresolved credit contributes to no release ranking until resolved. Changing a play's credited release moves its ranking contribution and time, never duplicates them.

**STAT-005 — Distinguish two release metrics explicitly.** 'Activity of included recordings' (sum or listing of plays for member recordings, possibly overlapping other releases) is not 'credited release plays' (disjoint allocation for rankings). Do not label both 'release plays' without qualification. The default ranking metric is credited plays/time, not sum of member recording plays.

**STAT-006 — Avoid double-counting within a collection.** A recording appearing more than once in a release's track list must not silently duplicate its full recording history in collection-level distinct-play statistics. Track-list presentation can show each position, but aggregation must specify whether counting distinct recordings/plays or track slots.

**STAT-007 — Artist totals are separately attributed.** Artist play counts follow the canonical recording's applicable artist credit and a documented policy for collaborations, rather than inheriting release credit. Do not accidentally multiply plays because of multiple release memberships or multiple artist relationships.

**STAT-008 — Rebuildable derived data.** Counts, rankings and charts are projections of immutable observations and current scoped decisions. They must be reproducible and recalculated or incrementally corrected when assignments change. Source and decision history are authoritative; materialized totals are not.

**STAT-009 — Duration uncertainty must be visible.** Prefer the resolved recording's supported duration where appropriate; distinguish known, estimated and unavailable duration. Never silently treat an unknown duration as zero *listening time* or invent actual completion duration from a Last.fm scrobble. Exact duration/fallback rules are open.

**STAT-010 — User/account scope.** Shared Last.fm source accounts must not cause double counting for a user. Users with the same source archive may have different credited-release rankings because their interpretations differ.

**STAT-011 — Scrobble is not proof of complete playback.** Last.fm is authoritative for what it reported, not a guarantee of the duration or completeness of actual listening. A scrobble of a recording containing a guitar solo counts as a scrobble of that recording; it does not prove the listener reached the solo's timestamp. Keep recording-level exposure queries distinct from measured passage-level playback. Conversational wording such as "how many times have I heard" may be answered naturally, but label the underlying metric accurately. Do not manufacture playback completion, elapsed listening seconds or additional events.

**STAT-012 — Queryable listening preferences and annotation coverage.** Future "favorites" and "what next" queries may combine counts, recency and explicit listener preferences, with transparent criteria rather than assuming most-scrobbled equals favorite. When filtering by musical events, distinguish known matches, known nonmatches and unannotated/unknown recordings. Count distinct scrobbles of qualifying recordings without multiplying by the number of solos or contributors; passage-level exposure requires independent playback evidence.

## Worked example

The canonical Radiohead recording *Fake Plastic Trees* has **150 accepted plays** (illustrative). Both *The Bends* and the *Fake Plastic Trees* single contain that recording. Each release's track listing displays 150 plays for that recording. The recording page also displays 150.

For ranking purposes, suppose 120 plays are credited to *The Bends* and 30 to the single. The release-ranking contributions sum to 150, not 300. Moving one play's credit from *The Bends* to the single changes the allocation to 119/31 but leaves the recording at 150 and both track-list displays at 150.

A release page may offer both 'All recording activity' and 'Credited to this release', clearly labeled. Only the latter is suitable for additive release rankings.

## Open questions

- Listening-time duration source and fallback when MusicBrainz and Discogs disagree or omit it.
- How to attribute a recording with multiple principal artists or featured performers in artist rankings.
- Treatment of unresolved recording identity in aggregate totals.
- Whether releases with identical song collections but different ordering should be merged for ranking.
- Presentation of partial/incomplete listening sessions and confidence of release credit.

## Revision history

- 2026-11-17: Clarified Last.fm's observation authority, non-guaranteed playback, and future shelf-selection/temporal annotation query semantics.

- 2026-11-17: Initial distinct membership-versus-credit and ranking semantics.
