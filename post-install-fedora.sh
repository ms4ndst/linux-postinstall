#!/bin/bash
# Fedora Workstation Post-Install Script v1 (dnf5)
# Menu-driven installer with error handling - Fedora/RPM port of post-install.sh
# Run as: chmod +x post-install-fedora.sh && sudo ./post-install-fedora.sh
#
# PACKAGE NAME CONFIDENCE NOTE: the "hard" categories (RPM Fusion, proprietary
# drivers, multimedia codecs, browsers, communication apps, desktop apps,
# Fedora Jam/Design Suite groups, Incus, Flathub fallbacks) were individually
# verified against live vendor docs / packages.fedoraproject.org / Flathub
# during development. The bulk of "ordinary" packages (editors, languages,
# system utilities - vim, ripgrep, htop, gcc, golang, ...) were NOT
# individually re-verified against a live Fedora system (this was written
# without one available) - they rely on well-established Fedora naming
# conventions instead. Either way, every install goes through
# package_exists() before safe_install() ever runs, so a wrong guess is
# logged "Not in repos" and skipped rather than failing the whole run -
# exactly the same safety net the Ubuntu version of this script uses.

# ── Catppuccin Mocha palette (24-bit truecolor ANSI) ─────────────────────────
# Same convention as the Ubuntu script: colors by SEMANTIC ROLE. Auto-disables
# when stdout isn't a terminal or NO_COLOR is set.
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

# Releases this script is validated against. Fedora ships a new release every
# ~6 months, so - like the Ubuntu script's own SUPPORTED_VERSIONS - this array
# needs bumping periodically; add a release here to make check_version accept
# it without prompting.
declare -a SUPPORTED_VERSIONS=("42" "43" "44")
FEDORA_VERSION=""

declare -a INSTALLED_PACKAGES FAILED_PACKAGES SKIPPED_PACKAGES
TOTAL_INSTALLED=0; TOTAL_FAILED=0; TOTAL_SKIPPED=0

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

# Detect the running release once, into globals the rest of the script reads.
# Reads /etc/os-release directly (every Fedora install has one) rather than
# leaning on lsb_release, which isn't installed by default on Fedora the way
# it is on Ubuntu.
detect_version() {
    FEDORA_VERSION=$(grep -oP '(?<=^VERSION_ID=)\d+' /etc/os-release 2>/dev/null)
    FEDORA_ID=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"')
}

check_version() {
    detect_version
    local supported=false v
    if [ "${FEDORA_ID:-}" = "fedora" ]; then
        for v in "${SUPPORTED_VERSIONS[@]}"; do
            [[ "$FEDORA_VERSION" == "$v" ]] && { supported=true; break; }
        done
    fi
    if $supported; then
        log INFO "Detected supported Fedora $FEDORA_VERSION"
    else
        local joined; joined=$(IFS=/; echo "${SUPPORTED_VERSIONS[*]}")
        log WARNING "Designed for Fedora ${joined} (id=fedora), detected: ${FEDORA_ID:-unknown} ${FEDORA_VERSION:-unknown}"
        read -p "Continue anyway? [y/N] " -n 1 -r; echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
}

# ── Package-manager front-end (dnf5) ─────────────────────────────────────────
# Fedora 41+ aliases the `dnf` command to dnf5 already, so PM is always just
# "dnf" - unlike the Ubuntu script's nala/apt-get split, there's no alternate
# front-end to bootstrap here. is_installed uses rpm directly (dnf itself
# shells out to rpm for this exact check, so this is no slower and avoids a
# dnf startup for every single lookup across ~90 install functions).
PM="dnf"
is_installed() { rpm -q "$1" &>/dev/null; }
# Does an installable candidate exist for this exact package? `dnf info`
# checks BOTH installed and available packages and exits non-zero if the name
# is unknown to any enabled repo - the direct dnf5 equivalent of the Ubuntu
# script's `apt-cache policy` check.
package_exists() { dnf info -q "$1" &>/dev/null; }

pm_update() {
    dnf makecache
}
pm_install() { dnf install -y "$@" 2>/dev/null; }

# Enable a COPR project (owner/project). Mirrors add_ppa's shape but simpler:
# COPR doesn't need a per-codename existence probe the way Launchpad PPAs do -
# `dnf copr enable` just fails cleanly (non-zero, no repo added) if the
# project has no build for this Fedora release, and that failure is handled
# the same way a failed pm_install already is everywhere else.
add_copr() {
    local copr="$1" tag="$2"
    grep -rq "$tag" /etc/yum.repos.d/ 2>/dev/null && return 0
    if dnf copr enable -y "$copr" &>/dev/null; then
        return 0
    fi
    log WARNING "COPR $copr not available for Fedora ${FEDORA_VERSION:-this release} - continuing without it"
    return 1
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
        if pm_install "$pkg" || is_installed "$pkg"; then
            INSTALLED_PACKAGES+=("$pkg"); ((TOTAL_INSTALLED++))
            log SUCCESS "Installed: $pkg"
        else
            FAILED_PACKAGES+=("$pkg"); ((TOTAL_FAILED++))
            log ERROR "Failed: $pkg"
        fi
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

update_packages() {
    log INFO "Refreshing package metadata..."
    if ! pm_update; then
        log ERROR "Failed to refresh metadata. Check internet."
        read -p "Retry? [y/N] " -n 1 -r; echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then update_packages; else log ERROR "Cannot proceed."; exit 1; fi
    fi
    log SUCCESS "Metadata refreshed."
}

# Enable RPM Fusion (free + nonfree) and the Cisco OpenH264 repo. This is the
# Fedora equivalent of install_nala bootstrapping a nicer apt front-end on the
# Ubuntu script - except here it's not cosmetic, it's load-bearing: almost
# every proprietary codec/driver/app below assumes these repos are already
# enabled. Runs once, early, before any category installs.
bootstrap_repos() {
    log INFO "Enabling RPM Fusion (free + nonfree)..."
    if ! rpm -q rpmfusion-free-release &>/dev/null; then
        dnf install -y \
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
            "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" \
            2>/dev/null
    fi
    if is_installed rpmfusion-free-release && is_installed rpmfusion-nonfree-release; then
        log SUCCESS "RPM Fusion enabled"
        # dnf5 doesn't fold RPM Fusion's AppStream metadata into a comps/group
        # refresh the way dnf4 sometimes did - install it explicitly so
        # GNOME Software/discover actually show RPM Fusion app entries.
        safe_install rpmfusion-free-appstream-data rpmfusion-nonfree-appstream-data
    else
        log WARNING "RPM Fusion setup failed - proprietary codecs/drivers/apps below will mostly fail too"
    fi

    log INFO "Enabling Cisco OpenH264 repo..."
    dnf config-manager setopt fedora-cisco-openh264.enabled=1 2>/dev/null \
        || log WARNING "Could not enable fedora-cisco-openh264 (non-fatal - H.264 decode may be limited)"
}

install_base() {
    log INFO "Installing base utilities..."
    batch_install "base" curl wget git gnupg2 dnf5-plugins dconf dbus-x11 xdg-user-dirs
    mkdir -p /usr/share/desktop-directories
}

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

# Resolve the logged-in desktop user + uid and confirm a live D-Bus session
# bus exists for them. Identical in spirit to the Ubuntu script's version -
# GNOME session detection has nothing to do with the package manager.
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

gset_if_exists() {
    local user="$1" uid="$2" schema="$3" key="$4" value="$5"
    gsettings_as_user "$user" "$uid" list-schemas 2>/dev/null | grep -qx "$schema" || return 1
    gsettings_as_user "$user" "$uid" list-keys "$schema" 2>/dev/null | grep -qx "$key" || return 1
    gsettings_as_user "$user" "$uid" set "$schema" "$key" "$value" 2>/dev/null
}

# Create/append a GNOME app folder (same schema/mechanism as the Ubuntu
# script - org.gnome.desktop.app-folders is a GNOME Shell feature, entirely
# independent of the package manager underneath).
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

    # Resolve requested packages to actual .desktop file IDs. Same NoDisplay/
    # Hidden filtering logic as the Ubuntu script, using `rpm -ql` in place
    # of `dpkg -L` - rpm packages a .desktop file directly under the package
    # that owns it far more often than Debian's split-out -common/-runtime
    # convention, so the "walk the dependency tree" fallback matters less
    # here, but is kept for the rare meta-package case (e.g. "emacs").
    displayable_desktop_files() {
        local pkg="$1" f
        rpm -ql "$pkg" 2>/dev/null | grep -iE '/applications/.*\.desktop$' | while IFS= read -r f; do
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
                # Meta-package fallback: walk rpm's own dependency list (rpm
                # -q --requires) and check each for a displayable .desktop -
                # the rpm equivalent of the Ubuntu script's
                # `apt-cache depends --recurse --important` walk.
                local dep line2
                while IFS= read -r dep; do
                    [ -z "$dep" ] && continue
                    is_installed "$dep" || continue
                    while IFS= read -r line2; do [ -n "$line2" ] && found+=("$line2"); done < <(displayable_desktop_files "$dep")
                done < <(rpm -q --requires "$app" 2>/dev/null | awk '{print $1}' | grep -v '^rpmlib\|^/' | sort -u)
            fi
        fi
        # Flatpak-exported apps live in export dirs dpkg/rpm lookups never
        # see - system-wide under /var/lib/flatpak and per-user under
        # ~/.local/share/flatpak. Match on the launcher's own Name= (falling
        # back to filename), honoring NoDisplay/Hidden like every other stage.
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
    local f="/var/log/fedora_post_install_$(date +%Y%m%d_%H%M%S).log"
    {
        echo "=== Log: $(date) ==="; echo "User: $(whoami)"; echo "Fedora: ${FEDORA_VERSION:-unknown}"
        echo "Installed: ${TOTAL_INSTALLED}"; echo "Skipped: ${TOTAL_SKIPPED}"; echo "Failed: ${TOTAL_FAILED}"
        echo; echo "Installed packages:"; printf "  %s\n" "${INSTALLED_PACKAGES[@]}"
        echo; echo "Failed packages:"; printf "  %s\n" "${FAILED_PACKAGES[@]}"
    } > "$f"
    log INFO "Log saved to: $f"
}

# ========== CREATIVE SUITE (Ubuntu Studio replacement) ==========
# Fedora has no per-domain metapackages like ubuntustudio-video/audio/graphics/
# photography/publishing. The closest native equivalents are two real dnf5
# comps groups: Fedora Jam's "audio" group (a genuinely full DAW/synth/plugin
# stack - Ardour, Audacity, Carla, Hydrogen, Guitarix, LV2/LADSPA bundles) and
# "design-suite" (GIMP, Inkscape, Krita, Blender, Darktable, Scribus, digiKam,
# Synfig, Pitivi - already covers graphics AND most of photography/publishing
# in one pull). Video has no group at all, so it's hand-curated to mirror the
# Ubuntu script's install_video() package list. Photography/Publishing are
# kept as their own (smaller, non-overlapping-where-possible) picks so the
# sub-menu still has 6 meaningful choices, same shape as Ubuntu Studio's.
install_creative_audio() {
    log INFO "Installing Audio Production (Fedora Jam group)..."
    if dnf group install -y audio 2>/dev/null; then
        INSTALLED_PACKAGES+=("audio (Fedora Jam group)"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: Audio Production (Fedora Jam)"
    else
        FAILED_PACKAGES+=("audio (Fedora Jam group)"); ((TOTAL_FAILED++))
        log WARNING "Fedora Jam 'audio' group install failed - try: sudo dnf group install audio"
    fi
    # A few Ubuntu-Studio-audio staples the Jam group doesn't carry.
    batch_install "Audio Production (extra)" qjackctl pulseaudio-utils soundconverter easytag pavucontrol
    install_cliamp
}

# cliamp (https://www.cliamp.stream/) - terminal Winamp-style music player/
# streamer (Spotify/Qobuz/YouTube Music/Plex/Jellyfin/30,000+ radio stations).
# Not packaged for Fedora - vendor curl|sh installer fetches a prebuilt
# release binary (no Go/build deps needed) into ~/.local/bin, same shape as
# install_claude_code above.
install_cliamp() {
    local u="$SUDO_USER"; [ "$u" = "root" ] && u=""
    local check_cmd install_cmd
    if [ -n "$u" ]; then
        check_cmd="su - $u -c 'command -v cliamp'"
        install_cmd="su - $u -c 'curl -fsSL https://raw.githubusercontent.com/bjarneo/cliamp/HEAD/install.sh | sh'"
    else
        check_cmd="command -v cliamp"
        install_cmd="curl -fsSL https://raw.githubusercontent.com/bjarneo/cliamp/HEAD/install.sh | sh"
    fi
    if eval "$check_cmd" &>/dev/null; then
        SKIPPED_PACKAGES+=("cliamp"); ((TOTAL_SKIPPED++)); log INFO "Already installed: cliamp"; return 0
    fi
    log INFO "Installing CLIamp (terminal music player)..."
    if eval "$install_cmd" 2>/dev/null && eval "$check_cmd" &>/dev/null; then
        INSTALLED_PACKAGES+=("cliamp"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: cliamp (~/.local/bin - ensure it's on your PATH)"; return 0
    fi
    FAILED_PACKAGES+=("cliamp"); ((TOTAL_FAILED++))
    log WARNING "CLIamp install failed - try: curl -fsSL https://raw.githubusercontent.com/bjarneo/cliamp/HEAD/install.sh | sh"; return 0
}

install_creative_graphics() {
    log INFO "Installing Graphics & Design (Design Suite group)... (large transaction, texlive-latex is multi-GB - this can take a while)"
    if dnf group install -y design-suite; then
        INSTALLED_PACKAGES+=("design-suite (Design Suite group)"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: Graphics & Design (Design Suite)"
    else
        FAILED_PACKAGES+=("design-suite (Design Suite group)"); ((TOTAL_FAILED++))
        log WARNING "Design Suite group install failed - try: sudo dnf group install design-suite"
    fi
    batch_install "Graphics (extra)" nomacs flameshot ImageMagick GraphicsMagick optipng jpegoptim pngquant libwebp-tools
    set_flameshot_hotkey
}

install_creative_video() {
    batch_install "Video Editing" \
        kdenlive shotcut obs-studio mkvtoolnix mkvtoolnix-gui mpv vlc yt-dlp
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

# Bind Print Screen to Flameshot (same GNOME keybinding merge/replace logic as
# the Ubuntu script - a gsettings feature, not a package-manager one).
set_flameshot_hotkey() {
    if ! command -v flameshot &>/dev/null; then
        log INFO "Flameshot not installed - skipping Print Screen keybinding"; return 0
    fi
    local user uid
    if ! read -r user uid < <(resolve_desktop_session); then
        log INFO "No desktop session - skipping Flameshot keybinding (bind Print to 'flameshot gui' later)"; return 0
    fi
    gset_if_exists "$user" "$uid" org.gnome.shell.keybindings show-screenshot-ui "[]" || true
    gset_if_exists "$user" "$uid" org.gnome.settings-daemon.plugins.media-keys screenshot "[]" || true

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

# ========== MULTIMEDIA CODECS ==========
# The ffmpeg-free -> ffmpeg swap and GStreamer "ugly/bad/libav" plugin tiers
# are what actually unlock real-world H.264/AAC/MP3/AC3 playback - stock
# Fedora ships only the patent-safe ffmpeg-free by default, same reasoning as
# Ubuntu shipping GStreamer/VLC without ugly/bad by default. Requires RPM
# Fusion (bootstrap_repos) to already be enabled.
install_multimedia_codecs() {
    log INFO "Installing multimedia codecs (RPM Fusion + OpenH264)..."
    if package_exists ffmpeg; then
        if dnf swap -y ffmpeg-free ffmpeg --allowerasing 2>/dev/null; then
            INSTALLED_PACKAGES+=("ffmpeg (swap)"); ((TOTAL_INSTALLED++)); log SUCCESS "Swapped ffmpeg-free -> ffmpeg"
        else
            FAILED_PACKAGES+=("ffmpeg (swap)"); ((TOTAL_FAILED++)); log WARNING "ffmpeg swap failed - needs RPM Fusion enabled"
        fi
    fi
    batch_install "GStreamer plugins" \
        gstreamer1-plugins-good gstreamer1-plugins-bad-free gstreamer1-plugins-bad-freeworld \
        gstreamer1-plugins-ugly gstreamer1-plugins-ugly-free gstreamer1-plugin-libav
    batch_install "OpenH264" openh264 gstreamer1-plugin-openh264 mozilla-openh264
}

# ========== NVIDIA DRIVER (new - no Ubuntu-script equivalent) ==========
# Opt-in only: this is real hardware-specific state, not a package a user can
# just skip on the wrong GPU. Installs from RPM Fusion nonfree, then POLLS for
# the akmod build to finish instead of assuming it's done the instant `dnf
# install` returns - RPM Fusion's own docs say the kernel-module build can
# take a few minutes in the background. Secure Boot MOK enrollment is a
# genuinely interactive, hardware-firmware-level step (needs a mid-flow
# reboot into a blue MOKManager screen) - this function prints the exact
# commands and STOPS there rather than pretending to automate it.
#
# akmod-nvidia-open (NOT plain akmod-nvidia) is used deliberately: Blackwell-
# generation cards (RTX 50 / RTX PRO Blackwell) have NO proprietary-branch
# support at all - the closed kernel module cannot initialize that hardware,
# only the open-source one can - and NVIDIA's own driver packages have been
# defaulting to open modules for Turing-and-newer GPUs generally, so this is
# the current mainstream path, not a Blackwell-only special case. Runs an
# explicit `akmods --force` so the build is triggered immediately rather than
# relying solely on akmod's own background trigger. Deliberately does NOT
# auto-reboot for you - same reasoning as the Secure Boot step below: a
# reboot here is a decision point, not something to fire blindly.
install_nvidia_driver() {
    if ! is_installed rpmfusion-nonfree-release; then
        log WARNING "RPM Fusion nonfree isn't enabled - run bootstrap first"; return 1
    fi
    local msg="Install the NVIDIA driver (akmod-nvidia-open + CUDA)?\n\nOpen kernel modules, not the legacy closed ones - required for Blackwell (RTX 50/RTX PRO) and the current default for Turing-and-newer GPUs generally. Only do this on a machine with an NVIDIA GPU. The kernel module is compiled in the background after install and can take a few minutes."
    local do_it=false
    if command -v whiptail &>/dev/null; then
        whiptail --yesno "$msg" --yes-button "Install" --no-button "Skip" 14 76 && do_it=true
    else
        echo -e "$msg [y/N]:"
        read -r REPLY
        { [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; } && do_it=true
    fi
    if ! $do_it; then
        SKIPPED_PACKAGES+=("akmod-nvidia-open"); ((TOTAL_SKIPPED++)); log INFO "Skipped NVIDIA driver"; return 0
    fi

    batch_install "NVIDIA Driver" akmod-nvidia-open xorg-x11-drv-nvidia-cuda

    if is_installed akmod-nvidia-open; then
        log INFO "Forcing the akmod build now (akmods --force)..."
        akmods --force 2>/dev/null

        log INFO "Waiting for the akmod kernel module to finish building (up to a few minutes)..."
        local waited=0
        while [ $waited -lt 300 ]; do
            if modinfo -F version nvidia &>/dev/null; then
                log SUCCESS "NVIDIA kernel module built ($(modinfo -F version nvidia 2>/dev/null))"
                break
            fi
            sleep 10; waited=$((waited+10))
        done
        [ $waited -ge 300 ] && log WARNING "akmod build still not done after 5 minutes - check later with: akmods --status"

        if mokutil --sb-state 2>/dev/null | grep -qi "enabled"; then
            log WARNING "Secure Boot is ON - the NVIDIA kernel module won't load until its key is enrolled."
            log WARNING "This needs an interactive reboot into MOKManager and CANNOT be automated by this script. Run manually:"
            log WARNING "  sudo kmodgenca -a"
            log WARNING "  sudo mokutil --import /etc/pki/akmods/certs/public_key.der   (sets an enrollment password)"
            log WARNING "  sudo systemctl reboot   (blue MOKManager screen -> Enroll MOK -> Continue -> Yes -> enter password)"
        else
            log INFO "Secure Boot is off/not detected - reboot when convenient to load the new kernel module: sudo reboot"
        fi
        log INFO "Verify after reboot with: nvidia-smi"
    fi
}

# ========== TERRA REPO (Ultramarine-Linux substitute) ==========
# Ultramarine Linux itself has no addable repo for stock Fedora - it's a full
# spin/image. Its parent project, Fyra Labs, publishes Terra instead: a
# general-purpose repo explicitly designed to layer onto any Fedora system,
# which is the practical way to get "Ultramarine's extras" without an OS swap.
# Deliberately scoped to terra-release-extras ONLY (patched apps/tools) - NOT
# terra-release-mesa or terra-release-nvidia, which Terra's own docs say
# conflict with RPM Fusion's Mesa/NVIDIA packages, and RPM Fusion is this
# script's default driver/codec path (see bootstrap_repos/install_nvidia_driver).
# Opt-in, since it's an extra third-party repo, not something every install needs.
install_terra_repo() {
    if is_installed terra-release; then
        SKIPPED_PACKAGES+=("terra-release"); ((TOTAL_SKIPPED++)); log INFO "Already installed: terra-release"; return 0
    fi
    local msg="Enable the Terra repo (repos.fyralabs.com)?\n\nAdds Ultramarine Linux's parent-project repo for extra/patched apps not in Fedora or RPM Fusion. Only the 'extras' subrepo is enabled - NOT its alternate Mesa/NVIDIA builds, which conflict with RPM Fusion's."
    local do_it=false
    if command -v whiptail &>/dev/null; then
        whiptail --yesno "$msg" --yes-button "Enable" --no-button "Skip" 12 76 && do_it=true
    else
        echo -e "$msg [y/N]:"
        read -r REPLY
        { [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; } && do_it=true
    fi
    if ! $do_it; then
        SKIPPED_PACKAGES+=("terra-release"); ((TOTAL_SKIPPED++)); log INFO "Skipped Terra repo"; return 0
    fi
    log INFO "Enabling Terra repo..."
    if dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release terra-gpg-keys 2>/dev/null \
        && is_installed terra-release; then
        INSTALLED_PACKAGES+=("terra-release"); ((TOTAL_INSTALLED++))
        safe_install terra-release-extras
        log SUCCESS "Terra repo enabled (extras subrepo only)"
    else
        FAILED_PACKAGES+=("terra-release"); ((TOTAL_FAILED++)); log WARNING "Terra repo setup failed"
    fi
}

# ========== DISPLAYLINK DRIVER ==========
# DisplayLink (USB/dock-connected display adapters, DL-3xxx through DL-7xxx
# chipsets) has no Fedora/RPM Fusion package - displaylink-rpm is the
# community project that builds it and, more usefully for us, publishes
# prebuilt per-Fedora-version RPMs as GitHub release assets (fedora-<ver>-
# displaylink-*.<arch>.rpm) - no local rpmbuild/DKMS toolchain or the
# proprietary vendor zip download needed. `dnf install ./file.rpm` resolves
# the RPM's own Requires (dkms, kernel-devel, etc) against Fedora's normal
# repos, and its %post scriptlet does the dkms add/build/install and starts
# displaylink-driver.service itself - nothing left for us to do afterward
# except flag Secure Boot, same as install_nvidia_driver's akmod case.
install_displaylink_driver() {
    if is_installed displaylink; then
        SKIPPED_PACKAGES+=("displaylink"); ((TOTAL_SKIPPED++)); log INFO "Already installed: displaylink"; return 0
    fi
    local msg="Install the DisplayLink driver (USB/dock display adapters)?\n\nDKMS-built evdi kernel module + DisplayLinkManager, for DL-3xxx through DL-7xxx chipset docking stations and USB monitors/adapters. Only useful if you actually have DisplayLink hardware."
    local do_it=false
    if command -v whiptail &>/dev/null; then
        whiptail --yesno "$msg" --yes-button "Install" --no-button "Skip" 14 76 && do_it=true
    else
        echo -e "$msg [y/N]:"
        read -r REPLY
        { [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; } && do_it=true
    fi
    if ! $do_it; then
        SKIPPED_PACKAGES+=("displaylink"); ((TOTAL_SKIPPED++)); log INFO "Skipped DisplayLink driver"; return 0
    fi

    local arch; arch=$(uname -m)
    local ver="${FEDORA_VERSION:-$(rpm -E %fedora)}"
    log INFO "Looking up the latest displaylink-rpm release for Fedora $ver ($arch)..."
    local url
    url=$(curl -fsSL "https://api.github.com/repos/displaylink-rpm/displaylink-rpm/releases/latest" 2>/dev/null \
        | grep -oP '"browser_download_url":\s*"\K[^"]*fedora-'"$ver"'-displaylink[^"]*\.'"$arch"'\.rpm(?=")')
    if [ -z "$url" ]; then
        FAILED_PACKAGES+=("displaylink"); ((TOTAL_FAILED++))
        log WARNING "No prebuilt displaylink-rpm release for Fedora $ver ($arch) yet - check https://github.com/displaylink-rpm/displaylink-rpm/releases and build from source manually if needed"
        return 1
    fi

    local t; t=$(mktemp -d)
    log INFO "Downloading DisplayLink driver RPM..."
    if ! curl -fL --retry 3 -o "$t/displaylink.rpm" "$url" 2>/dev/null; then
        rm -rf "$t"; FAILED_PACKAGES+=("displaylink"); ((TOTAL_FAILED++))
        log WARNING "DisplayLink driver download failed (needs network access to github.com)"; return 1
    fi
    log INFO "Installing DisplayLink driver (builds the evdi DKMS module - may take a minute)..."
    if dnf install -y "$t/displaylink.rpm" 2>/dev/null && is_installed displaylink; then
        INSTALLED_PACKAGES+=("displaylink"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: DisplayLink driver"
        if mokutil --sb-state 2>/dev/null | grep -qi "enabled"; then
            log WARNING "Secure Boot is ON - the evdi kernel module won't load until its DKMS-generated key is enrolled."
            log WARNING "  sudo mokutil --import /var/lib/dkms/mok.pub   (sets an enrollment password, needs a reboot into MOKManager)"
            log WARNING "  after reboot: sudo dkms autoinstall && sudo systemctl reboot"
        fi
    else
        FAILED_PACKAGES+=("displaylink"); ((TOTAL_FAILED++))
        log WARNING "DisplayLink driver install failed - check the dkms build log at /var/log/displaylink/displaylink.log"
    fi
    rm -rf "$t"
}

# ========== DRIVERS & EXTRA REPOS (new - no Ubuntu-script equivalent) ==========
install_drivers_and_repos() {
    install_nvidia_driver
    install_terra_repo
    install_displaylink_driver
}

# ========== PERIPHERALS (new - no Ubuntu-script equivalent) ==========
# Solaar talks HID++ directly to Logitech peripherals (over a Bolt/Unifying
# receiver OR native Bluetooth) - a different layer from logid/LogiOps (if
# installed - button/gesture remapping) and from libinput (OS-side scroll
# interpretation). It's needed here because at least one MX-series mouse
# (MX Anywhere 3S, confirmed on this hardware) ships with its on-device HID++
# "Scroll Wheel Resolution" feature OFF by default over Bluetooth. That
# produces genuinely slow-but-smooth scrolling - not a libinput bug, not a
# logid conflict, not a GNOME setting - so no OS-side fix touches it; only
# flipping this on-device flag does.
#
# Opt-in and interactive, same shape as install_nvidia_driver/install_terra_repo:
# this is one specific mouse's firmware state, not something every install
# needs, and it can only be applied to a device that's actually paired/
# connected at the time this runs (very possibly not true yet on a fresh
# install - see fix_logitech_hires_scroll below).
install_peripheral_tools() {
    batch_install "Peripheral Management" solaar solaar-udev
    if is_installed solaar; then
        log INFO "Solaar installed - GUI: 'solaar', CLI: 'solaar config' for battery/DPI/gesture/scroll-feature control of Logitech HID++ mice and keyboards"
    fi
}

# Applies the specific fix confirmed on this hardware: MX Anywhere 3S over
# Bluetooth with its "Scroll Wheel Resolution" HID++ feature disabled.
# `solaar config <device> hires-smooth-resolution 1` flips that feature ON
# THE MOUSE ITSELF - it's a device-side flag, so it persists across reboots
# and reconnects without Solaar needing to keep running (confirmed stable
# after restarting logid on this setup, so the two don't fight over it here).
#
# PACKAGE/CLI CONFIDENCE NOTE: the setting name "hires-smooth-resolution" and
# the "solaar config <device> <setting> <value>" form are taken from a
# published fix for the same symptom on a different MX-series mouse (MX
# Master 2S) - not independently verified against `solaar config --help` on
# this exact Solaar version. If it errors below, run
# `solaar config "MX Anywhere 3S"` with no value to list that device's real
# setting names before assuming the fix itself is wrong.
#
# Device name is hardcoded to "MX Anywhere 3S" deliberately rather than
# auto-parsed from `solaar show` output (that output's exact grammar wasn't
# verified either, and a wrong parse fails silently - a wrong hardcoded name
# fails loudly, which is safer for something this narrowly targeted). Update
# the name below if this mouse is ever replaced.
fix_logitech_hires_scroll() {
    local device_name="MX Anywhere 3S"

    if ! command -v solaar &>/dev/null; then
        log INFO "Solaar not installed - installing it first..."
        install_peripheral_tools
    fi
    if ! command -v solaar &>/dev/null; then
        log ERROR "Solaar install failed - cannot apply the scroll fix"
        return 1
    fi

    if ! solaar show 2>/dev/null | grep -qi "$device_name"; then
        log WARNING "'$device_name' not seen by Solaar - pair/connect it first (Bluetooth Settings), then re-run this from the Peripherals menu"
        return 1
    fi

    if solaar config "$device_name" hires-smooth-resolution 1 2>/dev/null; then
        log SUCCESS "Enabled 'Scroll Wheel Resolution' on $device_name"
        log INFO "Stored on the mouse itself - no reboot needed, test scrolling now"
    else
        log WARNING "'solaar config \"$device_name\" hires-smooth-resolution 1' failed - run: solaar config \"$device_name\"  (no value) to list its actual setting names, the CLI name may differ on your Solaar version"
        return 1
    fi
}

# ========== PRINTERS (new - no Ubuntu-script equivalent) ==========
# CUPS + HPLIP cover the open-source rendering path for most printers, but
# several HP models - especially older "host-based" LaserJets/inkjets like
# the LaserJet P1006/P1005/P1018 - also need a proprietary HP-supplied plugin
# for actual rasterization. Without it, jobs sit in the queue and silently
# fail with "hplip.plugin-error" / "m_Job initialization failed with error =
# 48" in /var/log/cups/error_log, with no obvious error surfaced to the user
# (confirmed directly against a real LaserJet P1006 - jobs looked "queued"
# forever with no error dialog anywhere).
install_printer_support() {
    batch_install "Printer Support" cups hplip system-config-printer
    systemctl enable --now cups.service &>/dev/null || true
}

# hp-plugin's installed/not-installed state lives in /var/lib/hp/hplip.state
# under a [plugin] section - only run the (interactive, license-accepting)
# installer if it isn't already recorded there. Only prompted when an HP
# device is actually detected (CUPS's discovered devices, or the USB vendor
# ID 03f0) - most printers don't need this at all, so there's no reason to
# bother everyone else with an interactive EULA + download.
install_hp_plugin() {
    if ! command -v hp-plugin &>/dev/null; then
        log INFO "hplip not installed yet - installing printer support first..."
        install_printer_support
    fi
    if ! lpinfo -v 2>/dev/null | grep -qi "hp\|hewlett" && ! lsusb 2>/dev/null | grep -qi "03f0"; then
        log WARNING "No HP printer detected (USB or CUPS-discovered) - plug it in first, then run this again."
        return 1
    fi
    if grep -qx "installed = 1" /var/lib/hp/hplip.state 2>/dev/null; then
        log SUCCESS "HP proprietary plugin already installed."
        return 0
    fi
    log INFO "Running hp-plugin - accept the download and license prompts to install HP's proprietary plugin (needed by several older LaserJet/inkjet models)."
    hp-plugin -i
}

# ========== FILESYSTEM SNAPSHOTS & BACKUP (new - no Ubuntu-script equivalent) ==========
# Fedora Workstation defaults to Btrfs since F33+, but unlike openSUSE it does
# NOT wire Snapper into dnf5 out of the box, and there's no automatic
# pre-transaction snapshot the way this script's own driver-install functions
# (NVIDIA, above) could really use as a safety net. Fedora's own fix for that -
# "BtrfsWithFullSystemSnapshots" (snapm/boom) - is a Change proposal targeted
# at Fedora 45, not shipped as of this writing, and python3-dnf-plugin-snapper
# is a dnf4/dnf-plugins-extras package whose dnf5 hook support is unconfirmed
# per multiple open Fedora Discussion threads. So this installs and enables
# the pieces that DO work reliably today regardless of that gap: Snapper's own
# timeline/cleanup timers (independent of dnf entirely), btrfs-assistant as
# the GUI (official Fedora repo package, not a COPR), and grub-btrfs (COPR -
# not upstream Fedora) to surface snapshots as bootable GRUB entries - and
# attempts the dnf hook as a bonus on top, not as the thing you should rely on.
# On non-Btrfs roots (ext4/xfs - e.g. custom partitioning at install time),
# Snapper doesn't apply at all, so Timeshift is used instead (official Fedora
# package, rsync-mode GUI+CLI backup, no filesystem-specific requirement).
#
# PACKAGE NAME CONFIDENCE NOTE: snapper, btrfs-assistant and timeshift were
# verified against packages.fedoraproject.org / fedora.pkgs.org during
# development. The grub-btrfs COPR is NOT upstream Fedora and ownership is
# unverified beyond a web search turning up kylegospo/grub-btrfs as one
# actively-referenced option among a few (pego-copr/grub-btrfs, theoware/
# grub-btrfs) - if it's empty or stale for your release, swap the coordinates
# in install_snapshots_btrfs() below. add_copr's existing failure handling
# (non-fatal, logged, continues) covers a wrong guess either way.

detect_root_fstype() {
    findmnt -no FSTYPE / 2>/dev/null
}

install_snapshots_full() {
    local fstype; fstype=$(detect_root_fstype)
    log INFO "Detected root filesystem: ${fstype:-unknown}"
    if [ "$fstype" = "btrfs" ]; then
        install_snapshots_btrfs
    else
        log WARNING "Root is not Btrfs (detected: ${fstype:-unknown}) - Snapper needs Btrfs, falling back to Timeshift (rsync mode)"
        install_snapshots_timeshift
    fi
}

install_snapshots_btrfs() {
    batch_install "Snapshots (Snapper + GUI)" snapper btrfs-assistant

    if is_installed snapper; then
        if ! snapper list-configs 2>/dev/null | grep -qw root; then
            log INFO "Creating Snapper config 'root' for /..."
            if snapper -c root create-config / 2>/dev/null; then
                log SUCCESS "Snapper config 'root' created"
            else
                log WARNING "Snapper config creation failed - your subvolume layout may need manual setup: sudo snapper -c root create-config /"
            fi
        else
            log INFO "Snapper config 'root' already exists"
        fi
        # Ships inside the snapper package itself - just needs enabling.
        if systemctl enable --now snapper-timeline.timer snapper-cleanup.timer 2>/dev/null; then
            log SUCCESS "Enabled snapper-timeline.timer + snapper-cleanup.timer (scheduled snapshots + retention)"
        else
            log WARNING "Could not enable snapper timers - enable manually: sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer"
        fi
    fi

    # Boot-menu integration: lets you boot straight into a pre-change snapshot
    # from GRUB if something goes wrong, without a live USB. See COPR note above.
    add_copr "kylegospo/grub-btrfs" grub-btrfs
    batch_install "Snapshots (GRUB boot entries)" grub-btrfs
    if is_installed grub-btrfs; then
        # NOTE: the daemon is grub-btrfs.path (triggers regen on snapshot
        # changes), NOT "grub-btrfsd" - that name doesn't exist in the
        # upstream package despite appearing in upstream's own docs prose;
        # verified against the actual installed unit files. grub-btrfs.service
        # itself is "static" (systemd-speak for "triggered, not enabled
        # directly") - enabling the .path unit is what you want.
        #
        # The shipped grub-btrfs.path unit hardcodes Requires=/After=/
        # BindsTo=/WantedBy= a phantom "-.snapshots.mount" unit - an
        # openSUSE-style assumption that /.snapshots is its OWN mounted
        # subvolume. Fedora's own `snapper create-config` creates .snapshots
        # as a plain nested subvolume inside the SAME root mount instead, so
        # that mount unit never exists here and enabling the unit as shipped
        # fails ("Unit \x2esnapshots.mount not found."). Verified directly
        # against `systemctl cat grub-btrfs.path` output during development.
        # Fix: only if /.snapshots ISN'T its own mount (the Fedora-default
        # case), fully SHADOW the vendor unit with a local file in
        # /etc/systemd/system/ (same name - systemd's own precedence rule
        # means the local file wins outright, no merge involved). A .path.d
        # drop-in that tries to clear Requires=/After=/BindsTo= with empty
        # assignments was tried first and did NOT reliably take effect in
        # testing (Install-section override worked, Unit-section did not) -
        # a full local override removes that ambiguity entirely rather than
        # relying on list-clearing semantics that didn't hold up here.
        if ! findmnt -no TARGET /.snapshots &>/dev/null; then
            rm -f /etc/systemd/system/grub-btrfs.path.d/override.conf
            rmdir /etc/systemd/system/grub-btrfs.path.d 2>/dev/null
            cat > /etc/systemd/system/grub-btrfs.path <<'GBTRFS_OVERRIDE_EOF'
[Unit]
Description=Monitors for new snapshots
DefaultDependencies=no

[Path]
PathModified=/.snapshots

[Install]
WantedBy=multi-user.target
GBTRFS_OVERRIDE_EOF
            systemctl daemon-reload
        fi

        if systemctl enable --now grub-btrfs.path 2>/dev/null; then
            log SUCCESS "Enabled grub-btrfs.path (snapshots now trigger a GRUB regen automatically)"
        else
            log WARNING "Could not enable grub-btrfs.path - enable manually: sudo systemctl enable --now grub-btrfs.path"
        fi
    fi

    # Best-effort only: auto-snapshot on every dnf transaction. NOT guaranteed
    # to actually hook dnf5 - see the section comment above. If it doesn't,
    # the timeline timer enabled above still gives you snapshots regardless.
    if package_exists python3-dnf-plugin-snapper; then
        safe_install python3-dnf-plugin-snapper
        log INFO "Installed the dnf-snapper plugin - dnf5 hook support is unconfirmed on this release; the timeline timer above is your reliable fallback either way"
    fi

    if is_installed snapper; then
        log INFO "Taking an initial baseline snapshot..."
        if snapper -c root create --description "post-install baseline" 2>/dev/null; then
            log SUCCESS "Baseline snapshot created (sudo snapper -c root list to view)"
        else
            log WARNING "Baseline snapshot failed - fix the 'root' config first, then retry"
        fi
    fi
}

install_snapshots_timeshift() {
    batch_install "Snapshots (Timeshift)" timeshift
    if is_installed timeshift; then
        log INFO "Timeshift installed - first run needs interactive setup (pick rsync mode + snapshot destination disk), this script won't guess your disk layout for you"
        log INFO "Configure it with: sudo timeshift-gtk (GUI) or sudo timeshift --create (CLI)"
    fi
}

# Ad-hoc snapshot, callable any time from the Snapshots submenu - useful
# right before something risky (a driver install, a risky dnf transaction).
snapshot_create_now() {
    local fstype; fstype=$(detect_root_fstype)
    if [ "$fstype" = "btrfs" ] && command -v snapper &>/dev/null; then
        if snapper -c root create --description "manual $(date +%Y-%m-%d_%H:%M)" 2>/dev/null; then
            log SUCCESS "Snapshot created - sudo snapper -c root list to view"
        else
            log ERROR "snapper create failed - is the 'root' config set up yet? (Full Setup, option 1, does this)"
        fi
    elif command -v timeshift &>/dev/null; then
        if timeshift --create --comments "manual $(date +%Y-%m-%d_%H:%M)" 2>/dev/null; then
            log SUCCESS "Snapshot created - timeshift --list to view"
        else
            log ERROR "timeshift --create failed - has it been configured yet? (run timeshift-gtk once first)"
        fi
    else
        log WARNING "No snapshot tool installed yet - run Full Setup first (option 1)"
    fi
    read -p "$(printf "${DIM}${SUBTEXT}  Press [Enter] to continue…${NC}")" _
}

snapshot_list() {
    local fstype; fstype=$(detect_root_fstype)
    if [ "$fstype" = "btrfs" ] && command -v snapper &>/dev/null; then
        snapper -c root list 2>/dev/null || log WARNING "snapper list failed - config 'root' may not exist yet"
    elif command -v timeshift &>/dev/null; then
        timeshift --list 2>/dev/null || log WARNING "timeshift --list failed - not configured yet"
    else
        log WARNING "No snapshot tool installed yet - run Full Setup first (option 1)"
    fi
    read -p "$(printf "${DIM}${SUBTEXT}  Press [Enter] to continue…${NC}")" _
}

# Launches whichever GUI actually got installed, in the desktop user's own
# session (same resolve_desktop_session mechanism used for GNOME app folders/
# Flameshot above) - both tools escalate privilege themselves via polkit when
# needed, so this deliberately does NOT run them as root.
snapshot_open_gui() {
    local user uid
    if ! read -r user uid < <(resolve_desktop_session); then
        log WARNING "No active GNOME session detected - launch the GUI yourself: btrfs-assistant or timeshift-gtk"
        return 1
    fi
    local home; home=$(getent passwd "$user" | cut -d: -f6)
    if command -v btrfs-assistant &>/dev/null; then
        sudo -u "$user" HOME="$home" XDG_RUNTIME_DIR="/run/user/${uid}" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
            nohup btrfs-assistant >/dev/null 2>&1 &
        log SUCCESS "Launched Btrfs Assistant"
    elif command -v timeshift-gtk &>/dev/null; then
        sudo -u "$user" HOME="$home" XDG_RUNTIME_DIR="/run/user/${uid}" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
            nohup timeshift-gtk >/dev/null 2>&1 &
        log SUCCESS "Launched Timeshift GUI"
    else
        log WARNING "No snapshot GUI installed yet - run Full Setup first (option 1)"
        return 1
    fi
    sleep 1
}

# ========== CODE EDITORS ==========
install_code_editors() {
    # gnome-text-editor replaces gedit as GNOME's default text editor since
    # GNOME 42 - both are listed since some Fedora releases still carry gedit.
    batch_install "Code Editors" vim-enhanced neovim emacs nano geany gnome-text-editor gedit kate
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

# Identical to the Ubuntu script's version - git clone + Nordic theme drop-in,
# nothing package-manager-specific here except the neovim self-heal.
install_lazyvim() {
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

# VS Code from Microsoft's official yum repo - same vendor, same key, just the
# yum/rpm variant of the Ubuntu script's apt repo (packages.microsoft.com
# hosts both). Package is "code" (ships code.desktop).
install_vscode() {
    if command -v code &>/dev/null || is_installed code; then
        SKIPPED_PACKAGES+=("code"); ((TOTAL_SKIPPED++)); log INFO "VS Code already installed"; return 0
    fi
    log INFO "Installing VS Code (Microsoft's official yum repo)..."
    rpm --import https://packages.microsoft.com/keys/microsoft.asc 2>/dev/null
    dnf config-manager addrepo --id=vscode --save-filename=vscode.repo \
        --set=name="Visual Studio Code" \
        --set=baseurl=https://packages.microsoft.com/yumrepos/vscode \
        --set=enabled=1 --set=gpgcheck=1 \
        --set=gpgkey=https://packages.microsoft.com/keys/microsoft.asc \
        --overwrite 2>/dev/null
    pm_update
    safe_install code
}

# Sublime Text from its official rpm repo (download.sublimetext.com/rpm) -
# same vendor as the Ubuntu apt path, rpm variant.
install_sublime_text() {
    if command -v subl &>/dev/null || is_installed sublime-text; then
        SKIPPED_PACKAGES+=("sublime-text"); ((TOTAL_SKIPPED++)); log INFO "Sublime Text already installed"; return 0
    fi
    log INFO "Installing Sublime Text (official rpm repo)..."
    rpm -v --import https://download.sublimetext.com/sublimehq-rpm-pub.gpg 2>/dev/null
    dnf config-manager addrepo --from-repofile=https://download.sublimetext.com/rpm/stable/x86_64/sublime-text.repo 2>/dev/null \
        || dnf config-manager --add-repo https://download.sublimetext.com/rpm/stable/x86_64/sublime-text.repo 2>/dev/null
    pm_update
    safe_install sublime-text
}

# Bruno API client - no rpm/COPR from usebruno.com, only Flatpak/AppImage/Snap
# officially, so Flathub is the correct (not a compromise) choice here.
install_bruno() { flatpak_install_flathub com.usebruno.Bruno "Bruno"; }

# ========== PYTHON ==========
install_python() {
    # Fedora Workstation ships python3 by default; python3-pip/virtualenv are
    # the closest equivalents to the Ubuntu list (no "python-is-python3"
    # package needed - Fedora's python3 IS the system python, no separate
    # /usr/bin/python shim to bridge).
    batch_install "Python" python3 python3-devel python3-pip python3-virtualenv ipython pipx
}

# ========== WEB DEVELOPMENT ==========
install_web_dev() {
    install_nodejs_full
    batch_install "Web Server - Nginx" nginx
    # httpd (Apache) is installed for availability but not enabled/started -
    # nginx owns :80. Unlike Debian's maintainer scripts, RPM %post scriptlets
    # don't auto-start services on install, so there's no Ubuntu-style
    # policy-rc.d workaround needed here - `dnf install httpd` alone never
    # starts it.
    batch_install "Web Server - Apache (not started)" httpd php-fpm php-cli composer
}

# Node.js ships natively in Fedora's own repos at a current version - unlike
# Ubuntu, no NodeSource repo is needed at all.
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

# ========== JAVA ==========
install_java() {
    batch_install "Java" java-latest-openjdk java-latest-openjdk-devel gradle maven ant junit
    # IntelliJ IDEA Community has no Fedora/RPM Fusion package - Flathub is
    # the real equivalent of the Ubuntu script's snap (verified: a dedicated
    # app exists, distinct from JetBrains Toolbox).
    flatpak_install_flathub com.jetbrains.IntelliJ-IDEA-Community "IntelliJ IDEA Community"
}

# ========== C/C++ ==========
install_c_cpp() {
    batch_install "C/C++" \
        gcc gcc-c++ gcc-gfortran clang cmake make ninja-build ccache \
        autoconf automake libtool m4 bison flex gettext pkgconf-pkg-config \
        cppcheck valgrind gdb ltrace strace
}

# ========== GO ==========
install_go() {
    if command -v go &>/dev/null; then
        SKIPPED_PACKAGES+=("golang"); ((TOTAL_SKIPPED++)); log INFO "Go already installed"; return 0
    fi
    if package_exists golang; then
        batch_install "Go" golang
    else
        log INFO "golang not in repos - installing latest upstream tarball to /usr/local/go..."
        local ver="1.22.5" arch; arch=$(uname -m)
        case "$arch" in x86_64) arch="amd64";; aarch64) arch="arm64";; esac
        local t; t=$(mktemp -d)
        if curl -fsSL "https://go.dev/dl/go${ver}.linux-${arch}.tar.gz" -o "$t/go.tar.gz" 2>/dev/null; then
            rm -rf /usr/local/go && tar -C /usr/local -xzf "$t/go.tar.gz"
            ln -sf /usr/local/go/bin/go /usr/local/bin/go
            ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
            INSTALLED_PACKAGES+=("golang"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: Go ${ver} (/usr/local/go)"
        else
            FAILED_PACKAGES+=("golang"); ((TOTAL_FAILED++)); log WARNING "Go tarball download failed"
        fi
        rm -rf "$t"
    fi
}

# ========== RUST ==========
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
    log INFO "Falling back to distro rust/cargo packages..."
    batch_install "Rust" rust cargo
}

# ========== PHP ==========
install_php() {
    batch_install "PHP" \
        php-cli php-fpm php-devel php-pear php-mysqlnd php-pgsql php-pdo \
        php-gd php-curl php-mbstring php-xml php-zip composer
}

# ========== RUBY ==========
install_ruby() {
    batch_install "Ruby" ruby ruby-devel rubygem-bundler
}

# ========== .NET ==========
# Ships natively in Fedora's own repos - no Microsoft repo needed at all
# (mixing Microsoft's repo with Fedora's own dotnet packages is explicitly
# discouraged upstream), unlike the Ubuntu script's packages.microsoft.com dance.
install_dotnet() {
    batch_install ".NET" dotnet-sdk-9.0 dotnet-sdk-8.0 aspnetcore-runtime-9.0
}

# ========== GENERAL DEV TOOLS ==========
install_dev_tools() {
    batch_install "Dev Tools" \
        jq tig subversion make cmake \
        autoconf automake bison flex gettext pkgconf-pkg-config man-db man-pages less
    install_bruno
}

# ========== DATABASES ==========
install_databases() {
    # Fedora's own repos ship MariaDB as the default MySQL-compatible server
    # (there's no plain "mysql-server" package the way Ubuntu has one -
    # Oracle's real MySQL is only "community-mysql-server", a separate
    # package). MariaDB is what the Ubuntu script's mysql-server users
    # actually want in practice - a MySQL-protocol-compatible server, not
    # specifically Oracle's build.
    batch_install "Databases" mariadb-server mariadb sqlite sqlitebrowser memcached
    # Fedora dropped the "redis" package starting Fedora 40 (Redis's license
    # moved off OSI terms) in favor of Valkey, the Linux Foundation's
    # redis-protocol-compatible fork - this IS the current Fedora path, not a
    # downgrade.
    batch_install "Valkey (Redis-compatible)" valkey
    # PostgreSQL needs an explicit initdb step on Fedora/RHEL-family systems -
    # Debian's postgresql-common package does this automatically on install,
    # RPM's postgresql-server package deliberately does not.
    if package_exists postgresql-server; then
        batch_install "PostgreSQL" postgresql-server postgresql
        if is_installed postgresql-server && [ ! -d /var/lib/pgsql/data ]; then
            log INFO "Initializing PostgreSQL database cluster..."
            /usr/bin/postgresql-setup --initdb 2>/dev/null \
                && systemctl enable --now postgresql 2>/dev/null \
                && log SUCCESS "PostgreSQL initialized and started" \
                || log WARNING "postgresql-setup --initdb failed - initialize manually"
        fi
    fi
    install_dbeaver
}

# DBeaver CE - no vendor rpm repo exists (dbeaver.io only ships a Debian apt
# repo, a standalone rpm, and Snap/Flathub which DBeaver Corporation itself
# says it doesn't support) - the community COPR is the best real option.
install_dbeaver() {
    if is_installed dbeaver-ce; then
        SKIPPED_PACKAGES+=("dbeaver-ce"); ((TOTAL_SKIPPED++)); log INFO "Already installed: dbeaver-ce"; return 0
    fi
    log INFO "Installing DBeaver CE (via COPR)..."
    add_copr "copart/dbeaver" copart
    batch_install "DBeaver" dbeaver-ce
}

# ========== CONTAINERS & VMS ==========
install_containers() {
    # Docker: Fedora's own moby-engine (upstream Moby, Docker-compatible),
    # not Docker Inc's official repo - mirroring the Ubuntu script's own
    # precedent of preferring the distro package (docker.io) over
    # download.docker.com there too, for consistency.
    batch_install "Containers" moby-engine docker-compose podman
    if is_installed moby-engine; then
        systemctl enable --now docker 2>/dev/null
        [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ] && usermod -aG docker "$SUDO_USER" 2>/dev/null \
            && log INFO "Added $SUDO_USER to the docker group (log out/in to take effect)"
    fi
    # Incus (the community-maintained LXD fork) - natively packaged in
    # Fedora since Fedora 41, replacing the Ubuntu script's Snap-only lxd.
    batch_install "Incus (LXD replacement)" incus
    batch_install "Virtualization" \
        qemu-kvm libvirt virt-install virt-manager virt-viewer \
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
# disk and no network. Fedora doesn't carry these RPMs in its own repos (the
# binaries are Red Hat/Fedora-virt-SIG-built Windows drivers, not something
# Fedora packaging accepts directly) - the upstream-maintained add-on repo at
# fedorapeople.org is the standard, dnf-updatable way to get them instead of
# downloading the ISO by hand. Falls back to a direct one-shot ISO download
# if the repo or package install doesn't go through (offline mirror, repo
# down, etc) so a working ISO still lands either way.
install_virtio_win() {
    if [ -e /var/lib/libvirt/images/virtio-win.iso ]; then
        SKIPPED_PACKAGES+=("Virtio-Win drivers"); ((TOTAL_SKIPPED++)); log INFO "Already installed: Virtio-Win drivers"; return 0
    fi
    mkdir -p /var/lib/libvirt/images
    log INFO "Adding the virtio-win repo (fedorapeople.org)..."
    if dnf config-manager addrepo --from-repofile=https://fedorapeople.org/groups/virt/virtio-win/virtio-win.repo 2>/dev/null \
        || dnf config-manager --add-repo https://fedorapeople.org/groups/virt/virtio-win/virtio-win.repo 2>/dev/null; then
        batch_install "Virtio-Win Drivers" virtio-win
    fi
    if is_installed virtio-win && [ -f /usr/share/virtio-win/virtio-win.iso ]; then
        ln -sf /usr/share/virtio-win/virtio-win.iso /var/lib/libvirt/images/virtio-win.iso
        log SUCCESS "Virtio-Win ISO ready at /var/lib/libvirt/images/virtio-win.iso (symlink to /usr/share/virtio-win - stays current via dnf)"
        return 0
    fi
    log WARNING "virtio-win repo/package unavailable - downloading the latest stable ISO directly instead"
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
# routes everything through its own DOCKER-USER/DOCKER-FORWARD chains - and
# it neither restores the policy to ACCEPT when it stops nor scopes the DROP
# to just its own bridges. Because install_containers() (above) installs
# Docker and libvirt side by side, that combination silently kills internet
# access for EVERY libvirt VM on a NAT network (virbr0, virbr1, ...): DHCP
# and local-subnet traffic still work fine (that path never touches FORWARD
# at all - it's answered directly by dnsmasq on the host), so a VM looks
# "half connected" - gets a real IP, can ping its own gateway, but every
# outbound TCP/UDP/ICMP packet to the actual internet silently vanishes.
# Diagnosed the hard way, live, on real hardware (nftables rule-by-rule,
# hook-priority-by-hook-priority) rather than assumed - see conversation
# history for the full trail if this ever needs re-verifying on a future
# Fedora/Docker/libvirt release.
#
# Docker's own docs recommend fixing this with an exception in DOCKER-USER
# specifically (a chain Docker creates once and never flushes on its own
# restarts) rather than resetting the FORWARD policy globally, which would
# blunt Docker's container network isolation for no reason. The "virbr+"
# wildcard covers the default network AND any additional libvirt networks
# created later, without needing their exact names in advance.
#
# DOCKER-USER rules don't survive a REBOOT on their own - nothing persists
# raw iptables edits made outside firewalld's own config files - so this
# installs a tiny oneshot systemd unit that reapplies the two rules after
# docker.service comes up, on every boot, not just once right now.
install_docker_libvirt_forward_fix() {
    if ! is_installed moby-engine || ! is_installed libvirt; then
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
# Idempotent: allow libvirt bridge traffic (virbr0, virbr1, ...) through
# Docker's DOCKER-USER chain. Without this, Docker's FORWARD policy=DROP
# silently kills internet access for every libvirt NAT-networked VM, while
# leaving DHCP/local-subnet traffic (which never hits FORWARD) working fine -
# so the VM looks "half connected" instead of obviously broken.
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
# Steam needs RPM Fusion nonfree (proprietary EULA); Lutris/GameMode/MangoHud
# are all in Fedora's OWN repos - no RPM Fusion needed for those three.
# Fedora handles 32-bit/multilib packages natively via .i686 builds, so
# there's no Ubuntu-style "dpkg --add-architecture i386" step needed at all.
install_gaming() {
    batch_install "Gaming" steam lutris gamemode mangohud
}

# ========== OFFICE & PRODUCTIVITY ==========
install_office() {
    # gnome-papers is GNOME's replacement for Evince in newer GNOME releases;
    # both are listed since which one is present depends on the exact Fedora
    # release - package_exists skips whichever isn't there.
    batch_install "Office" libreoffice okular evince papers zathura pandoc-cli
}

# ========== SYSTEM UTILITIES ==========
install_system_utils() {
    # Charm publishes their own yum repo for glow (a markdown-in-terminal
    # renderer) - no Fedora COPR/official build exists. Exact repo stanza
    # from their own install docs (github.com/charmbracelet/glow#installation).
    if [ ! -f /etc/yum.repos.d/charm.repo ]; then
        log INFO "Adding Charm's yum repo (for glow)..."
        cat > /etc/yum.repos.d/charm.repo <<'REPOEOF'
[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key
REPOEOF
        pm_update
    fi
    batch_install "System Utils" \
        htop iotop sysstat glances \
        nethogs iftop nload vnstat tcpdump wireshark \
        lsof strace ltrace valgrind gdb \
        tmux screen zsh fish fzf ripgrep tree ncdu rsync unzip bat glow
    # NOTE: unlike Ubuntu's "bat" package (which installs as /usr/bin/batcat
    # due to a Debian name collision), Fedora's "bat" package installs
    # straight to /usr/bin/bat - no alias/rename needed here.
}

# ========== ANDROID TOOLS ==========
install_android_tools() {
    # Fedora bundles adb+fastboot into a single "android-tools" package,
    # unlike Ubuntu's separate adb/fastboot packages. scrcpy has never
    # shipped in Fedora's own repos - needs the zeno/scrcpy COPR.
    add_copr "zeno/scrcpy" zeno
    batch_install "Android Tools" android-tools scrcpy
}

# ========== AI TOOLS ==========
# Almost entirely package-manager-agnostic (vendor curl|bash installers,
# npm globals, Flathub) - ported near-verbatim from the Ubuntu script. Only
# Cursor and IntelliJ (already handled in install_java) actually change.
install_ai_tools() {
    log INFO "Installing AI Tools..."
    install_ollama
    install_alpaca
    install_claude_code
    install_claude_desktop
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

# Alpaca - native GTK4/libadwaita Ollama client, Flathub-only (no vendor
# rpm/COPR exists), same as the Ubuntu script.
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

# Claude Desktop - unofficial repackaging by
# https://github.com/aaddrick/claude-desktop-debian, ships as an .rpm since
# Fedora has no official Anthropic repo of its own (same launcher/--doctor
# extras as the Ubuntu build). A real dnf repo means `dnf upgrade` keeps it
# current from here on, same rationale as install_cursor above. Tracking
# name matches the real rpm package name so its .desktop resolves
# automatically for the AI Tools app-folder.
install_claude_desktop() {
    if command -v claude-desktop-unofficial &>/dev/null || is_installed claude-desktop-unofficial; then
        SKIPPED_PACKAGES+=("claude-desktop-unofficial"); ((TOTAL_SKIPPED++)); log INFO "Already installed: claude-desktop-unofficial"; return 0
    fi
    log INFO "Installing Claude Desktop (unofficial rpm repo)..."
    curl -fsSL https://pkg.claude-desktop-debian.dev/rpm/claude-desktop-unofficial.repo -o /etc/yum.repos.d/claude-desktop-unofficial.repo 2>/dev/null
    pm_update
    safe_install claude-desktop-unofficial
}

install_gemini_cli() {
    if command -v gemini &>/dev/null; then
        SKIPPED_PACKAGES+=("gemini"); ((TOTAL_SKIPPED++)); log INFO "Already installed: gemini"; return 0
    fi
    if ! command -v npm &>/dev/null; then
        log INFO "npm not found - installing it (required by Gemini CLI)..."
        pm_install npm >/dev/null 2>&1 || true
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
        pm_install npm >/dev/null 2>&1 || true
    fi
    if command -v npm &>/dev/null && npm install -g opencode-ai 2>/dev/null && command -v opencode &>/dev/null; then
        INSTALLED_PACKAGES+=("opencode"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: opencode (npm)"; return 0
    fi
    FAILED_PACKAGES+=("opencode"); ((TOTAL_FAILED++))
    log WARNING "OpenCode install failed - try: curl -fsSL https://opencode.ai/install | bash"; return 0
}

# Cursor now ships an official yum repo (downloads.cursor.com/yumrepo),
# unlike the Ubuntu script's .deb/AppImage download-API dance - a real repo
# means normal `dnf upgrade` keeps it current from here on.
install_cursor() {
    if command -v cursor &>/dev/null || is_installed cursor; then
        SKIPPED_PACKAGES+=("cursor"); ((TOTAL_SKIPPED++)); log INFO "Already installed: cursor"; return 0
    fi
    log INFO "Installing Cursor (official yum repo)..."
    rpm --import https://downloads.cursor.com/keys/anysphere.asc 2>/dev/null
    cat > /etc/yum.repos.d/cursor.repo <<'EOF'
[cursor]
name=Cursor
baseurl=https://downloads.cursor.com/yumrepo
enabled=1
gpgcheck=1
gpgkey=https://downloads.cursor.com/keys/anysphere.asc
EOF
    pm_update
    safe_install cursor
}

# ========== GUI TWEAKS ==========
set_terminal_font() {
    local font_family="$1" font_size="${2:-12}"
    local user uid
    if ! read -r user uid < <(resolve_desktop_session); then
        log WARNING "No active desktop session - skipping terminal font"; return 1
    fi
    gsettings_as_user "$user" "$uid" set org.gnome.desktop.interface monospace-font-name "${font_family} ${font_size}" 2>/dev/null
    gset_if_exists "$user" "$uid" org.gnome.Ptyxis.Preferences use-system-font true || true
    local prof; prof=$(gsettings_as_user "$user" "$uid" get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'")
    if [ -n "$prof" ]; then
        local rel="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${prof}/"
        gsettings_as_user "$user" "$uid" set "$rel" use-system-font false 2>/dev/null
        gsettings_as_user "$user" "$uid" set "$rel" font "${font_family} ${font_size}" 2>/dev/null
    fi
    log SUCCESS "Terminal font set to ${font_family} ${font_size}"
}

configure_terminal_font() {
    local font_family="JetBrainsMono Nerd Font"
    if ! fc-list 2>/dev/null | grep -qi "jetbrainsmono nerd font"; then
        log INFO "JetBrainsMono Nerd Font not found - skipping terminal font prompt"; return 0
    fi
    local do_it=false
    if command -v whiptail &>/dev/null; then
        whiptail --yesno "Set the terminal / system monospace font to '$font_family'?" --yes-button "Set" --no-button "Skip" 10 70 && do_it=true
    else
        echo "Set the terminal / system monospace font to '$font_family'? [y/N]:"
        read -r REPLY
        [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ] && do_it=true
    fi
    if $do_it; then set_terminal_font "$font_family" 12; else echo "  Skipped terminal font."; fi
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

install_gnome_extensions() {
    local user uid
    if ! read -r user uid < <(resolve_desktop_session); then
        log INFO "No active desktop session - skipping GNOME extensions"; return 0
    fi
    command -v pipx &>/dev/null || safe_install pipx
    log INFO "Setting up gext (GNOME Extension Manager CLI) via pipx..."
    su - "$user" -c 'command -v gext >/dev/null 2>&1 || pipx install gnome-extensions-cli --system-site-packages' 2>/dev/null
    if ! su - "$user" -c 'PATH="$HOME/.local/bin:$PATH" command -v gext' &>/dev/null; then
        log WARNING "gext install failed (pipx/network issue) - skipping all GNOME extensions"
        FAILED_PACKAGES+=("GNOME extensions (gext setup failed)"); ((TOTAL_FAILED++))
        return 1
    fi
    local exts=(
        "gsconnect@andyholmes.github.io"
        "window-state-manager@kishorv06.github.io"
        "Bluetooth-Battery-Meter@maniacx.github.com"
        "auto-move-windows@gnome-shell-extensions.gcampax.github.com"
        "user-theme@gnome-shell-extensions.gcampax.github.com"
        "clipboard-history@alexsaveau.dev"
        "dash-to-dock@micxgx.gmail.com"
        "compact-quick-settings@gnome-shell-extensions.mariospr.org"
    )
    local e ok=0
    for e in "${exts[@]}"; do
        if su - "$user" -c "XDG_RUNTIME_DIR='/run/user/$uid' DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/$uid/bus' PATH=\"\$HOME/.local/bin:\$PATH\" gext install '$e'" 2>/dev/null; then
            log INFO "Installed extension: $e"; ((ok++))
            INSTALLED_PACKAGES+=("$e (extension)"); ((TOTAL_INSTALLED++))
        else
            log WARNING "Failed extension (skipped): $e"
            FAILED_PACKAGES+=("$e (extension)"); ((TOTAL_FAILED++))
        fi
    done
    log INFO "GNOME extensions: $ok/${#exts[@]} installed - log out/in to activate"
}

configure_logiops() {
    local msg="Build and install Logiops (Logitech HID++ driver) from source?\n\nOnly useful if you have a Logitech mouse/keyboard with HID++ support (MX Master, MX Anywhere, etc)."
    local do_it=false
    if command -v whiptail &>/dev/null; then
        whiptail --yesno "$msg" --yes-button "Build" --no-button "Skip" 12 72 && do_it=true
    else
        echo -e "$msg [y/N]:"
        read -r REPLY
        { [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; } && do_it=true
    fi
    if $do_it; then install_logiops; else log INFO "Skipped Logiops"; fi
}

install_logiops() {
    log INFO "Installing Logiops build dependencies..."
    batch_install "Logiops build deps" \
        cmake pkgconf-pkg-config systemd-devel libevdev-devel libconfig-devel glib2-devel gcc-c++
    local t; t=$(mktemp -d)
    if ! git clone --depth 1 https://github.com/PixlOne/logiops "$t/logiops" 2>/dev/null; then
        rm -rf "$t"; log WARNING "Logiops clone failed (needs network access to github.com)"; return 1
    fi
    (
        cd "$t/logiops" || exit 1
        mkdir -p build && cd build || exit 1
        cmake .. 2>/dev/null && make -j"$(nproc)" 2>/dev/null && make install 2>/dev/null
    )
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

install_gui_tools() {
    batch_install "GUI Tools" \
        gnome-tweaks \
        gnome-extensions-app \
        nautilus \
        eog \
        file-roller \
        simple-scan \
        gnome-screenshot \
        gnome-system-monitor \
        dconf-editor
}

# ── Icon Sets ─────────────────────────────────────────────────────────────
install_icon_sets() {
    # Unlike Ubuntu, Papirus/Numix/Breeze/Adwaita all ship directly in
    # Fedora's own repos already - no PPA equivalent needed for any of them.
    # obsidian-icon-theme is the exception: it's only in an unofficial COPR.
    add_copr "niohiani/MiscellanyMarketPlace" niohiani
    batch_install "Icon Sets" \
        papirus-icon-theme \
        numix-icon-theme \
        numix-icon-theme-circle \
        breeze-icon-theme \
        adwaita-icon-theme \
        obsidian-icon-theme
    install_qogir_icons
    install_whitesur_icons
    install_vimix_icons
    install_newaita_icons
}

# Shared install mechanics for the vinceliuice family of icon theme generators
# (Qogir, WhiteSur, Vimix). Their destination logic is $UID-aware (root ->
# /usr/share/icons) with no other hardcoded $HOME dependency, so this runs
# directly as root - system-wide, no su-as-desktop-user needed.
install_vinceliuice_repo() {
    local label="$1" repo="$2" slug="$3" kind="$4"; shift 4
    local extra_args=("$@")

    local marker="/var/lib/fedora-postinstall-themes/${slug}.done"
    if [ -f "$marker" ]; then
        SKIPPED_PACKAGES+=("$label $kind"); ((TOTAL_SKIPPED++)); log INFO "Already installed: $label $kind"; return 0
    fi
    command -v gtk-update-icon-cache &>/dev/null || safe_install gtk3

    local t; t=$(mktemp -d)
    if ! git clone --depth 1 "$repo" "$t/src" 2>/dev/null; then
        rm -rf "$t"; FAILED_PACKAGES+=("$label $kind"); ((TOTAL_FAILED++))
        log WARNING "$label $kind clone failed (needs network access to github.com)"; return 1
    fi
    log INFO "Installing $label $kind..."
    if bash "$t/src/install.sh" "${extra_args[@]}" 2>/dev/null; then
        mkdir -p "$(dirname "$marker")" && touch "$marker"
        INSTALLED_PACKAGES+=("$label $kind"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: $label $kind (pick via gnome-tweaks)"
    else
        FAILED_PACKAGES+=("$label $kind"); ((TOTAL_FAILED++)); log WARNING "$label $kind install failed"
    fi
    rm -rf "$t"
}

install_newaita_icons() {
    if [ -d /usr/share/icons/Newaita ]; then
        SKIPPED_PACKAGES+=("Newaita icons"); ((TOTAL_SKIPPED++)); log INFO "Already installed: Newaita icons"; return 0
    fi
    local t; t=$(mktemp -d)
    if ! git clone --depth 1 https://github.com/cbrnix/Newaita.git "$t/src" 2>/dev/null; then
        rm -rf "$t"; FAILED_PACKAGES+=("Newaita icons"); ((TOTAL_FAILED++))
        log WARNING "Newaita icons clone failed (needs network access to github.com)"; return 1
    fi
    log INFO "Installing Newaita icon theme..."
    if cp -r "$t/src/Newaita" "$t/src/Newaita-dark" /usr/share/icons/ 2>/dev/null; then
        INSTALLED_PACKAGES+=("Newaita icons"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: Newaita icons (/usr/share/icons)"
    else
        FAILED_PACKAGES+=("Newaita icons"); ((TOTAL_FAILED++)); log WARNING "Newaita icons install failed"
    fi
    rm -rf "$t"
}

install_qogir_icons()    { install_vinceliuice_repo "Qogir"    "https://github.com/vinceliuice/Qogir-icon-theme.git"    "qogir-icons"    "icons"; }
install_whitesur_icons() { install_vinceliuice_repo "WhiteSur" "https://github.com/vinceliuice/WhiteSur-icon-theme.git" "whitesur-icons" "icons"; }
install_vimix_icons()    { install_vinceliuice_repo "Vimix"    "https://github.com/vinceliuice/Vimix-icon-theme.git"    "vimix-icons"    "icons"; }
install_colloid_theme()  { install_vinceliuice_repo "Colloid"  "https://github.com/vinceliuice/Colloid-gtk-theme.git"  "colloid-gtk-theme" "theme"; }

# ── GTK Theme ──────────────────────────────────────────────────────────────
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
        log WARNING "Nordic theme clone failed (needs network access to github.com)"; return 1
    fi
    log INFO "Installing Nordic theme..."
    if su - "$user" -c "mkdir -p '$uh/.themes' && cp -r '$t/src/Nordic' '$uh/.themes/Nordic'" 2>/dev/null \
        && [ -d "$uh/.themes/Nordic" ]; then
        INSTALLED_PACKAGES+=("Nordic theme"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: Nordic theme (~/.themes - pick it in gnome-tweaks)"
    else
        FAILED_PACKAGES+=("Nordic theme"); ((TOTAL_FAILED++)); log WARNING "Nordic theme install failed"
    fi
    rm -rf "$t"
}

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
        log WARNING "Material GNOME theme clone failed (needs network access to github.com)"; return 1
    fi
    # Repo root IS the theme tree (no install.sh) - drop it straight into
    # ~/.themes/Material-Gnome, then symlink the GTK4/libadwaita stylesheets
    # into ~/.config/gtk-4.0 since those apps ignore ~/.themes entirely.
    log INFO "Installing Material GNOME theme..."
    if su - "$user" -c "rm -rf '$t/src/.git' && mkdir -p '$uh/.themes/Material-Gnome' && cp -r '$t/src/.' '$uh/.themes/Material-Gnome' && mkdir -p '$uh/.config/gtk-4.0' && ln -sf '$uh/.themes/Material-Gnome/gtk-4.0/gtk.css' '$uh/.config/gtk-4.0/gtk.css' && ln -sf '$uh/.themes/Material-Gnome/gtk-4.0/gtk-dark.css' '$uh/.config/gtk-4.0/gtk-dark.css'" 2>/dev/null \
        && [ -d "$uh/.themes/Material-Gnome" ]; then
        INSTALLED_PACKAGES+=("Material GNOME theme"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: Material GNOME theme (~/.themes - pick it in gnome-tweaks)"
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
    batch_install "Lycia Theme Dependencies" gtk-murrine-engine sassc gnome-themes-extra
    local t; t=$(mktemp -d); chmod 755 "$t"; chown "$user" "$t" 2>/dev/null
    if ! su - "$user" -c "git clone --depth 1 https://github.com/Aevstiel/Lycia-Theme.git '$t/src'" 2>/dev/null; then
        rm -rf "$t"; FAILED_PACKAGES+=("Lycia theme"); ((TOTAL_FAILED++))
        log WARNING "Lycia theme clone failed (needs network access to github.com)"; return 1
    fi
    # install.sh interactively asks two questions: install the GTK4/Libadwaita
    # files (yes) and install the GDM login-screen theme (no - that overwrites
    # a system gnome-shell resource file, too invasive for an unattended run).
    log INFO "Installing Lycia theme..."
    if printf 'Y\nN\n' | su - "$user" -c "bash '$t/src/install.sh'" 2>/dev/null && [ -d "$uh/.themes/Lycia" ]; then
        INSTALLED_PACKAGES+=("Lycia theme"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: Lycia theme (~/.themes - pick it in gnome-tweaks)"
    else
        FAILED_PACKAGES+=("Lycia theme"); ((TOTAL_FAILED++)); log WARNING "Lycia theme install failed"
    fi
    rm -rf "$t"
}

install_themes() {
    install_nordic_theme
    install_colloid_theme
    install_material_gnome_theme
    install_lycia_theme
}

install_cursor_themes() {
    # Candidate package names vary by Fedora release for the Breeze cursor
    # theme (xcursor-breeze vs breeze-cursor-theme) - package_exists skips
    # whichever isn't the real one on a given release.
    batch_install "Cursor Themes" xcursor-breeze breeze-cursor-theme
}

install_nerd_fonts() {
    log INFO "Installing Nerd Fonts..."
    mkdir -p /usr/share/fonts/truetype/nerd-fonts
    batch_install "Nerd Fonts (dnf)" fira-code-fonts jetbrains-mono-fonts
    local t=$(mktemp -d) c=0 f=0
    local fonts=(FiraCode JetBrainsMono Hack SourceCodePro CascadiaCode UbuntuMono DejaVuSansMono)
    local ext="tar.xz" ecmd="tar -xf" destflag="-C"
    if ! command -v tar &>/dev/null || ! tar --help 2>/dev/null | grep -q xz; then
        command -v unzip &>/dev/null && { ext="zip"; ecmd="unzip -qq -o"; destflag="-d"; } || safe_install tar xz 2>/dev/null || true
    fi
    log INFO "Downloading popular Nerd Fonts (format: ${ext})..."
    for font in "${fonts[@]}"; do
        local af="$t/${font}.${ext}" ed="$t/${font}"
        mkdir -p "$ed"
        local d=0
        curl -L -f --retry 3 -o "$af" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font}.${ext}" 2>/dev/null && d=1
        [ $d -eq 0 ] && { log WARNING "Failed: $font"; ((f++)); continue; }
        if ! $ecmd "$af" $destflag "$ed" 2>/dev/null; then log WARNING "Extract failed: $font"; ((f++)); continue; fi
        local cp=0
        while IFS= read -r -d '' ff; do cp "$ff" /usr/share/fonts/truetype/nerd-fonts/ 2>/dev/null; ((cp++)); done < <(find "$ed" -type f \( -iname "*.ttf" -o -iname "*.otf" \) -print0 2>/dev/null)
        [ $cp -gt 0 ] && { ((c++)); log INFO "Installed: $font"; } || { log WARNING "No files: $font"; ((f++)); }
        rm -rf "$af" "$ed"
    done
    command -v fc-cache &>/dev/null && fc-cache -f /usr/share/fonts/truetype/nerd-fonts/ 2>/dev/null
    rm -rf "$t"
    [ $c -gt 0 ] && log SUCCESS "Installed $c Nerd Fonts ($f failed)" || { log ERROR "No fonts installed"; return 1; }
    return 0
}

install_chris_titus_mybash() {
    local UH=$(eval echo ~$SUDO_USER 2>/dev/null || echo "/home/$(logname)")
    local MD="${UH}/mybash" BR="${UH}/.bashrc"
    if [ -d "$MD" ]; then log INFO "mybash already installed"; return 0; fi
    log INFO "Installing Chris Titus mybash..."
    if ! git clone --depth 1 https://github.com/christitustech/mybash "$MD"; then
        log ERROR "Clone failed"; return 1
    fi
    # setup.sh calls `sudo apt-get install ...` internally on Debian/Ubuntu -
    # on Fedora it detects dnf and calls `sudo dnf install ...` instead (the
    # upstream script branches on package manager itself). Run as root, not
    # via su, for the same "nested sudo needs a real terminal" reason as the
    # Ubuntu script.
    if HOME="$UH" USER="$SUDO_USER" LOGNAME="$SUDO_USER" bash "$MD/setup.sh"; then
        chown -R "$SUDO_USER:$SUDO_USER" "$MD" "$UH/.local" "$UH/.config" "$BR" 2>/dev/null || true
        log SUCCESS "mybash installed. User: source ~/.bashrc"
        return 0
    fi
    log WARNING "setup.sh failed, falling back to a plain .bashrc copy..."
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

# ========== SECURITY TOOLS ==========
# CAVEAT (flagged more prominently than most categories here): several
# classic pentest tools have historically been absent from Fedora's own
# repos entirely (no PPA-equivalent exists to pull them from either) - this
# list includes the best-known Fedora package names, but expect more
# "Not in repos" skips here than in other categories. Real GUI tools
# (firewall-config, keepassxc) do get folder icons.
install_security_tools() {
    batch_install "Security - Network" \
        nmap masscan nmap-ncat hping3 bind-utils

    batch_install "Security - Web" \
        nikto sqlmap gobuster whatweb wfuzz

    batch_install "Security - Cracking & Wireless" \
        john hashcat hydra aircrack-ng macchanger

    batch_install "Security - Forensics & RE" \
        radare2 binwalk sleuthkit steghide yara perl-Image-ExifTool

    batch_install "Security - Hardening" \
        lynis chkrootkit rkhunter clamav clamav-freshclam fail2ban aide

    # firewalld (Fedora's default firewall manager) replaces ufw/gufw -
    # there's no Fedora equivalent of Ubuntu's ufw/gufw pairing, firewalld
    # IS the native answer here, with firewall-config as its GUI.
    batch_install "Security - Firewall & Privacy" \
        firewalld firewall-config openvpn wireguard-tools proxychains-ng torsocks keepassxc ettercap
}

install_security_defensive() {
    batch_install "Defensive - Hardening & Integrity" \
        lynis chkrootkit rkhunter aide audit

    batch_install "Defensive - Anti-Malware" \
        clamav clamav-freshclam

    batch_install "Defensive - IDS/IPS" \
        fail2ban suricata

    batch_install "Defensive - Firewall, VPN & Credentials" \
        firewalld firewall-config openvpn wireguard-tools keepassxc
}

# ========== DEVOPS & CLOUD ==========
install_devops() {
    install_docker_standalone
    install_azure_cli
    install_lazygit
}

install_docker_standalone() {
    batch_install "Docker (standalone)" moby-engine docker-compose
    if is_installed moby-engine; then
        systemctl enable --now docker 2>/dev/null
        [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ] && usermod -aG docker "$SUDO_USER" 2>/dev/null
    fi
    # Covers the case where libvirt was already installed in an earlier run
    # (via the Containers menu) - see install_docker_libvirt_forward_fix's
    # own comment, above install_containers, for why this matters. No-ops
    # cleanly if libvirt isn't present yet.
    install_docker_libvirt_forward_fix
}

# Azure CLI from Microsoft's official yum repo (packages.microsoft.com) -
# same vendor as Ubuntu's install script, rpm-repo form instead of a deb
# install script.
install_azure_cli() {
    if command -v az &>/dev/null; then
        SKIPPED_PACKAGES+=("azure-cli"); ((TOTAL_SKIPPED++)); log INFO "Azure CLI already installed"; return 0
    fi
    log INFO "Installing Azure CLI (Microsoft's official yum repo)..."
    rpm --import https://packages.microsoft.com/keys/microsoft.asc 2>/dev/null
    cat > /etc/yum.repos.d/azure-cli.repo <<'EOF'
[azure-cli]
name=Azure CLI
baseurl=https://packages.microsoft.com/yumrepos/azure-cli
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
    pm_update
    safe_install azure-cli
}

# lazygit ships natively in Fedora's own repos - simpler than the Ubuntu
# script's `go install` build, which is kept only as a fallback.
install_lazygit() {
    if command -v lazygit &>/dev/null; then
        SKIPPED_PACKAGES+=("lazygit"); ((TOTAL_SKIPPED++)); log INFO "lazygit already installed"; return 0
    fi
    if package_exists lazygit; then
        batch_install "lazygit" lazygit
        return 0
    fi
    command -v go &>/dev/null || { log INFO "Go not found - installing it first for lazygit..."; install_go; }
    if ! command -v go &>/dev/null; then
        FAILED_PACKAGES+=("lazygit"); ((TOTAL_FAILED++)); log WARNING "Go unavailable - cannot install lazygit"; return 1
    fi
    local uh; uh=$(eval echo ~"$SUDO_USER" 2>/dev/null)
    log INFO "Installing lazygit via 'go install' (as $SUDO_USER)..."
    if su - "$SUDO_USER" -c "GOBIN='${uh}/go/bin' go install github.com/jesseduffield/lazygit@latest" 2>/dev/null \
       && [ -x "${uh}/go/bin/lazygit" ]; then
        ln -sf "${uh}/go/bin/lazygit" /usr/local/bin/lazygit 2>/dev/null || true
        INSTALLED_PACKAGES+=("lazygit"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: lazygit (${uh}/go/bin/lazygit)"
    else
        FAILED_PACKAGES+=("lazygit"); ((TOTAL_FAILED++)); log WARNING "lazygit install failed (needs Go + network access to github.com)"
    fi
}

# ========== WINDOWS SOFTWARE SUPPORT (WINE) ==========
install_windows_support() {
    batch_install "Wine" wine winetricks zenity
    # Winetricks ships no .desktop launcher on Fedora either - hand-write one
    # so it lands in the app grid, same as the Ubuntu script.
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

# ========== FLATPAK/FLATHUB HELPER ==========
# Fedora Workstation ships Flatpak + the Flathub remote pre-configured out of
# the box (unlike Ubuntu, which needs both added) - so this is even more of a
# no-op-if-already-there than the Ubuntu equivalent. Kept for the handful of
# apps researched to have NO better Fedora-native source (Signal, Floorp, Zen
# Browser, Spotify, Bruno, Alpaca) - everything else in this script goes
# through a real dnf repo, RPM Fusion, or COPR first.
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

# ========== BROWSERS ==========
# Every browser here was individually researched against its vendor's actual
# docs/repo files - Brave/Vivaldi/Chrome/Edge/LibreWolf all have real Fedora-
# targeted yum repos; Floorp and Zen Browser genuinely have none (confirmed:
# Ablaze/Zen's own docs point to Flathub as the Linux path), so Flatpak there
# isn't a fallback of convenience, it's the correct answer.
install_browsers() {
    install_brave
    install_vivaldi
    install_edge
    install_chrome
    install_librewolf
    install_zen
    install_floorp
}

install_brave() {
    if is_installed brave-browser; then
        SKIPPED_PACKAGES+=("brave-browser"); ((TOTAL_SKIPPED++)); log INFO "Already installed: brave-browser"; return 0
    fi
    log INFO "Installing Brave (official yum repo)..."
    dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo 2>/dev/null \
        || dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo 2>/dev/null
    rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc 2>/dev/null
    pm_update
    safe_install brave-browser
}

install_vivaldi() {
    if is_installed vivaldi-stable; then
        SKIPPED_PACKAGES+=("vivaldi-stable"); ((TOTAL_SKIPPED++)); log INFO "Already installed: vivaldi-stable"; return 0
    fi
    log INFO "Installing Vivaldi (official yum repo)..."
    rpm --import https://repo.vivaldi.com/archive/linux_signing_key.pub 2>/dev/null
    dnf config-manager addrepo --from-repofile=https://repo.vivaldi.com/stable/vivaldi-fedora.repo 2>/dev/null \
        || dnf config-manager --add-repo https://repo.vivaldi.com/stable/vivaldi-fedora.repo 2>/dev/null
    pm_update
    safe_install vivaldi-stable
}

# Microsoft Edge from Microsoft's official yum repo.
install_edge() {
    if is_installed microsoft-edge-stable; then
        SKIPPED_PACKAGES+=("microsoft-edge-stable"); ((TOTAL_SKIPPED++)); log INFO "Already installed: microsoft-edge-stable"; return 0
    fi
    log INFO "Installing Microsoft Edge (official yum repo)..."
    rpm --import https://packages.microsoft.com/keys/microsoft.asc 2>/dev/null
    dnf config-manager addrepo --id=microsoft-edge --save-filename=microsoft-edge.repo \
        --set=name="Microsoft Edge" \
        --set=baseurl=https://packages.microsoft.com/yumrepos/edge \
        --set=enabled=1 --set=gpgcheck=1 \
        --set=gpgkey=https://packages.microsoft.com/keys/microsoft.asc \
        --overwrite 2>/dev/null
    pm_update
    safe_install microsoft-edge-stable
}

# Google Chrome - self-registers its own repo on install (verified via live
# repodata fetch), so a plain rpm bootstrap install is all that's needed.
install_chrome() {
    if is_installed google-chrome-stable; then
        SKIPPED_PACKAGES+=("google-chrome-stable"); ((TOTAL_SKIPPED++)); log INFO "Already installed: google-chrome-stable"; return 0
    fi
    log INFO "Installing Google Chrome (official rpm, self-registers its repo)..."
    dnf install -y https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm 2>/dev/null
    if is_installed google-chrome-stable; then
        INSTALLED_PACKAGES+=("google-chrome-stable"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: google-chrome-stable"
    else
        FAILED_PACKAGES+=("google-chrome-stable"); ((TOTAL_FAILED++)); log WARNING "Chrome install failed"
    fi
}

# LibreWolf's own official rpm repo (supersedes older community COPRs).
install_librewolf() {
    if is_installed librewolf; then
        SKIPPED_PACKAGES+=("librewolf"); ((TOTAL_SKIPPED++)); log INFO "Already installed: librewolf"; return 0
    fi
    log INFO "Installing LibreWolf (official yum repo)..."
    rpm --import https://repo.librewolf.net/pubkey.gpg 2>/dev/null
    dnf config-manager addrepo --from-repofile=https://repo.librewolf.net/librewolf.repo 2>/dev/null \
        || dnf config-manager --add-repo https://repo.librewolf.net/librewolf.repo 2>/dev/null
    pm_update
    safe_install librewolf
}

# Zen Browser and Floorp: confirmed no vendor rpm/COPR exists for either -
# Flathub is the vendors' own documented Linux path, not a compromise.
install_zen()    { flatpak_install_flathub app.zen_browser.zen "Zen"; }
install_floorp() { flatpak_install_flathub one.ablaze.floorp "Floorp"; }

# ========== COMMUNICATION ==========
install_communication() {
    install_signal
    install_discord
    install_telegram
    install_teams
}

# Signal Desktop - confirmed no rpm/yum repo exists anywhere (the commonly-
# cited updates.signal.org/desktop/yum/ URL 404s); Flathub is the only real
# option, same conclusion the Ubuntu script reaches for it via a different
# mechanism (Ubuntu DOES have a real Signal apt repo - Fedora just has nothing
# equivalent).
install_signal() { flatpak_install_flathub org.signal.Signal "Signal"; }

# Discord - no vendor repo (their download page is a one-off rpm/deb/tar.gz),
# but RPM Fusion nonfree packages it natively - better than Flatpak here.
install_discord() {
    if is_installed discord; then
        SKIPPED_PACKAGES+=("discord"); ((TOTAL_SKIPPED++)); log INFO "Already installed: discord"; return 0
    fi
    if package_exists discord; then
        batch_install "Discord" discord
    else
        log INFO "discord not in repos (needs RPM Fusion nonfree) - installing from Flathub instead"
        flatpak_install_flathub com.discordapp.Discord "Discord"
    fi
}

# Telegram Desktop - RPM Fusion free packages it natively, better than the
# Ubuntu script's Flatpak fallback (Ubuntu's own telegram-desktop apt package
# is hit-or-miss by release; Fedora's RPM Fusion one is consistently there).
install_telegram() {
    if is_installed telegram-desktop; then
        SKIPPED_PACKAGES+=("telegram-desktop"); ((TOTAL_SKIPPED++)); log INFO "Already installed: telegram-desktop"; return 0
    fi
    if package_exists telegram-desktop; then
        batch_install "Telegram" telegram-desktop
    else
        log INFO "telegram-desktop not in repos - installing from Flathub instead"
        flatpak_install_flathub org.telegram.desktop "Telegram"
    fi
}

# Microsoft Teams via teams-for-linux's own real dnf repo (repo.teamsforlinux.de) -
# same community project the Ubuntu script uses, rpm-repo form.
install_teams() {
    if command -v teams-for-linux &>/dev/null; then
        SKIPPED_PACKAGES+=("teams-for-linux"); ((TOTAL_SKIPPED++)); log INFO "Already installed: teams-for-linux"; return 0
    fi
    log INFO "Installing Microsoft Teams (teams-for-linux)..."
    curl -1sLf -o /etc/yum.repos.d/teams-for-linux.repo https://repo.teamsforlinux.de/rpm/teams-for-linux.repo 2>/dev/null
    pm_update
    safe_install teams-for-linux
}

# ========== DESKTOP APPS ==========
install_desktop_apps() {
    install_spotify
    install_slack
    install_remmina
    install_windows_app
    install_teamviewer
    install_1password
}

# Spotify - confirmed no rpm/repo from Spotify (their own page lists only
# Snap + a Debian apt repo, and states Linux isn't actively supported) -
# Flathub (community-maintained) is the only real option.
install_spotify() { flatpak_install_flathub com.spotify.Client "Spotify"; }

# Slack - packagecloud.io/slacktechnologies/slack is real but permanently
# stale: every rpm in it is registered under a frozen fedora/21 path from
# ~2014 and was never updated to track current releases, so dnf gets a
# repo with nothing matching modern Fedora. There's no static "latest" rpm
# URL either - Slack's own downloads page embeds the current version-
# specific link, so we scrape that (same technique current install guides
# use) and install the rpm directly, keeping the official vendor build
# rather than falling back to Flathub's unaffiliated community package.
# Slack's own rpm postinst script re-registers packagecloud.io/slacktechnologies/
# slack (and a -source variant) as a dnf repo on every install/reinstall, even
# though that repo is permanently stale (frozen fedora/21 paths from ~2014).
# Left enabled, it breaks every subsequent `dnf update`/`makecache` with GPG
# "signing key not found" prompts and, if the box's CA trust is ever rebuilt,
# curl "SSL CA cert" errors - neither has anything to do with Slack itself,
# it's just noise from a repo nothing in it will ever be installed from.
# disable_stale_slack_repo() is idempotent and safe to call whether or not
# Slack (or the repo files) are present.
disable_stale_slack_repo() {
    local f found=false
    for f in /etc/yum.repos.d/slacktechnologies_slack.repo \
             /etc/yum.repos.d/slacktechnologies_slack-source.repo; do
        [ -f "$f" ] && { rm -f "$f"; found=true; }
    done
    $found && log INFO "Removed stale packagecloud Slack repo file(s)"
}

install_slack() {
    if is_installed slack; then
        SKIPPED_PACKAGES+=("slack"); ((TOTAL_SKIPPED++)); log INFO "Already installed: slack"
        disable_stale_slack_repo
        return 0
    fi
    log INFO "Installing Slack (direct rpm from slack.com - packagecloud repo is permanently stale)..."
    local page url t
    page=$(curl -sL "https://slack.com/downloads/instructions/linux?build=rpm&ddl=1" 2>/dev/null)
    url=$(printf '%s' "$page" | grep -oE 'https://downloads\.slack-edge\.com/desktop-releases/linux/x64/[0-9.]+/slack-[0-9.]+-[0-9.]+\.el[0-9]+\.x86_64\.rpm' | head -1)
    if [ -z "$url" ]; then
        FAILED_PACKAGES+=("slack"); ((TOTAL_FAILED++))
        log WARNING "Could not find current Slack rpm URL on slack.com (page layout may have changed)"; return 1
    fi
    t=$(mktemp -d)
    if ! curl -sL -o "$t/slack.rpm" "$url" 2>/dev/null || [ ! -s "$t/slack.rpm" ]; then
        rm -rf "$t"; FAILED_PACKAGES+=("slack"); ((TOTAL_FAILED++))
        log WARNING "Slack rpm download failed ($url)"; return 1
    fi
    if dnf install -y "$t/slack.rpm" 2>/dev/null; then
        INSTALLED_PACKAGES+=("slack"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: slack"
    else
        FAILED_PACKAGES+=("slack"); ((TOTAL_FAILED++)); log WARNING "Slack rpm install failed"
    fi
    rm -rf "$t"
    # The rpm's own postinst hook is what plants the stale repo files - it
    # runs as part of `dnf install` above, so this has to come after, not
    # before, or the just-added files would just get re-added underneath us.
    disable_stale_slack_repo
}

# Remmina ships directly in Fedora's own repos at a current version - no PPA
# equivalent needed the way Ubuntu needs remmina-ppa-team for a modern build.
install_remmina() {
    batch_install "Remmina" remmina remmina-plugins-rdp remmina-plugins-secret
}

# "Windows App" (mariuszkopowski/windows-app-for-linux) - not on Flathub, so
# it ships as a standalone Flatpak bundle from GitHub releases. Identical
# mechanics to the Ubuntu script - installed into the desktop user's
# per-user Flatpak scope.
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
            if curl -L -f --retry 2 -o "$tmp/windows-app.flatpak" "$url" 2>/dev/null; then
                bundle="$tmp/windows-app.flatpak"
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

# TeamViewer - real vendor yum repo, Fedora explicitly listed as supported.
install_teamviewer() {
    if command -v teamviewer &>/dev/null || is_installed teamviewer; then
        SKIPPED_PACKAGES+=("teamviewer"); ((TOTAL_SKIPPED++)); log INFO "Already installed: teamviewer"; return 0
    fi
    log INFO "Installing TeamViewer (official yum repo)..."
    rpm --import https://linux.teamviewer.com/pubkey/currentkey.asc 2>/dev/null
    cat > /etc/yum.repos.d/teamviewer.repo <<'EOF'
[teamviewer]
name=TeamViewer
baseurl=https://linux.teamviewer.com/yum/stable/main/binary-$basearch/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://linux.teamviewer.com/pubkey/currentkey.asc
EOF
    pm_update
    safe_install teamviewer
}

# 1Password - real vendor yum repo, Fedora explicitly supported. Simpler than
# the Ubuntu apt path: rpm has no debsig-verify-style extra policy step, just
# the repo + gpgkey.
install_1password() {
    if is_installed 1password; then
        SKIPPED_PACKAGES+=("1password"); ((TOTAL_SKIPPED++)); log INFO "Already installed: 1password"; return 0
    fi
    log INFO "Installing 1Password (official yum repo)..."
    rpm --import https://downloads.1password.com/linux/keys/1password.asc 2>/dev/null
    cat > /etc/yum.repos.d/1password.repo <<'EOF'
[1password]
name=1Password
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF
    pm_update
    safe_install 1password
}

# ========== MENU SYSTEM ==========
# Consolidation note: the Ubuntu script had both a standalone "Ubuntu Studio"
# sub-menu AND separate top-level Graphics/Video/Audio categories that
# overlapped with it by design. Fedora has no per-domain metapackage split to
# mirror that duplication meaningfully, so this port folds all of it into one
# "Creative Suite" category with the same Full/Graphics/Video/Audio/
# Photography/Publishing sub-menu shape - a deliberate simplification, not an
# oversight. "Zoom" is dropped entirely per explicit request (no Fedora repo
# exists for it anyway). "Drivers & Extra Repos" (NVIDIA, Terra) is new -
# Ubuntu's script had no GPU-driver category at all.

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
# category's packages, WITHOUT prompting - used by the bulk options (A/B/C).
auto_category() {
    local name="$1" fn="$2"
    reset_tracking
    "$fn"
    display_summary
    create_menu_category "$name" "applications-other" "$name" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}"
}

show_main_menu() {
    clear
    ui_header "FEDORA ${FEDORA_VERSION:-42/43/44}  ·  POST-INSTALL" "dnf5 · RPM Fusion · GNOME app folders"
    echo
    ui_section "Creative & Drivers"
    ui_cell  1 "Creative Suite";     ui_cell 28 "Drivers & Extra Repos"; echo
    ui_cell 14 "Gaming";             ui_cell 25 "Desktop Apps";          echo
    ui_cell 29 "Snapshots & Backup"; ui_cell 30 "Peripherals (Logitech)"; echo
    ui_cell 31 "Printers (CUPS + HP)";                                   echo
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
    ui_cell 16 "System Utilities";   ui_cell 19 "GUI Tweaks";            echo
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
    printf "  ${MAUVE}${BOLD}❯${NC} ${LAVENDER}Choose ${DIM}[0-31 · A-C · S]${NC}${LAVENDER}: ${NC}"
}

show_creative_menu() {
    clear
    ui_header "CREATIVE SUITE"
    echo
    ui_item 1 "Full (Graphics + Video + Audio + Photography + Publishing)"
    ui_item 2 "Graphics & Design (Design Suite)"
    ui_item 3 "Video Editing"
    ui_item 4 "Audio Production (Fedora Jam)"
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
    ui_header "GUI TWEAKS"
    echo
    ui_item 1 "All GUI Tweaks (everything below)"
    ui_item 2 "Icon Sets"
    ui_item 3 "GTK Themes (choose: Nordic / Colloid / Material GNOME / Lycia)"
    ui_item 4 "Cursor Themes"
    ui_item 5 "Nerd Fonts"
    ui_item 6 "Chris Titus mybash"
    ui_item 7 "GUI Tools"
    ui_item 8 "GNOME Shell Extensions"
    echo
    ui_item 0 "Back to Main Menu"
    echo
    ui_rule
    printf "  ${MAUVE}${BOLD}❯${NC} ${LAVENDER}Choose ${DIM}[0-8]${NC}${LAVENDER}: ${NC}"
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
    ui_item 1 "NVIDIA Driver (akmod-nvidia-open + CUDA)"
    ui_item 2 "Terra Repo (Ultramarine's parent project - extras only)"
    ui_item 3 "DisplayLink Driver (USB/dock display adapters)"
    echo
    ui_item 0 "Back to Main Menu"
    echo
    ui_rule
    printf "  ${MAUVE}${BOLD}❯${NC} ${LAVENDER}Choose ${DIM}[0-3]${NC}${LAVENDER}: ${NC}"
}

show_snapshots_menu() {
    clear
    ui_header "SNAPSHOTS & BACKUP" "Auto-detects Btrfs (Snapper+GUI) vs other (Timeshift)"
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

show_printers_menu() {
    clear
    ui_header "PRINTERS (CUPS + HP)" "HPLIP - HP's Linux printing/imaging stack"
    echo
    ui_item 1 "Install printer support (cups + hplip + system-config-printer)"
    ui_item 2 "Install/check HP proprietary plugin (some older LaserJets/inkjets need this)"
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
    bootstrap_repos
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
                case "$gui_choice" in
                    0) continue ;;
                    1) reset_tracking; install_gui_tweaks;        display_summary; prompt_menu_category "GUI Tweaks" "preferences" "GUI Customization & Tweaks" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    2) reset_tracking; install_icon_sets;         display_summary; prompt_menu_category "GUI Tweaks" "preferences" "GUI Customization & Tweaks" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
                    3)
                        show_gtk_theme_menu
                        read -r theme_choice
                        case "$theme_choice" in
                            0) continue ;;
                            1) reset_tracking; install_themes;               display_summary; prompt_menu_category "GUI Tweaks" "preferences" "GUI Customization & Tweaks" "${INSTALLED_PACKAGES[@]}" "${SKIPPED_PACKAGES[@]}";;
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
                    1) reset_tracking; install_nvidia_driver; display_summary ;;
                    2) reset_tracking; install_terra_repo; display_summary ;;
                    3) reset_tracking; install_displaylink_driver; display_summary ;;
                    *) log ERROR "Invalid choice"; sleep 2 ;;
                esac
                ;;
            29)
                show_snapshots_menu
                read -r snap_choice
                case "$snap_choice" in
                    0) continue ;;
                    1) reset_tracking; install_snapshots_full; display_summary ;;
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
                    1) reset_tracking; install_peripheral_tools; display_summary ;;
                    2) fix_logitech_hires_scroll ;;
                    *) log ERROR "Invalid choice"; sleep 2 ;;
                esac
                ;;
            31)
                show_printers_menu
                read -r printer_choice
                case "$printer_choice" in
                    0) continue ;;
                    1) reset_tracking; install_printer_support; display_summary ;;
                    2) install_hp_plugin ;;
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
