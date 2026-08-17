# OmaBlue finite imsg adapter

The first adapter accepts one bounded OmaBlue Protocol v1 request on stdin,
invokes the pinned `imsg rpc` child, and emits one JSON response on stdout.

Implemented requests:

- `status`: source identity and read/watch capabilities only
- `sync`: bounded chats and `messages.after` translation

The adapter:

- rejects unknown request fields
- validates source and database generation cursors
- imposes input, result, and process deadlines
- never emits Mac filesystem paths
- never fabricates unavailable service, unread, attachment ID, or actor data
- keeps every send capability disabled

Long-lived watch and all mutations are intentionally deferred. Translation tests
use only generated fixtures under `Fixtures/`.
