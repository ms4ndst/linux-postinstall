#!/bin/bash
# openSUSE Tumbleweed Post-Install Script v1 (zypper + OBS + Packman)
# Menu-driven installer with error handling - openSUSE port of post-install-fedora.sh
# Run as: chmod +x post-install-opensuse.sh && sudo ./post-install-opensuse.sh
#
# ROLLING RELEASE NOTE: Tumbleweed has no fixed release number the way Fedora
# has 42/43/44 - /etc/os-release's VERSION_ID is a YYYYMMDD snapshot stamp
# that changes with every sync, so there is no SUPPORTED_VERSIONS array to
# check against here; check_version() below just confirms
# ID=opensuse-tumbleweed and logs the snapshot date for the record.
#
# PACKAGE MANAGER NOTE (zypper vs dnf5): openSUSE is RPM-based like Fedora,
# so is_installed() below still uses plain `rpm -q` and create_menu_category's
# .desktop-file walk still uses `rpm -ql`/`rpm -q --requires` verbatim - only
# the install/query FRONT END differs. package_exists() specifically does
# NOT use `zypper info` the way Fedora uses `dnf info -q`: a live check
# during development (and github.com/openSUSE/zypper/issues/504) confirmed
# `zypper info` returns exit 0 for a package that does not exist at all,
# which would make it useless as an existence probe. `zypper install
# --dry-run` is documented to return ZYPPER_EXIT_INF_CAP_NOT_FOUND (104)
# specifically when a name matches no available/installed package or
# capability, so that documented exit code is what's actually checked below.
#
# THIRD-PARTY REPO NOTE (OBS + Packman, the RPM Fusion/COPR/AUR analog):
# openSUSE has no single COPR-style flat namespace or AUR-style flat search
# space - the Open Build Service (build.opensuse.org / download.opensuse.org)
# hosts thousands of independent "projects" (home:<user>, devel:<topic>,
# security, hardware, ...), and add_obs_repo() below enables one project's
# repo at a time, the same shape as add_copr in the Fedora script. Every OBS
# project referenced by name below (hardware, devel:languages:go, security,
# ...) was checked against a live build.opensuse.org/software.opensuse.org
# lookup during development - see each call site's own comment for exactly
# what was confirmed and how much to trust it. Packman
# (packman.links2linux.de, mirrored via ftp.gwdg.de) is openSUSE's direct
# RPM-Fusion analog specifically for patent-encumbered multimedia codecs -
# confirmed against openSUSE's own official codec documentation
# (doc.opensuse.org/documentation/tumbleweed/codecs) during development,
# including the exact priority-90 Essentials-repo recipe used in
# bootstrap_repos below.
#
# UPDATE NOTE (zypper dup, not zypper update): Tumbleweed's own docs and the
# wider community consensus (checked live during development) are explicit
# that `zypper up`/`update` is a conservative in-place upgrade that avoids
# repo/vendor changes and can leave stale packages behind release over
# release, while `zypper dup` (dist-upgrade) is the only officially
# recommended way to move a Tumbleweed system forward, since every snapshot
# is effectively a new coordinated release rather than an incremental patch
# stream. See update_packages() below.
#
# SNAPSHOTS NOTE: unlike Fedora (where Btrfs+Snapper is bolted on after the
# fact with an explicitly "unconfirmed" dnf5-hook caveat) and Arch (a from-
# scratch manual setup), Snapper-on-Btrfs is NATIVE to openSUSE - a default
# Tumbleweed install already ships a pre-created Snapper "root" config, the
# snapper-zypp-plugin already installed and taking a real pre/post snapshot
# pair around every YaST/zypper transaction (not best-effort), and
# grub2-snapper-plugin already wired into GRUB's own boot menu. See
# install_snapshots_btrfs below - its job is mostly to VERIFY that's in
# place, not build it from scratch.
#
# PACKAGE NAME CONFIDENCE NOTE (mirrors the Fedora/Arch scripts' own notes):
# the "hard" categories above - third-party/vendor repos, drivers, browsers,
# communication apps, Packman/multimedia, Snapper, and anywhere a comment
# below cites a specific web lookup - were individually verified against
# live vendor docs / openSUSE's own documentation / a live OBS or
# software.opensuse.org search during development. The bulk of "ordinary"
# packages (editors, languages, system utilities - vim, ripgrep, htop, gcc,
# golang, ...) were NOT individually re-verified against a live openSUSE
# system (this was written without one available); they follow well-
# established openSUSE/SUSE naming conventions instead (python3- prefixing,
# "-devel" suffixes, versioned language runtimes like php8/java-21-openjdk,
# apache2 instead of httpd, sqlite3 instead of sqlite, ...). Either way,
# every install goes through package_exists() before safe_install() ever
# runs, so a wrong guess is logged "Not in repos" and skipped rather than
# failing the whole run - the same safety net the Fedora/Ubuntu/Arch
# versions of this script all rely on.

# ── Force a UTF-8 locale for this script's own output ────────────────────────
# Real-world run turned up ✓/✗/↷ (and presumably the box-drawing characters
# just below) rendering as literal \xHH-style escapes instead of the actual
# glyphs. The file itself is verified correct, valid UTF-8 throughout (not
# the bug) - this is an ambient-locale problem: unlike Fedora Workstation,
# which ships en_US.UTF-8 configured out of the box, a minimal/JeOS-style
# openSUSE install can boot with LANG unset or set to POSIX/C, under which
# bash's own handling of multibyte characters in printf format strings goes
# through this byte-escaping fallback. C.UTF-8 is a real glibc locale that
# needs no locale-gen step and is present on every openSUSE install already
# (unlike, say, en_US.UTF-8, which may not be generated) - forcing it here
# only affects this script's own process, not the system's actual locale.
if ! locale -a 2>/dev/null | grep -qi '^C\.UTF-8$\|^C\.utf8$'; then
    echo "WARNING: no C.UTF-8 locale found - checkmark/box-drawing characters below may still render as escapes." >&2
fi
export LC_ALL=C.UTF-8 LANG=C.UTF-8

# ── Catppuccin Mocha palette (24-bit truecolor ANSI) ─────────────────────────
# Same convention as the Fedora/Arch/Ubuntu scripts: colors by SEMANTIC ROLE.
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

OPENSUSE_ID=""; OPENSUSE_SNAPSHOT=""

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

# Detect the running system once, into globals the rest of the script reads.
# Reads /etc/os-release directly, same as the Fedora/Arch scripts.
detect_version() {
    OPENSUSE_ID=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"')
    OPENSUSE_SNAPSHOT=$(grep -oP '(?<=^VERSION_ID=).+' /etc/os-release 2>/dev/null | tr -d '"')
}

check_version() {
    detect_version
    if [ "$OPENSUSE_ID" = "opensuse-tumbleweed" ]; then
        log INFO "Detected openSUSE Tumbleweed (snapshot ${OPENSUSE_SNAPSHOT:-unknown})"
    else
        log WARNING "Designed for openSUSE Tumbleweed (id=opensuse-tumbleweed), detected: ${OPENSUSE_ID:-unknown} ${OPENSUSE_SNAPSHOT:-}"
        log WARNING "openSUSE Leap also uses zypper but ships an older, fixed-version package set (like Fedora, not rolling) - this script assumes Tumbleweed's current rolling package set throughout, so Leap users should expect more 'Not in repos' skips than usual."
        read -p "Continue anyway? [y/N] " -n 1 -r; echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
}

# ── Package-manager front-end (zypper) ───────────────────────────────────────
PM="zypper"
is_installed() { rpm -q "$1" &>/dev/null; }

# See the ROLLING RELEASE / PACKAGE MANAGER header note above for why this is
# `install --dry-run` + exit-code 104, not `zypper info` (which was found to
# return 0 even for a package that doesn't exist anywhere).
package_exists() {
    zypper --non-interactive install --dry-run "$1" &>/dev/null
    [ $? -ne 104 ]
}

# --gpg-auto-import-keys is folded in here (rather than per call site) because
# nearly every use of pm_update in this script follows immediately after
# addrepo-ing a new signed vendor/OBS repo (VS Code, Cursor, NVIDIA, Packman,
# ...) - importing that repo's key non-interactively is the whole point of
# calling refresh right afterward, the zypper equivalent of Fedora's
# `rpm --import <key-url>` calls before its own dnf makecache.
pm_update() {
    zypper --gpg-auto-import-keys --non-interactive refresh
}
# Deliberately does NOT redirect stderr - a real run of this script hit
# several silent "Failed: X" results (VS Code, TeamViewer, Slack) with no
# way to tell WHY short of re-running the exact zypper command by hand.
# safe_install() below captures this output itself and shows a snippet on
# failure; the two other callers (npm fallback installs) already redirect
# everything themselves, so this change is safe for them too.
pm_install() { zypper --non-interactive install "$@"; }

# Enable an OBS (Open Build Service) project as a zypper repo - this script's
# equivalent of add_copr (Fedora) / the AUR fallback (Arch). Idempotency is
# checked by URL substring (not alias) because addrepo -r reads the alias
# from inside the fetched .repo file itself, which does not always match the
# label callers pass in for logging.
add_obs_repo() {
    local project="$1" label="$2"
    local urlpath="${project//:/:\/}"
    local url="https://download.opensuse.org/repositories/${urlpath}/openSUSE_Tumbleweed/"
    if zypper lr -u 2>/dev/null | grep -qF "$url"; then
        return 0
    fi
    if zypper --non-interactive addrepo --refresh -r "${url}${project}.repo" &>/dev/null \
        && pm_update &>/dev/null; then
        return 0
    fi
    log WARNING "OBS project '$project' ($label) not available for openSUSE Tumbleweed right now - continuing without it"
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
        local install_output
        if install_output=$(pm_install "$pkg" 2>&1) || is_installed "$pkg"; then
            INSTALLED_PACKAGES+=("$pkg"); ((TOTAL_INSTALLED++))
            log SUCCESS "Installed: $pkg"
        else
            FAILED_PACKAGES+=("$pkg"); ((TOTAL_FAILED++))
            log ERROR "Failed: $pkg. zypper said: $(printf '%s' "$install_output" | tail -3 | tr '\n' ' ')"
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
    log INFO "Refreshing repository metadata and syncing to the current Tumbleweed snapshot (zypper dup)..."
    # See the UPDATE NOTE in the header comment for why this is `dup`, not
    # `up`/`update`. --no-allow-vendor-change keeps this sync step itself from
    # silently switching a package's origin repo/vendor mid-run (e.g. quietly
    # reverting an OBS/Packman package back to the OSS build or vice versa) -
    # any deliberate vendor change (like install_multimedia_codecs swapping to
    # Packman's ffmpeg) happens explicitly in its own function instead.
    if ! zypper --gpg-auto-import-keys --non-interactive dup --no-allow-vendor-change; then
        log ERROR "System sync failed (zypper dup). Check internet/mirrors."
        read -p "Retry? [y/N] " -n 1 -r; echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then update_packages; else log ERROR "Cannot proceed."; exit 1; fi
    fi
    log SUCCESS "System synced to the current Tumbleweed snapshot."
}

# Ensure OSS + Non-OSS are enabled (a normal graphical/YaST-driven install
# already has both, but a minimal/JeOS image or a hand-rolled install can be
# missing Non-OSS specifically - needed below for e.g. Steam), then enable
# Packman Essentials for multimedia codecs. Runs once, early, before any
# category installs - the openSUSE equivalent of the Fedora script's
# bootstrap_repos (RPM Fusion) / the Arch script's bootstrap_multilib.
bootstrap_repos() {
    log INFO "Ensuring the OSS + Non-OSS repos are enabled..."
    zypper lr -u 2>/dev/null | grep -q '/tumbleweed/repo/oss/' \
        || zypper --non-interactive addrepo -c https://download.opensuse.org/tumbleweed/repo/oss/ repo-oss &>/dev/null
    zypper lr -u 2>/dev/null | grep -q '/tumbleweed/repo/non-oss/' \
        || zypper --non-interactive addrepo -c https://download.opensuse.org/tumbleweed/repo/non-oss/ repo-non-oss &>/dev/null

    # Packman (packman.links2linux.de, mirrored here via ftp.gwdg.de) is
    # openSUSE's RPM-Fusion analog: the community repo carrying the patent-
    # encumbered codec builds (full ffmpeg, GStreamer ugly/bad/libav,
    # vlc-codecs) that openSUSE's own OSS/Non-OSS repos deliberately ship
    # without. "Essentials" (not the full Packman repo) plus a priority of 90
    # is openSUSE's own documented recipe (doc.opensuse.org/documentation/
    # tumbleweed/codecs, cross-checked against the openSUSE Wiki's Packman
    # SDB page) - the priority ensures Packman wins dependency resolution
    # only for the handful of packages it overlaps with OSS on (ffmpeg,
    # libavcodec, ...), not everything else it carries.
    log INFO "Enabling Packman Essentials (multimedia codecs)..."
    if ! zypper lr -u 2>/dev/null | grep -qi 'packman'; then
        zypper --non-interactive addrepo -cfp 90 \
            'https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Tumbleweed/Essentials/' packman-essentials &>/dev/null
    fi
    pm_update &>/dev/null
    if zypper lr -u 2>/dev/null | grep -qi 'packman'; then
        log SUCCESS "Packman Essentials enabled"
    else
        log WARNING "Packman setup failed - proprietary codecs/apps below will mostly fail too (check network access to ftp.gwdg.de)"
    fi
}

install_base() {
    log INFO "Installing base utilities..."
    # gpg2 is openSUSE's own naming (Fedora: gnupg2) - confirmed against
    # current openSUSE package naming. dbus-1-x11 does NOT exist as its own
    # package on current Tumbleweed (checked against live repo metadata -
    # no such package, no provides either); dbus-launch now ships as part
    # of the base "dbus-1" package itself (confirmed via its own manpage,
    # which is filed under the dbus-1 package on Tumbleweed), so that's
    # installed directly instead of the old split-out X11 package.
    batch_install "base" curl wget git gpg2 dconf dbus-1 xdg-user-dirs
}

# Run a gsettings command as the target desktop user with a valid session -
# package-manager-agnostic, copied verbatim from the Fedora/Arch scripts.
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
# bus exists for them. GNOME-session detection has nothing to do with the
# package manager, so this is identical to the Fedora/Arch scripts.
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
        log WARNING "No active desktop session for $user (/run/user/${uid}/bus missing) - run from a logged-in desktop" >&2
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

# Create/append a GNOME app folder. openSUSE Tumbleweed's default desktop is
# GNOME (same as Fedora Workstation) so this schema applies out of the box;
# on a Tumbleweed install with KDE Plasma or another DE instead, gsettings
# simply finds no GNOME session (resolve_desktop_session below returns
# non-zero) and every caller already treats that as a normal, logged skip -
# same behavior as running the Fedora/Arch scripts on a non-GNOME desktop.
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

    # Resolve requested packages to actual .desktop file IDs. Identical logic
    # to the Fedora script's version (rpm -ql / rpm -q --requires) since
    # openSUSE shares RPM with Fedora - only the front-end command (zypper
    # vs dnf) that INSTALLED the package differs, not how rpm itself queries
    # what got installed.
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
                # Meta-package fallback: walk rpm's own dependency list, same
                # as the Fedora script's version.
                local dep line2
                while IFS= read -r dep; do
                    [ -z "$dep" ] && continue
                    is_installed "$dep" || continue
                    while IFS= read -r line2; do [ -n "$line2" ] && found+=("$line2"); done < <(displayable_desktop_files "$dep")
                done < <(rpm -q --requires "$app" 2>/dev/null | awk '{print $1}' | grep -v '^rpmlib\|^/' | sort -u)
            fi
        fi
        # Flatpak-exported apps live in export dirs rpm lookups never see -
        # same handling as the Fedora/Arch scripts.
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
    local f="/var/log/opensuse_post_install_$(date +%Y%m%d_%H%M%S).log"
    {
        echo "=== Log: $(date) ==="; echo "User: $(whoami)"; echo "openSUSE Tumbleweed snapshot: ${OPENSUSE_SNAPSHOT:-unknown}"
        echo "Installed: ${TOTAL_INSTALLED}"; echo "Skipped: ${TOTAL_SKIPPED}"; echo "Failed: ${TOTAL_FAILED}"
        echo; echo "Installed packages:"; printf "  %s\n" "${INSTALLED_PACKAGES[@]}"
        echo; echo "Failed packages:"; printf "  %s\n" "${FAILED_PACKAGES[@]}"
    } > "$f"
    log INFO "Log saved to: $f"
}

# ========== CREATIVE SUITE (Ubuntu Studio / Fedora Jam+Design-Suite replacement) ==========
# Fedora used two real dnf5 comps groups here (Fedora Jam's "audio" group,
# "design-suite"); Arch has no equivalent metapackage/group at all. openSUSE's
# zypper DOES have a native "patterns" concept (`zypper install -t pattern
# <name>`, e.g. kde_plasma, devel_C_C++), but a live check during development
# found no multimedia/creative pattern remotely as broad as Fedora's two
# groups - so, like the Arch script, every sub-category below is hand-curated
# to cover the same real-world app set. Package names track Arch's own
# research closely where the two distros' upstream availability overlaps
# (both ship the same GTK/Qt creative apps directly), with openSUSE-specific
# naming swapped in where confirmed (e.g. ImageMagick's actual openSUSE
# package casing, Packman-only codec pieces).
install_creative_audio() {
    batch_install "Audio Production" \
        ardour audacity carla hydrogen guitarix qjackctl \
        lsp-plugins calf pavucontrol easytag soundconverter
    install_cliamp
}

# cliamp (https://www.cliamp.stream/) - terminal Winamp-style music player/
# streamer (Spotify/Qobuz/YouTube Music/Plex/Jellyfin/30,000+ radio stations).
# Not packaged for openSUSE/OBS - vendor curl|sh installer fetches a prebuilt
# release binary into ~/.local/bin, identical to the Fedora/Arch scripts'
# versions (nothing package-manager-specific here).
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
    batch_install "Graphics & Design" gimp inkscape krita blender darktable pitivi scribus
    batch_install "Graphics (extra)" flameshot ImageMagick GraphicsMagick optipng jpegoptim pngquant libwebp-tools
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

# Bind Print Screen to Flameshot - a gsettings/GNOME feature, package-manager-
# agnostic, identical to the Fedora/Arch scripts.
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
# Requires Packman (bootstrap_repos) to already be enabled. openSUSE's own
# documented recipe (doc.opensuse.org/documentation/tumbleweed/codecs,
# cross-checked against a live Packman install guide) is a vendor-change
# dist-upgrade scoped to just Packman's overlapping packages FIRST - actively
# replacing the OSS-repo ffmpeg/GStreamer builds already on disk with
# Packman's patent-unencumbered ones - THEN installing the rest with
# --from packman-essentials, the same "swap" concept as Fedora's
# `dnf swap ffmpeg-free ffmpeg`. Package names (gstreamer-plugins-{good,bad,
# ugly,libav}, vlc-codecs) are taken verbatim from that documented recipe,
# not guessed.
install_multimedia_codecs() {
    log INFO "Installing multimedia codecs (Packman)..."
    if ! zypper lr -u 2>/dev/null | grep -qi 'packman'; then
        log WARNING "Packman isn't enabled - run bootstrap first"; return 1
    fi
    log INFO "Replacing OSS-repo ffmpeg/GStreamer builds with Packman's (vendor-change dist-upgrade, Packman packages only)..."
    if zypper --gpg-auto-import-keys --non-interactive dist-upgrade --from packman-essentials --allow-vendor-change &>/dev/null; then
        INSTALLED_PACKAGES+=("ffmpeg/GStreamer (Packman swap)"); ((TOTAL_INSTALLED++))
        log SUCCESS "Swapped ffmpeg/GStreamer packages to Packman's builds"
    else
        FAILED_PACKAGES+=("ffmpeg/GStreamer (Packman swap)"); ((TOTAL_FAILED++))
        log WARNING "Packman vendor-change dup step failed or had nothing to swap - continuing anyway"
    fi
    batch_install "Multimedia (Packman)" \
        gstreamer-plugins-good gstreamer-plugins-bad gstreamer-plugins-ugly gstreamer-plugins-libav vlc-codecs
}

# ========== NVIDIA DRIVER ==========
# Opt-in only, same reasoning as the Fedora/Arch scripts: real hardware-
# specific state, not something to install blind. Adds NVIDIA's own official
# openSUSE repo (download.nvidia.com/opensuse/tumbleweed - confirmed live
# during development, maintained directly by NVIDIA) and installs the G06
# OPEN kernel-module series (nvidia-open-driver-G06-signed-kmp-default),
# which - per openSUSE's own SDB:NVIDIA_drivers wiki page and SUSE's NVIDIA
# package maintainer's own blog, both checked during development - covers
# GeForce 700-series and newer, including Blackwell (RTX 50), the same
# "prefer the open kernel modules" reasoning as Fedora's akmod-nvidia-open.
# The "-signed-" variant is pre-signed against openSUSE's own Secure-Boot
# shim key, so unlike Fedora's akmod/DKMS path this does NOT need a manual
# MOK-enrollment reboot on a system that already trusts openSUSE's shim from
# install time - the Secure Boot check below is a fallback warning only, for
# systems where that isn't the case.
install_nvidia_driver() {
    local msg="Install the NVIDIA driver (open kernel modules, G06 series + CUDA-capable utils)?\n\nOpen kernel modules, not the legacy closed ones - covers GeForce 700-series and newer, including Blackwell (RTX 50/RTX PRO). Only do this on a machine with an NVIDIA GPU."
    local do_it=false
    if command -v whiptail &>/dev/null; then
        whiptail --yesno "$msg" --yes-button "Install" --no-button "Skip" 14 76 && do_it=true
    else
        echo -e "$msg [y/N]:"
        read -r REPLY
        { [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; } && do_it=true
    fi
    if ! $do_it; then
        SKIPPED_PACKAGES+=("nvidia-open-driver-G06"); ((TOTAL_SKIPPED++)); log INFO "Skipped NVIDIA driver"; return 0
    fi

    log INFO "Adding NVIDIA's official openSUSE repo (download.nvidia.com)..."
    zypper lr NVIDIA &>/dev/null \
        || zypper --non-interactive addrepo --refresh https://download.nvidia.com/opensuse/tumbleweed NVIDIA &>/dev/null
    pm_update &>/dev/null

    batch_install "NVIDIA Driver" \
        nvidia-open-driver-G06-signed-kmp-default nvidia-video-G06 nvidia-gl-G06 nvidia-compute-G06

    if is_installed nvidia-open-driver-G06-signed-kmp-default || is_installed nvidia-video-G06; then
        if command -v mokutil &>/dev/null && mokutil --sb-state 2>/dev/null | grep -qi "enabled"; then
            log INFO "Secure Boot is ON - the -signed- G06 package is pre-signed against openSUSE's own Secure-Boot shim key, so this normally loads without any manual MOK-enrollment step on a system that already trusts that shim (the default after a standard openSUSE install)."
            log WARNING "If the kernel module still refuses to load after reboot, that shim trust is missing - enroll it manually: sudo mokutil --import /var/lib/shim-signed/mok/MOK.der (path may vary) and follow the blue MOKManager prompt on the next reboot."
        else
            log INFO "Secure Boot is off/not detected - reboot when convenient to load the new kernel module: sudo reboot"
        fi
        log INFO "Verify after reboot with: nvidia-smi"
    fi
}

# ========== OBS PACKAGE INSTALLER (opi) - Terra/Chaotic-AUR/yay analog ==========
# openSUSE has no single second-tier catch-all repo the way Fedora has Terra
# or Arch has Chaotic-AUR/yay - every OBS project used elsewhere in this
# script (hardware, devel:languages:go, security, ...) is added individually,
# on demand, by add_obs_repo(). "opi" (github.com/openSUSE/opi) IS openSUSE's
# own official answer to "I just want to search/install whatever OBS package
# covers this" - a real openSUSE.org project, packaged directly in
# Tumbleweed's own OSS repo (confirmed via a live software.opensuse.org /
# GitHub lookup during development: `zypper install opi` needs no extra repo
# at all). Offered here, opt-in, as the closest genuine parity item to
# Fedora's Terra / Arch's yay bootstrap - it does not itself install
# anything beyond the `opi` tool; running `opi <name>` afterward is left to
# the user, the same way yay itself doesn't install packages until invoked.
install_opi_helper() {
    if command -v opi &>/dev/null; then
        SKIPPED_PACKAGES+=("opi"); ((TOTAL_SKIPPED++)); log INFO "Already installed: opi"; return 0
    fi
    local msg="Install 'opi' (OBS Package Installer)?\n\nopenSUSE's own official CLI for searching and installing ANY package from the Open Build Service, Packman, or several vendor repos (Chrome, TeamViewer, ...) on demand - the closest openSUSE equivalent to Arch's yay or Fedora's Terra repo. Ships directly in Tumbleweed's own OSS repo - no extra repo needed."
    local do_it=false
    if command -v whiptail &>/dev/null; then
        whiptail --yesno "$msg" --yes-button "Install" --no-button "Skip" 14 76 && do_it=true
    else
        echo -e "$msg [y/N]:"
        read -r REPLY
        { [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; } && do_it=true
    fi
    if ! $do_it; then
        SKIPPED_PACKAGES+=("opi"); ((TOTAL_SKIPPED++)); log INFO "Skipped opi"; return 0
    fi
    batch_install "OBS Package Installer" opi
    is_installed opi && log INFO "opi installed - try it with: opi codecs   (or: opi <any package name>)"
}

# ========== DISPLAYLINK DRIVER ==========
# GENUINE GAP, flagged rather than papered over (per this repo's own
# convention for cases like this - see the Omarchy-detection notes in the
# Arch script for the same spirit): unlike Fedora (displaylink-rpm publishes
# prebuilt per-release RPMs as GitHub release assets) and Arch (a real,
# actively-maintained AUR "displaylink" package pulling in evdi-dkms
# automatically), a live search during development found NO maintained,
# ready-to-install openSUSE package or OBS project for the DisplayLink
# evdi kernel module + DisplayLinkManager. What exists is a documented
# MANUAL process (0xcaffee.blog's "opensuse-tumbleweed-evdi" write-up, and
# the sinfomicien/displaylink-evdi-opensuse GitHub project) that patches and
# rebuilds Ubuntu's own driver tarball by hand for the current kernel - not
# something that can be safely automated here without either hardcoding a
# fragile multi-step patch/build sequence or silently attempting something
# that's known to break on kernel updates. Rather than guess at a plausible-
# looking repo/package name, this installs only the DKMS build prerequisites
# and prints the manual path.
install_displaylink_driver() {
    local msg="DisplayLink (USB/dock display adapters) has no maintained openSUSE package or OBS project (verified during development - see this function's own comment). Install DKMS build prerequisites and print manual instructions?"
    local do_it=false
    if command -v whiptail &>/dev/null; then
        whiptail --yesno "$msg" --yes-button "Continue" --no-button "Skip" 14 76 && do_it=true
    else
        echo -e "$msg [y/N]:"
        read -r REPLY
        { [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; } && do_it=true
    fi
    if ! $do_it; then
        SKIPPED_PACKAGES+=("displaylink"); ((TOTAL_SKIPPED++)); log INFO "Skipped DisplayLink driver"; return 0
    fi
    batch_install "DisplayLink build prerequisites" dkms kernel-devel kernel-default-devel make gcc
    log WARNING "No automated DisplayLink install path exists for openSUSE Tumbleweed (checked live during development - no maintained package or OBS project was found)."
    log WARNING "Manual path (evdi + DisplayLinkManager, patched from Ubuntu's driver tarball for the current kernel):"
    log WARNING "  1. Read: https://0xcaffee.blog/posts/opensuse-tumbleweed-evdi/"
    log WARNING "  2. Or try the community project: https://github.com/sinfomicien/displaylink-evdi-opensuse"
    log WARNING "Both rebuild against your CURRENT kernel and need to be re-run after kernel updates on a rolling release like Tumbleweed - there is no dkms-autoinstall-on-boot package doing this for you the way Fedora's/Arch's do."
    SKIPPED_PACKAGES+=("displaylink (manual path printed above)"); ((TOTAL_SKIPPED++))
}

# ========== DRIVERS & EXTRA REPOS ==========
install_drivers_and_repos() {
    install_nvidia_driver
    install_opi_helper
    install_displaylink_driver
}

# ========== PERIPHERALS (new - no Ubuntu-script equivalent) ==========
# Solaar isn't in openSUSE's own OSS repo. The "hardware" OBS project
# (build.opensuse.org/package/show/hardware/solaar) is openSUSE's own
# hardware-support project for packages that don't make it into OSS
# directly - confirmed as the current, actively-updated location (v1.1.16 at
# the time of writing) via a live OBS lookup during development. Unlike
# Fedora's solaar-udev, openSUSE's solaar package ships its udev rules
# bundled directly - no separate package needed.
install_peripheral_tools() {
    add_obs_repo hardware "Peripheral tools (Solaar)"
    batch_install "Peripheral Management" solaar
    if is_installed solaar; then
        log INFO "Solaar installed - GUI: 'solaar', CLI: 'solaar config' for battery/DPI/gesture/scroll-feature control of Logitech HID++ mice and keyboards"
    fi
}

# Applies the specific fix confirmed on this hardware: MX Anywhere 3S over
# Bluetooth with its "Scroll Wheel Resolution" HID++ feature disabled.
# Fully package-manager-agnostic (Solaar's CLI is identical regardless of
# distro) - ported verbatim from the Fedora/Arch scripts, see their own
# comments for the full confidence caveats on the exact setting name.
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
# CUPS + HPLIP cover the open-source rendering path for most printers, same
# reasoning as the Fedora/Arch scripts' own comment here. An earlier pass
# here assumed system-config-printer had no openSUSE package - re-checked
# directly against live Tumbleweed repo metadata and it's actually a real,
# literal package name in the default OSS repo, so it's installed after
# all. yast2-printer was dropped from Tumbleweed entirely (confirmed -
# openSUSE's own wiki/mailing list say it was pulled because it no longer
# worked), so there's no YaST equivalent to fall back to; CUPS' own web UI
# at https://localhost:631 (started by cups.service below) is the other
# supported way to configure printers now.
install_printer_support() {
    batch_install "Printer Support" cups hplip system-config-printer
    systemctl enable --now cups.service &>/dev/null || true
}

# hp-plugin's installed/not-installed state lives in /var/lib/hp/hplip.state -
# identical logic to the Fedora/Arch scripts (hplip's own CLI tool, nothing
# package-manager-specific here).
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

# ========== FILESYSTEM SNAPSHOTS & BACKUP ==========
# See the SNAPSHOTS NOTE in the header comment: unlike Fedora/Arch, this is
# NATIVE to openSUSE - a default Tumbleweed install already has Btrfs, a
# pre-created Snapper "root" config, snapper-zypp-plugin taking a real pre/
# post snapshot pair around every YaST/zypper transaction, the timeline/
# cleanup timers enabled, and grub2-snapper-plugin wired into GRUB - all
# verified against openSUSE's own Snapper documentation and the
# openSUSE:Snapper_Tutorial wiki page during development. So unlike the
# Fedora/Arch versions of this function (which BUILD the setup), this one
# mostly VERIFIES it and fills in anything a hand-partitioned/JeOS/non-
# default install might have skipped.

detect_root_fstype() {
    findmnt -no FSTYPE / 2>/dev/null
}

install_snapshots_full() {
    local fstype; fstype=$(detect_root_fstype)
    log INFO "Detected root filesystem: ${fstype:-unknown}"
    if [ "$fstype" = "btrfs" ]; then
        install_snapshots_btrfs
    else
        log WARNING "Root is not Btrfs (detected: ${fstype:-unknown}) - unusual for a default Tumbleweed install; Snapper needs Btrfs, falling back to Timeshift (rsync mode)"
        install_snapshots_timeshift
    fi
}

install_snapshots_btrfs() {
    # yast2-snapper (the YaST module, official in openSUSE's own repos) is
    # the idiomatic Snapper GUI here, not a third-party app - btrfs-assistant
    # isn't in any official openSUSE repo (only unofficial OBS home: projects),
    # so it's deliberately not used. NOTE: yast2-snapper ships on Tumbleweed
    # and Leap 15.6, but Leap 16.0 dropped the YaST stack entirely (verified
    # against openSUSE's own package search) - batch_install's existing
    # failure handling (non-fatal, logged, continues) covers that gap rather
    # than needing a version check here.
    batch_install "Snapshot Tools" snapper snapper-zypp-plugin grub2-snapper-plugin btrfsmaintenance yast2-snapper

    if ! snapper list-configs 2>/dev/null | grep -qw root; then
        log INFO "No Snapper 'root' config found (unusual on a default Tumbleweed install) - creating one..."
        if snapper -c root create-config / 2>/dev/null; then
            log SUCCESS "Snapper config 'root' created"
        else
            log WARNING "Snapper config creation failed - your subvolume layout may need manual setup: sudo snapper -c root create-config /"
        fi
    else
        log SUCCESS "Snapper config 'root' already exists (pre-created by the openSUSE installer, as expected on Tumbleweed)"
    fi

    if systemctl enable --now snapper-timeline.timer snapper-cleanup.timer 2>/dev/null; then
        log SUCCESS "snapper-timeline.timer + snapper-cleanup.timer enabled (scheduled snapshots + retention)"
    else
        log WARNING "Could not enable snapper timers - enable manually: sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer"
    fi

    if is_installed snapper-zypp-plugin; then
        log SUCCESS "snapper-zypp-plugin installed - every future zypper/YaST transaction now gets an automatic pre/post snapshot pair (list with: snapper list -t pre-post)"
    fi

    # grub2-snapper-plugin ships as a subpackage of the grub2 stack and lists
    # snapshots as bootable GRUB entries once the config is regenerated -
    # confirmed against openSUSE's own grub2 documentation during
    # development. Only meaningful when GRUB is actually the bootloader in
    # use (a systemd-boot install, less common but possible, would no-op here).
    if is_installed grub2-snapper-plugin && [ -d /boot/grub2 ]; then
        log INFO "Regenerating GRUB config to pick up snapshot boot entries..."
        if command -v grub2-mkconfig &>/dev/null && grub2-mkconfig -o /boot/grub2/grub.cfg &>/dev/null; then
            log SUCCESS "GRUB now lists Btrfs snapshots as bootable entries"
        else
            log WARNING "grub2-mkconfig failed - regenerate manually: sudo grub2-mkconfig -o /boot/grub2/grub.cfg"
        fi
    else
        log INFO "GRUB not detected as the bootloader (or grub2-snapper-plugin unavailable) - skipping boot-menu integration"
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

# Ad-hoc snapshot, callable any time from the Snapshots submenu.
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

# Launches whichever GUI is available. YaST's own Snapper module
# (yast2-snapper, `yast2 snapper`) is openSUSE's NATIVE Snapper GUI - a
# genuinely simpler story than Fedora's/Arch's reach for the cross-distro
# btrfs-assistant, since it's the same YaST framework already on the system
# either way and runs fine over ncurses without needing a graphical session
# at all (unlike a GTK app, so this deliberately does NOT need
# resolve_desktop_session/su-as-desktop-user the way the Fedora/Arch versions
# of this function do).
snapshot_open_gui() {
    if command -v yast2 &>/dev/null && (rpm -q yast2-snapper &>/dev/null || safe_install yast2-snapper); then
        log INFO "Launching YaST's Snapper module..."
        yast2 snapper
        return $?
    fi
    local user uid
    if command -v timeshift-gtk &>/dev/null && read -r user uid < <(resolve_desktop_session); then
        local home; home=$(getent passwd "$user" | cut -d: -f6)
        sudo -u "$user" HOME="$home" XDG_RUNTIME_DIR="/run/user/${uid}" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
            nohup timeshift-gtk >/dev/null 2>&1 &
        log SUCCESS "Launched Timeshift GUI"
        sleep 1
        return 0
    fi
    log WARNING "No snapshot GUI available yet - run Full Setup first (option 1)"
    return 1
}

# ========== CODE EDITORS ==========
install_code_editors() {
    batch_install "Code Editors" vim neovim emacs nano geany gnome-text-editor gedit kate
    install_vscode; install_sublime_text
    install_zed
    install_gram
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

# Identical to the Fedora/Arch scripts' version - git clone + Nordic theme
# drop-in, nothing package-manager-specific here except the neovim self-heal.
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

# VS Code from Microsoft's official yum repo. Microsoft's own docs only list
# apt/yum instructions explicitly, but that yum repo is a plain baseurl+
# gpgkey INI file with no dnf-specific macros - confirmed live during
# development that `zypper addrepo` consumes it exactly the way it consumes
# Brave's/Vivaldi's/Azure CLI's equivalent Microsoft/vendor yum repos
# elsewhere in this script, so this is a verified working path, not a guess.
install_vscode() {
    if command -v code &>/dev/null || is_installed code; then
        SKIPPED_PACKAGES+=("code"); ((TOTAL_SKIPPED++)); log INFO "VS Code already installed"; return 0
    fi
    log INFO "Installing VS Code (Microsoft's official yum repo)..."
    rpm --import https://packages.microsoft.com/keys/microsoft.asc 2>/dev/null
    if ! zypper lr vscode &>/dev/null; then
        local addrepo_err
        if ! addrepo_err=$(zypper --non-interactive addrepo --refresh https://packages.microsoft.com/yumrepos/vscode vscode 2>&1); then
            log WARNING "Adding the VS Code repo failed: $(printf '%s' "$addrepo_err" | tail -3 | tr '\n' ' ')"
        fi
    fi
    pm_update
    safe_install code
}

# Sublime Text from its official rpm repo - confirmed to explicitly document
# a zypper-compatible `zypper addrepo -g -f <repo-url>` install path on
# download.sublimetext.com/rpm/stable/x86_64/sublime-text.repo during
# development (unlike VS Code above, Sublime HQ's own docs cover openSUSE
# directly, not just yum).
install_sublime_text() {
    if command -v subl &>/dev/null || is_installed sublime-text; then
        SKIPPED_PACKAGES+=("sublime-text"); ((TOTAL_SKIPPED++)); log INFO "Sublime Text already installed"; return 0
    fi
    log INFO "Installing Sublime Text (official rpm repo)..."
    rpm -v --import https://download.sublimetext.com/sublimehq-rpm-pub.gpg 2>/dev/null
    zypper lr sublime-text &>/dev/null \
        || zypper --non-interactive addrepo -g -f https://download.sublimetext.com/rpm/stable/x86_64/sublime-text.repo &>/dev/null
    pm_update
    safe_install sublime-text
}

# Bruno API client - no rpm/OBS package from usebruno.com, only Flatpak/
# AppImage officially, so Flathub is the correct (not a compromise) choice.
install_bruno() { flatpak_install_flathub com.usebruno.Bruno "Bruno"; }

# Zed (https://zed.dev) - GPU-accelerated code editor. No openSUSE/OBS
# package; the vendor's own install script is the supported Linux path and
# drops the binary in ~/.local, so it must run as the invoking user rather
# than root - identical to the Fedora/Arch scripts.
install_zed() {
    local u="$SUDO_USER"; [ "$u" = "root" ] && u=""
    local check_cmd install_cmd
    if [ -n "$u" ]; then
        check_cmd="su - $u -c 'command -v zed'"
        install_cmd="su - $u -c 'curl -f https://zed.dev/install.sh | sh'"
    else
        check_cmd="command -v zed"
        install_cmd="curl -f https://zed.dev/install.sh | sh"
    fi
    if eval "$check_cmd" &>/dev/null || command -v zed &>/dev/null; then
        SKIPPED_PACKAGES+=("zed"); ((TOTAL_SKIPPED++)); log INFO "Already installed: zed"; return 0
    fi
    log INFO "Installing Zed (native installer)..."
    if eval "$install_cmd" 2>/dev/null && { eval "$check_cmd" &>/dev/null || command -v zed &>/dev/null; }; then
        INSTALLED_PACKAGES+=("zed"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: zed (~/.local/bin - ensure it's on your PATH)"; return 0
    fi
    FAILED_PACKAGES+=("zed"); ((TOTAL_FAILED++))
    log WARNING "Zed install failed - try: curl -f https://zed.dev/install.sh | sh"; return 0
}

# Gram (https://codeberg.org/GramEditor/gram) - a Zed-editor fork. Not
# packaged for openSUSE/OBS - Codeberg's own release assets include a self-
# contained Linux tarball, extracted into /opt exactly as the Fedora/Arch
# scripts do (nothing distro-specific in this mechanism).
install_gram() {
    if command -v gram &>/dev/null; then
        SKIPPED_PACKAGES+=("gram"); ((TOTAL_SKIPPED++)); log INFO "Already installed: gram"; return 0
    fi
    log INFO "Installing Gram (editor, tarball release)..."
    local t; t=$(mktemp -d)
    local url="https://codeberg.org/GramEditor/gram/releases/download/3.3.0/gram-linux-x86_64-3.3.0.tar.gz"
    if curl -fsSL --retry 2 -o "$t/gram.tar.gz" "$url" 2>/dev/null \
        && tar -xzf "$t/gram.tar.gz" -C "$t" 2>/dev/null \
        && [ -d "$t/gram.app" ]; then
        rm -rf /opt/gram.app
        mv "$t/gram.app" /opt/gram.app
        ln -sf /opt/gram.app/bin/gram /usr/local/bin/gram
        mkdir -p /usr/share/applications /usr/share/icons/hicolor/scalable/apps /usr/share/icons/hicolor/symbolic/apps
        cp /opt/gram.app/share/applications/gram.desktop /usr/share/applications/gram.desktop
        cp /opt/gram.app/share/icons/hicolor/scalable/apps/app.liten.Gram.svg /usr/share/icons/hicolor/scalable/apps/ 2>/dev/null
        cp /opt/gram.app/share/icons/hicolor/symbolic/apps/app.liten.Gram-symbolic.svg /usr/share/icons/hicolor/symbolic/apps/ 2>/dev/null
        command -v gtk-update-icon-cache &>/dev/null && gtk-update-icon-cache -f /usr/share/icons/hicolor &>/dev/null
        rm -rf "$t"
        INSTALLED_PACKAGES+=("gram"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: gram (/opt/gram.app, symlinked to /usr/local/bin/gram)"; return 0
    fi
    rm -rf "$t"
    FAILED_PACKAGES+=("gram"); ((TOTAL_FAILED++))
    log WARNING "Gram download failed - get it from https://codeberg.org/GramEditor/gram/releases"; return 0
}

# ========== PYTHON ==========
install_python() {
    # openSUSE names Python-ecosystem packages with the "python3-" prefix
    # consistently (unlike Fedora's unprefixed "ipython") - python3 itself is
    # the system default already, no separate "python-is-python3" shim needed.
    batch_install "Python" python3 python3-devel python3-pip python3-virtualenv python3-ipython python3-pipx
}

# ========== WEB DEVELOPMENT ==========
install_web_dev() {
    install_nodejs_full
    batch_install "Web Server - Nginx" nginx
    # openSUSE names the Apache package "apache2" (not "httpd" - that's the
    # Red Hat/Fedora binary name only). Installed for availability but not
    # enabled/started - nginx owns :80.
    batch_install "Web Server - Apache (not started)" apache2 php8-fpm php8-cli composer
}

# Node.js ships in Tumbleweed's own repos at a current version via the plain
# "nodejs"/"npm" alias packages (confirmed live during development - the
# same nodejsNN-versioned packages Arch/Fedora also carry exist here too,
# but the unversioned alias resolves to the current default like Fedora's
# plain "nodejs").
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
    # gradle isn't in Tumbleweed's default oss repo - confirmed via a real
    # run of this script failing on it, then verified on software.opensuse.org:
    # it's published by the Java:packages OBS project (maven/ant/junit and
    # the JDK itself ARE in the default repo, so only gradle needs this).
    add_obs_repo "Java:packages" "Gradle"
    batch_install "Java" java-21-openjdk java-21-openjdk-devel gradle maven ant junit
    # IntelliJ IDEA Community has no openSUSE/OBS package - Flathub is the
    # real equivalent of the Fedora/Ubuntu scripts' own choice here.
    flatpak_install_flathub com.jetbrains.IntelliJ-IDEA-Community "IntelliJ IDEA Community"
}

# ========== C/C++ ==========
install_c_cpp() {
    # ninja (not "ninja-build") is openSUSE's own current name - confirmed.
    # pkg-config: an earlier version of this script had this backwards -
    # "pkgconf-pkg-config" IS openSUSE's real current name (confirmed via
    # a real Tumbleweed rpm listing on opensuse.pkgs.org after a real run
    # of this script failed on the plain "pkg-config" name), not a Fedora
    # rename to avoid.
    batch_install "C/C++" \
        gcc gcc-c++ gcc-fortran clang cmake make ninja ccache \
        autoconf automake libtool m4 bison flex gettext-tools pkgconf-pkg-config \
        cppcheck valgrind gdb ltrace strace
}

# ========== GO ==========
install_go() {
    if command -v go &>/dev/null; then
        SKIPPED_PACKAGES+=("go"); ((TOTAL_SKIPPED++)); log INFO "Go already installed"; return 0
    fi
    # Confirmed: openSUSE's official package is the plain "go" alias
    # (resolving to the current version, same as Arch's "go" package) - no
    # third-party repo needed the way Fedora sometimes falls back to a
    # tarball download.
    if package_exists go; then
        batch_install "Go" go
    else
        log INFO "go not in repos - installing latest upstream tarball to /usr/local/go..."
        local ver="1.22.5" arch; arch=$(uname -m)
        case "$arch" in x86_64) arch="amd64";; aarch64) arch="arm64";; esac
        local t; t=$(mktemp -d)
        if curl -fsSL "https://go.dev/dl/go${ver}.linux-${arch}.tar.gz" -o "$t/go.tar.gz" 2>/dev/null; then
            rm -rf /usr/local/go && tar -C /usr/local -xzf "$t/go.tar.gz"
            ln -sf /usr/local/go/bin/go /usr/local/bin/go
            ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
            INSTALLED_PACKAGES+=("go"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: Go ${ver} (/usr/local/go)"
        else
            FAILED_PACKAGES+=("go"); ((TOTAL_FAILED++)); log WARNING "Go tarball download failed"
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
    # openSUSE versions its PHP package with a bare "php8" prefix (not
    # Fedora's "php-" style) - the names themselves check out against a
    # live package listing. But every real listing found for them (checked
    # after the gradle/pkg-config misses below turned up the same shape of
    # gap) points at the devel:languages:php OBS project specifically, with
    # no default-repo path shown anywhere - add it defensively, same as
    # Java:packages for gradle above.
    add_obs_repo "devel:languages:php" "PHP"
    # php-xml (no "8") is deliberate, not a typo: XML support ships bundled
    # into the base php8 package itself rather than as its own php8-xml
    # subpackage (checked against the real devel:languages:php repo listing
    # - no such subpackage exists) - "php-xml" is the virtual capability
    # name php8 itself provides, which zypper resolves to it directly.
    batch_install "PHP" \
        php8-cli php8-fpm php8-devel php8-mysql php8-pgsql php8-sqlite \
        php8-gd php8-curl php8-mbstring php-xml php8-zip composer
}

# ========== RUBY ==========
install_ruby() {
    # ruby/ruby-devel are real unversioned package names on Tumbleweed, but
    # gem subpackages are NOT - there's no unversioned "rubygem-bundler"
    # alias or provides (checked against live repo metadata), only the
    # version-prefixed "ruby4.0-rubygem-bundler" (Tumbleweed's Ruby version
    # as of this check) - package_exists still gates it, so a future Ruby
    # bump that changes this prefix fails this one package gracefully
    # rather than the whole run.
    batch_install "Ruby" ruby ruby-devel ruby4.0-rubygem-bundler
}

# ========== .NET ==========
# Microsoft's own rpm packages for openSUSE have a DOCUMENTED, live
# compatibility break on Tumbleweed specifically: dotnet-runtime-deps still
# depends on the legacy libopenssl1_0_0 soname, which Tumbleweed's rolling
# repos have already dropped in favor of openssl 3.x only (confirmed via a
# live github.com/dotnet/runtime issue during development, filed against
# Tumbleweed exactly for this) - so unlike Fedora/Ubuntu (native packages)
# or Arch (native dotnet-sdk/aspnet-runtime in [extra]), routing through
# Microsoft's own repo/rpm here is a known-broken path, not a safe default.
# Microsoft's OWN documented fallback for exactly this situation - "for
# distros/architectures without a working package repo, use the
# dotnet-install.sh script instead" - is used as the PRIMARY method instead:
# it drops a self-contained SDK into ~/.dotnet with no system OpenSSL/ICU
# package-version coupling at all, sidestepping the break entirely.
install_dotnet() {
    if command -v dotnet &>/dev/null; then
        SKIPPED_PACKAGES+=(".NET SDK"); ((TOTAL_SKIPPED++)); log INFO "Already installed: dotnet"; return 0
    fi
    local u="$SUDO_USER"
    if [ -z "$u" ] || [ "$u" = "root" ]; then
        log WARNING "No target user (run via sudo from a user session) - skipping .NET SDK (dotnet-install.sh installs per-user, into ~/.dotnet)"
        FAILED_PACKAGES+=(".NET SDK"); ((TOTAL_FAILED++)); return 1
    fi
    log INFO "Installing .NET SDK (Microsoft's dotnet-install.sh - see this function's comment for why Microsoft's own rpm repo is skipped on Tumbleweed)..."
    if su - "$u" -c 'curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh && bash /tmp/dotnet-install.sh --channel LTS' 2>/dev/null \
        && [ -x "$(eval echo ~"$u")/.dotnet/dotnet" ]; then
        INSTALLED_PACKAGES+=(".NET SDK"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: .NET SDK (~/.dotnet - add it to PATH: export PATH=\$HOME/.dotnet:\$PATH)"
        return 0
    fi
    FAILED_PACKAGES+=(".NET SDK"); ((TOTAL_FAILED++))
    log WARNING ".NET SDK install failed - try manually: curl -fsSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel LTS"
    return 0
}

# ========== GENERAL DEV TOOLS ==========
install_dev_tools() {
    batch_install "Dev Tools" \
        jq tig subversion make cmake \
        autoconf automake bison flex gettext-tools pkgconf-pkg-config man man-pages less
    install_bruno
}

# ========== DATABASES ==========
install_databases() {
    batch_install "Databases" mariadb sqlite3 sqlitebrowser memcached
    # Valkey is a real, current openSUSE Tumbleweed package (confirmed live
    # during development - "valkey" plus a "valkey-compat-redis" compat
    # package for anything that shells out to a literal `redis-cli`/
    # `redis-server` name) - same Redis-license-driven fork Fedora and Arch
    # both moved to.
    batch_install "Valkey (Redis-compatible)" valkey valkey-compat-redis
    if package_exists postgresql-server; then
        batch_install "PostgreSQL" postgresql-server postgresql
        if is_installed postgresql-server && [ ! -d /var/lib/pgsql/data ]; then
            log INFO "Initializing PostgreSQL database cluster..."
            # sudo -u postgres (not `su - postgres`) forces a real shell
            # regardless of the postgres system account's configured login
            # shell - the same reasoning the Arch script's own comment gives
            # for the identical initdb step there.
            sudo -u postgres bash -c "initdb --locale en_US.UTF-8 -D /var/lib/pgsql/data" 2>/dev/null \
                && systemctl enable --now postgresql 2>/dev/null \
                && log SUCCESS "PostgreSQL initialized and started" \
                || log WARNING "initdb failed - initialize manually"
        fi
    fi
    if is_installed mariadb && [ ! -d /var/lib/mysql/mysql ]; then
        log INFO "Initializing MariaDB data directory..."
        mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql 2>/dev/null \
            && systemctl enable --now mariadb 2>/dev/null \
            && log SUCCESS "MariaDB initialized and started" \
            || log WARNING "mariadb-install-db failed - initialize manually"
    fi
    install_dbeaver
}

# DBeaver CE - no official openSUSE/OBS package with a strong trust tier was
# found (only scattered personal home: projects, e.g. home:marec2000:server:
# database, checked live during development and deliberately NOT used here -
# too low a confidence tier to hardcode per this repo's own "verified, not
# assumed" standard). DBeaver's own site DOES publish a generic, self-
# contained standalone rpm for exactly this situation
# (dbeaver.io/files/dbeaver-ce-latest-stable.x86_64.rpm) - `zypper install
# <url>` resolves its (minimal, mostly-bundled-JRE) dependencies against
# Tumbleweed's normal repos the same way the Fedora script installs Google
# Chrome's generic rpm directly.
install_dbeaver() {
    if is_installed dbeaver-ce; then
        SKIPPED_PACKAGES+=("dbeaver-ce"); ((TOTAL_SKIPPED++)); log INFO "Already installed: dbeaver-ce"; return 0
    fi
    log INFO "Installing DBeaver CE (official standalone rpm)..."
    if zypper --non-interactive install https://dbeaver.io/files/dbeaver-ce-latest-stable.x86_64.rpm &>/dev/null \
        && is_installed dbeaver-ce; then
        INSTALLED_PACKAGES+=("dbeaver-ce"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: dbeaver-ce"
    else
        FAILED_PACKAGES+=("dbeaver-ce"); ((TOTAL_FAILED++))
        log WARNING "DBeaver install failed - try manually: zypper install https://dbeaver.io/files/dbeaver-ce-latest-stable.x86_64.rpm"
    fi
}

# ========== CONTAINERS & VMS ==========
install_containers() {
    # docker + docker-compose are both real, current Tumbleweed OSS-repo
    # packages (confirmed live during development - no separate Docker Inc.
    # repo needed, matching the Fedora/Arch scripts' own preference for the
    # distro package over download.docker.com).
    batch_install "Containers" docker docker-compose podman
    if is_installed docker; then
        systemctl enable --now docker 2>/dev/null
        [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ] && usermod -aG docker "$SUDO_USER" 2>/dev/null \
            && log INFO "Added $SUDO_USER to the docker group (log out/in to take effect)"
    fi
    # Incus ships directly in Tumbleweed's own repos (confirmed live during
    # development - openSUSE's rolling nature means it tracks current Incus
    # releases directly, no COPR/AUR-style side repo needed the way Fedora
    # needed one before Incus landed natively there).
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

# Virtio-Win: the Windows guest drivers needed for a Windows VM under KVM/
# QEMU. No openSUSE/OBS package was found for this (checked live during
# development) - falls back directly to the same one-shot upstream ISO
# download the Fedora/Arch scripts use as their OWN fallback, since that URL
# (fedorapeople.org's "stable-virtio" symlink) is upstream Red Hat/Fedora-
# virt-SIG infrastructure, not a Fedora-only artifact - it's the same
# ISO every distro's users download by hand today regardless of package
# manager.
install_virtio_win() {
    if [ -e /var/lib/libvirt/images/virtio-win.iso ]; then
        SKIPPED_PACKAGES+=("Virtio-Win drivers"); ((TOTAL_SKIPPED++)); log INFO "Already installed: Virtio-Win drivers"; return 0
    fi
    download_virtio_win_iso
}

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

# Docker sets the legacy iptables FORWARD chain's default policy to DROP,
# silently killing internet access for every libvirt NAT-networked VM when
# both Containers and Virtualization are installed - fully package-manager-
# agnostic (iptables/systemd), identical reasoning and fix to the Fedora/Arch
# scripts' own version of this function.
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
# Steam is non-free software and lives in openSUSE's own Non-OSS repo
# (confirmed live during development against openSUSE's own package listing
# and Wiki Steam page) - bootstrap_repos above already ensures Non-OSS is
# enabled. Unlike Arch, openSUSE needs NO separate multilib/32-bit-repo
# bootstrap step at all: its x86_64 repos already carry the needed 32-bit
# "-32bit" compat packages directly (Steam's own package pulls in what it
# needs), the same "no extra step" situation Fedora's .i686 multilib already
# has.
install_gaming() {
    batch_install "Gaming" steam lutris gamemode mangohud
}

# ========== OFFICE & PRODUCTIVITY ==========
install_office() {
    batch_install "Office" libreoffice okular evince zathura pandoc
}

# ========== SYSTEM UTILITIES ==========
install_system_utils() {
    # Charm publishes their own yum repo for glow - same generic INI format
    # already proven zypper-compatible elsewhere in this script (VS Code,
    # Brave, ...), so this is ported unchanged from the Fedora script with
    # dnf -> zypper swapped.
    if [ ! -f /etc/zypp/repos.d/charm.repo ]; then
        log INFO "Adding Charm's yum repo (for glow)..."
        rpm --import https://repo.charm.sh/yum/gpg.key 2>/dev/null
        zypper --non-interactive addrepo --refresh https://repo.charm.sh/yum/ charm &>/dev/null
        pm_update
    fi
    # wireshark is split into the base/CLI package and a separate Qt GUI
    # package on openSUSE (wireshark-ui-qt) - confirmed live during
    # development, the same kind of split Arch has (wireshark-cli/
    # wireshark-qt) under different names.
    batch_install "System Utils" \
        htop iotop sysstat glances \
        nethogs iftop nload vnstat tcpdump wireshark wireshark-ui-qt \
        lsof strace ltrace valgrind gdb \
        tmux screen zsh fish fzf ripgrep tree ncdu rsync unzip bat glow
}

# ========== ANDROID TOOLS ==========
install_android_tools() {
    batch_install "Android Tools" android-tools
    # scrcpy has no confirmed-trustworthy openSUSE package: only scattered
    # personal home: OBS projects exist (home:ecsos at v4.1, home:zzndb at
    # v3.1 - checked live during development), a similar trust tier to the
    # Fedora script's own zeno/scrcpy COPR pick. home:ecsos is used here as
    # the more current of the two, with the same caveat Fedora's COPR note
    # carries: if it goes stale, swap the project name below.
    add_obs_repo home:ecsos "scrcpy"
    batch_install "Android Tools (scrcpy)" scrcpy
}

# ========== AI TOOLS ==========
# Almost entirely package-manager-agnostic (vendor curl|bash installers, npm
# globals, Flathub) - ported near-verbatim from the Fedora/Arch scripts.
# Only Cursor and IntelliJ (already handled in install_java) actually change.
install_ai_tools() {
    log INFO "Installing AI Tools..."
    install_ollama
    install_alpaca
    install_jan
    install_localai
    install_claude_code
    install_claude_desktop
    install_gemini_cli
    install_vibe_cli
    install_opencode
    install_cursor
    install_lmstudio
    install_neuralinverse
    install_invokeai
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
# rpm/OBS package exists), same as the Fedora/Ubuntu/Arch scripts.
install_alpaca() { flatpak_install_flathub com.jeffser.Alpaca "Alpaca"; }

# Jan (https://www.jan.ai/) - local-first, OpenAI-alternative desktop chat
# client with its own local model runner (llama.cpp-based) plus support for
# remote providers. Flathub-only (no vendor rpm/deb/AUR package), same
# pattern as Alpaca above.
install_jan() { flatpak_install_flathub ai.jan.Jan "Jan"; }

# LocalAI - OpenAI-compatible local inference server. No rpm/OBS package
# exists; the GitHub release ships a plain, self-contained binary per arch,
# so resolve the latest release via the GitHub API and drop it into
# /usr/local/bin, same approach as every other distro script here.
install_localai() {
    if command -v local-ai &>/dev/null; then
        SKIPPED_PACKAGES+=("local-ai"); ((TOTAL_SKIPPED++)); log INFO "Already installed: local-ai"; return 0
    fi
    local arch; arch=$(uname -m)
    case "$arch" in x86_64) arch="amd64" ;; aarch64) arch="arm64" ;; esac
    log INFO "Looking up the latest LocalAI release ($arch)..."
    local url
    url=$(curl -fsSL "https://api.github.com/repos/mudler/LocalAI/releases/latest" 2>/dev/null \
        | grep -oP '"browser_download_url":\s*"\K[^"]*linux-'"$arch"'(?=")')
    if [ -z "$url" ]; then
        FAILED_PACKAGES+=("local-ai"); ((TOTAL_FAILED++))
        log WARNING "No prebuilt LocalAI release for $arch - get it from https://github.com/mudler/LocalAI/releases"; return 0
    fi
    local t; t=$(mktemp -d)
    log INFO "Installing LocalAI (GitHub release binary)..."
    if curl -fL --retry 2 -o "$t/local-ai" "$url" 2>/dev/null; then
        chmod +x "$t/local-ai"; mv "$t/local-ai" /usr/local/bin/local-ai
        rm -rf "$t"
        INSTALLED_PACKAGES+=("local-ai"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: local-ai (/usr/local/bin/local-ai - run 'local-ai run' to start the server)"; return 0
    fi
    rm -rf "$t"
    FAILED_PACKAGES+=("local-ai"); ((TOTAL_FAILED++))
    log WARNING "LocalAI download failed - get it from https://github.com/mudler/LocalAI/releases"; return 0
}

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
# openSUSE has no official Anthropic repo either. Same real dnf/yum-style
# repo the Fedora script uses, ported unchanged (zypper consumes the same
# INI file).
install_claude_desktop() {
    if command -v claude-desktop-unofficial &>/dev/null || is_installed claude-desktop-unofficial; then
        SKIPPED_PACKAGES+=("claude-desktop-unofficial"); ((TOTAL_SKIPPED++)); log INFO "Already installed: claude-desktop-unofficial"; return 0
    fi
    log INFO "Installing Claude Desktop (unofficial rpm repo)..."
    zypper lr claude-desktop-unofficial &>/dev/null \
        || zypper --non-interactive addrepo -r https://pkg.claude-desktop-debian.dev/rpm/claude-desktop-unofficial.repo &>/dev/null
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

# Neural Inverse - AI coding IDE. Not packaged for openSUSE/OBS - vendor
# curl|bash installer, identical mechanism to the Fedora/Arch scripts.
install_neuralinverse() {
    local u="$SUDO_USER"; [ "$u" = "root" ] && u=""
    local check_cmd install_cmd
    if [ -n "$u" ]; then
        check_cmd="su - $u -c 'command -v neuralinverse'"
        install_cmd="su - $u -c 'curl -fsSL https://neuralinverse.com/sh | bash -s -- --ide'"
    else
        check_cmd="command -v neuralinverse"
        install_cmd="curl -fsSL https://neuralinverse.com/sh | bash -s -- --ide"
    fi
    if eval "$check_cmd" &>/dev/null; then
        SKIPPED_PACKAGES+=("neuralinverse"); ((TOTAL_SKIPPED++)); log INFO "Already installed: neuralinverse"; return 0
    fi
    log INFO "Installing Neural Inverse IDE (native installer)..."
    if eval "$install_cmd" 2>/dev/null && eval "$check_cmd" &>/dev/null; then
        INSTALLED_PACKAGES+=("neuralinverse"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: neuralinverse (~/.local/bin - ensure it's on your PATH)"; return 0
    fi
    FAILED_PACKAGES+=("neuralinverse"); ((TOTAL_FAILED++))
    log WARNING "Neural Inverse install failed - try: curl -fsSL https://neuralinverse.com/sh | bash -s -- --ide"; return 0
}

# InvokeAI (invoke.ai) - "a free and open-source creative engine for
# AI-powered image generation" (local Stable Diffusion/Flux/SDXL web UI +
# node-based workflows, runs on an NVIDIA or AMD GPU). No AUR/COPR/
# openSUSE/Ubuntu package and no Flathub listing (confirmed via a live
# search) - the project's own README says "To get started with Invoke,
# Download the Launcher", pointing at a SEPARATE repo
# (github.com/invoke-ai/launcher, an Electron app that manages installing/
# updating the actual Python/PyTorch backend on first run) rather than the
# main invoke-ai/InvokeAI repo, which ships no binary release assets at
# all (confirmed via the GitHub API - InvokeAI itself is PyPI-only). The
# launcher's own releases always publish a version-independent
# "Invoke.Community.Edition-latest.AppImage" asset (confirmed live via a
# HEAD request), so - unlike install_claude_desktop above - no GitHub-API
# version lookup is needed, just a direct download of that stable URL.
install_invokeai() {
    if command -v invoke-ai &>/dev/null; then
        SKIPPED_PACKAGES+=("invoke-ai"); ((TOTAL_SKIPPED++)); log INFO "Already installed: invoke-ai"; return 0
    fi
    log INFO "Installing InvokeAI (Launcher AppImage - no distro package exists)..."
    local t; t=$(mktemp -d)
    local app_url="https://github.com/invoke-ai/launcher/releases/latest/download/Invoke.Community.Edition-latest.AppImage"
    if curl -L -f --retry 2 -o "$t/invoke-ai.AppImage" "$app_url" 2>/dev/null; then
        chmod +x "$t/invoke-ai.AppImage"; mv "$t/invoke-ai.AppImage" /usr/local/bin/invoke-ai
        cat > /usr/share/applications/invoke-ai.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=InvokeAI
GenericName=AI Image Generation
Comment=Local Stable Diffusion/Flux/SDXL creative engine (Invoke Community Edition)
Exec=invoke-ai %F
Icon=invoke-ai
Terminal=false
Categories=Graphics;Utility;
EOF
        chmod 644 /usr/share/applications/invoke-ai.desktop
        rm -rf "$t"
        INSTALLED_PACKAGES+=("invoke-ai"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: invoke-ai (AppImage, /usr/local/bin/invoke-ai - needs an NVIDIA/AMD GPU; downloads its own PyTorch/model backend on first run)"; return 0
    fi
    rm -rf "$t"
    FAILED_PACKAGES+=("invoke-ai"); ((TOTAL_FAILED++))
    log WARNING "InvokeAI download failed - get it from https://github.com/invoke-ai/launcher/releases"; return 0
}

# Cursor's official yum repo (downloads.cursor.com/yumrepo) is the SAME
# generic INI format already proven zypper-compatible elsewhere in this
# script (VS Code, Brave, ...) - ported unchanged from the Fedora script
# rather than reaching for a lower-trust community OBS package the way the
# Arch script reached for the AUR's cursor-bin.
install_cursor() {
    if command -v cursor &>/dev/null || is_installed cursor; then
        SKIPPED_PACKAGES+=("cursor"); ((TOTAL_SKIPPED++)); log INFO "Already installed: cursor"; return 0
    fi
    log INFO "Installing Cursor (official yum repo)..."
    rpm --import https://downloads.cursor.com/keys/anysphere.asc 2>/dev/null
    cat > /etc/zypp/repos.d/cursor.repo <<'EOF'
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

# LM Studio - GUI desktop app for local LLMs. No rpm/OBS package (Windows/
# macOS installers + a Linux AppImage only), but it has an official Flathub
# package (confirmed via a live Flathub API search, matching the Fedora/
# Ubuntu/Arch scripts' own conclusion) - so that's the right path here too.
install_lmstudio() { flatpak_install_flathub ai.lmstudio.lm-studio "LM Studio"; }

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
    configure_mousiki
}

install_gnome_extensions() {
    local user uid
    if ! read -r user uid < <(resolve_desktop_session); then
        log INFO "No active desktop session - skipping GNOME extensions"; return 0
    fi
    command -v pipx &>/dev/null || safe_install python3-pipx
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

configure_mousiki() {
    local msg="Build and install Mousiki (terminal music player) from source?"
    local do_it=false
    if command -v whiptail &>/dev/null; then
        whiptail --yesno "$msg" --yes-button "Build" --no-button "Skip" 12 72 && do_it=true
    else
        echo -e "$msg [y/N]:"
        read -r REPLY
        { [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; } && do_it=true
    fi
    if $do_it; then install_mousiki; else log INFO "Skipped Mousiki"; fi
}
# github.com/itzender5820/mousiki - no openSUSE package, no binary release
# (the one GitHub release is a source zip) - source-build-only. The
# project's own setup.sh only handles apt-get/pacman/dnf and explicitly
# errors out on anything else, so unlike the Arch/Fedora/Ubuntu versions of
# this function, there's no real upstream zypper list to mirror here - this
# dependency list is this rice's own, built by analogy to the dnf one
# (same gcc-c++/make split Fedora uses, same zypper "python3-" prefix this
# script's own Python-tooling section already establishes).
install_mousiki() {
    log INFO "Installing Mousiki build dependencies..."
    batch_install "Mousiki build deps" cmake gcc-c++ make ffmpeg yt-dlp python3 python3-pip
    local t; t=$(mktemp -d)
    if ! git clone --depth 1 https://github.com/itzender5820/mousiki "$t/mousiki" 2>/dev/null; then
        rm -rf "$t"; log WARNING "Mousiki clone failed (needs network access to github.com)"; return 1
    fi
    (
        cd "$t/mousiki" || exit 1
        cmake -B build 2>/dev/null && cmake --build build -j"$(nproc)" 2>/dev/null
    )
    if [ -x "$t/mousiki/build/mousiki" ]; then
        install -m 755 "$t/mousiki/build/mousiki" /usr/local/bin/mousiki
        log SUCCESS "Mousiki built and installed to /usr/local/bin/mousiki"
        setup_mousiki_user_config "$t/mousiki"
    else
        log WARNING "Mousiki build failed"
    fi
    rm -rf "$t"
}
# Lyrics (optional - the upstream setup.sh treats this pip package as
# soft/non-fatal too) and first-run config, both scoped to the real desktop
# user rather than root, matching this script's own user-config pattern
# elsewhere (e.g. LazyVim).
setup_mousiki_user_config() {
    local src="$1"
    [ -z "$SUDO_USER" ] || [ "$SUDO_USER" = "root" ] && return 0
    local uh; uh=$(eval echo ~"$SUDO_USER" 2>/dev/null)
    [ -z "$uh" ] && return 0
    su - "$SUDO_USER" -c "pip3 install --user requests" &>/dev/null || true
    su - "$SUDO_USER" -c "mkdir -p '$uh/.config/mousiki' '$uh/.config/yt-dlp'"
    if [ ! -f "$uh/.config/mousiki/config.txt" ] && [ -f "$src/config.txt" ]; then
        cp "$src/config.txt" "$uh/.config/mousiki/config.txt"
        chown "$SUDO_USER":"$SUDO_USER" "$uh/.config/mousiki/config.txt"
    fi
    if ! grep -q "player_client=android" "$uh/.config/yt-dlp/config" 2>/dev/null; then
        su - "$SUDO_USER" -c "echo '--extractor-args \"youtube:player_client=android\"' >> '$uh/.config/yt-dlp/config'"
    fi
}

install_gui_tools() {
    # openSUSE names the GNOME Shell extensions manager "gnome-extensions"
    # (no "-app" suffix, unlike its upstream/Fedora name) - confirmed
    # against the live package listing, summary "Extensions app for GNOME
    # Shell" matches exactly.
    batch_install "GUI Tools" \
        gnome-tweaks \
        gnome-extensions \
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
    # Papirus/Breeze/Adwaita all ship directly in Tumbleweed's own repos.
    # openSUSE names the Breeze icon package "breeze5-icons" (KDE Frameworks
    # 5 naming) rather than Fedora's "breeze-icon-theme" - it's actually a
    # virtual capability now, resolved by zypper to the real "kf6-breeze-
    # icons" package (KDE's Frameworks-6 rename), confirmed live against
    # repo metadata; the old bare "breeze-icons" name has no package and no
    # provides at all on current Tumbleweed, so it was dropped rather than
    # left as permanent dead weight. No confirmed numix-icon-theme/obsidian-
    # icon-theme package or OBS project was found for openSUSE (checked live
    # during development) - the vinceliuice-family installers below (Qogir/
    # WhiteSur/Vimix) plus Newaita cover the same "extra icon variety" role
    # via upstream install.sh scripts instead.
    batch_install "Icon Sets" \
        papirus-icon-theme \
        breeze5-icons \
        adwaita-icon-theme
    install_qogir_icons
    install_whitesur_icons
    install_vimix_icons
    install_newaita_icons
}

# Shared install mechanics for the vinceliuice family of icon theme
# generators (Qogir, WhiteSur, Vimix, Colloid). Their destination logic is
# $UID-aware (root -> /usr/share/icons) with no other hardcoded $HOME
# dependency, so this runs directly as root - package-manager-agnostic,
# identical to the Fedora/Arch scripts.
install_vinceliuice_repo() {
    local label="$1" repo="$2" slug="$3" kind="$4"; shift 4
    local extra_args=("$@")

    local marker="/var/lib/opensuse-postinstall-themes/${slug}.done"
    if [ -f "$marker" ]; then
        SKIPPED_PACKAGES+=("$label $kind"); ((TOTAL_SKIPPED++)); log INFO "Already installed: $label $kind"; return 0
    fi
    command -v gtk-update-icon-cache &>/dev/null || safe_install gtk3-tools

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
    # GTK3 murrine engine + gnome-themes-extras assets - openSUSE names the
    # murrine package "gtk2-engine-murrine" rather than Fedora's
    # "gtk-murrine-engine", and its own theme-assets package is
    # "gnome-themes-extras" (plural "extras", confirmed against the live
    # package listing - Fedora's "gnome-themes-extra" is singular).
    batch_install "Lycia Theme Dependencies" gtk2-engine-murrine sassc gnome-themes-extras
    local t; t=$(mktemp -d); chmod 755 "$t"; chown "$user" "$t" 2>/dev/null
    if ! su - "$user" -c "git clone --depth 1 https://github.com/Aevstiel/Lycia-Theme.git '$t/src'" 2>/dev/null; then
        rm -rf "$t"; FAILED_PACKAGES+=("Lycia theme"); ((TOTAL_FAILED++))
        log WARNING "Lycia theme clone failed (needs network access to github.com)"; return 1
    fi
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
    # openSUSE names the Breeze cursor theme "breeze5-cursors" (KDE
    # Frameworks 5 naming) - it's a virtual capability now, resolved by
    # zypper to the real "breeze6-cursors" package (KDE's Frameworks-6
    # rename), confirmed live against repo metadata. The old bare
    # "breeze-cursors" name has no package and no provides at all on
    # current Tumbleweed, so it was dropped rather than left as permanent
    # dead weight.
    batch_install "Cursor Themes" breeze5-cursors
}

# Unlike Arch (which has native ttf-*-nerd packages), openSUSE has no
# confirmed native Nerd Font packages (checked live during development) -
# this is 100% the same GitHub-release download method the Fedora script
# uses, unchanged.
install_nerd_fonts() {
    log INFO "Installing Nerd Fonts..."
    mkdir -p /usr/share/fonts/truetype/nerd-fonts
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
    # setup.sh has zypper-detection in some versions of this upstream
    # project; if this particular checkout doesn't recognize zypper it fails
    # gracefully and the fallback branch below still lands a working
    # .bashrc/starship/fastfetch config either way.
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
# CAVEAT (flagged more prominently than most categories, mirroring the
# Fedora/Arch scripts' own): several classic pentest tools are not in
# Tumbleweed's own OSS repo. The "security" OBS project
# (build.opensuse.org/package/show/security/...) is openSUSE's own curated
# home for exactly this category (hashcat confirmed to live there
# specifically; aircrack-ng/hydra are ALSO mirrored into openSUSE:Factory
# directly - both checked live during development) - enabled once, up front,
# for the whole category rather than per-package. A handful of others live
# in their own curated subprojects instead of "security" itself: hping
# ships there as "hping3" and torsocks lives in the "network" OBS project
# (both confirmed against real Tumbleweed repo metadata), and steghide is
# in "security:privacy" (same confirmed way). gobuster and ettercap were
# DROPPED from this list entirely - the only Tumbleweed builds found for
# either live in random personal home:* OBS projects, which is exactly the
# unvetted trust tier this script's own header comment says to avoid; they
# were not silently swapped for a shaky repo.
install_security_tools() {
    add_obs_repo security "Security tools"
    add_obs_repo network "Network tools (hping3, torsocks)"
    add_obs_repo "security:privacy" "steghide"

    batch_install "Security - Network" \
        nmap masscan hping3 bind-utils

    batch_install "Security - Web" \
        nikto sqlmap whatweb wfuzz

    batch_install "Security - Cracking & Wireless" \
        john hashcat hydra aircrack-ng macchanger

    batch_install "Security - Forensics & RE" \
        radare2 binwalk sleuthkit steghide yara perl-Image-ExifTool

    batch_install "Security - Hardening" \
        lynis chkrootkit rkhunter clamav fail2ban aide

    # firewalld has been openSUSE's own default firewall manager since Leap
    # 15.0 / Tumbleweed (replacing the older SuSEfirewall2 outright, per a
    # live check of openSUSE's own Firewalld wiki page during development) -
    # not a swap-in the way it is for Ubuntu's ufw, this IS the native answer.
    batch_install "Security - Firewall & Privacy" \
        firewalld firewall-config openvpn wireguard-tools proxychains-ng torsocks keepassxc
}

install_security_defensive() {
    add_obs_repo security "Security tools"

    batch_install "Defensive - Hardening & Integrity" \
        lynis chkrootkit rkhunter aide audit

    batch_install "Defensive - Anti-Malware" \
        clamav

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
    install_rclone_cloud_storage
}

# rclone-based cloud storage mount (e.g. Google Drive) - WM-agnostic and
# CLI-first, so it works the same under i3 as under any desktop shell.
# Unlike a GNOME Online Accounts/gvfs mount, this needs no
# graphical-session.target (i3's exec autostart never activates that
# target - see the i3/xdg-desktop-portal gap noted elsewhere), just a plain
# systemd --user unit gated on default.target, which starts with any login
# session regardless of WM.
#
# `rclone config` is interactive (OAuth happens in a browser) so it can't be
# scripted here - this installs rclone/fuse3, creates the mount point, and
# drops a ready-to-enable systemd user unit for a remote named "gdrive".
install_rclone_cloud_storage() {
    batch_install "rclone (cloud storage)" rclone fuse3
    if ! is_installed rclone; then
        log WARNING "rclone install failed - skipping mount setup"
        return 1
    fi
    if [ -z "$SUDO_USER" ] || [ "$SUDO_USER" = "root" ]; then
        log WARNING "No invoking user detected - skipping rclone mount unit (run 'rclone config' and set up the systemd unit manually)"
        return 0
    fi
    local uh; uh=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    local mount_dir="$uh/GoogleDrive" unit_dir="$uh/.config/systemd/user"
    local unit_file="$unit_dir/rclone-gdrive.service"
    mkdir -p "$mount_dir" "$unit_dir"
    if [ ! -f "$unit_file" ]; then
        cat > "$unit_file" <<'EOF'
[Unit]
Description=rclone mount (gdrive) for Google Drive
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/rclone mount gdrive: %h/GoogleDrive --vfs-cache-mode writes
ExecStop=/usr/bin/fusermount3 -u %h/GoogleDrive
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
    fi
    chown -R "$SUDO_USER:$SUDO_USER" "$mount_dir" "$unit_dir"
    su - "$SUDO_USER" -c "systemctl --user daemon-reload" 2>/dev/null
    log SUCCESS "rclone installed - mount point $mount_dir and unit $unit_file ready"
    log WARNING "Cloud storage needs one-time manual setup as $SUDO_USER:"
    log WARNING "  1. rclone config   (create a remote named 'gdrive', OAuth opens in a browser)"
    log WARNING "  2. loginctl enable-linger $SUDO_USER   (optional: mount starts even without staying logged in)"
    log WARNING "  3. systemctl --user enable --now rclone-gdrive.service   (mounts ~/GoogleDrive on login)"
}

install_docker_standalone() {
    batch_install "Docker (standalone)" docker docker-compose
    if is_installed docker; then
        systemctl enable --now docker 2>/dev/null
        [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ] && usermod -aG docker "$SUDO_USER" 2>/dev/null
    fi
    install_docker_libvirt_forward_fix
}

# Azure CLI from Microsoft's official yum repo - same generic INI format
# already proven zypper-compatible elsewhere in this script, and the SAME
# repo the Fedora script uses (Microsoft's own docs even show a
# --pivots=zypper tab for this exact repo, confirmed live during
# development - one of the few vendor repos here Microsoft explicitly
# documents for openSUSE, not just yum/dnf).
install_azure_cli() {
    if command -v az &>/dev/null; then
        SKIPPED_PACKAGES+=("azure-cli"); ((TOTAL_SKIPPED++)); log INFO "Azure CLI already installed"; return 0
    fi
    log INFO "Installing Azure CLI (Microsoft's official yum repo, zypper-documented)..."
    rpm --import https://packages.microsoft.com/keys/microsoft.asc 2>/dev/null
    zypper lr azure-cli &>/dev/null \
        || zypper --non-interactive addrepo --name 'Azure CLI' --check https://packages.microsoft.com/yumrepos/azure-cli azure-cli &>/dev/null
    pm_update
    safe_install azure-cli
}

# lazygit is a confirmed package in Tumbleweed's own OSS repo (checked
# live against the real repo metadata), so no OBS project or `go install`
# fallback is needed - the fallback below is only for the case Tumbleweed
# drops it from OSS in the future.
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
# Unlike Fedora (Flathub pre-configured out of the box), Tumbleweed ships
# Flatpak itself in its default repos but does NOT preconfigure the Flathub
# remote (confirmed live during development against Flathub's own openSUSE
# setup page) - closer to the Ubuntu script's situation than Fedora's. Kept
# for the same handful of apps with NO better openSUSE-native source
# (Signal, Telegram, Spotify, Zen Browser, Floorp, Bruno, Alpaca, LM Studio,
# IntelliJ IDEA CE) - everything else in this script goes through zypper, an
# OBS project, or a vendor repo first.
flatpak_install_flathub() {
    local app_id="$1" label="$2"
    if ! command -v flatpak &>/dev/null; then
        batch_install "Flatpak" flatpak
    fi
    if ! command -v flatpak &>/dev/null; then
        FAILED_PACKAGES+=("$label"); ((TOTAL_FAILED++))
        log WARNING "flatpak unavailable - install manually: flatpak install flathub $app_id"; return 0
    fi
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
    if flatpak info "$app_id" &>/dev/null; then
        SKIPPED_PACKAGES+=("$label"); ((TOTAL_SKIPPED++)); log INFO "Already installed: $label (flatpak)"; return 0
    fi
    log INFO "Installing $label (Flatpak from Flathub)..."
    if flatpak install -y --noninteractive flathub "$app_id" 2>/dev/null || flatpak info "$app_id" &>/dev/null; then
        INSTALLED_PACKAGES+=("$label"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: $label (flatpak) - launch with: flatpak run $app_id"; return 0
    fi
    FAILED_PACKAGES+=("$label"); ((TOTAL_FAILED++))
    log WARNING "$label install failed - try: flatpak install flathub $app_id"; return 0
}

# ========== BROWSERS ==========
# Every browser here was individually researched against its vendor's actual
# docs/repo files during development - Brave/Vivaldi/LibreWolf/Chrome all
# have real openSUSE-targeted (or generically zypper-compatible) repos;
# Zen Browser and Floorp genuinely have none (same conclusion the Fedora
# script reaches, for the same reason: Ablaze/Zen's own docs point to
# Flathub as the Linux path).
install_browsers() {
    install_brave
    install_vivaldi
    install_edge
    install_chrome
    install_librewolf
    install_zen
    install_floorp
}

# Brave's own install docs explicitly cover openSUSE with a zypper recipe
# (brave.com/linux, checked live during development) - not an assumption.
install_brave() {
    if is_installed brave-browser; then
        SKIPPED_PACKAGES+=("brave-browser"); ((TOTAL_SKIPPED++)); log INFO "Already installed: brave-browser"; return 0
    fi
    log INFO "Installing Brave (official repo, openSUSE-documented)..."
    rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc 2>/dev/null
    zypper lr brave-browser-rpm-release &>/dev/null \
        || zypper --non-interactive addrepo -r https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo &>/dev/null
    pm_update
    safe_install brave-browser
}

# Vivaldi publishes an openSUSE-specific repo file (repo.vivaldi.com/archive/
# vivaldi-suse.repo, distinct from their Fedora one) - confirmed live during
# development, not the same URL as install_edge/install_chrome below.
install_vivaldi() {
    if is_installed vivaldi-stable; then
        SKIPPED_PACKAGES+=("vivaldi-stable"); ((TOTAL_SKIPPED++)); log INFO "Already installed: vivaldi-stable"; return 0
    fi
    log INFO "Installing Vivaldi (official openSUSE repo)..."
    rpm --import https://repo.vivaldi.com/archive/linux_signing_key.pub 2>/dev/null
    zypper lr vivaldi &>/dev/null \
        || zypper --non-interactive addrepo -r https://repo.vivaldi.com/archive/vivaldi-suse.repo &>/dev/null
    pm_update
    safe_install vivaldi-stable
}

# Microsoft Edge from Microsoft's official yum repo. Microsoft's own docs
# focus on the RPM/DNF form of this repo rather than explicitly documenting
# zypper the way they do for Azure CLI above, but it's the same generic INI
# format already proven zypper-compatible elsewhere in this script - checked
# live during development.
install_edge() {
    if is_installed microsoft-edge-stable; then
        SKIPPED_PACKAGES+=("microsoft-edge-stable"); ((TOTAL_SKIPPED++)); log INFO "Already installed: microsoft-edge-stable"; return 0
    fi
    log INFO "Installing Microsoft Edge (official yum repo)..."
    rpm --import https://packages.microsoft.com/keys/microsoft.asc 2>/dev/null
    zypper lr microsoft-edge &>/dev/null \
        || zypper --non-interactive addrepo --name 'Microsoft Edge' --check https://packages.microsoft.com/yumrepos/edge microsoft-edge &>/dev/null
    pm_update
    safe_install microsoft-edge-stable
}

# Google Chrome - self-registers its own repo on install, same as the
# Fedora script; confirmed working on openSUSE via zypper directly (a plain
# rpm bootstrap install, then Google's own postinst wires up the ongoing repo).
install_chrome() {
    if is_installed google-chrome-stable; then
        SKIPPED_PACKAGES+=("google-chrome-stable"); ((TOTAL_SKIPPED++)); log INFO "Already installed: google-chrome-stable"; return 0
    fi
    log INFO "Installing Google Chrome (official rpm, self-registers its repo)..."
    rpm --import https://dl.google.com/linux/linux_signing_key.pub 2>/dev/null
    zypper --non-interactive install https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm 2>/dev/null
    if is_installed google-chrome-stable; then
        INSTALLED_PACKAGES+=("google-chrome-stable"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: google-chrome-stable"
    else
        FAILED_PACKAGES+=("google-chrome-stable"); ((TOTAL_FAILED++)); log WARNING "Chrome install failed"
    fi
}

# LibreWolf's own official rpm repo - LibreWolf's own maintainers have
# confirmed (in a public Codeberg issue, checked live during development)
# that this Fedora-targeted repo installs and updates fine on openSUSE too,
# even without dedicated openSUSE repodata; native openSUSE support is
# tracked upstream but not done yet.
install_librewolf() {
    if is_installed librewolf; then
        SKIPPED_PACKAGES+=("librewolf"); ((TOTAL_SKIPPED++)); log INFO "Already installed: librewolf"; return 0
    fi
    log INFO "Installing LibreWolf (official rpm repo, works on openSUSE per upstream)..."
    zypper lr librewolf &>/dev/null \
        || zypper --non-interactive addrepo -fr https://rpm.librewolf.net/librewolf-repo.repo librewolf &>/dev/null
    pm_update
    safe_install librewolf
}

# Zen Browser and Floorp: confirmed no vendor rpm/OBS package exists for
# either - Flathub is the vendors' own documented Linux path, not a
# compromise, same conclusion the Fedora script reaches.
install_zen()    { flatpak_install_flathub app.zen_browser.zen "Zen"; }
install_floorp() { flatpak_install_flathub one.ablaze.floorp "Floorp"; }

# ========== COMMUNICATION ==========
install_communication() {
    install_signal
    install_discord
    install_telegram
    install_teams
}

# Signal Desktop - confirmed no rpm/yum repo exists anywhere for any RPM
# distro (the commonly-cited updates.signal.org/desktop/yum/ URL 404s, same
# finding as the Fedora script) - Flathub is the only real option.
install_signal() { flatpak_install_flathub org.signal.Signal "Signal"; }

# Discord - no vendor repo and no confirmed trustworthy openSUSE/OBS package
# (checked live during development) - Flathub instead, matching the Fedora
# script's own fallback for the same reason (though Fedora's primary path,
# RPM Fusion, doesn't exist here at all to try first).
install_discord() { flatpak_install_flathub com.discordapp.Discord "Discord"; }

# Telegram Desktop - no official openSUSE package; the community OBS
# projects that do exist (home:13ilya, home:kosht, checked live during
# development) are personal home: projects, too low a trust tier to
# hardcode per this repo's "verified, not assumed" standard - Flathub's
# actively-maintained org.telegram.desktop (already the Fedora script's own
# fallback pick) is used directly instead.
install_telegram() { flatpak_install_flathub org.telegram.desktop "Telegram"; }

# Microsoft Teams via teams-for-linux (repo.teamsforlinux.de) - same
# community project the Fedora/Ubuntu scripts use, generic INI repo format.
install_teams() {
    if command -v teams-for-linux &>/dev/null; then
        SKIPPED_PACKAGES+=("teams-for-linux"); ((TOTAL_SKIPPED++)); log INFO "Already installed: teams-for-linux"; return 0
    fi
    log INFO "Installing Microsoft Teams (teams-for-linux)..."
    curl -1sLf -o /etc/zypp/repos.d/teams-for-linux.repo https://repo.teamsforlinux.de/rpm/teams-for-linux.repo 2>/dev/null
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

# Spotify - confirmed no rpm/repo from Spotify for any RPM distro - Flathub
# (community-maintained) is the only real option, same as the Fedora script.
install_spotify() { flatpak_install_flathub com.spotify.Client "Spotify"; }

# Slack - no openSUSE-targeted repo exists (their packagecloud.io repo is
# yum/apt-only and, per the Fedora script's own finding, permanently stale
# anyway). Slack's downloads page embeds a current version-specific .rpm
# link built against a generic RHEL/CentOS baseline (an ".el8" file name) -
# scraped the same way the Fedora script scrapes it. One openSUSE-specific
# wrinkle confirmed via a REAL run of this script (not just research): that
# rpm needs the X11 screensaver extension library, which Fedora/RHEL name
# libXScrnSaver but openSUSE packages as libXss1 (had this backwards in an
# earlier version of this script - corrected here after the real install
# failed on it) - installed defensively first so the rpm install itself
# doesn't fail on it.
#
# NOTE ON THE FEDORA SCRIPT'S disable_stale_slack_repo(): deliberately not
# ported. That function exists there because Slack's rpm %post scriptlet
# re-registers a permanently-stale packagecloud.io repo file under
# /etc/yum.repos.d/ on every install, which then breaks every subsequent
# `dnf update`. zypper never reads /etc/yum.repos.d/ at all (it reads
# /etc/zypp/repos.d/) - so even if this same %post scriptlet drops a file
# there on openSUSE, it's an inert orphan file zypper never touches, not a
# live repo breaking `zypper refresh`. Nothing to clean up here.
install_slack() {
    if is_installed slack; then
        SKIPPED_PACKAGES+=("slack"); ((TOTAL_SKIPPED++)); log INFO "Already installed: slack"; return 0
    fi
    safe_install libXss1
    log INFO "Installing Slack (direct rpm from slack.com)..."
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
    local install_err
    if install_err=$(zypper --non-interactive install "$t/slack.rpm" 2>&1); then
        INSTALLED_PACKAGES+=("slack"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: slack"
    else
        FAILED_PACKAGES+=("slack"); ((TOTAL_FAILED++))
        log WARNING "Slack rpm install failed - if it's a missing dependency, check 'rpm -qpR $url' and install the openSUSE-named equivalent manually. zypper said: $(printf '%s' "$install_err" | tail -3 | tr '\n' ' ')"
    fi
    rm -rf "$t"
}

# Remmina - a real run of this script found all three packages missing from
# whatever repos were enabled at the time, contradicting an earlier version
# of this comment's claim that Tumbleweed's own repos are enough on their
# own. Search results on this are genuinely mixed (opensuse.pkgs.org lists
# a build under the default "oss" repo, but the openSUSE Wiki's own Remmina
# page and software.opensuse.org point at the X11:RemoteDesktop OBS project
# instead) - rather than assert one source with more confidence than the
# evidence supports, add X11:RemoteDesktop defensively as an extra source;
# add_obs_repo() is a no-op if it's already reachable some other way.
install_remmina() {
    add_obs_repo "X11:RemoteDesktop" "Remmina"
    batch_install "Remmina" remmina remmina-plugin-rdp remmina-plugin-secret
}

# "Windows App" (mariuszkopowski/windows-app-for-linux) - not on Flathub, so
# it ships as a standalone Flatpak bundle from GitHub releases. Fully
# package-manager-agnostic (plain Flatpak/curl mechanics) - identical to the
# Fedora/Arch scripts, installed into the desktop user's per-user Flatpak scope.
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
    su - "$SUDO_USER" -c "flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo" 2>/dev/null || true
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

# TeamViewer - confirmed via a live check of TeamViewer's own download
# infrastructure during development: unlike Fedora/Ubuntu (a real ongoing
# yum/apt repo), TeamViewer publishes a SPECIFIC, standalone, openSUSE/SUSE-
# targeted generic rpm at a static URL (teamviewer-suse.x86_64.rpm) rather
# than a repo - simpler than the Fedora path, but it means no `dnf/zypper
# upgrade`-driven auto-update; re-run this function to pick up a new build.
install_teamviewer() {
    if command -v teamviewer &>/dev/null || is_installed teamviewer; then
        SKIPPED_PACKAGES+=("teamviewer"); ((TOTAL_SKIPPED++)); log INFO "Already installed: teamviewer"; return 0
    fi
    log INFO "Installing TeamViewer (official openSUSE/SUSE-targeted rpm)..."
    local install_err
    if install_err=$(zypper --non-interactive install https://download.teamviewer.com/download/linux/teamviewer-suse.x86_64.rpm 2>&1) \
        && { command -v teamviewer &>/dev/null || is_installed teamviewer; }; then
        INSTALLED_PACKAGES+=("teamviewer"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: teamviewer"
    else
        FAILED_PACKAGES+=("teamviewer"); ((TOTAL_FAILED++))
        # The download URL itself is confirmed working (a real 302 -> 200,
        # ~115MB rpm) - a failure here is much more likely an unresolved
        # dependency in TeamViewer's own rpm (built against a specific
        # SLES/Leap dependency set, not continuously tracked against
        # Tumbleweed's rolling one) than a broken URL, so show zypper's own
        # reason instead of a bare "failed".
        log WARNING "TeamViewer install failed. zypper said: $(printf '%s' "$install_err" | tail -5 | tr '\n' ' ')"
    fi
}

# 1Password - GENUINE GAP, flagged rather than papered over: a live check of
# 1Password's own support docs and community forum during development found
# that 1Password's rpm repo INTENTIONALLY BLOCKS zypper/openSUSE access
# (their own docs list Fedora/RHEL and Debian/Ubuntu explicitly, and
# recommend the AppImage or Snap Store specifically FOR openSUSE users) -
# this isn't a missing-repo situation this script can add its way around,
# it's a deliberate vendor restriction. Per that same official
# recommendation (and to avoid snap per this script's own preference order),
# the AppImage is downloaded and wrapped with a launcher + .desktop file,
# the same self-contained-binary pattern used for Zed/Gram above.
install_1password() {
    if command -v 1password &>/dev/null || [ -x /opt/1Password/1password ]; then
        SKIPPED_PACKAGES+=("1password"); ((TOTAL_SKIPPED++)); log INFO "Already installed: 1password"; return 0
    fi
    log WARNING "1Password's own rpm repo intentionally blocks zypper/openSUSE access (confirmed via 1Password's own support docs/community forum) - using their own documented AppImage fallback instead."
    log INFO "Installing 1Password (AppImage)..."
    local dest="/opt/1Password"
    mkdir -p "$dest"
    # downloads.1password.com/linux/appimage/1password-latest.AppImage (an
    # earlier version of this script) is a genuine 404 - confirmed directly
    # with curl, not just assumed from the plausible-looking URL shape. The
    # AppImage 1Password's own docs actually point to lives on S3 instead.
    if curl -fL --retry 2 -o "$dest/1password.AppImage" \
        https://onepassword.s3.amazonaws.com/linux/appimage/1password-latest.AppImage 2>/dev/null \
        && [ -s "$dest/1password.AppImage" ]; then
        chmod +x "$dest/1password.AppImage"
        ln -sf "$dest/1password.AppImage" /usr/local/bin/1password
        cat > /usr/share/applications/1password.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=1Password
GenericName=Password Manager
Comment=1Password password manager (AppImage - no zypper repo available, see this script's install_1password comment)
Exec=1password %U
Icon=1password
Terminal=false
Categories=Utility;Security;
EOF
        chmod 644 /usr/share/applications/1password.desktop
        INSTALLED_PACKAGES+=("1password (AppImage)"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: 1Password (AppImage, /opt/1Password) - needs libfuse2 if it won't launch"
    else
        FAILED_PACKAGES+=("1password"); ((TOTAL_FAILED++))
        log WARNING "1Password AppImage download failed - get it manually from https://1password.com/downloads/linux"
    fi
}

# ========== MENU SYSTEM ==========
# Same consolidation note as the Fedora script: no per-domain metapackage
# split exists here either, so Creative Suite stays one category with the
# same Full/Graphics/Video/Audio/Photography/Publishing sub-menu shape.
# "Drivers & Extra Repos" swaps Fedora's Terra repo for openSUSE's own opi
# (OBS Package Installer) bootstrap - see install_opi_helper's comment for
# why that's the better parity match than inventing a fake "Terra of
# openSUSE" repo that doesn't exist.

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
    ui_header "openSUSE TUMBLEWEED  ·  POST-INSTALL" "zypper · OBS · Packman · Snapper (native)"
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
    ui_item 1 "NVIDIA Driver (open kernel modules, G06 series + CUDA)"
    ui_item 2 "opi - OBS Package Installer (openSUSE's own yay/Terra analog)"
    ui_item 3 "DisplayLink Driver (USB/dock display adapters - no clean path, see warning)"
    echo
    ui_item 0 "Back to Main Menu"
    echo
    ui_rule
    printf "  ${MAUVE}${BOLD}❯${NC} ${LAVENDER}Choose ${DIM}[0-3]${NC}${LAVENDER}: ${NC}"
}

show_snapshots_menu() {
    clear
    ui_header "SNAPSHOTS & BACKUP" "Native Btrfs+Snapper - this mostly verifies what Tumbleweed already set up"
    echo
    ui_item 1 "Full Setup (verify/complete Snapper + enable timers)"
    ui_item 2 "Create a snapshot now"
    ui_item 3 "List snapshots"
    ui_item 4 "Open GUI (YaST Snapper / Timeshift)"
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
                    2) reset_tracking; install_opi_helper; display_summary ;;
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
