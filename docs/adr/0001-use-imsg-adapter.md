# ADR 0001: Use imsg Behind an Adapter

Status: Accepted

## Context

Apple provides no supported API for arbitrary Messages history. A production
bridge must handle private SQLite schemas, WAL rotation, attachments, reactions,
database replacement, and ambiguous send outcomes.

## Decision

Consume a pinned stable `imsg` release through its strict JSON-RPC stdio
interface. Convert its data into the versioned OmaBlue protocol at one adapter
boundary. Do not expose raw `imsg` RPC remotely.

## Consequences

- OmaBlue benefits from existing cursor, watch, overflow, and send-safety work.
- Upstream version changes remain isolated to one adapter.
- The first feasibility gate must verify macOS TCC attribution when the signed
  agent supervises the adapter.
- Features requiring the injected IMCore bridge remain disabled and unexposed.
