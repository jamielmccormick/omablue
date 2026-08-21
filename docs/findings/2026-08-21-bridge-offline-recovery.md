# 2026-08-21: Bridge Offline Recovery

## Summary

The plugin showed "Mac bridge offline" after a while. Four independent
defects combined to cause it; all are fixed and covered by the changes in
this commit.

## Root Causes

1. `resync_required` dead end. The Mac derives its database generation from
   `chat.db` file attributes, so every incoming iMessage changes the
   generation. The next sync failed with `resync_required`, which the plugin
   treated as a permanent error with no recovery path.

2. No retry once connected. All periodic timers stopped once
   `helperReady` became true, so a single failed request left the plugin
   offline forever until a shell restart.

3. Silent session rejection. The Mac bridge socket server served one session
   at a time and closed concurrent clients without any response. A request
   slower than the plugin's 1.5 s status timeout caused pipelining against a
   busy server, so healthy-but-slow responses surfaced as instant EOF
   (`ssh_eof`) on the helper side. A wedged adapter could pin the slot
   forever.

4. Adapter error frames carried `request_id: null`. The helper's strict
   response validation rejected legitimate remote errors (for example
   `upstream_rpc_error` before FDA was granted) as request-id mismatches,
   masking the real code behind a generic transport error.

## Fixes

### Plugin (`plugin/Service.qml`)

- `resync_required` now triggers an automatic cursor reset and resync.
- Health check timer retries status every 4 s while an error is latched.
- Sync poll refreshes messages every 20 s while idle.
- The helper process is relaunched automatically if it dies.
- Error text clears only on a proven-good response, not optimistically.
- Status timeout raised to 8 s and startup retries slowed to 2 s so slow
  Mac responses no longer cause pipelining.

### Mac socket server (`apps/mac-bridge/ipc/BridgeSocketServer.swift`)

- Sessions serialize through a semaphore: concurrent clients wait up to
  30 s for the slot instead of being dropped silently.
- Every session has a 180 s watchdog with SIGTERM then SIGKILL escalation,
  so no wedged adapter can pin the slot forever.
- Optional byte-count-only debug logging behind `OMABLUE_BRIDGE_DEBUG=1`.

### Adapter (`apps/mac-bridge/adapter/Sources/main.swift`)

- Error frames echo the parsed request id when one was parsed, so helpers
  can attribute remote failures correctly.

### Helper (`crates/omablue-helper`)

- Error frames with null request ids are accepted as remote errors; data
  frames still require exact ids.
- Transport error-code mapping now distinguishes request-id mismatch,
  closed transport, and invalid configuration instead of collapsing them
  into `remote_unavailable`.
- Agent startup on the Mac retries up to three times and records failures
  in `startup-error.log` (content-free error text only), clearing the file
  on success.

## Deployment Notes

- SMAppService registration of the launch agent proved flaky after repeated
  ad-hoc bundle replacements (`spawn failed`, exit 78 loops). The agent is
  now registered as a classic user LaunchAgent at
  `~/Library/LaunchAgents/com.jamielmccormick.omablue.feasibility-agent.plist`
  with identical KeepAlive behavior. TCC grants follow the code identity,
  not the launcher.
- Each ad-hoc re-signed replacement invalidates Full Disk Access and
  Contacts grants once; Developer ID signing will remove this churn before
  public alpha.
