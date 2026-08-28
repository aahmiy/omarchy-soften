// soften.status — one glyph in the bar, the machine's state behind it.
//
// The bar side stays deliberately mute: a single icon, which only picks up the
// urgent color when a watched unit has actually failed. Everything else lives
// in the panel, so the bar does not turn into a dashboard.
//
// Data comes from collect.sh, which shells out to `systemctl show` and `ss`
// and prints one JSON blob. It runs when the panel opens and on a timer while
// it stays open — never in the background.

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Panel {
  id: root
  moduleName: "soften.status"
  ipcTarget: "soften.status"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property var services: []
  property var ports: []
  property bool loaded: false

  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/soften.status"
  readonly property int refreshInterval: Math.max(1000, root.setting("interval", 5000))
  readonly property var extraUnits: String(root.setting("units", "")).split(/\s+/).filter(function (unit) {
    return unit.length > 0
  })

  readonly property int failedCount: services.filter(function (service) {
    return service.state === "failed"
  }).length
  readonly property int upCount: services.filter(function (service) {
    return service.state === "up"
  }).length
  readonly property int exposedCount: ports.filter(function (entry) {
    return entry.exposed
  }).length

  readonly property string summary: {
    if (!loaded) return "reading…"
    var parts = []
    parts.push(upCount + "/" + services.length + " up")
    parts.push(ports.length + (ports.length === 1 ? " port" : " ports"))
    if (exposedCount > 0) parts.push(exposedCount + " exposed")
    return parts.join("  ·  ")
  }

  function stateColor(state) {
    if (state === "failed") return root.bar ? root.bar.urgent : Color.urgent
    if (state === "up") return root.bar ? root.bar.foreground : Color.foreground
    return Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.9)
  }

  function refresh() {
    collector.command = ["bash", root.pluginDir + "/collect.sh"].concat(root.extraUnits)
    collector.running = true
  }

  Process {
    id: collector
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var payload = JSON.parse(text || "{}")
          root.services = payload.services || []
          root.ports = payload.ports || []
          root.loaded = true
        } catch (e) {
          // A malformed blob means collect.sh is missing or broke; keep the
          // last good reading rather than blanking the panel.
        }
      }
    }
  }

  Timer {
    // Only ticks while the panel is on screen.
    running: root.opened
    interval: root.refreshInterval
    repeat: true
    onTriggered: root.refresh()
  }

  onOpenedChanged: if (opened) refresh()
  Component.onCompleted: refresh()

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-md-server
    text: "󰒋"
    active: root.failedCount > 0
    useActiveColor: true
    activeColor: root.bar ? root.bar.urgent : Color.urgent
    onPressed: function (b) { root.toggle() }
    tooltipText: "Status — " + root.summary
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(330))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- Hero ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              text: "󰒋"
              color: root.failedCount > 0
                ? (root.bar ? root.bar.urgent : Color.urgent)
                : (root.bar ? root.bar.foreground : Color.foreground)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Status"
                color: root.bar ? root.bar.foreground : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                text: root.summary
                color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          // ---------- Services ----------
          PanelSeparator {
            visible: root.services.length > 0
            foreground: root.bar ? root.bar.foreground : Color.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.services.length > 0

            PanelSectionHeader {
              text: "SERVICES"
              foreground: root.bar ? root.bar.foreground : Color.foreground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }

            Repeater {
              model: root.services

              CursorSurface {
                id: serviceRow
                required property var modelData

                width: parent.width
                height: Style.spacing.popupRowHeight
                foreground: root.bar ? root.bar.foreground : Color.foreground
                hasCursor: serviceHover.hovered

                HoverHandler { id: serviceHover }

                Rectangle {
                  id: dot
                  width: Style.space(7)
                  height: width
                  radius: width / 2
                  color: root.stateColor(serviceRow.modelData.state)
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: serviceRow.modelData.label
                  color: serviceRow.modelData.state === "down"
                    ? Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.5)
                    : (root.bar ? root.bar.foreground : Color.foreground)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                  anchors.left: dot.right
                  anchors.leftMargin: Style.space(10)
                  anchors.right: serviceState.left
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: serviceState
                  text: serviceRow.modelData.detail
                  color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.6)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                }

                TapHandler {
                  onTapped: {
                    if (!root.bar) return
                    root.bar.run("omarchy-launch-or-focus-tui systemctl status --no-pager "
                      + root.bar.shellQuote(serviceRow.modelData.name + ".service"))
                    root.close()
                  }
                }
              }
            }
          }

          // ---------- Listening ports ----------
          PanelSeparator {
            visible: root.ports.length > 0
            foreground: root.bar ? root.bar.foreground : Color.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.ports.length > 0

            PanelSectionHeader {
              text: "LISTENING"
              foreground: root.bar ? root.bar.foreground : Color.foreground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }

            Repeater {
              model: root.ports

              CursorSurface {
                id: portRow
                required property var modelData

                width: parent.width
                height: Style.spacing.popupRowHeight
                foreground: root.bar ? root.bar.foreground : Color.foreground
                hasCursor: portHover.hovered

                HoverHandler { id: portHover }

                Text {
                  id: portNumber
                  text: portRow.modelData.port
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: portRow.modelData.proc !== "" ? portRow.modelData.proc : portRow.modelData.addr
                  color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                  anchors.left: portNumber.right
                  anchors.leftMargin: Style.space(14)
                  anchors.right: exposedTag.left
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                }

                // Only bindings reachable from off this machine get called out.
                Text {
                  id: exposedTag
                  text: portRow.modelData.exposed ? "exposed" : ""
                  color: root.bar ? root.bar.urgent : Color.urgent
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          // ---------- Empty ----------
          Text {
            width: parent.width
            visible: root.loaded && root.services.length === 0 && root.ports.length === 0
            text: "Nothing listening, nothing watched."
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.5)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
