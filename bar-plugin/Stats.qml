import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// CPU%, RAM%, and hottest thermal zone (preferring the CPU package sensor
// when present), read straight from /proc and /sys -- no lm_sensors or
// other extra packages needed. Lives in the taskbar itself (see the repo's
// install.sh, which places this right after the Workspaces widget on the
// left), rather than duplicating a status readout on the desktop overlay
// this repo also ships -- see ../desktop-overlay/.
//
// Drawn with the bar's own theme tokens (Color.*/Style.*), so it re-themes
// itself automatically on `omarchy theme set` -- no config or color picker
// needed, unlike the desktop overlay's clock/weather card.
BarWidget {
  id: root
  moduleName: "reapxiii.system-stats"

  property real cpuPercent: -1
  property real memPercent: -1
  property real tempC: -1
  property bool tempAvailable: false
  property real prevCpuTotal: -1
  property real prevCpuIdle: -1

  readonly property bool hasData: cpuPercent >= 0 || memPercent >= 0 || tempAvailable
  readonly property color textColor: root.bar ? root.bar.barForeground : Color.foreground

  visible: !vertical && hasData
  implicitWidth: visible ? statsRow.implicitWidth : 0
  implicitHeight: barSize

  function applyVitals(text) {
    try {
      var memSplit = String(text || "").split("---MEM---")
      var cpuLine = memSplit[0].trim()
      var tempSplit = (memSplit[1] || "").split("---TEMP---")
      var memBlock = tempSplit[0] || ""
      var tempBlock = tempSplit[1] || ""

      var cpuFields = cpuLine.split(/\s+/).slice(1).map(Number)
      if (cpuFields.length >= 4) {
        var idle = cpuFields[3] + (cpuFields[4] || 0)
        var total = cpuFields.reduce(function(a, b) { return a + (isFinite(b) ? b : 0) }, 0)
        if (root.prevCpuTotal >= 0) {
          var totalDelta = total - root.prevCpuTotal
          var idleDelta = idle - root.prevCpuIdle
          if (totalDelta > 0)
            root.cpuPercent = Math.max(0, Math.min(100, 100 * (totalDelta - idleDelta) / totalDelta))
        }
        root.prevCpuTotal = total
        root.prevCpuIdle = idle
      }

      var memTotal = 0, memAvail = 0
      memBlock.split("\n").forEach(function(line) {
        var m = line.match(/^(MemTotal|MemAvailable):\s*(\d+)/)
        if (!m) return
        if (m[1] === "MemTotal") memTotal = Number(m[2]); else memAvail = Number(m[2])
      })
      if (memTotal > 0)
        root.memPercent = Math.max(0, Math.min(100, 100 * (memTotal - memAvail) / memTotal))

      var best = null
      tempBlock.split("\n").forEach(function(line) {
        var parts = line.split("|")
        if (parts.length !== 2) return
        var type = parts[0].trim()
        var milli = Number(parts[1].trim())
        if (!isFinite(milli)) return
        var entry = { type: type, c: milli / 1000 }
        if (!best) best = entry
        if (/x86_pkg_temp|cpu/i.test(type)) best = entry
      })
      root.tempAvailable = !!best
      if (best) root.tempC = best.c
    } catch (e) {
      // Transient/partial poll output; keep previous values.
    }
  }

  function refresh() {
    if (!vitalsProc.running) vitalsProc.running = true
  }

  Process {
    id: vitalsProc
    command: ["bash", "-c",
      "cat /proc/stat | head -1; echo '---MEM---'; grep -E '^MemTotal|^MemAvailable' /proc/meminfo; echo '---TEMP---'; for f in /sys/class/thermal/thermal_zone*/type; do d=$(dirname \"$f\"); printf '%s|%s\\n' \"$(cat \"$f\" 2>/dev/null)\" \"$(cat \"$d/temp\" 2>/dev/null)\"; done 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyVitals(text)
    }
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Row {
    id: statsRow
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(10)

    // The "space | space" divider that sets this widget off from whatever
    // sits before it in the bar layout (the Workspaces widget, by default
    // -- see install.sh).
    Text {
      text: "|"
      color: Color.muted
      opacity: 0.6
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      visible: root.cpuPercent >= 0
      width: visible ? implicitWidth : 0
      text: "CPU " + Math.round(root.cpuPercent) + "%"
      color: root.textColor
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      visible: root.memPercent >= 0
      width: visible ? implicitWidth : 0
      text: "RAM " + Math.round(root.memPercent) + "%"
      color: root.textColor
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      visible: root.tempAvailable
      width: visible ? implicitWidth : 0
      text: Math.round(root.tempC) + "°C"
      color: root.tempC >= 80 ? Color.urgent : root.textColor
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      anchors.verticalCenter: parent.verticalCenter
    }
  }
}
