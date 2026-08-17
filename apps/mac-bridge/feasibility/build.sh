#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
build_dir="$root/.build"
dist_dir="$root/dist"
app="$dist_dir/OmaBlue Feasibility.app"
contents="$app/Contents"
identity="${OMABLUE_CODESIGN_IDENTITY:--}"

for command_name in xcrun codesign plutil; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'required macOS command not found: %s\n' "$command_name" >&2
    exit 1
  }
done

rm -rf -- "$build_dir" "$dist_dir"
mkdir -p "$build_dir" "$contents/MacOS" "$contents/Library/LaunchAgents"

xcrun --sdk macosx swiftc \
  -framework Foundation \
  -framework ServiceManagement \
  "$root/Sources/Controller/main.swift" \
  -o "$contents/MacOS/OmaBlueFeasibility"

xcrun --sdk macosx swiftc \
  -framework AppKit \
  -framework Foundation \
  "$root/Sources/Agent/main.swift" \
  -o "$contents/MacOS/OmaBlueFeasibilityAgent"

cp "$root/Resources/Info.plist" "$contents/Info.plist"
cp \
  "$root/Resources/com.jamielmccormick.omablue.feasibility-agent.plist" \
  "$contents/Library/LaunchAgents/"

plutil -lint "$contents/Info.plist"
plutil -lint "$contents/Library/LaunchAgents/com.jamielmccormick.omablue.feasibility-agent.plist"

sign_args=(--force --sign "$identity" --options runtime)
if [[ $identity != "-" ]]; then
  sign_args+=(--timestamp)
fi

codesign "${sign_args[@]}" \
  --entitlements "$root/Resources/Agent.entitlements" \
  "$contents/MacOS/OmaBlueFeasibilityAgent"
codesign "${sign_args[@]}" \
  --entitlements "$root/Resources/Controller.entitlements" \
  "$app"

codesign --verify --deep --strict --verbose=2 "$app"
printf 'Built %s\n' "$app"
