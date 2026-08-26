import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Standalone desktop overlay: a big clock + weather card centered on the
// screen, drawn on the wlr "bottom" layer -- above the wallpaper (which sits
// on "background"), below every normal window. Fully click-through, so it
// never steals mouse input.
//
// Runs as its own Quickshell instance (see ~/.config/hypr/autostart.lua),
// independent of the Omarchy shell (the bar) so it can't be destabilized by
// -- or destabilize -- bar/plugin reloads.
//
// Data is pulled from the exact same sources the bar's clock/weather widgets
// use: the clock format and weather refresh interval come from
// ~/.config/omarchy/shell.json, and current conditions come from the same
// omarchy-weather-status / omarchy-weather-icon helpers the bar's weather
// pill uses (which in turn read the location saved by omarchy-weather-location).
//
// Position, size, and font are user-editable in the sibling config.json;
// see applyOverlayConfig() below for the schema. Edits hot-reload on save.
ShellRoot {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string themeColorsPath: home + "/.local/state/omarchy/current/theme/colors.toml"
  readonly property string shellConfigPath: home + "/.config/omarchy/shell.json"

  // ---- Theme colors, read live from the active Omarchy theme so the widget
  // re-themes itself the moment `omarchy theme set` runs. Falls back to a
  // neutral dark palette if the file is missing or unreadable.
  property color accent: "#89b4fa"
  property color background: "#1e1e2e"
  property color foreground: "#cdd6f4"
  property color mutedForeground: "#9aa1b7"

  function parseToml(text) {
    var out = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line || line.charAt(0) === "#") continue
      var eq = line.indexOf("=")
      if (eq === -1) continue
      var key = line.slice(0, eq).trim()
      var value = line.slice(eq + 1).trim().replace(/^"|"$/g, "")
      out[key] = value
    }
    return out
  }

  function applyTheme(text) {
    var parsed = parseToml(text)
    if (parsed.accent) root.accent = parsed.accent
    if (parsed.dark_background) root.background = parsed.dark_background
    if (parsed.foreground) root.foreground = parsed.foreground
    if (parsed.dark_foreground) root.mutedForeground = parsed.dark_foreground
  }

  FileView {
    id: themeFile
    path: root.themeColorsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyTheme(text())
    onFileChanged: reload()
  }

  // ---- Bar settings mirror: 12/24-hour clock and weather refresh cadence
  // follow whatever the bar's own clock/weather widgets are configured with,
  // so this overlay never disagrees with the taskbar.
  property bool use12Hour: false
  property int weatherRefreshMinutes: 15

  // ---- User-facing overlay config: position, size, font. Lives in its own
  // config.json (sibling to this file) rather than shell.json, since it has
  // nothing to do with the bar. Hot-reloads on save.
  readonly property string configPath: home + "/.config/omarchy/desktop-overlay/config.json"
  readonly property var validPositions: ["center", "top-left", "top-right", "bottom-left", "bottom-right", "top-center", "bottom-center"]

  property string position: "center"
  property real margin: 48
  property string fontFamily: "JetBrainsMono Nerd Font"
  property real timeSize: 76
  property real dateSize: 18
  property real weatherIconSize: 44
  property real weatherTempSize: 24
  property real weatherDetailSize: 13

  // ---- System vitals (CPU/RAM/temp): off by default, toggled at runtime via
  // the "overlay" IPC target (see IpcHandler below) -- bind a key to
  // `qs ipc -n -p ~/.config/omarchy/desktop-overlay call -- overlay toggleVitals`.
  // `showVitals` in config.json only sets the *starting* state on launch.
  property bool vitalsVisible: false
  property real vitalsSize: 13

  function num(value, fallback) {
    var n = Number(value)
    return isFinite(n) && n > 0 ? n : fallback
  }

  function applyOverlayConfig(text) {
    try {
      var cfg = JSON.parse(text || "{}")
      root.position = root.validPositions.indexOf(cfg.position) !== -1 ? cfg.position : "center"
      root.margin = num(cfg.margin, 48)
      root.fontFamily = typeof cfg.fontFamily === "string" && cfg.fontFamily.trim() !== "" ? cfg.fontFamily : "JetBrainsMono Nerd Font"
      root.timeSize = num(cfg.timeSize, 76)
      root.dateSize = num(cfg.dateSize, 18)
      root.weatherIconSize = num(cfg.weatherIconSize, 44)
      root.weatherTempSize = num(cfg.weatherTempSize, 24)
      root.weatherDetailSize = num(cfg.weatherDetailSize, 13)
      root.vitalsVisible = cfg.showVitals === true
      root.vitalsSize = num(cfg.vitalsSize, 13)
    } catch (e) {
      // Keep previous/default values; a half-written config.json is transient.
    }
  }

  FileView {
    id: overlayConfigFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyOverlayConfig(text())
    onLoadFailed: root.applyOverlayConfig("")
    onFileChanged: reload()
  }

  function applyShellConfig(text) {
    try {
      var cfg = JSON.parse(text || "{}")
      var layout = (cfg.bar && cfg.bar.layout) ? cfg.bar.layout : {}
      var entries = [].concat(layout.left || [], layout.center || [], layout.right || [])
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i]
        if (!entry) continue
        if (entry.id === "omarchy.clock" && typeof entry.format === "string")
          root.use12Hour = entry.format.indexOf("AP") !== -1
        if (entry.id === "omarchy.weather" && entry.refreshMinutes)
          root.weatherRefreshMinutes = Math.max(1, parseInt(entry.refreshMinutes, 10) || 15)
      }
    } catch (e) {
      // Keep previous values; a half-written shell.json is transient.
    }
  }

  FileView {
    id: shellConfigFile
    path: root.shellConfigPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyShellConfig(text())
    onFileChanged: reload()
  }

  // ---- Weather, fetched with the same helpers the bar's weather pill and
  // its right-click notification use.
  property string weatherIcon: ""
  property string weatherTemp: ""
  property string weatherLocation: ""
  property string weatherWind: ""
  property bool weatherAvailable: false

  function refreshWeather() {
    if (!statusProc.running) statusProc.running = true
    if (!iconProc.running) iconProc.running = true
  }

  Process {
    id: statusProc
    command: ["omarchy-weather-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        var parts = raw.split("·").map(function(s) { return s.trim() })
        if (parts.length >= 3 && raw.toLowerCase() !== "weather unavailable") {
          root.weatherLocation = parts[0]
          root.weatherTemp = parts[1].replace(/^Temp\s*/i, "")
          root.weatherWind = parts[2].replace(/^Wind\s*/i, "")
          root.weatherAvailable = true
        } else {
          root.weatherAvailable = false
        }
      }
    }
  }

  Process {
    id: iconProc
    command: ["omarchy-weather-icon"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw) root.weatherIcon = raw
      }
    }
  }

  Timer {
    interval: root.weatherRefreshMinutes * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshWeather()
  }

  // ---- System vitals: CPU%, RAM%, and hottest thermal zone (preferring the
  // CPU package sensor when present). Reads straight from /proc and /sys, so
  // no extra packages (e.g. lm_sensors) are required. Only polls while
  // visible, so it costs nothing when the row is hidden.
  property real cpuPercent: -1
  property real memPercent: -1
  property real tempC: -1
  property bool tempAvailable: false
  property real prevCpuTotal: -1
  property real prevCpuIdle: -1

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

  function refreshVitals() {
    if (!vitalsProc.running) vitalsProc.running = true
  }

  Process {
    id: vitalsProc
    command: ["bash", "-c",
      "cat /proc/stat | head -1; echo '---MEM---'; grep -E '^MemTotal|^MemAvailable' /proc/meminfo; echo '---TEMP---'; for f in /sys/class/thermal/thermal_zone*/type; do d=$(dirname \"$f\"); printf '%s|%s\\n' \"$(cat \"$f\" 2>/dev/null)\" \"$(cat \"$d/temp\" 2>/dev/null)\"; done 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyVitals(text())
    }
  }

  Timer {
    interval: 2000
    running: root.vitalsVisible
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshVitals()
  }

  // External toggle: `qs ipc -n -p ~/.config/omarchy/desktop-overlay call -- overlay toggleVitals`
  IpcHandler {
    target: "overlay"

    function toggleVitals(): string {
      root.vitalsVisible = !root.vitalsVisible
      return root.vitalsVisible ? "on" : "off"
    }

    function ping(): string { return "ok" }
  }

  // Primary monitor only. Quickshell has no explicit "primary" flag on a
  // screen, but its screens list is ordered the same way Qt's is, where
  // index 0 is the primary output -- so this is one panel, not one per
  // screen, and it stays without a `Variants` wrapper.
  PanelWindow {
      id: panel
      screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore

      WlrLayershell.namespace: "omarchy-desktop-overlay"
      // Bottom sits above the wallpaper's Background layer but below every
      // normal window, which is exactly "over the background, behind windows".
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      // An empty region: the surface accepts no pointer input at all, so
      // every click passes straight through to whatever is beneath it.
      mask: Region {}

      SystemClock {
        id: clock
        precision: SystemClock.Minutes
      }

      Item {
        id: card
        width: cardColumn.implicitWidth + 72
        height: cardColumn.implicitHeight + 48

        x: {
          if (root.position.indexOf("left") !== -1) return root.margin
          if (root.position.indexOf("right") !== -1) return parent.width - width - root.margin
          return (parent.width - width) / 2
        }
        y: {
          if (root.position.indexOf("top") !== -1) return root.margin
          if (root.position.indexOf("bottom") !== -1) return parent.height - height - root.margin
          return (parent.height - height) / 2
        }

        Rectangle {
          id: cardBg
          anchors.fill: parent
          radius: 28
          color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.5)
          border.width: 1
          border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)

          layer.enabled: true
          layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.5
            shadowBlur: 0.85
            shadowVerticalOffset: 10
          }
        }

        Column {
          id: cardColumn
          anchors.centerIn: parent
          spacing: 10

          readonly property real contentWidth: Math.max(
            timeLabel.implicitWidth, dateLabel.implicitWidth,
            weatherRow.implicitWidth, unavailableLabel.implicitWidth,
            vitalsRow.implicitWidth)

          Text {
            id: timeLabel
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, root.use12Hour ? "h:mm AP" : "HH:mm")
            font.family: root.fontFamily
            font.pixelSize: root.timeSize
            font.weight: Font.DemiBold
            color: root.foreground
          }

          Text {
            id: dateLabel
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
            font.family: root.fontFamily
            font.pixelSize: root.dateSize
            font.letterSpacing: 1
            color: root.mutedForeground
          }

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: cardColumn.contentWidth
            height: 1
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
          }

          Row {
            id: weatherRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 16
            visible: root.weatherAvailable
            height: visible ? implicitHeight : 0

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.weatherIcon
              font.family: root.fontFamily
              font.pixelSize: root.weatherIconSize
              color: root.accent
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: 2

              Text {
                text: root.weatherTemp
                font.family: root.fontFamily
                font.pixelSize: root.weatherTempSize
                font.weight: Font.Medium
                color: root.foreground
              }
              Text {
                text: root.weatherLocation + "  ·  Wind " + root.weatherWind
                font.family: root.fontFamily
                font.pixelSize: root.weatherDetailSize
                color: root.mutedForeground
              }
            }
          }

          Text {
            id: unavailableLabel
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !root.weatherAvailable
            height: visible ? implicitHeight : 0
            text: "Weather unavailable"
            font.family: root.fontFamily
            font.pixelSize: root.weatherDetailSize
            font.italic: true
            color: root.mutedForeground
          }

          Row {
            id: vitalsRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 16
            visible: root.vitalsVisible && (root.cpuPercent >= 0 || root.memPercent >= 0 || root.tempAvailable)
            height: visible ? implicitHeight : 0

            Text {
              visible: root.cpuPercent >= 0
              width: visible ? implicitWidth : 0
              text: "CPU " + Math.round(root.cpuPercent) + "%"
              font.family: root.fontFamily
              font.pixelSize: root.vitalsSize
              color: root.mutedForeground
            }
            Text {
              visible: root.memPercent >= 0
              width: visible ? implicitWidth : 0
              text: "RAM " + Math.round(root.memPercent) + "%"
              font.family: root.fontFamily
              font.pixelSize: root.vitalsSize
              color: root.mutedForeground
            }
            Text {
              visible: root.tempAvailable
              width: visible ? implicitWidth : 0
              text: Math.round(root.tempC) + "°C"
              font.family: root.fontFamily
              font.pixelSize: root.vitalsSize
              color: root.tempC >= 80 ? "#f38ba8" : root.mutedForeground
            }
          }
        }
      }
  }
}
