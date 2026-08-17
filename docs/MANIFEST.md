# Manifest specification

Validated against Omarchy 4.0.0 (`omarchy plugin validate` → exit 0).

```json
{
  "schemaVersion": 1,
  "id": "pcrisho.container-admin",
  "name": "Container Administrator",
  "version": "1.0.0",
  "author": "pcrisho",
  "license": "MIT",
  "description": "Monitor and manage Docker containers from the topbar: status, live stats, and start/stop/restart actions.",
  "kinds": ["bar-widget"],
  "entryPoints": {
    "barWidget": "Panel.qml"
  },
  "barWidget": {
    "displayName": "Container Administrator",
    "description": "Topbar dropdown with Docker container status, CPU/memory usage, and start/stop/restart actions.",
    "category": "System",
    "defaultSection": "right",
    "allowMultiple": false,
    "defaults": {
      "pollIntervalSec": 10,
      "runtime": "Auto"
    },
    "schema": [
      {
        "key": "pollIntervalSec",
        "type": "integer",
        "label": "Refresh interval (seconds)",
        "min": 5,
        "max": 300,
        "step": 5,
        "defaultValue": 10
      },
      {
        "key": "runtime",
        "type": "enum",
        "label": "Container runtime",
        "options": [
          "Auto",
          "Docker",
          "Podman"
        ],
        "defaultValue": "Auto",
        "description": "Auto prefers Docker and falls back to Podman when the Docker daemon is unreachable."
      }
    ]
  }
}
```

## Notes

- `schemaVersion: 1` — Omarchy 4.0.0 (Quattro) plugin schema.
- Settings declared in the manifest `barWidget.schema` get surfaced in
  Omarchy's plugin settings UI and land in the `shell.json` bar entry
  (`{ "id": "pcrisho.container-admin", "pollIntervalSec": 10 }`).
- The widget reads them via the `settings`/`setting()` helpers provided by
  the shell (`Panel.setting(key, default)`), with validation/clamping in
  `Model.js` (`clampPollInterval`). `runtime` accepts `Auto` | `Docker` |
  `Podman` (case-insensitive on read).
- v1.1 will extend the schema with `showStoppedContainers`,
  `notificationsEnabled`, `logLines` (pattern borrowed from
  `djjeane.docker-monitor`).

## Install / enable

```bash
./install.sh                        # copies to ~/.config/omarchy/plugins/pcrisho.container-admin
omarchy plugin enable pcrisho.container-admin right
```

## IPC target — `pcrisho.container-admin`

| Method | Effect |
|---|---|
| `state` | `"up"` \| `"down"` (daemon) |
| `refresh` | Force a snapshot re-read |
| `action <name> <start\|stop\|restart\|pause\|unpause>` | Run the action |
| `open` / `close` | Toggle the dropdown panel |