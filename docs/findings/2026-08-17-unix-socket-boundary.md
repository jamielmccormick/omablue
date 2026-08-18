# Unix Socket Boundary

## Decision

The TCC-authorized agent owns a per-user Unix stream socket. The forced-command
stdio process has no Messages permissions and forwards bytes between SSH stdio
and that socket. The agent launches the already signed adapter only after
validating its code identity.

## Boundary Rules

- The state directory is owned by the current user and mode `0700`.
- The socket and lock file are owned by the current user and mode `0600`.
- Existing socket paths must be real sockets, not symlinks or regular files.
- A stale socket is removed only when connecting returns `ECONNREFUSED`.
- A second agent instance fails the lock rather than sharing the endpoint.
- A client must have the same effective UID and exact signing identity as the
  agent, including the Team ID when present.
- Only one active adapter session is allowed.
- Reads and writes use bounded chunks; the proxy never parses or logs message
  content.
- The stdio proxy sends a reserved EOT transport marker before its normal
  half-close; the agent strips it and uses its absence to detect an abandoned
  client.
- Closing either side terminates the adapter and closes the other side.

## Current Scope

This boundary supports the existing Protocol v1 NDJSON stream. The adapter
accepts one request frame per connection, while `watch` keeps the connection
open for events. Forced-command SSH configuration and the Rust helper remain
later integration steps.
