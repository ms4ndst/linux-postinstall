#!/bin/bash
# Ubuntu 26.04 LTS / 26.10 Post-Install Script v2
# Menu-driven installer with error handling and VERIFIED packages only
# Run as: chmod +x post-install.sh && sudo ./post-install.sh

# ── Catppuccin Mocha palette (24-bit truecolor ANSI) ─────────────────────────
# Colors are assigned by SEMANTIC ROLE, not by hex-at-random: Red=errors,
# Green=success, Yellow=warnings, Blue=info, Mauve=accent/headings, Lavender=
# active/prompts/"you are here", Peach=bulk actions, Teal=secondary. Hex values
# are from the Catppuccin Mocha palette (the default dark flavor). Everything
# auto-disables when stdout isn't a terminal or NO_COLOR is set, so piped or
# redirected output (and the plain-text log file) stays clean.
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
# A 58-wide horizontal rule (built at load so the width is never miscounted).
# Header box = ╭ + rule + ╮ = 60 cols, matching the two-column menu (2 cells of
# 30 cols each). ui_rule (dim) is the plain divider used mid-page.
printf -v UI_RULE '─%.0s' {1..58}
ui_rule() { printf "${OVERLAY}%s${NC}\n" "$UI_RULE"; }
# Framed header: rounded-corner top/bottom in the Mauve accent, bold Lavender
# title, optional dim subtitle. Open sides (no vertical bars) so there's no
# right-edge padding math to get wrong.
ui_header() {
    printf "${MAUVE}${BOLD}╭%s╮${NC}\n" "$UI_RULE"
    printf "  ${LAVENDER}${BOLD}%s${NC}\n" "$1"
    [ -n "${2:-}" ] && printf "  ${DIM}${SUBTEXT}%s${NC}\n" "$2"
    printf "${MAUVE}${BOLD}╰%s╯${NC}\n" "$UI_RULE"
}
# Single-column menu row (used by the short sub-menus): key in accent, label body.
ui_item()     { printf "  ${MAUVE}%3s${NC}  ${TEXT}%s${NC}\n" "$1" "$2"; }
# Two-column menu cell (no newline): fixed 30-col visible width so two align.
# Padding is applied to the %-24s ARGUMENT, so the zero-width color codes in the
# format string don't disturb alignment. ui_cell_alt = Peach key (bulk actions).
ui_cell()     { printf "  ${MAUVE}%2s${NC}  ${TEXT}%-24s${NC}" "$1" "$2"; }
ui_cell_alt() { printf "  ${PEACH}%2s${NC}  ${TEXT}%-24s${NC}" "$1" "$2"; }

# Releases this script is validated against. Both share the same package names
# and codename-resolved repositories, so one code path serves both; version-
# specific behavior is dispatched through is_lts()/UBUNTU_CODENAME below rather
# than by forking the whole script. Add a release here to make check_version
# accept it without prompting.
declare -a SUPPORTED_VERSIONS=("26.04" "26.10")
# Populated by detect_version() at startup; read everywhere else.
UBUNTU_VERSION=""
UBUNTU_CODENAME=""

declare -a INSTALLED_PACKAGES FAILED_PACKAGES SKIPPED_PACKAGES
TOTAL_INSTALLED=0; TOTAL_FAILED=0; TOTAL_SKIPPED=0

log() {
    local l="$1" m="$2"
    # Message goes through %s (never the format string) so a stray % or
    # backslash in $m can't be misinterpreted by printf.
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

# Detect the running release once, into globals the rest of the script reads.
# Prefers lsb_release (present after install_base pulls lsb-release, and shipped
# by default on desktop) and falls back to /etc/os-release, which always exists.
detect_version() {
    UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || grep -oP '(?<=^VERSION_ID=).+' /etc/os-release 2>/dev/null | tr -d '"')
    UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || grep -oP '(?<=^VERSION_CODENAME=).+' /etc/os-release 2>/dev/null | tr -d '"')
}

check_version() {
    detect_version
    local supported=false v
    for v in "${SUPPORTED_VERSIONS[@]}"; do
        [[ "$UBUNTU_VERSION" == "$v" ]] && { supported=true; break; }
    done
    if $supported; then
        log INFO "Detected supported Ubuntu $UBUNTU_VERSION (${UBUNTU_CODENAME:-unknown codename})"
    else
        local joined; joined=$(IFS=/; echo "${SUPPORTED_VERSIONS[*]}")
        log WARNING "Designed for Ubuntu ${joined}, detected: ${UBUNTU_VERSION:-unknown}"
        read -p "Continue anyway? [y/N] " -n 1 -r; echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
}

is_installed() { dpkg -l "$1" 2>/dev/null | grep -q "^ii"; }
# Does an installable candidate exist for this exact package? Uses `apt-cache
# policy` (literal package name) rather than `apt-cache search "^name$"`, whose
# ARGUMENT IS A REGEX - names with regex metacharacters like libconfig++-dev
# (invalid `++`) or an arch qualifier like libgl1-mesa-glx:i386 never matched and
# were wrongly reported "Not in repos". policy takes a literal name (arch
# qualifier included) and reports the candidate version, or "(none)" when there's
# no installable candidate.
package_exists() {
    local cand
    cand=$(apt-cache policy "$1" 2>/dev/null | awk -F': ' '/Candidate:/{print $2; exit}')
    [ -n "$cand" ] && [ "$cand" != "(none)" ]
}

# ── Package-manager front-end ────────────────────────────────────────────────
# Nala (https://github.com/volitank/nala) is a friendlier apt front-end with
# parallel downloads and cleaner output. install_nala() sets PM=nala once it's
# installed; until then (and if it's ever unavailable) PM stays apt-get, so the
# script works either way. Only install/update are routed through the front-end
# - queries stay on apt-cache/dpkg because nala has no equivalent for e.g.
# `apt-cache depends --recurse`. Both wrappers swallow stderr to match the
# script's existing "ignore install-info noise" behavior; callers still rely on
# the exit code (and an is_installed re-check) to decide success.
PM="apt-get"
pm_update() {
    if [ "$PM" = "nala" ]; then nala update 2>/dev/null; else apt-get update -qq 2>/dev/null; fi
}
pm_install() {
    if [ "$PM" = "nala" ]; then nala install -y "$@" 2>/dev/null; else apt-get install -y "$@" 2>/dev/null; fi
}

# Bootstrap Nala. Must run AFTER the first apt-get update (needs package lists)
# and is installed with apt-get since nala isn't present yet. On success PM
# flips to nala for every later install/update; on failure the script simply
# keeps using apt-get. Not fatal either way.
install_nala() {
    if command -v nala &>/dev/null; then
        PM="nala"; log INFO "Nala already present - using it as the apt front-end"; return 0
    fi
    if ! package_exists nala; then
        log WARNING "Nala not in repos for ${UBUNTU_CODENAME:-this release} - using apt-get"; return 1
    fi
    log INFO "Installing Nala (nicer apt front-end: parallel downloads, cleaner output)..."
    if apt-get install -y nala 2>/dev/null && command -v nala &>/dev/null; then
        PM="nala"; log SUCCESS "Nala installed - routing package operations through it"
    else
        log WARNING "Nala install failed - continuing with apt-get"; return 1
    fi
}

# Recover from a previous run's `nala fetch` mirror selection. That command wrote
# the chosen mirrors to /etc/apt/sources.list.d/fetch.sources; on a fresh interim
# release those mirrors are frequently incomplete or unsigned, producing 404 /
# "is not signed" errors on every apt/nala operation. This script no longer runs
# `nala fetch`, but a leftover file from an older version persists and keeps
# breaking updates. Detect it up front (before the first update, which the bad
# file would otherwise fail) and offer to remove it so the system falls back to
# Ubuntu's default mirrors in ubuntu.sources. Prompted, default-yes, non-fatal.
check_stale_fetch_sources() {
    local f="/etc/apt/sources.list.d/fetch.sources"
    [ -f "$f" ] || return 0
    log WARNING "Found a leftover Nala mirror list ($f) from a previous 'nala fetch'."
    log WARNING "Such mirrors often cause 404 / 'is not signed' errors on updates."
    local do_it=false
    local msg="A leftover 'nala fetch' mirror list was found:\n  $f\n\nIt can cause 404 / signature errors on every update. Remove it and\nfall back to Ubuntu's default mirrors?"
    if command -v whiptail &>/dev/null; then
        whiptail --yesno "$msg" --yes-button "Remove" --no-button "Keep" 13 72 && do_it=true
    else
        echo -e "$msg [Y/n]:"
        read -r REPLY
        case "$REPLY" in ""|y|Y) do_it=true;; esac
    fi
    if $do_it; then
        rm -f "$f" && log SUCCESS "Removed $f - using Ubuntu's default mirrors"
    else
        log INFO "Keeping $f - mirror errors may persist"
    fi
}

safe_install() {
    for pkg in "$@"; do
        [[ -z "$pkg" ]] && continue
        if is_installed "$pkg"; then
            SKIPPED_PACKAGES+=("$pkg"); ((TOTAL_SKIPPED++))
            log INFO "Already installed: $pkg"; continue
        fi
        if ! package_exists "$pkg"; then
            FAILED_PACKAGES+=("$pkg"); ((TOTAL_FAILED++))
            log WARNING "Not in repos: $pkg"; continue
        fi
        log INFO "Installing: $pkg"
        # Install via the active front-end (Nala when available, else apt-get);
        # ignore install-info errors (common on these releases).
        if pm_install "$pkg" || is_installed "$pkg"; then
            INSTALLED_PACKAGES+=("$pkg"); ((TOTAL_INSTALLED++))
            log SUCCESS "Installed: $pkg"
        else
            FAILED_PACKAGES+=("$pkg"); ((TOTAL_FAILED++))
            log ERROR "Failed: $pkg"
        fi
    done
}

# systemd prints a "unit files changed on disk, run daemon-reload" notice when a
# package install drops or updates a unit file or binfmt registration (e.g. a
# clang/binfmt file in C/C++). It's informational, not an error - but left
# unaddressed, systemd keeps the "changed on disk" flag set and Nala re-prints
# the notice on every subsequent per-package transaction. A quiet daemon-reload
# reconciles systemd's view and stops the notice from recurring. It only reparses
# units (starts/stops nothing), and is a no-op where systemd isn't the init
# (containers/WSL), so it's always safe to call.
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

update_packages() {
    log INFO "Updating package lists..."
    if ! pm_update; then
        log ERROR "Failed to update. Check internet."
        read -p "Retry? [y/N] " -n 1 -r; echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then update_packages; else log ERROR "Cannot proceed."; exit 1; fi
    fi
    log SUCCESS "Updated."
}

install_base() {
    log INFO "Installing base utilities..."
    # dbus-x11 provides dbus-launch: without it, any dconf write made without an
    # active D-Bus session (e.g. Chris Titus mybash's setup.sh applying a
    # terminal-font setting under sudo) fails with a "dbus-launch: No such file
    # or directory" warning. Harmless but noisy; installing it quiets that path
    # on both 26.04 and 26.10.
    batch_install "base" software-properties-common apt-transport-https ca-certificates curl wget git gnupg lsb-release ubuntu-keyring whiptail debconf-utils dialog alacarte dconf-cli dbus-x11
    
    # Create menu directory for custom categories
    mkdir -p /usr/share/desktop-directories
}

# Create GNOME Shell app folder via the real schema: org.gnome.desktop.app-folders
# (This is the only schema GNOME Shell's Activities/app-grid overview reads for
#  folder grouping. Editing .desktop 'Categories=' does NOT create a folder there
#  on any GNOME Shell version - that field is for other menu implementations.)

# Run a gsettings command as the target desktop user with a valid session
gsettings_as_user() {
    local user="$1" uid="$2"; shift 2
    local home; home=$(getent passwd "$user" | cut -d: -f6)
    sudo -u "$user" \
        HOME="$home" \
        XDG_RUNTIME_DIR="/run/user/${uid}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
        gsettings "$@"
}

# Resolve the logged-in desktop user + uid and confirm a live D-Bus session bus
# exists for them. Any gsettings/dconf write needs that session bus; a root/SSH/
# TTY invocation doesn't have one. Echoes "user uid" on success; on failure logs
# a specific reason and returns non-zero so callers can skip gracefully.
# Usage: read -r user uid < <(resolve_desktop_session) || return 1
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
        log WARNING "No active GNOME session for $user (/run/user/${uid}/bus missing) - run from a logged-in desktop" >&2
        return 1
    fi
    echo "$user $uid"
}

# Set a gsettings key ONLY if the schema is installed and the key exists, so the
# same call is a safe no-op across releases/terminals that lack it (e.g. Ptyxis
# keys absent on a box that only has gnome-terminal, or vice-versa). Works for
# non-relocatable schemas; relocatable per-profile schemas are handled inline by
# their callers. Returns non-zero (quietly) when the schema/key isn't present.
gset_if_exists() {
    local user="$1" uid="$2" schema="$3" key="$4" value="$5"
    gsettings_as_user "$user" "$uid" list-schemas 2>/dev/null | grep -qx "$schema" || return 1
    gsettings_as_user "$user" "$uid" list-keys "$schema" 2>/dev/null | grep -qx "$key" || return 1
    gsettings_as_user "$user" "$uid" set "$schema" "$key" "$value" 2>/dev/null
}

# Create/append a GNOME app folder (verified schema, GNOME 3.12 through 51)
# Usage: create_menu_category "Display Name" "icon(unused)" "comment(unused)" "pkg1" "pkg2" ...
create_menu_category() {
    local name="$1" icon="$2" comment="$3"
    shift 3
    local apps=("$@")

    # Sanitize to a safe dconf path segment: slashes, dots, plusses (e.g. "C/C++
    # Development") would otherwise corrupt the dconf path or break parsing.
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

    # Resolve requested packages to actual .desktop file IDs.
    # Modern packages (KDE apps, HandBrake, OBS, MuseScore, ...) ship desktop
    # files under a reverse-DNS ID (e.g. org.kde.kdenlive.desktop,
    # fr.handbrake.ghb.desktop) that has nothing predictable to do with the apt
    # package name, and the exact prefix varies by upstream project and even by
    # packaging era - guessing a fixed prefix list is fragile (this is why apps
    # like winetricks silently dropped out of their group before: whatever name
    # was hardcoded at the call site didn't match, and the guess list below
    # doesn't cover every vendor). Since callers now pass real, just-installed
    # package names (see the case statement), asking dpkg what that exact
    # package actually shipped is authoritative and works for every vendor.
    #
    # A package's own file list can contain MULTIPLE .desktop files that
    # aren't real, separate menu entries: okular ships one per file type it
    # can open (okularApplication_comicbook.desktop, ..._pdf.desktop, etc,
    # all pointing at the same app) and libreoffice-xsltfilter.desktop is just
    # a filter registration - none of these are meant to appear anywhere.
    # Every one of them sets NoDisplay=true, which is the exact, standard
    # signal desktop environments use to hide a .desktop file from menus -
    # GNOME Shell itself honors it. Filtering on it is what tells apart those
    # decoy files from a package's real, separate applications: libreoffice's
    # component apps (writer/calc/impress/draw/base/math/startcenter) are
    # ALL real, independently displayable apps with NoDisplay unset - so
    # unlike okular/evince, "libreoffice" is supposed to contribute several
    # icons to its group, not just one. Picking a single "best" match per
    # package (the previous approach) was wrong in both directions: it could
    # grab a NoDisplay decoy (okular picked okularApplication_comicbook.desktop
    # over the real org.kde.okular.desktop; evince picked the
    # print-preview-only Evince-previewer.desktop over the real
    # org.gnome.Evince.desktop) AND it dropped every LibreOffice app but one.
    displayable_desktop_files() {
        local pkg="$1" f
        dpkg -L "$pkg" 2>/dev/null | grep -iE '/applications/.*\.desktop$' | while IFS= read -r f; do
            grep -qE '^(NoDisplay|Hidden)[[:space:]]*=[[:space:]]*true' "$f" 2>/dev/null || basename "$f"
        done
    }

    local desktop_ids=()
    for app in "${apps[@]}"; do
        local found=()
        if is_installed "$app"; then
            local pkg_bare="${app%%:*}"
            local line
            while IFS= read -r line; do [ -n "$line" ] && found+=("$line"); done < <(displayable_desktop_files "$app")
            # Some packages split their launcher into a dependency rather than
            # shipping it themselves - neovim's real desktop file
            # (nvim.desktop) lives in neovim-runtime, vim's (vim.desktop) in
            # vim-common, and a pure meta-package like "libreoffice" or
            # "emacs" has NO files of its own at all and depends on several
            # genuinely separate real apps. "emacs" specifically depends ONLY
            # on a 4-way alternative (emacs-gtk | emacs-pgtk | emacs-lucid |
            # emacs-nox - whichever one apt actually resolved), and the app
            # you actually want, emacsclient.desktop ("Emacs (Client)"), is a
            # dependency of THAT alternative, not of "emacs" directly - two
            # levels down, not one. A plain "check direct Depends" walk
            # cannot see that far and also cannot tell an OR-alternative
            # apart from a real Depends line without extra parsing that's
            # easy to get subtly wrong (an earlier version of this only
            # matched the LAST alternative in the OR-group, e.g. emacs-nox,
            # which usually isn't even the one apt installed).
            #
            # `apt-cache depends --recurse --important` sidesteps all of that:
            # it walks the full dependency tree (Depends/PreDepends only, no
            # Recommends/Suggests noise) and lists every package name
            # regardless of alternative-group formatting. is_installed then
            # naturally discards every alternative that ISN'T the one actually
            # on this system, so there's no risk of crediting an uninstalled
            # alternative's files. Collect from every match, don't stop at the
            # first, for the same reason as above: a meta-package can
            # legitimately have several real, separate components.
            if [ ${#found[@]} -eq 0 ]; then
                # Batch the dpkg lookups instead of forking once per candidate
                # dependency. emacs alone has 254 entries in its recursive
                # Depends tree; calling `dpkg -l`/`dpkg -L` once PER entry
                # (~18ms/call) turned this into a ~12s stall. dpkg -l and
                # dpkg -L both accept a list of package names in one
                # invocation, so the whole tree resolves in ~2 dpkg calls
                # total - measured at ~1.7s for emacs, matching the cost of
                # the apt-cache call alone (i.e. the dpkg lookups now add
                # essentially nothing).
                local all_deps=() installed_deps=() dep line
                while IFS= read -r dep; do
                    [ -n "$dep" ] && all_deps+=("$dep")
                done < <(apt-cache depends --recurse --important "$pkg_bare" 2>/dev/null | awk '$1 ~ /Depends:$/ {print $2}' | sort -u)
                if [ ${#all_deps[@]} -gt 0 ]; then
                    while IFS= read -r dep; do
                        [ -n "$dep" ] && installed_deps+=("$dep")
                    done < <(dpkg -l "${all_deps[@]}" 2>/dev/null | awk '/^ii/{print $2}' | sed -E 's/:.*//')
                    if [ ${#installed_deps[@]} -gt 0 ]; then
                        while IFS= read -r line; do
                            [ -n "$line" ] || continue
                            grep -qE '^(NoDisplay|Hidden)[[:space:]]*=[[:space:]]*true' "$line" 2>/dev/null || found+=("$(basename "$line")")
                        done < <(dpkg -L "${installed_deps[@]}" 2>/dev/null | grep -iE '/applications/.*\.desktop$')
                    fi
                fi
            fi
        fi
        # Fallback: guess a common reverse-DNS prefix. Only useful when the
        # caller passed a display name rather than a literal package (e.g. a
        # meta group), since a real package is already covered above.
        if [ ${#found[@]} -eq 0 ]; then
            for pattern in "" "org.kde." "org.gnome." "com.obsproject." "org.handbrake." "fr.handbrake." "org.ardour." "org.pitivi." "org.bunkus." "net.shotcut." "org.musescore."; do
                local candidate="/usr/share/applications/${pattern}${app}.desktop"
                if [ -f "$candidate" ] && ! grep -qE '^(NoDisplay|Hidden)[[:space:]]*=[[:space:]]*true' "$candidate" 2>/dev/null; then
                    found+=("${pattern}${app}.desktop")
                    break
                fi
            done
        fi
        # Snap-installed apps (e.g. intellij-idea-community) ship their
        # desktop file in a completely different place with a different naming
        # scheme: /var/lib/snapd/desktop/applications/<snapname>_<appname>.desktop
        # - dpkg has never heard of them (is_installed above is always false for
        # a snap) and they don't match the guessed prefixes either, so every
        # snap-only app's icon was silently dropping out of its group until now.
        # Glob instead of guessing the exact <appname> suffix, since it isn't
        # always identical to the snap name.
        if [ ${#found[@]} -eq 0 ]; then
            local snap_match
            snap_match=$(compgen -G "/var/lib/snapd/desktop/applications/${app}_*.desktop" 2>/dev/null | head -1)
            [ -z "$snap_match" ] && snap_match=$(compgen -G "/var/lib/snapd/desktop/applications/${app}.desktop" 2>/dev/null | head -1)
            [ -n "$snap_match" ] && found+=("$(basename "$snap_match")")
        fi
        # Flatpak-exported apps (Alpaca, Windows App, ...) live in export dirs that
        # dpkg/snap/prefix guessing never see - system-wide under /var/lib/flatpak
        # and per-user under ~/.local/share/flatpak. Their .desktop filename is a
        # reverse-DNS app-id (com.jeffser.Alpaca.desktop) with no relation to the
        # display name callers track them by ("Alpaca", "Windows App"), so match on
        # the launcher's own [Desktop Entry] Name= (the first Name= in the file),
        # falling back to a filename match. Honor NoDisplay/Hidden like every stage.
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
    # Dedup in case two requested packages resolved to the same file.
    local uniq_ids=() d existing already
    for d in "${desktop_ids[@]}"; do
        already=false
        for existing in "${uniq_ids[@]}"; do [ "$existing" = "$d" ] && already=true && break; done
        $already || uniq_ids+=("$d")
    done
    desktop_ids=("${uniq_ids[@]}")

    # Build the 'apps' GVariant array, e.g. ['gimp.desktop', 'inkscape.desktop']
    local apps_gv="[" first=true
    for id in "${desktop_ids[@]}"; do
        $first && first=false || apps_gv+=", "
        apps_gv+="'${id}'"
    done
    apps_gv+="]"

    # Read the existing folder-children list so we ADD to it instead of clobbering
    # every other folder created by earlier menu options in this script.
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

# Display installation summary
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

# Save installation log
save_log() {
    local f="/var/log/ubuntu_post_install_$(date +%Y%m%d_%H%M%S).log"
    {
        echo "=== Log: $(date) ==="; echo "User: $(whoami)"; echo "Ubuntu: ${UBUNTU_VERSION:-unknown} (${UBUNTU_CODENAME:-unknown})"
        echo "Installed: ${TOTAL_INSTALLED}"; echo "Skipped: ${TOTAL_SKIPPED}"; echo "Failed: ${TOTAL_FAILED}"
        echo; echo "Installed packages:"; printf "  %s\n" "${INSTALLED_PACKAGES[@]}"
        echo; echo "Failed packages:"; printf "  %s\n" "${FAILED_PACKAGES[@]}"
    } > "$f"
    log INFO "Log saved to: $f"
}

# NOTE: the real metapackage names have NO hyphen between "ubuntu" and "studio"
# (ubuntustudio-video, not ubuntu-studio-video). The hyphenated names used below
# in earlier versions of this script don't exist in the archive at all - every
# one of these would have failed with "Not in repos" and been silently marked
# FAILED. Verified against the live Ubuntu archive (apt-cache policy) before
# fixing: ubuntustudio-video/audio/graphics/photography/publishing are all real
# universe/metapackages maintained by the Ubuntu Studio team.
install_ubuntu_studio_video() { batch_install "Ubuntu Studio Video" ubuntustudio-video; }
install_ubuntu_studio_audio() { batch_install "Ubuntu Studio Audio" ubuntustudio-audio; }
install_ubuntu_studio_graphics() { batch_install "Ubuntu Studio Graphics" ubuntustudio-graphics; }
install_ubuntu_studio_photography() { batch_install "Ubuntu Studio Photography" ubuntustudio-photography; }
install_ubuntu_studio_publishing() { batch_install "Ubuntu Studio Publishing" ubuntustudio-publishing; }

# Full Ubuntu Studio install = every submenu category (2-6: Graphics, Video,
# Audio, Photography, Publishing). Does not touch the underlying ubuntu-studio
# desktop session/theme packages - just the content metapackages, matching what
# submenu options 2-6 install individually.
install_ubuntu_studio_full() {
    install_ubuntu_studio_graphics
    install_ubuntu_studio_video
    install_ubuntu_studio_audio
    install_ubuntu_studio_photography
    install_ubuntu_studio_publishing
}

# ========== GRAPHICS ==========
install_graphics() {
    batch_install "Graphics" \
        gimp inkscape krita darktable rawtherapee shotwell nomacs pinta blender \
        flameshot \
        imagemagick graphicsmagick optipng jpegoptim pngquant webp
    set_flameshot_hotkey
}

# Bind the Print Screen key to Flameshot instead of GNOME's built-in screenshot
# UI. Two steps: (1) release 'Print' from GNOME's own screenshot keybindings so it
# stops grabbing the key, then (2) add a media-keys custom keybinding that runs
# 'flameshot gui' on Print, MERGING into any existing custom-keybindings array
# (same non-clobbering approach as create_menu_category's folder-children). Runs as
# the desktop user; self-skips with a clear log when Flameshot isn't installed or
# there's no live GNOME session. Idempotent - re-running just re-asserts the values.
set_flameshot_hotkey() {
    if ! command -v flameshot &>/dev/null; then
        log INFO "Flameshot not installed - skipping Print Screen keybinding"; return 0
    fi
    local user uid
    if ! read -r user uid < <(resolve_desktop_session); then
        log INFO "No desktop session - skipping Flameshot keybinding (bind Print to 'flameshot gui' later)"; return 0
    fi

    # 1) Free the Print key from GNOME's own screenshot bindings so it doesn't
    #    swallow the keypress before our custom binding sees it. Both the modern
    #    shell binding (GNOME 42+) and the legacy media-keys one are cleared; each
    #    is a quiet no-op where the schema/key is absent on this release.
    gset_if_exists "$user" "$uid" org.gnome.shell.keybindings show-screenshot-ui "[]" || true
    gset_if_exists "$user" "$uid" org.gnome.settings-daemon.plugins.media-keys screenshot "[]" || true

    # 2) Merge a custom keybinding entry for Flameshot into the existing list.
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

# ========== VIDEO ==========
install_video() {
    batch_install "Video" \
        kdenlive shotcut pitivi handbrake \
        mkvtoolnix mkvtoolnix-gui mpv vlc obs-studio \
        gstreamer1.0-libav ffmpeg yt-dlp
    # Full codec/plugin stack. Ubuntu ships GStreamer and VLC without the
    # patent-encumbered codecs (h.264/AAC/MP3 decoding via ffmpeg,
    # gstreamer-ugly's MP3/AC3/etc) for licensing reasons - they live in
    # universe/multiverse instead of being pulled in automatically, so
    # without this, playback of a lot of real-world media silently fails or
    # falls back to a broken/no-audio state. gstreamer1.0-libav is already
    # installed above; this adds the rest of the plugin tiers plus
    # libavcodec-extra (used by anything else that decodes through ffmpeg's
    # libraries, not just VLC) and unrar (many downloaded media bundles are
    # RAR archives). gstreamer1.0-vaapi adds hardware-accelerated decode
    # where the GPU supports it - harmless no-op otherwise.
    # ubuntu-restricted-extras (which pulls ttf-mscorefonts-installer) is NOT in
    # the batch above because it gates on an interactive Microsoft core-fonts
    # EULA (msttcorefonts/accepted-mscorefonts-eula, defaults to declined) that
    # would hang an unattended "apt-get install -y". It's offered instead as an
    # explicit opt-in below (install_restricted_extras), which surfaces the EULA
    # in a prompt and preseeds the answer so the install then runs unattended.
    batch_install "Media Codecs & Plugins" \
        gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-vaapi \
        libavcodec-extra unrar
    install_libdvdcss
    install_restricted_extras
}

# Optional Ubuntu "restricted extras": extra patent-encumbered codecs (MP3/H.264
# helpers) plus Microsoft core fonts. Kept out of the default codec batch because
# its ttf-mscorefonts-installer dependency requires accepting the Microsoft
# core-fonts EULA - so this is a deliberate opt-in with the EULA shown in the
# prompt, then preseeded (same debconf-set-selections technique as libdvd-pkg)
# so the install is non-interactive. Declining is tracked as SKIPPED, not FAILED.
install_restricted_extras() {
    if is_installed ubuntu-restricted-extras; then
        SKIPPED_PACKAGES+=("ubuntu-restricted-extras"); ((TOTAL_SKIPPED++))
        log INFO "Already installed: ubuntu-restricted-extras"
        return 0
    fi
    if ! package_exists ubuntu-restricted-extras; then
        FAILED_PACKAGES+=("ubuntu-restricted-extras"); ((TOTAL_FAILED++))
        log WARNING "Not in repos: ubuntu-restricted-extras"
        return 1
    fi

    local msg="Install ubuntu-restricted-extras (extra MP3/H.264 codecs + Microsoft core fonts)?\n\nChoosing Yes ACCEPTS the Microsoft core-fonts EULA on your behalf."
    local do_it=false
    if command -v whiptail &>/dev/null; then
        whiptail --yesno "$msg" --yes-button "Accept & Install" --no-button "Skip" 12 72 && do_it=true
    else
        echo -e "$msg [y/N]:"
        read -r REPLY
        { [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; } && do_it=true
    fi
    if ! $do_it; then
        SKIPPED_PACKAGES+=("ubuntu-restricted-extras"); ((TOTAL_SKIPPED++))
        log INFO "Skipped ubuntu-restricted-extras (Microsoft fonts EULA not accepted)"
        return 0
    fi

    # Preseed the EULA acceptance so ttf-mscorefonts-installer doesn't block.
    echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | debconf-set-selections
    log INFO "Installing ubuntu-restricted-extras (non-interactive, EULA preseeded)..."
    if DEBIAN_FRONTEND=noninteractive pm_install ubuntu-restricted-extras || is_installed ubuntu-restricted-extras; then
        INSTALLED_PACKAGES+=("ubuntu-restricted-extras"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: ubuntu-restricted-extras"
    else
        FAILED_PACKAGES+=("ubuntu-restricted-extras"); ((TOTAL_FAILED++))
        log ERROR "Failed: ubuntu-restricted-extras"
    fi
}

# DVD decryption support (libdvdcss2). Not a normal .deb - this multiverse
# package's postinst downloads its source from videolan.org and compiles it
# locally the first time it's configured. Whether doing so is legal varies by
# jurisdiction (why it's not in main/universe), but it's the standard,
# widely-documented way Ubuntu desktops get DVD playback working, and is
# exactly the "am I missing an extra media plugin" gap this addresses.
# Preseed the debconf answer (verified directly from the package's own
# postinst script) so the build step runs unattended instead of blocking on
# a prompt; failure here is non-fatal since it typically means no network
# path to videolan.org.
install_libdvdcss() {
    if is_installed libdvd-pkg; then
        SKIPPED_PACKAGES+=("libdvd-pkg"); ((TOTAL_SKIPPED++))
        log INFO "Already installed: libdvd-pkg"
        return 0
    fi
    if ! package_exists libdvd-pkg; then
        FAILED_PACKAGES+=("libdvd-pkg"); ((TOTAL_FAILED++))
        log WARNING "Not in repos: libdvd-pkg"
        return 1
    fi
    echo "libdvd-pkg libdvd-pkg/build boolean true" | debconf-set-selections
    log INFO "Installing libdvd-pkg (builds libdvdcss2 from source - needs network access to videolan.org, may take a moment)..."
    if pm_install libdvd-pkg; then
        INSTALLED_PACKAGES+=("libdvd-pkg"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: libdvd-pkg (encrypted DVD playback support)"
    else
        FAILED_PACKAGES+=("libdvd-pkg"); ((TOTAL_FAILED++))
        log WARNING "libdvd-pkg failed - encrypted DVD playback won't work. Retry manually: sudo dpkg-reconfigure libdvd-pkg"
    fi
}

# ========== AUDIO ==========
install_audio() {
    # zynaddsubfx (a software synth) and xjadeo (a JACK video monitor) are
    # Ubuntu Studio audio staples that also get pulled in by the ubuntustudio-
    # audio metapackage. Listing them here explicitly means this standalone Audio
    # Production category installs them too - and, more to the point, that their
    # launchers get grouped into the Audio app folder. zynaddsubfx ships FOUR
    # real, displayable launchers (Alsa/Jack/Jack-multi/Oss), all of which the
    # resolver picks up. If they were already installed by a prior Ubuntu Studio
    # run they register as SKIPPED, which is still fed to the folder resolver.
    batch_install "Audio" \
        audacity ardour lmms musescore hydrogen zynaddsubfx \
        qjackctl jackd2 pulseaudio-module-jack ladspa-sdk calf-plugins xjadeo \
        soundconverter easytag flac lame opus-tools vorbis-tools wavpack sox libsox-fmt-all \
        pavucontrol
}

# ========== CODE EDITORS ==========
install_code_editors() {
    batch_install "Code Editors" vim neovim emacs nano geany gedit kate
    install_vscode; install_sublime_text
    configure_lazyvim
}

# Prompt to set up LazyVim (Neovim starter config) with the Nordic theme. It
# REPLACES ~/.config/nvim, so it's a prompted opt-in and backs up any existing
# config first. Prompted rather than automatic so a bulk (A/C) run can't silently
# clobber a user's Neovim setup.
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

# Install LazyVim (https://github.com/LazyVim/starter) as the Neovim config plus
# the Nordic theme (https://github.com/AlexvZyl/nordic.nvim). Runs as the target
# user; existing ~/.config/nvim is backed up. Plugins sync on first `nvim` launch.
install_lazyvim() {
    # Needs a real sudo-invoking user - without one, `eval echo ~` resolves to
    # /root and the later chown "$SUDO_USER:$SUDO_USER" becomes chown ":" (error).
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
    # Track the already-installed case like safe_install does (SKIPPED_PACKAGES),
    # not just a log line. create_menu_category only ever looks at
    # INSTALLED_PACKAGES + SKIPPED_PACKAGES to decide which apps get an icon in
    # the folder - if "code" never lands in either array, its icon is silently
    # never even attempted, regardless of how good the desktop-file resolver is.
    if command -v code &>/dev/null; then
        SKIPPED_PACKAGES+=("code"); ((TOTAL_SKIPPED++))
        log INFO "VS Code already installed"
        return 0
    fi
    log INFO "Installing VS Code..."
    # Dearmor the key STRAIGHT into the keyring - no predictable /tmp intermediate
    # (as root, `> /tmp/microsoft.gpg` follows a symlink and can overwrite an
    # arbitrary file). install -D creates the dir and sets mode 644; the key is
    # public, so 644 is correct. Same safe pattern as install_sublime_text.
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor \
        | install -D -m 644 /dev/stdin /usr/share/keyrings/microsoft.gpg 2>/dev/null
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/vscode stable main" > /etc/apt/sources.list.d/vscode.list
    apt-get update -qq 2>/dev/null
    safe_install code
    rm -f /etc/apt/sources.list.d/vscode.list
}

install_sublime_text() {
    # Same tracking fix as install_vscode above - see the comment there.
    if command -v sublime_text &>/dev/null; then
        SKIPPED_PACKAGES+=("sublime-text"); ((TOTAL_SKIPPED++))
        log INFO "Sublime Text already installed"
        return 0
    fi
    log INFO "Installing Sublime Text..."
    wget -qO- https://download.sublimetext.com/sublimehq-pub.gpg | gpg --dearmor | tee /usr/share/keyrings/sublime-text.gpg >/dev/null 2>&1
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/sublime-text.gpg] https://download.sublimetext.com/ apt/stable/" > /etc/apt/sources.list.d/sublime-text.list
    apt-get update -qq 2>/dev/null
    safe_install sublime-text
    # Keep BOTH the keyring and the .list (like install_spotify/install_dbeaver):
    # unlike VS Code, Sublime's package does NOT re-register its repo, so removing
    # either the key or the source would block future `apt upgrade` updates.
}

install_bruno() {
    # Bruno - open-source API client (Postman/Insomnia alternative), https://www.usebruno.com
    # Same tracking fix as install_vscode above - see the comment there.
    if command -v bruno &>/dev/null; then
        SKIPPED_PACKAGES+=("bruno"); ((TOTAL_SKIPPED++))
        log INFO "Bruno already installed"
        return 0
    fi
    log INFO "Installing Bruno..."
    # Official apt repo. The signing key lives on Ubuntu's keyserver (key id
    # 0x9FA6017ECABE0266), so fetch+dearmor it straight into the keyring - same
    # symlink-safe pattern as install_vscode. Keep the .gpg keyring in place so
    # future `apt upgrade` still trusts the repo (only the .list is removed).
    curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x9FA6017ECABE0266" | gpg --dearmor \
        | install -D -m 644 /dev/stdin /usr/share/keyrings/bruno.gpg 2>/dev/null
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/bruno.gpg] http://debian.usebruno.com/ bruno stable" > /etc/apt/sources.list.d/bruno.list
    apt-get update -qq 2>/dev/null
    safe_install bruno
    rm -f /etc/apt/sources.list.d/bruno.list
}

# ========== PYTHON ==========
install_python() {
    batch_install "Python" python3 python3-dev python3-venv python3-pip python-is-python3 ipython3 pipx
}

# ========== WEB DEVELOPMENT ==========
# Stop dpkg maintainer scripts from (re)starting apache2 during the web-server
# installs. Both apache2's own postinst and libapache2-mod-php's postinst try to
# (re)start apache2, which fails hard when nginx already holds :80 and dumps a
# systemd error mid-install. A policy-rc.d that returns 101 is the standard
# Debian mechanism to make invoke-rc.d a no-op; this one targets ONLY apache2 so
# other services (php-fpm) still start normally. It's removed again afterward,
# and only if we were the ones who created it (never clobbers a pre-existing one).
_block_apache_autostart() {
    if [ ! -e /usr/sbin/policy-rc.d ]; then
        printf '#!/bin/sh\ncase "$1" in apache2) exit 101 ;; esac\nexit 0\n' > /usr/sbin/policy-rc.d
        chmod +x /usr/sbin/policy-rc.d
        _POLICY_RC_ADDED=1
    fi
}
_unblock_apache_autostart() {
    [ -n "${_POLICY_RC_ADDED:-}" ] && rm -f /usr/sbin/policy-rc.d
    unset _POLICY_RC_ADDED
}

install_web_dev() {
    install_nodejs_full

    # nginx is the primary web server here - install it first and let it start
    # normally (it takes :80).
    batch_install "Web Server - Nginx" nginx

    # From here on, keep apache2 from being auto-started by any postinst.
    _block_apache_autostart

    # Apache2 is installed for availability but intentionally NOT run (nginx owns
    # :80). With autostart blocked it simply never starts, so - unlike before -
    # there's no failed apache2 unit left behind and no systemd error mid-install.
    log INFO "Installing Apache2 (kept available but not started - port 80 is nginx's)..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends apache2 2>/dev/null
    if is_installed apache2; then
        INSTALLED_PACKAGES+=("apache2"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: apache2 (not started - port 80 used by nginx)"
        systemctl stop apache2 2>/dev/null || true
    else
        FAILED_PACKAGES+=("apache2"); ((TOTAL_FAILED++))
        log ERROR "Failed: apache2"
    fi

    # PHP baseline for an nginx stack: php-fpm (the SAPI nginx talks to) + php-cli
    # (needed by composer) + composer. The bare "php" metapackage is deliberately
    # NOT listed: with apache2 present, its OR-dependency resolves to
    # libapache2-mod-php, whose postinst switches Apache's MPM and restarts it -
    # the exact :80 collision that was failing this step. php-fpm provides the
    # same language runtime without ever touching Apache.
    batch_install "Web Dev" php-cli php-fpm composer

    _unblock_apache_autostart
    # memcached/redis-server/sqlite3/sqlitebrowser intentionally NOT installed
    # here - none is required for a web server to function, and "Database
    # Tools" already owns them as its own category (per your call).
    # ruby/ruby-dev intentionally NOT installed here either - they're not
    # required by this stack and "Ruby Development" already owns them.
}

install_nodejs_full() {
    # Check if Node.js is already installed
    if command -v node &>/dev/null; then
        log INFO "Node.js already installed: $(node -v 2>/dev/null)"
        install_npm_packages
        return 0
    fi
    
    log INFO "Installing Node.js 20.x via NodeSource..."
    
    # Add NodeSource repository
    if ! grep -q nodesource /etc/apt/sources.list.d/* 2>/dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>/dev/null
        if [ $? -ne 0 ]; then
            log ERROR "Failed to add NodeSource repository"
            return 1
        fi
        apt-get update -qq 2>/dev/null
    fi
    
    # Install Node.js (npm is included with nodejs from NodeSource)
    safe_install nodejs
    
    # Verify installation
    if ! command -v node &>/dev/null; then
        log ERROR "Node.js installation failed"
        return 1
    fi
    
    if ! command -v npm &>/dev/null; then
        log ERROR "npm installation failed"
        return 1
    fi
    
    log SUCCESS "Node.js installed: $(node -v 2>/dev/null)"
    
    # Install global npm packages
    install_npm_packages
}

install_npm_packages() {
    # Check if npm is available
    if ! command -v npm &>/dev/null; then
        log WARNING "npm not available, skipping npm packages"
        return 1
    fi
    
    log INFO "Installing global npm packages..."
    
    # Verify npm works
    if ! npm --version &>/dev/null; then
        log ERROR "npm is not working properly"
        return 1
    fi
    
    # Ensure npm cache is clean
    npm cache clean --force 2>/dev/null || true
    
    local pkgs=(npm-check-updates nodemon pm2 webpack webpack-cli eslint prettier)
    local failed=0
    
    for p in "${pkgs[@]}"; do
        if npm list -g "$p" &>/dev/null; then
            log INFO "Already installed: $p"
            continue
        fi
        
        log INFO "Installing npm package: $p"
        
        # Try with retry logic
        local retries=3
        local success=0
        while [ $retries -gt 0 ]; do
            if npm install -g "$p" 2>&1; then
                success=1
                break
            fi
            ((retries--))
            sleep 2
        done
        
        if [ $success -eq 1 ]; then
            log SUCCESS "Installed: $p"
        else
            log WARNING "Failed after retries: $p"
            ((failed++))
        fi
    done
    
    if [ $failed -gt 0 ]; then
        log WARNING "$failed npm package(s) failed to install"
        log INFO "User can install manually: npm install -g <package>"
        return 1
    fi
    
    return 0
}

# ========== JAVA ==========
install_java() {
    # Only verified packages - hamcrest and mockito not in Ubuntu 26.10 repos
    batch_install "Java" default-jdk default-jre gradle maven ant junit4 testng
    local jh=$(update-alternatives --list java 2>/dev/null | head -n 1 | xargs dirname | xargs dirname)
    if [ -n "$jh" ]; then
        # /etc/environment is a plain NAME=value file (pam_env) - NOT a shell
        # script. Writing "export JAVA_HOME=..." here is invalid: anything that
        # reads the file (some dpkg maintainer scripts do, e.g. install-info's)
        # trips over the "export " prefix with "bad variable name", which then
        # fails EVERY later package that configures install-info. And $PATH /
        # $JAVA_HOME aren't expanded in this file, so the old PATH line was
        # broken too. Correct approach: a bare JAVA_HOME=... line here (system-
        # wide, idempotently rewritten), and a /etc/profile.d script - which IS
        # sourced as a shell and can expand - for the PATH addition. The sed
        # also cleans up any malformed lines a previous run left behind.
        sed -i -E '/^(export[[:space:]]+)?JAVA_HOME=/d; /^export[[:space:]]+PATH=.*JAVA_HOME/d' /etc/environment 2>/dev/null
        echo "JAVA_HOME=$jh" >> /etc/environment
        cat > /etc/profile.d/java-home.sh <<EOF
export JAVA_HOME="$jh"
export PATH="\$PATH:\$JAVA_HOME/bin"
EOF
        chmod 0644 /etc/profile.d/java-home.sh
    fi
    # No Java IDE exists in the Ubuntu archive at all (verified: eclipse,
    # intellij-idea-community, netbeans all return nothing from apt-cache
    # policy) - snap is the only real distribution channel for one.
    safe_snap_install intellij-idea-community --classic
}

# ========== C/C++ ==========
install_c_cpp() {
    batch_install "C/C++" \
        build-essential gcc g++ gfortran clang cmake make ninja-build ccache \
        autoconf automake libtool m4 bison flex gettext pkg-config \
        cppcheck valgrind gdb ltrace strace
}

# ========== GO ==========
install_go() {
    batch_install "Go" golang
    if ! command -v go &>/dev/null; then
        log INFO "Installing Go from source..."
        local t=$(mktemp -d) goarch
        # Map dpkg arch -> Go's release naming so this fallback isn't amd64-only.
        case "$(dpkg --print-architecture 2>/dev/null)" in
            amd64) goarch=amd64;; arm64) goarch=arm64;;
            armhf) goarch=armv6l;; i386) goarch=386;; *) goarch=amd64;;
        esac
        if curl -L -o "$t/go.tar.gz" "https://go.dev/dl/go1.22.5.linux-${goarch}.tar.gz" 2>/dev/null; then
            rm -rf /usr/local/go && tar -C /usr/local -xzf "$t/go.tar.gz" 2>/dev/null
            # Put Go on PATH via /etc/profile.d (a real shell script that IS
            # sourced and expands $PATH) - NOT via an "export ..." line in
            # /etc/environment, which is a pam_env NAME=value file, not a shell
            # script: an export line there breaks install-info's postinst with
            # "bad variable name" and then fails every later package (same bug the
            # Java path documents). Also strip any such broken line a previous
            # version of this script left behind, and update PATH for this run so
            # later steps (e.g. lazygit) find `go` immediately.
            sed -i '\|^export PATH=.*/usr/local/go/bin|d' /etc/environment 2>/dev/null
            echo 'export PATH="$PATH:/usr/local/go/bin"' > /etc/profile.d/go.sh
            chmod 0644 /etc/profile.d/go.sh
            export PATH="$PATH:/usr/local/go/bin"
            log SUCCESS "Go installed"
        else
            log WARNING "Go download failed"
        fi
        rm -rf "$t"
    fi
}

# ========== RUST ==========
install_rust() {
    batch_install "Rust" rustc cargo
    # rustup must be installed AS THE DESKTOP USER, not root - otherwise it lands
    # in /root/.cargo and the actual user gets nothing from this step. (The apt
    # rustc/cargo above are already system-wide.) Skip cleanly if there's no
    # sudo-invoking user (e.g. run as root directly).
    if [ -z "$SUDO_USER" ] || [ "$SUDO_USER" = "root" ]; then
        log INFO "No target user for rustup (run via sudo from a user session) - skipping rustup"
        return 0
    fi
    if su - "$SUDO_USER" -c 'command -v rustup' &>/dev/null; then
        log INFO "rustup already installed for $SUDO_USER"
        return 0
    fi
    log INFO "Installing rustup for $SUDO_USER..."
    if su - "$SUDO_USER" -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y" 2>/dev/null; then
        su - "$SUDO_USER" -c '. "$HOME/.cargo/env" 2>/dev/null; rustup default stable; rustup component add rust-src' 2>/dev/null
        log SUCCESS "Rust (rustup) installed for $SUDO_USER"
    else
        log WARNING "rustup installation may have failed"
    fi
}

# ========== NODE.JS ==========
install_nodejs_dev() { install_nodejs_full; }

# ========== PHP ==========
install_php() {
    # Using default Ubuntu PHP packages only (Ondrej PPA not available for 26.10 yet).
    # Note: the bare "php" metapackage is intentionally omitted - if apache2 is
    # already installed (e.g. from a prior Web Development / "EVERYTHING" run) its
    # OR-dependency pulls libapache2-mod-php, whose postinst restarts apache2 and
    # collides with nginx on :80. php-cli + php-fpm provide the runtime without
    # that. The apache-autostart block is also applied as a safety net in case a
    # transitive dependency still drags the module in.
    _block_apache_autostart
    batch_install "PHP" \
        php-cli php-fpm php-dev php-pear \
        php-mysql php-pgsql php-sqlite3 php-gd php-curl php-mbstring \
        php-xml php-zip composer
    _unblock_apache_autostart
}

# ========== RUBY ==========
install_ruby() { batch_install "Ruby" ruby ruby-dev ruby-bundler; }

# ========== .NET ==========
# Ubuntu ships the .NET SDK as dotnet-sdk-<major>.0 in its own repos, but which
# versions exist drifts by release. Install the newest one actually present
# rather than hardcoding a version that may have aged out. aspnetcore-runtime is
# added when available for web/API development. EF Core and other dotnet tools
# are per-user (`dotnet tool install -g`), left to the developer.
install_dotnet() {
    local v picked=""
    for v in dotnet-sdk-10.0 dotnet-sdk-9.0 dotnet-sdk-8.0; do
        if package_exists "$v"; then picked="$v"; break; fi
    done
    if [ -n "$picked" ]; then
        batch_install ".NET SDK" "$picked"
        # Matching ASP.NET Core runtime (same major as the SDK), if packaged.
        local major="${picked#dotnet-sdk-}"
        package_exists "aspnetcore-runtime-${major}" && batch_install ".NET ASP.NET Core" "aspnetcore-runtime-${major}"
    else
        FAILED_PACKAGES+=("dotnet-sdk"); ((TOTAL_FAILED++))
        log WARNING "No dotnet-sdk-* package found in repos - see https://learn.microsoft.com/dotnet/core/install/linux-ubuntu"
    fi
}

# ========== DATABASES ==========
install_databases() {
    batch_install "Databases" \
        mysql-server mysql-client postgresql \
        sqlite3 sqlitebrowser redis-server redis-tools memcached
    # sqlitebrowser above is the only DB GUI in the Ubuntu archive - no
    # MySQL/Postgres GUI exists there at all (verified: dbeaver-ce,
    # mysql-workbench, pgadmin4 all return nothing from apt-cache policy).
    # DBeaver covers MySQL/Postgres/SQLite in one tool.
    install_dbeaver
}

# DBeaver CE from its official apt repo (dbeaver.io/debs/dbeaver-ce) rather than
# snap, so it installs through the active front-end (Nala/apt) and updates via apt.
# It's a FLAT repo (note the trailing " /" in the deb line, no suite/component).
# Package dbeaver-ce (binary `dbeaver`, ships dbeaver-ce.desktop). Same keyring/.list
# convention as install_vscode; the .list is kept since the repo doesn't self-register.
install_dbeaver() {
    # Gate on the .deb specifically, not `command -v dbeaver` - a leftover DBeaver
    # snap also puts `dbeaver` on PATH and would make us wrongly skip the migration.
    if is_installed dbeaver-ce; then
        SKIPPED_PACKAGES+=("dbeaver-ce"); ((TOTAL_SKIPPED++)); log INFO "Already installed: dbeaver-ce"
        remove_snap_if_present dbeaver-ce; return 0
    fi
    log INFO "Installing DBeaver CE (official apt repo via $PM)..."
    wget -qO- https://dbeaver.io/debs/dbeaver.gpg.key | gpg --dearmor \
        | install -D -m 644 /dev/stdin /usr/share/keyrings/dbeaver.gpg 2>/dev/null
    echo "deb [signed-by=/usr/share/keyrings/dbeaver.gpg] https://dbeaver.io/debs/dbeaver-ce /" > /etc/apt/sources.list.d/dbeaver.list
    pm_update
    safe_install dbeaver-ce
    # Drop a superseded snap once the .deb is actually in place.
    is_installed dbeaver-ce && remove_snap_if_present dbeaver-ce
}

# ========== CONTAINERS ==========
install_containers() {
    # lxd has no apt/deb package on Ubuntu anymore - Canonical ships it as a snap
    # only. Leaving it in safe_install always logs a FAILED result, even on a
    # perfectly healthy system, so it's handled separately below.
    batch_install "Containers" docker.io docker-compose podman lxc
    if command -v docker &>/dev/null; then
        usermod -aG docker "$SUDO_USER" 2>/dev/null || true
        systemctl enable docker 2>/dev/null || true
        systemctl start docker 2>/dev/null || true
        log INFO "Docker configured"
    fi
    install_lxd_snap

    # This category has always been titled "Container & Virtualization" but
    # never actually installed anything for the "Virtualization" half.
    # KVM/QEMU + libvirt is the standard Linux virtualization stack;
    # virt-manager and GNOME Boxes are the two real, independent GUI
    # front-ends for it (virt-manager is the fuller-featured multi-VM
    # manager, Boxes is GNOME's simpler one-VM-at-a-time tool) - kept both
    # for the same "different UX, not a real duplicate" reason earlier
    # graphics-tool decisions did. virtinst/virt-viewer/spice-client-gtk are
    # what actually let virt-manager create a VM and show its graphical
    # console - without them it installs but can barely do anything.
    # qemu-kvm is NOT a real package on this Ubuntu version (checked) -
    # qemu-system-x86 is the one that actually exists, same class of stale
    # package-name mistake as the earlier ubuntustudio-* hyphen bug.
    batch_install "Virtualization (KVM/QEMU)" \
        qemu-system-x86 qemu-utils \
        libvirt-daemon-system libvirt-clients bridge-utils \
        virtinst virt-manager virt-viewer spice-client-gtk \
        gnome-boxes
    if command -v virsh &>/dev/null; then
        usermod -aG libvirt "$SUDO_USER" 2>/dev/null || true
        systemctl enable libvirtd 2>/dev/null || true
        systemctl start libvirtd 2>/dev/null || true
        log INFO "libvirtd configured"
    fi

    # Cockpit is a real, actively-maintained web GUI
    # (https://localhost:9090) that manages BOTH containers and VMs from one
    # dashboard - genuinely complementary to virt-manager/Boxes/docker CLI,
    # not a duplicate of any of them. cockpit-machines is its libvirt/VM
    # module, cockpit-podman its container module (podman is already
    # installed above). Checked: no maintained podman-desktop/docker-desktop
    # equivalent exists as a normal apt package in these repos - those only
    # ship as Flatpak/vendor .deb, out of scope for safe_install. Cockpit's
    # own packages ship NO .desktop file at all (it's browser-based, not a
    # GUI app) - the "Desktop file not found: cockpit[-machines/-podman]"
    # warnings this produces are expected, same as docker/podman/adb.
    batch_install "Cockpit (Web GUI)" cockpit cockpit-machines cockpit-podman
    if is_installed cockpit; then
        systemctl enable cockpit.socket 2>/dev/null || true
        systemctl start cockpit.socket 2>/dev/null || true
        log INFO "Cockpit enabled - manage containers/VMs at https://localhost:9090"
    fi
}

# Generic snap installer with proper tracking, reused by every snap-only
# package in this script (lxd, and now the Java IDE / DB GUI client below) -
# one implementation instead of three near-identical copies.
# Usage: safe_snap_install <snap-name> [extra snap-install args, e.g. --classic]
safe_snap_install() {
    local snap_name="$1"; shift
    local snap_args=("$@")
    if command -v "$snap_name" &>/dev/null || snap list "$snap_name" &>/dev/null 2>&1; then
        SKIPPED_PACKAGES+=("$snap_name"); ((TOTAL_SKIPPED++))
        log INFO "Already installed: $snap_name (snap)"
        return 0
    fi
    if ! command -v snap &>/dev/null; then
        FAILED_PACKAGES+=("$snap_name"); ((TOTAL_FAILED++))
        log WARNING "snapd not available - install manually: sudo snap install $snap_name ${snap_args[*]}"
        return 1
    fi
    log INFO "Installing $snap_name via snap..."
    if snap install "$snap_name" "${snap_args[@]}" 2>/dev/null; then
        INSTALLED_PACKAGES+=("$snap_name"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: $snap_name (snap)"
        return 0
    else
        FAILED_PACKAGES+=("$snap_name"); ((TOTAL_FAILED++))
        log ERROR "Failed: $snap_name (snap)"
        return 1
    fi
}

install_lxd_snap() { safe_snap_install lxd; }

# Remove a snap that a .deb has just superseded, so the user isn't left running two
# copies of the same app (Slack/Spotify/DBeaver migrated from snap to .deb). No-op
# when snap/snapd is absent or that snap was never installed. Called only once the
# .deb is confirmed installed, so the app stays available throughout.
remove_snap_if_present() {
    local snap_name="$1"
    command -v snap &>/dev/null || return 0
    snap list "$snap_name" &>/dev/null 2>&1 || return 0
    log INFO "Removing superseded snap '$snap_name' (replaced by .deb)..."
    if snap remove "$snap_name" 2>/dev/null; then
        log SUCCESS "Removed snap: $snap_name"
    else
        log WARNING "Could not remove snap '$snap_name' - remove manually: sudo snap remove $snap_name"
    fi
}

# ========== GAMING ==========
install_gaming() {
    # Add 32-bit architecture for Steam and Wine compatibility
    if ! dpkg --print-foreign-architectures 2>/dev/null | grep -q i386; then
        dpkg --add-architecture i386 2>/dev/null || true
        apt-get update -qq 2>/dev/null || true
    fi
    
    # obs-studio/mpv/vlc intentionally NOT installed here - none of them are a
    # dependency of steam or lutris (checked: apt-cache depends lists neither),
    # and "Video Creation & Editing" already owns them as its own category.
    batch_install "Gaming" steam lutris gamemode mangohud
    # 32-bit GL for Steam/Wine titles. The old libgl1-mesa-glx name was dropped on
    # current Ubuntu; libgl1 is the maintained replacement.
    safe_install libgl1:i386
}

install_windows_support() {
    log INFO "Installing Windows software support..."
    
    # Add 32-bit architecture for Wine
    if ! dpkg --print-foreign-architectures 2>/dev/null | grep -q i386; then
        dpkg --add-architecture i386 2>/dev/null || true
        apt-get update -qq 2>/dev/null || true
    fi
    
    # Install Wine and related tools (verified packages only).
    # lutris intentionally NOT installed here - it's not an apt dependency of
    # wine/winetricks (checked: apt-cache depends lutris lists neither), and
    # "Gaming" already owns it as its own category.
    # zenity is included so winetricks' GUI works (it needs zenity/kdialog to
    # draw its dialogs when launched with no arguments).
    batch_install "Wine Environment" \
        wine \
        winetricks \
        zenity

    # The Ubuntu winetricks package ships as a CLI script with NO .desktop
    # launcher, so it never gets a menu icon and never lands in the app folder
    # (the resolver can only place apps that have a launcher - same reason
    # adb/docker don't). But winetricks DOES have a GUI when run with no args, so
    # give it a launcher if one doesn't already exist. Written to the standard
    # path (winetricks.desktop) with NoDisplay unset, so create_menu_category's
    # resolver finds it (its empty-prefix fallback matches this exact filename)
    # and includes it in the Windows Software Support folder.
    if is_installed winetricks && ! compgen -G "/usr/share/applications/*winetricks*.desktop" >/dev/null 2>&1; then
        cat > /usr/share/applications/winetricks.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Winetricks
GenericName=Wine Helper
Comment=Install and configure Windows components and apps under Wine
Exec=winetricks
Icon=wine
Terminal=false
Categories=Utility;System;Wine;
Keywords=wine;windows;dll;
EOF
        chmod 644 /usr/share/applications/winetricks.desktop
        log SUCCESS "Created menu launcher for winetricks (package ships none)"
    fi

    # Install core dependencies for Wine (verified to exist)
    # Note: libgl1-mesa-glx not in Ubuntu 26.10, let wine pull its own deps
    batch_install "Wine Dependencies" \
        libasound2-plugins \
        libsdl2-2.0-0 \
        libfreetype6 \
        libx11-6 \
        libxext6
    
    # Configure Wine
    if command -v wine &>/dev/null; then
        log INFO "Configuring Wine..."
        # Set up Wine prefix. The prefix is created in the DESKTOP USER's home (the
        # wineboot runs via `su - $SUDO_USER`), so the guard must test THAT home -
        # not root's $HOME, which would always be missing and defeat the check.
        local uwine; uwine="$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)/.wine"
        if [ ! -d "$uwine" ]; then
            su - "$SUDO_USER" -c "wine wineboot --init" 2>/dev/null || true
            log INFO "Wine prefix initialized"
        fi
        
        # Install corefonts via winetricks
        su - "$SUDO_USER" -c "winetricks -q corefonts" 2>/dev/null || true
        log INFO "Wine configuration complete"
    fi
    
    log SUCCESS "Windows software support installed"
}

# ========== OFFICE ==========
install_office() {
    batch_install "Office" libreoffice okular evince zathura pandoc
}

# ========== SYSTEM UTILITIES ==========
install_system_utils() {
    batch_install "System Utils" \
        htop iotop nmon sysstat dstat glances \
        nethogs iftop nload vnstat tcpdump wireshark \
        lsof strace ltrace valgrind gdb \
        tmux screen byobu zsh fish fzf ripgrep tree ncdu rsync unzip bat
    # NOTE: the apt package "bat" installs its binary as /usr/bin/batcat, not
    # /usr/bin/bat, due to an unrelated Debian package name collision. Users
    # typing "bat" after this will get "command not found" unless they alias
    # it or use "batcat" directly.
}

# ========== GENERAL DEV TOOLS ==========
install_dev_tools() {
    # git intentionally NOT re-listed here - install_base already installs it
    # (this script itself needs git for install_chris_titus_mybash's clone step,
    # so it's a genuine shared dependency, not a convenience duplicate).
    # make/cmake/autoconf/automake/bison/flex/gettext/pkg-config are intentionally
    # left overlapping with install_c_cpp - kept by request as shared
    # foundational tooling any developer may want regardless of category.
    batch_install "Dev Tools" \
        jq tig subversion make cmake \
        autoconf automake bison flex gettext pkg-config manpages less
    # Bruno API client - installed from its own apt repo, so it can't ride the
    # batch_install list above; call its dedicated installer like install_ai_tools does.
    install_bruno
}

# ========== AI TOOLS ==========
install_ai_tools() {
    log INFO "Installing AI Tools..."
    install_ollama
    install_alpaca
    install_claude_code
    install_gemini_cli
    install_cursor
}

# NOTE on tracking: these tools install outside apt (curl script, npm/native
# installer, direct .deb/AppImage), so they must update the tracking arrays
# THEMSELVES - nothing else does it for them. Without this they never appeared in
# the summary and, more visibly, never got fed to the AI Tools app-folder
# resolver, so the folder came up empty even when Cursor (a real GUI app) had
# installed fine. Each now records installed/skipped/failed. ollama and claude
# are CLI-only (no launcher, so no folder icon - expected, like docker/adb);
# Cursor ships its own cursor.desktop (or a hand-written one for the AppImage).
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

# Alpaca (com.jeffser.Alpaca) - a native GTK4/libadwaita graphical CLIENT for
# Ollama, replacing the buggy JHubi1 Flutter app. Ollama ships NO official desktop
# app on Linux (its GUI is macOS/Windows only); Alpaca is the standout GNOME-native
# client, actively maintained and distributed on Flathub. It talks to the Ollama
# server install_ollama sets up (and can manage its own). Installed system-wide as
# a Flatpak, same tooling the Windows App installer uses. Tracking name "Alpaca".
#
# NOTE: Flatpak apps export their launcher under /var/lib/flatpak/exports (per-user
# ones under ~/.local/share/flatpak/exports). create_menu_category's resolver now
# scans both and matches on the launcher's Name=, so Alpaca (installed system-wide
# here) DOES get grouped into the AI Tools app-folder.
install_alpaca() { flatpak_install_flathub com.jeffser.Alpaca "Alpaca"; }

install_claude_code() {
    # Claude Code CLI. The primary path is Anthropic's official native installer
    # (https://claude.ai/install.sh), which needs NO Node/npm - important because
    # this machine can have `node` without `npm`, which is exactly what made the
    # old npm-only install fail. Run it as the desktop user so `claude` lands in
    # their ~/.local/bin (not root's). The npm global package stays as a fallback
    # for when npm is present. Tracking name stays "claude" (the command it adds).
    local u="$SUDO_USER"; [ "$u" = "root" ] && u=""

    # Build user-scoped vs root-scoped check/install commands once.
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
    # Fallback: official npm global package (only works if npm is on PATH).
    if command -v npm &>/dev/null && npm install -g @anthropic-ai/claude-code 2>/dev/null && command -v claude &>/dev/null; then
        INSTALLED_PACKAGES+=("claude"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: claude (npm)"; return 0
    fi
    FAILED_PACKAGES+=("claude"); ((TOTAL_FAILED++))
    log WARNING "Claude Code install failed - try: curl -fsSL https://claude.ai/install.sh | bash"; return 0
}

install_gemini_cli() {
    # Google's official Gemini CLI (https://github.com/google-gemini/gemini-cli),
    # the closest thing to an official Gemini app on Linux. Distributed via npm as
    # @google/gemini-cli; needs Node 18+. CLI-only (no launcher/folder icon, like
    # ollama/claude). Tracking name stays "gemini" (the command it adds).
    if command -v gemini &>/dev/null; then
        SKIPPED_PACKAGES+=("gemini"); ((TOTAL_SKIPPED++)); log INFO "Already installed: gemini"; return 0
    fi
    # npm is required for the global install. Unlike Claude Code, Gemini CLI has no
    # standalone native installer, so if npm is absent we can't proceed. On Ubuntu
    # the apt `nodejs` package ships WITHOUT npm (npm is a separate package), so a
    # machine can easily have `node` but no `npm` - self-heal by pulling npm through
    # the active front-end before giving up. apt's npm depends on the matching
    # node-* packages, so it's conflict-free with an apt-provided nodejs.
    if ! command -v npm &>/dev/null; then
        log INFO "npm not found - installing it (required by Gemini CLI)..."
        pm_install npm >/dev/null 2>&1 || true
    fi
    if ! command -v npm &>/dev/null; then
        FAILED_PACKAGES+=("gemini"); ((TOTAL_FAILED++))
        log WARNING "Gemini CLI needs npm (Node 18+) and npm could not be installed - install it, then: npm install -g @google/gemini-cli"; return 0
    fi
    log INFO "Installing Gemini CLI..."
    if npm install -g @google/gemini-cli 2>/dev/null && command -v gemini &>/dev/null; then
        INSTALLED_PACKAGES+=("gemini"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: gemini (run 'gemini' to sign in)"; return 0
    fi
    FAILED_PACKAGES+=("gemini"); ((TOTAL_FAILED++))
    log WARNING "Gemini CLI install failed - try: npm install -g @google/gemini-cli"; return 0
}

install_cursor() {
    if command -v cursor &>/dev/null || is_installed cursor; then
        SKIPPED_PACKAGES+=("cursor"); ((TOTAL_SKIPPED++)); log INFO "Already installed: cursor"; return 0
    fi
    log INFO "Installing Cursor..."
    # Cursor no longer serves the old download.cursor.com/linux/deb/* paths (they
    # are now unreachable). The current build URLs come from its download API,
    # which returns per-arch .deb + AppImage links at downloads.cursor.com. Query
    # it, prefer the .deb (real package + menu entry), fall back to the AppImage.
    local t=$(mktemp -d) a=$(dpkg --print-architecture) plat
    case "$a" in amd64) plat="linux-x64";; arm64) plat="linux-arm64";; *) plat="linux-x64";; esac
    local json deb_url app_url
    json=$(curl -fsSL "https://www.cursor.com/api/download?platform=${plat}&releaseTrack=stable" 2>/dev/null)
    deb_url=$(printf '%s' "$json" | grep -oP '"debUrl":\s*"\K[^"]+')
    app_url=$(printf '%s' "$json" | grep -oP '"downloadUrl":\s*"\K[^"]+')

    # 1) .deb - gives a proper package and a .desktop launcher via dpkg.
    if [ -n "$deb_url" ] && { curl -L -f --retry 2 -o "$t/cursor.deb" "$deb_url" 2>/dev/null || wget -q --tries=2 -O "$t/cursor.deb" "$deb_url" 2>/dev/null; }; then
        dpkg -i "$t/cursor.deb" 2>/dev/null || { apt-get install -f -y 2>/dev/null; dpkg -i "$t/cursor.deb" 2>/dev/null; }
        if command -v cursor &>/dev/null || is_installed cursor; then
            rm -rf "$t"; INSTALLED_PACKAGES+=("cursor"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: cursor (.deb)"; return 0
        fi
    fi

    # 2) AppImage fallback - drop it in /usr/local/bin and hand-write a launcher
    #    (a bare AppImage ships no .desktop of its own).
    if [ -n "$app_url" ] && { curl -L -f --retry 2 -o "$t/cursor.AppImage" "$app_url" 2>/dev/null || wget -q --tries=2 -O "$t/cursor.AppImage" "$app_url" 2>/dev/null; }; then
        chmod +x "$t/cursor.AppImage"; mv "$t/cursor.AppImage" /usr/local/bin/cursor
        cat > /usr/share/applications/cursor.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Cursor
GenericName=AI Code Editor
Comment=The AI-first code editor
Exec=cursor %F
Icon=text-editor
Terminal=false
Categories=Development;IDE;TextEditor;
EOF
        chmod 644 /usr/share/applications/cursor.desktop
        rm -rf "$t"
        INSTALLED_PACKAGES+=("cursor"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: cursor (AppImage, /usr/local/bin/cursor)"; return 0
    fi

    rm -rf "$t"
    FAILED_PACKAGES+=("cursor"); ((TOTAL_FAILED++))
    log WARNING "Cursor download failed - get it from https://www.cursor.com/"; return 0
}

# ========== GUI TWEAKS ==========
# Point the terminal (and the desktop's monospace font generally) at an installed
# Nerd Font, run as the logged-in user against their live D-Bus session.
#
# This is what Chris Titus mybash's setup.sh tries to do, but that write targets
# GNOME Terminal's own keys and runs as root with no session bus - so on GNOME's
# newer default terminal (Ptyxis, shipped on Ubuntu 26.04+) and under sudo it
# silently no-ops (this is the "dbus-launch: No such file or directory" path).
#
# org.gnome.desktop.interface monospace-font-name is the authoritative lever:
# GNOME Console and a default Ptyxis both follow it, as do GNOME apps and
# gnome-tweaks. Ptyxis is additionally pinned to "use system font" so it honors
# it even if that was toggled off, avoiding a guess at Ptyxis's per-profile font
# key. gnome-terminal (only if the user installed it) uses its own per-profile
# 'font' key and is handled explicitly. Every write is guarded, so this is a safe
# no-op on whichever terminals/keys aren't present.
# Usage: set_terminal_font ["Font Family"] [size]
set_terminal_font() {
    local font_family="${1:-JetBrainsMono Nerd Font}" size="${2:-12}"
    local font_spec="${font_family} ${size}"

    # Don't point the desktop at a font that isn't actually installed.
    if command -v fc-list &>/dev/null && ! fc-list | grep -qi "$font_family"; then
        log WARNING "Font '$font_family' not found (fc-list) - skipping terminal font setup"
        return 1
    fi

    local user uid
    read -r user uid < <(resolve_desktop_session) || return 1

    local ok=1
    # 1) System monospace font - covers GNOME Console, a default Ptyxis, and apps.
    if gset_if_exists "$user" "$uid" org.gnome.desktop.interface monospace-font-name "$font_spec"; then
        log SUCCESS "System monospace font set to '$font_spec'"
        ok=0
    else
        log WARNING "Could not set system monospace font (org.gnome.desktop.interface)"
    fi

    # 2) Ptyxis: ensure it follows the system font we just set (no-op if absent).
    if gset_if_exists "$user" "$uid" org.gnome.Ptyxis use-system-font true; then
        log INFO "Ptyxis set to use the system monospace font"
        ok=0
    fi

    # 3) gnome-terminal (only if installed): per-profile 'font' key + opt out of
    #    its system-font default so the custom font applies.
    local profile
    profile=$(gsettings_as_user "$user" "$uid" get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'")
    if [ -n "$profile" ]; then
        local path="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${profile}/"
        if gsettings_as_user "$user" "$uid" set "$path" use-system-font false 2>/dev/null \
           && gsettings_as_user "$user" "$uid" set "$path" font "$font_spec" 2>/dev/null; then
            log INFO "gnome-terminal default profile font set to '$font_spec'"
            ok=0
        fi
    fi

    if [ $ok -eq 0 ]; then
        log SUCCESS "Terminal font configured - takes effect immediately in open terminals"
        return 0
    fi
    log WARNING "Terminal font not set on any known terminal"
    return 1
}

# Prompt (whiptail, or plain read as fallback) before changing the user's font,
# mirroring prompt_menu_category's style. Skipped cleanly with no prompt when
# there's no desktop session to write to.
configure_terminal_font() {
    local font_family="JetBrainsMono Nerd Font"
    # No live session -> nothing we could set; say why once and move on.
    if ! resolve_desktop_session >/dev/null 2>&1; then
        log INFO "Skipping terminal font (no active desktop session detected)"
        return 0
    fi
    if command -v fc-list &>/dev/null && ! fc-list | grep -qi "$font_family"; then
        log INFO "Skipping terminal font ('$font_family' not installed)"
        return 0
    fi
    local do_it=false
    if command -v whiptail &>/dev/null; then
        whiptail --yesno "Set the terminal / system monospace font to '$font_family'?" --yes-button "Yes" --no-button "No" 10 60 && do_it=true
    else
        echo "Set the terminal / system monospace font to '$font_family'? [y/N]:"
        read -r REPLY
        [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ] && do_it=true
    fi
    if $do_it; then
        set_terminal_font "$font_family" 12
    else
        echo "  Skipped terminal font."
    fi
}

install_gui_tweaks() {
    log INFO "Installing GUI Tweaks..."
    install_icon_sets
    install_themes
    install_cursor_themes
    install_nerd_fonts
    configure_terminal_font
    install_chris_titus_mybash
    install_gui_tools
    install_gnome_extensions
    configure_logiops
}

# Install a curated set of GNOME Shell extensions via gext (the gnome-extensions-cli
# tool), set up per-user with pipx. Runs entirely as the logged-in desktop user
# (extensions are per-user and enabling them needs their session), and needs an
# active GNOME session - skipped cleanly otherwise. Best-effort: a failed
# extension is logged and skipped, not fatal. Some need a session reload (log
# out/in) to actually activate.
install_gnome_extensions() {
    local user uid
    if ! read -r user uid < <(resolve_desktop_session); then
        log INFO "No active desktop session - skipping GNOME extensions"; return 0
    fi
    command -v pipx &>/dev/null || safe_install pipx
    log INFO "Setting up gext (GNOME Extension Manager CLI) via pipx..."
    su - "$user" -c 'command -v gext >/dev/null 2>&1 || pipx install gnome-extensions-cli --system-site-packages' 2>/dev/null
    local exts=(
        "gsconnect@andyholmes.github.io"                               # GSConnect
        "window-state-manager@kishorv06.github.io"                     # Window State Manager
        "Bluetooth-Battery-Meter@maniacx.github.com"                   # Bluetooth Battery Meter
        "auto-move-windows@gnome-shell-extensions.gcampax.github.com"  # Auto Move Windows
        "user-theme@gnome-shell-extensions.gcampax.github.com"         # User Themes (ego 19)
        "clipboard-history@alexsaveau.dev"                             # Clipboard History (ego 4839)
    )
    local e ok=0
    for e in "${exts[@]}"; do
        if su - "$user" -c "PATH=\"\$HOME/.local/bin:\$PATH\" gext install '$e'" 2>/dev/null; then
            log INFO "Installed extension: $e"; ((ok++))
        else
            log WARNING "Failed extension (skipped): $e"
        fi
    done
    log INFO "GNOME extensions: $ok/${#exts[@]} installed - log out/in to activate"
}

# Prompt to build + install Logiops (the Logitech HID++ driver, https://github.com/
# PixlOne/logiops) from source. Prompted opt-in because it only matters for
# Logitech input devices and it compiles from source (pulls a build toolchain).
configure_logiops() {
    local msg="Build and install Logiops (Logitech HID++ driver) from source?\n\nOnly needed for configurable Logitech mice/keyboards. It pulls a build toolchain, compiles from source, and enables the 'logid' service."
    local do_it=false
    if command -v whiptail &>/dev/null; then
        whiptail --yesno "$msg" --yes-button "Build & install" --no-button "Skip" 12 72 && do_it=true
    else
        echo -e "$msg [y/N]:"
        read -r REPLY
        { [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; } && do_it=true
    fi
    if $do_it; then install_logiops; else log INFO "Skipped Logiops"; fi
}

install_logiops() {
    batch_install "Logiops Build Deps" \
        cmake pkg-config libevdev-dev libudev-dev libconfig++-dev libglib2.0-dev
    # Build in a FRESH private temp dir (mktemp -d is mode 700, root-owned), not a
    # predictable, reused /tmp/logiops. A fixed path that's cloned only "if it
    # doesn't already exist" lets a local attacker pre-plant a malicious source
    # tree that then gets built and `make install`ed AS ROOT. Always clone fresh;
    # remove the tree afterward.
    local d; d=$(mktemp -d) || { log WARNING "logiops: mktemp failed"; return 1; }
    if ! git clone --depth 1 https://github.com/PixlOne/logiops.git "$d/src" 2>/dev/null; then
        log WARNING "logiops clone failed"; rm -rf "$d"; return 1
    fi
    local rc=0
    if ( cd "$d/src" && mkdir -p build && cd build && cmake .. 2>/dev/null && make 2>/dev/null && make install 2>/dev/null ); then
        write_logid_config
        systemctl enable --now logid 2>/dev/null || true
        systemctl restart logid 2>/dev/null || true
        log SUCCESS "Logiops installed and logid service enabled"
    else
        log WARNING "logiops build/install failed"; rc=1
    fi
    rm -rf "$d"
    return $rc
}

# Write a working /etc/logid.cfg (Logitech MX Master 3 / MX Master: gestures,
# smartshift, hi-res scroll, DPI). Embedded here - via a single-quoted heredoc so
# nothing is shell-expanded - so the script stays self-contained (no dependency
# on a sibling files/ directory when run standalone). Any existing config is
# backed up first. Edit the mappings below to taste; keys reference:
# https://github.com/torvalds/linux/blob/master/include/uapi/linux/input-event-codes.h
write_logid_config() {
    [ -f /etc/logid.cfg ] && cp /etc/logid.cfg "/etc/logid.cfg.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null \
        && log INFO "Backed up existing /etc/logid.cfg"
    cat > /etc/logid.cfg <<'LOGID_EOF'
// Logiops (Linux driver) configuration for Logitech MX Master 3.
// Includes gestures, smartshift, DPI.
// Tested on logid v0.2.3 - GNOME 3.38.4 on Zorin OS 16 Pro
// What's working:
//   1. Window snapping using Gesture button (Thumb)
//   2. Forward Back Buttons
//   3. Top button (Ratchet-Free wheel)
// What's not working:
//   1. Thumb scroll (H-scroll)
//   2. Scroll button

// File location: /etc/logid.cfg
//
// https://github.com/PixlOne/logiops
// Keys: https://github.com/torvalds/linux/blob/master/include/uapi/linux/input-event-codes.h

devices: (
{
    name: "Wireless Mouse MX Master 3";
    smartshift:
    {
        on: true;
        threshold: 20;
    };
    hiresscroll:
    {
        hires: true;
        invert: false;
        target: false;
        up: {
            mode: "Axis";
            axis: "REL_WHEEL_HI_RES";
            axis_multiplier: 3;
        },
        down: {
            mode: "Axis";
            axis: "REL_WHEEL_HI_RES";
            axis_multiplier: -3;
        },
    };
    dpi: 1100;

    buttons: (
        {
            cid: 0xc3;
            action =
            {
                type: "Gestures";
                gestures: (
                    {
                        direction: "Up";
                        mode: "OnRelease";
                        action =
                        {
                            type: "Keypress";
                            keys: ["KEY_LEFTCTRL", "KEY_LEFTMETA", "KEY_UP"];
                        };
                    },
                    {
                        direction: "Down";
                        mode: "OnRelease";
                        action =
                        {
                            type: "Keypress";
                            keys: ["KEY_LEFTCTRL", "KEY_LEFTMETA", "KEY_DOWN"];
                        };
                    },
                    {
                        direction: "Left";
                        mode: "OnRelease";
                        action =
                        {
                            type: "Keypress";
                            keys: ["KEY_PREVIOUSSONG"]
                        };
                    },
                    {
                        direction: "Right";
                        mode: "OnRelease";
                        action =
                        {
                            type: "Keypress";
                            keys: ["KEY_NEXTSONG"]
                        }
                    },
                    {
                        direction: "None";
                        mode: "OnRelease";
                        action =
                        {
                            type: "Keypress";
                            keys: ["KEY_PLAYPAUSE"]
                        }
                    }
                );
            };
        },
        {
            cid: 0x53;
            action =
            {
              type: "Keypress";
              keys: ["KEY_LEFTALT", "KEY_LEFT"]
            };
        },
        {
            cid: 0x56;
            action =
            {
              type: "Keypress";
              keys: ["KEY_LEFTALT", "KEY_RIGHT"]
            };
        },
        {
            cid: 0xc4;
            action =
            {
                type = "ToggleSmartshift";
            };
        }
    );
},
{
    name: "Wireless Mouse MX Master";
    smartshift:
    {
        on: true;
        threshold: 20;
    };
    hiresscroll:
    {
        hires: true;
        invert: false;
        target: false;
        up: {
            mode: "Axis";
            axis: "REL_WHEEL_HI_RES";
            axis_multiplier: 3;
        },
        down: {
            mode: "Axis";
            axis: "REL_WHEEL_HI_RES";
            axis_multiplier: -3;
        },
    };
    dpi: 1000;

    buttons: (
        {
            cid: 0xc3;
            action =
            {
                type: "Gestures";
                gestures: (
                    {
                        direction: "Up";
                        mode: "OnRelease";
                        action =
                        {
                            type: "Keypress";
                            keys: ["KEY_LEFTCTRL", "KEY_LEFTMETA", "KEY_UP"];
                        };
                    },
                    {
                        direction: "Down";
                        mode: "OnRelease";
                        action =
                        {
                            type: "Keypress";
                            keys: ["KEY_LEFTCTRL", "KEY_LEFTMETA", "KEY_DOWN"];
                        };
                    },
                    {
                        direction: "Left";
                        mode: "OnRelease";
                        action =
                        {
                            type: "Keypress";
                            keys: ["KEY_PREVIOUSSONG"]
                        };
                    },
                    {
                        direction: "Right";
                        mode: "OnRelease";
                        action =
                        {
                            type: "Keypress";
                            keys: ["KEY_NEXTSONG"]
                        }
                    },
                    {
                        direction: "None";
                        mode: "OnRelease";
                        action =
                        {
                            type: "Keypress";
                            keys: ["KEY_PLAYPAUSE"]
                        }
                    }
                );
            };
        },
        {
            cid: 0x53;
            action =
            {
              type: "Keypress";
              keys: ["KEY_LEFTALT", "KEY_LEFT"]
            };
        },
        {
            cid: 0x56;
            action =
            {
              type: "Keypress";
              keys: ["KEY_LEFTALT", "KEY_RIGHT"]
            };
        },
        {
            cid: 0xc4;
            action =
            {
                type = "ToggleSmartshift";
            };
        }
    );
}
);
LOGID_EOF
    log INFO "Wrote /etc/logid.cfg (MX Master 3 / MX Master mappings)"
}

# Add a PPA in a way that works cleanly across both supported releases. PPAs
# are keyed by codename: the 26.04 LTS (a stable, released codename) almost
# always has a build, while a brand-new interim release frequently has none yet.
#
# Crucial gotcha: on current Ubuntu `add-apt-repository -y` SUCCEEDS (exit 0) and
# writes the .sources file even when the PPA has no build for this codename - the
# failure only surfaces later as a 404 at `apt-get update` ("does not have a
# Release file"), and the broken source then breaks EVERY subsequent apt run.
# So for a ppa:owner/name we HEAD the Release file for this exact codename up
# front and, if it's missing, remove any stale source a prior run left behind and
# degrade to distro packages instead of committing a repo that only 404s.
# Usage: add_ppa ppa:owner/name  grep-tag-identifying-the-source
add_ppa() {
    local ppa="$1" tag="$2"

    # Pre-flight probe for ppa: specs (the only form used here). Launchpad serves
    # PPAs at ppa.launchpadcontent.net/<owner>/<name>/ubuntu, so the per-codename
    # Release lives at dists/<codename>/Release - exactly the URL apt would 404 on.
    if [[ "$ppa" == ppa:* && -n "$UBUNTU_CODENAME" ]] && command -v curl &>/dev/null; then
        local spec="${ppa#ppa:}"
        local url="https://ppa.launchpadcontent.net/${spec}/ubuntu/dists/${UBUNTU_CODENAME}/Release"
        if ! curl -fsSL -o /dev/null "$url" 2>/dev/null; then
            # No build for this codename. Remove any stale source/list a previous
            # run wrote for this PPA so it stops breaking apt, then degrade.
            local owner="${spec%%/*}" name="${spec#*/}"
            rm -f /etc/apt/sources.list.d/*"${owner}"*"${name}"*.sources \
                  /etc/apt/sources.list.d/*"${owner}"*"${name}"*.list 2>/dev/null
            apt-get update -qq 2>/dev/null || true
            log WARNING "$ppa has no build for ${UBUNTU_CODENAME} - continuing with distro packages"
            return 1
        fi
    fi

    grep -rq "$tag" /etc/apt/sources.list.d/ 2>/dev/null && return 0
    if add-apt-repository -y "$ppa" 2>/dev/null; then
        apt-get update -qq 2>/dev/null || true
        return 0
    fi
    log WARNING "$ppa not available for ${UBUNTU_CODENAME:-this release} - continuing with distro packages"
    return 1
}

install_icon_sets() {
    # Add Papirus Team PPA for additional icon themes (codename-aware; see add_ppa)
    add_ppa ppa:papirus/papirus papirus
    batch_install "Icon Sets" \
        papirus-icon-theme \
        numix-icon-theme \
        breeze-icon-theme \
        adwaita-icon-theme
}

install_themes() {
    batch_install "Themes" arc-theme
}

install_cursor_themes() {
    batch_install "Cursor Themes" dmz-cursor-theme breeze-cursor-theme
}

install_nerd_fonts() {
    log INFO "Installing Nerd Fonts..."
    mkdir -p /usr/share/fonts/truetype/nerd-fonts
    batch_install "Nerd Fonts (APT)" fonts-firacode fonts-jetbrains-mono
    local t=$(mktemp -d) c=0 f=0
    local fonts=(FiraCode JetBrainsMono Hack SourceCodePro CascadiaCode UbuntuMono DejaVuSansMono)
    # destflag differs by tool: tar uses -C for the output dir, unzip uses -d.
    # (An earlier version hardcoded -C for both, so the unzip fallback extracted
    # into the CWD and every font came up empty.)
    local ext="tar.xz" ecmd="tar -xf" destflag="-C"
    if ! command -v tar &>/dev/null || ! tar --help 2>/dev/null | grep -q xz; then
        command -v unzip &>/dev/null && { ext="zip"; ecmd="unzip -qq -o"; destflag="-d"; } || safe_install tar xz-utils 2>/dev/null || true
    fi
    log INFO "Downloading popular Nerd Fonts (format: ${ext})..."
    for font in "${fonts[@]}"; do
        local af="$t/${font}.${ext}" ed="$t/${font}"
        mkdir -p "$ed"
        local d=0
        command -v curl &>/dev/null && curl -L -f --retry 3 -o "$af" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font}.${ext}" 2>/dev/null && d=1
        [ $d -eq 0 ] && command -v wget &>/dev/null && wget -q --tries=3 -O "$af" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font}.${ext}" 2>/dev/null && d=1
        [ $d -eq 0 ] && { log WARNING "Failed: $font"; ((f++)); continue; }
        if ! $ecmd "$af" $destflag "$ed" 2>/dev/null; then log WARNING "Extract failed: $font"; ((f++)); continue; fi
        local cp=0
        while IFS= read -r -d '' ff; do cp "$ff" /usr/share/fonts/truetype/nerd-fonts/ 2>/dev/null; ((cp++)); done < <(find "$ed" -type f \( -iname "*.ttf" -o -iname "*.otf" \) -print0 2>/dev/null)
        [ $cp -gt 0 ] && { ((c++)); log INFO "Installed: $font"; } || { log WARNING "No files: $font"; ((f++)); }
        rm -rf "$af" "$ed"
    done
    command -v fc-cache &>/dev/null && fc-cache -f -v /usr/share/fonts/truetype/nerd-fonts/ 2>/dev/null
    rm -rf "$t"
    [ $c -gt 0 ] && log SUCCESS "Installed $c Nerd Fonts ($f failed)" || { log ERROR "No fonts installed"; return 1; }
    return 0
}

install_chris_titus_mybash() {
    local UH=$(eval echo ~$SUDO_USER 2>/dev/null || echo "/home/$(logname)")
    local MD="${UH}/mybash" BR="${UH}/.bashrc"
    if [ -d "$MD" ]; then log INFO "mybash already installed"; return 0; fi
    log INFO "Installing Chris Titus mybash..."

    # Clone directly (no privilege needed for a plain clone) - ownership gets
    # fixed once everything below is done.
    if ! git clone --depth 1 https://github.com/christitustech/mybash "$MD"; then
        log ERROR "Clone failed"
        return 1
    fi

    # Run setup.sh AS ROOT, not via `su - $SUDO_USER -c "... bash setup.sh"`.
    # setup.sh installs a handful of packages via its own internal `sudo`
    # call (verified by reading the upstream script - it runs
    # "sudo apt-get install -y bash-completion bat tree ..."). When invoked
    # through su as the unprivileged user, that nested sudo needs to prompt
    # for a password and requires a real controlling terminal - a different,
    # stricter requirement than plain `read`, which only needs readable
    # stdin. That's why the rest of this script's interactive menu can work
    # fine in a given terminal/session while this one step still fails with
    # "sudo: a terminal is required to authenticate". Running setup.sh as
    # root sidesteps the problem entirely: sudo invoked by root never prompts
    # or needs a terminal (verified empirically). HOME/USER/LOGNAME are
    # overridden so setup.sh writes into the target user's home, not root's.
    if HOME="$UH" USER="$SUDO_USER" LOGNAME="$SUDO_USER" bash "$MD/setup.sh"; then
        chown -R "$SUDO_USER:$SUDO_USER" "$MD" "$UH/.local" "$UH/.config" "$BR" 2>/dev/null || true
        log SUCCESS "mybash installed. User: source ~/.bashrc"
        return 0
    fi

    log WARNING "setup.sh failed, falling back to a plain .bashrc copy..."
    # Fallback matches the CURRENT upstream repo layout (verified by cloning
    # and inspecting it directly). The previous fallback listed
    # bash_profile/bash_aliases/bash_functions/bash_colors/git-prompt.sh/
    # git-completion.bash - none of which exist in this repo anymore - and
    # checked for a file named "bashrc" without the leading dot the real file
    # (".bashrc") actually has. That fallback matched nothing, copied
    # nothing, and still logged SUCCESS - a silent no-op wearing a success
    # message, exactly like the group-membership bug from earlier.
    [ -f "$MD/.bashrc" ] && cp "$MD/.bashrc" "$BR" 2>/dev/null
    if [ -f "$MD/starship.toml" ]; then
        mkdir -p "$UH/.config"
        cp "$MD/starship.toml" "$UH/.config/starship.toml" 2>/dev/null
    fi
    if [ -f "$MD/config.jsonc" ]; then
        mkdir -p "$UH/.config/fastfetch"
        cp "$MD/config.jsonc" "$UH/.config/fastfetch/config.jsonc" 2>/dev/null
    fi
    chown -R "$SUDO_USER:$SUDO_USER" "$MD" "$UH/.local" "$UH/.config" "$BR" 2>/dev/null || true
    if [ -f "$BR" ]; then
        log SUCCESS "mybash .bashrc installed via fallback copy. User: source ~/.bashrc"
        return 0
    else
        log ERROR "mybash fallback copy also failed - nothing was installed"
        return 1
    fi
}

install_gui_tools() {
    # evince and gedit intentionally NOT installed here - "Office &
    # Productivity" already owns evince and "Code Editors" already owns gedit;
    # neither is a dependency of gnome-tweaks/nautilus/etc.
    batch_install "GUI Tools" \
        gnome-tweaks \
        gnome-shell-extensions \
        gnome-themes-extra \
        nautilus \
        eog \
        file-roller \
        simple-scan \
        gnome-screenshot \
        gnome-system-monitor \
        dconf-editor
}

# ========== ANDROID TOOLS ==========
install_android_tools() {
    # adb/fastboot are plain packages on modern Ubuntu (the old
    # android-tools-adb/android-tools-fastboot names from 20.04-era guides
    # don't exist here - same class of stale-name mistake as the earlier
    # ubuntustudio-* hyphen bug). adb and fastboot are CLI-only and ship no
    # .desktop file, so they'll correctly log "Desktop file not found" and
    # just not get an icon - that's expected, same as docker/podman in
    # Containers. scrcpy DOES ship two real, separate desktop launchers
    # (scrcpy.desktop, and a scrcpy-console.desktop that opens a terminal
    # first) - neither is a NoDisplay decoy, so both are legitimately
    # supposed to get icons, same situation as Emacs (Client)/(Terminal).
    batch_install "Android Tools" adb fastboot scrcpy
}

# ========== SECURITY TOOLS ==========
# Standard security / pentest / defensive tooling, all from Ubuntu's own repos
# (main/universe). Intended for authorized security testing, CTFs, education, and
# defensive/hardening work on your own systems. As everywhere else, package_exists
# guards each name, so anything not in the archive is logged "Not in repos" rather
# than failing the batch. Most of these are CLI-only (no .desktop launcher), so
# they won't get folder icons - expected, same as nmap/adb; the few GUI tools
# (gufw, keepassxc, ettercap-graphical, wireshark if present) do get grouped.
install_security_tools() {
    # Network scanning / analysis. NOTE: wireshark and tcpdump are intentionally
    # NOT re-listed here - "System Utilities" already owns them.
    batch_install "Security - Network" \
        nmap masscan netcat-openbsd hping3 dnsutils

    # Web application testing
    batch_install "Security - Web" \
        nikto sqlmap dirb gobuster whatweb wapiti wfuzz

    # Password / hash cracking and wireless
    batch_install "Security - Cracking & Wireless" \
        john hashcat hydra aircrack-ng macchanger

    # Reverse engineering / forensics / stego
    batch_install "Security - Forensics & RE" \
        radare2 binwalk foremost sleuthkit steghide yara exiftool

    # Auditing / hardening / anti-malware (defensive)
    batch_install "Security - Hardening" \
        lynis chkrootkit rkhunter clamav clamav-daemon fail2ban aide

    # Firewall / VPN / privacy / credentials (GUI tools here get folder icons)
    batch_install "Security - Firewall & Privacy" \
        gufw openvpn wireguard proxychains4 torsocks keepassxc ettercap-graphical
}

# Defensive-only subset: hardening, integrity, auditing, anti-malware, intrusion
# detection, firewall, VPN and credential management - deliberately EXCLUDES the
# offensive/dual-use tooling (port/vuln scanners, web-attack tools, password
# crackers, wireless attack, MITM) from the full set. For blue-team / hardening
# use on systems you own or operate. Adds a few defense-specific packages the
# full set doesn't carry (auditd, aide, debsums, suricata, ufw).
install_security_defensive() {
    # System hardening, auditing, and file integrity
    batch_install "Defensive - Hardening & Integrity" \
        lynis chkrootkit rkhunter aide debsums auditd

    # Anti-malware
    batch_install "Defensive - Anti-Malware" \
        clamav clamav-daemon

    # Intrusion detection / prevention
    batch_install "Defensive - IDS/IPS" \
        fail2ban suricata

    # Firewall, VPN, and credential management (GUI tools here get folder icons)
    batch_install "Defensive - Firewall, VPN & Credentials" \
        ufw gufw openvpn wireguard keepassxc
}

# ========== DEVOPS & CLOUD ==========
install_devops() {
    install_docker_standalone
    install_azure_cli
    install_lazygit
}

# Docker + docker-compose as a lightweight, dedicated install (the full
# "Container & Virtualization" category also installs these, alongside
# podman/lxc/KVM/Cockpit - this is just Docker for a dev box). Adds the invoking
# user to the docker group and enables the service, same as the Containers path.
install_docker_standalone() {
    batch_install "Docker" docker.io docker-compose
    if command -v docker &>/dev/null; then
        usermod -aG docker "$SUDO_USER" 2>/dev/null || true
        systemctl enable --now docker 2>/dev/null || true
        log INFO "Docker configured - log out/in for the 'docker' group to take effect"
    fi
}

# Azure CLI via Microsoft's official install script (the exact command from
# Microsoft's docs). The script itself uses sudo internally; we're already root,
# so pipe to bash directly. Non-fatal on failure.
install_azure_cli() {
    if command -v az &>/dev/null; then
        SKIPPED_PACKAGES+=("azure-cli"); ((TOTAL_SKIPPED++)); log INFO "Already installed: azure-cli"; return 0
    fi
    log INFO "Installing Azure CLI (Microsoft install script)..."
    if curl -sL https://aka.ms/InstallAzureCLIDeb | bash 2>/dev/null && command -v az &>/dev/null; then
        INSTALLED_PACKAGES+=("azure-cli"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: azure-cli"
    else
        FAILED_PACKAGES+=("azure-cli"); ((TOTAL_FAILED++)); log WARNING "Azure CLI install failed - see https://aka.ms/InstallAzureCLIDeb"
    fi
}

# lazygit via `go install` (per request). Needs Go; install it first if missing
# (reuses install_go, which sets up /usr/local/go). `go install` is run AS the
# target user so the module cache and binary land in their home (~/go/bin), then
# the binary is symlinked into /usr/local/bin so it's on everyone's PATH.
install_lazygit() {
    if command -v lazygit &>/dev/null; then
        SKIPPED_PACKAGES+=("lazygit"); ((TOTAL_SKIPPED++)); log INFO "Already installed: lazygit"; return 0
    fi
    command -v go &>/dev/null || [ -x /usr/local/go/bin/go ] || { log INFO "Go not found - installing it first for lazygit..."; install_go; }
    local go_bin="/usr/local/go/bin"
    if ! command -v go &>/dev/null && [ ! -x "$go_bin/go" ]; then
        FAILED_PACKAGES+=("lazygit"); ((TOTAL_FAILED++)); log WARNING "Go unavailable - cannot install lazygit"; return 1
    fi
    local uh; uh=$(eval echo ~"$SUDO_USER" 2>/dev/null)
    log INFO "Installing lazygit via 'go install' (as $SUDO_USER)..."
    if su - "$SUDO_USER" -c "PATH=\$PATH:${go_bin} GOBIN='${uh}/go/bin' go install github.com/jesseduffield/lazygit@latest" 2>/dev/null \
       && [ -x "${uh}/go/bin/lazygit" ]; then
        ln -sf "${uh}/go/bin/lazygit" /usr/local/bin/lazygit 2>/dev/null || true
        INSTALLED_PACKAGES+=("lazygit"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: lazygit (${uh}/go/bin/lazygit)"
    else
        FAILED_PACKAGES+=("lazygit"); ((TOTAL_FAILED++)); log WARNING "lazygit install failed (needs Go + network access to github.com)"
    fi
}

# ========== DESKTOP APPS ==========
install_desktop_apps() {
    install_vivaldi
    install_spotify
    install_slack
    install_teams
    install_remmina
    install_windows_app
    install_teamviewer
}

# Vivaldi web browser - Chromium-based, feature-rich. Installed from Vivaldi's
# official apt repo (https://repo.vivaldi.com/archive/deb) so future updates flow
# through apt. amd64-only upstream. The repo publishes a detached Release.gpg (no
# inline InRelease), which signed-by handles fine. Package vivaldi-stable ships
# vivaldi-stable.desktop, so it lands a Desktop Apps folder icon via safe_install's
# tracking. Same keyring/.list convention as install_vscode: the keyring stays; the
# temp .list is removed after install (Vivaldi's own postinst re-registers the repo
# for updates, exactly as the VS Code package re-adds Microsoft's).
install_vivaldi() {
    if command -v vivaldi &>/dev/null || is_installed vivaldi-stable; then
        SKIPPED_PACKAGES+=("vivaldi-stable"); ((TOTAL_SKIPPED++)); log INFO "Already installed: vivaldi-stable"; return 0
    fi
    log INFO "Installing Vivaldi..."
    # Dearmor the signing key straight into the keyring (public key, mode 644),
    # same safe pattern as install_vscode.
    wget -qO- https://repo.vivaldi.com/archive/linux_signing_key.pub | gpg --dearmor \
        | install -D -m 644 /dev/stdin /usr/share/keyrings/vivaldi-browser.gpg 2>/dev/null
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/vivaldi-browser.gpg] https://repo.vivaldi.com/archive/deb/ stable main" > /etc/apt/sources.list.d/vivaldi.list
    apt-get update -qq 2>/dev/null
    safe_install vivaldi-stable
    rm -f /etc/apt/sources.list.d/vivaldi.list
}

# Spotify from its official apt repo (repository.spotify.com) rather than snap, so
# it installs through the active front-end (Nala/apt) and updates via apt. Package
# is spotify-client (binary `spotify`, ships spotify.desktop for its folder icon).
# Same keyring/.list convention as install_vscode; unlike VS Code, Spotify's repo
# does NOT re-register itself, so the .list is kept for future updates.
install_spotify() {
    # Gate on the .deb specifically, not `command -v spotify` - a leftover Spotify
    # snap also puts `spotify` on PATH and would make us wrongly skip the migration.
    if is_installed spotify-client; then
        SKIPPED_PACKAGES+=("spotify-client"); ((TOTAL_SKIPPED++)); log INFO "Already installed: spotify-client"
        remove_snap_if_present spotify; return 0
    fi
    log INFO "Installing Spotify (official apt repo via $PM)..."
    # Dearmor Spotify's signing key straight into the keyring (public key, mode 644).
    wget -qO- https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg | gpg --dearmor \
        | install -D -m 644 /dev/stdin /usr/share/keyrings/spotify.gpg 2>/dev/null
    echo "deb [signed-by=/usr/share/keyrings/spotify.gpg] https://repository.spotify.com stable non-free" > /etc/apt/sources.list.d/spotify.list
    pm_update
    safe_install spotify-client
    # Drop a superseded snap once the .deb is actually in place.
    is_installed spotify-client && remove_snap_if_present spotify
}

# Slack desktop. Not in Ubuntu's repos, and Slack shut down its old apt repo, so
# the "from apt" path is: download Slack's official .deb and install it THROUGH the
# active front-end (Nala when present, else apt-get) via pm_install, so runtime
# dependencies resolve - i.e. `nala install /path/slack.deb`, not a bare `dpkg -i`.
# Replaces the previous snap. Package is slack-desktop (binary `slack`, ships
# slack.desktop so it lands a Desktop Apps folder icon). amd64-only upstream. The
# current version is scraped from Slack's Linux release-notes page, with a pinned
# fallback if that lookup fails (the page is JS-heavy and can change shape).
install_slack() {
    # Gate on the .deb specifically, not `command -v slack` - a leftover Slack snap
    # also puts `slack` on PATH and would make us wrongly skip the .deb migration.
    if is_installed slack-desktop; then
        SKIPPED_PACKAGES+=("slack-desktop"); ((TOTAL_SKIPPED++)); log INFO "Already installed: slack-desktop"
        remove_snap_if_present slack; return 0
    fi
    local a; a=$(dpkg --print-architecture 2>/dev/null)
    if [ "$a" != "amd64" ]; then
        FAILED_PACKAGES+=("slack-desktop"); ((TOTAL_FAILED++))
        log WARNING "Slack ships an amd64 .deb only - not available for '$a'"; return 0
    fi
    log INFO "Installing Slack (official .deb via $PM)..."
    local ver
    ver=$(curl -fsSL "https://slack.com/release-notes/linux" 2>/dev/null \
        | grep -oP 'slack-desktop-\K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$ver" ] && ver="4.51.180"
    local url="https://downloads.slack-edge.com/desktop-releases/linux/x64/${ver}/slack-desktop-${ver}-amd64.deb"
    local t; t=$(mktemp -d)
    if curl -L -f --retry 2 -o "$t/slack.deb" "$url" 2>/dev/null || wget -q --tries=2 -O "$t/slack.deb" "$url" 2>/dev/null; then
        # Install the local .deb through the package manager so dependencies
        # resolve. An absolute path (has a '/') is treated as a file by both
        # nala and apt-get; is_installed re-check covers a 0-exit-with-warnings run.
        if pm_install "$t/slack.deb" || is_installed slack-desktop; then
            rm -rf "$t"; INSTALLED_PACKAGES+=("slack-desktop"); ((TOTAL_INSTALLED++))
            log SUCCESS "Installed: slack-desktop ${ver} (.deb via $PM)"
            remove_snap_if_present slack; return 0
        fi
    fi
    rm -rf "$t"
    FAILED_PACKAGES+=("slack-desktop"); ((TOTAL_FAILED++))
    log WARNING "Slack install failed - download the .deb from slack.com/downloads/linux and: $PM install ./slack-desktop-*.deb"; return 0
}

# Microsoft Teams. Microsoft discontinued the official native Linux client in
# Dec 2022, so this installs teams-for-linux (https://github.com/IsmaelMartinez/
# teams-for-linux) - the maintained open-source Electron wrapper around the Teams
# web app, and the de-facto Teams client on Linux. Installed from its official
# apt repo (https://teamsforlinux.de), which builds for amd64 + arm64; the
# package ships teams-for-linux.desktop so it lands an icon in the Desktop Apps
# folder automatically via safe_install.
install_teams() {
    if command -v teams-for-linux &>/dev/null; then
        SKIPPED_PACKAGES+=("teams-for-linux"); ((TOTAL_SKIPPED++)); log INFO "Already installed: teams-for-linux"; return 0
    fi
    log INFO "Installing Microsoft Teams (teams-for-linux)..."
    # Key is served pre-armored (.asc), so install it as-is - no gpg --dearmor.
    # The .list is removed after install (same convention as install_vscode); the
    # public key is left in keyrings (harmless). arch is resolved from dpkg so the
    # repo line is correct on both amd64 and arm64.
    install -d -m 755 /etc/apt/keyrings 2>/dev/null
    if ! { curl -fsSL https://repo.teamsforlinux.de/teams-for-linux.asc -o /etc/apt/keyrings/teams-for-linux.asc 2>/dev/null \
           || wget -qO /etc/apt/keyrings/teams-for-linux.asc https://repo.teamsforlinux.de/teams-for-linux.asc 2>/dev/null; }; then
        FAILED_PACKAGES+=("teams-for-linux"); ((TOTAL_FAILED++)); log WARNING "Could not fetch Teams signing key - skipping"; return 0
    fi
    chmod 644 /etc/apt/keyrings/teams-for-linux.asc 2>/dev/null
    echo "deb [signed-by=/etc/apt/keyrings/teams-for-linux.asc arch=$(dpkg --print-architecture)] https://repo.teamsforlinux.de/debian/ stable main" > /etc/apt/sources.list.d/teams-for-linux-packages.list
    apt-get update -qq 2>/dev/null
    safe_install teams-for-linux
    rm -f /etc/apt/sources.list.d/teams-for-linux-packages.list
}

# Remmina remote-desktop client. Tries the upstream remmina-next PPA for the
# latest build (codename-aware via add_ppa - degrades to the distro package if
# the PPA has no build for this release), then installs Remmina + the RDP and
# secret-storage plugins.
install_remmina() {
    add_ppa ppa:remmina-ppa-team/remmina-next remmina
    batch_install "Remmina" remmina remmina-plugin-rdp remmina-plugin-secret
}

# "Windows App" (mariuszkopowski/windows-app-for-linux) - a Linux remote-desktop
# client for Windows 365 / Azure Virtual Desktop / RDP. It is NOT on Flathub, so it
# ships as a standalone Flatpak bundle from its GitHub releases. This installer
# fetches the latest x86_64 .flatpak automatically (like install_cursor pulls
# vendor binaries), and still honours a local bundle dropped next to this script
# for offline/pinned use. Installed into the desktop user's per-user Flatpak scope
# (flatpak --user), so it lands in that user's app grid. Deliberately NOT launched
# during install; the run command is echoed in the success message instead.
install_windows_app() {
    local app_id="io.github.mariuszkopowski.WindowsAppForLinux"
    local repo="mariuszkopowski/windows-app-for-linux"

    # A --user install needs a real desktop user to own it; bail cleanly if the
    # script was run as root without sudo (SUDO_USER unset or literally root).
    if [ -z "$SUDO_USER" ] || [ "$SUDO_USER" = "root" ]; then
        log WARNING "No desktop user (SUDO_USER) - skipping Windows App"
        SKIPPED_PACKAGES+=("Windows App"); ((TOTAL_SKIPPED++)); return 1
    fi

    # Flatpak isn't installed by default on these releases - pull it (plus a
    # portal so the sandboxed app can reach the desktop) before installing.
    if ! command -v flatpak &>/dev/null; then
        batch_install "Flatpak" flatpak xdg-desktop-portal-gtk
    fi
    if ! command -v flatpak &>/dev/null; then
        log WARNING "flatpak unavailable - install manually: flatpak install --user \"Windows*.flatpak\""
        FAILED_PACKAGES+=("Windows App"); ((TOTAL_FAILED++)); return 1
    fi

    # Already present in the user's Flatpak scope? Skip.
    if su - "$SUDO_USER" -c "flatpak info --user '$app_id'" &>/dev/null; then
        SKIPPED_PACKAGES+=("Windows App"); ((TOTAL_SKIPPED++))
        log INFO "Already installed: Windows App (flatpak)"; return 0
    fi

    # Prefer a local bundle next to the script if present (glob matches both
    # "Windows App-*.flatpak" and the real release name "Windows.App-*.flatpak");
    # otherwise download the latest x86_64 .flatpak from the project's releases.
    local dir bundle tmp=""
    dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    bundle=$(ls -1t "$dir"/Windows*.flatpak 2>/dev/null | head -n1)
    if [ -z "$bundle" ]; then
        log INFO "No local Windows App bundle - downloading latest from github.com/$repo ..."
        local url
        url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
            | grep -oP '"browser_download_url":\s*"\K[^"]*x86_64[^"]*\.flatpak')
        if [ -n "$url" ]; then
            tmp=$(mktemp -d)
            if curl -L -f --retry 2 -o "$tmp/windows-app.flatpak" "$url" 2>/dev/null \
                || wget -q --tries=2 -O "$tmp/windows-app.flatpak" "$url" 2>/dev/null; then
                bundle="$tmp/windows-app.flatpak"
                # The bundle lives in a root-owned tempdir; make it reachable and
                # readable by SUDO_USER, who runs the --user install below.
                chmod 755 "$tmp" 2>/dev/null; chmod 644 "$bundle" 2>/dev/null
                chown "$SUDO_USER" "$tmp" "$bundle" 2>/dev/null || true
            fi
        fi
    fi
    if [ -z "$bundle" ]; then
        [ -n "$tmp" ] && rm -rf "$tmp"
        log WARNING "Windows App bundle not found locally and download failed - skipping"
        SKIPPED_PACKAGES+=("Windows App"); ((TOTAL_SKIPPED++)); return 1
    fi

    log INFO "Installing Windows App from $(basename "$bundle") (flatpak --user)..."
    # Add Flathub (per-user) first so the bundle's runtime dependencies can be
    # resolved; harmless if the bundle is self-contained or Flathub is already set.
    su - "$SUDO_USER" -c "flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo" 2>/dev/null || true
    if su - "$SUDO_USER" -c "flatpak install --user -y '$bundle'" 2>/dev/null \
        || su - "$SUDO_USER" -c "flatpak info --user '$app_id'" &>/dev/null; then
        [ -n "$tmp" ] && rm -rf "$tmp"
        INSTALLED_PACKAGES+=("Windows App"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: Windows App (flatpak) - launch with: flatpak run $app_id"
        return 0
    fi
    [ -n "$tmp" ] && rm -rf "$tmp"
    FAILED_PACKAGES+=("Windows App"); ((TOTAL_FAILED++))
    log ERROR "Failed: Windows App (flatpak)"
    return 1
}

# TeamViewer remote-desktop/support client. Distributed only as a vendor .deb
# (not in Ubuntu's repos), so - like install_cursor - download it and let apt
# resolve dependencies. The .deb itself registers TeamViewer's own apt repo +
# signing key on install, so future updates flow through the normal apt path.
install_teamviewer() {
    if command -v teamviewer &>/dev/null || is_installed teamviewer; then
        SKIPPED_PACKAGES+=("teamviewer"); ((TOTAL_SKIPPED++)); log INFO "Already installed: teamviewer"; return 0
    fi
    log INFO "Installing TeamViewer..."
    local t=$(mktemp -d) a=$(dpkg --print-architecture)
    # TeamViewer ships amd64 and arm64 builds; any other arch falls back to the
    # amd64 package (it pulls its 32-bit deps via multiarch).
    local deb="teamviewer_${a}.deb"
    case "$a" in amd64|arm64) ;; *) deb="teamviewer_amd64.deb";; esac
    for u in "https://download.teamviewer.com/download/linux/${deb}" "https://download.teamviewer.com/download/linux/teamviewer_amd64.deb"; do
        if curl -L -f --retry 2 -o "$t/teamviewer.deb" "$u" 2>/dev/null || wget -q --tries=2 -O "$t/teamviewer.deb" "$u" 2>/dev/null; then
            dpkg -i "$t/teamviewer.deb" 2>/dev/null || { apt-get install -f -y 2>/dev/null; dpkg -i "$t/teamviewer.deb" 2>/dev/null; }
            rm -rf "$t"
            if command -v teamviewer &>/dev/null || is_installed teamviewer; then
                INSTALLED_PACKAGES+=("teamviewer"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: teamviewer"
            else
                FAILED_PACKAGES+=("teamviewer"); ((TOTAL_FAILED++)); log ERROR "Failed: teamviewer"
            fi
            return 0
        fi
    done
    rm -rf "$t"
    FAILED_PACKAGES+=("teamviewer"); ((TOTAL_FAILED++))
    log WARNING "TeamViewer download failed - get it from https://www.teamviewer.com/"; return 0
}

# ========== BROWSERS ==========
install_browsers() {
    install_chrome
    install_brave
}

# Google Chrome from Google's official apt repo. amd64-only. Package
# google-chrome-stable (ships google-chrome.desktop). Same keyring convention as
# install_vscode: Chrome's postinst re-registers its own repo, so the temp .list is
# removed after install (the kept key still verifies Chrome's re-added source).
install_chrome() {
    if is_installed google-chrome-stable; then
        SKIPPED_PACKAGES+=("google-chrome-stable"); ((TOTAL_SKIPPED++)); log INFO "Already installed: google-chrome-stable"; return 0
    fi
    local a; a=$(dpkg --print-architecture 2>/dev/null)
    if [ "$a" != "amd64" ]; then
        FAILED_PACKAGES+=("google-chrome-stable"); ((TOTAL_FAILED++))
        log WARNING "Chrome ships an amd64 .deb only - not available for '$a'"; return 0
    fi
    log INFO "Installing Google Chrome (official apt repo via $PM)..."
    wget -qO- https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor \
        | install -D -m 644 /dev/stdin /usr/share/keyrings/google-chrome.gpg 2>/dev/null
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome-setup.list
    pm_update
    safe_install google-chrome-stable
    rm -f /etc/apt/sources.list.d/google-chrome-setup.list
}

# Brave from Brave's official apt repo. Package brave-browser (ships
# brave-browser.desktop). Brave publishes a ready-made keyring .gpg (already
# dearmored), so install it as-is. Keeps key + .list (repo isn't self-registered).
install_brave() {
    if is_installed brave-browser; then
        SKIPPED_PACKAGES+=("brave-browser"); ((TOTAL_SKIPPED++)); log INFO "Already installed: brave-browser"; return 0
    fi
    log INFO "Installing Brave (official apt repo via $PM)..."
    curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
        -o /usr/share/keyrings/brave-browser-archive-keyring.gpg 2>/dev/null
    chmod 644 /usr/share/keyrings/brave-browser-archive-keyring.gpg 2>/dev/null
    echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" > /etc/apt/sources.list.d/brave-browser-release.list
    pm_update
    safe_install brave-browser
}

# ========== COMMUNICATION ==========
install_communication() {
    install_signal
    install_discord
    install_zoom
    install_telegram
}

# Signal Desktop from Signal's official apt repo. amd64-only. Package signal-desktop
# (ships signal-desktop.desktop). Keeps key + .list (repo isn't self-registered).
install_signal() {
    if is_installed signal-desktop; then
        SKIPPED_PACKAGES+=("signal-desktop"); ((TOTAL_SKIPPED++)); log INFO "Already installed: signal-desktop"; return 0
    fi
    local a; a=$(dpkg --print-architecture 2>/dev/null)
    if [ "$a" != "amd64" ]; then
        FAILED_PACKAGES+=("signal-desktop"); ((TOTAL_FAILED++))
        log WARNING "Signal ships an amd64 .deb only - not available for '$a'"; return 0
    fi
    log INFO "Installing Signal (official apt repo via $PM)..."
    wget -qO- https://updates.signal.org/desktop/apt/keys.asc | gpg --dearmor \
        | install -D -m 644 /dev/stdin /usr/share/keyrings/signal-desktop-keyring.gpg 2>/dev/null
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/signal-desktop-keyring.gpg] https://updates.signal.org/desktop/apt xenial main" > /etc/apt/sources.list.d/signal-xenial.list
    pm_update
    safe_install signal-desktop
}

# Discord and Zoom are installed as Flatpaks from Flathub rather than direct .debs:
# neither has an apt repo, so a .deb would never auto-update (Discord in particular
# refuses to launch until manually updated). Flathub keeps them current. Installed
# system-wide via flatpak_install_flathub, which tracks by display name so the
# Communication app-folder picks them up through create_menu_category's Flatpak
# stage. Contrast with install_signal/install_telegram, which stay as apt .debs
# because those DO have an update path.
install_discord() { flatpak_install_flathub com.discordapp.Discord "Discord"; }
install_zoom()    { flatpak_install_flathub us.zoom.Zoom "Zoom"; }

# Shared helper: install a Flathub app system-wide, tracking it under a friendly
# display name (matched by the app-folder resolver's Flatpak stage). Pulls flatpak +
# a GTK portal first if absent, adds the Flathub remote, then installs. Best-effort
# and self-skipping, same shape as install_alpaca.
flatpak_install_flathub() {
    local app_id="$1" label="$2"
    if ! command -v flatpak &>/dev/null; then
        batch_install "Flatpak" flatpak xdg-desktop-portal-gtk
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

# Telegram Desktop from Ubuntu's own universe repo: package telegram-desktop, a real
# .deb (ships org.telegram.desktop.desktop). safe_install tracks it and skips
# cleanly if the package isn't available on this release.
install_telegram() { batch_install "Telegram" telegram-desktop; }

# ========== MENU SYSTEM ==========
# Dim section label spanning the two-column menu.
ui_section() { printf "  ${LAVENDER}${BOLD}%s${NC}\n" "$1"; }

show_main_menu() {
    clear
    ui_header "UBUNTU ${UBUNTU_VERSION:-26.04/26.10}  ·  POST-INSTALL" "verified packages · nala · GNOME app folders"
    echo
    ui_section "Media & Creative"
    ui_cell  1 "Ubuntu Studio";      ui_cell  2 "Graphics & Images";    echo
    ui_cell  3 "Video Editing";      ui_cell  4 "Audio Production";      echo
    ui_cell 17 "Gaming";             ui_cell 28 "Desktop Apps";          echo
    echo
    ui_section "Development"
    ui_cell  5 "Code Editors";       ui_cell  6 "Python";               echo
    ui_cell  7 "Web Development";    ui_cell  8 "Java";                 echo
    ui_cell  9 "C/C++";              ui_cell 10 "Go";                   echo
    ui_cell 11 "Rust";               ui_cell 12 "Node.js";              echo
    ui_cell 13 "PHP";                ui_cell 14 "Ruby";                 echo
    ui_cell 26 ".NET";               ui_cell 27 "DevOps & Cloud";       echo
    ui_cell 20 "General Dev Tools";  ui_cell 21 "AI Tools";             echo
    echo
    ui_section "Data, System & Desktop"
    ui_cell 15 "Databases";          ui_cell 16 "Containers & VMs";     echo
    ui_cell 19 "System Utilities";   ui_cell 22 "GUI Tweaks";           echo
    ui_cell 18 "Office & Docs";      ui_cell 25 "Security Tools";       echo
    echo
    ui_section "Compatibility & Devices"
    ui_cell 23 "Windows (Wine)";     ui_cell 24 "Android Tools";        echo
    echo
    ui_section "Internet & Communication"
    ui_cell 29 "Browsers";           ui_cell 30 "Communication";        echo
    echo
    ui_section "Bulk"
    ui_cell_alt A "All Dev Tools";   ui_cell_alt B "All Media";         echo
    ui_cell_alt C "EVERYTHING";                                         echo
    echo
    ui_rule
    ui_cell  S "Summary";            ui_cell  0 "Exit";                 echo
    printf "  ${MAUVE}${BOLD}❯${NC} ${LAVENDER}Choose ${DIM}[0-30 · A-C · S]${NC}${LAVENDER}: ${NC}"
}

show_ubuntu_studio_menu() {
    clear
    ui_header "UBUNTU STUDIO PACKAGES"
    echo
    ui_item 1 "Ubuntu Studio (Full)"
    ui_item 2 "Graphics"
    ui_item 3 "Video"
    ui_item 4 "Audio"
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

# Reset tracking for each new installation
reset_tracking() {
    INSTALLED_PACKAGES=()
    FAILED_PACKAGES=()
    SKIPPED_PACKAGES=()
    TOTAL_INSTALLED=0
    TOTAL_FAILED=0
    TOTAL_SKIPPED=0
}

# Prompt to create menu category after installation
# Usage: prompt_menu_category "Category Name" "icon-name" "Comment" "app1" "app2" ...
prompt_menu_category() {
    local name="$1"
    local icon="$2"
    local comment="$3"
    shift 3
    local apps=("$@")
    
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

# Install one category and auto-create its GNOME app folder from just that
# category's packages, WITHOUT prompting. Used by the bulk options (A/B/C) so a
# full run still produces the per-category app folders the individual menu
# entries create interactively. Instead of resetting tracking per category
# (which would break the whole-run summary the bulk block prints at the end), it
# snapshots the tracking-array lengths before the install and slices out only
# the newly-added installed+skipped packages afterward - so the global arrays
# keep accumulating for display_summary while each folder still gets exactly its
# own category's apps. create_menu_category's icon/comment args are unused ("").
# Folder names match the individual menu entries for consistency.
auto_category() {
    local name="$1" fn="$2"
    local pre_i=${#INSTALLED_PACKAGES[@]} pre_s=${#SKIPPED_PACKAGES[@]}
    "$fn"
    local apps=("${INSTALLED_PACKAGES[@]:$pre_i}" "${SKIPPED_PACKAGES[@]:$pre_s}")
    [ ${#apps[@]} -gt 0 ] && create_menu_category "$name" "" "" "${apps[@]}"
}

# ========== MAIN EXECUTION ==========
main() {
    check_root
    # Safety net: if the run is interrupted between _block_apache_autostart and
    # _unblock_apache_autostart, make sure our temporary /usr/sbin/policy-rc.d
    # (which makes invoke-rc.d a no-op for apache2) doesn't get left behind and
    # silently break service starts on the system afterward.
    trap '[ -n "${_POLICY_RC_ADDED:-}" ] && rm -f /usr/sbin/policy-rc.d 2>/dev/null || true' EXIT
    check_version
    check_stale_fetch_sources
    update_packages
    install_nala
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
                show_ubuntu_studio_menu
                read -r studio_choice
                case "$studio_choice" in
                    0) continue ;;
                    1) reset_tracking; install_ubuntu_studio_full; display_summary; prompt_menu_category "Ubuntu Studio" "ubuntu-studio" "Ubuntu Studio Applications" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    2) reset_tracking; install_ubuntu_studio_graphics; display_summary; prompt_menu_category "Ubuntu Studio Graphics" "graphics" "Ubuntu Studio Graphics Applications" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    3) reset_tracking; install_ubuntu_studio_video; display_summary; prompt_menu_category "Ubuntu Studio Video" "video" "Ubuntu Studio Video Applications" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    4) reset_tracking; install_ubuntu_studio_audio; display_summary; prompt_menu_category "Audio Production" "audio" "Audio Production Applications" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    5) reset_tracking; install_ubuntu_studio_photography; display_summary; prompt_menu_category "Photography" "camera" "Photography Applications" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    6) reset_tracking; install_ubuntu_studio_publishing; display_summary; prompt_menu_category "Publishing" "office" "Publishing Applications" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    *) log ERROR "Invalid choice"; sleep 2 ;;
                esac
                ;;
            2) reset_tracking; install_graphics; display_summary; prompt_menu_category "Graphics" "applications-graphics" "Graphics & Image Manipulation" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            3) reset_tracking; install_video; display_summary; prompt_menu_category "Video" "video" "Video Creation & Editing" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            4) reset_tracking; install_audio; display_summary; prompt_menu_category "Audio Production" "audio" "Audio Production & Editing" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            5) reset_tracking; install_code_editors; display_summary; prompt_menu_category "Code Editors" "text-editor" "Code Editors" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            6) reset_tracking; install_python; display_summary; prompt_menu_category "Python Development" "python" "Python Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            7) reset_tracking; install_web_dev; display_summary; prompt_menu_category "Web Development" "web" "Web Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            8) reset_tracking; install_java; display_summary; prompt_menu_category "Java Development" "java" "Java Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            9) reset_tracking; install_c_cpp; display_summary; prompt_menu_category "C/C++ Development" "application-x-executable" "C/C++ Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            10) reset_tracking; install_go; display_summary; prompt_menu_category "Go Development" "golang" "Go Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            11) reset_tracking; install_rust; display_summary; prompt_menu_category "Rust Development" "rust" "Rust Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            12) reset_tracking; install_nodejs_dev; display_summary; prompt_menu_category "Node.js Development" "nodejs" "Node.js Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            13) reset_tracking; install_php; display_summary; prompt_menu_category "PHP Development" "php" "PHP Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            14) reset_tracking; install_ruby; display_summary; prompt_menu_category "Ruby Development" "ruby" "Ruby Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            15) reset_tracking; install_databases; display_summary; prompt_menu_category "Database Tools" "database" "Database Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            16) reset_tracking; install_containers; display_summary; prompt_menu_category "Containers" "docker" "Container & Virtualization Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            17) reset_tracking; install_gaming; display_summary; prompt_menu_category "Gaming" "games" "Gaming Applications" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            18) reset_tracking; install_office; display_summary; prompt_menu_category "Office & Productivity" "office" "Office & Productivity Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            19) reset_tracking; install_system_utils; display_summary; prompt_menu_category "System Utilities" "utilities" "System Utilities" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            20) reset_tracking; install_dev_tools; display_summary; prompt_menu_category "General Development Tools" "development" "General Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            21) reset_tracking; install_ai_tools; display_summary; prompt_menu_category "AI Tools" "ai" "AI Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            22) reset_tracking; install_gui_tweaks; display_summary; prompt_menu_category "GUI Tweaks" "preferences" "GUI Customization & Tweaks" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            23) reset_tracking; install_windows_support; display_summary; prompt_menu_category "Windows Software Support" "wine" "Windows Software Support (Wine)" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            24) reset_tracking; install_android_tools; display_summary; prompt_menu_category "Android Tools" "phone" "Android Tools (adb, fastboot, scrcpy)" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            25)
                show_security_menu
                read -r sec_choice
                case "$sec_choice" in
                    0) continue ;;
                    1) reset_tracking; install_security_tools; display_summary; prompt_menu_category "Security Tools" "security" "Security & Pentest Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    2) reset_tracking; install_security_defensive; display_summary; prompt_menu_category "Security (Defensive)" "security" "Defensive Security Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    *) log ERROR "Invalid choice"; sleep 2 ;;
                esac
                ;;
            26) reset_tracking; install_dotnet; display_summary; prompt_menu_category ".NET Development" "dotnet" ".NET Development Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            27) reset_tracking; install_devops; display_summary; prompt_menu_category "DevOps & Cloud" "cloud" "DevOps & Cloud Tools" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            28) reset_tracking; install_desktop_apps; display_summary; prompt_menu_category "Desktop Apps" "applications-other" "Desktop Applications" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            29) reset_tracking; install_browsers; display_summary; prompt_menu_category "Browsers" "web-browser" "Web Browsers" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            30) reset_tracking; install_communication; display_summary; prompt_menu_category "Communication" "internet-group-chat" "Communication Apps" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
            A|a)
                reset_tracking
                log INFO "Installing ALL Development Tools (with app folders)..."
                auto_category "Code Editors" install_code_editors
                auto_category "Python Development" install_python
                auto_category "Web Development" install_web_dev
                auto_category "Java Development" install_java
                auto_category "C/C++ Development" install_c_cpp
                auto_category "Go Development" install_go
                auto_category "Rust Development" install_rust
                auto_category "Node.js Development" install_nodejs_dev
                auto_category "PHP Development" install_php
                auto_category "Ruby Development" install_ruby
                auto_category ".NET Development" install_dotnet
                auto_category "General Development Tools" install_dev_tools
                auto_category "AI Tools" install_ai_tools
                display_summary
                ;;
            B|b)
                reset_tracking
                log INFO "Installing ALL Media Tools (with app folders)..."
                auto_category "Ubuntu Studio" install_ubuntu_studio_full
                auto_category "Graphics" install_graphics
                auto_category "Video" install_video
                auto_category "Audio Production" install_audio
                display_summary
                ;;
            C|c)
                reset_tracking
                log INFO "Installing EVERYTHING (with app folders)..."
                auto_category "Ubuntu Studio" install_ubuntu_studio_full
                auto_category "Graphics" install_graphics
                auto_category "Video" install_video
                auto_category "Audio Production" install_audio
                auto_category "Code Editors" install_code_editors
                auto_category "Python Development" install_python
                auto_category "Web Development" install_web_dev
                auto_category "Java Development" install_java
                auto_category "C/C++ Development" install_c_cpp
                auto_category "Go Development" install_go
                auto_category "Rust Development" install_rust
                auto_category "Node.js Development" install_nodejs_dev
                auto_category "PHP Development" install_php
                auto_category "Ruby Development" install_ruby
                auto_category ".NET Development" install_dotnet
                auto_category "DevOps & Cloud" install_devops
                auto_category "Database Tools" install_databases
                auto_category "Containers" install_containers
                auto_category "Gaming" install_gaming
                auto_category "Office & Productivity" install_office
                auto_category "System Utilities" install_system_utils
                auto_category "General Development Tools" install_dev_tools
                auto_category "AI Tools" install_ai_tools
                auto_category "GUI Tweaks" install_gui_tweaks
                auto_category "Windows Software Support" install_windows_support
                auto_category "Android Tools" install_android_tools
                auto_category "Security Tools" install_security_tools
                auto_category "Desktop Apps" install_desktop_apps
                auto_category "Browsers" install_browsers
                auto_category "Communication" install_communication
                display_summary
                ;;
            *)
                log ERROR "Invalid choice. Please try again."
                sleep 2
                ;;
        esac
        read -p "$(printf "${DIM}${SUBTEXT}  Press [Enter] to continue…${NC}")" _
    done
}

# Only auto-run the installer when executed directly (sudo ./post-install.sh). When
# the script is sourced - e.g. `source post-install.sh; install_vivaldi` to run one
# installer, or for testing - this guard stops main() (and its check_root / apt
# update / interactive menu) from firing, so individual functions can be called.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi