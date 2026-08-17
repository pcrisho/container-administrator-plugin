# Roadmap

## v1 (current)

- [x] Repo + docs artifacts
- [x] Manifest with settings schema (`pollIntervalSec`)
- [x] Snapshot data layer (ps/stats/info via one Process)
- [x] Pure parsers in `Model.js` (node-testable)
- [x] Topbar dropdown UX: list, state glyphs/colors, keyboard, actions
- [x] Actions: start / stop / restart / pause / unpause (serialized queue)
- [x] Daemon-down state (no silent empty list)
- [ ] Live validation with real containers

## v1.1 (planned)

- [ ] Log viewer per container (`docker logs --tail N`, timestamps)
- [ ] Desktop notifications on state changes (stopped / unhealthy / started),
      with persistable "already notified" state
- [ ] `showStoppedContainers`, `notificationsEnabled`, `logLines` settings
- [ ] Error surfacing per row (exit code ≠ 0)

## Tier 3 (later)

- [ ] **Podman support** — when Docker is solid:
  - Detect `podman` CLI; reuse the same snapshot script
    (`podman ps --format json` etc. — compatible output)
  - `podman stats --no-stream` (same template support)
  - Option: prefer `docker` when both are present (user's runtime today)
  - `podman-docker` alias as fallback (unverified for `stats`)
- [ ] Compose project grouping with collapsible headers
- [ ] RAM limit slider (`docker update --memory --memory-swap -1`, devgtv
      pattern: pending-set queue + optimistic preview)
- [ ] Search / filter by name or image
- [ ] Images / volumes / networks views
- [ ] Byte parsing for `MemUsage`/`NetIO` (mixed-unit strings)

## Decisions log

| # | Decision | Status |
|---|---|---|
| 1 | Docker first, Podman after (user's active runtime is Docker) | ✅ |
| 2 | v1 = core only (stats + actions); logs/notifications → v1.1 | ✅ |
| 3 | Data layer: inline bash snapshot + pure JS parsers (node-testable) instead of a Python helper | ✅ |
| 4 | Single `Process` per job (snapshot, actions) — serialized queue | ✅ |
| 5 | Bars show a daemon state dot; dropdown holds the detail | ✅ |

## Out of scope (indefinitely)

- Container creation / removal / image pull (shell is a monitor + lifecycle
  controller, not a full Docker Desktop replacement)
- Multi-host / remote daemons (`DOCKER_HOST`)