# Threat Model

## Summary

OmaBlue is a high-value remote-control service. A successful compromise can
expose years of private conversations and send messages as the user. Network
parsers must not run with Messages permissions.

## Assets

- Message bodies, metadata, contacts, attachments, and conversation graph
- Authority to send messages
- Full Disk Access and Messages Automation grants
- SSH, Tailscale, signing, and release credentials
- Linux cursors, caches, notifications, and diagnostic output

## Trust Boundaries

1. Messages storage to the signed Mac agent
2. The TCC-authorized agent to the unprivileged forced-command process
3. The Mac to OpenSSH and Tailscale
4. Remote protocol data to the Linux helper
5. The helper to the unsandboxed Quickshell plugin
6. Attachments to previewers and user-selected applications
7. Source control to CI, signing, and release artifacts

## Primary Threats

### Unauthorized Message Access or Sending

Mitigations:

- Default-deny Tailnet rule for the Mac SSH port
- Dedicated SSH key and host-key pinning
- `restrict` plus a fixed forced command
- No generic SQL, AppleScript, shell, path, or URL operations
- Separate read and send capabilities where practical
- Device revocation and short, content-free audit records

### Network Parser Compromise Inherits FDA

Mitigations:

- Signed agent owns FDA and Automation but has no network listener
- Forced-command process has no TCC permissions
- Narrow mode-`0600` Unix socket with peer validation
- Typed operation allowlist and strict size/deadline limits

### Duplicate or Misreported Sends

Mitigations:

- Durable idempotency key and payload hash before dispatch
- Distinct accepted, observed, failed, and outcome-unknown states
- Never automatically retry an ambiguous send
- Reconcile outcomes against the Messages database when possible

### Malicious Message Content

Mitigations:

- Render text as data, not HTML or Markdown
- Escape controls, terminal sequences, bidi overrides, and unsafe URLs
- Never interpolate content into shell commands
- Bound Unicode, regular expression, frame, and allocation work

### Malicious Attachments

Mitigations:

- No automatic download or opening by default
- Opaque local filenames and strict byte limits
- Reject traversal, symlinks, special files, and unsupported roots
- Verify content type and digest independently of filename
- No automatic archive extraction or remote preview fetching
- Keep parsing outside the Messages-authorized process

### Stolen Linux Device

Mitigations:

- Dedicated revocable SSH key
- Minimal cache in the first release
- Mode-`0700` state and mode-`0600` credentials
- Encrypted bounded cache before offline history is added
- Notification preview controls

### Supply-Chain Compromise

Mitigations:

- Locked dependencies and SHA-pinned CI actions
- No release secrets in pull-request workflows
- Signed tags, checksums, SBOM, provenance, and notarization
- Private vulnerability reporting
- No `curl | sh` installation path

## Security Release Gates

- No unresolved critical or high findings
- SIP and Gatekeeper remain enabled
- No LAN or public message listener
- FDA belongs only to the stable signed agent identity
- Unknown Messages schema fails closed
- Send ambiguity and database replacement tests pass
- Path, parser, content, and protocol fuzzing pass
- Logs and support bundles pass automated privacy tests
- Artifact signatures and provenance verify from a clean environment

## Out of Scope

OmaBlue cannot protect messages after root compromise, after compromise of an
unlocked endpoint account, or from Apple platform/service compromise. It does
not provide a new end-to-end encryption layer beyond the intended private
transport between the user's endpoints.
