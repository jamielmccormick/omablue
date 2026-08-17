# ADR 0003: Keep SIP Enabled

Status: Accepted

## Decision

OmaBlue will not disable System Integrity Protection, AMFI, library validation,
Gatekeeper, or FileVault. It will not inject code into Messages or expose
private IMCore bridge methods.

## Consequences

Typing indicators, edits, unsend, rich effects, native polls, and group
administration are outside the supported product. The project favors a smaller,
safer feature set on a general-purpose personal Mac.
