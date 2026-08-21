# OmaBlue Bridge

Native macOS setup application and per-user signed agent.

The agent runs as the logged-in user, keeps SIP enabled, supervises the
`imsg` adapter, and exposes only a private Unix socket. See
[macos/](macos/) for the build and the permission test matrix.
