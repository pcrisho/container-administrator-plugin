# PRD — Container Administrator (`pcrisho.container-admin`)

Omarchy topbar widget to monitor and manage **Docker** containers.

## Goal

Give the user a single, always-visible entry point in the topbar to validate
container health and act on containers while working, without leaving the
desktop shell.

## UX (v1)

- **Bar widget**: `BarIconButton` with the container glyph `󰆳` in the
  right section of the bar.
  - A small status hint on the icon: a colored dot (green = all running,
    yellow = any paused/restarting, red = any exited/dead/unhealthy, gray =
    daemon unreachable).
  - Tooltip: running count, e.g. `3/5 running`.
- **Left click** on the icon → opens a dropdown `KeyboardPanel` with the
  container list.
- **Dropdown content** per container row: state glyph + color, name, image
  (short), CPU %, memory %.
- **Keyboard**: `j`/`k` move the selection, `Enter`/`Space` run the action
  for the selected container, `r` force refresh, `Esc` close. Mouse: click a
  row to select; click the action button in the row.
- **Actions** (per container, via CLI): `start`, `stop`, `restart`,
  `pause`, `unpause`.
- **Daemon-down state**: if the Docker CLI errors, the panel shows a clear
  "Docker daemon unavailable" message (instead of a silent empty list) and
  the bar dot turns gray.
- **Refresh**: on open + periodic poll (default 10s, configurable
  `pollIntervalSec`, 5–300s). Manual refresh with `r` / middle click.

## Feature tiers

| Tier | Features | Status |
|---|---|---|
| **1 — Core (v1)** | Status + live stats (CPU/mem %), actions start/stop/restart/pause/unpause, daemon-down state, poll + manual refresh, dropdown UX, IPC | Shipped |
| **2 — High value (v1.1)** | Log viewer per container, desktop notifications on state changes (stopped/unhealthy/started) | Planned |
| **3 — Roadmap** | Compose project grouping, RAM limit slider (`docker update`), search/filter, images/volumes/networks views, **Podman support** | Later |

## Non-goals (v1)

- Podman (after Docker is solid — see ROADMAP).
- Container creation/removal, image management, volumes/networks.
- Logs and notifications (v1.1).

## Reference implementations

- **Base**: `djjeane.docker-monitor` — actions, live stats, settings schema
  in manifest, keyboard/panel UX.
- **Patterns to borrow**: pure JS parsers in `Model.js` (node-testable) and
  the RAM-limit update-queue from `devgtv.docker`.
- **Gap we fix vs both**: explicit daemon-down state; both show a silent
  empty list when Docker is unavailable.

## Constraints

- Omarchy 4.0.0 (Quattro shell): `schemaVersion: 1` manifest, `Panel` +
  `BarIconButton` + `KeyboardPanel` components (same as
  `pcrisho.power-admin`).
- Docker CLI via `Quickshell.Io.Process`; the user runs in the `docker`
  group (no sudo needed).
- Security: the plugin executes unsandboxed; `docker` CLI access equals root
  access on the daemon. Standard third-party-plugin caveat.