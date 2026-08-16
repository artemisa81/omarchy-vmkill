import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property var state: Model.EMPTY
  property bool everParsed: false
  property string lastError: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 8, 3, 60)
  readonly property bool notifyEnabled: setting("notify", true) !== false
  readonly property bool showDropped: setting("showDropped", true) !== false

  readonly property bool blocked: String(state.effective) === "blocked"
  readonly property bool heldByPolicy: state.reason === "vpn" || state.reason === "firewall"
  readonly property string vpn: String(state.vpn || "UNKNOWN")
  readonly property string firewall: String(state.firewall || "UNKNOWN")
  readonly property bool requireVpn: state.requireVpn === true
  readonly property bool lanBlocked: state.lanBlocked === true
  readonly property var vms: state.vms || []
  readonly property var runningVms: Model.runningVms(state)
  readonly property int totalDropped: Model.totalDropped(state)
  readonly property string summary: Model.summary(state)
  readonly property string explanation: Model.explanation(state)
  readonly property bool busy: syncProcess.running || actionProcess.running

  // Optimistic switch position so a click reacts immediately instead of
  // waiting out a poll. -1 follows the real state; 0/1 while a toggle settles.
  // The require-VPN policy can overrule the request, so this only ever governs
  // the switch's own animation, never what the panel reports as true.
  property int _desired: -1
  readonly property bool switchOn: _desired === -1 ? !blocked : (_desired === 1)

  property bool _lastBlocked: true

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function refresh() {
    if (!syncProcess.running) syncProcess.running = true
  }

  // Every tick reconciles as well as reads. That is what makes a VM restarted
  // by windows-vm-launch pick its rules back up on its own: the container is
  // recreated, its namespace comes up empty, and the next sync refills it.
  function run(args) {
    if (actionProcess.running) return
    actionProcess.command = ["vmkill"].concat(args)
    actionProcess.running = true
  }

  function toggle() {
    _desired = blocked ? 1 : 0
    run([blocked ? "off" : "on"])
  }

  function setRequireVpn(on) { run(["vpn", on ? "on" : "off"]) }
  function setLanBlocked(on) { run(["lan", on ? "on" : "off"]) }

  function notify(title, body, urgent) {
    if (!notifyEnabled || !everParsed) return
    var cmd = ["omarchy-notification-send"]
    if (urgent) cmd = cmd.concat(["-u", "critical"])
    Quickshell.execDetached(cmd.concat([title, body]))
  }

  onBlockedChanged: {
    if (!everParsed || blocked === _lastBlocked) return
    _lastBlocked = blocked
    if (blocked)
      notify("VM Killswitch", heldByPolicy ? "VMs cut off — " + summary : "VMs cut off from the internet", heldByPolicy)
    else
      notify("VM Killswitch", "VMs are online" + (requireVpn ? " through the VPN" : ""), false)
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    // A toggle takes a moment to land (and, under the VPN policy, may take a
    // tunnel handshake). Poll faster for a while so the panel catches up.
    id: settleTimer
    property int ticks: 0
    interval: 1500
    repeat: true
    running: false
    onTriggered: {
      settleTimer.ticks += 1
      root.refresh()
      if (settleTimer.ticks >= 12) {
        settleTimer.ticks = 0
        settleTimer.running = false
        root._desired = -1
      }
    }
  }

  Timer {
    // If nothing has parsed by now, `vmkill` is not answering: not on PATH,
    // or docker is unreachable. Say so rather than sitting on a stale "blocked".
    id: watchdogTimer
    interval: 15000
    repeat: false
    running: true
    onTriggered: if (!root.everParsed) root.lastError = "vmkill is not responding — check: vmkill status --plain"
  }

  Process {
    id: syncProcess
    running: false
    command: ["vmkill", "sync"]
    stdout: StdioCollector { id: syncStdout; waitForEnd: true }
    stderr: StdioCollector { id: syncStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var parsed = Model.parse(syncStdout.text)
      if (parsed) {
        if (!root.everParsed) root._lastBlocked = String(parsed.effective) === "blocked"
        root.everParsed = true
        root.lastError = ""
        root.state = parsed
        if (root._desired !== -1 && root.blocked === (root._desired === 0)) root._desired = -1
      } else if (exitCode !== 0) {
        root.lastError = String(syncStderr.text || "").trim() || "vmkill sync failed"
      }
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = String(actionStderr.text || "").trim() || "vmkill command failed"
      }
      settleTimer.ticks = 0
      settleTimer.restart()
      root.refresh()
    }
  }
}
