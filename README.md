# Container Administrator

Omarchy topbar widget to monitor and manage **Docker** containers: status,
live CPU/memory usage, and start / stop / restart / pause / unpause actions
from a dropdown panel.

![screenshot placeholder — run ./install.sh to see it live]

## Features

- **Bar icon** `󰡨` with a status dot: green = all running, yellow =
  paused/restarting, red = exited/dead/unhealthy, gray = daemon down.
  Tooltip shows the running count (e.g. `3/5 running`).
- **Dropdown panel** (left click / right click on the icon): container list
  with state glyphs, image, CPU% · mem%, and per-row action buttons.
- **Actions**: Start, Stop, Restart (plus pause/unpause via
  `omarchy-shell ipc pcrisho.container-admin action <name> pause`).
- **Daemon-down state**: when `docker` is unreachable the panel says so —
  no silent empty list.
- **Auto refresh**: on open + poll (default 10s, configurable 5–300s);
  manual refresh with `r` or middle click.

## Requirements

- Omarchy 4.0.0+ (Quattro shell)
- Docker CLI (`docker`) with the daemon running
- Your user in the `docker` group (no sudo needed):
  `sudo usermod -aG docker $USER` + re-login

## Install

```bash
./install.sh
```

This copies the plugin to `~/.config/omarchy/plugins/pcrisho.container-admin`,
rescans plugins and enables it in the right bar section. Uninstall:

```bash
omarchy plugin disable pcrisho.container-admin
rm -rf ~/.config/omarchy/plugins/pcrisho.container-admin
omarchy-shell shell rescanPlugins
```

## Usage

| Input | Effect |
|---|---|
| Left click icon | Toggle panel |
| Right click icon | Open panel |
| `j` / `k` | Move selection |
| `Enter` | Restart selected container |
| `r` | Force refresh |
| `Esc` | Close panel |
| Row buttons | Start / Stop / Restart that container |

## Configuration

Omarchy plugin settings UI → `pollIntervalSec` (default 10, min 5, max 300),
or set it directly in `shell.json`:

```json
{ "id": "pcrisho.container-admin", "pollIntervalSec": 10 }
```

## IPC

Target `pcrisho.container-admin`:

| Method | Effect |
|---|---|
| `state` | `"up"` \| `"down"` (daemon reachability) |
| `refresh` | Force a snapshot re-read |
| `action <name> <start\|stop\|restart\|pause\|unpause>` | Run the action |
| `open` / `close` | Toggle the panel |

Example:

```bash
omarchy-shell ipc pcrisho.container-admin action web restart
```

## Architecture

- `Panel.qml` — bar widget + dropdown UI; runs one `Process` per job
  (snapshot, actions).
- `Model.js` — pure, node-testable parsers (`docker ps --format '{{json .}}'`,
  `docker stats --no-stream`, daemon check). Run the tests:
  `node test/Model.test.js`.
- `install.sh` — copies the plugin, rescans, enables.

Details: [docs/PRD.md](docs/PRD.md) · [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
· [docs/DATA-MODEL.md](docs/DATA-MODEL.md) · [docs/MANIFEST.md](docs/MANIFEST.md)
· [docs/ROADMAP.md](docs/ROADMAP.md)

## Known limitations

- v1 shows per-container CPU/mem percentages only (byte-precise usage
  parsing is planned).
- Pause/unpause are not exposed as buttons (rarely used); use IPC.
- Podman support is on the roadmap, after Docker is solid.

## License

MIT — see [LICENSE](LICENSE).