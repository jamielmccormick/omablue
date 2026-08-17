# ADR 0004: Build an Omarchy-First Monorepo

Status: Accepted

## Decision

Develop the Mac bridge, protocol, Linux helper, fixtures, packaging, and
Omarchy plugin in one repository. Optimize the first product for current stable
Omarchy while keeping component interfaces independent of QML.

## Consequences

- Protocol and fixture changes remain atomic across components.
- One release can coordinate helper and plugin compatibility.
- Other Linux desktops are community-supported until the Omarchy product is
  reliable.
- The repository must resist premature SDK, package, and platform expansion.
