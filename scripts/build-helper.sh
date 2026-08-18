#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cargo build --manifest-path "$root/Cargo.toml" --package omablue-helper --release --locked
mkdir -p "$root/plugin/bin"
install -m 0755 "$root/target/release/omablue-helper" "$root/plugin/bin/omablue-helper"
printf 'Built %s\n' "$root/plugin/bin/omablue-helper"
