# Muzeum v0.7.0 — Musical Collections and Autonomous Investigation

Muzeum now investigates a recording’s publication history before proposing a release. Confirm one original collection from an authentic MusicBrainz edition. If several credible editions have different tracklists, compare the shared tracks and the differences, then choose the exact source edition. The complete ordered tracklist is retained with its original source IDs.

- **Recording identity.** Corroborated clean and explicit source recordings can resolve to one Muzeum recording. The source IDs, descriptions, credits, and review evidence are retained. Revision history records subsequent identity changes, and existing listening decisions remain attached to the recording the listener confirmed.
- **Additional editions.** Original tracklists stay intact. Additional tracks appear in compact rows with edition provenance, duration, and play count. Base tracks always count toward release listening totals. Each listener can include additional tracks in that release’s counts, estimated time, and rankings.
- **Investigation status.** Queued work, active investigation, and scheduled retries appear live alongside queue information where it is available. A reconnect recovers missed updates. When there is insufficient release evidence, Muzeum explains the gap and can resolve the recording by itself.
- **Listening history.** Confirming a recording admits at most one new release, and other editions remain evidence. One listening observation contributes at most once to a release.

This candidate includes three additive database migrations with no backfill. Existing listening observations, canonical decisions, and revision history are retained.
