# Omarchy Desktop Overlay

A fancy clock + weather widget for [Omarchy](https://omarchy.org/) that sits
on your desktop -- drawn above the wallpaper, below every normal window --
and never intercepts the mouse, except while you're actively dragging it to
a new spot.

Looking for the CPU/RAM/temp taskbar widget this repo used to also ship?
It's a real Omarchy shell plugin now, split into its own repo since it
installs a completely different way (`omarchy plugin add`, not this repo's
`install.sh`): **[omarchy-bar-stats](https://github.com/ReapXIII/omarchy-bar-stats)**.

## What it is

This is **not** an Omarchy shell plugin (those are bar widgets/panels
registered through the shell's plugin registry, meant for on-demand popups).
This is its own tiny, independent [Quickshell](https://quickshell.org/)
instance -- a `PanelWindow` on the wlr `bottom` layer, click-through except
while you're actively dragging it (see "Reposition by dragging" below), so
it runs alongside Omarchy's own shell (the bar) without touching it.

It pulls its data straight from the same places the bar does, so it never
disagrees with your taskbar:

- **Clock format** (12h/24h) -- read from `~/.config/omarchy/shell.json`,
  matching your bar's clock widget setting.
- **Weather** -- fetched with the same `omarchy-weather-status` /
  `omarchy-weather-icon` helpers the bar's weather pill uses (which read the
  location set via `omarchy-weather-location`), on the same refresh interval
  as the bar's weather widget.
- **Colors** -- read live from your active theme's
  `~/.local/state/omarchy/current/theme/colors.toml`, so it re-themes itself
  the moment you run `omarchy theme set`. `omarchy theme set` swaps in a whole
  new theme directory rather than editing that file in place, so `install.sh`
  also drops a hook into `~/.config/omarchy/hooks/theme-set.d/` that nudges
  the overlay to re-read it right after a theme switch -- the same problem
  Omarchy's own bar works around by pushing the new palette over IPC instead
  of relying on file watching alone. Light-mode themes (`mode = "light"` in
  `colors.toml`) get their own card shade and a light (instead of black) text
  halo, since dark-mode's choices wash out or blur against a bright theme.

## Requirements

- Omarchy (needs `quickshell`, `omarchy-weather-status`, and
  `omarchy-weather-icon` on `PATH`)
- A [Nerd Font](https://www.nerdfonts.com/) installed, for the weather icon
  glyph to render (Omarchy ships `JetBrainsMono Nerd Font` by default)
- `python-gobject` and `gtk3`, for the `Super+Alt+C` color picker (both
  ship by default on Omarchy). Everything else works fine without them --
  `install.sh` just skips that one keybind.

## Install

```bash
git clone https://github.com/ReapXIII/omarchy-desktop-overlay
cd omarchy-desktop-overlay
./install.sh
```

This copies `desktop-overlay/` into `~/.config/omarchy/desktop-overlay/`,
adds a launch line to `~/.config/hypr/autostart.lua` (so it starts every
login), and starts it immediately for your current session. Re-running it
is safe -- it won't overwrite a `config.json` you've already customized,
and won't duplicate the autostart line.

Want CPU/RAM/temp in the taskbar too? That's a separate install:

```bash
omarchy plugin add https://github.com/ReapXIII/omarchy-bar-stats --enable
```

See that repo's README for placing it next to a specific widget.

## Configure

Edit `~/.config/omarchy/desktop-overlay/config.json` -- changes hot-reload
within about a second, no restart needed.

| Key | Meaning |
|---|---|
| `position` | `center`, `top-left`, `top-right`, `bottom-left`, `bottom-right`, `top-center`, `bottom-center`, or `custom` |
| `customX` / `customY` | Card center as a fraction (`0`-`1`) of screen width/height; only used when `position` is `custom`. Normally set by dragging (see "Reposition by dragging" below) rather than by hand. |
| `margin` | Distance from the screen edge in px (ignored when `position` is `center` or `custom`) |
| `fontFamily` | Any installed font; needs to be a Nerd Font for the weather glyph |
| `timeSize` / `dateSize` | Font size of the clock / date line |
| `weatherIconSize` / `weatherTempSize` / `weatherDetailSize` | Weather row font sizes |
| `showCard` | Whether the rounded background card is drawn (default `true`); set `false` to have the text float directly on the desktop with no container |
| `colors` | Optional -- see "Custom colors" below. Omit it (the default) to follow your active theme exactly. |

It currently targets your primary monitor only.

### Custom colors

By default every color -- accent, card background, text -- comes straight
from your active Omarchy theme and updates live when you run `omarchy theme
set`. If you want to break from the theme, add a `colors` object to
`config.json`; any key you leave out (or the whole block, if you don't want
to override anything) keeps following the theme:

```json
{
  "colors": {
    "accent": "#ff79c6",
    "background": "#1e1e2e",
    "foreground": "#f8f8f2",
    "mutedForeground": "#6272a4",
    "textHalo": "#000000",
    "border": "#ff79c680",
    "divider": "#f8f8f224",
    "cardOpacity": 0.6,
    "shadowBlur": 0.4,
    "shadowOffset": 2
  }
}
```

| Key | Overrides |
|---|---|
| `accent` | Weather icon |
| `background` | The card's fill color |
| `foreground` | Clock and weather-temp text |
| `mutedForeground` | Date, weather location/wind, "unavailable" text |
| `textHalo` | The soft shadow/halo behind the text -- black on dark themes, white on light ones by default; set this if a custom `foreground` needs a different one for legibility |
| `border` | Card border tint (theme default: `accent` at 35% alpha) |
| `divider` | The line under the date (theme default: `foreground` at 14% alpha) |
| `cardOpacity` | Card background opacity, `0`-`1` (theme default `0.5` dark / `0.78` light) |
| `shadowBlur` | Text shadow/halo blur amount, `0`-`1` (theme default `0.4` dark / `0.25` light) |
| `shadowOffset` | Text shadow vertical offset in pixels, `0`-`20` (theme default `2` dark / `0` light) |

Colors are `#rgb`, `#rgba`, `#rrggbb`, or `#rrggbbaa` hex strings (`border`
and `divider` are usually worth giving an alpha channel, since they're tints
by default); anything else is ignored and falls back to the theme. This is
per-key, so you can pin just `accent` to your favorite hue and let everything
else keep tracking the theme.

### Color picker

`Super+Alt+C` opens a small GTK window (`color-picker.py`) with a
color-chooser button per key above plus sliders for card opacity and text
shadow blur/offset. Every pick writes straight into `config.json`'s `colors`
block, which the overlay hot-reloads within about a second, so you see it
change live. Each row has its own "Reset" back to the theme value, plus a
"Reset all" at the bottom. It's a normal floating window, not a dialog with
its own close button, so use Omarchy's usual `Super+W` to close it when
you're done.

`install.sh` also floats the picker to the right edge of the screen (via a
Hyprland window rule in `~/.config/hypr/windows.lua`, matched on its
`omarchy-color-picker` app id) instead of tiling it, so the real overlay
stays visible next to it as your live preview while you pick -- no separate
mock-up to keep in sync with the real rendering. While the picker is open
you can also drag the card itself to a new spot -- see "Reposition by
dragging" below.

Needs `python-gobject` and `gtk3` (both ship by default on Omarchy); if
they're missing, `install.sh` skips wiring the keybind and window rule and
tells you what to install -- re-run it once you have them.

## Toggle card

`install.sh` wires up `Super+Shift+V` in `~/.config/hypr/bindings.lua` to
show/hide the card background live. The state writes back into
`config.json`'s `showCard`, so it survives both a reboot and a config.json
rewrite from elsewhere (e.g. the color picker saving a pick). It's the same
mechanism the overlay's own IPC target uses, so you can also drive it by
hand or from your own bindings:

```bash
qs ipc -n -p ~/.config/omarchy/desktop-overlay call -- overlay toggleCard
```

## Reposition by dragging

Open the color picker (`Super+Alt+C`) -- while it's open, the card gets an
accent-colored outline and becomes draggable (the rest of the desktop stays
click-through as always -- only the card itself starts accepting clicks).
Drag it anywhere on screen; letting go writes `position: "custom"` plus
`customX`/`customY` (the card's center, as a fraction of screen
width/height) into `config.json` immediately, so it's remembered even if you
drag it again before closing the picker. Close the picker window
(`Super+W`) to lock the position in and return to fully click-through.

Positioning mode is tied to the picker's own open/closed state rather than
its own keybind -- the picker already sits next to the overlay as a live
preview while you pick colors, so it doubles as the place to move it too.
`color-picker.py` drives it via the same IPC mechanism as the card toggle:

```bash
qs ipc -n -p ~/.config/omarchy/desktop-overlay call -- overlay startPositioning
qs ipc -n -p ~/.config/omarchy/desktop-overlay call -- overlay stopPositioning
```

To go back to a named preset instead of a dragged position, just set
`position` back to one of the presets (e.g. `"center"`) in `config.json` --
`customX`/`customY` are simply ignored until `position` is `"custom"` again.

## Uninstall

```bash
./uninstall.sh          # stops it, removes autostart/keybinds, keeps config.json
./uninstall.sh --purge  # also deletes ~/.config/omarchy/desktop-overlay
```

This doesn't touch the taskbar plugin; remove that separately with
`omarchy plugin remove reapxiii.system-stats --yes`.
