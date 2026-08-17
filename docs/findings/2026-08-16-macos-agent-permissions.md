# macOS Agent Permission Finding

Date: 2026-08-16

## Environment

- Physical Apple silicon Mac
- macOS 26.5.2
- Xcode 26.6
- Swift 6.3.3
- SIP enabled
- Ad-hoc signed OmaBlue feasibility bundle with Hardened Runtime
- Per-user agent registered through `SMAppService`

## Probe Scope

The agent opened and immediately closed the fixed Messages database path without
reading bytes or querying rows. It asked Messages only for its application
version and did not retain the returned value or send a message.

## Results

| Case | Result |
|---|---|
| Build and nested signature verification | Pass |
| Embedded LaunchAgent registration | Pass |
| Agent starts with main controller closed | Pass |
| Database before Full Disk Access | Denied with `NSCocoaErrorDomain` code 513 |
| Database after granting app Full Disk Access | Pass |
| Messages application-version Apple Event | Pass |
| Kill and automatic agent relaunch | Pass; PID changed and both permissions remained usable |
| Explicit unregister/register | Pass; agent stopped, restarted, and both permissions remained usable |
| Status file permissions | Pass; mode `0600` |
| Replace changed bundle without incrementing `CFBundleVersion` | Fails closed with `EX_CONFIG` and `needs LWCR update` |
| Replace ad-hoc signed bundle with incremented build | Agent launches; FDA consent does not persist across the changed ad-hoc code identity |
| Resource lookup from LaunchAgent `argv[0]` | `argv[0]` is relative; bundle resources must resolve through `Bundle.main` |

## Architectural Evidence

On this macOS release and bundle layout, the embedded agent registered by
`SMAppService` successfully uses Full Disk Access granted to the containing
OmaBlue application. The main controller does not need to remain running.

This does not yet prove that an `imsg rpc` child inherits the same responsible
identity, that a Developer ID update preserves consent, or that permissions
survive logout, reboot, and sleep/wake. Those remain release gates.

macOS also requires each changed background-item bundle to advance its build
number. OmaBlue release tooling must reject a non-increasing
`CFBundleVersion`; replacing changed code under the same value leaves the
registered job enabled but unable to spawn.

The ad-hoc update correctly did not preserve FDA because changing the bundle
changed its ad-hoc designated requirement. Permission persistence must be tested
with two builds signed by the same Apple Development or Developer ID identity;
development results must not be generalized to release updates.

## Follow-up

1. Add a pinned `imsg` child probe that requests only status and database
   readiness.
2. Test lock, sleep/wake, logout/login, and reboot/login.
3. Repeat with a same-team Developer ID signed update.
4. Inspect responsible-process diagnostics during the child probe.
