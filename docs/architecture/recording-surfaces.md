## Recording Surfaces

Recording surfaces represent *observed presentations* of recordings.

A surface captures:
- Artist name string
- Album name string
- Track name string
- Normalized key
- Observed MBIDs (artist / album / track)
- Observation frequency
- Release candidates (JSON - set by MB search)
- Chosen release candidate index
- Ingested release id (set by ReleaseIngestor)

Surfaces are immutable historical observations.

### Normalization

Normalization exists only to detect **exact surface recurrence**, not equivalence.

Normalized surface key:

```
artist_name || album_name || track_name
```

Normalization rules:
- Downcase
- Trim
- Collapse whitespace
- Preserve punctuation and parentheticals

Album name is intentionally included to preserve ambiguity.
