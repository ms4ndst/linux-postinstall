#!/bin/bash
# OpenMandriva Lx Post-Install Script v1 (dnf5)
# Menu-driven installer with error handling - OpenMandriva port of post-install-fedora.sh
# Run as: chmod +x post-install-openmandriva.sh && sudo ./post-install-openmandriva.sh
#
# PACKAGE NAME CONFIDENCE NOTE: same honesty as the Fedora script - the
# "hard" OpenMandriva-specific parts (repo layout + enable mechanism, NVIDIA
# driver packages, codec sourcing, os-release detection) were verified against
# the OpenMandriva wiki and OpenMandrivaAssociation/OpenMandrivaSoftware
# GitHub sources during development. The bulk of "ordinary" packages (editors,
# languages, system utilities - vim, ripgrep, htop, gcc, golang, ...) were NOT
# individually verified against a live OpenMandriva system (this was written
# without one available) - they rely on the Fedora/Mageia-style naming
# conventions OpenMandriva mostly follows instead. Either way, every install
# goes through package_exists() before safe_install() ever runs, so a wrong
# guess is logged "Not in repos" and skipped rather than failing the whole
# run - exactly the same safety net the Fedora and Ubuntu scripts use.
#
# OPENMANDRIVA ADAPTATIONS vs the Fedora script (what changed and why):
# - No RPM Fusion, no COPR: OpenMandriva ships its own restricted (patent-
#   encumbered codec libs) and non-free (proprietary drivers/apps) repos as
#   pre-written DISABLED stanzas in /etc/yum.repos.d - bootstrap_repos()
#   flips them on using the same <tree>-<arch>[-<subrepo>] repoid scheme
#   OpenMandriva's own `enable-repo` tool uses (see
#   github.com/OpenMandrivaSoftware/om-repo-picker, cli/enable-repo).
# - NVIDIA: kernel modules are PREBUILT per-kernel by OpenMandriva's build
#   farm - the official wiki install command is
#   `dnf install nvidia nvidia-kmod-open-desktop --refresh` from non-free,
#   then a reboot. No akmod compile-and-poll loop like the Fedora path.
# - Dropped entirely (no OpenMandriva equivalent exists): the Terra repo
#   (Fyra Labs builds target Fedora only) and the DisplayLink driver
#   (displaylink-rpm publishes Fedora-kernel-specific prebuilt RPMs).
# - Vendor yum repos kept as-is (VS Code, Sublime, Cursor, Azure CLI,
#   1Password, TeamViewer, Claude Desktop, Charm) use distro-generic
#   baseurls - but their RPMs are BUILT against Fedora, so dependency
#   resolution is not guaranteed here; safe_install's existing failure
#   handling covers the miss. 1Password and TeamViewer fall back to their
#   official rpm installed as a local file (every dependency of both
#   resolves on OpenMandriva - the fragile part is the vendor repo's signed
#   metadata), and 1Password then to Flathub (TeamViewer has no Flathub
#   package).
# - Flathub-first where the vendor RPM can't work here: Brave, Vivaldi,
#   Edge, Chrome, LibreWolf, teams-for-linux (all have official Flathub
#   listings), and Slack (its rpm requires the Fedora package names
#   libXScrnSaver / libappindicator-gtk3, which nothing here provides).
# - Creative Suite has no comps groups to lean on (no Fedora Jam /
#   design-suite equivalents) - explicit package lists instead.
# - OpenMandriva Lx defaults to KDE Plasma: GNOME-only steps (app folders,
#   gsettings keybinds, Shell extensions) degrade gracefully via their
#   existing resolve_desktop_session/package_exists guards rather than being
#   removed.

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

# Fixed-point releases this script is validated against (VERSION_ID from
# /etc/os-release - OpenMandriva reports "5.0", "6.0", ...). The ROME rolling
# edition has no stable VERSION_ID, so check_version() accepts it via the
# repo-tree probe instead (detect_repo_tree below).
declare -a SUPPORTED_VERSIONS=("5.0" "6.0")
OM_VERSION=""
OM_ID=""
OM_ARCH=""
OM_REPO_TREE=""

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

# Probe whether a given repoid (enabled or disabled) is currently flipped
# on. Prefers dnf5's --dump-repo-config (the exact mechanism OpenMandriva's
# own enable-repo/disable-repo tools use); falls back to parsing the shipped
# .repo stanzas directly if this is a dnf4-era system.
om_probe_enabled() {
    local repoid="$1"
    if dnf --dump-repo-config "$repoid" &>/dev/null; then
        dnf --dump-repo-config "$repoid" 2>/dev/null | grep -Eq '^enabled *= *(1|true|on)'
        return
    fi
    local f
    for f in /etc/yum.repos.d/openmandriva-*.repo; do
        [ -f "$f" ] || continue
        if awk -v id="[$repoid]" '
            BEGIN { found = 0; enabled = 0 }
            /^\[/ { inrepo = ($0 == id); if (inrepo) found = 1; next }
            inrepo && /^enabled[[:space:]]*=/ {
                sub(/^[^=]*=[[:space:]]*/, "")
                enabled = ($0 ~ /^(1|true|on)$/) ? 1 : 0
                exit
            }
            END { exit (found && enabled) ? 0 : 1 }
        ' "$f"; then
            return 0
        fi
    done
    return 1
}

# Detect which OpenMandriva repo tree is active: fixed-point releases use
# their VERSION_ID as the tree name, rolling (ROME) uses "rolling", rock
# uses "rock", cooker "cooker". Same walk order as OpenMandriva's own
# enable-repo tool (cooker rolling rock release $RELEASEVER) - see
# github.com/OpenMandrivaSoftware/om-repo-picker/blob/master/cli/enable-repo.
detect_repo_tree() {
    OM_REPO_TREE=""
    local tree
    for tree in cooker rolling rock release "${OM_VERSION:-}"; do
        [ -n "$tree" ] || continue
        if om_probe_enabled "${tree}-${OM_ARCH}"; then
            OM_REPO_TREE="$tree"; return 0
        fi
    done
    return 1
}

# Detect the running release once, into globals the rest of the script reads.
# Reads /etc/os-release directly (every OpenMandriva install has one) rather
# than leaning on lsb_release, which isn't installed by default here.
detect_version() {
    OM_VERSION=$(grep -oP '(?<=^VERSION_ID=)\S+' /etc/os-release 2>/dev/null | tr -d '"')
    OM_ID=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"')
    # Same arch probe OpenMandriva's enable-repo uses (basesystem-minimal is
    # an every-install package); rpm -q prints its "not installed" error to
    # STDOUT, so validate the result instead of trusting exit codes alone.
    local a
    a=$(rpm -q --qf '%{ARCH}' basesystem-minimal 2>/dev/null || true)
    case "$a" in
        x86_64|aarch64|armv7hnl|i686|riscv64) OM_ARCH="$a" ;;
        *) OM_ARCH=$(uname -m) ;;
    esac
    detect_repo_tree
}

check_version() {
    detect_version
    local supported=false v
    if [ "${OM_ID:-}" = "openmandriva" ]; then
        for v in "${SUPPORTED_VERSIONS[@]}"; do
            [[ "$OM_VERSION" == "$v" ]] && { supported=true; break; }
        done
        # ROME rolling: no stable VERSION_ID, but its repo tree is detectable.
        [ "${OM_REPO_TREE:-}" = "rolling" ] && supported=true
    fi
    if $supported; then
        log INFO "Detected supported OpenMandriva ${OM_VERSION:-ROME rolling} (repo tree: ${OM_REPO_TREE:-unknown})"
    else
        local joined; joined=$(IFS=/; echo "${SUPPORTED_VERSIONS[*]}")
        log WARNING "Designed for OpenMandriva Lx ${joined} or ROME (id=openmandriva), detected: ${OM_ID:-unknown} ${OM_VERSION:-unknown}"
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
# `dnf info` only matches real package NAMES - a Fedora-style name that an
# OpenMandriva package merely Provides (e.g. vim-enhanced, provided by
# OpenMandriva's plain `vim`) would be rejected as "Not in repos" even
# though `dnf install` itself resolves it fine. Accept provided names too.
package_exists() {
    dnf info -q "$1" &>/dev/null \
        || [ -n "$(dnf repoquery -q --whatprovides "$1" 2>/dev/null)" ]
}

pm_update() {
    dnf makecache
}
pm_install() { dnf install -y "$@" 2>/dev/null; }

# ── OpenMandriva repo helpers ────────────────────────────────────────────────
# There is no COPR equivalent on OpenMandriva - Fedora COPR builds target
# Fedora releases/kernels and would be wrong here even if the plugin worked.
# Instead, the openmandriva-repos package ships every tree/subrepo as a
# pre-written disabled stanza, and enabling one is a config-manager setopt
# on the <tree>-<arch>[-<subrepo>] repoid - exactly what OpenMandriva's own
# `enable-repo` CLI tool does under its pkexec wrapper.

# Is a subrepo (extra | restricted | non-free) enabled? (OpenMandriva has no
# "unsupported" repo in its configuration - "extra" is the community one.)
om_repo_enabled() {
    local sub="$1"
    [ -z "${OM_REPO_TREE:-}" ] && detect_version
    if [ -z "${OM_REPO_TREE:-}" ] || [ -z "${OM_ARCH:-}" ]; then return 1; fi
    om_probe_enabled "${OM_REPO_TREE}-${OM_ARCH}-${sub}"
}

# Enable a subrepo (idempotent; returns non-zero + logs if it can't).
enable_om_repo() {
    local sub="$1"
    if [ -z "${OM_REPO_TREE:-}" ] || [ -z "${OM_ARCH:-}" ]; then
        log WARNING "Could not detect the active OpenMandriva repo tree - enable '$sub' manually in /etc/yum.repos.d/"
        return 1
    fi
    local repoid="${OM_REPO_TREE}-${OM_ARCH}-${sub}"
    om_probe_enabled "$repoid" && return 0
    if dnf config-manager setopt "$repoid.enabled=1" &>/dev/null; then
        return 0
    fi
    # dnf4 fallback: flip the stanza in the shipped .repo file directly.
    local f
    for f in /etc/yum.repos.d/openmandriva-*.repo; do
        [ -f "$f" ] || continue
        if grep -q "^\[$repoid\]" "$f" 2>/dev/null; then
            if awk -v id="[$repoid]" '
                /^\[/ { inrepo = ($0 == id); print; next }
                inrepo && /^enabled[[:space:]]*=/ { print "enabled=1"; next }
                { print }
            ' "$f" > "$f.omnew" && mv "$f.omnew" "$f"; then
                return 0
            fi
            rm -f "$f.omnew"
        fi
    done
    log WARNING "Could not enable '$repoid' - check /etc/yum.repos.d/openmandriva-*.repo"
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

# OpenMandriva's rpm is built with its OpenSSL backend, i.e. rpm's own
# legacy OpenPGP parser rather than Sequoia (Fedora's), and that parser can't
# read the signing keys of these four vendors (TeamViewer, Cursor, Claude
# Desktop, 1Password) - dnf fails with "parsing armored OpenPGP packet(s)
# failed". With gpgcheck/repo_gpgcheck on, such a repo can't be read at all,
# and dnf5 doesn't skip unreadable repos by default, so one of these files
# would fail every later dnf command (including the metadata refresh below,
# which exits the script). So their repos are kept - `dnf upgrade` still
# updates them, over HTTPS from the vendor - but without signature checking,
# and marked skip_if_unavailable. Applied to the vendors' own repo files too:
# the TeamViewer rpm ships teamviewer.repo, and the Cursor and 1Password
# rpms write theirs on install, all with signature checking on.
# Charm (glow) too, but only on Rolling: Rock's rpm 4.20 reads Charm's key,
# Rolling's rpm 6.1 doesn't (verified in both).
OM_UNVERIFIABLE_REPOS=(teamviewer cursor claude-desktop-unofficial 1password charm)
om_relax_vendor_repos() {
    local name f
    for name in "${OM_UNVERIFIABLE_REPOS[@]}"; do
        f="/etc/yum.repos.d/$name.repo"
        [ -f "$f" ] || continue
        awk '
            /^[[:space:]]*(gpgcheck|repo_gpgcheck|skip_if_unavailable)[[:space:]]*=/ { next }
            { print }
            /^[[:space:]]*\[.*\][[:space:]]*$/ { print "gpgcheck=0"; print "repo_gpgcheck=0"; print "skip_if_unavailable=1" }
        ' "$f" > "$f.tmp" && cat "$f.tmp" > "$f" && rm -f "$f.tmp"
    done
}

update_packages() {
    om_relax_vendor_repos
    log INFO "Refreshing package metadata..."
    if ! pm_update; then
        log ERROR "Failed to refresh metadata. Check internet."
        read -p "Retry? [y/N] " -n 1 -r; echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then update_packages; else log ERROR "Cannot proceed."; exit 1; fi
    fi
    log SUCCESS "Metadata refreshed."
}

# The OpenMandriva equivalent of RPM Fusion bootstrapping: flip the
# restricted (patent-encumbered codec libs) and non-free (proprietary
# drivers/apps) subrepos on. This is load-bearing exactly like RPM Fusion is
# in the Fedora script - the codec and NVIDIA categories below assume both.
# 'extra' (community-maintained) is deliberately left OFF: OpenMandriva's own
# wiki warns much of it won't install or work properly.
bootstrap_repos() {
    # dnf5's config-manager subcommand ships as a plugin - make sure it
    # exists before relying on it (no-op if the command already works, which
    # it does on stock OpenMandriva Lx 5.0/6.0).
    if ! dnf config-manager --help &>/dev/null; then
        safe_install dnf5-plugins
        dnf config-manager --help &>/dev/null \
            || log WARNING "dnf config-manager unavailable - repo enabling falls back to editing .repo files directly"
    fi

    log INFO "Enabling OpenMandriva extra + restricted + non-free repos..."
    local ok=true
    # extra: community packages several categories below need (fish, ncdu,
    # iotop, iftop, nload, sysstat, zathura, ...)
    om_repo_enabled extra || { enable_om_repo extra || ok=false; }
    om_repo_enabled restricted || { enable_om_repo restricted || ok=false; }
    om_repo_enabled non-free  || { enable_om_repo non-free  || ok=false; }
    if $ok; then
        log SUCCESS "OpenMandriva extra (community) + restricted (codecs) + non-free (proprietary) repos enabled"
    else
        log WARNING "Repo enabling failed - codec/driver categories below will mostly fail too"
    fi
}

install_base() {
    log INFO "Installing base utilities..."
    batch_install "base" curl wget git gnupg2 dconf dbus-x11 xdg-user-dirs
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
    local f="/var/log/openmandriva_post_install_$(date +%Y%m%d_%H%M%S).log"
    {
        echo "=== Log: $(date) ==="; echo "User: $(whoami)"; echo "OpenMandriva: ${OM_VERSION:-ROME rolling} (repo tree: ${OM_REPO_TREE:-unknown})"
        echo "Installed: ${TOTAL_INSTALLED}"; echo "Skipped: ${TOTAL_SKIPPED}"; echo "Failed: ${TOTAL_FAILED}"
        echo; echo "Installed packages:"; printf "  %s\n" "${INSTALLED_PACKAGES[@]}"
        echo; echo "Failed packages:"; printf "  %s\n" "${FAILED_PACKAGES[@]}"
    } > "$f"
    log INFO "Log saved to: $f"
}

# ========== CREATIVE SUITE (Ubuntu Studio replacement) ==========
# OpenMandriva has no per-domain metapackages like ubuntustudio-* and no
# comps groups matching Fedora Jam's "audio" / "design-suite" either - every
# category below is an explicit package list mirroring those groups'
# contents instead. package_exists() skips whatever OpenMandriva's repos
# don't carry, so the lists can afford to be generous. Photography/
# Publishing stay as their own smaller picks so the sub-menu keeps the same
# 6-choice shape as the Fedora and Ubuntu scripts.
install_creative_audio() {
    log INFO "Installing Audio Production..."
    batch_install "Audio Production" \
        ardour audacity lmms hydrogen yoshimi musescore \
        carla guitarix qtractor \
        qjackctl pulseaudio-utils pavucontrol soundconverter easytag
    install_cliamp
}

# cliamp (https://www.cliamp.stream/) - terminal Winamp-style music player/
# streamer (Spotify/Qobuz/YouTube Music/Plex/Jellyfin/30,000+ radio stations).
# Not packaged for OpenMandriva - vendor curl|sh installer fetches a prebuilt
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
    log INFO "Installing Graphics & Design... (large transaction - this can take a while)"
    batch_install "Graphics & Design" \
        gimp inkscape krita blender darktable digikam pitivi scribus
    # Synfig isn't packaged for OpenMandriva at all (no synfig* package in
    # main/extra/non-free/restricted, Rock or Rolling) - an unknown
    # name in the batch above failed the whole dnf transaction. Flathub has
    # the official build.
    flatpak_install_flathub org.synfig.SynfigStudio "Synfig Studio"
    batch_install "Graphics (extra)" nomacs flameshot imagemagick graphicsmagick optipng jpegoptim pngquant libwebp-tools
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
# OpenMandriva ships full-codec ffmpeg in its own main repo and the patent-
# embargered extras in restricted - there is no Fedora-style ffmpeg-free
# swap, no Cisco OpenH264 special repo, and nothing like RPM Fusion needed.
# This just makes sure the complete stack is present once bootstrap_repos()
# has enabled restricted. GStreamer plugin names follow the
# Mageia/Mandriva-style gstreamer1.0-* convention; package_exists() skips
# any that OpenMandriva doesn't carry under this exact name.
install_multimedia_codecs() {
    log INFO "Installing multimedia codecs (OpenMandriva main + restricted)..."
    batch_install "Multimedia codecs" \
        ffmpeg gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
        gstreamer1.0-plugins-ugly gstreamer1.0-libav libdvdcss
}

# ========== NVIDIA DRIVER (OpenMandriva non-free repo) ==========
# OpenMandriva pre-builds the NVIDIA kernel modules in its own ABF build farm
# per kernel release - `dnf install nvidia nvidia-kmod-open-desktop --refresh`
# from the non-free repo is the official wiki install command (the -open
# variant matches the Fedora script's open-kernel-module choice; prebuilt
# means NO akmod compile loop to poll, unlike the Fedora RPM Fusion path).
# The kmod package matches the default kernel-desktop flavor; a non-default
# kernel flavor needs the matching nvidia-kmod-open-<flavor> package instead.
# Opt-in only, same reasoning as the Fedora script: real hardware-specific
# state, not a package to fire blindly.
install_nvidia_driver() {
    if ! om_repo_enabled non-free; then
        log WARNING "OpenMandriva non-free repo isn't enabled - run bootstrap first"; return 1
    fi
    local msg="Install the NVIDIA driver (nvidia + nvidia-kmod-open-desktop)?\n\nOpen kernel modules, prebuilt by OpenMandriva for the default kernel-desktop flavor - no local compile step. Only do this on a machine with an NVIDIA GPU. A reboot is needed after install to load the module."
    local do_it=false
    if command -v whiptail &>/dev/null; then
        whiptail --yesno "$msg" --yes-button "Install" --no-button "Skip" 14 76 && do_it=true
    else
        echo -e "$msg [y/N]:"
        read -r REPLY
        { [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; } && do_it=true
    fi
    if ! $do_it; then
        SKIPPED_PACKAGES+=("nvidia"); ((TOTAL_SKIPPED++)); log INFO "Skipped NVIDIA driver"; return 0
    fi

    log INFO "Installing NVIDIA driver (prebuilt kmods from non-free)..."
    dnf install -y --refresh nvidia nvidia-kmod-open-desktop 2>/dev/null
    if is_installed nvidia-kmod-open-desktop || is_installed nvidia; then
        INSTALLED_PACKAGES+=("nvidia + nvidia-kmod-open-desktop"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: NVIDIA driver (nvidia + nvidia-kmod-open-desktop)"
        if mokutil --sb-state 2>/dev/null | grep -qi "enabled"; then
            log WARNING "Secure Boot is ON - if the module is refused at load time, disable Secure Boot in firmware setup or enroll a MOK per OpenMandriva's wiki"
        else
            log INFO "Reboot when convenient to load the new kernel module: sudo reboot"
        fi
        log INFO "A non-default kernel flavor needs the matching nvidia-kmod-open-<flavor> package"
        log INFO "Verify after reboot with: nvidia-smi"
    else
        FAILED_PACKAGES+=("nvidia + nvidia-kmod-open-desktop"); ((TOTAL_FAILED++))
        log WARNING "NVIDIA driver install failed - try: sudo dnf install nvidia nvidia-kmod-open-desktop"
    fi
}

# ========== DRIVERS ==========
install_drivers_and_repos() {
    install_nvidia_driver
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
# Opt-in and interactive, same shape as install_nvidia_driver:
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

# Elgato Wave:3 USB mic - pins the card to WirePlumber's "pro-audio" profile.
#
# ROOT CAUSE NOTE (corrected 2026-09-25): this is NOT the fix for "OBS records
# silence from the Wave:3". That was diagnosed on Fedora 44 (PipeWire 1.6.9,
# WirePlumber 0.5.17) as a stale OBS audio source: in the broken state
# pw-record from the default source peaked normally and pw-link showed the
# mic linked into OBS, yet OBS's meter stayed flat. Deleting and re-adding
# the OBS "Audio Input Capture" source (or re-selecting its Device) fixed it;
# reboots, PipeWire/WirePlumber restarts and the profile switch did not.
# If it recurs: re-create/re-select the source in OBS first.
#
# What this function still does: pin pro-audio so the mic always shows up as
# the stable "Elgato Wave 3 Pro" source instead of the auto-picked
# "analog-stereo + mono-fallback" profile. Kept because it works and is
# harmless - not because it is proven necessary.
#
# Needs WirePlumber >= 0.5 (SPA-JSON .conf drop-ins); 0.4 used Lua config
# and is refused loudly rather than half-configured.
#
# Written system-wide (/etc/wireplumber/wireplumber.conf.d/) so it needs no
# $SUDO_USER home handling, and matched on USB vendor/product ID (0fd9:0070,
# as reported by `pactl list cards`) instead of device.name, which embeds the
# unit's serial number and would silently stop matching a replacement mic.
# Harmless when the mic isn't plugged in - the rule just never matches.
#
# After this, OBS must use the source named "Elgato Wave 3 Pro" (the source
# name changes with the profile) - re-select it in the source's properties.
fix_elgato_wave3_profile() {
    local conf_dir="/etc/wireplumber/wireplumber.conf.d"
    local conf="$conf_dir/51-elgato-wave3-pro-audio.conf"

    if ! command -v wireplumber &>/dev/null; then
        log WARNING "WirePlumber not installed - skipping Elgato Wave:3 profile fix"
        return 1
    fi

    local wp_ver; wp_ver=$(wireplumber --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | tail -1)
    if [ -n "$wp_ver" ] && [ "$(printf '%s\n' 0.5.0 "$wp_ver" | sort -V | head -1)" != "0.5.0" ]; then
        log WARNING "WirePlumber $wp_ver is older than 0.5 - this fix uses 0.5-style config, skipping"
        return 1
    fi

    mkdir -p "$conf_dir"
    if cat > "$conf" <<'WPEOF'
# Managed by post-install-fedora.sh (fix_elgato_wave3_profile)
# Elgato Wave:3: pin the pro-audio profile (stable source name).
# Silence in OBS was a stale OBS source, not this - re-create it in OBS.
monitor.alsa.rules = [
  {
    matches = [
      { device.vendor.id = "0x0fd9", device.product.id = "0x0070" }
    ]
    actions = {
      update-props = {
        device.profile = "pro-audio"
      }
    }
  }
]
WPEOF
    then
        log SUCCESS "Wrote $conf"
    else
        log ERROR "Could not write $conf"
        return 1
    fi

    # Apply now for the invoking user's session, if there is one.
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        local uid; uid=$(id -u "$SUDO_USER")
        if [ -S "/run/user/$uid/bus" ] && \
           sudo -u "$SUDO_USER" XDG_RUNTIME_DIR="/run/user/$uid" \
               DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
               systemctl --user restart wireplumber 2>/dev/null; then
            log SUCCESS "Restarted WirePlumber for $SUDO_USER - Wave:3 should now show as 'Elgato Wave 3 Pro'"
        else
            log INFO "Could not restart WirePlumber for $SUDO_USER - log out/in or reboot to apply"
        fi
    fi
    log INFO "Verify: pactl list cards | grep -A60 Elgato | grep 'Active Profile'  (expect: pro-audio)"
    log INFO "In OBS: set the mic source's Device to 'Elgato Wave 3 Pro'"
    log INFO "If OBS ever records silence from the mic: delete + re-add the OBS audio source (reboots don't fix it)"
    [ -t 0 ] && read -p "$(printf "${DIM}${SUBTEXT}  Press [Enter] to continue…${NC}")" _
    return 0
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
# OpenMandriva Lx defaults to an ext4 root (unlike Fedora Workstation's
# Btrfs default since F33+), so a stock install takes the Timeshift path
# here; the Btrfs/Snapper path is kept for custom-partitioned systems.
# There's no third-party layer for grub-btrfs on OpenMandriva (Fedora COPR
# builds target Fedora kernels), and no dnf5 snapper hook - so on Btrfs the
# reliable layer is Snapper's own timeline/cleanup timers, which are
# independent of dnf entirely. On non-Btrfs roots (ext4/xfs) Snapper
# doesn't apply at all, so Timeshift is used instead (rsync-mode GUI+CLI
# backup, no filesystem-specific requirement).

detect_root_fstype() {
    findmnt -no FSTYPE / 2>/dev/null
}

install_snapshots_full() {
    local fstype; fstype=$(detect_root_fstype)
    log INFO "Detected root filesystem: ${fstype:-unknown}"
    if [ "$fstype" = "btrfs" ]; then
        # Snapper/Btrfs Assistant presence in OpenMandriva's repos is NOT
        # confirmed (unlike Timeshift, which is confirmed in-repo by OM's
        # own forum), so fall back to Timeshift - it supports btrfs
        # snapshots natively, not just rsync mode.
        if package_exists snapper || package_exists btrfs-assistant; then
            install_snapshots_btrfs
        else
            log WARNING "Snapper/Btrfs Assistant not in repos - falling back to Timeshift (native btrfs snapshot support)"
            install_snapshots_timeshift
        fi
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
    batch_install "Snapshots (Timeshift)" timeshift cronie
    if is_installed timeshift; then
        # OM-specific: Timeshift's scheduled snapshots run via cron, and the
        # cron daemon is not enabled by default on OpenMandriva (per OM forum
        # guidance) - without this, schedules silently never fire.
        if systemctl enable --now crond &>/dev/null || systemctl enable --now cronie &>/dev/null; then
            log SUCCESS "Enabled the cron daemon (Timeshift's scheduled snapshots need it)"
        else
            log WARNING "Could not enable the cron daemon - Timeshift schedules won't fire until you do: sudo systemctl enable --now crond"
        fi
        log INFO "Timeshift installed - first run needs interactive setup (pick rsync or btrfs mode + snapshot destination), this script won't guess your disk layout for you"
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
    # Written directly rather than via `dnf config-manager addrepo`: on
    # dnf5-based OpenMandriva, config-manager is a plugin that isn't packaged
    # here (no dnf5-plugins), so that call silently added nothing. Every
    # dependency of the code rpm itself resolves on OpenMandriva.
    cat > /etc/yum.repos.d/vscode.repo <<'EOF'
[vscode]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
    pm_update
    safe_install code
}

# Sublime Text from Sublime HQ's official tarball build (installed to
# /opt/sublime_text, the path its own bundled .desktop file expects).
# Its rpm can't install on OpenMandriva - it requires the Fedora package
# NAME gtk3, which nothing here provides (OpenMandriva ships the GTK 3
# libraries under its own lib64gtk* names) - and dnf5's config-manager,
# which the rpm-repo route used to add the repo, isn't packaged here
# either (no dnf5-plugins). The tarball bundles its own Python/OpenSSL and
# only needs the system GTK 3 libraries. No auto-update: re-run this to
# move to a newer build (it always fetches the current stable one).
install_sublime_text() {
    if command -v subl &>/dev/null || [ -x /opt/sublime_text/sublime_text ]; then
        SKIPPED_PACKAGES+=("sublime-text"); ((TOTAL_SKIPPED++)); log INFO "Sublime Text already installed"; return 0
    fi
    log INFO "Installing Sublime Text (official tarball build)..."
    local build t
    build=$(curl -fsSL https://www.sublimetext.com/updates/4/stable_update_check 2>/dev/null \
        | grep -oE '"latest_version":[[:space:]]*[0-9]+' | grep -oE '[0-9]+$')
    if [ -z "$build" ]; then
        log WARNING "Couldn't read the current Sublime Text build number - trying Flathub instead"
        flatpak_install_flathub com.sublimetext.three "Sublime Text"; return 0
    fi
    t=$(mktemp -d)
    if curl -fsSL --retry 3 -o "$t/sublime.tar.xz" \
            "https://download.sublimetext.com/sublime_text_build_${build}_x64.tar.xz" 2>/dev/null \
        && tar -xJf "$t/sublime.tar.xz" -C "$t" \
        && [ -x "$t/sublime_text/sublime_text" ]; then
        rm -rf /opt/sublime_text
        mv "$t/sublime_text" /opt/sublime_text
        ln -sf /opt/sublime_text/sublime_text /usr/local/bin/subl
        install -Dm644 /opt/sublime_text/sublime_text.desktop /usr/share/applications/sublime_text.desktop
        local size
        for size in 16x16 32x32 48x48 128x128 256x256; do
            [ -f "/opt/sublime_text/Icon/$size/sublime-text.png" ] && install -Dm644 \
                "/opt/sublime_text/Icon/$size/sublime-text.png" "/usr/share/icons/hicolor/$size/apps/sublime-text.png"
        done
        gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
        update-desktop-database -q /usr/share/applications 2>/dev/null || true
        rm -rf "$t"
        INSTALLED_PACKAGES+=("sublime-text"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: Sublime Text build $build (/opt/sublime_text, 'subl' on PATH)"; return 0
    fi
    rm -rf "$t"
    log WARNING "Sublime Text tarball install failed - trying Flathub instead"
    flatpak_install_flathub com.sublimetext.three "Sublime Text"
}

# Bruno API client - no rpm/COPR from usebruno.com, only Flatpak/AppImage/Snap
# officially, so Flathub is the correct (not a compromise) choice here.
install_bruno() { flatpak_install_flathub com.usebruno.Bruno "Bruno"; }

# ========== PYTHON ==========
# pipx isn't packaged for OpenMandriva (no package, nothing provides the
# name). Install pipx's own official standalone zipapp (pipx.pyz, published
# with every pipx release) as /usr/local/bin/pipx: a single file that only
# needs python3 - no pip, no --user install, no PEP 668 workaround, and no
# dependency on knowing the desktop user. Each user's pipx-installed apps
# still land in their own ~/.local as usual.
ensure_pipx() {
    # pipx builds every app's virtualenv with `python -m venv`, which needs
    # ensurepip - split into its own package on OpenMandriva (without it:
    # "No module named ensurepip", and every pipx install fails).
    is_installed python-ensurepip || pm_install python-ensurepip &>/dev/null
    if command -v pipx &>/dev/null || [ -x /usr/local/bin/pipx ]; then return 0; fi
    log INFO "Installing pipx (official standalone pipx.pyz - not packaged for OpenMandriva)..."
    curl -fsSL --retry 3 -o /usr/local/bin/pipx \
            https://github.com/pypa/pipx/releases/latest/download/pipx.pyz 2>/dev/null \
        && chmod 755 /usr/local/bin/pipx \
        && /usr/local/bin/pipx --version &>/dev/null && return 0
    rm -f /usr/local/bin/pipx
    return 1
}

install_python() {
    # OpenMandriva's Python 3 packages are unversioned: `python` IS Python 3
    # (Python 2 is the separate `python2`), and the Fedora-style python3-*
    # names are at most Provides of these - python3-virtualenv not even that.
    # lib64python-devel, not the python-devel Provide, which lib64python2-devel
    # also carries.
    batch_install "Python" python lib64python-devel python-pip python-virtualenv python-ensurepip ipython
    if ensure_pipx; then
        INSTALLED_PACKAGES+=("pipx"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: pipx (/usr/local/bin/pipx)"
    else
        FAILED_PACKAGES+=("pipx"); ((TOTAL_FAILED++)); log WARNING "pipx install failed"
    fi
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
    # OpenMandriva's own repo-preferences package points Java installs at
    # the "jdk-current" meta (see openmandriva-repos' pkgprefs), which is
    # always the newest JDK (21 on Rock, 25 on Rolling) - the role Fedora's
    # java-latest-openjdk plays, which OpenMandriva has no package for.
    # junit is only packaged on Rolling.
    batch_install "Java" jdk-current java-21-openjdk gradle ant junit
    install_maven
    # IntelliJ IDEA Community - not carried by OpenMandriva's repos;
    # Flathub's official listing is the real equivalent.
    flatpak_install_flathub com.jetbrains.IntelliJ-IDEA-Community "IntelliJ IDEA Community"
}

# Maven - packaged on both releases, but on Rolling the package can't be
# installed (its maven-lib needs org.eclipse.sisu jars Rolling doesn't ship).
# Fall back to Apache's official binary release there: newest 3.x from
# Apache's download CDN, checked against its published SHA-512, unpacked to
# /opt/apache-maven with mvn linked into /usr/local/bin.
install_maven() {
    if command -v mvn &>/dev/null; then
        SKIPPED_PACKAGES+=("maven"); ((TOTAL_SKIPPED++)); log INFO "Already installed: maven"; return 0
    fi
    if package_exists maven && pm_install maven && command -v mvn &>/dev/null; then
        INSTALLED_PACKAGES+=("maven"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: maven"; return 0
    fi
    local ver t f
    ver=$(curl -fsSL https://dlcdn.apache.org/maven/maven-3/ 2>/dev/null \
        | grep -oE 'href="3\.[0-9]+\.[0-9]+/"' | grep -oE '3\.[0-9]+\.[0-9]+' | sort -V | tail -1)
    log INFO "maven package not installable here - using Apache's official release ${ver:-?}..."
    f="apache-maven-${ver}-bin.tar.gz"
    t=$(mktemp -d)
    if [ -n "$ver" ] \
        && curl -fsSL --retry 3 -o "$t/$f" "https://dlcdn.apache.org/maven/maven-3/$ver/binaries/$f" 2>/dev/null \
        && curl -fsSL --retry 3 -o "$t/$f.sha512" "https://downloads.apache.org/maven/maven-3/$ver/binaries/$f.sha512" 2>/dev/null \
        && [ "$(sha512sum "$t/$f" | cut -d' ' -f1)" = "$(grep -oE '^[0-9a-f]{128}' "$t/$f.sha512")" ] \
        && tar -xzf "$t/$f" -C "$t" \
        && rm -rf /opt/apache-maven && mv "$t/apache-maven-$ver" /opt/apache-maven \
        && ln -sf /opt/apache-maven/bin/mvn /usr/local/bin/mvn; then
        INSTALLED_PACKAGES+=("maven $ver"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: maven $ver (/opt/apache-maven, mvn in /usr/local/bin)"
    else
        FAILED_PACKAGES+=("maven"); ((TOTAL_FAILED++)); log WARNING "maven install failed"
    fi
    rm -rf "$t"
}

# ========== C/C++ ==========
install_c_cpp() {
    batch_install "C/C++" \
        gcc gcc-c++ gcc-gfortran clang cmake make ninja ccache \
        autoconf automake libtool m4 bison flex gettext pkgconf \
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
    # No rubygem-bundler package: OpenMandriva's ruby ships Bundler itself
    # (bundle/bundler in /usr/bin), as upstream Ruby has since 2.6.
    batch_install "Ruby" ruby ruby-devel
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
    # pkgconf (not Fedora's pkgconf-pkg-config split) is OpenMandriva's
    # package, and it provides /usr/bin/pkg-config itself. tig isn't packaged
    # for OpenMandriva at all - built from source below instead.
    batch_install "Dev Tools" \
        jq subversion make cmake \
        autoconf automake bison flex gettext pkgconf man-db man-pages less
    install_tig_source
    install_bruno
}

# tig - not packaged for OpenMandriva (no package, nothing provides it), so
# build the official release tarball (github.com/jonas/tig) into /usr/local,
# checksum-verified against the .sha256 file published with each release.
# Only needs a C compiler (+ glibc-devel), make, and ncursesw (lib64ncurses-devel).
# Built as -std=gnu17: tig 2.6.1 has `return false;` in a pointer-returning
# function (src/stage.c:350), which Rock's GCC 14 rejects as a hard error
# ("incompatible types when returning type '_Bool'") - valid in C17, where
# false is just 0. Verified building on both Rock and Rolling containers.
install_tig_source() {
    if command -v tig &>/dev/null || [ -x /usr/local/bin/tig ]; then
        SKIPPED_PACKAGES+=("tig"); ((TOTAL_SKIPPED++)); log INFO "Already installed: tig"; return 0
    fi
    # glibc-devel too: OpenMandriva's gcc doesn't pull in the C library's
    # crt1.o/crti.o and headers, so without it gcc can't link anything
    # ("C compiler cannot create executables" from configure).
    batch_install "tig build deps" gcc glibc-devel make lib64ncurses-devel pkgconf
    local tag t
    tag=$(curl -fsSL https://api.github.com/repos/jonas/tig/releases/latest 2>/dev/null \
        | grep -oE '"tag_name":[[:space:]]*"tig-[0-9.]+"' | grep -oE 'tig-[0-9.]+')
    [ -z "$tag" ] && tag="tig-2.6.1"
    log INFO "Building $tag from source..."
    t=$(mktemp -d)
    if curl -fsSL --retry 3 -o "$t/$tag.tar.gz" "https://github.com/jonas/tig/releases/download/$tag/$tag.tar.gz" 2>/dev/null \
        && curl -fsSL --retry 3 -o "$t/$tag.tar.gz.sha256" "https://github.com/jonas/tig/releases/download/$tag/$tag.tar.gz.sha256" 2>/dev/null \
        && (cd "$t" && sha256sum -c "$tag.tar.gz.sha256" &>/dev/null) \
        && tar -xzf "$t/$tag.tar.gz" -C "$t" \
        && (cd "$t/$tag" && ./configure --prefix=/usr/local CFLAGS="-O2 -std=gnu17" &>/dev/null \
            && make -j"$(nproc)" &>/dev/null && make install &>/dev/null) \
        && [ -x /usr/local/bin/tig ]; then
        rm -rf "$t"
        INSTALLED_PACKAGES+=("tig"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: $tag (built from source, /usr/local/bin/tig)"; return 0
    fi
    rm -rf "$t"
    FAILED_PACKAGES+=("tig"); ((TOTAL_FAILED++)); log WARNING "tig source build failed"; return 0
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
    # No COPR-equivalent third-party layer on OpenMandriva to carry dbeaver-ce
    # - Flathub's community package is the reliable path, the same conclusion
    # the Ubuntu script reaches.
    flatpak_install_flathub io.dbeaver.DBeaverCommunity "DBeaver CE"
}

# ========== CONTAINERS & VMS ==========
# Docker Desktop: Docker Inc publishes no package for OpenMandriva (its only
# SUSE builds are SLES/s390x; Linux desktop packages exist for Ubuntu/Debian,
# Fedora/RHEL and Arch only), so there's nothing safe to install here - the
# Docker Engine + CLI + compose installed above are the supported route.
configure_docker_desktop() {
    log INFO "Docker Desktop: not available for OpenMandriva (Docker Inc only packages it for Ubuntu/Debian, Fedora/RHEL and Arch) - Docker Engine + CLI + compose are installed instead"
}

install_containers() {
    # Docker: no Fedora-style "moby-engine" package name here, and Docker
    # Inc's official yum repo only builds Fedora/openSUSE/CentOS RPMs - plain
    # `docker` from OpenMandriva's own repos, mirroring the sibling scripts'
    # distro-package-over-vendor-repo precedent. (package_exists() skips it
    # cleanly if OpenMandriva doesn't carry it.)
    batch_install "Containers" docker docker-compose podman
    if is_installed docker; then
        systemctl enable --now docker 2>/dev/null
        [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ] && usermod -aG docker "$SUDO_USER" 2>/dev/null \
            && log INFO "Added $SUDO_USER to the docker group (log out/in to take effect)"
    fi
    # Not packaged for OpenMandriva (Rock or Rolling - no package, nothing
    # provides the names), and neither has a Flatpak: Incus (the LXD fork)
    # and Cockpit with its machines/podman plugins. Skipped rather than
    # listed, so they don't show up as failures on every run.
    log INFO "Skipping Incus and Cockpit - not packaged for OpenMandriva"
    SKIPPED_PACKAGES+=("incus (not packaged for OpenMandriva)" "cockpit (not packaged for OpenMandriva)")
    ((TOTAL_SKIPPED += 2))
    # OpenMandriva's libvirt is libvirt-utils: the whole thing - libvirtd /
    # virtqemud & co., their systemd units, virsh, and the libvirt group.
    # There is no package named "libvirt" here.
    batch_install "Virtualization" \
        qemu qemu-kvm libvirt-utils virt-install virt-manager virt-viewer \
        gnome-boxes
    if is_installed libvirt-utils; then
        systemctl enable --now libvirtd 2>/dev/null
        [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ] && usermod -aG libvirt "$SUDO_USER" 2>/dev/null \
            && log INFO "Added $SUDO_USER to the libvirt group (log out/in to take effect)"
        install_virtio_win
    fi
    install_docker_libvirt_forward_fix
    configure_docker_desktop
}

# Virtio-Win: the Windows guest drivers (network, disk, balloon, etc) needed
# for a Windows VM under KVM/QEMU to get more than a crawling emulated IDE
# disk and no network. Fedora's fedorapeople virtio-win repo builds against
# Fedora releases only - on OpenMandriva the direct stable-channel ISO
# download is the reliable path (the same file the repo RPM ships, from the
# upstream project's own maintained static URL), landing at the standard
# /var/lib/libvirt/images/virtio-win.iso location virt-manager expects.
install_virtio_win() {
    if [ -e /var/lib/libvirt/images/virtio-win.iso ]; then
        SKIPPED_PACKAGES+=("Virtio-Win drivers"); ((TOTAL_SKIPPED++)); log INFO "Already installed: Virtio-Win drivers"; return 0
    fi
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
    if ! is_installed docker || ! is_installed libvirt-utils; then
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
# Steam needs a proprietary-EULA package that main can't carry - non-free
# (enabled by bootstrap_repos) may have it; if package_exists() still says
# no, Flathub's official com.valvesoftware.Steam is the fallback, and the
# same repo-then-Flathub dance applies to Lutris. OpenMandriva handles
# 32-bit multilib natively via .i686 builds, so there's no Ubuntu-style
# "dpkg --add-architecture i386" step needed at all.
# Repo package if it installs, Flathub otherwise - including when the
# package exists but dnf can't install it on this particular system (a
# dependency clash with something already installed, as Lutris hit on one
# Rolling install while installing fine on fresh Rock and Rolling). dnf's
# reason is shown before falling back.
# Usage: install_repo_or_flathub <package> <flatpak app id> <label>
install_repo_or_flathub() {
    local pkg="$1" app="$2" label="$3" err
    if is_installed "$pkg"; then
        SKIPPED_PACKAGES+=("$pkg"); ((TOTAL_SKIPPED++)); log INFO "Already installed: $pkg"; return 0
    fi
    if command -v flatpak &>/dev/null && flatpak info "$app" &>/dev/null; then
        SKIPPED_PACKAGES+=("$label"); ((TOTAL_SKIPPED++)); log INFO "Already installed: $label (flatpak)"; return 0
    fi
    if package_exists "$pkg"; then
        log INFO "Installing: $pkg"
        err=$(mktemp)
        if dnf install -y "$pkg" >/dev/null 2>"$err" || is_installed "$pkg"; then
            rm -f "$err"
            INSTALLED_PACKAGES+=("$pkg"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: $pkg"; return 0
        fi
        log WARNING "dnf couldn't install $pkg - falling back to Flathub. dnf said:"
        grep -v '^[[:space:]]*$' "$err" | tail -n 6 | sed 's/^/    /'
        rm -f "$err"
    fi
    flatpak_install_flathub "$app" "$label"
}

install_gaming() {
    install_repo_or_flathub steam com.valvesoftware.Steam "Steam"
    install_repo_or_flathub lutris net.lutris.Lutris "Lutris"
    batch_install "Gaming (tweaks)" gamemode mangohud
}

# ========== OFFICE & PRODUCTIVITY ==========
install_office() {
    # gnome-papers is GNOME's replacement for Evince in newer GNOME releases;
    # both are listed since which one is present depends on the exact Fedora
    # release - package_exists skips whichever isn't there.
    batch_install "Office" libreoffice okular evince papers zathura
    install_pandoc_release
}

# pandoc - not packaged for OpenMandriva (neither pandoc nor pandoc-cli).
# The official Linux release build (github.com/jgm/pandoc) is a static
# binary whose tarball is laid out like a prefix (bin/, share/man/), so it
# unpacks straight into /usr/local.
install_pandoc_release() {
    if command -v pandoc &>/dev/null || [ -x /usr/local/bin/pandoc ]; then
        SKIPPED_PACKAGES+=("pandoc"); ((TOTAL_SKIPPED++)); log INFO "Already installed: pandoc"; return 0
    fi
    local tag t
    tag=$(curl -fsSL https://api.github.com/repos/jgm/pandoc/releases/latest 2>/dev/null \
        | grep -oE '"tag_name":[[:space:]]*"[0-9.]+"' | grep -oE '[0-9][0-9.]*')
    [ -z "$tag" ] && tag="3.12"
    log INFO "Installing pandoc $tag (official release build)..."
    t=$(mktemp -d)
    if curl -fsSL --retry 3 -o "$t/pandoc.tar.gz" \
            "https://github.com/jgm/pandoc/releases/download/$tag/pandoc-$tag-linux-amd64.tar.gz" 2>/dev/null \
        && tar -xzf "$t/pandoc.tar.gz" -C /usr/local --strip-components=1 \
        && /usr/local/bin/pandoc --version &>/dev/null; then
        rm -rf "$t"
        INSTALLED_PACKAGES+=("pandoc"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: pandoc $tag (/usr/local/bin/pandoc)"; return 0
    fi
    rm -rf "$t"
    FAILED_PACKAGES+=("pandoc"); ((TOTAL_FAILED++)); log WARNING "pandoc install failed"; return 0
}

# ========== SYSTEM UTILITIES ==========
install_system_utils() {
    # Charm publishes their own yum repo for glow (a markdown-in-terminal
    # renderer) - no Fedora COPR/official build exists. Exact repo stanza
    # from their own install docs (github.com/charmbracelet/glow#installation).
    # Unsigned here (see om_relax_vendor_repos): Rolling's rpm can't parse
    # Charm's signing key ("Parsing armored OpenPGP packet(s) failed").
    if [ ! -f /etc/yum.repos.d/charm.repo ]; then
        log INFO "Adding Charm's yum repo (for glow)..."
        cat > /etc/yum.repos.d/charm.repo <<'REPOEOF'
[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
REPOEOF
    fi
    om_relax_vendor_repos
    pm_update
    # glances, ripgrep and vnstat are installed separately below: the first
    # two aren't packaged for OpenMandriva (Rolling's "rg" package is a
    # different program - a ripgrep-compatible GNU grep, not ripgrep), and
    # OpenMandriva's vnstat package is uninstallable (it requires
    # user(vnstat)/group(vnstat), which nothing provides).
    batch_install "System Utils" \
        htop iotop sysstat \
        nethogs iftop nload tcpdump wireshark \
        lsof strace ltrace valgrind gdb \
        tmux screen zsh fish fzf tree ncdu rsync unzip bat glow
    install_glances
    install_ripgrep_release
    install_vnstat_source
    # NOTE: unlike Ubuntu's "bat" package (which installs as /usr/bin/batcat
    # due to a Debian name collision), RPM distros' "bat" packages typically
    # install straight to /usr/bin/bat - if OpenMandriva's does too, no
    # alias/rename is needed here.
}

# glances (system monitor) - not packaged for OpenMandriva; it's a Python
# app on PyPI, so install it system-wide with pipx (/opt/pipx, launcher in
# /usr/local/bin) rather than into the system Python.
install_glances() {
    if command -v glances &>/dev/null || [ -x /usr/local/bin/glances ]; then
        SKIPPED_PACKAGES+=("glances"); ((TOTAL_SKIPPED++)); log INFO "Already installed: glances"; return 0
    fi
    log INFO "Installing glances (pipx --global - not packaged for OpenMandriva)..."
    if ensure_pipx && PATH="/usr/local/bin:$PATH" pipx install --global glances &>/dev/null \
        && [ -x /usr/local/bin/glances ]; then
        INSTALLED_PACKAGES+=("glances"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: glances (/usr/local/bin/glances)"; return 0
    fi
    FAILED_PACKAGES+=("glances"); ((TOTAL_FAILED++)); log WARNING "glances install failed"; return 0
}

# ripgrep - not packaged for OpenMandriva. The official release's static
# (musl) build, checksum-verified against the .sha256 published with it.
install_ripgrep_release() {
    if [ -x /usr/local/bin/rg ] || { command -v rg &>/dev/null && rg --version 2>/dev/null | grep -q '^ripgrep '; }; then
        SKIPPED_PACKAGES+=("ripgrep"); ((TOTAL_SKIPPED++)); log INFO "Already installed: ripgrep"; return 0
    fi
    local tag name t
    tag=$(curl -fsSL https://api.github.com/repos/BurntSushi/ripgrep/releases/latest 2>/dev/null \
        | grep -oE '"tag_name":[[:space:]]*"[0-9.]+"' | grep -oE '[0-9][0-9.]*')
    [ -z "$tag" ] && tag="15.2.0"
    name="ripgrep-$tag-x86_64-unknown-linux-musl"
    log INFO "Installing ripgrep $tag (official static release build)..."
    t=$(mktemp -d)
    if curl -fsSL --retry 3 -o "$t/$name.tar.gz" "https://github.com/BurntSushi/ripgrep/releases/download/$tag/$name.tar.gz" 2>/dev/null \
        && curl -fsSL --retry 3 -o "$t/$name.tar.gz.sha256" "https://github.com/BurntSushi/ripgrep/releases/download/$tag/$name.tar.gz.sha256" 2>/dev/null \
        && (cd "$t" && sha256sum -c "$name.tar.gz.sha256" &>/dev/null) \
        && tar -xzf "$t/$name.tar.gz" -C "$t" \
        && install -Dm755 "$t/$name/rg" /usr/local/bin/rg; then
        [ -f "$t/$name/doc/rg.1" ] && install -Dm644 "$t/$name/doc/rg.1" /usr/local/share/man/man1/rg.1
        [ -f "$t/$name/complete/rg.bash" ] && install -Dm644 "$t/$name/complete/rg.bash" /usr/share/bash-completion/completions/rg
        rm -rf "$t"
        INSTALLED_PACKAGES+=("ripgrep"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: ripgrep $tag (/usr/local/bin/rg)"; return 0
    fi
    rm -rf "$t"
    FAILED_PACKAGES+=("ripgrep"); ((TOTAL_FAILED++)); log WARNING "ripgrep install failed"; return 0
}

# vnstat - OpenMandriva's own package can't be installed (it requires
# user(vnstat)/group(vnstat) and nothing provides either), so build the
# official release (github.com/vergoh/vnstat) into /usr/local with its config
# in /etc, and run it with vnstat's own hardened systemd unit
# (examples/systemd/vnstat.service), pointed at the /usr/local daemon.
install_vnstat_source() {
    if command -v vnstat &>/dev/null || [ -x /usr/local/bin/vnstat ]; then
        SKIPPED_PACKAGES+=("vnstat"); ((TOTAL_SKIPPED++)); log INFO "Already installed: vnstat"; return 0
    fi
    batch_install "vnstat build deps" gcc glibc-devel make lib64sqlite3-devel
    local tag t
    tag=$(curl -fsSL https://api.github.com/repos/vergoh/vnstat/releases/latest 2>/dev/null \
        | grep -oE '"tag_name":[[:space:]]*"v[0-9.]+"' | grep -oE 'v[0-9.]+')
    [ -z "$tag" ] && tag="v2.13"
    log INFO "Building vnstat ${tag#v} from source..."
    t=$(mktemp -d)
    if curl -fsSL --retry 3 -o "$t/vnstat.tar.gz" "https://github.com/vergoh/vnstat/releases/download/$tag/vnstat-${tag#v}.tar.gz" 2>/dev/null \
        && tar -xzf "$t/vnstat.tar.gz" -C "$t" \
        && (cd "$t/vnstat-${tag#v}" && ./configure --prefix=/usr/local --sysconfdir=/etc &>/dev/null \
            && make -j"$(nproc)" &>/dev/null && make install &>/dev/null) \
        && [ -x /usr/local/bin/vnstat ] && [ -x /usr/local/sbin/vnstatd ]; then
        sed 's#^ExecStart=/usr/sbin/vnstatd#ExecStart=/usr/local/sbin/vnstatd#' \
            "$t/vnstat-${tag#v}/examples/systemd/vnstat.service" > /etc/systemd/system/vnstat.service
        systemctl daemon-reload 2>/dev/null
        systemctl enable --now vnstat 2>/dev/null
        rm -rf "$t"
        INSTALLED_PACKAGES+=("vnstat"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: vnstat ${tag#v} (built from source, service: vnstat)"; return 0
    fi
    rm -rf "$t"
    FAILED_PACKAGES+=("vnstat"); ((TOTAL_FAILED++)); log WARNING "vnstat source build failed"; return 0
}

# ========== ANDROID TOOLS ==========
install_android_tools() {
    # adb+fastboot ride the same single "android-tools" package as on
    # Fedora. scrcpy isn't confirmed in OpenMandriva's repos -
    # package_exists() skips it cleanly if absent; the official GitHub
    # release build is the manual fallback if you need it.
    batch_install "Android Tools" android-tools scrcpy
}

# ========== AI TOOLS ==========
# Almost entirely package-manager-agnostic (vendor curl|bash installers,
# npm globals, Flathub) - ported near-verbatim from the Fedora/Ubuntu
# scripts. The vendor yum repos kept here (Cursor, Claude Desktop) use
# distro-generic baseurls - their RPMs are BUILT against Fedora, so a
# failed dependency resolution just lands in FAILED_PACKAGES like any
# other miss rather than breaking the run.
install_ai_tools() {
    log INFO "Installing AI Tools..."
    install_ollama
    install_jan
    install_ai_key_manager
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

# Jan (https://www.jan.ai/) - local-first, OpenAI-alternative desktop chat
# client with its own local model runner (llama.cpp-based) plus support for
# remote providers. Flathub-only (no vendor rpm/COPR package exists).
install_jan() { flatpak_install_flathub ai.jan.Jan "Jan"; }

# AI API key manager - GUI (zenity) for storing/testing/removing Anthropic and
# Mistral API keys in the Secret Service keyring (service=anthropic|mistral),
# readable by any tool that shells out to `secret-tool lookup` for its own
# credentials. Keys never touch
# argv, disk or shell history. Installs /usr/local/bin/ai-key-manager plus a
# launcher so it shows up in rofi drun / any app menu as "AI API Keys".
# Prefers the repo copy (ai-key-manager.sh next to this script) so edits live
# in one place; falls back to the embedded copy when run standalone.
install_ai_key_manager() {
    # OpenMandriva names: the real GTK zenity is zenity-gtk (it pulls in
    # zenity-wrapper, which provides /usr/bin/zenity; a plain "zenity" only
    # resolves to qarma, a Qt clone, on Rock), and secret-tool is in
    # libsecret-tools ("libsecret" only resolves to the bare library,
    # lib64secret1_0, without secret-tool).
    batch_install "AI Key Manager deps" zenity-gtk libsecret-tools gnome-keyring curl

    local dir src
    dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    src="$dir/ai-key-manager.sh"
    if [ -f "$src" ]; then
        install -Dm755 "$src" /usr/local/bin/ai-key-manager
    else
        cat > /usr/local/bin/ai-key-manager <<'AIKEYMGR_EOF'
#!/usr/bin/env bash
# ai-key-manager — store/test/remove Anthropic + Mistral API keys in the
# Secret Service keyring (GNOME Keyring). Readable by any tool that shells
# out to secret-tool for its own credentials, e.g.:
#   secret-tool lookup service anthropic|mistral
# Keys never touch argv, disk, or shell history: zenity -> stdin -> secret-tool,
# and curl reads its auth header from a process-substitution fd.
# Deps: zenity, secret-tool (libsecret), curl, a running Secret Service daemon.
set -u

TITLE="AI API Keys"

die() { zenity --error --title="$TITLE" --width=360 --text="$1" 2>/dev/null; exit 1; }
for c in zenity secret-tool curl; do
  command -v "$c" >/dev/null || { notify-send "$TITLE" "Missing dependency: $c" 2>/dev/null; echo "missing $c" >&2; exit 1; }
done

label()  { case $1 in anthropic) echo "Anthropic (Claude)";; mistral) echo "Mistral";; esac; }

# HTTP status of GET /v1/models with the given key (key passed on stdin).
test_key() {
  local svc=$1 key
  IFS= read -r key
  case $svc in
    anthropic)
      curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
        -H @<(printf 'x-api-key: %s\nanthropic-version: 2023-06-01\n' "$key") \
        https://api.anthropic.com/v1/models ;;
    mistral)
      curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
        -H @<(printf 'Authorization: Bearer %s\n' "$key") \
        https://api.mistral.ai/v1/models ;;
  esac
}

explain() {
  case $1 in
    200) echo "valid";;
    401|403) echo "rejected (invalid or revoked key)";;
    000) echo "no response (network?)";;
    *) echo "HTTP $1";;
  esac
}

set_key() {
  local svc=$1 key code
  key=$(zenity --password --title="$TITLE — $(label "$svc")" 2>/dev/null) || return
  key=$(printf '%s' "$key" | tr -d '[:space:]')
  [[ -n $key ]] || { die "Empty key — nothing stored."; }

  # Sanity check: catches the "typed my login password" mistake.
  if [[ $svc == anthropic && $key != sk-ant-* ]]; then
    zenity --question --title="$TITLE" --width=380 \
      --text="This doesn't look like an Anthropic API key (should start with sk-ant-).\n\nStore it anyway?" 2>/dev/null || return
  fi

  code=$(printf '%s\n' "$key" | test_key "$svc")
  if [[ $code != 200 ]]; then
    zenity --question --title="$TITLE" --width=380 \
      --text="$(label "$svc") says: $(explain "$code").\n\nStore it anyway?" 2>/dev/null || { key=; return; }
  fi

  if printf '%s' "$key" | secret-tool store --label="$(label "$svc") API" service "$svc"; then
    zenity --info --title="$TITLE" --width=320 --text="$(label "$svc") key stored ($(explain "$code"))." 2>/dev/null
  else
    die "Could not write to the keyring. Is gnome-keyring-daemon running?"
  fi
  key=
}

status() {
  local out="" svc key code
  for svc in anthropic mistral; do
    key=$(secret-tool lookup service "$svc" 2>/dev/null)
    if [[ -z $key ]]; then
      out+="$(label "$svc"): not set\n"
    else
      code=$(printf '%s\n' "$key" | test_key "$svc")
      out+="$(label "$svc"): stored, $(explain "$code")\n"
    fi
  done
  key=
  zenity --info --title="$TITLE — status" --width=360 --text="$out" 2>/dev/null
}

remove_key() {
  local svc=$1
  zenity --question --title="$TITLE" --width=320 \
    --text="Remove the stored $(label "$svc") key?" 2>/dev/null || return
  secret-tool clear service "$svc"
  zenity --info --title="$TITLE" --width=300 --text="$(label "$svc") key removed." 2>/dev/null
}

while :; do
  choice=$(zenity --list --title="$TITLE" --width=380 --height=320 \
    --text="Keys are stored in your login keyring." \
    --column="id" --column="Action" --hide-column=1 --print-column=1 \
    set-anthropic "Set Anthropic (Claude) key" \
    set-mistral   "Set Mistral key" \
    status        "Test stored keys" \
    rm-anthropic  "Remove Anthropic key" \
    rm-mistral    "Remove Mistral key" 2>/dev/null) || exit 0
  case $choice in
    set-anthropic) set_key anthropic ;;
    set-mistral)   set_key mistral ;;
    status)        status ;;
    rm-anthropic)  remove_key anthropic ;;
    rm-mistral)    remove_key mistral ;;
    *)             exit 0 ;;
  esac
done
AIKEYMGR_EOF
        chmod 755 /usr/local/bin/ai-key-manager
    fi

    cat > /usr/share/applications/ai-key-manager.desktop <<'AIKEYMGR_EOF'
[Desktop Entry]
Type=Application
Name=AI API Keys
GenericName=API Key Manager
Comment=Store and test Anthropic (Claude) and Mistral API keys in the keyring
Exec=/usr/local/bin/ai-key-manager
Icon=dialog-password
Terminal=false
Categories=Utility;Security;Settings;
Keywords=claude;anthropic;mistral;api;key;secret;
AIKEYMGR_EOF
    chmod 644 /usr/share/applications/ai-key-manager.desktop

    if [ -x /usr/local/bin/ai-key-manager ]; then
        INSTALLED_PACKAGES+=("ai-key-manager"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: ai-key-manager (app menu: 'AI API Keys')"
    else
        FAILED_PACKAGES+=("ai-key-manager"); ((TOTAL_FAILED++))
        log WARNING "ai-key-manager install failed"
    fi
    return 0
}

# LocalAI (https://github.com/mudler/LocalAI) - OpenAI-compatible local
# inference server. No rpm/COPR package exists; the GitHub release ships a
# plain, self-contained binary per arch (local-ai-<version>-linux-<amd64|
# arm64>, no archive to extract) rather than a vendor install script, so
# resolve the latest release via the GitHub API and drop the binary
# straight into /usr/local/bin, same approach as install_displaylink's rpm
# lookup above.
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
    om_relax_vendor_repos  # its .repo has gpgcheck/repo_gpgcheck=1 - unreadable key here
    pm_update
    safe_install claude-desktop-unofficial
    # The rpm itself only requires /bin/sh, so it installs fine here - it's
    # the repo route (signed metadata, repo_gpgcheck=1) that's fragile. Fall
    # back to the newest rpm listed in the repo's own metadata, installed
    # as a local file.
    if ! is_installed claude-desktop-unofficial; then
        local base=https://pkg.claude-desktop-debian.dev/rpm/x86_64 prim rpm
        prim=$(curl -fsSL "$base/repodata/repomd.xml" 2>/dev/null \
            | tr -d '\n' | grep -oE '<data type="primary">.*</data>' \
            | grep -oE 'href="repodata/[^"]*primary[^"]*"' | head -1 | sed 's/^href="//;s/"$//')
        [ -n "$prim" ] && rpm=$(curl -fsSL "$base/$prim" 2>/dev/null | gzip -dc 2>/dev/null \
            | grep -oE 'href="claude-desktop-unofficial-[0-9][^"]*\.x86_64\.rpm"' \
            | sed 's/^href="//;s/"$//' | sort -V | tail -1)
        if [ -n "$rpm" ]; then
            install_vendor_rpm_direct claude-desktop-unofficial "$base/$rpm" "Claude Desktop" || true
        else
            log WARNING "Couldn't read the Claude Desktop repo metadata for a direct rpm"
        fi
    fi
    om_relax_vendor_repos
}

# Zed (https://zed.dev) - GPU-accelerated code editor. No Fedora/COPR
# package; the vendor's own install script is the supported Linux path
# and drops the binary in ~/.local, so it must run as the invoking user
# rather than root - same shape as install_opencode/install_vibe_cli above.
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

# Gram (https://codeberg.org/GramEditor/gram) - a Zed-editor fork (its
# changelog references upstream zed# issue numbers throughout, confirmed by
# reading a real release's notes, not assumed from the name). Not packaged
# for Fedora/COPR - Codeberg's own release assets include a self-contained
# Linux tarball (gram.app/ - bin/gram, libexec/gram-editor, bundled
# lib/*.so, share/applications/gram.desktop, share/icons/...) rather than an
# .rpm, so the whole bundle is extracted into /opt (keeping bin/libexec/lib
# together, since gram's own launcher finds its sibling files by a path
# relative to itself) and only its .desktop/icons get copied into the usual
# system locations; bin/gram is symlinked onto PATH rather than copied out
# alone. Version pinned to the one actually tested (3.3.0) rather than
# resolved via Codeberg's API at install time, unlike claude-desktop above.
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

# Neural Inverse (https://github.com/NeuralInverse/neuralinverse) - AI coding
# IDE. Not packaged for Fedora/COPR - vendor curl|bash installer is genuinely
# non-interactive with --ide (skips the arrow-key IDE/CLI/Both selector
# entirely, and the only interactive prompt in the installer itself - a CLI
# terms-of-use acceptance - only triggers for CLI/Both installs, never for
# --ide alone; confirmed by reading the installer script before using it,
# not assumed from its docs). Installs into ~/.local/bin, same as opencode
# above.
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
    # The installer is the only documented install method (the GitHub
    # releases carry no IDE builds), and neuralinverse.com has been answering
    # every request with HTTP 402 Payment Required. Check it's reachable
    # first, so an unavailable installer is reported as skipped rather than
    # as a failed install - it picks up again on its own once the site is back.
    if ! curl -fsSL -o /dev/null --max-time 20 https://neuralinverse.com/sh 2>/dev/null; then
        SKIPPED_PACKAGES+=("neuralinverse (installer site unavailable)"); ((TOTAL_SKIPPED++))
        log WARNING "Neural Inverse installer (neuralinverse.com/sh) is unavailable right now - skipping; re-run later"
        return 0
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

# Cursor now ships an official yum repo (downloads.cursor.com/yumrepo),
# unlike the Ubuntu script's .deb/AppImage download-API dance - a real repo
# means normal `dnf upgrade` keeps it current from here on.
install_cursor() {
    if command -v cursor &>/dev/null || is_installed cursor; then
        SKIPPED_PACKAGES+=("cursor"); ((TOTAL_SKIPPED++)); log INFO "Already installed: cursor"; return 0
    fi
    log INFO "Installing Cursor (official yum repo, unsigned - see om_relax_vendor_repos)..."
    cat > /etc/yum.repos.d/cursor.repo <<'EOF'
[cursor]
name=Cursor
baseurl=https://downloads.cursor.com/yumrepo
enabled=1
EOF
    om_relax_vendor_repos
    pm_update
    safe_install cursor
    om_relax_vendor_repos  # the rpm's install script rewrites cursor.repo
}

# LM Studio (lmstudio.ai) - GUI desktop app for discovering/running local
# LLMs (GGUF models, local OpenAI-compatible API server). No rpm/COPR exists
# (LM Studio ships Windows/macOS installers + a Linux AppImage only) - but it
# does have an official Flathub package (confirmed via a live Flathub API
# search), so that's the right path here rather than hand-rolling an
# AppImage-download wrapper.
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
    # gext installs through GNOME Shell's own D-Bus service (org.gnome.Shell),
    # so outside a GNOME session (i3, KDE, ...) every extension fails with
    # "The name org.gnome.Shell was not provided by any .service files".
    if ! pgrep -u "$uid" -x gnome-shell &>/dev/null; then
        log INFO "GNOME Shell isn't running in this session (i3/KDE/...) - skipping GNOME extensions"
        SKIPPED_PACKAGES+=("GNOME extensions (no GNOME Shell session)"); ((TOTAL_SKIPPED++))
        return 0
    fi
    ensure_pipx || log WARNING "pipx unavailable - gext install will likely fail"
    log INFO "Setting up gext (GNOME Extension Manager CLI) via pipx..."
    su - "$user" -c 'PATH="$HOME/.local/bin:$PATH" command -v gext >/dev/null 2>&1 || PATH="/usr/local/bin:$PATH" pipx install gnome-extensions-cli --system-site-packages' 2>/dev/null
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
        cmake pkgconf systemd-devel libevdev-devel libconfig-devel glib2-devel gcc-c++
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
# github.com/itzender5820/mousiki - no COPR/RPM package, no binary release
# (the one GitHub release is a source zip) - the project's own setup.sh is
# source-build-only everywhere, so this mirrors that script's real Fedora
# dependency list and build steps by hand rather than shelling out to it.
install_mousiki() {
    log INFO "Installing Mousiki build dependencies..."
    batch_install "Mousiki build deps" cmake gcc-c++ make ffmpeg yt-dlp python python-pip
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
# user rather than root, matching this script's own LazyVim/user-config
# pattern elsewhere.
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
    # No gnome-extensions-app here: on OpenMandriva the Extensions app is part
    # of the gnome-shell package itself (not a separate package), so it's
    # already present wherever GNOME is - and useless without it (e.g. i3).
    batch_install "GUI Tools" \
        gnome-tweaks \
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
    # Packaged on OpenMandriva: papirus-icon-theme, adwaita-icon-theme and
    # Breeze (named breeze-icons here, not breeze-icon-theme). Numix,
    # Numix Circle and Obsidian aren't packaged on Rock or Rolling - they're
    # plain icon folders, so install them from their upstream repos below.
    # (This line used to end in a doubled backslash, which ended the command
    # there - batch_install got no packages and every name below it ran as
    # a command of its own, "command not found".)
    batch_install "Icon Sets" \
        papirus-icon-theme \
        breeze-icons \
        adwaita-icon-theme
    install_git_icon_theme "Numix icons" https://github.com/numixproject/numix-icon-theme.git Numix Numix-Light
    # Numix Circle inherits Numix, so it goes after it
    install_git_icon_theme "Numix Circle icons" https://github.com/numixproject/numix-icon-theme-circle.git Numix-Circle Numix-Circle-Light
    install_git_icon_theme "Obsidian icons" https://github.com/madmaxms/iconpack-obsidian.git 'Obsidian*'
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

    local marker="/var/lib/openmandriva-postinstall-themes/${slug}.done"
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
    # The GTK themes compile their CSS with sassc, and their install.sh
    # installs it itself if missing - but with a plain `sudo dnf install
    # sassc` (no -y; zypper likewise), whose confirmation prompt is hidden
    # by the 2>/dev/null below, so the run silently hung after listing
    # sassc. Install it up front, and give install.sh no stdin so any
    # future prompt fails fast instead of hanging.
    [ "$kind" = "theme" ] && ! command -v sassc &>/dev/null && safe_install sassc
    if bash "$t/src/install.sh" "${extra_args[@]}" </dev/null 2>/dev/null; then
        mkdir -p "$(dirname "$marker")" && touch "$marker"
        INSTALLED_PACKAGES+=("$label $kind"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: $label $kind (pick via gnome-tweaks)"
    else
        FAILED_PACKAGES+=("$label $kind"); ((TOTAL_FAILED++)); log WARNING "$label $kind install failed"
    fi
    rm -rf "$t"
}

# Icon theme that's just theme folders at the top of a git repo: clone it and
# copy the named folders (globs allowed) into /usr/share/icons.
install_git_icon_theme() {  # <label> <git url> <folder>...
    local label="$1" url="$2"; shift 2
    local first="${1%\*}"
    if compgen -G "/usr/share/icons/${first}*" >/dev/null; then
        SKIPPED_PACKAGES+=("$label"); ((TOTAL_SKIPPED++)); log INFO "Already installed: $label"; return 0
    fi
    local t; t=$(mktemp -d)
    if ! git clone --depth 1 "$url" "$t/src" 2>/dev/null; then
        rm -rf "$t"; FAILED_PACKAGES+=("$label"); ((TOTAL_FAILED++))
        log WARNING "$label clone failed (needs network access to github.com)"; return 1
    fi
    log INFO "Installing $label..."
    local ok=true pat d
    for pat in "$@"; do
        for d in "$t"/src/$pat; do
            [ -d "$d" ] || { ok=false; continue; }
            cp -r "$d" /usr/share/icons/ 2>/dev/null || ok=false
            gtk-update-icon-cache -q -f "/usr/share/icons/$(basename "$d")" 2>/dev/null || true
        done
    done
    if $ok; then
        INSTALLED_PACKAGES+=("$label"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: $label (/usr/share/icons)"
    else
        FAILED_PACKAGES+=("$label"); ((TOTAL_FAILED++)); log WARNING "$label install failed"
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
    log INFO "Installing Nordic theme..."
    # The Nordic repo's top level IS the theme (index.theme, gtk-3.0/, ...),
    # with no Nordic/ subfolder - so the old clone + `cp -r src/Nordic` never
    # copied anything, on any distro. Use the release's own prebuilt
    # Nordic.tar.xz instead: exactly one clean Nordic/ theme folder, without
    # the repo's development files (src/, Gulpfile.js, package.json, ...).
    if su - "$user" -c "curl -fsSL --retry 3 -o '$t/Nordic.tar.xz' https://github.com/EliverLara/Nordic/releases/latest/download/Nordic.tar.xz && mkdir -p '$uh/.themes' && tar -xJf '$t/Nordic.tar.xz' -C '$uh/.themes'" 2>/dev/null \
        && [ -f "$uh/.themes/Nordic/index.theme" ]; then
        INSTALLED_PACKAGES+=("Nordic theme"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: Nordic theme (~/.themes - pick it in gnome-tweaks)"
    else
        FAILED_PACKAGES+=("Nordic theme"); ((TOTAL_FAILED++))
        log WARNING "Nordic theme download failed (needs network access to github.com)"
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
    # GTK murrine engine + gnome-themes-extra assets are runtime deps the
    # theme itself needs to render - not something its installer pulls in.
    # OpenMandriva packages the engine simply as "murrine".
    batch_install "Lycia Theme Dependencies" murrine sassc gnome-themes-extra
    local t; t=$(mktemp -d); chmod 755 "$t"; chown "$user" "$t" 2>/dev/null
    if ! su - "$user" -c "git clone --depth 1 https://github.com/Aevstiel/Lycia-Theme.git '$t/src'" 2>/dev/null; then
        rm -rf "$t"; FAILED_PACKAGES+=("Lycia theme"); ((TOTAL_FAILED++))
        log WARNING "Lycia theme clone failed (needs network access to github.com)"; return 1
    fi
    # install.sh interactively asks two questions: install the GTK4/Libadwaita
    # files (yes) and install the GDM login-screen theme (no - that overwrites
    # a system gnome-shell resource file, too invasive for an unattended run).
    log INFO "Installing Lycia theme..."
    # Upstream bug: install.sh runs under `set -euo pipefail` and looks for an
    # earlier GTK4 backup with `ls ... | head`, which fails (and so exits the
    # installer, code 2) on every first run - before the GTK4 symlinks are
    # made. Let that lookup come back empty instead, as it intends to.
    sed -i 's#2>/dev/null | head -n1)"#2>/dev/null | head -n1 || true)"#' "$t/src/install.sh"
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
    # OpenMandriva has no standalone Breeze cursor package (Fedora's
    # xcursor-breeze / breeze-cursor-theme): its cursors only ship inside the
    # KDE `breeze` style package, which pulls in the whole KF/Qt stack. The
    # cursors are prebuilt Xcursor files in KDE's own breeze repo, though -
    # fetch just those two folders from invent.kde.org into the same
    # /usr/share/icons names Fedora's package uses (breeze_cursors,
    # Breeze_Light).
    log INFO "Installing Cursor Themes..."
    local t name src dest
    for name in Breeze Breeze_Light; do
        src="cursors/$name/$name"
        [ "$name" = Breeze ] && dest=/usr/share/icons/breeze_cursors || dest="/usr/share/icons/$name"
        if [ -f "$dest/index.theme" ]; then
            SKIPPED_PACKAGES+=("$name cursors"); ((TOTAL_SKIPPED++)); log INFO "Already installed: $name cursors"; continue
        fi
        t=$(mktemp -d)
        if curl -fsSL --retry 3 -o "$t/c.tar.gz" "https://invent.kde.org/plasma/breeze/-/archive/master/breeze-master.tar.gz?path=$src" 2>/dev/null \
            && tar -xzf "$t/c.tar.gz" -C "$t" \
            && [ -f "$t/breeze-master-${src//\//-}/$src/index.theme" ] \
            && rm -rf "$dest" && cp -a "$t/breeze-master-${src//\//-}/$src" "$dest"; then
            INSTALLED_PACKAGES+=("$name cursors"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: $name cursors ($dest)"
        else
            FAILED_PACKAGES+=("$name cursors"); ((TOTAL_FAILED++)); log WARNING "$name cursors download failed (needs network access to invent.kde.org)"
        fi
        rm -rf "$t"
    done
}

# Fira Code and JetBrains Mono (the plain, non-Nerd fonts) aren't packaged
# for OpenMandriva - install their official release zips instead, into
# /usr/share/fonts/truetype/<dir>. Usage: install_release_font <label> <owner/repo> <dir>
install_release_font() {
    local label="$1" repo="$2" dir="$3" url t
    if [ -d "/usr/share/fonts/truetype/$dir" ]; then
        SKIPPED_PACKAGES+=("$label"); ((TOTAL_SKIPPED++)); log INFO "Already installed: $label"; return 0
    fi
    command -v unzip &>/dev/null || safe_install unzip
    url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
        | grep -oE '"browser_download_url":[[:space:]]*"[^"]+\.zip"' | head -1 | grep -oE 'https://[^"]+')
    t=$(mktemp -d)
    if [ -n "$url" ] && curl -fsSL --retry 3 -o "$t/f.zip" "$url" 2>/dev/null \
        && unzip -qq -o "$t/f.zip" -d "$t/x" \
        && mkdir -p "/usr/share/fonts/truetype/$dir" \
        && find "$t/x" -path '*/ttf/*' -iname '*.ttf' -exec cp {} "/usr/share/fonts/truetype/$dir/" \; \
        && [ -n "$(ls -A "/usr/share/fonts/truetype/$dir")" ]; then
        INSTALLED_PACKAGES+=("$label"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: $label (${url##*/})"
    else
        rm -rf "/usr/share/fonts/truetype/$dir"
        FAILED_PACKAGES+=("$label"); ((TOTAL_FAILED++)); log WARNING "$label download failed (needs network access to github.com)"
    fi
    rm -rf "$t"
}

install_nerd_fonts() {
    log INFO "Installing Nerd Fonts..."
    mkdir -p /usr/share/fonts/truetype/nerd-fonts
    install_release_font "Fira Code" tonsky/FiraCode fira-code
    install_release_font "JetBrains Mono" JetBrains/JetBrainsMono jetbrains-mono
    command -v fc-cache &>/dev/null && fc-cache -f /usr/share/fonts/truetype/ 2>/dev/null
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
    # "Already installed" only counts if starship actually made it in too -
    # earlier runs of this script left ~/mybash in place with no starship
    # (see below), and returning early here would never repair that.
    if [ -d "$MD" ] && { command -v starship &>/dev/null || [ -x /usr/local/bin/starship ]; }; then
        log INFO "mybash already installed"; return 0
    fi
    log INFO "Installing Chris Titus mybash..."
    if [ ! -d "$MD" ] && ! git clone --depth 1 https://github.com/christitustech/mybash "$MD"; then
        log ERROR "Clone failed"; return 1
    fi
    # OpenMandriva: mybash's setup.sh runs `set -eu` and does ONE
    # `sudo dnf install ... trash-cli ... zoxide ...` - trash-cli isn't packaged
    # here (zoxide neither, on Rock), so that dnf call failed, setup.sh exited
    # on the spot, and starship + mybash's config links were never installed -
    # leaving a .bashrc whose prompt theming (starship.toml, which the desktop
    # theme switcher rewrites) nothing ever read. So:
    #   1. pre-install what does exist, and starship into /usr/local/bin
    #      (always on PATH - mybash's own install target, ~/.local/bin, isn't
    #      added to PATH by its .bashrc on Linux); trash-cli via pipx, zoxide
    #      via its official installer where it isn't packaged;
    #   2. run setup.sh with a `sudo` shim on PATH that adds --setopt=strict=0
    #      to its dnf call, so missing names are skipped instead of fatal.
    dnf install -y --setopt=strict=0 bash-completion bat tree multitail fastfetch neovim \
        fzf zoxide curl fontconfig tar xz >/dev/null 2>&1 || true
    if ! command -v starship &>/dev/null && [ ! -x /usr/local/bin/starship ]; then
        curl -fsSL https://starship.rs/install.sh 2>/dev/null | sh -s -- -y -b /usr/local/bin >/dev/null 2>&1 \
            || log WARNING "starship install failed - the shell prompt won't follow desktop themes"
    fi
    if ! command -v zoxide &>/dev/null && [ ! -x /usr/local/bin/zoxide ]; then
        curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh 2>/dev/null \
            | sh -s -- --bin-dir /usr/local/bin --man-dir /usr/local/share/man >/dev/null 2>&1 || true
    fi
    if ! command -v trash-put &>/dev/null && ensure_pipx; then
        PATH="/usr/local/bin:$PATH" pipx install --global trash-cli >/dev/null 2>&1 || true
    fi
    local shim
    shim=$(mktemp -d)
    cat > "$shim/sudo" <<'SHIMEOF'
#!/bin/sh
if [ "$1" = dnf ]; then shift; exec /usr/bin/dnf --setopt=strict=0 "$@"; fi
exec /usr/bin/sudo "$@"
SHIMEOF
    chmod 755 "$shim/sudo"
    # setup.sh calls `sudo apt-get install ...` internally on Debian/Ubuntu -
    # on Fedora it detects dnf and calls `sudo dnf install ...` instead (the
    # upstream script branches on package manager itself). Run as root, not
    # via su, for the same "nested sudo needs a real terminal" reason as the
    # Ubuntu script.
    # setup.sh's output is also kept in a log, so that when it fails the
    # reason can be shown right next to the fallback warning below instead
    # of scrolled away above it.
    local mlog; mlog=$(mktemp)
    if PATH="$shim:/usr/local/bin:$PATH" HOME="$UH" USER="$SUDO_USER" LOGNAME="$SUDO_USER" bash "$MD/setup.sh" 2>&1 | tee "$mlog"; [ "${PIPESTATUS[0]}" -eq 0 ]; then
        rm -rf "$shim" "$mlog"
        chown -R "$SUDO_USER:$SUDO_USER" "$MD" "$UH/.local" "$UH/.config" "$BR" 2>/dev/null || true
        log SUCCESS "mybash installed. User: source ~/.bashrc"
        return 0
    fi
    rm -rf "$shim"
    log WARNING "setup.sh failed - its last output was:"
    tail -n 8 "$mlog" | sed 's/^/    /'
    cp "$mlog" "$UH/mybash-setup.log" 2>/dev/null && chown "$SUDO_USER:$SUDO_USER" "$UH/mybash-setup.log" 2>/dev/null
    rm -f "$mlog"
    log WARNING "Full log: ~/mybash-setup.log - falling back to a plain .bashrc copy..."
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
# classic pentest tools are not guaranteed to be in OpenMandriva's repos at
# all (and there's no PPA/COPR-equivalent third-party layer to pull them
# from either) - this list keeps the best-known RPM-world package names, but
# expect more "Not in repos" skips here than in other categories. Real GUI
# tools (firewall-config, keepassxc) do get folder icons.
# Security tools that can't be installed from OpenMandriva's repos (checked
# against Rock and Rolling): hping3's package is uninstallable on both (needs
# libtcl8.6.so, which neither ships any more), and whatweb, radare2,
# steghide, yara and ettercap aren't packaged at all. Recorded as skipped
# with the reason, rather than as failures on every run. whatweb, radare2
# and yara are built from source instead (install_*_source below).
om_skip_unavailable() {  # <name> <reason>
    SKIPPED_PACKAGES+=("$1 ($2)"); ((TOTAL_SKIPPED++))
    log INFO "Skipping $1 - $2"
}

# gobuster - not packaged for OpenMandriva; official release build
# (github.com/OJ/gobuster), checksum-verified against the release's own
# checksums file.
install_gobuster_release() {
    if command -v gobuster &>/dev/null || [ -x /usr/local/bin/gobuster ]; then
        SKIPPED_PACKAGES+=("gobuster"); ((TOTAL_SKIPPED++)); log INFO "Already installed: gobuster"; return 0
    fi
    local tag t
    tag=$(curl -fsSL https://api.github.com/repos/OJ/gobuster/releases/latest 2>/dev/null \
        | grep -oE '"tag_name":[[:space:]]*"v[0-9.]+"' | grep -oE 'v[0-9.]+')
    [ -z "$tag" ] && tag="v3.8.2"
    log INFO "Installing gobuster ${tag#v} (official release build)..."
    t=$(mktemp -d)
    if curl -fsSL --retry 3 -o "$t/gobuster_Linux_x86_64.tar.gz" \
            "https://github.com/OJ/gobuster/releases/download/$tag/gobuster_Linux_x86_64.tar.gz" 2>/dev/null \
        && curl -fsSL --retry 3 -o "$t/checksums.txt" \
            "https://github.com/OJ/gobuster/releases/download/$tag/gobuster_${tag#v}_checksums.txt" 2>/dev/null \
        && (cd "$t" && grep ' gobuster_Linux_x86_64.tar.gz$' checksums.txt | sha256sum -c - &>/dev/null) \
        && tar -xzf "$t/gobuster_Linux_x86_64.tar.gz" -C "$t" \
        && install -Dm755 "$t/gobuster" /usr/local/bin/gobuster; then
        rm -rf "$t"
        INSTALLED_PACKAGES+=("gobuster"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: gobuster ${tag#v} (/usr/local/bin/gobuster)"; return 0
    fi
    rm -rf "$t"
    FAILED_PACKAGES+=("gobuster"); ((TOTAL_FAILED++)); log WARNING "gobuster install failed"; return 0
}

# Source-built tools below install shared libraries into /usr/local/lib*,
# which OpenMandriva's dynamic linker doesn't search by default.
ensure_local_lib_path() {
    [ -f /etc/ld.so.conf.d/usr-local.conf ] \
        || printf '/usr/local/lib\n/usr/local/lib64\n' > /etc/ld.so.conf.d/usr-local.conf
    ldconfig 2>/dev/null || true
}

# Latest release tag of a GitHub repo, or the given fallback.
gh_latest_tag() {  # <owner/repo> <fallback>
    local tag
    tag=$(curl -fsSL "https://api.github.com/repos/$1/releases/latest" 2>/dev/null \
        | grep -oE '"tag_name":[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/')
    echo "${tag:-$2}"
}

# yara - not packaged for OpenMandriva. Built from the release's source
# archive (github.com/VirusTotal/yara publishes no release files, so there's
# no separate checksum to verify against) as a static-libyara build, so the
# yara/yarac binaries don't depend on a shared library in /usr/local.
# LIBTOOLIZE=libtoolize: on Rolling, OpenMandriva's autoreconf defaults to
# slibtool's slibtoolize (not installed), not GNU libtool's libtoolize.
install_yara_source() {
    if command -v yara &>/dev/null || [ -x /usr/local/bin/yara ]; then
        SKIPPED_PACKAGES+=("yara"); ((TOTAL_SKIPPED++)); log INFO "Already installed: yara"; return 0
    fi
    batch_install "yara build deps" gcc glibc-devel make autoconf automake libtool pkgconf
    local tag t
    tag=$(gh_latest_tag VirusTotal/yara v4.5.8)
    log INFO "Building yara ${tag#v} from source..."
    t=$(mktemp -d)
    if curl -fsSL --retry 3 -o "$t/yara.tar.gz" "https://github.com/VirusTotal/yara/archive/refs/tags/$tag.tar.gz" 2>/dev/null \
        && tar -xzf "$t/yara.tar.gz" -C "$t" \
        && (cd "$t/yara-${tag#v}" && LIBTOOLIZE=libtoolize ./bootstrap.sh &>/dev/null \
            && ./configure --prefix=/usr/local --disable-shared &>/dev/null \
            && make -j"$(nproc)" &>/dev/null && make install &>/dev/null) \
        && /usr/local/bin/yara --version &>/dev/null; then
        rm -rf "$t"
        INSTALLED_PACKAGES+=("yara"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: yara ${tag#v} (built from source, /usr/local/bin/yara)"; return 0
    fi
    rm -rf "$t"
    FAILED_PACKAGES+=("yara"); ((TOTAL_FAILED++)); log WARNING "yara source build failed"; return 0
}

# radare2 - not packaged for OpenMandriva. Built from the official source
# tarball (radare2-<ver>.tar.xz), checksum-verified against the release's
# checksums.txt.
install_radare2_source() {
    if command -v r2 &>/dev/null || [ -x /usr/local/bin/r2 ]; then
        SKIPPED_PACKAGES+=("radare2"); ((TOTAL_SKIPPED++)); log INFO "Already installed: radare2"; return 0
    fi
    batch_install "radare2 build deps" gcc glibc-devel make patch pkgconf
    local tag t
    tag=$(gh_latest_tag radareorg/radare2 6.2.4)
    log INFO "Building radare2 $tag from source (takes a few minutes)..."
    t=$(mktemp -d)
    if curl -fsSL --retry 3 -o "$t/radare2-$tag.tar.xz" "https://github.com/radareorg/radare2/releases/download/$tag/radare2-$tag.tar.xz" 2>/dev/null \
        && curl -fsSL --retry 3 -o "$t/checksums.txt" "https://github.com/radareorg/radare2/releases/download/$tag/checksums.txt" 2>/dev/null \
        && (cd "$t" && grep "  radare2-$tag.tar.xz\$" checksums.txt | sha256sum -c - &>/dev/null) \
        && tar -xJf "$t/radare2-$tag.tar.xz" -C "$t" \
        && (cd "$t/radare2-$tag" && ./configure --prefix=/usr/local &>/dev/null \
            && make -j"$(nproc)" &>/dev/null && make install &>/dev/null); then
        ensure_local_lib_path
        if /usr/local/bin/r2 -v &>/dev/null; then
            rm -rf "$t"
            INSTALLED_PACKAGES+=("radare2"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: radare2 $tag (built from source, r2 in /usr/local/bin)"; return 0
        fi
    fi
    rm -rf "$t"
    FAILED_PACKAGES+=("radare2"); ((TOTAL_FAILED++)); log WARNING "radare2 source build failed"; return 0
}

# WhatWeb - not packaged for OpenMandriva. A Ruby program, installed from
# the release's source archive into /usr/local/share/whatweb with the
# command linked into /usr/local/bin - not via its own `make install`,
# which ends in `bundle install` (needs Bundler, and pulls in its test/dev
# gem groups too). Its runtime gems are just ipaddr, addressable and json;
# json ships with Ruby itself as a default gem (OpenMandriva's rubygem-json
# is only in the optional extra repo), the other two come from RubyGems.
install_whatweb_source() {
    if command -v whatweb &>/dev/null || [ -x /usr/local/bin/whatweb ]; then
        SKIPPED_PACKAGES+=("whatweb"); ((TOTAL_SKIPPED++)); log INFO "Already installed: whatweb"; return 0
    fi
    batch_install "WhatWeb deps (Ruby)" ruby
    local tag t
    tag=$(gh_latest_tag urbanadventurer/WhatWeb v0.6.4)
    log INFO "Installing WhatWeb ${tag#v} (Ruby, from source)..."
    t=$(mktemp -d)
    if command -v gem &>/dev/null \
        && gem install --no-document ipaddr addressable &>/dev/null \
        && curl -fsSL --retry 3 -o "$t/whatweb.tar.gz" "https://github.com/urbanadventurer/WhatWeb/archive/refs/tags/$tag.tar.gz" 2>/dev/null \
        && tar -xzf "$t/whatweb.tar.gz" -C "$t"; then
        rm -rf /usr/local/share/whatweb
        mv "$t/WhatWeb-${tag#v}" /usr/local/share/whatweb
        ln -sf /usr/local/share/whatweb/whatweb /usr/local/bin/whatweb
        [ -f /usr/local/share/whatweb/whatweb.1 ] \
            && install -Dm644 /usr/local/share/whatweb/whatweb.1 /usr/local/share/man/man1/whatweb.1
        if /usr/local/bin/whatweb --version &>/dev/null; then
            rm -rf "$t"
            INSTALLED_PACKAGES+=("whatweb"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: WhatWeb ${tag#v} (/usr/local/bin/whatweb)"; return 0
        fi
    fi
    rm -rf "$t"
    FAILED_PACKAGES+=("whatweb"); ((TOTAL_FAILED++)); log WARNING "WhatWeb install failed"; return 0
}

# KeePassXC - OpenMandriva's package works on Rock but not on current
# Rolling (needs libbotan-2.so.19, which Rolling no longer ships); fall back
# to KeePassXC's own verified Flathub build.
install_keepassxc() {
    safe_install keepassxc
    if ! is_installed keepassxc; then
        log INFO "keepassxc package not installable here - using KeePassXC's Flathub build"
        flatpak_install_flathub org.keepassxc.KeePassXC "KeePassXC"
        flatpak info org.keepassxc.KeePassXC &>/dev/null && clear_failed keepassxc
    fi
}

install_security_tools() {
    # nmap ships ncat itself here (no separate nmap-ncat package)
    batch_install "Security - Network" \
        nmap masscan bind-utils
    om_skip_unavailable hping3 "OpenMandriva's package is uninstallable (needs libtcl8.6)"

    batch_install "Security - Web" \
        nikto sqlmap wfuzz
    install_gobuster_release
    install_whatweb_source

    batch_install "Security - Cracking & Wireless" \
        john hashcat hydra aircrack-ng macchanger

    batch_install "Security - Forensics & RE" \
        binwalk sleuthkit perl-Image-ExifTool
    install_radare2_source
    install_yara_source
    om_skip_unavailable steghide "not packaged for OpenMandriva"

    # clamav ships freshclam itself here (no separate clamav-freshclam)
    batch_install "Security - Hardening" \
        lynis chkrootkit rkhunter clamav fail2ban aide

    # firewalld (Fedora's default firewall manager) replaces ufw/gufw -
    # there's no Fedora equivalent of Ubuntu's ufw/gufw pairing, firewalld
    # IS the native answer here, with firewall-config as its GUI.
    batch_install "Security - Firewall & Privacy" \
        firewalld firewall-config openvpn wireguard-tools proxychains-ng torsocks
    install_keepassxc
    om_skip_unavailable ettercap "not packaged for OpenMandriva"
}

install_security_defensive() {
    batch_install "Defensive - Hardening & Integrity" \
        lynis chkrootkit rkhunter aide audit

    batch_install "Defensive - Anti-Malware" \
        clamav

    batch_install "Defensive - IDS/IPS" \
        fail2ban suricata

    batch_install "Defensive - Firewall, VPN & Credentials" \
        firewalld firewall-config openvpn wireguard-tools
    install_keepassxc
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
    batch_install "Wine" wine winetricks zenity-gtk
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
# OpenMandriva ships Flatpak but, unlike Fedora, does NOT pre-configure the
# Flathub remote - it's added on demand below. Flathub is the primary source
# here for everything researched to have no reliable OpenMandriva-native RPM
# source (browsers, several communication apps, a handful of dev/AI picks)
# - the repo-then-Flathub shape the Fedora script uses inverted for the
# apps whose vendor repos only build Fedora RPMs.
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
# Every browser here has an official yum repo, but none of them list
# OpenMandriva as a supported build target (Brave/Vivaldi/Edge/Chrome/
# LibreWolf build Fedora and some openSUSE RPMs only) - pulling them via dnf
# here means Fedora-built RPMs whose dependency resolution isn't guaranteed
# on OpenMandriva. Flathub is the first choice on this distro, not a
# fallback: all of these have official Flathub listings (Floorp and Zen
# included, as on Fedora - their vendors' own documented Linux path).
install_browsers() {
    install_brave
    install_vivaldi
    install_edge
    install_chrome
    install_librewolf
    install_zen
    install_floorp
}

install_brave()     { flatpak_install_flathub com.brave.Browser "Brave"; }
install_vivaldi()   { flatpak_install_flathub com.vivaldi.Vivaldi "Vivaldi"; }
install_edge()      { flatpak_install_flathub com.microsoft.Edge "Microsoft Edge"; }
install_chrome()    { flatpak_install_flathub com.google.Chrome "Google Chrome"; }
install_librewolf() { flatpak_install_flathub io.gitlab.librewolf-community "LibreWolf"; }

# Zen Browser and Floorp: confirmed no vendor rpm exists for either -
# Flathub is the vendors' own documented Linux path, not a compromise.
install_zen()    { flatpak_install_flathub app.zen_browser.zen "Zen"; }
install_floorp() { flatpak_install_flathub one.ablaze.floorp "Floorp"; }

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

# Microsoft Teams via teams-for-linux - its rpm repo
# (repo.teamsforlinux.de) builds Fedora RPMs only, so Flathub's official
# listing is the path here (same community project the sibling scripts use).
install_teams() { flatpak_install_flathub com.github.IsmaelMartinez.teams_for_linux "Teams"; }

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

# Vendor rpm fetched straight from its own download URL and installed as a
# local file - dnf still resolves its dependencies from OpenMandriva's own
# repos, but nothing depends on the vendor's yum repo metadata (signed-repo
# key import, $basearch layout) working on this distro.
# Drop an earlier "failed" entry once a fallback has installed the package
# after all, so the summary doesn't list it as both failed and installed.
clear_failed() {  # <name as recorded in FAILED_PACKAGES>
    local i kept=()
    for i in "${FAILED_PACKAGES[@]}"; do
        if [ "$i" = "$1" ]; then ((TOTAL_FAILED--)); else kept+=("$i"); fi
    done
    FAILED_PACKAGES=("${kept[@]}")
}

install_vendor_rpm_direct() {  # <package name> <rpm url> <label>
    local pkg="$1" url="$2" label="$3" t
    log INFO "Installing $label from its official rpm ($url)..."
    t=$(mktemp -d)
    if curl -fsSL --retry 3 -o "$t/$pkg.rpm" "$url" 2>/dev/null && [ -s "$t/$pkg.rpm" ] \
        && dnf install -y "$t/$pkg.rpm" 2>/dev/null; then
        rm -rf "$t"
        clear_failed "$pkg"
        INSTALLED_PACKAGES+=("$pkg"); ((TOTAL_INSTALLED++)); log SUCCESS "Installed: $label"; return 0
    fi
    rm -rf "$t"
    log WARNING "$label direct rpm install failed"; return 1
}

install_slack() {
    if is_installed slack || flatpak info com.slack.Slack &>/dev/null; then
        SKIPPED_PACKAGES+=("slack"); ((TOTAL_SKIPPED++)); log INFO "Already installed: slack"
        disable_stale_slack_repo
        return 0
    fi
    # Slack's own rpm can never install here: it requires the Fedora package
    # NAMES libXScrnSaver and libappindicator-gtk3, which nothing on
    # OpenMandriva provides (the libraries themselves exist, as
    # lib64xscrnsaver1 / lib64appindicator3_1, but dnf matches the name).
    # Flathub's Slack package is the working path - and skipping the rpm
    # also skips its postinst hook re-adding the stale packagecloud repo.
    flatpak_install_flathub com.slack.Slack "Slack"
    disable_stale_slack_repo
}

# Remmina ships in OpenMandriva's own repos - no PPA equivalent needed the
# way Ubuntu needs remmina-ppa-team for a modern build.
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
    log INFO "Installing TeamViewer (official yum repo, unsigned - see om_relax_vendor_repos)..."
    cat > /etc/yum.repos.d/teamviewer.repo <<'EOF'
[teamviewer]
name=TeamViewer
baseurl=https://linux.teamviewer.com/yum/stable/main/binary-$basearch/
enabled=1
EOF
    om_relax_vendor_repos
    pm_update
    safe_install teamviewer
    # OpenMandriva note: if the repo route doesn't take (its signed-metadata
    # key import is the fragile part), install TeamViewer's own rpm directly -
    # every dependency it has resolves from OpenMandriva's repos. There is no
    # Flathub TeamViewer package to fall back to.
    if ! is_installed teamviewer; then
        install_vendor_rpm_direct teamviewer \
            https://download.teamviewer.com/download/linux/teamviewer.x86_64.rpm "TeamViewer" \
            || { FAILED_PACKAGES+=("teamviewer"); ((TOTAL_FAILED++)); }
    fi
    om_relax_vendor_repos  # the rpm ships its own teamviewer.repo
}

# 1Password - real vendor yum repo, Fedora explicitly supported. Simpler than
# the Ubuntu apt path: rpm has no debsig-verify-style extra policy step, just
# the repo + gpgkey.
install_1password() {
    if is_installed 1password; then
        SKIPPED_PACKAGES+=("1password"); ((TOTAL_SKIPPED++)); log INFO "Already installed: 1password"; return 0
    fi
    log INFO "Installing 1Password (official yum repo, unsigned - see om_relax_vendor_repos)..."
    cat > /etc/yum.repos.d/1password.repo <<'EOF'
[1password]
name=1Password
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
EOF
    om_relax_vendor_repos
    pm_update
    safe_install 1password
    # Same fallback chain as TeamViewer: the official rpm directly (all its
    # dependencies resolve on OpenMandriva), then Flathub's 1Password
    # package (verified, published by 1Password itself).
    if ! is_installed 1password; then
        install_vendor_rpm_direct 1password \
            https://downloads.1password.com/linux/rpm/stable/x86_64/1password-latest.rpm "1Password" \
            || flatpak_install_flathub com.onepassword.OnePassword "1Password"
        flatpak info com.onepassword.OnePassword &>/dev/null && clear_failed 1password
    fi
    om_relax_vendor_repos  # the rpm's install script writes its own 1password.repo
}

# ========== MENU SYSTEM ==========
# Consolidation note: same shape as the Fedora script - one "Creative
# Suite" category with the Full/Graphics/Video/Audio/Photography/Publishing
# sub-menu (OpenMandriva has no per-domain metapackages either). "Zoom" is
# dropped per the Fedora port's explicit precedent. "Drivers" keeps NVIDIA
# only - the Fedora port's Terra and DisplayLink entries have no OpenMandriva
# equivalent (see header note).

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
    ui_header "OPENMANDRIVA ${OM_VERSION:-Lx}  ·  POST-INSTALL" "dnf5 · restricted + non-free repos · Flathub"
    echo
    ui_section "Creative & Drivers"
    ui_cell  1 "Creative Suite";     ui_cell 28 "Drivers"; echo
    ui_cell 14 "Gaming";             ui_cell 25 "Desktop Apps";          echo
    ui_cell 29 "Snapshots & Backup"; ui_cell 30 "Peripherals"; echo
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
    ui_header "DRIVERS"
    echo
    ui_item 1 "NVIDIA Driver (nvidia + nvidia-kmod-open-desktop, non-free repo)"
    echo
    ui_item 0 "Back to Main Menu"
    echo
    ui_rule
    printf "  ${MAUVE}${BOLD}❯${NC} ${LAVENDER}Choose ${DIM}[0-1]${NC}${LAVENDER}: ${NC}"
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
    ui_header "PERIPHERALS" "Logitech (Solaar HID++) · Elgato Wave:3 audio"
    echo
    ui_item 1 "Install Solaar (peripheral manager)"
    ui_item 2 "Fix slow scroll wheel (MX Anywhere 3S - enable Scroll Wheel Resolution)"
    ui_item 3 "Pin Elgato Wave:3 to pro-audio profile (WirePlumber)"
    echo
    ui_item 0 "Back to Main Menu"
    echo
    ui_rule
    printf "  ${MAUVE}${BOLD}❯${NC} ${LAVENDER}Choose ${DIM}[0-3]${NC}${LAVENDER}: ${NC}"
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
                    3) fix_elgato_wave3_profile ;;
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
