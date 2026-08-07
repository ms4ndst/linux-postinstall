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
        if apt-get install -y "$pkg" 2>/dev/null; then
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
    batch_install "base" software-properties-common apt-transport-https ca-certificates curl wget git gnupg lsb-release ubuntu-keyring whiptail debconf-utils dialog
}

display_summary() {
    clear; echo "=== INSTALLATION SUMMARY ==="; echo "Total: $((TOTAL_INSTALLED+TOTAL_FAILED+TOTAL_SKIPPED))"; echo "Installed: $TOTAL_INSTALLED"; echo "Skipped: $TOTAL_SKIPPED"; echo "Failed: $TOTAL_FAILED"; echo
    [ ${#FAILED_PACKAGES[@]} -gt 0 ] && { echo "${RED}Failed:${NC}"; for p in "${FAILED_PACKAGES[@]}"; do echo "  - $p"; done; echo; }
    [ ${#SKIPPED_PACKAGES[@]} -gt 0 ] && { echo "${YELLOW}Skipped:${NC}"; printf "  - %s\n" "${SKIPPED_PACKAGES[@]}" | head -n 10; [ ${#SKIPPED_PACKAGES[@]} -gt 10 ] && echo "  ...and more"; echo; }
    echo "==================================="
}

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

# ========== UBUNTU STUDIO ==========
install_ubuntu_studio_full() { batch_install "Ubuntu Studio" ubuntu-studio; }
install_ubuntu_studio_graphics() { batch_install "Ubuntu Studio Graphics" ubuntu-studio-graphics; }
install_ubuntu_studio_video() { batch_install "Ubuntu Studio Video" ubuntu-studio-video; }
install_ubuntu_studio_audio() { batch_install "Ubuntu Studio Audio" ubuntu-studio-audio; }
install_ubuntu_studio_photography() { batch_install "Ubuntu Studio Photography" ubuntu-studio-photography; }
install_ubuntu_studio_publishing() { batch_install "Ubuntu Studio Publishing" ubuntu-studio-publishing; }

# ========== GRAPHICS ==========
install_graphics() {
    batch_install "Graphics" \
        gimp inkscape krita darktable rawtherapee shotwell nomacs pinta blender \
        imagemagick graphicsmagick optipng jpegoptim pngquant webp-tools
}

# ========== VIDEO ==========
install_video() {
    batch_install "Video" \
        openshot kdenlive shotcut pitivi handbrake ffmpeg \
        mkvtoolnix mkvtoolnix-gui mpv vlc obs-studio \
        gstreamer1.0-libav gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-tools
}

# ========== AUDIO ==========
install_audio() {
    batch_install "Audio" \
        audacity ardour lmms musescore hydrogen \
        qjackctl jackd2 pulseaudio-module-jack ladspa-sdk calf-plugins \
        soundconverter easytag flac lame oggenc opus-tools vorbis-tools wavpack sox libsox-fmt-all
}

# ========== CODE EDITORS ==========
install_code_editors() {
    batch_install "Code Editors" vim neovim emacs nano geany gedit kate
    install_vscode; install_sublime_text
}

install_vscode() {
    if command -v code &>/dev/null; then log INFO "VS Code already installed"; return 0; fi
    log INFO "Installing VS Code..."
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/microsoft.gpg 2>/dev/null
    install -D -m 644 /tmp/microsoft.gpg /usr/share/keyrings/microsoft.gpg 2>/dev/null
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/vscode stable main" > /etc/apt/sources.list.d/vscode.list
    apt-get update -qq 2>/dev/null
    safe_install code
    rm -f /tmp/microsoft.gpg /etc/apt/sources.list.d/vscode.list
}

install_sublime_text() {
    if command -v sublime_text &>/dev/null; then log INFO "Sublime Text already installed"; return 0; fi
    log INFO "Installing Sublime Text..."
    wget -qO- https://download.sublimetext.com/sublimehq-pub.gpg | gpg --dearmor | tee /usr/share/keyrings/sublime-text.gpg >/dev/null 2>&1
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/sublime-text.gpg] https://download.sublimetext.com/ apt/stable/" > /etc/apt/sources.list.d/sublime-text.list
    apt-get update -qq 2>/dev/null
    safe_install sublime-text
    rm -f /usr/share/keyrings/sublime-text.gpg /etc/apt/sources.list.d/sublime-text.list
}

# ========== PYTHON ==========
install_python() {
    batch_install "Python" python3 python3-dev python3-venv python3-pip python-is-python3 ipython3
}

# ========== WEB DEVELOPMENT ==========
install_web_dev() {
    install_nodejs_repo
    batch_install "Web Dev" nginx apache2 php php-cli php-fpm composer redis-server memcached sqlite3 sqlitebrowser
    safe_install ruby ruby-dev
    install_npm_packages
}

install_nodejs_repo() {
    if command -v node &>/dev/null; then log INFO "Node.js already installed"; return 0; fi
    log INFO "Adding NodeSource repository..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>/dev/null && apt-get update -qq 2>/dev/null
}

install_npm_packages() {
    log INFO "Installing npm packages..."
    local pkgs=(npm-check-updates nodemon pm2 webpack webpack-cli eslint prettier)
    for p in "${pkgs[@]}"; do
        npm list -g "$p" &>/dev/null || npm install -g "$p" 2>/dev/null && log SUCCESS "Installed: $p" || log WARNING "Failed: $p"
    done
}

# ========== JAVA ==========
install_java() {
    batch_install "Java" default-jdk default-jre gradle maven ant junit4 testng hamcrest mockito
    local jh=$(update-alternatives --list java 2>/dev/null | head -n 1 | xargs dirname | xargs dirname)
    [ -n "$jh" ] && echo "export JAVA_HOME=$jh" >> /etc/environment && echo 'export PATH="$PATH:$JAVA_HOME/bin"' >> /etc/environment
}

# ========== C/C++ ==========
install_c_cpp() {
    batch_install "C/C++" \
        build-essential gcc g++ gfortran clang cmake make \
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
install_nodejs_dev() { install_nodejs_repo; safe_install nodejs npm; }

# ========== PHP ==========
install_php() {
    if ! grep -q ondrej-php /etc/apt/sources.list.d/* 2>/dev/null; then
        log INFO "Adding Ondrej PHP repository..."
        add-apt-repository -y ppa:ondrej/php 2>/dev/null || true
        apt-get update -qq 2>/dev/null || true
    fi
    batch_install "PHP" \
        php php-cli php-fpm php-dev php-pear \
        php-mysql php-pgsql php-sqlite3 php-gd php-curl php-mbstring composer
}

# ========== RUBY ==========
install_ruby() { batch_install "Ruby" ruby ruby-dev ruby-bundler; }

# ========== DATABASES ==========
install_databases() {
    batch_install "Databases" \
        mysql-server mysql-client postgresql postgresql-contrib \
        sqlite3 sqlitebrowser redis-server redis-tools memcached
}

# ========== CONTAINERS ==========
install_containers() {
    batch_install "Containers" docker.io docker-compose podman lxc lxd
    if command -v docker &>/dev/null; then
        usermod -aG docker "$SUDO_USER" 2>/dev/null || true
        systemctl enable docker 2>/dev/null || true
        systemctl start docker 2>/dev/null || true
        log INFO "Docker configured"
    fi
}

# ========== GAMING ==========
install_gaming() {
    batch_install "Gaming" steam lutris wine winetricks obs-studio mpv vlc
    dpkg --add-architecture i386 2>/dev/null || true
    apt-get update -qq 2>/dev/null || true
    safe_install libgl1-mesa-glx:i386
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
        tmux screen byobu zsh fish fzf ripgrep tree ncdu rsync unzip
}

# ========== GENERAL DEV TOOLS ==========
install_dev_tools() {
    batch_install "Dev Tools" \
        git tig subversion make cmake \
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
    if command -v mistral-vibe &>/dev/null; then log INFO "Mistral Vibe already installed"; return 0; fi
    log INFO "Installing Mistral AI Vibe..."
    local t=$(mktemp -d) a=$(dpkg --print-architecture)
    for u in "https://github.com/mistralai/vibe/releases/latest/download/vibe_${a}.deb" "https://github.com/mistralai/vibe/releases/latest/download/vibe-${a}.deb"; do
        if curl -L -f --retry 2 -o "$t/vibe.deb" "$u" 2>/dev/null || wget -q --tries=2 -O "$t/vibe.deb" "$u" 2>/dev/null; then
            dpkg -i "$t/vibe.deb" 2>/dev/null || { apt-get install -f -y 2>/dev/null; dpkg -i "$t/vibe.deb" 2>/dev/null; }
            rm -rf "$t"; log SUCCESS "Mistral Vibe installed"; return 0
        fi
    done
    rm -rf "$t"; log WARNING "Download from: https://vibe.mistral.ai/"; return 0
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
    batch_install "Icon Sets" papirus-icon-theme tela-icon-theme numix-icon-theme adwaita-icon-theme-full yaru-icon-theme
}

install_themes() {
    batch_install "Themes" arc-theme yaru-theme yaru-theme-gnome adwaita-dark
}

install_cursor_themes() {
    batch_install "Cursor Themes" papirus-cursor-theme tela-cursor-theme numix-cursor-theme dmz-cursor-theme adwaita-cursor-theme
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
    if su - "$SUDO_USER" -c "git clone --depth 1 https://github.com/christitustech/mybash $MD" 2>&1; then
        if su - "$SUDO_USER" -c "cd $MD && bash setup.sh" 2>&1; then
            log SUCCESS "mybash installed. User: source ~/.bashrc"; return 0
        else
            log WARNING "setup.sh failed, manual copy..."
            for f in bash_profile bashrc bash_aliases bash_functions bash_colors git-prompt.sh git-completion.bash; do
                [ -f "$MD/$f" ] && cp "$MD/$f" "$UH/.$f" 2>/dev/null && chown "$SUDO_USER:$SUDO_USER" "$UH/.$f" 2>/dev/null
            done
            if [ -f "$BR" ]; then
                if ! grep -q "mybash" "$BR"; then
                    echo "" >> "$BR"
                    echo '# Chris Titus mybash' >> "$BR"
                    echo 'if [ -f "$HOME/.bash_profile" ]; then . "$HOME/.bash_profile"; fi' >> "$BR"
                    chown "$SUDO_USER:$SUDO_USER" "$BR"
                fi
            else
                echo '# Chris Titus mybash' > "$BR"
                echo 'if [ -f "$HOME/.bash_profile" ]; then . "$HOME/.bash_profile"; fi' >> "$BR"
                chown "$SUDO_USER:$SUDO_USER" "$BR"
            fi
            log SUCCESS "mybash installed via copy. User: source ~/.bashrc"; return 0
        fi
    else
        log ERROR "Clone failed"; return 1
    fi
}

install_gui_tools() {
    batch_install "GUI Tools" gnome-tweaks gnome-shell-extensions gnome-shell-extension-manager gnome-themes-extra nautilus eog evince file-roller gedit simple-scan cheese gnome-screenshot gnome-system-monitor
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
    echo "  A.  Install ALL Development Tools"
    echo "  B.  Install ALL Media Tools"
    echo "  C.  Install EVERYTHING"
    echo ""
    echo "  S.  Show Installation Summary"
    echo "  0.  Exit"
    echo ""
    echo "======================================"
    echo -n "  Enter your choice [0-22, A-C, S]: "
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
                    1) install_ubuntu_studio_full ;;
                    2) install_ubuntu_studio_graphics ;;
                    3) install_ubuntu_studio_video ;;
                    4) install_ubuntu_studio_audio ;;
                    5) install_ubuntu_studio_photography ;;
                    6) install_ubuntu_studio_publishing ;;
                    *) log ERROR "Invalid choice"; sleep 2 ;;
                esac
                ;;
            2) install_graphics ;;
            3) install_video ;;
            4) install_audio ;;
            5) install_code_editors ;;
            6) install_python ;;
            7) install_web_dev ;;
            8) install_java ;;
            9) install_c_cpp ;;
            10) install_go ;;
            11) install_rust ;;
            12) install_nodejs_dev ;;
            13) install_php ;;
            14) install_ruby ;;
            15) install_databases ;;
            16) install_containers ;;
            17) install_gaming ;;
            18) install_office ;;
            19) install_system_utils ;;
            20) install_dev_tools ;;
            21) install_ai_tools ;;
            22) install_gui_tweaks ;;
            A|a)
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
                ;;
            B|b)
                log INFO "Installing ALL Media Tools..."
                install_ubuntu_studio_full
                install_graphics
                install_video
                install_audio
                ;;
            C|c)
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