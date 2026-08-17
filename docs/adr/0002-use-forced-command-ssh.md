# ADR 0002: Use Forced-Command SSH for the First Transport

Status: Accepted

## Context

The first release supports one Linux client and one Mac on a private Tailnet.
Building an HTTP service, authentication system, TLS lifecycle, and WebSocket
transport would duplicate mature OpenSSH capabilities.

## Decision

Use regular OpenSSH over Tailscale with a dedicated Ed25519 key restricted by
`authorized_keys` to one OmaBlue stdio executable. Disable PTY, forwarding,
agent forwarding, X11, user RC, tunnels, and arbitrary commands.

## Consequences

- SSH provides encryption, host authentication, client authentication, and
  streaming without a custom network listener.
- The forced command has no Messages permissions and communicates with the
  signed agent over a private Unix socket.
- A later HTTPS/SSE transport may implement the same domain protocol without
  replacing the Mac agent.
