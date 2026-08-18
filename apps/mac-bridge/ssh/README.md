# Restricted SSH Transport

The first transport uses OpenSSH over a private Tailnet. The Mac account's
`authorized_keys` entry runs only `OmaBlueBridgeStdio`; it does not provide a
shell or a general SSH session.

## Mac Setup

1. Enable Remote Login for the Mac user and confirm the Mac is reachable only
   through the intended private Tailnet policy.
2. Install the signed OmaBlue app at `/Applications/OmaBlue.app` or update the
   forced-command path in `authorized_keys.example`.
3. Create a dedicated Ed25519 `SSH Key` item in 1Password. Generate the key
   inside 1Password rather than exporting the private key to disk. Copy only
   its public key to the Linux device:

   ```sh
   install -d -m 700 "$HOME/.ssh"
   op item get "OmaBlue Mac SSH" --fields public_key > "$HOME/.ssh/omablue_mac.pub"
   chmod 600 "$HOME/.ssh/omablue_mac.pub"
   ```

4. Replace the placeholder public key in `authorized_keys.example` and append
   exactly that one-line entry to the Mac user's `~/.ssh/authorized_keys`.
5. Keep `authorized_keys` mode `0600` and the `.ssh` directory mode `0700`.

The forced-command executable rejects any non-empty `SSH_ORIGINAL_COMMAND`.
The `restrict` options are repeated explicitly so the intended boundary is
visible during review: no PTY, forwarding, agent forwarding, X11, or user RC.

## Linux Host Verification

Pin the Mac host key out-of-band before enabling the helper. Do not trust an
unreviewed `ssh-keyscan` result as proof of identity. Configure the helper with
the public identity path, the 1Password agent socket
(`~/.1password/agent.sock`), and the pinned `known_hosts` file. The private key
must remain in 1Password.

The helper invokes an absolute SSH executable with no remote command and ignores
the user's SSH config. Its destination must therefore include the SSH user and
host explicitly, for example `jamielmccormick@mac-host`. It also forces batch
mode, strict host-key checking, disabled forwarding, disabled environment
forwarding, and a ten-second connection timeout.

If the installed app path contains spaces, quote the path inside the
`authorized_keys` command option with escaped inner quotes, as required by the
sshd command parser.

## Negative Checks

- `ssh <destination>` must reach only the stdio bridge.
- `ssh <destination> true` must be rejected by the forced-command executable.
- PTY and forwarding requests must fail.
- Removing or changing the pinned host key must fail closed.
- A second agent instance must not replace the existing Unix socket.
