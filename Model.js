.pragma library

// Shape returned before `vmkill` has ever answered. It reads "blocked" on
// purpose: the widget should never draw a reassuring "allowed" that it has not
// actually confirmed, and the script itself defaults to blocked too.
var EMPTY = {
  desired: "blocked",
  effective: "blocked",
  reason: "user",
  requireVpn: false,
  lanBlocked: true,
  vpn: "UNKNOWN",
  firewall: "UNKNOWN",
  vms: []
}

function parse(text) {
  try {
    var parsed = JSON.parse(String(text || ""))
    if (!parsed || typeof parsed !== "object") return null
    if (!Array.isArray(parsed.vms)) parsed.vms = []
    return parsed
  } catch (e) {
    return null
  }
}

function runningVms(state) {
  return (state.vms || []).filter(function(v) { return v.running === true })
}

function totalDropped(state) {
  return runningVms(state).reduce(function(sum, v) {
    var n = Number(v.dropped)
    return sum + (isFinite(n) ? n : 0)
  }, 0)
}

// The one-line summary in the hero and the tooltip. The distinction that
// matters is *why* traffic is blocked: a cut you asked for and a cut the VPN
// policy imposed look identical at the firewall and mean different things to
// you.
function summary(state) {
  var running = runningVms(state).length
  if (running === 0) return "no VM running"
  if (state.effective !== "blocked") return running === 1 ? "online" : running + " VMs online"

  if (state.reason === "vpn") return "held — VPN " + friendlyVpn(state.vpn)
  if (state.reason === "firewall") return "held — IVPN firewall off"
  return running === 1 ? "cut off" : running + " VMs cut off"
}

function friendlyVpn(s) {
  switch (String(s || "").toUpperCase()) {
    case "CONNECTED": return "connected"
    case "DISCONNECTED": return "down"
    case "CONNECTING": return "connecting"
    case "RECONNECTING": return "reconnecting"
    case "DISCONNECTING": return "disconnecting"
    case "PAUSED": return "paused"
    case "UNAVAILABLE": return "unavailable"
    default: return "unknown"
  }
}

// Full sentence for the explanatory line under the hero. Returns "" when
// there is nothing worth saying, so the caller can hide the row.
function explanation(state) {
  if (state.reason === "vpn")
    return "Waiting for IVPN. The VMs stay cut off until the tunnel is up — connecting now."
  if (state.reason === "firewall")
    return "Tunnel is up, arming the IVPN firewall. The VMs stay cut off until it is on."
  if (state.effective === "blocked" && state.desired === "blocked")
    return "Every guest-initiated connection is dropped. RDP and the shared folder keep working."
  if (state.effective !== "blocked" && !state.requireVpn)
    return "The VMs can reach the internet by whatever route the host uses — the VPN is not being enforced."
  return ""
}

function vmLabel(vm) {
  // "omarchy-windows-eng" -> "Windows-Eng"
  var n = String(vm.name || "")
  n = n.replace(/^omarchy-/, "")
  return n.replace(/(^|-)([a-z])/g, function(_, sep, ch) { return sep + ch.toUpperCase() })
}

function vmStatus(vm) {
  if (!vm.running) return "not running"
  return vm.blocked ? "blocked" : "allowed"
}

function formatCount(n) {
  var v = Number(n)
  if (!isFinite(v) || v <= 0) return ""
  if (v < 1000) return v + " dropped"
  if (v < 1000000) return (v / 1000).toFixed(v < 10000 ? 1 : 0) + "k dropped"
  return (v / 1000000).toFixed(1) + "M dropped"
}
