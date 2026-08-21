# OmaBlue

OmaBlue is a secure, open-source Messages bridge for Omarchy, powered by a
user-owned Mac.

The project is in active development. It is not yet ready to install or use
with personal messages, and a public alpha has not shipped.

## Principles

- Keep System Integrity Protection enabled.
- Keep message transport private; no hosted relay, Firebase, or public tunnel.
- Give Messages permissions to the smallest stable macOS process.
- Treat every message and attachment as untrusted input.
- Make uncertain sends visible and never retry them automatically.
- Keep the Omarchy plugin thin and free of credentials.

## Planned Architecture

```text
Messages.app and chat.db
          |
Signed macOS agent -> imsg JSON-RPC
          |
Private Unix socket
          |
Restricted SSH command over Tailscale
          |
Rust Linux helper
          |
Omarchy Quickshell plugin
```

See [the product plan](docs/plans/2026-08-16-omablue-product-plan.md),
[architecture decisions](docs/adr/), and [threat model](docs/threat-model.md).

## Scope

The first supported configuration will be one Omarchy user, one physical Mac,
one Messages account, and regular OpenSSH over a private Tailnet. Features that
require disabling SIP or injecting into Messages are intentionally excluded.

## Status

A working read-only vertical slice runs end to end: a signed macOS agent with
Full Disk Access and Messages Automation supervises a pinned `imsg` release,
the restricted SSH transport streams versioned sync frames to a Rust helper,
and an Omarchy bar plugin renders conversations, unread counts, and contact
names. Live watch updates, safe sending, and attachment previews are in
progress. See the
[TCC test plan](docs/plans/2026-08-16-macos-tcc-feasibility-plan.md) and the
[macOS app](apps/mac-bridge/macos/).

## License

Apache License 2.0. See [LICENSE](LICENSE).

OmaBlue is not affiliated with or endorsed by Apple, Basecamp, Omarchy,
OpenClaw, the `imsg` maintainers, or the unrelated Secureblue project that also
uses the name Omablue.
