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
  apps/mac-bridge/feasibility/build.sh
)

for file in "${required_files[@]}"; do
  [[ -s "$repo_root/$file" ]] || {
    printf 'missing or empty required file: %s\n' "$file" >&2
    exit 1
  }
done

if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout \
    "$repo_root/apps/mac-bridge/feasibility/Resources/Info.plist" \
    "$repo_root/apps/mac-bridge/feasibility/Resources/com.jamielmccormick.omablue.feasibility-agent.plist" \
    "$repo_root/apps/mac-bridge/feasibility/Resources/Controller.entitlements" \
    "$repo_root/apps/mac-bridge/feasibility/Resources/Agent.entitlements"
fi

printf 'OmaBlue repository validation passed.\n'
