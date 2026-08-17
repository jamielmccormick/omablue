# Finite imsg Adapter Finding

Date: 2026-08-17

## Result

The first signed OmaBlue adapter successfully translated a content-free physical
`status` request on the Apple silicon test Mac.

- Protocol version: 1
- Read capability: available
- Watch capability: available
- Send capabilities: disabled
- Source instance: persisted without message data
- Database generation: derived from filesystem identity
- Bundled upstream: `imsg v0.14.1`
- SIP: enabled
- Same-team build 5 to build 6 update: FDA persisted

No conversation or message payload was emitted during physical verification.

## CI Coverage

- Swift compilation on a clean macOS runner
- Synthetic status translation
- Synthetic chats and `messages.after` translation
- Unknown request-field rejection
- Unknown service and missing unread values remain null
- Attachment paths reduce to display-only basenames
- Adapter, agent, app, and upstream nested signatures verify
- Rust Protocol v1 fixtures round-trip against the same output contract

## Remaining Work

- Add a local-only verification mode that checks sync counts and invariants
  without printing personal content.
- Supervise one long-running `imsg rpc` process for watch.
- Add overflow recovery and cursor reconciliation.
- Place the adapter behind the private agent IPC boundary before remote access.
