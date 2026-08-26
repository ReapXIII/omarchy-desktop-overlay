#!/bin/bash
# Removes the desktop clock/weather overlay: stops the running instance,
# strips its autostart entry, and (with --purge) deletes its config too.
set -euo pipefail

DEST_DIR="$HOME/.config/omarchy/desktop-overlay"
AUTOSTART="$HOME/.config/hypr/autostart.lua"
BINDINGS="$HOME/.config/hypr/bindings.lua"

pkill -f "quickshell -n -p $DEST_DIR" 2>/dev/null && echo "Stopped running overlay." || true

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
  # Drop the marker comment and the o.bind(...) line together.
  python3 - "$BINDINGS" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
pattern = re.compile(
    r'\n?-- Toggle CPU/RAM/temp on the desktop clock overlay.*?\no\.bind\("SUPER \+ SHIFT \+ V", "Toggle desktop vitals",.*?\)\n?',
    re.DOTALL,
)
new_text = pattern.sub("\n", text)
if new_text != text:
    open(path, "w").write(new_text)
    print("Removed vitals toggle keybind.")
else:
    print("No vitals toggle keybind found (already removed?).")
PY
  command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true
fi

if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "$DEST_DIR"
  echo "Removed $DEST_DIR (config.json included)."
else
  echo "Left $DEST_DIR in place (your config.json). Re-run with --purge to delete it too."
fi
