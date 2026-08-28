import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Standalone desktop overlay: a big clock + weather card centered on the
// screen, drawn on the wlr "bottom" layer -- above the wallpaper (which sits
// on "background"), below every normal window. Click-through except while
// actively being repositioned (see "positioning mode" below), so it never
// steals mouse input the rest of the time.
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
// CPU/RAM/temp used to live here too; that moved out to its own Omarchy bar
// plugin (see ../bar-plugin/) so it shows up in the taskbar itself rather
// than duplicating a status readout on the desktop.
//
// Position, size, and font are user-editable in the sibling config.json;
// see applyOverlayConfig() below for the schema. Edits hot-reload on save.
// Position can also be set by dragging: see "positioning mode" below.
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
  property string colorTextHalo: ""
  property string colorBorder: ""
  property string colorDivider: ""
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
  readonly property color cardBgColor: colorBackground !== "" ? colorBackground : themeCardBgColor
  readonly property real cardBgOpacity: colorCardOpacity >= 0 ? colorCardOpacity : themeCardBgOpacity
  readonly property color textHaloColor: colorTextHalo !== "" ? colorTextHalo : themeTextHaloColor
  readonly property color borderColor: colorBorder !== "" ? colorBorder : Qt.rgba(accent.r, accent.g, accent.b, 0.35)
  readonly property color dividerColor: colorDivider !== "" ? colorDivider : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.14)

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
  // "custom" is what dragging the card (see "positioning mode" below)
  // writes; the rest are the original fixed presets.
  readonly property var validPositions: ["center", "top-left", "top-right", "bottom-left", "bottom-right", "top-center", "bottom-center", "custom"]

  property string position: "center"
  property real margin: 48
  // Fractional (0-1) screen coordinates for position "custom" -- the card's
  // center as a fraction of screen width/height, so a saved position still
  // makes sense if the monitor resolution changes. Only used when
  // position === "custom"; ignored (like margin) otherwise.
  property real customX: 0.5
  property real customY: 0.5
  property string fontFamily: "JetBrainsMono Nerd Font"
  property real timeSize: 76
  property real dateSize: 18
  property real weatherIconSize: 44
  property real weatherTempSize: 24
  property real weatherDetailSize: 13
  property bool showCard: true

  // ---- Positioning mode: on for as long as the color picker
  // (color-picker.py) is open, rather than a dedicated keybind -- the
  // picker already sits next to the overlay as a live preview while you
  // pick colors, so it's also the natural place to grab and drag the card.
  // color-picker.py calls the "overlay" IPC target's startPositioning() on
  // window show and stopPositioning() on window close (see below). While
  // true, the card can be dragged anywhere on screen; each release writes
  // position "custom" plus customX/customY back to config.json immediately
  // -- so it's remembered even if you keep dragging it again before closing
  // the picker. The panel is click-through the rest of the time -- see the
  // PanelWindow's mask below, which only accepts pointer input over the
  // card itself, and only in this mode.
  property bool positioningMode: false

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

  function clampUnit(value, fallback) {
    return (typeof value === "number" && isFinite(value) && value >= 0 && value <= 1) ? value : fallback
  }

  function applyOverlayConfig(text) {
    try {
      var cfg = JSON.parse(text || "{}")
      root.position = root.validPositions.indexOf(cfg.position) !== -1 ? cfg.position : "center"
      root.margin = num(cfg.margin, 48)
      root.customX = clampUnit(cfg.customX, 0.5)
      root.customY = clampUnit(cfg.customY, 0.5)
      root.fontFamily = typeof cfg.fontFamily === "string" && cfg.fontFamily.trim() !== "" ? cfg.fontFamily : "JetBrainsMono Nerd Font"
      root.timeSize = num(cfg.timeSize, 76)
      root.dateSize = num(cfg.dateSize, 18)
      root.weatherIconSize = num(cfg.weatherIconSize, 44)
      root.weatherTempSize = num(cfg.weatherTempSize, 24)
      root.weatherDetailSize = num(cfg.weatherDetailSize, 13)
      root.showCard = cfg.showCard !== false

      // Advanced: override individual theme colors. Omit "colors" (or any
      // key in it) to keep following the live theme for that color -- see
      // README's "Custom colors" section for the full key list.
      var colors = (cfg.colors && typeof cfg.colors === "object") ? cfg.colors : {}
      root.colorAccent = root.hexColor(colors.accent)
      root.colorBackground = root.hexColor(colors.background)
      root.colorForeground = root.hexColor(colors.foreground)
      root.colorMutedForeground = root.hexColor(colors.mutedForeground)
      root.colorTextHalo = root.hexColor(colors.textHalo)
      root.colorBorder = root.hexColor(colors.border)
      root.colorDivider = root.hexColor(colors.divider)
      root.colorCardOpacity = (typeof colors.cardOpacity === "number" && colors.cardOpacity >= 0 && colors.cardOpacity <= 1) ? colors.cardOpacity : -1
      root.colorShadowBlur = (typeof colors.shadowBlur === "number" && colors.shadowBlur >= 0 && colors.shadowBlur <= 1) ? colors.shadowBlur : -1
      root.colorShadowOffset = (typeof colors.shadowOffset === "number" && colors.shadowOffset >= 0 && colors.shadowOffset <= 20) ? colors.shadowOffset : -1
    } catch (e) {
      // Keep previous/default values; a half-written config.json is transient.
    }
  }

  // Re-reads the file fresh (rather than trusting anything cached) before
  // writing, so each of these only ever touches its own keys -- a concurrent
  // edit to any other key (e.g. the color picker saving a pick while a drag
  // is also in flight) can't be clobbered by a stale in-memory copy of the
  // rest of the config.
  function persistCardState() {
    try {
      var cfg = JSON.parse(overlayConfigFile.text() || "{}")
      cfg.showCard = root.showCard
      overlayConfigFile.setText(JSON.stringify(cfg, null, 2) + "\n")
    } catch (e) {
      // Leave config.json alone; the in-memory toggle still applies this session.
    }
  }

  function persistPosition() {
    try {
      var cfg = JSON.parse(overlayConfigFile.text() || "{}")
      cfg.position = root.position
      cfg.customX = root.customX
      cfg.customY = root.customY
      overlayConfigFile.setText(JSON.stringify(cfg, null, 2) + "\n")
    } catch (e) {
      // Leave config.json alone; the in-memory position still applies this session.
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

  // External calls:
  //   qs ipc -n -p ~/.config/omarchy/desktop-overlay call -- overlay toggleCard
  //   qs ipc -n -p ~/.config/omarchy/desktop-overlay call -- overlay startPositioning
  //   qs ipc -n -p ~/.config/omarchy/desktop-overlay call -- overlay stopPositioning
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

    function toggleCard(): string {
      root.showCard = !root.showCard
      root.persistCardState()
      return root.showCard ? "card" : "no-card"
    }

    // Called by color-picker.py on window show/destroy (see its
    // COLOR_PICKER_LINE-launched process) -- explicit start/stop rather than
    // a toggle, since the picker's own open/closed state is already
    // authoritative and a toggle could drift out of sync with it (e.g. two
    // stray calls in a row).
    function startPositioning(): string {
      root.positioningMode = true
      return "positioning-on"
    }

    function stopPositioning(): string {
      root.positioningMode = false
      return "positioning-off"
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

      // Click-through everywhere except the card itself, and even that only
      // while root.positioningMode is true -- otherwise this is the same
      // fully click-through empty region as before, so every click passes
      // straight through to whatever is beneath it.
      Region { id: clickThroughRegion }
      Region { id: cardDragRegion; item: card }
      mask: root.positioningMode ? cardDragRegion : clickThroughRegion

      SystemClock {
        id: clock
        precision: SystemClock.Minutes
      }

      Item {
        id: card
        width: cardColumn.implicitWidth + (root.showCard ? 72 : 0)
        height: cardColumn.implicitHeight + (root.showCard ? 48 : 0)

        // x/y are computed imperatively (rather than declaratively bound)
        // so DragHandler below can take them over mid-drag without fighting
        // a binding -- see computePosition() and the DragHandler's
        // onActiveChanged.
        function computePosition() {
          if (!card.parent) return
          if (root.position === "custom") {
            var targetX = root.customX * card.parent.width
            var targetY = root.customY * card.parent.height
            card.x = Math.max(0, Math.min(card.parent.width - card.width, targetX - card.width / 2))
            card.y = Math.max(0, Math.min(card.parent.height - card.height, targetY - card.height / 2))
            return
          }
          if (root.position.indexOf("left") !== -1) card.x = root.margin
          else if (root.position.indexOf("right") !== -1) card.x = card.parent.width - card.width - root.margin
          else card.x = (card.parent.width - card.width) / 2
          if (root.position.indexOf("top") !== -1) card.y = root.margin
          else if (root.position.indexOf("bottom") !== -1) card.y = card.parent.height - card.height - root.margin
          else card.y = (card.parent.height - card.height) / 2
        }

        onWidthChanged: computePosition()
        onHeightChanged: computePosition()
        Component.onCompleted: computePosition()

        Connections {
          target: root
          function onPositionChanged() { card.computePosition() }
          function onMarginChanged() { card.computePosition() }
          function onCustomXChanged() { card.computePosition() }
          function onCustomYChanged() { card.computePosition() }
        }

        Connections {
          target: card.parent
          ignoreUnknownSignals: true
          function onWidthChanged() { card.computePosition() }
          function onHeightChanged() { card.computePosition() }
        }

        DragHandler {
          id: dragHandler
          // A static target with `enabled` gating it (rather than toggling
          // `target` itself between card/null) -- reassigning `target` was
          // leaving Qt's internal drag reference frame stale on
          // reattachment, which is what caused wildly-wrong jumps instead
          // of tracking the cursor.
          target: card
          enabled: root.positioningMode
          xAxis.minimum: 0
          xAxis.maximum: card.parent ? Math.max(0, card.parent.width - card.width) : 0
          yAxis.minimum: 0
          yAxis.maximum: card.parent ? Math.max(0, card.parent.height - card.height) : 0

          onActiveChanged: {
            if (active || !root.positioningMode || !card.parent) return
            // Capture the drag's true end position into locals *before*
            // touching any root property. Assigning root.customX alone
            // synchronously triggers computePosition() (via the Connections
            // handler below) using the still-stale root.customY, which
            // resets card.y back to its old position right then -- so
            // reading card.y *after* that assignment would silently read
            // back the old, wrong value instead of where the card was just
            // dragged to. Computing both from local snapshots first sidesteps
            // that entirely.
            var newCustomX = Math.max(0, Math.min(1, (card.x + card.width / 2) / card.parent.width))
            var newCustomY = Math.max(0, Math.min(1, (card.y + card.height / 2) / card.parent.height))
            root.customX = newCustomX
            root.customY = newCustomY
            root.position = "custom"
            root.persistPosition()
          }
        }

        HoverHandler {
          enabled: root.positioningMode
          cursorShape: Qt.SizeAllCursor
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

        // Positioning-mode affordance: an accent outline around the card so
        // it's obvious it's draggable right now, drawn regardless of
        // showCard (so a card-hidden setup still shows something to grab).
        Rectangle {
          anchors.fill: parent
          visible: root.positioningMode
          radius: cardBg.radius
          color: "transparent"
          border.width: 2
          border.color: root.accent
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
            weatherRow.implicitWidth, unavailableLabel.implicitWidth)

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
        }
      }
  }
}
