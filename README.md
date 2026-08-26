# Omarchy Desktop Overlay

A fancy clock + weather widget for [Omarchy](https://omarchy.org/) that sits
on your desktop -- drawn above the wallpaper, below every normal window --
and never intercepts the mouse.

## What it is

This is **not** an Omarchy shell plugin (those are bar widgets/panels
registered through the shell's plugin registry, meant for on-demand popups).
This is its own tiny, independent [Quickshell](https://quickshell.org/)
instance -- a `PanelWindow` on the wlr `bottom` layer with an empty input
mask, so it's fully click-through. It runs alongside Omarchy's own shell
(the bar) without touching it.

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
  the moment you run `omarchy theme set`.
- **System vitals** (optional, off by default) -- CPU%, RAM%, and the
  hottest thermal zone (preferring the CPU package sensor when present),
  read straight from `/proc` and `/sys` -- no `lm_sensors` or other extra
  packages needed. Toggle it on/off live with `Super+Shift+V`, or start it
  enabled by setting `"showVitals": true` in `config.json`.

## Requirements

- Omarchy (needs `quickshell`, `omarchy-weather-status`, and
  `omarchy-weather-icon` on `PATH`)
- A [Nerd Font](https://www.nerdfonts.com/) installed, for the weather icon
  glyph to render (Omarchy ships `JetBrainsMono Nerd Font` by default)

## Install

```bash
git clone https://github.com/ReapXIII/omarchy-desktop-overlay
cd omarchy-desktop-overlay
./install.sh
```

This copies `desktop-overlay/` into `~/.config/omarchy/desktop-overlay/`,
adds a launch line to `~/.config/hypr/autostart.lua` (so it starts every
login), and starts it immediately for your current session. Re-running it is
safe -- it won't overwrite a `config.json` you've already customized, and
won't duplicate the autostart line.

## Configure

Edit `~/.config/omarchy/desktop-overlay/config.json` -- changes hot-reload
within about a second, no restart needed.

| Key | Meaning |
|---|---|
| `position` | `center`, `top-left`, `top-right`, `bottom-left`, `bottom-right`, `top-center`, `bottom-center` |
| `margin` | Distance from the screen edge in px (ignored when centered) |
| `fontFamily` | Any installed font; needs to be a Nerd Font for the weather glyph |
| `timeSize` / `dateSize` | Font size of the clock / date line |
| `weatherIconSize` / `weatherTempSize` / `weatherDetailSize` | Weather row font sizes |
| `showVitals` | Whether the CPU/RAM/temp row starts visible (default `false`) |
| `vitalsSize` | Font size of the vitals row |
| `showCard` | Whether the rounded background card is drawn (default `false`, text floats directly on the desktop); set `true` for the card/border/shadow container |

It currently targets your primary monitor only.

## Toggle vitals

`install.sh` wires up `Super+Shift+V` in `~/.config/hypr/bindings.lua` to flip
the vitals row on/off live, without touching `config.json`. It's the same
mechanism the overlay's own IPC target uses, so you can also drive it by
hand or from your own bindings:

```bash
qs ipc -n -p ~/.config/omarchy/desktop-overlay call -- overlay toggleVitals
```

## Uninstall

```bash
./uninstall.sh          # stops it, removes the autostart entry and the vitals keybind, keeps config.json
./uninstall.sh --purge  # also deletes ~/.config/omarchy/desktop-overlay
```
