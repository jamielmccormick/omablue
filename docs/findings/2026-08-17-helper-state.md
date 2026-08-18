# Helper State and Replay Handling

## Implemented

- Cursor state is stored as a small atomic JSON document under a mode-`0700`
  directory.
- Cursor files are mode `0600`, reject symlinks and insecure permissions, and
  are replaced only after the temporary file is flushed and synchronized.
- Corrupt state is reported instead of being silently reset.
- A cursor can be committed only when its source instance and database
  generation match.
- Watch events are decoded into the typed Protocol v1 model.
- Event IDs are retained in a bounded replay window.
- Events are classified before application and committed afterward, so a failed
  application does not advance durable state.
- Generation-mismatched events fail closed; resync events require an explicit
  reset.

## Remaining Work

The next helper layer will connect these primitives to reconnect orchestration,
attachment policy, notifications, and the presentational Quickshell service.
