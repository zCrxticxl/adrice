#!/usr/bin/env bash
# adrice — AD HyperRice · deep desktop customization TUI
# GNOME / KDE Plasma / Hyprland / XFCE / generic · single file, zero extra deps
#
#   ./adrice.sh              interactive TUI
#   ./adrice.sh list         list saved profiles
#   ./adrice.sh save NAME    snapshot current look as profile
#   ./adrice.sh apply NAME   apply profile non-interactively
#   ./adrice.sh undo         undo last change
#   ./adrice.sh export NAME  pack profile + themes + wallpaper as tar
#   ./adrice.sh import FILE   import such a tar (FILE may be a URL)
#   ./adrice.sh magic IMAGE   generate + apply a full theme from any image
#   ./adrice.sh doctor        diagnose why theming might not work
#   ./adrice.sh --help

VERSION="2.2.0"
SELF_PATH=$(realpath "$0" 2>/dev/null || echo "$0")
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/adrice"
PROFILE_DIR="$CONFIG_DIR/profiles"
STATE_FILE="$CONFIG_DIR/state"
mkdir -p "$PROFILE_DIR"

# ══════════════════════════ palette (truecolor) ══════════════════════════
ESC=$'\e'
RST="$ESC[0m"; BOLD="$ESC[1m"; E39="$ESC[39m"
fgc(){ printf '\e[38;2;%d;%d;%dm' "$((16#${1:0:2}))" "$((16#${1:2:2}))" "$((16#${1:4:2}))"; }

C_ACC=$(fgc 89b4fa)   # blue
C_MAU=$(fgc cba6f7)   # mauve
C_PNK=$(fgc f5c2e7)   # pink
C_TXT=$(fgc cdd6f4)   # text
C_BRD=$(fgc 45475a)   # border
C_SELBG=$'\e[48;2;49;50;68m'
OK=$(fgc a6e3a1); WARN=$(fgc f9e2af); ERR=$(fgc f38ba8); MUT=$(fgc 7f849c)

# ══════════════════════════ ui primitives ══════════════════════════
TUI_ACTIVE=0
tui_on(){ printf '%s' "$ESC[?1049h$ESC[?25l"; TUI_ACTIVE=1; }
tui_off(){ (( TUI_ACTIVE )) && printf '%s' "$ESC[?25h$ESC[?1049l"; TUI_ACTIVE=0; }
trap tui_off EXIT
cls(){ printf '%s' "$ESC[2J$ESC[H"; }
cols(){ tput cols 2>/dev/null || echo 80; }
rows(){ tput lines 2>/dev/null || echo 24; }

shopt -s extglob
rep(){ local s; (( $2 > 0 )) || return 0; printf -v s '%*s' "$2" ''; printf '%s' "${s// /$1}"; }
plain(){ printf '%s' "${1//$'\e['*([0-9;])m/}"; }
plainlen(){ local p; p=$(plain "$1"); printf '%s' "${#p}"; }
pad(){ # pad STR WIDTH  (ANSI-aware)
  local l; l=$(plainlen "$1")
  printf '%s' "$1"; (( l < $2 )) && printf '%*s' "$(( $2 - l ))" ''
}

grad(){ # grad HEX1 HEX2 TEXT → per-char gradient
  local s=$3 n=${#3} i r g b out=""
  local r1=$((16#${1:0:2})) g1=$((16#${1:2:2})) b1=$((16#${1:4:2}))
  local r2=$((16#${2:0:2})) g2=$((16#${2:2:2})) b2=$((16#${2:4:2}))
  local d=$(( n > 1 ? n - 1 : 1 ))
  for (( i = 0; i < n; i++ )); do
    r=$(( r1 + (r2 - r1) * i / d )); g=$(( g1 + (g2 - g1) * i / d )); b=$(( b1 + (b2 - b1) * i / d ))
    out+=$'\e[38;2;'"$r;$g;$b"$'m'"${s:i:1}"
  done
  printf '%s%s' "$out" "$RST"
}

LOGO_RAW=(
' █████╗ ██████╗ ██████╗ ██╗ ██████╗███████╗'
'██╔══██╗██╔══██╗██╔══██╗██║██╔════╝██╔════╝'
'███████║██║  ██║██████╔╝██║██║     █████╗  '
'██╔══██║██║  ██║██╔══██╗██║██║     ██╔══╝  '
'██║  ██║██████╔╝██║  ██║██║╚██████╗███████╗'
'╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚═╝ ╚═════╝╚══════╝'
)
LOGO_R=(); HDR_SMALL=""; TAGLINE=""
build_headers(){ # vertical gradient blue → pink
  local i n=${#LOGO_RAW[@]} r g b
  local r1=$((16#89)) g1=$((16#b4)) b1=$((16#fa))
  local r2=$((16#f5)) g2=$((16#c2)) b2=$((16#e7))
  for (( i = 0; i < n; i++ )); do
    r=$(( r1 + (r2 - r1) * i / (n - 1) )); g=$(( g1 + (g2 - g1) * i / (n - 1) )); b=$(( b1 + (b2 - b1) * i / (n - 1) ))
    LOGO_R+=("  "$'\e[38;2;'"$r;$g;$b"$'m'"${LOGO_RAW[i]}$RST")
  done
  TAGLINE="  $(grad 89b4fa f5c2e7 "AD HyperRice")${MUT} — deep desktop customization ${C_BRD}·${MUT} v$VERSION ${C_BRD}·${MUT} $DE_LABEL$RST"
  HDR_SMALL="  $(grad 89b4fa f5c2e7 "◢◤ adrice") ${MUT}v$VERSION ${C_BRD}·${MUT} $DE_LABEL$RST"
}

HDR_MODE=small HDR_H=3
header(){
  printf '\n'
  if [[ $HDR_MODE == big ]] && (( $(cols) >= 60 )); then
    printf '%s\n' "${LOGO_R[@]}"
    printf '%s\n\n' "$TAGLINE"
    HDR_H=$(( ${#LOGO_R[@]} + 3 ))
  else
    printf '%s\n\n' "$HDR_SMALL"
    HDR_H=3
  fi
}

W=60
setw(){ W=$(( $(cols) - 8 )); (( W > 62 )) && W=62; (( W < 36 )) && W=36; }
box_top(){ # box_top [TITLE]
  if [[ -n ${1:-} ]]; then
    local fill=$(( W - 3 - ${#1} ))
    printf '  %s╭─%s %s %s%s╮%s\n' "$C_BRD" "$RST$BOLD$C_TXT" "$1" "$RST$C_BRD" "$(rep '─' $fill)" "$RST"
  else
    printf '  %s╭%s╮%s\n' "$C_BRD" "$(rep '─' "$W")" "$RST"
  fi
}
box_row(){ printf '  %s│%s%s%s│%s\n' "$C_BRD" "$RST" "$(pad "${1:-}" "$W")" "$C_BRD" "$RST"; }
box_wrap(){ # box_row with word wrap for long lines
  local word out=""
  [[ -z ${1// /} ]] && { box_row; return; }
  for word in $1; do
    if [[ -n $out ]] && (( $(plainlen "$out $word") > W - 4 )); then
      box_row "  $out"; out="    $word"
    elif [[ -z $out ]]; then out=$word
    else out+=" $word"; fi
  done
  [[ -n $out ]] && box_row "  $out"
}
box_bot(){ printf '  %s╰%s╯%s\n' "$C_BRD" "$(rep '─' "$W")" "$RST"; }

chip(){ printf '%s %s %s' "$C_SELBG$C_TXT" "$1" "$RST"; }
footer(){
  printf '\n   %s %s%s%s %s %s%s%s %s %s%s%s %s %s%s%s %s %s%s%s %s %s%s%s\n' \
    "$(chip '↑↓')" "$MUT" "move" "$RST" \
    "$(chip '⏎')" "$MUT" "pick" "$RST" \
    "$(chip '/')" "$MUT" "filter" "$RST" \
    "$(chip 'u')" "$MUT" "undo" "$RST" \
    "$(chip 'esc')" "$MUT" "back" "$RST" \
    "$(chip 'q')" "$MUT" "quit" "$RST"
}

read_key(){
  local k rest
  IFS= read -rsn1 k < /dev/tty || { echo esc; return; }
  if [[ $k == "$ESC" ]]; then
    IFS= read -rsn2 -t 0.02 rest < /dev/tty || { echo esc; return; }
    case $rest in
      '[A') echo up ;; '[B') echo down ;;
      '[C') echo right ;; '[D') echo left ;;
      *) echo esc ;;
    esac
  else
    case $k in
      '') echo enter ;;
      q|Q) echo q ;;
      k) echo up ;; j) echo down ;;
      *) echo "$k" ;;
    esac
  fi
}

MENU_IDX=0
MENU_START=0
PV_FN=""   # optional: draws a preview pane under the menu, gets selected index
PV_CB=""   # optional: called on every selection change (live apply), gets index
PV_H=0     # extra lines the preview pane needs
# menu TITLE SUBTITLE OPTION...  → 0 + MENU_IDX, 1 on esc
# NOTE: option labels may use fg colors but must end colors with $E39, never $RST
menu(){
  local title=$1 sub=$2; shift 2
  local opts=("$@") start=$MENU_START off=0 vis key i j inner FQ="" lab q
  local vmap=() vn=0 sel=0 rebuild=1
  MENU_START=0
  while :; do
    if (( rebuild )); then
      vmap=()
      if [[ -n $FQ ]]; then
        q=${FQ,,}
        for j in "${!opts[@]}"; do
          lab=$(plain "${opts[j]}")
          [[ ${lab,,} == *"$q"* ]] && vmap+=("$j")
        done
      else
        for j in "${!opts[@]}"; do vmap+=("$j"); done
      fi
      vn=${#vmap[@]}; sel=0; off=0
      if (( start >= 0 )); then
        for i in "${!vmap[@]}"; do (( vmap[i] == start )) && sel=$i; done
        start=-1
      fi
      rebuild=0
    fi
    setw
    vis=$(( $(rows) - HDR_H - 9 - PV_H )); (( vis < 3 )) && vis=3
    (( vn > 0 && vis > vn )) && vis=$vn
    (( sel < off )) && off=$sel
    (( sel >= off + vis )) && off=$(( sel - vis + 1 ))
    cls; header
    box_top "$title"
    [[ -n $sub ]] && box_row "  ${MUT}${sub}${E39}"
    [[ -n $FQ ]] && box_row "  ${C_ACC}/${FQ}${E39} ${MUT}— $vn matches · / to change · esc clears${E39}"
    box_row
    if (( vn == 0 )); then
      box_row "   ${MUT}no matches${E39}"
    else
      (( off > 0 )) && box_row "    ${MUT}↑ more${E39}"
      for (( i = off; i < vn && i < off + vis; i++ )); do
        if (( i == sel )); then
          inner=$(pad " ${C_ACC}▌ ${C_TXT}${BOLD}${opts[vmap[i]]}" "$W")
          printf '  %s│%s%s%s%s│%s\n' "$C_BRD" "$RST" "$C_SELBG" "$inner" "$RST$C_BRD" "$RST"
        else
          box_row "   ${opts[vmap[i]]}"
        fi
      done
      (( off + vis < vn )) && box_row "    ${MUT}↓ more${E39}"
    fi
    box_row
    box_bot
    [[ -n $PV_FN ]] && (( vn > 0 )) && $PV_FN "${vmap[sel]}"
    footer
    key=$(read_key)
    case $key in
      up)    (( vn )) && { sel=$(( (sel - 1 + vn) % vn )); [[ -n $PV_CB ]] && $PV_CB "${vmap[sel]}"; } ;;
      down)  (( vn )) && { sel=$(( (sel + 1) % vn )); [[ -n $PV_CB ]] && $PV_CB "${vmap[sel]}"; } ;;
      enter) (( vn )) || continue; MENU_IDX=${vmap[sel]}; return 0 ;;
      '/')   printf '\n   %s/%s ' "$C_ACC$BOLD" "$RST"; printf '%s' "$ESC[?25h"
             IFS= read -r FQ < /dev/tty; printf '%s' "$ESC[?25l"
             rebuild=1 ;;
      u)     [[ -n ${UNDO_HOOK:-} ]] && $UNDO_HOOK ;;
      esc)   if [[ -n $FQ ]]; then FQ=""; rebuild=1; else return 1; fi ;;
      q)     tui_off; exit 0 ;;
    esac
  done
}

QUIET=0
notify(){ # boxed message screen, %b-expanded, multiline; suppressed when QUIET=1
  (( QUIET )) && return 0
  local lines=() l
  while IFS= read -r l; do lines+=("$l"); done <<< "$(printf '%b' "$1")"
  HDR_MODE=small
  cls; header; setw
  box_top
  box_row
  for l in "${lines[@]}"; do box_wrap "$l"; done
  box_row
  box_bot
  printf '\n   %s %s%s%s\n' "$(chip 'any key')" "$MUT" "continue" "$RST"
  read_key >/dev/null
}
working(){ # progress screen, no key wait
  (( QUIET )) && return 0
  HDR_MODE=small
  cls; header; setw
  box_top
  box_row
  box_row "  ${WARN}⏳ $1${E39}"
  box_row
  box_bot
}
ask(){ # ask PROMPT [default] → REPLY
  printf '\n   %s❯%s %s%s%s ' "$C_ACC$BOLD" "$RST" "$BOLD" "$1" "$RST"
  [[ -n ${2:-} ]] && printf '%s(%s)%s ' "$MUT" "$2" "$RST"
  printf '%s' "$ESC[?25h"
  IFS= read -r REPLY < /dev/tty
  printf '%s' "$ESC[?25l"
  [[ -z $REPLY && -n ${2:-} ]] && REPLY=$2
  [[ -n $REPLY ]]
}
pick_from(){ # pick_from TITLE [HINT] < lines → PICK
  local items=() line
  while IFS= read -r line; do [[ -n $line ]] && items+=("$line"); done
  (( ${#items[@]} )) || { notify "${WARN}⚠ nothing found${RST}${2:+\n${MUT}$2${RST}}"; return 1; }
  menu "$1" "${#items[@]} available" "${items[@]}" || return 1
  PICK=${items[MENU_IDX]}
}

# ── live picker: highlighted item is applied to the desktop INSTANTLY.
#    ⏎ keeps it, esc reverts to what you had before.
LIVE_SETTER="" LIVE_ITEMS=()
live_cb(){ $LIVE_SETTER "${LIVE_ITEMS[$1]}" >/dev/null 2>&1; }
pick_live(){ # pick_live TITLE HINT SETTER CURRENT < values → PICK
  local title=$1 hint=$2 setter=$3 cur=$4 line i start=0
  LIVE_ITEMS=()
  while IFS= read -r line; do [[ -n $line ]] && LIVE_ITEMS+=("$line"); done
  (( ${#LIVE_ITEMS[@]} )) || { notify "${WARN}⚠ nothing found${RST}\n${MUT}$hint${RST}"; return 1; }
  for i in "${!LIVE_ITEMS[@]}"; do [[ ${LIVE_ITEMS[i]} == "$cur" ]] && start=$i; done
  LIVE_SETTER=$setter
  MENU_START=$start PV_CB=live_cb
  if menu "$title" "${#LIVE_ITEMS[@]} available ${C_BRD}·${MUT} applied live while browsing ${C_BRD}·${MUT} esc reverts" "${LIVE_ITEMS[@]}"; then
    PV_CB=""; PICK=${LIVE_ITEMS[MENU_IDX]}; return 0
  fi
  PV_CB=""
  [[ -n $cur ]] && $setter "$cur" >/dev/null 2>&1   # revert
  return 1
}

current_of(){ # current_of KIND → currently active value
  case "$1:$DE" in
    gtk:gnome)    gget org.gnome.desktop.interface gtk-theme ;;
    gtk:xfce)     xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null ;;
    gtk:*)        state_get gtk_theme ;;
    icons:gnome)  gget org.gnome.desktop.interface icon-theme ;;
    icons:kde)    kr --file kdeglobals --group Icons --key Theme 2>/dev/null ;;
    icons:xfce)   xfconf-query -c xsettings -p /Net/IconThemeName 2>/dev/null ;;
    icons:*)      state_get icon_theme ;;
    cursor:gnome) gget org.gnome.desktop.interface cursor-theme ;;
    cursor:xfce)  xfconf-query -c xsettings -p /Gtk/CursorThemeName 2>/dev/null ;;
    cursor:*)     state_get cursor_theme ;;
    dl:gnome)     [[ $(gget org.gnome.desktop.interface color-scheme) == prefer-dark ]] && echo dark || echo light ;;
    dl:*)         state_get color_scheme ;;
    accent:gnome) gget org.gnome.desktop.interface accent-color ;;
    accent:*)     state_get accent ;;
    wall:gnome)   local u; u=$(gget org.gnome.desktop.background picture-uri); printf '%s\n' "${u#file://}" ;;
    wall:*)       state_get wallpaper ;;
    kcs:kde)      kr --file kdeglobals --group General --key ColorScheme 2>/dev/null ;;
    font:gnome)   gget org.gnome.desktop.interface font-name ;;
    font:*)       state_get font ;;
    mono:gnome)   gget org.gnome.desktop.interface monospace-font-name ;;
    mono:*)       state_get mono_font ;;
  esac
}

# ══════════════════════════ error-surfacing runner ══════════════════════════
FB=""
try(){ # try CMD ARGS... → FB gets ✓/✗ + real error message
  local out
  command -v "$1" >/dev/null 2>&1 || {
    FB="${ERR}✗ '$1' is not installed${RST}\n${MUT}wrong desktop backend? check System info${RST}"
    return 1
  }
  if out=$("$@" 2>&1); then
    FB="${OK}✓ applied${RST}"
    return 0
  else
    FB="${ERR}✗ failed${RST}\n${MUT}$(head -2 <<<"$out")${RST}"
    return 1
  fi
}

# ══════════════════════════ state helpers ══════════════════════════
state_set(){ touch "$STATE_FILE"; sed -i "\|^$1=|d" "$STATE_FILE"; printf '%s=%s\n' "$1" "$2" >> "$STATE_FILE"; }
state_get(){ [[ -f $STATE_FILE ]] && sed -n "s|^$1=||p" "$STATE_FILE" | head -1; }

# ══════════════════════════ detection ══════════════════════════
DE=generic DE_LABEL=generic
detect_de(){
  local d="${XDG_CURRENT_DESKTOP:-} ${DESKTOP_SESSION:-}"; d=${d,,}
  case $d in
    *hyprland*)      DE=hyprland ;;
    *kde*|*plasma*)  DE=kde ;;
    *gnome*|*unity*) DE=gnome ;;
    *xfce*)          DE=xfce ;;
  esac
  [[ $DE == generic && -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && DE=hyprland
  if [[ $DE == generic ]] && command -v gsettings >/dev/null 2>&1 \
     && gsettings get org.gnome.desktop.interface gtk-theme >/dev/null 2>&1; then
    DE=gnome
  fi
  case $DE in
    gnome) DE_LABEL="GNOME" ;; kde) DE_LABEL="KDE Plasma" ;;
    hyprland) DE_LABEL="Hyprland" ;; xfce) DE_LABEL="XFCE" ;;
    *) DE_LABEL="generic" ;;
  esac
}

kw(){
  if command -v kwriteconfig6 >/dev/null 2>&1; then kwriteconfig6 "$@"
  elif command -v kwriteconfig5 >/dev/null 2>&1; then kwriteconfig5 "$@"
  else echo "kwriteconfig5/6 not found" >&2; return 127; fi
}
kr(){
  if command -v kreadconfig6 >/dev/null 2>&1; then kreadconfig6 "$@"
  elif command -v kreadconfig5 >/dev/null 2>&1; then kreadconfig5 "$@"; fi
}
gget(){ gsettings get "$@" 2>/dev/null | sed "s/^'//;s/'$//"; }

list_dirs(){
  local d
  for d in "$@"; do
    [[ -d $d ]] && find "$d" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null
  done | sort -u
}
list_gtk_themes(){ list_dirs /usr/share/themes "$HOME/.themes" "$HOME/.local/share/themes"; }
list_icon_themes(){ list_dirs /usr/share/icons "$HOME/.icons" "$HOME/.local/share/icons" | grep -vi '^default$'; }
list_cursor_themes(){
  local d t
  for d in /usr/share/icons "$HOME/.icons" "$HOME/.local/share/icons"; do
    [[ -d $d ]] || continue
    for t in "$d"/*/cursors; do [[ -d $t ]] && basename "$(dirname "$t")"; done
  done | sort -u
}
list_kde_colorschemes(){
  find /usr/share/color-schemes "$HOME/.local/share/color-schemes" \
    -maxdepth 1 -name '*.colors' -printf '%f\n' 2>/dev/null | sed 's/\.colors$//' | sort -u
}
list_kde_lookandfeel(){ list_dirs /usr/share/plasma/look-and-feel "$HOME/.local/share/plasma/look-and-feel"; }
list_font_families(){ fc-list : family 2>/dev/null | sed 's/,.*//' | sort -u; }
list_mono_families(){ fc-list :spacing=100 family 2>/dev/null | sed 's/,.*//' | sort -u; }
list_wallpapers(){
  local d
  for d in "$HOME/Pictures" "$HOME/Bilder" "$HOME/Downloads" "$HOME/wallpapers" /usr/share/backgrounds; do
    [[ -d $d ]] && find "$d" -maxdepth 3 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null
  done | sort -u | head -400
}

# ── preview panes (drawn under the menu) ──
gtk_pv(){ # extract real theme colors from gtk.css if readable
  local t=${LIVE_ITEMS[$1]} d css="" c sw="" n=0
  for d in "$HOME/.themes" "$HOME/.local/share/themes" /usr/share/themes; do
    [[ -f "$d/$t/gtk-3.0/gtk.css" ]] && { css="$d/$t/gtk-3.0/gtk.css"; break; }
  done
  box_top "theme preview"
  if [[ -n $css ]]; then
    while IFS= read -r c; do sw+="$(fgc "$c")██ "; (( n++ )); done \
      < <(grep -oE '@define-color[^;]*#[0-9a-fA-F]{6}' "$css" | grep -oE '[0-9a-fA-F]{6}' | head -8)
  fi
  if (( n )); then box_row "  ${sw}${E39}${MUT}colors from its gtk.css${E39}"
  else box_row "  ${MUT}no parseable gtk.css — watch your desktop instead${E39}"; fi
  box_row "  ${MUT}affects GTK apps (Files, gedit …) · not Qt/libadwaita${E39}"
  box_bot
}

SCHEME_NAMES=()
scheme_pv(){ # fake terminal rendered in the actual scheme colors
  local C i strip="" r
  read -r -a C <<< "${SCHEMES[${SCHEME_NAMES[$1]:-${SCHEME_NAMES[0]}}]}"
  local BG; BG=$'\e[48;2;'"$((16#${C[0]:0:2}));$((16#${C[0]:2:2}));$((16#${C[0]:4:2}))"$'m'
  local F R G Y B M
  F=$(fgc "${C[1]}"); R=$(fgc "${C[3]}"); G=$(fgc "${C[4]}")
  Y=$(fgc "${C[5]}"); B=$(fgc "${C[6]}"); M=$(fgc "${C[7]}")
  for i in {2..17}; do strip+="$(fgc "${C[i]}")██"; done
  box_top "terminal preview"
  local rws=(
    " ${G}adrian@arch${F} ${B}~/dev${F} ${M}❯${F} cargo build --release"
    " ${M}fn ${B}main${F}() { println!(${Y}\"rice\"${F}); }  ${R}✗ E0308${F}"
    " $strip"
  )
  for r in "${rws[@]}"; do
    printf '  %s│%s%s%s%s│%s\n' "$C_BRD" "$BG" "$(pad "$r" "$W")" "$RST" "$C_BRD" "$RST"
  done
  box_bot
}

wallpaper_picker(){
  local paths=() labels=() p lab cur start=0 i
  while IFS= read -r p; do
    paths+=("$p")
    lab=${p/#$HOME/\~}; (( ${#lab} > 46 )) && lab="…${lab: -45}"
    labels+=("$lab")
  done < <(list_wallpapers)
  labels=("✎ enter path manually" "${labels[@]}")
  WALL_PATHS=("" "${paths[@]}")
  cur=$(current_of wall)
  for i in "${!WALL_PATHS[@]}"; do [[ ${WALL_PATHS[i]} == "$cur" ]] && start=$i; done
  local pvh=3; command -v chafa >/dev/null 2>&1 && pvh=12
  MENU_START=$start PV_CB=wall_cb
  if PV_FN=wall_pv PV_H=$pvh menu "Wallpaper" "${#paths[@]} images ${C_BRD}·${MUT} applied live while browsing ${C_BRD}·${MUT} esc reverts" "${labels[@]}"; then
    PV_CB=""
    if (( MENU_IDX == 0 )); then
      ask "image path:" "" && { set_wallpaper "$REPLY"; log_change wallpaper "$cur" "$REPLY"; notify "$FB"; }
    else
      set_wallpaper "${WALL_PATHS[MENU_IDX]}"
      log_change wallpaper "$cur" "${WALL_PATHS[MENU_IDX]}"
      notify "$FB"
    fi
  else
    PV_CB=""
    [[ -n $cur && -f $cur ]] && set_wallpaper "$cur" >/dev/null 2>&1
  fi
}
wall_cb(){ (( $1 > 0 )) && set_wallpaper "${WALL_PATHS[$1]}" >/dev/null 2>&1; }
wall_pv(){ # inline image preview via chafa (sixel/kitty/ansi-art, auto-detected)
  local p=${WALL_PATHS[$1]:-}
  if [[ -n $p && -f $p ]] && command -v chafa >/dev/null 2>&1; then
    chafa -s "$((W - 2))x10" "$p" 2>/dev/null | sed 's/^/   /'
  elif [[ -n $p ]]; then
    printf '\n   %s\n' "${MUT}↯ applied live on your desktop — install 'chafa' for inline image preview${RST}"
  fi
}

FONT_SIZE=11
font_live(){ set_font "$1 $FONT_SIZE"; }
mono_live(){ set_mono_font "$1 $FONT_SIZE"; }
font_picker(){ # font_picker iface|mono
  local kind=$1 cur setter lister live title
  if [[ $kind == mono ]]; then
    cur=$(current_of mono); setter=set_mono_font; lister=list_mono_families; live=mono_live; title="Monospace font"
  else
    cur=$(current_of font); setter=set_font; lister=list_font_families; live=font_live; title="Interface font"
  fi
  FONT_SIZE=${cur##* }; [[ $FONT_SIZE =~ ^[0-9]+([.,][0-9]+)?$ ]] || FONT_SIZE=11
  if pick_live "$title" "needs fontconfig (fc-list)" "$live" "${cur% *}" < <($lister); then
    ask "size:" "$FONT_SIZE" && {
      $setter "$PICK $REPLY"
      log_change "$([[ $kind == mono ]] && echo mono_font || echo font)" "$cur" "$PICK $REPLY"
      notify "$FB"
    }
  fi
}

# ══════════════════════════ undo / history ══════════════════════════
HIST_FILE="$CONFIG_DIR/history"
log_change(){ # KEY OLD NEW
  [[ -z $2 || "$2" == "$3" ]] && return 0
  printf '%s|%s|%s|%s\n' "$(date +%H:%M)" "$1" "$2" "$3" >> "$HIST_FILE"
}
apply_kv(){ # KEY VALUE — abstract dispatcher (profiles, undo, import)
  case $1 in
    gtk_theme)       set_gtk_theme "$2" ;;
    icon_theme)      set_icon_theme "$2" ;;
    cursor_theme)    set_cursor_theme "$2" ;;
    font)            set_font "$2" ;;
    mono_font)       set_mono_font "$2" ;;
    color_scheme)    set_color_scheme "$2" ;;
    accent)          set_accent "$2" ;;
    wallpaper)       [[ -f $2 ]] && set_wallpaper "$2" ;;
    kde_colorscheme) set_kde_colorscheme "$2" ;;
    kde_lookandfeel) set_kde_lookandfeel "$2" ;;
    term_scheme)     [[ -n ${SCHEMES[$2]:-} ]] && apply_term_scheme "$2" ;;
    starship)        apply_starship "$2" ;;
  esac
}
undo_last(){
  [[ -s $HIST_FILE ]] || { notify "${WARN}⚠ nothing to undo${RST}"; return; }
  local line t key old new
  line=$(tail -1 "$HIST_FILE")
  IFS='|' read -r t key old new <<< "$line"
  local QUIET=1
  apply_kv "$key" "$old"
  QUIET=0
  sed -i '$d' "$HIST_FILE"
  notify "${OK}↶ undid ${BOLD}$key${RST}\n${MUT}$new → $old${E39}"
}
history_menu(){
  while :; do
    local lines=() items=("↶ Undo last change" "✕ Clear history") l t key old new
    [[ -f $HIST_FILE ]] && while IFS= read -r l; do lines+=("$l"); done < <(tac "$HIST_FILE" | head -40)
    for l in "${lines[@]}"; do
      IFS='|' read -r t key old new <<< "$l"
      items+=("${MUT}$t${E39}  $(pad "$key" 13) ${MUT}$old →${E39} $new")
    done
    menu "Undo / History" "newest first · ⏎ on an entry rolls back to its old value" "${items[@]}" || return
    local QUIET
    case $MENU_IDX in
      0) undo_last ;;
      1) : > "$HIST_FILE"; notify "${OK}✓ history cleared${RST}" ;;
      *) IFS='|' read -r t key old new <<< "${lines[MENU_IDX-2]}"
         QUIET=1; apply_kv "$key" "$old"; QUIET=0
         notify "${OK}↶ rolled back ${BOLD}$key${RST} ${MUT}→ $old${E39}" ;;
    esac
  done
}

# ══════════════════════════ theme catalog (download) ══════════════════════════
# label|target|method|url|arg
CATALOG=(
  "Nordic ${MUT}GTK dark${E39}|themes|self|https://github.com/EliverLara/Nordic|Nordic"
  "Orchis ${MUT}GTK modern${E39}|themes|script|https://github.com/vinceliuice/Orchis-theme|./install.sh -c dark -c light"
  "Catppuccin ${MUT}GTK${E39}|themes|copy|https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme|themes"
  "Tokyonight ${MUT}GTK${E39}|themes|copy|https://github.com/Fausto-Korpsvart/Tokyonight-GTK-Theme|themes"
  "Gruvbox ${MUT}GTK${E39}|themes|copy|https://github.com/Fausto-Korpsvart/Gruvbox-GTK-Theme|themes"
  "Papirus ${MUT}Icons${E39}|icons|copy|https://github.com/PapirusDevelopmentTeam/papirus-icon-theme|Papirus Papirus-Dark Papirus-Light"
  "Tela ${MUT}Icons${E39}|icons|script|https://github.com/vinceliuice/Tela-icon-theme|./install.sh"
  "Bibata ${MUT}Cursor${E39}|icons|tar|https://github.com/ful1e5/Bibata_Cursor/releases/latest/download/Bibata.tar.xz|"
  "Phinger ${MUT}Cursor${E39}|icons|tar|https://github.com/phisch/phinger-cursors/releases/latest/download/phinger-cursors-variants.tar.bz2|"
  "Capitaine ${MUT}Cursor${E39}|icons|copy|https://github.com/keeferrourke/capitaine-cursors|dist:capitaine-cursors"
  "JetBrainsMono ${MUT}Nerd Font${E39}|fonts|zip|https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip|JetBrainsMono"
  "FiraCode ${MUT}Nerd Font${E39}|fonts|zip|https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip|FiraCode"
  "Hack ${MUT}Nerd Font${E39}|fonts|zip|https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip|Hack"
  "CaskaydiaCove ${MUT}Nerd Font${E39}|fonts|zip|https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip|CascadiaCode"
  "Meslo ${MUT}Nerd Font${E39}|fonts|zip|https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.zip|Meslo"
)
theme_install(){ # theme_install "CATALOG-LINE" [quiet]
  local label target method url arg
  IFS='|' read -r label target method url arg <<< "$1"
  local tdir="$HOME/.themes"
  [[ $target == icons ]] && tdir="$HOME/.icons"
  [[ $target == fonts ]] && tdir="$HOME/.local/share/fonts/$arg"
  mkdir -p "$tdir"
  local tmp out tok src name
  tmp=$(mktemp -d)
  working "downloading $(plain "$label") …"
  FB=""
  if [[ $method != tar && $method != zip ]] && ! command -v git >/dev/null 2>&1; then
    FB="${ERR}✗ git required${RST}"
  elif [[ $method == tar || $method == zip ]] && ! command -v curl >/dev/null 2>&1; then
    FB="${ERR}✗ curl required${RST}"
  else
    case $method in
      self)
        out=$(git clone --depth 1 "$url" "$tmp/t" 2>&1) \
          && { rm -rf "$tmp/t/.git" "${tdir:?}/$arg"; mv "$tmp/t" "$tdir/$arg"; } \
          || FB="${ERR}✗ git clone failed${RST}\n${MUT}$(tail -1 <<<"$out")${E39}" ;;
      copy)
        out=$(git clone --depth 1 "$url" "$tmp/t" 2>&1) \
          || FB="${ERR}✗ git clone failed${RST}\n${MUT}$(tail -1 <<<"$out")${E39}"
        if [[ -z $FB ]]; then
          for tok in $arg; do
            src=${tok%%:*}; name=${tok#*:}; [[ $name == "$tok" ]] && name=$(basename "$src")
            if [[ -d $tmp/t/$src ]]; then
              if [[ -d $tmp/t/$src/gtk-3.0 || -f $tmp/t/$src/index.theme || -d $tmp/t/$src/cursors ]]; then
                rm -rf "${tdir:?}/$name"; cp -r "$tmp/t/$src" "$tdir/$name"
              else
                cp -r "$tmp/t/$src"/. "$tdir"/ 2>/dev/null
              fi
            else
              FB="${WARN}⚠ '$src' not found in repo layout${RST}"
            fi
          done
        fi ;;
      script)
        out=$(git clone --depth 1 "$url" "$tmp/t" 2>&1) \
          || FB="${ERR}✗ git clone failed${RST}\n${MUT}$(tail -1 <<<"$out")${E39}"
        [[ -z $FB ]] && { out=$(cd "$tmp/t" && eval "$arg" 2>&1) \
          || FB="${ERR}✗ install script failed${RST}\n${MUT}$(tail -1 <<<"$out")${E39}"; } ;;
      tar)
        out=$(curl -fsSL "$url" -o "$tmp/pkg" 2>&1) \
          || FB="${ERR}✗ download failed${RST}\n${MUT}$(tail -1 <<<"$out")${E39}"
        [[ -z $FB ]] && { tar -xf "$tmp/pkg" -C "$tdir" 2>/dev/null || FB="${ERR}✗ extract failed${RST}"; } ;;
      zip)
        command -v unzip >/dev/null 2>&1 || FB="${ERR}✗ unzip required${RST}"
        [[ -z $FB ]] && { out=$(curl -fsSL "$url" -o "$tmp/pkg.zip" 2>&1) \
          || FB="${ERR}✗ download failed${RST}\n${MUT}$(tail -1 <<<"$out")${E39}"; }
        [[ -z $FB ]] && { unzip -oq "$tmp/pkg.zip" -d "$tdir" 2>/dev/null || FB="${ERR}✗ extract failed${RST}"; } ;;
    esac
  fi
  rm -rf "$tmp"
  [[ $target == fonts && -z $FB ]] && fc-cache -f "$tdir" >/dev/null 2>&1
  [[ -z $FB ]] && FB="${OK}✓ $(plain "$label") installed → ${tdir/#$HOME/\~}${RST}"
  [[ -z ${2:-} ]] && notify "$FB"
  [[ $FB == *✓* ]]
}
themes_menu(){
  while :; do
    local labels=() c
    for c in "${CATALOG[@]}"; do labels+=("${c%%|*}"); done
    menu "Get themes & fonts" "curated packs from GitHub → ~/.themes · ~/.icons · fonts" "${labels[@]}" || return
    local keep=$MENU_IDX
    theme_install "${CATALOG[MENU_IDX]}"
    MENU_START=$keep
  done
}

# ══════════════════════════ rice presets (one-shot full looks) ══════════════════════════
# name|gtk-glob|icon-glob|cursor-glob|term-scheme|dark/light|accent|catalog idx (gtk icons cursor)
PRESETS=(
  "Catppuccin|Catppuccin*|Papirus-Dark|phinger-cursors*|catppuccin-mocha|dark|pink|2 5 8"
  "Nordic|Nordic*|Papirus-Dark|phinger-cursors*|nord|dark|blue|0 5 8"
  "Gruvbox|Gruvbox*|Papirus-Dark|Bibata-*|gruvbox-dark|dark|orange|4 5 7"
  "Tokyonight|Tokyonight*|Papirus-Dark|Bibata-*|tokyo-night|dark|purple|3 5 7"
)
find_installed(){ # GLOB DIR... → basename of first match
  local g=$1 d m; shift
  for d in "$@"; do
    for m in "$d"/$g; do [[ -d $m ]] && { basename "$m"; return 0; }; done
  done
  return 1
}
preset_apply(){
  local name gtkg icong curg term dl acc needs t sum=""
  IFS='|' read -r name gtkg icong curg term dl acc needs <<< "$1"
  local ni=($needs) i dirs globs=("$gtkg" "$icong" "$curg")
  for i in 0 1 2; do
    if (( i == 0 )); then dirs=("$HOME/.themes" "$HOME/.local/share/themes" /usr/share/themes)
    else dirs=("$HOME/.icons" "$HOME/.local/share/icons" /usr/share/icons); fi
    find_installed "${globs[i]}" "${dirs[@]}" >/dev/null \
      || theme_install "${CATALOG[${ni[i]}]}" quiet
  done
  local QUIET=1
  t=$(find_installed "$gtkg" "$HOME/.themes" "$HOME/.local/share/themes" /usr/share/themes) \
    && { set_gtk_theme "$t"; sum+="\n  ${MUT}gtk${E39}       $t"; }
  t=$(find_installed "$icong" "$HOME/.icons" "$HOME/.local/share/icons" /usr/share/icons) \
    && { set_icon_theme "$t"; sum+="\n  ${MUT}icons${E39}     $t"; }
  t=$(find_installed "$curg" "$HOME/.icons" "$HOME/.local/share/icons" /usr/share/icons) \
    && { set_cursor_theme "$t"; sum+="\n  ${MUT}cursor${E39}    $t"; }
  set_color_scheme "$dl"
  set_accent "$acc"
  apply_term_scheme "$term"
  sum+="\n  ${MUT}terminal${E39}  $term\n  ${MUT}mode${E39}      $dl · accent $acc"
  QUIET=0
  notify "${OK}✓ full rice applied: ${BOLD}$name${RST}$sum\n\n${MUT}icons/cursor may need re-login · restart terminals${E39}"
}
preset_menu(){
  while :; do
    local labels=() p n term C sw i _x
    for p in "${PRESETS[@]}"; do
      IFS='|' read -r n _x _x _x term _x _x _x <<< "$p"
      read -r -a C <<< "${SCHEMES[$term]}"
      sw=""; for i in 3 4 5 6 7 8; do sw+="$(fgc "${C[i]}")██"; done
      labels+=("$(pad "$n" 14) ${sw}${E39}")
    done
    labels=("⚄ Random rice ${MUT}shuffle installed themes${E39}" "${labels[@]}")
    menu "Rice presets" "one shot: GTK + icons + cursor + terminal + accent — downloads what's missing" "${labels[@]}" || return
    local keep=$MENU_IDX
    if (( MENU_IDX == 0 )); then random_rice
    else preset_apply "${PRESETS[MENU_IDX-1]}"; fi
    MENU_START=$keep
  done
}

# ══════════════════════════ gnome extensions ══════════════════════════
# name|uuid|description
EXT_CATALOG=(
  "User Themes|user-theme@gnome-shell-extensions.gcampax.github.com|Loads custom GNOME Shell themes from ~/.themes — the top bar and overview finally follow your rice. Essential."
  "Blur my Shell|blur-my-shell@aunetx|Adds a configurable blur effect to the overview, top panel, dock and app windows. The single biggest visual upgrade for GNOME."
  "Dash to Dock|dash-to-dock@micxgx.gmail.com|Pulls the dash out of the overview and turns it into a permanent macOS-style dock with autohide, themes and click actions."
  "Dash to Panel|dash-to-panel@jderose9.github.com|Merges dash and top bar into a single Windows-style taskbar with pinned apps and window previews. Alternative to Dash to Dock."
  "AppIndicator Support|appindicatorsupport@rgcjonas.gmail.com|Brings back tray icons — Discord, Steam, Telegram and co. show up in the top bar again instead of vanishing."
  "Caffeine|caffeine@patapon.info|One click in the top bar to block auto-suspend and screen blanking — for downloads, games or long builds."
  "Clipboard Indicator|clipboard-indicator@tudmotu.com|Clipboard history in the top bar with search, pinning and keyboard shortcuts."
  "GSConnect|gsconnect@andyholmes.github.io|KDE Connect for GNOME: pair your phone — file transfer, notifications, clipboard sync, remote input."
  "Vitals|Vitals@CoreCoding.com|Live CPU load, RAM, temperatures, fan speed and network throughput in the top bar."
  "Just Perfection|just-perfection-desktop@just-perfection|Hide or move any shell element (activities button, clock, panel…), change animation speed — the shell tweak tool."
  "Tiling Assistant|tiling-assistant@leleat-on-github|Windows-style snap assist: drag to edges for halves/quarters, snap layouts, keyboard tiling."
)
ext_pv(){ # description pane
  local desc=${EXT_CATALOG[$1]#*|}; desc=${desc#*|}
  local l
  box_top "what it does"
  while IFS= read -r l; do box_row "  ${MUT}$l${E39}"; done < <(fold -s -w $(( W - 4 )) <<< "$desc")
  box_bot
}
ext_install(){ # UUID NAME → FB
  local uuid=$1 name=${2:-$1} out ver info dlurl tmp
  working "installing $name — confirm the dialog on your desktop if one appears …"
  # 1) live install through gnome-shell itself (no re-login needed)
  if command -v gdbus >/dev/null 2>&1; then
    out=$(gdbus call --session --dest org.gnome.Shell.Extensions \
      --object-path /org/gnome/Shell/Extensions \
      --method org.gnome.Shell.Extensions.InstallRemoteExtension "$uuid" 2>/dev/null)
    case $out in
      *successful*) FB="${OK}✓ $name installed & enabled${RST}"; return 0 ;;
      *cancelled*)  FB="${WARN}⚠ cancelled in the desktop dialog${RST}"; return 1 ;;
    esac
  fi
  # 2) fallback: fetch matching build from extensions.gnome.org
  command -v curl >/dev/null 2>&1 || { FB="${ERR}✗ curl required${RST}"; return 1; }
  ver=$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -1)
  info=$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=$uuid&shell_version=$ver" 2>/dev/null)
  dlurl=$(sed -n 's/.*"download_url": *"\([^"]*\)".*/\1/p' <<< "$info" | head -1)
  [[ -n $dlurl ]] || { FB="${ERR}✗ no build for GNOME $ver on extensions.gnome.org${RST}"; return 1; }
  tmp=$(mktemp -d)
  if curl -fsSL "https://extensions.gnome.org$dlurl" -o "$tmp/ext.zip" 2>/dev/null \
     && gnome-extensions install --force "$tmp/ext.zip" >/dev/null 2>&1; then
    gnome-extensions enable "$uuid" >/dev/null 2>&1
    FB="${OK}✓ $name installed${RST}\n${MUT}if it doesn't show up: log out & back in, then toggle it on here${E39}"
  else
    FB="${ERR}✗ download or install failed${RST}"
  fi
  rm -rf "$tmp"
}
ext_install_menu(){
  while :; do
    local labels=() e name uuid have
    have=$(gnome-extensions list 2>/dev/null)
    for e in "${EXT_CATALOG[@]}"; do
      IFS='|' read -r name uuid _ <<< "$e"
      if [[ $have == *"$uuid"* ]]; then labels+=("$(pad "$name" 26) ${OK}✓ installed${E39}")
      else labels+=("$(pad "$name" 26) ${MUT}⇣ get${E39}"); fi
    done
    PV_FN=ext_pv PV_H=7 menu "Get extensions" "one-click install from extensions.gnome.org · ⏎ installs" "${labels[@]}" || return
    local keep=$MENU_IDX
    IFS='|' read -r name uuid _ <<< "${EXT_CATALOG[MENU_IDX]}"
    ext_install "$uuid" "$name"
    notify "$FB"
    MENU_START=$keep
  done
}
ext_menu(){
  command -v gnome-extensions >/dev/null 2>&1 \
    || { notify "${WARN}⚠ gnome-extensions CLI not found (GNOME only)${RST}\n${MUT}browse https://extensions.gnome.org${E39}"; return; }
  local sel=0
  while :; do
    local uuids=() items=("${C_MAU}⇣${E39} Get new extensions ${MUT}curated · one-click${E39}") uu en
    en=$(gnome-extensions list --enabled 2>/dev/null)
    while IFS= read -r uu; do [[ -n $uu ]] && uuids+=("$uu"); done < <(gnome-extensions list 2>/dev/null | sort)
    for uu in "${uuids[@]}"; do
      if [[ $en == *"$uu"* ]]; then items+=("$(pad "${uu%%@*}" 34) ${OK}◉ on${E39}")
      else items+=("$(pad "${uu%%@*}" 34) ${MUT}○ off${E39}"); fi
    done
    MENU_START=$sel
    menu "GNOME Extensions" "⏎ on an extension toggles it instantly" "${items[@]}" || return
    sel=$MENU_IDX
    if (( sel == 0 )); then
      ext_install_menu
    else
      uu=${uuids[sel-1]}
      if [[ $en == *"$uu"* ]]; then gnome-extensions disable "$uu" 2>/dev/null
      else gnome-extensions enable "$uu" 2>/dev/null; fi
    fi
  done
}

# ══════════════════════════ fastfetch presets ══════════════════════════
apply_fastfetch(){ # minimal|rice|full
  command -v fastfetch >/dev/null 2>&1 || { notify "${WARN}⚠ fastfetch not installed${RST}"; return; }
  local d="${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch" f
  mkdir -p "$d"; f="$d/config.jsonc"
  [[ -f $f ]] && cp "$f" "$f.bak"
  case $1 in
    minimal) cat > "$f" <<'EOF'
{ "logo": { "type": "small" },
  "modules": [ "title", "os", "kernel", "uptime", "packages", "memory" ] }
EOF
    ;;
    rice) cat > "$f" <<'EOF'
{ "logo": { "padding": { "top": 1 } },
  "display": { "separator": "  " },
  "modules": [
    "break", "title", "separator",
    { "type": "os",       "key": "󰣇 os" },
    { "type": "kernel",   "key": "󰌽 kernel" },
    { "type": "wm",       "key": "󱂬 wm" },
    { "type": "terminal", "key": " term" },
    { "type": "cpu",      "key": "󰻠 cpu" },
    { "type": "gpu",      "key": "󰢮 gpu" },
    { "type": "memory",   "key": "󰍛 mem" },
    "break", "colors" ] }
EOF
    ;;
    full) cat > "$f" <<'EOF'
{ "modules": [
    "title", "separator", "os", "host", "kernel", "uptime", "packages", "shell",
    "display", "de", "wm", "wmtheme", "theme", "icons", "font", "cursor",
    "terminal", "terminalfont", "cpu", "gpu", "memory", "swap", "disk",
    "localip", "battery", "locale", "break", "colors" ] }
EOF
    ;;
  esac
  notify "${OK}✓ fastfetch config: ${BOLD}$1${RST}\n${MUT}old config → config.jsonc.bak · 'rice' preset needs a nerd font${E39}"
}

# ══════════════════════════ profile export / import ══════════════════════════
profile_export(){ # NAME → prints tar path
  local name=$1
  local f="$PROFILE_DIR/$name.profile"
  [[ -f $f ]] || { echo "profile not found: $name" >&2; return 1; }
  local tmp key val d
  tmp=$(mktemp -d)
  mkdir -p "$tmp/rice/themes" "$tmp/rice/icons" "$tmp/rice/wallpaper"
  cp "$f" "$tmp/rice/profile"
  while IFS='=' read -r key val; do
    case $key in
      gtk_theme)
        for d in "$HOME/.themes" "$HOME/.local/share/themes"; do
          [[ -d $d/$val ]] && { cp -r "$d/$val" "$tmp/rice/themes/"; break; }
        done ;;
      icon_theme|cursor_theme)
        for d in "$HOME/.icons" "$HOME/.local/share/icons"; do
          [[ -d $d/$val ]] && { cp -r "$d/$val" "$tmp/rice/icons/"; break; }
        done ;;
      wallpaper) [[ -f $val ]] && cp "$val" "$tmp/rice/wallpaper/" ;;
    esac
  done < "$f"
  local out="$HOME/adrice-$name.tar.gz"
  tar -czf "$out" -C "$tmp" rice
  rm -rf "$tmp"
  echo "$out"
}
profile_import(){ # FILE or URL → prints profile name
  local a=$1 orig=$1
  if [[ $a == http://* || $a == https://* ]]; then
    local dl; dl=$(mktemp --suffix=.tar.gz)
    curl -fsSL "$a" -o "$dl" 2>/dev/null || { echo "download failed: $a" >&2; return 1; }
    a=$dl
  fi
  [[ -f $a ]] || { echo "file not found: $a" >&2; return 1; }
  local tmp name wp
  tmp=$(mktemp -d)
  tar -xzf "$a" -C "$tmp" 2>/dev/null && [[ -f $tmp/rice/profile ]] \
    || { echo "not a adrice export" >&2; rm -rf "$tmp"; return 1; }
  name=$(basename "${orig%%\?*}"); name=${name#adrice-}; name=${name%.tar.gz}
  [[ -n $name && $name != "$(basename "${orig%%\?*}")" ]] || name=imported
  mkdir -p "$HOME/.themes" "$HOME/.icons" "$CONFIG_DIR/wallpapers"
  cp -rn "$tmp"/rice/themes/. "$HOME/.themes/" 2>/dev/null
  cp -rn "$tmp"/rice/icons/. "$HOME/.icons/" 2>/dev/null
  wp=$(find "$tmp/rice/wallpaper" -type f 2>/dev/null | head -1)
  if [[ -n $wp ]]; then
    cp "$wp" "$CONFIG_DIR/wallpapers/"
    sed -i "s|^wallpaper=.*|wallpaper=$CONFIG_DIR/wallpapers/$(basename "$wp")|" "$tmp/rice/profile"
  fi
  cp "$tmp/rice/profile" "$PROFILE_DIR/$name.profile"
  rm -rf "$tmp"
  echo "$name"
}

# ══════════════════════════ color math ══════════════════════════
lum(){ local r=$((16#${1:0:2})) g=$((16#${1:2:2})) b=$((16#${1:4:2})); echo $(( (2*r + 3*g + b) / 6 )); }
sat(){
  local r=$((16#${1:0:2})) g=$((16#${1:2:2})) b=$((16#${1:4:2}))
  local mx=$r mn=$r
  (( g > mx )) && mx=$g; (( b > mx )) && mx=$b
  (( g < mn )) && mn=$g; (( b < mn )) && mn=$b
  echo $(( mx - mn ))
}
hue(){ # 0..359
  local r=$((16#${1:0:2})) g=$((16#${1:2:2})) b=$((16#${1:4:2}))
  local mx=$r mn=$r h
  (( g > mx )) && mx=$g; (( b > mx )) && mx=$b
  (( g < mn )) && mn=$g; (( b < mn )) && mn=$b
  local d=$(( mx - mn )); (( d == 0 )) && { echo 0; return; }
  if (( mx == r )); then h=$(( (60 * (g - b) / d + 360) % 360 ))
  elif (( mx == g )); then h=$(( 60 * (b - r) / d + 120 ))
  else h=$(( 60 * (r - g) / d + 240 )); fi
  echo $h
}
lighten(){ # HEX PCT
  local r=$((16#${1:0:2})) g=$((16#${1:2:2})) b=$((16#${1:4:2})) p=$2
  printf '%02x%02x%02x' $(( r + (255-r)*p/100 )) $(( g + (255-g)*p/100 )) $(( b + (255-b)*p/100 ))
}
darken(){ # HEX PCT
  local r=$((16#${1:0:2})) g=$((16#${1:2:2})) b=$((16#${1:4:2})) p=$2
  printf '%02x%02x%02x' $(( r*(100-p)/100 )) $(( g*(100-p)/100 )) $(( b*(100-p)/100 ))
}
nearest_accent(){ # HEX → gnome accent name
  (( $(sat "$1") < 25 )) && { echo slate; return; }
  local h; h=$(hue "$1")
  if   (( h < 20 || h >= 340 )); then echo red
  elif (( h < 45 ));  then echo orange
  elif (( h < 70 ));  then echo yellow
  elif (( h < 160 )); then echo green
  elif (( h < 200 )); then echo teal
  elif (( h < 260 )); then echo blue
  elif (( h < 290 )); then echo purple
  else echo pink; fi
}

# ══════════════════════════ wallpaper magic (pywal-style) ══════════════════════════
WALLGEN_ACCENT=blue WALLGEN_PRIMARY=89b4fa
wallgen_build(){ # IMAGE → SCHEMES[wallpaper-gen] + persisted; 1 on failure
  local img=$1 im
  if command -v magick >/dev/null 2>&1; then im=magick
  elif command -v convert >/dev/null 2>&1; then im=convert
  else FB="${ERR}✗ imagemagick required${RST}\n${MUT}install: sudo apt install imagemagick / pacman -S imagemagick${E39}"; return 1; fi
  [[ -f $img ]] || { FB="${ERR}✗ file not found${RST}"; return 1; }
  local colors=() line hex
  while IFS= read -r line; do
    hex=$(grep -oE '#[0-9A-Fa-f]{6}' <<< "$line" | head -1); hex=${hex#\#}; hex=${hex,,}
    [[ -n $hex ]] && colors+=("$hex")
  done < <($im "$img" -resize 10% -depth 8 -colors 24 -format %c histogram:info:- 2>/dev/null | sort -rn)
  (( ${#colors[@]} >= 4 )) || { FB="${ERR}✗ color extraction failed${RST}"; return 1; }
  # bg = darkest, fg = lightest (forced into readable range)
  local bg="" fg="" c l minl=999 maxl=-1
  for c in "${colors[@]}"; do
    l=$(lum "$c")
    (( l < minl )) && { minl=$l; bg=$c; }
    (( l > maxl )) && { maxl=$l; fg=$c; }
  done
  (( minl > 45 ))  && bg=$(darken "$bg" 60)
  (( maxl < 170 )) && fg=$(lighten "$fg" 55)
  # vibrant candidates
  local vib=()
  for c in "${colors[@]}"; do (( $(sat "$c") >= 25 )) && vib+=("$c"); done
  (( ${#vib[@]} )) || vib=("$(lighten "$fg" 10)")
  # most saturated = primary (accent, hyprland border)
  local best=${vib[0]} bs=0 s
  for c in "${vib[@]}"; do s=$(sat "$c"); (( s > bs )) && { bs=$s; best=$c; }; done
  WALLGEN_PRIMARY=$best
  WALLGEN_ACCENT=$(nearest_accent "$best")
  # fill 6 ansi slots (red green yellow blue magenta cyan) by nearest hue
  local targets=(0 120 60 240 300 180) slots=() t bd d h cand pick
  for t in "${targets[@]}"; do
    pick=${vib[0]}; bd=999
    for cand in "${vib[@]}"; do
      h=$(hue "$cand"); d=$(( h > t ? h - t : t - h )); (( d > 180 )) && d=$(( 360 - d ))
      (( d < bd )) && { bd=$d; pick=$cand; }
    done
    l=$(lum "$pick")
    (( l < 90 ))  && pick=$(lighten "$pick" 35)
    (( l > 200 )) && pick=$(darken "$pick" 20)
    slots+=("$pick")
  done
  local pal=("$(lighten "$bg" 12)" "${slots[0]}" "${slots[1]}" "${slots[2]}" "${slots[3]}" "${slots[4]}" "${slots[5]}" "$(darken "$fg" 12)")
  local i br=()
  for i in {0..7}; do br+=("$(lighten "${pal[i]}" 20)"); done
  SCHEMES[wallpaper-gen]="$bg $fg ${pal[*]} ${br[*]}"
  printf '%s\n' "${SCHEMES[wallpaper-gen]}" > "$CONFIG_DIR/wallgen.scheme"
  return 0
}
magic_apply_full(){ # IMAGE — wallpaper + terminals + dark + accent (+ hypr border)
  local img=$1 QUIET=1
  set_wallpaper "$img"
  apply_term_scheme wallpaper-gen
  set_color_scheme dark
  set_accent "$WALLGEN_ACCENT"
  [[ $DE == hyprland ]] && hypr_apply "general:col.active_border" "rgb($WALLGEN_PRIMARY)"
  QUIET=0
}
magic_menu(){
  local paths=() labels=() p lab img
  while IFS= read -r p; do
    paths+=("$p")
    lab=${p/#$HOME/\~}; (( ${#lab} > 46 )) && lab="…${lab: -45}"
    labels+=("$lab")
  done < <(list_wallpapers)
  labels=("✎ enter path manually" "${labels[@]}")
  WALL_PATHS=("" "${paths[@]}")
  local pvh=3; command -v chafa >/dev/null 2>&1 && pvh=12
  PV_FN=wall_pv PV_H=$pvh menu "Wallpaper magic" "pick an image — a full color theme gets generated from it" "${labels[@]}" || return
  if (( MENU_IDX == 0 )); then
    ask "image path:" "" || return; img=$REPLY
  else
    img=${WALL_PATHS[MENU_IDX]}
  fi
  working "extracting colors from $(basename "$img") …"
  wallgen_build "$img" || { notify "$FB"; return; }
  SCHEME_NAMES=(wallpaper-gen wallpaper-gen)
  PV_FN=scheme_pv PV_H=6 menu "Generated theme" "from $(basename "$img") · accent: $WALLGEN_ACCENT" \
    "Apply full ${MUT}wallpaper + terminals + dark + accent${E39}" \
    "Apply terminal scheme only" || return
  local old; old=$(state_get term_scheme)
  if (( MENU_IDX == 0 )); then
    magic_apply_full "$img"
    log_change term_scheme "$old" "wallpaper-gen"
    notify "${OK}✓ full theme generated & applied${RST}\n${MUT}accent $WALLGEN_ACCENT · dark mode · all terminals · wallpaper set${E39}\n${MUT}restart terminals to see the colors${E39}"
  else
    local QUIET=1; apply_term_scheme wallpaper-gen; QUIET=0
    log_change term_scheme "$old" "wallpaper-gen"
    notify "${OK}✓ terminal scheme applied${RST}\n${MUT}restart terminals to see it${E39}"
  fi
}

# ══════════════════════════ flatpak theme sync ══════════════════════════
flatpak_sync(){
  command -v flatpak >/dev/null 2>&1 \
    || { notify "${WARN}⚠ flatpak not installed — nothing to sync${RST}"; return; }
  working "granting flatpak apps access to your themes …"
  flatpak override --user \
    --filesystem="$HOME/.themes:ro" --filesystem="$HOME/.icons:ro" \
    --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro 2>/dev/null
  local t ic
  t=$(current_of gtk);   [[ -n $t ]]  && flatpak override --user --env=GTK_THEME="$t" 2>/dev/null
  ic=$(current_of icons); [[ -n $ic ]] && flatpak override --user --env=ICON_THEME="$ic" 2>/dev/null
  notify "${OK}✓ flatpak apps now follow your rice${RST}\n${MUT}gtk: ${t:-—} · icons: ${ic:-—}${E39}\n${MUT}restart open flatpak apps to see it${E39}"
}

# ══════════════════════════ auto day / night (systemd user timers) ══════════════════════════
autotheme_setup(){
  command -v systemctl >/dev/null 2>&1 || { notify "${WARN}⚠ systemd required${RST}"; return; }
  local profs=() p
  while IFS= read -r p; do profs+=("${p%.profile}"); done \
    < <(find "$PROFILE_DIR" -maxdepth 1 -name '*.profile' -printf '%f\n' 2>/dev/null | sort)
  (( ${#profs[@]} >= 2 )) || { notify "${WARN}⚠ save at least 2 profiles first (a light + a dark one)${RST}"; return; }
  menu "Day profile" "applied every morning" "${profs[@]}" || return
  local dayp=${profs[MENU_IDX]}
  menu "Night profile" "applied every evening" "${profs[@]}" || return
  local nightp=${profs[MENU_IDX]}
  ask "day starts at (HH:MM):" "07:00" || return; local dayt=$REPLY
  ask "night starts at (HH:MM):" "19:00" || return; local nightt=$REPLY
  local ud="$HOME/.config/systemd/user" n prof tm
  mkdir -p "$ud"
  for n in day night; do
    if [[ $n == day ]]; then prof=$dayp tm=$dayt; else prof=$nightp tm=$nightt; fi
    cat > "$ud/adrice-$n.service" <<EOF
[Unit]
Description=adrice: switch to $n profile ($prof)

[Service]
Type=oneshot
ExecStart=$SELF_PATH apply $prof
EOF
    cat > "$ud/adrice-$n.timer" <<EOF
[Unit]
Description=adrice $n switch

[Timer]
OnCalendar=*-*-* $tm:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
  done
  systemctl --user daemon-reload 2>/dev/null
  systemctl --user enable --now adrice-day.timer adrice-night.timer >/dev/null 2>&1 \
    && notify "${OK}✓ auto-theming active${RST}\n${MUT}$dayp at $dayt · $nightp at $nightt${E39}" \
    || notify "${ERR}✗ could not enable timers${RST}\n${MUT}check: systemctl --user status adrice-day.timer${E39}"
}
autotheme_menu(){
  while :; do
    menu "Auto day / night" "systemd user timers switch your profiles automatically" \
      "Set up ${MUT}pick profiles + times${E39}" "Status" "Disable" || return
    local keep=$MENU_IDX s
    case $MENU_IDX in
      0) autotheme_setup ;;
      1) s=$(systemctl --user list-timers 'adrice-*' --no-pager 2>/dev/null | head -4)
         notify "${MUT}${s:-no adrice timers active}${E39}" ;;
      2) systemctl --user disable --now adrice-day.timer adrice-night.timer >/dev/null 2>&1
         rm -f "$HOME/.config/systemd/user"/adrice-{day,night}.{timer,service}
         systemctl --user daemon-reload 2>/dev/null
         notify "${OK}✓ auto-theming disabled${RST}" ;;
    esac
    MENU_START=$keep
  done
}

# ══════════════════════════ app sync (btop · cava · vscode · spicetify) ══════════════════════════
appsync(){
  local name; name=$(state_get term_scheme)
  [[ -n $name && -n ${SCHEMES[$name]:-} ]] \
    || { notify "${WARN}⚠ apply a terminal color scheme first${RST}\n${MUT}Terminal & Shell → Color scheme${E39}"; return; }
  local C bg fg pal
  read -r -a C <<< "${SCHEMES[$name]}"
  bg=${C[0]}; fg=${C[1]}; pal=("${C[@]:2:16}")
  local done_=() skipped=()

  if command -v btop >/dev/null 2>&1; then
    local bd="$HOME/.config/btop/themes"; mkdir -p "$bd"
    {
      echo "theme[main_bg]=\"#$bg\""
      echo "theme[main_fg]=\"#$fg\""
      echo "theme[title]=\"#$fg\""
      echo "theme[hi_fg]=\"#${pal[4]}\""
      echo "theme[selected_bg]=\"#${pal[0]}\""
      echo "theme[selected_fg]=\"#${pal[4]}\""
      echo "theme[inactive_fg]=\"#${pal[8]}\""
      echo "theme[graph_text]=\"#$fg\""
      echo "theme[proc_misc]=\"#${pal[2]}\""
      echo "theme[cpu_box]=\"#${pal[4]}\""
      echo "theme[mem_box]=\"#${pal[2]}\""
      echo "theme[net_box]=\"#${pal[5]}\""
      echo "theme[proc_box]=\"#${pal[6]}\""
      echo "theme[div_line]=\"#${pal[8]}\""
      echo "theme[temp_start]=\"#${pal[2]}\""
      echo "theme[temp_mid]=\"#${pal[3]}\""
      echo "theme[temp_end]=\"#${pal[1]}\""
      echo "theme[cpu_start]=\"#${pal[6]}\""
      echo "theme[cpu_mid]=\"#${pal[4]}\""
      echo "theme[cpu_end]=\"#${pal[5]}\""
      echo "theme[free_start]=\"#${pal[2]}\""
      echo "theme[used_start]=\"#${pal[1]}\""
      echo "theme[download]=\"#${pal[4]}\""
      echo "theme[upload]=\"#${pal[5]}\""
    } > "$bd/adrice.theme"
    local bc="$HOME/.config/btop/btop.conf"
    if [[ -f $bc ]]; then
      sed -i 's|^color_theme.*|color_theme = "adrice"|' "$bc"
      grep -q '^color_theme' "$bc" || echo 'color_theme = "adrice"' >> "$bc"
    else
      echo 'color_theme = "adrice"' > "$bc"
    fi
    done_+=(btop)
  fi

  if command -v cava >/dev/null 2>&1; then
    local cf="$HOME/.config/cava/config"; mkdir -p "${cf%/*}"; touch "$cf"
    sed -i '/# >>> adrice/,/# <<< adrice/d' "$cf"
    cat >> "$cf" <<EOF
# >>> adrice
[color]
gradient = 1
gradient_count = 6
gradient_color_1 = '#${pal[4]}'
gradient_color_2 = '#${pal[6]}'
gradient_color_3 = '#${pal[2]}'
gradient_color_4 = '#${pal[3]}'
gradient_color_5 = '#${pal[5]}'
gradient_color_6 = '#${pal[1]}'
# <<< adrice
EOF
    done_+=(cava)
  fi

  local vs="$HOME/.config/Code/User/settings.json"
  if command -v python3 >/dev/null 2>&1 && { command -v code >/dev/null 2>&1 || [[ -f $vs ]]; }; then
    mkdir -p "${vs%/*}"
    if python3 - "$vs" "#$bg" "#$fg" "${pal[@]/#/#}" <<'PYEOF'
import json, sys, os
p, bg, fg, *pal = sys.argv[1:]
d = {}
if os.path.exists(p) and os.path.getsize(p) > 0:
    try:
        d = json.load(open(p))
    except Exception:
        sys.exit(1)  # settings.json has comments — refuse to touch it
names = ["Black","Red","Green","Yellow","Blue","Magenta","Cyan","White"]
cc = d.setdefault("workbench.colorCustomizations", {})
cc["terminal.background"] = bg
cc["terminal.foreground"] = fg
for i, n in enumerate(names):
    cc["terminal.ansi" + n] = pal[i]
    cc["terminal.ansiBright" + n] = pal[i + 8]
json.dump(d, open(p, "w"), indent=2)
PYEOF
    then done_+=("vscode terminal"); else skipped+=("vscode — settings.json has comments, skipped for safety"); fi
  fi

  if command -v spicetify >/dev/null 2>&1; then
    local sd="$HOME/.config/spicetify/Themes/adrice"; mkdir -p "$sd"
    cat > "$sd/color.ini" <<EOF
[Base]
text               = $fg
subtext            = ${pal[7]}
main               = $bg
sidebar            = ${pal[0]}
player             = $bg
card               = ${pal[0]}
shadow             = 000000
selected-row       = ${pal[4]}
button             = ${pal[4]}
button-active      = ${pal[5]}
button-disabled    = ${pal[8]}
tab-active         = ${pal[4]}
notification       = ${pal[2]}
notification-error = ${pal[1]}
misc               = ${pal[8]}
EOF
    if spicetify config current_theme adrice >/dev/null 2>&1 && spicetify apply >/dev/null 2>&1; then
      done_+=(spicetify)
    else
      skipped+=("spicetify — theme written, run 'spicetify apply' manually")
    fi
  fi

  local msg="" x
  if (( ${#done_[@]} )); then
    msg="${OK}✓ ${BOLD}$name${RST}${OK} synced to:${RST}"
    for x in "${done_[@]}"; do msg+="\n  ${MUT}· $x${E39}"; done
  else
    msg="${WARN}⚠ none of btop/cava/vscode/spicetify found${RST}"
  fi
  for x in "${skipped[@]}"; do msg+="\n  ${WARN}⚠ $x${E39}"; done
  notify "$msg"
}

# ══════════════════════════ doctor ══════════════════════════
doctor_report(){
  local ok="${OK}✓${E39}" warn="${WARN}⚠${E39}" t
  printf '%s\n' "${BOLD}adrice doctor${RST}" ""
  printf '%s\n' "${MUT}desktop${E39}  $DE_LABEL · ${XDG_SESSION_TYPE:-unknown session}"
  if [[ ${COLORTERM:-} == *truecolor* || ${COLORTERM:-} == *24bit* ]]; then
    printf '%s\n' "$ok truecolor terminal"
  else
    printf '%s\n' "$warn COLORTERM is not 'truecolor' — TUI colors may look wrong"
  fi
  for t in git curl unzip chafa python3; do
    if command -v "$t" >/dev/null 2>&1; then printf '%s\n' "$ok $t"
    else printf '%s\n' "$warn $t missing — some features limited"; fi
  done
  if command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then
    printf '%s\n' "$ok imagemagick (Wallpaper magic works)"
  else
    printf '%s\n' "$warn imagemagick missing — Wallpaper magic needs it"
  fi
  printf '%s\n' "$ok $(list_gtk_themes | wc -l) gtk themes · $(list_icon_themes | wc -l) icon themes installed"
  if command -v fc-list >/dev/null 2>&1; then
    if fc-list 2>/dev/null | grep -qi 'nerd'; then printf '%s\n' "$ok nerd font installed"
    else printf '%s\n' "$warn no nerd font — starship/fastfetch icons will look broken (Get themes & fonts)"; fi
  fi
  if [[ $DE == gnome ]]; then
    if gnome-extensions list 2>/dev/null | grep -q 'user-theme'; then
      printf '%s\n' "$ok User Themes extension (shell is themable)"
    else
      printf '%s\n' "$warn User Themes extension missing — GNOME Shell ignores ~/.themes (GNOME Extensions → Get)"
    fi
    printf '%s\n' "${MUT}note${E39}  libadwaita apps ignore gtk-theme by design — they only follow dark/light + accent"
  fi
  if command -v flatpak >/dev/null 2>&1; then
    if flatpak override --user --show 2>/dev/null | grep -q '.themes'; then
      printf '%s\n' "$ok flatpak apps follow your themes"
    else
      printf '%s\n' "$warn flatpak apps ignore your themes — run Doctor & sync → Flatpak theme sync"
    fi
  fi
}
# interactive doctor: every ⚠ line is selectable, ⏎ runs the fix
pkg_install(){ # PKG — leaves the TUI, runs the package manager with sudo, returns
  local pkg=$1 mgr=""
  if   command -v apt    >/dev/null 2>&1; then mgr="sudo apt install -y"
  elif command -v pacman >/dev/null 2>&1; then mgr="sudo pacman -S --noconfirm"
  elif command -v dnf    >/dev/null 2>&1; then mgr="sudo dnf install -y"
  elif command -v zypper >/dev/null 2>&1; then mgr="sudo zypper install -y"
  else notify "${WARN}⚠ no known package manager — install manually: $pkg${RST}"; return 1; fi
  case "$mgr $pkg" in
    *dnf*imagemagick)   pkg=ImageMagick ;;
    *pacman*python3)    pkg=python ;;
  esac
  tui_off
  printf '\n\033[1m→ %s %s\033[0m\n\033[2msudo will ask for your password\033[0m\n\n' "$mgr" "$pkg"
  $mgr "$pkg" < /dev/tty
  local rc=$?
  printf '\npress enter to return to adrice … '
  IFS= read -r _ < /dev/tty
  tui_on
  if (( rc == 0 )); then notify "${OK}✓ installed: $pkg${RST}"
  else notify "${ERR}✗ install failed (exit $rc)${RST}"; fi
}
DOC_ITEMS=() DOC_ACTIONS=()
doc_add(){ DOC_ITEMS+=("$1"); DOC_ACTIONS+=("$2"); }
doctor_scan(){
  DOC_ITEMS=(); DOC_ACTIONS=()
  local fixtag="${MUT}· ⏎ fix${E39}" t
  doc_add "${MUT}desktop  $DE_LABEL · ${XDG_SESSION_TYPE:-?}${E39}" none
  if [[ ${COLORTERM:-} == *truecolor* || ${COLORTERM:-} == *24bit* ]]; then
    doc_add "${OK}✓${E39} truecolor terminal" none
  else
    doc_add "${WARN}⚠${E39} no truecolor — use a modern terminal" none
  fi
  for t in git curl unzip chafa python3; do
    if command -v "$t" >/dev/null 2>&1; then doc_add "${OK}✓${E39} $t" none
    else doc_add "${WARN}⚠${E39} $t missing $fixtag" "pkg:$t"; fi
  done
  if command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then
    doc_add "${OK}✓${E39} imagemagick — Wallpaper magic ready" none
  else
    doc_add "${WARN}⚠${E39} imagemagick (Wallpaper magic) $fixtag" "pkg:imagemagick"
  fi
  doc_add "${OK}✓${E39} $(list_gtk_themes | wc -l) gtk themes · $(list_icon_themes | wc -l) icon themes" none
  if command -v fc-list >/dev/null 2>&1; then
    if fc-list 2>/dev/null | grep -qi 'nerd'; then doc_add "${OK}✓${E39} nerd font installed" none
    else doc_add "${WARN}⚠${E39} no nerd font — prompt icons broken $fixtag" nerdfont; fi
  fi
  if [[ $DE == gnome ]] && command -v gnome-extensions >/dev/null 2>&1; then
    if gnome-extensions list 2>/dev/null | grep -q 'user-theme'; then
      doc_add "${OK}✓${E39} User Themes extension" none
    else
      doc_add "${WARN}⚠${E39} User Themes ext — shell not themable $fixtag" userext
    fi
  fi
  [[ $DE == gnome ]] && doc_add "${MUT}note: libadwaita apps only follow dark/light + accent${E39}" none
  if command -v flatpak >/dev/null 2>&1; then
    if flatpak override --user --show 2>/dev/null | grep -q '.themes'; then
      doc_add "${OK}✓${E39} flatpak follows your themes" none
    else
      doc_add "${WARN}⚠${E39} flatpak ignores your themes $fixtag" flatpak
    fi
  fi
}
doctor_menu(){
  local sel=0 act c
  while :; do
    doctor_scan
    MENU_START=$sel
    menu "Doctor" "⏎ on a ⚠ line runs the fix · list refreshes after each fix" "${DOC_ITEMS[@]}" || return
    sel=$MENU_IDX
    act=${DOC_ACTIONS[sel]}
    case $act in
      none)     : ;;
      pkg:*)    pkg_install "${act#pkg:}" ;;
      nerdfont) for c in "${CATALOG[@]}"; do [[ $c == JetBrainsMono* ]] && { theme_install "$c"; break; }; done ;;
      userext)  ext_install "user-theme@gnome-shell-extensions.gcampax.github.com" "User Themes"; notify "$FB" ;;
      flatpak)  flatpak_sync ;;
    esac
  done
}
fix_menu(){
  while :; do
    menu "Doctor & sync" "" \
      "Doctor ${MUT}diagnose + one-key fixes${E39}" \
      "Flatpak theme sync ${MUT}make flatpak apps follow your rice${E39}" \
      "Sync colors to apps ${MUT}btop · cava · VS Code · Spicetify${E39}" || return
    local keep=$MENU_IDX
    case $MENU_IDX in
      0) doctor_menu ;;
      1) flatpak_sync ;;
      2) appsync ;;
    esac
    MENU_START=$keep
  done
}

# ══════════════════════════ random rice ══════════════════════════
random_rice(){
  local g=() ic=() cu=() sn=() n
  while IFS= read -r n; do g+=("$n"); done < <(list_gtk_themes)
  while IFS= read -r n; do ic+=("$n"); done < <(list_icon_themes)
  while IFS= read -r n; do cu+=("$n"); done < <(list_cursor_themes)
  while IFS= read -r n; do sn+=("$n"); done < <(printf '%s\n' "${!SCHEMES[@]}")
  local accents=(blue teal green yellow orange red pink purple)
  local QUIET=1 sum="" t old
  (( ${#g[@]} ))  && { old=$(current_of gtk);    t=${g[RANDOM % ${#g[@]}]};  set_gtk_theme "$t";    log_change gtk_theme "$old" "$t";    sum+="\n  ${MUT}gtk${E39}       $t"; }
  (( ${#ic[@]} )) && { old=$(current_of icons);  t=${ic[RANDOM % ${#ic[@]}]}; set_icon_theme "$t";  log_change icon_theme "$old" "$t";   sum+="\n  ${MUT}icons${E39}     $t"; }
  (( ${#cu[@]} )) && { old=$(current_of cursor); t=${cu[RANDOM % ${#cu[@]}]}; set_cursor_theme "$t"; log_change cursor_theme "$old" "$t"; sum+="\n  ${MUT}cursor${E39}    $t"; }
  old=$(state_get term_scheme); t=${sn[RANDOM % ${#sn[@]}]}; apply_term_scheme "$t"; log_change term_scheme "$old" "$t"; sum+="\n  ${MUT}terminal${E39}  $t"
  old=$(current_of accent); t=${accents[RANDOM % ${#accents[@]}]}; set_accent "$t"; log_change accent "$old" "$t"; sum+="\n  ${MUT}accent${E39}    $t"
  QUIET=0
  notify "${OK}✓ random rice rolled${RST}$sum\n\n${MUT}not feeling it? press u to undo piece by piece or roll again${E39}"
}

# ══════════════════════════ appearance backends ══════════════════════════
set_gtk_theme(){
  case $DE in
    gnome) try gsettings set org.gnome.desktop.interface gtk-theme "$1" ;;
    xfce)  try xfconf-query -c xsettings -p /Net/ThemeName -s "$1" ;;
    *)
      local v f
      for v in gtk-3.0 gtk-4.0; do
        f="$HOME/.config/$v/settings.ini"; mkdir -p "${f%/*}"; touch "$f"
        grep -q '^\[Settings\]' "$f" || printf '[Settings]\n' >> "$f"
        sed -i '/^gtk-theme-name=/d' "$f"
        sed -i "/^\[Settings\]/a gtk-theme-name=$1" "$f"
      done
      FB="${WARN}⚠ no GNOME/XFCE backend — wrote gtk settings.ini${RST}\n${MUT}GTK apps pick it up after restart${RST}" ;;
  esac
  state_set gtk_theme "$1"
}
set_icon_theme(){
  case $DE in
    gnome) try gsettings set org.gnome.desktop.interface icon-theme "$1" ;;
    kde)   try kw --file kdeglobals --group Icons --key Theme "$1" \
             && FB+="\n${MUT}may need re-login on KDE${RST}" ;;
    xfce)  try xfconf-query -c xsettings -p /Net/IconThemeName -s "$1" ;;
    *)     FB="${WARN}⚠ no icon backend for '$DE_LABEL'${RST}"; return 1 ;;
  esac
  state_set icon_theme "$1"
}
set_cursor_theme(){
  case $DE in
    gnome)    try gsettings set org.gnome.desktop.interface cursor-theme "$1" ;;
    kde)      try plasma-apply-cursortheme "$1" ;;
    xfce)     try xfconf-query -c xsettings -p /Gtk/CursorThemeName -s "$1" ;;
    hyprland) try hyprctl setcursor "$1" 24 ;;
    *)        FB="${WARN}⚠ no cursor backend for '$DE_LABEL'${RST}"; return 1 ;;
  esac
  state_set cursor_theme "$1"
}
set_font(){
  case $DE in
    gnome) try gsettings set org.gnome.desktop.interface font-name "$1" ;;
    xfce)  try xfconf-query -c xsettings -p /Gtk/FontName -s "$1" ;;
    kde)   try kw --file kdeglobals --group General --key font "$1,-1,5,50,0,0,0,0,0" ;;
    *)     FB="${WARN}⚠ no font backend for '$DE_LABEL'${RST}"; return 1 ;;
  esac
  state_set font "$1"
}
set_mono_font(){
  if [[ $DE == gnome ]]; then try gsettings set org.gnome.desktop.interface monospace-font-name "$1"
  else FB="${WARN}⚠ monospace font backend is GNOME-only${RST}"; return 1; fi
  state_set mono_font "$1"
}
set_color_scheme(){ # dark|light
  case $DE in
    gnome)
      if [[ $1 == dark ]]; then try gsettings set org.gnome.desktop.interface color-scheme prefer-dark
      else try gsettings set org.gnome.desktop.interface color-scheme default; fi ;;
    kde)
      try plasma-apply-colorscheme "$([[ $1 == dark ]] && echo BreezeDark || echo BreezeLight)" ;;
    *) FB="${WARN}⚠ no dark/light backend for '$DE_LABEL'${RST}"; return 1 ;;
  esac
  state_set color_scheme "$1"
}
set_accent(){
  try gsettings set org.gnome.desktop.interface accent-color "$1" \
    || FB+="\n${MUT}accent-color needs GNOME 47+${RST}"
  state_set accent "$1"
}
set_wallpaper(){
  local p=$1
  [[ -f $p ]] || { FB="${ERR}✗ file not found: $p${RST}"; return 1; }
  p=$(realpath "$p")
  case $DE in
    gnome)
      try gsettings set org.gnome.desktop.background picture-uri "file://$p" \
        && try gsettings set org.gnome.desktop.background picture-uri-dark "file://$p" ;;
    kde) try plasma-apply-wallpaperimage "$p" ;;
    hyprland)
      if command -v swww >/dev/null 2>&1; then try swww img "$p"
      elif command -v hyprctl >/dev/null 2>&1; then
        hyprctl hyprpaper preload "$p" >/dev/null 2>&1
        try hyprctl hyprpaper wallpaper ",$p"
      else FB="${ERR}✗ need swww or hyprpaper${RST}"; return 1; fi ;;
    *)
      try feh --bg-fill "$p" ;;
  esac
  state_set wallpaper "$p"
}
set_kde_colorscheme(){ try plasma-apply-colorscheme "$1" && state_set kde_colorscheme "$1"; }
set_kde_lookandfeel(){ try plasma-apply-lookandfeel -a "$1" && state_set kde_lookandfeel "$1"; }

# ══════════════════════════ terminal color schemes ══════════════════════════
# format: bg fg color0..color15 (hex, no #)
declare -A SCHEMES
SCHEMES[catppuccin-mocha]="1e1e2e cdd6f4 45475a f38ba8 a6e3a1 f9e2af 89b4fa f5c2e7 94e2d5 bac2de 585b70 f38ba8 a6e3a1 f9e2af 89b4fa f5c2e7 94e2d5 a6adc8"
SCHEMES[gruvbox-dark]="282828 ebdbb2 282828 cc241d 98971a d79921 458588 b16286 689d6a a89984 928374 fb4934 b8bb26 fabd2f 83a598 d3869b 8ec07c ebdbb2"
SCHEMES[nord]="2e3440 d8dee9 3b4252 bf616a a3be8c ebcb8b 81a1c1 b48ead 88c0d0 e5e9f0 4c566a bf616a a3be8c ebcb8b 81a1c1 b48ead 8fbcbb eceff4"
SCHEMES[tokyo-night]="1a1b26 c0caf5 15161e f7768e 9ece6a e0af68 7aa2f7 bb9af7 7dcfff a9b1d6 414868 f7768e 9ece6a e0af68 7aa2f7 bb9af7 7dcfff c0caf5"
SCHEMES[dracula]="282a36 f8f8f2 21222c ff5555 50fa7b f1fa8c bd93f9 ff79c6 8be9fd f8f8f2 6272a4 ff6e6e 69ff94 ffffa5 d6acff ff92df a4ffff ffffff"
# persisted wallpaper-generated scheme (see Wallpaper magic)
[[ -f "$CONFIG_DIR/wallgen.scheme" ]] && SCHEMES[wallpaper-gen]=$(< "$CONFIG_DIR/wallgen.scheme")

h2rgb(){ printf '%d,%d,%d' "0x${1:0:2}" "0x${1:2:2}" "0x${1:4:2}"; }

scheme_picker(){ # → PICK (clean name), swatches in menu + rendered terminal mock below
  local labels=() n C i sw
  SCHEME_NAMES=()
  while IFS= read -r n; do SCHEME_NAMES+=("$n"); done < <(printf '%s\n' "${!SCHEMES[@]}" | sort)
  for n in "${SCHEME_NAMES[@]}"; do
    read -r -a C <<< "${SCHEMES[$n]}"
    sw=""
    for i in 3 4 5 6 7 8 9; do sw+="$(fgc "${C[i]}")██"; done
    labels+=("$(pad "$n" 18) ${sw}${E39}")
  done
  PV_FN=scheme_pv PV_H=6 menu "Color scheme" "exact preview below — rendered in the scheme's colors" "${labels[@]}" || return 1
  PICK=${SCHEME_NAMES[MENU_IDX]}
}

apply_term_scheme(){
  local name=$1 applied=() C bg fg pal i
  read -r -a C <<< "${SCHEMES[$name]}"
  bg=${C[0]}; fg=${C[1]}; pal=("${C[@]:2:16}")
  local cfg="${XDG_CONFIG_HOME:-$HOME/.config}"

  if command -v alacritty >/dev/null 2>&1; then
    mkdir -p "$cfg/alacritty/themes"
    {
      echo '[colors.primary]'
      echo "background = \"#$bg\""
      echo "foreground = \"#$fg\""
      echo '[colors.normal]'
      local names=(black red green yellow blue magenta cyan white)
      for i in {0..7}; do echo "${names[i]} = \"#${pal[i]}\""; done
      echo '[colors.bright]'
      for i in {0..7}; do echo "${names[i]} = \"#${pal[i+8]}\""; done
    } > "$cfg/alacritty/themes/current.toml"
    if [[ ! -f $cfg/alacritty/alacritty.toml ]]; then
      printf '[general]\nimport = ["~/.config/alacritty/themes/current.toml"]\n' > "$cfg/alacritty/alacritty.toml"
    elif ! grep -q 'themes/current.toml' "$cfg/alacritty/alacritty.toml"; then
      applied+=("alacritty: add import of themes/current.toml manually")
    fi
    applied+=(alacritty)
  fi

  if command -v kitty >/dev/null 2>&1; then
    mkdir -p "$cfg/kitty"
    {
      echo "background #$bg"
      echo "foreground #$fg"
      for i in {0..15}; do echo "color$i #${pal[i]}"; done
    } > "$cfg/kitty/current-theme.conf"
    touch "$cfg/kitty/kitty.conf"
    grep -q '^include current-theme.conf' "$cfg/kitty/kitty.conf" \
      || printf '\ninclude current-theme.conf\n' >> "$cfg/kitty/kitty.conf"
    applied+=(kitty)
  fi

  if command -v foot >/dev/null 2>&1; then
    mkdir -p "$cfg/foot"
    {
      echo '[colors]'
      echo "background=$bg"
      echo "foreground=$fg"
      for i in {0..7}; do echo "regular$i=${pal[i]}"; done
      for i in {0..7}; do echo "bright$i=${pal[i+8]}"; done
    } > "$cfg/foot/adrice-theme.ini"
    touch "$cfg/foot/foot.ini"
    grep -q 'adrice-theme.ini' "$cfg/foot/foot.ini" \
      || sed -i "1i include=$cfg/foot/adrice-theme.ini" "$cfg/foot/foot.ini"
    applied+=(foot)
  fi

  if command -v gnome-terminal >/dev/null 2>&1; then
    local uuid base palstr=""
    uuid=$(gget org.gnome.Terminal.ProfilesList default)
    if [[ -n $uuid ]]; then
      base="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$uuid/"
      for i in {0..15}; do palstr+="'#${pal[i]}', "; done
      palstr="[${palstr%, }]"
      gsettings set "$base" use-theme-colors false
      gsettings set "$base" background-color "#$bg"
      gsettings set "$base" foreground-color "#$fg"
      gsettings set "$base" palette "$palstr"
      applied+=(gnome-terminal)
    fi
  fi

  if command -v konsole >/dev/null 2>&1; then
    local kdir="$HOME/.local/share/konsole"; mkdir -p "$kdir"
    {
      printf '[Background]\nColor=%s\n' "$(h2rgb "$bg")"
      printf '[BackgroundIntense]\nColor=%s\n' "$(h2rgb "$bg")"
      printf '[Foreground]\nColor=%s\n' "$(h2rgb "$fg")"
      printf '[ForegroundIntense]\nColor=%s\n' "$(h2rgb "$fg")"
      for i in {0..7}; do
        printf '[Color%d]\nColor=%s\n' "$i" "$(h2rgb "${pal[i]}")"
        printf '[Color%dIntense]\nColor=%s\n' "$i" "$(h2rgb "${pal[i+8]}")"
      done
      printf '[General]\nDescription=adrice %s\nOpacity=1\n' "$name"
    } > "$kdir/adrice-$name.colorscheme"
    local prof; prof=$(kr --file konsolerc --group 'Desktop Entry' --key DefaultProfile 2>/dev/null)
    [[ -n $prof && -f $kdir/$prof ]] \
      && kw --file "$kdir/$prof" --group Appearance --key ColorScheme "adrice-$name"
    applied+=(konsole)
  fi

  state_set term_scheme "$name"
  if (( ${#applied[@]} )); then
    local msg="${OK}✓ ${BOLD}$name${RST}${OK} →${RST} " a
    for a in "${applied[@]}"; do msg+="\n   ${MUT}· $a${RST}"; done
    notify "$msg\n\n${MUT}restart open terminals to see it${RST}"
  else
    notify "${WARN}⚠ no supported terminal found${RST}\n${MUT}supported: alacritty · kitty · foot · gnome-terminal · konsole${RST}"
  fi
}

# ══════════════════════════ starship presets ══════════════════════════
apply_starship(){
  local preset=$1 f="${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml"
  command -v starship >/dev/null 2>&1 \
    || { notify "${WARN}⚠ starship not installed${RST}\n${MUT}curl -sS https://starship.rs/install.sh | sh${RST}"; return; }
  [[ -f $f ]] && cp "$f" "$f.bak"
  case $preset in
    minimal) cat > "$f" <<'EOF'
add_newline = false
format = "$directory$git_branch$git_status$character"
[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"
[directory]
style = "bold blue"
truncation_length = 3
[git_branch]
format = "[$branch]($style) "
style = "dimmed white"
[git_status]
format = "[$all_status$ahead_behind]($style) "
style = "dimmed yellow"
EOF
    ;;
    full) cat > "$f" <<'EOF'
add_newline = true
format = "$username$hostname$directory$git_branch$git_status$rust$nodejs$python$cmd_duration$line_break$character"
[character]
success_symbol = "[➜](bold green)"
error_symbol = "[➜](bold red)"
[directory]
style = "bold cyan"
truncation_length = 4
[cmd_duration]
min_time = 500
format = "[$duration]($style) "
style = "yellow"
[rust]
format = "[$symbol$version]($style) "
[nodejs]
format = "[$symbol$version]($style) "
[python]
format = "[$symbol$version]($style) "
EOF
    ;;
    plain) cat > "$f" <<'EOF'
add_newline = false
format = "$directory$character"
[character]
success_symbol = "[\\$](white)"
error_symbol = "[\\$](red)"
[directory]
style = "white"
truncation_length = 2
EOF
    ;;
  esac
  state_set starship "$preset"
  local rc sh hint=""
  for rc in "$HOME/.bashrc:bash" "$HOME/.zshrc:zsh"; do
    sh=${rc#*:}; rc=${rc%%:*}
    [[ -f $rc ]] && ! grep -q 'starship init' "$rc" \
      && hint+="\n${MUT}add to ${rc##*/}: eval \"\$(starship init $sh)\"${RST}"
  done
  notify "${OK}✓ starship preset ${BOLD}$preset${RST}${OK} written${RST}\n${MUT}old config → starship.toml.bak${RST}$hint"
}

# ══════════════════════════ hyprland deep config ══════════════════════════
HYPR_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/adrice.conf"
hypr_apply(){
  try hyprctl keyword "$1" "$2" || return 1
  mkdir -p "$(dirname "$HYPR_FILE")"; touch "$HYPR_FILE"
  sed -i "\|^$1 *=|d" "$HYPR_FILE"
  printf '%s = %s\n' "$1" "$2" >> "$HYPR_FILE"
  local main="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.conf"
  [[ -f $main ]] && ! grep -q 'adrice.conf' "$main" \
    && printf '\nsource = ~/.config/hypr/adrice.conf\n' >> "$main"
}
hypr_menu(){
  while :; do
    menu "Hyprland" "runtime via hyprctl + persisted to hypr/adrice.conf" \
      "Inner gaps" "Outer gaps" "Corner rounding" "Border size" \
      "Active border color" "Blur" "Animations" || return
    local keep=$MENU_IDX
    case $MENU_IDX in
      0) ask "inner gaps (px):" 5 && { hypr_apply general:gaps_in "$REPLY"; notify "$FB"; } ;;
      1) ask "outer gaps (px):" 10 && { hypr_apply general:gaps_out "$REPLY"; notify "$FB"; } ;;
      2) ask "rounding (px):" 8 && { hypr_apply decoration:rounding "$REPLY"; notify "$FB"; } ;;
      3) ask "border size (px):" 2 && { hypr_apply general:border_size "$REPLY"; notify "$FB"; } ;;
      4) ask "hex color:" 89b4fa && { hypr_apply "general:col.active_border" "rgb($REPLY)"; notify "$FB"; } ;;
      5) menu "Blur" "" "enable" "disable" \
           && { hypr_apply decoration:blur:enabled "$( ((MENU_IDX==0)) && echo true || echo false )"; notify "$FB"; } ;;
      6) menu "Animations" "" "enable" "disable" \
           && { hypr_apply animations:enabled "$( ((MENU_IDX==0)) && echo true || echo false )"; notify "$FB"; } ;;
    esac
    MENU_START=$keep
  done
}

# ══════════════════════════ behavior toggles ══════════════════════════
GNOME_TOGGLES=(
  "Animations|org.gnome.desktop.interface|enable-animations"
  "Hot corner|org.gnome.desktop.interface|enable-hot-corners"
  "Night light|org.gnome.settings-daemon.plugins.color|night-light-enabled"
  "Tap to click|org.gnome.desktop.peripherals.touchpad|tap-to-click"
  "Battery percentage|org.gnome.desktop.interface|show-battery-percentage"
  "Clock: weekday|org.gnome.desktop.interface|clock-show-weekday"
  "Clock: seconds|org.gnome.desktop.interface|clock-show-seconds"
  "Center new windows|org.gnome.mutter|center-new-windows"
  "Attach modal dialogs|org.gnome.mutter|attach-modal-dialogs"
)
behavior_menu(){
  case $DE in
    gnome)
      command -v gsettings >/dev/null 2>&1 || { notify "${ERR}✗ gsettings not found${RST}"; return; }
      local t items label schema key cur sel=0
      while :; do
        items=()
        for t in "${GNOME_TOGGLES[@]}"; do
          IFS='|' read -r label schema key <<< "$t"
          cur=$(gget "$schema" "$key")
          if [[ $cur == true ]]; then items+=("$(pad "$label" 24) ${OK}◉ on${E39}")
          else items+=("$(pad "$label" 24) ${MUT}○ off${E39}"); fi
        done
        MENU_START=$sel
        menu "Behavior & Tweaks" "⏎ toggles instantly" "${items[@]}" || return
        sel=$MENU_IDX
        IFS='|' read -r label schema key <<< "${GNOME_TOGGLES[sel]}"
        cur=$(gget "$schema" "$key")
        if [[ $cur == true ]]; then gsettings set "$schema" "$key" false 2>/dev/null
        else gsettings set "$schema" "$key" true 2>/dev/null; fi
      done ;;
    kde)
      while :; do
        menu "Behavior & Tweaks" "KDE" \
          "Animation speed" "Single click opens files: on" "Single click opens files: off" \
          "Night color: on" "Night color: off" || return
        local keep=$MENU_IDX
        case $MENU_IDX in
          0) ask "animation duration factor (0 = instant, 1 = default):" 0.5 \
               && try kw --file kdeglobals --group KDE --key AnimationDurationFactor "$REPLY" ;;
          1) try kw --file kdeglobals --group KDE --key SingleClick true ;;
          2) try kw --file kdeglobals --group KDE --key SingleClick false ;;
          3) try kw --file kwinrc --group NightColor --key Active true ;;
          4) try kw --file kwinrc --group NightColor --key Active false ;;
        esac
        command -v qdbus >/dev/null 2>&1 && qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1
        notify "$FB\n${MUT}some changes need re-login${RST}"
        MENU_START=$keep
      done ;;
    hyprland) hypr_menu ;;
    *) notify "${WARN}⚠ no behavior backend for '$DE_LABEL'${RST}" ;;
  esac
}

# ══════════════════════════ appearance menu ══════════════════════════
appearance_menu(){
  while :; do
    local items=() actions=()
    case $DE in
      kde)
        items=("Global theme (look & feel)" "Color scheme" "Icon theme" "Cursor theme" "Font" "Wallpaper")
        actions=(lnf kcs icons cursor font wall) ;;
      *)
        items=("GTK theme" "Icon theme" "Cursor theme" "Dark / Light" "Accent color" "Interface font" "Monospace font" "Wallpaper")
        actions=(gtk icons cursor dl accent font mono wall) ;;
    esac
    menu "Appearance" "backend: $DE_LABEL ${C_BRD}·${MUT} everything previews live on your desktop" "${items[@]}" || return
    local a=${actions[MENU_IDX]} keep=$MENU_IDX cur
    case $a in
      gtk)    cur=$(current_of gtk)
              PV_FN=gtk_pv PV_H=5 pick_live "GTK theme" "install themes via 'Get themes'" \
                set_gtk_theme "$cur" < <(list_gtk_themes) \
                && { set_gtk_theme "$PICK"; log_change gtk_theme "$cur" "$PICK"; notify "$FB"; } ;;
      lnf)    pick_from "Global theme" "looked in plasma/look-and-feel dirs" < <(list_kde_lookandfeel) \
                && { set_kde_lookandfeel "$PICK"; notify "$FB"; } ;;
      kcs)    cur=$(current_of kcs)
              pick_live "Color scheme" "looked in color-schemes dirs" \
                set_kde_colorscheme "$cur" < <(list_kde_colorschemes) \
                && { set_kde_colorscheme "$PICK"; log_change kde_colorscheme "$cur" "$PICK"; notify "$FB"; } ;;
      icons)  cur=$(current_of icons)
              pick_live "Icon theme" "install icon packs via 'Get themes'" \
                set_icon_theme "$cur" < <(list_icon_themes) \
                && { set_icon_theme "$PICK"; log_change icon_theme "$cur" "$PICK"; notify "$FB"; } ;;
      cursor) cur=$(current_of cursor)
              pick_live "Cursor theme" "install cursors via 'Get themes'" \
                set_cursor_theme "$cur" < <(list_cursor_themes) \
                && { set_cursor_theme "$PICK"; log_change cursor_theme "$cur" "$PICK"; notify "$FB"; } ;;
      dl)     cur=$(current_of dl)
              pick_live "Color scheme" "" set_color_scheme "$cur" < <(printf 'dark\nlight\n') \
                && { set_color_scheme "$PICK"; log_change color_scheme "$cur" "$PICK"; notify "$FB"; } ;;
      accent) cur=$(current_of accent)
              pick_live "Accent color" "GNOME 47+" set_accent "$cur" \
                < <(printf '%s\n' blue teal green yellow orange red pink purple slate) \
                && { set_accent "$PICK"; log_change accent "$cur" "$PICK"; notify "$FB"; } ;;
      font)   font_picker iface ;;
      mono)   font_picker mono ;;
      wall)   wallpaper_picker ;;
    esac
    MENU_START=$keep
  done
}

# ══════════════════════════ terminal menu ══════════════════════════
terminal_menu(){
  while :; do
    menu "Terminal & Shell" "" \
      "Color scheme ${MUT}→ all installed terminals${E39}" \
      "Starship prompt ${MUT}minimal${E39}" \
      "Starship prompt ${MUT}full${E39}" \
      "Starship prompt ${MUT}plain${E39}" \
      "Fastfetch config ${MUT}minimal${E39}" \
      "Fastfetch config ${MUT}rice · nerd font${E39}" \
      "Fastfetch config ${MUT}full${E39}" || return
    local keep=$MENU_IDX old sp
    case $MENU_IDX in
      0) old=$(state_get term_scheme)
         scheme_picker && { apply_term_scheme "$PICK"; log_change term_scheme "$old" "$PICK"; } ;;
      1|2|3) local presets=(minimal full plain); sp=${presets[MENU_IDX-1]}
         old=$(state_get starship)
         apply_starship "$sp"
         log_change starship "$old" "$sp" ;;
      4) apply_fastfetch minimal ;;
      5) apply_fastfetch rice ;;
      6) apply_fastfetch full ;;
    esac
    MENU_START=$keep
  done
}

# ══════════════════════════ profiles ══════════════════════════
profile_snapshot(){
  case $DE in
    gnome)
      echo "gtk_theme=$(gget org.gnome.desktop.interface gtk-theme)"
      echo "icon_theme=$(gget org.gnome.desktop.interface icon-theme)"
      echo "cursor_theme=$(gget org.gnome.desktop.interface cursor-theme)"
      echo "font=$(gget org.gnome.desktop.interface font-name)"
      echo "mono_font=$(gget org.gnome.desktop.interface monospace-font-name)"
      local cs; cs=$(gget org.gnome.desktop.interface color-scheme)
      echo "color_scheme=$([[ $cs == prefer-dark ]] && echo dark || echo light)"
      local ac; ac=$(gget org.gnome.desktop.interface accent-color); [[ -n $ac ]] && echo "accent=$ac"
      local wp; wp=$(gget org.gnome.desktop.background picture-uri); echo "wallpaper=${wp#file://}"
      ;;
    kde)
      echo "icon_theme=$(kr --file kdeglobals --group Icons --key Theme 2>/dev/null)"
      echo "kde_colorscheme=$(kr --file kdeglobals --group General --key ColorScheme 2>/dev/null)"
      local k v
      for k in kde_lookandfeel cursor_theme wallpaper; do
        v=$(state_get $k); [[ -n $v ]] && echo "$k=$v"
      done
      ;;
    *)
      local k v
      for k in gtk_theme icon_theme cursor_theme font wallpaper; do
        v=$(state_get $k); [[ -n $v ]] && echo "$k=$v"
      done
      ;;
  esac
  local ts; ts=$(state_get term_scheme); [[ -n $ts ]] && echo "term_scheme=$ts"
  local sp; sp=$(state_get starship);    [[ -n $sp ]] && echo "starship=$sp"
  echo "de=$DE"
}
profile_save(){
  profile_snapshot | grep -v '=$' > "$PROFILE_DIR/$1.profile"
  echo "saved: $PROFILE_DIR/$1.profile"
}
profile_apply(){
  local f="$PROFILE_DIR/$1.profile"
  [[ -f $f ]] || { echo "profile not found: $1" >&2; return 1; }
  local key val QUIET=1
  while IFS='=' read -r key val; do
    [[ -z $key || -z $val ]] && continue
    apply_kv "$key" "$val"
  done < "$f"
  echo "applied profile: $1"
}
profiles_menu(){
  while :; do
    local profs=() p
    while IFS= read -r p; do profs+=("${p%.profile}"); done \
      < <(find "$PROFILE_DIR" -maxdepth 1 -name '*.profile' -printf '%f\n' 2>/dev/null | sort)
    menu "Profiles" "${#profs[@]} saved ${C_BRD}·${MUT} ~/.config/adrice/profiles" \
      "Save current look as profile" "Apply profile" "Show profile" "Delete profile" \
      "Export profile ${MUT}shareable tar with themes + wallpaper${E39}" \
      "Import profile ${MUT}from tar${E39}" || return
    local keep=$MENU_IDX out
    case $MENU_IDX in
      0) ask "profile name:" "" && { profile_save "$REPLY" >/dev/null; notify "${OK}✓ saved ${BOLD}$REPLY${RST}"; } ;;
      1) if (( ${#profs[@]} )); then
           menu "Apply" "" "${profs[@]}" && { profile_apply "${profs[MENU_IDX]}" >/dev/null; notify "${OK}✓ applied${RST}"; }
         else notify "${WARN}⚠ no profiles yet${RST}"; fi ;;
      2) if (( ${#profs[@]} )); then
           menu "Show" "" "${profs[@]}" && notify "$(sed "s/^/${MUT}/;s/=/${E39} = ${MUT}/" "$PROFILE_DIR/${profs[MENU_IDX]}.profile")"
         else notify "${WARN}⚠ no profiles yet${RST}"; fi ;;
      3) if (( ${#profs[@]} )); then
           menu "Delete" "" "${profs[@]}" && { rm -f "$PROFILE_DIR/${profs[MENU_IDX]}.profile"; notify "${OK}✓ deleted${RST}"; }
         else notify "${WARN}⚠ no profiles yet${RST}"; fi ;;
      4) if (( ${#profs[@]} )); then
           menu "Export" "" "${profs[@]}" && {
             working "packing profile + themes + wallpaper …"
             out=$(profile_export "${profs[MENU_IDX]}" 2>/dev/null) \
               && notify "${OK}✓ exported${RST}\n${MUT}${out/#$HOME/\~}${E39}\n${MUT}import on another machine: adrice import <file>${E39}" \
               || notify "${ERR}✗ export failed${RST}"
           }
         else notify "${WARN}⚠ no profiles yet${RST}"; fi ;;
      5) ask "path to adrice-*.tar.gz:" "" && {
           out=$(profile_import "$REPLY" 2>/dev/null) \
             && notify "${OK}✓ imported as ${BOLD}$out${RST}\n${MUT}activate via 'Apply profile'${E39}" \
             || notify "${ERR}✗ import failed — not a adrice export?${RST}"
         } ;;
    esac
    MENU_START=$keep
  done
}

# ══════════════════════════ info ══════════════════════════
info_screen(){
  HDR_MODE=small; cls; header; setw
  box_top "System info"
  box_row
  box_row "  ${MUT}desktop${E39}     ${BOLD}$DE_LABEL${RST}  ${MUT}(backend: $DE)${E39}"
  box_row "  ${MUT}session${E39}     ${XDG_SESSION_TYPE:-?}"
  box_row "  ${MUT}config${E39}      ~/.config/adrice"
  box_row
  local t line=""
  box_row "  ${MUT}terminals${E39}"
  for t in alacritty kitty foot gnome-terminal konsole wezterm; do
    if command -v "$t" >/dev/null 2>&1; then line+="${OK}✓${E39} $t   "; else line+="${MUT}✗ $t${E39}   "; fi
  done
  box_row "  $line"
  line=""
  box_row "  ${MUT}backend tools${E39}"
  for t in gsettings kwriteconfig6 hyprctl xfconf-query starship; do
    if command -v "$t" >/dev/null 2>&1; then line+="${OK}✓${E39} $t   "; else line+="${MUT}✗ $t${E39}   "; fi
  done
  box_row "  $line"
  box_row
  box_bot
  printf '\n   %s %s%s%s\n' "$(chip 'any key')" "$MUT" "continue" "$RST"
  read_key >/dev/null
}

# ══════════════════════════ main ══════════════════════════
main_menu(){
  [[ -f $PROFILE_DIR/_original.profile ]] || profile_save _original >/dev/null 2>&1
  UNDO_HOOK=undo_last
  tui_on
  while :; do
    local items=(
      "${C_ACC}◈${E39} Appearance"
      "${C_MAU}▤${E39} Terminal & Shell"
      "${C_PNK}✦${E39} Behavior & Tweaks"
    )
    local map=(appearance terminal behavior)
    if [[ $DE == hyprland ]]; then
      items+=("${C_ACC}⬡${E39} Hyprland deep config"); map+=(hypr)
    fi
    items+=(
      "${C_PNK}★${E39} Wallpaper magic ${MUT}full theme from any image${E39}"
      "${C_PNK}❖${E39} Rice presets ${MUT}full looks · random${E39}"
      "${C_MAU}⇣${E39} Get themes & fonts ${MUT}download packs${E39}"
    )
    map+=(magic presets getthemes)
    if [[ $DE == gnome ]]; then
      items+=("${C_ACC}⚙${E39} GNOME Extensions"); map+=(ext)
    fi
    items+=(
      "${WARN}☀${E39} Auto day / night ${MUT}timed profiles${E39}"
      "${OK}✚${E39} Doctor & sync ${MUT}flatpak · apps · diagnose${E39}"
      "${OK}▣${E39} Profiles ${MUT}save · apply · export${E39}"
      "${WARN}↶${E39} Undo / History"
      "${WARN}✱${E39} System info"
      "${MUT}✕ Quit${E39}"
    )
    map+=(auto fix profiles history info quit)
    HDR_MODE=big
    menu "Main" "" "${items[@]}" || { tui_off; exit 0; }
    local keep=$MENU_IDX
    HDR_MODE=small
    case ${map[MENU_IDX]} in
      appearance) appearance_menu ;;
      terminal)   terminal_menu ;;
      behavior)   behavior_menu ;;
      hypr)       hypr_menu ;;
      magic)      magic_menu ;;
      getthemes)  themes_menu ;;
      presets)    preset_menu ;;
      ext)        ext_menu ;;
      auto)       autotheme_menu ;;
      fix)        fix_menu ;;
      profiles)   profiles_menu ;;
      history)    history_menu ;;
      info)       info_screen ;;
      quit)       tui_off; exit 0 ;;
    esac
    MENU_START=$keep
  done
}

detect_de
build_headers
case ${1:-} in
  -h|--help)
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  list)
    find "$PROFILE_DIR" -maxdepth 1 -name '*.profile' -printf '%f\n' 2>/dev/null | sed 's/\.profile$//' | sort; exit 0 ;;
  save)
    [[ -n ${2:-} ]] || { echo "usage: $0 save NAME" >&2; exit 1; }
    profile_save "$2"; exit 0 ;;
  apply)
    [[ -n ${2:-} ]] || { echo "usage: $0 apply NAME" >&2; exit 1; }
    profile_apply "$2"; exit $? ;;
  undo)
    if [[ -s $HIST_FILE ]]; then
      IFS='|' read -r _ ukey uold unew <<< "$(tail -1 "$HIST_FILE")"
      QUIET=1 && apply_kv "$ukey" "$uold"; QUIET=0
      sed -i '$d' "$HIST_FILE"
      echo "undid $ukey: $unew → $uold"
    else echo "nothing to undo"; fi
    exit 0 ;;
  export)
    [[ -n ${2:-} ]] || { echo "usage: $0 export NAME" >&2; exit 1; }
    out=$(profile_export "$2") && echo "exported: $out"; exit $? ;;
  import)
    [[ -n ${2:-} ]] || { echo "usage: $0 import FILE|URL" >&2; exit 1; }
    n=$(profile_import "$2") && echo "imported as profile: $n  (activate: $0 apply $n)"; exit $? ;;
  magic)
    [[ -f ${2:-} ]] || { echo "usage: $0 magic IMAGE" >&2; exit 1; }
    wallgen_build "$2" || { echo "color extraction failed — is imagemagick installed?" >&2; exit 1; }
    QUIET=1
    set_wallpaper "$2" >/dev/null 2>&1
    apply_term_scheme wallpaper-gen
    set_color_scheme dark >/dev/null 2>&1
    set_accent "$WALLGEN_ACCENT" >/dev/null 2>&1
    [[ $DE == hyprland ]] && hypr_apply "general:col.active_border" "rgb($WALLGEN_PRIMARY)" >/dev/null 2>&1
    QUIET=0
    echo "generated + applied full theme from $2 (accent: $WALLGEN_ACCENT)"
    exit 0 ;;
  doctor)
    printf '%b\n' "$(doctor_report)"; exit 0 ;;
  '') [[ -t 0 && -t 1 ]] || { echo "adrice: interactive mode needs a terminal" >&2; exit 1; }
      main_menu ;;
  *)  echo "unknown command: $1 (see --help)" >&2; exit 1 ;;
esac
