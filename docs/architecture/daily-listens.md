## DailyListens are derived state

They never own truth

They must be:

- rebuildable
- idempotent
- correct after reprocessing

They are allowed to be temporarily stale.
They are never manually edited.

### The correct production pattern

Aggregation API (this matters)

You should end up with one authoritative entry point, e.g.:

```
DailyListen::Aggregator.reaggregate!(
  user_id:,
  recording_ids:,
  dates:
)
```

or a slightly higher-level variant:

```
DailyListen::Aggregator.reaggregate_recordings!(
  user_id:,
  recording_ids:
)
```

That method:

Computes affected dates from scrobbles

Deletes only affected DailyListen rows

Recomputes from scrobbles

Upserts results

No side effects beyond that scope.

### Merge behavior (Recording B → Recording A)

This is the critical production scenario.

Step 1: Update scrobbles

`Scrobble.where(recording_id: B).update_all(recording_id: A)`

Step 2: Targeted reaggregation

```
DailyListen::Aggregator.reaggregate_recordings!(
  user_id: user.id,
  recording_ids: [A, B]
)
```

That’s it.

No global rebuild.
No guessing.
No drift.
