# Local Helper Process

## Boundary

The Omarchy service starts one `omablue-helper` process and communicates with
it over stdin/stdout. QML does not receive SSH key material, read the SSH
configuration, or construct transport arguments.

The local command set is intentionally smaller than the remote protocol:

- `status` requests bridge capabilities and source identity.
- `sync` requests a bounded batch using the helper-owned cursor.
- `ack` confirms that QML applied the complete sync batch.
- `reset` explicitly clears the durable cursor after a reported database
  generation change.

Unknown fields, unsupported protocol versions, empty request IDs, invalid sync
limits, oversized frames, and malformed JSON fail closed.

## Cursor Commit Rule

The helper holds a sync response in memory after writing it. QML replaces its
in-memory conversation/message/event models first, then sends an ACK naming the
response request ID. Only then does the helper atomically commit the response's
next cursor. A shell or helper crash before the ACK causes the batch to replay,
which is safer than silently skipping messages.

The SSH stdio proxy closes its input with a transport-only EOT marker followed
by a half-close. The Mac agent strips that marker before the adapter sees the
request and can terminate the adapter if the marker is absent.

Watch orchestration uses the typed `ReadOnlySession` and `WatchSession` APIs;
the QML watch command remains deliberately disabled until its bidirectional ACK
loop is implemented.
