# Next Steps: Aggregation, Resolver, Releases, Admin UI

This document outlines the immediate next phases of the system after raw scrobble ingestion is functioning.

---

## 1. Aggregation Layer

### Current State
- Raw scrobbles are stored immutably (`scrobbles`)
- DailyListen aggregates exist or are planned
- Canonical identity is not yet stable

### Decisions
- Scrobbles are the source of truth
- Aggregation operates on top of scrobbles
- Aggregation must be re-runnable and auditable

### Next Steps
- Implement an Aggregation Job:
  - Input: scrobbles within an ImportRun range
  - Output: DailyListen rows (user × recording × date)
- Aggregation rules:
  - One scrobble = one listen
  - No duration at import time
  - Aggregation may update DailyListen rows incrementally
- Ensure aggregation:
  - Does not assume canonical identities
  - Can be re-run after resolution changes

### Open Questions
- Do we mark DailyListen rows as “finalized” after resolution stabilizes?
- Do we allow partial re-aggregation (by date range)?

---

## 2. Resolver Architecture

### Core Principle
Resolvers upgrade identity hypotheses, never raw events.

### Resolver Responsibilities
- Validate MBIDs (existence, redirects)
- Merge duplicate provisional entities
- Re-point DailyListen rows
- Backfill metadata (duration, release membership)

### Planned Resolvers (Initial)
- RecordingResolver
- ArtistResolver
- ReleaseResolver
- (later) DurationBackfillResolver

### Required Supporting Structure
- resolution_actions table (audit log):
  - resolver type
  - subject (entity)
  - action (validate / merge / repoint)
  - before / after snapshots
  - confidence delta

### Alias Memory (Critical)
- Add identity_aliases:
  - normalized string → canonical entity
  - confidence + source
- Resolver:
  - checks aliases first
  - writes aliases on successful resolution
- Importer never consults aliases

---

## 3. Release Storage Strategy

### Conceptual Model
- Releases are conceptual albums / collections
- Functionally equivalent to Release Groups
- Anchored to a chosen MusicBrainz Release MBID
- Format and edition details are intentionally ignored

### Release Entity (Minimal)
- title
- mbid (canonical reference)
- release_year (optional)
- status / confidence / source
- merged_into_id

### Relationships
- ReleaseRecording:
  - recording belongs to release
  - no track positions required initially

### Resolver Role
- Choose a canonical MusicBrainz Release as representative
- Fetch tracklist only to establish membership
- Merge provisional releases when appropriate

### Non-Goals
- No format-specific modeling
- No edition-level correctness
- No attempt to perfectly mirror MusicBrainz structure

---

## 4. Admin UI (Inspection, Not Control)

### Core Purpose
Answer: “Why does the system believe this?”

Not for bulk editing or discography management.

### Initial Admin Surfaces

#### A. Scrobble Inspector (Read-only)
- Raw payload
- played_at
- Derived recording / artist / release
- Resolution status

#### B. Entity Dashboards
- Recording list with:
  - status, confidence, aliases, attached listens
- Release list with:
  - title, status, membership, confidence

#### C. Merge Review Queue
- Resolver-suggested merges
- Impact preview (affected listens)
- Approve / reject / defer

#### D. Alias Inspector
- Normalized strings
- Canonical targets
- Confidence
- Lock / deprecate

### Explicitly Not Included
- Inline editing of raw scrobbles
- Free-text “fix metadata” forms
- Automatic resolution without auditability

---

## 5. Execution Order (Recommended)

1. Lock aggregation job design
2. Add resolution_actions and identity_aliases
3. Implement RecordingResolver (MBID validation only)
4. Add minimal admin UI for Recording inspection
5. Introduce Release tables and ReleaseResolver stub
6. Run everything on your own data
7. Observe real failure modes before expanding logic

---

## Guiding Constraint

- Forward motion over premature correctness
- Nothing deletes raw truth
- Everything is explainable, inspectable, and reversible
