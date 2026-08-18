# Restricted SSH Transport

## Implemented Boundary

- The Linux helper invokes an absolute OpenSSH executable directly, never a
  shell.
- No remote command is supplied; the Mac `authorized_keys` entry forces the
  signed no-TCC stdio bridge.
- PTY, agent forwarding, X11 forwarding, port forwarding, proxy commands,
  proxy jumps, remote commands, local commands, and environment forwarding are
  disabled.
- Batch mode, strict host-key checking, a pinned `known_hosts` path, a
  dedicated identity path, and connection liveness limits are required.
- Request and response frames are bounded to 1 MiB and use one JSON object per
  line.
- Non-watch responses must carry the request ID that was sent. Watch streams
  are exposed as one frame at a time without treating a write as an
  acknowledgment.

## Not Yet Implemented

- Attachment transfer
- Quickshell integration
