# Data model

All data is collected through the container CLI — `docker` (25+) or `podman`
(4+, tested against 6.1) — via `Quickshell.Io.Process`. Parsers live in
`Model.js` as pure functions and normalize the CLI-specific JSON schemas
into one internal model.

## Runtime selection

The snapshot script resolves the runtime once per run and reports it in the
`==RUNTIME==` section:

- `runtime = auto` (default): `docker` if its daemon answers `docker info`,
  otherwise `podman` if installed.
- `runtime = docker | podman`: that CLI must exist and answer its `info`
  command, otherwise the widget reports the runtime as down.

Actions always use the runtime reported by the last snapshot, so `restart`
hits the same engine the list came from.

## 1. Container list — `docker ps -a --format '{{json .}}'` / `podman ps -a --format json`

One JSON object per line (not a JSON array):

```json
{"ID":"abc123def456...","Image":"nginx:latest","Command":"nginx -g ...",
 "CreatedAt":"2026-08-16 18:00:00 +0000 UTC","RunningFor":"2 hours",
 "Ports":"0.0.0.0:8080->80/tcp","State":"running","Status":"Up 2 hours",
 "Size":"0B (virtual 190MB)","Names":"web","Labels":"com.docker.compose.project=webapp,maintainer=me",
 "Mounts":"...","Networks":"bridge"}
```

Fields used in v1: `ID`/`Id` (first 12 chars), `Names` (string in docker,
array in podman), `Image`, `State`, `Status`, `Labels` (tier 3: compose
project).

### CLI output differences

| | docker `{{json .}}` | podman `--format json` |
|---|---|---|
| Shape | one JSON object per line | single JSON array |
| ID field | `ID` | `Id` |
| Names | string `"web"` | array `["web"]` |
| Image | `nginx:latest` | `docker.io/library/nginx:latest` (shortened) |

`Model.js` auto-detects the array form and normalizes both schemas into the
same container object.

### State values

`created`, `running`, `paused`, `restarting`, `exited`, `dead` (docker);
podman also reports `stopping` (mapped to the same glyph as `restarting`).
`unhealthy` is detectable in `Status` (`(healthy)` / `(unhealthy)`).

## 2. Live stats — `docker stats --no-stream --format '{{json .}}'` / `podman stats --no-stream --format json`

One JSON object per line (**only for running containers**), percentages as
"1.23%" strings:

```json
{"ID":"abc123def456","Name":"web","CPUPerc":"1.23%","MemUsage":"12.4MiB / 3.8GiB",
 "MemPerc":"0.32%","NetIO":"1.2kB / 3.4kB","BlockIO":"0B / 0B","PIDs":"8"}
```

Podman's stats JSON differs: a single array with snake_case string fields
(`id`, `name`, `cpu_percent`, `mem_percent`, `mem_usage`); the
`{{json .}}` template form instead yields numeric fields (`CPU` percent
number, `MemPerc` as a 0..1 fraction). `Model.js` handles all three
variants.

Note: `MemUsage` mixes units (MiB/GiB) — v1 uses `MemPerc`/`CPUPerc`
(percentages) only; byte parsing is a v1.1/tier-3 concern.

## 3. Runtime reachability — `docker info` / `podman info`

The snapshot script uses the runtime's `info` command both to resolve the
active runtime (auto mode) and to report reachability:

```bash
docker info >/dev/null 2>&1 && echo up || echo down
```

`down` → the widget shows the "Container runtime unavailable" state (no
silent empty list).

## 4. Actions — `<runtime> <action> <name>`

```bash
docker start web        # podman start web
docker stop web         # podman stop web
docker restart web      # podman restart web
docker pause web        # podman pause web
docker unpause web      # podman unpause web
```

Exit code ≠ 0 → generic footer error (`lastError`); the list is re-refreshed.
Per-row error details (exit code + stderr) are planned for v1.1.

## Normalized model (what the UI binds to)

```js
{
  containers: [
    {
      id: "abc123def456",        // 12-char short id
      name: "web",
      image: "nginx:latest",
      state: "running",          // created|running|paused|restarting|exited|dead
      status: "Up 2 hours",
      unhealthy: false,          // derived from Status
      cpuPct: 1.23,              // from stats, -1 if not running
      memPct: 0.32               // from stats, -1 if not running
    }
  ],
  daemon: "up" | "down"
}
```