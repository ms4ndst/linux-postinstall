#!/usr/bin/env bash
# ============================================================================
# NixOS post-install — declarative port of post-install-fedora.sh
# ============================================================================
# Unlike the dnf/zypper/dnf5/pacman scripts, NixOS doesn't install packages
# imperatively into a mutable system. Instead this script maintains a single
# generated module, /etc/nixos/postinstall.nix, listing every category you
# picked (as environment.systemPackages plus the services/programs those
# categories need), imports it into your configuration, and runs
# `nixos-rebuild switch`. Re-running a category adds to that module and
# rebuilds again - so the result is reproducible, rolls back with the normal
# NixOS generation mechanism, and survives future rebuilds. Nothing is
# installed outside the Nix store.
#
# Supports both classic channels (/etc/nixos/configuration.nix) and flakes
# (/etc/nixos/flake.nix) - it detects which you use and wires the import in
# the right place, or prints the one line to add if it can't do it safely.
#
# Targets nixpkgs nixos-26.05 (the current stable). A handful of items the
# other scripts install from vendor repos aren't in nixpkgs or need unfree/
# flake sources; those are reported, never silently dropped.
# ============================================================================
set -uo pipefail

# ----------------------------------------------------------------------------
# Paths & state
# ----------------------------------------------------------------------------
NIXOS_DIR="/etc/nixos"
MODULE="$NIXOS_DIR/postinstall.nix"
RICE_MODULE="$NIXOS_DIR/rice.nix"
# The chosen categories persist here between runs, so the generated module
# can be rebuilt from scratch every time (the Nix way: the module is a pure
# function of this selection, never edited in place).
STATE_DIR="/var/lib/nixos-postinstall"
SELECTION="$STATE_DIR/selection"

C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_BLUE=$'\e[1;34m'; C_GREEN=$'\e[1;32m'
C_YELLOW=$'\e[1;33m'; C_RED=$'\e[1;31m'; C_CYAN=$'\e[1;36m'; C_MAGENTA=$'\e[1;35m'

log()     { echo -e "${C_BLUE}[nixos-setup]${C_RESET} $*"; }
success() { echo -e "${C_GREEN}[nixos-setup]${C_RESET} $*"; }
warn()    { echo -e "${C_YELLOW}[nixos-setup]${C_RESET} $*"; }
err()     { echo -e "${C_RED}[nixos-setup]${C_RESET} $*" >&2; }
note()    { echo -e "${C_CYAN}[nixos-setup]${C_RESET} $*"; }

# ----------------------------------------------------------------------------
# Preconditions
# ----------------------------------------------------------------------------
if [ ! -e /etc/NIXOS ] && ! command -v nixos-rebuild >/dev/null 2>&1; then
  err "This script targets NixOS (no /etc/NIXOS and no nixos-rebuild). Aborting."
  exit 1
fi

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
  command -v sudo >/dev/null 2>&1 || { err "Not root and sudo not found. Re-run as root."; exit 1; }
fi

# The desktop user whose home the GUI tweaks/dotfiles belong to (not root,
# even when this runs under sudo).
DESKTOP_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}"
DESKTOP_HOME="$(getent passwd "$DESKTOP_USER" | cut -d: -f6)"
[ -z "$DESKTOP_HOME" ] && DESKTOP_HOME="$HOME"

$SUDO mkdir -p "$STATE_DIR"
[ -f "$SELECTION" ] || $SUDO touch "$SELECTION"

# ----------------------------------------------------------------------------
# Flakes vs channels detection
# ----------------------------------------------------------------------------
# Three cases:
#   - flake.nix present  -> flakes; the user adds the import to their modules
#     list (we can't safely rewrite an arbitrary flake), we print the line
#   - configuration.nix  -> channels; we add `./postinstall.nix` to its
#     imports = [ ... ] list automatically if it isn't already there
USE_FLAKES=0
CONFIG_NIX="$NIXOS_DIR/configuration.nix"
if [ -f "$NIXOS_DIR/flake.nix" ]; then
  USE_FLAKES=1
fi

# unfree packages (vscode, discord, spotify, 1password, teams, steam, nvidia,
# vivaldi, edge, cursor, ...) need this; the module sets it per-package via
# allowUnfreePredicate, but the user's own nixpkgs.config must also allow it
# at eval time for a channels setup. We set nixpkgs.config.allowUnfree in the
# module itself, which covers the channels case.

# ----------------------------------------------------------------------------
# Selection helpers - the selection file holds one "group" token per line,
# e.g. "pkgs:code-editors" or "svc:docker" or "opt:steam". generate_module()
# turns the whole set into one .nix file.
# ----------------------------------------------------------------------------
select_add() {  # select_add <token...>
  local tok tmp
  tmp="$($SUDO cat "$SELECTION")"
  for tok in "$@"; do
    printf '%s\n' "$tmp" | grep -qxF "$tok" || tmp="$tmp"$'\n'"$tok"
  done
  printf '%s\n' "$tmp" | grep -v '^$' | sort -u | $SUDO tee "$SELECTION" >/dev/null
}

selected() {  # selected <token>
  $SUDO grep -qxF "$1" "$SELECTION" 2>/dev/null
}

# ----------------------------------------------------------------------------
# Category -> nixpkgs attrs. Each PKGS_<name> is the list of attribute paths
# (verified against nixos-26.05). Vendor/unpackaged items are listed in
# NOTE_<name> and reported instead of installed.
# ----------------------------------------------------------------------------
declare -A PKGS NOTES SVCS

PKGS[code-editors]="vim neovim emacs nano geany gnome-text-editor gedit kdePackages.kate"
NOTES[code-editors]="ttt (terminal IDE, github.com/eugenioenko/ttt) is not in nixpkgs - try it with 'nix run github:eugenioenko/ttt', or add that flake as an input and include ttt.packages.\${system}.default in your systemPackages"
PKGS[python]="python3 python3Packages.pip python3Packages.virtualenv python3Packages.ipython pipx"
PKGS[web-dev]="nginx apacheHttpd php phpPackages.composer"
PKGS[nodejs]="nodejs"          # npm ships with nodejs
PKGS[java]="jdk gradle maven ant"
NOTES[java]="IntelliJ IDEA Community: jetbrains.idea-community (unfree)"
PKGS[c-cpp]="gcc clang cmake gnumake ninja ccache autoconf automake libtool bison flex gettext pkg-config cppcheck valgrind gdb ltrace strace"
PKGS[go]="go"
PKGS[rust]="rustc cargo rustup"
PKGS[php]="php phpPackages.composer"
PKGS[ruby]="ruby bundler"
PKGS[dotnet]="dotnetCorePackages.sdk_8_0 dotnetCorePackages.sdk_9_0 dotnetCorePackages.sdk_10_0"
PKGS[dev-tools]="jq tig subversion gnumake cmake autoconf automake bison flex gettext pkg-config man-pages less lazygit"
PKGS[databases]="mariadb sqlite sqlitebrowser memcached valkey postgresql dbeaver-bin"
SVCS[databases]="postgresql mysql"
PKGS[containers]="podman docker-compose distrobox qemu_kvm libvirt virt-manager virt-viewer gnome-boxes"
SVCS[containers]="libvirtd podman"
PKGS[gaming]="lutris gamemode mangohud protonup-qt"
SVCS[gaming]="steam"
PKGS[office]="libreoffice kdePackages.okular evince zathura pandoc"
PKGS[system-utils]="htop iotop sysstat glances nethogs iftop nload vnstat tcpdump wireshark lsof tmux screen zsh fish fzf ripgrep tree ncdu rsync unzip bat glow"
PKGS[android]="android-tools scrcpy fdroidcl"
PKGS[devops]="azure-cli rclone lazygit docker-compose"
PKGS[security]="nmap masscan nikto sqlmap gobuster whatweb wfuzz john hashcat thc-hydra aircrack-ng radare2 binwalk sleuthkit yara exiftool lynis clamav keepassxc"
NOTES[security]="chkrootkit and rkhunter are not in nixpkgs"
PKGS[security-defensive]="lynis aide suricata fail2ban clamav keepassxc wireguard-tools openvpn"
SVCS[security-defensive]="clamav fail2ban"
PKGS[windows]="wine winetricks zenity"
PKGS[creative-graphics]="nomacs flameshot imagemagick graphicsmagick optipng jpegoptim pngquant libwebp"
NOTES[creative-graphics]="greenshot for Linux (github.com/ms4ndst/greenshot_for_linux, the Wayland Greenshot port) is not in nixpkgs and publishes no binaries - build it from source with the .NET 10 SDK (e.g. nix-shell -p dotnetCorePackages.sdk_10_0 git, then: git clone https://github.com/ms4ndst/greenshot_for_linux && cd greenshot_for_linux && bash packaging/install.sh, which installs to ~/.local)"
PKGS[creative-video]="kdePackages.kdenlive shotcut obs-studio mkvtoolnix mpv vlc yt-dlp"
PKGS[creative-audio]="qjackctl pavucontrol soundconverter easytag"
PKGS[creative-photography]="darktable rawtherapee digikam hugin gthumb"
PKGS[creative-publishing]="scribus fontforge calibre"
PKGS[browsers]="brave vivaldi microsoft-edge google-chrome librewolf floorp-bin"
NOTES[browsers]="Zen Browser is a flake only (github:0xc000022070/zen-browser-flake), not in nixpkgs"
PKGS[communication]="discord telegram-desktop teams-for-linux signal-desktop slack"
PKGS[desktop-apps]="remmina spotify _1password-gui _1password-cli teamviewer"
PKGS[ai-tools]="ollama claude-code gemini-cli code-cursor zed-editor"
NOTES[ai-tools]="Antigravity/Vibe/OpenCode CLIs: official installers (not in nixpkgs); run them per the main README"
PKGS[gui-tools]="gnome-tweaks nautilus eog file-roller simple-scan gnome-screenshot gnome-system-monitor dconf-editor lxappearance"
PKGS[icon-sets]="papirus-icon-theme numix-icon-theme numix-icon-theme-circle adwaita-icon-theme"
PKGS[cursor-themes]="bibata-cursors"
PKGS[nerd-fonts]="nerd-fonts.jetbrains-mono nerd-fonts.fira-code jetbrains-mono fira-code"
PKGS[gtk-themes]="nordic colloid-gtk-theme catppuccin-gtk"
PKGS[printers]="cups hplip system-config-printer"
SVCS[printers]="printing"
PKGS[peripherals]="solaar"
SVCS[peripherals]="solaar"
PKGS[snapshots]="snapper btrfs-assistant timeshift"
SVCS[snapshots]="snapper"

# ----------------------------------------------------------------------------
# Module generation
# ----------------------------------------------------------------------------
# Collect every selected category's packages into one systemPackages list and
# turn the SVCS tokens into the matching NixOS service/program options. The
# module is self-contained and safe to import from either channels or flakes.
# Categories whose packages are FONTS - these must go in fonts.packages (so
# fontconfig registers them), not environment.systemPackages (which would
# install the files but leave apps unable to find them).
FONT_GROUPS=" nerd-fonts "

emit_pkgs() {
  local token group attr
  for token in $($SUDO grep '^pkgs:' "$SELECTION" 2>/dev/null | sed 's/^pkgs://'); do
    group="$token"
    case "$FONT_GROUPS" in *" $group "*) continue;; esac
    for attr in ${PKGS[$group]:-}; do
      printf '    %s\n' "$attr"
    done
  done | sort -u
}

emit_fonts() {
  local token group attr
  for token in $($SUDO grep '^pkgs:' "$SELECTION" 2>/dev/null | sed 's/^pkgs://'); do
    group="$token"
    case "$FONT_GROUPS" in *" $group "*) ;; *) continue;; esac
    for attr in ${PKGS[$group]:-}; do
      printf '    %s\n' "$attr"
    done
  done | sort -u
}

emit_services() {
  # Map SVCS tokens to real option blocks. Only emit a block once.
  local token svc seen=" "
  for token in $($SUDO grep '^pkgs:' "$SELECTION" 2>/dev/null | sed 's/^pkgs://'); do
    for svc in ${SVCS[$token]:-}; do
      case "$seen" in *" $svc "*) continue;; esac
      seen="$seen$svc "
      case "$svc" in
        docker)     printf '  virtualisation.docker.enable = true;\n';;
        podman)     printf '  virtualisation.podman.enable = true;\n  virtualisation.podman.dockerCompat = true;\n';;
        libvirtd)   printf '  virtualisation.libvirtd.enable = true;\n  programs.virt-manager.enable = true;\n';;
        steam)      printf '  programs.steam.enable = true;\n';;
        postgresql) printf '  services.postgresql.enable = true;\n';;
        mysql)      printf '  services.mysql.enable = true;\n  services.mysql.package = pkgs.mariadb;\n';;
        printing)   printf '  services.printing.enable = true;\n  services.printing.drivers = [ pkgs.hplip ];\n';;
        solaar)     printf '  hardware.logitech.wireless.enable = true;\n';;
        snapper)
          # Snapper's root config only makes sense on Btrfs (it snapshots a
          # subvolume). On anything else, enabling it would break activation,
          # so emit the service only on Btrfs - the snapper/timeshift packages
          # still install either way.
          if [ "$(findmnt -n -o FSTYPE / 2>/dev/null)" = btrfs ]; then
            printf '  services.snapper.configs.root = { SUBVOLUME = "/"; ALLOW_USERS = [ "%s" ]; };\n' "$DESKTOP_USER"
          else
            warn "Root filesystem isn't Btrfs - installing the snapshot tools but not enabling the snapper service (it needs a Btrfs subvolume)." >&2
          fi
          ;;
        clamav)     printf '  services.clamav.daemon.enable = true;\n  services.clamav.updater.enable = true;\n';;
        fail2ban)   printf '  services.fail2ban.enable = true;\n';;
      esac
    done
  done
}

generate_module() {
  log "Generating $MODULE from your selection..."
  local pkgs services fonts
  pkgs="$(emit_pkgs)"
  services="$(emit_services)"
  fonts="$(emit_fonts)"
  {
    cat <<'HEADER'
# Generated by post-install-nixos.sh - DO NOT EDIT BY HAND.
# Re-run the script to change the selection; it regenerates this whole file.
# Imported from configuration.nix (channels) or your flake's modules list.
{ config, pkgs, lib, ... }:

{
  # Several apps below (vscode, discord, spotify, 1password, teams, steam,
  # the nvidia driver, vivaldi, edge, cursor, ...) are unfree. Allowing them
  # here keeps the selection self-contained; remove this if you set
  # allowUnfree elsewhere.
  nixpkgs.config.allowUnfree = true;

  # Markdown terminal helpers (the shell scripts' md/mdb, which need `glow`
  # from System Utilities). Declarative here rather than editing ~/.bashrc:
  #   md <file>  - render + page a markdown file
  #   mdb [dir]  - glow's TUI markdown browser for a directory
  programs.bash.interactiveShellInit = ''
    md()  { glow -p "$@"; }
    mdb() { glow "''${1:-.}"; }
  '';

  environment.systemPackages = with pkgs; [
HEADER
    [ -n "$pkgs" ] && printf '%s\n' "$pkgs"
    cat <<'MID'
  ];

MID
    if [ -n "$fonts" ]; then
      printf '  fonts.packages = with pkgs; [\n%s\n  ];\n\n' "$fonts"
    fi
    [ -n "$services" ] && printf '%s\n' "$services"
    cat <<'FOOTER'
}
FOOTER
  } | $SUDO tee "$MODULE" >/dev/null
  success "Wrote $MODULE"
}

# ----------------------------------------------------------------------------
# Wire the module into the system config
# ----------------------------------------------------------------------------
ensure_import() {
  if [ "$USE_FLAKES" -eq 1 ]; then
    note "Flakes detected ($NIXOS_DIR/flake.nix)."
    note "Add the generated modules to your host's modules list, e.g.:"
    echo -e "    ${C_BOLD}modules = [ ./configuration.nix ./postinstall.nix ${SELECTION_HAS_RICE:+./rice.nix} ];${C_RESET}"
    note "(then this script's rebuild will pick them up)."
    return 0
  fi
  # Channels: splice ./postinstall.nix into configuration.nix's imports list
  # if it isn't already there. Done with a surgical awk pass, and only when
  # there's a plain `imports = [ ... ];` to extend.
  if ! [ -f "$CONFIG_NIX" ]; then
    warn "No $CONFIG_NIX found - add ./postinstall.nix to your imports manually."
    return 0
  fi
  if $SUDO grep -q 'postinstall.nix' "$CONFIG_NIX"; then
    return 0
  fi
  # The stock configuration.nix writes `imports =` and the opening `[` on
  # separate lines, so match the `imports =` line, then insert right after
  # the first following `[` (works whether it's same-line or next-line). A
  # fully-inline `imports = [ ... ];` (both brackets on one line) can't be
  # extended safely this way, so that case is left for the user. The result
  # is verified before it's written back - configuration.nix is never
  # corrupted by a failed splice.
  if $SUDO grep -qE '^[[:space:]]*imports[[:space:]]*=' "$CONFIG_NIX"; then
    local tmp; tmp="$(mktemp)"
    # Insert the path right after the first `[` that follows `imports =`.
    # Nix lists are whitespace-separated, so inserting a path immediately
    # after the opening bracket is valid for every layout - the stock
    # multiline form, `imports = [` with items below, and a compact
    # `[ ./x.nix ];` all on one line alike.
    $SUDO awk '
      !done && !arm && /^[[:space:]]*imports[[:space:]]*=/ { arm=1 }
      arm && !done && /\[/ { sub(/\[/, "[ ./postinstall.nix "); done=1; arm=0 }
      { print }
    ' "$CONFIG_NIX" > "$tmp"
    if grep -q 'postinstall.nix' "$tmp"; then
      $SUDO cp "$CONFIG_NIX" "$CONFIG_NIX.postinstall-bak"
      $SUDO cp "$tmp" "$CONFIG_NIX"; rm -f "$tmp"
      success "Added ./postinstall.nix to $CONFIG_NIX imports (backup: $CONFIG_NIX.postinstall-bak)."
    else
      rm -f "$tmp"
      warn "Couldn't safely edit the imports list in $CONFIG_NIX (unusual layout)."
      warn "Add this line inside your config's imports = [ ... ]; yourself:"
      echo -e "    ${C_BOLD}./postinstall.nix${C_RESET}"
    fi
  else
    warn "No 'imports = [ ... ];' found in $CONFIG_NIX."
    warn "Add this line inside your config's imports list yourself:"
    echo -e "    ${C_BOLD}./postinstall.nix${C_RESET}"
  fi
}

rebuild() {
  generate_module
  [ -f "$RICE_MODULE" ] && SELECTION_HAS_RICE=1
  ensure_import
  log "Running nixos-rebuild switch (this builds everything you selected)..."
  if $SUDO nixos-rebuild switch; then
    success "Rebuild complete. Your selection is live and rolls back via the boot menu."
  else
    err "nixos-rebuild failed. Your previous generation is untouched - fix the"
    err "error above (often an unfree/unpackaged item) and re-run. The generated"
    err "module is $MODULE; your selection is $SELECTION."
    return 1
  fi
}

# ----------------------------------------------------------------------------
# Category actions - each records the selection, reports notes, then rebuilds
# ----------------------------------------------------------------------------
apply_category() {  # apply_category <group> <label>
  local group="$1" label="$2"
  select_add "pkgs:$group"
  log "Added: $label"
  if [ -n "${NOTES[$group]:-}" ]; then
    note "Not installed automatically — ${NOTES[$group]}"
  fi
  rebuild
}

# ----------------------------------------------------------------------------
# TUI
# ----------------------------------------------------------------------------
pause() { echo; read -rp "Press Enter to continue..." _; }

show_selection() {
  echo -e "${C_BOLD}Currently selected categories:${C_RESET}"
  local t count=0
  for t in $($SUDO grep '^pkgs:' "$SELECTION" 2>/dev/null | sed 's/^pkgs://'); do
    echo "  - $t"; count=$((count + 1))
  done
  [ "$count" -eq 0 ] && echo "  (none yet)"
}

main_menu() {
  while true; do
    clear
    echo -e "${C_MAGENTA}${C_BOLD}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║          NixOS post-install (declarative)                ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${C_RESET}"
    [ "$USE_FLAKES" -eq 1 ] && echo -e "  ${C_CYAN}flakes${C_RESET} setup detected" \
                            || echo -e "  ${C_CYAN}channels${C_RESET} setup detected ($CONFIG_NIX)"
    echo "  Module: $MODULE   Selection: $SELECTION"
    echo
    echo -e "  ${C_BOLD}Development${C_RESET}"
    echo "    1) Code Editors      2) Python           3) Web Dev"
    echo "    4) Java              5) C/C++            6) Go"
    echo "    7) Rust              8) Node.js          9) PHP"
    echo "   10) Ruby             11) .NET            12) General Dev Tools"
    echo
    echo -e "  ${C_BOLD}System & Apps${C_RESET}"
    echo "   13) Databases        14) Containers/VMs  15) Gaming"
    echo "   16) Office & Docs    17) System Utils    18) Android Tools"
    echo "   19) DevOps & Cloud   20) AI Tools        21) Desktop Apps"
    echo "   22) Browsers         23) Communication   24) Security Tools"
    echo "   25) Security (Def.)  26) Windows (Wine)"
    echo
    echo -e "  ${C_BOLD}Creative${C_RESET}"
    echo "   27) Graphics  28) Video  29) Audio  30) Photography  31) Publishing"
    echo
    echo -e "  ${C_BOLD}Desktop / hardware${C_RESET}"
    echo "   32) GUI Tools   33) Icon Sets   34) Cursor Themes   35) Nerd Fonts"
    echo "   36) GTK Themes  37) Printers    38) Peripherals     39) Snapshots"
    echo
    echo -e "  ${C_BOLD}Other${C_RESET}"
    echo "   s) Show selection    r) Rebuild now    0) Quit"
    echo
    read -rp "  Choose: " c
    case "$c" in
      1) apply_category code-editors "Code Editors";;
      2) apply_category python "Python";;
      3) apply_category web-dev "Web Development";;
      4) apply_category java "Java";;
      5) apply_category c-cpp "C/C++";;
      6) apply_category go "Go";;
      7) apply_category rust "Rust";;
      8) apply_category nodejs "Node.js";;
      9) apply_category php "PHP";;
      10) apply_category ruby "Ruby";;
      11) apply_category dotnet ".NET";;
      12) apply_category dev-tools "General Dev Tools";;
      13) apply_category databases "Databases";;
      14) apply_category containers "Containers & VMs";;
      15) apply_category gaming "Gaming";;
      16) apply_category office "Office & Docs";;
      17) apply_category system-utils "System Utilities";;
      18) apply_category android "Android Tools";;
      19) apply_category devops "DevOps & Cloud";;
      20) apply_category ai-tools "AI Tools";;
      21) apply_category desktop-apps "Desktop Apps";;
      22) apply_category browsers "Browsers";;
      23) apply_category communication "Communication";;
      24) apply_category security "Security Tools";;
      25) apply_category security-defensive "Security (Defensive)";;
      26) apply_category windows "Windows Support (Wine)";;
      27) apply_category creative-graphics "Graphics & Design";;
      28) apply_category creative-video "Video Editing";;
      29) apply_category creative-audio "Audio Production";;
      30) apply_category creative-photography "Photography";;
      31) apply_category creative-publishing "Publishing";;
      32) apply_category gui-tools "GUI Tools";;
      33) apply_category icon-sets "Icon Sets";;
      34) apply_category cursor-themes "Cursor Themes";;
      35) apply_category nerd-fonts "Nerd Fonts";;
      36) apply_category gtk-themes "GTK Themes";;
      37) apply_category printers "Printers (CUPS + HP)";;
      38) apply_category peripherals "Peripherals (Solaar)";;
      39) apply_category snapshots "Snapshots (Snapper/Timeshift)";;
      s|S) show_selection;;
      r|R) rebuild;;
      0|q|Q) exit 0;;
      *) warn "Invalid choice"; sleep 1; continue;;
    esac
    pause
  done
}

main_menu
