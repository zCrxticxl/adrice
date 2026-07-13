# adrice — AD HyperRice

**Deep desktop customization TUI for Linux. Single file, zero dependencies, live previews, one-key fixes.**

Rice your entire desktop from one terminal UI: generate a full theme from any wallpaper, live-preview GTK/icon/cursor themes while you scroll, sync colors into every terminal and app, switch looks automatically at sunset — with undo for everything.

```
 █████╗ ██████╗ ██████╗ ██╗ ██████╗███████╗
██╔══██╗██╔══██╗██╔══██╗██║██╔════╝██╔════╝
███████║██║  ██║██████╔╝██║██║     █████╗
██╔══██║██║  ██║██╔══██╗██║██║     ██╔══╝
██║  ██║██████╔╝██║  ██║██║╚██████╗███████╗
╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚═╝ ╚═════╝╚══════╝
```

## Highlights

### ★ Wallpaper magic
Pick any image — adrice extracts its dominant colors (ImageMagick) and generates a complete, coherent theme from it: a full 16-color terminal scheme (hue-matched to the ANSI slots, readability-corrected), a matching GNOME accent color, dark mode, and the Hyprland border color. Preview as a rendered terminal mockup before applying. Also headless: `./adrice.sh magic wallpaper.jpg`.

### Live preview everywhere
The highlighted theme, icon set, cursor, font or wallpaper is applied to your desktop **instantly while you scroll**. `⏎` keeps it, `esc` reverts to exactly what you had. Wallpapers render inline in the terminal (via `chafa`), GTK themes show their real `gtk.css` colors, terminal schemes render as a live mockup.

### Doctor with one-key fixes
`adrice doctor` diagnoses why theming isn't working — missing tools, no nerd font, missing User Themes extension, flatpak apps ignoring your themes, libadwaita quirks. In the TUI, **every ⚠ line is selectable and `⏎` runs the fix**: installs the package via your package manager, downloads the font, installs the extension, sets the flatpak overrides.

### Everything else

- **Rice presets** — Catppuccin, Nordic, Gruvbox, Tokyonight as complete one-shot looks (GTK + icons + cursor + terminal + accent), missing packs auto-downloaded. Plus a **random rice** roll from whatever you have installed.
- **Terminal schemes** — Catppuccin Mocha, Gruvbox, Nord, Tokyo Night, Dracula (+ your generated ones), written to **all installed terminals at once**: alacritty, kitty, foot, gnome-terminal, konsole.
- **App sync** — push the active scheme into btop, cava, VS Code's integrated terminal and Spicetify in one step.
- **Flatpak theme sync** — one fix for the classic "my theme doesn't apply to flatpak apps" problem (overrides + `GTK_THEME`).
- **Auto day / night** — pick a light and a dark profile plus times; adrice generates systemd user timers that switch automatically.
- **Get themes & fonts** — curated downloads straight from GitHub: Nordic, Orchis, Catppuccin/Tokyonight/Gruvbox GTK, Papirus, Tela, Bibata, Phinger, Capitaine, and Nerd Fonts (JetBrainsMono, FiraCode, Hack, CaskaydiaCove, Meslo).
- **GNOME Extensions** — toggle installed ones, or one-click-install curated essentials (User Themes, Blur my Shell, Dash to Dock, Caffeine, GSConnect …) with plain-language descriptions of what each does.
- **Undo everything** — every change is logged; `u` anywhere undoes the last one, the history menu rolls back to any point. Your pre-adrice state is auto-saved as `_original` on first run.
- **Profiles + sharing** — snapshot full looks, export as a tar including theme folders and wallpaper, import on another machine — **directly from a URL**: `./adrice.sh import https://…/adrice-mycoolrice.tar.gz`.
- **Behavior tweaks** — GNOME toggles (animations, hot corner, night light …), KDE equivalents, deep Hyprland config (gaps, rounding, blur, borders) applied live *and* persisted.
- Starship & fastfetch presets, type-to-filter (`/`) in every menu, truecolor UI throughout.

## Supported environments

GNOME · KDE Plasma · Hyprland · XFCE — auto-detected, menus and backends adapt. Anything else falls back to config-file writes where possible.

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

Requirements: `bash` ≥ 4 and a truecolor terminal. Everything else is optional and the built-in doctor installs it for you: `imagemagick` (wallpaper magic), `chafa` (inline image previews), `git`/`curl`/`unzip` (downloads), `fc-list` (font pickers).

## CLI

```
./adrice.sh               interactive TUI
./adrice.sh magic IMAGE   generate + apply a full theme from any image
./adrice.sh doctor        diagnose theming problems
./adrice.sh list          list saved profiles
./adrice.sh save NAME     snapshot current look as profile
./adrice.sh apply NAME    apply profile non-interactively
./adrice.sh undo          undo last change
./adrice.sh export NAME   pack profile + themes + wallpaper as tar
./adrice.sh import X      import such a tar — local file or URL
```

`apply` and `magic` are scriptable — bind them to shortcuts, cron, or let the built-in day/night timers do it.

## Keybinds

| Key | Action |
|-----|--------|
| `↑↓` / `jk` | move |
| `⏎` | select / keep previewed / run fix |
| `esc` | back / revert live preview / clear filter |
| `/` | type-to-filter any list |
| `u` | undo last change |
| `q` | quit |

## Reset

Your pre-adrice state is saved automatically on first run:

```bash
./adrice.sh apply _original
```

## License

MIT — see [LICENSE](LICENSE).
