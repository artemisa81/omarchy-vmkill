import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "artemisa81.vmkill"
  ipcTarget: "artemisa81.vmkill"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool idle: vmkill.runningVms.length === 0

  // Three states worth telling apart at a glance: nothing running (dim), the
  // VMs are online (normal), the VMs are cut off (urgent when a policy did it
  // rather than you, because that one you did not ask for).
  readonly property color barIconColor: {
    if (idle) return Qt.darker(barForeground, 1.9)
    if (vmkill.heldByPolicy) return urgent
    return vmkill.blocked ? barForeground : Qt.darker(barForeground, 1.35)
  }

  readonly property string tooltip: {
    if (vmkill.lastError !== "") return "VM Killswitch — " + vmkill.lastError
    var head = "VM Killswitch — " + vmkill.summary
    if (vmkill.requireVpn) head += "\nVPN required: " + Model.friendlyVpn(vmkill.vpn)
    if (vmkill.blocked && vmkill.totalDropped > 0 && vmkill.showDropped)
      head += "\n" + Model.formatCount(vmkill.totalDropped)
    return head
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Service {
    id: vmkill
    settings: root.settings
  }

  onOpenedChanged: if (opened) {
    vmkill.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function cut(): void { if (!vmkill.blocked) vmkill.toggle() }
    function allow(): void { if (vmkill.blocked) vmkill.toggle() }
    function switchNet(): void { vmkill.toggle() }
    function refresh(): string { vmkill.refresh(); return "ok" }
    function status(): string { return vmkill.summary }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Both glyphs are already used elsewhere in the Omarchy shell, so they are
    // known to exist in the bar font rather than rendering as tofu.
    text: vmkill.blocked ? "󰤮" : "󰍹"
    foreground: root.barIconColor
    tooltipText: root.tooltip
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) vmkill.toggle()
      else if (buttonCode === Qt.MiddleButton) vmkill.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") vmkill.refresh()
        else if (t === "b" || t === "B") vmkill.toggle()
        else if (t === "v" || t === "V") vmkill.setRequireVpn(!vmkill.requireVpn)
        else if (t === "l" || t === "L") vmkill.setLanBlocked(!vmkill.lanBlocked)
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(12)

        PanelHero {
          id: hero
          width: parent.width
          title: "VM Killswitch"
          meta: vmkill.summary
          detail: vmkill.blocked ? "blocked" : "online"
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: root.idle ? 0.5 : 1.0
          iconComponent: Component {
            Text {
              text: vmkill.blocked ? "󰤮" : "󰍹"
              color: vmkill.heldByPolicy ? root.urgent : (vmkill.blocked ? root.foreground : root.accent)
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: Component {
            ToggleSwitch {
              id: netSwitch
              // On = the VMs may reach the internet. Deliberately not "on =
              // killswitch armed": the switch should read the same way as
              // every other network toggle in the bar.
              checked: vmkill.switchOn
              busy: vmkill.busy
              interactive: vmkill.everParsed
              foreground: hero.foreground
              onToggled: vmkill.toggle()

              PanelToolTip {
                visible: netSwitch.containsMouse
                text: vmkill.blocked ? "Allow internet" : "Cut internet"
                fontFamily: hero.fontFamily
              }
            }
          }
        }

        Text {
          visible: text !== ""
          width: parent.width
          text: vmkill.lastError !== "" ? vmkill.lastError : vmkill.explanation
          color: (vmkill.lastError !== "" || vmkill.heldByPolicy) ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "VIRTUAL MACHINES"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            visible: vmkill.vms.length === 0
            width: parent.width
            text: vmkill.everParsed ? "No dockur/windows VMs configured." : "Reading…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: vmkill.vms
            Item {
              required property var modelData
              width: column.width
              height: vmRow.implicitHeight

              Row {
                id: vmRow
                width: parent.width

                Text {
                  width: parent.width * 0.45
                  text: Model.vmLabel(modelData)
                  color: modelData.running ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width * 0.3
                  text: Model.vmStatus(modelData)
                  color: !modelData.running ? root.dim : (modelData.blocked ? root.urgent : root.accent)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  width: parent.width * 0.25
                  horizontalAlignment: Text.AlignRight
                  visible: vmkill.showDropped
                  text: modelData.running && modelData.blocked ? Model.formatCount(modelData.dropped) : ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(8)

          Toggle {
            width: parent.width
            label: "Require VPN"
            description: "Hold the VMs offline unless IVPN is connected with its firewall on"
            checked: vmkill.requireVpn
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: vmkill.setRequireVpn(!vmkill.requireVpn)
          }

          Toggle {
            width: parent.width
            label: "Isolate from LAN"
            description: "Block the VMs from your homelab, tailnet and the host itself"
            checked: vmkill.lanBlocked
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: vmkill.setLanBlocked(!vmkill.lanBlocked)
          }
        }

        Text {
          width: parent.width
          text: "RDP and the shared folder are never affected — the rules only stop connections the guest starts."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
