# Muzeum domain principles

Status: **Authoritative product policy**, 2026-11-17. These rules describe intended behavior; they do not assert that the behavior has been implemented. Revise in Git alongside product decisions. Read with [recording resolution](recording-resolution.md), [release assignment](release-assignment.md), [listening statistics](listening-statistics.md), and the [roadmap](../roadmap.md).

## Purpose and boundaries

**DOM-001 — Muzeum presents music, not raw scrobbles.** Last.fm supplies immutable observations of listening events. The normal experience centers on canonical artists, releases, recordings and their listening histories. Raw payloads, source discrepancies, and unresolved observations remain available in an appropriate resolution/diagnostic workspace, not as the primary library interface.

**DOM-002 — Source is evidence, interpretation is separate.** Never overwrite or delete an original observation merely because its artist, title, recording or release has been resolved differently. An observation's identity and provenance are not determined by the current canonical mapping. Source import must function with no MusicBrainz, Discogs, or canonical records. Preserve original timestamps, text, identifiers and raw-page lineage.

**DOM-003 — MusicBrainz and Discogs are evidence providers, not product policy.** Muzeum establishes its own canonicalization, release-selection and accounting rules. A provider's classification is not automatically Muzeum's choice. Preserve source identifiers and the evidence/algorithm version behind each decision.

**DOM-004 — The listener's experience is decisive.** Muzeum makes intelligent automatic interpretations so routine manual organization is unnecessary. A listener can correct the interpretation of an individual play, including its credited release, and the correction takes precedence over automatic policy for that listener.

**DOM-005 — Release identity prioritizes the collection of songs.** Physical media, packaging, barcode, and remaster labels are not primary distinctions. Different song collections and orderings may be meaningfully different even when providers group them together. The listener may explicitly credit a greatest-hits collection when that represents what they heard. Do not assume MusicBrainz release group or Discogs master is always a perfect Muzeum collection identity; preserve evidence and map carefully.

**DOM-006 — Interpretations are revisable and attributable.** Automatic and human assessments record their actor, evidence, policy/algorithm version, timestamp, reason and uncertainty. Changes to effective decisions are append-only and reversible. New evidence may produce a no-change assessment. Reverting appends a new decision; it never erases the past.

**DOM-007 — Shared source does not mean shared private interpretation.** Multiple Muzeum users may associate the same public Last.fm archive. Their own overrides, release credits and personal statistics remain independently scoped. Association is not proof of Last.fm account ownership. Auth at auth.harvj.com remains the only interactive identity provider.

**DOM-008 — One listening event stays one event.** Multiple release views may display a recording's entire listening history; this does not create duplicate listens. Release ranking credits each play at most once. See [listening statistics](listening-statistics.md).

**DOM-009 — Near-term simplicity.** Prefer reliable, understandable implementation for demonstrated usage and plausible growth below roughly 1,000 users over speculative infrastructure for 10,000. Preserve straightforward paths to scale. Do not confuse benchmark targets with product requirements.

**DOM-010 — Provider independence.** Spotify identifiers may later identify playable equivalents and support playlist export; Spotify must not own Muzeum's recording identity or playlist definitions. Spotify API integration is deferred. Last.fm completed scrobbles should import automatically; no now-playing UI is required.

## Daily use, purposeful metadata and musical knowledge

**DOM-011 — Choose from the listener's own shelf.** Muzeum's primary everyday purpose is helping listeners explore, remember and choose what to listen to next from music already in their collection/history. "What am I pulling off my shelf next?" is a first-class product question, not merely a deferred streaming recommendation feature. Support useful discovery using available listening frequency, recency, canonical relationships and eventually richer musical characteristics. Do not assume favorite means most scrobbled; make preference/ranking semantics explicit and revisable. Discovery of unfamiliar music may exist later, but is not the defining daily workflow.

**DOM-012 — Deliberate canonical metadata.** Import only fields with a stated purpose in identity verification, relationships, presentation, search, listening analysis or choosing music. Define each field's intended use, provenance, conflict policy and refresh semantics before promoting it into canonical storage. Provider payload availability alone is not a reason to mirror it. Preserve compact audit evidence separately from canonical attributes and respect provider retention/licensing.

**DOM-013 — Repeatable import/refresh.** A canonical artist, release or recording should eventually offer an **Import** action that fetches current MusicBrainz/Discogs evidence by known identifiers, compares selected fields and safely updates the same Muzeum entity. It must be idempotent against unchanged evidence, preserve import/change history, report contradictions, distinguish absent/unknown from explicit correction or removal, and never silently erase useful metadata. Run bounded background work without duplicate concurrent imports; metadata refresh must not rewrite scrobbles, canonical identity, or protected listener recording/release decisions. The initial UI and service belong to a future numbered milestone, not P1.3a.

**DOM-014 — Queryable musical content.** Eventually model recording contributors (musicians and roles), instruments, and time-bounded musical events (such as solos, entrances, harmonies and transitions) with evidence, uncertainty and optional start/end offsets. Model distinct events and overlapping/coordinated contributions: two successive guitar solos differ from one dual-guitar solo with two participants. Absence of annotation is unknown, not proof of absence. This is a first-class future musical-knowledge capability, not a request to indiscriminately ingest provider fields.

**DOM-015 — Listening history meets musical knowledge.** Support questions such as "Which of my favorite recordings have dual guitar solos?" and "What should I revisit that I haven't played recently?" by intersecting listener-scoped scrobbles, effective canonical interpretations, explicit preferences where available, and musical annotations. Return known coverage/uncertainty rather than claiming unannotated recordings lack a property. Keep the experience focused on choosing music rather than supervising metadata.

## Product-facing vocabulary

- **Observation / scrobble:** Immutable Last.fm evidence of a listening event.
- **Recording:** Canonical identity for the particular recorded performance heard, usually associated with a MusicBrainz recording.
- **Release collection:** Muzeum's representation of a particular collection/ordering of songs, supported by MusicBrainz and Discogs release evidence, independent of physical format/remaster.
- **Release membership:** A recording appears on a release collection; many-to-many.
- **Credited release:** The one collection, if any, receiving a given play's release-ranking credit.
- **Assessment:** Evidence-based evaluation, possibly without a change.
- **Decision:** Effective selection or revision of an interpretation, with historical attribution.
- **User override:** Explicit listener decision, protected against automatic replacement.

## Policy precedence

These documents supersede contradictory *proposals* in dated P1.0 design notes. They do not supersede current deployed authentication, provenance, security, recovery or import contracts. When policy conflicts with implementation, record the discrepancy and plan a numbered milestone; do not silently rewrite production history.

## Open questions

- How to identify a stable Muzeum release collection when provider release groups/masters contain materially different track lists.
- How to interpret artist country of origin for collaborations, migrations, or artists with no unambiguous country.
- Whether user-level release preferences are needed in addition to individual-play overrides.
- How to handle cases where a single song has multiple distinct recordings with ambiguous source metadata.

## Revision history

- 2026-11-17: Made choosing from one's own shelf a primary daily purpose; added purposeful metadata, repeatable imports and future queryable musical-event annotations.

- 2026-11-17: First authoritative consolidation of agreed domain rules. Implementation remains governed by numbered milestones.
