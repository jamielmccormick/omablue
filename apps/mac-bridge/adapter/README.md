# OmaBlue finite imsg adapter

The first adapter accepts one bounded OmaBlue Protocol v1 request on stdin,
invokes the pinned `imsg rpc` child, and emits one JSON response on stdout.

Implemented requests:

- `status`: source identity and read/watch capabilities only
- `sync`: bounded chats and `messages.after` translation
- `watch`: catch up from a client cursor, subscribe, and stream Protocol v1 events

The adapter:

- rejects unknown request fields
- validates source and database generation cursors
- imposes input, result, and process deadlines
- never emits Mac filesystem paths
- never fabricates unavailable service, unread, attachment ID, or actor data
- keeps every send capability disabled
- bounds lines, pending requests, notification count, and notification bytes
- recovers child termination and watch overflow through `messages.after`
- emits deterministic event IDs for replay deduplication

All mutations are intentionally deferred. Translation and recovery tests use
only generated fixtures under `Fixtures/`.
