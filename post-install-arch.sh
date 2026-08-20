#!/bin/bash
# Arch Linux Post-Install Script v1 (pacman + yay)
# Menu-driven installer with error handling - Arch/Omarchy port of post-install-fedora.sh
# Run as: chmod +x post-install-arch.sh && sudo ./post-install-arch.sh
#
# OMARCHY COMPATIBILITY NOTE: this script targets both plain Arch Linux and
# Omarchy (https://omarchy.org, basecamp/omarchy) - an opinionated Arch distro
# built around Hyprland + a custom Quickshell desktop shell, distributed as an
# ISO and updated as real pacman packages (not a curl|bash overlay on top of a
# generic Arch install). Reviewed against the Omarchy v4.0.0 ("Quattro")
# release (https://github.com/basecamp/omarchy/releases/tag/v4.0.0) and its
# repo source (bin/, install/, manual/, docs/) during development. Two things
# follow directly from that:
#
#   1. Omarchy already owns the desktop layer entirely - Hyprland, its own
#      Quickshell-based bar/launcher/notifications/lock-screen/theme system,
#      terminal (Foot), editor (Neovim), browser (Chromium), file manager
#      (Nautilus), screenshot tool, and even 9 pre-wired AI coding-agent CLIs
#      via mise stubs. This script does NOT try to install or theme a desktop
#      environment - GNOME-specific helpers here (gsettings app-folders,
#      terminal-font, GNOME Shell extensions) only actually do anything if a
#      GNOME session happens to be running, which is never true on Omarchy and
#      only true on a plain Arch box someone set up with GNOME themselves.
#   2. Since v4.0.0 Omarchy installs itself via real pacman packages fed from
#      its own repo/mirror, and ships a pacman pre-transaction hook that
#      ABORTS any direct full-sync (`pacman -Sy`/`-Syu`) not launched through
#      `omarchy update` - see docs/update-process.md in the Omarchy repo. This
#      script never runs a raw `-Syu` when Omarchy is detected (see
#      update_packages below); it only ever does targeted `pacman -S <pkg>`
#      installs, which the guard does not touch.
#
# Everywhere Omarchy already provides a first-party wrapper for something this
# script would otherwise hand-roll (theme switching, NVIDIA driver selection,
# Btrfs snapshots, web-app .desktop files), this script prefers detecting and
# deferring to that wrapper over duplicating its logic.
#
# PACKAGE NAME CONFIDENCE NOTE: Arch has no RPM-Fusion/COPR-style curated
# third-party repo layer - "not in the official repos" here almost always
# means "check the AUR" rather than "unavailable", so safe_install below
# tries the official repos first and transparently falls back to the AUR
# (via yay) per package. Category package lists were researched against
# archlinux.org/packages and aur.archlinux.org during development, following
# the same spirit as the Fedora script's own confidence notes; is_installed/
# package_exists still gate every install, so a wrong guess is logged
# "Not in repos or AUR" and skipped rather than failing the whole run.

# ── Catppuccin Mocha palette (24-bit truecolor ANSI) ─────────────────────────
# Same convention as the Fedora/Ubuntu scripts: colors by SEMANTIC ROLE.
# Auto-disables when stdout isn't a terminal or NO_COLOR is set.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    _cat() { printf '\033[38;2;%sm' "$1"; }
    RED=$(_cat '243;139;168')       # #f38ba8  errors
    GREEN=$(_cat '166;227;161')     # #a6e3a1  success
    YELLOW=$(_cat '249;226;175')    # #f9e2af  warnings
    BLUE=$(_cat '137;180;250')      # #89b4fa  info
    MAUVE=$(_cat '203;166;247')     # #cba6f7  accent / headings
    LAVENDER=$(_cat '180;190;254')  # #b4befe  active / prompts
    PEACH=$(_cat '250;179;135')     # #fab387  bulk / emphasis
    TEAL=$(_cat '148;226;213')      # #94e2d5  secondary info
    ROSEWATER=$(_cat '245;224;220') # #f5e0dc  warm highlight
    TEXT=$(_cat '205;214;244')      # #cdd6f4  body text
    SUBTEXT=$(_cat '166;173;200')   # #a6adc8  labels / secondary
    OVERLAY=$(_cat '108;112;134')   # #6c7086  rules / hints
    BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'
    unset -f _cat
else
    RED='' GREEN='' YELLOW='' BLUE='' MAUVE='' LAVENDER='' PEACH='' TEAL=''
    ROSEWATER='' TEXT='' SUBTEXT='' OVERLAY='' BOLD='' DIM='' NC=''
fi

# ── UI helpers (Catppuccin-themed terminal chrome) ───────────────────────────
printf -v UI_RULE '─%.0s' {1..58}
ui_rule() { printf "${OVERLAY}%s${NC}\n" "$UI_RULE"; }
ui_header() {
    printf "${MAUVE}${BOLD}╭%s╮${NC}\n" "$UI_RULE"
    printf "  ${LAVENDER}${BOLD}%s${NC}\n" "$1"
    [ -n "${2:-}" ] && printf "  ${DIM}${SUBTEXT}%s${NC}\n" "$2"
    printf "${MAUVE}${BOLD}╰%s╯${NC}\n" "$UI_RULE"
}
ui_item()     { printf "  ${MAUVE}%3s${NC}  ${TEXT}%s${NC}\n" "$1" "$2"; }
ui_cell()     { printf "  ${MAUVE}%2s${NC}  ${TEXT}%-24s${NC}" "$1" "$2"; }
ui_cell_alt() { printf "  ${PEACH}%2s${NC}  ${TEXT}%-24s${NC}" "$1" "$2"; }
ui_section()  { printf "  ${LAVENDER}${BOLD}%s${NC}\n" "$1"; }

declare -a INSTALLED_PACKAGES FAILED_PACKAGES SKIPPED_PACKAGES
TOTAL_INSTALLED=0; TOTAL_FAILED=0; TOTAL_SKIPPED=0

ARCH_ID=""; ARCH_ID_LIKE=""
IS_OMARCHY=false
OMARCHY_VERSION=""
IS_MANJARO=false
IS_GARUDA=false

log() {
    local l="$1" m="$2"
    case "$l" in
        ERROR)   printf "${RED}${BOLD} ✗${NC} ${RED}%s${NC}\n" "$m" >&2;;
        WARNING) printf "${YELLOW}${BOLD} ▲${NC} ${YELLOW}%s${NC}\n" "$m";;
        INFO)    printf "${BLUE}${BOLD} •${NC} ${TEXT}%s${NC}\n" "$m";;
        SUCCESS) printf "${GREEN}${BOLD} ✓${NC} ${GREEN}%s${NC}\n" "$m";;
        *)       printf "${TEXT}%s${NC}\n" "$m";;
    esac
}

check_root() {
    [ "$(id -u)" -ne 0 ] && { log ERROR "This script must be run as root. Use sudo."; exit 1; }
}

# Detect plain Arch vs Omarchy. Omarchy still reports ID=arch in os-release
# (it IS Arch underneath - see the header note), so detection has to key off
# something Omarchy-specific rather than os-release ID/ID_LIKE. The `omarchy`
# pacman package (present since the v4.0.0 "real pacman packages" rearchitecture)
# is the most reliable signal; command -v omarchy is a fallback for the same
# fact when pacman's DB lookup itself is unavailable for some reason.
detect_system() {
    ARCH_ID=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"')
    ARCH_ID_LIKE=$(grep -oP '(?<=^ID_LIKE=).+' /etc/os-release 2>/dev/null | tr -d '"')
    if pacman -Qq omarchy &>/dev/null || command -v omarchy &>/dev/null; then
        IS_OMARCHY=true
        OMARCHY_VERSION=$(pacman -Qi omarchy 2>/dev/null | awk -F': ' '/^Version/{print $2; exit}')
    fi
    [ "$ARCH_ID" = "manjaro" ] && IS_MANJARO=true
    [ "$ARCH_ID" = "garuda" ] && IS_GARUDA=true
}

# Beyond the generic "id=arch or ID_LIKE contains arch" acceptance check
# below, two specific Arch derivatives get their own explicit handling
# because "just another Arch box" isn't quite true for either of them:
#
#   - Manjaro deliberately holds packages back on its own delayed/tested
#     branch rather than tracking Arch's rolling repos in real time. This
#     script's update_packages() runs a full `pacman -Syu` and bootstrap_arch
#     installs yay unconditionally - AUR packages are built/published against
#     current Arch library versions, and installing them on top of Manjaro's
#     intentionally-older base is a well-documented way to break a Manjaro
#     system (mismatched glibc/library versions). This isn't a Fedora/Ubuntu-
#     style "wrong version detected" warning, it's a real compatibility risk
#     specific to combining Manjaro with this script's automatic -Syu+yay
#     flow, so it gets its own confirmation gate.
#   - Garuda Linux ships Chaotic-AUR (and usually Snapper/Btrfs) enabled by
#     default already. This script's own opt-in Chaotic-AUR/Snapshots
#     functions already no-op cleanly when they detect an existing setup
#     (see install_chaotic_aur / install_snapshots_btrfs), so nothing breaks
#     here either way - this is purely an upfront heads-up so a Garuda user
#     isn't confused when those menu items immediately report "already
#     installed" instead of doing anything.
print_distro_notes() {
    if $IS_MANJARO; then
        log WARNING "Manjaro detected. Manjaro intentionally runs a delayed/tested package branch, not Arch's live rolling repos."
        log WARNING "This script will shortly run a full 'pacman -Syu' and install AUR packages via yay - AUR packages are built against CURRENT Arch libraries, and installing them on top of Manjaro's older base is a known way to break dependencies (mismatched glibc/library versions)."
        log WARNING "If you want to stay safe, use Manjaro's own 'pamac'/AUR support instead of this script's yay-driven installs, or at minimum review each category's package list before installing."
        read -p "Continue anyway? [y/N] " -n 1 -r; echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
    if $IS_GARUDA; then
        log INFO "Garuda Linux detected - Chaotic-AUR and Snapper/Btrfs snapshots typically already come enabled by default there."
        log INFO "This script's Chaotic-AUR (Drivers & Extra Repos) and Snapshots menu items already detect an existing setup and skip re-doing it - no action needed unless you actually want to change something."
    fi
}

check_version() {
    detect_system
    if [[ "$ARCH_ID" == "arch" || "$ARCH_ID" == "omarchy" || "$ARCH_ID_LIKE" == *arch* ]]; then
        if $IS_OMARCHY; then
            log INFO "Detected Omarchy ${OMARCHY_VERSION:-(version unknown)} on Arch Linux"
        elif $IS_MANJARO; then
            log INFO "Detected Manjaro Linux (Arch-based)"
        elif $IS_GARUDA; then
            log INFO "Detected Garuda Linux (Arch-based)"
        elif [ -n "$ARCH_ID" ] && [ "$ARCH_ID" != "arch" ]; then
            log INFO "Detected ${ARCH_ID} (Arch-based)"
        else
            log INFO "Detected Arch Linux"
        fi
        print_distro_notes
    else
        log WARNING "Designed for Arch Linux (id=arch) or Omarchy, detected: ${ARCH_ID:-unknown}"
        read -p "Continue anyway? [y/N] " -n 1 -r; echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
}

# ── Package-manager front-end (pacman + yay) ─────────────────────────────────
# Arch has no per-distro "extra proprietary repo" layer to bootstrap the way
# Fedora needs RPM Fusion or Ubuntu needs PPAs - the AUR (via yay, see
# ensure_yay below) fills that role for essentially everything not in the
# official repos, so safe_install tries official repos first and transparently
# falls back to the AUR per package rather than needing a per-category repo
# dance.
PM="pacman"
is_installed() { pacman -Qq "$1" &>/dev/null; }
repo_package_exists() { pacman -Si "$1" &>/dev/null; }
aur_helper_available() { command -v yay &>/dev/null; }
aur_package_exists() { aur_helper_available && yay -Si "$1" &>/dev/null; }
package_exists() { repo_package_exists "$1" || aur_package_exists "$1"; }

# Bootstraps yay (AUR helper) if it's missing. Uses yay-bin specifically (a
# prebuilt-binary AUR package) rather than plain `yay`, so bootstrapping it
# only needs base-devel + git, not a Go toolchain, on a fresh box that may not
# have one yet. makepkg refuses to run as root by design (Arch's build
# tooling assumes an unprivileged builder), so the clone+build step runs as
# SUDO_USER via su -, and only the final `pacman -U` of the built package runs
# as root. Omarchy already ships yay by default (install/omarchy-base.packages)
# so this is a no-op there; it exists for plain Arch installs.
ensure_yay() {
    aur_helper_available && return 0
    if [ -z "$SUDO_USER" ] || [ "$SUDO_USER" = "root" ]; then
        log WARNING "yay (AUR helper) isn't installed and there's no non-root user (SUDO_USER) to build it as - run this script via sudo from a user session to get AUR support. AUR packages will be skipped for now."
        return 1
    fi
    log INFO "yay not found - bootstrapping it from the AUR (yay-bin, needs base-devel + git)..."
    pacman -S --needed --noconfirm base-devel git &>/dev/null
    local t="/tmp/yay-bootstrap-$$"
    if su - "$SUDO_USER" -c "rm -rf '$t' && git clone --depth 1 https://aur.archlinux.org/yay-bin.git '$t' && cd '$t' && makepkg -s --noconfirm" &>/dev/null; then
        local built
        built=$(su - "$SUDO_USER" -c "ls '$t'"/*.pkg.tar.* 2>/dev/null | head -1)
        if [ -n "$built" ] && pacman -U --noconfirm "$built" &>/dev/null; then
            log SUCCESS "yay installed"
        else
            log WARNING "yay built but the package install step failed"
        fi
    else
        log WARNING "yay bootstrap failed (needs network access to aur.archlinux.org) - AUR packages will be skipped for this run"
    fi
    su - "$SUDO_USER" -c "rm -rf '$t'" 2>/dev/null
    aur_helper_available
}

# Installs one AUR package as SUDO_USER. Deliberately NOT silenced with
# 2>/dev/null the way repo installs are below: yay's build output is worth
# seeing on failure. yay itself has no standing privilege, so partway
# through a real AUR build it shells out to `sudo pacman -U`/`-S` to
# actually land the built package and any repo dependencies it pulled in.
# That's exactly what enable_temp_passwordless_sudo (below) exists for - see
# its comment for why relying on an interactive password prompt here doesn't
# reliably work in this specific su-then-yay-then-sudo chain.
aur_install() {
    local pkg="$1"
    ensure_yay || return 1
    enable_temp_passwordless_sudo
    su - "$SUDO_USER" -c "yay -S --needed --noconfirm --removemake '$pkg'"
}

# yay must run unprivileged (makepkg refuses outright to run as root - Arch's
# build tooling assumes an unprivileged builder), but still needs to shell
# out to `sudo pacman -U`/`-S` itself to actually land a built AUR package or
# pull its repo dependencies. This script runs as root already, so
# aur_install drops to SUDO_USER via `su - ... -c` to run yay - chaining
# root-script -> su -> yay -> sudo. That specific chain is a well-known
# gotcha: sudo needs to open /dev/tty directly to prompt for a password (not
# just an interactive stdin/stdout), and su's handling of the controlling
# terminal across that hand-off frequently breaks that, independent of
# whether this script itself is running interactively. The visible symptom
# is exactly "sudo: a terminal is needed to read the password" with no
# prompt ever shown - not a hang, an outright failure.
#
# Rather than fight that plumbing, grant SUDO_USER a narrowly-scoped,
# TEMPORARY passwordless-sudo rule for pacman specifically (not a blanket
# NOPASSWD: ALL) so yay's internal sudo calls never need to prompt at all,
# and remove the rule again via traps so nothing persists past this run - a
# crash, Ctrl-C, or a normal exit all trigger the same cleanup. Idempotent:
# safe to call before every AUR install, only does real work once.
AUR_SUDOERS_FILE=""

enable_temp_passwordless_sudo() {
    [ -n "$AUR_SUDOERS_FILE" ] && return 0
    if [ -z "$SUDO_USER" ] || [ "$SUDO_USER" = "root" ]; then
        return 1
    fi
    if ! command -v visudo &>/dev/null; then
        log WARNING "visudo not found - cannot safely grant temporary sudo for AUR builds; yay may fail with 'a terminal is needed to read the password'"
        return 1
    fi
    local f="/etc/sudoers.d/99-postinstall-aur-${SUDO_USER}"
    local tmp; tmp=$(mktemp)
    printf '%s ALL=(root) NOPASSWD: /usr/bin/pacman\n' "$SUDO_USER" > "$tmp"
    if visudo -c -f "$tmp" &>/dev/null; then
        install -m 0440 -o root -g root "$tmp" "$f"
        AUR_SUDOERS_FILE="$f"
        trap disable_temp_passwordless_sudo EXIT
        trap 'disable_temp_passwordless_sudo; exit 130' INT TERM
        log INFO "Granted $SUDO_USER temporary passwordless sudo for pacman (AUR builds only - removed automatically when this script exits)"
    else
        log WARNING "Generated sudoers rule failed validation - skipping temporary passwordless sudo"
    fi
    rm -f "$tmp"
}

disable_temp_passwordless_sudo() {
    [ -n "$AUR_SUDOERS_FILE" ] && rm -f "$AUR_SUDOERS_FILE"
    AUR_SUDOERS_FILE=""
}

# Enables the [multilib] repo (32-bit libs - needed for Steam, Wine, and most
# native Linux games) if it isn't already. Arch ships pacman.conf with the
# whole [multilib] block present but commented out by default, so this
# uncomments the existing block instead of appending a second one - appending
# a duplicate [multilib] section is a real (if harmless-looking) footgun on
# Arch, since pacman just merges both and it silently works until the day
# someone edits only one of the two and wonders why nothing changed.
bootstrap_multilib() {
    if grep -qE '^\[multilib\]' /etc/pacman.conf; then
        return 0
    fi
    log INFO "Enabling [multilib] (32-bit libs - Steam, Wine, native games)..."
    if grep -qE '^#\[multilib\]' /etc/pacman.conf; then
        sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
    else
        printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> /etc/pacman.conf
    fi
    if $IS_OMARCHY; then
        log INFO "Omarchy detected - not syncing here (see update_packages note); run 'omarchy update' once to pick up [multilib], or 'sudo pacman -Sy' if you understand the partial-upgrade caveat."
    else
        pacman -Sy --noconfirm &>/dev/null
    fi
    log SUCCESS "[multilib] enabled"
}

safe_install() {
    for pkg in "$@"; do
        [[ -z "$pkg" ]] && continue
        if is_installed "$pkg"; then
            SKIPPED_PACKAGES+=("$pkg"); ((TOTAL_SKIPPED++))
            log INFO "Already installed: $pkg"; continue
        fi
        if repo_package_exists "$pkg"; then
            log INFO "Installing: $pkg"
            if pacman -S --needed --noconfirm "$pkg" &>/dev/null && is_installed "$pkg"; then
                INSTALLED_PACKAGES+=("$pkg"); ((TOTAL_INSTALLED++))
                log SUCCESS "Installed: $pkg"
            else
                FAILED_PACKAGES+=("$pkg"); ((TOTAL_FAILED++))
                log ERROR "Failed: $pkg"
            fi
            continue
        fi
        if aur_package_exists "$pkg"; then
            log INFO "Installing (AUR): $pkg"
            if aur_install "$pkg" && is_installed "$pkg"; then
                INSTALLED_PACKAGES+=("$pkg (AUR)"); ((TOTAL_INSTALLED++))
                log SUCCESS "Installed: $pkg (AUR)"
            else
                FAILED_PACKAGES+=("$pkg"); ((TOTAL_FAILED++))
                log ERROR "Failed (AUR): $pkg"
            fi
            continue
        fi
        FAILED_PACKAGES+=("$pkg"); ((TOTAL_FAILED++))
        log WARNING "Not in repos or AUR: $pkg"
    done
}

reload_systemd() {
    { [ -d /run/systemd/system ] && command -v systemctl &>/dev/null && systemctl daemon-reload 2>/dev/null; } || true
}

batch_install() {
    local cat="$1"; shift; local pkgs=("$@")
    local s=$TOTAL_INSTALLED f=$TOTAL_FAILED k=$TOTAL_SKIPPED
    log INFO "Installing $cat..."
    safe_install "${pkgs[@]}"
    reload_systemd
    log INFO "$cat: $((TOTAL_INSTALLED-s)) installed, $((TOTAL_FAILED-f)) failed, $((TOTAL_SKIPPED-k)) skipped"
}

# On plain Arch this is a full `pacman -Syu` - the Arch Wiki is explicit that
# a bare `-Sy` sync without an immediate `-u` upgrade risks a partial-upgrade
# breakage (wiki.archlinux.org/title/System_maintenance#Partial_upgrades_are_unsupported),
# so unlike Fedora's dnf makecache-only refresh, this deliberately upgrades
# the whole system before installing anything new.
#
# On Omarchy this is skipped entirely and on purpose: since v4.0.0, Omarchy
# ships a pacman pre-transaction hook that aborts any direct full-sync not
# launched through its own `omarchy update` flow (which also takes a Btrfs
# snapshot first and runs post-update migrations) - see the header note.
# Every install this script does afterwards is a targeted `pacman -S <pkg>`,
# which that guard does not intercept, so skipping the sync here doesn't
# block anything else in the script; it just means package databases may be
# slightly stale until the user runs `omarchy update` themselves.
update_packages() {
    if $IS_OMARCHY; then
        log INFO "Omarchy detected - skipping a raw pacman sync/upgrade here."
        log WARNING "Omarchy guards direct 'pacman -Syu' behind its own 'omarchy update' flow (snapshots + migrations) - run that yourself periodically."
        log INFO "Every install below is a targeted 'pacman -S <pkg>', which that guard doesn't touch."
        return 0
    fi
    log INFO "Refreshing package databases and upgrading the system (pacman -Syu)..."
    if ! pacman -Syu --noconfirm; then
        log ERROR "System upgrade failed. Check internet/mirrors."
        read -p "Retry? [y/N] " -n 1 -r; echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then update_packages; else log ERROR "Cannot proceed."; exit 1; fi
    fi
    log SUCCESS "System up to date."
}

bootstrap_arch() {
    ensure_yay
    bootstrap_multilib
}

install_base() {
    log INFO "Installing base utilities..."
    batch_install "base" curl wget git gnupg base-devel xdg-user-dirs
}

# ========== DESKTOP-SESSION HELPERS (GNOME-only; no-op under Hyprland/Omarchy) ==========
# gsettings/dconf and org.gnome.desktop.app-folders are GNOME Shell features.
# Omarchy runs Hyprland + its own Quickshell-based shell instead of GNOME
# Shell, so these helpers correctly find no GNOME session there and skip -
# kept as-is (verbatim logic from the Fedora/Ubuntu scripts) for anyone
# running this on a plain Arch box with GNOME installed.
gsettings_as_user() {
    local user="$1" uid="$2"; shift 2
    local home; home=$(getent passwd "$user" | cut -d: -f6)
    sudo -u "$user" \
        HOME="$home" \
        XDG_RUNTIME_DIR="/run/user/${uid}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
        gsettings "$@"
}

resolve_desktop_session() {
    local user="$SUDO_USER"
    [ -z "$user" ] && user=$(logname 2>/dev/null)
    if [ -z "$user" ] || [ "$user" = "root" ]; then
        log WARNING "Could not determine the desktop user (run via sudo from a desktop session)" >&2
        return 1
    fi
    local uid
    if ! uid=$(id -u "$user" 2>/dev/null); then
        log WARNING "User '$user' not found" >&2
        return 1
    fi
    if [ ! -S "/run/user/${uid}/bus" ]; then
        log WARNING "No active session for $user (/run/user/${uid}/bus missing) - run from a logged-in desktop" >&2
        return 1
    fi
    echo "$user $uid"
}

gset_if_exists() {
    local user="$1" uid="$2" schema="$3" key="$4" value="$5"
    gsettings_as_user "$user" "$uid" list-schemas 2>/dev/null | grep -qx "$schema" || return 1
    gsettings_as_user "$user" "$uid" list-keys "$schema" 2>/dev/null | grep -qx "$key" || return 1
    gsettings_as_user "$user" "$uid" set "$schema" "$key" "$value" 2>/dev/null
}

create_menu_category() {
    local name="$1" icon="$2" comment="$3"
    shift 3
    local apps=("$@")

    local folder_id
    folder_id=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed -e 's/^-*//' -e 's/-*$//')

    local user="$SUDO_USER"
    [ -z "$user" ] && user=$(logname 2>/dev/null)
    if [ -z "$user" ] || [ "$user" = "root" ]; then
        log WARNING "Could not determine the desktop user; skipping app-folder '$name'"
        return 1
    fi
    local uid
    if ! uid=$(id -u "$user" 2>/dev/null); then
        log WARNING "User '$user' not found; skipping app-folder '$name'"
        return 1
    fi
    if [ ! -S "/run/user/${uid}/bus" ]; then
        log WARNING "No active GNOME session found for $user (/run/user/${uid}/bus missing)."
        log WARNING "Run this from a logged-in GNOME desktop session as $user to create '$name'."
        return 1
    fi
    if ! gsettings_as_user "$user" "$uid" list-schemas 2>/dev/null | grep -qx "org.gnome.desktop.app-folders"; then
        log INFO "No GNOME Shell app-folders schema found - skipping app-folder '$name' (this desktop isn't GNOME)"
        return 1
    fi

    displayable_desktop_files() {
        local pkg="$1" f
        pacman -Qlq "$pkg" 2>/dev/null | grep -iE '/applications/.*\.desktop$' | while IFS= read -r f; do
            grep -qE '^(NoDisplay|Hidden)[[:space:]]*=[[:space:]]*true' "$f" 2>/dev/null || basename "$f"
        done
    }

    local desktop_ids=()
    for app in "${apps[@]}"; do
        local found=()
        if is_installed "$app"; then
            local line
            while IFS= read -r line; do [ -n "$line" ] && found+=("$line"); done < <(displayable_desktop_files "$app")
            if [ ${#found[@]} -eq 0 ]; then
                local dep line2
                while IFS= read -r dep; do
                    [ -z "$dep" ] && continue
                    is_installed "$dep" || continue
                    while IFS= read -r line2; do [ -n "$line2" ] && found+=("$line2"); done < <(displayable_desktop_files "$dep")
                done < <(pacman -Qiq "$app" 2>/dev/null | awk -F': ' '/^Depends On/{print $2}' | tr ' ' '\n' | grep -v '^None$\|^$' | sed 's/[<>=].*//' | sort -u)
            fi
        fi
        if [ ${#found[@]} -eq 0 ]; then
            local fp_dirs=("/var/lib/flatpak/exports/share/applications")
            local uhome; uhome=$(getent passwd "$user" 2>/dev/null | cut -d: -f6)
            [ -n "$uhome" ] && fp_dirs+=("$uhome/.local/share/flatpak/exports/share/applications")
            local fpd fpf nm base
            for fpd in "${fp_dirs[@]}"; do
                [ -d "$fpd" ] || continue
                for fpf in "$fpd"/*.desktop; do
                    [ -e "$fpf" ] || continue
                    grep -qE '^(NoDisplay|Hidden)[[:space:]]*=[[:space:]]*true' "$fpf" 2>/dev/null && continue
                    nm=$(awk -F= '/^Name=/{print $2; exit}' "$fpf")
                    base=$(basename "$fpf" .desktop)
                    if [ "${nm,,}" = "${app,,}" ] || [ "${base,,}" = "${app,,}" ]; then
                        found+=("$(basename "$fpf")"); break
                    fi
                done
                [ ${#found[@]} -gt 0 ] && break
            done
        fi
        if [ ${#found[@]} -gt 0 ]; then
            desktop_ids+=("${found[@]}")
        else
            log WARNING "Desktop file not found: $app"
        fi
    done
    if [ ${#desktop_ids[@]} -eq 0 ]; then
        log WARNING "No GUI apps with .desktop launchers found for '$name' - skipping empty folder"
        return 1
    fi
    local uniq_ids=() d existing already
    for d in "${desktop_ids[@]}"; do
        already=false
        for existing in "${uniq_ids[@]}"; do [ "$existing" = "$d" ] && already=true && break; done
        $already || uniq_ids+=("$d")
    done
    desktop_ids=("${uniq_ids[@]}")

    local apps_gv="[" first=true
    for id in "${desktop_ids[@]}"; do
        $first && first=false || apps_gv+=", "
        apps_gv+="'${id}'"
    done
    apps_gv+="]"

    local current
    current=$(gsettings_as_user "$user" "$uid" get org.gnome.desktop.app-folders folder-children 2>/dev/null)
    local children=()
    if [[ "$current" =~ \[(.*)\] ]]; then
        local inner="${BASH_REMATCH[1]}" raw part
        IFS=',' read -ra raw <<< "$inner"
        for part in "${raw[@]}"; do
            part="${part//\'/}"; part="${part// /}"
            [ -n "$part" ] && children+=("$part")
        done
    fi
    local exists=false c
    for c in "${children[@]}"; do [ "$c" = "$folder_id" ] && exists=true; done
    $exists || children+=("$folder_id")

    local children_gv="["
    first=true
    for c in "${children[@]}"; do
        $first && first=false || children_gv+=", "
        children_gv+="'${c}'"
    done
    children_gv+="]"

    local folder_path="/org/gnome/desktop/app-folders/folders/${folder_id}/"
    echo "Creating GNOME app folder: $name ($((${#desktop_ids[@]})) apps)..."
    if gsettings_as_user "$user" "$uid" set org.gnome.desktop.app-folders folder-children "$children_gv" \
        && gsettings_as_user "$user" "$uid" set "org.gnome.desktop.app-folders.folder:${folder_path}" name "$name" \
        && gsettings_as_user "$user" "$uid" set "org.gnome.desktop.app-folders.folder:${folder_path}" apps "$apps_gv"; then
        echo "✓ Created GNOME app folder: $name"
        echo "  Press Super and look in the app grid - takes effect immediately, no logout needed"
        return 0
    fi

    log ERROR "gsettings write failed for '$name' (schema org.gnome.desktop.app-folders)"
    return 1
}

display_summary() {
    clear
    ui_header "INSTALLATION SUMMARY"
    echo
    printf "  ${SUBTEXT}%-11s${NC}${TEXT}${BOLD}%s${NC}\n" "Total"     "$((TOTAL_INSTALLED+TOTAL_FAILED+TOTAL_SKIPPED))"
    printf "  ${GREEN} ✓ %-8s${NC}${TEXT}%s${NC}\n"        "Installed" "$TOTAL_INSTALLED"
    printf "  ${YELLOW} ↷ %-8s${NC}${TEXT}%s${NC}\n"       "Skipped"   "$TOTAL_SKIPPED"
    printf "  ${RED} ✗ %-8s${NC}${TEXT}%s${NC}\n"          "Failed"    "$TOTAL_FAILED"
    echo
    if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
        printf "  ${RED}${BOLD}Failed${NC}\n"
        for p in "${FAILED_PACKAGES[@]}"; do printf "    ${RED}✗${NC} ${TEXT}%s${NC}\n" "$p"; done
        echo
    fi
    if [ ${#SKIPPED_PACKAGES[@]} -gt 0 ]; then
        printf "  ${YELLOW}${BOLD}Skipped${NC}\n"
        printf "    ${YELLOW}↷${NC} ${TEXT}%s${NC}\n" "${SKIPPED_PACKAGES[@]:0:10}"
        [ ${#SKIPPED_PACKAGES[@]} -gt 10 ] && printf "    ${DIM}${SUBTEXT}…and %s more${NC}\n" "$(( ${#SKIPPED_PACKAGES[@]} - 10 ))"
        echo
    fi
    ui_rule
}

save_log() {
    local f="/var/log/arch_post_install_$(date +%Y%m%d_%H%M%S).log"
    {
        echo "=== Log: $(date) ==="; echo "User: $(whoami)"
        echo "System: $($IS_OMARCHY && echo "Omarchy ${OMARCHY_VERSION:-unknown}" || echo "Arch Linux")"
        echo "Installed: ${TOTAL_INSTALLED}"; echo "Skipped: ${TOTAL_SKIPPED}"; echo "Failed: ${TOTAL_FAILED}"
        echo; echo "Installed packages:"; printf "  %s\n" "${INSTALLED_PACKAGES[@]}"
        echo; echo "Failed packages:"; printf "  %s\n" "${FAILED_PACKAGES[@]}"
    } > "$f"
    log INFO "Log saved to: $f"
}

# ========== FLATPAK/FLATHUB HELPER (last resort only) ==========
# On Arch, official repos + AUR (via yay) cover almost everything already, so
# unlike the Fedora/Ubuntu scripts this is genuinely a last resort here, not a
# routine fallback - kept only for the rare app with neither an official
# package nor an AUR package that actually builds/works.
flatpak_install_flathub() {
    local app_id="$1" label="$2"
    if ! command -v flatpak &>/dev/null; then
        batch_install "Flatpak" flatpak
    fi
    if ! command -v flatpak &>/dev/null; then
        FAILED_PACKAGES+=("$label"); ((TOTAL_FAILED++))
        log WARNING "flatpak unavailable - install manually: flatpak install flathub $app_id"; return 0
    fi
    if flatpak info "$app_id" &>/dev/null; then
        SKIPPED_PACKAGES+=("$label"); ((TOTAL_SKIPPED++)); log INFO "Already installed: $label (flatpak)"; return 0
    fi
    log INFO "Installing $label (Flatpak from Flathub)..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
    if flatpak install -y --noninteractive flathub "$app_id" 2>/dev/null || flatpak info "$app_id" &>/dev/null; then
        INSTALLED_PACKAGES+=("$label"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: $label (flatpak) - launch with: flatpak run $app_id"; return 0
    fi
    FAILED_PACKAGES+=("$label"); ((TOTAL_FAILED++))
    log WARNING "$label install failed - try: flatpak install flathub $app_id"; return 0
}

# ========== AI TOOLS ==========
# Almost entirely package-manager-agnostic (vendor curl|bash installers, npm
# globals, Flathub) - ported near-verbatim from the Fedora/Ubuntu scripts.
# Only Cursor changes (AUR package instead of a yum repo).
#
# OMARCHY NOTE: Omarchy pre-wires NINE coding-agent CLIs (claude, codex,
# opencode, gemini, copilot, crush, grok, pi, omp) as lazy-loading mise stubs
# that already resolve on $PATH - see manual/17-ai.md in the omarchy repo.
# No special-casing is needed here: every function below already gates on
# `command -v <tool>` first, so on Omarchy those checks succeed immediately
# and the function just logs "already installed" and returns, exactly the
# idempotency behavior the rest of this script relies on everywhere else.
# Ollama, Alpaca, and Cursor aren't among Omarchy's nine stubs, so those still
# genuinely install something new even there.
install_ai_tools() {
    log INFO "Installing AI Tools..."
    install_ollama
    install_alpaca
    install_claude_code
    install_gemini_cli
    install_vibe_cli
    install_opencode
    install_cursor
}

install_ollama() {
    if command -v ollama &>/dev/null; then
        SKIPPED_PACKAGES+=("ollama"); ((TOTAL_SKIPPED++)); log INFO "Already installed: ollama"; return 0
    fi
    log INFO "Installing Ollama..."
    if curl -fsSL https://ollama.com/install.sh | sh 2>/dev/null && command -v ollama &>/dev/null; then
        INSTALLED_PACKAGES+=("ollama"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: ollama"; return 0
    else
        FAILED_PACKAGES+=("ollama"); ((TOTAL_FAILED++)); log ERROR "Failed: ollama"; return 1
    fi
}

# Alpaca - native GTK4/libadwaita Ollama client, Flathub-only (no AUR
# package that stays reliably current), same conclusion as Fedora/Ubuntu.
install_alpaca() { flatpak_install_flathub com.jeffser.Alpaca "Alpaca"; }

install_claude_code() {
    local u="$SUDO_USER"; [ "$u" = "root" ] && u=""
    local check_cmd install_cmd
    if [ -n "$u" ]; then
        check_cmd="su - $u -c 'command -v claude'"
        install_cmd="su - $u -c 'curl -fsSL https://claude.ai/install.sh | bash'"
    else
        check_cmd="command -v claude"
        install_cmd="curl -fsSL https://claude.ai/install.sh | bash"
    fi
    if eval "$check_cmd" &>/dev/null || command -v claude &>/dev/null; then
        SKIPPED_PACKAGES+=("claude"); ((TOTAL_SKIPPED++)); log INFO "Already installed: claude"; return 0
    fi
    log INFO "Installing Claude Code CLI (native installer)..."
    if eval "$install_cmd" 2>/dev/null && { eval "$check_cmd" &>/dev/null || command -v claude &>/dev/null; }; then
        INSTALLED_PACKAGES+=("claude"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: claude (~/.local/bin - ensure it's on your PATH)"; return 0
    fi
    if command -v npm &>/dev/null && npm install -g @anthropic-ai/claude-code 2>/dev/null && command -v claude &>/dev/null; then
        INSTALLED_PACKAGES+=("claude"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: claude (npm)"; return 0
    fi
    FAILED_PACKAGES+=("claude"); ((TOTAL_FAILED++))
    log WARNING "Claude Code install failed - try: curl -fsSL https://claude.ai/install.sh | bash"; return 0
}

install_gemini_cli() {
    if command -v gemini &>/dev/null; then
        SKIPPED_PACKAGES+=("gemini"); ((TOTAL_SKIPPED++)); log INFO "Already installed: gemini"; return 0
    fi
    if ! command -v npm &>/dev/null; then
        log INFO "npm not found - installing it (required by Gemini CLI)..."
        pacman -S --needed --noconfirm npm &>/dev/null || true
    fi
    if ! command -v npm &>/dev/null; then
        FAILED_PACKAGES+=("gemini"); ((TOTAL_FAILED++))
        log WARNING "Gemini CLI needs npm and npm could not be installed - install it, then: npm install -g @google/gemini-cli"; return 0
    fi
    log INFO "Installing Gemini CLI..."
    if npm install -g @google/gemini-cli 2>/dev/null && command -v gemini &>/dev/null; then
        INSTALLED_PACKAGES+=("gemini"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: gemini (run 'gemini' to sign in)"; return 0
    fi
    FAILED_PACKAGES+=("gemini"); ((TOTAL_FAILED++))
    log WARNING "Gemini CLI install failed - try: npm install -g @google/gemini-cli"; return 0
}

install_vibe_cli() {
    local u="$SUDO_USER"; [ "$u" = "root" ] && u=""
    local check_cmd install_cmd
    if [ -n "$u" ]; then
        check_cmd="su - $u -c 'command -v vibe'"
        install_cmd="su - $u -c 'curl -LsSf https://mistral.ai/vibe/install.sh | bash'"
    else
        check_cmd="command -v vibe"
        install_cmd="curl -LsSf https://mistral.ai/vibe/install.sh | bash"
    fi
    if eval "$check_cmd" &>/dev/null || command -v vibe &>/dev/null; then
        SKIPPED_PACKAGES+=("vibe"); ((TOTAL_SKIPPED++)); log INFO "Already installed: vibe"; return 0
    fi
    log INFO "Installing Mistral Vibe CLI..."
    if eval "$install_cmd" 2>/dev/null && { eval "$check_cmd" &>/dev/null || command -v vibe &>/dev/null; }; then
        INSTALLED_PACKAGES+=("vibe"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: vibe (run 'vibe' to sign in or paste an API key)"; return 0
    fi
    FAILED_PACKAGES+=("vibe"); ((TOTAL_FAILED++))
    log WARNING "Vibe CLI install failed (needs Python 3.12+) - try: curl -LsSf https://mistral.ai/vibe/install.sh | bash"; return 0
}

install_opencode() {
    local u="$SUDO_USER"; [ "$u" = "root" ] && u=""
    local check_cmd install_cmd
    if [ -n "$u" ]; then
        check_cmd="su - $u -c 'command -v opencode'"
        install_cmd="su - $u -c 'curl -fsSL https://opencode.ai/install | bash'"
    else
        check_cmd="command -v opencode"
        install_cmd="curl -fsSL https://opencode.ai/install | bash"
    fi
    if eval "$check_cmd" &>/dev/null || command -v opencode &>/dev/null; then
        SKIPPED_PACKAGES+=("opencode"); ((TOTAL_SKIPPED++)); log INFO "Already installed: opencode"; return 0
    fi
    log INFO "Installing OpenCode (native installer)..."
    if eval "$install_cmd" 2>/dev/null && { eval "$check_cmd" &>/dev/null || command -v opencode &>/dev/null; }; then
        INSTALLED_PACKAGES+=("opencode"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: opencode (run 'opencode' then '/connect' to add a provider)"; return 0
    fi
    if ! command -v npm &>/dev/null; then
        log INFO "npm not found - installing it (fallback for OpenCode)..."
        pacman -S --needed --noconfirm npm &>/dev/null || true
    fi
    if command -v npm &>/dev/null && npm install -g opencode-ai 2>/dev/null && command -v opencode &>/dev/null; then
        INSTALLED_PACKAGES+=("opencode"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: opencode (npm)"; return 0
    fi
    FAILED_PACKAGES+=("opencode"); ((TOTAL_FAILED++))
    log WARNING "OpenCode install failed - try: curl -fsSL https://opencode.ai/install | bash"; return 0
}

# Cursor has a well-known prebuilt-binary AUR package (cursor-bin) - simpler
# than Fedora's yum-repo bootstrap, no repo registration needed at all.
install_cursor() {
    if command -v cursor &>/dev/null; then
        SKIPPED_PACKAGES+=("cursor"); ((TOTAL_SKIPPED++)); log INFO "Already installed: cursor"; return 0
    fi
    batch_install "Cursor" cursor-bin
}

# ========== CODE EDITORS, LANGUAGES, GENERAL DEV, DEVOPS ==========
install_code_editors() {
    # Omarchy ships Neovim by default as "omarchy-nvim" (its own default editor
    # config layer on top of neovim) - installing plain "neovim" here is
    # harmless/idempotent (is_installed/safe_install skip already-installed
    # packages) whether Omarchy or the user installed it first.
    # gnome-text-editor and gedit both exist as real official-repo ("extra")
    # packages on Arch, same as Fedora, so both are kept for parity even
    # though a non-GNOME desktop (e.g. Omarchy/Hyprland) won't need either.
    batch_install "Code Editors" vim neovim emacs nano geany gnome-text-editor gedit kate
    install_vscode; install_sublime_text
    configure_lazyvim
}

configure_lazyvim() {
    local msg="Set up LazyVim (Neovim config) with the Nordic theme?\n\nThis REPLACES ~/.config/nvim (any existing config is backed up first)."
    local do_it=false
    if command -v whiptail &>/dev/null; then
        whiptail --yesno "$msg" --yes-button "Set up" --no-button "Skip" 12 72 && do_it=true
    else
        echo -e "$msg [y/N]:"
        read -r REPLY
        { [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; } && do_it=true
    fi
    if $do_it; then install_lazyvim; else log INFO "Skipped LazyVim setup"; fi
}

install_lazyvim() {
    # NOTE: on Omarchy, ~/.config/nvim is already populated by omarchy-nvim -
    # the backup-then-clone logic below handles that exactly like any other
    # pre-existing config, so no special-casing is needed here.
    if [ -z "$SUDO_USER" ] || [ "$SUDO_USER" = "root" ]; then
        log WARNING "No target user (run via sudo from a user session) - skipping LazyVim"; return 1
    fi
    local uh; uh=$(eval echo ~"$SUDO_USER" 2>/dev/null)
    [ -z "$uh" ] && { log WARNING "Could not determine home dir - skipping LazyVim"; return 1; }
    if ! command -v nvim &>/dev/null && ! is_installed neovim; then
        log INFO "Neovim not installed - installing it for LazyVim..."; safe_install neovim
    fi
    local nvdir="$uh/.config/nvim"
    if [ -e "$nvdir" ]; then
        local bak="${nvdir}.bak.$(date +%Y%m%d_%H%M%S)"
        mv "$nvdir" "$bak" && log INFO "Backed up existing Neovim config to $bak"
    fi
    if ! su - "$SUDO_USER" -c "git clone --depth 1 https://github.com/LazyVim/starter '$nvdir'" 2>/dev/null; then
        log WARNING "LazyVim clone failed (needs network access to github.com)"; return 1
    fi
    rm -rf "$nvdir/.git"
    mkdir -p "$nvdir/lua/plugins"
    cat > "$nvdir/lua/plugins/nordic.lua" <<'EOF'
-- Nordic theme (https://github.com/AlexvZyl/nordic.nvim) for LazyVim
return {
  {
    "AlexvZyl/nordic.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("nordic").load()
    end,
  },
  { "LazyVim/LazyVim", opts = { colorscheme = "nordic" } },
}
EOF
    chown -R "$SUDO_USER:$SUDO_USER" "$nvdir"
    log SUCCESS "LazyVim + Nordic theme installed to $nvdir (launch 'nvim' to sync plugins)"
}

install_vscode() {
    # VS Code has no official-repo package on Arch (the closest official-ish
    # option is the community-maintained OSS build "code", which is itself
    # only in the AUR too - not in [extra]). The well-known prebuilt-binary
    # AUR package straight from Microsoft is "visual-studio-code-bin" -
    # verified present on aur.archlinux.org. safe_install will pull it via
    # the AUR fallback automatically.
    if command -v code &>/dev/null; then
        SKIPPED_PACKAGES+=("code"); ((TOTAL_SKIPPED++)); log INFO "VS Code already installed"; return 0
    fi
    batch_install "VS Code" visual-studio-code-bin
}

install_sublime_text() {
    # Confirmed on aur.archlinux.org: "sublime-text-4" is the current stable
    # AUR package name (there's also sublime-text-3 legacy and
    # sublime-text-dev for the dev build) - not in official repos.
    if command -v subl &>/dev/null; then
        SKIPPED_PACKAGES+=("sublime-text"); ((TOTAL_SKIPPED++)); log INFO "Sublime Text already installed"; return 0
    fi
    batch_install "Sublime Text" sublime-text-4
}

install_bruno() {
    # No official-repo or reliably-working AUR package confirmed for Bruno
    # at the time of writing (AUR entries for it have historically been
    # flaky/unmaintained) - Flathub's com.usebruno.Bruno is the dependable
    # cross-distro path, same as upstream recommends.
    flatpak_install_flathub com.usebruno.Bruno "Bruno"
}

install_python() {
    # All confirmed present in official [extra]: python-pip, python-virtualenv,
    # ipython (unprefixed - it's an application, not a library), python-pipx.
    batch_install "Python" python python-pip python-virtualenv ipython python-pipx
}

install_web_dev() {
    install_nodejs_full
    batch_install "Web Server - Nginx" nginx
    batch_install "Web Server - Apache (not started)" apache php-fpm php composer
}

install_nodejs_full() {
    batch_install "Node.js" nodejs npm
    install_npm_packages
}
install_nodejs_dev() { install_nodejs_full; }

install_npm_packages() {
    if ! command -v npm &>/dev/null; then
        log INFO "npm not found - skipping global npm packages"; return 1
    fi
    log INFO "Installing global npm packages..."
    if npm install -g npm-check-updates nodemon pm2 webpack webpack-cli eslint prettier 2>/dev/null; then
        log SUCCESS "Installed global npm packages"
    else
        log WARNING "Some global npm packages may have failed to install"
    fi
}

install_java() {
    # Confirmed on archlinux.org/packages (extra): jdk-openjdk is the
    # metapackage tracking the current LTS, and gradle, maven, ant, junit are
    # all present in [extra] too - no AUR needed. Arch doesn't ship a
    # separate "openjdk-doc" package (Fedora-specific split); javadoc is
    # bundled with jdk-openjdk itself.
    batch_install "Java" jdk-openjdk gradle maven ant junit
    flatpak_install_flathub com.jetbrains.IntelliJ-IDEA-Community "IntelliJ IDEA Community"
}

install_c_cpp() {
    # ninja (not "ninja-build") and pkgconf (not "pkgconf-pkg-config") are
    # the correct Arch names - pkgconf is Arch's default pkg-config provider.
    batch_install "C/C++" \
        gcc gcc-fortran clang cmake make ninja ccache \
        autoconf automake libtool m4 bison flex gettext pkgconf \
        cppcheck valgrind gdb ltrace strace
}

install_go() {
    # Confirmed: official package is simply "go" (in [extra]), not "golang".
    if command -v go &>/dev/null; then
        SKIPPED_PACKAGES+=("go"); ((TOTAL_SKIPPED++)); log INFO "Go already installed"; return 0
    fi
    batch_install "Go" go
}

install_rust() {
    if command -v rustc &>/dev/null; then
        SKIPPED_PACKAGES+=("rust"); ((TOTAL_SKIPPED++)); log INFO "Rust already installed"; return 0
    fi
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        log INFO "Installing Rust via rustup (as $SUDO_USER)..."
        if su - "$SUDO_USER" -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y' 2>/dev/null; then
            INSTALLED_PACKAGES+=("rust (rustup)"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: Rust via rustup (~/.cargo/bin)"
            return 0
        fi
    fi
    log INFO "Falling back to distro rust package..."
    # Arch's official "rust" package is a single bundle (rustc + cargo +
    # stdlib) - no split rust-vs-cargo situation to worry about here.
    batch_install "Rust" rust
}

install_php() {
    # php-gd/php-curl/php-pgsql/php-sqlite confirmed in [extra]. Unlike
    # Fedora, Arch does NOT split out php-xml/php-mbstring/php-json - those
    # are compiled into the base "php" package, so they're intentionally
    # omitted here rather than listed as separate (nonexistent) packages.
    batch_install "PHP" \
        php php-fpm php-gd php-curl php-pgsql php-sqlite composer
}

install_ruby() {
    # ruby-bundler is a real, current official-repo ([extra]) package
    # (provides the `bundle`/`bundler` gem). rubygems ships bundled inside
    # the main "ruby" package on Arch rather than being separate.
    batch_install "Ruby" ruby ruby-bundler
}

install_dotnet() {
    # Confirmed on archlinux.org/packages: dotnet-sdk and aspnet-runtime are
    # both real, current packages in official [extra] - no AUR fallback
    # needed (this used to require a Microsoft-maintained AUR package).
    batch_install ".NET" dotnet-sdk aspnet-runtime
}

install_dev_tools() {
    batch_install "Dev Tools" \
        jq tig subversion make cmake \
        autoconf automake bison flex gettext pkgconf man-db man-pages less
    install_bruno
}

install_devops() {
    install_docker_standalone
    install_azure_cli
    install_lazygit
}

install_docker_standalone() {
    batch_install "Docker (standalone)" docker docker-compose
    if is_installed docker; then
        systemctl enable --now docker 2>/dev/null
        [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ] && usermod -aG docker "$SUDO_USER" 2>/dev/null
    fi
    # install_docker_libvirt_forward_fix is defined in the Containers
    # category below - not redefined here.
    install_docker_libvirt_forward_fix
}

install_azure_cli() {
    # Confirmed: azure-cli is now in the official [extra] repo (no longer
    # AUR-only).
    if command -v az &>/dev/null; then
        SKIPPED_PACKAGES+=("azure-cli"); ((TOTAL_SKIPPED++)); log INFO "Azure CLI already installed"; return 0
    fi
    batch_install "Azure CLI" azure-cli
}

install_lazygit() {
    # Confirmed: lazygit is in the official [extra] repo on current Arch
    # (unlike Fedora's historical need for a `go install`/COPR fallback) -
    # that fallback logic is unnecessary here and intentionally omitted.
    if command -v lazygit &>/dev/null; then
        SKIPPED_PACKAGES+=("lazygit"); ((TOTAL_SKIPPED++)); log INFO "lazygit already installed"; return 0
    fi
    batch_install "lazygit" lazygit
}

# ========== DATABASES ==========
install_databases() {
    # MariaDB is Arch's default MySQL-compatible server; pacman resolves
    # mariadb-libs/mariadb-clients as dependencies automatically.
    batch_install "Databases" mariadb sqlite sqlitebrowser memcached
    # Arch moved `redis` to the AUR (deprecated/unmaintained there) and
    # replaced it in [extra] with `valkey` in 2024 over Redis's license
    # change - the same dispute that drove Fedora to valkey too. Unlike
    # Fedora there's no "offer both" question: valkey is the only actively
    # maintained redis-compatible option in the official repos.
    batch_install "Valkey (Redis-compatible)" valkey
    if package_exists postgresql; then
        batch_install "PostgreSQL" postgresql
        if is_installed postgresql && [ ! -d /var/lib/postgres/data ]; then
            log INFO "Initializing PostgreSQL database cluster..."
            # Deliberately NOT "su - postgres -c ...": Arch's postgres system
            # user has shell /usr/bin/nologin, and `su - USER -c CMD` runs
            # CMD through USER's login shell - nologin just refuses, silently
            # no-opping the whole init step. `sudo -u postgres bash -c "..."`
            # forces a real shell regardless of the account's configured
            # shell, per the Arch Wiki PostgreSQL page's own recommendation.
            sudo -u postgres bash -c "initdb --locale en_US.UTF-8 -D /var/lib/postgres/data" 2>/dev/null \
                && systemctl enable --now postgresql 2>/dev/null \
                && log SUCCESS "PostgreSQL initialized and started" \
                || log WARNING "initdb failed - initialize manually"
        fi
    fi
    # MariaDB also needs an explicit first-run init step on Arch, unlike
    # Fedora/Debian where the package's own post-install scriptlet does it.
    if is_installed mariadb && [ ! -d /var/lib/mysql/mysql ]; then
        log INFO "Initializing MariaDB data directory..."
        mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql 2>/dev/null \
            && systemctl enable --now mariadb 2>/dev/null \
            && log SUCCESS "MariaDB initialized and started" \
            || log WARNING "mariadb-install-db failed - initialize manually"
    fi
    install_dbeaver
}

install_dbeaver() {
    if is_installed dbeaver; then
        SKIPPED_PACKAGES+=("dbeaver"); ((TOTAL_SKIPPED++)); log INFO "Already installed: dbeaver"; return 0
    fi
    # Unlike Fedora (which needed a third-party COPR because no official rpm
    # existed), Arch ships DBeaver Community Edition straight from [extra]
    # as plain "dbeaver" - no AUR/dbeaver-ce fallback needed.
    batch_install "DBeaver" dbeaver
}

# ========== CONTAINERS & VMS ==========
install_containers() {
    # `iptables` is added explicitly: Arch's `docker` package now depends on
    # `nftables` directly rather than `iptables`, and libvirt only lists
    # iptables-nft/iptables as an OPTIONAL dependency - so neither package is
    # guaranteed to pull in the `iptables` command our forward-fix script
    # below shells out to. Installing it explicitly guarantees it's present.
    batch_install "Containers" docker docker-compose podman iptables
    if is_installed docker; then
        systemctl enable --now docker 2>/dev/null
        [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ] && usermod -aG docker "$SUDO_USER" 2>/dev/null \
            && log INFO "Added $SUDO_USER to the docker group (log out/in to take effect)"
    fi
    # qemu-full is Arch's current comprehensive QEMU metapackage (all
    # emulators + GUI/audio backends), alongside the leaner qemu-base/
    # qemu-desktop variants - qemu-full is the right choice for a full
    # desktop virt-manager setup. cockpit/cockpit-machines/cockpit-podman
    # are all confirmed present in Arch's official [extra] repo.
    batch_install "Virtualization" \
        qemu-full libvirt virt-install virt-manager virt-viewer \
        gnome-boxes cockpit cockpit-machines cockpit-podman
    if is_installed libvirt; then
        systemctl enable --now libvirtd 2>/dev/null
        [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ] && usermod -aG libvirt "$SUDO_USER" 2>/dev/null \
            && log INFO "Added $SUDO_USER to the libvirt group (log out/in to take effect)"
        install_virtio_win
    fi
    install_docker_libvirt_forward_fix
}

# Virtio-Win: the Windows guest drivers (network, disk, balloon, etc) needed
# for a Windows VM under KVM/QEMU to get more than a crawling emulated IDE
# disk and no network. The AUR package's PKGBUILD installs the ISO straight
# to /var/lib/libvirt/images/virtio-win.iso itself (no /usr/share detour like
# Fedora's RPM) - so once safe_install's normal AUR fallback lands it, there's
# nothing left to symlink. Falls back to a direct one-shot download of
# upstream's "latest stable" ISO if yay/AUR isn't available (no SUDO_USER,
# no network to aur.archlinux.org, etc) so a working ISO still lands either way.
install_virtio_win() {
    if [ -e /var/lib/libvirt/images/virtio-win.iso ]; then
        SKIPPED_PACKAGES+=("Virtio-Win drivers"); ((TOTAL_SKIPPED++)); log INFO "Already installed: Virtio-Win drivers"; return 0
    fi
    batch_install "Virtio-Win Drivers" virtio-win
    [ -e /var/lib/libvirt/images/virtio-win.iso ] && return 0
    log WARNING "virtio-win (AUR) unavailable - downloading the latest stable ISO directly instead"
    download_virtio_win_iso
}

# Static URL maintained upstream to always point at the current stable
# release - no version parsing/GitHub-releases lookup needed.
download_virtio_win_iso() {
    mkdir -p /var/lib/libvirt/images
    log INFO "Downloading latest stable Virtio-Win ISO..."
    local url="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
    local tmp="/var/lib/libvirt/images/.virtio-win.iso.tmp"
    if curl -fL --retry 3 -o "$tmp" "$url" 2>/dev/null && [ -s "$tmp" ]; then
        mv "$tmp" /var/lib/libvirt/images/virtio-win.iso
        INSTALLED_PACKAGES+=("Virtio-Win ISO"); ((TOTAL_INSTALLED++))
        log SUCCESS "Downloaded: Virtio-Win ISO -> /var/lib/libvirt/images/virtio-win.iso"
    else
        rm -f "$tmp"
        FAILED_PACKAGES+=("Virtio-Win ISO"); ((TOTAL_FAILED++))
        log WARNING "Virtio-Win ISO download failed (needs network access to fedorapeople.org)"
    fi
}

# Docker sets the legacy iptables FORWARD chain's default policy to DROP and
# routes everything through its own DOCKER-USER/DOCKER-FORWARD chains, and it
# neither restores the policy to ACCEPT when it stops nor scopes the DROP to
# just its own bridges. Installing Docker and libvirt side by side silently
# kills internet access for every libvirt NAT-networked VM (virbr0, virbr1,
# ...): DHCP/local-subnet traffic still works (never touches FORWARD - it's
# answered directly by dnsmasq on the host), so a VM looks "half connected" -
# gets a real IP, can ping its own gateway, but outbound traffic to the real
# internet silently vanishes. This is a genuinely package-manager-agnostic
# iptables/systemd fix, identical on Fedora, Ubuntu, and Arch - see
# install_containers above for why `iptables` is installed explicitly here.
# One further wrinkle flagged for awareness rather than acted on: newer
# Docker Engine releases can manage firewall rules through a native nftables
# backend instead of the legacy iptables-nft compat layer. In that mode
# DOCKER-USER may live as a native nftables chain that the `iptables -C/-I
# DOCKER-USER ...` calls below still reach correctly through the compat shim
# in normal configurations, but if Docker's nftables integration changes
# further upstream this should be re-verified against `nft list ruleset`.
install_docker_libvirt_forward_fix() {
    if ! is_installed docker || ! is_installed libvirt; then
        log INFO "Skipping Docker/libvirt forwarding fix - both Containers and Virtualization need to be installed first"
        return 0
    fi
    if [ -f /etc/systemd/system/docker-libvirt-forward-fix.service ]; then
        log INFO "Docker/libvirt forwarding fix already installed"
        return 0
    fi
    log INFO "Installing Docker <-> libvirt forwarding fix (DOCKER-USER virbr+ exception)..."
    cat > /usr/local/sbin/docker-libvirt-forward-fix.sh <<'DLFF_EOF'
#!/bin/bash
set -e
for dir_flag in -i -o; do
    iptables -C DOCKER-USER "$dir_flag" virbr+ -j ACCEPT 2>/dev/null \
        || iptables -I DOCKER-USER "$dir_flag" virbr+ -j ACCEPT
done
DLFF_EOF
    chmod +x /usr/local/sbin/docker-libvirt-forward-fix.sh
    cat > /etc/systemd/system/docker-libvirt-forward-fix.service <<'DLFF_UNIT_EOF'
[Unit]
Description=Allow libvirt bridge traffic through Docker's FORWARD chain
After=docker.service libvirtd.service
Wants=docker.service libvirtd.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/docker-libvirt-forward-fix.sh

[Install]
WantedBy=multi-user.target
DLFF_UNIT_EOF
    reload_systemd
    if systemctl enable --now docker-libvirt-forward-fix.service 2>/dev/null; then
        log SUCCESS "Docker/libvirt forwarding fix applied now and will reapply on every boot"
    else
        log WARNING "Could not enable docker-libvirt-forward-fix.service - apply manually: sudo iptables -I DOCKER-USER -i virbr+ -j ACCEPT && sudo iptables -I DOCKER-USER -o virbr+ -j ACCEPT"
    fi
}

# ========== GAMING ==========
install_gaming() {
    # steam and lib32-* packages need [multilib]; main() already calls
    # bootstrap_multilib once, but it's idempotent, so call it again here in
    # case a user jumps straight into this menu item.
    bootstrap_multilib
    batch_install "Gaming" steam lutris gamemode mangohud lib32-gamemode lib32-mangohud
    # Unlike Fedora, Arch's gamemode package does NOT auto-enroll the user
    # into a "gamemode" group - without membership, gamemoded is denied
    # permission to change the CPU governor/process niceness, so most of its
    # actual optimizations silently no-op. Add the invoking user explicitly.
    if is_installed gamemode; then
        [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ] && usermod -aG gamemode "$SUDO_USER" 2>/dev/null \
            && log INFO "Added $SUDO_USER to the gamemode group (log out/in to take effect)"
    fi
    # Omarchy already ships its own on-demand installers
    # (omarchy-install-gaming-steam, -lutris, -gpu-lib32) for these same
    # packages - calling batch_install here doesn't conflict with or
    # duplicate that, pacman/safe_install just no-ops on anything already
    # installed.
}

# ========== WINDOWS SOFTWARE SUPPORT (WINE) ==========
install_windows_support() {
    # Wine's 32-bit Windows application support depends on [multilib] the
    # same way Steam does - ensure it's enabled here too rather than
    # assuming install_gaming already ran first.
    bootstrap_multilib
    batch_install "Wine" wine wine-mono wine-gecko winetricks zenity
    if command -v winetricks &>/dev/null; then
        cat > /usr/share/applications/winetricks.desktop <<'EOF'
[Desktop Entry]
Name=Winetricks
Comment=Install and configure Windows software components for Wine
Exec=winetricks --gui
Icon=wine
Terminal=false
Type=Application
Categories=System;Utility;
EOF
        log SUCCESS "Created winetricks.desktop launcher"
    fi
}

# ========== BROWSERS ==========
# Almost every browser here needed a hand-rolled vendor-repo dance on Fedora
# (rpm --import + registering a yum repo). On Arch nearly all of them have a
# well-established AUR package (usually a prebuilt "-bin" package, no
# compiling), and several landed in the official [extra] repo outright -
# this whole category collapses to a single batch_install call per browser.
install_browsers() {
    install_brave
    install_vivaldi
    install_edge
    install_chrome
    install_librewolf
    install_zen
    install_floorp
}

# AUR-only. brave-bin is the actively maintained package; the plain source
# package "brave" no longer exists in the AUR at all.
install_brave() { batch_install "Brave" brave-bin; }

# Official [extra] repo on current Arch, NOT AUR - Vivaldi ships a native
# Arch package upstream now.
install_vivaldi() { batch_install "Vivaldi" vivaldi; }

# AUR-only. microsoft-edge-stable-bin confirmed current/actively maintained
# (there have been a few competing edge AUR packages over the years).
install_edge() { batch_install "Microsoft Edge" microsoft-edge-stable-bin; }

# AUR-only. Its PKGBUILD downloads and repackages Google's official .deb, so
# it can occasionally break for a short window if Google changes their
# download URL/packaging - in practice it's fixed quickly given its
# popularity (2000+ AUR votes).
install_chrome() { batch_install "Google Chrome" google-chrome; }

# Official [extra] repo on current Arch, NOT AUR - a prebuilt package, no
# from-source AUR build/long compile to worry about.
install_librewolf() { batch_install "LibreWolf" librewolf; }

# AUR-only. zen-browser-bin is the maintained/popular choice; a from-source
# zen-browser AUR package also exists but pulls a heavy rust/llvm/wasi build
# toolchain - avoid it in favor of the -bin package.
install_zen() { batch_install "Zen Browser" zen-browser-bin; }

# AUR-only. floorp-bin exists and is actively maintained - no need for the
# Flathub fallback the Fedora script had to reach for.
install_floorp() { batch_install "Floorp" floorp-bin; }

# ========== COMMUNICATION ==========
install_communication() {
    install_signal
    install_discord
    install_telegram
    install_teams
}

# Official [extra] repo on current Arch - a nice simplification vs Fedora,
# which needed a dedicated vendor repo for the same app.
install_signal() { batch_install "Signal" signal-desktop; }

# Official [extra] repo on current Arch, unlike Fedora where Discord
# required enabling RPM Fusion nonfree.
install_discord() { batch_install "Discord" discord; }

# Official [extra] repo on current Arch, unlike Fedora's RPM-Fusion
# dependency for the same package.
install_telegram() { batch_install "Telegram" telegram-desktop; }

# AUR-only (same upstream community project - eneshecan/teams-for-linux -
# the Fedora/Ubuntu scripts also consume via their own repos).
install_teams() { batch_install "Microsoft Teams" teams-for-linux; }

# ========== DESKTOP APPS ==========
install_desktop_apps() {
    install_spotify
    install_slack
    install_remmina
    install_windows_app
    install_teamviewer
    install_1password
}

# AUR-only, confirmed - there is no official-repo path for Spotify on Arch
# either, matching the Fedora script's own conclusion (Flathub there).
install_spotify() { batch_install "Spotify" spotify; }

# AUR-only. slack-desktop is the most-voted/actively-maintained Slack
# option; no evidence it needs anything like Fedora's manual slack.com
# URL-scraping workaround - its PKGBUILD handles fetching Slack's package
# itself and has stayed reliable.
install_slack() { batch_install "Slack" slack-desktop; }

# Official [extra] repo. freerdp is only an *optional* dependency of remmina
# (enables the RDP plugin) - not pulled in automatically - so it must still
# be requested explicitly here, mirroring Fedora's need for a separate
# remmina-plugins-rdp package.
install_remmina() { batch_install "Remmina" remmina freerdp; }

# AUR-only, community-maintained - TeamViewer has no official Arch/AUR
# support the way it lists real vendor rpm/deb repos for Fedora/Ubuntu.
# CAUTION: this AUR package has carried an open out-of-date flag before
# without being bumped for a while - fine for general use, but don't assume
# it's always current; check aur.archlinux.org/packages/teamviewer if a
# specific version matters.
install_teamviewer() { batch_install "TeamViewer" teamviewer; }

# AUR-only. Note: 1Password is not on Arch/AUR's official supported-platform
# list (unlike their real Fedora rpm/Ubuntu deb repos) - treat this as
# carrying no formal vendor support guarantee regardless of maintainer.
install_1password() { batch_install "1Password" 1password; }

# "Windows App" (mariuszkopowski/windows-app-for-linux) - confirmed via AUR
# search that no AUR package exists for this project, so unlike every other
# app in this category it keeps the GitHub-releases Flatpak-bundle download
# logic (plain Flatpak/curl mechanics, nothing Fedora-specific), installed
# into the desktop user's per-user Flatpak scope.
install_windows_app() {
    local app_id="io.github.mariuszkopowski.WindowsAppForLinux"
    local repo="mariuszkopowski/windows-app-for-linux"
    if [ -z "$SUDO_USER" ] || [ "$SUDO_USER" = "root" ]; then
        log WARNING "No desktop user (SUDO_USER) - skipping Windows App"
        SKIPPED_PACKAGES+=("Windows App"); ((TOTAL_SKIPPED++)); return 1
    fi
    if ! command -v flatpak &>/dev/null; then
        batch_install "Flatpak" flatpak
    fi
    if ! command -v flatpak &>/dev/null; then
        log WARNING "flatpak unavailable - install manually: flatpak install --user \"Windows*.flatpak\""
        FAILED_PACKAGES+=("Windows App"); ((TOTAL_FAILED++)); return 1
    fi
    if su - "$SUDO_USER" -c "flatpak info --user '$app_id'" &>/dev/null; then
        SKIPPED_PACKAGES+=("Windows App"); ((TOTAL_SKIPPED++))
        log INFO "Already installed: Windows App (flatpak)"; return 0
    fi
    local api_json url tmp
    api_json=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null)
    if [ -z "$api_json" ]; then
        log WARNING "Could not reach GitHub's API for $repo (network issue, or GitHub's unauthenticated rate limit - 60 requests/hour per IP - may already be used up) - skipping Windows App"
        FAILED_PACKAGES+=("Windows App"); ((TOTAL_FAILED++)); return 1
    fi
    # Match any .flatpak asset rather than requiring "x86_64" in the
    # filename specifically - the current release names it
    # "Windows.App-<ver>-x86_64.flatpak" so the stricter match still works
    # today, but there's only ever one .flatpak asset per release, so this
    # is less likely to silently break if that naming ever changes upstream.
    url=$(printf '%s' "$api_json" | grep -oP '"browser_download_url":\s*"\K[^"]*\.flatpak(?=")')
    if [ -z "$url" ]; then
        log WARNING "Windows App's latest GitHub release has no .flatpak asset - skipping (check https://github.com/$repo/releases/latest manually)"
        FAILED_PACKAGES+=("Windows App"); ((TOTAL_FAILED++)); return 1
    fi
    tmp=$(mktemp -d)
    if ! curl -L -f --retry 2 -o "$tmp/windows-app.flatpak" "$url" 2>/dev/null; then
        rm -rf "$tmp"
        log WARNING "Windows App download failed ($url) - skipping"
        FAILED_PACKAGES+=("Windows App"); ((TOTAL_FAILED++)); return 1
    fi
    chmod 755 "$tmp" 2>/dev/null; chmod 644 "$tmp/windows-app.flatpak" 2>/dev/null
    chown "$SUDO_USER" "$tmp" "$tmp/windows-app.flatpak" 2>/dev/null || true
    su - "$SUDO_USER" -c "flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo" || true
    # Deliberately NOT silenced with 2>/dev/null on this specific call (unlike
    # the curl steps above): this is the step that was reported failing in
    # practice, and swallowing its stderr means the real reason (a runtime
    # conflict between a system-wide and user-scope flathub remote, a stuck
    # confirmation prompt, disk space, etc.) never gets seen - it just shows
    # up as a generic "Failed: Windows App" with nothing to go on.
    if su - "$SUDO_USER" -c "flatpak install --user -y '$tmp/windows-app.flatpak'"; then
        rm -rf "$tmp"
        INSTALLED_PACKAGES+=("Windows App"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: Windows App (flatpak) - launch with: flatpak run $app_id"
        return 0
    fi
    if su - "$SUDO_USER" -c "flatpak info --user '$app_id'" &>/dev/null; then
        rm -rf "$tmp"
        INSTALLED_PACKAGES+=("Windows App"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: Windows App (flatpak) - launch with: flatpak run $app_id"
        return 0
    fi
    rm -rf "$tmp"
    FAILED_PACKAGES+=("Windows App"); ((TOTAL_FAILED++))
    log ERROR "Failed: Windows App (flatpak) - see the flatpak error output above for the actual reason"
    return 1
}

# ========== CREATIVE SUITE ==========
# Fedora used its "Fedora Jam"/"Design Suite" dnf comps groups here - Arch
# has NO equivalent metapackage/group at all (not even a partial one), so
# every sub-category below is hand-curated to cover the same real-world app
# set, individually verified against archlinux.org/packages and aur.archlinux.org.
install_creative_audio() {
    # Covers the same DAW/synth/plugin stack as Fedora Jam: Ardour, Audacity,
    # Carla, Hydrogen, Guitarix, plus JACK/PipeWire glue and LV2 plugins.
    # Two names don't carry over as-is: Fedora's "lsp-plugins" is packaged on
    # Arch as "lsp-plugins-lv2" (no bare "lsp-plugins" exists), and Fedora's
    # "pulseaudio-utils" doesn't exist on Arch at all - on a PipeWire system
    # (Arch's default, including Omarchy) pactl/pacmd/paplay ship in
    # "libpulse" instead.
    batch_install "Audio Production" \
        ardour audacity carla hydrogen guitarix qjackctl \
        lsp-plugins-lv2 calf libpulse soundconverter easytag pavucontrol
}

install_creative_graphics() {
    # gimp/inkscape/krita/blender/darktable/pitivi all confirmed in official
    # [extra]. CONFIDENCE NOTE (Pitivi): kept rather than dropped - it's
    # still packaged cleanly in [extra], but upstream Pitivi hasn't cut a
    # new stable release since March 2023 and project activity is low; it's
    # the least actively developed app in this whole category. Its AUR
    # fallback (pitivi-git) has reported missing-dependency issues, so don't
    # rely on that if [extra] ever drops the plain package.
    batch_install "Graphics & Design" gimp inkscape krita blender darktable pitivi
    # nomacs (AUR-only) currently fails to build/install: its PKGBUILD
    # depends on "quazip-qt6", which does not exist anywhere - not in the
    # official repos, not in the AUR (only quazip-qt5/-qt4/-legacy and
    # mingw-w64 cross-compile variants exist; confirmed via a live AUR RPC
    # query) - so yay can never resolve that dependency no matter what.
    # This is a break in nomacs's own AUR package, not something this
    # script can work around by picking a different name. Swapped in qimgv
    # instead: a Qt6 image viewer/browser filling the same role, maintained
    # by the same AUR maintainer (FabioLolix) as nomacs, with no such broken
    # dependency as of this writing.
    batch_install "Graphics (extra)" qimgv flameshot imagemagick graphicsmagick optipng jpegoptim pngquant libwebp
    set_flameshot_hotkey
}

install_creative_video() {
    # mkvtoolnix-cli/mkvtoolnix-gui, kdenlive, shotcut, obs-studio, mpv, vlc,
    # yt-dlp all confirmed in official [extra] - obs-studio in particular
    # needs no COPR/RPM-Fusion-style side repo on Arch, unlike Fedora.
    batch_install "Video Editing" \
        kdenlive shotcut obs-studio mkvtoolnix-cli mkvtoolnix-gui mpv vlc yt-dlp
    install_multimedia_codecs
}

install_creative_photography() {
    batch_install "Photography" darktable rawtherapee digikam hugin gthumb
}

install_creative_publishing() {
    batch_install "Publishing" scribus fontforge calibre
}

install_creative_full() {
    install_creative_graphics
    install_creative_video
    install_creative_audio
    install_creative_photography
    install_creative_publishing
}

# Bind Print Screen to Flameshot. GNOME-specific (org.gnome.settings-daemon
# media-keys custom-keybindings schema) - only does anything if a GNOME
# session is actually running, which is never true under Omarchy's
# Hyprland+Quickshell shell (Omarchy has its own native screenshot tool/
# keybinding, omarchy-capture-*) and only sometimes true on a plain Arch box
# someone set up with GNOME.
set_flameshot_hotkey() {
    if ! command -v flameshot &>/dev/null; then
        log INFO "Flameshot not installed - skipping Print Screen keybinding"; return 0
    fi
    if $IS_OMARCHY; then
        log INFO "Omarchy already has its own screenshot tool/keybinding (omarchy-capture-*) - not touching Print Screen. Launch Flameshot manually with 'flameshot gui' if you want it instead."
        return 0
    fi
    local user uid
    if ! read -r user uid < <(resolve_desktop_session); then
        log INFO "No desktop session - skipping Flameshot keybinding (bind Print to 'flameshot gui' later)"; return 0
    fi

    local schema="org.gnome.settings-daemon.plugins.media-keys"
    local kb_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/flameshot/"
    local current
    current=$(gsettings_as_user "$user" "$uid" get "$schema" custom-keybindings 2>/dev/null)
    local paths=()
    if [[ "$current" =~ \[(.*)\] ]]; then
        local inner="${BASH_REMATCH[1]}" raw part
        IFS=',' read -ra raw <<< "$inner"
        for part in "${raw[@]}"; do
            part="${part//\'/}"; part="${part// /}"
            [ -n "$part" ] && paths+=("$part")
        done
    fi
    local exists=false p
    for p in "${paths[@]}"; do [ "$p" = "$kb_path" ] && exists=true; done
    $exists || paths+=("$kb_path")
    local gv="[" first=true
    for p in "${paths[@]}"; do
        $first && first=false || gv+=", "
        gv+="'${p}'"
    done
    gv+="]"

    gsettings_as_user "$user" "$uid" set "$schema" custom-keybindings "$gv" 2>/dev/null
    local rel="${schema}.custom-keybinding:${kb_path}"
    gsettings_as_user "$user" "$uid" set "$rel" name 'Flameshot' 2>/dev/null
    gsettings_as_user "$user" "$uid" set "$rel" command 'flameshot gui' 2>/dev/null
    if gsettings_as_user "$user" "$uid" set "$rel" binding 'Print' 2>/dev/null; then
        log SUCCESS "Print Screen bound to Flameshot ('flameshot gui') - takes effect immediately"
        return 0
    fi
    log WARNING "Could not set Flameshot keybinding on Print"
    return 1
}

# ffmpeg-free -> ffmpeg swap + GStreamer ugly/bad/libav tiers. On Arch, plain
# `ffmpeg` in [extra] is the full/unencumbered build already (Arch has never
# shipped a patent-pared-down "ffmpeg-free") - no "swap" step needed, just
# install ffmpeg and the GStreamer plugin sets directly.
install_multimedia_codecs() {
    log INFO "Installing multimedia codecs..."
    batch_install "FFmpeg" ffmpeg
    batch_install "GStreamer plugins" \
        gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav
}

# ========== OFFICE & PRODUCTIVITY ==========
install_office() {
    # libreoffice-fresh (tracks the current upstream feature release) chosen
    # over libreoffice-still (older maintenance branch). pandoc-cli is
    # correct on Arch too (not a Fedora quirk) - a bare "pandoc" package
    # doesn't exist here; the Haskell library is "haskell-pandoc".
    batch_install "Office" libreoffice-fresh okular evince zathura pandoc-cli
}

# ========== SYSTEM UTILITIES ==========
install_system_utils() {
    # wireshark differs from Fedora's single GUI+CLI package: Arch splits it
    # into wireshark-cli (tshark/core) and wireshark-qt (the Qt GUI, depends
    # on wireshark-cli) - both listed explicitly for clarity.
    batch_install "System Utils" \
        htop iotop sysstat glances \
        nethogs iftop nload vnstat tcpdump wireshark-cli wireshark-qt \
        lsof strace ltrace valgrind gdb \
        tmux screen zsh fish fzf ripgrep tree ncdu rsync unzip bat
}

# ========== ANDROID TOOLS ==========
install_android_tools() {
    # android-tools (adb/fastboot) and android-udev (device udev rules) are
    # two separate official [extra] packages - android-tools does NOT pull
    # android-udev in automatically (it's an optional, not hard, dependency).
    # scrcpy is directly in official [extra] on Arch (depends on
    # android-tools already) - unlike Fedora, which needs a COPR for it, so
    # no third-party repo step is required at all here.
    batch_install "Android Tools" android-tools android-udev scrcpy
}

# ========== SECURITY TOOLS ==========
install_security_tools() {
    # Network: Arch's "nmap" bundles ncat itself (no separate nmap-ncat like
    # Fedora), and dig/nslookup live in the package literally named "bind"
    # (Fedora calls the same thing bind-utils). hping3's Arch package is
    # named "hping" (still installs the hping3/hping2/hping binaries).
    batch_install "Security - Network" \
        nmap masscan hping bind
    # Web: nikto, sqlmap and gobuster all landed in Arch's official [extra]
    # repo (AUR/BlackArch-only in the past). whatweb and wfuzz have no
    # official package and only exist as AUR sources with real maintenance
    # risk (whatweb flagged by its own maintainer for possible removal;
    # wfuzz has open Python 3.13 build issues) - safe_install still tries
    # them via AUR automatically, but these two are the most realistic
    # candidates for actually needing install_blackarch_repo's prebuilt
    # binaries if/when their AUR builds break.
    batch_install "Security - Web" \
        nikto sqlmap gobuster whatweb wfuzz
    # Cracking & Wireless: all confirmed in official [extra], including
    # macchanger (Fedora needs it from a third-party repo too; Arch ships it
    # directly).
    batch_install "Security - Cracking & Wireless" \
        john hashcat hydra aircrack-ng macchanger
    # Forensics & RE: radare2, binwalk, yara and perl-image-exiftool are all
    # official [extra] packages. sleuthkit has no plain "sleuthkit" package
    # anywhere on Arch right now - only "sleuthkit-git" exists in the AUR.
    # steghide is AUR-only with an open, unresolved libjpeg-turbo
    # build-dependency issue - another realistic BlackArch-fallback
    # candidate alongside whatweb/wfuzz above.
    batch_install "Security - Forensics & RE" \
        radare2 binwalk sleuthkit-git steghide yara perl-image-exiftool
    # Hardening: lynis, rkhunter, clamav and fail2ban are all official
    # [extra] packages. clamav's Arch package bundles freshclam directly (no
    # separate clamav-freshclam split like Fedora). chkrootkit and aide have
    # no official package, only AUR.
    batch_install "Security - Hardening" \
        lynis chkrootkit rkhunter clamav fail2ban aide
    # Firewall & Privacy: firewalld+firewall-config, openvpn,
    # wireguard-tools, proxychains-ng, torsocks, keepassxc and ettercap are
    # ALL confirmed in Arch's official [extra] repo - none of these need AUR
    # or BlackArch on Arch, unlike on Fedora.
    batch_install "Security - Firewall & Privacy" \
        firewalld firewall-config openvpn wireguard-tools proxychains-ng torsocks keepassxc ettercap
    if is_installed firewalld; then
        log INFO "firewalld installed (zone-based, matches the Fedora setup) - Arch's more idiomatic minimal alternative is 'ufw' if you'd rather have a simple allow/deny rule list instead; the two firewall managers conflict, so this script does not install both - swap manually with 'pacman -S ufw' + 'systemctl disable --now firewalld' if you prefer it"
    fi
}

install_security_defensive() {
    # audit (auditd/auditctl) lives in Arch's [core] repo, not AUR - often
    # already pulled in as a base dependency.
    batch_install "Defensive - Hardening & Integrity" \
        lynis chkrootkit rkhunter aide audit
    batch_install "Defensive - Anti-Malware" \
        clamav
    # fail2ban is official [extra]. suricata has no official-repo package on
    # Arch - it's AUR-only, currently actively maintained there.
    batch_install "Defensive - IDS/IPS" \
        fail2ban suricata
    batch_install "Defensive - Firewall, VPN & Credentials" \
        firewalld firewall-config openvpn wireguard-tools keepassxc
}

# Arch/Omarchy equivalent of the Fedora script's install_terra_repo: an
# opt-in, prompted bootstrap of the BlackArch pentest/security repo
# (blackarch.org), which fills the same "curated third-party collection of
# security tools" role on Arch that Terra fills on Fedora. As the comments
# above show, the vast majority of tools this script installs turned out to
# already be in Arch's official [extra] repo or the AUR, so BlackArch is
# genuinely optional here - it exists for the long tail (thousands of niche
# pentest packages) beyond what's covered above. Never called automatically
# by install_security_tools/install_security_defensive - only reachable as
# its own opt-in entry from the Drivers & Extra Repos menu.
install_blackarch_repo() {
    if grep -Eq '^\[blackarch\]' /etc/pacman.conf 2>/dev/null || is_installed blackarch-keyring; then
        SKIPPED_PACKAGES+=("blackarch-keyring"); ((TOTAL_SKIPPED++)); log INFO "Already installed: blackarch repo"; return 0
    fi

    local msg="Enable the BlackArch repo (blackarch.org)?\n\nAdds thousands of pentest/security tools not in the official Arch repos or AUR.\n\nWARNING: this is a large, uncurated third-party binary repo - enabling it adds real risk (dependency/version churn, trusting a third-party signing key, and a much bigger attack surface) compared to sticking with official repos + AUR."
    if $IS_OMARCHY; then
        msg+="\n\nOmarchy-specific warning: Omarchy is a curated, pacman-package-based system with its own 'omarchy update' guard hook on top of plain Arch. Layering a large uncurated third-party repo like BlackArch on top of that carries more real risk of interfering with Omarchy's own package set/update flow than it would on plain Arch. Your call - this is not blocked, just make sure you actually want that trade-off."
    fi

    local do_it=false
    if command -v whiptail &>/dev/null; then
        whiptail --yesno "$msg" --yes-button "Enable" --no-button "Skip" 22 78 && do_it=true
    else
        echo -e "$msg [y/N]:"
        read -r REPLY
        { [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; } && do_it=true
    fi
    if ! $do_it; then
        SKIPPED_PACKAGES+=("blackarch-keyring"); ((TOTAL_SKIPPED++)); log INFO "Skipped BlackArch repo"; return 0
    fi

    log INFO "Fetching BlackArch's bootstrap script (strap.sh)..."
    # Official bootstrap method per blackarch.org/downloads.html: download
    # strap.sh and run it as root - it adds the [blackarch] repo lines to
    # /etc/pacman.conf, imports the blackarch-keyring signing key, and
    # refreshes pacman's databases itself. There is no currently-documented
    # manual repo-line-only alternative on the downloads page.
    #
    # SECURITY NOTE: this script executes arbitrary code as root. Rather
    # than pinning a specific SHA1 checksum in this script (BlackArch's own
    # published checksum for strap.sh has a documented history of going
    # stale in their docs when the script gets updated - see
    # github.com/BlackArch/blackarch issue #1249 - so a hardcoded hash here
    # would either silently trust an out-of-date value or block a perfectly
    # legitimate update), this computes the checksum of what was actually
    # downloaded and asks YOU to cross-check it against the value currently
    # published at https://www.blackarch.org/downloads.html before it runs.
    local strap_tmp; strap_tmp="$(mktemp)"
    if ! curl -fsSL "https://blackarch.org/strap.sh" -o "$strap_tmp"; then
        rm -f "$strap_tmp"
        FAILED_PACKAGES+=("blackarch-keyring"); ((TOTAL_FAILED++))
        log ERROR "Could not download strap.sh (needs network access to blackarch.org)"; return 1
    fi
    local sha1; sha1=$(sha1sum "$strap_tmp" | awk '{print $1}')
    echo
    log INFO "Downloaded strap.sh - SHA1: ${sha1}"
    log WARNING "Open https://www.blackarch.org/downloads.html now and confirm this checksum matches the one currently published there before continuing."
    read -p "Checksum confirmed - run strap.sh as root? [y/N] " -n 1 -r; echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        rm -f "$strap_tmp"
        SKIPPED_PACKAGES+=("blackarch-keyring"); ((TOTAL_SKIPPED++)); log INFO "Skipped BlackArch repo (checksum not confirmed)"; return 0
    fi

    chmod +x "$strap_tmp"
    if "$strap_tmp" && pacman -Sy --noconfirm && is_installed blackarch-keyring; then
        rm -f "$strap_tmp"
        INSTALLED_PACKAGES+=("blackarch-keyring"); ((TOTAL_INSTALLED++))
        log SUCCESS "BlackArch repo enabled - browse tools with 'pacman -Sg' | grep blackarch, or see https://blackarch.org/tools.html"
        log INFO "BlackArch's own docs also recommend enabling multilib afterwards if you need 32-bit tool variants - not done automatically here"
    else
        rm -f "$strap_tmp"
        FAILED_PACKAGES+=("blackarch-keyring"); ((TOTAL_FAILED++))
        log WARNING "BlackArch repo setup failed - re-check https://www.blackarch.org/downloads.html for a possibly-updated strap.sh and try again"
    fi
}

# Chaotic-AUR (aur.chaotic.cx) - a large, hourly-rebuilt repo of PREBUILT
# binaries for thousands of popular AUR packages. Once enabled, it's just
# another pacman repo: anything it covers now resolves via plain
# `repo_package_exists`/`pacman -S` instead of falling through to yay's
# build-from-source AUR path in safe_install - no changes needed elsewhere
# in this script, enabling the repo alone makes those installs both faster
# and no-compile. Opt-in, same shape/risk-profile as install_blackarch_repo
# above (large uncurated third-party repo, extra Omarchy warning) - never
# called automatically.
install_chaotic_aur() {
    if grep -Eq '^\[chaotic-aur\]' /etc/pacman.conf 2>/dev/null || is_installed chaotic-keyring; then
        SKIPPED_PACKAGES+=("chaotic-keyring"); ((TOTAL_SKIPPED++)); log INFO "Already installed: Chaotic-AUR repo"; return 0
    fi

    local msg="Enable the Chaotic-AUR repo (aur.chaotic.cx)?\n\nProvides prebuilt binaries for thousands of popular AUR packages, rebuilt hourly - once enabled, safe_install in this script will pull anything it covers straight from pacman instead of compiling it from AUR source via yay, which is both faster and skips the build step entirely.\n\nWARNING: this is a large, uncurated third-party binary repo (same risk shape as BlackArch above) - enabling it means trusting a third-party signing key and prebuilt binaries instead of building from AUR source yourself."
    if $IS_OMARCHY; then
        msg+="\n\nOmarchy-specific warning: same reasoning as BlackArch - Omarchy is a curated, pacman-package-based system with its own 'omarchy update' guard hook. Layering a large hourly-rebuilt third-party repo on top of that carries more real risk of interfering with Omarchy's own package set than it would on plain Arch. Your call."
    fi

    local do_it=false
    if command -v whiptail &>/dev/null; then
        whiptail --yesno "$msg" --yes-button "Enable" --no-button "Skip" 20 78 && do_it=true
    else
        echo -e "$msg [y/N]:"
        read -r REPLY
        { [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; } && do_it=true
    fi
    if ! $do_it; then
        SKIPPED_PACKAGES+=("chaotic-keyring"); ((TOTAL_SKIPPED++)); log INFO "Skipped Chaotic-AUR repo"; return 0
    fi

    # Chaotic-AUR's own docs list multilib as a flat prerequisite ("You must
    # have the multilib repository enabled") despite the repo itself being
    # x86_64-only - no clearly stated technical reason found for it, but
    # it's their documented requirement, so honor it rather than second-guess it.
    bootstrap_multilib

    log INFO "Importing Chaotic-AUR's signing key..."
    if ! pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com 2>/dev/null \
        || ! pacman-key --lsign-key 3056513887B78AEB 2>/dev/null; then
        FAILED_PACKAGES+=("chaotic-keyring"); ((TOTAL_FAILED++))
        log ERROR "Could not import/sign Chaotic-AUR's key (needs network access to keyserver.ubuntu.com)"; return 1
    fi

    log INFO "Installing chaotic-keyring + chaotic-mirrorlist..."
    if ! pacman -U --noconfirm \
        'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
        'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' 2>/dev/null; then
        FAILED_PACKAGES+=("chaotic-keyring"); ((TOTAL_FAILED++))
        log ERROR "chaotic-keyring/chaotic-mirrorlist install failed (needs network access to cdn-mirror.chaotic.cx)"; return 1
    fi

    if ! grep -Eq '^\[chaotic-aur\]' /etc/pacman.conf 2>/dev/null; then
        printf '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n' >> /etc/pacman.conf
    fi
    if grep -Eq '^\[blackarch\]' /etc/pacman.conf 2>/dev/null; then
        log INFO "Note: Chaotic-AUR's own docs recommend it come BEFORE other third-party repos in /etc/pacman.conf (it rebuilds most packages hourly) - [blackarch] is already present above it here; reorder the sections manually if you want Chaotic-AUR to win on any overlapping package names"
    fi

    if $IS_OMARCHY; then
        log INFO "Omarchy detected - not syncing here (see update_packages note); run 'omarchy update' once to pick up chaotic-aur, or 'sudo pacman -Sy' if you understand the partial-upgrade caveat."
    else
        pacman -Sy --noconfirm &>/dev/null
    fi

    if is_installed chaotic-keyring; then
        INSTALLED_PACKAGES+=("chaotic-keyring"); ((TOTAL_INSTALLED++))
        log SUCCESS "Chaotic-AUR repo enabled - safe_install will now prefer its prebuilt binaries over building from AUR source for anything it covers"
    else
        FAILED_PACKAGES+=("chaotic-keyring"); ((TOTAL_FAILED++))
        log WARNING "Chaotic-AUR repo setup may have failed - check /etc/pacman.conf and https://aur.chaotic.cx/ for current instructions"
    fi
}

# ========== PERIPHERALS (LOGITECH) ==========
install_peripheral_tools() {
    # solaar is confirmed in Arch's official [extra] repo. There's no
    # separate "solaar-udev" package on Arch - the udev rules ship bundled
    # inside the main solaar package itself.
    batch_install "Peripheral Management" solaar
    if is_installed solaar; then
        log INFO "Solaar installed - GUI: 'solaar', CLI: 'solaar config' for battery/DPI/gesture/scroll-feature control of Logitech HID++ mice and keyboards"
    fi
}

# Applies a specific fix confirmed on real hardware: an MX Anywhere 3S over
# Bluetooth with its "Scroll Wheel Resolution" HID++ feature disabled by
# default, producing genuinely slow-but-smooth scrolling that no OS-side
# setting can fix - only flipping this on-device flag does. Fully
# package-manager-agnostic (Solaar's CLI is identical regardless of distro).
fix_logitech_hires_scroll() {
    local device_name="MX Anywhere 3S" rc=0
    if ! command -v solaar &>/dev/null; then
        log INFO "Solaar not installed - installing it first..."
        install_peripheral_tools
    fi
    if ! command -v solaar &>/dev/null; then
        log ERROR "Solaar install failed - cannot apply the scroll fix"
        rc=1
    elif ! solaar show 2>/dev/null | grep -qi "$device_name"; then
        log WARNING "'$device_name' not seen by Solaar - pair/connect it first (Bluetooth Settings), then re-run this from the Peripherals menu"
        rc=1
    elif solaar config "$device_name" hires-smooth-resolution 1 2>/dev/null; then
        log SUCCESS "Enabled 'Scroll Wheel Resolution' on $device_name"
        log INFO "Stored on the mouse itself - no reboot needed, test scrolling now"
    else
        log WARNING "'solaar config \"$device_name\" hires-smooth-resolution 1' failed - run: solaar config \"$device_name\"  (no value) to list its actual setting names, the CLI name may differ on your Solaar version"
        rc=1
    fi
    # Every exit path above funnels through here (rc records the outcome)
    # so whichever message printed actually gets read before the main menu
    # loop clears the screen and redraws.
    read -p "$(printf "${DIM}${SUBTEXT}  Press [Enter] to continue…${NC}")" _
    return $rc
}

# ========== NVIDIA DRIVER ==========
install_nvidia_driver() {
    local msg="Install/configure the NVIDIA GPU driver? Only answer yes if this machine actually has an NVIDIA GPU."
    local do_it=false
    if command -v whiptail &>/dev/null; then
        whiptail --yesno "$msg" --yes-button "Install" --no-button "Skip" 12 72 && do_it=true
    else
        echo -e "$msg [y/N]:"; read -r REPLY
        { [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; } && do_it=true
    fi
    if ! $do_it; then
        log INFO "Skipped NVIDIA driver setup"
        return 0
    fi

    if $IS_OMARCHY; then
        # Omarchy already owns NVIDIA driver selection end-to-end: its own
        # install/hardware/nvidia.sh detects the GPU via sysfs (deliberately
        # not lspci, to avoid waking a runtime-suspended dGPU), picks
        # nvidia-open-dkms (GSP-capable: Turing/Ampere/Ada/Blackwell) or
        # nvidia-580xx-dkms (pre-GSP: Maxwell/Pascal), and writes the
        # modprobe.d + mkinitcpio early-KMS config to match. Re-deriving
        # that classification here would just be a worse, unmaintained copy
        # of logic Omarchy already keeps current - so prefer re-invoking
        # Omarchy's own flow (via omarchy-apply-hardware, the documented
        # idempotent "redo hardware detection" entry point) over duplicating it.
        if command -v omarchy-hw-nvidia-gsp &>/dev/null && command -v omarchy-hw-nvidia-without-gsp &>/dev/null; then
            if command -v omarchy-apply-hardware &>/dev/null; then
                local install_user="${SUDO_USER:-}"
                if [ -z "$install_user" ]; then
                    log WARNING "No SUDO_USER set - cannot pass --install-user to omarchy-apply-hardware"
                    log INFO "Run manually: sudo omarchy-apply-hardware --install-user <your-username>"
                    return 1
                fi
                log INFO "Re-running Omarchy's hardware-apply flow (nvidia.sh + friends) via omarchy-apply-hardware..."
                if omarchy-apply-hardware --install-user "$install_user"; then
                    INSTALLED_PACKAGES+=("NVIDIA driver (via omarchy-apply-hardware)"); ((TOTAL_INSTALLED++))
                    log SUCCESS "Omarchy hardware-apply finished - reboot to load the NVIDIA driver"
                    log INFO "Hybrid (laptop dGPU+iGPU) systems: see 'omarchy-toggle-hybrid-gpu' to switch modes"
                else
                    FAILED_PACKAGES+=("NVIDIA driver (omarchy-apply-hardware)"); ((TOTAL_FAILED++))
                    log ERROR "omarchy-apply-hardware failed - check /var/log/omarchy-install.log"
                    return 1
                fi
            else
                log WARNING "omarchy-hw-nvidia-* detectors exist but omarchy-apply-hardware was not found on this Omarchy build"
                log INFO "Run manually: omarchy-hw-nvidia-gsp && sudo pacman -S nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver"
                log INFO "             (or, if that check fails) omarchy-hw-nvidia-without-gsp && sudo pacman -S nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils"
            fi
            # Secure Boot: Omarchy's own docs require Secure Boot OFF in
            # firmware just to install/run Omarchy at all. If it's somehow
            # on, that's a preexisting unsupported state, not something this
            # NVIDIA path should try to remediate with MOK-enrollment guidance.
            return 0
        fi
        log WARNING "omarchy-hw-nvidia-* commands not found (older/different Omarchy build) - falling back to the manual NVIDIA path"
    fi

    # ---- Plain Arch (or Omarchy fallback above) manual path ----
    if ! lspci -nn 2>/dev/null | grep -qi 'nvidia'; then
        log INFO "No NVIDIA GPU detected via lspci - skipping NVIDIA driver install"
        return 0
    fi

    bootstrap_multilib   # needed for lib32-nvidia-utils

    # Arch's plain `nvidia` package is precompiled against the exact current
    # official `linux` kernel package and breaks on any other kernel
    # (linux-lts, linux-zen, a custom kernel, ...). The DKMS variant rebuilds
    # itself for whatever kernel is actually running instead - the safer
    # default for a general-purpose script that can't assume the kernel
    # package, matching the reasoning (not the package names) behind
    # Fedora's own akmod-nvidia-open choice. nvidia-open-dkms (open kernel
    # module) is current Arch Wiki/NVIDIA guidance for Turing-and-newer.
    local headers=() kpkg
    while IFS= read -r kpkg; do
        [ -n "$kpkg" ] && headers+=("${kpkg}-headers")
    done < <(pacman -Qqs '^linux(-zen|-lts|-hardened)?$' 2>/dev/null)

    batch_install "NVIDIA Driver" nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver "${headers[@]}"

    mkdir -p /etc/modprobe.d
    cat > /etc/modprobe.d/nvidia.conf <<'EOF'
options nvidia_drm modeset=1
EOF

    mkdir -p /etc/mkinitcpio.conf.d
    cat > /etc/mkinitcpio.conf.d/nvidia.conf <<'EOF'
MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
EOF
    mkinitcpio -P 2>/dev/null || log WARNING "mkinitcpio -P failed - regenerate the initramfs manually before rebooting"

    if $IS_OMARCHY; then
        log INFO "Secure Boot check skipped here: Omarchy requires Secure Boot OFF in firmware to run at all, so an enabled state is a preexisting unsupported condition, not something this NVIDIA path should fix."
    elif command -v mokutil &>/dev/null && mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
        log WARNING "Secure Boot is enabled - the DKMS-built NVIDIA kernel modules will not load until signed/enrolled."
        log INFO  "DKMS normally prompts to enroll a Machine Owner Key (MOK) automatically on the next module build."
        log INFO  "If it does not, run manually: sudo mokutil --import /var/lib/dkms/mok.pub"
        log INFO  "then reboot and, on the blue MOK Manager screen, choose Enroll MOK -> Continue -> enter the password you just set -> reboot to finish enrollment."
    fi

    log SUCCESS "NVIDIA driver installed - reboot to load it"
}

# DisplayLink (USB/dock-connected display adapters, DL-3xxx through DL-7xxx
# chipsets) has no official Arch package - the AUR's "displaylink" (which
# pulls in evdi-dkms as a dependency automatically via yay) is the community
# path, repackaging the same vendor installer Fedora's displaylink-rpm project
# builds from. Unlike that RPM's %post, Arch's own packaging conventions
# discourage a package auto-enabling services on install, so the
# systemctl enable --now step below is done explicitly here, same as
# docker/libvirtd elsewhere in this script.
install_displaylink_driver() {
    local msg="Install the DisplayLink driver (USB/dock display adapters)?\n\nBuilds the evdi DKMS kernel module + DisplayLinkManager from the AUR, for DL-3xxx through DL-7xxx chipset docking stations and USB monitors/adapters. Only useful if you actually have DisplayLink hardware."
    local do_it=false
    if command -v whiptail &>/dev/null; then
        whiptail --yesno "$msg" --yes-button "Install" --no-button "Skip" 14 76 && do_it=true
    else
        echo -e "$msg [y/N]:"; read -r REPLY
        { [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; } && do_it=true
    fi
    if ! $do_it; then
        log INFO "Skipped DisplayLink driver"
        return 0
    fi

    # evdi-dkms (the AUR dependency behind "displaylink") needs the matching
    # kernel headers to build against - same detection as install_nvidia_driver.
    local headers=() kpkg
    while IFS= read -r kpkg; do
        [ -n "$kpkg" ] && headers+=("${kpkg}-headers")
    done < <(pacman -Qqs '^linux(-zen|-lts|-hardened)?$' 2>/dev/null)

    batch_install "DisplayLink Driver" "${headers[@]}" displaylink

    if is_installed displaylink; then
        systemctl enable --now displaylink.service 2>/dev/null
        if command -v mokutil &>/dev/null && mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
            log WARNING "Secure Boot is enabled - the DKMS-built evdi kernel module will not load until signed/enrolled."
            log INFO  "DKMS normally prompts to enroll a Machine Owner Key (MOK) automatically on the next module build."
            log INFO  "If it does not, run manually: sudo mokutil --import /var/lib/dkms/mok.pub"
            log INFO  "then reboot and, on the blue MOK Manager screen, choose Enroll MOK -> Continue -> enter the password you just set -> reboot to finish enrollment."
        fi
        log SUCCESS "DisplayLink driver installed"
    fi
}

# ========== SNAPSHOTS & BACKUP ==========
detect_root_fstype() {
    findmnt -no FSTYPE / 2>/dev/null
}

install_snapshots_full() {
    log INFO "Configuring System Snapshots..."
    local fstype
    fstype=$(detect_root_fstype)
    log INFO "Detected root filesystem: ${fstype:-unknown}"
    if [ "$fstype" = "btrfs" ]; then
        install_snapshots_btrfs
    else
        install_snapshots_timeshift
    fi
}

install_snapshots_btrfs() {
    if $IS_OMARCHY; then
        # Omarchy already runs Btrfs + Snapper + Limine + limine-snapper-sync
        # out of the box: every `omarchy update` takes a pre-transaction
        # snapshot automatically, plus a manual `omarchy-snapshot` wrapper.
        # Omarchy also deliberately disables Snapper's periodic timeline
        # timer in favor of update-triggered + manual snapshots only.
        # Detect that existing setup and defer to it - do NOT re-run
        # `snapper -c root create-config /` (conflicts with the existing
        # config) or re-enable snapper-timeline.timer (fights a deliberate
        # Omarchy choice).
        if command -v snapper &>/dev/null && snapper -c root list &>/dev/null; then
            log INFO "Omarchy's Snapper 'root' config already exists - leaving its snapshot/timer setup as-is"
            SKIPPED_PACKAGES+=("Snapper root config (already managed by Omarchy)"); ((TOTAL_SKIPPED++))
            # btrfs-assistant is still a useful standalone GUI complement to
            # Omarchy's own omarchy-snapshot/limine-snapper-restore tools -
            # it only touches Snapper/Btrfs, not Omarchy's shell or configs.
            batch_install "Btrfs snapshot GUI" btrfs-assistant
            return 0
        fi
        log WARNING "Omarchy's usual Snapper 'root' config was not found - falling back to the plain-Arch manual Snapper setup"
    fi

    # Plain Arch: no existing snapshot setup to detect/defer to - build it.
    batch_install "Btrfs Snapshot Tools" snapper grub-btrfs btrfs-assistant

    if ! snapper -c root list &>/dev/null; then
        if snapper -c root create-config / 2>/dev/null; then
            log SUCCESS "Created Snapper 'root' config for /"
        else
            log WARNING "snapper -c root create-config / failed"
        fi
    else
        log INFO "Snapper 'root' config already exists"
    fi

    systemctl enable --now snapper-timeline.timer snapper-cleanup.timer 2>/dev/null \
        && log SUCCESS "Enabled Snapper timeline + cleanup timers" \
        || log WARNING "Could not enable snapper timers"

    # grub-btrfs boots into old snapshots from the GRUB menu - it's
    # GRUB-specific and does nothing useful under Limine (Omarchy's
    # bootloader) or systemd-boot, so only wire it in when GRUB is actually
    # the bootloader in use on this machine.
    if [ -d /boot/grub ] && command -v grub-mkconfig &>/dev/null; then
        systemctl enable --now grub-btrfsd.service 2>/dev/null \
            && log SUCCESS "Enabled grub-btrfsd (Btrfs snapshots in the GRUB boot menu)" \
            || log WARNING "Could not enable grub-btrfsd.service"
    else
        log INFO "GRUB not detected as the bootloader - skipping grub-btrfs boot-menu integration (package still installed)"
    fi

    log SUCCESS "Btrfs snapshot support configured (Snapper + btrfs-assistant)"
}

install_snapshots_timeshift() {
    log WARNING "Root filesystem is not Btrfs - using Timeshift (rsync mode) instead of Snapper"
    batch_install "Timeshift" timeshift
    log INFO "Timeshift installed. Run 'sudo timeshift-gtk' (GUI) or 'sudo timeshift --create' (CLI) to take your first snapshot and configure a schedule."
}

snapshot_create_now() {
    if $IS_OMARCHY && command -v omarchy-snapshot &>/dev/null; then
        log INFO "Creating snapshot via omarchy-snapshot (wraps Snapper across every configured Snapper config, then cleans up by count)..."
        omarchy-snapshot create
        return $?
    fi
    local fstype; fstype=$(detect_root_fstype)
    if [ "$fstype" = "btrfs" ] && command -v snapper &>/dev/null && snapper -c root list &>/dev/null; then
        log INFO "Creating Snapper snapshot..."
        snapper -c root create -c number -d "manual snapshot $(date '+%Y-%m-%d %H:%M:%S')"
    elif command -v timeshift &>/dev/null; then
        log INFO "Creating Timeshift snapshot..."
        timeshift --create --comments "manual snapshot $(date '+%Y-%m-%d %H:%M:%S')" --scripted
    else
        log ERROR "No snapshot tool available (Snapper/omarchy-snapshot/Timeshift) - run install_snapshots_full first"
        return 1
    fi
    read -p "$(printf "${DIM}${SUBTEXT}  Press [Enter] to continue…${NC}")" _
}

snapshot_list() {
    # omarchy-snapshot has no listing subcommand of its own (only
    # create/restore), so listing always goes straight to the underlying
    # tool, Omarchy or not.
    local fstype; fstype=$(detect_root_fstype)
    if [ "$fstype" = "btrfs" ] && command -v snapper &>/dev/null && snapper -c root list &>/dev/null; then
        snapper -c root list
    elif command -v timeshift &>/dev/null; then
        timeshift --list
    else
        log WARNING "No snapshot tool available (Snapper/Timeshift) - nothing to list"
        return 1
    fi
    read -p "$(printf "${DIM}${SUBTEXT}  Press [Enter] to continue…${NC}")" _
}

snapshot_open_gui() {
    local user uid
    if command -v btrfs-assistant &>/dev/null; then
        if read -r user uid < <(resolve_desktop_session); then
            log INFO "Launching btrfs-assistant..."
            su - "$user" -c btrfs-assistant
            return $?
        fi
        log WARNING "btrfs-assistant is installed but no active desktop session was found to launch it in"
        return 1
    fi
    if $IS_OMARCHY && command -v omarchy-snapshot &>/dev/null; then
        log INFO "Omarchy has no dedicated snapshot GUI - 'omarchy-snapshot restore' drives an interactive limine-snapper-restore instead."
        local msg="Run the interactive Snapper/Limine restore tool now?"
        local do_it=false
        if command -v whiptail &>/dev/null; then
            whiptail --yesno "$msg" --yes-button "Restore" --no-button "Cancel" 10 72 && do_it=true
        else
            echo -e "$msg [y/N]:"; read -r REPLY
            { [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; } && do_it=true
        fi
        $do_it && omarchy-snapshot restore
        return 0
    fi
    if command -v timeshift-gtk &>/dev/null && read -r user uid < <(resolve_desktop_session); then
        log INFO "Launching Timeshift GUI..."
        su - "$user" -c timeshift-gtk
        return $?
    fi
    log WARNING "No snapshot GUI available (btrfs-assistant/omarchy-snapshot/timeshift-gtk not found)"
    return 1
}

# ========== GUI TWEAKS / THEMING ==========
install_gui_tweaks() {
    log INFO "Installing GUI Tweaks..."
    install_icon_sets
    install_themes
    install_cursor_themes
    install_nerd_fonts
    if ! $IS_OMARCHY; then configure_terminal_font; fi
    install_chris_titus_mybash
    if ! $IS_OMARCHY; then install_gui_tools; install_gnome_extensions; fi
    configure_logiops
}

install_icon_sets() {
    # numix-icon-theme itself isn't packaged (official or AUR) under that
    # exact name any more - only the community -git rebuild is.
    batch_install "Icon Sets" papirus-icon-theme numix-icon-theme-git breeze-icons adwaita-icon-theme
    install_qogir_icons; install_whitesur_icons; install_vimix_icons; install_newaita_icons
}

install_vinceliuice_repo() {
    local label="$1" repo="$2" slug="$3" kind="$4"; shift 4
    local extra_args=("$@")
    local marker="/var/lib/arch-postinstall-themes/${slug}.done"
    if [ -f "$marker" ]; then
        SKIPPED_PACKAGES+=("$label $kind"); ((TOTAL_SKIPPED++)); log INFO "Already installed: $label $kind"; return 0
    fi
    # gtk-update-icon-cache is its own small split package off gtk4 on Arch
    # (not bundled with the much larger gtk3 package).
    command -v gtk-update-icon-cache &>/dev/null || safe_install gtk-update-icon-cache
    local t; t=$(mktemp -d)
    if ! git clone --depth 1 "$repo" "$t/src" 2>/dev/null; then
        rm -rf "$t"; FAILED_PACKAGES+=("$label $kind"); ((TOTAL_FAILED++))
        log WARNING "$label $kind clone failed (needs network access to github.com)"; return 1
    fi
    log INFO "Installing $label $kind..."
    if bash "$t/src/install.sh" "${extra_args[@]}" 2>/dev/null; then
        mkdir -p "$(dirname "$marker")" && touch "$marker"
        INSTALLED_PACKAGES+=("$label $kind"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: $label $kind"
    else
        FAILED_PACKAGES+=("$label $kind"); ((TOTAL_FAILED++)); log WARNING "$label $kind install failed"
    fi
    rm -rf "$t"
}
install_qogir_icons()    { install_vinceliuice_repo "Qogir"    "https://github.com/vinceliuice/Qogir-icon-theme.git"    "qogir-icons"    "icons"; }
install_whitesur_icons() { install_vinceliuice_repo "WhiteSur" "https://github.com/vinceliuice/WhiteSur-icon-theme.git" "whitesur-icons" "icons"; }
install_vimix_icons()    { install_vinceliuice_repo "Vimix"    "https://github.com/vinceliuice/Vimix-icon-theme.git"    "vimix-icons"    "icons"; }
install_colloid_theme()  { install_vinceliuice_repo "Colloid"  "https://github.com/vinceliuice/Colloid-gtk-theme.git"  "colloid-gtk-theme" "theme"; }
install_newaita_icons() {
    if [ -d /usr/share/icons/Newaita ]; then
        SKIPPED_PACKAGES+=("Newaita icons"); ((TOTAL_SKIPPED++)); log INFO "Already installed: Newaita icons"; return 0
    fi
    local t; t=$(mktemp -d)
    if ! git clone --depth 1 https://github.com/cbrnix/Newaita.git "$t/src" 2>/dev/null; then
        rm -rf "$t"; FAILED_PACKAGES+=("Newaita icons"); ((TOTAL_FAILED++))
        log WARNING "Newaita icons clone failed"; return 1
    fi
    if cp -r "$t/src/Newaita" "$t/src/Newaita-dark" /usr/share/icons/ 2>/dev/null; then
        INSTALLED_PACKAGES+=("Newaita icons"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: Newaita icons"
    else
        FAILED_PACKAGES+=("Newaita icons"); ((TOTAL_FAILED++)); log WARNING "Newaita icons install failed"
    fi
    rm -rf "$t"
}

install_nordic_theme() {
    local user uid
    if ! read -r user uid < <(resolve_desktop_session); then
        log INFO "No active desktop session - skipping Nordic theme"
        SKIPPED_PACKAGES+=("Nordic theme"); ((TOTAL_SKIPPED++)); return 0
    fi
    local uh; uh=$(getent passwd "$user" | cut -d: -f6)
    if [ -d "$uh/.themes/Nordic" ]; then
        SKIPPED_PACKAGES+=("Nordic theme"); ((TOTAL_SKIPPED++)); log INFO "Already installed: Nordic theme"; return 0
    fi
    local t; t=$(mktemp -d); chmod 755 "$t"; chown "$user" "$t" 2>/dev/null
    if ! su - "$user" -c "git clone --depth 1 https://github.com/EliverLara/Nordic.git '$t/src'" 2>/dev/null; then
        rm -rf "$t"; FAILED_PACKAGES+=("Nordic theme"); ((TOTAL_FAILED++))
        log WARNING "Nordic theme clone failed"; return 1
    fi
    if su - "$user" -c "mkdir -p '$uh/.themes' && cp -r '$t/src/Nordic' '$uh/.themes/Nordic'" 2>/dev/null && [ -d "$uh/.themes/Nordic" ]; then
        INSTALLED_PACKAGES+=("Nordic theme"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: Nordic theme"
    else
        FAILED_PACKAGES+=("Nordic theme"); ((TOTAL_FAILED++)); log WARNING "Nordic theme install failed"
    fi
    rm -rf "$t"
}
# Icon themes, GTK themes, cursor themes, and Nerd Fonts remain meaningfully
# useful even under Omarchy: some GTK apps still read gsettings/dconf for
# icon/cursor theme without GNOME Shell running, and users may want font
# families beyond Omarchy's bundled default - kept unconditionally.
install_material_gnome_theme() {
    local user uid
    if ! read -r user uid < <(resolve_desktop_session); then
        log INFO "No active desktop session - skipping Material GNOME theme"
        SKIPPED_PACKAGES+=("Material GNOME theme"); ((TOTAL_SKIPPED++)); return 0
    fi
    local uh; uh=$(getent passwd "$user" | cut -d: -f6)
    if [ -d "$uh/.themes/Material-Gnome" ]; then
        SKIPPED_PACKAGES+=("Material GNOME theme"); ((TOTAL_SKIPPED++)); log INFO "Already installed: Material GNOME theme"; return 0
    fi
    local t; t=$(mktemp -d); chmod 755 "$t"; chown "$user" "$t" 2>/dev/null
    if ! su - "$user" -c "git clone --depth 1 https://github.com/SakibShahariar/material-gnome-theme.git '$t/src'" 2>/dev/null; then
        rm -rf "$t"; FAILED_PACKAGES+=("Material GNOME theme"); ((TOTAL_FAILED++))
        log WARNING "Material GNOME theme clone failed"; return 1
    fi
    # Repo root IS the theme tree (no install.sh) - drop it straight into
    # ~/.themes/Material-Gnome, then symlink the GTK4/libadwaita stylesheets
    # into ~/.config/gtk-4.0 since those apps ignore ~/.themes entirely.
    if su - "$user" -c "rm -rf '$t/src/.git' && mkdir -p '$uh/.themes/Material-Gnome' && cp -r '$t/src/.' '$uh/.themes/Material-Gnome' && mkdir -p '$uh/.config/gtk-4.0' && ln -sf '$uh/.themes/Material-Gnome/gtk-4.0/gtk.css' '$uh/.config/gtk-4.0/gtk.css' && ln -sf '$uh/.themes/Material-Gnome/gtk-4.0/gtk-dark.css' '$uh/.config/gtk-4.0/gtk-dark.css'" 2>/dev/null && [ -d "$uh/.themes/Material-Gnome" ]; then
        INSTALLED_PACKAGES+=("Material GNOME theme"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: Material GNOME theme"
    else
        FAILED_PACKAGES+=("Material GNOME theme"); ((TOTAL_FAILED++)); log WARNING "Material GNOME theme install failed"
    fi
    rm -rf "$t"
}
install_lycia_theme() {
    local user uid
    if ! read -r user uid < <(resolve_desktop_session); then
        log INFO "No active desktop session - skipping Lycia theme"
        SKIPPED_PACKAGES+=("Lycia theme"); ((TOTAL_SKIPPED++)); return 0
    fi
    local uh; uh=$(getent passwd "$user" | cut -d: -f6)
    if [ -d "$uh/.themes/Lycia" ]; then
        SKIPPED_PACKAGES+=("Lycia theme"); ((TOTAL_SKIPPED++)); log INFO "Already installed: Lycia theme"; return 0
    fi
    # GTK3 murrine engine + gnome-themes-extra assets are runtime deps the
    # theme itself needs to render - not something its installer pulls in.
    batch_install "Lycia Theme Dependencies" gtk-engine-murrine sassc gnome-themes-extra
    local t; t=$(mktemp -d); chmod 755 "$t"; chown "$user" "$t" 2>/dev/null
    if ! su - "$user" -c "git clone --depth 1 https://github.com/Aevstiel/Lycia-Theme.git '$t/src'" 2>/dev/null; then
        rm -rf "$t"; FAILED_PACKAGES+=("Lycia theme"); ((TOTAL_FAILED++))
        log WARNING "Lycia theme clone failed"; return 1
    fi
    # install.sh interactively asks two questions: install the GTK4/Libadwaita
    # files (yes) and install the GDM login-screen theme (no - that overwrites
    # a system gnome-shell resource file, too invasive for an unattended run).
    if printf 'Y\nN\n' | su - "$user" -c "bash '$t/src/install.sh'" 2>/dev/null && [ -d "$uh/.themes/Lycia" ]; then
        INSTALLED_PACKAGES+=("Lycia theme"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: Lycia theme"
    else
        FAILED_PACKAGES+=("Lycia theme"); ((TOTAL_FAILED++)); log WARNING "Lycia theme install failed"
    fi
    rm -rf "$t"
}
install_themes() { install_nordic_theme; install_colloid_theme; install_material_gnome_theme; install_lycia_theme; }

install_cursor_themes() {
    # breeze-icons is icons only - it ships no XCursor files. The actual
    # cursor packages are capitaine-cursors (official) and the community
    # xcursor-breeze5 rebuild (AUR); Adwaita's own cursor theme already
    # comes bundled with adwaita-icon-theme from install_icon_sets.
    batch_install "Cursor Themes" capitaine-cursors xcursor-breeze5
}

install_nerd_fonts() {
    log INFO "Installing Nerd Fonts..."
    # Arch now ships most popular families as official ttf-*-nerd packages -
    # prefer those (proper pacman-managed, no GitHub-release flakiness) and
    # only fall back to fetching upstream release tarballs for whatever
    # isn't covered that way.
    local pacman_fonts=(ttf-firacode-nerd ttf-jetbrains-mono-nerd ttf-hack-nerd ttf-sourcecodepro-nerd ttf-cascadia-code-nerd ttf-ubuntu-mono-nerd ttf-dejavu-nerd)
    batch_install "Nerd Fonts (pacman)" "${pacman_fonts[@]}"

    mkdir -p /usr/share/fonts/truetype/nerd-fonts
    local fonts=(FiraCode JetBrainsMono Hack SourceCodePro CascadiaCode UbuntuMono DejaVuSansMono)
    local pkg_for_font=(ttf-firacode-nerd ttf-jetbrains-mono-nerd ttf-hack-nerd ttf-sourcecodepro-nerd ttf-cascadia-code-nerd ttf-ubuntu-mono-nerd ttf-dejavu-nerd)
    local t=$(mktemp -d) c=0 f=0 i
    for i in "${!fonts[@]}"; do
        local font="${fonts[$i]}" pkg="${pkg_for_font[$i]}"
        is_installed "$pkg" && continue   # already covered by the pacman batch above
        local af="$t/${font}.tar.xz" ed="$t/${font}"
        mkdir -p "$ed"
        curl -L -f --retry 3 -o "$af" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font}.tar.xz" 2>/dev/null || { log WARNING "Failed: $font"; ((f++)); continue; }
        tar -xf "$af" -C "$ed" 2>/dev/null || { log WARNING "Extract failed: $font"; ((f++)); continue; }
        local cp=0
        while IFS= read -r -d '' ff; do cp "$ff" /usr/share/fonts/truetype/nerd-fonts/ 2>/dev/null; ((cp++)); done < <(find "$ed" -type f \( -iname "*.ttf" -o -iname "*.otf" \) -print0 2>/dev/null)
        [ $cp -gt 0 ] && { ((c++)); log INFO "Installed: $font"; } || { log WARNING "No files: $font"; ((f++)); }
        rm -rf "$af" "$ed"
    done
    fc-cache -f /usr/share/fonts/truetype/nerd-fonts/ 2>/dev/null
    rm -rf "$t"
    if [ $c -gt 0 ] || [ $f -eq 0 ]; then
        log SUCCESS "Nerd Fonts installed ($c downloaded manually, rest via pacman, $f failed)"
    else
        log ERROR "No fonts installed"; return 1
    fi
}

configure_terminal_font() {
    if $IS_OMARCHY; then
        log INFO "Omarchy uses its own Quickshell-based terminal theming, not GNOME Terminal/gsettings - skipping terminal font configuration"
        return 0
    fi
    local user uid
    if ! read -r user uid < <(resolve_desktop_session); then
        log INFO "No active desktop session - skipping terminal font configuration"
        return 0
    fi
    set_terminal_font "$user" "$uid" "JetBrainsMono Nerd Font 11"
}

set_terminal_font() {
    local user="$1" uid="$2" font="$3"
    local profile
    profile=$(gsettings_as_user "$user" "$uid" get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'")
    if [ -z "$profile" ]; then
        log INFO "No GNOME Terminal default profile found - skipping font configuration"
        return 0
    fi
    local schema_path="/org/gnome/terminal/legacy/profiles:/:$profile/"
    gsettings_as_user "$user" "$uid" set "org.gnome.Terminal.Legacy.Profile:$schema_path" use-system-font false 2>/dev/null
    if gsettings_as_user "$user" "$uid" set "org.gnome.Terminal.Legacy.Profile:$schema_path" font "$font" 2>/dev/null; then
        log SUCCESS "Set GNOME Terminal font to: $font"
    else
        log WARNING "Failed to set GNOME Terminal font"
    fi
}

install_chris_titus_mybash() {
    local UH=$(eval echo ~$SUDO_USER 2>/dev/null || echo "/home/$(logname)")
    local MD="${UH}/mybash" BR="${UH}/.bashrc"
    if [ -d "$MD" ]; then log INFO "mybash already installed"; return 0; fi
    log INFO "Installing Chris Titus mybash..."
    if ! git clone --depth 1 https://github.com/christitustech/mybash "$MD"; then
        log ERROR "Clone failed"; return 1
    fi
    # setup.sh detects the package manager itself (a pacman branch already
    # exists upstream) - run as root same as the Fedora/Ubuntu versions, for
    # the same "nested sudo needs a real terminal" reason.
    if HOME="$UH" USER="$SUDO_USER" LOGNAME="$SUDO_USER" bash "$MD/setup.sh"; then
        chown -R "$SUDO_USER:$SUDO_USER" "$MD" "$UH/.local" "$UH/.config" "$BR" 2>/dev/null || true
        log SUCCESS "mybash installed. User: source ~/.bashrc"
        return 0
    fi
    log WARNING "setup.sh failed, falling back to a plain .bashrc copy..."
    [ -f "$MD/.bashrc" ] && cp "$MD/.bashrc" "$BR" 2>/dev/null
    [ -f "$MD/starship.toml" ] && { mkdir -p "$UH/.config"; cp "$MD/starship.toml" "$UH/.config/starship.toml" 2>/dev/null; }
    [ -f "$MD/config.jsonc" ] && { mkdir -p "$UH/.config/fastfetch"; cp "$MD/config.jsonc" "$UH/.config/fastfetch/config.jsonc" 2>/dev/null; }
    chown -R "$SUDO_USER:$SUDO_USER" "$MD" "$UH/.local" "$UH/.config" "$BR" 2>/dev/null || true
    [ -f "$BR" ] && { log SUCCESS "mybash .bashrc installed via fallback copy"; return 0; } || { log ERROR "mybash fallback copy also failed"; return 1; }
}

install_gui_tools() {
    # eog (Eye of GNOME) is being phased out upstream in favor of Loupe.
    # Arch still ships eog today, but fall forward automatically once it's
    # gone rather than hard-failing on a renamed package.
    local image_viewer="eog"
    package_exists eog || image_viewer="loupe"
    batch_install "GUI Tools" gnome-tweaks nautilus "$image_viewer" file-roller simple-scan gnome-screenshot gnome-system-monitor dconf-editor
}

install_gnome_extensions() {
    if $IS_OMARCHY; then
        log INFO "Omarchy replaces GNOME Shell (bar/launcher/notifications/etc) with its own Quickshell-based desktop - skipping GNOME Shell extensions"
        return 0
    fi
    local user uid
    if ! read -r user uid < <(resolve_desktop_session); then
        log INFO "No active desktop session - skipping GNOME extensions"; return 0
    fi
    command -v pipx &>/dev/null || safe_install python-pipx
    su - "$user" -c 'command -v gext >/dev/null 2>&1 || pipx install gnome-extensions-cli --system-site-packages' 2>/dev/null
    if ! su - "$user" -c 'PATH="$HOME/.local/bin:$PATH" command -v gext' &>/dev/null; then
        log WARNING "gext install failed - skipping all GNOME extensions"
        FAILED_PACKAGES+=("GNOME extensions (gext setup failed)"); ((TOTAL_FAILED++)); return 1
    fi
    local exts=(gsconnect@andyholmes.github.io window-state-manager@kishorv06.github.io Bluetooth-Battery-Meter@maniacx.github.com auto-move-windows@gnome-shell-extensions.gcampax.github.com user-theme@gnome-shell-extensions.gcampax.github.com clipboard-history@alexsaveau.dev dash-to-dock@micxgx.gmail.com compact-quick-settings@gnome-shell-extensions.mariospr.org)
    local e ok=0
    for e in "${exts[@]}"; do
        if su - "$user" -c "XDG_RUNTIME_DIR='/run/user/$uid' DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/$uid/bus' PATH=\"\$HOME/.local/bin:\$PATH\" gext install '$e'" 2>/dev/null; then
            log INFO "Installed extension: $e"; ((ok++)); INSTALLED_PACKAGES+=("$e (extension)"); ((TOTAL_INSTALLED++))
        else
            log WARNING "Failed extension (skipped): $e"; FAILED_PACKAGES+=("$e (extension)"); ((TOTAL_FAILED++))
        fi
    done
    log INFO "GNOME extensions: $ok/${#exts[@]} installed"
}

configure_logiops() {
    local msg="Build and install Logiops (Logitech HID++ driver) from source?"
    local do_it=false
    if command -v whiptail &>/dev/null; then
        whiptail --yesno "$msg" --yes-button "Build" --no-button "Skip" 12 72 && do_it=true
    else
        echo -e "$msg [y/N]:"; read -r REPLY
        { [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; } && do_it=true
    fi
    if $do_it; then install_logiops; else log INFO "Skipped Logiops"; fi
}
install_logiops() {
    log INFO "Installing Logiops build dependencies..."
    batch_install "Logiops build deps" cmake pkgconf systemd-libs libevdev libconfig glib2 gcc
    local t; t=$(mktemp -d)
    if ! git clone --depth 1 https://github.com/PixlOne/logiops "$t/logiops" 2>/dev/null; then
        rm -rf "$t"; log WARNING "Logiops clone failed"; return 1
    fi
    ( cd "$t/logiops" && mkdir -p build && cd build && cmake .. 2>/dev/null && make -j"$(nproc)" 2>/dev/null && make install 2>/dev/null )
    if command -v logid &>/dev/null; then
        write_logid_config
        systemctl enable --now logid 2>/dev/null
        log SUCCESS "Logiops installed and logid service started"
    else
        log WARNING "Logiops build/install failed"
    fi
    rm -rf "$t"
}
write_logid_config() {
    [ -f /etc/logid.cfg ] && return 0
    cat > /etc/logid.cfg <<'EOF'
devices: (
  {
    name: "Default";
    smartshift: { on: true; threshold: 30; };
    hiresscroll: { hires: true; invert: false; target: false; };
  }
);
EOF
}

# Omarchy theme picker (Omarchy only - not reachable/used on plain Arch).
omarchy_theme_picker() {
    if ! $IS_OMARCHY; then
        log WARNING "omarchy_theme_picker only applies to Omarchy - skipping"
        return 1
    fi
    if [ -z "$SUDO_USER" ]; then
        log WARNING "No desktop user (SUDO_USER unset) - cannot launch the Omarchy theme picker"
        return 1
    fi
    if command -v omarchy-theme-switcher &>/dev/null; then
        log INFO "Launching the Omarchy theme switcher..."
        su - "$SUDO_USER" -c omarchy-theme-switcher
    else
        log WARNING "omarchy-theme-switcher not found - listing available themes instead"
        if command -v omarchy-theme-list &>/dev/null; then
            su - "$SUDO_USER" -c omarchy-theme-list
        fi
        log INFO 'Run as your normal user: omarchy-theme-set "<theme name>"   (e.g. omarchy-theme-set "Tokyo Night")'
    fi
}

# ========== MENU SYSTEM ==========
reset_tracking() {
    INSTALLED_PACKAGES=()
    FAILED_PACKAGES=()
    SKIPPED_PACKAGES=()
    TOTAL_INSTALLED=0
    TOTAL_FAILED=0
    TOTAL_SKIPPED=0
}

prompt_menu_category() {
    local name="$1"
    local icon="$2"
    local comment="$3"
    shift 3
    local apps=("$@")

    if $IS_OMARCHY; then
        log INFO "Omarchy's app launcher (Super+Space) already fuzzy-searches every installed app - no GNOME-style menu folder needed."
        # On non-Omarchy this function always pauses naturally (it asks a
        # y/N question about creating a GNOME app-folder below), which gives
        # you time to read display_summary's output before the main menu
        # redraws and clears the screen. Omarchy skips that question
        # entirely, so without an explicit pause here the summary would
        # flash by and vanish the instant this function returns - add the
        # same "press Enter" pause used elsewhere (e.g. the Summary menu
        # option) so a single-category run is actually readable here too.
        read -p "$(printf "${DIM}${SUBTEXT}  Press [Enter] to continue…${NC}")" _
        return 0
    fi

    if command -v whiptail &>/dev/null; then
        if whiptail --yesno "Create menu group for $name with ${#apps[@]} applications?" --yes-button "Yes" --no-button "No" 10 60; then
            if create_menu_category "$name" "$icon" "$comment" "${apps[@]}"; then
                echo "✓ Created menu group: $name"
            else
                echo "⚠ Menu group NOT created: $name (see warnings above)"
            fi
        else
            echo "  Skipped menu group: $name"
        fi
    else
        echo "Create menu group for '$name' with ${#apps[@]} applications? [y/N]:"
        read -r REPLY
        if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
            if create_menu_category "$name" "$icon" "$comment" "${apps[@]}"; then
                echo "✓ Created menu group: $name"
            else
                echo "⚠ Menu group NOT created: $name (see warnings above)"
            fi
        else
            echo "  Skipped menu group: $name"
        fi
    fi
}

auto_category() {
    local name="$1" fn="$2"
    reset_tracking
    "$fn"
    display_summary
    create_menu_category "$name" "applications-other" "$name" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}"
}

show_main_menu() {
    clear
    local subtitle="pacman · AUR (yay) · GNOME app folders (if present)"
    $IS_OMARCHY && subtitle="pacman · AUR (yay) · Omarchy ${OMARCHY_VERSION:-}"
    ui_header "ARCH LINUX  ·  POST-INSTALL" "$subtitle"
    echo
    ui_section "Creative & Drivers"
    ui_cell  1 "Creative Suite";     ui_cell 28 "Drivers & Extra Repos"; echo
    ui_cell 14 "Gaming";             ui_cell 25 "Desktop Apps";          echo
    # Snapshots & Backup is hidden on Omarchy: it already ships Btrfs +
    # Snapper + Limine snapshots built in and wired to `omarchy update`
    # (see the header note / install_snapshots_btrfs) - offering a menu
    # item that mostly exists to re-explain "this is already set up" is
    # more clutter than it's worth. Option 29 still works if typed
    # directly (see the case handler below), it's just not listed here.
    if $IS_OMARCHY; then
        ui_cell "" "";                ui_cell 30 "Peripherals (Logitech)"; echo
    else
        ui_cell 29 "Snapshots & Backup"; ui_cell 30 "Peripherals (Logitech)"; echo
    fi
    echo
    ui_section "Development"
    ui_cell  2 "Code Editors";       ui_cell  3 "Python";                echo
    ui_cell  4 "Web Development";    ui_cell  5 "Java";                  echo
    ui_cell  6 "C/C++";              ui_cell  7 "Go";                    echo
    ui_cell  8 "Rust";               ui_cell  9 "Node.js";               echo
    ui_cell 10 "PHP";                ui_cell 11 "Ruby";                  echo
    ui_cell 23 ".NET";               ui_cell 24 "DevOps & Cloud";        echo
    ui_cell 17 "General Dev Tools";  ui_cell 18 "AI Tools";              echo
    echo
    ui_section "Data, System & Desktop"
    ui_cell 12 "Databases";          ui_cell 13 "Containers & VMs";      echo
    ui_cell 16 "System Utilities";   ui_cell 19 "GUI Tweaks / Theming";  echo
    ui_cell 15 "Office & Docs";      ui_cell 22 "Security Tools";        echo
    echo
    ui_section "Compatibility & Devices"
    ui_cell 20 "Windows (Wine)";     ui_cell 21 "Android Tools";         echo
    echo
    ui_section "Internet & Communication"
    ui_cell 26 "Browsers";           ui_cell 27 "Communication";         echo
    echo
    ui_section "Bulk"
    ui_cell_alt A "All Dev Tools";   ui_cell_alt B "All Creative";       echo
    ui_cell_alt C "EVERYTHING";                                          echo
    echo
    ui_rule
    ui_cell  S "Summary";            ui_cell  0 "Exit";                  echo
    printf "  ${MAUVE}${BOLD}❯${NC} ${LAVENDER}Choose ${DIM}[0-30 · A-C · S]${NC}${LAVENDER}: ${NC}"
}

show_creative_menu() {
    clear
    ui_header "CREATIVE SUITE"
    echo
    ui_item 1 "Full (Graphics + Video + Audio + Photography + Publishing)"
    ui_item 2 "Graphics & Design"
    ui_item 3 "Video Editing"
    ui_item 4 "Audio Production"
    ui_item 5 "Photography"
    ui_item 6 "Publishing"
    echo
    ui_item 0 "Back to Main Menu"
    echo
    ui_rule
    printf "  ${MAUVE}${BOLD}❯${NC} ${LAVENDER}Choose ${DIM}[0-6]${NC}${LAVENDER}: ${NC}"
}

show_security_menu() {
    clear
    ui_header "SECURITY TOOLS"
    echo
    ui_item 1 "Full (pentest + defensive)"
    ui_item 2 "Defensive only (hardening, AV, IDS, firewall)"
    echo
    ui_item 0 "Back to Main Menu"
    echo
    ui_rule
    printf "  ${MAUVE}${BOLD}❯${NC} ${LAVENDER}Choose ${DIM}[0-2]${NC}${LAVENDER}: ${NC}"
}

show_browsers_menu() {
    clear
    ui_header "WEB BROWSERS"
    echo
    ui_item 1 "All Browsers"
    ui_item 2 "Brave"
    ui_item 3 "Vivaldi"
    ui_item 4 "Edge"
    ui_item 5 "Chrome"
    ui_item 6 "LibreWolf"
    ui_item 7 "Zen"
    ui_item 8 "Floorp"
    echo
    ui_item 0 "Back to Main Menu"
    echo
    ui_rule
    printf "  ${MAUVE}${BOLD}❯${NC} ${LAVENDER}Choose ${DIM}[0-8]${NC}${LAVENDER}: ${NC}"
}

show_communication_menu() {
    clear
    ui_header "COMMUNICATION"
    echo
    ui_item 1 "All Communication Apps"
    ui_item 2 "Signal"
    ui_item 3 "Discord"
    ui_item 4 "Telegram"
    ui_item 5 "Teams"
    echo
    ui_item 0 "Back to Main Menu"
    echo
    ui_rule
    printf "  ${MAUVE}${BOLD}❯${NC} ${LAVENDER}Choose ${DIM}[0-5]${NC}${LAVENDER}: ${NC}"
}

show_gui_tweaks_menu() {
    clear
    ui_header "GUI TWEAKS / THEMING" "$($IS_OMARCHY && echo "Omarchy owns the shell/theme - see options below" || echo "GTK/icon themes, fonts, GNOME extensions")"
    echo
    if $IS_OMARCHY; then
        ui_item 1 "All (Nerd Fonts + mybash + Omarchy theme picker)"
        ui_item 2 "Nerd Fonts (extra families beyond Omarchy's default)"
        ui_item 3 "Chris Titus mybash"
        ui_item 4 "Omarchy theme picker (omarchy-theme-switcher / omarchy-theme-set)"
    else
        ui_item 1 "All GUI Tweaks (everything below)"
        ui_item 2 "Icon Sets"
        ui_item 3 "GTK Themes (choose: Nordic / Colloid / Material GNOME / Lycia)"
        ui_item 4 "Cursor Themes"
        ui_item 5 "Nerd Fonts"
        ui_item 6 "Chris Titus mybash"
        ui_item 7 "GUI Tools"
        ui_item 8 "GNOME Shell Extensions (if GNOME is installed)"
    fi
    echo
    ui_item 0 "Back to Main Menu"
    echo
    ui_rule
    printf "  ${MAUVE}${BOLD}❯${NC} ${LAVENDER}Choose: ${NC}"
}

show_gtk_theme_menu() {
    clear
    ui_header "GTK THEMES" "Choose which GTK theme(s) to install"
    echo
    ui_item 1 "All GTK Themes (Nordic + Colloid + Material GNOME + Lycia)"
    ui_item 2 "Nordic"
    ui_item 3 "Colloid"
    ui_item 4 "Material GNOME"
    ui_item 5 "Lycia"
    echo
    ui_item 0 "Back"
    echo
    ui_rule
    printf "  ${MAUVE}${BOLD}❯${NC} ${LAVENDER}Choose ${DIM}[0-5]${NC}${LAVENDER}: ${NC}"
}

show_drivers_menu() {
    clear
    ui_header "DRIVERS & EXTRA REPOS"
    echo
    ui_item 1 "NVIDIA Driver"
    ui_item 2 "BlackArch Repo (extra security/pentest packages, opt-in)"
    ui_item 3 "Chaotic-AUR Repo (prebuilt AUR binaries, opt-in)"
    ui_item 4 "DisplayLink Driver (USB/dock display adapters, AUR)"
    echo
    ui_item 0 "Back to Main Menu"
    echo
    ui_rule
    printf "  ${MAUVE}${BOLD}❯${NC} ${LAVENDER}Choose ${DIM}[0-4]${NC}${LAVENDER}: ${NC}"
}

show_snapshots_menu() {
    clear
    ui_header "SNAPSHOTS & BACKUP" "$($IS_OMARCHY && echo "Omarchy already runs Btrfs+Snapper+Limine" || echo "Auto-detects Btrfs (Snapper+GUI) vs other (Timeshift)")"
    echo
    ui_item 1 "Full Setup (install + configure + enable timers)"
    ui_item 2 "Create a snapshot now"
    ui_item 3 "List snapshots"
    ui_item 4 "Open GUI (Btrfs Assistant / Timeshift)"
    echo
    ui_item 0 "Back to Main Menu"
    echo
    ui_rule
    printf "  ${MAUVE}${BOLD}❯${NC} ${LAVENDER}Choose ${DIM}[0-4]${NC}${LAVENDER}: ${NC}"
}

show_peripherals_menu() {
    clear
    ui_header "PERIPHERALS (LOGITECH)" "Solaar - HID++ device management"
    echo
    ui_item 1 "Install Solaar (peripheral manager)"
    ui_item 2 "Fix slow scroll wheel (MX Anywhere 3S - enable Scroll Wheel Resolution)"
    echo
    ui_item 0 "Back to Main Menu"
    echo
    ui_rule
    printf "  ${MAUVE}${BOLD}❯${NC} ${LAVENDER}Choose ${DIM}[0-2]${NC}${LAVENDER}: ${NC}"
}

main() {
    check_root
    check_version
    update_packages
    bootstrap_arch
    install_base
    while true; do
        show_main_menu
        read -r choice
        case "$choice" in
            0)
                display_summary
                save_log
                log INFO "Exiting..."
                exit 0
                ;;
            S|s)
                display_summary
                read -p "$(printf "${DIM}${SUBTEXT}  Press [Enter] to continue…${NC}")" _
                ;;
            1)
                show_creative_menu
                read -r cr_choice
                case "$cr_choice" in
                    0) continue ;;
                    1) reset_tracking; install_creative_full;        display_summary; prompt_menu_category "Creative Suite" "applications-graphics" "Creative Suite Applications" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    2) reset_tracking; install_creative_graphics;    display_summary; prompt_menu_category "Graphics & Design" "applications-graphics" "Graphics & Design" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    3) reset_tracking; install_creative_video;       display_summary; prompt_menu_category "Video Editing" "video" "Video Editing" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    4) reset_tracking; install_creative_audio;       display_summary; prompt_menu_category "Audio Production" "audio" "Audio Production" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    5) reset_tracking; install_creative_photography; display_summary; prompt_menu_category "Photography" "camera" "Photography" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    6) reset_tracking; install_creative_publishing;  display_summary; prompt_menu_category "Publishing" "office" "Publishing" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    *) log ERROR "Invalid choice"; sleep 2 ;;
                esac
                ;;
            2) reset_tracking; install_code_editors; display_summary; prompt_menu_category "Code Editors" "text-editor" "Code Editors" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            3) reset_tracking; install_python; display_summary; prompt_menu_category "Python Development" "python" "Python Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            4) reset_tracking; install_web_dev; display_summary; prompt_menu_category "Web Development" "web" "Web Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            5) reset_tracking; install_java; display_summary; prompt_menu_category "Java Development" "java" "Java Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            6) reset_tracking; install_c_cpp; display_summary; prompt_menu_category "C/C++ Development" "application-x-executable" "C/C++ Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            7) reset_tracking; install_go; display_summary; prompt_menu_category "Go Development" "golang" "Go Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            8) reset_tracking; install_rust; display_summary; prompt_menu_category "Rust Development" "rust" "Rust Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            9) reset_tracking; install_nodejs_dev; display_summary; prompt_menu_category "Node.js Development" "nodejs" "Node.js Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            10) reset_tracking; install_php; display_summary; prompt_menu_category "PHP Development" "php" "PHP Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            11) reset_tracking; install_ruby; display_summary; prompt_menu_category "Ruby Development" "ruby" "Ruby Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            12) reset_tracking; install_databases; display_summary; prompt_menu_category "Database Tools" "database" "Database Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            13) reset_tracking; install_containers; display_summary; prompt_menu_category "Containers" "docker" "Container & Virtualization Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            14) reset_tracking; install_gaming; display_summary; prompt_menu_category "Gaming" "games" "Gaming Applications" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            15) reset_tracking; install_office; display_summary; prompt_menu_category "Office & Productivity" "office" "Office & Productivity Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            16) reset_tracking; install_system_utils; display_summary; prompt_menu_category "System Utilities" "utilities" "System Utilities" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            17) reset_tracking; install_dev_tools; display_summary; prompt_menu_category "General Development Tools" "development" "General Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            18) reset_tracking; install_ai_tools; display_summary; prompt_menu_category "AI Tools" "ai" "AI Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            19)
                show_gui_tweaks_menu
                read -r gui_choice
                if $IS_OMARCHY; then
                    local pause_prompt; pause_prompt="$(printf "${DIM}${SUBTEXT}  Press [Enter] to continue…${NC}")"
                    case "$gui_choice" in
                        0) continue ;;
                        1) reset_tracking; install_gui_tweaks; display_summary; read -p "$pause_prompt" _ ;;
                        2) reset_tracking; install_nerd_fonts; display_summary; read -p "$pause_prompt" _ ;;
                        3) reset_tracking; install_chris_titus_mybash; display_summary; read -p "$pause_prompt" _ ;;
                        4) omarchy_theme_picker ;;
                        *) log ERROR "Invalid choice"; sleep 2 ;;
                    esac
                else
                    case "$gui_choice" in
                        0) continue ;;
                        1) reset_tracking; install_gui_tweaks;        display_summary; prompt_menu_category "GUI Tweaks" "preferences" "GUI Customization & Tweaks" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                        2) reset_tracking; install_icon_sets;         display_summary; prompt_menu_category "GUI Tweaks" "preferences" "GUI Customization & Tweaks" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                        3)
                            show_gtk_theme_menu
                            read -r theme_choice
                            case "$theme_choice" in
                                0) continue ;;
                                1) reset_tracking; install_themes;        display_summary; prompt_menu_category "GUI Tweaks" "preferences" "GUI Customization & Tweaks" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                                2) reset_tracking; install_nordic_theme;         display_summary; prompt_menu_category "GUI Tweaks" "preferences" "GUI Customization & Tweaks" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                                3) reset_tracking; install_colloid_theme;        display_summary; prompt_menu_category "GUI Tweaks" "preferences" "GUI Customization & Tweaks" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                                4) reset_tracking; install_material_gnome_theme; display_summary; prompt_menu_category "GUI Tweaks" "preferences" "GUI Customization & Tweaks" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                                5) reset_tracking; install_lycia_theme;          display_summary; prompt_menu_category "GUI Tweaks" "preferences" "GUI Customization & Tweaks" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                                *) log ERROR "Invalid choice"; sleep 2 ;;
                            esac
                            ;;
                        4) reset_tracking; install_cursor_themes;     display_summary; prompt_menu_category "GUI Tweaks" "preferences" "GUI Customization & Tweaks" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                        5) reset_tracking; install_nerd_fonts; configure_terminal_font; display_summary; prompt_menu_category "GUI Tweaks" "preferences" "GUI Customization & Tweaks" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                        6) reset_tracking; install_chris_titus_mybash; display_summary; prompt_menu_category "GUI Tweaks" "preferences" "GUI Customization & Tweaks" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                        7) reset_tracking; install_gui_tools;         display_summary; prompt_menu_category "GUI Tweaks" "preferences" "GUI Customization & Tweaks" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                        8) reset_tracking; install_gnome_extensions;  display_summary; prompt_menu_category "GUI Tweaks" "preferences" "GUI Customization & Tweaks" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                        *) log ERROR "Invalid choice"; sleep 2 ;;
                    esac
                fi
                ;;
            20) reset_tracking; install_windows_support; display_summary; prompt_menu_category "Windows Software Support" "wine" "Windows Software Support (Wine)" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            21) reset_tracking; install_android_tools; display_summary; prompt_menu_category "Android Tools" "phone" "Android Tools (adb, fastboot, scrcpy)" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            22)
                show_security_menu
                read -r sec_choice
                case "$sec_choice" in
                    0) continue ;;
                    1) reset_tracking; install_security_tools; display_summary; prompt_menu_category "Security Tools" "security" "Security & Pentest Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    2) reset_tracking; install_security_defensive; display_summary; prompt_menu_category "Security (Defensive)" "security" "Defensive Security Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    *) log ERROR "Invalid choice"; sleep 2 ;;
                esac
                ;;
            23) reset_tracking; install_dotnet; display_summary; prompt_menu_category ".NET Development" "dotnet" ".NET Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            24) reset_tracking; install_devops; display_summary; prompt_menu_category "DevOps & Cloud" "cloud" "DevOps & Cloud Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            25) reset_tracking; install_desktop_apps; display_summary; prompt_menu_category "Desktop Apps" "applications-other" "Desktop Applications" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            26)
                show_browsers_menu
                read -r br_choice
                case "$br_choice" in
                    0) continue ;;
                    1) reset_tracking; install_browsers;  display_summary; prompt_menu_category "Browsers" "web-browser" "Web Browsers" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    2) reset_tracking; install_brave;     display_summary; prompt_menu_category "Browsers" "web-browser" "Web Browsers" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    3) reset_tracking; install_vivaldi;   display_summary; prompt_menu_category "Browsers" "web-browser" "Web Browsers" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    4) reset_tracking; install_edge;      display_summary; prompt_menu_category "Browsers" "web-browser" "Web Browsers" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    5) reset_tracking; install_chrome;    display_summary; prompt_menu_category "Browsers" "web-browser" "Web Browsers" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    6) reset_tracking; install_librewolf; display_summary; prompt_menu_category "Browsers" "web-browser" "Web Browsers" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    7) reset_tracking; install_zen;       display_summary; prompt_menu_category "Browsers" "web-browser" "Web Browsers" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    8) reset_tracking; install_floorp;    display_summary; prompt_menu_category "Browsers" "web-browser" "Web Browsers" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    *) log ERROR "Invalid choice"; sleep 2 ;;
                esac
                ;;
            27)
                show_communication_menu
                read -r comm_choice
                case "$comm_choice" in
                    0) continue ;;
                    1) reset_tracking; install_communication; display_summary; prompt_menu_category "Communication" "internet-group-chat" "Communication Apps" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    2) reset_tracking; install_signal;    display_summary; prompt_menu_category "Communication" "internet-group-chat" "Communication Apps" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    3) reset_tracking; install_discord;   display_summary; prompt_menu_category "Communication" "internet-group-chat" "Communication Apps" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    4) reset_tracking; install_telegram;  display_summary; prompt_menu_category "Communication" "internet-group-chat" "Communication Apps" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    5) reset_tracking; install_teams;     display_summary; prompt_menu_category "Communication" "internet-group-chat" "Communication Apps" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    *) log ERROR "Invalid choice"; sleep 2 ;;
                esac
                ;;
            28)
                show_drivers_menu
                read -r drv_choice
                case "$drv_choice" in
                    0) continue ;;
                    1) reset_tracking; install_nvidia_driver; display_summary; read -p "$(printf "${DIM}${SUBTEXT}  Press [Enter] to continue…${NC}")" _ ;;
                    2) reset_tracking; install_blackarch_repo; display_summary; read -p "$(printf "${DIM}${SUBTEXT}  Press [Enter] to continue…${NC}")" _ ;;
                    3) reset_tracking; install_chaotic_aur; display_summary; read -p "$(printf "${DIM}${SUBTEXT}  Press [Enter] to continue…${NC}")" _ ;;
                    4) reset_tracking; install_displaylink_driver; display_summary; read -p "$(printf "${DIM}${SUBTEXT}  Press [Enter] to continue…${NC}")" _ ;;
                    *) log ERROR "Invalid choice"; sleep 2 ;;
                esac
                ;;
            29)
                show_snapshots_menu
                read -r snap_choice
                case "$snap_choice" in
                    0) continue ;;
                    1) reset_tracking; install_snapshots_full; display_summary; read -p "$(printf "${DIM}${SUBTEXT}  Press [Enter] to continue…${NC}")" _ ;;
                    2) snapshot_create_now ;;
                    3) snapshot_list ;;
                    4) snapshot_open_gui ;;
                    *) log ERROR "Invalid choice"; sleep 2 ;;
                esac
                ;;
            30)
                show_peripherals_menu
                read -r periph_choice
                case "$periph_choice" in
                    0) continue ;;
                    1) reset_tracking; install_peripheral_tools; display_summary; read -p "$(printf "${DIM}${SUBTEXT}  Press [Enter] to continue…${NC}")" _ ;;
                    2) fix_logitech_hires_scroll ;;
                    *) log ERROR "Invalid choice"; sleep 2 ;;
                esac
                ;;
            A|a)
                auto_category "Code Editors" install_code_editors
                auto_category "Python" install_python
                auto_category "Web Development" install_web_dev
                auto_category "Java" install_java
                auto_category "C/C++" install_c_cpp
                auto_category "Go" install_go
                auto_category "Rust" install_rust
                auto_category "Node.js" install_nodejs_dev
                auto_category "PHP" install_php
                auto_category "Ruby" install_ruby
                auto_category ".NET" install_dotnet
                auto_category "General Dev Tools" install_dev_tools
                auto_category "AI Tools" install_ai_tools
                ;;
            B|b)
                auto_category "Creative Suite" install_creative_full
                ;;
            C|c)
                auto_category "Creative Suite" install_creative_full
                auto_category "Code Editors" install_code_editors
                auto_category "Python" install_python
                auto_category "Web Development" install_web_dev
                auto_category "Java" install_java
                auto_category "C/C++" install_c_cpp
                auto_category "Go" install_go
                auto_category "Rust" install_rust
                auto_category "Node.js" install_nodejs_dev
                auto_category "PHP" install_php
                auto_category "Ruby" install_ruby
                auto_category "Database Tools" install_databases
                auto_category "Containers" install_containers
                auto_category "Gaming" install_gaming
                auto_category "Office & Productivity" install_office
                auto_category "System Utilities" install_system_utils
                auto_category "General Dev Tools" install_dev_tools
                auto_category "AI Tools" install_ai_tools
                auto_category "GUI Tweaks" install_gui_tweaks
                auto_category "Windows Software Support" install_windows_support
                auto_category "Android Tools" install_android_tools
                auto_category "Security Tools" install_security_tools
                auto_category ".NET" install_dotnet
                auto_category "DevOps & Cloud" install_devops
                auto_category "Desktop Apps" install_desktop_apps
                auto_category "Browsers" install_browsers
                auto_category "Communication" install_communication
                ;;
            *) log ERROR "Invalid choice"; sleep 2 ;;
        esac
    done
}

main
