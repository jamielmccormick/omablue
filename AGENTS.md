# Agent Guidance

Read the accepted Product Contract under `docs/plans/`, all ADRs under
`docs/adr/`, and `docs/threat-model.md` before changing behavior.

## Non-Negotiable Constraints

- Keep SIP, AMFI, Gatekeeper, and FileVault enabled.
- Never add Firebase, telemetry, a hosted relay, public tunnel, or Funnel.
- Never grant Messages permissions to SSH, QML, a shell, or a shared runtime.
- Never expose raw SQL, AppleScript, shell commands, or filesystem paths.
- Never log message bodies, contacts, attachment names, credentials, Tailnet
  names, or private addresses.
- Never retry an ambiguous send automatically.
- Treat messages, contacts, links, and attachments as hostile input.
- Keep QML presentational; networking, credentials, and persistence belong in
  the helper.

## Compound Workflow

Use requirements -> plan -> work -> review -> compound. Persist new platform
constraints as tests, ADRs, fixtures, or troubleshooting documentation rather
than leaving them only in an issue or conversation.

Implementation must remain behind the current phase's explicit go/no-go gates.
