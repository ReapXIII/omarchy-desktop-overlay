#!/bin/bash
# Removes the desktop clock/weather overlay: stops the running instance,
# strips its autostart entry and keybinds, and (with --purge) deletes its
# config too.
#
# This does not touch the CPU/RAM/temp taskbar widget -- that's a separate
# plugin now (https://github.com/ReapXIII/omarchy-bar-stats); remove it with
# `omarchy plugin remove reapxiii.system-stats --yes` if you want it gone too.
set -euo pipefail

DEST_DIR="$HOME/.config/omarchy/desktop-overlay"
AUTOSTART="$HOME/.config/hypr/autostart.lua"
BINDINGS="$HOME/.config/hypr/bindings.lua"
WINDOWS_LUA="$HOME/.config/hypr/windows.lua"
THEME_HOOK_DEST="$HOME/.config/omarchy/hooks/theme-set.d/desktop-overlay.sh"

pkill -f "quickshell -n -p $DEST_DIR" 2>/dev/null && echo "Stopped running overlay." || true
pkill -f "desktop-overlay/color-picker.py" 2>/dev/null && echo "Closed the color picker." || true

if [[ -f "$THEME_HOOK_DEST" ]]; then
  rm -f "$THEME_HOOK_DEST"
  echo "Removed theme-set hook."
fi

if [[ -f "$AUTOSTART" ]]; then
  # Drop the marker comment block and the launch_on_start line together.
  python3 - "$AUTOSTART" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
pattern = re.compile(
    r"\n?-- Desktop clock/weather overlay:.*?\no\.launch_on_start\(\"quickshell -n -p \" \.\. os\.getenv\(\"HOME\"\) \.\. \"/\.config/omarchy/desktop-overlay\"\)\n?",
    re.DOTALL,
)
new_text = pattern.sub("\n", text)
if new_text != text:
    open(path, "w").write(new_text)
    print("Removed autostart entry.")
else:
    print("No autostart entry found (already removed?).")
PY
fi

if [[ -f "$BINDINGS" ]]; then
  # Drop the card-toggle keybind's marker comment and o.bind(...) line together.
  python3 - "$BINDINGS" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
pattern = re.compile(
    r'\n?-- Show/hide the desktop clock overlay\'s card background.*?\no\.bind\("SUPER \+ SHIFT \+ V", "Toggle desktop overlay card",.*?\)\n?',
    re.DOTALL,
)
new_text = pattern.sub("\n", text)
if new_text != text:
    open(path, "w").write(new_text)
    print("Removed card toggle keybind.")
else:
    print("No card toggle keybind found (already removed?).")
PY

  # Drop the color picker's marker comment and o.bind(...) line together.
  python3 - "$BINDINGS" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
pattern = re.compile(
    r'\n?-- Open a GTK color picker for the desktop clock overlay.*?\no\.bind\("SUPER \+ (SHIFT|ALT) \+ C", "Open desktop overlay color picker",.*?\)\n?',
    re.DOTALL,
)
new_text = pattern.sub("\n", text)
if new_text != text:
    open(path, "w").write(new_text)
    print("Removed color picker keybind.")
else:
    print("No color picker keybind found (already removed?).")
PY
  command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true
fi

if [[ -f "$WINDOWS_LUA" ]]; then
  # Drop the color picker's marker comment and o.window(...) block together.
  # Leaves `require("hypr.windows")` in hyprland.lua alone, same as bindings
  # entries leave `require("hypr.bindings")` alone -- it's harmless to keep
  # requiring a file with nothing else in it, and it may not be empty if you
  # added your own rules to it since installing.
  python3 - "$WINDOWS_LUA" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
pattern = re.compile(
    r'\n?-- Float the desktop overlay color picker.*?\no\.window\("\^omarchy-color-picker\$", \{.*?\}\)\n?',
    re.DOTALL,
)
new_text = pattern.sub("\n", text)
if new_text != text:
    open(path, "w").write(new_text)
    print("Removed color picker window rule.")
else:
    print("No color picker window rule found (already removed?).")
PY
  command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true
fi

if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "$DEST_DIR"
  echo "Removed $DEST_DIR (config.json included)."
else
  echo "Left $DEST_DIR in place (your config.json). Re-run with --purge to delete it too."
fi
