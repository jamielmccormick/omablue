---
artifact_contract: ce-unified-plan/v1
artifact_readiness: requirements-only
date: 2026-08-16
status: accepted
---

# OmaBlue Product Plan

## Problem

Omarchy users cannot read and send messages from Apple's Messages service in a
native desktop surface. Existing bridges typically require a hosted control
plane, public tunnel, broad legacy server, or disabled macOS security controls.

## Product Promise

OmaBlue provides an Omarchy-native Messages experience through a user-owned,
always-on Mac while keeping SIP enabled and message transport private.

## Primary User

One technical Omarchy user with one physical Mac signed into Messages and
reachable through a private Tailnet.

## Success Criteria

- The user can browse conversations and receive new messages without opening a
  separate desktop application.
- A sent message is either observed in Messages, reported failed, or clearly
  marked outcome unknown. OmaBlue never silently duplicates it.
- Sleep, network loss, shell restart, and Mac restart recover without silently
  skipping eligible messages.
- No OmaBlue process exposes message access on a LAN or public interface.
- SIP remains enabled and only the stable signed agent receives Full Disk
  Access and Messages Automation.
- Message bodies, attachments, contacts, and credentials never enter default
  logs or diagnostics.
- The UI responds to active Omarchy theme and font changes.

## MVP

- Mac permission and compatibility diagnostics
- Conversation list and unread counts
- Message history and live updates
- Text sends with explicit outcome state
- Delivery and read state where persisted by Messages
- Received reaction rendering
- Basic image and file attachments
- Optional contact names and avatars
- Desktop notifications
- Theme-aware bar widget and conversation panel
- Client revocation and complete uninstall documentation

## Excluded

- Disabling SIP, AMFI, Gatekeeper, or FileVault
- Private IMCore injection
- Typing indicators, edit, unsend, effects, polls, or group administration
- Firebase, hosted relays, public tunnels, port forwarding, or Funnel
- Multiple users, Macs, or Messages accounts
- Offline mutation queues
- Claims of Apple endorsement or complete Messages parity

## Product Decisions

- Omarchy-first, with reusable protocol boundaries
- One public monorepo
- Original protocol and visual identity
- `imsg` consumed behind an adapter
- OpenSSH forced command over Tailscale for the first transport
- Apache-2.0 project license

## Delivery Phases

### Phase 0: Foundations

Establish the repository, requirements, decisions, threat model, governance,
license, support boundaries, and mock-first contributor workflow.

### Phase 1: Feasibility

Validate TCC identity, FDA, Messages Automation, `SMAppService`, child process
attribution, sleep/wake recovery, database generation detection, send
observation, attachments, and SIP-safe reactions.

### Phase 2: Read-only Vertical Slice

Ship the Mac adapter, versioned sync/watch protocol, Rust helper, generated
fixtures, bar state, inbox, and message timeline.

### Phase 3: Safe Sending

Add text sending, command idempotency, observed outcomes, outcome-unknown UX,
reconnect reconciliation, and failure-injection tests.

### Phase 4: Media and Identity

Add bounded attachments, content validation, contact consent, avatars, group
mosaics, and standard desktop notifications.

### Phase 5: Distribution

Publish signed and notarized Mac artifacts, signed Linux artifacts, SBOMs,
provenance, installation documentation, diagnostics, and a public alpha.

## Go/No-Go Gate

The project does not progress to personal-message testing until a signed agent
retains the intended TCC identity across login, reboot, restart, and upgrade
while supervising the `imsg` adapter. If that fails, the adapter must be linked
or incorporated into the signed agent rather than granting FDA to shared
interpreters or SSH.
