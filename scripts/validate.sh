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
  docs/threat-model.md
  plugin/manifest.json
)

for file in "${required_files[@]}"; do
  [[ -s "$repo_root/$file" ]] || {
    printf 'missing or empty required file: %s\n' "$file" >&2
    exit 1
  }
done

printf 'OmaBlue repository validation passed.\n'
