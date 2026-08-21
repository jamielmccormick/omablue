# OmaBlue macOS App

The signed macOS side of OmaBlue: a controller, a per-user background agent,
the `imsg` adapter boundary, and the restricted stdio bridge used by the
forced-command SSH transport.

It builds an application bundle containing:

- `OmaBlueController`: registration and permission helpers
- `OmaBlueAgent`: per-user agent supervising the `imsg` adapter over a
  private Unix socket
- `OmaBlueIMsgAdapter`: converts pinned `imsg` JSON-RPC output into the
  versioned OmaBlue protocol
- `OmaBlueBridgeStdio`: forced-command entry point for the Linux helper

## Safety

The agent opens `~/Library/Messages/chat.db` and immediately closes it without
reading bytes or querying rows. It asks Messages for its application version to
test Apple Events authorization, but it does not persist that version or send a
message.

Only redacted status fields are written to:

```text
~/Library/Application Support/OmaBlue/agent-status.json
```

## Build

Run on macOS 14 or newer with Xcode command-line tools:

```sh
./build.sh
```

For release-equivalent identity testing:

```sh
OMABLUE_CODESIGN_IDENTITY="Developer ID Application: Example (TEAMID)" ./build.sh
```

To include the pinned, checksum-verified `imsg v0.14.1` child probe:

```sh
OMABLUE_INCLUDE_IMSG=1 ./build.sh
```

The fetch script intentionally excludes `imsg-bridge-helper.dylib`; OmaBlue does
not ship or test the injected private-API bridge.

Every installed update must use a higher bundle build number so macOS refreshes
the background item's launch constraint:

```sh
OMABLUE_BUILD_NUMBER=2 OMABLUE_INCLUDE_IMSG=1 ./build.sh
```

The app is produced under `dist/`. Copy it to `/Applications` before registering
the agent so subsequent runs use a stable path and code identity.

## Commands

```sh
APP="/Applications/OmaBlue.app/Contents/MacOS/OmaBlueController"
"$APP" status
"$APP" register
"$APP" open-settings
"$APP" unregister
```

Follow the complete matrix in
`docs/plans/2026-08-16-macos-tcc-feasibility-plan.md`.
