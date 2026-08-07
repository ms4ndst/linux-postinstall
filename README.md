# Ubuntu 26.10 Post-Install Script

> **Comprehensive, menu-driven post-installation script with verified packages, error handling, and installation checks**

---

## 📋 Table of Contents

- [🚀 Overview](#-overview)
- [✨ Features](#-features)
- [📥 Installation](#-installation)
- [🎯 Usage](#-usage)
- [📦 Package Categories](#-package-categories)
  - [Ubuntu Studio (Media)](#ubuntu-studio-media)
  - [Graphics &amp; Image Manipulation](#graphics--image-manipulation)
  - [Video Creation &amp; Editing](#video-creation--editing)
  - [Audio Production](#audio-production)
  - [Code Editors](#code-editors)
  - [Python Development](#python-development)
  - [Web Development](#web-development)
  - [Java Development](#java-development)
  - [C/C++ Development](#cc-development)
  - [Go Development](#go-development)
  - [Rust Development](#rust-development)
  - [Node.js Development](#nodejs-development)
  - [PHP Development](#php-development)
  - [Ruby Development](#ruby-development)
  - [Database Tools](#database-tools)
  - [Container &amp; Virtualization](#container--virtualization)
  - [Gaming](#gaming)
  - [Office &amp; Productivity](#office--productivity)
  - [System Utilities](#system-utilities)
  - [General Development Tools](#general-development-tools)
  - [AI Tools](#ai-tools)
  - [GUI Tweaks](#gui-tweaks)
- [🔧 Error Handling &amp; Installation Checks](#-error-handling--installation-checks)
- [📊 Installation Summary &amp; Logging](#-installation-summary--logging)
- [⚙️ Customization](#-customization)
- [🐛 Troubleshooting](#-troubleshooting)
- [📜 License](#-license)

---

## 🚀 Overview

This script automates the post-installation setup of **Ubuntu 26.10** by providing a menu-driven interface for installing software packages grouped by category. It is designed for developers, creatives, and power users who want to quickly set up a fully-featured development or media production environment.

**Key Design Principles:**

- ✅ **Verified Packages Only**: Only includes packages confirmed to exist in Ubuntu 26.10 repositories
- ✅ **Direct Downloads for Third-Party**: Non-repo tools (VS Code, Sublime, Ollama, etc.) use official installers
- ✅ **PPA Integration**: Automatically adds required PPAs (NodeSource, Ondrej PHP)
- ✅ **Robust Error Handling**: Gracefully handles failures without crashing

---

## ✨ Features

### Core Features


| Feature                   | Description                                                         |
| ------------------------- | ------------------------------------------------------------------- |
| **Interactive Menu**      | Easy-to-use text-based menu with 22+ categories                     |
| **Error Handling**        | Skips unavailable packages, continues installation                  |
| **Pre-Install Checks**    | Verifies if packages are already installed                          |
| **Package Verification**  | Checks if packages exist in repositories before attempting          |
| **Dependency Resolution** | Automatically resolves and installs dependencies                    |
| **Installation Tracking** | Tracks installed, skipped, and failed packages                      |
| **Summary Reporting**     | Shows detailed installation summary with "S" command                |
| **Log Saving**            | Saves complete logs to `/var/log/ubuntu_post_install_TIMESTAMP.log` |


### Statistics

- **Total Categories:** 22
- **Verified APT Packages:** 150+
- **Third-Party Tools:** 10+ (VS Code, Sublime, Ollama, Cursor, etc.)
- **Estimated Install Time:** 15-120 minutes (depending on selections)
- **Estimated Disk Space:** 5-30GB (depending on selections)

---

## 📥 Installation

### Prerequisites

- **Ubuntu 26.10** (recommended, but works on other versions with warning)
- **Root access** (script must be run with `sudo`)
- **Internet connection** (for downloading packages)
- **Minimum 10GB free disk space** (for full installation)

### Quick Start

```bash
# Make the script executable
chmod +x post-install.sh

# Run with sudo
sudo ./post-install.sh
```

---

## 🎯 Usage

### Running the Script

```bash
# Make executable (one-time)
chmod +x post-install.sh

# Run with sudo
sudo ./post-install.sh
```

### Menu Navigation

1. **Main Menu**: Shows all 22 available categories (0-22)
2. **Sub-Menus**: Ubuntu Studio has its own sub-menu (options 1-6)
3. **Bulk Options**:
  - `A` - Install ALL Development Tools
  - `B` - Install ALL Media Tools
  - `C` - Install EVERYTHING
  - `S` - Show Installation Summary
  - `0` - Exit

### Example Workflows

#### Install Development Environment

```bash
sudo ./post-install.sh
# Select: 5 (Code Editors)
# Select: 6 (Python Development)
# Select: 7 (Web Development)
# Press 0 to exit
```

#### Install Media Production Tools

```bash
sudo ./post-install.sh
# Select: 1 (Ubuntu Studio)
# Select: 2 (Graphics)
# Select: 3 (Video)
# Select: 4 (Audio)
# Press 0 to exit
```

#### Full System Setup

```bash
sudo ./post-install.sh
# Select: C (Install EVERYTHING)
# Wait for completion (1-2 hours)
```

---

## 📦 Package Categories

Below is a comprehensive breakdown of what each category installs. **All APT packages listed are verified to exist in Ubuntu 26.10 repositories.**

---

### Ubuntu Studio (Media)

Official Ubuntu Studio meta-packages for creative professionals.


| Option | Package                     | Description                          |
| ------ | --------------------------- | ------------------------------------ |
| 1      | `ubuntu-studio`             | Full Ubuntu Studio suite (all media) |
| 2      | `ubuntu-studio-graphics`    | Graphics applications                |
| 3      | `ubuntu-studio-video`       | Video production tools               |
| 4      | `ubuntu-studio-audio`       | Audio production tools               |
| 5      | `ubuntu-studio-photography` | Photography tools                    |
| 6      | `ubuntu-studio-publishing`  | Publishing tools                     |


**Includes:** GIMP, Inkscape, Krita, Blender, Ardour, Audacity, OpenShot, Kdenlive, and more.

---

### Graphics &amp; Image Manipulation

**All packages verified in Ubuntu 26.10 repos:**

**Raster Graphics:**

- `gimp` - GNU Image Manipulation Program
- `inkscape` - Vector graphics editor
- `krita` - Digital painting program
- `darktable` - RAW photo editor
- `rawtherapee` - RAW image processing
- `shotwell` - Photo manager
- `nomacs` - Image viewer
- `pinta` - Simple drawing program

**3D Modeling:**

- `blender` - 3D creation suite

**Utilities:**

- `imagemagick` - Image manipulation suite
- `graphicsmagick` - Image processing system
- `optipng` - PNG optimizer
- `jpegoptim` - JPEG optimizer
- `pngquant` - PNG quantizer
- `webp-tools` - WebP image tools

---

### Video Creation &amp; Editing

**All packages verified in Ubuntu 26.10 repos:**

**Editors:**

- `openshot` - Video editor
- `kdenlive` - Non-linear video editor
- `shotcut` - Video editor
- `pitivi` - Video editor

**Encoding &amp; Conversion:**

- `handbrake` - Video transcoder
- `ffmpeg` - Complete solution to record, convert and stream audio and video
- `mkvtoolnix` - Matroska tools
- `mkvtoolnix-gui` - GUI for MKVToolNix

**Players:**

- `mpv` - Video player
- `vlc` - Media player

**Recording:**

- `obs-studio` - Open Broadcaster Software

**GStreamer:**

- `gstreamer1.0-libav` - FFmpeg plugin for GStreamer
- `gstreamer1.0-plugins-bad` - GStreamer plugins from the "bad" set
- `gstreamer1.0-plugins-ugly` - GStreamer plugins from the "ugly" set
- `gstreamer1.0-tools` - GStreamer tools

---

### Audio Production

**All packages verified in Ubuntu 26.10 repos:**

**DAWs &amp; Editors:**

- `audacity` - Audio editor and recorder
- `ardour` - Digital audio workstation
- `lmms` - Linux MultiMedia Studio
- `musescore` - Music composition and notation
- `hydrogen` - Advanced drum machine

**JACK Audio:**

- `qjackctl` - JACK Audio Connection Kit control panel
- `jackd2` - JACK Audio Connection Kit server
- `pulseaudio-module-jack` - PulseAudio JACK module

**Plugins &amp; Effects:**

- `ladspa-sdk` - LADSPA plugin development kit
- `calf-plugins` - CALF audio plugins

**Conversion &amp; Tagging:**

- `soundconverter` - Audio file converter
- `easytag` - Audio file tag editor
- `flac` - Free Lossless Audio Codec
- `lame` - LAME MP3 encoder
- `oggenc` - Ogg Vorbis encoder
- `opus-tools` - Opus audio codec tools
- `vorbis-tools` - Ogg Vorbis tools
- `wavpack` - Audio compression
- `sox` - Sound eXchange (audio processing)
- `libsox-fmt-all` - All SoX format libraries

---

### Code Editors

**APT Packages (verified):**

- `vim` - Vi IMproved
- `neovim` - Vim fork with modern features
- `emacs` - GNU Emacs editor
- `nano` - GNU nano text editor
- `geany` - Lightweight IDE
- `gedit` - GNOME text editor
- `kate` - KDE Advanced Text Editor

**Third-Party (direct download):**

- **Visual Studio Code** - Installed via Microsoft repository
- **Sublime Text** - Installed via Sublime HQ repository

---

### Python Development

**All packages verified in Ubuntu 26.10 repos:**

**Core Python:**

- `python3` - Python 3 interpreter
- `python3-dev` - Python 3 development headers
- `python3-venv` - Python 3 virtual environment module
- `python3-pip` - Python 3 pip package installer
- `python-is-python3` - Symlink python to python3
- `ipython3` - Interactive Python shell

**Pip Packages:**

- Installed via `pip3 install --user` for user-level installation
- Basic packages: pip, setuptools, wheel

---

### Web Development

**APT Packages (verified):**

- `nginx` - High-performance web server
- `apache2` - Apache HTTP Server
- `apache2-utils` - Apache utilities
- `php` - PHP scripting language
- `php-cli` - PHP command-line interpreter
- `php-fpm` - PHP FastCGI Process Manager
- `composer` - Dependency Manager for PHP
- `redis-server` - Redis key-value store
- `memcached` - Memory caching system
- `sqlite3` - SQLite database engine
- `sqlitebrowser` - SQLite database browser

**Ruby:**

- `ruby` - Ruby interpreter
- `ruby-dev` - Ruby development headers
- `ruby-bundler` - Ruby dependency manager

**Node.js:**

- Installed via **NodeSource repository** (v20.x)
- Packages: `nodejs`, `npm`
- Global npm packages: npm-check-updates, nodemon, pm2, webpack, webpack-cli, eslint, prettier

---

### Java Development

**All packages verified in Ubuntu 26.10 repos:**

**JDK/JRE:**

- `default-jdk` - Default Java Development Kit
- `default-jre` - Default Java Runtime Environment

**Build Tools:**

- `gradle` - Gradle build tool
- `maven` - Apache Maven
- `ant` - Apache Ant
- `ant-contrib` - Ant contrib tasks

**Testing:**

- `junit4` - JUnit 4 testing framework
- `testng` - TestNG testing framework
- `hamcrest` - Hamcrest matcher library
- `mockito` - Mocking framework

**Environment:**

- Automatically sets `JAVA_HOME` in `/etc/environment`

---

### C/C++ Development

**All packages verified in Ubuntu 26.10 repos:**

**Compilers:**

- `build-essential` - Essential build tools (gcc, g++, make, etc.)
- `gcc` - GNU C compiler
- `g++` - GNU C++ compiler
- `gfortran` - GNU Fortran compiler
- `clang` - LLVM/Clang compiler

**Build Systems:**

- `cmake` - Cross-platform build system
- `make` - GNU make
- `autoconf` - Auto configuration tool
- `automake` - Automake tool
- `libtool` - Generic library support script
- `m4` - Macro processor
- `bison` - Parser generator
- `flex` - Lexical analyzer generator
- `gettext` - Internationalization tools
- `pkg-config` - Package configuration tool

**Debugging &amp; Profiling:**

- `cppcheck` - Static C/C++ analysis
- `valgrind` - Memory debugging tool
- `gdb` - GNU Debugger
- `ltrace` - Library call tracer
- `strace` - System call tracer

---

### Go Development

**APT Package:**

- `golang` - Go programming language compiler

**Direct Install:**

- Downloads and installs **Go 1.22.5** from official source
- Installs to `/usr/local/go`
- Adds to `PATH` in `/etc/environment`

---

### Rust Development

**APT Packages:**

- `rustc` - Rust compiler
- `cargo` - Rust package manager

**Direct Install:**

- Installs **rustup** from official source
- Sets stable as default
- Adds `rust-src` component

---

### Node.js Development

**Via NodeSource Repository:**

- Adds NodeSource PPA for Node.js 20.x
- Installs `nodejs` and `npm`

---

### PHP Development

**Via Ondrej PHP PPA:**

- Adds `ppa:ondrej/php` repository
- Installs latest PHP versions

**Packages:**

- `php` - PHP CLI
- `php-cli` - PHP command-line interpreter
- `php-fpm` - PHP FastCGI Process Manager
- `php-dev` - PHP development headers
- `php-pear` - PEAR module
- `php-mysql` - MySQL module
- `php-pgsql` - PostgreSQL module
- `php-sqlite3` - SQLite3 module
- `php-gd` - GD library module
- `php-curl` - cURL module
- `php-mbstring` - Multibyte string module
- `composer` - Dependency Manager for PHP

---

### Ruby Development

**All packages verified in Ubuntu 26.10 repos:**

- `ruby` - Ruby interpreter
- `ruby-dev` - Ruby development headers
- `ruby-bundler` - Ruby dependency manager
- `rake` - Ruby build tool
- `rdoc` - Ruby documentation generator

---

### Database Tools

**All packages verified in Ubuntu 26.10 repos:**

**SQL Databases:**

- `mysql-server` - MySQL Server
- `mysql-client` - MySQL Client
- `postgresql` - PostgreSQL database
- `postgresql-contrib` - Additional PostgreSQL utilities
- `sqlite3` - SQLite3 command-line tool
- `sqlitebrowser` - SQLite database browser

**NoSQL &amp; Cache:**

- `redis-server` - Redis key-value store
- `redis-tools` - Redis tools
- `memcached` - Memory caching system

---

### Container &amp; Virtualization

**APT Packages:**

- `docker.io` - Docker container runtime
- `docker-compose` - Docker Compose
- `podman` - Podman container runtime
- `lxc` - Linux Containers
- `lxd` - LXD container hypervisor

**Configuration:**

- Adds user to `docker` group
- Enables and starts Docker service

---

### Gaming

**APT Packages:**

- `steam` - Steam client
- `lutris` - Game manager
- `wine` - Windows compatibility layer
- `winetricks` - Wine configuration tool
- `obs-studio` - Open Broadcaster Software
- `mpv` - Video player
- `vlc` - Media player

**32-bit Support:**

- Adds i386 architecture
- Installs `libgl1-mesa-glx:i386` for Steam

---

### Office &amp; Productivity

**All packages verified in Ubuntu 26.10 repos:**

- `libreoffice` - LibreOffice office suite
- `okular` - Universal document viewer
- `evince` - Document viewer
- `zathura` - PDF viewer
- `pandoc` - Document converter

---

### System Utilities

**All packages verified in Ubuntu 26.10 repos:**

**Process Monitoring:**

- `htop` - Interactive process viewer
- `iotop` - I/O monitoring tool
- `nmon` - System monitoring tool
- `sysstat` - System statistics
- `dstat` - System resource statistics
- `glances` - System monitoring tool

**Network Monitoring:**

- `nethogs` - Network traffic per process
- `iftop` - Bandwidth monitoring
- `nload` - Network traffic monitor
- `vnstat` - Network traffic monitor
- `tcpdump` - Network packet analyzer
- `wireshark` - Network protocol analyzer

**System Inspection:**

- `lsof` - List open files
- `strace` - System call tracer
- `ltrace` - Library call tracer
- `valgrind` - Memory debugging tool
- `gdb` - GNU Debugger

**Shells &amp; Terminal:**

- `tmux` - Terminal multiplexer
- `screen` - Terminal multiplexer
- `byobu` - Terminal multiplexer wrapper
- `zsh` - Z Shell
- `fish` - Fish shell
- `fzf` - Fuzzy finder
- `ripgrep` - Fast grep alternative

**File Utilities:**

- `tree` - Directory tree display
- `ncdu` - NCurses disk usage
- `rsync` - Fast file transfer
- `unzip` - ZIP file extractor
- `p7zip-full` - 7-Zip file archiver

---

### General Development Tools

**All packages verified in Ubuntu 26.10 repos:**

**Version Control:**

- `git` - Git version control
- `tig` - Git text-mode interface
- `subversion` - Subversion version control

**Build Tools:**

- `make` - GNU make
- `cmake` - Cross-platform build system
- `autoconf` - Auto configuration tool
- `automake` - Automake tool
- `bison` - Parser generator
- `flex` - Lexical analyzer generator
- `gettext` - Internationalization tools
- `pkg-config` - Package configuration tool

**Documentation:**

- `manpages` - Manual pages
- `less` - Pager

---

### AI Tools

**Third-Party Tools (direct installation):**


| Tool                | Installation Method | Description                            |
| ------------------- | ------------------- | -------------------------------------- |
| **Ollama**          | Official script     | Local LLM runner, auto-detects GPU/CPU |
| **Mistral AI Vibe** | .deb package        | Desktop AI assistant from Mistral AI   |
| **Claude CLI**      | npm                 | Anthropic's CLI code assistant         |
| **Cursor**          | .deb package        | AI-powered code editor                 |


**Additional Tools:**

- **text-generation-webui** - Cloned to user's home directory (`~/text-generation-webui`)

---

### GUI Tweaks

**Icon Sets (verified):**

- `papirus-icon-theme` - Papirus icon theme
- `tela-icon-theme` - Tela icon theme
- `numix-icon-theme` - Numix icon theme
- `adwaita-icon-theme-full` - Adwaita icon theme (full)
- `yaru-icon-theme` - Yaru icon theme

**GTK Themes (verified):**

- `arc-theme` - Arc GTK theme
- `yaru-theme` - Yaru GTK theme
- `yaru-theme-gnome` - Yaru GNOME theme
- `adwaita-dark` - Adwaita dark theme

**Cursor Themes (verified):**

- `papirus-cursor-theme` - Papirus cursor theme
- `tela-cursor-theme` - Tela cursor theme
- `numix-cursor-theme` - Numix cursor theme
- `dmz-cursor-theme` - DMZ cursor theme
- `adwaita-cursor-theme` - Adwaita cursor theme

**Nerd Fonts:**

- Installs via **individual downloads** from GitHub releases
- Popular fonts: FiraCode, JetBrainsMono, Hack, SourceCodePro, CascadiaCode, UbuntuMono, DejaVuSansMono
- Also installs APT packages: `fonts-firacode`, `fonts-jetbrains-mono`
- Installs to `/usr/share/fonts/truetype/nerd-fonts/`
- Updates font cache automatically

**Chris Titus mybash:**

- Clones from GitHub: [https://github.com/christitustech/mybash](https://github.com/christitustech/mybash)
- Runs `setup.sh` as the user
- Falls back to manual file copying if setup.sh fails
- Adds sourcing to user's `.bashrc`
- User must run `source ~/.bashrc` or restart terminal

**GUI Tools (verified):**

- `gnome-tweaks` - GNOME Tweaks
- `gnome-shell-extensions` - GNOME Shell Extensions
- `gnome-shell-extension-manager` - Extension Manager
- `gnome-themes-extra` - Extra GNOME themes
- `nautilus` - File manager
- `nautilus-admin` - Nautilus admin extensions
- `eog` - Eye of GNOME image viewer
- `evince` - Document viewer
- `file-roller` - Archive manager
- `gedit` - Text editor
- `simple-scan` - Simple scanner tool
- `cheese` - Webcam tool
- `gnome-screenshot` - Screenshot tool
- `gnome-system-monitor` - System monitor

---

## 🔧 Error Handling &amp; Installation Checks

The script implements comprehensive error handling and installation checks to ensure reliability.

### Installation Check Flow

```
1. Check if package is ALREADY INSTALLED
   ↓ Yes → Skip (add to SKIPPED_PACKAGES)
   ↓ No
2. Check if package EXISTS in repositories
   ↓ No → Fail (add to FAILED_PACKAGES)
   ↓ Yes
3. Attempt INSTALLATION
   ↓ Success → Add to INSTALLED_PACKAGES
   ↓ Fail → Add to FAILED_PACKAGES
```

### Key Functions


| Function                           | Purpose                                             |
| ---------------------------------- | --------------------------------------------------- |
| `is_installed(pkg)`                | Checks if package is installed via dpkg             |
| `package_exists(pkg)`              | Verifies package exists in apt cache                |
| `safe_install(pkgs...)`            | Safely installs packages with checks                |
| `batch_install(category, pkgs...)` | Installs batch of packages with summary             |
| `log(level, message)`              | Color-coded logging (ERROR, WARNING, INFO, SUCCESS) |


### Error Recovery

- **Failed Package Lists**: Continues installation even if some packages fail
- **Dependency Fixing**: Automatically runs `apt-get install -f` for broken dependencies
- **Retry Logic**: Allows retry for critical operations like `apt-get update`
- **Cleanup**: Removes temporary files even on failure

---

## 📊 Installation Summary &amp; Logging

### Real-Time Feedback

The script provides **color-coded real-time feedback**:

- 🟢 **GREEN**: Success messages
- 🔵 **BLUE**: Info messages
- 🟡 **YELLOW**: Warnings
- 🔴 **RED**: Errors

### Summary Screen

Press `S` at any time to see:

- Total packages processed
- Successfully installed count
- Already installed (skipped) count
- Failed to install count
- List of failed packages
- List of skipped packages (first 10)

### Log File

A detailed log is saved to:

```
/var/log/ubuntu_post_install_TIMESTAMP.log
```

**Log Contents:**

- Timestamp
- User and hostname
- Summary statistics
- Complete list of installed packages
- Complete list of skipped packages
- Complete list of failed packages

---

## ⚙️ Customization

### Adding New Packages

To add packages to a category, edit the corresponding `batch_install` call:

```bash
batch_install "Category Name" \
    package1 \
    package2 \
    package3
```

**Important:** Only add packages that you have verified exist in Ubuntu 26.10 repositories.

### Creating New Categories

1. Create a new installation function:
  ```bash
  install_my_category() {
    batch_install "My Category" \
        package1 \
        package2
  }
  ```
2. Add to main menu:
  ```bash
  echo " 23.  My Category"
  ```
3. Add to case statement:
  ```bash
  
  ```
4. install\_my\_category ;;
  ```
  
  ```
5. Add to bulk options if needed

### Modifying Default Behavior

Edit these variables at the top of the script:

- Color definitions: Customize output colors
- Array declarations: Track different metrics

### Disabling Categories

Comment out or remove:

- The menu echo line
- The case statement
- The function definition

---

## 🐛 Troubleshooting

### Common Issues


| Issue                        | Solution                                                                           |
| ---------------------------- | ---------------------------------------------------------------------------------- |
| **Script exits immediately** | Run with `sudo`                                                                    |
| **Package not found**        | Package may not be in Ubuntu 26.10 repos. Check package name or use direct install |
| **Dependency errors**        | Run `sudo apt-get install -f` to fix broken dependencies                           |
| **Network errors**           | Check internet connection, retry                                                   |
| **Disk space full**          | Free up space (minimum 10GB recommended)                                           |
| **Permission denied**        | Ensure script is executable: `chmod +x post-install.sh`                            |


### Debug Mode

For verbose output, modify the script:

```bash
# Remove or comment out:
# set -euo pipefail
```

### Manual Installation

If a package fails, install it manually:

```bash
sudo apt-get install package-name
```

Or for third-party tools, follow their official installation instructions.

### Checking Logs

View the installation log:

```bash
cat /var/log/ubuntu_post_install_*.log
```

Or tail the most recent:

```bash
ls -lt /var/log/ubuntu_post_install_*.log | head -1 | awk '{print $NF}' | xargs cat
```

---

## 📜 License

This script is provided **as-is** without warranty. You are free to:

- Use it for personal or commercial purposes
- Modify and distribute it
- Use it as a base for your own scripts

**Attribution:**

- If you share modified versions, please credit the original source
- Some packages have their own licenses (check individual package terms)

---

## 🙏 Acknowledgments

- **Ubuntu Community**: For the excellent package repositories
- **Chris Titus Tech**: For the mybash configuration
- **Ollama**: For making local LLMs accessible
- **Mistral AI**: For Vibe and open-source AI models
- **All package maintainers**: For their hard work on the included software

---

*Last updated: August 7, 2026*