# Physical Status Verification

## Environment

- Linux helper ran from the installed OmaBlue plugin.
- Mac used the same-team signed feasibility app build 13.
- SSH used a dedicated Ed25519 key, strict host-key checking, and the forced
  `OmaBlueBridgeStdio` command.
- The Mac agent owned a mode-`0600` Unix socket in its mode-`0700` state
  directory.

## Result

The content-free `status` request completed end to end and returned Protocol v1
capabilities, server version, and source identity. No `sync`, `watch`, message
body, contact, attachment, or conversation data was requested or emitted.

The verified path was:

```text
omablue-helper -> /usr/bin/ssh -> forced authorized_keys command
-> OmaBlueBridgeStdio -> signed agent Unix socket
-> OmaBlueIMsgAdapter -> content-free status response
```

The initial attempts also exposed and fixed three transport issues: SSH config
could select an unrestricted key, paths with spaces needed escaped command
quotes, and the helper had to half-close SSH stdin after writing a request so
the Mac pipe reader could finish its bounded frame.
