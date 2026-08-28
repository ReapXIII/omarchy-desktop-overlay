#!/usr/bin/env python3
"""Small GTK window for tuning the desktop overlay's colors, bound to
Super+Alt+C by install.sh. Writes straight into config.json's "colors"
block; the overlay's own FileView already watches that file and hot-reloads,
so a pick here shows up on the desktop within about a second.

Also doubles as the trigger for repositioning: while this window is open,
the overlay card becomes draggable (see startPositioning()/stopPositioning()
in shell.qml) -- this is already the live-preview companion window next to
the overlay, so it's the natural place to also grab and move it, and it
frees up a keybind that (on at least one setup) was already bound to
something else.

Swatches start from whatever's actually on screen right now: an existing
config.json override if one is set, otherwise the live theme value computed
the same way shell.qml's applyTheme() does. That logic has to be kept in
sync with shell.qml by hand -- there's no shared source between QML and
Python here.
"""
import fcntl
import json
import os
import re
import subprocess
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk

# Sets the Wayland app_id (and X11 WM_CLASS) GTK advertises for every window
# this process opens. install.sh's Hyprland window rule (~/.config/hypr/
# windows.lua) matches on this exact id to float the picker off to the side
# of the screen instead of tiling it -- keep the two in sync if this changes.
APP_ID = "omarchy-color-picker"
GLib.set_prgname(APP_ID)

HOME = os.path.expanduser("~")
OVERLAY_DIR = f"{HOME}/.config/omarchy/desktop-overlay"
COLORS_TOML = f"{HOME}/.local/state/omarchy/current/theme/colors.toml"
CONFIG_JSON = f"{OVERLAY_DIR}/config.json"


def call_overlay_ipc(method):
    """Best-effort: the overlay may not be running, and a missed call just
    means positioning mode doesn't start/stop -- not worth failing over."""
    try:
        subprocess.run(
            ["qs", "ipc", "-n", "-p", OVERLAY_DIR, "call", "--", "overlay", method],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )
    except Exception:
        pass

# Single-instance guard. This used to be a `pgrep -f color-picker.py` in the
# keybind command itself, but that command line contains the string
# "color-picker.py" too, so pgrep matched its own wrapping shell and the
# picker could never launch. A flock on our own PID avoids that self-match
# entirely and also stops a second window opening if the key is pressed
# twice in a row.
LOCK_PATH = f"{HOME}/.cache/omarchy-desktop-overlay-color-picker.lock"


def acquire_single_instance_lock():
    os.makedirs(os.path.dirname(LOCK_PATH), exist_ok=True)
    lock_file = open(LOCK_PATH, "w")
    try:
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        sys.exit(0)
    return lock_file  # kept open (and thus locked) for the process lifetime

# (config key, label) -- fallbacks when colors.toml is missing/unreadable
# live in theme_defaults() below, alongside the derived-color logic they need.
COLOR_FIELDS = [
    ("accent", "Accent"),
    ("background", "Card background"),
    ("foreground", "Text"),
    ("mutedForeground", "Muted text"),
    ("textHalo", "Text halo"),
    ("border", "Card border"),
    ("divider", "Divider line"),
]

# (config key, label, min, max, digits, unit)
SCALE_FIELDS = [
    ("cardOpacity", "Card opacity", 0, 1, 2, ""),
    ("shadowBlur", "Text shadow blur", 0, 1, 2, ""),
    ("shadowOffset", "Text shadow offset", 0, 20, 0, "px"),
]


def parse_toml(text):
    out = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        out[key.strip()] = value.strip().strip('"')
    return out


def hex_with_alpha(hex_color, alpha):
    rgba = Gdk.RGBA()
    rgba.parse(hex_color)
    r, g, b = (round(getattr(rgba, c) * 255) for c in ("red", "green", "blue"))
    a = round(alpha * 255)
    return f"#{r:02x}{g:02x}{b:02x}{a:02x}"


def theme_defaults():
    """Mirrors shell.qml's applyTheme()/effective-color logic."""
    try:
        with open(COLORS_TOML) as f:
            parsed = parse_toml(f.read())
    except OSError:
        parsed = {}

    light = parsed.get("mode") == "light"
    background = parsed.get("dark_background") or "#1e1e2e"
    accent = parsed.get("accent") or "#89b4fa"
    foreground = parsed.get("foreground") or "#cdd6f4"
    defaults = {
        "accent": accent,
        "background": background,
        "foreground": foreground,
        "mutedForeground": parsed.get("dark_foreground") or "#9aa1b7",
        "textHalo": "#ffffff" if light else "#000000",
        "border": hex_with_alpha(accent, 0.35),
        "divider": hex_with_alpha(foreground, 0.14),
        "cardOpacity": 0.78 if light else 0.5,
        "shadowBlur": 0.25 if light else 0.4,
        "shadowOffset": 0 if light else 2,
    }
    if light:
        defaults["background"] = (
            parsed.get("darker_background") or parsed.get("dark_background") or background
        )
    return defaults


def load_config():
    try:
        with open(CONFIG_JSON) as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return {}


def save_config(cfg):
    tmp = CONFIG_JSON + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
    os.replace(tmp, CONFIG_JSON)


HEX_RE = re.compile(r"^#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")


def rgba_to_hex(rgba):
    r, g, b, a = (round(c * 255) for c in (rgba.red, rgba.green, rgba.blue, rgba.alpha))
    return f"#{r:02x}{g:02x}{b:02x}" if a == 255 else f"#{r:02x}{g:02x}{b:02x}{a:02x}"


class ColorPickerWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Desktop Overlay Colors")
        self.set_type_hint(Gdk.WindowTypeHint.DIALOG)
        self.set_resizable(False)
        self.set_border_width(16)
        self.set_default_size(340, -1)

        self.theme = theme_defaults()
        self.config = load_config()
        self.colors = dict(self.config.get("colors") or {})
        self.buttons = {}
        self.scales = {}
        self.resets = {}

        grid = Gtk.Grid(column_spacing=12, row_spacing=10)
        self.add(grid)

        row = 0
        for key, label in COLOR_FIELDS:
            grid.attach(Gtk.Label(label=label, xalign=0), 0, row, 1, 1)

            button = Gtk.ColorButton()
            button.set_use_alpha(True)
            button.set_rgba(self._current_rgba(key))
            button.connect("color-set", self._on_color_set, key)
            grid.attach(button, 1, row, 1, 1)
            self.buttons[key] = button

            self._attach_reset(grid, row, key)
            row += 1

        for key, label, lo, hi, digits, unit in SCALE_FIELDS:
            grid.attach(Gtk.Label(label=label, xalign=0), 0, row, 1, 1)

            step = 1 if digits == 0 else 10 ** -digits
            scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, lo, hi, step)
            scale.set_value(self.colors.get(key, self.theme[key]))
            scale.set_hexpand(True)
            scale.set_digits(digits)
            scale.connect("value-changed", self._on_scale_changed, key, digits)
            grid.attach(scale, 1, row, 1, 1)
            self.scales[key] = scale

            self._attach_reset(grid, row, key)
            row += 1

        reset_all = Gtk.Button(label="Reset all to theme")
        reset_all.connect("clicked", self._on_reset_all)
        grid.attach(reset_all, 0, row, 3, 1)

        # While this window is open, the overlay card is draggable too --
        # see call_overlay_ipc() above and startPositioning()/
        # stopPositioning() in shell.qml.
        self.connect("show", self._on_show)
        self.connect("destroy", self._on_destroy)

    def _on_show(self, _window):
        call_overlay_ipc("startPositioning")

    def _on_destroy(self, _window):
        call_overlay_ipc("stopPositioning")
        Gtk.main_quit()

    def _attach_reset(self, grid, row, key):
        reset = Gtk.Button(label="Reset")
        reset.set_sensitive(key in self.colors)
        reset.connect("clicked", self._on_reset, key)
        grid.attach(reset, 2, row, 1, 1)
        self.resets[key] = reset

    def _current_rgba(self, key):
        hex_value = self.colors.get(key) or self.theme.get(key)
        rgba = Gdk.RGBA()
        rgba.parse(hex_value)
        return rgba

    def _persist(self):
        # Re-read from disk rather than reusing the config loaded at startup:
        # the overlay itself writes showCard back to this same file when you
        # toggle the card (Super+Shift+V), and position/customX/customY when
        # you drag it (this same window, while it's open -- see
        # call_overlay_ipc() and _on_show()/_on_destroy() above), and a stale
        # in-memory copy here would silently revert those on the next color
        # pick.
        cfg = load_config()
        if self.colors:
            cfg["colors"] = self.colors
        else:
            cfg.pop("colors", None)
        save_config(cfg)
        self.config = cfg

    def _on_color_set(self, button, key):
        hex_value = rgba_to_hex(button.get_rgba())
        if not HEX_RE.match(hex_value):
            return
        self.colors[key] = hex_value
        self.resets[key].set_sensitive(True)
        self._persist()

    def _on_scale_changed(self, scale, key, digits):
        value = round(scale.get_value(), digits) if digits else int(scale.get_value())
        self.colors[key] = value
        self.resets[key].set_sensitive(True)
        self._persist()

    def _on_reset(self, _button, key):
        self.colors.pop(key, None)
        self.resets[key].set_sensitive(False)
        if key in self.scales:
            self.scales[key].set_value(self.theme[key])
        else:
            self.buttons[key].set_rgba(self._current_rgba(key))
        self._persist()

    def _on_reset_all(self, _button):
        self.colors = {}
        for key, _label in COLOR_FIELDS:
            self.buttons[key].set_rgba(self._current_rgba(key))
            self.resets[key].set_sensitive(False)
        for key, _label, _lo, _hi, _digits, _unit in SCALE_FIELDS:
            self.scales[key].set_value(self.theme[key])
            self.resets[key].set_sensitive(False)
        self._persist()


if __name__ == "__main__":
    _lock = acquire_single_instance_lock()
    win = ColorPickerWindow()
    win.show_all()
    Gtk.main()
