#!/bin/bash
# Installed by install.sh into ~/.config/omarchy/hooks/theme-set.d/.
#
# `omarchy theme set` replaces the whole current-theme directory (rm -rf +
# mv) instead of editing colors.toml in place, so the overlay's inotify
# watch on that file is left pointing at a deleted inode and never fires.
# This hook runs after the swap completes and nudges the overlay to
# re-read colors.toml via its "overlay" IPC target.
qs ipc -n -p "$HOME/.config/omarchy/desktop-overlay" call -- overlay reloadTheme >/dev/null 2>&1 || true
