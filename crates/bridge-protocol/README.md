# OmaBlue Protocol

Shared Rust models for the versioned OmaBlue wire protocol.

Protocol v1 starts with status, bounded synchronization, generation-scoped
cursors, conversation projections, message projections, reactions, and opaque
attachment metadata. It contains no transport, database, or Apple-specific
filesystem paths.

See `protocol/v1.md` and `protocol/fixtures/` for the normative contract and
synthetic examples.
