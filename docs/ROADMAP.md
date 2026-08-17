# Roadmap

## v1 (current)

- [x] Repo + docs artifacts
- [x] Manifest with settings schema (`pollIntervalSec`)
- [x] Snapshot data layer (ps/stats/info via one Process)
- [x] Pure parsers in `Model.js` (node-testable)
- [x] Topbar dropdown UX: list, state glyphs/colors, keyboard, actions
- [x] Actions: start / stop / restart / pause / unpause (serialized queue)
- [x] Daemon-down state (no silent empty list)
- [x] Generic error surfacing (footer `lastError` on docker failure)
- [x] Live validation with real containers (loads clean, no QML errors; IPC
      state/refresh/action validated against real containers)

## v1.3 (shipped)

- [x] **Compose project grouping** — containers grouped in a collapsible
  accordion (collapsed by default, expanded state kept per session;
  ungrouped containers under "Other"); the panel scrolls when the list
  exceeds its height and j/k skips collapsed groups
- [x] **In-flight action indicator** — the affected row shows a spinner and
  hides its buttons while an action runs (stop can take ~10s on a busy
  container), cleared on exit
- [x] Fix action stderr surfacing (`actionStderr` lives on the Process, not
  the Panel — was silently never captured)

## v1.2 (shipped)

- [x] **Podman support** — runtime auto-detection (`runtime` setting:
      Auto | Docker | Podman):
  - Auto prefers `docker` and falls back to `podman` when the docker
    daemon is unreachable
  - Podman's JSON schemas differ per subcommand (`ps --format json` is a
    PascalCase array, `stats --format json` is snake_case with string
    percents, `{{json .}}` yields numeric fields) — `Model.js` normalizes
    all of them (validated against podman 6.1)
  - Same actions (`podman start/stop/restart/pause/unpause`)

## v1.1 (planned)

- [ ] Log viewer per container (`docker logs --tail N`, timestamps)
- [ ] Desktop notifications on state changes (stopped / unhealthy / started),
      with persistable "already notified" state
- [ ] `showStoppedContainers`, `notificationsEnabled`, `logLines` settings
- [ ] Per-row error details (exit code + stderr; generic footer error is
      already in v1)

## Tier 3 (later)

- [ ] RAM limit slider (`docker update --memory --memory-swap -1`, devgtv
      pattern: pending-set queue + optimistic preview)
- [ ] Search / filter by name or image
- [ ] Images / volumes / networks views
- [ ] Byte parsing for `MemUsage`/`NetIO` (mixed-unit strings)

## Decisions log

| # | Decision | Status |
|---|---|---|
| 1 | Docker first, Podman after (user's active runtime is Docker) | Kept |
| 2 | v1 = core only (stats + actions); logs/notifications → v1.1 | Kept |
| 3 | Data layer: inline bash snapshot + pure JS parsers (node-testable) instead of a Python helper | Kept |
| 4 | Single `Process` per job (snapshot, actions) — serialized queue | Kept |
| 5 | Bars show a daemon state dot; dropdown holds the detail | Kept |
| 6 | Runtime resolution in the snapshot script (auto = prefer docker, fall back to podman), reported via `==RUNTIME==` so actions always use the live runtime | Kept |
| 7 | Normalize podman's divergent JSON schemas in `Model.js` instead of requiring jq at runtime | Kept |

## Known upstream issues (shell, not this repo)

- **Live plugin reload is unreliable**: after a failed QML compile, the
  engine keeps serving the stale error for that file URL until the shell is
  restarted (`omarchy restart shell`); files added to a plugin dir after
  startup also fail with a misleading "File name case mismatch". Editing
  `Panel.qml` during development therefore requires a shell restart to see
  the change — the watcher log alone is not enough.

## Out of scope (indefinitely)

- Container creation / removal / image pull (shell is a monitor + lifecycle
  controller, not a full Docker Desktop replacement)
- Multi-host / remote daemons (`DOCKER_HOST`)