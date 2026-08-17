# Architecture

## Security Boundary

The Messages-authorized macOS agent has no network listener. A separately
invoked forced-command executable handles remote framing and forwards only
allowlisted operations through a private Unix socket.

```text
Messages.app and chat.db
          |
Signed macOS agent
  - Full Disk Access
  - Messages Automation
  - imsg adapter
          |
Unix socket (0600)
          |
Forced-command executable
  - no Messages permissions
          |
OpenSSH over Tailscale
          |
Rust helper
          |
Quickshell service and UI
```

## macOS Components

The signed native application provides setup, diagnostics, and a stable TCC
identity. It registers a per-user background item through `SMAppService`. The
agent supervises a pinned `imsg rpc` adapter and translates upstream models into
the OmaBlue protocol.

The first feasibility gate determines whether the agent can reliably remain the
responsible TCC identity while supervising the adapter. If not, the adapter must
move into the signed executable boundary.

## Transport

The first transport is a dedicated OpenSSH key restricted to the OmaBlue stdio
command. Tailscale limits network reachability but is not treated as application
authorization. The Mac agent remains unreachable from the network directly.

## Linux Components

The Rust helper owns SSH, host-key verification, reconnect behavior, cursors,
deduplication, notifications, attachments, and diagnostics. The Quickshell
plugin consumes helper state and renders it using Omarchy semantic theme tokens.

## Authority and Recovery

Messages storage remains the source of truth. OmaBlue stores only rebuildable
state and command outcomes. Cursors are scoped to a source instance and database
generation. Generation changes require an explicit resync.

Send results distinguish acceptance from observation. A lost or ambiguous send
response becomes `outcome_unknown` and requires reconciliation or user action;
it is never blindly retried.
