# OmaBlue Omarchy Helper

The `omablue-helper` crate owns the Linux-side restricted SSH transport. It
starts an absolute-path OpenSSH client with no user SSH config, no remote
command, no PTY, no forwarding, strict host-key checking, and a dedicated
identity path.

The transport sends and receives bounded NDJSON frames and validates request
IDs before returning a response. Watch requests remain streaming and expose
frames one at a time to the typed cursor and deduplication layer.

The helper now also provides a mode-`0700` state directory with an atomic,
mode-`0600` cursor file and a bounded event ledger. Cursors are committed only
after event application, replayed event IDs are suppressed, and database
generation changes require an explicit reset.

Attachment validation, notifications, and redacted diagnostics remain the next
helper-layer milestones.

Credentials, persistence, and network behavior will not live in QML.

See [the Mac forced-command setup](../../apps/mac-bridge/ssh/README.md).
