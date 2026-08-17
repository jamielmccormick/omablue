# Persistent Watch Recovery Finding

Date: 2026-08-17

## Result

The OmaBlue adapter now supports one persistent `imsg rpc` child and one
all-chat watch stream with bounded at-least-once delivery.

## Invariants

- Catch-up through `messages.after` always precedes `watch.subscribe`.
- The authoritative `next_rowid` advances the cursor, including empty pages.
- Catch-up and watch both set `include_reactions: true`.
- One physical row produces one cursor-bearing event.
- Message events carry an optional conversation snapshot atomically.
- Reaction rows produce explicit add/remove events rather than fake messages.
- Responses route only by JSON-RPC ID and may interleave with notifications.
- A watch overflow resumes from `resume_after_rowid` and catches up before
  resubscribing.
- Child failure restarts with bounded exponential backoff and always catches up
  before returning to live mode.
- Database-generation changes emit one terminal `resync_required` event.
- Unknown, malformed, oversized, or wrong-subscription records fail closed.

## Bounds

- 4 MiB maximum upstream line
- 8 pending RPC requests
- 64 queued notifications
- 8 MiB queued notification data
- 100 rows per recovery page
- 64-row upstream watch buffer
- 30-second maximum restart backoff

## Synthetic Test

The fake upstream produces:

1. Catch-up row 11
2. Live row 12
3. Terminal watch overflow with resume cursor 12
4. Recovery catch-up row 13

The adapter emits deterministic events in 11, 12, 13 order. The test also
verifies a notification arriving while a read response is pending.

## Signed Physical Verification

Team-signed build 7 ran the installed adapter on the physical Apple silicon Mac
against the same synthetic upstream. The output was reduced before display to
event type and cursor only:

```text
message_upsert 11
message_upsert 12
message_upsert 13
```

This verified catch-up, live delivery, overflow recovery, stable same-team FDA,
and the installed bundle path without reading or persisting personal message
payloads.

## Acknowledgment Limitation

Protocol v1 has no server-side cursor acknowledgment. The adapter's successful
stdout write is not proof that a client durably applied the event. The client
must reconnect using its own last committed cursor; replay is expected and
event application must be idempotent.

No personal Messages data was used or emitted during this milestone.
