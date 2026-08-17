# Compatibility Policy

Before 1.0, OmaBlue supports its latest release only and may make breaking
changes between minor releases.

## Initial Targets

- Current stable Omarchy
- macOS versions supported by the pinned stable `imsg` release
- Apple silicon first; Intel only when upstream and test hardware support it
- One OmaBlue client, one physical Mac, one logged-in Messages account
- Regular OpenSSH over Tailscale

Every release records exact tested versions. New macOS releases and betas are
unsupported until the Messages schema, TCC behavior, sleep/wake lifecycle, and
send semantics pass the compatibility suite.

Unknown database schemas fail closed rather than returning incomplete or
misattributed messages.
