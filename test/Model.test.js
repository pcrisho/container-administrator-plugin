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

// --- mergeStats (stats only for running) ---
const merged = M.mergeStats(containers, stats)
assert.strictEqual(merged[0].cpuPct, 2.5, "running container gets stats")
assert.strictEqual(merged[1].cpuPct, -1, "stopped container has no stats")

// --- state mapping ---
assert.strictEqual(M.stateGlyph("running"), "●")
assert.strictEqual(M.stateGlyph("exited"), "○")
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