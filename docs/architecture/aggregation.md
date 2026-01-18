## Aggregation

Aggregation interprets raw scrobbles into structured facts.

### DailyListen

Fields:
- `user_id`
- `recording_id`
- `date`
- `listen_count`
- `total_duration_ms`

Rules:
- Each scrobble increments count by 1
- Aggregation is idempotent
- Duration is backfilled later

Aggregation answers:
> "What happened, as experienced by the user?"
