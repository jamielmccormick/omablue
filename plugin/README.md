# OmaBlue Plugin

The QML service owns one credential-free `omablue-helper` process per shell
session. The helper reads its private SSH configuration from
`~/.config/omablue/config.json`; QML never receives key contents or constructs
SSH arguments.

## Local Setup

1. Build the helper with `./scripts/build-helper.sh`.
2. Create `~/.config/omablue/config.json` from
   `crates/omablue-helper/config.example.json`.
3. Replace the destination, public identity path, 1Password agent socket, and
   pinned known-hosts path. Keep the configuration mode `0600`.
4. Install the plugin directory under `~/.config/omarchy/plugins/omablue/` with
   the helper at `bin/omablue-helper`.

The service applies each sync batch before sending the helper an ACK. The
helper persists the cursor only after that ACK, so a shell restart resumes from
the last applied batch rather than from an optimistic transport write.

## Settings

Configure the plugin in `~/.config/omarchy/shell.json` under the plugin's
`settings` object:

```jsonc
{
  "id": "omablue",
  "settings": {
    "deviceName": "Home Mac",              // shown in the panel header
    "notificationsEnabled": true,          // set false to silence notifications
    "notificationCooldownSeconds": 60      // minimum seconds between notifications
  }
}
```

All keys are optional. Notifications never include message bodies — only the
conversation label and a count.
