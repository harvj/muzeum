# Muzeum — Current State & What’s Next

This document captures **where the system is right now**, the **invariants we’ve already committed to**, and the **next concrete steps**.
It is intended to let work resume immediately without re-litigating architecture.

---

## 1. What Exists Today (Ground Truth)

### 1.1 Scrobbles
- Raw listening events imported from Last.fm
- Schema includes:
  - `user_id`
  - `played_at`
  - `payload` (JSON string from Last.fm)
  - `recording_id` (nullable)
- Scrobbles are **immutable facts**
- They may be re-linked to a different `recording_id` later, but the scrobble itself is never rewritten

---

### 1.2 RecordingSurfaces
RecordingSurfaces represent **observed identity**, not truth.

Each surface captures how a scrobble *presented* a recording:

Fields include:
- `artist_name`
- `track_name`
- `album_name`
- observed MBIDs (`artist_mbid`, `track_mbid`, `album_mbid`)
- `normalized_key`  Format:  `artist||album||track`
- `observed_count`
- `confidence` (observational, not canonical)
- `source` (currently always `lastfm`)
- `recording_id` (the recording this surface currently points to)

**Key rules**
- Surfaces are never deleted
- Surfaces accumulate observations over time
- MBIDs from Last.fm are treated as *claims*, not truth

---

### 1.3 Recordings
Recordings represent **internal identity**.

Fields include:
- `title`
- `status` (enum)
- `provisional`
- `canonical`
- `merged`
- `confidence`
- `source`
- `merged_into_id` (for merged recordings)

**Important**
- Recordings may be ugly and duplicated initially
- Merging is expected and first-class
- Recordings become authoritative only once marked `canonical`

---

### 1.4 Importer & Resolver (CLI-first)

#### Importer
- `bin/import_scrobbles LASTFM_USERNAME [PAGE_LIMIT]`
- Delegates all logic to `Lastfm::Importer.run!`
- Logs minimal progress (page requests, counts)
- Logging is centralized via a reusable logger wrapper
- API keys are redacted explicitly (not via global blacklist)

#### Resolver
- `bin/resolve_scrobbles USERNAME [LIMIT]`
- Processes **oldest unresolved scrobbles first**
- Links scrobbles → recording surfaces → provisional recordings
- Does **not** attempt canonicalization or MusicBrainz enrichment yet

---

### 1.5 Logging
- Unified logging abstraction
- CLI logging when invoked via `bin/*`
- Rails.logger when running inside app
- Null logger for specs (to keep output clean)
- No `puts` in domain code

---

## 2. What Does *Not* Exist Yet (By Design)

### ❌ DailyListens aggregation
- Not built yet
- Intentionally deferred

### ❌ Canonical artists & releases
- No Artist / Release creation from provisional data
- No aggregation by artist or release

### ❌ MusicBrainz enrichment
- Client exists conceptually
- No active enrichment pipeline yet

---

## 3. Core Architectural Invariants (Locked In)

These should **not be revisited lightly**.

### 3.1 Separation of concerns
- Scrobbles = facts
- Surfaces = observations
- Recordings = identity
- Canonicalization happens *after* enrichment
- Aggregation happens *after* canonicalization

---

### 3.2 Aggregation invariants
- DailyListens only reference **canonical recordings**
- Updating a scrobble’s `recording_id` should only affect:
- DailyListens rows referencing the *old* recording
- No full re-aggregation allowed

---

### 3.3 MusicBrainz trust model
- MBIDs from Last.fm are untrusted
- MBIDs must be confirmed via enrichment
- Confidence increases incrementally
- No auto-merge without high confidence or human confirmation

---

## 4. What DailyListens Will Be (Later)

DailyListens is a **derived fact table**, not a source of truth.

Eventually: `(user_id, recording_id, date) → listen_count`

Rules:
- Only canonical recordings are aggregated
- Aggregation is incremental
- Merges only trigger localized recomputation

**Aggregation must wait until recording identity stabilizes.**

---

## 5. The Next System to Build (This Is “What’s Next”)

### 5.1 MusicBrainz Client (Pure I/O)

A clean client layer:
- No persistence
- No business logic

Responsibilities:
- Search recordings using surface context
- Fetch recording details
- Fetch release details
- Fetch artist credits

---

### 5.2 RecordingEnricher (Core Domain Logic)

This is the next *real* system.

Inputs:
- A provisional Recording
- Its associated RecordingSurfaces

Responsibilities:
1. Query MusicBrainz using surface context
2. Rank candidate matches
3. Attach verified MBIDs
4. Adjust recording confidence
5. Decide when a recording becomes `canonical`
6. Trigger Artist / Release creation **only when canonical**

Important:
- No aggregation here
- No auto-merging without strong confidence
- Designed to support human review

---

### 5.3 Canonicalization Rules (Explicit & Tunable)

Examples (subject to tuning):
- Confidence ≥ 0.9 → canonical
- Full release tracklist known → create release + sibling recordings
- Conflicting MBIDs → hold provisional
- Multiple agreeing surfaces → confidence increases

---

## 6. UI Direction (First UI Should Be This)

### Recording Enrichment Workbench

The first UI should support:
- Reviewing provisional recordings
- Viewing all associated surfaces
- Viewing MusicBrainz candidates
- Accept / reject / defer matches
- Manual linking when needed

This is **not a stopgap UI** — it is the control surface for correctness.

---

## 7. Order of Operations (Strict)

1. MusicBrainz client
2. RecordingEnricher service
3. Confidence & canonicalization rules
4. Enrichment workbench UI
5. Artist & Release creation
6. DailyListens aggregation

Skipping or reordering these creates tech debt.

---

## 8. Current Goal

> Become confident that recordings in the database represent real musical works
> before counting, aggregating, or summarizing anything.

Everything else flows from that.


