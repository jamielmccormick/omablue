# OmaBlue macOS Feasibility Harness

This harness tests the macOS permission and lifecycle boundary without reading
messages or sending anything.

It builds an application bundle containing:

- `OmaBlueFeasibility`: controller for `SMAppService` registration and status
- `OmaBlueFeasibilityAgent`: per-user agent that performs content-free probes

## Safety

The agent opens `~/Library/Messages/chat.db` and immediately closes it without
reading bytes or querying rows. It asks Messages for its application version to
test Apple Events authorization, but it does not persist that version or send a
message.

Only redacted status fields are written to:

```text
~/Library/Application Support/OmaBlue/feasibility-status.json
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

The app is produced under `dist/`. Copy it to `/Applications` before registering
the agent so subsequent runs use a stable path and code identity.

## Commands

```sh
APP="/Applications/OmaBlue Feasibility.app/Contents/MacOS/OmaBlueFeasibility"
"$APP" status
"$APP" register
"$APP" open-settings
"$APP" unregister
```

Follow the complete matrix in
`docs/plans/2026-08-16-macos-tcc-feasibility-plan.md`.
