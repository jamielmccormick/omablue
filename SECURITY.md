# Security Policy

OmaBlue handles private communications and the ability to send messages as the
user. Treat vulnerabilities as potentially high impact.

## Reporting

Do not open public issues for suspected security vulnerabilities. Use GitHub's
private vulnerability reporting for this repository.

Never include real message databases, message bodies, contact information,
attachments, credentials, Tailnet names, or private IP addresses in a report.

## Supported Versions

There are no supported releases yet. Security support begins with the first
public alpha and will cover the latest release only until version 1.0.

## Security Boundaries

- System Integrity Protection must remain enabled.
- The Mac bridge runs as the logged-in user, never root.
- The Messages-authorized process does not listen on a network interface.
- Remote access uses a restricted SSH command over a private network.
- Message bodies and credentials are excluded from logs and diagnostics.
- Ambiguous sends are never retried automatically.

See [the threat model](docs/threat-model.md) for the full design.
