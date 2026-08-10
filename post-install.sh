#!/bin/bash
# Ubuntu 26.10 Post-Install Script v2
# Menu-driven installer with error handling and VERIFIED packages only
# Run as: chmod +x post-install.sh && sudo ./post-install.sh

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

declare -a INSTALLED_PACKAGES FAILED_PACKAGES SKIPPED_PACKAGES
TOTAL_INSTALLED=0; TOTAL_FAILED=0; TOTAL_SKIPPED=0

log() {
    local l="$1" m="$2"
    case "$l" in
        ERROR) echo -e "${RED}[ERROR]${NC} $m" >&2;;
        WARNING) echo -e "${YELLOW}[WARNING]${NC} $m";;
        INFO) echo -e "${BLUE}[INFO]${NC} $m";;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $m";;
        *) echo -e "$m";;
    esac
}

check_root() {
    [ "$(id -u)" -ne 0 ] && { log ERROR "This script must be run as root. Use sudo."; exit 1; }
}

check_version() {
    local v="26.10"
    local uv=$(lsb_release -rs 2>/dev/null || grep -oP '(?<=^VERSION_ID=).+' /etc/os-release | tr -d '"')
    [[ ! "$uv" == "$v" ]] && { log WARNING "Designed for Ubuntu $v, detected: $uv"; read -p "Continue? [y/N] " -n 1 -r; echo; [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1; }
}

is_installed() { dpkg -l "$1" 2>/dev/null | grep -q "^ii"; }
package_exists() { apt-cache search "^${1}$" 2>/dev/null | grep -q "${1}"; }

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
        # Install package, ignore install-info errors (common in Ubuntu 26.10)
        if apt-get install -y "$pkg" 2>/dev/null || is_installed "$pkg"; then
            INSTALLED_PACKAGES+=("$pkg"); ((TOTAL_INSTALLED++))
            log SUCCESS "Installed: $pkg"
        else
            FAILED_PACKAGES+=("$pkg"); ((TOTAL_FAILED++))
            log ERROR "Failed: $pkg"
        fi
    done
}

batch_install() {
    local cat="$1"; shift; local pkgs=("$@")
    local s=$TOTAL_INSTALLED f=$TOTAL_FAILED k=$TOTAL_SKIPPED
    log INFO "Installing $cat..."
    safe_install "${pkgs[@]}"
    log INFO "$cat: $((TOTAL_INSTALLED-s)) installed, $((TOTAL_FAILED-f)) failed, $((TOTAL_SKIPPED-k)) skipped"
}

update_packages() {
    log INFO "Updating package lists..."
    if ! apt-get update -qq 2>/dev/null; then
        log ERROR "Failed to update. Check internet."
        read -p "Retry? [y/N] " -n 1 -r; echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then update_packages; else log ERROR "Cannot proceed."; exit 1; fi
    fi
    log SUCCESS "Updated."
}

install_base() {
    log INFO "Installing base utilities..."
    batch_install "base" software-properties-common apt-transport-https ca-certificates curl wget git gnupg lsb-release ubuntu-keyring whiptail debconf-utils dialog alacarte dconf-cli
    
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
        # Snap-installed apps (dbeaver-ce, intellij-idea-community) ship their
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
    clear; echo "=== INSTALLATION SUMMARY ==="; echo "Total: $((TOTAL_INSTALLED+TOTAL_FAILED+TOTAL_SKIPPED))"; echo "Installed: $TOTAL_INSTALLED"; echo "Skipped: $TOTAL_SKIPPED"; echo "Failed: $TOTAL_FAILED"; echo
    [ ${#FAILED_PACKAGES[@]} -gt 0 ] && { echo -e "${RED}Failed:${NC}"; for p in "${FAILED_PACKAGES[@]}"; do echo "  - $p"; done; echo; }
    [ ${#SKIPPED_PACKAGES[@]} -gt 0 ] && { echo -e "${YELLOW}Skipped:${NC}"; printf "  - %s\n" "${SKIPPED_PACKAGES[@]}" | head -n 10; [ ${#SKIPPED_PACKAGES[@]} -gt 10 ] && echo "  ...and more"; echo; }
    echo "==================================="
}

# Save installation log
save_log() {
    local f="/var/log/ubuntu_post_install_$(date +%Y%m%d_%H%M%S).log"
    {
        echo "=== Log: $(date) ==="; echo "User: $(whoami)"
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
        imagemagick graphicsmagick optipng jpegoptim pngquant webp-tools
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
    # NOT included: ttf-mscorefonts-installer (pulled in by the
    # "ubuntu-restricted-extras" meta-package some guides recommend) - it's
    # fonts, not a media codec, and it gates on an interactive EULA
    # (msttcorefonts/accepted-mscorefonts-eula, defaults to declined) that
    # would either silently no-op or need its own preseed decision. Say the
    # word if you want that added too.
    batch_install "Media Codecs & Plugins" \
        gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-vaapi \
        libavcodec-extra unrar
    install_libdvdcss
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
    if apt-get install -y libdvd-pkg 2>/dev/null; then
        INSTALLED_PACKAGES+=("libdvd-pkg"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: libdvd-pkg (encrypted DVD playback support)"
    else
        FAILED_PACKAGES+=("libdvd-pkg"); ((TOTAL_FAILED++))
        log WARNING "libdvd-pkg failed - encrypted DVD playback won't work. Retry manually: sudo dpkg-reconfigure libdvd-pkg"
    fi
}

# ========== AUDIO ==========
install_audio() {
    batch_install "Audio" \
        audacity ardour lmms musescore hydrogen \
        qjackctl jackd2 pulseaudio-module-jack ladspa-sdk calf-plugins \
        soundconverter easytag flac lame oggenc opus-tools vorbis-tools wavpack sox libsox-fmt-all \
        pavucontrol
}

# ========== CODE EDITORS ==========
install_code_editors() {
    batch_install "Code Editors" vim neovim emacs nano geany gedit kate
    install_vscode; install_sublime_text
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
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/microsoft.gpg 2>/dev/null
    install -D -m 644 /tmp/microsoft.gpg /usr/share/keyrings/microsoft.gpg 2>/dev/null
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/vscode stable main" > /etc/apt/sources.list.d/vscode.list
    apt-get update -qq 2>/dev/null
    safe_install code
    rm -f /tmp/microsoft.gpg /etc/apt/sources.list.d/vscode.list
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
    rm -f /usr/share/keyrings/sublime-text.gpg /etc/apt/sources.list.d/sublime-text.list
}

# ========== PYTHON ==========
install_python() {
    batch_install "Python" python3 python3-dev python3-venv python3-pip python-is-python3 ipython3 pipx
}

# ========== WEB DEVELOPMENT ==========
install_web_dev() {
    install_nodejs_full
    
    # Install nginx first
    batch_install "Web Server - Nginx" nginx
    
    # Install Apache2 but prevent it from starting (port 80 conflict with nginx)
    # Apache2 will be installed but not started - user must manually configure
    log INFO "Installing Apache2 (will not start automatically due to port 80 conflict with nginx)..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends apache2 2>/dev/null
    if is_installed apache2; then
        INSTALLED_PACKAGES+=("apache2"); ((TOTAL_INSTALLED++))
        log SUCCESS "Installed: apache2 (not started - port 80 used by nginx)"
        # Stop apache2 if it somehow started
        systemctl stop apache2 2>/dev/null || true
    else
        FAILED_PACKAGES+=("apache2"); ((TOTAL_FAILED++))
        log ERROR "Failed: apache2"
    fi
    
    # PHP baseline kept here on purpose: without a language runtime, "Web
    # Development" would just be a bare nginx/apache/DB stack with nothing to
    # serve. "PHP Development" layers on deeper PHP-specific tooling on top.
    batch_install "Web Dev" php php-cli php-fpm composer
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
    [ -n "$jh" ] && echo "export JAVA_HOME=$jh" >> /etc/environment && echo 'export PATH="$PATH:$JAVA_HOME/bin"' >> /etc/environment
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
        local t=$(mktemp -d)
        if curl -L -o "$t/go.tar.gz" https://go.dev/dl/go1.22.5.linux-amd64.tar.gz 2>/dev/null; then
            rm -rf /usr/local/go && tar -C /usr/local -xzf "$t/go.tar.gz" 2>/dev/null
            echo 'export PATH="$PATH:/usr/local/go/bin"' >> /etc/environment
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
    if ! command -v rustup &>/dev/null; then
        log INFO "Installing rustup..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y 2>/dev/null
        if [ -f "$HOME/.cargo/env" ]; then
            source "$HOME/.cargo/env"
            rustup default stable 2>/dev/null
            rustup component add rust-src 2>/dev/null
            log SUCCESS "Rust installed"
        else
            log WARNING "rustup installation may have failed"
        fi
    fi
}

# ========== NODE.JS ==========
install_nodejs_dev() { install_nodejs_full; }

# ========== PHP ==========
install_php() {
    # Using default Ubuntu PHP packages only (Ondrej PPA not available for 26.10 yet)
    batch_install "PHP" \
        php php-cli php-fpm php-dev php-pear \
        php-mysql php-pgsql php-sqlite3 php-gd php-curl php-mbstring \
        php-xml php-zip composer
}

# ========== RUBY ==========
install_ruby() { batch_install "Ruby" ruby ruby-dev ruby-bundler; }

# ========== DATABASES ==========
install_databases() {
    batch_install "Databases" \
        mysql-server mysql-client postgresql \
        sqlite3 sqlitebrowser redis-server redis-tools memcached
    # sqlitebrowser above is the only DB GUI in the Ubuntu archive - no
    # MySQL/Postgres GUI exists there at all (verified: dbeaver-ce,
    # mysql-workbench, pgadmin4 all return nothing from apt-cache policy).
    # DBeaver covers MySQL/Postgres/SQLite in one tool - snap is the only real
    # distribution channel for it.
    safe_snap_install dbeaver-ce --classic
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
    safe_install libgl1-mesa-glx:i386
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
    batch_install "Wine Environment" \
        wine \
        winetricks
    
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
        # Set up Wine prefix
        if [ ! -d "$HOME/.wine" ]; then
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
}

# ========== AI TOOLS ==========
install_ai_tools() {
    log INFO "Installing AI Tools..."
    install_ollama
    install_mistral_vibe
    install_claude_code
    install_cursor
}

install_ollama() {
    if command -v ollama &>/dev/null; then log INFO "Ollama already installed"; return 0; fi
    log INFO "Installing Ollama..."
    if curl -fsSL https://ollama.com/install.sh | sh 2>/dev/null; then
        log SUCCESS "Ollama installed"
        return 0
    else
        log ERROR "Ollama install failed"
        return 1
    fi
}

install_mistral_vibe() {
    if command -v mistral-vibe &>/dev/null; then
        log INFO "Mistral Vibe already installed"
        return 0
    fi
    
    log INFO "Installing Mistral AI Vibe..."
    
    # Mistral Vibe is distributed as AppImage, not .deb
    # Official download: https://vibe.mistral.ai/
    local temp_dir=$(mktemp -d)
    local arch=$(uname -m)
    local vibe_url="https://github.com/mistralai/vibe/releases/latest/download/vibe-${arch}.AppImage"
    
    # Try to download AppImage
    if curl -L -f --retry 2 -o "$temp_dir/vibe.AppImage" "$vibe_url" 2>/dev/null; then
        chmod +x "$temp_dir/vibe.AppImage"
        mv "$temp_dir/vibe.AppImage" /usr/local/bin/mistral-vibe
        rm -rf "$temp_dir"
        log SUCCESS "Mistral Vibe installed to /usr/local/bin/mistral-vibe"
        return 0
    elif wget -q --tries=2 -O "$temp_dir/vibe.AppImage" "$vibe_url" 2>/dev/null; then
        chmod +x "$temp_dir/vibe.AppImage"
        mv "$temp_dir/vibe.AppImage" /usr/local/bin/mistral-vibe
        rm -rf "$temp_dir"
        log SUCCESS "Mistral Vibe installed to /usr/local/bin/mistral-vibe"
        return 0
    fi
    
    rm -rf "$temp_dir"
    log WARNING "Could not download Mistral Vibe AppImage"
    log INFO "Download manually from: https://vibe.mistral.ai/"
    return 0
}

install_claude_code() {
    if command -v claude &>/dev/null; then log INFO "Claude CLI already installed"; return 0; fi
    log INFO "Installing Claude CLI..."
    if command -v npm &>/dev/null && npm install -g claude 2>/dev/null; then
        log SUCCESS "Claude CLI installed"; return 0
    fi
    log WARNING "Install: npm install -g claude"; return 0
}

install_cursor() {
    if command -v cursor &>/dev/null; then log INFO "Cursor already installed"; return 0; fi
    log INFO "Installing Cursor..."
    local t=$(mktemp -d) a=$(dpkg --print-architecture)
    for u in "https://download.cursor.com/linux/deb/${a}/cursor_${a}.deb" "https://download.cursor.com/linux/deb/cursor.deb"; do
        if curl -L -f --retry 2 -o "$t/cursor.deb" "$u" 2>/dev/null || wget -q --tries=2 -O "$t/cursor.deb" "$u" 2>/dev/null; then
            dpkg -i "$t/cursor.deb" 2>/dev/null || { apt-get install -f -y 2>/dev/null; dpkg -i "$t/cursor.deb" 2>/dev/null; }
            rm -rf "$t"; log SUCCESS "Cursor installed"; return 0
        fi
    done
    rm -rf "$t"; log WARNING "Download from: https://www.cursor.com/"; return 0
}

# ========== GUI TWEAKS ==========
install_gui_tweaks() {
    log INFO "Installing GUI Tweaks..."
    install_icon_sets
    install_themes
    install_cursor_themes
    install_nerd_fonts
    install_chris_titus_mybash
    install_gui_tools
}

install_icon_sets() {
    # Add Papirus Team PPA for additional icon themes
    if ! grep -q papirus /etc/apt/sources.list.d/* 2>/dev/null; then
        add-apt-repository -y ppa:papirus/papirus 2>/dev/null || log WARNING "Papirus PPA not available"
        apt-get update -qq 2>/dev/null || true
    fi
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
    local ext="tar.xz" ecmd="tar -xf"
    if ! command -v tar &>/dev/null || ! tar --help 2>/dev/null | grep -q xz; then
        command -v unzip &>/dev/null && { ext="zip"; ecmd="unzip -qq -o"; } || safe_install tar xz-utils 2>/dev/null || true
    fi
    log INFO "Downloading popular Nerd Fonts (format: ${ext})..."
    for font in "${fonts[@]}"; do
        local af="$t/${font}.${ext}" ed="$t/${font}"
        mkdir -p "$ed"
        local d=0
        command -v curl &>/dev/null && curl -L -f --retry 3 -o "$af" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font}.${ext}" 2>/dev/null && d=1
        [ $d -eq 0 ] && command -v wget &>/dev/null && wget -q --tries=3 -O "$af" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font}.${ext}" 2>/dev/null && d=1
        [ $d -eq 0 ] && { log WARNING "Failed: $font"; ((f++)); continue; }
        if ! $ecmd "$af" -C "$ed" 2>/dev/null; then log WARNING "Extract failed: $font"; ((f++)); continue; fi
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

# ========== MENU SYSTEM ==========
show_main_menu() {
    clear
    echo "=== UBUNTU 26.10 POST-INSTALL ==="
    echo "  with Error Handling & Verified Packages"
    echo "======================================"
    echo ""
    echo "  MAIN MENU"
    echo ""
    echo "  1.  Ubuntu Studio (All Media)"
    echo "  2.  Graphics & Image Manipulation"
    echo "  3.  Video Creation & Editing"
    echo "  4.  Audio Production"
    echo "  5.  Code Editors"
    echo "  6.  Python Development"
    echo "  7.  Web Development"
    echo "  8.  Java Development"
    echo "  9.  C/C++ Development"
    echo " 10.  Go Development"
    echo " 11.  Rust Development"
    echo " 12.  Node.js Development"
    echo " 13.  PHP Development"
    echo " 14.  Ruby Development"
    echo " 15.  Database Tools"
    echo " 16.  Container & Virtualization"
    echo " 17.  Gaming"
    echo "  18.  Office & Productivity"
    echo " 19.  System Utilities"
    echo " 20.  General Development Tools"
    echo " 21.  AI Tools"
    echo " 22.  GUI Tweaks"
    echo ""
    echo "  23.  Windows Software Support"
    echo "  24.  Android Tools (adb, fastboot, scrcpy)"
    echo ""
    echo "  A.  Install ALL Development Tools"
    echo "  B.  Install ALL Media Tools"
    echo "  C.  Install EVERYTHING"
    echo ""
    echo "  S.  Show Installation Summary"
    echo "  0.  Exit"
    echo ""
    echo "======================================"
    echo -n "  Enter your choice [0-24, A-C, S]: "
}

show_ubuntu_studio_menu() {
    clear
    echo "=== UBUNTU STUDIO PACKAGES ==="
    echo "================================"
    echo ""
    echo "  1.  Ubuntu Studio (Full)"
    echo "  2.  Graphics"
    echo "  3.  Video"
    echo "  4.  Audio"
    echo "  5.  Photography"
    echo "  6.  Publishing"
    echo ""
    echo "  0.  Back to Main Menu"
    echo ""
    echo "================================"
    echo -n "  Enter your choice [0-6]: "
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

# ========== MAIN EXECUTION ==========
main() {
    check_root
    check_version
    update_packages
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
                read -p "Press [Enter] to continue..."
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
            A|a)
                reset_tracking
                log INFO "Installing ALL Development Tools..."
                install_code_editors
                install_python
                install_web_dev
                install_java
                install_c_cpp
                install_go
                install_rust
                install_nodejs_dev
                install_php
                install_ruby
                install_dev_tools
                install_ai_tools
                display_summary
                ;;
            B|b)
                reset_tracking
                log INFO "Installing ALL Media Tools..."
                install_ubuntu_studio_full
                install_graphics
                install_video
                install_audio
                display_summary
                ;;
            C|c)
                reset_tracking
                log INFO "Installing EVERYTHING..."
                install_ubuntu_studio_full
                install_graphics
                install_video
                install_audio
                install_code_editors
                install_python
                install_web_dev
                install_java
                install_c_cpp
                install_go
                install_rust
                install_nodejs_dev
                install_php
                install_ruby
                install_databases
                install_containers
                install_gaming
                install_office
                install_system_utils
                install_dev_tools
                install_ai_tools
                install_gui_tweaks
                install_windows_support
                install_android_tools
                display_summary
                ;;
            *)
                log ERROR "Invalid choice. Please try again."
                sleep 2
                ;;
        esac
        read -p "Press [Enter] to continue..."
    done
}

main