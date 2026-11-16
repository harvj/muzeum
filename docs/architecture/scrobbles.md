> Historical contract. The current importer stores selected parsed fields, not verbatim upstream data; timestamp-only identity is under review. See the [P1.0 observation and account proposal](../p1.0/foundation-and-data-contract.md#42-observation-and-import-extension). No proposed schema changes are implemented yet.

## Scrobbles

Scrobbles represent immutable upstream facts exactly as provided by Last.fm.

Fields:
- `user_id`
- `played_at` (UTC)
- `payload` (raw Last.fm data)
- `recording_id` (begins null - set ReleaseIngestor)
- `recording_surface_id` (begins null - set by ScrobbleResolver)

Invariants:
- Scrobbles are never rewritten.
- A user cannot have two scrobbles at the same timestamp.
- Payload is preserved verbatim.

Scrobbles answer:
> “What data did the upstream system give us?”



