## Overview

The system models *beliefs about identity*, not absolute truth. Confidence and status express epistemic certainty, not correctness.

## Core Entities

### Artist

Represents a hypothesis about a real‑world artist.

Fields:
- `name`
- `mbid` (nullable)
- `status` (`provisional`, `resolved`, `canonical`, `merged`)
- `confidence` (0.0–1.0)
- `merged_into_id` (self‑reference)

### Recording

Represents a hypothesis about a real‑world recording.

Fields:
- `title`
- `status`
- `confidence`
- `duration_ms` (nullable)
- `merged_into_id`

Recordings are *belief buckets*. Titles are provisional until promoted.

### RecordingArtist

Represents a factual attribution between a recording and an artist.

This table contains no confidence or status. Attribution is replaced, not probabilistically resolved.
