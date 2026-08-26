#!/bin/bash
# Installs the desktop clock/weather overlay for Omarchy.
#
# Copies desktop-overlay/ into ~/.config/omarchy/desktop-overlay/, wires it
# into ~/.config/hypr/autostart.lua so it launches every login, and starts it
# for the current session. Safe to re-run: it won't clobber a config.json you
# already customized, and it won't add a duplicate autostart line.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/desktop-overlay"
DEST_DIR="$HOME/.config/omarchy/desktop-overlay"
AUTOSTART="$HOME/.config/hypr/autostart.lua"
AUTOSTART_LINE='o.launch_on_start("quickshell -n -p " .. os.getenv("HOME") .. "/.config/omarchy/desktop-overlay")'
AUTOSTART_MARKER="omarchy/desktop-overlay"
BINDINGS="$HOME/.config/hypr/bindings.lua"
KEYBIND_MARKER="Toggle desktop vitals"
KEYBIND_LINE='o.bind("SUPER + SHIFT + V", "Toggle desktop vitals", "qs ipc -n -p $HOME/.config/omarchy/desktop-overlay call -- overlay toggleVitals")'

command -v quickshell >/dev/null 2>&1 || {
  echo "quickshell was not found on PATH -- this overlay needs Omarchy's Quickshell install." >&2
  exit 1
}
command -v omarchy-weather-status >/dev/null 2>&1 || {
  echo "omarchy-weather-status was not found -- this only works on an Omarchy system." >&2
  exit 1
}

mkdir -p "$DEST_DIR"
cp "$SRC_DIR/shell.qml" "$DEST_DIR/shell.qml"

if [[ -f "$DEST_DIR/config.json" ]]; then
  echo "Keeping your existing config.json (position/size/font settings)."
else
  cp "$SRC_DIR/config.json" "$DEST_DIR/config.json"
  echo "Installed default config.json."
fi

if [[ -f "$AUTOSTART" ]]; then
  if grep -qF "$AUTOSTART_MARKER" "$AUTOSTART"; then
    echo "Autostart already wired up in $AUTOSTART -- leaving it alone."
  else
    {
      echo ""
      echo "-- Desktop clock/weather overlay: a separate Quickshell instance, layered"
      echo "-- above the wallpaper and behind normal windows. -n skips relaunching it if"
      echo "-- it's already running (e.g. after a config reload)."
      echo "$AUTOSTART_LINE"
    } >> "$AUTOSTART"
    echo "Added autostart entry to $AUTOSTART."
  fi
else
  echo "Warning: $AUTOSTART not found -- add this line to your Hyprland autostart yourself:" >&2
  echo "  $AUTOSTART_LINE" >&2
fi

if [[ -f "$BINDINGS" ]]; then
  if grep -qF "$KEYBIND_MARKER" "$BINDINGS"; then
    echo "Vitals toggle keybind already wired up in $BINDINGS -- leaving it alone."
  else
    {
      echo ""
      echo "-- Toggle CPU/RAM/temp on the desktop clock overlay (omarchy-desktop-overlay)."
      echo "$KEYBIND_LINE"
    } >> "$BINDINGS"
    echo "Added Super+Shift+V keybind to $BINDINGS (toggles the vitals row)."
    command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true
  fi
else
  echo "Warning: $BINDINGS not found -- add this keybind yourself to toggle vitals:" >&2
  echo "  $KEYBIND_LINE" >&2
fi

if pgrep -f "quickshell -n -p $DEST_DIR" >/dev/null 2>&1; then
  echo "Already running."
else
  setsid quickshell -n -p "$DEST_DIR" >/dev/null 2>&1 < /dev/null &
  disown
  echo "Started for this session."
fi

echo "Done. Edit $DEST_DIR/config.json to change position, size, or font -- it hot-reloads on save."
