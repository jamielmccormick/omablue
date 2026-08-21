#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

jq empty "$repo_root/plugin/manifest.json"

required_files=(
  README.md
  LICENSE
  NOTICE
  SECURITY.md
  SUPPORT.md
  GOVERNANCE.md
  CONTRIBUTING.md
  docs/plans/2026-08-16-omablue-product-plan.md
  docs/plans/2026-08-16-macos-tcc-feasibility-plan.md
  docs/threat-model.md
  plugin/manifest.json
  apps/mac-bridge/macos/build.sh
  apps/mac-bridge/macos/fetch-imsg.sh
  apps/mac-bridge/adapter/Sources/AdapterCore.swift
  apps/mac-bridge/adapter/Sources/IMsgRPC.swift
  apps/mac-bridge/adapter/Sources/PersistentIMsgRPC.swift
  apps/mac-bridge/adapter/Sources/SourceIdentity.swift
  apps/mac-bridge/adapter/Sources/WatchBridge.swift
  apps/mac-bridge/adapter/Sources/main.swift
  apps/mac-bridge/adapter/README.md
  apps/mac-bridge/adapter/Tests/main.swift
  apps/mac-bridge/adapter/Tests/FakeIMsg/main.swift
  apps/mac-bridge/adapter/Tests/PersistentRPC/main.swift
  apps/mac-bridge/adapter/Tests/WatchBridge/main.swift
  apps/mac-bridge/adapter/Fixtures/rpc-status.json
  apps/mac-bridge/adapter/Fixtures/rpc-chats.json
  apps/mac-bridge/adapter/Fixtures/rpc-messages-after.json
  apps/mac-bridge/ipc/UnixSocket.swift
  apps/mac-bridge/ipc/CodeIdentity.swift
  apps/mac-bridge/ipc/BridgeSocketServer.swift
  apps/mac-bridge/ipc/StdioBridge/main.swift
  apps/mac-bridge/ipc/Tests/EchoAdapter/main.swift
  apps/mac-bridge/ipc/Tests/SocketBoundary/main.swift
  apps/mac-bridge/ssh/authorized_keys.example
  apps/mac-bridge/ssh/README.md
  crates/omablue-helper/config.example.json
  crates/omablue-helper/src/lib.rs
  crates/omablue-helper/src/main.rs
  crates/omablue-helper/src/session.rs
  crates/omablue-helper/src/state.rs
  crates/omablue-helper/src/watch.rs
  plugin/Service.qml
  plugin/README.md
  scripts/build-helper.sh
  Cargo.toml
  crates/bridge-protocol/Cargo.toml
  protocol/v1.md
  protocol/fixtures/v1/status-response.json
  protocol/fixtures/v1/sync-response.json
  protocol/fixtures/v1/message-event.json
  docs/findings/2026-08-17-watch-recovery.md
  docs/findings/2026-08-17-unix-socket-boundary.md
  docs/findings/2026-08-17-ssh-transport.md
  docs/findings/2026-08-17-helper-state.md
  docs/findings/2026-08-17-local-helper.md
  docs/findings/2026-08-17-physical-status.md
)

for file in "${required_files[@]}"; do
  [[ -s "$repo_root/$file" ]] || {
    printf 'missing or empty required file: %s\n' "$file" >&2
    exit 1
  }
done

jq empty \
  "$repo_root/protocol/fixtures/v1/status-response.json" \
  "$repo_root/protocol/fixtures/v1/sync-response.json" \
  "$repo_root/protocol/fixtures/v1/message-event.json"

jq empty \
  "$repo_root/apps/mac-bridge/adapter/Fixtures/rpc-status.json" \
  "$repo_root/apps/mac-bridge/adapter/Fixtures/rpc-chats.json" \
  "$repo_root/apps/mac-bridge/adapter/Fixtures/rpc-messages-after.json"

if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout \
    "$repo_root/apps/mac-bridge/macos/Resources/Info.plist" \
    "$repo_root/apps/mac-bridge/macos/Resources/com.jamielmccormick.omablue.agent.plist" \
    "$repo_root/apps/mac-bridge/macos/Resources/Controller.entitlements" \
    "$repo_root/apps/mac-bridge/macos/Resources/Agent.entitlements"
fi

printf 'OmaBlue repository validation passed.\n'
