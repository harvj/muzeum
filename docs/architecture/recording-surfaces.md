## Recording Surfaces

Recording surfaces represent *observed presentations* of recordings.

A surface captures:
- Artist name string
- Album name string
- Track name string
- Observed MBIDs (artist / album / track)
- Source (e.g. `lastfm`)
- Observation frequency
- Confidence

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
