#!/usr/bin/env bash
set -euo pipefail

readonly version="0.14.1"
readonly archive_sha256="04f82882cf0ef56b9d677b0c1fcd8b7d6fa9b62c51c468c22566ceeac2379864"
readonly archive_url="https://github.com/openclaw/imsg/releases/download/v${version}/imsg-macos.zip"

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
destination="$root/.build/imsg-v${version}"
archive="$root/.build/imsg-v${version}.zip"

if [[ ! -x $destination/imsg ]]; then
  rm -rf -- "$destination"
  mkdir -p "$root/.build" "$destination"
  curl --fail --location --silent --show-error \
    --output "$archive" \
    "$archive_url"
  printf '%s  %s\n' "$archive_sha256" "$archive" | shasum -a 256 --check --status
  ditto -x -k "$archive" "$destination"
  rm -f -- "$destination/imsg-bridge-helper.dylib"
  chmod 0755 "$destination/imsg"
fi

codesign --verify --strict --verbose=2 "$destination/imsg" >/dev/null
printf '%s\n' "$destination"
