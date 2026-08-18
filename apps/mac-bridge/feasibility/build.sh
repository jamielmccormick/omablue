#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
build_dir="$root/.build"
dist_dir="$root/dist"
app="$build_dir/OmaBlue Feasibility.app"
contents="$app/Contents"
identity="${OMABLUE_CODESIGN_IDENTITY:--}"
include_imsg="${OMABLUE_INCLUDE_IMSG:-0}"
build_number="${OMABLUE_BUILD_NUMBER:-1}"

for command_name in xcrun codesign plutil; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'required macOS command not found: %s\n' "$command_name" >&2
    exit 1
  }
done

rm -rf -- "$build_dir"
mkdir -p "$build_dir" "$contents/MacOS" "$contents/Library/LaunchAgents"

xcrun --sdk macosx swiftc \
  -framework AppKit \
  -framework Foundation \
  -framework Contacts \
  -framework ServiceManagement \
  "$root/Sources/Controller/main.swift" \
  -o "$contents/MacOS/OmaBlueFeasibility"

xcrun --sdk macosx swiftc \
  -framework AppKit \
  -framework Foundation \
  -framework Security \
  "$root/../ipc/UnixSocket.swift" \
  "$root/../ipc/CodeIdentity.swift" \
  "$root/../ipc/BridgeSocketServer.swift" \
  "$root/Sources/Agent/main.swift" \
  -o "$contents/MacOS/OmaBlueFeasibilityAgent"

xcrun --sdk macosx swiftc \
  -framework Foundation \
  -framework Security \
  "$root/../ipc/UnixSocket.swift" \
  "$root/../ipc/CodeIdentity.swift" \
  "$root/../ipc/StdioBridge/main.swift" \
  -o "$contents/MacOS/OmaBlueBridgeStdio"

xcrun --sdk macosx swiftc \
  -framework Foundation \
  "$root/../ipc/Tests/EchoAdapter/main.swift" \
  -o "$build_dir/OmaBlueEchoAdapter"
xcrun --sdk macosx swiftc \
  -framework Foundation \
  -framework Security \
  "$root/../ipc/UnixSocket.swift" \
  "$root/../ipc/CodeIdentity.swift" \
  "$root/../ipc/BridgeSocketServer.swift" \
  "$root/../ipc/Tests/SocketBoundary/main.swift" \
  -o "$build_dir/OmaBlueSocketBoundaryTests"
test_identity="com.jamielmccormick.omablue.ipc-test"
codesign --force --sign - --identifier "$test_identity" "$build_dir/OmaBlueEchoAdapter"
codesign --force --sign - --identifier "$test_identity" "$build_dir/OmaBlueSocketBoundaryTests"
"$build_dir/OmaBlueSocketBoundaryTests" "$build_dir/OmaBlueEchoAdapter"

xcrun --sdk macosx swiftc \
  -framework Foundation \
  -framework Contacts \
  "$root/../adapter/Sources/AdapterCore.swift" \
  "$root/../adapter/Sources/ContactDirectory.swift" \
  "$root/../adapter/Sources/IMsgRPC.swift" \
  "$root/../adapter/Sources/PersistentIMsgRPC.swift" \
  "$root/../adapter/Sources/SourceIdentity.swift" \
  "$root/../adapter/Sources/WatchBridge.swift" \
  "$root/../adapter/Sources/main.swift" \
  -o "$contents/MacOS/OmaBlueIMsgAdapter"

xcrun --sdk macosx swiftc \
  -framework Foundation \
  -framework Contacts \
  "$root/../adapter/Sources/AdapterCore.swift" \
  "$root/../adapter/Sources/ContactDirectory.swift" \
  "$root/../adapter/Tests/main.swift" \
  -o "$build_dir/OmaBlueAdapterTests"
"$build_dir/OmaBlueAdapterTests" "$root/../adapter/Fixtures"

xcrun --sdk macosx swiftc \
  -framework Foundation \
  "$root/../adapter/Tests/FakeIMsg/main.swift" \
  -o "$build_dir/FakeIMsg"
xcrun --sdk macosx swiftc \
  -framework Foundation \
  "$root/../adapter/Sources/AdapterCore.swift" \
  "$root/../adapter/Sources/PersistentIMsgRPC.swift" \
  "$root/../adapter/Tests/PersistentRPC/main.swift" \
  -o "$build_dir/OmaBluePersistentRPCTests"
"$build_dir/OmaBluePersistentRPCTests" "$build_dir/FakeIMsg"
xcrun --sdk macosx swiftc \
  -framework Foundation \
  "$root/../adapter/Sources/AdapterCore.swift" \
  "$root/../adapter/Sources/PersistentIMsgRPC.swift" \
  "$root/../adapter/Sources/SourceIdentity.swift" \
  "$root/../adapter/Sources/WatchBridge.swift" \
  "$root/../adapter/Tests/WatchBridge/main.swift" \
  -o "$build_dir/OmaBlueWatchBridgeTests"
"$build_dir/OmaBlueWatchBridgeTests" "$build_dir/FakeIMsg"

cp "$root/Resources/Info.plist" "$contents/Info.plist"
cp \
  "$root/Resources/com.jamielmccormick.omablue.feasibility-agent.plist" \
  "$contents/Library/LaunchAgents/"

plutil -replace CFBundleVersion -string "$build_number" "$contents/Info.plist"

if [[ $include_imsg == "1" ]]; then
  imsg_source="$($root/fetch-imsg.sh)"
  mkdir -p "$contents/Resources/imsg"
  cp "$imsg_source/imsg" "$contents/Resources/imsg/imsg"
  cp -R "$imsg_source/PhoneNumberKit_PhoneNumberKit.bundle" "$contents/Resources/imsg/"
  cp -R "$imsg_source/SQLite.swift_SQLite.bundle" "$contents/Resources/imsg/"
  codesign --verify --strict --verbose=2 "$contents/Resources/imsg/imsg"
fi

plutil -lint "$contents/Info.plist"
plutil -lint "$contents/Library/LaunchAgents/com.jamielmccormick.omablue.feasibility-agent.plist"

sign_args=(--force --sign "$identity" --options runtime)
bundle_identifier="$(plutil -extract CFBundleIdentifier raw "$contents/Info.plist")"
sign_args+=(--identifier "$bundle_identifier")
if [[ $identity != "-" ]]; then
  sign_args+=(--timestamp)
fi

codesign "${sign_args[@]}" \
  --entitlements "$root/Resources/Agent.entitlements" \
  "$contents/MacOS/OmaBlueFeasibilityAgent"
codesign "${sign_args[@]}" \
  --entitlements "$root/Resources/Controller.entitlements" \
  "$contents/MacOS/OmaBlueIMsgAdapter"
codesign "${sign_args[@]}" \
  --entitlements "$root/Resources/Controller.entitlements" \
  "$contents/MacOS/OmaBlueBridgeStdio"
codesign "${sign_args[@]}" \
  --entitlements "$root/Resources/Controller.entitlements" \
  "$app"

codesign --verify --deep --strict --verbose=2 "$app"

mkdir -p "$dist_dir"
rm -rf -- "$dist_dir/OmaBlue Feasibility.app"
mv -- "$app" "$dist_dir/OmaBlue Feasibility.app"
printf 'Built %s\n' "$dist_dir/OmaBlue Feasibility.app"
