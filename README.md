# Muzeum.fm

Muzeum.fm is a listening archive that transforms raw listening history into a structured, queryable record of music over time.

Rather than treating listening activity as transient or purely behavioral data, Muzeum preserves listening events and resolves them against authoritative music metadata to create a durable personal and collective archive.

---

## What Muzeum Does

Muzeum ingests listening data (such as scrobbles) and incrementally resolves that data into canonical musical entities:

- Artists
- Recordings
- Releases and release contexts

The system is designed to reflect how music actually exists in the world: with multiple releases, partial dates, reissues, regional variations, and evolving metadata.

---

## Core Concepts

### Scrobbles Are Source Data

Listening data is considered authoritative.
Scrobbles are never fabricated, inferred, or modified.

They serve as the trigger for all downstream resolution and ingestion processes.

---

### Recording Surfaces

Incoming scrobbles are first attached to provisional “recording surfaces” that reflect exactly what the listening source reported (artist name, track name, album name).

These surfaces are not assumed to be correct or canonical.

---

### Canonical Resolution

Canonical artists, recordings, and releases are created later using MusicBrainz data.

This process is explicit and controlled:
- Multiple valid release candidates may exist
- Human selection is supported where ambiguity remains
- Canonical entities are created once and reused

---

### Releases as First-Class Entities

Muzeum models releases directly rather than collapsing everything into a single “album” concept.

This allows:
- Multiple release dates (by country)
- Distinction between original releases and later reissues
- Accurate tracklists per release
- Proper handling of compilations and bonus material

---

### Idempotent Ingestion

All ingestion processes are designed to be idempotent.

Running the same ingest multiple times:
- Does not duplicate data
- Does not overwrite historical associations
- Preserves the integrity of existing records

---

## What Muzeum Is Not

- A recommendation engine
- A streaming service
- A social platform

Muzeum does not attempt to predict taste or optimize engagement.

---

## Why This Exists

Most music platforms optimize for discovery and consumption but do not preserve listening history in a way that is:

- structurally accurate
- historically meaningful
- resilient to platform changes

Muzeum is intended to function as a long-lived archive that can answer questions about listening history long after the original listening context has passed.

---

## Technical Overview

Muzeum is built as a Ruby on Rails application with a strong emphasis on:

- explicit data modeling
- test-driven development
- external metadata reconciliation
- long-term data integrity

Key external data sources currently include:
- MusicBrainz (for music metadata)
- Last.fm (for listening history)

---

## Current Status

Muzeum is under active development.

Current areas of focus include:
- MusicBrainz release candidate extraction
- Release ingestion and tracklist construction
- Canonical recording resolution and merging
- Preservation of scrobble lineage

The data model and ingestion workflows are still evolving.

---

## Intended Audience

Muzeum is intended for users who want:

- a durable record of their listening history
- accurate representation of musical releases
- the ability to revisit and reinterpret listening data over time

