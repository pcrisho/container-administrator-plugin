// Model.js unit tests — run with: node test/Model.test.js
const assert = require("assert")
const M = require("../Model.js")

// --- shortImage ---
assert.strictEqual(M.shortImage("nginx:latest"), "nginx")
assert.strictEqual(M.shortImage("ghcr.io/org/app:v2"), "app")
assert.strictEqual(M.shortImage(""), "")

// --- toPercent ---
assert.strictEqual(M.toPercent("1.23%"), 1.23)
assert.strictEqual(M.toPercent("0%"), 0)
assert.strictEqual(M.toPercent(null), -1)

// --- parsePsLines ---
const psRaw = [
  '{"ID":"abc123def4567890","Names":"web","Image":"nginx:latest","State":"running","Status":"Up 2 hours"}',
  '{"ID":"def456abc7890123","Names":"db","Image":"postgres:16","State":"exited","Status":"Exited (0) 5 hours ago"}',
  'not-json'
].join("\n")
const containers = M.parsePsLines(psRaw)
assert.strictEqual(containers.length, 2, "malformed line skipped")
assert.strictEqual(containers[0].name, "web")
assert.strictEqual(containers[0].id, "abc123def456")
assert.strictEqual(containers[0].image, "nginx")
assert.strictEqual(containers[0].state, "running")
assert.strictEqual(containers[1].state, "exited")

// --- unhealthy detection ---
const unhealthy = M.parsePsLines('{"ID":"x","Names":"svc","Image":"a","State":"running","Status":"Up 10 minutes (unhealthy)"}')
assert.strictEqual(unhealthy[0].unhealthy, true)

// --- parseStatsLines ---
const statsRaw = [
  '{"ID":"abc123def456","Name":"web","CPUPerc":"2.50%","MemPerc":"12.34%"}',
  '{"ID":"zzz","Name":"nope","CPUPerc":"0.00%","MemPerc":"0.10%"}'
].join("\n")
const stats = M.parseStatsLines(statsRaw)
assert.strictEqual(stats.web.cpuPct, 2.5)
assert.strictEqual(stats.web.memPct, 12.34)

// --- podman ps (single JSON array, Id + Names as array) ---
const podmanPsRaw = JSON.stringify([
  { Id: "aaa111bbb222ccc333ddd444eee555fff666777888999000aaa111bbb222", Names: ["web"], Image: "docker.io/library/nginx:latest", State: "running", Status: "Up 2 minutes" },
  { Id: "bbb222ccc333ddd444eee555fff666777888999000aaa111bbb222ccc333", Names: ["db"], Image: "docker.io/library/postgres:16", State: "exited", Status: "Exited (0) 1 minute ago" }
])
const podmanContainers = M.parsePsLines(podmanPsRaw)
assert.strictEqual(podmanContainers.length, 2, "podman array parsed")
assert.strictEqual(podmanContainers[0].id, "aaa111bbb222")
assert.strictEqual(podmanContainers[0].name, "web")
assert.strictEqual(podmanContainers[0].image, "nginx")
assert.strictEqual(podmanContainers[0].state, "running")
assert.strictEqual(podmanContainers[1].state, "exited")

// --- podman stats (array, snake_case string percents — podman 6.1) ---
const podmanStatsRaw = JSON.stringify([
  { id: "108beef3e68f", name: "web", cpu_percent: "0.09%", mem_percent: "0.01%", mem_usage: "1.52MB / 16.28GB" },
  { id: "zzz", name: "other", cpu_percent: "0.00%", mem_percent: "0.00%" }
])
const podmanStats = M.parseStatsLines(podmanStatsRaw)
assert.strictEqual(podmanStats.web.cpuPct, 0.09, "podman snake_case cpu_percent")
assert.strictEqual(podmanStats.web.memPct, 0.01, "podman snake_case mem_percent")
const mergedPodman = M.mergeStats(podmanContainers, podmanStats)
assert.strictEqual(mergedPodman[0].cpuPct, 0.09, "podman stats merged")
assert.strictEqual(mergedPodman[1].cpuPct, -1, "stopped podman container has no stats")

// --- podman stats (array, numeric fields: CPU percent number, MemPerc fraction) ---
const podmanStatsNumericRaw = JSON.stringify([
  { ContainerID: "aaa111bbb222", Name: "web", CPU: 1.79, MemPerc: 0.001786 }
])
const podmanStatsNumeric = M.parseStatsLines(podmanStatsNumericRaw)
assert.strictEqual(podmanStatsNumeric.web.cpuPct, 1.79, "podman numeric CPU is a percent")
assert.ok(Math.abs(podmanStatsNumeric.web.memPct - 0.1786) < 0.0001, "podman MemPerc fraction x100")

// --- podman state glyphs ---
assert.strictEqual(M.stateGlyph("stopping"), "󰀘")
assert.strictEqual(M.worstState([{ state: "stopping" }]), "warn")

// --- compose project from docker label strings and podman label objects ---
const withLabels = M.parsePsLines('{"ID":"x","Names":"api","Image":"a","State":"running","Labels":"com.docker.compose.project=webapp,maintainer=me"}')
assert.strictEqual(withLabels[0].project, "webapp")
const quotedLabels = M.parsePsLines('{"ID":"y","Names":"db","Image":"a","State":"running","Labels":"a=\\"x,y\\",com.docker.compose.project=webapp"}')
assert.strictEqual(quotedLabels[0].project, "webapp")
const podmanLabels = M.parsePsLines(JSON.stringify([{ Id: "z", Names: ["worker"], Image: "a", State: "running", Labels: { "com.docker.compose.project": "jobs", "owner": "me" } }]))
assert.strictEqual(podmanLabels[0].project, "jobs")

// --- groupByProject ---
const groups = M.groupByProject(containers.concat(withLabels, quotedLabels, podmanLabels))
assert.strictEqual(groups.length, 3, "two projects + ungrouped bucket")
assert.strictEqual(groups[0].project, "jobs", "projects alphabetical")
assert.strictEqual(groups[0].containers.length, 1)
assert.strictEqual(groups[1].project, "webapp")
assert.strictEqual(groups[1].containers.length, 2, "api and db are webapp")
assert.strictEqual(groups[2].project, "", "ungrouped last")
assert.strictEqual(groups[2].containers.length, 2, "web and db have no project")
assert.strictEqual(groups[2].containers[0].flatIndex, 0, "flatIndex preserved")
assert.strictEqual(groups[1].containers[0].flatIndex, 2)
assert.deepStrictEqual(M.groupByProject([]), [], "empty input")

// --- mergeStats (stats only for running) ---
const merged = M.mergeStats(containers, stats)
assert.strictEqual(merged[0].cpuPct, 2.5, "running container gets stats")
assert.strictEqual(merged[1].cpuPct, -1, "stopped container has no stats")

// --- state mapping ---
assert.strictEqual(M.stateGlyph("running"), "●")
assert.strictEqual(M.stateGlyph("exited"), "○")
assert.strictEqual(M.stateGlyph("restarting"), "󰀘")
assert.strictEqual(M.stateColor("running", false), "#22c55e")
assert.strictEqual(M.stateColor("running", true), "#ef4444")

// --- worstState / runningCount / dotColor ---
assert.strictEqual(M.worstState([]), "none")
assert.strictEqual(M.worstState(merged), "bad", "exited container -> bad")
const paused = [{ state: "running" }, { state: "paused" }]
assert.strictEqual(M.worstState(paused), "warn")
const allGood = [{ state: "running" }, { state: "running" }]
assert.strictEqual(M.worstState(allGood), "good")
assert.strictEqual(M.runningCount(allGood), 2)
assert.strictEqual(M.dotColor("good"), "#22c55e")
assert.strictEqual(M.dotColor("none"), "#6b7280")

// --- clampPollInterval ---
assert.strictEqual(M.clampPollInterval(10, 10), 10)
assert.strictEqual(M.clampPollInterval(2, 10), 10, "below min -> fallback")
assert.strictEqual(M.clampPollInterval(999, 10), 300, "above max -> 300")
assert.strictEqual(M.clampPollInterval(undefined, 10), 10)
assert.strictEqual(M.clampPollInterval(7.4, 10), 7)

console.log("All Model.js tests passed")