## Scrobbles

Scrobbles represent immutable upstream facts exactly as provided by Last.fm.

Fields:
- `user_id`
- `played_at` (UTC)
- `payload` (raw Last.fm data)
- `recording_id` (may change, begins NULL until Resolver runs)

Invariants:
- Scrobbles are never rewritten.
- A user cannot have two scrobbles at the same timestamp.
- Payload is preserved verbatim.

Scrobbles answer:
> “What data did the upstream system give us?”



