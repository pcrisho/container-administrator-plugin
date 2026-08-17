# Data model

All data is collected through the Docker CLI (`docker` 25+, JSON templates)
via `Quickshell.Io.Process`. Parsers live in `Model.js` as pure functions.

## 1. Container list — `docker ps -a --format '{{json .}}'`

One JSON object per line (not a JSON array):

```json
{"ID":"abc123def456...","Image":"nginx:latest","Command":"nginx -g ...",
 "CreatedAt":"2026-08-16 18:00:00 +0000 UTC","RunningFor":"2 hours",
 "Ports":"0.0.0.0:8080->80/tcp","State":"running","Status":"Up 2 hours",
 "Size":"0B (virtual 190MB)","Names":"web","Labels":"com.docker.compose.project=webapp,maintainer=me",
 "Mounts":"...","Networks":"bridge"}
```

Fields used in v1: `ID` (first 12 chars), `Names`, `Image`, `State`,
`Status`, `Labels` (tier 3: compose project).

### State values

`created`, `running`, `paused`, `restarting`, `exited`, `dead` — plus
`unhealthy` detectable in `Status` (`(healthy)` / `(unhealthy)`).

## 2. Live stats — `docker stats --no-stream --format '{{json .}}'`

One JSON object per line, **only for running containers**:

```json
{"ID":"abc123def456","Name":"web","CPUPerc":"1.23%","MemUsage":"12.4MiB / 3.8GiB",
 "MemPerc":"0.32%","NetIO":"1.2kB / 3.4kB","BlockIO":"0B / 0B","PIDs":"8"}
```

Note: `MemUsage` mixes units (MiB/GiB) — v1 uses `MemPerc`/`CPUPerc`
(percentages) only; byte parsing is a v1.1/tier-3 concern.

## 3. Daemon reachability — `docker info`

```bash
docker info >/dev/null 2>&1 && echo up || echo down
```

`down` → the widget shows the "Docker daemon unavailable" state (no silent
empty list).

## 4. Actions — `docker <action> <name>`

```bash
docker start web
docker stop web
docker restart web
docker pause web
docker unpause web
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