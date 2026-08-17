// Container plugin data logic: pure parsers, no Qt dependencies.
// Testable with node (see test/Model.test.js).

function shortImage(image) {
  var img = String(image || "")
  var slash = img.lastIndexOf("/")
  if (slash >= 0) img = img.substring(slash + 1)
  var colon = img.indexOf(":")
  if (colon >= 0) img = img.substring(0, colon)
  return img
}

function toPercent(value) {
  if (value === null || value === undefined) return -1
  var n = parseFloat(String(value).replace("%", ""))
  return isFinite(n) ? n : -1
}

// Normalize one container row from either CLI:
//   docker: docker ps --format '{{json .}}'  → ID, Names (string), ...
//   podman: podman ps --format json          → Id, Names (array), ...
function psRow(d) {
  var names = d.Names !== undefined ? d.Names : d.names
  return {
    id: String(d.ID || d.Id || "").slice(0, 12),
    name: Array.isArray(names) ? String(names[0] || "") : String(names || ""),
    image: shortImage(String(d.Image || "")),
    state: String(d.State || "").toLowerCase(),
    status: String(d.Status || ""),
    unhealthy: String(d.Status || "").indexOf("unhealthy") >= 0,
    cpuPct: -1,
    memPct: -1
  }
}

// docker ps --format '{{json .}}' → one JSON object per line.
// podman ps --format json → a single JSON array.
function parsePsLines(raw) {
  var containers = []
  var text = String(raw || "").trim()
  if (text.charAt(0) === "[") {
    try {
      var arr = JSON.parse(text)
      for (var i = 0; i < arr.length; i++) containers.push(psRow(arr[i]))
    } catch (e) {
      // malformed array
    }
    return containers
  }
  text.split("\n").forEach(function(line) {
    line = line.trim()
    if (!line) return
    try {
      containers.push(psRow(JSON.parse(line)))
    } catch (e) {
      // skip malformed line
    }
  })
  return containers
}

// Normalize one stats row across the CLI output variants:
//   docker stats {{json .}}  → { Name, CPUPerc: "1.23%", MemPerc: "0.32%" }
//   podman stats --format json → { name, cpu_percent: "0.09%", mem_percent: "0.01%" }
//   podman stats {{json .}}  → { Name, CPU: 1.79, MemPerc: 0.0018 (0..1 fraction) }
function statsRow(d) {
  var name = d.Name !== undefined ? d.Name : d.name
  var cpu = d.CPUPerc !== undefined ? d.CPUPerc : (d.CPU !== undefined ? d.CPU : d.cpu_percent)
  var mem = d.MemPerc !== undefined ? d.MemPerc : d.mem_percent
  return {
    cpuPct: typeof cpu === "number" ? cpu : toPercent(cpu),
    memPct: typeof mem === "number" ? mem * 100 : toPercent(mem)
  }
}

// docker stats --no-stream --format '{{json .}}' → one object per line,
// percentages as "1.23%" strings.
// podman stats --no-stream --format json → a single JSON array.
function parseStatsLines(raw) {
  var stats = {}
  var text = String(raw || "").trim()
  if (text.charAt(0) === "[") {
    try {
      var arr = JSON.parse(text)
      for (var i = 0; i < arr.length; i++) {
        var row = statsRow(arr[i])
        stats[String(arr[i].Name !== undefined ? arr[i].Name : arr[i].name || "")] = row
      }
    } catch (e) {
      // malformed array
    }
    return stats
  }
  String(raw || "").split("\n").forEach(function(line) {
    line = line.trim()
    if (!line) return
    try {
      var d = JSON.parse(line)
      var row = statsRow(d)
      if (row.cpuPct >= 0 || row.memPct >= 0) stats[String(d.Name || "")] = row
    } catch (e) {
      // skip malformed line
    }
  })
  return stats
}

// Merge stats into the container list (stats only covers running containers).
function mergeStats(containers, stats) {
  var out = []
  for (var i = 0; i < containers.length; i++) {
    var c = containers[i]
    var s = stats[c.name] || {}
    out.push({
      id: c.id,
      name: c.name,
      image: c.image,
      state: c.state,
      status: c.status,
      unhealthy: c.unhealthy,
      cpuPct: typeof s.cpuPct === "number" ? s.cpuPct : -1,
      memPct: typeof s.memPct === "number" ? s.memPct : -1
    })
  }
  return out
}

function stateGlyph(state) {
  if (state === "running") return "●"
  if (state === "paused") return "◫"
  if (state === "restarting" || state === "stopping") return "↻"
  if (state === "exited") return "○"
  if (state === "dead") return "✕"
  if (state === "created") return "◌"
  return "?"
}

function stateColor(state, unhealthy) {
  if (unhealthy) return "#ef4444"
  if (state === "running") return "#22c55e"
  if (state === "paused") return "#eab308"
  if (state === "restarting") return "#3b82f6"
  return "#6b7280"
}

// Bar status dot: "good" | "warn" | "bad" | "none"
function worstState(containers) {
  if (!containers || containers.length === 0) return "none"
  for (var i = 0; i < containers.length; i++) {
    var c = containers[i]
    if (c.unhealthy || c.state === "exited" || c.state === "dead") return "bad"
  }
  for (var j = 0; j < containers.length; j++) {
    var s = containers[j].state
    if (s === "paused" || s === "restarting" || s === "stopping") return "warn"
  }
  return "good"
}

function runningCount(containers) {
  var n = 0
  for (var i = 0; i < containers.length; i++) {
    if (containers[i].state === "running") n++
  }
  return n
}

function dotColor(worst) {
  if (worst === "good") return "#22c55e"
  if (worst === "warn") return "#eab308"
  if (worst === "bad") return "#ef4444"
  return "#6b7280"
}

function clampPollInterval(sec, fallback) {
  var v = Number(sec)
  if (!isFinite(v) || v < 5) return typeof fallback === "number" ? fallback : 10
  if (v > 300) return 300
  return Math.round(v)
}

if (typeof module !== "undefined") {
  module.exports = {
    shortImage: shortImage,
    toPercent: toPercent,
    parsePsLines: parsePsLines,
    parseStatsLines: parseStatsLines,
    mergeStats: mergeStats,
    stateGlyph: stateGlyph,
    stateColor: stateColor,
    worstState: worstState,
    runningCount: runningCount,
    dotColor: dotColor,
    clampPollInterval: clampPollInterval
  }
}