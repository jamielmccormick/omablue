---
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
date: 2026-08-16
status: active
---

# macOS TCC Feasibility Plan

## Goal

Prove that a stable signed OmaBlue agent can retain Full Disk Access and
Messages Automation across realistic lifecycle events while an unprivileged
remote process remains outside that permission boundary.

The harness does not read message rows or send messages. It opens `chat.db`
without reading content and asks Messages only for its application version.

## Acceptance Gate

The feasibility spike passes only when all required cases produce the expected
result without granting Full Disk Access to Terminal, SSH, a shell, or a shared
runtime.

| Case | Database | Messages Automation | Agent lifecycle |
|---|---|---|---|
| Fresh install before consent | denied | denied or not requested | enabled or awaiting approval |
| After explicit consent | readable | version query succeeds | enabled |
| Agent restart | readable | succeeds | relaunches cleanly |
| Main app closed | readable | succeeds | remains independent |
| Screen locked | readable | succeeds | remains healthy |
| Sleep and wake | readable after reconciliation | succeeds | remains or relaunches |
| Logout and login | readable after login | succeeds | bootstraps per user |
| Reboot and login | readable after login | succeeds | bootstraps per user |
| Same-team signed update | readable without regrant | succeeds | updated agent runs |
| FDA revoked | denied and reported | unaffected | remains healthy |
| Automation revoked | readable | denied and reported | remains healthy |
| Messages quit | readable | query may relaunch or fail clearly | remains healthy |

## Test Variants

1. Ad-hoc signed development bundle for functional iteration
2. Apple Development signed bundle for responsible-process inspection
3. Developer ID signed and notarized bundle for release-equivalent identity
4. Agent directly performing probes
5. Agent supervising a bundled `imsg rpc` child

Variant 5 is the architectural go/no-go case. If the child cannot reliably use
the intended responsible identity, the `imsg` adapter must be linked or moved
into the agent boundary.

## Diagnostics

Collect only:

- Timestamp
- App and agent bundle identifiers and versions
- Agent PID and effective UID
- `SMAppService` status
- Boolean database-open result and redacted error domain/code
- Boolean Messages-version query result and Apple Event error number
- macOS version, architecture, signing identity, and code requirement

Never collect database contents, paths outside the fixed Messages database,
Messages version text, account data, contacts, message metadata, or attachment
information.

## Procedure

1. Build with `apps/mac-bridge/feasibility/build.sh` on the physical Mac.
2. Copy the app to `/Applications/OmaBlue Feasibility.app`.
3. Inspect nested signatures and entitlements before first launch.
4. Run the controller's `register` command.
5. Approve the background item if macOS reports `requiresApproval`.
6. Add only OmaBlue Feasibility to Full Disk Access.
7. Trigger the Messages Automation probe and approve only Messages control.
8. Inspect the content-free status JSON written by the agent.
9. Execute every lifecycle row in the acceptance matrix.
10. Repeat with the supervised `imsg` child variant before accepting ADR 0001.

## Failure Rules

- Do not grant FDA to Terminal or Remote Login to make the test pass.
- Do not disable SIP, library validation, Hardened Runtime, or Gatekeeper.
- Do not edit TCC databases.
- Do not continue to message synchronization after an unexplained permission
  inheritance result.
- Preserve failed cases as tests and architecture findings.
