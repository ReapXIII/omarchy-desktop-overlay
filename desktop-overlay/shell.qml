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
  // neutral dark palette if the file is missing or unreadable. These are the
  // theme's own values; see "effective colors" below for what actually gets
  // drawn once an advanced user's config.json overrides are layered on top.
  property color themeAccent: "#89b4fa"
  property color themeBackground: "#1e1e2e"
  property color themeForeground: "#cdd6f4"
  property color themeMutedForeground: "#9aa1b7"

  // Vitals row uses the theme's own bright green (its "everything's fine"
  // status hue) rather than the foreground/accent already used by the clock
  // and weather, so it reads as a distinct, brighter accent of the same theme.
  property color themeVitalsColor: "#a6e3a1"

  // `colors.toml` carries an explicit `mode = "light" | "dark"`. In dark
  // themes `dark_background` is darker than `background`, so using it for
  // the card gives the darkest thing on screen -- good separation from
  // most wallpapers. In light themes `dark_background` is barely darker
  // than `background` (both near-white), so the card nearly disappears
  // against a bright wallpaper; `darker_background` is the shade that
  // actually reads as distinct there. Same story for the text shadow: a
  // black halo behind near-black light-mode text just smears into the
  // glyphs, so light mode gets a light halo instead.
  property bool lightMode: false
  property color themeCardBgColor: themeBackground
  property real themeCardBgOpacity: 0.5
  property color themeTextHaloColor: "#000000"

  // ---- Advanced color overrides from config.json's optional "colors"
  // object (see applyOverlayConfig() below). Each is "" / -1 when unset, in
  // which case the theme value above wins -- so the default, with no
  // "colors" block at all, is exactly the live theme.
  property string colorAccent: ""
  property string colorBackground: ""
  property string colorForeground: ""
  property string colorMutedForeground: ""
  property string colorVitalsColor: ""
  property string colorTextHalo: ""
  property string colorBorder: ""
  property string colorDivider: ""
  property string colorHotTemp: ""
  property real colorCardOpacity: -1
  property real colorShadowBlur: -1
  property real colorShadowOffset: -1

  // ---- Effective colors: what everything below actually draws with. An
  // override wins over the theme; overriding "background" also restyles the
  // card, since the card is the only place background paints. Border and
  // divider default to theme-derived tints (a translucent accent/foreground)
  // rather than their own theme.toml fields, since colors.toml has no
  // "border" or "divider" role of its own.
  readonly property color accent: colorAccent !== "" ? colorAccent : themeAccent
  readonly property color background: colorBackground !== "" ? colorBackground : themeBackground
  readonly property color foreground: colorForeground !== "" ? colorForeground : themeForeground
  readonly property color mutedForeground: colorMutedForeground !== "" ? colorMutedForeground : themeMutedForeground
  readonly property color vitalsColor: colorVitalsColor !== "" ? colorVitalsColor : themeVitalsColor
  readonly property color cardBgColor: colorBackground !== "" ? colorBackground : themeCardBgColor
  readonly property real cardBgOpacity: colorCardOpacity >= 0 ? colorCardOpacity : themeCardBgOpacity
  readonly property color textHaloColor: colorTextHalo !== "" ? colorTextHalo : themeTextHaloColor
  readonly property color borderColor: colorBorder !== "" ? colorBorder : Qt.rgba(accent.r, accent.g, accent.b, 0.35)
  readonly property color dividerColor: colorDivider !== "" ? colorDivider : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.14)
  readonly property color hotTempColor: colorHotTemp !== "" ? colorHotTemp : "#f38ba8"

  // Text-shadow "size": shadowBlur is Qt's normalized 0-1 blur amount;
  // shadowOffset is a literal pixel vertical offset. Dark mode defaults to a
  // conventional offset drop shadow; light mode to a soft halo with no
  // offset (see applyTheme()'s comment on why a black halo blurs into
  // near-black text).
  readonly property real shadowBlurAmount: colorShadowBlur >= 0 ? colorShadowBlur : (lightMode ? 0.25 : 0.4)
  readonly property real shadowOffsetAmount: colorShadowOffset >= 0 ? colorShadowOffset : (lightMode ? 0 : 2)

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
    root.lightMode = parsed.mode === "light"
    if (parsed.accent) root.themeAccent = parsed.accent
    if (parsed.dark_background) root.themeBackground = parsed.dark_background
    if (parsed.foreground) root.themeForeground = parsed.foreground
    if (parsed.dark_foreground) root.themeMutedForeground = parsed.dark_foreground
    if (parsed.bright_green || parsed.green) root.themeVitalsColor = parsed.bright_green || parsed.green

    if (root.lightMode) {
      root.themeCardBgColor = parsed.darker_background || parsed.dark_background || root.themeBackground
      root.themeCardBgOpacity = 0.78
      root.themeTextHaloColor = "#ffffff"
    } else {
      root.themeCardBgColor = root.themeBackground
      root.themeCardBgOpacity = 0.5
      root.themeTextHaloColor = "#000000"
    }
  }

  // `watchChanges` alone isn't enough here: `omarchy theme set` swaps in a
  // brand-new theme directory (rm -rf + mv) rather than editing colors.toml
  // in place, so the inotify watch is left pointing at a now-deleted inode
  // and never fires again. Omarchy's own bar sidesteps this by having
  // `omarchy-theme-set` push the new palette over shell IPC instead of
  // relying on file watching -- see the "overlay" IpcHandler's reloadTheme()
  // below, wired up by install.sh's theme-set hook.
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
  property bool showCard: true

  // ---- System vitals (CPU/RAM/temp): off by default. `showCard` and
  // `vitalsVisible` together form a 4-state cycle -- card-only, card+vitals,
  // no-card, no-card+vitals -- stepped through at runtime by one keybind via
  // the "overlay" IPC target's toggleVitals (see IpcHandler below):
  // `qs ipc -n -p ~/.config/omarchy/desktop-overlay call -- overlay toggleVitals`.
  // toggleVitals() writes the new state back into config.json's
  // showCard/showVitals (see persistCardState() below), so it survives a
  // reboot and, just as importantly, survives the *next* config.json reload
  // -- e.g. the color picker rewriting the file to save a color pick would
  // otherwise stomp the toggle back to config.json's stale on-disk value
  // every time applyOverlayConfig() re-reads it.
  property bool vitalsVisible: false
  property real vitalsSize: 13

  function num(value, fallback) {
    var n = Number(value)
    return isFinite(n) && n > 0 ? n : fallback
  }

  // "" means unset (theme wins) -- see the effective-color properties above.
  // Anything that isn't a well-formed #rgb/#rgba/#rrggbb/#rrggbbaa string is
  // treated the same way rather than handed to QML's color parser, which
  // would just log a runtime warning and fall back to black.
  readonly property var hexColorPattern: /^#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/
  function hexColor(value) {
    return typeof value === "string" && hexColorPattern.test(value.trim()) ? value.trim() : ""
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
      root.showCard = cfg.showCard !== false
      root.vitalsVisible = cfg.showVitals === true
      root.vitalsSize = num(cfg.vitalsSize, 13)

      // Advanced: override individual theme colors. Omit "colors" (or any
      // key in it) to keep following the live theme for that color -- see
      // README's "Custom colors" section for the full key list.
      var colors = (cfg.colors && typeof cfg.colors === "object") ? cfg.colors : {}
      root.colorAccent = root.hexColor(colors.accent)
      root.colorBackground = root.hexColor(colors.background)
      root.colorForeground = root.hexColor(colors.foreground)
      root.colorMutedForeground = root.hexColor(colors.mutedForeground)
      root.colorVitalsColor = root.hexColor(colors.vitalsColor)
      root.colorTextHalo = root.hexColor(colors.textHalo)
      root.colorBorder = root.hexColor(colors.border)
      root.colorDivider = root.hexColor(colors.divider)
      root.colorHotTemp = root.hexColor(colors.hotTemp)
      root.colorCardOpacity = (typeof colors.cardOpacity === "number" && colors.cardOpacity >= 0 && colors.cardOpacity <= 1) ? colors.cardOpacity : -1
      root.colorShadowBlur = (typeof colors.shadowBlur === "number" && colors.shadowBlur >= 0 && colors.shadowBlur <= 1) ? colors.shadowBlur : -1
      root.colorShadowOffset = (typeof colors.shadowOffset === "number" && colors.shadowOffset >= 0 && colors.shadowOffset <= 20) ? colors.shadowOffset : -1
    } catch (e) {
      // Keep previous/default values; a half-written config.json is transient.
    }
  }

  // Re-reads the file fresh (rather than trusting anything cached) before
  // writing, so this only ever touches showCard/showVitals -- a concurrent
  // edit to any other key (e.g. the color picker saving a pick) can't be
  // clobbered by a stale in-memory copy of the rest of the config.
  function persistCardState() {
    try {
      var cfg = JSON.parse(overlayConfigFile.text() || "{}")
      cfg.showCard = root.showCard
      cfg.showVitals = root.vitalsVisible
      overlayConfigFile.setText(JSON.stringify(cfg, null, 2) + "\n")
    } catch (e) {
      // Leave config.json alone; the in-memory toggle still applies this session.
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

  // A failed fetch (network blip, wttr.in hiccup) used to just sit as
  // "unavailable" until the next full weatherRefreshMinutes cycle -- up to
  // 15 minutes of a dead-looking widget. Give it a few short retries first;
  // each full refresh cycle gets a fresh budget so an earlier exhausted
  // round (e.g. waking with the network still down) doesn't starve retries
  // for the rest of the session.
  property int weatherRetries: 0
  readonly property int weatherMaxRetries: 4

  function refreshWeather() {
    root.weatherRetries = 0
    fetchWeather()
  }

  function fetchWeather() {
    if (!statusProc.running) statusProc.running = true
    if (!iconProc.running) iconProc.running = true
  }

  function retryWeather() {
    if (root.weatherRetries >= root.weatherMaxRetries) return
    root.weatherRetries++
    weatherRetryTimer.restart()
  }

  Timer {
    id: weatherRetryTimer
    interval: 30 * 1000
    onTriggered: root.fetchWeather()
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
          root.retryWeather()
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
      onStreamFinished: root.applyVitals(text)
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
  // Steps through all 4 combinations of showCard/vitalsVisible in order:
  // card only -> card+vitals -> no card -> no card+vitals -> back to card only.
  IpcHandler {
    target: "overlay"

    // Called from the theme-set.d hook (see install.sh) right after
    // `omarchy theme set` swaps in the new theme directory, since watching
    // colors.toml for changes can't see through that swap (see themeFile
    // above).
    function reloadTheme(): string {
      themeFile.reload()
      return "ok"
    }

    function toggleVitals(): string {
      if (root.showCard && !root.vitalsVisible) {
        root.vitalsVisible = true
      } else if (root.showCard && root.vitalsVisible) {
        root.showCard = false
        root.vitalsVisible = false
      } else if (!root.showCard && !root.vitalsVisible) {
        root.vitalsVisible = true
      } else {
        root.showCard = true
        root.vitalsVisible = false
      }
      root.persistCardState()
      return (root.showCard ? "card" : "no-card") + (root.vitalsVisible ? "+vitals" : "")
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
        width: cardColumn.implicitWidth + (root.showCard ? 72 : 0)
        height: cardColumn.implicitHeight + (root.showCard ? 48 : 0)

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
          visible: root.showCard
          radius: 28
          color: Qt.rgba(root.cardBgColor.r, root.cardBgColor.g, root.cardBgColor.b, root.cardBgOpacity)
          border.width: 1
          border.color: root.borderColor

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

          // A subtle drop shadow on the text itself (not just the card), so
          // everything stays legible against a bright wallpaper even when
          // showCard turns the background off.
          layer.enabled: true
          layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: root.textHaloColor
            shadowOpacity: root.lightMode ? 0.7 : 0.85
            shadowBlur: root.shadowBlurAmount
            shadowVerticalOffset: root.shadowOffsetAmount
          }

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
            color: root.dividerColor
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
              color: root.vitalsColor
            }
            Text {
              visible: root.memPercent >= 0
              width: visible ? implicitWidth : 0
              text: "RAM " + Math.round(root.memPercent) + "%"
              font.family: root.fontFamily
              font.pixelSize: root.vitalsSize
              color: root.vitalsColor
            }
            Text {
              visible: root.tempAvailable
              width: visible ? implicitWidth : 0
              text: Math.round(root.tempC) + "°C"
              font.family: root.fontFamily
              font.pixelSize: root.vitalsSize
              color: root.tempC >= 80 ? root.hotTempColor : root.vitalsColor
            }
          }
        }
      }
  }
}
