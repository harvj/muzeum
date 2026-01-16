# Architecture Overview

This document describes the core architecture, data model, and execution model
of the system. It is intentionally pragmatic and non-philosophical. The goal is
clarity, correctness, and long-term maintainability.

---

## Core Principles

- Listening events are immutable facts.
- Identity is provisional and converges over time.
- Canonical enrichment is required but non-blocking.
- The system favors forward motion over premature correctness.
- All background work is explicit, bounded, and inspectable.
- Raw input is preserved whenever lossless capture is possible.

---

## Event Capture vs Identity Resolution

The system is explicitly two-phase:

### Phase 0: Raw Event Capture (Importer)

The system stores raw listening events (Scrobbles) exactly as received from Last.fm.

This layer exists to:

- Preserve lossless input
- Prevent double-counting
- Allow re-aggregation and re-interpretation
- Enable debugging and user trust

The raw layer answers:

> “What data did the upstream system actually give us?”

---

### Phase 1: Event Interpretation (Aggregator)

The aggregator interprets raw scrobbles into structured, queryable facts (DailyListens).

Aggregation is a first-class system component and is guaranteed to run; it is intentionally decoupled from ingestion to preserve data integrity and forward motion.

The aggregator answers:

> “What happened, as experienced by the user?”

### Phase 2: Canonical Enrichment (Resolver)

Canonical enrichment validates, resolves, and consolidates identity using
external authorities (primarily MusicBrainz).

The resolver answers:

> “What is this, really?”

It may update identity pointers, merge records, and backfill metadata, but it
never discards or rewrites listening events.

---

## Data Model Overview

### Raw Listening Events (Scrobbles)

Scrobbles represent immutable upstream facts.

#### Fields include:

- user_id
- played_at (UTC timestamp, unique per user)
- payload (raw parsed Last.fm data)
- timestamps

#### Invariants:

Scrobbles are immutable once written

- A user cannot have two scrobbles at the same timestamp
- Raw payload is never rewritten
- Scrobbles exist to preserve truth, not convenience.

### Core Entities

#### Artist

Represents a real-world artist hypothesis.

Fields include:
- `name`
- `mbid` (nullable)
- `status` (enum)
- `confidence` (float, 0.0–1.0)
- `source` (string)
- `merged_into_id` (self-reference, nullable)

Status lifecycle:
- `provisional` → `resolved` → `canonical` → `merged`

Confidence represents epistemic certainty, not moral or qualitative judgment.

Source records provenance of identity creation (e.g. `lastfm`, `musicbrainz`,
`manual`).

---

#### Recording

Represents a real-world recording hypothesis.

Fields include:
- `title`
- `mbid` (nullable)
- `status` (enum)
- `confidence` (float)
- `source` (string)
- `duration_ms` (nullable)
- `merged_into_id` (self-reference, nullable)

Recordings may be merged when multiple provisional records resolve to the same
canonical identity.

---

#### RecordingArtist

Represents an attribution:

> “This recording is credited to this artist.”

This is a factual relationship, not an identity hypothesis.

Fields include:
- `recording_id`
- `artist_id`
- `role` (optional)

No `source`, `confidence`, or `status` is stored on this table.

**Identity certainty is modeled on core entities (Artist, Recording); attribution
relationships are treated as factual and replaced rather than probabilistically
resolved.**

MusicBrainz is treated as the implicit authority for canonical recording–artist
relationships.

---

#### DailyListen

Represents aggregated listening events.

Fields include:
- `user_id`
- `recording_id`
- `date`
- `listen_count`
- `total_duration_ms`

Daily listens are immutable facts once written.

---

## Importer

### Responsibilities

The importer:
- Fetches recent scrobbles from Last.fm
- Extracts only what Last.fm actually provides
- Aggregates listens by user, recording, and day
- Advances an import cursor

The importer does not:
- Resolve canonical identities
- Assign albums or releases
- Infer duration
- Merge records
- Perform enrichment

**Upstream MBIDs are treated as provisional identifiers and are subject to
validation, consolidation, or replacement during canonical enrichment.**

---

### Cursor Model

Import progress is tracked exclusively via ImportRun range boundaries.
No per-user “last imported” timestamp exists by design.

---

### Aggregation Rules

- Each scrobble increments `listen_count` by 1.
- Duration is not calculated at import time.
- Duration is backfilled during enrichment once recording duration is known.

---

## Canonical Enrichment

### Responsibilities

The resolver:
- Validates MBIDs against MusicBrainz
- Resolves string-based identities when MBIDs are missing
- Merges provisional entities into canonical ones
- Re-points listening events to canonical entities
- Backfills metadata (e.g. duration, releases)

**Canonical resolution may reassign listening records to a different internal
entity; all such operations are additive, auditable, and never discard event
history.**

---

### Merging Rules

When entities are merged:
- Listening events are re-pointed, never recalculated
- Counts are summed, not recomputed
- Provisional records are marked `merged`, not deleted
- All merges are reversible

---

## Execution Model

### Imports

- User-initiated via UI (initially)
- Executed as bounded background jobs
- No continuous polling or automatic sync

---

### Enrichment

- Triggered explicitly or on entity creation
- Executed as bounded background jobs
- No continuous database polling

**All ingestion and enrichment processes are executed as explicit, bounded
background jobs; the system performs no continuous polling or autonomous
background activity.**

---

## Non-Goals

The system intentionally does not:
- Store individual scrobbles
- Attempt real-time accuracy
- Guarantee perfect discography resolution
- Optimize for social interaction
- Perform speculative inference at ingestion time

---

## Summary

This system treats listening history as lived experience first, raw input second, and discographic classification third.

It preserves truth at the boundaries, admits uncertainty in the middle, and allows identity to converge over time without rewriting history.

Nothing is lost. Nothing is rushed. Nothing pretends to be more certain than it is.
