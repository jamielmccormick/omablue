# Contributing

OmaBlue is in an early security and feasibility phase. Discuss substantial
changes before implementation.

## Requirements

- Keep SIP enabled and preserve the documented security boundaries.
- Do not add telemetry, hosted relays, public tunnels, or credential custody.
- Do not include real message data in fixtures, logs, screenshots, or issues.
- Add tests and documentation for behavioral changes.
- Keep networking, persistence, and credentials outside QML.
- Preserve upstream licenses and update third-party notices when dependencies
  change.

Contributions use the Developer Certificate of Origin. Sign commits with
`git commit -s` to certify the contribution under the repository license.

## Workflow

1. Start with a requirement or architecture decision under `docs/`.
2. Implement the smallest coherent change.
3. Add tests, failure cases, and redacted diagnostics.
4. Run repository validation.
5. Document new constraints or lessons so later work compounds them.
