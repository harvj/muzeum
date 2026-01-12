# muzeum.fm

muzeum.fm is a personal listening archive built on top of Last.fm data and
MusicBrainz canonical metadata.

It is intentionally **not** a social platform.

There are no feeds, recommendations, likes, follows, or engagement mechanics.
The system exists to provide a correct, durable, and user-owned view of a
person’s listening history.

## Philosophy

- Correctness over speed
- Archival integrity over real-time streaming
- User ownership over platform behavior
- No growth hacking
- No dark patterns
- No data resale

## What This App Does

- Imports listening history from the Last.fm API (read-only)
- Normalizes inconsistent metadata using MusicBrainz
- Aggregates listens into immutable daily records
- Supports time-weighted listening metrics
- Enables flexible querying across time ranges and user-defined tags

## What This App Does Not Do

- No social features
- No recommendations or discovery
- No playlists as a primary feature
- No advertising
- No selling or sharing of user data

## Technical Stack

- Ruby on Rails
- PostgreSQL
- Background jobs (Sidekiq or Solid Queue)
- Server-rendered views with progressive enhancement
- Single-region deployment

## Development Setup

Requirements:
- Ruby (see `.ruby-version`)
- PostgreSQL 15+

Setup:
```bash
bin/rails db:create
bin/rails server
```

## Status

This project is in active development.
The initial focus is on data correctness, canonical mapping, and query fidelity.
