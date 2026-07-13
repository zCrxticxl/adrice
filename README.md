# adrice — AD HyperRice

**Deep desktop customization TUI for Linux. Single file, zero dependencies, live previews.**

Rice your entire desktop from one terminal UI: GTK/icon/cursor themes, wallpaper, fonts, terminal color schemes, GNOME extensions, full one-shot rice presets — with everything applied **live while you browse** and instant undo.

```
 █████╗ ██████╗ ██████╗ ██╗ ██████╗███████╗
██╔══██╗██╔══██╗██╔══██╗██║██╔════╝██╔════╝
███████║██║  ██║██████╔╝██║██║     █████╗
██╔══██║██║  ██║██╔══██╗██║██║     ██╔══╝
██║  ██║██████╔╝██║  ██║██║╚██████╗███████╗
╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚═╝ ╚═════╝╚══════╝
```

## Features

- **Live preview everywhere** — the highlighted theme/icon/cursor/wallpaper/font is applied to your desktop instantly while you scroll. `⏎` keeps it, `esc` reverts to what you had.
- **Appearance** — GTK theme, icon theme, cursor, dark/light, accent color (GNOME 47+), interface & monospace fonts (from `fc-list`), wallpaper browser with inline image preview (via `chafa`).
- **Terminal color schemes** — Catppuccin Mocha, Gruvbox, Nord, Tokyo Night, Dracula. Written to **all installed terminals at once** (alacritty, kitty, foot, gnome-terminal, konsole), with a rendered terminal mockup as exact preview.
- **Get themes** — curated packs (Nordic, Orchis, Catppuccin/Tokyonight/Gruvbox GTK, Papirus, Tela, Bibata, Phinger, Capitaine) downloaded straight from GitHub into `~/.themes` / `~/.icons`.
- **Rice presets** — one keystroke applies a complete coherent look: GTK + icons + cursor + terminal scheme + dark mode + accent. Missing packs are downloaded automatically.
- **GNOME Extensions** — toggle installed extensions, plus one-click install of curated extensions (Blur my Shell, Dash to Dock, User Themes, Caffeine, GSConnect …) via the shell's own installer or the extensions.gnome.org API — each with a description of what it does.
- **Undo everything** — every change is logged. Press `u` anywhere to undo the last change, or roll back to any point in the history menu. An `_original` profile of your starting state is saved automatically on first run.
- **Profiles** — snapshot your full look, apply it later, and **export it as a tar** (including theme folders + wallpaper) to import on another machine.
- **Behavior tweaks** — GNOME toggles (animations, hot corner, night light, tap-to-click, …), KDE equivalents, and deep Hyprland config (gaps, rounding, blur, borders) applied at runtime *and* persisted.
- **Starship & fastfetch presets**, type-to-filter (`/`) in every menu, truecolor UI.

## Supported environments

GNOME · KDE Plasma · Hyprland · XFCE — auto-detected, menus adapt to the backend. Anything else falls back to config-file writes where possible.

## Install

```bash
git clone https://github.com/zCrxticxl/adrice.git
cd adrice
chmod +x adrice.sh
./adrice.sh
```

Optional, run as `adrice` from anywhere:

```bash
cp adrice.sh ~/.local/bin/adrice
```

Requirements: `bash` ≥ 4, a truecolor terminal (any modern one). Optional: `git`/`curl` for downloads, `chafa` for inline wallpaper previews, `fc-list` for font pickers.

## CLI

```
./adrice.sh              interactive TUI
./adrice.sh list         list saved profiles
./adrice.sh save NAME    snapshot current look as profile
./adrice.sh apply NAME   apply profile non-interactively
./adrice.sh undo         undo last change
./adrice.sh export NAME  pack profile + themes + wallpaper as tar
./adrice.sh import FILE  import such a tar on another machine
```

`apply` is scriptable — bind profiles to keyboard shortcuts or cron (e.g. dark rice at night).

## Keybinds

| Key | Action |
|-----|--------|
| `↑↓` / `jk` | move |
| `⏎` | select / keep previewed |
| `esc` | back / revert live preview / clear filter |
| `/` | type-to-filter any list |
| `u` | undo last change |
| `q` | quit |

## Reset

Your pre-adrice state is saved automatically:

```bash
./adrice.sh apply _original
```

## License

MIT — see [LICENSE](LICENSE).
