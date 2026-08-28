#!/bin/bash
# Installs the desktop clock/weather overlay for Omarchy.
#
# Copies desktop-overlay/ into ~/.config/omarchy/desktop-overlay/, wires it
# into ~/.config/hypr/autostart.lua so it launches every login, and starts it
# for the current session. Safe to re-run: it won't clobber a config.json
# you've already customized, and it won't add duplicate autostart or
# keybind lines.
#
# Looking for the CPU/RAM/temp taskbar widget that used to live here? It's
# now its own Omarchy shell plugin, in its own repo:
# https://github.com/ReapXIII/omarchy-bar-stats
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$ROOT_DIR/desktop-overlay"
DEST_DIR="$HOME/.config/omarchy/desktop-overlay"
AUTOSTART="$HOME/.config/hypr/autostart.lua"
AUTOSTART_LINE='o.launch_on_start("quickshell -n -p " .. os.getenv("HOME") .. "/.config/omarchy/desktop-overlay")'
AUTOSTART_MARKER="omarchy/desktop-overlay"
BINDINGS="$HOME/.config/hypr/bindings.lua"
CARD_KEYBIND_MARKER="Toggle desktop overlay card"
CARD_KEYBIND_LINE='o.bind("SUPER + SHIFT + V", "Toggle desktop overlay card", "qs ipc -n -p $HOME/.config/omarchy/desktop-overlay call -- overlay toggleCard")'
COLOR_PICKER_MARKER="Open desktop overlay color picker"
COLOR_PICKER_LINE='o.bind("SUPER + ALT + C", "Open desktop overlay color picker", "python3 $HOME/.config/omarchy/desktop-overlay/color-picker.py")'
THEME_HOOK_DIR="$HOME/.config/omarchy/hooks/theme-set.d"
THEME_HOOK_DEST="$THEME_HOOK_DIR/desktop-overlay.sh"
HYPRLAND_LUA="$HOME/.config/hypr/hyprland.lua"
WINDOWS_LUA="$HOME/.config/hypr/windows.lua"
WINDOW_RULE_MARKER="omarchy-color-picker"

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
cp "$SRC_DIR/color-picker.py" "$DEST_DIR/color-picker.py"
chmod +x "$DEST_DIR/color-picker.py"

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

# Migrate off older bindings this repo used to install:
# - Super+Shift+V used to toggle vitals (CPU/RAM/temp moved out to its own
#   Omarchy bar plugin -- see https://github.com/ReapXIII/omarchy-bar-stats),
#   so the overlay's IPC target lost toggleVitals() in favor of a plain
#   toggleCard().
# - Super+Shift+M used to toggle positioning mode. It turned out to already
#   be bound to something else (Spotify) on at least one setup, and
#   positioning mode is tied to the color picker's open/closed state now
#   instead (see color-picker.py and startPositioning()/stopPositioning()
#   in shell.qml) -- so this binding is just removed, not replaced.
# Drop the old blocks so the marker check below re-adds the renamed one
# fresh, with nothing left over for the removed one.
if [[ -f "$BINDINGS" ]]; then
  python3 - "$BINDINGS" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
patterns = [
    re.compile(
        r'\n?-- Toggle CPU/RAM/temp on the desktop clock overlay.*?\no\.bind\("SUPER \+ SHIFT \+ V", "Toggle desktop vitals",.*?\)\n?',
        re.DOTALL),
    re.compile(
        r'\n?-- Drag the desktop clock overlay to a new spot.*?\no\.bind\("SUPER \+ SHIFT \+ M", "Reposition desktop overlay",.*?\)\n?',
        re.DOTALL),
]
new_text = text
for pattern in patterns:
    new_text = pattern.sub("\n", new_text)
if new_text != text:
    open(path, "w").write(new_text)
    print("Removed a retired desktop-overlay keybind.")
PY
fi

if [[ -f "$BINDINGS" ]]; then
  if grep -qF "$CARD_KEYBIND_MARKER" "$BINDINGS"; then
    echo "Card toggle keybind already wired up in $BINDINGS -- leaving it alone."
  else
    {
      echo ""
      echo "-- Show/hide the desktop clock overlay's card background (omarchy-desktop-overlay)."
      echo "$CARD_KEYBIND_LINE"
    } >> "$BINDINGS"
    echo "Added Super+Shift+V keybind to $BINDINGS (toggles the card)."
    command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true
  fi
else
  echo "Warning: $BINDINGS not found -- add this keybind yourself:" >&2
  echo "  $CARD_KEYBIND_LINE" >&2
fi

# Migrate off any older version of this binding -- the original Super+Shift+C
# (conflicted with an existing app keybind for some users) and/or the
# `pgrep -f desktop-overlay/color-picker.py || ...` guard (which always
# self-matched its own wrapping shell's command line and so never actually
# launched the picker) -- so the marker check below re-adds it fresh.
if [[ -f "$BINDINGS" ]] && grep -qF 'Open desktop overlay color picker' "$BINDINGS" \
   && ! grep -qF "$COLOR_PICKER_LINE" "$BINDINGS"; then
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
PY
fi

if ! python3 -c "import gi; gi.require_version('Gtk', '3.0'); from gi.repository import Gtk" >/dev/null 2>&1; then
  echo "Warning: python-gobject/GTK3 not found -- skipping the Super+Alt+C color picker keybind." >&2
  echo "  Install them (e.g. 'sudo pacman -S python-gobject gtk3') and re-run install.sh to add it." >&2
elif [[ -f "$BINDINGS" ]]; then
  if grep -qF "$COLOR_PICKER_MARKER" "$BINDINGS"; then
    echo "Color picker keybind already wired up in $BINDINGS -- leaving it alone."
  else
    {
      echo ""
      echo "-- Open a GTK color picker for the desktop clock overlay's theme overrides"
      echo "-- (omarchy-desktop-overlay); writes straight to its config.json."
      echo "$COLOR_PICKER_LINE"
    } >> "$BINDINGS"
    echo "Added Super+Alt+C keybind to $BINDINGS (opens the color picker)."
    command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true
  fi
else
  echo "Warning: $BINDINGS not found -- add this keybind yourself to open the color picker:" >&2
  echo "  $COLOR_PICKER_LINE" >&2
fi

# Float the color picker off to the right side of the screen (rather than
# tiling it) so the real, live overlay stays visible behind it while you
# pick -- that's the actual "live preview". Matches Omarchy's own pattern
# for small floating utility windows (see default/hypr/apps/pip.lua).
if python3 -c "import gi; gi.require_version('Gtk', '3.0'); from gi.repository import Gtk" >/dev/null 2>&1; then
  mkdir -p "$(dirname "$WINDOWS_LUA")"
  if [[ -f "$WINDOWS_LUA" ]] && grep -qF "$WINDOW_RULE_MARKER" "$WINDOWS_LUA"; then
    echo "Color picker window rule already wired up in $WINDOWS_LUA -- leaving it alone."
  else
    {
      [[ -s "$WINDOWS_LUA" ]] && echo ""
      echo "-- Float the desktop overlay color picker off to the right side of the"
      echo "-- screen instead of tiling it, so the live overlay stays visible while"
      echo "-- you pick colors (omarchy-desktop-overlay)."
      echo 'o.window("^omarchy-color-picker$", {'
      echo '  float = true,'
      echo '  move = { "(monitor_w-window_w-40)", "(monitor_h-window_h)/2" },'
      echo '})'
    } >> "$WINDOWS_LUA"
    echo "Added a window rule to $WINDOWS_LUA (floats the color picker on the right side of the screen)."
  fi

  if [[ -f "$HYPRLAND_LUA" ]] && ! grep -qF 'require("hypr.windows")' "$HYPRLAND_LUA"; then
    python3 - "$HYPRLAND_LUA" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
anchor = 'require("hypr.autostart")'
if anchor in text:
    text = text.replace(anchor, anchor + '\nrequire("hypr.windows")', 1)
    open(path, "w").write(text)
PY
    if grep -qF 'require("hypr.windows")' "$HYPRLAND_LUA"; then
      echo "Wired $WINDOWS_LUA into $HYPRLAND_LUA."
    else
      echo "Warning: couldn't find where to load $WINDOWS_LUA from $HYPRLAND_LUA automatically." >&2
      echo "  Add this line yourself, near your other require(\"hypr...\") lines:" >&2
      echo '  require("hypr.windows")' >&2
    fi
  fi
  command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true
fi

mkdir -p "$THEME_HOOK_DIR"
cp "$ROOT_DIR/hooks/theme-set.sh" "$THEME_HOOK_DEST"
chmod +x "$THEME_HOOK_DEST"
echo "Installed theme-set hook to $THEME_HOOK_DEST (keeps overlay colors in sync with \`omarchy theme set\`)."

if pgrep -f "quickshell -n -p $DEST_DIR" >/dev/null 2>&1; then
  echo "Already running."
else
  setsid quickshell -n -p "$DEST_DIR" >/dev/null 2>&1 < /dev/null &
  disown
  echo "Started for this session."
fi

echo "Done. Edit $DEST_DIR/config.json to change position, size, or font -- it hot-reloads on save."
echo "Super+Alt+C opens a color picker for the theme overrides (needs python-gobject + gtk3) --"
echo "  while it's open you can also drag the card to move it; letting go remembers the spot."
echo "Want CPU/RAM/temp in the taskbar too? That's a separate plugin now:"
echo "  omarchy plugin add https://github.com/ReapXIII/omarchy-bar-stats --enable"
